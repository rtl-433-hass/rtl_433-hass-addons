# AI Agent Guidelines

This repository contains Home Assistant add-ons for rtl_433.

## Commit Style

Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` new features
- `fix:` bug fixes
- `docs:` documentation
- `style:` formatting, whitespace
- `refactor:` code restructuring
- `perf:` performance improvements
- `test:` adding/updating tests
- `build:` build system changes
- `ci:` CI/workflow changes
- `chore:` maintenance (deps, etc.)
- `revert:` reverting changes

Commits that only touch AI task-manager artifacts under `.ai/task-manager/`
(plans, tasks, blueprints, execution summaries, archival) use `chore` (e.g.
`chore(tasks): ...`), **not** `docs`. The `docs` type is reserved for changes to
human- or assistant-facing documentation such as `README.md` or this file.

Create unique commits for each step in a process, as long as pre-commit hooks pass. Structure commits so the reviewer has the option of squashing the commits or rebasing and merging them all.

## Linting

Pre-commit hooks run automatically. Key linters:
- **shellcheck** - shell scripts
- **hadolint** - Dockerfiles
- **actionlint** - GitHub Actions workflows
- **check-yaml/check-json** - config files

Run manually: `pre-commit run --all-files`

## GitHub Actions

When creating or modifying GitHub Actions workflows, always check the repository for existing references to external actions. Use the same action references (including the commit hash and version comment) that are already in use. This ensures consistency and avoids introducing different versions of the same action.

## Structure

Each add-on has its own directory:
- `config.json` - add-on metadata and version
- `Dockerfile` - container build
- `run.sh` - entrypoint script
- `CHANGELOG.md` - version history
- `rtl_433/rtl_433.defaults.conf` - the internal default rtl_433 config baked
  into the image (copied to `/etc/rtl_433/rtl_433.defaults.conf`). It is not
  user-editable; user customization happens via per-radio `<id>.conf` override
  files that are appended to it.

User override files live in the **add-on config directory** (the `addon_config`
map, reachable at `/addon_configs/<slug>/`), **not** the Home Assistant config
directory. The add-on auto-detects connected RTL-SDR dongles and renders each
radio's config from the baked-in default plus any matching override file.

The add-on exposes three radio-optimization options (in `config.json` and
`run.sh`): `correct_ppm_offset` (auto-measure each radio's crystal PPM offset),
`detect_noise_floor` (sweep the ambient noise floor), and `noise_floor_bands` (a
comma-separated list of center frequencies the noise-floor sweep uses). These
rely on `rtl_test`, `rtl_power`, and `gnuplot`, which are now part of the image.
The per-radio measured PPM offsets are cached in the **add-on config directory**
as `<id>.ppm` (next to each radio's `<id>.conf` override; `ppm_cache_dir`
defaults to `conf_directory`), so the slow `rtl_test` measurement runs once and
is reused on later boots, and the user can delete the file to re-measure or
return to defaults. Noise-floor reports are written to the same config
directory.

The `-next` variants are development versions built from `main`.

## Releases & Changelogs

Releases are managed by [release-please](https://github.com/googleapis/release-please)
(`release-please-config.json` + `.release-please-manifest.json`). On each push to
`main` it maintains a release PR; merging that PR tags the release, bumps
`rtl_433/config.json` `$.version`, and prepends a new entry to
`rtl_433/CHANGELOG.md` derived from Conventional Commits.

Because of this:
- **Do not hand-edit `rtl_433/CHANGELOG.md` for releases, and do not add an
  `[Unreleased]` section.** The open release PR is the "unreleased" view; it is
  built automatically from commit messages. Accurate Conventional Commit
  messages are what produce good changelog entries.
- This project is a fork but is versioned independently as a new, parallel
  add-on, so its version numbers were reset and start at `0.1.0`. Entries below
  the latest release in `rtl_433/CHANGELOG.md` are pre-fork history kept for
  reference.
- The `-next` add-on is a rolling build with no version numbers, so it is **not**
  a release-please package. Its `CHANGELOG.md` just links to the `main` commit
  history rather than carrying per-release notes.

## Pull Requests

The pull request title should always be the value of the first commit in the branch.

## Testing

Pre-commit hooks still run the linters (shellcheck, hadolint, actionlint,
check-yaml/json) automatically.

Automated tests run in CI on every push/PR and can also be run locally:
- **BATS unit tests** for the `rtl_433/run.sh` helper functions:
  `bats -r tests/` (the `-r` is required so bats recurses into
  `tests/rtl_433/`).
- **Container smoke test** — builds `./rtl_433` and checks the binary plus the
  baked-in configs; see `.github/workflows/smoke-tests.yml`.
- **Config validation**: `python3 tests/config/validate_configs.py`.

`run.sh` is `main()`-guarded so its functions can be sourced by the tests
without running the entrypoint. See `tests/README.md` for layout and fixture
conventions.
