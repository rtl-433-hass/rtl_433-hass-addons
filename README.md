# rtl_433 Home Assistant add-ons

This is a collection of Home Assistant add-ons that work with [rtl_433](https://github.com/merbanan/rtl_433).

* [How to add this add-on repository to your Home Assistant install](https://home-assistant.io/hassio/installing_third_party_addons/)
* Use `https://github.com/pbkhrv/rtl_433-hass-addons` as the URL for the repository.

## Running the Development Version

- First, follow the tutorial at [Tutorial: Making your first add-on](https://developers.home-assistant.io/docs/add-ons/tutorial/) to learn how to build a basic addon.
- Use `git` to clone this repository same `addons` folder used in the tutorial.
- Make changes to the code, or use `git` to checkout branches to test.
- Remember to to [reload](https://developers.home-assistant.io/docs/add-ons/tutorial/#i-dont-see-my-add-on) and reinstall the addon to rebuild the Docker containers to see any changes.

## Release Process

All development happens on the `main` branch. The `-next` addons are built automatically on every push to `main`, while stable addons are only built when a release tag is created.

### Automatic Builds

| Event | What gets built | Version |
|-------|-----------------|---------|
| Push to `main` | `-next` addons only | `next` |
| Daily schedule | `-next` addons only | `next` |
| Tag push (`2025.01.15.0`) | Stable addons only | From `config.json` |

### Creating a Release

1. Create a pull request bumping the versions in [rtl_433/config.json](rtl_433/config.json) and/or [rtl_433_mqtt_autodiscovery/config.json](rtl_433_mqtt_autodiscovery/config.json). Update the corresponding `CHANGELOG.md` files.
2. After the PR is merged, create a date-based tag (e.g., `2025.01.15.0`) on the merge commit. This triggers the stable addon builds.

That's it! No branch reconciliation needed. Stable users see "Update Available" when the new version is published.
