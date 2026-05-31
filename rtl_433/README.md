# rtl_433 Home Assistant Add-on

## About

This add-on is a simple wrapper around the excellent [rtl_433](https://github.com/merbanan/rtl_433) project that receives wireless sensor data via [one of the supported SDR dongles](https://triq.org/rtl_433/HARDWARE.html), decodes and outputs it in a variety of formats. The wireless sensors rtl_433 understands transmit data mostly on 433.92 MHz, 868 MHz, 315 MHz, 345 MHz, and 915 MHz ISM bands.

[View the rtl_433 documentation](https://triq.org/rtl_433)

## How it works

This add-on runs rtl_433 under the Home Assistant OS supervisor. It works with **no configuration**: just install it, plug in your dongle(s), and start it.

On start, the add-on auto-detects every connected RTL-SDR dongle and runs one rtl_433 process per dongle, using an internal default config baked into the image. Each process exposes rtl_433's built-in HTTP/WebSocket server with an `output http://0.0.0.0:<port>` line that the default config already provides. The add-on assigns each radio a stable TCP port starting at `8433` (the second radio gets `8434`, and so on, up to a maximum of 10 radios). Ports are assigned deterministically, so a given radio keeps the same port across restarts.

The [rtl_433 integration for Home Assistant](https://github.com/rtl-433-hass/rtl_433) is the consumer of this data: it connects to each radio over `ws://<addon-host>:<port>/ws` and discovers and configures your devices automatically.

The add-on also publishes each radio to Home Assistant's Supervisor discovery API (best-effort). Full automatic setup depends on the rtl_433 integration adding Supervisor discovery support, which it does not have yet. Until then, add the integration manually in **Settings -> Devices & Services -> rtl_433**, supplying the add-on host and the radio's port.

Each discovery message carries a stable `unique_id` so the integration can keep the same config entry for a radio across restarts and port reassignments. The add-on derives it, in order of preference, from:

 1. the dongle's **USB serial**, when it is unique and not the factory default (this survives moving the dongle to a different USB port);
 2. otherwise the dongle's **USB port path** — which physical port it is plugged into (stable as long as the dongle stays in that port);
 3. otherwise the **configuration template's name** (a deterministic last resort for devices the add-on can't match to a USB RTL-SDR entry, such as SoapySDR/HackRF devices).

Because nearly all RTL-SDR dongles ship with the same default serial (`00000001`), multi-dongle setups get the most stable identity either by keeping each dongle in a fixed USB port or by flashing a unique serial with `rtl_eeprom -s <serial>` (a one-time step performed outside the add-on).

## Prerequisites

 To use this add-on, you need the following:

 1. [An SDR dongle supported by rtl_433](https://triq.org/rtl_433/HARDWARE.html).

 2. Home Assistant OS running on a machine with the SDR dongle plugged into it.

 3. Some wireless sensors supported by rtl_433. The full list of supported protocols and devices can be found under "Supported device protocols" section of the [rtl_433's README](https://github.com/merbanan/rtl_433/blob/master/README.md).

## Installation

 1. Install the add-on.

 2. Plug your SDR dongle(s) into the machine running the add-on.

 3. Start the add-on. No configuration is required — it auto-detects every connected RTL-SDR dongle and starts one rtl_433 process per dongle using a built-in default config.

 4. Check the logs. For each detected radio the add-on prints a line like:

    ```
    Radio <id> -> HTTP port <port>. To customize, create /config/<id>.conf.
    ```

    The `<id>` is that radio's stable identifier (its USB serial when usable, otherwise its USB port path). You only need this if you want to customize a radio (see [Configuration](#configuration) below).

 5. Install the dedicated [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433) in Home Assistant and point it at the add-on host and each radio's port.

## Configuration

For a "zero configuration" setup, just start the add-on and install the dedicated [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433). The built-in default config captures common protocols (and disables noisy TPMS protocols) and exposes the data over rtl_433's HTTP/WebSocket server, which the integration consumes. **No file editing is required for the default case.**

### Per-radio overrides

To customize a specific radio, create an override file named after that radio's identifier. Each detected radio's exact override filename is printed in the add-on log on start, for example:

```
Radio <id> -> HTTP port <port>. To customize, create /config/<id>.conf.
```

Create that `<id>.conf` file in the **add-on config directory**. From Home Assistant this directory is reachable at `/addon_configs/rtl433/` (use the Samba, File Editor, or Studio Code Server add-ons to edit files there). So a radio logged as `Radio AB12CD34 -> ...` is customized by creating `/addon_configs/rtl433/AB12CD34.conf`.

Put **only the extra directives you want** in the override file — they are appended to the internal default config, and on any conflict the override wins (rtl_433 applies the last matching directive). For example:

```
frequency 868M
protocol  40
convert   si
```

Notes:

 - The default already provides `output http://0.0.0.0:${port}`, so **do not add an `output http://...` line yourself**; the `${port}` placeholder is filled in with the radio's assigned port automatically.
 - **Overriding `device` is discouraged**: it breaks the file-to-radio mapping the add-on relies on.
 - Because the file is rendered through a shell heredoc, **dollar signs and other special shell characters need to be escaped**. For example, to use the literal string `$GPRMC`, write `\$GPRMC`.

For the full list of available directives, see the example config in the rtl_433 source: [rtl_433.example.conf](https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf), the [official rtl_433 documentation](https://triq.org/rtl_433), and the supported protocol list in the [rtl_433 README](https://github.com/merbanan/rtl_433/blob/master/README.md).

An override file whose name does not match any detected radio is ignored, and the add-on logs a warning so a typo or an unplugged dongle does not silently do nothing.

### Logging

The **Log received messages** option (in the add-on's Configuration tab) appends `output kv` to each radio's config so decoded events appear in the add-on log. This is useful for confirming that sensors are being received. The rtl_433 diagnostic `output log` is intentionally **not** bundled, to keep the log readable.

### Breaking change / migration

Earlier versions of this add-on read config files from `/config/rtl_433/` in the **Home Assistant config directory**. That location is **no longer read**. Move any per-radio tuning into `<id>.conf` files in the **add-on config directory** (`/addon_configs/rtl433/`) as described above. There is no longer a separate config file for the default case — the default is baked into the image.

### Limitation

Auto-detection enumerates **RTL-SDR** dongles only (via the kernel's USB device table). Non-RTL-SDR SDRs such as SoapySDR or HackRF devices are **not** auto-detected and will not be launched by this add-on.

## Credit

This add-on is based on James Fry's [rtl4332mqtt Hass.IO Add-on](https://github.com/james-fry/hassio-addons/tree/master/rtl4332mqtt), which is in turn based on Chris Kacerguis' project here: [https://github.com/chriskacerguis/honeywell2mqtt](https://github.com/chriskacerguis/honeywell2mqtt), which is in turn based on Marco Verleun's rtl2mqtt image here: [https://github.com/roflmao/rtl2mqtt](https://github.com/roflmao/rtl2mqtt).
