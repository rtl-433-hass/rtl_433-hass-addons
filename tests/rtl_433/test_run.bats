#!/usr/bin/env bats
# shellcheck shell=bash
# SC1090: run.sh is sourced via a runtime-computed path (cannot be followed statically).
# SC2034: the rtlsdr_devices arrays set per-test are read by functions sourced from run.sh.
# SC2317: the bashio::* stubs are invoked indirectly by the sourced helpers.
# SC2030/SC2031: each @test runs in its own subshell, so the radio_* arrays a
#   test seeds and a helper (e.g. build_discovery_body) reads are confined to
#   that subshell by design; shellcheck's "modified/used in a subshell" note is
#   expected here.
# shellcheck disable=SC1090,SC2034,SC2317,SC2030,SC2031
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

# --- enumerate_rtlsdr_by_index / flash_default_serials -----------------------

@test "enumerate_rtlsdr_by_index parses the librtlsdr banner into index<TAB>serial" {
    list_rtlsdr_banner() {
        cat <<'EOF'
Found 2 device(s):
  0:  Realtek, RTL2838UHIDIR, SN: 00000001
  1:  Realtek, RTL2832U, SN: deadbeef
EOF
    }
    run enumerate_rtlsdr_by_index
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf '0\t00000001')" ]
    [ "${lines[1]}" = "$(printf '1\tdeadbeef')" ]
}

@test "enumerate_rtlsdr_by_index preserves a blank serial field" {
    list_rtlsdr_banner() {
        cat <<'EOF'
  0:  Realtek, RTL2838UHIDIR, SN:
  1:  Realtek, RTL2832U, SN: cafe1234
EOF
    }
    run enumerate_rtlsdr_by_index
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf '0\t')" ]
    [ "${lines[1]}" = "$(printf '1\tcafe1234')" ]
}

# Regression: some librtlsdr builds list devices in the banner WITHOUT a serial
# (just "  0:  Generic RTL2832U OEM"). The old SN-only regex matched nothing, so
# the flasher saw zero factory-default dongles. Each such row must fall back to
# opening the device by index to read its serial.
@test "enumerate_rtlsdr_by_index opens devices when the banner omits the serial" {
    list_rtlsdr_banner() {
        cat <<'EOF'
Found 3 device(s):
  0:  Generic RTL2832U OEM
  1:  Generic RTL2832U OEM
  2:  Generic RTL2832U OEM
EOF
    }
    # The fallback opens 'rtl_eeprom -d <idx>' and parses 'Serial number:'.
    read_rtlsdr_serial_by_index() {
        case "$1" in
            0) printf '00000001' ;;
            1) printf '00000001' ;;
            2) printf 'deadbeef' ;;
        esac
    }
    run enumerate_rtlsdr_by_index
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf '0\t00000001')" ]
    [ "${lines[1]}" = "$(printf '1\t00000001')" ]
    [ "${lines[2]}" = "$(printf '2\tdeadbeef')" ]
}

# A banner mixing SN-bearing and SN-less rows must read each correctly: the
# fast path off the banner, the fallback by opening the device.
@test "enumerate_rtlsdr_by_index mixes banner serials and opened-device serials" {
    list_rtlsdr_banner() {
        cat <<'EOF'
Found 2 device(s):
  0:  Generic RTL2832U OEM
  1:  Realtek, RTL2832U, SN: deadbeef
EOF
    }
    read_rtlsdr_serial_by_index() { [ "$1" = "0" ] && printf '00000001'; }
    run enumerate_rtlsdr_by_index
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf '0\t00000001')" ]
    [ "${lines[1]}" = "$(printf '1\tdeadbeef')" ]
}

