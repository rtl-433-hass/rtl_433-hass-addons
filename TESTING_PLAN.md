# Testing Plan for rtl_433 Home Assistant Add-ons

## Executive Summary

This document proposes a comprehensive testing strategy for the four add-ons in this repository:
- `rtl_433` (stable SDR reader)
- `rtl_433-next` (development SDR reader)
- `rtl_433_mqtt_autodiscovery` (stable Home Assistant discovery)
- `rtl_433_mqtt_autodiscovery-next` (development discovery)

## Current State

### What IS Being Tested
- Linting: Shell scripts (shellcheck), Dockerfiles (hadolint), JSON, YAML, GitHub Actions (actionlint)
- Addon validation: Home Assistant add-on structure (frenck/action-addon-linter)
- Build verification: Test builds for all architectures (amd64, aarch64)
- Commit message format: Conventional commits

### What IS NOT Being Tested
- Functional/runtime behavior
- Integration with MQTT
- Configuration template processing
- Multi-radio scenarios
- Auto-discovery accuracy
- Container security scanning
- MQTT payload validation

---

## Proposed Testing Layers

### Layer 1: Unit Tests for Shell Scripts

**Goal**: Validate the logic in `run.sh` scripts without requiring Home Assistant or hardware.

#### 1.1 rtl_433/run.sh Tests

Create `rtl_433/tests/test_run.sh` using BATS (Bash Automated Testing System):

```
Test Cases:
├── Configuration Directory Creation
│   ├── Creates /config/rtl_433 if it doesn't exist
│   └── Skips creation if directory already exists
│
├── Template Processing
│   ├── Generates .conf from .conf.template files
│   ├── Substitutes ${host}, ${port}, ${username}, ${password}, ${retain} variables
│   ├── Handles multiple template files for multi-radio setup
│   └── Removes old .conf files before regeneration
│
├── Retain Flag Handling
│   ├── Converts "true" to 1
│   └── Leaves other values unchanged
│
├── Legacy Configuration Warning
│   ├── Shows deprecation warning when rtl_433_conf_file is set
│   └── Uses legacy file path correctly
│
└── Default Template Generation
    ├── Creates default template when directory is empty
    ├── Includes TPMS protocol exclusions
    └── Contains correct MQTT output line format
```

#### 1.2 rtl_433_mqtt_autodiscovery/run.sh Tests

Create `rtl_433_mqtt_autodiscovery/tests/test_run.sh`:

```
Test Cases:
├── Standalone Docker Mode
│   ├── Uses MQTT_HOST environment variable when set
│   ├── Applies default port 1883
│   ├── Applies default RTL_TOPIC rtl_433/+/events
│   ├── Applies default DISCOVERY_PREFIX homeassistant
│   └── Applies default DISCOVERY_INTERVAL 600
│
├── Log Level Handling
│   ├── Adds --quiet flag for quiet log level
│   ├── Adds --debug flag for debug log level
│   └── No extra flags for default log level
│
├── Optional Parameters
│   ├── Adds --retain when mqtt_retain is true
│   ├── Adds --force_update when force_update is true
│   ├── Adds -T suffix when device_topic_suffix is set
│   └── Omits optional flags when not configured
│
└── Command Construction
    └── Builds correct python3 command with all arguments
```

**Implementation Approach**:
- Mock `bashio::` functions to simulate Home Assistant environment
- Use BATS framework for structured test execution
- Create test fixtures for configuration scenarios

#### 1.3 Code Coverage with kcov

