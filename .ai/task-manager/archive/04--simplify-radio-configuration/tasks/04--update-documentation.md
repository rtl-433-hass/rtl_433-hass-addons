---
id: 4
group: "documentation"
dependencies: [3]
status: "completed"
created: "2026-05-31"
skills:
  - technical-writing
---
# Update documentation for the new configuration model

## Objective
Rewrite the user- and agent-facing documentation to describe the new zero-config, auto-detection model; the add-on config directory; identifier-named append-only override files; the baked-in default; and the "Log received messages" option.

## Skills Required
- `technical-writing`: clear Markdown documentation for end users and AI agents.

## Acceptance Criteria
- [ ] `rtl_433/README.md` "How it works", "Installation", and "Configuration" sections describe: auto-detection of all connected RTL-SDR dongles (no file editing for the default case), the add-on config directory location (`/addon_configs/rtl433/`), creating an override file named after a radio's logged identifier, the append/last-wins semantics, and the relationship to the internal baked-in default.
- [ ] `rtl_433/README.md` documents the "Log received messages" add-on option (adds `output kv`) and notes `output log` is intentionally not included.
- [ ] `rtl_433/README.md` notes the limitation that non-RTL-SDR SDRs (SoapySDR/HackRF) are not auto-detected.
- [ ] The breaking change (old `/config/rtl_433` location no longer read; move tuning into the add-on config dir) is called out.
- [ ] `rtl_433-next/README.md` overlapping guidance is updated to match.
- [ ] `AGENTS.md` Structure section notes the new baked-in default config file (`rtl_433/rtl_433.defaults.conf`) and the add-on-config-dir model.
- [ ] All edited Markdown passes pre-commit checks.

## Technical Requirements
- Reflect the actual option name (`log_received_messages`), default config path, and identifier-naming scheme implemented in tasks 1-3.
- Do not hand-edit `rtl_433/CHANGELOG.md` (release-please owns it).

## Input Dependencies
- Task 3: final `run.sh` behavior (identifier logging, override matching, log toggle) so docs match implementation.
- Task 2: option name and map.

## Output Artifacts
- Updated `rtl_433/README.md`, `rtl_433-next/README.md`, `AGENTS.md`.

## Implementation Notes
<details>
<summary>Step-by-step guidance</summary>

1. **`rtl_433/README.md`**:
   - "How it works": replace the template-sorting explanation with: the add-on enumerates connected RTL-SDR dongles and runs one rtl_433 process per dongle using an internal default config; ports are still assigned deterministically from `8433`. Keep the existing `unique_id` preference-order explanation (serial → USB port path → template name) since it still applies to discovery.
   - "Installation": remove the "create/upload a config file" prerequisite steps. New flow: install the add-on, plug in the dongle(s), start it — it works with no configuration. Mention logs show each detected radio and the override filename to create for customization.
   - "Configuration": describe the optional per-radio override. To customize a radio, find its identifier in the add-on logs (the log line states the exact filename), create that `<identifier>.conf` file in the add-on config directory (accessible at `/addon_configs/rtl433/` via Samba/File Editor/VS Code), and put only the extra directives you want (e.g. `frequency 868M`, `protocol 40`, `convert si`). Explain these are appended to the internal default and that on conflict the override wins. Note that `output http://0.0.0.0:${port}` is provided by the default — users do not need to add it, and overriding `device` is discouraged because it breaks the file→radio mapping.
   - Add a short "Logging" subsection: enabling the **Log received messages** option (in the add-on Configuration tab) adds `output kv` so decoded events appear in the add-on log; note `output log` (rtl_433 diagnostics) is intentionally not bundled.
   - Add a "Breaking change" / migration note: the old `/config/rtl_433` (Home Assistant config dir) location is no longer used; move any per-radio tuning into `<identifier>.conf` files in the add-on config directory.
   - Add the SoapySDR/HackRF auto-detection limitation note.

2. **`rtl_433-next/README.md`**: update the brief overlapping guidance to point at the same model (auto-detection, add-on config dir, override files, log option). Keep it concise.

3. **`AGENTS.md`**: in the "Structure" section, add a bullet noting `rtl_433/rtl_433.defaults.conf` is the internal default baked into the image, and that user overrides live in the add-on config directory (`addon_config` map), not the Home Assistant config directory.

4. Run `pre-commit run --files rtl_433/README.md rtl_433-next/README.md AGENTS.md` and fix any issues.
</details>
