---
id: 2
group: "testing-infrastructure"
dependencies: [1]
status: "pending"
created: 2026-06-01
skills:
  - bats
  - bash
---
# Write fresh BATS unit tests for the `run.sh` detection/identifier functions

## Objective
Create `tests/rtl_433/test_run.bats` that **sources the real `run.sh`** and verifies its custom logic: dongle enumeration, serial usability, unique-id resolution, and match-id derivation. Use the `SYSFS_USB_BASE` seam for enumeration. No submodules, no `bats-assert`/`bats-support`, no `bashio` mock.

## Skills Required
- `bats` — BATS test structure (`setup`, `@test`, `run`, `$status`, `$output`).
- `bash` — fixture construction and calling the functions under test.

## Meaningful Test Strategy Guidelines

Your critical mantra for test generation is: "write a few tests, mostly integration".

**Definition of "Meaningful Tests":** Tests that verify custom business logic, critical paths, and edge cases specific to the application. Focus on testing YOUR code, not the framework or library functionality.

**When TO Write Tests:** Custom business logic and algorithms; critical workflows and data transformations; edge cases and error conditions for core functionality; integration points between components; complex validation logic.

**When NOT to Write Tests:** Third-party/framework functionality; simple CRUD without custom logic; getters/setters; configuration/static data; obvious functionality that would break immediately if incorrect.

**Test Task Creation Rules:** Combine related scenarios into single tests; favor integration/critical-path over exhaustive unit coverage; do not test shell built-ins.

Here, the **functions themselves are the custom business logic** (sysfs enumeration, serial-usability rules, the unique-id fallback ladder), so unit tests of them are meaningful. Keep the suite small and focused — one `@test` per behavior, not per input permutation.

## Acceptance Criteria
- [ ] `tests/rtl_433/test_run.bats` exists and sources `rtl_433/run.sh` (relative to `BATS_TEST_DIRNAME`) without triggering the main body.
- [ ] Tests for `enumerate_rtlsdr_devices` against a mock sysfs tree under `SYSFS_USB_BASE`: (a) a known RTL-SDR VID:PID is emitted as `serial<TAB>portpath`; (b) USB interface nodes (names containing `:`) and devices lacking `idVendor`/`idProduct` are skipped; (c) a non-RTL-SDR VID:PID is skipped; (d) an empty/missing tree yields no output and exit status 0.
- [ ] Tests for `_serial_is_usable`: rejects empty, `00000000`, `00000001`, a short reserved integer (e.g. `5`), and a serial duplicated within `rtlsdr_devices`; accepts a unique realistic serial.
- [ ] Tests for `resolve_radio_unique_id`: `:SERIAL` selector with a usable serial → `serial:<serial>`; selector matching an entry with an unusable serial but a port path → `usbpath:<path>`; unmatched/empty selector → `template:<tag>`; result contains only `[A-Za-z0-9:._-]`.
- [ ] Tests for `radio_match_id`: returns the usable serial when present; returns the sanitised port path otherwise.
- [ ] `bats tests/` passes locally.
- [ ] Uses only plain BATS assertions; no external bats libraries, no submodules, no `bashio` mock.

## Technical Requirements
BATS. The functions read globals: `enumerate_rtlsdr_devices` reads `SYSFS_USB_BASE` and `RTLSDR_KNOWN_IDS`; `_serial_is_usable`, `resolve_radio_unique_id`, and `radio_match_id` read the `rtlsdr_devices` array. Set these in the test before calling.

## Input Dependencies
- Task 1: `run.sh` must be sourceable (the `main`-guard).

## Output Artifacts
- `tests/rtl_433/test_run.bats`.

## Implementation Notes

<details>
<summary>Detailed implementation steps and reference test skeleton</summary>

1. **Locate the script** relative to the test file:
   ```bash
   setup() {
       RUN_SH="${BATS_TEST_DIRNAME}/../../rtl_433/run.sh"
       # Source for function definitions only; main-guard prevents the body from running.
       source "$RUN_SH"
   }
   ```
   Sourcing under plain bash is safe (no top-level `bashio`). If `bats` is unavailable when developing locally, install it (`apt-get install -y bats` or `brew install bats-core`).

