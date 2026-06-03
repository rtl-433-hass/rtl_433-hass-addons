---
id: 3
group: "remove-mqtt-http"
dependencies: [1, 2]
status: "completed"
created: "2026-05-30"
skills:
  - bash
  - home-assistant
---
# Publish each radio to the Supervisor discovery API

## Objective
After the radios launch, POST one discovery message per radio to the Home Assistant Supervisor discovery API so the rtl_433 integration can offer to set up each radio automatically. Publication must be best-effort and never block the radios from running.

## Skills Required
- `bash`: `curl`/HTTP calls, JSON construction, error handling, iterating the device→port arrays from task 2.
- `home-assistant`: Supervisor discovery API contract (endpoint, auth token, payload shape) and the connection fields the rtl_433 integration expects.

## Acceptance Criteria
- [ ] For each launched radio, `run.sh` sends a discovery message to the Supervisor discovery API using the Supervisor token, carrying the radio's connection details (host reachable by Home Assistant and the radio's assigned port; include the integration's expected `path`/`secure` defaults).
- [ ] The discovery `service` name matches the `discovery` entry declared in `config.json` (task 1).
- [ ] Publication is best-effort: a failed POST is logged (non-fatal) and does not prevent radios from running or the script from reaching its `wait`.
- [ ] The discovery call happens after the rtl_433 processes are launched but before/around the final `wait`, so it does not block radio startup.
- [ ] `shellcheck` (via pre-commit) passes.

## Technical Requirements
The Supervisor API is reachable from inside the add-on at `http://supervisor/discovery` using the `$SUPERVISOR_TOKEN` bearer token (granted by `hassio_api: true` from task 1). A discovery message includes a `service` identifier and a `config` object with the integration's connection parameters. The rtl_433 integration consumes `host`, `port` (default 8433), `path` (default `/ws`), and `secure` (default false).

## Input Dependencies
- Task 1: `config.json` must grant `hassio_api: true` and declare the `discovery` service.
- Task 2: `run.sh` must expose the per-radio device→port mapping arrays and the launch loop to hook into.

## Output Artifacts
`run.sh` augmented with a discovery-publication step iterating all radios.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

Add a publication step to `rtl_433/run.sh` after the launch loop (task 2) populates the `radio_devices`/`radio_ports` arrays and starts the processes.

1. **Endpoint & auth:** POST to `http://supervisor/discovery` with header `Authorization: Bearer ${SUPERVISOR_TOKEN}` and `Content-Type: application/json`. `SUPERVISOR_TOKEN` is provided in the add-on environment when `hassio_api: true`. Guard for its absence (log and skip if empty) so local/test runs don't fail.

2. **Host value:** determine the host Home Assistant should connect to. Do not hard-code an IP. Prefer the add-on's Supervisor-provided hostname (e.g. from the add-on self info via `bashio::addon.hostname` / the Supervisor `/addons/self/info` endpoint) or document the chosen source inline. The integration connects to `ws://<host>:<port>/ws`.

3. **Payload:** for each radio i, build a JSON body of the form:
   `{"service": "rtl_433", "config": {"host": "<host>", "port": <port_i>, "path": "/ws", "secure": false}}`
   Construct JSON safely (prefer `jq -n` if available in the image, otherwise a carefully-quoted printf). The `service` string must equal the `discovery` value in `config.json`.

4. **Best-effort semantics:** wrap each `curl` in error handling: capture the HTTP status, `bashio::log.info` on success and `bashio::log.warning` on failure, but never `exit` non-zero from a publish failure. The Supervisor may reject the service if the integration has not registered discovery support yet — log this clearly as expected/non-fatal.

5. **Ordering:** publish after launching processes (so a radio that failed to start isn't advertised — optionally check the pid is alive), and ensure the final `wait -n "${rtl_433_pids[@]}"` still executes so the container stays alive.

6. Keep all additions shellcheck-clean and consistent with the repo's existing `# shellcheck disable=` style.

If `jq` is not present in the runtime image (check the Dockerfile's `apk add` list — it installs `sed` but not `jq`), either add `jq` to the image or build the JSON with printf; prefer printf to avoid changing the image in this task. If you choose to add `jq`, coordinate with the Dockerfile and note it; the simpler path is a printf template.
</details>
