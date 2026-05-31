## [0.6.0] - 2025-03-22

* Update Alpine base to 3.21
* Update the stable addon to rtl_433 25.02

## [0.2.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.1.0...v0.2.0) (2026-05-31)


### ⚠ BREAKING CHANGES

* **rtl_433:** MQTT output, the retain option, and the rtl_433_conf_file option are removed. Configurations must use rtl_433 HTTP output and the rtl_433 Home Assistant integration.

### Features

* **rtl_433:** advertise a stable per-radio unique_id in discovery ([#66](https://github.com/rtl-433-hass/rtl_433-hass-addons/issues/66)) ([c0a4c65](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/c0a4c65da06acdb14dd3ba9484c257d7853a58c5))
* **rtl_433:** expose radios over HTTP instead of MQTT ([be095a9](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/be095a993a37da2cc9cb0ecc7d51414252946182))
* **rtl_433:** publish radios to Supervisor discovery API ([3b695bc](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/3b695bcb057bb3d68ad72e4587e80eb30ec2b007))

## [0.1.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.0.1...v0.1.0) (2026-05-30)


### ⚠ BREAKING CHANGES

* remove rtl_433_mqtt_autodiscovery add-on

### Features

* **deps:** update dependency merbanan/rtl_433 to v25.12 ([#16](https://github.com/rtl-433-hass/rtl_433-hass-addons/issues/16)) ([5d82cb3](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/5d82cb321add25e05aa72300ee2cb32cc5b8655f))
* remove rtl_433_mqtt_autodiscovery add-on ([148a238](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/148a238558f7dc8db1b67f5c2b30378d9aae8254))


### Bug Fixes

* address remaining hadolint warnings ([6496e69](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/6496e697d7f9cf5e0ffae2c73da93dad69e11b99))
* **config:** resolve addon linter errors and warnings ([98711d5](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/98711d5bf210a097605a830cd3a797cf90b54484))
* **rtl_433:** pin apk package versions (DL3018) ([001daca](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/001daca7ccd9668f2db35d4768f24ea58550070f))
* **rtl_433:** remove deprecated MAINTAINER instruction ([cf68a5d](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/cf68a5d58ce4437c0b2e811d02656012fe57f20a))
* **rtl_433:** use absolute WORKDIR paths (DL3000) ([bb28e85](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/bb28e8574914fc9744aca2c502b6636d90f58739))
* use inline hadolint ignores for DL3006 ([ed762d5](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/ed762d522ba7de480686ff899aa0dbafef40071a))

## [0.5.3] - 2024-10-20

* Support SoapySDR devices #198 #199

## [0.5.2] - 2024-06-23

* Upgrade base images to support RTL-SDR V4 #181

## [0.5.1] - 2024-02-17

* Add better help text when the mqtt addon isn't in use or available

## [0.5.0] - 2024-02-16

* Update to rtl_433 23.11 for the stable addon

## [0.4.1] - 2023-10-27

* Fix wrong retain value when setting in mqtt connection string #149 by @cserem

## [0.4.0] - 2023-02-08

* Update rtl_433 to the 22.11 release.
* Adds a new "next" version of the addon that tracks our next branch and rtl_433 master.
  * The addon is built once per day. To update, the "next" addon must be uninstalled and reinstalled.
  * The output line in each configuration file likely needs to be updated to preserve existing topic layouts.
* run.sh: Use ISO timestamp with timezone and usec precision #128

## [0.3.1] - 2022-10-25

* Upgrade rtl_433 to the latest master #117 #119

## [0.3.0] - 2022-10-19

### Looking to disable TPMS sensors?

By default, new installations will now disable TPMS sensors. To disable them in
an existing configuration, add the following lines to `rtl_433/<filename>.conf.template`:

```
protocol -59
protocol -60
protocol -82
protocol -88
protocol -89
protocol -90
protocol -95
protocol -110
protocol -123
protocol -140
protocol -156
protocol -168
protocol -180
protocol -186
protocol -201
protocol -203
```

### Other Changes

- [DOCS] Note the device must be set first if supplied
- Update for S6-Overlay 3.x #97 #98
- Fix output lag due to sed buffering #85 #95
- Ensure template has an EOL character when rendering #81 #96
- Apply Reject short messages for Acurite-Rain899 #2105 #2116 #104
- Update minimum config readme #108 #94
- Disable TPMS sensors by default #110 #113
- Update to rtl_433 master from September 24 2022 / e066b669f7574c37f943f251ec8023b00cff1df6 #114

## [0.2.3] - 2022-05-09

- Update to rtl_433 master as of April 28, 2022.

## [0.2.2] - 2022-04-02

- Update to rtl_433 master as of Mar 26, 2022 #82

## [0.2.1] - 2022-02-19

- Add builds for aarch64
- **READ BEFORE UPDATING** below still applies

## [0.2.0] - 2022-02-14

**READ BEFORE UPDATING**

The addon now uses a prebuilt image instead of being built locally when installed. This significantly speeds up installation times for slower devices, and ensures everyone is using the same code. Unfortunately, Home Assistant can't switch these installation methods automatically. To upgrade, **uninstall and reinstall the addon**. This will lose settings set in the Configuration section **but not files in `rtl_433/*.conf.template`**. Save them aside before reinstalling.

- Prevent using old cached rtl_433 repository during installation or update #43 #41
- Update to rtl_433 master as of Feb 4, 2021

## [0.1.3] - 2021-12-30

- Support multiple templated configuration files for multiple radios
  - The single-file configuration is still supported, but will be removed in a future release.
  - To migrate, create a `rtl_433` directory in your HA configuration, and move the configuration file to it, adding `.template` to the end of it.
  - The addon now also supports autodiscovery of credentials and settings for the Mosquitto HA addon. To use these settings, set your `output` line to:

```
output mqtt://${host}:${port},user=${username},pass=${password},retain=${retain}
```

- Prefix log lines with the config name
- Update rtl_433 tag pointer to latest release (to 21.12)
- Mirror Dockerfile from hertzg/rtl_433_docker

## [0.1.2] - 2021-02-10

- Update add-on config to require USB access per new supervisor config format (thanks to @telegreen and @schorsch3000)

## [0.1.1] - 2020-12-31

- Fix missing LD library path on aarch64 systems (#1, thanks @nickF007)

## [0.1.0] - 2020-12-27

- Publish the first version of the add-on
