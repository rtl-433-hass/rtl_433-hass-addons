#!/usr/bin/env python3
"""Validate Home Assistant addon configurations for consistency and correctness."""

import json
import sys
from pathlib import Path

# Define the addons to validate
ADDONS = [
    "rtl_433",
    "rtl_433-next",
    "rtl_433_mqtt_autodiscovery",
    "rtl_433_mqtt_autodiscovery-next",
]

# Required fields in config.json
REQUIRED_CONFIG_FIELDS = [
    "name",
    "version",
    "slug",
    "description",
    "arch",
    "image",
]

# Required fields in build.json
REQUIRED_BUILD_FIELDS = [
    "build_from",
]

# Expected architectures
EXPECTED_ARCHS = ["aarch64", "amd64"]


def load_json(path: Path) -> dict:
    """Load and parse a JSON file."""
    with open(path) as f:
        return json.load(f)


def validate_config_json(addon_path: Path, addon_name: str) -> list[str]:
    """Validate config.json for an addon."""
    errors = []
    config_path = addon_path / "config.json"

    if not config_path.exists():
        errors.append(f"{addon_name}: config.json not found")
        return errors

    try:
        config = load_json(config_path)
    except json.JSONDecodeError as e:
        errors.append(f"{addon_name}: Invalid JSON in config.json: {e}")
        return errors

    # Check required fields
    for field in REQUIRED_CONFIG_FIELDS:
        if field not in config:
            errors.append(f"{addon_name}: Missing required field '{field}' in config.json")

    # Check architectures
    if "arch" in config:
        archs = config["arch"]
        for expected in EXPECTED_ARCHS:
            if expected not in archs:
                errors.append(f"{addon_name}: Missing architecture '{expected}' in config.json")

    # Check version format
    if "version" in config:
        version = config["version"]
        if version != "next" and not version.replace(".", "").isdigit():
            # Allow semver-like versions and "next"
            parts = version.split(".")
            if not all(p.isdigit() for p in parts):
                errors.append(
                    f"{addon_name}: Invalid version format '{version}' "
                    "(expected semver or 'next')"
                )

    # Check image naming convention
    if "image" in config:
        image = config["image"]
        if not image.startswith("ghcr.io/"):
            errors.append(f"{addon_name}: Image should use ghcr.io registry: {image}")
        if "{arch}" not in image:
            errors.append(f"{addon_name}: Image should contain '{{arch}}' placeholder: {image}")

    # Check schema matches options
    if "options" in config and "schema" in config:
        options_keys = set(config["options"].keys())
        schema_keys = set(config["schema"].keys())
        missing_in_schema = options_keys - schema_keys
        if missing_in_schema:
            errors.append(
                f"{addon_name}: Options keys missing from schema: {missing_in_schema}"
            )

    return errors


def validate_build_json(addon_path: Path, addon_name: str) -> list[str]:
    """Validate build.json for an addon."""
    errors = []
    build_path = addon_path / "build.json"

    if not build_path.exists():
        errors.append(f"{addon_name}: build.json not found")
        return errors

    try:
        build = load_json(build_path)
    except json.JSONDecodeError as e:
        errors.append(f"{addon_name}: Invalid JSON in build.json: {e}")
        return errors

    # Check required fields
    for field in REQUIRED_BUILD_FIELDS:
        if field not in build:
            errors.append(f"{addon_name}: Missing required field '{field}' in build.json")

    # Check build_from has entries for all architectures
    if "build_from" in build:
        build_from = build["build_from"]
        for arch in EXPECTED_ARCHS:
            if arch not in build_from:
                errors.append(
                    f"{addon_name}: Missing build_from for architecture '{arch}'"
                )

    return errors


def validate_consistency(addon_pairs: list[tuple[str, str]]) -> list[str]:
    """Validate consistency between stable and -next addon pairs."""
    errors = []
    repo_root = Path(__file__).parent.parent.parent

    for stable, next_addon in addon_pairs:
        stable_path = repo_root / stable / "config.json"
        next_path = repo_root / next_addon / "config.json"

        if not stable_path.exists() or not next_path.exists():
            continue

        try:
            stable_config = load_json(stable_path)
            next_config = load_json(next_path)
        except json.JSONDecodeError:
            continue

        # Check that schemas match between stable and next
        stable_schema = stable_config.get("schema", {})
        next_schema = next_config.get("schema", {})

        # Allow next to have additional fields (like "master")
        for key in stable_schema:
            if key not in next_schema:
                errors.append(
                    f"Schema mismatch: '{key}' in {stable} but not in {next_addon}"
                )
            elif stable_schema[key] != next_schema[key]:
                errors.append(
                    f"Schema mismatch: '{key}' has different definition "
                    f"in {stable} vs {next_addon}"
                )

        # Check that options match (stable should be subset of next)
        stable_options = set(stable_config.get("options", {}).keys())
        next_options = set(next_config.get("options", {}).keys())
        missing_in_next = stable_options - next_options
        if missing_in_next:
            errors.append(
                f"Options mismatch: {missing_in_next} in {stable} but not in {next_addon}"
            )

    return errors


def validate_files_exist(addon_path: Path, addon_name: str) -> list[str]:
    """Check that required files exist."""
    errors = []

    # All addons require these files
    required_files = ["config.json", "build.json"]

    # -next addons may share Dockerfile and run.sh with their stable counterpart
    # They use the Home Assistant builder's ability to reference other directories
    is_next_addon = addon_name.endswith("-next")
    if not is_next_addon:
        required_files.extend(["Dockerfile", "run.sh"])

    for filename in required_files:
        if not (addon_path / filename).exists():
            errors.append(f"{addon_name}: Missing required file '{filename}'")

    return errors


def main() -> int:
    """Main validation function."""
    repo_root = Path(__file__).parent.parent.parent
    all_errors = []

    print("Validating addon configurations...")
    print("=" * 60)

    # Validate each addon
    for addon_name in ADDONS:
        addon_path = repo_root / addon_name
        if not addon_path.exists():
            all_errors.append(f"{addon_name}: Addon directory not found")
            continue

        print(f"\nValidating {addon_name}...")

        # Run all validations
        errors = []
        errors.extend(validate_files_exist(addon_path, addon_name))
        errors.extend(validate_config_json(addon_path, addon_name))
        errors.extend(validate_build_json(addon_path, addon_name))

        if errors:
            for error in errors:
                print(f"  ERROR: {error}")
            all_errors.extend(errors)
        else:
            print("  OK")

    # Validate consistency between pairs
    print("\nValidating consistency between stable and next versions...")
    addon_pairs = [
        ("rtl_433", "rtl_433-next"),
        ("rtl_433_mqtt_autodiscovery", "rtl_433_mqtt_autodiscovery-next"),
    ]
    consistency_errors = validate_consistency(addon_pairs)
    if consistency_errors:
        for error in consistency_errors:
            print(f"  ERROR: {error}")
        all_errors.extend(consistency_errors)
    else:
        print("  OK")

    # Summary
    print("\n" + "=" * 60)
    if all_errors:
        print(f"FAILED: {len(all_errors)} error(s) found")
        return 1
    else:
        print("PASSED: All validations successful")
        return 0


if __name__ == "__main__":
    sys.exit(main())
