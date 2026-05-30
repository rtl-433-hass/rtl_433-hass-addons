---
id: 4
group: "remove-mqtt-http"
dependencies: [2, 3]
status: "pending"
created: "2026-05-30"
skills:
  - bash
  - bats
---
# Update test suite for HTTP/port/discovery behaviour

## Objective
Remove the obsolete MQTT tests and add focused tests for the new behaviour: deterministic device→port assignment, the HTTP default template, and the discovery payload shape.

## Skills Required
- `bash`: shell logic under test.
- `bats`: bats-core test authoring with the existing mock-bashio helpers.

## Acceptance Criteria
- [ ] The `tests/rtl_433_mqtt_autodiscovery/` tests (for the unused autodiscovery script) are removed.
- [ ] MQTT-specific cases in `tests/rtl_433/test_run.bats` (MQTT service discovery, retain conversion, legacy `rtl_433_conf_file`, mqtt default-template assertions) are removed.
- [ ] New/updated tests cover: (a) the default template contains a `device` line and an `output http` line and no `mqtt` line; (b) sorting templates by `device` yields ports 8433/8434/8435 in order and is stable across re-runs; (c) the 10-radio cap is enforced; (d) the discovery payload contains the expected `service`, `port`, and `path` for a radio.
- [ ] All bats tests pass; `pre-commit run --all-files` passes.

## Technical Requirements
The repo uses bats-core with helpers in `tests/bats/` (`test_helper.bash`, `mock_bashio.bash`). Tests follow the existing pattern of sourcing `mock_bashio.bash` and exercising extracted logic from `run.sh`. Follow the project's "write a few tests, mostly integration" approach.

## Input Dependencies
- Task 2: the rewritten `run.sh` (template + port logic) being tested.
- Task 3: the discovery publication being tested.

## Output Artifacts
Updated `tests/rtl_433/test_run.bats` and removal of `tests/rtl_433_mqtt_autodiscovery/`.

## Implementation Notes

<details>
<summary>Detailed implementation guidance — includes Meaningful Test Strategy</summary>

**Meaningful Test Strategy Guidelines** (apply these):
Your mantra: "write a few tests, mostly integration." Test YOUR logic, not rtl_433 or bashio.
- DO test: the device-sort→port-assignment algorithm, the 10-radio cap, the rendered default template content, the discovery JSON shape.
- DON'T test: that `curl` works, that rtl_433 starts, that bashio functions behave, trivial string ops.
- Combine related scenarios into single tests rather than one-per-assertion.

Steps:

1. **Remove** the entire `tests/rtl_433_mqtt_autodiscovery/` directory (it tests `/rtl_433_mqtt_hass.py`, which is no longer used). Also remove its references if any test runner enumerates it. Note: the unrelated active plan `01--remove-autodiscovery-addon` may also remove this; if already gone, skip without error.

2. In `tests/rtl_433/test_run.bats`, **delete** these existing tests (now obsolete): "retrieves MQTT settings when service is available", "logs info when MQTT service is not available", "converts retain true to 1", "leaves retain unchanged when not true", "shows deprecation warning for legacy rtl_433_conf_file option", "does not trigger legacy mode when rtl_433_conf_file is empty", and adjust the default-template tests so they assert HTTP output instead of `${host}`/`${port}` mqtt variables. Update `setup()` to drop the mock MQTT service seeding if no longer used.

3. **Add** tests mirroring the existing self-contained style (source `mock_bashio.bash`, operate in `$conf_directory`):
   - *Default template*: create the template via the same heredoc logic the script uses and assert it contains `device ` and `output http` and `grep -qv mqtt`.
   - *Port assignment*: create three templates with distinct `device` values (e.g. `device :AAA`, `device :BBB`, `device :CCC`) in unsorted filename order, run the sort+assign logic, assert ports map to 8433/8434/8435 in device-sorted order, and assert a second run produces the identical mapping.
   - *Cap*: create 11 templates and assert the cap message appears and no 8443 is assigned.
   - *Discovery payload*: given a device/port pair, build the discovery JSON the way `run.sh` does and assert it contains `"service": "rtl_433"`, the right `"port"`, and `"path": "/ws"`.

4. Keep tests hermetic and fast; reuse `setup_temp_dir`/`teardown_temp_dir`. Ensure `shellcheck` is satisfied for any helper snippets.

Run locally with the bats submodule runner used by the repo (e.g. `tests/bats/bats-core/bin/bats tests/rtl_433/test_run.bats`).
</details>
