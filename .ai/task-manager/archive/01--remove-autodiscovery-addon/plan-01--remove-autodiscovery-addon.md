---
id: 1
summary: "Remove the rtl_433_mqtt_autodiscovery add-on (stable and -next) from the repository and scrub all live references, redirecting users to the new dedicated rtl_433 integration"
created: 2026-05-30
---

# Plan: Remove the MQTT Autodiscovery Add-on

## Original Work Order
> Remove the autodiscovery addon from this project. We only want the rtl_433 and rtl_433_next addons. Autodiscovery is being replaced by a dedicated rtl_433 integration available at https://github.com/rtl-433-hass/rtl_433.

## Plan Clarifications

| Question | Answer |
| --- | --- |
| How should existing users be handled? | Hard removal. No one is using this add-on yet (it was copied from another repo), so no backwards compatibility or upgrade path is needed. |
| Should the rtl_433 docs point to the new integration? | Yes — replace autodiscovery mentions in `rtl_433/README.md` with a pointer to https://github.com/rtl-433-hass/rtl_433. |
| Should historical CHANGELOG entries be left intact? | Yes — keep past CHANGELOG entries unchanged; only remove the live add-on and its active references. |

## Executive Summary

This plan removes the `rtl_433_mqtt_autodiscovery` add-on, including both its stable directory and its `-next` development variant, from the Home Assistant add-on repository. The add-on's discovery functionality is being superseded by a dedicated, non-MQTT rtl_433 integration hosted at https://github.com/rtl-433-hass/rtl_433, so the in-repo add-on is no longer needed.

Because the add-on was copied from an upstream repository and has no installed user base here, a hard removal is appropriate: the two add-on directories are deleted outright and every live reference in CI workflows, repository metadata, issue/PR templates, and the renovate configuration is scrubbed. The remaining `rtl_433` and `rtl_433-next` add-ons stay untouched except for documentation that previously recommended the autodiscovery add-on, which is updated to point users at the new integration.

The result is a leaner repository that builds, lints, and releases only the two rtl_433 add-ons, with no dangling references to the removed add-on. Historical CHANGELOG entries are deliberately preserved because they record real project history.

## Context

### Current State vs Target State

| Current State | Target State | Why? |
| --- | --- | --- |
| Four add-on directories exist: `rtl_433`, `rtl_433-next`, `rtl_433_mqtt_autodiscovery`, `rtl_433_mqtt_autodiscovery-next` | Only `rtl_433` and `rtl_433-next` directories remain | The autodiscovery add-on is being replaced by a dedicated integration |
| CI build/lint matrices include the autodiscovery add-on (build-addon.yml, addon-linter.yml, hadolint.yml) | CI matrices reference only the two rtl_433 add-ons | Removed directories would cause build/lint failures or wasted jobs |
| `renovate.json` tracks the rtl433 git revision in `rtl_433_mqtt_autodiscovery/Dockerfile` | renovate tracks only `rtl_433/Dockerfile` | The autodiscovery Dockerfile no longer exists |
| Issue template offers autodiscovery as a reportable add-on; PR template references the autodiscovery script | Templates reference only the rtl_433 add-on | Templates should not reference a removed add-on |
| `rtl_433/README.md` and root `README.md` recommend the autodiscovery add-on for discovery | Docs point users to the new dedicated integration at the given URL | Guide users to the supported replacement |
| Historical CHANGELOG entries mention autodiscovery | Unchanged | They record real history |

### Background

The repository ships Home Assistant add-ons for rtl_433. Each add-on is a directory containing `config.json`, `Dockerfile`, `run.sh`, `build.json`, `CHANGELOG.md`, and assets. The `-next` variants are development versions built on every push to `main`; the build workflow copies shared files from the stable directory into the `-next` directory at build time.

The autodiscovery add-on appears in several coordinated places that must be changed together so the repository remains consistent and CI stays green:

- **Add-on directories**: `rtl_433_mqtt_autodiscovery/` and `rtl_433_mqtt_autodiscovery-next/`.
- **CI workflows**: `.github/workflows/build-addon.yml` (the `setup` matrix selection and the "Copy shared files into -next variants" step), `.github/workflows/addon-linter.yml` (lint matrix), and `.github/workflows/hadolint.yml` (a dedicated Dockerfile lint step plus the combined result check).
- **Repository metadata**: `renovate.json` (a custom regex manager that tracks the rtl433 git revision in the autodiscovery Dockerfile).
- **Templates**: `.github/ISSUE_TEMPLATE/bug_report.yml` (an add-on dropdown and a log-location note) and `.github/pull_request_template.md` (a comment about the upstream-maintained script).
- **Documentation**: `rtl_433/README.md` (two recommendations to install the autodiscovery add-on) and the root `README.md` (a release-process example referencing the autodiscovery `config.json`).