Use [kcov](https://github.com/SimonKagstrom/kcov) to measure shell script test coverage.

**Why kcov**:
- Native Linux tool, no Ruby dependency
- Multiple output formats: lcov HTML, Cobertura XML, JSON
- Direct integration with Codecov/Coveralls
- Available in Alpine Linux (`apk add kcov`)
- Works with BATS out of the box

**Coverage Workflow**:

```bash
# Install kcov (Ubuntu/Debian)
apt-get install kcov

# Run BATS tests with coverage collection
kcov --include-path=./rtl_433,./rtl_433_mqtt_autodiscovery \
     --exclude-pattern=tests/ \
     ./coverage \
     bats tests/

# Output structure:
# ./coverage/
# ├── index.html           # HTML report
# ├── coverage.json        # JSON summary
# ├── cobertura.xml        # Cobertura XML for CI tools
# └── bats/                # Per-file coverage data
```

**GitHub Actions Integration**:

```yaml
# .github/workflows/unit-tests.yml
name: Unit Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y kcov
          # Install BATS
          git clone https://github.com/bats-core/bats-core.git /tmp/bats
          sudo /tmp/bats/install.sh /usr/local
          # Install BATS helpers
          git clone https://github.com/bats-core/bats-support.git tests/bats/bats-support
          git clone https://github.com/bats-core/bats-assert.git tests/bats/bats-assert

      - name: Run tests with coverage
        run: |
          kcov --include-path=./rtl_433,./rtl_433_mqtt_autodiscovery \
               --exclude-pattern=tests/,bats-support,bats-assert \
               ./coverage \
               bats tests/

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          directory: ./coverage
          files: ./coverage/cobertura.xml
          fail_ci_if_error: false
          verbose: true

      - name: Upload coverage artifacts
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: ./coverage/
          retention-days: 30
```

**Coverage Thresholds**:

| File | Minimum Coverage |
|------|------------------|
| `rtl_433/run.sh` | 80% |
| `rtl_433_mqtt_autodiscovery/run.sh` | 80% |
| Overall | 75% |

**Enforcing Coverage in CI**:

```yaml
- name: Check coverage threshold
  run: |
    COVERAGE=$(jq '.percent_covered' coverage/coverage.json)
    if (( $(echo "$COVERAGE < 75" | bc -l) )); then
      echo "Coverage $COVERAGE% is below threshold of 75%"
      exit 1
    fi
    echo "Coverage: $COVERAGE%"
```

---

### Layer 2: Container Build & Smoke Tests

**Goal**: Verify containers build correctly and basic startup works.

#### 2.1 Build Verification Tests

Extend `.github/workflows/builder.yml`:

```yaml
Test Cases:
├── Docker Build Success
│   ├── Build completes without errors for amd64
│   ├── Build completes without errors for aarch64
│   └── Multi-stage build produces final image
│
├── Required Binaries Present
│   ├── rtl_433 binary exists and is executable
│   ├── Required SDR libraries are installed (librtlsdr, soapysdr)
│   └── Python + paho-mqtt installed (autodiscovery addon)
│
├── File Permissions
│   ├── run.sh is executable
│   └── Configuration files have correct ownership
│
└── Image Metadata
    ├── Labels match config.json
    └── Architecture labels are correct
```

#### 2.2 Smoke Tests

Create `.github/workflows/smoke-tests.yml`:

```yaml
Test Cases:
├── rtl_433 Container
│   ├── Container starts without crash (no hardware mode)
│   ├── Shows help output: `rtl_433 --help`
│   ├── Lists supported protocols: `rtl_433 -R help`
│   └── Exits gracefully when no SDR device found (expected behavior)
│
└── rtl_433_mqtt_autodiscovery Container
    ├── Container starts without crash
    ├── Python script is valid: `python3 -m py_compile /rtl_433_mqtt_hass.py`
    └── Shows help output when run with --help
```

---

### Layer 3: Integration Tests with Mock MQTT

**Goal**: Test end-to-end behavior with a real MQTT broker but simulated sensor data.

#### 3.1 MQTT Integration Test Infrastructure

Create `tests/integration/` directory:

```
tests/integration/
├── docker-compose.test.yml    # Test environment with Mosquitto
├── conftest.py                # pytest fixtures
├── test_mqtt_autodiscovery.py # Python integration tests
├── test_rtl433_mqtt_output.py # MQTT output format tests
└── fixtures/
    ├── sample_events.json     # Real rtl_433 event samples
    └── expected_discovery.json # Expected HA discovery payloads
```

#### 3.2 MQTT Autodiscovery Integration Tests

```python
Test Cases:
├── Device Discovery
│   ├── Publishes discovery config for temperature sensor
│   ├── Publishes discovery config for humidity sensor
│   ├── Publishes discovery config for battery status
│   ├── Creates unique device identifiers
│   └── Uses correct MQTT topics (homeassistant/sensor/...)
│
├── Event Processing
│   ├── Parses rtl_433 JSON event correctly
│   ├── Handles missing optional fields gracefully
│   ├── Processes events from multiple devices
│   └── Respects discovery_interval setting
│
├── MQTT Connection
│   ├── Connects with username/password authentication
│   ├── Reconnects on connection loss
│   └── Publishes with retain flag when configured
│
└── Topic Configuration
    ├── Subscribes to configured rtl_topic pattern
    ├── Publishes to configured discovery_prefix
    └── Applies device_topic_suffix correctly
```

#### 3.3 Mock Sensor Event Fixtures

Create sample rtl_433 events for testing:

```json
// fixtures/sample_events.json
[
  {
    "time": "2024-01-15T10:30:00",
    "model": "Acurite-Tower",
    "id": 12345,
    "channel": "A",
    "battery_ok": 1,
    "temperature_C": 22.5,
    "humidity": 45
  },
  {
    "time": "2024-01-15T10:30:01",
    "model": "LaCrosse-TX141THBv2",
    "id": 67890,
    "temperature_C": -5.2,
    "humidity": 80,
    "battery_ok": 0
  }
]
```

---

### Layer 4: Configuration Validation Tests

**Goal**: Ensure addon configurations are valid and consistent.

#### 4.1 Schema Validation Tests

Create `tests/config/test_config_schema.py`:

```python
Test Cases:
├── config.json Validation
│   ├── All required fields present (name, version, slug, etc.)
│   ├── Architectures match between addons
│   ├── Image URLs follow naming convention
│   ├── Schema matches options structure
│   └── Version format is valid (semver or "next")
│
├── build.json Validation
│   ├── Build args are valid
│   ├── Base images exist and are pullable
│   └── Architecture-specific images defined
│
├── Consistency Checks
│   ├── Stable and -next versions have same options schema
│   ├── CHANGELOG.md version matches config.json (stable only)
│   └── Documentation matches available options
│
└── Template Validation
    └── Default rtl_433.conf.template is syntactically valid
```

---

### Layer 5: Security Scanning

**Goal**: Detect vulnerabilities in container images and dependencies.

#### 5.1 Container Security Scanning

Add to CI pipeline:

```yaml
# .github/workflows/security-scan.yml
Tools:
├── Trivy - Container vulnerability scanning
│   ├── Scan built images for CVEs
│   ├── Check for outdated base images
│   └── Detect secrets in image layers
│
├── Grype - Dependency vulnerability scanning
│   ├── Scan Python dependencies (paho-mqtt)
│   └── Scan Alpine packages
│
└── Hadolint - Already implemented
    └── Dockerfile security best practices
```

---

### Layer 6: End-to-End Tests (Optional/Manual)

**Goal**: Validate complete workflow with real hardware (for maintainer use).

#### 6.1 Hardware-in-the-Loop Tests

```
Test Cases (Manual Execution):
├── SDR Device Detection
│   ├── RTL-SDR dongle detected correctly
│   ├── HackRF device detected correctly
│   └── Multiple devices handled
│
├── Signal Reception
│   ├── 433 MHz sensor data received
│   ├── JSON output formatted correctly
│   └── MQTT messages published
│
└── Home Assistant Integration
    ├── Devices appear in Home Assistant
    ├── Sensor values update correctly
    └── Entities have correct device classes
```

---

## Implementation Recommendations

### Phase 1: Foundation (Recommended First)

1. **Add BATS framework for shell script testing**
   - Create `tests/` directory structure
   - Add BATS as a test dependency
   - Implement mock bashio functions

2. **Set up kcov for code coverage**
   - Configure kcov to track run.sh coverage
   - Integrate with Codecov for PR coverage reports
   - Set initial coverage thresholds (start at 50%, increase to 80%)

3. **Add container smoke tests to CI**
   - Verify binaries exist and are executable
   - Run `--help` commands to verify basic functionality

4. **Add configuration schema validation**
   - Use Python/jsonschema or similar
   - Run on every PR

### Phase 2: Integration Tests

5. **Create docker-compose test environment**
   - Mosquitto MQTT broker
   - Mock rtl_433 event publisher
   - Autodiscovery addon under test

6. **Implement MQTT integration tests with pytest**
   - Test discovery payload generation
   - Test event processing logic

### Phase 3: Security & Polish

7. **Add Trivy container scanning**
   - Run on release builds
   - Block on critical vulnerabilities

8. **Enhance coverage reporting**
   - Add coverage badges to README
   - Configure coverage trend tracking in Codecov
   - Set up PR comments with coverage diff

---

## Proposed CI Workflow Structure

```
.github/workflows/
├── builder.yml           # (existing) Build verification
├── addon-linter.yml      # (existing) HA addon linting
├── shellcheck.yml        # (existing) Shell linting
├── hadolint.yml          # (existing) Dockerfile linting
├── actionlint.yml        # (existing) Actions linting
├── json-lint.yml         # (existing) JSON linting
│
├── unit-tests.yml        # (new) BATS shell script tests
├── smoke-tests.yml       # (new) Container startup tests
├── integration-tests.yml # (new) MQTT integration tests
├── config-validation.yml # (new) Schema & consistency checks
└── security-scan.yml     # (new) Trivy container scanning
```

---

## Test File Structure

```
rtl_433-hass-addons/
├── tests/
│   ├── bats/                    # BATS test helpers
│   │   ├── test_helper.bash
│   │   └── mock_bashio.bash     # Bashio function mocks
│   ├── integration/
│   │   ├── docker-compose.test.yml
│   │   ├── conftest.py
│   │   ├── test_autodiscovery.py
│   │   └── fixtures/
│   │       ├── sample_events.json
│   │       └── expected_discovery.json
│   └── config/
│       └── test_config_schema.py
│
├── rtl_433/
│   └── tests/
│       └── test_run.bats        # Unit tests for run.sh
│
└── rtl_433_mqtt_autodiscovery/
    └── tests/
        └── test_run.bats        # Unit tests for run.sh
```

---

## Dependencies to Add

### Development Dependencies

```yaml
# For BATS testing
- bats-core (Bash testing framework)
- bats-support (Test helpers)
- bats-assert (Assertion library)

# For code coverage
- kcov (Bash/Python coverage tool)
- jq (JSON parsing for coverage threshold checks)

# For Python integration tests
- pytest
- pytest-docker
- paho-mqtt (already used by addon)

# For security scanning
- trivy (container scanning)
```

### CI Dependencies

```yaml
# GitHub Actions
- actions/setup-python
- docker/setup-buildx-action
- aquasecurity/trivy-action
- codecov/codecov-action@v4
```

---

## Success Metrics

| Metric | Target | Measurement Tool |
|--------|--------|------------------|
| Shell script line coverage | ≥80% of run.sh lines | kcov + Codecov |
| Shell script branch coverage | ≥70% of branches | kcov + Codecov |
| Integration test coverage | All supported sensor types | pytest-cov |
| Build success rate | 100% on main branch | GitHub Actions |
| Security scan pass rate | No critical/high CVEs | Trivy |
| CI pipeline duration | <15 minutes total | GitHub Actions |
| Coverage trend | No regression on PRs | Codecov PR checks |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| No real SDR hardware in CI | Can't test actual reception | Use mock events, document manual tests |
| bashio mocking complexity | Tests may diverge from reality | Keep mocks minimal, test in HA environment periodically |
| Flaky MQTT tests | CI unreliability | Use deterministic waits, retry logic |
| Test maintenance burden | Slow development velocity | Focus on high-value tests, avoid over-testing |

---

## Next Steps

1. Review and approve this testing plan
2. Create GitHub issue for Phase 1 implementation
3. Set up BATS framework and initial shell tests
4. Add smoke tests to CI pipeline
5. Iterate with integration tests in Phase 2
