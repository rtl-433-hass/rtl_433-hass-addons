---
id: 3
group: "runsh"
dependencies: [2]
status: "pending"
created: 2026-06-02
skills:
  - bash
complexity_score: 4.5
complexity_notes: "Adds three pure helpers plus per-radio main() integration with device selection, a slow external tool, /data caching, and config injection. Kept as one task because it all lives in run.sh."
---
# Implement PPM offset calibration in run.sh

## Objective
When `correct_ppm_offset` is on, measure each radio's PPM once with `rtl_test`, cache it under `/data`, reuse it on later boots, inject it as a `ppm_error` directive into the rendered config, log the active offset, and respect a manually-set `ppm_error` in an override (skip auto for that radio).

## Skills Required
- `bash` — editing `rtl_433/run.sh` in its existing `main()`-guarded, helper-factored style.

## Acceptance Criteria
- [ ] New **pure** helpers (sourceable, no side effects beyond the cache file) are added near the other helpers:
  - parse the final cumulative PPM integer from captured `rtl_test` output;
  - read / write the per-radio PPM cache file under `DATA_DIR`;
  - detect whether an override file already contains a `ppm_error` directive.
- [ ] `main()` reads `correct_ppm_offset` (via `bashio::config.true`) into a global, defaulting off.
- [ ] In the per-dongle enumeration loop, before `launch_radio`, when the option is on:
  - if the radio's override `<id>.conf` already declares `ppm_error`, skip `rtl_test`, inject nothing, and log that auto-PPM was skipped due to a manual value;
  - else reuse a cached value if present, otherwise run `rtl_test` for ~180s (select the dongle by serial when usable, else by enumeration index), parse the cumulative PPM, and persist it (value + measurement date);
  - inject `ppm_error <n>` into the rendered config and log the active offset (e.g. `Radio <id>: PPM offset <n> (measured <date> / cached)`).
- [ ] A missing/empty/unparseable measurement is non-fatal: log a warning and launch the radio without correction.
- [ ] With the option off, the rendered config and logs are byte-for-byte unchanged from today.
- [ ] `pre-commit run --all-files` (shellcheck) passes; sourcing `run.sh` does not execute `main`.

## Technical Requirements
`rtl_test -d <serial|index> -p` (cumulative PPM after ~5s warmup). rtl_433 `ppm_error <n>` config directive. Existing globals: `conf_directory=/config`, `render_dir=/tmp/rtl_433`, `DATA_DIR` (defaults `/data`, overridable for tests), the `rtlsdr_devices` array, and `_serial_is_usable`.

## Input Dependencies
- Task 2: the `correct_ppm_offset` option must exist in the schema.

## Output Artifacts
- New PPM helper functions in `run.sh`.
- PPM measurement/caching/injection wired into `main()`'s launch path.

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. **Constants** (top of file, near the other config-path constants): add a PPM sampling-duration constant, e.g. `PPM_CALIBRATION_SECONDS=180`, and a cache dir under DATA_DIR, e.g. `ppm_cache_dir="${DATA_DIR}/ppm"`.
2. **Pure helpers** (place above `main`, alongside `_serial_is_usable`/`radio_match_id`, so BATS can source them; keep them side-effect-free except the cache writer):
   - `parse_rtl_test_ppm <text>`: from captured `rtl_test -p` output, extract the LAST "cumulative PPM" integer. `rtl_test` prints lines like `cumulative PPM: 2` periodically; grab the final one with `grep`/`sed`/`tail -1`. Print just the integer (may be negative). Print nothing if none found.
   - `ppm_cache_path <id>`: print `${ppm_cache_dir}/<id>.ppm`.
   - `read_ppm_cache <id>`: print the cached integer if the file exists and is a valid (optionally signed) integer; else print nothing / return non-zero.
   - `write_ppm_cache <id> <ppm>`: `mkdir -p "$ppm_cache_dir"`; write the integer (you may also write a `# measured <date>` companion or a second line — keep it parseable). Best-effort; warn on failure.
   - `override_has_ppm_error <file>`: return 0 if the file exists and contains a line matching `^[[:space:]]*ppm_error[[:space:]]`, else non-zero. (Mirror the existing `grep -qE '^[[:space:]]*device[[:space:]]'` style used for the device line.)
3. **Read option** in `main()` near the other `bashio::config.true` reads: set `correct_ppm_offset="true"|"false"`.
4. **Measurement function** `resolve_ppm_for_radio <selector> <id> <override_file>` (defined inside `main` or as a helper that reads globals): implements the decision order in the acceptance criteria. For the actual measurement, run `rtl_test` against the device for the fixed window and capture output. Because `rtl_test -p` runs until interrupted, bound it, e.g. `timeout "${PPM_CALIBRATION_SECONDS}" rtl_test -d "<sel>" -p 2>&1` (it will exit non-zero on timeout — that is expected; still parse the captured output). The `<sel>` is the serial when `_serial_is_usable` is true, else the enumeration index `$i` (same logic already used to build the rtl_433 `device` selector — note rtl_433 uses `:serial` but the rtl-sdr tools take a bare serial for `-d`). Log progress before the (slow) call so the user sees why startup is paused.
5. **Inject** the resolved PPM into the rendered config: extend `launch_radio` (or pass the value in) so that when a non-empty ppm is resolved, an `ppm_error <n>` line is written into the rendered config. Simplest: append `echo "ppm_error <n>"` in the same here-doc block that emits `output kv`/`output log`. The order does not matter for the no-manual case (the override has no `ppm_error`). Use a per-radio global array or a parameter — match how `radio_ports`/`radio_tags` are threaded.
6. **Logging**: always log the active offset on startup for each radio when correction is on (measured vs cached vs skipped-manual).
7. Guard everything behind `correct_ppm_offset == "true"`; when off, do not call any new code so existing behavior/rendered output is identical.
8. Run `shellcheck`/`pre-commit` and `bats -r tests/` (existing tests must still pass; new tests come in Task 5).

Keep the `main()` guard intact (`if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi`).
</details>
