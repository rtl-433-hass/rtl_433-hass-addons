#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

conf_directory="/config/rtl_433"

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

if [ ! -d "$conf_directory" ]
then
    mkdir -p "$conf_directory"
fi

# Create a reasonable default configuration in /config/rtl_433.
if [ ! "$(ls -A "$conf_directory")" ]
then
    cat > "$conf_directory"/rtl_433.conf.template <<EOD
# This template configures rtl_433 to expose its decoded events over an HTTP
# server. The Home Assistant integration connects to that server (ws://host:port/ws)
# to receive device data. Each radio runs its own rtl_433 process with its own
# HTTP port.
#
# Create multiple files ending in '.conf.template' to manage multiple rtl_433
# radios. Each template MUST set a distinct 'device' so radios can be told apart,
# for example 'device :SERIAL' or a SoapySDR device string. The 'device' line
# must appear before any output lines.
#
# Radios are sorted by their 'device' value and assigned a stable HTTP port
# starting at ${BASE_PORT} (so the first radio binds ${BASE_PORT}, the second
# ${BASE_PORT}+1, and so on). The \${port} placeholder below is filled in at
# render time with this radio's assigned port.
# https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf

device 0

output http://0.0.0.0:\${port}
report_meta time:iso:usec:tz

# Uncomment the following line to also enable the default "table" output to the
# addon logs.
# output kv

# Disable TPMS sensors by default. These can cause an overwhelming number of
# devices and entities to show up in Home Assistant.
# This list is generated by running:
# rtl_433 -R help 2>&1 | grep -i tpms | sd '.*\[(\d+)\].*' 'protocol -$1'
#    [59]  Steelmate TPMS
#    [60]  Schrader TPMS
#    [82]  Citroen TPMS
#    [88]  Toyota TPMS
#    [89]  Ford TPMS
#    [90]  Renault TPMS
#    [95]  Schrader TPMS EG53MA4, PA66GF35
#    [110]  PMV-107J (Toyota) TPMS
#    [123]* Jansite TPMS Model TY02S
#    [140]  Elantra2012 TPMS
#    [156]  Abarth 124 Spider TPMS
#    [168]  Schrader TPMS SMD3MA4 (Subaru)
#    [180]  Jansite TPMS Model Solar
#    [186]  Hyundai TPMS (VDO)
#    [201]  Unbranded SolarTPMS for trucks
#    [203]  Porsche Boxster/Cayman TPMS
protocol -59
protocol -60
protocol -82
protocol -88
protocol -89
protocol -90
protocol -95
protocol -110
protocol -123
protocol -140
protocol -156
protocol -168
protocol -180
protocol -186
protocol -201
protocol -203
EOD
fi

# Remove all rendered configuration files.
rm -f "$conf_directory"/*.conf

# Build the list of templates, pairing each with its 'device' value so we can
# sort deterministically and assign stable ports.
templates_by_device=()
for template in "$conf_directory"/*.conf.template
do
    # Skip the glob literal if no templates exist.
    [ -e "$template" ] || continue

    # Extract the device value from the first 'device ' line in the template.
    device=$(grep -m1 '^[[:space:]]*device[[:space:]]' "$template" | sed -E 's/^[[:space:]]*device[[:space:]]+//')
    if [ -z "$device" ]
    then
        bashio::log.warning "Template $template has no 'device' line; defaulting to an empty device value."
    fi

    # Prefix with the device value (tab-separated) so we can sort on it.
    templates_by_device+=("${device}"$'\t'"${template}")
done

# Sort templates by device value for a deterministic, stable ordering.
mapfile -t sorted_templates < <(printf '%s\n' "${templates_by_device[@]}" | sort)

# Enumerate RTL-SDR dongles once so each radio's identifier can be resolved from
# real hardware (serial / USB port path) rather than the unstable device index.
mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)

# Parallel arrays describing each launched radio. These are populated during port
# assignment/launch and consumed by the Supervisor discovery step below, which
# iterates them to publish one Home Assistant discovery message per radio.
radio_ports=()
radio_tags=()
radio_unique_ids=()

rtl_433_pids=()
index=0
for entry in "${sorted_templates[@]}"
do
    # Split the "device<TAB>template" entry back into its parts.
    device="${entry%%$'\t'*}"
    template="${entry#*$'\t'}"

    if [ "$index" -ge "$MAX_RADIOS" ]
    then
        bashio::log.warning "More than ${MAX_RADIOS} radio templates found; the maximum supported is ${MAX_RADIOS}. Skipping $template."
        index=$((index + 1))
        continue
    fi

    # Assign a stable port based on the sorted position of this radio.
    # 'port' is referenced by the heredoc template via ${port}.
    # shellcheck disable=SC2034
    port=$((BASE_PORT + index))

    # Remove '.template' from the file name.
    live=$(basename "$template" .template)
    tag=$(basename "$live" .conf)

    # Resolve a stable identifier (serial -> USB port path -> template tag) to
    # advertise so Home Assistant can keep a stable config entry per radio.
    unique_id="$(resolve_radio_unique_id "$device" "$tag")"

    radio_ports+=("$port")
    radio_tags+=("$tag")
    radio_unique_ids+=("$unique_id")

    bashio::log.info "Radio '${device:-<none>}' (template $tag) assigned HTTP port ${port} (unique_id ${unique_id})."

    # By sourcing the template, we can substitute any environment variable in
    # the template. In fact, enterprising users could write _any_ valid bash
    # to create the final configuration file. To simplify template creation,
    # we wrap the needed redirections into a temporary file.
    {
        echo "cat <<EOD > $live"
        cat "$template"
        # Ensure a newline exists in case the template doesn't have one at the end
        # of its file.
        echo
        echo EOD
    } > /tmp/rtl_433_heredoc

    # shellcheck source=/dev/null
    source /tmp/rtl_433_heredoc

    echo "Starting rtl_433 with $live..."
    rtl_433 -c "$live" > >(sed -u "s/^/[$tag] /") 2> >(>&2 sed -u "s/^/[$tag] /")&
    rtl_433_pids+=($!)

    index=$((index + 1))
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

wait -n "${rtl_433_pids[@]}"
