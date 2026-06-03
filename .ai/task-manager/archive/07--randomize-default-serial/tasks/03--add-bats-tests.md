---
id: 3
group: "testing"
dependencies: [2]
status: "completed"
created: "2026-06-03"
skills:
  - bash
---
# Add BATS unit tests for the new serial helpers

## Objective
Add focused BATS unit tests to `tests/rtl_433/test_run.bats` covering the two new pure helpers (`_serial_is_default` and `generate_random_serial`), matching the existing test style (the file sources `run.sh` via its main-guard).

## Skills Required
- `bash` — writing BATS tests using plain assertions.

## Acceptance Criteria
- [ ] A test asserts `_serial_is_default` succeeds for `""`, `00000000`, and `00000001`.
- [ ] A test asserts `_serial_is_default` fails for a realistic serial (e.g. `00000abc`) and for a non-default numeric like `12345678`.
- [ ] A test asserts `generate_random_serial` output matches `^[0-9a-f]{8}$`.
- [ ] (Optional but recommended) a test asserts two successive `generate_random_serial` calls are well-formed (format stability across invocations).
- [ ] `bats -r tests/` passes with the new tests included.

## Meaningful Test Strategy Guidelines
Your critical mantra for test generation is: "write a few tests, mostly integration".

**Definition of "Meaningful Tests":** Tests that verify custom business logic, critical paths, and edge cases specific to the application. Focus on testing YOUR code, not the framework or library functionality.

**When TO Write Tests:** custom logic and algorithms; critical workflows; edge cases and error conditions for core functionality; integration points; complex validation.

**When NOT to Write Tests:** third-party functionality; framework features; simple CRUD without custom logic; getters/setters; config/static data; obvious functionality that would break immediately if incorrect.

**Test Task Creation Rules:** combine related scenarios into single tests; favour integration/critical-path over exhaustive unit coverage; do not test framework behaviour.

For this task: the factory-default predicate and the serial generator are exactly the kind of small, custom, pure logic worth unit-testing (mirroring the existing `_serial_is_usable` / `parse_rtl_test_ppm` tests). **Do not** attempt to unit-test the `rtl_eeprom` flashing/re-enumeration orchestration — it requires real hardware and a live kernel USB reset, which BATS cannot meaningfully simulate; that path is covered by the plan's static-trace self-validation instead.

## Technical Requirements
- Tests are plain BATS using `run <fn> <args>` and `[ "$status" -eq 0 ]` / `[[ "$output" =~ ... ]]` assertions.
- The existing `setup()` already sources `run.sh`, so the helpers are in scope.

## Input Dependencies
- Task 2: the `_serial_is_default` and `generate_random_serial` helpers must exist in `run.sh`.

## Output Artifacts
- New `@test` blocks in `tests/rtl_433/test_run.bats`.

## Implementation Notes
<details>
<summary>Step-by-step</summary>

Append a new section to `tests/rtl_433/test_run.bats` (after the `radio_match_id` section, or at the end of the file before EOF):

```bash
# --- _serial_is_default ------------------------------------------------------

@test "_serial_is_default is true for empty and the factory placeholders" {
    run _serial_is_default ""        ; [ "$status" -eq 0 ]
    run _serial_is_default "00000000"; [ "$status" -eq 0 ]
    run _serial_is_default "00000001"; [ "$status" -eq 0 ]
}

@test "_serial_is_default is false for realistic / non-default serials" {
    run _serial_is_default "00000abc"; [ "$status" -ne 0 ]
    run _serial_is_default "12345678"; [ "$status" -ne 0 ]
}

# --- generate_random_serial --------------------------------------------------

@test "generate_random_serial emits exactly 8 lowercase hex characters" {
    run generate_random_serial
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}$ ]]
    # A second call is also well-formed (format stable across invocations).
    run generate_random_serial
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}$ ]]
}
```

Then run `bats -r tests/` and confirm everything passes (the `-r` flag is required so bats recurses into `tests/rtl_433/`).

</details>
