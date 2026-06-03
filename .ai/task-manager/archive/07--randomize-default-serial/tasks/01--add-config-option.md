---
id: 1
group: "config"
dependencies: []
status: "completed"
created: "2026-06-03"
skills:
  - json
---
# Add `randomize_default_serial` option to both add-on config.json files

## Objective
Declare a new, opt-in boolean add-on option `randomize_default_serial` (default `false`, schema `bool`) in **both** `rtl_433/config.json` and `rtl_433-next/config.json`, so the toggle is exposed in the Home Assistant Configuration tab and the two add-ons stay in sync.

## Skills Required
- `json` — editing Home Assistant add-on `config.json` option/schema blocks while preserving formatting.

## Acceptance Criteria
- [ ] `rtl_433/config.json` `options` block contains `"randomize_default_serial": false`.
- [ ] `rtl_433/config.json` `schema` block contains `"randomize_default_serial": "bool"`.
- [ ] `rtl_433-next/config.json` `options` block contains `"randomize_default_serial": false`.
- [ ] `rtl_433-next/config.json` `schema` block contains `"randomize_default_serial": "bool"`.
- [ ] `python3 tests/config/validate_configs.py` reports `OK` for both add-ons.
- [ ] Both files remain valid JSON (check-json pre-commit hook passes).

## Technical Requirements
The two `config.json` files must keep identical option/schema sets (the validator enforces options↔schema parity). Add the new key alongside the existing radio options.

## Input Dependencies
None.

## Output Artifacts
The `randomize_default_serial` option declared in both `config.json` files, ready for `run.sh` to read.

## Implementation Notes
<details>
<summary>Step-by-step</summary>

1. Edit `rtl_433/config.json`:
   - In the `"options"` object, add a new line after `"noise_floor_duration": 30`:
     - Add a trailing comma to the `noise_floor_duration` line if needed and insert `"randomize_default_serial": false`. The `options` block should become:
       ```json
       "options": {
         "disable_tpms": true,
         "log_received_messages": false,
         "log_diagnostic_messages": false,
         "correct_ppm_offset": false,
         "detect_noise_floor": false,
         "noise_floor_bands": "433.92M,868M,915M",
         "noise_floor_duration": 30,
         "randomize_default_serial": false
       },
       ```
   - In the `"schema"` object, add `"randomize_default_serial": "bool"` after `"noise_floor_duration": "int(1,600)"`:
       ```json
       "schema": {
         "disable_tpms": "bool",
         "log_received_messages": "bool",
         "log_diagnostic_messages": "bool",
         "correct_ppm_offset": "bool",
         "detect_noise_floor": "bool",
         "noise_floor_bands": "str",
         "noise_floor_duration": "int(1,600)",
         "randomize_default_serial": "bool"
       },
       ```
2. Apply the **identical** additions to `rtl_433-next/config.json` (same `options` and `schema` keys/values). Note `-next` uses single-line array formatting for some fields, but the `options`/`schema` blocks are multi-line and match `rtl_433/config.json`; mirror them exactly.
3. Validate:
   - `python3 tests/config/validate_configs.py` → expect `OK   rtl_433` and `OK   rtl_433-next`.
   - Confirm both files still parse as JSON (e.g. `python3 -c "import json,sys; json.load(open('rtl_433/config.json'))"`).
4. Do **not** edit `tests/config/validate_configs.py` — its existing options↔schema parity check already covers the new key. (Optionally the maintainer may later add it to `RADIO_OPT_OPTIONS`, but that is out of scope here.)

</details>