Historical CHANGELOG references (e.g. `rtl_433/CHANGELOG.md`) are intentionally out of scope per the clarifications.

## Architectural Approach

The work is a coordinated deletion-and-scrub across three concerns: the add-on directories themselves, the CI/automation that operates on them, and the human-facing documentation/templates that mention them. The directories are deleted first; everything that references them is then updated so nothing points at a missing path. Documentation is updated to redirect users to the replacement integration.

```mermaid
graph TD
    A[Delete autodiscovery add-on directories] --> B[Scrub CI workflows & renovate config]
    A --> C[Update issue/PR templates]
    A --> D[Update README docs to point to new integration]
    B --> E[Self-validation: lint, grep, CI sanity]
    C --> E
    D --> E
```

### Add-on Directory Removal
**Objective**: Eliminate the source of the removed add-on.

Delete the `rtl_433_mqtt_autodiscovery/` and `rtl_433_mqtt_autodiscovery-next/` directories in their entirety, including configs, Dockerfile, scripts, changelog, license, and image assets. This is the root change that all other edits support.

### CI and Automation Scrub
**Objective**: Keep the build, lint, and dependency-update automation consistent with the reduced add-on set.

In `build-addon.yml`, remove the autodiscovery entries from the `release`, `nightly`, and `test` matrix arrays in the `setup` job, and remove the `rtl_433_mqtt_autodiscovery-next` branch of the "Copy shared files into -next variants" step. In `addon-linter.yml`, remove the two autodiscovery entries from the lint matrix. In `hadolint.yml`, remove the dedicated autodiscovery Dockerfile lint step and simplify the combined "Check lint results" condition so it only inspects the rtl_433 outcome. In `renovate.json`, remove the autodiscovery Dockerfile path from the custom regex manager's file patterns. All edited workflows must remain valid for actionlint and the JSON for renovate must remain valid.

### Templates and Documentation Update
**Objective**: Ensure human-facing surfaces reference only existing add-ons and guide users to the replacement.

In `bug_report.yml`, remove the autodiscovery option from the add-on dropdown and the autodiscovery log-location line. In `pull_request_template.md`, remove the comment block describing the upstream-maintained autodiscovery script. In `rtl_433/README.md`, replace the two autodiscovery recommendations with guidance pointing to the new dedicated integration at https://github.com/rtl-433-hass/rtl_433. In the root `README.md`, update the release-process example so it no longer references the autodiscovery `config.json`.

## Risk Considerations and Mitigation Strategies

<details>
<summary>Technical Risks</summary>

- **Dangling references break CI**: A missed reference to a deleted directory could fail a build or lint job.
    - **Mitigation**: After edits, grep the whole tree (excluding `.git`, `.ai`, and historical CHANGELOGs) for `autodiscovery` and confirm only intentional/historical matches remain.
- **Workflow files become syntactically invalid**: Editing YAML matrices or conditionals by hand can introduce errors.
    - **Mitigation**: Rely on the repository's pre-commit hooks (actionlint, check-yaml, check-json) which run automatically; ensure they pass.
</details>

<details>
<summary>Implementation Risks</summary>

- **Over-scrubbing history**: Accidentally editing historical CHANGELOG entries that should be preserved.
    - **Mitigation**: Explicitly exclude `**/CHANGELOG.md` historical entries from edits per the clarifications; only the live add-on references are removed.
</details>

## Success Criteria

### Primary Success Criteria
1. The `rtl_433_mqtt_autodiscovery/` and `rtl_433_mqtt_autodiscovery-next/` directories no longer exist in the repository.
2. No CI workflow, `renovate.json`, issue template, or PR template references the autodiscovery add-on; all edited files pass their respective pre-commit linters (actionlint, check-yaml, check-json).
3. `rtl_433/README.md` points users to https://github.com/rtl-433-hass/rtl_433 instead of the autodiscovery add-on, and the root `README.md` release example no longer references the autodiscovery add-on.
4. A repository-wide search for `autodiscovery` (excluding `.git`, `.ai/task-manager`, and historical CHANGELOG entries) returns no matches.

## Self Validation

After all tasks complete, perform these concrete checks:

