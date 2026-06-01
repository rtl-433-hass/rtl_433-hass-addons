---
id: 3
group: "testing-infrastructure"
dependencies: []
status: "pending"
created: 2026-06-01
skills:
  - python
---
# Create the add-on config validator `tests/config/validate_configs.py`

## Objective
Provide a standard-library-only Python script that validates both add-ons' `config.json`/`build.json` for required fields, architecture coverage, image registry, schema/options consistency, the HTTP `ports` map, and discovery-related flags. It exits non-zero with clear messages on any problem.

## Skills Required
- `python` — standard-library JSON parsing and validation logic.

## Meaningful Test Strategy Guidelines

Your critical mantra for test generation is: "write a few tests, mostly integration".

**Definition of "Meaningful Tests":** Tests that verify custom business logic and edge cases specific to the application, not framework functionality.

**When TO Write Tests / When NOT to:** Validate the project's own configuration invariants (cross-file drift, required fields). Do not re-validate generic JSON parsing or add checks for hypothetical fields not present in the configs.

This validator IS the test: it asserts repository-specific invariants (ports coupled to `run.sh` constants, schema↔options agreement). Keep checks tied to what the add-ons actually declare today; avoid speculative rules.

## Acceptance Criteria
- [ ] `tests/config/validate_configs.py` exists, uses only the Python standard library (no `jsonschema` or other third-party imports), and is runnable as `python3 tests/config/validate_configs.py`.
- [ ] Validates both `rtl_433` and `rtl_433-next`.
- [ ] For each add-on `config.json`: parses; has required fields (`name`, `version`, `slug`, `description`, `arch`, `image`); `arch` includes `aarch64` and `amd64`; `version` is dotted-numeric semver **or** the literal `next`; `image` starts with `ghcr.io/`.
- [ ] For each add-on `build.json`: parses; has `build_from` with both `aarch64` and `amd64` keys.
- [ ] `schema` keys and `options` keys are mutually consistent (report any key in one but not the other).
- [ ] The `ports` map is exactly the range 8433–8442 (host and container), matching `run.sh` `BASE_PORT=8433`/`MAX_RADIOS=10`; `discovery` includes `"rtl_433"`; and `hassio_api`, `usb`, `udev` are present and truthy.
- [ ] Does **not** require a `Dockerfile` or `run.sh` to exist in an add-on directory (so `rtl_433-next` validates).
- [ ] Exits 0 on the current repo; exits non-zero (with a per-add-on error report) when an invariant is violated.

## Technical Requirements
Python 3 standard library only (`json`, `sys`, `pathlib`). Resolve add-on directories relative to the repository root (the script lives in `tests/config/`, so the repo root is two levels up).

## Input Dependencies
None. (Independent of `run.sh`; references its constants only as the expected ports range.)

## Output Artifacts
- `tests/config/validate_configs.py`.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

1. **Base on the PR #42 validator but adapt.** Structure: an `ADDONS = ["rtl_433", "rtl_433-next"]` list, `load_json(path)`, a per-add-on `validate_config_json()` and `validate_build_json()`, accumulate error strings, print them, and `sys.exit(1)` if any.

2. **Repo root resolution** (script in `tests/config/`):
   ```python
   from pathlib import Path
   REPO_ROOT = Path(__file__).resolve().parents[2]
   ```

3. **Required config fields:** `["name", "version", "slug", "description", "arch", "image"]`.

4. **Arch check:** ensure both `"aarch64"` and `"amd64"` are in `config["arch"]`.

5. **Version check:** accept the literal `"next"`, otherwise require all dot-separated parts to be digits (e.g. `0.2.0`). Reject anything else with a clear message.

6. **Image check:** `config["image"].startswith("ghcr.io/")`.

7. **schema/options consistency:** when both present, compute `set(options) ^ set(schema)` and report each differing key (missing in schema OR missing in options).

8. **Ports check (the new, repo-specific invariant):** expected host ports and container targets are `8433..8442` inclusive. Example:
   ```python
   EXPECTED_PORTS = {f"{p}/tcp": p for p in range(8433, 8443)}
   if config.get("ports") != EXPECTED_PORTS:
       errors.append(f"{addon}: 'ports' must be exactly {EXPECTED_PORTS} "
                     f"(matches run.sh BASE_PORT=8433/MAX_RADIOS=10); got {config.get('ports')}")
   ```

9. **Discovery/flags check:**
   - `"rtl_433"` in `config.get("discovery", [])`.
   - `config.get("hassio_api") is True`, `config.get("usb") is True`, `config.get("udev") is True`.
   Report a clear error for each missing/false one.

10. **build.json:** parse and require `build_from` to be a dict containing both `aarch64` and `amd64` keys.

11. **Error handling:** if `config.json` (or `build.json`) is missing or unparseable, record an error for that add-on and continue to the next; do not crash. At the end, print all errors grouped per add-on and `sys.exit(1 if errors else 0)`. On success, print a short confirmation line per add-on.

12. **No Dockerfile/run.sh assumptions** — only read `config.json` and `build.json`.

13. Verify locally: `python3 tests/config/validate_configs.py; echo "exit=$?"` → `exit=0`. Then break a ports value, confirm non-zero, and revert. Commit, e.g. `test(addons): add config.json/build.json validator`.
</details>
