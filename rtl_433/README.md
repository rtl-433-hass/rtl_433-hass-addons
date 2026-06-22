# rtl_433 Home Assistant Add-on

This add-on runs [rtl_433](https://github.com/merbanan/rtl_433) under the Home Assistant Supervisor so Home Assistant can receive wireless sensor data from SDR radios.

It works with no file editing for the common case: install the add-on, plug in one or more RTL-SDR dongles, start it, then connect the companion [rtl_433 Home Assistant integration](https://rtl-433-hass.github.io/rtl_433/latest/) to each radio's WebSocket endpoint.

## Documentation

Full documentation is published at:

https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/

Key pages:

- [Installation](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/installation/)
- [Configuration](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/configuration/)
- [Advanced topics](https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/advanced/)

## Quick Start

1. Install this add-on from `https://github.com/rtl-433-hass/rtl_433-hass-addons`.
2. Plug the SDR dongle or dongles into the Home Assistant host.
3. Start the add-on.
4. Check the add-on log for each radio's host, port, and stable `unique_id`.
5. Add the companion rtl_433 integration in Home Assistant and connect it to each radio. The first radio usually uses port `8433` and path `/ws`.

Per-radio override files live in the add-on config directory, reachable as `/addon_configs/rtl433/`. The add-on log prints the exact `<id>.conf` filename for each detected radio.
