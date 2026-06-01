#!/usr/bin/env bats
# shellcheck shell=bash
# SC1090: run.sh is sourced via a runtime-computed path (cannot be followed statically).
# SC2034: the rtlsdr_devices arrays set per-test are read by functions sourced from run.sh.
# shellcheck disable=SC1090,SC2034
# Unit tests for the dongle-detection / identifier helpers in rtl_433/run.sh.
#
# run.sh has a main()-guard, so sourcing it under plain bash defines the helper
# functions without executing the add-on body. These tests exercise the custom
# logic: sysfs enumeration, serial usability, the unique-id fallback ladder, the
# raw match-id derivation, and the Supervisor discovery uuid persistence/cleanup.
# Uses only plain BATS assertions.

setup() {
    RUN_SH="${BATS_TEST_DIRNAME}/../../rtl_433/run.sh"
    # Source for function definitions only; the main-guard prevents the body
    # from running. The enumeration/identifier helpers never call bashio; the
    # discovery tests stub bashio/curl themselves (see discovery_mocks).
    source "$RUN_SH"
}

# Create a mock sysfs USB device directory under $SYSFS_USB_BASE.
# Args: <dir> <vid> <pid> [serial]
make_usb_dev() {
    local d="$SYSFS_USB_BASE/$1"
    mkdir -p "$d"
    printf '%s' "$2" > "$d/idVendor"
    printf '%s' "$3" > "$d/idProduct"
    [ -n "${4:-}" ] && printf '%s' "$4" > "$d/serial"
    return 0
}

# --- enumerate_rtlsdr_devices ------------------------------------------------

@test "enumerate emits serial<TAB>portpath for a known RTL-SDR dongle" {
    SYSFS_USB_BASE="$BATS_TEST_TMPDIR/sys"
    mkdir -p "$SYSFS_USB_BASE"
    make_usb_dev "1-1.4" "0bda" "2838" "00000abc"
    run enumerate_rtlsdr_devices
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '00000abc\t1-1.4')" ]
}

@test "enumerate skips interface nodes, id-less devices, and non-RTL-SDR ids" {
    SYSFS_USB_BASE="$BATS_TEST_TMPDIR/sys"
    mkdir -p "$SYSFS_USB_BASE"
    make_usb_dev "1-1.4"     "0bda" "2838" "abc"   # match (known id)
    make_usb_dev "1-1.4:1.0" "0bda" "2838" "iface" # interface node: name has ':'
    make_usb_dev "2-1"       "1234" "5678" "other" # unknown id
    # Device lacking idVendor/idProduct: just an empty dir, must be skipped.
    mkdir -p "$SYSFS_USB_BASE/usb1"
    run enumerate_rtlsdr_devices
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'abc\t1-1.4')" ]
}

