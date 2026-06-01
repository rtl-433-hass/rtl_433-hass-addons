#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# Add-on config directory (the 'addon_config' mount). Read-only for optional
# per-radio '<identifier>.conf' override files; the add-on never writes here.
conf_directory="/config"

# Internal default rtl_433 configuration baked into the image. Rendered configs
# are built from this default plus an injected 'device' line and any matching
# per-radio override file.
default_conf="/etc/rtl_433/rtl_433.defaults.conf"

# TPMS protocol disables generated at image build time (see Dockerfile). Appended
# to each rendered config only when the 'disable_tpms' add-on option is enabled.
tpms_disables_conf="/etc/rtl_433/rtl_433.tpms-disables.conf"

# Directory the rendered, ready-to-run config files are written to. Kept under
# /tmp so nothing is ever written into the user-visible config directory.
render_dir="/tmp/rtl_433"

# Base port for the first radio's HTTP server. Each additional radio is assigned
# the next sequential port. The Home Assistant integration connects to
# ws://<host>:<port>/ws.
BASE_PORT=8433

# Maximum number of radios (and therefore HTTP ports) supported. Templates
# beyond this count are skipped.
MAX_RADIOS=10

# Restart-backoff bounds (seconds) for a supervised radio. A crashed/failed
# rtl_433 is restarted after RADIO_RESTART_MIN_DELAY, doubling on each repeated
# quick failure up to RADIO_RESTART_MAX_DELAY. A run that stays up at least
# RADIO_HEALTHY_UPTIME seconds resets the backoff to the minimum, so a one-off
# crash recovers immediately while a hard failure (e.g. a permanently busy or
# unplugged dongle) backs off instead of hammering in a tight loop.
RADIO_RESTART_MIN_DELAY=2
RADIO_RESTART_MAX_DELAY=60
RADIO_HEALTHY_UPTIME=60

# Base sysfs path for USB device enumeration. Overridable so the enumeration can
# be exercised against a mock tree in tests.
SYSFS_USB_BASE="${SYSFS_USB_BASE:-/sys/bus/usb/devices}"

# Per-add-on persistent storage (the always-present '/data' volume). Used to
# remember the Supervisor discovery message's uuid across restarts so a later
# run with no radios can delete it. Overridable so tests can use a temp dir.
DATA_DIR="${DATA_DIR:-/data}"

# Known RTL-SDR USB VID:PID identifiers (from librtlsdr's known-device table),
# stored space-padded so a membership test is a simple glob. Used to pick out
# RTL-SDR dongles while enumerating sysfs.
RTLSDR_KNOWN_IDS=" 0bda:2832 0bda:2838 0413:6680 0413:6f0f 0458:707f \
0ccd:00a9 0ccd:00b3 0ccd:00b4 0ccd:00b5 0ccd:00b7 0ccd:00b8 0ccd:00c0 0ccd:00c6 \
0ccd:00d3 0ccd:00d7 0ccd:00e0 1554:5020 15f4:0131 15f4:0133 185b:0620 185b:0650 \
185b:0680 1b80:d393 1b80:d394 1b80:d395 1b80:d397 1b80:d398 1b80:d39d 1b80:d3a4 \
1b80:d3a8 1b80:d3af 1b80:d3b0 1d19:1101 1d19:1102 1d19:1103 1d19:1104 1f4d:a803 \
1f4d:b803 1f4d:c803 1f4d:d286 1f4d:d803 1209:2832 "