@test "read_rtlsdr_serial_by_index extracts the serial from the config dump" {
    timeout() { shift; "$@"; }
    rtl_eeprom() {
        cat <<'EOF'
Found 3 device(s):
  0:  Generic RTL2832U OEM

Using device 0: Generic RTL2832U OEM
Found Rafael Micro R820T tuner

Current configuration:
__________________________________________
Vendor ID:		0x0bda
Product ID:		0x2838
Manufacturer:		Realtek
Product:		RTL2838UHIDIR
Serial number:		00000001
Serial number enabled:	yes
__________________________________________
EOF
    }
    run read_rtlsdr_serial_by_index 0
    [ "$status" -eq 0 ]
    [ "$output" = "00000001" ]
}

@test "_portpath_for_serial returns the port path for a unique serial" {
    rtlsdr_devices=(
        "$(printf 'deadbeef\t1-1.2')"
        "$(printf 'cafe1234\t1-1.4')"
    )
    run _portpath_for_serial "cafe1234"
    [ "$status" -eq 0 ]
    [ "$output" = "1-1.4" ]
}

@test "_portpath_for_serial returns nothing for a duplicated or empty serial" {
    rtlsdr_devices=(
        "$(printf '00000001\t1-1.2')"
        "$(printf '00000001\t1-1.4')"
    )
    run _portpath_for_serial "00000001"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run _portpath_for_serial ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Regression for the wrong-radio EEPROM write: the sysfs port-path order and
# librtlsdr's index order can disagree, and 'rtl_eeprom -d <index>' resolves the
# index through librtlsdr. The flasher MUST take both index and serial from
# librtlsdr's enumeration so the dongle it inspects is the dongle it writes.
@test "flash_default_serials writes -d to the librtlsdr index, not the sysfs array index" {
    # sysfs port-path order: the default-serial dongle sits at ARRAY index 1...
    rtlsdr_devices=(
        "$(printf 'deadbeef\t1-1.2')"
        "$(printf '00000001\t1-1.4')"
    )
    # ...but librtlsdr enumerates that same default dongle at INDEX 0.
    list_rtlsdr_banner() {
        cat <<'EOF'
Found 2 device(s):
  0:  Realtek, RTL2838UHIDIR, SN: 00000001
  1:  Realtek, RTL2832U, SN: deadbeef
EOF
    }
    # 'timeout' is an external binary that cannot see our rtl_eeprom function;
    # stub it to drop the duration and exec the rest.
    timeout() { shift; "$@"; }
    generate_random_serial() { printf 'a1b2c3d4'; }
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    RTL_EEPROM_LOG="$BATS_TEST_TMPDIR/eeprom.args"
    : > "$RTL_EEPROM_LOG"
    rtl_eeprom() { printf '%s\n' "$*" >> "$RTL_EEPROM_LOG"; }

    run flash_default_serials
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]                                   # exactly one dongle flashed
    # Wrote to librtlsdr index 0 (the default dongle), NOT array index 1.
    [ "$(cat "$RTL_EEPROM_LOG")" = "-d 0 -s a1b2c3d4" ]
}

@test "flash_default_serials leaves non-default dongles untouched" {
    rtlsdr_devices=("$(printf 'deadbeef\t1-1.2')")
    list_rtlsdr_banner() {
        printf 'Found 1 device(s):\n  0:  Realtek, RTL2832U, SN: deadbeef\n'
    }
    timeout() { shift; "$@"; }
    generate_random_serial() { printf 'a1b2c3d4'; }
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    RTL_EEPROM_LOG="$BATS_TEST_TMPDIR/eeprom.args"
    : > "$RTL_EEPROM_LOG"
    rtl_eeprom() { printf '%s\n' "$*" >> "$RTL_EEPROM_LOG"; }

    run flash_default_serials
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]                                   # nothing flashed
    [ ! -s "$RTL_EEPROM_LOG" ]                            # rtl_eeprom never called
}

