#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# Add-on config directory (the 'addon_config' mount). Read-only for optional
# per-radio '<identifier>.conf' override files; the add-on never writes here.
conf_directory="/config"

# Internal default rtl_433 configuration baked into the image. Rendered configs
# are built from this default plus an injected 'device' line and any matching
# per-radio override file.
default_conf="/etc/rtl_433/rtl_433.defaults.conf"

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

# Base sysfs path for USB device enumeration. Overridable so the enumeration can
# be exercised against a mock tree in tests.
SYSFS_USB_BASE="${SYSFS_USB_BASE:-/sys/bus/usb/devices}"

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

# Read the "Log received messages" add-on option. When true, 'output kv' is
# appended to every radio's rendered config so decoded events show in the log.
log_received_messages="false"
if bashio::config.true 'log_received_messages'
then
    log_received_messages="true"
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

if [ "${#rtlsdr_devices[@]}" -eq 0 ]
then
    bashio::log.warning "No RTL-SDR dongles detected; no rtl_433 process will be launched."
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

    # 'port' is referenced by the rendered heredoc via ${port}.
    # shellcheck disable=SC2034
    port=$((BASE_PORT + i))

    # Determine the rtl_433 device selector for this dongle: a ':SERIAL' selector
    # when the serial is usable, else the bare enumeration index.
    if _serial_is_usable "$serial"
    then
        selector=":${serial}"
    else
        selector="$i"
    fi
    device_line="device ${selector}"

    # Raw, filename-safe identifier used to match an override file.
    match_id="$(radio_match_id "$serial" "$portpath")"
    expected_file="${conf_directory}/${match_id}.conf"

    # Resolve a stable identifier (serial -> USB port path) for discovery. Pass
    # the same selector used above so the resolution matches this enumerated
    # entry.
    unique_id="$(resolve_radio_unique_id "$selector" "$match_id")"

    radio_ports+=("$port")
    radio_tags+=("$match_id")
    radio_unique_ids+=("$unique_id")
    matched_ids+="${match_id} "

    bashio::log.info "Radio ${match_id} -> HTTP port ${port}. To customize, create ${expected_file}."

    live="${render_dir}/${match_id}.conf"

    # Build the raw rendered config: injected device line + baked-in default +
    # any matching override file + an optional 'output kv' for the log option.
    {
        echo "$device_line"
        cat "$default_conf"
        if [ -f "$expected_file" ]
        then
            echo
            echo "# --- appended from ${expected_file} ---"
            cat "$expected_file"
        fi
        if [ "$log_received_messages" = "true" ]
        then
            echo
            echo "output kv"
        fi
    } > "${live}.raw"

    # Substitute ${port} (and allow advanced shell escapes) by sourcing the raw
    # config wrapped in a heredoc. 'port' is in scope and expands here.
    {
        echo "cat <<EOD > $live"
        cat "${live}.raw"
        # Ensure a trailing newline even if the override file lacks one.
        echo
        echo EOD
    } > /tmp/rtl_433_heredoc

    # shellcheck source=/dev/null
    source /tmp/rtl_433_heredoc

    echo "Starting rtl_433 with $live..."
    rtl_433 -c "$live" > >(sed -u "s/^/[$match_id] /") 2> >(>&2 sed -u "s/^/[$match_id] /")&
    rtl_433_pids+=($!)
done

# Warn about override files that match no detected radio so a typo or unplugged
# dongle does not silently do nothing.
for f in "$conf_directory"/*.conf
do
    # Skip the glob literal when no override files exist.
    [ -e "$f" ] || continue
    base="$(basename "$f" .conf)"
    case "$matched_ids" in
        *" ${base} "*) ;;
        *) bashio::log.warning "Override file ${f} matches no detected RTL-SDR radio; ignoring it." ;;
    esac
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

    local i port tag uid body http_code
    for i in "${!radio_ports[@]}"
    do
        port="${radio_ports[$i]}"
        tag="${radio_tags[$i]}"
        uid="${radio_unique_ids[$i]}"

        # Build the discovery payload with printf (jq is not in the runtime
        # image). 'service' MUST equal the discovery entry in config.json
        # ("rtl_433"). The integration connects to ws://<host>:<port>/ws and uses
        # 'unique_id' as a stable per-radio key. host/port are interpolated; the
        # unique_id is pre-sanitised to a JSON-safe character set by
        # resolve_radio_unique_id, so no further JSON escaping is needed.
        printf -v body \
            '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s"}}' \
            "$host" "$port" "$uid"

        # Best-effort POST. Capture the HTTP status separately from the body so
        # a non-2xx response or a curl failure is logged but never aborts the
        # script. -o /dev/null discards the response body.
        http_code="$(curl -s -o /dev/null -w '%{http_code}' \
            -X POST \
            -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$body" \
            "http://supervisor/discovery" 2>/dev/null)" || http_code="000"

        if [[ "$http_code" =~ ^2 ]]
        then
            bashio::log.info "Published discovery for radio '${tag}' on port ${port} (HTTP ${http_code})."
        else
            # The Supervisor may reject the 'rtl_433' service until the
            # integration registers discovery support. This is expected and
            # non-fatal; the radios keep running regardless.
            bashio::log.warning "Discovery publication for radio '${tag}' on port ${port} returned HTTP ${http_code} (non-fatal; Supervisor may reject the service until the integration supports discovery)."
        fi
    done
}

publish_discovery

# Block on the radios. With no radios launched there is nothing to wait on, so
# sleep indefinitely to keep the add-on container alive (and restartable) rather
# than exiting immediately.
if [ "${#rtl_433_pids[@]}" -gt 0 ]
then
    wait -n "${rtl_433_pids[@]}"
else
    bashio::log.info "No radios running; idling."
    sleep infinity
fi
