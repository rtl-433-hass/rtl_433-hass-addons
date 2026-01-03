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

## Structure

Each add-on has its own directory:
- `config.json` - add-on metadata and version
- `Dockerfile` - container build
- `run.sh` - entrypoint script
- `CHANGELOG.md` - version history

The `-next` variants are development versions built from `main`.

## Testing

Rely on pre-commit hooks to run all checks automatically.
