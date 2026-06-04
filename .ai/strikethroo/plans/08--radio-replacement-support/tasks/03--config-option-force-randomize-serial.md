---
id: 3
group: "radio-replacement"
dependencies: []
status: "completed"
created: 2026-06-03
skills:
  - json
---
# Add force_randomize_serial option to both config.json files

## Objective
Expose the new `force_randomize_serial` option in the add-on configuration so the
user can set a target USB port path from the Home Assistant add-on UI. Add it to
both `rtl_433/config.json` and `rtl_433-next/config.json`, and ensure
`validate_configs.py` passes.

## Skills Required
- `json` — editing add-on `config.json` `options`/`schema` (and, if needed, a
  small Python allowance in `validate_configs.py`).

## Acceptance Criteria
- [ ] `rtl_433/config.json` has `force_randomize_serial: ""` in `options` and
      `force_randomize_serial: "str?"` in `schema`.
- [ ] `rtl_433-next/config.json` has the same two additions.
- [ ] `python3 tests/config/validate_configs.py` exits 0.
- [ ] `check-json` / valid JSON (no trailing commas, keys consistent between
      `options` and `schema`).

Use your internal Todo tool to track these and keep on track.

## Technical Requirements
- Files: `rtl_433/config.json`, `rtl_433-next/config.json`,
  and possibly `tests/config/validate_configs.py`.
- Schema type `"str?"` = optional string (empty/omitted allowed); default `""`.

## Input Dependencies
None — independent of the run.sh logic (run.sh reads the option via
`bashio::config`, which tolerates the key's presence; tests stub the option).

## Output Artifacts
- The new option keys in both config files. Consumed by the runtime option read
  in Task 1's `main()` and by Task 5's README (which references the option name).

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

In each `config.json`, the `options` and `schema` objects currently contain (at
least) `randomize_default_serial`. Add the new key next to it:

`options`:
```json
"randomize_default_serial": false,
"force_randomize_serial": "",
```

`schema`:
```json
"randomize_default_serial": "bool",
"force_randomize_serial": "str?",
```

Apply the identical change to BOTH `rtl_433/config.json` and
`rtl_433-next/config.json`. Preserve existing key order and formatting/indentation
of each file (do not reformat the whole file).

**validate_configs.py:** review `tests/config/validate_configs.py`. It validates
required fields, ports (8433–8442), and a `RADIO_OPT_OPTIONS` map for the
PPM/noise-floor options. `force_randomize_serial` is NOT in that map, so it is
not currently required or rejected — adding an extra option key should pass as-is.
**Run the validator** to confirm. Only if it enforces a strict allowlist that
rejects unknown keys (it does not at time of writing) should you extend it; if you
do, add `force_randomize_serial` with expected default `""` / schema `"str?"` to
the appropriate structure, matching the existing pattern. Do not add validation
the plan does not require.
</details>
