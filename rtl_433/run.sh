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

# How long to sample a dongle with 'rtl_test -p' when auto-measuring its PPM
# crystal offset. rtl_test refines a cumulative PPM estimate over time, so a
# longer window is more accurate; ~3 minutes is a good one-off balance. The
# result is cached (see ppm_cache_dir) and reused on later boots.
PPM_CALIBRATION_SECONDS=180

# Where measured per-radio PPM offsets are cached, one '<id>.ppm' file per radio.
# This lives in the user-visible add-on config directory (next to each radio's
# '<id>.conf' override), NOT the private '/data' volume, so the slow rtl_test
# sampling runs once and is reused across restarts AND the user can delete the
# file to force a re-measurement (or remove it and turn the option off to return
# to defaults).
ppm_cache_dir="$conf_directory"

# Noise-floor scan geometry. Each configured band is a center frequency that is
# swept +/- NOISE_WINDOW_HZ (so a 2 MHz-wide window) in NOISE_BIN_HZ-wide FFT
# bins by 'rtl_power'. A single one-shot sweep ('rtl_power -i 1 -1') is enough to
# characterise the ambient floor; the scan is best-effort and never blocks launch
# for long, so a wide-but-coarse window is the right trade-off.
NOISE_WINDOW_HZ=1000000
NOISE_BIN_HZ=10000

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

# Emit librtlsdr's device-enumeration banner (stdout+stderr merged). Factored out
# as a one-liner so tests can stub the hardware call. Both rtl_eeprom and rtl_test
# print a banner like:
#     Found 2 device(s):
#       0:  Realtek, RTL2838UHIDIR, SN: 00000001
#       1:  Realtek, RTL2832U, SN: deadbeef
# rtl_eeprom prints it for ALL devices and then exits after reading device 0 (no
# sampling loop), so it is the cheap lister; the timeout only guards a wedged read
# and never truncates the banner, which is flushed before device 0 is opened.
list_rtlsdr_banner() {
    timeout 15 rtl_eeprom 2>&1
}

# Read one dongle's USB serial by opening it through its librtlsdr index. Some
# librtlsdr builds list devices in the enumeration banner WITHOUT a serial (just
# "  0:  Generic RTL2832U OEM"); the serial only appears once the device is
# opened, in rtl_eeprom's 'Current configuration' dump as a 'Serial number:'
# line. Opening by '-d <index>' resolves the index through the SAME librtlsdr
# path the EEPROM write uses, so the serial read here and the serial written by
# the flasher target the same dongle. Prints the serial (empty if none); the
# timeout guards a wedged read and a non-zero exit is tolerated. Args: <index>.
read_rtlsdr_serial_by_index() {
    timeout 15 rtl_eeprom -d "$1" 2>&1 \
        | sed -n 's/^Serial number:[[:space:]]*\([^[:space:]]*\).*/\1/p' \
        | head -n 1
}

# Print librtlsdr's OWN device enumeration, one "index<TAB>serial" line per
# device, in the exact order that 'rtl_eeprom -d <index>' / 'rtl_test -d <index>'
# resolve. librtlsdr derives this index from libusb's device list, which is NOT
# guaranteed to match enumerate_rtlsdr_devices' port-path sort. Any pass that
# writes by '-d <index>' (the EEPROM flasher) MUST use this ordering so the index
# it writes is the same dongle whose serial it inspected. A blank serial (no USB
# serial descriptor) is preserved as an empty field.
enumerate_rtlsdr_by_index() {
    local line idx
    while IFS= read -r line
    do
        # Banner rows look like "  0:  Realtek, RTL2838UHIDIR, SN: 00000001".
        if [[ "$line" =~ ^[[:space:]]*([0-9]+):.*SN:[[:space:]]*([^[:space:],]*) ]]
        then
            printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        # Other builds omit the serial from the banner ("  0:  Generic RTL2832U
        # OEM"); fall back to opening the device to read its serial directly.
        elif [[ "$line" =~ ^[[:space:]]*([0-9]+): ]]
        then
            idx="${BASH_REMATCH[1]}"
            printf '%s\t%s\n' "$idx" "$(read_rtlsdr_serial_by_index "$idx")"
        fi
    done < <(list_rtlsdr_banner)
}

