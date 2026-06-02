---
id: 2
group: "config"
dependencies: []
status: "pending"
created: 2026-06-02
skills:
  - json
  - python
---
# Add the three new add-on options to both config.json files and validate them

## Objective
Expose the two features and the noise-scan band list as add-on options on **both** add-ons, defaulting to no behavior change, and extend the config-validation test to cover them.

## Skills Required
- `json` — editing `rtl_433/config.json` and `rtl_433-next/config.json`.
- `python` — extending `tests/config/validate_configs.py`.

## Acceptance Criteria
- [ ] Both `rtl_433/config.json` and `rtl_433-next/config.json` gain three options in **both** their `options` and `schema` blocks:
  - `correct_ppm_offset` → `bool`, default `false`
  - `detect_noise_floor` → `bool`, default `false`
  - `noise_floor_bands` → `str`, default `"433.92M,868M,915M"`
- [ ] Both files remain valid JSON and keep their existing options unchanged.
- [ ] `tests/config/validate_configs.py` asserts the three new keys are present in each add-on's `options` and `schema` with the expected types/defaults.
- [ ] `python3 tests/config/validate_configs.py` exits 0, and `pre-commit run --all-files` (check-json) passes.

## Technical Requirements
Home Assistant add-on `config.json` `options`/`schema` syntax (`bool`, `str`). Standard-library Python for the validator.

## Input Dependencies
None.

## Output Artifacts
- Updated `config.json` for both add-ons.
- Extended `validate_configs.py`.

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. Edit `rtl_433/config.json`:
   - In `options`, add (after the existing three): `"correct_ppm_offset": false`, `"detect_noise_floor": false`, `"noise_floor_bands": "433.92M,868M,915M"`.
   - In `schema`, add: `"correct_ppm_offset": "bool"`, `"detect_noise_floor": "bool"`, `"noise_floor_bands": "str"`.
2. Apply the identical additions to `rtl_433-next/config.json` (it has its own copy of `options`/`schema`).
3. Edit `tests/config/validate_configs.py`:
   - There is an `ADDONS = ["rtl_433", "rtl_433-next"]` list already. Add a check (looping over both add-ons) that each new key exists in `options` and in `schema`, that the two bools default to `false`, that `noise_floor_bands` defaults to the expected string, and that the `schema` types are `bool`/`bool`/`str`. Follow the file's existing per-add-on error-reporting style (collect errors, print a report, exit 1 on any failure).
4. Run `python3 tests/config/validate_configs.py` (expect exit 0) and `pre-commit run --all-files`.

Keep JSON formatting (2-space indent, trailing-newline) consistent with the existing files so check-json and any formatter stay happy.
</details>