# Enumerate connected RTL-SDR dongles from sysfs. Prints one
# "serial<TAB>portpath" line per matching device (serial may be empty), sorted
# by port path for a deterministic ordering that approximates librtlsdr's index
# enumeration. USB interfaces ('1-1.4:1.0'), root hubs ('usb1'), and non-RTL-SDR
# devices are skipped. A missing/empty sysfs tree yields no output (and never
# errors), so non-Supervisor runs degrade gracefully.
enumerate_rtlsdr_devices() {
    local dev name vid pid serial
    for dev in "$SYSFS_USB_BASE"/*
    do
        [ -e "$dev" ] || continue
        name="$(basename "$dev")"
        # Skip USB interfaces (they carry a ':' in the node name).
        case "$name" in
            *:*) continue ;;
        esac
        if [ ! -r "$dev/idVendor" ] || [ ! -r "$dev/idProduct" ]
        then
            continue
        fi
        vid="$(cat "$dev/idVendor" 2>/dev/null)"
        pid="$(cat "$dev/idProduct" 2>/dev/null)"
        case "$RTLSDR_KNOWN_IDS" in
            *" ${vid}:${pid} "*) ;;
            *) continue ;;
        esac
        serial=""
        if [ -r "$dev/serial" ]
        then
            serial="$(cat "$dev/serial" 2>/dev/null)"
        fi
        printf '%s\t%s\n' "$serial" "$name"
    done | sort -t"$(printf '\t')" -k2,2 -V
}

# Decide whether a USB serial is usable as a stable identifier. A serial only
# counts when it is present, not a known factory default/placeholder, not a
# short reserved integer (which collides with the device index), and unique
# among the enumerated dongles (the 'rtlsdr_devices' array). Args: <serial>.
_serial_is_usable() {
    local serial="$1" count=0 entry s
    [ -n "$serial" ] || return 1
    case "$serial" in
        00000000|00000001) return 1 ;;
    esac
    [[ "$serial" =~ ^[0-9]{1,3}$ ]] && return 1
    for entry in "${rtlsdr_devices[@]}"
    do
        s="${entry%%$'\t'*}"
        [ "$s" = "$serial" ] && count=$((count + 1))
    done
    [ "$count" -le 1 ]
}

# Resolve a stable unique identifier for one radio. Args: <device_value> <tag>.
# Reads the enumerated 'rtlsdr_devices' array. Layered strategy:
#   1. usable serial      -> 'serial:<serial>'  (survives moving USB ports)
#   2. else USB port path -> 'usbpath:<path>'   (stable per physical port)
#   3. else template tag  -> 'template:<tag>'   (deterministic last resort)
# The result is sanitised to a JSON-safe allowlist so the hand-built discovery
# payload stays valid without jq.
resolve_radio_unique_id() {
    local device="$1" tag="$2"
    local entry sel match_serial="" match_path="" found=0 result

    if [ -n "$device" ] && [ "${device#:}" != "$device" ]
    then
        # ':SERIAL' selector — match the enumerated entry by serial.
        sel="${device#:}"
        for entry in "${rtlsdr_devices[@]}"
        do
            if [ "${entry%%$'\t'*}" = "$sel" ]
            then
                match_serial="${entry%%$'\t'*}"
                match_path="${entry#*$'\t'}"
                found=1
                break
            fi
        done
    elif [[ "$device" =~ ^[0-9]+$ ]]
    then
        # Bare index selector — take the Nth enumerated device.
        if [ "$device" -lt "${#rtlsdr_devices[@]}" ]
        then
            entry="${rtlsdr_devices[$device]}"
            match_serial="${entry%%$'\t'*}"
            match_path="${entry#*$'\t'}"
            found=1
        fi
    fi

    if [ "$found" -eq 1 ] && _serial_is_usable "$match_serial"
    then
        result="serial:${match_serial}"
    elif [ "$found" -eq 1 ] && [ -n "$match_path" ]
    then
        result="usbpath:${match_path}"
    else
        result="template:${tag}"
    fi

    printf '%s' "$result" | tr -c 'A-Za-z0-9:._-' '_'
}

# Compute the raw match identifier for one enumerated dongle. This is the bare
# value (no 'serial:'/'usbpath:' prefix) used to name an override file:
#   * the USB serial when it is usable as a stable identifier, else
#   * the USB port path.
# It is sanitised to a filename-safe allowlist so the logged filename and the
# on-disk filename agree. Args: <serial> <portpath>.
radio_match_id() {
    local serial="$1" portpath="$2" raw
    if _serial_is_usable "$serial"
    then
        raw="$serial"
    else
        raw="$portpath"
    fi
    printf '%s' "$raw" | tr -c 'A-Za-z0-9:._-' '_'
}

# Supervise a single radio: run its rtl_433 in a restart loop so a single
# device failure (USB busy, dongle unplugged, decoder crash) only restarts that
# radio rather than taking down the whole add-on. Uses exponential backoff
# (capped at RADIO_RESTART_MAX_DELAY) for repeated quick failures, reset once a
# run stays up at least RADIO_HEALTHY_UPTIME seconds. Intended to run in a
# background subshell whose stdout/stderr are '[tag]'-prefixed by the caller, so
# it loops forever; the add-on stays alive as long as any radio is supervised.
# rtl_433 is run in the background and waited on so a shutdown signal interrupts
# the wait promptly; the trap forwards SIGTERM to it for a clean stop.
# Args: <tag> <live_config_path>.
supervise_radio() {
    local tag="$1" live="$2"
    local delay="$RADIO_RESTART_MIN_DELAY" start uptime code child=""
    trap 'kill -TERM "$child" 2>/dev/null; exit 0' TERM INT
    while true
    do
        start="$SECONDS"
        rtl_433 -c "$live" &
        child="$!"
        wait "$child"
        code="$?"
        uptime=$(( SECONDS - start ))
        # A run that stayed healthy resets the backoff; repeated quick failures
        # let it grow toward the cap.
        if [ "$uptime" -ge "$RADIO_HEALTHY_UPTIME" ]
        then
            delay="$RADIO_RESTART_MIN_DELAY"
        fi
        echo "rtl_433 exited (status ${code}, ran ${uptime}s); restarting in ${delay}s." >&2
        # Interruptible sleep so a shutdown signal during the backoff is handled
        # immediately rather than after the full delay.
        sleep "$delay" &
        wait "$!"
        delay=$(( delay * 2 ))
        [ "$delay" -gt "$RADIO_RESTART_MAX_DELAY" ] && delay="$RADIO_RESTART_MAX_DELAY"
    done
}

# Run the add-on: read options, enumerate radios, launch rtl_433 per radio,
# publish discovery, then block. Defined as a function so the file can be sourced
# (e.g. by BATS tests) to load the pure helpers above without executing any of
# this. Variables here are intentionally global (no 'local') so the nested and
# top-level helpers continue to read them.
main() {
    # Read the "Disable TPMS sensors" add-on option (default on). When true, the
    # build-time-generated TPMS 'protocol -N' disables are appended to every radio's
    # rendered config. When false, no disables are appended, so every decoder
    # rtl_433 ships is enabled.
    disable_tpms="false"
    if bashio::config.true 'disable_tpms'
    then
        disable_tpms="true"
    fi

    # Read the "Log received messages" add-on option. When true, 'output kv' is
    # appended to every radio's rendered config so decoded events show in the log.
    log_received_messages="false"
    if bashio::config.true 'log_received_messages'
    then
        log_received_messages="true"
    fi

    # Read the "Log diagnostic messages" add-on option. When true, 'output log' is
    # appended to every radio's rendered config so rtl_433's own status/diagnostic
    # messages show in the log. This is separate from the decoded-event 'output kv'.
    log_diagnostic_messages="false"
    if bashio::config.true 'log_diagnostic_messages'
    then
        log_diagnostic_messages="true"
    fi

    # Directory rendered configs are written to. Never the user config directory.
    mkdir -p "$render_dir"

    # Enumerate RTL-SDR dongles once so each radio's identifier can be resolved from
    # real hardware (serial / USB port path) rather than the unstable device index.
    mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)

    # Parallel arrays describing each launched radio. These are populated during port
    # assignment/launch and consumed by the Supervisor discovery step below, which
    # iterates them to publish one Home Assistant discovery message per radio.
    radio_ports=()
    radio_tags=()
    radio_unique_ids=()

    # Space-padded set of override identifiers that matched a detected radio, so we
    # can warn about leftover '<id>.conf' files that match nothing.
    matched_ids=" "

    rtl_433_pids=()

    # Forward shutdown signals to the radio supervisors so each rtl_433 gets a
    # clean SIGTERM (and the supervisors stop looping) instead of being
    # SIGKILLed when the container stops.
    shutting_down="false"
    trap 'shutting_down="true"; [ "${#rtl_433_pids[@]}" -gt 0 ] && kill -TERM "${rtl_433_pids[@]}" 2>/dev/null' TERM INT

    # Render one radio's config from the baked-in default and launch rtl_433 for it.
    # Args:
    #   $1 port          - assigned HTTP port (substituted into the default's ${port})
    #   $2 tag           - short label used for log prefixing and the render filename
    #   $3 device_line   - 'device ...' line injected before the default (empty when
    #                      the device selection is left entirely to the default)
    #   $4 override_file - file whose contents are appended after the default (may be
    #                      empty)
    #   $5 uid           - discovery unique_id
    #   $6 source_label  - path shown in the 'appended from' comment (defaults to $4)
    launch_radio() {
        local port="$1" tag="$2" device_line="$3" override_file="$4" uid="$5" source_label="${6:-$4}"
        local live="${render_dir}/${tag}.conf"

        # Build the raw rendered config: optional injected device line + baked-in
        # default + any override file + optional 'output kv'/'output log' lines.
        {
            [ -n "$device_line" ] && echo "$device_line"
            cat "$default_conf"
            if [ "$disable_tpms" = "true" ] && [ -f "$tpms_disables_conf" ]
            then
                echo
                cat "$tpms_disables_conf"
            fi
            if [ -n "$override_file" ] && [ -f "$override_file" ]
            then
                echo
                echo "# --- appended from ${source_label} ---"
                cat "$override_file"
            fi
            if [ "$log_received_messages" = "true" ]
            then
                echo
                echo "output kv"
            fi
            if [ "$log_diagnostic_messages" = "true" ]
            then
                echo
                echo "output log"
            fi
            # Trailing newline so the last line is rendered even if an override file
            # lacks one.
            echo
        } > "${live}.raw"

        # Render the live config by substituting the radio's assigned HTTP port. The
        # canonical placeholder is '{{port}}'; the legacy '${port}' form is also
        # accepted so existing override files keep working. This is a plain literal
        # substitution (not shell expansion), so '$', backticks, and quotes in an
        # override file are left untouched and need no escaping. '$port' is always
        # numeric, so it is safe to inline into the replacement.
        sed -e "s|{{port}}|$port|g" -e "s|[$]{port}|$port|g" "${live}.raw" > "$live"

        echo "Starting rtl_433 with $live..."
        # Run under a per-radio restart loop so this radio failing (e.g. its
        # dongle is busy or unplugged) does not stop the others or the add-on.
        supervise_radio "$tag" "$live" > >(sed -u "s/^/[$tag] /") 2> >(>&2 sed -u "s/^/[$tag] /")&
        rtl_433_pids+=("$!")

        radio_ports+=("$port")
        radio_tags+=("$tag")
        radio_unique_ids+=("$uid")
    }

    if [ "${#rtlsdr_devices[@]}" -eq 0 ]
    then
        bashio::log.warning "No RTL-SDR dongles detected; only explicitly-declared radios (if any) will be launched."
    fi

    for i in "${!rtlsdr_devices[@]}"
    do
        if [ "$i" -ge "$MAX_RADIOS" ]
        then
            bashio::log.warning "More than ${MAX_RADIOS} RTL-SDR dongles detected; the maximum supported is ${MAX_RADIOS}. Skipping the rest."
            break
        fi

        entry="${rtlsdr_devices[$i]}"
        serial="${entry%%$'\t'*}"
        portpath="${entry#*$'\t'}"

        port=$((BASE_PORT + i))

        # Determine the rtl_433 device selector for this dongle: a ':SERIAL' selector
        # when the serial is usable, else the bare enumeration index.
        if _serial_is_usable "$serial"
        then
            selector=":${serial}"
        else
            selector="$i"
        fi

        # Raw, filename-safe identifier used to match an override file.
        match_id="$(radio_match_id "$serial" "$portpath")"
        expected_file="${conf_directory}/${match_id}.conf"
        matched_ids+="${match_id} "

        # Resolve a stable identifier (serial -> USB port path) for discovery. Pass
        # the same selector used above so the resolution matches this enumerated
        # entry.
        unique_id="$(resolve_radio_unique_id "$selector" "$match_id")"

        bashio::log.info "Radio ${match_id} -> HTTP port ${port}. To customize, create ${expected_file}."

        launch_radio "$port" "$match_id" "device ${selector}" "$expected_file" "$unique_id"
    done

# Launch explicitly-declared radios from config-dir files that did not match a
# detected RTL-SDR dongle. Such a file becomes its own radio only when it carries
# its own 'device' line (e.g. a SoapySDR/HackRF device string that cannot be
# auto-detected); otherwise it is an orphan (typo or unplugged dongle) and is
# ignored with a warning. Auto-detected radios were launched first, so these are
# assigned the next free ports.
    for f in "$conf_directory"/*.conf
    do
        # Skip the glob literal when no override files exist.
        [ -e "$f" ] || continue

        base="$(basename "$f" .conf)"

        # Skip files already consumed as an override for a detected radio.
        case "$matched_ids" in
            *" ${base} "*) continue ;;
        esac

        if ! grep -qE '^[[:space:]]*device[[:space:]]' "$f"
        then
            bashio::log.warning "Config file ${f} matches no detected RTL-SDR radio and declares no 'device' line; ignoring it."
            continue
        fi

        if [ "${#radio_ports[@]}" -ge "$MAX_RADIOS" ]
        then
            bashio::log.warning "Maximum of ${MAX_RADIOS} radios reached; skipping explicitly-declared radio ${f}."
            continue
        fi

        # Filename-safe tag, consistent with how detected identifiers are sanitised.
        tag="$(printf '%s' "$base" | tr -c 'A-Za-z0-9:._-' '_')"
        port=$((BASE_PORT + ${#radio_ports[@]}))

        # Pull the 'device' line out so it can be injected before the default's output
        # line (rtl_433 expects 'device' before any 'output'); append the rest of the
        # user's file with its 'device' lines stripped to avoid a duplicate after the
        # output line.
        device_value="$(grep -m1 -E '^[[:space:]]*device[[:space:]]' "$f" | sed -E 's/^[[:space:]]*device[[:space:]]+//')"
        stripped="${render_dir}/${tag}.user"
        grep -vE '^[[:space:]]*device[[:space:]]' "$f" > "$stripped"

        unique_id="$(resolve_radio_unique_id "$device_value" "$tag")"

        bashio::log.info "Explicitly-declared radio ${tag} (device '${device_value}') -> HTTP port ${port}."

        launch_radio "$port" "$tag" "device ${device_value}" "$stripped" "$unique_id" "$f"
    done

    # ---------------------------------------------------------------------------
    # Publish each radio to the Home Assistant Supervisor discovery API.
    #
    # This runs after the radios are launched (so a radio that failed to start is
    # not advertised) but before the blocking 'wait' below. Every step here is
    # best-effort: a failure to publish must never stop the radios from running.
    # ---------------------------------------------------------------------------
    publish_discovery() {
        # The Supervisor token is injected into the add-on environment when
        # 'hassio_api: true' is set in config.json. Without it we cannot reach the
        # Supervisor API (e.g. local/test runs), so log and skip gracefully.
        if [ -z "${SUPERVISOR_TOKEN:-}" ]
        then
            bashio::log.info "SUPERVISOR_TOKEN not set; skipping Supervisor discovery publication."
            return 0
        fi

        # Determine the host Home Assistant should connect to. We use the add-on's
        # Supervisor-assigned hostname rather than a hard-coded IP so the value
        # stays correct across restarts and networks. bashio::addon.hostname wraps
        # the Supervisor '/addons/self/info' endpoint; if that helper is missing or
        # returns nothing we fall back to querying the endpoint directly.
        local host=""
        if bashio::var.has_value "$(bashio::addon.hostname 2>/dev/null)"
        then
            host="$(bashio::addon.hostname)"
        else
            host="$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                "http://supervisor/addons/self/info" \
                | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        fi

        if [ -z "$host" ]
        then
            bashio::log.warning "Could not determine the add-on hostname; skipping Supervisor discovery publication."
            return 0
        fi

        local i port tag uid body response http_code resp_body msg_uuid published_uuid=""
        for i in "${!radio_ports[@]}"
        do
            port="${radio_ports[$i]}"
            tag="${radio_tags[$i]}"
            uid="${radio_unique_ids[$i]}"

            # Build the discovery payload with printf (parsed with sed below, to
            # match how the Supervisor JSON is handled elsewhere here). 'service'
            # MUST equal the discovery entry in config.json ("rtl_433"). The
            # integration connects to ws://<host>:<port>/ws and uses 'unique_id' as
            # a stable per-radio key. host/port are interpolated; the unique_id is
            # pre-sanitised to a JSON-safe character set by resolve_radio_unique_id,
            # so no further JSON escaping is needed.
            printf -v body \
                '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s"}}' \
                "$host" "$port" "$uid"

            # Best-effort POST. Capture the response body and the HTTP status (the
            # latter appended on its own trailing line) so a non-2xx response or a
            # curl failure is logged but never aborts the script. The body carries
            # the message uuid, which we persist so a later run with no radios can
            # delete the message.
            response="$(curl -s -w $'\n%{http_code}' \
                -X POST \
                -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "$body" \
                "http://supervisor/discovery" 2>/dev/null)" || response=$'\n000'
            http_code="${response##*$'\n'}"
            resp_body="${response%$'\n'*}"

            if [[ "$http_code" =~ ^2 ]]
            then
                # All radios share one Supervisor discovery message (equality is
                # add-on + service, so each POST overwrites the same message and
                # returns the same uuid); remember it for cleanup.
                msg_uuid="$(printf '%s' "$resp_body" | sed -n 's/.*"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
                [ -n "$msg_uuid" ] && published_uuid="$msg_uuid"
                bashio::log.info "Published discovery for radio '${tag}' on port ${port} (HTTP ${http_code})."
            else
                # The Supervisor may reject the 'rtl_433' service until the
                # integration registers discovery support. This is expected and
                # non-fatal; the radios keep running regardless.
                bashio::log.warning "Discovery publication for radio '${tag}' on port ${port} returned HTTP ${http_code} (non-fatal; Supervisor may reject the service until the integration supports discovery)."
            fi
        done

        # Persist the discovery message uuid so a later boot with no radios can
        # delete it (see remove_discovery_state). Best-effort: a write failure is
        # logged but never fatal.
        if [ -n "$published_uuid" ]
        then
            printf '%s' "$published_uuid" > "${DATA_DIR}/discovery.uuid" 2>/dev/null \
                || bashio::log.warning "Could not persist discovery uuid to ${DATA_DIR}/discovery.uuid."
        fi
    }

    # Remove a previously-published discovery message when this run has no radios
    # to advertise (e.g. the last/only dongle was unplugged), so Home Assistant
    # stops trying to reach a radio that is no longer present. All radios share a
    # single Supervisor discovery message (keyed by add-on + 'rtl_433' service),
    # so there is at most one uuid to delete, remembered in DATA_DIR by
    # publish_discovery. Best-effort: any failure is logged and ignored.
    remove_discovery_state() {
        if [ -z "${SUPERVISOR_TOKEN:-}" ]
        then
            return 0
        fi

        local state="${DATA_DIR}/discovery.uuid" uuid http_code
        [ -f "$state" ] || return 0
        uuid="$(cat "$state" 2>/dev/null)"
        if [ -z "$uuid" ]
        then
            rm -f "$state"
            return 0
        fi

        http_code="$(curl -s -o /dev/null -w '%{http_code}' \
            -X DELETE \
            -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            "http://supervisor/discovery/${uuid}" 2>/dev/null)" || http_code="000"

        if [[ "$http_code" =~ ^2 ]]
        then
            bashio::log.info "Removed stale rtl_433 discovery message (uuid ${uuid}, HTTP ${http_code}); no radios are running."
        else
            # A 404 just means the message was already gone (e.g. the Supervisor
            # purged it); either way the local state is cleared below.
            bashio::log.warning "Removal of stale discovery uuid ${uuid} returned HTTP ${http_code} (non-fatal)."
        fi
        rm -f "$state"
    }

    # Advertise the running radios, or clean up a leftover discovery message when
    # there are none.
    if [ "${#radio_ports[@]}" -gt 0 ]
    then
        publish_discovery
    else
        remove_discovery_state
    fi

    # Block until shutdown. Each supervisor restarts its own rtl_433, so under
    # normal operation the supervisor PIDs never exit and the add-on stays up; a
    # single failing radio no longer brings the container down. A trap firing
    # during 'wait' makes it return early, so re-wait until shutdown is signalled.
    # With no radios launched there is nothing to supervise, so idle to keep the
    # container alive (and restartable) rather than exiting immediately.
    if [ "${#rtl_433_pids[@]}" -gt 0 ]
    then
        while [ "$shutting_down" != "true" ]
        do
            wait "${rtl_433_pids[@]}"
            if [ "$shutting_down" != "true" ]
            then
                # 'wait' returned without a shutdown signal: every supervisor
                # exited unexpectedly. Idle (kept restartable) rather than
                # busy-looping on already-dead PIDs.
                bashio::log.warning "All radio supervisors exited unexpectedly; idling."
                sleep infinity & wait "$!"
            fi
        done
    else
        bashio::log.info "No radios running; idling."
        while [ "$shutting_down" != "true" ]
        do
            sleep infinity & wait "$!"
        done
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
