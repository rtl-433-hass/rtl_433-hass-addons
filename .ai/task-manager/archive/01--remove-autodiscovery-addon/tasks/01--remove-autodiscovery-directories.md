---
id: 1
group: "removal"
dependencies: []
status: "completed"
created: 2026-05-30
skills:
  - bash
---
# Remove the autodiscovery add-on directories

## Objective
Delete the `rtl_433_mqtt_autodiscovery` and `rtl_433_mqtt_autodiscovery-next` add-on directories from the repository so only the `rtl_433` and `rtl_433-next` add-ons remain.

## Skills Required
- `bash` (file/directory removal via git)

## Acceptance Criteria
- [ ] The `rtl_433_mqtt_autodiscovery/` directory no longer exists.
- [ ] The `rtl_433_mqtt_autodiscovery-next/` directory no longer exists.
- [ ] The `rtl_433/` and `rtl_433-next/` directories are untouched and still present.

## Technical Requirements
Remove two top-level directories at the repository root, including all their contents (config.json, Dockerfile, run.sh, build.json, CHANGELOG.md, LICENSE, README.md, icon.png, logo.png as applicable).

## Input Dependencies
None — this is the root change.

## Output Artifacts
A repository tree containing only the two rtl_433 add-on directories. Subsequent tasks scrub references to the removed directories.

## Implementation Notes
<details>
<summary>Step-by-step</summary>

1. From the repository root (`/home/andrew.guest/github.com/rtl-433-hass/rtl_433-hass-addons`), run:
   ```bash
   git rm -r rtl_433_mqtt_autodiscovery rtl_433_mqtt_autodiscovery-next
   ```
   Using `git rm` stages the deletion. If the files are not tracked for some reason, fall back to `rm -rf` for the same two paths.
2. Verify with `ls` that both directories are gone and that `rtl_433` and `rtl_433-next` still exist.
3. Do NOT touch any other files in this task — reference scrubbing happens in the dependent tasks.
</details>
