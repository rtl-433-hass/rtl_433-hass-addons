# rtl_433 Home Assistant Add-on (next)

## About

This is the "next" version of the rtl_433 addon for Home Assistant. It includes
both unreleased changes to the addon itself, and whatever the latest
code from the rtl_433 master branch is available at build time.

When starting, rtl_433 will show the version info such as:

```
[rtl_433] rtl_433 version 22.11-89-g416d6c4f branch master at 202302071819 inputs file rtl_tcp RTL-SDR
```

To find the upstream git commit rtl_433 was built from, drop the leading `g`. In the above example, rtl_433 was built with 89 commits since the 22.11 release, in git commit `416d6c4f`, which can be found at https://github.com/merbanan/rtl_433/commit/416d6c4f9768f22e7b4cfdd684c58df17c946dbc.

Like the stable add-on, this works with **no configuration**: it auto-detects
every connected RTL-SDR dongle and runs one rtl_433 process per dongle using a
built-in default config, assigning each a stable port starting at `8433`. The
[rtl_433 integration for Home Assistant](https://github.com/rtl-433-hass/rtl_433)
connects to `ws://<addon-host>:<port>/ws` to consume the data.

To customize a radio, create an `<id>.conf` override file in the add-on config
directory (`/addon_configs/rtl433-next/`); the exact filename for each detected
radio is printed in the add-on log. Override directives are appended to the
default and win on conflict. The **Log received messages** option (Configuration
tab) adds `output kv` so decoded events show in the log. See the
[stable add-on README](../rtl_433/README.md) for full configuration details.

To update rtl_433 to the latest version, uninstall and reinstall the addon.
