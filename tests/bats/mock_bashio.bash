#!/usr/bin/env bash
# Mock bashio functions for testing Home Assistant addon scripts
# These mocks simulate the bashio library behavior without requiring Home Assistant

# Configuration storage - set these in your tests to control behavior
declare -A MOCK_BASHIO_CONFIG=()
declare -A MOCK_BASHIO_SERVICES=()
declare -a MOCK_BASHIO_LOG_MESSAGES=()
MOCK_MQTT_AVAILABLE="true"

# Reset all mocks to default state
mock_bashio_reset() {
    MOCK_BASHIO_CONFIG=()
    MOCK_BASHIO_SERVICES=()
    MOCK_BASHIO_LOG_MESSAGES=()
    MOCK_MQTT_AVAILABLE="true"
}

# Set a config value
# Usage: mock_bashio_set_config "key" "value"
mock_bashio_set_config() {
    MOCK_BASHIO_CONFIG["$1"]="$2"
}

# Set a service value
# Usage: mock_bashio_set_service "mqtt" "host" "localhost"
mock_bashio_set_service() {
    local service="$1"
    local key="$2"
    local value="$3"
    MOCK_BASHIO_SERVICES["${service}_${key}"]="$value"
}

# Set MQTT availability
# Usage: mock_bashio_set_mqtt_available "true" or "false"
mock_bashio_set_mqtt_available() {
    MOCK_MQTT_AVAILABLE="$1"
}

# bashio::services.available - check if a service is available
bashio::services.available() {
    local service="$1"
    if [[ "$service" == "mqtt" && "$MOCK_MQTT_AVAILABLE" == "true" ]]; then
        return 0
    fi
    return 1
}

# bashio::services - get a service configuration value
bashio::services() {
    local service="$1"
    local key="$2"
    local lookup_key="${service}_${key}"

    if [[ -n "${MOCK_BASHIO_SERVICES[$lookup_key]:-}" ]]; then
        echo "${MOCK_BASHIO_SERVICES[$lookup_key]}"
    else
        # Return sensible defaults for common MQTT settings
        case "$key" in
            host) echo "localhost" ;;
            port) echo "1883" ;;
            username) echo "mqtt_user" ;;
            password) echo "mqtt_pass" ;;
            *) echo "" ;;
        esac
    fi
}

# bashio::config - get a configuration value
bashio::config() {
    local key="$1"
    if [[ -n "${MOCK_BASHIO_CONFIG[$key]:-}" ]]; then
        echo "${MOCK_BASHIO_CONFIG[$key]}"
    else
        # Return sensible defaults
        case "$key" in
            retain) echo "true" ;;
            mqtt_port) echo "1883" ;;
            rtl_topic) echo "rtl_433/+/events" ;;
            discovery_prefix) echo "homeassistant" ;;
            discovery_interval) echo "600" ;;
            log_level) echo "default" ;;
            *) echo "" ;;
        esac
    fi
}

# bashio::config.true - check if a config value is true
bashio::config.true() {
    local key="$1"
    local value="${MOCK_BASHIO_CONFIG[$key]:-false}"
    [[ "$value" == "true" ]]
}

# bashio::config.false - check if a config value is false
bashio::config.false() {
    local key="$1"
    local value="${MOCK_BASHIO_CONFIG[$key]:-true}"
    [[ "$value" == "false" ]]
}

# bashio::log.info - log an info message
bashio::log.info() {
    MOCK_BASHIO_LOG_MESSAGES+=("[INFO] $*")
    # Optionally print for debugging: echo "[INFO] $*" >&2
}

# bashio::log.warning - log a warning message
bashio::log.warning() {
    MOCK_BASHIO_LOG_MESSAGES+=("[WARNING] $*")
    # Optionally print for debugging: echo "[WARNING] $*" >&2
}

# bashio::log.error - log an error message
bashio::log.error() {
    MOCK_BASHIO_LOG_MESSAGES+=("[ERROR] $*")
    # Optionally print for debugging: echo "[ERROR] $*" >&2
}

# bashio::log.debug - log a debug message
bashio::log.debug() {
    MOCK_BASHIO_LOG_MESSAGES+=("[DEBUG] $*")
}

# Helper to check if a log message was recorded
# Usage: mock_bashio_log_contains "expected message substring"
mock_bashio_log_contains() {
    local expected="$1"
    for msg in "${MOCK_BASHIO_LOG_MESSAGES[@]}"; do
        if [[ "$msg" == *"$expected"* ]]; then
            return 0
        fi
    done
    return 1
}

# Helper to get all log messages
mock_bashio_get_logs() {
    printf '%s\n' "${MOCK_BASHIO_LOG_MESSAGES[@]}"
}

# Export all functions so they're available in subshells
export -f bashio::services.available
export -f bashio::services
export -f bashio::config
export -f bashio::config.true
export -f bashio::config.false
export -f bashio::log.info
export -f bashio::log.warning
export -f bashio::log.error
export -f bashio::log.debug
export -f mock_bashio_reset
export -f mock_bashio_set_config
export -f mock_bashio_set_service
export -f mock_bashio_set_mqtt_available
export -f mock_bashio_log_contains
export -f mock_bashio_get_logs