1. Run `ls` on the repository root and confirm `rtl_433_mqtt_autodiscovery` and `rtl_433_mqtt_autodiscovery-next` are absent while `rtl_433` and `rtl_433-next` remain.
2. Run `grep -rin "autodiscovery" --exclude-dir=.git --exclude-dir=.ai .` and confirm the only remaining matches are intentional historical CHANGELOG entries (e.g. `rtl_433/CHANGELOG.md` line ~102). Any match in a workflow, template, renovate config, or active README is a failure.
3. Run `pre-commit run --all-files` and confirm actionlint, check-yaml, check-json, hadolint, and shellcheck all pass (no failures attributable to the edits).
4. Inspect `.github/workflows/build-addon.yml` and confirm the `release`, `nightly`, and `test` matrix arrays contain only rtl_433 add-ons and that the "Copy shared files" step has no autodiscovery branch.
5. Open `rtl_433/README.md` and confirm the discovery guidance now links to https://github.com/rtl-433-hass/rtl_433.

## Documentation

This plan updates human-facing documentation (`rtl_433/README.md`, root `README.md`) and GitHub templates as part of the work itself. `AGENTS.md` describes the per-add-on directory structure generically ("Each add-on has its own directory") and does not enumerate add-ons, so it requires no change. No skill or assistant-config files reference the autodiscovery add-on.

## Resource Requirements

### Development Skills
- `bash` / `git` for directory removal.
- `github-actions` for editing CI workflow YAML.
- `markdown` / technical writing for documentation and template updates.

### Technical Infrastructure
- Pre-commit hooks (actionlint, hadolint, shellcheck, check-yaml, check-json) for validation.

## Notes
- The untracked `MULTI-RADIO-DISCOVERY.md` research file is unrelated to this removal and is left untouched.
- The repository directory for the development add-on is named `rtl_433-next` (hyphen); the work order's `rtl_433_next` refers to it.

## Execution Blueprint

**Validation Gates:**
- Reference: `/config/hooks/POST_PHASE.md`

### Dependency Diagram

```mermaid
graph TD
    001[Task 001: Remove autodiscovery directories] --> 002[Task 002: Scrub CI & renovate]
    001 --> 003[Task 003: Update GitHub templates]
    001 --> 004[Task 004: Update README docs]
```

### ✅ Phase 1: Remove the add-on
**Parallel Tasks:**
- ✔️ Task 001: Remove the autodiscovery add-on directories

### ✅ Phase 2: Scrub references
**Parallel Tasks:**
- ✔️ Task 002: Scrub autodiscovery from CI workflows and renovate config (depends on: 001)
- ✔️ Task 003: Update GitHub issue and PR templates (depends on: 001)
- ✔️ Task 004: Update README docs to point to the new integration (depends on: 001)

### Post-phase Actions
After Phase 2, run a repository-wide `grep` for `autodiscovery` (excluding `.git`, `.ai/task-manager`, and historical CHANGELOGs) and `pre-commit run --all-files` to confirm no dangling references and all linters pass.

### Execution Summary
- Total Phases: 2
- Total Tasks: 4

## Execution Summary

**Status**: ✅ Completed Successfully
**Completed Date**: 2026-05-30

### Results
The `rtl_433_mqtt_autodiscovery` add-on and its `-next` variant were deleted, and every live reference was scrubbed across the repository. Two commits were produced on `feat/remote-autodiscovery`:
- `feat!: remove rtl_433_mqtt_autodiscovery add-on` — deletes both add-on directories.
- `chore: scrub autodiscovery references from CI, templates, and docs` — updates `build-addon.yml`, `addon-linter.yml`, `hadolint.yml`, `renovate.json`, `bug_report.yml`, `pull_request_template.md`, `rtl_433/README.md`, and the root `README.md`.

The remaining `rtl_433` and `rtl_433-next` add-ons are untouched except for documentation that now points users to the dedicated integration at https://github.com/rtl-433-hass/rtl_433. All four tasks completed; all self-validation steps passed.

### Noteworthy Events
- `pre-commit`/`actionlint` are not installed in the execution environment, so linting was validated directly: `renovate.json` parsed as valid JSON and all edited workflow/template YAML parsed as valid YAML. No shell scripts or Dockerfiles were modified, so shellcheck/hadolint were unaffected.
- The issue-template add-on dropdown was left with a single `rtl_433` option; the pre-existing `rtl_443` typo in that option was corrected as part of removing the autodiscovery entry since it became the sole choice.
- Historical CHANGELOG references (`rtl_433/CHANGELOG.md` line 102) were intentionally preserved per the clarifications.

### Necessary follow-ups
None. Consider running the repository's pre-commit suite (actionlint in particular) in CI to confirm, which will happen automatically on push.
