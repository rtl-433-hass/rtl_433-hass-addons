# Configuration

The default configuration is intentionally usable without file editing. The add-on auto-detects RTL-SDR dongles, starts one rtl_433 process per radio, and exposes each process over WebSocket for the companion integration.

## Add-on Options

| Option | Default | Purpose |
| --- | --- | --- |
| `disable_tpms` | `true` | Disable noisy TPMS decoders that can flood Home Assistant with passing cars. |
| `log_received_messages` | `false` | Add `output kv` so decoded sensor events appear in the add-on log. |
| `log_diagnostic_messages` | `false` | Add `output log` so rtl_433 diagnostics appear in the add-on log. |
| `correct_ppm_offset` | `false` | Measure and apply each RTL-SDR dongle's crystal PPM offset. |
| `detect_noise_floor` | `false` | Sweep the configured bands with `rtl_power` and write noise reports. |
| `noise_floor_bands` | `433.92M,868M,915M` | Comma-separated center frequencies for noise-floor scans. |
| `noise_floor_duration` | `30` | Seconds to sample each band during a noise-floor scan. |
| `randomize_default_serial` | `false` | One-time maintenance mode that writes unique serials to factory-default RTL-SDR dongles and halts. |
| `force_randomize_serial` | empty | One-time maintenance mode that writes a fresh random serial to the dongle at one USB port path and halts. |

## Disable TPMS Sensors

Passing cars constantly broadcast TPMS data. With `disable_tpms` enabled, the add-on appends generated `protocol -<n>` lines to every radio config to disable known TPMS decoders for the bundled rtl_433 version.

When `disable_tpms` is off, the add-on emits no protocol lines, so rtl_433 enables every decoder it ships.

Protocol selection in rtl_433 is subtractive or exclusive, never additive. A negative `protocol -<n>` disables one decoder. A positive `protocol <n>` switches rtl_433 into "only these protocols" mode. That means an override such as `protocol 40` decodes only protocol 40; it does not add protocol 40 to the defaults.

## Per-Radio Overrides

Each detected radio's exact override filename is printed in the add-on log:

```text
Radio <id> -> HTTP port <port>. To customize, create /config/<id>.conf.
```

Create `<id>.conf` in the add-on config directory, not in Home Assistant's main config directory:

| Add-on | Add-on config directory |
| --- | --- |
| `rtl_433` | `/addon_configs/rtl433/` |
| `rtl_433 (next)` | `/addon_configs/rtl433-next/` |

The add-on log refers to this directory as `/config` because that is its path *inside the add-on container*. From Home Assistant — the File Editor, Samba, or the VS Code add-on — the same directory is `/addon_configs/<slug>/`, **not** Home Assistant's own top-level `/config` folder. Both are called `/config` from different vantage points, so always create `<id>.conf` under `/addon_configs/...`.

Put only the extra directives you want in the override file. The add-on appends the override to the internal default config, and rtl_433 applies the last matching directive.

Example:

```text
frequency 868M
protocol  40
convert   si
```

Important details:

- Do not add your own `output http://...` line; the default already provides the WebSocket server output with the assigned port.
- Avoid overriding `device`; it can break the file-to-radio mapping the add-on uses.
- Override files are used as-is, so no shell escaping is required for dollar signs, backticks, quotes, or NMEA strings such as `$GPRMC`.
- An override file that does not match a detected radio and does not declare its own `device` line is ignored, and the add-on logs a warning.

For the full rtl_433 config syntax, see [rtl_433.example.conf](https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf) and the [official rtl_433 documentation](https://triq.org/rtl_433).

## Correct PPM Offset

Every RTL-SDR dongle's crystal oscillator is slightly off-frequency. `correct_ppm_offset` measures that error with `rtl_test` and injects the measured value as a `ppm_error` directive.

When enabled:

- Each detected RTL-SDR radio is measured once, in parallel.
- First startup with the option enabled pauses for roughly three minutes.
- The measured value is cached as `<id>.ppm` next to that radio's optional `<id>.conf` override.
- Later starts reuse the cached value.
- Delete `<id>.ppm` and restart to force a fresh measurement.
- Turn the option off to stop applying automatic correction.

If a per-radio override already sets `ppm_error`, that manual value is respected and automatic measurement is skipped for that radio.

## Detect Noise Floor

`detect_noise_floor` measures ambient RF noise around the configured `noise_floor_bands`. This is useful when diagnosing reception problems, because a high noise floor makes weak sensor transmissions harder to decode.

While enabled:

- Every radio is scanned on every boot.
- Radios are scanned one after another.
- Startup is paused by roughly `noise_floor_duration * number of bands` per radio.
- Timestamped reports are written to the add-on config directory.

For each radio and run, the add-on writes:

- `noise-<id>-<timestamp>.csv` with raw `rtl_power` sweeps.
- `noise-<id>-<timestamp>.txt` with min, median, and peak dBm summaries.
- `noise-<id>-<timestamp>.png` with a spectrum graph.

The add-on does not delete old reports. Disable the option after collecting the data you need, and clean up old files manually.

The report is a boot-time snapshot of the configured bands. It is not a continuous measurement, and it may not match the frequency Home Assistant later commands the radio to use at runtime.

## Randomize Default Serial

Most low-cost RTL-SDR dongles ship with a factory default serial such as `00000000` or `00000001`. Multiple dongles with the same default serial cannot be distinguished by serial, so the add-on falls back to USB-port identity.

`randomize_default_serial` is a one-time maintenance mode that writes a unique random 8-hex-character serial to every connected default-serial dongle, then stops without starting rtl_433. The dongle must be physically replugged before the new serial takes effect.

Procedure:

1. Turn on `randomize_default_serial` and start the add-on.
2. Wait for the log to show that serials were written, or that no eligible dongles were found.
3. Turn the option off.
4. Stop the add-on.
5. Unplug and replug the dongles, or power-cycle the USB hub.
6. Start the add-on again.

Dongles with non-default serials are not touched.

## Replacing a Radio

When a dongle identified by `serial:` dies, the replacement reports a different serial and the integration sees a new radio identity. The add-on should not clone the dead serial onto the replacement; two connected radios must never share a serial.

Use this process instead:

1. Remove the dead dongle and plug in the replacement.
2. If the replacement has a default serial, run `randomize_default_serial` once. If it has a non-default serial you need to discard, set `force_randomize_serial` to that dongle's USB port path and start the add-on once.
3. Clear the maintenance option, stop the add-on, replug the dongle, and start normally.
4. Copy the new radio identity from the add-on log or `/addon_configs/<slug>/radios.status`.
5. In the companion integration, use the replace/reconfigure flow to bind the existing hub entry to the new radio `unique_id` and host/port.

Identity trade-off:

- `serial:` survives moving a dongle between USB ports, but dies with the dongle.
- `usbpath:` survives replacing a dongle in the same physical port, but breaks if the dongle moves to another port.

If you never rearrange USB ports, USB-port identity can make same-port replacements transparent. If you do rearrange ports, unique serials are more stable, and replacement requires the integration rebind step.
