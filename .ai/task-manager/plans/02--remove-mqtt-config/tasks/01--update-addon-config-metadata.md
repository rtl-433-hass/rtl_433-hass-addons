---
id: 1
group: "remove-mqtt-http"
dependencies: []
status: "pending"
created: "2026-05-30"
skills:
  - home-assistant
  - json
---
# Update add-on config.json metadata for HTTP + discovery

## Objective
Remove all MQTT-related metadata from both add-ons and grant the permissions needed for the HTTP server and Supervisor discovery, so the add-on no longer depends on an MQTT broker and can publish discovery messages.

## Skills Required
- `home-assistant`: knowledge of add-on `config.json` services, schema, options, API permissions, and `discovery`/`ports` fields.
- `json`: valid JSON edits that pass `check-json`.

## Acceptance Criteria
- [ ] `rtl_433/config.json` and `rtl_433-next/config.json` no longer contain `"services": ["mqtt:want"]`.
- [ ] The `retain` and `rtl_433_conf_file` options and their `schema` entries are removed from both files.
- [ ] Both files grant the Supervisor discovery permission (`hassio_api: true`) and declare the rtl_433 discovery service.
- [ ] Both files expose the HTTP port range used by radios so Home Assistant can reach the servers.
- [ ] Both files remain valid JSON (pre-commit `check-json` passes) and keep their existing differing values (`name`, `image`, `slug`, `version`, `url`).

## Technical Requirements
Home Assistant add-on configuration schema. The discovery permission requires `hassio_api: true`. Declaring `discovery: ["rtl_433"]` tells the Supervisor the add-on will publish that discovery service. Ports are exposed via the `ports` map.

## Input Dependencies
None.

## Output Artifacts
Updated `rtl_433/config.json` and `rtl_433-next/config.json` providing the permission/port surface consumed by the discovery publication in task 3 and the run.sh changes in task 2.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

Current `rtl_433/config.json` (and `rtl_433-next/config.json`, which mirrors it with different `name`/`image`/`slug`/`version`/`url`) contains:

```
"services": ["mqtt:want"],
...
"options": { "rtl_433_conf_file": "", "retain": true },
"schema": { "rtl_433_conf_file": "str?", "retain": "bool" }
```

Make these edits to BOTH files, preserving each file's distinct `name`/`image`/`slug`/`version`/`url`:

1. **Delete** the `"services": ["mqtt:want"],` line entirely.
2. **Replace** the `options` object so it no longer has `rtl_433_conf_file` or `retain`. The add-on currently has no other options. If no options remain, set `"options": {}` and `"schema": {}` (keep both keys present and valid).
3. **Add** `"hassio_api": true,` to grant Supervisor API access (needed to POST discovery).
4. **Add** a discovery declaration: `"discovery": ["rtl_433"],`.
5. **Expose the HTTP ports.** The radios bind ports 8433–8442 (base 8433, up to 10 radios). Add a `ports` map exposing this range to the host network so Home Assistant can reach `ws://host:<port>/ws`, e.g. entries of the form `"8433/tcp": 8433` through `"8442/tcp": 8442`. Use `tcp`. Keep formatting consistent with the file.

Keep `"arch"`, `"init": false`, `"map": ["homeassistant_config:rw"]`, `"usb": true`, `"udev": true` unchanged.

Validate with: `python3 -c "import json,sys; json.load(open('rtl_433/config.json')); json.load(open('rtl_433-next/config.json')); print('ok')"` or rely on the `check-json` pre-commit hook.

Note: the exact `discovery` service name (`rtl_433`) must match what the discovery publication in task 3 sends and what the integration will register; keep them identical.
</details>