# Best-effort: print the sysfs port path of the connected dongle carrying the
# given serial, but ONLY when exactly one dongle has it. Factory-default/empty
# serials are shared by multiple dongles (or unset), so they resolve to nothing —
# the flasher then logs by librtlsdr index alone. Reads the 'rtlsdr_devices'
# array. Args: <serial>.
_portpath_for_serial() {
    local serial="$1" entry s count=0 found=""
    [ -n "$serial" ] || return 0
    for entry in "${rtlsdr_devices[@]}"
    do
        s="${entry%%$'\t'*}"
        if [ "$s" = "$serial" ]
        then
            count=$((count + 1))
            found="${entry#*$'\t'}"
        fi
    done
    [ "$count" -eq 1 ] && printf '%s' "$found"
    return 0
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

# Decide whether a USB serial is a factory-default placeholder that the
# randomize_default_serial option should replace. This is intentionally
# narrower than _serial_is_usable: it matches only the empty/missing serial and
# the two well-known factory defaults, not every technically-unusable value.
# Args: <serial>.
_serial_is_default() {
    local serial="$1"
    case "$serial" in
        ""|00000000|00000001) return 0 ;;
    esac
    return 1
}

# Print a random 8-character lowercase-hex serial drawn from the kernel entropy
# source. Used to give a factory-default dongle a unique identity. The caller is
# responsible for rejecting a value that collides with an existing/just-assigned
# serial (see the flashing pass in main()).
generate_random_serial() {
    od -An -N4 -tx1 /dev/urandom | tr -dc '0-9a-f'
}

# One-time maintenance pass for the 'randomize_default_serial' option: give every
# factory-default dongle a unique random serial via 'rtl_eeprom -d <index>'.
#
# CRITICAL: the loop is driven by enumerate_rtlsdr_by_index (librtlsdr's own
# index order), NOT the sysfs 'rtlsdr_devices' array (port-path order). The two
# orderings can disagree, and 'rtl_eeprom -d <index>' resolves the index through
# librtlsdr — so iterating the sysfs array and passing its array index as '-d'
# would inspect one dongle's serial but write to whichever dongle librtlsdr calls
# that index, flashing the wrong radio. Reading the index and serial from the
# same enumeration that the write targets keeps them in lock-step.
#
# Reads the 'rtlsdr_devices' array only to (a) seed the set of serials to avoid
# and (b) resolve a port path for the log line. Prints the number of dongles
# flashed to stdout; all human-facing messages go through bashio (stderr).
flash_default_serials() {
    local existing_serials=" " entry idx serial portpath new_serial cand
    local flashed_count=0

    # Serials already present on a connected dongle, plus any picked earlier in
    # this same pass, so a freshly generated serial can never collide.
    for entry in "${rtlsdr_devices[@]}"
    do
        existing_serials+="${entry%%$'\t'*} "
    done

    while IFS=$'\t' read -r idx serial
    do
        [ -n "$idx" ] || continue
        [ "$idx" -ge "$MAX_RADIOS" ] && continue
        # Only touch dongles that still carry a factory-default serial; a dongle
        # with a real serial is left alone.
        _serial_is_default "$serial" || continue

        portpath="$(_portpath_for_serial "$serial")"

        # Pick a random serial not already present or assigned this pass.
        new_serial=""
        for _ in 1 2 3 4 5
        do
            cand="$(generate_random_serial)"
            case "$existing_serials" in
                *" ${cand} "*) continue ;;
            esac
            new_serial="$cand"
            break
        done
        if [ -z "$new_serial" ]
        then
            bashio::log.warning "Radio at index ${idx}${portpath:+ (${portpath})}: could not generate a unique serial; leaving its default serial unchanged."
            continue
        fi

        bashio::log.info "Radio at index ${idx}${portpath:+ (${portpath})}: writing random serial ${new_serial} to EEPROM (was default '${serial}')."
        # rtl_eeprom prompts for confirmation; auto-answer 'y' and bound the call
        # so a stuck write cannot hang startup. A non-zero exit is tolerated.
        if printf 'y\n' | timeout 30 rtl_eeprom -d "$idx" -s "$new_serial" >/dev/null 2>&1
        then
            existing_serials+="${new_serial} "
            flashed_count=$((flashed_count + 1))
        else
            bashio::log.warning "Radio at index ${idx}: rtl_eeprom failed to write serial ${new_serial} (non-fatal)."
        fi
    done < <(enumerate_rtlsdr_by_index)

    printf '%s' "$flashed_count"
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

