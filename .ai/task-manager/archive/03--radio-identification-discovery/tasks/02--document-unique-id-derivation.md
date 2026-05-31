---
id: 2
group: "radio-identification"
dependencies: [1]
status: "completed"
created: 2026-05-31
skills:
  - technical-writing
---
# Document the `unique_id` derivation in the rtl_433 README

## Objective
Update `rtl_433/README.md` so operators understand that each radio is advertised to Home Assistant discovery with a stable `unique_id`, how that value is derived, and how to make radio identity most robust.

## Skills Required
- `technical-writing` (Markdown documentation)

## Acceptance Criteria
- [ ] The discovery section of `rtl_433/README.md` explains that each radio is published with a `unique_id` field in its discovery `config`.
- [ ] It describes the layered derivation in plain language: unique USB serial → USB port path → template/config name, and what each means for stability (serial survives moving ports; port path is stable per physical port; tag is a deterministic last resort).
- [ ] It includes the practical note that flashing a unique serial with `rtl_eeprom -s <serial>` (done outside the add-on) gives the most robust identity, and that nearly all dongles ship with the colliding default serial `00000001`.
- [ ] Wording matches the actual implemented behavior and field name from task 1 (`unique_id`, prefixes `serial:`/`usbpath:`/`template:`).
- [ ] `CHANGELOG.md` is NOT modified and no `[Unreleased]` section is added (release-please owns the changelog per AGENTS.md).
- [ ] `pre-commit run --all-files` passes.

## Technical Requirements
- Edit only `rtl_433/README.md` (and no changelog). Keep the existing README tone/structure; extend the existing discovery paragraph rather than adding a redundant section.

## Input Dependencies
- Task 1 (the implemented `unique_id` behavior and field name in `run.sh`).

## Output Artifacts
- Updated `rtl_433/README.md`.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

- The current discovery paragraph in `rtl_433/README.md` reads (approximately): "The add-on also publishes each radio to Home Assistant's Supervisor discovery API (best-effort)... add the integration manually... supplying the add-on host and the radio's port." Extend this.
- Add a short explanation, e.g.:
  - Each discovery message now carries a `unique_id` so the integration can keep a stable config entry for a radio across restarts and port reassignments.
  - How it is chosen, in order: (1) the dongle's USB serial when it is unique and not the factory default; (2) otherwise the dongle's USB port path (which physical port it is plugged into); (3) otherwise the configuration template's name.
  - Practical guidance: because almost all RTL-SDR dongles ship with the same serial `00000001`, multi-dongle setups get the most stable identity either by keeping each dongle in a fixed USB port (port-path identity) or by flashing a unique serial with `rtl_eeprom -s <serial>` (a one-time step performed outside the add-on).
- Verify field name/prefixes against `run.sh` as implemented in task 1 before finalizing wording.
- Do not duplicate content already covered; keep it concise and operator-focused.
</details>
