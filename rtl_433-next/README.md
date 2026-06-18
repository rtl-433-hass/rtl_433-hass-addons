# rtl_433 Home Assistant Add-on (next)

This is the development version of the rtl_433 Home Assistant add-on. It includes unreleased add-on changes and the latest available upstream rtl_433 source at build time.

Use this channel when you need a development fix or newer upstream decoder support and are comfortable with a less stable add-on.

## Documentation

Full documentation is published at:

https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/

Start with:

- [Installation](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/installation/)
- [Configuration](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/configuration/)
- [Advanced topics](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/advanced/)

## Notes

The add-on works like the stable channel: it auto-detects RTL-SDR dongles, starts one rtl_433 process per radio, and exposes each radio at `/ws` on ports starting at `8433`.

Per-radio override files live in `/addon_configs/rtl433-next/`. The add-on log prints the exact `<id>.conf` filename for each detected radio.

To see which upstream rtl_433 commit was built, check the rtl_433 version line in the add-on log and drop the leading `g` from the reported commit token.
