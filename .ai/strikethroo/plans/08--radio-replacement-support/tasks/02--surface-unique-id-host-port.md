---
id: 2
group: "radio-replacement"
dependencies: [1]
status: "completed"
created: 2026-06-03
skills:
  - shell
---
# Surface each radio's unique_id + host:port via log line and radios.status

## Objective
In normal operation (maintenance options off), make each radio's `unique_id` and
`host:port` easy for the user to read — the exact values the companion
integration's reconfigure step asks for. Emit one copy-pasteable log line per
radio and write a human-readable `radios.status` file into the add-on config
directory.

## Skills Required
- `shell` — bash scripting in `run.sh`, reusing the existing host resolution and
  per-radio arrays.

## Acceptance Criteria
- [ ] During normal operation, each launched radio emits a single copy-pasteable
      line, e.g. `Radio <match_id>: unique_id=<serial:…|usbpath:…> host=<host> port=<port>`.
- [ ] A `radios.status` file is written into `conf_directory` listing, per radio,
      its `match_id`, `unique_id`, `host:port`, and current serial.
- [ ] Host resolution reuses the same mechanism the discovery step uses
      (`bashio::addon.hostname` with the Supervisor `self/info` fallback); when the
      host is unavailable, the line/file still shows `unique_id` and `port`.
- [ ] Writing `radios.status` is best-effort: a failure logs and never affects
      radio startup.
- [ ] `shellcheck rtl_433/run.sh` passes with no new findings.

Use your internal Todo tool to track these and keep on track.

## Technical Requirements
- File: `rtl_433/run.sh`.
- Reuse the parallel arrays populated during launch: `radio_ports`, `radio_tags`,
  `radio_unique_ids` (see `main()` and `publish_discovery`).
- Reuse the host-resolution logic from `publish_discovery` (the
  `bashio::addon.hostname` → `curl .../addons/self/info` fallback).
- `conf_directory` is the add-on config dir (`/addon_configs/<slug>/`).

## Input Dependencies
- Task 1: shares `main()` and the maintenance-mode gating. This task edits the
  **normal-operation** path of `main()`; Task 1 edits the maintenance path. They
  touch the same file, so this task runs after Task 1 to avoid edit conflicts.

## Output Artifacts
- Per-radio log line + `radios.status` writer in `rtl_433/run.sh`. Consumed by
  Task 4 (BATS asserts the fields) and Task 5 (README references the file).

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

**Where:** the discovery section runs after radios are launched and the
`radio_ports`/`radio_tags`/`radio_unique_ids` arrays are populated (run.sh
~1180+). Add the surfacing right alongside / after `publish_discovery` is
invoked, in the `${#radio_ports[@]} > 0` branch, so it reflects only radios that
actually started.

**Host resolution:** factor the host lookup out of `publish_discovery` (or
replicate it) so both discovery and the status surfacing use it. Pseudocode:

```sh
resolve_addon_host() {
    local host=""
    if bashio::var.has_value "$(bashio::addon.hostname 2>/dev/null)"; then
        host="$(bashio::addon.hostname)"
    elif [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        host="$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            "http://supervisor/addons/self/info" \
            | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    fi
    printf '%s' "$host"
}
```

**Per-radio log line + status file:**

```sh
surface_radio_status() {
    local host i tag uid port serial status_file tmp
    host="$(resolve_addon_host)"
    status_file="${conf_directory}/radios.status"
    tmp="${status_file}.tmp"
    {
        printf '# rtl_433 radios — values for the Home Assistant reconfigure step\n'
        for i in "${!radio_ports[@]}"; do
            tag="${radio_tags[$i]}"; uid="${radio_unique_ids[$i]}"; port="${radio_ports[$i]}"
            serial="${radio_serials[$i]:-}"   # capture serial during launch if available, else omit
            bashio::log.info "Radio ${tag}: unique_id=${uid} host=${host:-<unknown>} port=${port}"
            printf 'radio=%s\tunique_id=%s\thost=%s\tport=%s\tserial=%s\n' \
                "$tag" "$uid" "${host:-}" "$port" "$serial"
        done
    } > "$tmp" 2>/dev/null && mv "$tmp" "$status_file" 2>/dev/null \
        || bashio::log.warning "Could not write ${status_file} (non-fatal)."
}
```

Note the log lines should be emitted unconditionally (they go to the add-on log
regardless of whether the status file can be written). If capturing the current
serial per radio requires a new parallel array, add a `radio_serials` array
populated where `serial` is known in the launch loop (run.sh ~1079); if that adds
noticeable complexity, the serial field may be derived from the `unique_id`
(`serial:` prefix) or left blank — keep it simple, the `unique_id`+`host:port`
are the required fields.

**Constraints:** best-effort only; never let a status-file failure abort startup.
Keep `main()`-guard intact and functions sourceable for BATS (stub `curl` /
`bashio::addon.hostname`).
</details>