# Extract the discovery message uuid from a Supervisor 'POST /discovery' response
# body. Prints the uuid (empty if absent). Pure string parsing with sed, matching
# how the rest of this script reads Supervisor JSON. Args: <response_body>.
parse_discovery_uuid() {
    printf '%s' "$1" | sed -n 's/.*"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Persist the Supervisor discovery message uuid under DATA_DIR so a later run with
# no radios can delete it (see remove_discovery_state). No-op for an empty uuid.
# Best-effort: a write failure is logged, never fatal. Args: <uuid>.
save_discovery_uuid() {
    local uuid="$1"
    [ -n "$uuid" ] || return 0
    printf '%s' "$uuid" > "${DATA_DIR}/discovery.uuid" 2>/dev/null \
        || bashio::log.warning "Could not persist discovery uuid to ${DATA_DIR}/discovery.uuid."
}

# Remove a previously-published discovery message when a run has no radios to
# advertise (e.g. the last/only dongle was unplugged), so Home Assistant stops
# trying to reach a radio that is no longer present. All radios share a single
# Supervisor discovery message (keyed by add-on + 'rtl_433' service), so there is
# at most one uuid to delete, remembered in DATA_DIR by save_discovery_uuid.
# Best-effort: any failure is logged and ignored. Needs SUPERVISOR_TOKEN; without
# it (e.g. local/test runs) it is a no-op.
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

# Extract the auto-measured PPM crystal offset from captured 'rtl_test -p' output.
# rtl_test prints a refining 'cumulative PPM: <n>' line periodically; the LAST one
# is its best estimate. Prints just that integer (which may be negative); prints
# nothing if no such line is present. Pure string parsing. Args: <captured_text>.
parse_rtl_test_ppm() {
    printf '%s' "$1" \
        | sed -n 's/.*cumulative PPM:[[:space:]]*\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' \
        | tail -n 1
}

# Path of the cache file holding one radio's measured PPM offset. Args: <id>.
ppm_cache_path() {
    printf '%s' "${ppm_cache_dir}/$1.ppm"
}

# Print a radio's cached PPM offset if one is stored and valid. The cache file's
# first line is the (optionally signed) integer; a following '# measured <date>'
# comment line (written by write_ppm_cache) is ignored. Returns non-zero with no
# output when the file is missing or its first line is not a valid integer.
# Args: <id>.
read_ppm_cache() {
    local file value
    file="$(ppm_cache_path "$1")"
    [ -f "$file" ] || return 1
    # Only the first line carries the value; the rest is a human-readable comment.
    value="$(sed -n '1p' "$file" 2>/dev/null)"
    [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
    printf '%s' "$value"
}

# Persist a radio's measured PPM offset under ppm_cache_dir so it is reused on
# later boots. The integer is written on the first line, with a '# measured
# <date>' comment on the second so the cache is self-documenting (read_ppm_cache
# reads only the first line). Best-effort: a write failure is warned, not fatal.
# Args: <id> <ppm>.
write_ppm_cache() {
    local id="$1" ppm="$2" file
    file="$(ppm_cache_path "$id")"
    mkdir -p "$ppm_cache_dir" 2>/dev/null
    {
        printf '%s\n' "$ppm"
        printf '# measured %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$file" 2>/dev/null \
        || bashio::log.warning "Could not persist measured PPM offset to ${file}."
}

# Return 0 if an override file exists and already declares a 'ppm_error'
# directive, so auto-measurement can defer to a user-set value. Mirrors the
# 'device' line detection used in main(). Args: <override_file>.
override_has_ppm_error() {
    local file="$1"
    [ -n "$file" ] && [ -f "$file" ] || return 1
    grep -qE '^[[:space:]]*ppm_error[[:space:]]' "$file"
}

# Parse the 'noise_floor_bands' option (a comma-separated list of center
# frequencies) into 'rtl_power' sweep ranges. Each entry is a center frequency in
# either an 'M'-suffixed MHz form ('433.92M', '868M') or plain Hz ('915000000').
# For every valid entry one 'lo:hi:bin' triple is printed, with
# lo=center-NOISE_WINDOW_HZ, hi=center+NOISE_WINDOW_HZ, bin=NOISE_BIN_HZ. Decimal
# MHz are handled (433.92M -> 433920000) so the arithmetic stays integer Hz.
# Malformed entries are skipped (with a warning). Pure: no external tools beyond
# awk, which is deterministic. Args: <csv_string>.
parse_noise_bands() {
    local csv="$1" entry center
    local IFS=','
    for entry in $csv
    do
        # Trim surrounding whitespace.
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [ -n "$entry" ] || continue
        center=""
        case "$entry" in
            # 'M'-suffixed MHz, optionally with a single decimal point. Scale to
            # Hz with awk so a fractional MHz (e.g. 433.92M) lands on an integer.
            *[Mm])
                if [[ "${entry%[Mm]}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
                then
                    center="$(awk -v v="${entry%[Mm]}" 'BEGIN { printf "%d", v * 1000000 }')"
                fi
                ;;
            # Plain integer Hz.
            *)
                if [[ "$entry" =~ ^[0-9]+$ ]]
                then
                    center="$entry"
                fi
                ;;
        esac
        if [ -z "$center" ] || [ "$center" -le 0 ] 2>/dev/null
        then
            bashio::log.warning "Ignoring malformed noise_floor_bands entry '${entry}'."
            continue
        fi
        printf '%s:%s:%s\n' "$((center - NOISE_WINDOW_HZ))" "$((center + NOISE_WINDOW_HZ))" "$NOISE_BIN_HZ"
    done
}

# Compute the ambient noise statistics from an 'rtl_power' CSV. rtl_power rows are
# 'date,time,Hz_low,Hz_high,Hz_step,samples,dB,dB,...' so the power readings are
# fields 7..NF. All dB values across all rows are collected and 'min median peak'
# (in dBm) is printed. Prints nothing and returns non-zero when the file has no
# usable readings. Uses awk (sort for the median). Args: <csv_file>.
rtl_power_stats() {
    local file="$1"
    [ -f "$file" ] || return 1
    awk -F',' '
        {
            for (i = 7; i <= NF; i++) {
                v = $i + 0
                # Skip empty/non-numeric trailing fields.
                if ($i ~ /^[[:space:]]*-?[0-9]+(\.[0-9]+)?[[:space:]]*$/) {
                    vals[n++] = v
                }
            }
        }
        END {
            if (n == 0) { exit 1 }
            # Insertion sort (small datasets; avoids a non-portable asort).
            for (i = 1; i < n; i++) {
                key = vals[i]
                j = i - 1
                while (j >= 0 && vals[j] > key) { vals[j + 1] = vals[j]; j-- }
                vals[j + 1] = key
            }
            min = vals[0]
            peak = vals[n - 1]
            if (n % 2) { median = vals[(n - 1) / 2] }
            else { median = (vals[n / 2 - 1] + vals[n / 2]) / 2 }
            printf "%g %g %g\n", min, median, peak
        }
    ' "$file"
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

    # Read the "Correct PPM offset" add-on option (default off). When true, each
    # detected radio's crystal PPM offset is measured once with rtl_test, cached
    # as '<id>.ppm' in the add-on config directory, and injected as a 'ppm_error'
    # directive into its rendered config (unless an override already sets
    # ppm_error). When false, none of the PPM code runs and the rendered
    # config/logs are unchanged.
    correct_ppm_offset="false"
    if bashio::config.true 'correct_ppm_offset'
    then
        correct_ppm_offset="true"
    fi

    # Read the "Detect noise floor" add-on option (default off). When true, each
    # detected radio is swept once with rtl_power across 'noise_floor_bands' before
    # its rtl_433 launches, writing a timestamped CSV/TXT/PNG report into the
    # add-on config directory and logging a per-band summary. Purely diagnostic and
    # best-effort: it never changes the rendered config and never blocks launch on
    # failure. When false, none of the noise-floor code runs.
    detect_noise_floor="false"
    if bashio::config.true 'detect_noise_floor'
    then
        detect_noise_floor="true"
    fi

    # Read the "Randomize default serial" add-on option (default off). When true,
    # every detected dongle still carrying a factory-default serial is flashed
    # with a unique random serial via rtl_eeprom before any process claims it,
    # then the dongles are re-enumerated once. When false, none of this runs.
    randomize_default_serial="false"
    if bashio::config.true 'randomize_default_serial'
    then
        randomize_default_serial="true"
    fi

    # Center frequencies swept when detect_noise_floor is on (see parse_noise_bands
    # for the accepted forms). Falls back to the common ISM bands when unset/empty.
    noise_floor_bands="$(bashio::config 'noise_floor_bands')"
    if [ -z "$noise_floor_bands" ] || [ "$noise_floor_bands" = "null" ]
    then
        noise_floor_bands="433.92M,868M,915M"
    fi

    # Seconds rtl_power samples each band when detect_noise_floor is on. A longer
    # window accumulates more sweeps so the min/median/peak reflect time-varying
    # (intermittent) interference rather than a single instant. Each band is swept
    # serially per radio, so the per-radio cost is roughly this times the number
    # of bands. Falls back to the default when unset/non-numeric/out of range.
    noise_floor_duration="$(bashio::config 'noise_floor_duration')"
    if ! [[ "$noise_floor_duration" =~ ^[0-9]+$ ]] || [ "$noise_floor_duration" -lt 1 ] || [ "$noise_floor_duration" -gt 600 ]
    then
        noise_floor_duration=30
    fi

    # Directory rendered configs are written to. Never the user config directory.
    mkdir -p "$render_dir"

    # Enumerate RTL-SDR dongles once so each radio's identifier can be resolved from
    # real hardware (serial / USB port path) rather than the unstable device index.
    mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)

    # When 'randomize_default_serial' is on, run a one-time MAINTENANCE pass and
    # then halt without launching any radios. Rationale: rtl_eeprom writes the new
    # serial to the dongle's EEPROM but does NOT reset the device, and the RTL2832U
    # only re-reads its serial at USB power-on — so a freshly written serial can
    # only be applied by a physical unplug/replug (or hub power-cycle), never by a
    # re-enumeration from inside the container. Rather than guess or churn the
    # EEPROM on every boot, we flash every default-serial dongle once, print clear
    # instructions, and block: the user turns the option back off, stops the
    # add-on, replugs the dongle(s), and starts again. Because we block instead of
    # exiting, a watchdog cannot restart-loop us into re-flashing.
    if [ "$randomize_default_serial" = "true" ]
    then
        flashed_count=0
        if ! command -v rtl_eeprom >/dev/null 2>&1
        then
            bashio::log.warning "randomize_default_serial is on but rtl_eeprom is not available; no serials can be written."
        else
            flashed_count="$(flash_default_serials)"
        fi

        bashio::log.info "============================================================"
        bashio::log.info "randomize_default_serial is ON — one-time maintenance mode."
        if [ "$flashed_count" -gt 0 ]
        then
            bashio::log.info "Wrote a new random serial to ${flashed_count} dongle(s)."
        else
            bashio::log.info "No factory-default dongles found; no serials written."
        fi
        bashio::log.info "rtl_433 will NOT start while this option is on. To finish:"
        bashio::log.info "  1. Turn OFF 'Randomize default serial' in the add-on options."
        bashio::log.info "  2. Stop the add-on."
        bashio::log.info "  3. Unplug and replug the RTL-SDR dongle(s) (or power-cycle the hub)."
        bashio::log.info "  4. Start the add-on again."
        bashio::log.info "============================================================"

        # Block (do not launch radios, do not exit). The user stops the add-on per
        # the message above; SIGTERM then exits cleanly.
        trap 'exit 0' TERM INT
        while true
        do
            sleep 3600 & wait "$!"
        done
    fi

    # Normal operation (option off): surface any factory-default serials so the
    # user knows identical dongles are indistinguishable (the add-on falls back to
    # USB-port-path identity for them) and can run the one-time randomize step.
    for entry in "${rtlsdr_devices[@]}"
    do
        serial="${entry%%$'\t'*}"
        portpath="${entry#*$'\t'}"
        if _serial_is_default "$serial"
        then
            bashio::log.warning "Radio at ${portpath} has a factory-default serial ('${serial:-empty}'); multiple such dongles cannot be told apart. Enable 'Randomize default serial' once to assign it a unique serial (writes the EEPROM, then requires a physical replug)."
        fi
    done

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
    #   $7 ppm           - measured PPM offset to inject as 'ppm_error' (empty for none)
    launch_radio() {
        local port="$1" tag="$2" device_line="$3" override_file="$4" uid="$5" source_label="${6:-$4}" ppm="${7:-}"
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
            if [ -n "$ppm" ]
            then
                echo
                echo "ppm_error $ppm"
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

    # Measure one radio's PPM crystal offset with rtl_test and cache it under
    # '<id>.ppm', unless a value is already available (a manual 'ppm_error' in the
    # override, or a measurement cached on a previous boot). Prints nothing — it
    # only populates the cache, which resolve_ppm_for_radio reads later. 'rtl_test
    # -p' samples its own dongle (selected by -d) against the host clock, so this
    # is safe to run concurrently for different radios: each samples a distinct
    # device and writes a distinct cache file. rtl_test -p runs until interrupted,
    # so 'timeout' bounds it (a non-zero exit on expiry is expected; the captured
    # output still holds the cumulative PPM estimate). A missing/unparseable
    # measurement is non-fatal. Args: <rtl_test_selector> <id> <override_file>.
    measure_ppm_to_cache() {
        local sel="$1" id="$2" override_file="$3" ppm out
        # A user-set ppm_error in the override takes precedence; never measure.
        if override_has_ppm_error "$override_file"
        then
            return 0
        fi
        # Reuse a previously-measured value so the slow sampling runs only once.
        if read_ppm_cache "$id" >/dev/null
        then
            return 0
        fi
        bashio::log.info "Radio ${id}: measuring PPM offset with rtl_test for up to ${PPM_CALIBRATION_SECONDS}s (cached for next boot)..."
        out="$(timeout "${PPM_CALIBRATION_SECONDS}" rtl_test -d "$sel" -p 2>&1)"
        ppm="$(parse_rtl_test_ppm "$out")"
        if [ -z "$ppm" ]
        then
            bashio::log.warning "Radio ${id}: could not measure a PPM offset (no cumulative PPM in rtl_test output); launching without correction."
            return 0
        fi
        write_ppm_cache "$id" "$ppm"
        bashio::log.info "Radio ${id}: PPM offset ${ppm} (measured)."
    }

    # Resolve the PPM offset to inject for one detected radio, honouring the
    # decision order: a manual 'ppm_error' in the override wins (inject nothing so
    # rtl_433 uses the override's own value), else the measurement cached by the
    # parallel measure_ppm_to_cache pass is injected. Prints the integer to inject
    # (empty for "none"). Measurement is NOT performed here: it runs concurrently
    # for every radio up front (see the measurement pre-pass below) so the launch
    # loop never blocks on it. Args: <id> <override_file>.
    resolve_ppm_for_radio() {
        local id="$1" override_file="$2" ppm
        # A user-set ppm_error in the override takes precedence; leave it alone.
        if override_has_ppm_error "$override_file"
        then
            bashio::log.info "Radio ${id}: manual ppm_error present in override; skipping auto PPM measurement."
            return 0
        fi
        # Inject the value measured by the pre-pass (or cached on a previous boot).
        if ppm="$(read_ppm_cache "$id")"
        then
            bashio::log.info "Radio ${id}: PPM offset ${ppm} (cached)."
            printf '%s' "$ppm"
            return 0
        fi
        # No cached value: the measurement pass found nothing usable (and already
        # warned). Launch without correction.
        return 0
    }

    # Render the accumulated noise-floor CSV for one radio into a PNG spectrum plot
    # via gnuplot. The rtl_power CSV packs each sweep row as
    # 'date,time,Hz_low,Hz_high,Hz_step,samples,dB,...', so awk flattens it into
    # 'freq_hz dB' pairs (bin i sits at Hz_low + i*Hz_step) before plotting.
    # Best-effort: any awk/gnuplot failure (or a missing binary) is warned and
    # skipped. Args: <csv_file> <png_file>.
    render_noise_png() {
        local csv="$1" png="$2" dat
        command -v gnuplot >/dev/null 2>&1 || {
            bashio::log.warning "gnuplot not available; skipping noise-floor PNG ${png}."
            return 0
        }
        dat="$(mktemp 2>/dev/null)" || return 0
        if ! awk -F',' '
            {
                lo = $3 + 0; step = $5 + 0
                for (i = 7; i <= NF; i++) {
                    if ($i ~ /^[[:space:]]*-?[0-9]+(\.[0-9]+)?[[:space:]]*$/) {
                        printf "%d %g\n", lo + (i - 7) * step, $i + 0
                    }
                }
            }
        ' "$csv" > "$dat" 2>/dev/null
        then
            rm -f "$dat"
            bashio::log.warning "Could not flatten noise-floor CSV for ${png}; skipping plot."
            return 0
        fi
        if ! gnuplot -e "set terminal png; set output '${png}'; set xlabel 'Hz'; set ylabel 'dBm'; plot '${dat}' with lines" 2>/dev/null
        then
            bashio::log.warning "gnuplot failed to render noise-floor PNG ${png} (non-fatal)."
        fi
        rm -f "$dat"
    }

    # Sweep one radio's configured noise-floor bands with rtl_power while the
    # dongle is still free, writing a timestamped CSV (raw sweeps), TXT (per-band
    # min/median/peak) and PNG (spectrum) into conf_directory and logging a
    # one-line summary per band. The rtl-sdr tools take a BARE serial for '-d'
    # (unlike rtl_433's ':serial'), so the caller passes a serial-or-index
    # selector. Every step is best-effort: a tool failure, empty CSV, or write
    # error is warned and the radio still launches. Args: <selector> <id>.
    scan_noise_for_radio() {
        local sel="$1" id="$2" ts lo_hi_bin tmp stats min median peak label
        local -a bands
        ts="$(date +%Y%m%d-%H%M%S)"
        local csv="${conf_directory}/noise-${id}-${ts}.csv"
        local txt="${conf_directory}/noise-${id}-${ts}.txt"
        local png="${conf_directory}/noise-${id}-${ts}.png"

        mapfile -t bands < <(parse_noise_bands "$noise_floor_bands")
        if [ "${#bands[@]}" -eq 0 ]
        then
            bashio::log.warning "Radio ${id}: no valid noise_floor_bands to scan; skipping noise-floor detection."
            return 0
        fi

        bashio::log.info "Radio ${id}: measuring noise floor over ${#bands[@]} band(s) at ${noise_floor_duration}s each (startup paused)..."
        for lo_hi_bin in "${bands[@]}"
        do
            tmp="$(mktemp 2>/dev/null)" || continue
            # Sample the band for noise_floor_duration seconds in 1-second sweeps so
            # the accumulated rows capture time-varying interference (not a single
            # instant). 'timeout' bounds a hung rtl_power with a margin for device
            # setup/teardown. A non-zero exit or empty capture is tolerated (the
            # radio must still launch).
            if ! timeout "$((noise_floor_duration + 15))" rtl_power -d "$sel" -f "$lo_hi_bin" -i 1 -e "$noise_floor_duration" "$tmp" >/dev/null 2>&1
            then
                bashio::log.warning "Radio ${id}: rtl_power sweep of ${lo_hi_bin} failed (non-fatal)."
            fi
            if [ ! -s "$tmp" ]
            then
                bashio::log.warning "Radio ${id}: noise-floor sweep of ${lo_hi_bin} produced no data; skipping band."
                rm -f "$tmp"
                continue
            fi
            # Accumulate the raw sweeps so the CSV/PNG cover every band.
            cat "$tmp" >> "$csv" 2>/dev/null \
                || bashio::log.warning "Radio ${id}: could not write ${csv} (non-fatal)."
            # A human-friendly label is the band's center in MHz.
            label="$(awk -F':' 'BEGIN { } { printf "%g MHz", (($1 + $2) / 2) / 1000000 }' <<<"$lo_hi_bin")"
            if stats="$(rtl_power_stats "$tmp")"
            then
                read -r min median peak <<<"$stats"
                printf '%s: min %s dBm, median %s dBm, peak %s dBm\n' "$label" "$min" "$median" "$peak" >> "$txt" 2>/dev/null \
                    || bashio::log.warning "Radio ${id}: could not write ${txt} (non-fatal)."
                bashio::log.info "Radio ${id} ${label} noise floor ~ ${median} dBm (peak ${peak})."
            else
                bashio::log.warning "Radio ${id}: no usable readings for band ${label}."
            fi
            rm -f "$tmp"
        done

        if [ -s "$csv" ]
        then
            render_noise_png "$csv" "$png"
            bashio::log.info "Radio ${id}: noise-floor report written to ${csv} (and .txt/.png)."
        fi
    }

    if [ "${#rtlsdr_devices[@]}" -eq 0 ]
    then
        bashio::log.warning "No RTL-SDR dongles detected; only explicitly-declared radios (if any) will be launched."
    fi

    # Measure every detected dongle's PPM offset up front and in parallel. Each
    # 'rtl_test -p' run samples its own dongle against the host clock for up to
    # PPM_CALIBRATION_SECONDS, so the measurements are independent and concurrency
    # does not degrade them; running them together keeps startup to ~one
    # measurement window instead of N back-to-back (e.g. ~3 min total rather than
    # ~9 min for three radios). Each job only writes its own '<id>.ppm' cache;
    # the launch loop below reads those cached values instantly. measure_ppm_to_cache
    # is a no-op for radios that already have a manual ppm_error or a cached value,
    # so this pass costs nothing once every dongle has been measured once.
    if [ "$correct_ppm_offset" = "true" ] && [ "${#rtlsdr_devices[@]}" -gt 0 ]
    then
        ppm_measure_pids=()
        for i in "${!rtlsdr_devices[@]}"
        do
            [ "$i" -ge "$MAX_RADIOS" ] && break
            entry="${rtlsdr_devices[$i]}"
            serial="${entry%%$'\t'*}"
            portpath="${entry#*$'\t'}"
            # The rtl-sdr tools take a BARE serial for '-d' (unlike rtl_433's
            # ':serial' selector), so select by serial when usable, else by index.
            if _serial_is_usable "$serial"
            then
                ppm_selector="$serial"
            else
                ppm_selector="$i"
            fi
            match_id="$(radio_match_id "$serial" "$portpath")"
            measure_ppm_to_cache "$ppm_selector" "$match_id" "${conf_directory}/${match_id}.conf" &
            ppm_measure_pids+=("$!")
        done
        if [ "${#ppm_measure_pids[@]}" -gt 0 ]
        then
            bashio::log.info "Measuring PPM offsets for up to ${#ppm_measure_pids[@]} radio(s) in parallel (up to ${PPM_CALIBRATION_SECONDS}s)..."
            wait "${ppm_measure_pids[@]}"
        fi
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

        # Inject the PPM crystal offset measured for this dongle by the parallel
        # pre-pass above (or set manually / cached on a previous boot). This only
        # reads the cache, so it never blocks startup.
        radio_ppm=""
        if [ "$correct_ppm_offset" = "true" ]
        then
            radio_ppm="$(resolve_ppm_for_radio "$match_id" "$expected_file")"
        fi

        # Optionally scan the ambient noise floor while the dongle is still free
        # (before its rtl_433 claims it). Uses the same bare serial-or-index
        # selector the rtl-sdr tools expect. Purely diagnostic and best-effort.
        if [ "$detect_noise_floor" = "true" ]
        then
            if _serial_is_usable "$serial"
            then
                noise_selector="$serial"
            else
                noise_selector="$i"
            fi
            scan_noise_for_radio "$noise_selector" "$match_id"
        fi

        launch_radio "$port" "$match_id" "device ${selector}" "$expected_file" "$unique_id" "$expected_file" "$radio_ppm"
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
                msg_uuid="$(parse_discovery_uuid "$resp_body")"
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
        # delete it (see remove_discovery_state).
        save_discovery_uuid "$published_uuid"
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
