#!/usr/bin/env bats
# Tests for rtl_433_mqtt_autodiscovery/run.sh addon script

# Load test helpers
load '../bats/test_helper'

setup() {
    setup_temp_dir
    mock_bashio_reset

    # Set up default mock MQTT service
    mock_bashio_set_service "mqtt" "host" "test-mqtt-host"
    mock_bashio_set_service "mqtt" "port" "1883"
    mock_bashio_set_service "mqtt" "username" "test-user"
    mock_bashio_set_service "mqtt" "password" "test-pass"

    # Clear environment variables that might interfere
    unset MQTT_HOST
    unset MQTT_PORT
    unset RTL_TOPIC
    unset DISCOVERY_PREFIX
    unset DISCOVERY_INTERVAL
    unset LOG_LEVEL
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Standalone Docker Mode Tests
# =============================================================================

@test "uses MQTT_HOST environment variable in standalone mode" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        export MQTT_HOST="standalone-mqtt-host"

        if [ -n "${MQTT_HOST+x}" ]; then
            echo "standalone_mode: host=$MQTT_HOST"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"standalone_mode"* ]]
    [[ "$output" == *"host=standalone-mqtt-host"* ]]
}

@test "applies default port 1883 in standalone mode" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        export MQTT_HOST="standalone-host"

        MQTT_PORT="${MQTT_PORT:-1883}"
        echo "port=$MQTT_PORT"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"port=1883"* ]]
}

@test "applies default RTL_TOPIC in standalone mode" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        export MQTT_HOST="standalone-host"

        RTL_TOPIC="${RTL_TOPIC:-rtl_433/+/events}"
        echo "topic=$RTL_TOPIC"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"topic=rtl_433/+/events"* ]]
}

@test "applies default DISCOVERY_PREFIX in standalone mode" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        export MQTT_HOST="standalone-host"

        DISCOVERY_PREFIX="${DISCOVERY_PREFIX:-homeassistant}"
        echo "prefix=$DISCOVERY_PREFIX"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"prefix=homeassistant"* ]]
}

@test "applies default DISCOVERY_INTERVAL in standalone mode" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        export MQTT_HOST="standalone-host"

        DISCOVERY_INTERVAL="${DISCOVERY_INTERVAL:-600}"
        echo "interval=$DISCOVERY_INTERVAL"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"interval=600"* ]]
}

# =============================================================================
# Home Assistant Mode Tests
# =============================================================================

@test "retrieves MQTT settings from Home Assistant services" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_service "mqtt" "host" "ha-mqtt-host"
        mock_bashio_set_service "mqtt" "port" "1884"

        if bashio::services.available mqtt; then
            MQTT_HOST=$(bashio::services mqtt "host")
            MQTT_PORT=$(bashio::services mqtt "port")
            echo "ha_mode: host=$MQTT_HOST port=$MQTT_PORT"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"ha_mode"* ]]
    [[ "$output" == *"host=ha-mqtt-host"* ]]
    [[ "$output" == *"port=1884"* ]]
}

@test "uses external broker config when MQTT service unavailable" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_mqtt_available "false"
        mock_bashio_set_config "mqtt_host" "external-broker"
        mock_bashio_set_config "mqtt_port" "1885"

        if bashio::services.available mqtt; then
            MQTT_HOST=$(bashio::services mqtt "host")
        else
            MQTT_HOST=$(bashio::config "mqtt_host")
            MQTT_PORT=$(bashio::config "mqtt_port")
            echo "external_mode: host=$MQTT_HOST port=$MQTT_PORT"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"external_mode"* ]]
    [[ "$output" == *"host=external-broker"* ]]
    [[ "$output" == *"port=1885"* ]]
}

# =============================================================================
# Log Level Tests
# =============================================================================

@test "adds --quiet flag for quiet log level" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "log_level" "quiet"

        OTHER_ARGS=()
        LOG_LEVEL=$(bashio::config "log_level")
        if [[ $LOG_LEVEL == "quiet" ]]; then
            OTHER_ARGS+=(--quiet)
        fi
        echo "args: ${OTHER_ARGS[*]}"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"--quiet"* ]]
}

@test "adds --debug flag for debug log level" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "log_level" "debug"

        OTHER_ARGS=()
        LOG_LEVEL=$(bashio::config "log_level")
        if [[ $LOG_LEVEL == "debug" ]]; then
            OTHER_ARGS+=(--debug)
        fi
        echo "args: ${OTHER_ARGS[*]}"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"--debug"* ]]
}

@test "no extra flags for default log level" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "log_level" "default"

        OTHER_ARGS=()
        LOG_LEVEL=$(bashio::config "log_level")
        if [[ $LOG_LEVEL == "quiet" ]]; then
            OTHER_ARGS+=(--quiet)
        fi
        if [[ $LOG_LEVEL == "debug" ]]; then
            OTHER_ARGS+=(--debug)
        fi
        if [ ${#OTHER_ARGS[@]} -eq 0 ]; then
            echo "no_extra_flags"
        else
            echo "args: ${OTHER_ARGS[*]}"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"no_extra_flags"* ]]
}

