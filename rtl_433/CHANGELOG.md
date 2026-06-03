# Changelog

## [0.5.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.4.0...v0.5.0) (2026-06-03)


### Features

* **rtl_433:** make the noise-floor scan duration configurable ([#80](https://github.com/rtl-433-hass/rtl_433-hass-addons/issues/80)) ([a47619d](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/a47619da119b694400989055ac7997fcbc129919))


### Performance Improvements

* **rtl_433:** measure radio PPM offsets in parallel at startup ([1977d69](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/1977d69cecc561b33d773af64d69dc63037bee39))

## [0.4.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.3.0...v0.4.0) (2026-06-02)


### Features

* **rtl_433:** add SDR optimization tooling and add-on options ([8b89912](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/8b89912df4836d1024646a8adb1cb364f9183446))
* **rtl_433:** auto-correct PPM offset on startup ([fcf0974](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/fcf09749593ae6867028fcf385e345f6c0a7d352))
* **rtl_433:** detect noise floor on startup with rtl_power ([8e74976](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/8e7497641e36a68088e9ce72c2f1a640c8c15d53))

## [0.3.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.2.0...v0.3.0) (2026-06-01)


### Features

* add rtl_433 brand icon and logo to both add-ons ([6583ad8](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/6583ad8b6e03e6e0f909c69e9030af9c4955a232))
* **rtl_433:** remove stale Supervisor discovery when no radios are present ([#73](https://github.com/rtl-433-hass/rtl_433-hass-addons/issues/73)) ([6091519](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/6091519e5125f34e0a7addda406f4d1e8f3abf8b))


### Bug Fixes

* **rtl_433:** supervise each radio so one failure doesn't stop the add-on ([554cc81](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/554cc81c40701bc51aac1e78302f73b7508e8043))

## [0.2.0](https://github.com/rtl-433-hass/rtl_433-hass-addons/compare/v0.1.0...v0.2.0) (2026-06-01)


### ⚠ BREAKING CHANGES

* **rtl_433:** configuration moves from the Home Assistant config directory (/config/rtl_433) to the add-on's own config directory (/addon_configs/rtl433/). The old location is no longer read, and users no longer author full config files -- only optional per-radio overrides.
* **rtl_433:** MQTT output, the retain option, and the rtl_433_conf_file option are removed. Configurations must use rtl_433 HTTP output and the rtl_433 Home Assistant integration.

### Features

* **rtl_433:** add a 'disable_tpms' option to toggle TPMS decoders ([71670ab](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/71670ab2f0c0e46f8f576568cefde991702ff89f))
* **rtl_433:** add a 'Log diagnostic messages' option for output log ([d4d5054](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/d4d5054b136857314e7bad99e08d9b2df467f84f))
* **rtl_433:** advertise a stable per-radio unique_id in discovery ([#66](https://github.com/rtl-433-hass/rtl_433-hass-addons/issues/66)) ([c0a4c65](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/c0a4c65da06acdb14dd3ba9484c257d7853a58c5))
* **rtl_433:** auto-detect dongles and append per-radio overrides ([395e1ce](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/395e1ce5d0dd9cdf8d7ba808e9286810b7da0b8a))
* **rtl_433:** expose radios over HTTP instead of MQTT ([be095a9](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/be095a993a37da2cc9cb0ecc7d51414252946182))
* **rtl_433:** publish radios to Supervisor discovery API ([3b695bc](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/3b695bcb057bb3d68ad72e4587e80eb30ec2b007))
* **rtl_433:** render config via literal {{port}} substitution instead of bash ([7c64d65](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/7c64d6549ba3002843f568a3960a6a97915d5159))
* **rtl_433:** store config in the add-on config dir and add log option ([05bcfb9](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/05bcfb9dd51f621ad4319ac9feaa2899a3d8d08e))
* **rtl_433:** support manually-declared SoapySDR/HackRF radios ([9507a2d](https://github.com/rtl-433-hass/rtl_433-hass-addons/commit/9507a2d6495637f68e82e65ce607f8c8b8b0b73f))

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
