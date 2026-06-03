---
id: 4
group: "documentation"
dependencies: [2]
status: "completed"
created: "2026-06-03"
skills:
  - markdown
---
# Document the `randomize_default_serial` option

## Objective
Document the new option for users: add a configuration subsection to `rtl_433/README.md` and a brief mention to `rtl_433-next/README.md`, consistent with the existing option documentation style.

## Skills Required
- `markdown` — writing user-facing README documentation matching the existing tone/structure.

## Acceptance Criteria
- [ ] `rtl_433/README.md` has a new "Randomize default serial" subsection under `## Configuration`, styled like the existing "Correct PPM offset" / "Detect noise floor" sections.
- [ ] The subsection states: it is off by default; it flashes only dongles that still carry a factory default serial (`00000000`/`00000001`); each such dongle gets a unique random 8-hex-character serial; the operation is one-time/idempotent (a flashed dongle is not re-flashed); the add-on re-enumerates once so the new serial is used the same boot; and the in-container re-enumeration caveat (if the reset does not propagate, the new serial still persists and takes effect on the next restart).
- [ ] The existing manual `rtl_eeprom -s <serial>` sentence in `rtl_433/README.md` cross-references the new option as an automated alternative.
- [ ] `rtl_433-next/README.md` options paragraph mentions the new option briefly.
- [ ] `CHANGELOG.md` files are **not** hand-edited (release-please owns them).
- [ ] Markdown remains well-formed (any markdown pre-commit hooks pass).

## Technical Requirements
Match the existing documentation conventions: H3 subsection headings under `## Configuration`, the `/addon_configs/rtl433/` path references, and the bold option-name style used by the other options.

## Input Dependencies
- Task 2: documents the implemented behaviour (best-effort flash + single re-enumeration).

## Output Artifacts
- Updated `rtl_433/README.md` and `rtl_433-next/README.md`.

## Implementation Notes
<details>
<summary>Step-by-step</summary>

1. **`rtl_433/README.md`** — add a new H3 subsection under `## Configuration`. A natural place is right after the "### Detect noise floor" section (before "### Non-RTL-SDR radios"). Suggested content (adapt wording to match surrounding tone):

   ```markdown
   ### Randomize default serial

   Nearly all RTL-SDR dongles ship with the same factory-default serial
   (`00000000` or `00000001`), which makes multiple dongles indistinguishable and
   pushes the add-on to identify them by USB port instead. The **Randomize default
   serial** option (off by default) fixes this automatically: at startup, before
   any radio claims a device, the add-on flashes a **unique random serial** onto
   every connected dongle that still carries a factory-default serial, using
   `rtl_eeprom`. Dongles that already have a real serial are never touched.

   This is a **one-time** operation: once a dongle has been given a serial it is no
   longer a factory default, so later boots find nothing to flash (even with the
   option left on). After flashing, the add-on re-enumerates the dongles once so
   the new serials are used for the rest of that same boot — for identity,
   override-file matching, and launch.

   **Caveat:** applying a new serial requires the dongle to re-enumerate (a USB
   reset). The EEPROM write always persists, but if the reset does not propagate
   inside the container on the first boot, the freshly assigned serial simply takes
   effect on the **next add-on restart**. Every step is best-effort: a failure to
   flash or re-enumerate never stops the radio (or the add-on) from starting.
   ```

2. **Cross-reference the manual note.** In `rtl_433/README.md` find the existing sentence (around the "How it works" area):

   > Because nearly all RTL-SDR dongles ship with the same default serial (`00000001`), multi-dongle setups get the most stable identity either by keeping each dongle in a fixed USB port or by flashing a unique serial with `rtl_eeprom -s <serial>` (a one-time step performed outside the add-on).

   Append a short pointer so the reader knows the add-on can now do this for them, e.g. add at the end of that sentence: " — or enable the [Randomize default serial](#randomize-default-serial) option to have the add-on do this automatically."

3. **`rtl_433-next/README.md`** — in the options summary paragraph (the one listing **Correct PPM offset** / **Detect noise floor**), add a brief sentence such as: "**Randomize default serial** (off by default) flashes a unique random serial onto any dongle still carrying a factory-default serial at startup, so multiple dongles become individually identifiable." Keep it short and let it defer to the stable README for details (it already links there).

4. Do not touch either `CHANGELOG.md`.

</details>
