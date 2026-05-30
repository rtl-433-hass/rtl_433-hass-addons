---
id: 2
group: "remove-mqtt-http"
dependencies: []
status: "pending"
created: "2026-05-30"
skills:
  - bash
complexity_score: 5
complexity_notes: "Core entrypoint rewrite: MQTT removal, deterministic port assignment, HTTP template, and per-radio launch. Kept as one task because the steps share the same file and control flow; discovery publication is split into task 3."
---
# Rewrite run.sh: HTTP output with stable per-radio ports

## Objective
Replace the MQTT-based entrypoint logic with HTTP output: remove the MQTT/`retain`/legacy-file code, generate an HTTP default template, deterministically assign a stable port to each radio from its `device` value, render each template with its port, and launch one rtl_433 HTTP server per radio.

## Skills Required
- `bash`: `bashio`, heredoc templating, array handling, sorting, process launch/`wait`, shellcheck-clean scripting.

## Acceptance Criteria
- [ ] All MQTT service lookups (`bashio::services "mqtt" …`), the `retain` handling, and the `rtl_433_conf_file` legacy branch are removed from `rtl_433/run.sh`.
- [ ] On an empty config dir, the generated default `rtl_433.conf.template` contains a `device` line and an `output http` line bound to the assigned port, with no `mqtt` line; existing helpful defaults (report_meta, TPMS `protocol -` exclusions) are retained.
- [ ] Templates are sorted by their `device` value and assigned ports `8433 + index` (8433 for the first device, up to 8442), and the mapping is identical across repeated runs for the same device set.
- [ ] A maximum of 10 radios is enforced; if more than 10 templates exist, the script logs a clear message and does not assign an 11th port.
- [ ] Each radio's assigned port is substituted into its rendered `.conf` so the `output http` line binds that port; one rtl_433 process is launched per radio and the script waits on them.
- [ ] `shellcheck` (via pre-commit) passes; the device→port mapping is logged on startup.

## Technical Requirements
rtl_433 HTTP output syntax is `output http://<bind>:<port>` in a config file (CLI equivalent `-F http[:[//]bind[:port]]`, default `0.0.0.0:8433`); the integration connects to `ws://host:<port>/ws`. Device selection uses a `device` line (`device 0`, `device :SERIAL`, or a SoapySDR string) which must appear before output lines. The `rtl_433` binary copied into the image must already be invoked the same way as today (`rtl_433 -c <conf>`).

## Input Dependencies
None (operates on `rtl_433/run.sh`). The config.json permission/port changes (task 1) are complementary but not required to author this script.

## Output Artifacts
Rewritten `rtl_433/run.sh` exposing, for the discovery step (task 3), the per-radio device→port mapping (e.g. via a shell array or a structure the discovery code can iterate). The launch loop and port-assignment logic are the integration point for task 3.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

Start from the existing `rtl_433/run.sh`. Preserve the overall shape (bashio shebang, `conf_directory="/config/rtl_433"`, create-dir-if-missing, default-template-on-empty, remove old `*.conf`, render templates via heredoc, launch + `wait`). Change these parts:

1. **Remove the MQTT block** at the top (the entire `if bashio::services.available "mqtt"; then … else … fi`) and the `retain` conversion.

2. **Remove the legacy `rtl_433_conf_file` branch** entirely (the `conf_file=$(bashio::config "rtl_433_conf_file")` block that runs `rtl_433 -c "$conf_file"` and exits).

3. **Default template (empty-dir case):** rewrite the heredoc that creates `rtl_433.conf.template` so it:
   - Begins with a comment block explaining HTTP output and multi-radio `device`/port behaviour (replace the MQTT-oriented comments).
   - Includes a `device 0` line (with a comment that each radio's template must set a distinct `device`, e.g. `device :SERIAL`, and that the `device` line must come before output lines).
   - Includes an HTTP output line that binds the assigned port using the existing env-substitution mechanism, e.g. `output http://0.0.0.0:\${port}` (the `\${port}` is filled in during rendering, mirroring how `\${host}` was filled before).
   - Keeps `report_meta time:iso:usec:tz` and the full block of `protocol -NN` TPMS exclusions.
   - Contains NO `output mqtt` line and no `output kv` requirement (the commented kv hint may stay).

4. **Port assignment:** after determining the list of templates (`"$conf_directory"/*.conf.template`), build a deterministic ordering. For each template, extract its `device` value (grep the first `device ` line; default to empty/`0` if absent and log a warning). Sort the templates by that device value. Assign `port = 8433 + i` for the i-th template (0-based). Define `BASE_PORT=8433` and `MAX_RADIOS=10`. If the template count exceeds `MAX_RADIOS`, log via `bashio::log.warning` (or `echo`) a clear message naming the cap and only process the first 10 in sorted order. Log the full device→port mapping with `bashio::log.info`.

5. **Rendering:** keep the heredoc-source mechanism but set `port` (and confirm `device`) as shell variables before sourcing each template so `\${port}` substitutes correctly. Each template keeps its own `device` line from its file content; `port` is the per-radio assigned value.

6. **Launch:** keep the per-radio launch with the `[$tag]` log prefix and `rtl_433_pids+=($!)`, then `wait -n "${rtl_433_pids[@]}"`. Preserve the existing stdout/stderr `sed` tagging.

7. **Expose the mapping for task 3:** keep parallel arrays (e.g. `radio_devices`, `radio_ports`, `radio_tags`) populated during assignment/launch so task 3 can iterate them to publish discovery. Do not implement the discovery POST here.

Keep shellcheck happy: quote variables, use `# shellcheck disable=` only where genuinely needed (as the repo already does), and avoid unused variables.

Do NOT edit `rtl_433-next/` — it has no `run.sh` of its own (the `-next` image reuses the same build context). Confirm by checking the directory; only `rtl_433/run.sh` exists.
</details>
