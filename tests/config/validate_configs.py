#!/usr/bin/env python3
"""Validate the rtl_433 add-ons' config.json/build.json invariants.

Standard-library only. Run as:

    python3 tests/config/validate_configs.py

Exits 0 if every add-on passes, otherwise prints a per-add-on error report
and exits 1.
"""

import json
import sys
from pathlib import Path

# The script lives in tests/config/, so the repo root is two levels up.
REPO_ROOT = Path(__file__).resolve().parents[2]

ADDONS = ["rtl_433", "rtl_433-next"]

REQUIRED_CONFIG_FIELDS = ["name", "version", "slug", "description", "arch", "image"]
REQUIRED_ARCHES = ["aarch64", "amd64"]

# Host port -> container port. Couples to run.sh BASE_PORT=8433 / MAX_RADIOS=10.
EXPECTED_PORTS = {f"{p}/tcp": p for p in range(8433, 8443)}

# Radio-optimization options: key -> (expected default, expected schema type).
RADIO_OPT_OPTIONS = {
    "correct_ppm_offset": (False, "bool"),
    "detect_noise_floor": (False, "bool"),
    "noise_floor_bands": ("433.92M,868M,915M", "str"),
}


def load_json(path):
    """Return (data, error). On success error is None; on failure data is None."""
    if not path.exists():
        return None, f"missing file: {path}"
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh), None
    except (json.JSONDecodeError, OSError) as exc:
        return None, f"could not parse {path}: {exc}"


def is_valid_version(version):
    """Accept the literal 'next' or a dotted-numeric semver like '0.2.0'."""
    if version == "next":
        return True
    if not isinstance(version, str):
        return False
    parts = version.split(".")
    return len(parts) > 0 and all(part.isdigit() for part in parts)


def validate_config_json(addon, addon_dir, errors):
    config, err = load_json(addon_dir / "config.json")
    if err is not None:
        errors.append(err)
        return

    # Required fields.
    for field in REQUIRED_CONFIG_FIELDS:
        if field not in config:
            errors.append(f"config.json: missing required field '{field}'")

    # Architecture coverage.
    arch = config.get("arch", [])
    for required_arch in REQUIRED_ARCHES:
        if required_arch not in arch:
            errors.append(
                f"config.json: 'arch' must include '{required_arch}'; got {arch}"
            )

    # Version format.
    version = config.get("version")
    if not is_valid_version(version):
        errors.append(
            f"config.json: 'version' must be dotted-numeric (e.g. 0.2.0) or "
            f"'next'; got {version!r}"
        )

    # Image registry.
    image = config.get("image", "")
    if not (isinstance(image, str) and image.startswith("ghcr.io/")):
        errors.append(
            f"config.json: 'image' must start with 'ghcr.io/'; got {image!r}"
        )

    # schema / options consistency.
    options = config.get("options")
    schema = config.get("schema")
    if isinstance(options, dict) and isinstance(schema, dict):
        for key in sorted(set(options) ^ set(schema)):
            if key not in schema:
                errors.append(
                    f"config.json: option '{key}' has no matching 'schema' entry"
                )
            else:
                errors.append(
                    f"config.json: schema '{key}' has no matching 'options' entry"
                )

    # Radio-optimization options must be present with expected defaults/types.
    if isinstance(options, dict) and isinstance(schema, dict):
        for key, (default, schema_type) in RADIO_OPT_OPTIONS.items():
            if key not in options:
                errors.append(
                    f"config.json: 'options' must include '{key}'"
                )
            elif options[key] != default:
                errors.append(
                    f"config.json: option '{key}' must default to {default!r}; "
                    f"got {options[key]!r}"
                )
            if key not in schema:
                errors.append(
                    f"config.json: 'schema' must include '{key}'"
                )
            elif schema[key] != schema_type:
                errors.append(
                    f"config.json: schema '{key}' must be {schema_type!r}; "
                    f"got {schema[key]!r}"
                )

    # Ports map (repo-specific invariant).
    ports = config.get("ports")
    if ports != EXPECTED_PORTS:
        errors.append(
            f"config.json: 'ports' must be exactly {EXPECTED_PORTS} "
            f"(matches run.sh BASE_PORT=8433/MAX_RADIOS=10); got {ports}"
        )

    # Discovery and HA integration flags.
    discovery = config.get("discovery", [])
    if "rtl_433" not in discovery:
        errors.append(
            f"config.json: 'discovery' must include 'rtl_433'; got {discovery}"
        )
    for flag in ["hassio_api", "usb", "udev"]:
        if config.get(flag) is not True:
            errors.append(
                f"config.json: '{flag}' must be true; got {config.get(flag)!r}"
            )


def validate_build_json(addon, addon_dir, errors):
    build, err = load_json(addon_dir / "build.json")
    if err is not None:
        errors.append(err)
        return

    build_from = build.get("build_from")
    if not isinstance(build_from, dict):
        errors.append(
            f"build.json: 'build_from' must be an object; got {build_from!r}"
        )
        return
    for required_arch in REQUIRED_ARCHES:
        if required_arch not in build_from:
            errors.append(
                f"build.json: 'build_from' must include '{required_arch}'; "
                f"got keys {sorted(build_from)}"
            )


def main():
    overall_ok = True

    for addon in ADDONS:
        addon_dir = REPO_ROOT / addon
        errors = []

        validate_config_json(addon, addon_dir, errors)
        validate_build_json(addon, addon_dir, errors)

        if errors:
            overall_ok = False
            print(f"FAIL {addon}: {len(errors)} problem(s)")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"OK   {addon}: all config checks passed")

    sys.exit(0 if overall_ok else 1)


if __name__ == "__main__":
    main()
