---
id: 5
group: "ci"
dependencies: [2, 3, 4]
status: "completed"
created: 2026-06-01
skills:
  - documentation
---
# Update `AGENTS.md` Testing section and add `tests/README.md`

## Objective
Keep contributor/assistant documentation accurate now that automated tests live outside pre-commit. Describe the three test layers and how to run them, and add a short `tests/README.md`.

## Skills Required
- `documentation` — concise technical writing in Markdown.

## Acceptance Criteria
- [ ] `AGENTS.md` "Testing" section no longer claims tests are run solely via pre-commit; it describes the BATS unit tests, the container smoke test, and the config validator, with the commands to run them locally.
- [ ] A new `tests/README.md` documents the layout (`tests/rtl_433/`, `tests/config/`), how to run each layer, and the `SYSFS_USB_BASE` fixture convention.
- [ ] No end-user `README.md` changes (this is contributor/CI-facing only).
- [ ] Markdown is consistent with existing repo docs; `pre-commit run --all-files` passes (trailing-whitespace/end-of-file fixers).

## Technical Requirements
Markdown only. Note that pre-commit still runs the linters; the new test suite runs in CI (and can be run locally).

## Input Dependencies
- Tasks 2, 3, 4: the tests, validator, and workflows must exist so the docs describe the real layout and commands.

## Output Artifacts
- Updated `AGENTS.md`.
- New `tests/README.md`.

## Implementation Notes

<details>
<summary>Detailed guidance</summary>

1. **`AGENTS.md` "Testing" section.** It currently reads roughly: "Rely on pre-commit hooks to run all checks automatically." Replace/expand it to something like:
   - Pre-commit hooks still run the linters (shellcheck, hadolint, actionlint, yaml/json) automatically.
   - Automated tests run in CI on every push/PR and can be run locally:
     - Unit tests (BATS) for `rtl_433/run.sh` helper functions: `bats -r tests/`
     - Container smoke test: build `./rtl_433` and check the binary + baked-in configs (see `.github/workflows/smoke-tests.yml`).
     - Config validation: `python3 tests/config/validate_configs.py`
   - Note that `run.sh` is `main`-guarded so its functions can be sourced by tests.
   Keep it brief and factual; do not duplicate the full workflow YAML.

2. **`tests/README.md`** — short, e.g.:
   - Layout: `tests/rtl_433/test_run.bats` (BATS unit tests), `tests/config/validate_configs.py` (config validator).
   - Running: `bats -r tests/` and `python3 tests/config/validate_configs.py`.
   - Fixture convention: the BATS tests build a mock sysfs tree and point `SYSFS_USB_BASE` at it to exercise `enumerate_rtlsdr_devices` without real hardware.
   - Prerequisites: `bats` (install via `apt-get install -y bats` or `bats-core`); Python 3 standard library only.

3. Run `pre-commit run --all-files` to satisfy whitespace/EOF fixers. Commit, e.g. `docs: document the automated test suite`.
</details>
