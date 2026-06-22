# Installation

## Prerequisites

You need:

1. Home Assistant OS or another Supervisor-based installation that supports add-ons.
2. An SDR supported by rtl_433, usually an RTL-SDR USB dongle.
3. Wireless sensors supported by rtl_433.
4. The companion [rtl_433 Home Assistant integration](https://rtl-433-hass.github.io/rtl_433/latest/) to create Home Assistant devices and entities from the decoded data.

The upstream rtl_433 hardware and protocol references are useful when choosing radios and sensors:

- [rtl_433 hardware documentation](https://triq.org/rtl_433/HARDWARE.html)
- [rtl_433 supported protocols](https://github.com/merbanan/rtl_433/blob/master/README.md)

## Add the Repository

1. In Home Assistant, open **Settings -> Add-ons -> Add-on Store**.
2. Open the menu and choose **Repositories**.
3. Add `https://github.com/rtl-433-hass/rtl_433-hass-addons`.
4. Install `rtl_433` for the stable add-on, or `rtl_433 (next)` if you intentionally want the development build.

## Start the Add-on

1. Plug the SDR dongle or dongles into the Home Assistant host.
2. Start the add-on.
3. Open the add-on log and look for one line per radio similar to:

```text
Radio <id> -> HTTP port <port>. To customize, create /config/<id>.conf.
Radio <id>: unique_id=<serial:...|usbpath:...> host=<host> port=<port>
```

The `<id>` identifies the radio for per-radio override files. The `unique_id`, host, and port identify the radio for the Home Assistant integration.

## Connect Home Assistant

Install the companion [rtl_433 integration](https://rtl-433-hass.github.io/rtl_433/latest/) and add one hub per radio. The default connection values are:

| Field | Value |
| --- | --- |
| Host | The add-on host shown in the add-on log or Supervisor discovery |
| Port | `8433` for the first radio, `8434` for the second, and so on |
| Path | `/ws` |
| Secure | Off |

The add-on's built-in config already includes `output http://0.0.0.0:<port>`, so you do not need to add an output line yourself.

## Development Add-on

`rtl_433 (next)` is a rolling development build. It includes unreleased add-on changes and the latest available upstream rtl_433 source at build time. Use it when you need a development fix or newer upstream decoder support and are comfortable with a less stable channel.

To find the upstream rtl_433 commit in use, check the add-on log. rtl_433 prints a version line such as:

```text
[rtl_433] rtl_433 version 22.11-89-g416d6c4f branch master at 202302071819 inputs file rtl_tcp RTL-SDR
```

Drop the leading `g` from `g416d6c4f` to get the upstream commit hash.
