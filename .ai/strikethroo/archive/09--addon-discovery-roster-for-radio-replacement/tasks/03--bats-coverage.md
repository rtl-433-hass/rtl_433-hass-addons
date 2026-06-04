---
id: 3
group: "tests"
dependencies: [1, 2]
status: "completed"
created: 2026-06-04
skills:
  - bats
  - bash
---
# BATS coverage for the discovery roster and dual-identity surfacing

## Objective
Add BATS unit tests that lock in the new behavior from Tasks 1–2: the discovery
payload's additive `radios` roster (all radios, both identifiers per entry, valid
JSON, legacy fields retained) and the `portpath=` field in `radios.status`. Tests
source the `main()`-guarded `rtl_433/run.sh` and drive the helpers with a mock
multi-radio device set, following the existing conventions in
`tests/rtl_433/test_run.bats`.

## Skills Required
`bats`, `bash` — the project's BATS harness and shell test fixtures.

## Acceptance Criteria
- [ ] A test exercises the discovery-payload assembly with a **mixed** mock radio
      set: a usable serial, a factory-default/empty serial (usbpath identity), and
      a `template:`-identity radio with **both** serial and usbpath empty.
- [ ] The test pipes the assembled payload through `jq .` and asserts it is valid
      JSON.
- [ ] It asserts `config.radios | length` equals the number of mock radios, and
      that each entry has `unique_id`, `port`, `path`, `serial`, `usbpath` keys
      (serial/usbpath may be empty strings).
- [ ] It asserts the legacy top-level fields (`host`/`port`/`path`/`unique_id`)
      are still present (back-compat).
- [ ] A test asserts `radios.status` lines now include a `portpath=` field.
- [ ] `bats -r tests/` passes the full suite (new + existing).

## Technical Requirements
- Add tests to `tests/rtl_433/test_run.bats` (or a sibling `.bats` file under
  `tests/rtl_433/` if that matches existing layout).
- Use `jq` for JSON assertions (already used in the validation flow).
- Follow the existing fixture/mock conventions documented in `tests/README.md`
  (e.g. how `rtlsdr_devices` and the `radio_*` arrays are seeded in current tests).

## Input Dependencies
- Task 1: `radio_portpaths` array and `radios.status` `portpath=` field.
- Task 2: the `radios` roster in the discovery payload.

## Output Artifacts
- BATS tests covering the roster builder, dual-identity surfacing, and
  back-compat of the legacy discovery fields.

## Implementation Notes

Test philosophy — "write a few tests, mostly integration":

**Definition.** Meaningful tests verify custom business logic, critical paths,
and edge cases specific to this application. Test *your* code, not the framework
or library.

**When TO write tests:** custom business logic and algorithms; critical user
workflows and data transformations; edge cases and error conditions for core
functionality; integration points between components; complex validation logic.

**When NOT to write tests:** third-party library functionality; framework
features; simple CRUD without custom logic; trivial getters/setters or static
config; obvious functionality that would break immediately if incorrect.

**Rules:** combine related scenarios into a single test task; favor
integration/critical-path coverage over per-method unit tests; question whether
simple functions need dedicated tests.

Apply this here: focus on the roster-assembly logic and the dual-identity edge
cases (the genuinely custom behavior), not on re-testing `jq` or bash itself.

<details>
<summary>Step-by-step</summary>

1. **Find the existing seeding pattern.** Open `tests/rtl_433/test_run.bats` and
   locate how it sources `run.sh` (a `setup()` that sets `BASH_SOURCE`-guard
   conditions so `main` does not run) and how it populates arrays like
   `rtlsdr_devices`, `radio_ports`, `radio_unique_ids`, `radio_serials`. Reuse
   that exact pattern; do not invent a new harness.

2. **Seed a mixed multi-radio set.** Populate the parallel arrays (or drive the
   detected-radio path) for three radios:
   - usable serial → `unique_id=serial:abcd1234`, `serial=abcd1234`,
     `portpath=1-1.4`
   - default/empty serial → `unique_id=usbpath:1-1.2`, `serial=""`,
     `portpath=1-1.2`
   - template identity → `unique_id=template:soapy`, `serial=""`, `portpath=""`

3. **Exercise the payload assembly.** Call the same code path Task 2 added
   (factor the `radios_json` build into a callable helper if that makes it
   testable without hitting the network; otherwise capture the `body` string).
   Then:
   ```bash
   run bash -c 'printf "%s" "$body" | jq -e ".config.radios | length == 3"'
   [ "$status" -eq 0 ]
   printf '%s' "$body" | jq -e '.config.radios[2].serial == "" and .config.radios[2].usbpath == ""'
   printf '%s' "$body" | jq -e '.config.host and .config.port and .config.unique_id'
   ```

4. **Test `radios.status` portpath.** Invoke `surface_radio_status` against the
   mock set (with `conf_directory` pointed at a `BATS_TMPDIR` path) and assert:
   ```bash
   grep -q 'portpath=' "$conf_directory/radios.status"
   ```

5. **Run the whole suite:** `bats -r tests/` — the `-r` recursion is required.
</details>
