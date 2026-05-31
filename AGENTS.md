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

Rely on pre-commit hooks to run all checks automatically.
