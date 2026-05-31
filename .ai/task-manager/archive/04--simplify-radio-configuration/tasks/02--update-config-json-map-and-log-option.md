---
id: 2
group: "addon-metadata"
dependencies: []
status: "completed"
created: "2026-05-31"
skills:
  - json
---
# Migrate add-on config dir and add the "Log received messages" option

## Objective
Update both add-on manifests so configuration storage moves from the Home Assistant config directory to the add-on's own config directory, and add a boolean "Log received messages" option that the entrypoint will read to enable `output kv`.

## Skills Required
- `json`: edit Home Assistant add-on `config.json` (`map`, `options`, `schema`) keeping valid JSON.

## Acceptance Criteria
- [ ] In both `rtl_433/config.json` and `rtl_433-next/config.json`, the `map` array replaces `homeassistant_config:rw` with `addon_config:rw` (and contains no other map entries unless already present).
- [ ] Both manifests gain an `options` object with `log_received_messages: false`.
- [ ] Both manifests gain a `schema` object with `log_received_messages: "bool"`.
- [ ] Both files remain valid JSON and pass `check-json`.

## Technical Requirements
- HA add-on option name: `log_received_messages` (boolean, default `false`).
- `map` value: `addon_config:rw` (mounts the add-on's private config at `/config` in-container, surfaced to users at `/addon_configs/rtl433/`).
- Do not change `version`, `ports`, `discovery`, `usb`, `udev`, or `hassio_api`.

## Input Dependencies
None.

## Output Artifacts
- Updated `rtl_433/config.json` and `rtl_433-next/config.json` — the option name and map are consumed by the `run.sh` rewrite (task 3) and the docs (task 4).

## Implementation Notes
<details>
<summary>Step-by-step guidance</summary>

1. Edit `rtl_433/config.json`:
   - Change `"map": ["homeassistant_config:rw"]` to `"map": ["addon_config:rw"]`.
   - Add two top-level keys (anywhere valid, e.g. after `"discovery"`):
     ```json
     "options": {
       "log_received_messages": false
     },
     "schema": {
       "log_received_messages": "bool"
     },
     ```
   - Mind trailing commas — JSON does not allow them. Place the new keys so the surrounding commas stay valid.

2. Apply the identical changes to `rtl_433-next/config.json`. Note its `map` is currently written as `["homeassistant_config:rw"]` on one line — change it to `["addon_config:rw"]`. Add the same `options` and `schema` blocks. (CI copies `rtl_433/*` into `rtl_433-next/` with `cp -n`, which does NOT overwrite an existing `config.json`, so this file must be edited directly.)

3. Validate: run `pre-commit run --files rtl_433/config.json rtl_433-next/config.json` and confirm `check-json` passes. Optionally `jq '.map, .options, .schema' rtl_433/config.json rtl_433-next/config.json` to eyeball the result.

4. Do not write the bashio read logic here — that belongs to task 3. This task only declares the option and the map.
</details>
