# rtl_433 Home Assistant Add-ons

These add-ons run [rtl_433](https://github.com/merbanan/rtl_433) under the Home Assistant Supervisor so Home Assistant can receive data from wireless sensors through software-defined radio (SDR) receivers.

The default add-on works with no file editing: install it, plug in one or more RTL-SDR dongles, start the add-on, and connect the companion [rtl_433 Home Assistant integration](https://rtl-433-hass.github.io/rtl_433/latest/) to the radio WebSocket endpoints.

## Add-ons

| Add-on | Purpose |
| --- | --- |
| `rtl_433` | The stable version of this add-on, including the most recent stable version of rtl_433. |
| `rtl_433 (next)` | Development add-on built from `main` and the current upstream rtl_433 source. |

## How It Works

On startup the add-on auto-detects every connected RTL-SDR dongle and launches one rtl_433 process per radio. (Throughout these docs, a *radio* is a single rtl_433 process bound to one device — usually a dongle, but also a manually declared SoapySDR or HackRF device.) Each radio gets an HTTP/WebSocket endpoint with a predictable TCP port starting at `8433`; the second radio gets `8434`, and so on, up to the configured port range.

The add-on publishes Supervisor discovery data for each radio on a best-effort basis. The companion integration consumes that discovery data when available, or you can add the integration manually with the add-on host, port, and `/ws` path.

## Start Here

- [Installation](installation.md) covers installing the repository, starting the add-on, and connecting the integration.
- [Configuration](configuration.md) covers add-on options, per-radio overrides, PPM correction, noise-floor scans, serial randomization, and replacing radios.
- [Advanced](advanced.md) covers SoapySDR/HackRF devices, logging, signal-level metadata, migration from the old config path, and discovery payload details.
