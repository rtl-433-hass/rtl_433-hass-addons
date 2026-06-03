---
id: 1
group: "image"
dependencies: []
status: "completed"
created: 2026-06-02
skills:
  - docker
  - github-actions
---
# Add rtl-sdr and gnuplot to the image and smoke-test them

## Objective
Make `rtl_test`, `rtl_power`, and a PNG plotter (`gnuplot`) available in the runtime image, and assert their presence in the smoke-test workflow so a missing tool fails CI rather than at runtime.

## Skills Required
- `docker` — editing the Alpine-based multi-stage `rtl_433/Dockerfile`.
- `github-actions` — extending `.github/workflows/smoke-tests.yml`.

## Acceptance Criteria
- [ ] The final-stage `apk add` in `rtl_433/Dockerfile` installs `rtl-sdr` (provides `rtl_test` and `rtl_power`) and `gnuplot`.
- [ ] The Dockerfile still passes `hadolint` (follow existing DL3018 ignore convention; do not pin versions).
- [ ] `.github/workflows/smoke-tests.yml` asserts `rtl_test`, `rtl_power`, and `gnuplot` are present in the built image (mirroring the existing `which rtl_433` step).
- [ ] `pre-commit run --all-files` passes for the changed files (hadolint, actionlint).

## Technical Requirements
Alpine `apk` packages: `rtl-sdr`, `gnuplot`. GitHub Actions workflow steps using the already-built `rtl_433-test:latest` image.

## Input Dependencies
None.

## Output Artifacts
- Updated `rtl_433/Dockerfile` with the new runtime packages.
- New smoke-test assertions.

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. In `rtl_433/Dockerfile`, locate the **final stage** `apk add` (the one after `FROM $BUILD_FROM`, currently installing `libusb hackrf librtlsdr soapy-sdr sed`, around lines 67-72). Add `rtl-sdr` and `gnuplot` to that same `apk add --no-cache` list (one package per line, keeping alphabetical-ish ordering and the trailing backslashes consistent). Keep the existing `# hadolint ignore=DL3018` comment above it — do NOT pin versions (Alpine drops superseded versions).
   - Note: `rtl-sdr` is the Alpine package that ships the CLI tools (`rtl_test`, `rtl_power`, etc.); `librtlsdr` (already present) is only the library.
2. In `.github/workflows/smoke-tests.yml`, after the existing `rtl_433 binary exists` step, add steps that run on `rtl_433-test:latest`:
   - `docker run --rm rtl_433-test:latest which rtl_test`
   - `docker run --rm rtl_433-test:latest which rtl_power`
   - `docker run --rm rtl_433-test:latest which gnuplot`
   Use the same step style/indentation as the existing `which rtl_433` step.
3. Run `pre-commit run --all-files` and fix any hadolint/actionlint findings. Do not introduce a new action reference; only `run:` steps are added.

Do NOT touch the builder stages or the SoapyHackRF build. Only the final runtime stage's package list changes.
</details>
