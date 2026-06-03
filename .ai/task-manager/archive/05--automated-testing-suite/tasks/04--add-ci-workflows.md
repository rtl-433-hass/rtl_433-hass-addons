---
id: 4
group: "ci"
dependencies: [2, 3]
status: "completed"
created: 2026-06-01
skills:
  - github-actions
---
# Add the three CI workflows (unit tests, smoke tests, config validation)

## Objective
Wire the test suite into CI with three small, single-concern workflow files matching the repository's existing style. All trigger on push to `main` and on pull requests, use the repo-standard `actions/checkout` pin, and introduce **no** new third-party GitHub Actions.

## Skills Required
- `github-actions` — workflow YAML, runners, pinned action references.

## Acceptance Criteria
- [ ] `.github/workflows/unit-tests.yml`: checkout, install `bats` (`sudo apt-get update && sudo apt-get install -y bats`), run `bats -r tests/` (the `-r` is required — bats 1.11 does not recurse into `tests/rtl_433/` without it).
- [ ] `.github/workflows/smoke-tests.yml`: checkout, `docker build` the `rtl_433` image, then assert the binary works and the baked-in config files exist (see notes).
- [ ] `.github/workflows/config-validation.yml`: checkout, run `python3 tests/config/validate_configs.py` using the runner's system Python (no `setup-python`, no `pip install`).
- [ ] All three use `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6` (the repo standard) and introduce no other third-party actions.
- [ ] All three trigger `on: push: branches: [main]` and `on: pull_request`.
- [ ] `actionlint` passes on all three (verify via `pre-commit run --all-files`).

## Technical Requirements
GitHub-hosted `ubuntu` runner (Docker preinstalled; system `python3` present). No `setup-python`/`setup-buildx` actions (none are pinned in the repo, so avoid introducing new references per `AGENTS.md`).

## Input Dependencies
- Task 2: `tests/rtl_433/test_run.bats` exists (consumed by `unit-tests.yml`).
- Task 3: `tests/config/validate_configs.py` exists (consumed by `config-validation.yml`).
- (`smoke-tests.yml` depends only on the existing `rtl_433/Dockerfile` + `run.sh`.)

## Output Artifacts
- `.github/workflows/unit-tests.yml`
- `.github/workflows/smoke-tests.yml`
- `.github/workflows/config-validation.yml`

## Implementation Notes

<details>
<summary>Workflow contents and conventions</summary>

**Conventions (match existing workflows like `shellcheck.yml`):** YAML starts with `---`; `on: { push: { branches: [main] }, pull_request: }`; `runs-on: ubuntu-latest` (or `ubuntu-24.04` — match whichever the existing workflows use; prefer `ubuntu-latest` for consistency with `build-addon.yml`). Use the exact checkout pin below.

**`unit-tests.yml`:**
```yaml
---
name: Unit Tests
on:
  push:
    branches: [main]
  pull_request:
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6
      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats
      - name: Run BATS tests
        run: bats -r tests/
```

**`smoke-tests.yml`:** build the real image, then assert. `rtl_433 --help` exits non-zero by design, so capture output and grep a stable token.
```yaml
---
name: Smoke Tests
on:
  push:
    branches: [main]
  pull_request:
jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6
      - name: Build rtl_433 image
        run: |
          docker build \
            --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
            --tag rtl_433-test:latest ./rtl_433
      - name: rtl_433 binary exists
        run: docker run --rm rtl_433-test:latest which rtl_433
      - name: rtl_433 --help runs
        run: |
          out=$(docker run --rm rtl_433-test:latest rtl_433 --help 2>&1 || true)
          echo "$out"
          echo "$out" | grep -qi "Receive frequency"
      - name: rtl_433 lists protocols
        run: docker run --rm rtl_433-test:latest rtl_433 -R help 2>&1 | head -20
      - name: run.sh is executable
        run: docker run --rm rtl_433-test:latest test -x /run.sh
      - name: baked-in default config exists
        run: docker run --rm rtl_433-test:latest test -f /etc/rtl_433/rtl_433.defaults.conf
      - name: TPMS disables config is present and non-empty
        run: |
          docker run --rm rtl_433-test:latest sh -c \
            'test -s /etc/rtl_433/rtl_433.tpms-disables.conf && grep -q "^protocol -" /etc/rtl_433/rtl_433.tpms-disables.conf'
```
Notes: `ghcr.io/home-assistant/amd64-base:3.21` matches `rtl_433/build.json`'s amd64 base. Confirm the `--help` token by checking the Dockerfile/binary if `Receive frequency` ever fails; `-f`'s help text contains "Receive frequency". The build compiles rtl_433 from source and is the heaviest job — that is expected and acceptable on PR/push.

**`config-validation.yml`:**
```yaml
---
name: Config Validation
on:
  push:
    branches: [main]
  pull_request:
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6
      - name: Validate add-on configs
        run: python3 tests/config/validate_configs.py
```

**Validation:** run `pre-commit run --all-files` (actionlint must pass on all three). If actionlint flags `pull_request:` with no value, write it as `pull_request: {}` or with a `branches`/empty mapping per actionlint's preference — match how other repo workflows express PR triggers. Commit, e.g. `ci: add unit, smoke, and config-validation workflows`.
</details>