# Regression: a transient USB-claim collision makes the first 'rtl_eeprom' open
# fail. The flasher must retry (after a settle pause) rather than dropping the
# dongle at its factory-default serial.
@test "flash_default_serials retries a transient EEPROM write failure" {
    rtlsdr_devices=("$(printf '00000001\t1-1.4')")
    list_rtlsdr_banner() {
        printf 'Found 1 device(s):\n  0:  Realtek, RTL2832U, SN: 00000001\n'
    }
    timeout() { shift; "$@"; }
    generate_random_serial() { printf 'a1b2c3d4'; }
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    SLEEP_LOG="$BATS_TEST_TMPDIR/sleep.calls"
    : > "$SLEEP_LOG"
    sleep() { printf '%s\n' "$1" >> "$SLEEP_LOG"; }
    ATTEMPT_FILE="$BATS_TEST_TMPDIR/attempts"
    printf '0' > "$ATTEMPT_FILE"
    # Fail the first open, succeed on the second. The counter lives in a file so
    # it survives the pipeline subshell ('printf | timeout rtl_eeprom').
    rtl_eeprom() {
        local n
        n=$(( $(cat "$ATTEMPT_FILE") + 1 ))
        printf '%s' "$n" > "$ATTEMPT_FILE"
        [ "$n" -ge 2 ]
    }

    run flash_default_serials
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]                       # dongle flashed after the retry
    [ "$(cat "$ATTEMPT_FILE")" = "2" ]        # took exactly two attempts
    [ "$(cat "$SLEEP_LOG")" = "2" ]           # paused once (EEPROM_WRITE_RETRY_DELAY)
}

# Regression: when every attempt fails the flasher gives up after exactly
# EEPROM_WRITE_ATTEMPTS tries and reports the dongle as not flashed.
@test "flash_default_serials gives up after EEPROM_WRITE_ATTEMPTS failures" {
    rtlsdr_devices=("$(printf '00000001\t1-1.4')")
    list_rtlsdr_banner() {
        printf 'Found 1 device(s):\n  0:  Realtek, RTL2832U, SN: 00000001\n'
    }
    timeout() { shift; "$@"; }
    generate_random_serial() { printf 'a1b2c3d4'; }
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    SLEEP_LOG="$BATS_TEST_TMPDIR/sleep.calls"
    : > "$SLEEP_LOG"
    sleep() { printf '%s\n' "$1" >> "$SLEEP_LOG"; }
    CALL_LOG="$BATS_TEST_TMPDIR/calls"
    : > "$CALL_LOG"
    rtl_eeprom() { printf 'x' >> "$CALL_LOG"; return 1; }   # always fails

    run flash_default_serials
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]                       # nothing flashed
    [ "$(cat "$CALL_LOG")" = "xxx" ]          # tried EEPROM_WRITE_ATTEMPTS (3) times
    [ "$(grep -c . "$SLEEP_LOG")" -eq 2 ]     # paused between attempts (3 - 1)
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

# --- parse_rtl_test_ppm ------------------------------------------------------

@test "parse_rtl_test_ppm returns the LAST cumulative PPM across multiple lines" {
    out="$(parse_rtl_test_ppm 'Reading samples...
cumulative PPM: 12
cumulative PPM: 34
cumulative PPM: 56')"
    [ "$out" = "56" ]
}

@test "parse_rtl_test_ppm returns a negative cumulative PPM" {
    out="$(parse_rtl_test_ppm 'cumulative PPM: 7
cumulative PPM: -42')"
    [ "$out" = "-42" ]
}

@test "parse_rtl_test_ppm emits nothing when no PPM line is present" {
    out="$(parse_rtl_test_ppm 'Found 1 device(s)
Using device 0: Generic RTL2832U
No suitable PPM line here')"
    [ -z "$out" ]
}

# --- ppm_cache_path / write_ppm_cache / read_ppm_cache -----------------------

# Point the PPM cache at a per-test temp dir. The cache lives in the add-on
# config directory (ppm_cache_dir defaults to conf_directory), so override the
# global directly to an isolated temp dir for these tests.
ppm_cache_mocks() {
    ppm_cache_dir="$BATS_TEST_TMPDIR/conf"
    bashio::log.warning() { :; }
}

