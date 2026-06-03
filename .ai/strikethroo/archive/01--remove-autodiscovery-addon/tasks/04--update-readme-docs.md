---
id: 4
group: "scrub"
dependencies: [1]
status: "completed"
created: 2026-05-30
skills:
  - markdown
---
# Update README docs to point to the new integration

## Objective
Replace the autodiscovery add-on recommendations in `rtl_433/README.md` with pointers to the new dedicated rtl_433 integration, and remove the autodiscovery reference from the root `README.md` release example.

## Skills Required
- `markdown` (technical documentation editing)

## Acceptance Criteria
- [ ] `rtl_433/README.md` no longer recommends installing the autodiscovery add-on; it points to https://github.com/rtl-433-hass/rtl_433 as the discovery method.
- [ ] The root `README.md` release-process example no longer references `rtl_433_mqtt_autodiscovery/config.json`.
- [ ] No live (non-historical) autodiscovery references remain in either README.

## Technical Requirements
Edit two markdown files, preserving surrounding structure and tone.

## Input Dependencies
Task 1 (directories removed).

## Output Artifacts
User-facing docs that guide users to the supported replacement integration.

## Implementation Notes
<details>
<summary>Exact edits</summary>

**`rtl_433/README.md`** — two spots reference the autodiscovery add-on:

1. In the "How it works" bulleted list, the third bullet currently reads:
   `* install the [rtl_433 MQTT Auto Discovery Home Assistant Add-on](https://github.com/pbkhrv/rtl_433-hass-addons/tree/main/rtl_433_mqtt_autodiscovery), which runs rtl_433_mqtt_hass.py for you.`
   Replace it with a bullet pointing to the new dedicated integration, e.g.:
   `* install the dedicated [rtl_433 integration for Home Assistant](https://github.com/rtl-433-hass/rtl_433), which discovers and configures your devices automatically.`

2. In the "Configuration" section, the "zero configuration" paragraph says:
   `Once the addon is installed, start or restart the rtl_433 and rtl_433_mqtt_autodiscovery addons to start capturing known 433 MHz protocols.`
   Reword to drop the autodiscovery add-on and instead reference installing the rtl_433 add-on plus the new integration, e.g.:
   `Once the addon is installed, start or restart the rtl_433 add-on to start capturing known 433 MHz protocols, and install the [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433) so Home Assistant can discover your devices.`

   (The later sentence "if you decide to use the MQTT auto discovery script or add-on, its documentation recommends converting units ... into SI" may be left as a general note about the upstream script, OR reworded to drop "or add-on". Prefer minimal change: change "the MQTT auto discovery script or add-on" to "the MQTT auto discovery integration".)

**`README.md`** (root) — in the "Creating a Release" section, step 1 reads:
   `Create a pull request bumping the versions in [rtl_433/config.json](rtl_433/config.json) and/or [rtl_433_mqtt_autodiscovery/config.json](rtl_433_mqtt_autodiscovery/config.json). Update the corresponding CHANGELOG.md files.`
   Remove the autodiscovery clause so it reads:
   `Create a pull request bumping the version in [rtl_433/config.json](rtl_433/config.json). Update the corresponding CHANGELOG.md file.`

Do NOT edit any `CHANGELOG.md` — historical references are intentionally preserved.
</details>