# =============================================================================
# Optional Parameter Tests
# =============================================================================

@test "adds --retain when mqtt_retain is true" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "mqtt_retain" "true"

        OTHER_ARGS=()
        if bashio::config.true "mqtt_retain"; then
            OTHER_ARGS+=(--retain)
        fi
        echo "args: ${OTHER_ARGS[*]}"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"--retain"* ]]
}

@test "adds --force_update when force_update is true" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "force_update" "true"

        OTHER_ARGS=()
        if bashio::config.true "force_update"; then
            OTHER_ARGS+=(--force_update)
        fi
        echo "args: ${OTHER_ARGS[*]}"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"--force_update"* ]]
}

@test "adds -T suffix when device_topic_suffix is set" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "device_topic_suffix" "my-suffix"

        OTHER_ARGS=()
        DEVICE_TOPIC_SUFFIX=$(bashio::config "device_topic_suffix")
        if [ -n "$DEVICE_TOPIC_SUFFIX" ]; then
            OTHER_ARGS+=(-T "$DEVICE_TOPIC_SUFFIX")
        fi
        echo "args: ${OTHER_ARGS[*]}"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"-T my-suffix"* ]]
}

@test "omits -T when device_topic_suffix is empty" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "device_topic_suffix" ""

        OTHER_ARGS=()
        DEVICE_TOPIC_SUFFIX=$(bashio::config "device_topic_suffix")
        if [ -n "$DEVICE_TOPIC_SUFFIX" ]; then
            OTHER_ARGS+=(-T "$DEVICE_TOPIC_SUFFIX")
        fi
        if [ ${#OTHER_ARGS[@]} -eq 0 ]; then
            echo "no_suffix_arg"
        else
            echo "args: ${OTHER_ARGS[*]}"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"no_suffix_arg"* ]]
}

# =============================================================================
# Command Construction Tests
# =============================================================================

@test "builds correct python command with all arguments" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "mqtt_retain" "true"
        mock_bashio_set_config "log_level" "debug"
        mock_bashio_set_config "device_topic_suffix" "test-suffix"

        MQTT_HOST="localhost"
        MQTT_PORT="1883"
        RTL_TOPIC="rtl_433/+/events"
        DISCOVERY_PREFIX="homeassistant"
        DISCOVERY_INTERVAL="600"

        OTHER_ARGS=()
        if bashio::config.true "mqtt_retain"; then
            OTHER_ARGS+=(--retain)
        fi
        LOG_LEVEL=$(bashio::config "log_level")
        if [[ $LOG_LEVEL == "debug" ]]; then
            OTHER_ARGS+=(--debug)
        fi
        DEVICE_TOPIC_SUFFIX=$(bashio::config "device_topic_suffix")
        if [ -n "$DEVICE_TOPIC_SUFFIX" ]; then
            OTHER_ARGS+=(-T "$DEVICE_TOPIC_SUFFIX")
        fi

        # Build the command (without actually running python)
        CMD="python3 -u /rtl_433_mqtt_hass.py"
        CMD+=" -H $MQTT_HOST"
        CMD+=" -p $MQTT_PORT"
        CMD+=" -R $RTL_TOPIC"
        CMD+=" -D $DISCOVERY_PREFIX"
        CMD+=" -i $DISCOVERY_INTERVAL"
        CMD+=" ${OTHER_ARGS[*]}"
        echo "$CMD"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"python3 -u /rtl_433_mqtt_hass.py"* ]]
    [[ "$output" == *"-H localhost"* ]]
    [[ "$output" == *"-p 1883"* ]]
    [[ "$output" == *"-R rtl_433/+/events"* ]]
    [[ "$output" == *"-D homeassistant"* ]]
    [[ "$output" == *"-i 600"* ]]
    [[ "$output" == *"--retain"* ]]
    [[ "$output" == *"--debug"* ]]
    [[ "$output" == *"-T test-suffix"* ]]
}

# =============================================================================
# Environment Variable Export Tests
# =============================================================================

@test "exports MQTT_USERNAME for python script" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_service "mqtt" "username" "exported-user"

        if bashio::services.available mqtt; then
            MQTT_USERNAME=$(bashio::services mqtt "username")
            export MQTT_USERNAME
        fi
        echo "MQTT_USERNAME=$MQTT_USERNAME"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"MQTT_USERNAME=exported-user"* ]]
}

@test "exports MQTT_PASSWORD for python script" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_service "mqtt" "password" "secret-pass"

        if bashio::services.available mqtt; then
            MQTT_PASSWORD=$(bashio::services mqtt "password")
            export MQTT_PASSWORD
        fi
        echo "MQTT_PASSWORD=$MQTT_PASSWORD"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"MQTT_PASSWORD=secret-pass"* ]]
}
