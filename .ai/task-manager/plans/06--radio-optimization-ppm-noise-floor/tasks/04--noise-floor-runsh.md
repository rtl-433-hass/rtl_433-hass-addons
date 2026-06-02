---
id: 4
group: "runsh"
dependencies: [3]
status: "completed"
created: 2026-06-02
skills:
  - bash
complexity_score: 4.5
complexity_notes: "Adds two pure helpers plus per-radio rtl_power invocation, CSV parsing, timestamped file output to the config dir, and gnuplot rendering. Depends on task 3 only to serialize edits to run.sh (same file/loop)."
---
# Implement noise-floor detection in run.sh

## Objective
When `detect_noise_floor` is on, scan each radio (every boot) with `rtl_power` across the configured bands before launch, save timestamped CSV + text summary + PNG graph to the add-on config directory, and log a per-band summary. All best-effort and non-fatal.

## Skills Required
- `bash` — editing `rtl_433/run.sh`; awk/gnuplot invocation for the graph.

## Acceptance Criteria
- [ ] New **pure** helpers are added near the other helpers:
  - parse `noise_floor_bands` (comma-separated center frequencies like `433.92M,868M,915M`) into validated `rtl_power` sweep ranges, skipping malformed entries with a warning;
  - compute min / median / peak dBm from `rtl_power` CSV rows.
- [ ] `main()` reads `detect_noise_floor` (default off) and `noise_floor_bands` into globals.
- [ ] In the per-dongle enumeration loop, before `launch_radio`, when the option is on: for each parsed band run `rtl_power` once (one-shot sweep) against the dongle (serial when usable, else index), and write to the add-on config directory (`conf_directory`):
  - `noise-<id>-<timestamp>.csv` (raw rtl_power CSV),
  - `noise-<id>-<timestamp>.txt` (human-readable min/median/peak per band),
  - `noise-<id>-<timestamp>.png` (spectrum plot via gnuplot),
  and log a one-line summary per band (e.g. `Radio <id> 433.92M noise floor ~ -98 dBm (peak -71)`).
- [ ] Every step is best-effort: a tool failure, empty CSV, or write failure is logged and the radio still launches.
- [ ] With the option off, no scan runs and behavior is unchanged.
- [ ] The scan runs on every boot while the option is on (no run-once sentinel, no self-modifying config).
- [ ] `pre-commit run --all-files` (shellcheck) passes; sourcing `run.sh` does not execute `main`.

## Technical Requirements
`rtl_power -d <serial|index> -f <lo>:<hi>:<bin> -1 <out.csv>` (one-shot sweep). rtl_power CSV columns: `date, time, Hz_low, Hz_high, Hz_step, samples, dB, dB, …`. `gnuplot` for PNG. busybox `awk` for CSV reshaping. Existing globals: `conf_directory=/config`, `rtlsdr_devices`, `_serial_is_usable`.

## Input Dependencies
- Task 2: `detect_noise_floor` / `noise_floor_bands` options.
- Task 3: prior run.sh edits (same file & enumeration loop) — serialize to avoid conflicts; reuse its serial/index device-selection approach and per-radio `<id>`.

## Output Artifacts
- New noise-floor helper functions in `run.sh`.
- Per-radio scan + timestamped CSV/TXT/PNG generation wired into `main()` before launch.

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. **Constants**: add a fixed sweep window half-width and bin size, e.g. `NOISE_WINDOW_HZ=1000000` (±1 MHz) and `NOISE_BIN_HZ=10000`, and a scan duration/interval for `rtl_power` (e.g. `-i 1 -1` for a single one-shot sweep). Keep them named constants with comments.
2. **Pure helpers** (above `main`, sourceable):
   - `parse_noise_bands <csv_string>`: split on commas; for each entry, normalize a center frequency (accept forms like `433.92M`, `868M`, `915000000`); convert the `M` suffix to Hz; emit one `lo:hi:bin` triple per valid entry where `lo=center-NOISE_WINDOW_HZ`, `hi=center+NOISE_WINDOW_HZ`, `bin=NOISE_BIN_HZ`. Skip and warn on entries that don't parse. Print one triple per line.
   - `rtl_power_stats <csv_file>`: read the dB columns (fields 7..N) across all rows, and print `min median peak` in dBm. Use awk: collect all numeric dB values, sort for median, track min/max. Print nothing / non-zero if the file has no usable rows.
3. **Read options** in `main()`: `detect_noise_floor="true"|"false"`; `noise_floor_bands="$(bashio::config 'noise_floor_bands')"` (fall back to the default string if empty).
4. **Scan function** `scan_noise_for_radio <selector> <id>` (reads globals): obtain a timestamp once (e.g. `ts="$(date +%Y%m%d-%H%M%S)"`); `mapfile` the parsed bands; for each band triple, run `timeout`-bounded `rtl_power -d "<sel>" -f "<lo:hi:bin>" -i 1 -1 "<csv>"` writing to a temp file, append/accumulate into `noise-<id>-<ts>.csv` under `conf_directory`, compute stats via `rtl_power_stats`, append a line to `noise-<id>-<ts>.txt`, and log the summary. After all bands, render `noise-<id>-<ts>.png`.
5. **PNG rendering**: flatten the rtl_power CSV into `freq_hz dB` pairs with awk (for each row, the dB columns map linearly from `Hz_low` to `Hz_high` in `Hz_step` increments), then call `gnuplot` non-interactively (`gnuplot -e "set terminal png; set output '<png>'; set xlabel 'Hz'; set ylabel 'dBm'; plot '<dat>' with lines"`). Wrap in a function; on any failure log a warning and continue (PNG is best-effort).
6. **Placement**: call `scan_noise_for_radio` inside the enumeration loop, before `launch_radio`, only when `detect_noise_floor == "true"`. It must run while the dongle is still free (before its rtl_433 launches). Guard so nothing runs when off.
7. **Device selection**: reuse the serial-when-usable-else-index choice from Task 3 (do not duplicate logic if a helper already exists).
8. Run `shellcheck`/`pre-commit`; existing `bats -r tests/` must still pass.

Do not prune old report files; accumulation is intentional/documented. Do not touch user `<id>.conf` override files.
</details>