@test "enumerate yields no output for an empty/missing sysfs tree" {
    SYSFS_USB_BASE="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$SYSFS_USB_BASE"
    run enumerate_rtlsdr_devices
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- _serial_is_usable -------------------------------------------------------

@test "_serial_is_usable rejects placeholders, short ints, empty, and duplicates" {
    rtlsdr_devices=( "$(printf 'DUP\t1-1')" "$(printf 'DUP\t1-2')" )
    run _serial_is_usable ""        ; [ "$status" -ne 0 ]
    run _serial_is_usable "00000000"; [ "$status" -ne 0 ]
    run _serial_is_usable "00000001"; [ "$status" -ne 0 ]
    run _serial_is_usable "5"       ; [ "$status" -ne 0 ]  # short reserved int
    run _serial_is_usable "DUP"     ; [ "$status" -ne 0 ]  # appears twice
}

@test "_serial_is_usable accepts a unique realistic serial" {
    rtlsdr_devices=( "$(printf '00000abc\t1-1')" )
    run _serial_is_usable "00000abc"
    [ "$status" -eq 0 ]
}

# --- resolve_radio_unique_id -------------------------------------------------

@test "resolve_radio_unique_id prefers a usable serial" {
    rtlsdr_devices=( "$(printf '00000abc\t1-1.4')" )
    run resolve_radio_unique_id ":00000abc" "tmpl"
    [ "$status" -eq 0 ]
    [ "$output" = "serial:00000abc" ]
}

@test "resolve_radio_unique_id falls back to usbpath for an unusable serial" {
    rtlsdr_devices=( "$(printf '00000000\t1-1.4')" )   # placeholder serial
    run resolve_radio_unique_id ":00000000" "tmpl"
    [ "$status" -eq 0 ]
    [ "$output" = "usbpath:1-1.4" ]
}

@test "resolve_radio_unique_id falls back to template when nothing matches" {
    rtlsdr_devices=()
    run resolve_radio_unique_id ":nope" "tmpl"
    [ "$status" -eq 0 ]
    [ "$output" = "template:tmpl" ]
}

@test "resolve_radio_unique_id result only contains the JSON-safe allowlist" {
    rtlsdr_devices=()
    run resolve_radio_unique_id "" "a b/c"   # space and '/' are disallowed
    [ "$status" -eq 0 ]
    [ "$output" = "template:a_b_c" ]
    # Confirm nothing outside [A-Za-z0-9:._-] survived.
    [ -z "$(printf '%s' "$output" | tr -d 'A-Za-z0-9:._-')" ]
}

# --- radio_match_id ----------------------------------------------------------

@test "radio_match_id returns the usable serial" {
    rtlsdr_devices=( "$(printf '00000abc\t1-1.4')" )
    run radio_match_id "00000abc" "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "00000abc" ]
}

@test "radio_match_id returns the sanitised port path when serial is unusable" {
    rtlsdr_devices=( "$(printf '00000000\t1-1.4')" )
    run radio_match_id "00000000" "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "1-1.4" ]
}

# --- parse_discovery_uuid ----------------------------------------------------

@test "parse_discovery_uuid extracts the uuid from a POST /discovery response" {
    run parse_discovery_uuid '{"result":"ok","data":{"uuid":"abc123DEF456"}}'
    [ "$status" -eq 0 ]
    [ "$output" = "abc123DEF456" ]
}

@test "parse_discovery_uuid emits nothing when the body carries no uuid" {
    run parse_discovery_uuid '{"result":"error","message":"bad service"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- save_discovery_uuid / remove_discovery_state ----------------------------

# Stub the Supervisor-facing dependencies: bashio logging is silenced and curl
# records its arguments to $CURL_LOG and prints $MOCK_HTTP_CODE (mimicking
# 'curl -w %{http_code}' with the response body discarded via -o /dev/null). The
# stubs and variables are inherited by the subshell that 'run' forks. DATA_DIR is
# pointed at a per-test temp dir; the discovery helpers read it at call time.
discovery_mocks() {
    DATA_DIR="$BATS_TEST_TMPDIR/data"
    mkdir -p "$DATA_DIR"
    CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    : > "$CURL_LOG"
    MOCK_HTTP_CODE="200"
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    curl() { printf '%s\n' "$*" >> "$CURL_LOG"; printf '%s' "$MOCK_HTTP_CODE"; }
}

@test "save_discovery_uuid writes the uuid under DATA_DIR" {
    discovery_mocks
    run save_discovery_uuid "uuid-xyz"
    [ "$status" -eq 0 ]
    [ "$(cat "$DATA_DIR/discovery.uuid")" = "uuid-xyz" ]
}

@test "save_discovery_uuid is a no-op for an empty uuid" {
    discovery_mocks
    run save_discovery_uuid ""
    [ "$status" -eq 0 ]
    [ ! -e "$DATA_DIR/discovery.uuid" ]
}

@test "save+remove round-trip: persisted uuid is DELETEd and the state cleared" {
    SUPERVISOR_TOKEN="tok"
    discovery_mocks
    save_discovery_uuid "uuid-123"
    MOCK_HTTP_CODE="200"
    run remove_discovery_state
    [ "$status" -eq 0 ]
    grep -q -- "-X DELETE" "$CURL_LOG"
    grep -q "http://supervisor/discovery/uuid-123" "$CURL_LOG"
    [ ! -e "$DATA_DIR/discovery.uuid" ]
}

@test "remove_discovery_state clears local state even on a non-2xx (already gone)" {
    SUPERVISOR_TOKEN="tok"
    discovery_mocks
    save_discovery_uuid "uuid-404"
    MOCK_HTTP_CODE="404"
    run remove_discovery_state
    [ "$status" -eq 0 ]
    grep -q "http://supervisor/discovery/uuid-404" "$CURL_LOG"
    [ ! -e "$DATA_DIR/discovery.uuid" ]
}

@test "remove_discovery_state is a no-op when no state file exists" {
    SUPERVISOR_TOKEN="tok"
    discovery_mocks
    run remove_discovery_state
    [ "$status" -eq 0 ]
    [ ! -s "$CURL_LOG" ]   # curl never called
}

@test "remove_discovery_state clears an empty state file without calling curl" {
    SUPERVISOR_TOKEN="tok"
    discovery_mocks
    : > "$DATA_DIR/discovery.uuid"
    run remove_discovery_state
    [ "$status" -eq 0 ]
    [ ! -s "$CURL_LOG" ]
    [ ! -e "$DATA_DIR/discovery.uuid" ]
}

@test "remove_discovery_state skips entirely without a Supervisor token" {
    unset SUPERVISOR_TOKEN
    discovery_mocks
    save_discovery_uuid "uuid-x"
    run remove_discovery_state
    [ "$status" -eq 0 ]
    [ ! -s "$CURL_LOG" ]                   # curl never called
    [ -e "$DATA_DIR/discovery.uuid" ]      # state left untouched
}
