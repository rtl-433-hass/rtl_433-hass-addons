# rtl_433 Home Assistant Add-on

## About

This add-on is a simple wrapper around the excellent [rtl_433](https://github.com/merbanan/rtl_433) project that receives wireless sensor data via [one of the supported SDR dongles](https://triq.org/rtl_433/HARDWARE.html), decodes and outputs it in a variety of formats. The wireless sensors rtl_433 understands transmit data mostly on 433.92 MHz, 868 MHz, 315 MHz, 345 MHz, and 915 MHz ISM bands.

[View the rtl_433 documentation](https://triq.org/rtl_433)

## How it works

This add-on runs rtl_433 under the Home Assistant OS supervisor. All you have to do is supply a config file.

Each radio runs its own rtl_433 process, and each process exposes rtl_433's built-in HTTP/WebSocket server with an `output http://0.0.0.0:<port>` line in its config. The add-on assigns each radio a stable TCP port starting at `8433` (the second radio gets `8434`, and so on, up to a maximum of 10 radios). Ports are assigned deterministically by sorting the templates by their `device` value, so a given radio keeps the same port across restarts.

The [rtl_433 integration for Home Assistant](https://github.com/rtl-433-hass/rtl_433) is the consumer of this data: it connects to each radio over `ws://<addon-host>:<port>/ws` and discovers and configures your devices automatically.

The add-on also publishes each radio to Home Assistant's Supervisor discovery API (best-effort). Full automatic setup depends on the rtl_433 integration adding Supervisor discovery support, which it does not have yet. Until then, add the integration manually in **Settings -> Devices & Services -> rtl_433**, supplying the add-on host and the radio's port.

## Prerequisites

 To use this add-on, you need the following:

 1. [An SDR dongle supported by rtl_433](https://triq.org/rtl_433/HARDWARE.html).

 2. Home Assistant OS running on a machine with the SDR dongle plugged into it.

 3. Some wireless sensors supported by rtl_433. The full list of supported protocols and devices can be found under "Supported device protocols" section of the [rtl_433's README](https://github.com/merbanan/rtl_433/blob/master/README.md).

## Installation

 1. Create an rtl_433 config file that does what you need. It might work better if you do this on a computer other than the one running Home Assistant OS, so that you can experiment freely and iterate until you arrive at a configuration that works well. See below for more details.

 2. Upload the config file into Home Assistant's "/config" directory using whatever method works for you (via Samba add-on, ssh/scp, File Editor add-on etc).

 3. Install the add-on.

 5. Plug your SDR dongle to the machine running the add-on.

 5. Start the addon. A default configuration will be created in `/config/rtl_433/`. To add or edit additional configurations, create multiple `.conf.template` files in that directory.

 6. Start the add-on and check the logs.

## Configuration

For a "zero configuration" setup, just start the add-on with the default config and install the dedicated [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433). The default configuration captures known 433 MHz protocols and exposes them over rtl_433's HTTP/WebSocket server, which the integration consumes.

For more advanced configuration, take a look at the example config file included in the rtl_433 source code: [rtl_433.example.conf](https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf)

Note that since the configuration file has bash variables in it, **dollar signs and other special shell characters need to be escaped**. For example, to use the literal string `$GPRMC` in the configuration file, use `\$GPRMC`.

When configuring manually, assuming that you intend to get the rtl_433 data into Home Assistant, the absolute minimum that you need to specify in the config file is the [HTTP output](https://triq.org/rtl_433/OPERATION.html#http-server). The add-on fills in the radio's assigned port via the `${port}` placeholder, so use:

```
output      http://0.0.0.0:${port}
```

This makes rtl_433 expose its decoded events over an HTTP/WebSocket server on the port the add-on assigned to this radio (the first radio gets `8433`, the next `8434`, and so on). The Home Assistant rtl_433 integration then connects to `ws://<addon-host>:<port>/ws` to receive the data.

rtl_433 defaults to listening on 433.92MHz, but even if that's what you need, it's probably a good idea to specify the frequency explicitly to avoid confusion:

```
frequency   433.92M
```

You might also want to narrow down the list of protocols that rtl_433 should try to decode. The full list can be found under "Supported device protocols" section of the [README](https://github.com/merbanan/rtl_433/blob/master/README.md). Let's say you want to listen to Acurite 592TXR temperature/humidity sensors:

```
protocol    40
```

Last but not least, the rtl_433 integration's documentation recommends converting units in all of the data coming out of rtl_433 into SI:

```
convert     si
```

Assuming you have only one USB dongle attached and rtl_433 is able to automatically find it, we arrive at a minimal rtl_433 config file that looks like this:

```
output      http://0.0.0.0:${port}

frequency   433.92M
protocol    40

convert     si
```

Please check [the official rtl_433 documentation](https://triq.org/rtl_433) and [config file examples](https://github.com/merbanan/rtl_433/tree/master/conf) for more information.

## Credit

This add-on is based on James Fry's [rtl4332mqtt Hass.IO Add-on](https://github.com/james-fry/hassio-addons/tree/master/rtl4332mqtt), which is in turn based on Chris Kacerguis' project here: [https://github.com/chriskacerguis/honeywell2mqtt](https://github.com/chriskacerguis/honeywell2mqtt), which is in turn based on Marco Verleun's rtl2mqtt image here: [https://github.com/roflmao/rtl2mqtt](https://github.com/roflmao/rtl2mqtt).
