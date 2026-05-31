---
id: 1
group: "image-and-defaults"
dependencies: []
status: "completed"
created: "2026-05-31"
skills:
  - docker
  - bash
---
# Bake the internal default rtl_433 config into the image

## Objective
Extract the add-on's default rtl_433 configuration out of `run.sh`'s runtime heredoc and into a standalone file under `rtl_433/`, then `COPY` it into the container image via the `Dockerfile` so it becomes an internal, non-user-editable artifact. This file is the single source of truth that every radio's config is built from.

## Skills Required
- `docker`: add a `COPY` instruction placing the default config at a fixed in-image path.
- `bash`/rtl_433 config authoring: produce a valid rtl_433 config file.

## Acceptance Criteria
- [ ] A new file `rtl_433/rtl_433.defaults.conf` exists containing the default rtl_433 configuration.
- [ ] The default config contains `report_meta time:iso:usec:tz`, the HTTP output line `output http://0.0.0.0:${port}` (keeping the `${port}` placeholder), the full list of TPMS `protocol -NN` disables currently in `run.sh`, and a commented hint line about `output kv`.
- [ ] The default config does **not** contain a hard-coded physical `device` line (the add-on injects `device` per radio at runtime).
- [ ] The `Dockerfile` copies this file to `/etc/rtl_433/rtl_433.defaults.conf` in the final image stage.
- [ ] `hadolint` passes on the `Dockerfile`.

## Technical Requirements
- Target in-image path: `/etc/rtl_433/rtl_433.defaults.conf`.
- The `${port}` placeholder must remain literally in the file (it is substituted by `run.sh` at render time, not by Docker).
- Place the `COPY` in the final runtime stage of the multi-stage `Dockerfile` (the stage beginning `FROM $BUILD_FROM` near the bottom that already does `COPY run.sh /`).

## Input Dependencies
None.

## Output Artifacts
- `rtl_433/rtl_433.defaults.conf` (new) — consumed by the `run.sh` rewrite (task 3).
- Updated `rtl_433/Dockerfile`.

## Implementation Notes
<details>
<summary>Step-by-step guidance</summary>

1. Open `rtl_433/run.sh` and locate the heredoc that currently writes `rtl_433.conf.template` (the `cat > "$conf_directory"/rtl_433.conf.template <<EOD ... EOD` block, roughly lines 141-203). Use its body as the basis for the new file.

2. Create `rtl_433/rtl_433.defaults.conf` with content along these lines (a comment header explaining it is the internal default, then the active directives). Keep the `${port}` placeholder literal and keep the TPMS disables. Remove the `device 0` line — the add-on sets the device per radio. Example body:

   ```
   # Internal default rtl_433 configuration for the Home Assistant add-on.
   # This file is baked into the image and is NOT user-editable. To customize a
   # specific radio, create a file named after that radio's identifier in the
   # add-on config directory; its contents are appended to this default.
   #
   # The ${port} placeholder is filled in at render time with the radio's
   # assigned HTTP port. The add-on injects the correct 'device' line per radio.

   output http://0.0.0.0:${port}
   report_meta time:iso:usec:tz

   # The "Log received messages" add-on option appends 'output kv' to log decoded
   # events to the add-on log.

   # Disable TPMS sensors by default (they create an overwhelming number of
   # entities in Home Assistant).
   protocol -59
   protocol -60
   protocol -82
   protocol -88
   protocol -89
   protocol -90
   protocol -95
   protocol -110
   protocol -123
   protocol -140
   protocol -156
   protocol -168
   protocol -180
   protocol -186
   protocol -201
   protocol -203
   ```

   Note: this content is rendered later by `run.sh` (which substitutes `${port}`), so the literal `${port}` must be preserved in the file on disk. Do not escape it here.

3. In `rtl_433/Dockerfile`, in the FINAL stage (the second `FROM $BUILD_FROM` block, near `COPY run.sh /`), add a copy instruction. To satisfy hadolint, ensure the destination directory pattern is valid; copying to an explicit file path is fine:

   ```
   COPY rtl_433.defaults.conf /etc/rtl_433/rtl_433.defaults.conf
   ```

   Docker creates intermediate directories for a file destination automatically, so no separate `mkdir` is required. Place this near the existing `COPY run.sh /` line.

4. Do not remove the heredoc from `run.sh` in this task — that rewrite is task 3's responsibility. This task only adds the new file and the COPY.

5. Run `pre-commit run --files rtl_433/Dockerfile rtl_433/rtl_433.defaults.conf` (or `pre-commit run --all-files`) and confirm hadolint passes.
</details>
