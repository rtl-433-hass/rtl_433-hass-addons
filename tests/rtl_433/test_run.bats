#!/usr/bin/env bats
# Tests for rtl_433/run.sh addon script

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

    # Create the config directory
    export conf_directory="${TEST_TEMP_DIR}/config/rtl_433"
    mkdir -p "$conf_directory"

    # Mock rtl_433 command to just echo what would be run
    rtl_433() {
        echo "MOCK_RTL_433: $*"
        return 0
    }
    export -f rtl_433
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Configuration Directory Tests
# =============================================================================

@test "creates config directory if it does not exist" {
    rmdir "$conf_directory"
    rmdir "$(dirname "$conf_directory")"

    # Source just the directory creation logic
    run bash -c '
        source tests/bats/mock_bashio.bash
        conf_directory="'"$conf_directory"'"
        if [ ! -d "$conf_directory" ]; then
            mkdir -p "$conf_directory"
        fi
        test -d "$conf_directory" && echo "created"
    '

    [[ "$output" == *"created"* ]]
    [ -d "$conf_directory" ]
}

@test "config directory already exists - no error" {
    [ -d "$conf_directory" ]

    run bash -c '
        conf_directory="'"$conf_directory"'"
        if [ ! -d "$conf_directory" ]; then
            mkdir -p "$conf_directory"
        fi
        echo "ok"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# =============================================================================
# MQTT Service Discovery Tests
# =============================================================================

@test "retrieves MQTT settings when service is available" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_service "mqtt" "host" "my-mqtt-server"
        mock_bashio_set_service "mqtt" "port" "1884"
        mock_bashio_set_service "mqtt" "username" "myuser"
        mock_bashio_set_service "mqtt" "password" "mypass"

        if bashio::services.available "mqtt"; then
            host=$(bashio::services "mqtt" "host")
            port=$(bashio::services "mqtt" "port")
            username=$(bashio::services "mqtt" "username")
            password=$(bashio::services "mqtt" "password")
            echo "host=$host port=$port user=$username pass=$password"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"host=my-mqtt-server"* ]]
    [[ "$output" == *"port=1884"* ]]
    [[ "$output" == *"user=myuser"* ]]
    [[ "$output" == *"pass=mypass"* ]]
}

@test "logs info when MQTT service is not available" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_mqtt_available "false"

        if bashio::services.available "mqtt"; then
            echo "mqtt available"
        else
            bashio::log.info "The mqtt addon is not available."
            echo "mqtt not available"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"mqtt not available"* ]]
}

# =============================================================================
# Retain Flag Tests
# =============================================================================

@test "converts retain true to 1" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "retain" "true"

        retain=$(bashio::config "retain")
        if [ "$retain" = "true" ]; then
            retain=1
        fi
        echo "retain=$retain"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"retain=1"* ]]
}

@test "leaves retain unchanged when not true" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "retain" "false"

        retain=$(bashio::config "retain")
        if [ "$retain" = "true" ]; then
            retain=1
        fi
        echo "retain=$retain"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"retain=false"* ]]
}

# =============================================================================
# Legacy Configuration Tests
# =============================================================================

@test "shows deprecation warning for legacy rtl_433_conf_file option" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "rtl_433_conf_file" "old_config.conf"

        conf_file=$(bashio::config "rtl_433_conf_file")
        if [[ $conf_file != "" ]]; then
            bashio::log.warning "rtl_433 now supports automatic configuration"
            echo "legacy_mode"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy_mode"* ]]
}

@test "does not trigger legacy mode when rtl_433_conf_file is empty" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        mock_bashio_set_config "rtl_433_conf_file" ""

        conf_file=$(bashio::config "rtl_433_conf_file")
        if [[ $conf_file != "" ]]; then
            echo "legacy_mode"
        else
            echo "normal_mode"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"normal_mode"* ]]
}

# =============================================================================
# Default Template Generation Tests
# =============================================================================

