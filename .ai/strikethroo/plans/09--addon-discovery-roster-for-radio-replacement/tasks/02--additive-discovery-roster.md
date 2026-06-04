---
id: 2
group: "addon-runsh"
dependencies: [1]
status: "pending"
created: 2026-06-04
skills:
  - bash
---
# Add an additive `radios` roster to the Supervisor discovery payload (run.sh)

## Objective
Extend `publish_discovery` in `rtl_433/run.sh` so the discovery payload `config`
carries a `radios` array describing **every** launched radio, in addition to the
existing single-radio fields (which stay byte-for-byte unchanged for
back-compat). Each roster entry exposes `unique_id`, `port`, `path`, and **both**
`serial` and `usbpath` (from Task 1). Because the Supervisor collapses an add-on's
same-service discovery messages into one (config of the last publish wins —
confirmed against Supervisor source in the plan), attaching the full array to the
existing per-radio payload leaves the single surviving message carrying the last
radio's legacy fields plus the complete roster. The array must be valid JSON
assembled without `jq`, with device-derived text sanitized so it cannot break the
JSON.

## Skills Required
`bash` — shell scripting and careful hand-built JSON string assembly, matching the
existing `printf`-built payload in `publish_discovery`.

## Acceptance Criteria
- [ ] The discovery payload `config` object gains a `radios` array; each entry has
      `unique_id`, `port` (number), `path` (string), `serial` (string, may be
      empty), and `usbpath` (string, may be empty).
- [ ] The existing top-level `host`/`port`/`path`/`secure`/`unique_id` fields are
      retained unchanged (an un-updated integration sees identical behavior).
- [ ] The roster includes **all** entries in the `radio_*` parallel arrays
      (every launched radio), index-aligned and in array order.
- [ ] `serial` and `usbpath` values are sanitized to the JSON-safe allowlist
      already used by `resolve_radio_unique_id` (`tr -c 'A-Za-z0-9:._-' '_'`), so
      no quote/backslash can break the payload; an empty value renders as `""`.
- [ ] The assembled body is valid JSON (verifiable with `jq .`).
- [ ] No per-message uuid lifecycle is added; `save_discovery_uuid` /
      `remove_discovery_state` behavior is unchanged.
- [ ] `pre-commit run --all-files` passes (shellcheck clean).

## Technical Requirements
- Edit only `rtl_433/run.sh` (the `publish_discovery` function, ~L1406-1452).
- No `jq` at runtime — assemble the JSON with shell/`printf` like the existing
  payload.
- Keep the contract field names exactly: `unique_id`, `port`, `path`, `serial`,
  `usbpath` (these match the integration's `async_step_hassio` consumer; see the
  plan's "Discovery payload contract" subsection).

## Input Dependencies
- Task 1: the `radio_portpaths` parallel array and the existing
  `radio_unique_ids` / `radio_serials` / `radio_ports` arrays.

## Output Artifacts
- A discovery payload whose `config.radios` array is the authoritative current
  roster consumed by the companion integration's Repairs-based replacement flow.

## Implementation Notes

<details>
<summary>Step-by-step</summary>

Edit `publish_discovery` in `rtl_433/run.sh`.

1. **Add a small JSON-string sanitizer** (or inline the `tr`). Mirror the existing
   allowlist so device text is safe inside double quotes:
   ```bash
   _json_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9:._-' '_'; }
   ```
   (Define it near the other helpers, or inline `tr` at each use.)

2. **Build the `radios` array string** once, before/inside the POST loop, by
   iterating the parallel arrays (all index-aligned thanks to Task 1):
   ```bash
   local radios_json="" sep="" j ruid rport rserial rpath rusb
   for j in "${!radio_ports[@]}"
   do
       ruid="$(_json_safe "${radio_unique_ids[$j]}")"
       rport="${radio_ports[$j]}"
       rserial="$(_json_safe "${radio_serials[$j]:-}")"
       rusb="$(_json_safe "${radio_portpaths[$j]:-}")"
       rpath="/ws"
       radios_json+="${sep}{\"unique_id\": \"${ruid}\", \"port\": ${rport}, \"path\": \"${rpath}\", \"serial\": \"${rserial}\", \"usbpath\": \"${rusb}\"}"
       sep=", "
   done
   ```
   `rport` is always numeric (`BASE_PORT + i`), so it is safe unquoted.

3. **Attach the array to the existing payload.** The current body is built with:
   ```bash
   printf -v body \
       '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s"}}' \
       "$host" "$port" "$uid"
   ```
   Add a `radios` member to the inner `config` object (keep the existing members
   first so the legacy shape is untouched):
   ```bash
   printf -v body \
       '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s", "radios": [%s]}}' \
       "$host" "$port" "$uid" "$radios_json"
   ```
   Building `radios_json` once outside the loop and reusing it in each per-radio
   POST is fine (the collapse means only the last surviving message matters, and
   every copy is identical).

4. **Validate JSON locally** while developing:
   ```bash
   printf '%s' "$body" | jq . >/dev/null && echo OK
   ```

5. **Do not touch** `save_discovery_uuid` / `remove_discovery_state` — the
   single-message lifecycle is intentionally unchanged.

6. **Lint:** `pre-commit run --all-files`; fix shellcheck findings.
</details>