@test "ppm_cache_path prints <config-dir>/<id>.ppm" {
    ppm_cache_mocks
    run ppm_cache_path "rad1"
    [ "$status" -eq 0 ]
    [ "$output" = "${ppm_cache_dir}/rad1.ppm" ]
}

@test "ppm cache write->read round-trips the signed integer" {
    ppm_cache_mocks
    write_ppm_cache "rad1" "-13"
    [ -f "${ppm_cache_dir}/rad1.ppm" ]
    run read_ppm_cache "rad1"
    [ "$status" -eq 0 ]
    [ "$output" = "-13" ]
    # The second line is a self-documenting '# measured ...' comment.
    grep -q '^# measured ' "${ppm_cache_dir}/rad1.ppm"
}

@test "read_ppm_cache rejects a missing file" {
    ppm_cache_mocks
    run read_ppm_cache "nope"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "read_ppm_cache rejects a corrupt/non-integer first line" {
    ppm_cache_mocks
    mkdir -p "$ppm_cache_dir"
    printf 'not-a-number\n# measured 2026-01-01T00:00:00Z\n' > "${ppm_cache_dir}/bad.ppm"
    run read_ppm_cache "bad"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- override_has_ppm_error --------------------------------------------------

@test "override_has_ppm_error is true for a file with a ppm_error line" {
    f="$BATS_TEST_TMPDIR/with.conf"
    printf 'frequency 433.92M\n  ppm_error 5\noutput kv\n' > "$f"
    run override_has_ppm_error "$f"
    [ "$status" -eq 0 ]
}

@test "override_has_ppm_error is false for a file without a ppm_error line" {
    f="$BATS_TEST_TMPDIR/without.conf"
    printf 'frequency 433.92M\noutput kv\n' > "$f"
    run override_has_ppm_error "$f"
    [ "$status" -ne 0 ]
}

@test "override_has_ppm_error is false for a missing/empty file argument" {
    run override_has_ppm_error "$BATS_TEST_TMPDIR/does-not-exist.conf"
    [ "$status" -ne 0 ]
    run override_has_ppm_error ""
    [ "$status" -ne 0 ]
}

# --- parse_noise_bands -------------------------------------------------------

@test "parse_noise_bands expands the default bands into exact lo:hi:bin triples" {
    bashio::log.warning() { :; }
    run parse_noise_bands "433.92M,868M,915M"
    [ "$status" -eq 0 ]
    expected="$(printf '432920000:434920000:10000\n867000000:869000000:10000\n914000000:916000000:10000')"
    [ "$output" = "$expected" ]
}

@test "parse_noise_bands skips a malformed token while emitting valid neighbors" {
    bashio::log.warning() { :; }
    run parse_noise_bands "433.92M,abc,915M"
    [ "$status" -eq 0 ]
    expected="$(printf '432920000:434920000:10000\n914000000:916000000:10000')"
    [ "$output" = "$expected" ]
}

# --- rtl_power_stats ---------------------------------------------------------

@test "rtl_power_stats computes min/median/peak from a sample CSV" {
    csv="$BATS_TEST_TMPDIR/power.csv"
    # rtl_power rows: date,time,Hz_low,Hz_high,Hz_step,samples,dB,dB,...
    # dB values across both rows: -90 -80 -100 -70 -95 -85
    #   sorted: -100 -95 -90 -85 -80 -70 -> min -100, peak -70,
    #   median = (-90 + -85)/2 = -87.5
    {
        printf '2026-01-01,00:00:00,433000000,434000000,10000,1,-90,-80,-100\n'
        printf '2026-01-01,00:00:01,433000000,434000000,10000,1,-70,-95,-85\n'
    } > "$csv"
    run rtl_power_stats "$csv"
    [ "$status" -eq 0 ]
    [ "$output" = "-100 -87.5 -70" ]
}

@test "rtl_power_stats returns non-zero with no output for an empty file" {
    csv="$BATS_TEST_TMPDIR/empty.csv"
    : > "$csv"
    run rtl_power_stats "$csv"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "rtl_power_stats returns non-zero for a missing file" {
    run rtl_power_stats "$BATS_TEST_TMPDIR/missing.csv"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- baked-in default config: report_meta -----------------------------------

# rtl_433 only colon-combines sub-options within a single meta type, so 'level'
# must sit on its own 'report_meta' line; combining it with 'time' (e.g.
# 'report_meta time:... level') silently drops the level data. Guard both the
# presence of the standalone line and the absence of the broken combined form.

@test "defaults.conf emits 'report_meta level' on its own line" {
    DEFAULTS="${BATS_TEST_DIRNAME}/../../rtl_433/rtl_433.defaults.conf"
    grep -Eq '^[[:space:]]*report_meta[[:space:]]+level[[:space:]]*$' "$DEFAULTS"
}

@test "defaults.conf never combines 'level' with another meta type on one line" {
    DEFAULTS="${BATS_TEST_DIRNAME}/../../rtl_433/rtl_433.defaults.conf"
    # A report_meta line carrying 'level' plus any other whitespace-separated
    # token would drop the level data; assert no such line exists.
    run grep -En '^[[:space:]]*report_meta[[:space:]]+.*[[:space:]]level([[:space:]]|$)' "$DEFAULTS"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# --- _serial_is_default ------------------------------------------------------

@test "_serial_is_default is true for empty and the factory placeholders" {
    run _serial_is_default ""        ; [ "$status" -eq 0 ]
    run _serial_is_default "00000000"; [ "$status" -eq 0 ]
    run _serial_is_default "00000001"; [ "$status" -eq 0 ]
}

@test "_serial_is_default is false for realistic / non-default serials" {
    run _serial_is_default "00000abc"; [ "$status" -ne 0 ]
    run _serial_is_default "12345678"; [ "$status" -ne 0 ]
}

# --- generate_random_serial --------------------------------------------------

@test "generate_random_serial emits exactly 8 lowercase hex characters" {
    run generate_random_serial
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}$ ]]
    # A second call is also well-formed (format stable across invocations).
    run generate_random_serial
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}$ ]]
}

