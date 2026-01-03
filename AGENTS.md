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

## Release Process

1. Bump version in `config.json`
2. Update `CHANGELOG.md`
3. Merge to `main`
4. Tag with date format: `YYYY.MM.DD.N` (e.g., `2025.01.15.0`)

## Testing

Before committing:
- Verify JSON syntax in config files
- Run `shellcheck` on shell scripts
- Run `hadolint` on Dockerfiles