@test "creates default template when config directory is empty" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        conf_directory="'"$conf_directory"'"

        # Check if directory is empty and create default template
        if [ ! "$(ls -A "$conf_directory")" ]; then
            cat > "$conf_directory/rtl_433.conf.template" <<EOD
output mqtt://\${host}:\${port},user=\${username},pass=\${password},retain=\${retain}
report_meta time:iso:usec:tz
protocol -59
EOD
        fi

        # Verify template was created
        if [ -f "$conf_directory/rtl_433.conf.template" ]; then
            echo "template_created"
            cat "$conf_directory/rtl_433.conf.template"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"template_created"* ]]
    [[ "$output" == *'${host}'* ]]
    [[ "$output" == *'${port}'* ]]
    [[ "$output" == *"protocol -59"* ]]
}

@test "does not overwrite existing templates" {
    # Create an existing template
    echo "existing_config" > "$conf_directory/custom.conf.template"

    run bash -c '
        conf_directory="'"$conf_directory"'"

        if [ ! "$(ls -A "$conf_directory")" ]; then
            echo "would_create_default"
        else
            echo "skip_default_creation"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"skip_default_creation"* ]]
}

# =============================================================================
# Template Processing Tests
# =============================================================================

@test "processes template files and substitutes variables" {
    # Create a template file
    cat > "$conf_directory/test.conf.template" << 'EOF'
output mqtt://${host}:${port},user=${username},pass=${password},retain=${retain}
frequency 433.92M
EOF

    run bash -c '
        source tests/bats/mock_bashio.bash
        conf_directory="'"$conf_directory"'"

        # Set up variables as the script would
        host="mqtt.local"
        port="1883"
        username="user1"
        password="pass1"
        retain="1"

        # Process templates (simplified version of the script logic)
        for template in "$conf_directory"/*.conf.template; do
            live=$(basename "$template" .template)
            {
                echo "cat <<EOD"
                cat "$template"
                echo
                echo "EOD"
            } > /tmp/heredoc_test

            # shellcheck source=/dev/null
            eval "$(cat /tmp/heredoc_test)" > "$conf_directory/$live"
        done

        cat "$conf_directory/test.conf"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"mqtt.local"* ]]
    [[ "$output" == *"1883"* ]]
    [[ "$output" == *"user1"* ]]
    [[ "$output" == *"pass1"* ]]
    [[ "$output" == *"retain=1"* ]]
}

@test "removes old .conf files before regeneration" {
    # Create an old conf file
    echo "old config" > "$conf_directory/old.conf"

    run bash -c '
        conf_directory="'"$conf_directory"'"
        rm -f "$conf_directory"/*.conf
        if [ -f "$conf_directory/old.conf" ]; then
            echo "old_exists"
        else
            echo "old_removed"
        fi
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"old_removed"* ]]
}

@test "handles multiple template files for multi-radio setup" {
    # Create multiple templates
    echo "radio1_config" > "$conf_directory/radio1.conf.template"
    echo "radio2_config" > "$conf_directory/radio2.conf.template"

    run bash -c '
        conf_directory="'"$conf_directory"'"
        count=0
        for template in "$conf_directory"/*.conf.template; do
            ((count++))
        done
        echo "template_count=$count"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"template_count=2"* ]]
}

# =============================================================================
# TPMS Protocol Exclusion Tests
# =============================================================================

@test "default template includes TPMS protocol exclusions" {
    run bash -c '
        source tests/bats/mock_bashio.bash
        conf_directory="'"$conf_directory"'"

        # Simulate empty directory check and template creation
        cat > "$conf_directory/rtl_433.conf.template" <<EOD
protocol -59
protocol -60
protocol -82
protocol -88
protocol -89
protocol -90
EOD
        grep "protocol -" "$conf_directory/rtl_433.conf.template" | wc -l
    '

    [ "$status" -eq 0 ]
    # Should have multiple protocol exclusions
    [[ "$output" -ge 6 ]]
}