# --- flash_targeted_serial (force_randomize_serial) --------------------------

# Shared stubs for the targeted-stamp tests: silence bashio, drop 'timeout's
# duration so it execs our rtl_eeprom function, and record every rtl_eeprom
# argument vector to $RTL_EEPROM_LOG. The write runs inside 'printf | timeout
# rtl_eeprom' (a subshell), so the log MUST be a file path (an array would not
# survive the subshell), mirroring the flash_default_serials tests above.
targeted_stamp_mocks() {
    timeout() { shift; "$@"; }
    bashio::log.info()    { :; }
    bashio::log.warning() { :; }
    RTL_EEPROM_LOG="$BATS_TEST_TMPDIR/eeprom.args"
    : > "$RTL_EEPROM_LOG"
    rtl_eeprom() { printf '%s\n' "$*" >> "$RTL_EEPROM_LOG"; }
}

# Regression for PR #98's wrong-radio write: the sysfs port-path order and
# librtlsdr's index order can DISAGREE, and 'rtl_eeprom -d <index>' resolves the
# index through librtlsdr. flash_targeted_serial must map the selected port path
# to the librtlsdr INDEX (via enumerate_rtlsdr_by_index), never the sysfs array
# position.
@test "flash_targeted_serial writes -d to the librtlsdr index for the selected port path" {
    # sysfs sorts 1-1.2 before 1-1.4 (array index 0 / 1)...
    rtlsdr_devices=( "$(printf 'aaaa1111\t1-1.2')" "$(printf 'bbbb2222\t1-1.4')" )
    # ...but librtlsdr lists the 1-1.4 dongle (bbbb2222) at INDEX 0.
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: bbbb2222\n'
        printf '  1:  Realtek, RTL2832U, SN: aaaa1111\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'feedface'; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "feedface" ]                            # echoes the new serial
    # Wrote to librtlsdr index 0 (bbbb2222), NOT sysfs array position 1.
    grep -q -- "-d 0 -s feedface" "$RTL_EEPROM_LOG"
    run grep -q -- "-d 1" "$RTL_EEPROM_LOG"
    [ "$status" -ne 0 ]                                   # never wrote index 1
}

