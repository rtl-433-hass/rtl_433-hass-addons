---
id: 3
group: "scrub"
dependencies: [1]
status: "completed"
created: 2026-05-30
skills:
  - markdown
---
# Update GitHub issue and PR templates

## Objective
Remove autodiscovery references from the issue and pull request templates so they describe only the `rtl_433` add-on.

## Skills Required
- `markdown` (editing YAML issue form and markdown PR template)

## Acceptance Criteria
- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml` add-on dropdown no longer offers the autodiscovery option.
- [ ] The autodiscovery log-location line is removed from `bug_report.yml`.
- [ ] `.github/pull_request_template.md` no longer contains the autodiscovery upstream-script comment block.
- [ ] check-yaml passes on `bug_report.yml`.

## Technical Requirements
Edit a GitHub issue form (YAML) and a markdown PR template. Keep the YAML valid.

## Input Dependencies
Task 1 (directories removed).

## Output Artifacts
Templates that reference only existing add-ons.

## Implementation Notes
<details>
<summary>Exact edits</summary>

**`.github/ISSUE_TEMPLATE/bug_report.yml`**:
- In the dropdown labelled "What addon are you reporting the bug for?", the `options:` list currently has `- rtl_443` and `- rtl_433_mqtt_autodiscover`. Remove the `- rtl_433_mqtt_autodiscover` option so only the rtl_433 option remains. (Leave the existing `rtl_443` text as-is; fixing that pre-existing typo is out of scope unless trivial — do not introduce new entries.)
- In the "Addon log messages" textarea description, remove the sentence:
  `rtl_433_mqtt_autodiscovery logs can be found in: [Settings -> Add-ons -> rtl_433](https://my.home-assistant.io/redirect/supervisor_addon/?addon=9b13b3f4_rtl433mqttautodiscovery).`
  Keep the preceding rtl_433 log-location sentence.

**`.github/pull_request_template.md`**:
- Remove the HTML comment block that begins `<!-- rtl_433_mqtt_autodiscovery/rtl_433_mqtt_hass.py is maintained upstream at` and ends with the closing `-->`. Leave the rest of the template (Summary, Alternatives Considered, Testing Steps) intact.

After editing, confirm `bug_report.yml` is still valid YAML (check-yaml hook).
</details>
