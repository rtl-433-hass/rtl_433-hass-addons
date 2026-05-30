This tracks the latest "next" branch along with upstream rtl_433's master
branch.

## [Unreleased]

* **BREAKING:** Removed the MQTT output, the `retain` option, and the legacy
  `rtl_433_conf_file` option, and dropped the `mqtt` service dependency. The
  add-on no longer publishes to MQTT.
* Each radio now runs its own rtl_433 process and exposes rtl_433's
  HTTP/WebSocket server via an `output http://0.0.0.0:<port>` line. Radios are
  assigned stable ports starting at 8433 (8433, 8434, ..., up to 10 radios),
  sorted deterministically by their `device` value.
* Radios are published to Home Assistant's Supervisor discovery API
  (best-effort). Consume the data with the [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433),
  which connects over `ws://<addon-host>:<port>/ws`. Until the integration adds
  Supervisor discovery support, add it manually in
  Settings -> Devices & Services -> rtl_433 with the add-on host and port.

  Since versions are derived from Conventional Commits by release-please, no
  manual version bump is included here.
