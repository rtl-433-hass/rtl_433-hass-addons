---
id: 6
group: "docs"
dependencies: [1, 2, 3, 4]
status: "completed"
created: 2026-06-02
skills:
  - technical-writing
---
# Document the PPM and noise-floor features

## Objective
Document the two new options and their behavior in the user-facing READMEs and the assistant-facing AGENTS.md, matching the plan's clarified behavior.

## Skills Required
- `technical-writing` — editing `rtl_433/README.md`, `rtl_433-next/README.md`, and `AGENTS.md`.

## Acceptance Criteria
- [ ] `rtl_433/README.md` documents, under Configuration:
  - `correct_ppm_offset`: PPM is measured once (~3 min) with `rtl_test` and cached under `/data`; later boots reuse it; deleting the cache forces re-measurement; a manually-set `ppm_error` in an override is respected (auto is skipped); the active offset is logged on startup.
  - `detect_noise_floor` + `noise_floor_bands` (comma-separated center frequencies): a scan runs on **every boot while the option is on** (disable it when satisfied), writing **timestamped** `noise-<id>-<timestamp>.{csv,txt,png}` to the add-on config dir that the add-on never prunes; the noise floor is a **boot-time snapshot at the configured band**, not Home Assistant's runtime-managed frequency; first-boot/scan startup-delay caveat.
- [ ] `rtl_433-next/README.md` is updated to mirror the relevant additions appropriately for the rolling build.
- [ ] `AGENTS.md` (Structure section) notes the new add-on options, that `rtl_test`/`rtl_power`/`gnuplot` are now part of the image, and that the per-radio PPM cache lives under `/data`.
- [ ] `CHANGELOG.md` is NOT hand-edited (release-please owns it).
- [ ] `pre-commit run --all-files` passes (markdown/yaml/json hooks).

## Technical Requirements
Markdown. Match the existing README tone/structure (the Configuration section already documents `disable_tpms` and per-radio overrides).

## Input Dependencies
- Tasks 1–4: final option names, defaults, file locations, and behavior.

## Output Artifacts
- Updated `rtl_433/README.md`, `rtl_433-next/README.md`, `AGENTS.md`.

## Implementation Notes
<details>
<summary>Detailed steps</summary>

1. In `rtl_433/README.md`, add subsections under the existing `## Configuration` area (near "Disable TPMS sensors" / "Per-radio overrides"): one for PPM offset correction and one for noise-floor detection, covering every bullet in the acceptance criteria. Reference the config-dir path convention already used in the README (`/addon_configs/rtl433/`).
2. Update `rtl_433-next/README.md` consistent with how it already differs from the main README (it is shorter / experimental). Keep it proportionate — a brief mention of the same options is sufficient.
3. In `AGENTS.md`, extend the `## Structure` section with the noted items (new options, new image tools, `/data` PPM cache).
4. Do not add an `[Unreleased]` section or edit `rtl_433/CHANGELOG.md` (per repo policy).
5. Run `pre-commit run --all-files`.
</details>