2. **`enumerate_rtlsdr_devices` fixtures.** Build a mock sysfs tree in `BATS_TEST_TMPDIR` and point `SYSFS_USB_BASE` at it. Each "device" is a directory containing `idVendor`, `idProduct`, and optionally `serial` files. Use a **known** RTL-SDR id from `RTLSDR_KNOWN_IDS` such as `0bda:2838`.
   ```bash
   make_usb_dev() { # dir vid pid [serial]
       local d="$SYSFS_USB_BASE/$1"; mkdir -p "$d"
       printf '%s' "$2" > "$d/idVendor"
       printf '%s' "$3" > "$d/idProduct"
       [ -n "${4:-}" ] && printf '%s' "$4" > "$d/serial"
   }

   @test "enumerate emits serial<TAB>portpath for a known RTL-SDR dongle" {
       SYSFS_USB_BASE="$BATS_TEST_TMPDIR/sys"; mkdir -p "$SYSFS_USB_BASE"
       make_usb_dev "1-1.4" "0bda" "2838" "00000abc"
       run enumerate_rtlsdr_devices
       [ "$status" -eq 0 ]
       [ "$output" = "$(printf '00000abc\t1-1.4')" ]
   }

   @test "enumerate skips USB interface nodes and non-RTL-SDR devices" {
       SYSFS_USB_BASE="$BATS_TEST_TMPDIR/sys"; mkdir -p "$SYSFS_USB_BASE"
       make_usb_dev "1-1.4"     "0bda" "2838" "abc"   # match
       make_usb_dev "1-1.4:1.0" "0bda" "2838" "iface" # interface node: contains ':'
       make_usb_dev "2-1"       "1234" "5678" "other" # unknown id
       run enumerate_rtlsdr_devices
       [ "$status" -eq 0 ]
       [ "$output" = "$(printf 'abc\t1-1.4')" ]
   }

   @test "enumerate yields no output for an empty/missing sysfs tree" {
       SYSFS_USB_BASE="$BATS_TEST_TMPDIR/empty"; mkdir -p "$SYSFS_USB_BASE"
       run enumerate_rtlsdr_devices
       [ "$status" -eq 0 ]
       [ -z "$output" ]
   }
   ```
   Notes: device dir names containing `:` are skipped by the function; the function returns success and empty output when the base dir has no matching entries (the `[ -e "$dev" ] || continue` and the glob guard handle missing trees). Use a serial that is **not** a short reserved integer so it survives, OR assert only the port path if you choose an unusable serial.

3. **`_serial_is_usable`.** Set the `rtlsdr_devices` array (TAB-separated `serial\tportpath` entries) to control the uniqueness check.
   ```bash
   @test "_serial_is_usable rejects placeholders, short ints, empty, and duplicates" {
       rtlsdr_devices=( "$(printf 'DUP\t1-1')" "$(printf 'DUP\t1-2')" )
       run _serial_is_usable ""        ; [ "$status" -ne 0 ]
       run _serial_is_usable "00000000"; [ "$status" -ne 0 ]
       run _serial_is_usable "00000001"; [ "$status" -ne 0 ]
       run _serial_is_usable "5"       ; [ "$status" -ne 0 ]
       run _serial_is_usable "DUP"     ; [ "$status" -ne 0 ]  # appears twice
   }

   @test "_serial_is_usable accepts a unique realistic serial" {
       rtlsdr_devices=( "$(printf '00000abc\t1-1')" )
       run _serial_is_usable "00000abc"
       [ "$status" -eq 0 ]
   }
   ```

4. **`resolve_radio_unique_id`** (reads `rtlsdr_devices`):
   ```bash
   @test "resolve_radio_unique_id prefers a usable serial" {
       rtlsdr_devices=( "$(printf '00000abc\t1-1.4')" )
       run resolve_radio_unique_id ":00000abc" "tmpl"
       [ "$output" = "serial:00000abc" ]
   }

   @test "resolve_radio_unique_id falls back to usbpath for an unusable serial" {
       rtlsdr_devices=( "$(printf '00000000\t1-1.4')" )   # placeholder serial
       run resolve_radio_unique_id ":00000000" "tmpl"
       [ "$output" = "usbpath:1-1.4" ]
   }

   @test "resolve_radio_unique_id falls back to template when nothing matches" {
       rtlsdr_devices=()
       run resolve_radio_unique_id ":nope" "tmpl"
       [ "$output" = "template:tmpl" ]
   }
   ```
   Confirm against the function the exact selector forms it accepts (`:SERIAL`, bare index, etc.) and adjust the inputs to match the real branches. The sanitisation step maps disallowed characters to `_`; pick tag/serial values that are already in the allowlist so assertions are exact.

5. **`radio_match_id`:**
   ```bash
   @test "radio_match_id returns the usable serial" {
       rtlsdr_devices=( "$(printf '00000abc\t1-1.4')" )
       run radio_match_id "00000abc" "1-1.4"
       [ "$output" = "00000abc" ]
   }

   @test "radio_match_id returns the port path when serial is unusable" {
       rtlsdr_devices=( "$(printf '00000000\t1-1.4')" )
       run radio_match_id "00000000" "1-1.4"
       [ "$output" = "1-1.4" ]
   }
   ```

6. **Important:** Read each function in `run.sh` before finalizing assertions — match the exact selector grammar, sort order, and sanitisation so expected strings are correct. Keep the file to roughly the tests above (one behavior each); do not over-enumerate inputs.

7. Run `bats tests/` and ensure green. Commit, e.g. `test(rtl_433): add BATS unit tests for dongle detection helpers`.
</details>
