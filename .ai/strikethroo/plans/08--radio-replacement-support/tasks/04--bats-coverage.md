---
id: 4
group: "radio-replacement"
dependencies: [1, 2]
status: "pending"
created: 2026-06-03
skills:
  - bats
  - shell
---
# BATS coverage for targeted stamp, collision guard, and surfacing output

## Objective
Add BATS unit tests in `tests/rtl_433/test_run.bats` proving the new
`force_randomize_serial` targeting is correct (right librtlsdr index, non-default
rewrite, collision/ambiguity refusal) and that the per-radio
`unique_id`+`host:port` surfacing emits the expected fields. The existing
`randomize_default_serial` tests must continue to pass unchanged.

## Skills Required
- `bats` — Bash Automated Testing System, following the existing test conventions.
- `shell` — stubbing `enumerate_rtlsdr_*`, `rtl_eeprom`, host resolution.

## Acceptance Criteria
- [ ] Test: `force_randomize_serial` maps a USB-port-path selector to the correct
      **librtlsdr index** and writes `rtl_eeprom -d <that index> -s <new>`,
      including a case where the sysfs port-path order disagrees with the
      librtlsdr index order (the PR #98 regression shape).
- [ ] Test: the targeted pass rewrites a dongle whose current serial is
      **non-default** (proving it is not gated on default-only).
- [ ] Test (collision/ambiguity guard): the targeted pass refuses (no
      `rtl_eeprom` write) when the port path matches zero/multiple dongles or when
      the target maps to zero/ambiguous librtlsdr indices; and a generated serial
      never reuses one already present on another connected dongle.
- [ ] Test: the per-radio surfacing emits a line containing `unique_id=…`,
      `host=…`, `port=…`, and writes a `radios.status` file with those fields.
- [ ] All pre-existing tests (notably the `flash_default_serials` /
      `randomize_default_serial` suite) still pass with no modification to their
      assertions.
- [ ] `bats -r tests/` passes.

Use your internal Todo tool to track these and keep on track.

## Technical Requirements
- File: `tests/rtl_433/test_run.bats`.
- Run with `bats -r tests/` (the `-r` recurses into `tests/rtl_433/`).
- Follow existing fixture conventions: override `list_rtlsdr_banner` /
  `rtl_eeprom` as shell functions; capture writes to a `RTL_EEPROM_LOG` file
  (recall `timeout`/`printf | timeout rtl_eeprom` runs in a subshell, so log to a
  file path exported via env, as the existing tests do).

## Input Dependencies
- Task 1: provides `flash_targeted_serial` / shared stamp helper / `main()` gating.
- Task 2: provides the surfacing function(s) and `radios.status` writer.

## Output Artifacts
- New `@test` cases appended to `tests/rtl_433/test_run.bats`.

## Implementation Notes

Apply the project's test philosophy: a few focused tests on the **custom**
logic (index correlation, non-default rewrite, refusal guards, surfacing fields),
not exhaustive permutations. Test our code, not bats/librtlsdr.

<details>
<summary>Detailed implementation guidance</summary>

Model the new tests on the existing `flash_default_serials` block
(`tests/rtl_433/test_run.bats` ~190–300). Key fixtures:

- Set `rtlsdr_devices=( $'<serial>\t<portpath>' ... )` to control the sysfs view.
- Override `list_rtlsdr_banner()` to emit a librtlsdr banner whose index order
  **disagrees** with the sysfs port-path sort, so the test proves the write uses
  the librtlsdr index. Example (sysfs sorts `1-1.2` before `1-1.4`, but librtlsdr
  lists the `1-1.4` dongle as index 0):

```bash
@test "force_randomize_serial writes -d to the librtlsdr index for the selected port path" {
    rtlsdr_devices=( $'aaaa1111\t1-1.2' $'bbbb2222\t1-1.4' )
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: bbbb2222\n'   # 1-1.4 is index 0
        printf '  1:  Realtek, RTL2832U, SN: aaaa1111\n'   # 1-1.2 is index 1
    }
    export RTL_EEPROM_LOG="$BATS_TEST_TMPDIR/eeprom.log"
    rtl_eeprom() { printf '%s\n' "$*" >> "$RTL_EEPROM_LOG"; }
    run flash_targeted_serial "1-1.4"
    [ "$status" -eq 0 ]
    grep -q -- "-d 0 -s " "$RTL_EEPROM_LOG"      # wrote to librtlsdr index 0, not sysfs position 1
    ! grep -q -- "-d 1" "$RTL_EEPROM_LOG"
}
```

- **Non-default rewrite:** target a dongle whose serial is a real value (e.g.
  `bbbb2222`) and assert `rtl_eeprom` IS called (contrast with
  `flash_default_serials`, which would skip it).

- **Refusal guards** (assert `RTL_EEPROM_LOG` is empty / `status` non-zero):
  - port path matches no `rtlsdr_devices` entry;
  - port path matches two entries (duplicate portpath);
  - target serial is a shared default AND two default indices exist in the banner
    (ambiguous → refuse).

- **Collision avoidance:** stub `generate_random_serial` to first return a serial
  already in `rtlsdr_devices`, then a fresh one, and assert the written serial is
  the fresh one (mirrors how the avoid-set is exercised).

- **Surfacing test:** populate `radio_ports`/`radio_tags`/`radio_unique_ids`,
  stub host resolution (`bashio::addon.hostname` or `curl`) to a fixed host, set
  `conf_directory="$BATS_TEST_TMPDIR"`, invoke the surfacing function, and assert
  (a) the emitted log/output contains `unique_id=`, `host=`, `port=`, and (b)
  `$BATS_TEST_TMPDIR/radios.status` exists and contains the expected fields.

Keep helper stubs local to each `@test` (as the existing tests do) so suites stay
independent. Do not edit the assertions of the existing `flash_default_serials`
tests; if Task 1's refactor changed an internal log string they relied on, that is
a Task 1 regression to fix there, not a test relaxation here.
</details>
