---
id: 3
group: "entrypoint"
dependencies: [1, 2]
status: "completed"
created: "2026-05-31"
skills:
  - bash
complexity_score: 5
complexity_notes: "Single file, single skill (bash), but cohesively rewrites the config/launch model: enumeration-driven execution, identifier-named override append, device/port assignment, log toggle, and discovery adaptation."
---
# Rewrite run.sh: enumeration-driven config with per-radio append overrides

## Objective
Rewrite `rtl_433/run.sh` so the add-on no longer reads or writes the Home Assistant config directory or relies on user template files to declare radios. Instead it: runs one rtl_433 process per **auto-detected** RTL-SDR dongle using the internal baked-in default; optionally appends a per-radio override file (named after the radio's stable identifier) from the add-on config directory; appends `output kv` when the "Log received messages" option is on; and keeps the existing stable port assignment and Supervisor discovery publication.

## Skills Required
- `bash`: shell rewrite using bashio, sysfs enumeration, rtl_433 config rendering, and the Supervisor discovery API.

## Acceptance Criteria
- [ ] `run.sh` no longer creates, reads, or writes `/config/rtl_433` and no longer writes any default template into a user-visible directory.
- [ ] The add-on config directory is set to the `addon_config` mount (`/config` in-container) and is only read for optional `*.conf` override files.
- [ ] Execution is driven by `enumerate_rtlsdr_devices`: one rtl_433 process is launched per detected dongle, in the existing stable order, with sequential ports from `BASE_PORT` (`8433`), capped at `MAX_RADIOS`.
- [ ] For each radio, the rendered config is built from `/etc/rtl_433/rtl_433.defaults.conf` (baked in task 1) plus an injected `device` line selecting that dongle.
- [ ] For each radio, if a file named `<identifier>.conf` exists in the add-on config dir (identifier = serial when usable, else USB port path — reuse the existing resolution preference), its contents are appended **after** the default and the injected device line.
- [ ] The add-on logs, per detected radio, the exact override filename a user can create to customize it.
- [ ] Override files present in the dir that match no detected radio are logged as ignored (warning).
- [ ] When the `log_received_messages` option is true, `output kv` is appended to every radio's rendered config; when false it is absent.
- [ ] The `${port}` placeholder in the default config is substituted with the radio's assigned port in the rendered config.
- [ ] Supervisor discovery publication still runs per radio with a stable `unique_id` (reuse `resolve_radio_unique_id`).
- [ ] `shellcheck` passes (`pre-commit run --files rtl_433/run.sh`).

## Technical Requirements
- Internal default path: `/etc/rtl_433/rtl_433.defaults.conf`.
- Add-on config dir: `/config` (the `addon_config` mount).
- Option read: `bashio::config 'log_received_messages'`.
- Reuse existing functions verbatim where possible: `enumerate_rtlsdr_devices`, `_serial_is_usable`, `resolve_radio_unique_id`, and the `rtlsdr_devices` array population.
- Preserve `BASE_PORT=8433`, `MAX_RADIOS=10`, `SYSFS_USB_BASE` override hook, and the discovery `publish_discovery` machinery.

## Input Dependencies
- Task 1: `/etc/rtl_433/rtl_433.defaults.conf` exists in the image.
- Task 2: `config.json` declares `addon_config:rw` and the `log_received_messages` option.

## Output Artifacts
- Rewritten `rtl_433/run.sh`.

## Implementation Notes
<details>
<summary>Step-by-step guidance</summary>

Keep the top-of-file helper functions that still apply: `enumerate_rtlsdr_devices`, `_serial_is_usable`, and `resolve_radio_unique_id`. Remove the heredoc that wrote the default template and the `*.conf.template` discovery/sorting loop. Replace the driver loop so it iterates `rtlsdr_devices` (the enumerated dongles) instead of `sorted_templates`.

1. **Constants / paths**: keep `BASE_PORT`, `MAX_RADIOS`, `SYSFS_USB_BASE`, `RTLSDR_KNOWN_IDS`. Replace `conf_directory="/config/rtl_433"` with `conf_directory="/config"` (the addon_config mount). Add `default_conf="/etc/rtl_433/rtl_433.defaults.conf"`. Define a render output dir, e.g. `render_dir="/tmp/rtl_433"`, and `mkdir -p "$render_dir"`; do NOT render into the user config dir.

2. **Read the log option** near the top:
   ```bash
   log_received_messages="false"
   if bashio::config.true 'log_received_messages'; then
       log_received_messages="true"
   fi
   ```
   (Use `bashio::config.true` which returns success when the option is `true`.)

3. **Enumerate**: keep `mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)`. If `${#rtlsdr_devices[@]}` is 0, `bashio::log.warning` that no RTL-SDR dongles were detected and skip launching (still call `publish_discovery` with empty arrays, which is a no-op, then `wait`/exit gracefully — mirror current graceful degradation).

4. **Identifier for matching**: you need the RAW identifier (without the `serial:`/`usbpath:` prefix) to match a filename, plus the prefixed `unique_id` for discovery. Add a small helper, or inline logic, that given an enumerated entry (`serial<TAB>portpath`) returns the match identifier: the serial when `_serial_is_usable "$serial"`, else the port path. Sanitize it to a filename-safe set the same way `resolve_radio_unique_id` sanitizes (`tr -c 'A-Za-z0-9:._-' '_'`), so the logged filename and the on-disk filename agree. Keep using `resolve_radio_unique_id "$device" "$tag"` for the discovery `unique_id` value.

5. **Driver loop** over `"${!rtlsdr_devices[@]}"` (index `i`):
   - Stop/skip past `MAX_RADIOS` with the existing warning.
   - `entry="${rtlsdr_devices[$i]}"`; `serial="${entry%%$'\t'*}"`; `portpath="${entry#*$'\t'}"`.
   - `port=$((BASE_PORT + i))`.
   - Determine the rtl_433 `device` selector for this dongle: if `_serial_is_usable "$serial"`, use `:"$serial"` (serial selector); else use the index `i` (bare index selector). Set `device_line="device ${selector}"`.
   - Compute `match_id` (step 4) and `expected_file="${conf_directory}/${match_id}.conf"`.
   - `tag` for logs/discovery: use `match_id` (or `radio${i}`); pass the dongle's device value to `resolve_radio_unique_id`. For the unique_id call, pass the selector you used (`:"$serial"` or `"$i"`) as the `device` argument and `tag` as the second arg so the existing resolution matches the enumerated entry.
   - Log: `bashio::log.info "Radio ${match_id} -> HTTP port ${port}. To customize, create ${expected_file}."`

   - **Render the config** into `live="${render_dir}/${match_id}.conf"`:
     ```bash
     {
       echo "$device_line"
       cat "$default_conf"
       if [ -f "$expected_file" ]; then
         echo
         echo "# --- appended from ${expected_file} ---"
         cat "$expected_file"
       fi
       if [ "$log_received_messages" = "true" ]; then
         echo
         echo "output kv"
       fi
     } > "${live}.raw"
     ```
     Then substitute `${port}` (and allow the existing "template is sourced as bash" behavior if you want to preserve advanced substitution). The simplest faithful port substitution that preserves the existing heredoc-sourcing capability:
     ```bash
     {
       echo "cat <<EOD > $live"
       cat "${live}.raw"
       echo
       echo EOD
     } > /tmp/rtl_433_heredoc
     # shellcheck source=/dev/null
     source /tmp/rtl_433_heredoc
     ```
     This keeps the existing semantics where `${port}` is expanded (and users may use shell escapes), now applied to default+override instead of a user template. `port` must be in scope (it is). Keep the `# shellcheck disable=SC2034` note for `port` if needed.

   - Launch: `rtl_433 -c "$live" > >(sed -u "s/^/[$match_id] /") 2> >(>&2 sed -u "s/^/[$match_id] /") &` and record the pid, exactly as today.
   - Populate the discovery parallel arrays: `radio_ports+=("$port")`, `radio_tags+=("$match_id")`, `radio_unique_ids+=("$unique_id")`.

6. **Unmatched override files**: after the loop, scan `"$conf_directory"/*.conf` and warn for any whose basename (minus `.conf`) is not among the matched identifiers. Build a set of matched ids during the loop (e.g. an associative array or a space-padded string) and test membership. Skip the glob-literal when no files exist (`[ -e "$f" ] || continue`).

7. **Discovery**: leave `publish_discovery` and its call intact; it consumes the parallel arrays you populated.

8. **Wait**: keep `wait -n "${rtl_433_pids[@]}"` (guard for the empty case so it does not error when no radios launched — e.g. only `wait` if `${#rtl_433_pids[@]}` > 0, otherwise sleep/exit appropriately).

9. **Lint**: run `pre-commit run --files rtl_433/run.sh` and resolve any shellcheck findings (quote expansions, `# shellcheck disable=` only where already idiomatic in this file).

10. Sanity-test the enumeration path locally if possible by pointing `SYSFS_USB_BASE` at a mock tree with fake `idVendor`/`idProduct`/`serial` files matching a known RTL-SDR id, and confirm two fake dongles render two configs on ports 8433/8434 with the default content and correct device lines. Stub the actual `rtl_433`/`bashio` calls as needed for a dry run.
</details>