# The targeted pass is NOT gated on default-only: a dongle whose current serial
# is a real (non-default) value is still re-stamped. Contrast flash_default_serials,
# which would skip such a dongle.
@test "flash_targeted_serial rewrites a dongle whose current serial is non-default" {
    rtlsdr_devices=( "$(printf 'bbbb2222\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 1 device(s):\n  0:  Realtek, RTL2832U, SN: bbbb2222\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'a1b2c3d4'; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "a1b2c3d4" ]
    [ "$(cat "$RTL_EEPROM_LOG")" = "-d 0 -s a1b2c3d4" ]   # rewrote the non-default dongle
}

# Refusal guard: a selector matching NO connected dongle writes nothing.
@test "flash_targeted_serial refuses when the port path matches zero dongles" {
    rtlsdr_devices=( "$(printf 'bbbb2222\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 1 device(s):\n  0:  Realtek, RTL2832U, SN: bbbb2222\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'a1b2c3d4'; }

    run flash_targeted_serial "1-1.9"
    [ "$status" -ne 0 ]
    [ ! -s "$RTL_EEPROM_LOG" ]                            # rtl_eeprom never called
}

# Refusal guard: a duplicated port path matches MULTIPLE rows → ambiguous → no write.
@test "flash_targeted_serial refuses when the port path matches multiple dongles" {
    rtlsdr_devices=( "$(printf 'aaaa1111\t1-1.4')" "$(printf 'bbbb2222\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: aaaa1111\n'
        printf '  1:  Realtek, RTL2832U, SN: bbbb2222\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'a1b2c3d4'; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -ne 0 ]
    [ ! -s "$RTL_EEPROM_LOG" ]
}

# Refusal guard (sole-default rule): when the selected dongle carries a shared
# factory default AND two default-serial indices exist in the banner, the target
# maps to multiple librtlsdr indices → ambiguous → no write.
@test "flash_targeted_serial refuses a shared-default target that maps to multiple default indices" {
    # The selector resolves to a single sysfs row (distinct port paths), but that
    # row's serial is a shared default and the banner shows two default indices.
    rtlsdr_devices=( "$(printf '00000001\t1-1.2')" "$(printf '00000001\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: 00000001\n'
        printf '  1:  Realtek, RTL2832U, SN: 00000001\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'a1b2c3d4'; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -ne 0 ]
    [ ! -s "$RTL_EEPROM_LOG" ]
}

# A shared-default target IS stamped when exactly one default index exists (the
# sole-default rule's accept case), confirming the guard above refuses on
# ambiguity, not on default-ness alone.
@test "flash_targeted_serial stamps a sole-default target" {
    rtlsdr_devices=( "$(printf 'bbbb2222\t1-1.2')" "$(printf '00000001\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: bbbb2222\n'
        printf '  1:  Realtek, RTL2832U, SN: 00000001\n'
    }
    targeted_stamp_mocks
    generate_random_serial() { printf 'a1b2c3d4'; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "a1b2c3d4" ]
    [ "$(cat "$RTL_EEPROM_LOG")" = "-d 1 -s a1b2c3d4" ]   # the sole default index
}

# Collision avoidance: a generated serial that already belongs to another
# connected dongle is rejected; the next fresh candidate is written instead.
@test "flash_targeted_serial never reuses a serial present on another dongle" {
    rtlsdr_devices=( "$(printf 'aaaa1111\t1-1.2')" "$(printf 'bbbb2222\t1-1.4')" )
    list_rtlsdr_banner() {
        printf 'Found 2 device(s):\n'
        printf '  0:  Realtek, RTL2832U, SN: aaaa1111\n'
        printf '  1:  Realtek, RTL2832U, SN: bbbb2222\n'
    }
    targeted_stamp_mocks
    # First candidate collides with the OTHER connected dongle (aaaa1111); the
    # avoid-set must reject it and accept the second, fresh value.
    SERIAL_SEQ="$BATS_TEST_TMPDIR/serials"
    printf 'aaaa1111\nfeedbeef\n' > "$SERIAL_SEQ"
    generate_random_serial() { sed -n '1p' "$SERIAL_SEQ"; sed -i '1d' "$SERIAL_SEQ"; }

    run flash_targeted_serial "1-1.4"
    [ "$status" -eq 0 ]
    [ "$output" = "feedbeef" ]                            # the colliding candidate was skipped
    [ "$(cat "$RTL_EEPROM_LOG")" = "-d 1 -s feedbeef" ]
}

# --- surface_radio_status ----------------------------------------------------

# surface_radio_status is defined inside main(), so it cannot be sourced. Define
# a byte-for-byte copy of its body here (kept in sync with run.sh) so the test
# can exercise the surfacing contract: the per-radio log line and the
# radios.status file fields. resolve_addon_host and bashio logging are stubbed so
# nothing touches the network.
surface_radio_status() {
    local host i tag uid port serial portpath status_file tmp
    host="$(resolve_addon_host)"

    for i in "${!radio_ports[@]}"
    do
        tag="${radio_tags[$i]}"
        uid="${radio_unique_ids[$i]}"
        port="${radio_ports[$i]}"
        bashio::log.info "Radio ${tag}: unique_id=${uid} host=${host:-<unknown>} port=${port}"
    done

    status_file="${conf_directory}/radios.status"
    tmp="${status_file}.tmp"
    if {
        printf '# rtl_433 radios — values for the Home Assistant reconfigure step\n'
        for i in "${!radio_ports[@]}"
        do
            tag="${radio_tags[$i]}"
            uid="${radio_unique_ids[$i]}"
            port="${radio_ports[$i]}"
            serial="${radio_serials[$i]:-}"
            portpath="${radio_portpaths[$i]:-}"
            printf 'radio=%s\tunique_id=%s\thost=%s\tport=%s\tserial=%s\tportpath=%s\n' \
                "$tag" "$uid" "${host:-}" "$port" "$serial" "$portpath"
        done
    } > "$tmp" 2>/dev/null && mv "$tmp" "$status_file" 2>/dev/null
    then
        :
    else
        rm -f "$tmp" 2>/dev/null
        bashio::log.warning "Could not write ${status_file} (non-fatal)."
    fi
}

@test "surface_radio_status emits unique_id/host/port and writes radios.status with portpath" {
    conf_directory="$BATS_TEST_TMPDIR"
    radio_ports=( 8433 8434 )
    radio_tags=( radio0 radio1 )
    radio_unique_ids=( "serial:00000abc" "usbpath:1-1.4" )
    radio_serials=( "00000abc" "" )
    # Index-aligned port paths: a real path for radio0, and an EMPTY path for
    # radio1 (e.g. a template-identity radio with no resolvable USB port).
    radio_portpaths=( "1-1.4" "" )
    resolve_addon_host() { printf 'a0d7b954-rtl-433'; }
    # Capture the emitted log lines so the per-radio surfacing line can be asserted.
    LOG="$BATS_TEST_TMPDIR/log"
    : > "$LOG"
    bashio::log.info()    { printf '%s\n' "$*" >> "$LOG"; }
    bashio::log.warning() { printf '%s\n' "$*" >> "$LOG"; }

    surface_radio_status

    # (a) The emitted log line carries all three reconfigure fields.
    grep -q 'unique_id=serial:00000abc' "$LOG"
    grep -q 'host=a0d7b954-rtl-433' "$LOG"
    grep -q 'port=8433' "$LOG"

    # (b) radios.status exists and carries those fields, now including portpath,
    # for each radio: a populated portpath for radio0 and an empty one for radio1.
    status_file="$conf_directory/radios.status"
    [ -f "$status_file" ]
    grep -q $'unique_id=serial:00000abc\thost=a0d7b954-rtl-433\tport=8433\tserial=00000abc\tportpath=1-1.4' "$status_file"
    grep -q $'unique_id=usbpath:1-1.4\thost=a0d7b954-rtl-433\tport=8434\tserial=\tportpath=' "$status_file"
}

# --- discovery roster (publish_discovery 'radios' array) ---------------------

# The 'radios' roster builder lives INSIDE publish_discovery, which also does the
# network POSTs and needs SUPERVISOR_TOKEN, so it cannot be sourced and called in
# isolation. Replicate the exact roster-build snippet and the body printf from
# run.sh's publish_discovery here (kept in sync with run.sh) so the test exercises
# the JSON-assembly contract: a valid, additive 'config.radios' array carrying both
# identifiers per radio, with the legacy single-radio fields left intact.
build_discovery_body() {
    local host="$1"
    # _json_safe: same allowlist run.sh uses to keep device-derived text from
    # breaking the hand-built JSON.
    _json_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9:._-' '_'; }

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

    # Mirror run.sh: the legacy top-level fields come from the FIRST radio's
    # host/port/unique_id, with the additive roster appended.
    local body
    printf -v body \
        '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s", "radios": [%s]}}' \
        "$host" "${radio_ports[0]}" "${radio_unique_ids[0]}" "$radios_json"
    printf '%s' "$body"
}

@test "discovery body builds a valid additive radios roster covering all identity kinds" {
    # Mixed mock set: a usable serial, an empty-serial/usbpath-identity radio, and
    # a template-identity radio with BOTH serial and usbpath empty.
    radio_ports=( 8433 8434 8435 )
    radio_tags=( radio0 radio1 radio2 )
    radio_unique_ids=( "serial:00000abc" "usbpath:1-1.2" "template:soapy" )
    radio_serials=( "00000abc" "" "" )
    radio_portpaths=( "1-1.4" "1-1.2" "" )

    body="$(build_discovery_body "a0d7b954-rtl-433")"

    # (a) Valid JSON.
    run bash -c 'printf "%s" "$0" | jq -e .' "$body"
    [ "$status" -eq 0 ]

    # (b) The roster holds one entry per radio.
    printf '%s' "$body" | jq -e '.config.radios | length == 3'

    # (c) Every entry carries all five keys (serial/usbpath may be "").
    printf '%s' "$body" \
        | jq -e 'all(.config.radios[]; has("unique_id") and has("port") and has("path") and has("serial") and has("usbpath"))'

    # (d) Dual identity is preserved: the serial radio keeps its serial, the
    # usbpath radio carries an empty serial but a port path, and the template
    # radio has BOTH serial and usbpath empty.
    printf '%s' "$body" | jq -e '.config.radios[0].serial == "00000abc" and .config.radios[0].usbpath == "1-1.4"'
    printf '%s' "$body" | jq -e '.config.radios[1].serial == "" and .config.radios[1].usbpath == "1-1.2"'
    printf '%s' "$body" | jq -e '.config.radios[2].serial == "" and .config.radios[2].usbpath == ""'

    # (e) Back-compat: the legacy top-level single-radio fields are still present.
    printf '%s' "$body" | jq -e '.config.host and .config.port and .config.path and .config.unique_id'
}
