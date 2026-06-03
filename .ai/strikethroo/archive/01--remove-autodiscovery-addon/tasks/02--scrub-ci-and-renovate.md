---
id: 2
group: "scrub"
dependencies: [1]
status: "completed"
created: 2026-05-30
skills:
  - github-actions
---
# Scrub autodiscovery from CI workflows and renovate config

## Objective
Update the CI workflows and `renovate.json` so they reference only the `rtl_433` and `rtl_433-next` add-ons, with no remaining references to the removed autodiscovery directories.

## Skills Required
- `github-actions` (editing workflow YAML and renovate JSON)

## Acceptance Criteria
- [ ] `.github/workflows/build-addon.yml` matrix arrays and the "Copy shared files" step contain no autodiscovery references.
- [ ] `.github/workflows/addon-linter.yml` lint matrix contains only `rtl_433` and `rtl_433-next`.
- [ ] `.github/workflows/hadolint.yml` no longer lints an autodiscovery Dockerfile and its result check is simplified accordingly.
- [ ] `renovate.json` custom managers no longer reference `rtl_433_mqtt_autodiscovery/Dockerfile`.
- [ ] actionlint, check-yaml, and check-json pre-commit hooks pass on the edited files.

## Technical Requirements
Edit GitHub Actions YAML matrices/conditionals and a JSON config. Keep YAML and JSON syntactically valid.

## Input Dependencies
Task 1 (directories removed) so the references point at nothing.

## Output Artifacts
CI and dependency automation consistent with the two-add-on repository.

## Implementation Notes
<details>
<summary>Exact edits</summary>

**`.github/workflows/build-addon.yml`** — in the `setup` job's "Select addons for build type" step, change the three case arms:
```
release) addons='["rtl_433", "rtl_433_mqtt_autodiscovery"]' ;;
nightly) addons='["rtl_433-next", "rtl_433_mqtt_autodiscovery-next"]' ;;
test)    addons='["rtl_433", "rtl_433-next", "rtl_433_mqtt_autodiscovery", "rtl_433_mqtt_autodiscovery-next"]' ;;
```
to:
```
release) addons='["rtl_433"]' ;;
nightly) addons='["rtl_433-next"]' ;;
test)    addons='["rtl_433", "rtl_433-next"]' ;;
```
Then in the "Copy shared files into -next variants" step, remove the autodiscovery branch of the `case` so only the `rtl_433-next` branch remains:
```
case "${ADDON}" in
  rtl_433-next)
    cp -nv -R rtl_433/* "${ADDON}/" ;;
esac
```
(Delete the `rtl_433_mqtt_autodiscovery-next)` arm and its `cp` line.)

**`.github/workflows/addon-linter.yml`** — in the matrix `addon:` list, remove the `- rtl_433_mqtt_autodiscovery` and `- rtl_433_mqtt_autodiscovery-next` lines, leaving only `- rtl_433` and `- rtl_433-next`.

**`.github/workflows/hadolint.yml`** — delete the entire "Lint rtl_433_mqtt_autodiscovery Dockerfile" step (the step with `id: lint-autodiscovery`). Then change the final "Check lint results" step condition from:
```
if: steps.lint-rtl_433.outcome == 'failure' || steps.lint-autodiscovery.outcome == 'failure'
```
to:
```
if: steps.lint-rtl_433.outcome == 'failure'
```

**`renovate.json`** — in the custom regex manager whose `matchStrings` contains `ARG rtl433GitRevision=...`, remove the `"/^rtl_433_mqtt_autodiscovery/Dockerfile$/"` entry from `managerFilePatterns`, leaving only `"/^rtl_433/Dockerfile$/"`. Ensure the JSON array and surrounding commas remain valid.

After editing, run `pre-commit run --all-files` (or at minimum actionlint, check-yaml, check-json) and confirm no failures from these files.
</details>
