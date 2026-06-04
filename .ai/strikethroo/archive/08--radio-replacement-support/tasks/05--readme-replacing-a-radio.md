---
id: 5
group: "radio-replacement"
dependencies: [1, 2]
status: "completed"
created: 2026-06-03
skills:
  - technical-writing
---
# Document "Replacing a radio" in the rtl_433 README

## Objective
Add a "Replacing a radio" section to `rtl_433/README.md` (and `rtl_433-next/README.md`
only if it diverges) covering the end-to-end replacement procedure, when to use
`force_randomize_serial` vs `randomize_default_serial` vs nothing, and the
`serial:` vs `usbpath:` identity trade-off.

## Skills Required
- `technical-writing` — clear user-facing Markdown documentation.

## Acceptance Criteria
- [ ] `rtl_433/README.md` contains a "Replacing a radio" section.
- [ ] It documents the step-by-step procedure (remove dead dongle → stamp if
      needed → read identity → integration reconfigure).
- [ ] It explains when to use `force_randomize_serial` (replacement has a
      non-default serial to discard), `randomize_default_serial` (default serial),
      or nothing (no-EEPROM dongle in the same port).
- [ ] It explains the trade-off: `serial:` survives moving USB ports but dies with
      the dongle; `usbpath:` survives a dongle swap in the same port but breaks on
      a port move — with the practical guidance on which to rely on.
- [ ] It tells the user where to read the new radio's `unique_id`/`host:port`
      (the per-radio log line and the `radios.status` file in the add-on config dir).
- [ ] `rtl_433-next/README.md` updated only if it carries equivalent content that
      would diverge; otherwise left as-is.

Use your internal Todo tool to track these and keep on track.

## Technical Requirements
- Files: `rtl_433/README.md` (and `rtl_433-next/README.md` if it diverges).
- Use the exact option names and the `radios.status` filename as implemented in
  Tasks 1–3.

## Input Dependencies
- Task 1: final `force_randomize_serial` selector semantics (USB port path) and
  flash-and-halt behavior.
- Task 2: the `radios.status` filename/fields and per-radio log line format.

## Output Artifacts
- A new README section. No code consumers.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

Source content from the design brief's §"End-to-end user procedure" and §C
trade-off guidance (repo-root `RADIO_REPLACEMENT_PLAN.md`) and the plan document.
Suggested structure:

1. **Replacing a radio** (intro: why a replaced serial-identified dongle needs
   re-linking).
2. **Procedure:**
   1. Remove the dead dongle; plug in the replacement (any port).
   2. Choose the stamping action:
      - Replacement has a **non-default** serial to discard → set
        `force_randomize_serial` to the new dongle's **USB port path**
        (e.g. `1-1.4`, visible in the add-on log), start once (it stamps and
        halts), clear the option, stop, **replug**, start again.
      - Replacement has a **default** serial → enable `randomize_default_serial`
        once instead.
      - No-EEPROM dongle in the **same port** as the dead one → skip stamping;
        its `usbpath:` identity is unchanged.
   3. Read the new radio's `unique_id` and `host:port` from the per-radio log line
      (`Radio … unique_id=… host=… port=…`) or the `radios.status` file in the
      add-on config directory (`/addon_configs/<slug>/radios.status`).
   4. In Home Assistant, run the integration's **Replace radio / reconfigure**
      workflow and point the existing hub entry at the new radio — entities,
      history, and automations are preserved.
3. **Identity trade-off (`serial:` vs `usbpath:`):**
   - `serial:` survives moving the dongle between USB ports, but the identity dies
     with the dongle (the serial lived in its EEPROM).
   - `usbpath:` survives swapping a dongle **in the same port**, but breaks if the
     dongle moves to a different port.
   - Practical guidance: users who don't rearrange USB ports may prefer relying on
     `usbpath:` identity for the easiest replacement; users who rearrange ports
     should use serials and accept the reconfigure step on replacement.

Match the README's existing heading depth, voice, and formatting. Keep it concise
and task-oriented. Mention that stamping writes the EEPROM and requires a physical
replug to take effect (consistent with the existing `randomize_default_serial`
docs, if present).
</details>
