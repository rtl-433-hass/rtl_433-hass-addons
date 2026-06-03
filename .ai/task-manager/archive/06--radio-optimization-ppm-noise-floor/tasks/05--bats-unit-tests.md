---
id: 5
group: "tests"
dependencies: [3, 4]
status: "completed"
created: 2026-06-02
skills:
  - bash
---
# BATS unit tests for the new run.sh helpers

## Objective
Add meaningful BATS unit tests for the new pure helpers introduced in Tasks 3 and 4, following the existing `tests/rtl_433/test_run.bats` conventions and the project's "write a few tests, mostly integration" mantra.

## Skills Required
- `bash` — BATS tests sourcing `run.sh` helpers (the file is `main()`-guarded so sourcing runs no entrypoint).

## Acceptance Criteria
- [ ] Tests cover the custom logic, not the external tools:
  - `parse_rtl_test_ppm` returns the final cumulative PPM (including a negative value) from sample `rtl_test` output, and returns empty for output with no PPM line.
  - PPM cache round-trip: `write_ppm_cache` then `read_ppm_cache` returns the same integer using a temp `DATA_DIR`; `read_ppm_cache` rejects a non-integer / missing file.
  - `override_has_ppm_error` is true for a file containing a `ppm_error` line and false otherwise.
  - `parse_noise_bands` expands `433.92M,868M,915M` into the expected `lo:hi:bin` triples and skips a malformed entry.
  - `rtl_power_stats` computes min/median/peak from a small sample CSV fixture.
- [ ] Tests use `DATA_DIR`/`SYSFS_USB_BASE`-style temp seams (no writes outside the temp dir).
- [ ] `bats -r tests/` passes (all existing and new tests).

## Technical Requirements
BATS. Sample fixtures for `rtl_test -p` output and an `rtl_power` CSV. The helpers are sourced from `rtl_433/run.sh`.

## Input Dependencies
- Tasks 3 and 4: the helper functions under test must exist with the documented names/behaviors.

## Output Artifacts
- New test cases in `tests/rtl_433/test_run.bats` (and any small fixture files under `tests/`).

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. Read the existing `tests/rtl_433/test_run.bats` and `tests/README.md` to match the `setup()` pattern (it sources `run.sh`, sets `SYSFS_USB_BASE`/`DATA_DIR` to temp dirs, etc.). Reuse that harness.
2. Add `@test` cases for each helper listed in the acceptance criteria. Keep fixtures inline (here-strings/heredocs) or as small files under `tests/` consistent with existing fixtures.
   - For `parse_rtl_test_ppm`, feed a multi-line string containing several `cumulative PPM: N` lines and assert the LAST one is returned; add a case with a negative value; add a no-match case returning empty.
   - For the cache, set `DATA_DIR="$BATS_TEST_TMPDIR/data"`, call the writer then reader; assert equality; assert rejection of a corrupt value.
   - For `parse_noise_bands`, assert the exact triples for the default band string and that a junk token is dropped.
   - For `rtl_power_stats`, craft a tiny CSV with known dB values and assert the min/median/peak.
3. If a helper name differs slightly from this task's wording, align the test to the actual function name in `run.sh` (the implementation is the source of truth) but keep the same coverage.
4. Run `bats -r tests/` and `pre-commit run --all-files`.

Do NOT write tests that invoke the real `rtl_test`/`rtl_power`/`gnuplot` binaries (no hardware in CI) — test only the pure parsing/caching helpers. The binary presence is covered by the smoke test (Task 1).
</details>
