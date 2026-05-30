#!/usr/bin/env bash
# Test helper for BATS tests
# Loads bats-support and bats-assert, and sets up common test environment

# Get the directory where this script is located
BATS_TEST_DIRNAME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # REPO_ROOT is available for use in test files
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# Load bats-support and bats-assert from git submodules
# These are located in tests/bats/bats-support and tests/bats/bats-assert
if [[ -d "${BATS_TEST_DIRNAME}/bats-support" ]]; then
    load "${BATS_TEST_DIRNAME}/bats-support/load"
else
    echo "Warning: bats-support not found. Run 'git submodule update --init --recursive'" >&2
fi

if [[ -d "${BATS_TEST_DIRNAME}/bats-assert" ]]; then
    load "${BATS_TEST_DIRNAME}/bats-assert/load"
else
    echo "Warning: bats-assert not found. Run 'git submodule update --init --recursive'" >&2
fi

# Load mock bashio functions
load "${BATS_TEST_DIRNAME}/mock_bashio.bash"

# Create a temporary directory for each test
setup_temp_dir() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

# Clean up temporary directory after each test
teardown_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Helper to create a mock config directory structure
setup_config_dir() {
    mkdir -p "${TEST_TEMP_DIR}/config/rtl_433"
    export conf_directory="${TEST_TEMP_DIR}/config/rtl_433"
}

# Helper to capture command that would be executed
# Usage: capture_command command args...
# The command and args are stored in CAPTURED_COMMAND array
CAPTURED_COMMANDS=()
capture_command() {
    CAPTURED_COMMANDS+=("$*")
}

# Reset captured commands
reset_captured_commands() {
    CAPTURED_COMMANDS=()
}

# Check if a command was captured
# Usage: assert_command_captured "expected command string"
assert_command_captured() {
    local expected="$1"
    for cmd in "${CAPTURED_COMMANDS[@]}"; do
        if [[ "$cmd" == *"$expected"* ]]; then
            return 0
        fi
    done
    echo "Expected command not found: $expected"
    echo "Captured commands: ${CAPTURED_COMMANDS[*]}"
    return 1
}
