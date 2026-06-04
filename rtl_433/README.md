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

Because nearly all RTL-SDR dongles ship with the same default serial (`00000001`), multi-dongle setups get the most stable identity either by keeping each dongle in a fixed USB port or by flashing a unique serial with `rtl_eeprom -s <serial>` (a one-time step performed outside the add-on) — or enable the [Randomize default serial](#randomize-default-serial) option to have the add-on do this automatically.

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

For a "zero configuration" setup, just start the add-on and install the dedicated [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433). The built-in default config captures common protocols (and disables noisy TPMS protocols by default) and exposes the data over rtl_433's HTTP/WebSocket server, which the integration consumes. **No file editing is required for the default case.**

### Disable TPMS sensors

The **Disable TPMS sensors** option in the add-on's Configuration tab controls whether tyre-pressure (TPMS) decoders are disabled. It is **on by default**: passing cars constantly broadcast TPMS data, which can otherwise flood Home Assistant with a large number of short-lived devices and entities.

When enabled, the add-on appends a set of `protocol -<n>` disables — generated at image build time from the bundled rtl_433's own decoder list, so they always match the rtl_433 version in the image — to every radio's config. When you **uncheck** it, no `protocol` lines are emitted at all, so every decoder rtl_433 ships (TPMS included) is enabled, exactly as if you had selected no protocols.

Note that because protocol selection is subtractive/exclusive (see the override note below), this all-or-nothing toggle is the supported way to re-enable TPMS: you cannot keep the other defaults *and* re-enable a single TPMS sensor via an override file.

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

 - The default already provides `output http://0.0.0.0:{{port}}`, so **do not add an `output http://...` line yourself**; the `{{port}}` placeholder is filled in with the radio's assigned port automatically.
 - **Overriding `device` is discouraged**: it breaks the file-to-radio mapping the add-on relies on.
 - **Protocol selection is subtractive or exclusive, never additive** (this is rtl_433's own `-R` behaviour). The default disables noisy protocols such as TPMS with negative entries like `protocol -60`, which keep every *other* decoder enabled. In an appended override, another `protocol -<n>` simply disables one more decoder. A *positive* `protocol <n>`, however, switches rtl_433 to "enable only these": it enables just the positively-listed protocols and disables everything else — so `protocol 40` means "decode **only** protocol 40", not "also decode 40". Consequently you cannot re-enable one of the default-disabled protocols (for example a single TPMS sensor) *and* keep the other decoders, because doing so requires a positive entry, which is exclusive.
 - Override files are used as-is, so **no shell escaping is required**: dollar signs, backticks, and quotes (for example a literal `$GPRMC`) can be written directly. The only thing the add-on substitutes is the `{{port}}` placeholder.

For the full list of available directives, see the example config in the rtl_433 source: [rtl_433.example.conf](https://github.com/merbanan/rtl_433/blob/master/conf/rtl_433.example.conf), the [official rtl_433 documentation](https://triq.org/rtl_433), and the supported protocol list in the [rtl_433 README](https://github.com/merbanan/rtl_433/blob/master/README.md).

An override file whose name does not match any detected radio **and** does not declare its own `device` line is ignored, and the add-on logs a warning so a typo or an unplugged dongle does not silently do nothing.

### Correct PPM offset

Every RTL-SDR dongle's crystal oscillator is slightly off-frequency, and that error (measured in parts-per-million, PPM) can be large enough to push a sensor's signal out of rtl_433's reach. The **Correct PPM offset** option in the add-on's Configuration tab turns on automatic per-radio PPM correction. It is **off by default**.

When enabled, the add-on measures each detected radio's PPM offset **once**, on the first boot, by sampling the dongle with `rtl_test` for about three minutes. All radios are measured **in parallel**, and **startup is paused until they finish** — so plan for roughly **three minutes of added startup** the first time this option is on, regardless of how many dongles you have (rather than three minutes *per* dongle). The measured value is cached in the add-on config directory as `<id>.ppm` (right next to that radio's optional `<id>.conf` override) and reused on every later boot, so only that first measurement is slow. The active offset (whether freshly measured or read from the cache) is logged on startup, and is injected into the radio's rendered config as a `ppm_error` directive so rtl_433 compensates for it.

Because the cache lives in the add-on config directory, it is visible and editable from Home Assistant (e.g. via the Samba, File Editor, or Studio Code Server add-ons at `/addon_configs/rtl433/`). So a radio logged as `Radio AB12CD34 -> ...` caches its offset in `/addon_configs/rtl433/AB12CD34.ppm`.

Notes:

 - **To force a fresh measurement** (for example after moving the dongle to a different machine), delete that radio's `<id>.ppm` file and restart the add-on.
 - **To return a radio to no PPM correction**, delete its `<id>.ppm` file *and* turn the **Correct PPM offset** option off. (Turning the option off already stops the correction being applied; deleting the file also clears the stored measurement so a future re-enable measures fresh.)
 - If a [per-radio override file](#per-radio-overrides) already sets its own `ppm_error` directive, that manual value is respected and automatic measurement is **skipped** for that radio. Copying the logged offset into an override this way is a convenient way to pin a value permanently without re-measuring.

### Detect noise floor

The **Detect noise floor** option (off by default) measures the ambient RF noise level around the bands your sensors use, which is useful for diagnosing reception problems (a high noise floor means weak signals are harder to decode). The companion **Noise floor bands** option is a comma-separated list of center frequencies to sweep; it defaults to `433.92M,868M,915M` (the common ISM bands). Each entry may be written in MHz with an `M` suffix (`433.92M`, `868M`) or as a plain integer number of hertz (`915000000`).

The **Noise floor duration** option sets how many seconds each band is sampled (default `30`, range `1`–`600`). Each band is swept in 1-second passes for this long, and the min/median/peak are taken across every sweep — so a longer duration captures **time-varying (intermittent) interference** rather than a single instant. A short value (e.g. `1`) gives a quick instantaneous snapshot of the static floor; the `30`-second default trades startup time for a measurement that better reflects bursty interferers.

While the option is on, every radio is swept with `rtl_power` **on every boot** — so turn it back off once you have collected the reports you need. Each scan writes a set of **timestamped** files into the add-on config directory (reachable at `/addon_configs/rtl433/`):

 - `noise-<id>-<timestamp>.csv` — the raw `rtl_power` sweeps.
 - `noise-<id>-<timestamp>.txt` — a per-band min / median / peak summary in dBm.
 - `noise-<id>-<timestamp>.png` — a spectrum graph.

The `<id>` is the radio's identifier (the same one used for override files). Because the files are timestamped, each boot produces a new set; **the add-on never deletes old reports**, so clean them up yourself when you no longer need them. A one-line per-band summary is also written to the add-on log. Unlike the parallel PPM measurement above, **radios are scanned one after another, and startup is paused for each** — so the added startup per radio is roughly **Noise floor duration × the number of bands** (plus a little device setup). With the defaults (30 seconds × 3 bands) that's about **90 seconds per radio**; lower **Noise floor duration** for a quicker scan or raise it for a more thorough interference survey.

**Important:** the noise floor reported here is a **boot-time snapshot taken at the configured band(s)**, not at whatever frequency Home Assistant is using at runtime. The rtl_433 integration can retune a radio after boot, so the live operating frequency may differ from the band(s) measured here. Treat the report as a point-in-time survey of the configured bands, not a continuous measurement of the radio's current frequency.

### Randomize default serial

Nearly all RTL-SDR dongles ship with the same factory-default serial
(`00000000` or `00000001`), which makes multiple dongles indistinguishable and
pushes the add-on to identify them by USB port instead. When the add-on detects
a default-serial dongle it logs a warning recommending you assign it a unique
serial with the **Randomize default serial** option (off by default).

This option is a **one-time maintenance step**, not a normal runtime setting,
because applying a new serial requires physically replugging the dongle:
`rtl_eeprom` writes the serial to the dongle's EEPROM, but the RTL2832U only
reads its serial at USB power-on, and the add-on's container cannot power-cycle
the USB bus. So when the option is **on**, the add-on writes a **unique random
8-hex-character serial** to every connected default-serial dongle and then
**stops — it does not start `rtl_433`** — printing instructions to the log.

To assign serials to your dongles:

1. Turn **on** *Randomize default serial* and (re)start the add-on. It writes new
   serials to any factory-default dongles, then halts without starting `rtl_433`.
2. Turn the option back **off**.
3. **Stop** the add-on.
4. **Unplug and replug** the RTL-SDR dongle(s) (or power-cycle the USB hub) so
   they re-read their new serials.
5. **Start** the add-on again — each dongle now reports its unique serial and is
   identified by it (stable across USB-port changes).

Dongles that already have a real serial are never touched. Every step is
best-effort: a missing `rtl_eeprom` or a failed/rejected write is logged and
skipped. Leaving the option on simply keeps the add-on in this maintenance mode
(no radios start), so remember to turn it back off when you're done.

### Replacing a radio

When an RTL-SDR dongle dies, you replace it with a new one and want your existing
Home Assistant configuration — the decoded sensor entities, their history, and
your automations — to keep working against the new hardware. The challenge is
that a dongle identified by its **USB serial** cannot keep that identity: the
serial lived in the dead dongle's EEPROM, so the replacement reports a different
serial and the add-on advertises a **new** `unique_id` that the integration no
longer recognizes. A dongle identified by its **USB port path** has no such
problem if the replacement goes back into the same port (see the
[identity trade-off](#identity-trade-off-serial-vs-usbpath) below).

The procedure stamps the **replacement** dongle with a fresh random serial (never
a clone of the dead one — two connected dongles must never share a serial), then
re-links it in the integration:

1. **Remove the dead dongle and plug in the replacement** (any port).

2. **Stamp the replacement, if needed.** Pick the case that matches your
   replacement dongle:

    - **It carries a non-default serial you want to discard** (for example a
      batch-shared serial it shipped with): set the **Force randomize serial**
      (`force_randomize_serial`) option to the new dongle's **USB port path**
      (e.g. `1-1.4` — the same identifier printed in the add-on log), and start
      the add-on once. Like [Randomize default serial](#randomize-default-serial),
      this is a one-time **flash-and-halt** maintenance step: it writes a fresh
      random serial to that one radio and stops without starting `rtl_433`.
      Then **clear the option**, **stop** the add-on, **unplug and replug** the
      dongle so it re-reads its new serial, and **start** again.
    - **It has a factory-default serial** (`00000000`/`00000001`): enable
      [Randomize default serial](#randomize-default-serial) once instead — it
      stamps every default-serial dongle with a fresh random serial.
    - **It is a no-EEPROM dongle going back into the same port** as the dead one:
      skip stamping entirely. Its `usbpath:` identity is unchanged, so the
      replacement is transparent and the integration still recognizes it.

    As with *Randomize default serial*, stamping writes the dongle's EEPROM, and
    the RTL2832U only re-reads its serial at USB power-on — so the new serial does
    **not** take effect until you physically replug the dongle.

3. **Read the new radio's identity.** On a normal boot the add-on logs a
   copy-pasteable line per radio:

    ```
    Radio <id>: unique_id=<serial:…|usbpath:…> host=<host> port=<port>
    ```

    The same values are also written to a `radios.status` file in the add-on
    config directory (`/addon_configs/rtl433/radios.status`), one tab-separated
    line per radio, so you can read them without scraping the log.

4. **Re-link in Home Assistant.** In the
   [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433), run its
   **Replace radio / reconfigure** workflow and point the existing hub entry at
   the new radio's `unique_id` and `host:port` from the previous step. Your
   decoded sensor entities, their history, and automations are preserved.

**Guided alternative (Repairs).** The same re-link can be driven from a Home
Assistant **Repairs** issue instead of doing step 4 by hand. The
[rtl_433 integration](https://github.com/rtl-433-hass/rtl_433) detects a new
radio by diffing the add-on's discovery roster across the restart that the
procedure already requires (stop → replug → start): on the next start the add-on
re-publishes the full current roster (see
[Discovery payload contract](#discovery-payload-contract) below), and a
`unique_id` that was not present before surfaces as a "a new radio was found —
replace the radio on hub X?" repair you can resolve in **Settings -> Devices &
Services -> Repairs**. The manual procedure above remains available; the Repairs
flow is the guided equivalent of step 4.

#### Identity trade-off (`serial:` vs `usbpath:`)

The two stable identities the add-on can assign behave differently when hardware
changes:

 - **`serial:`** survives moving the dongle between USB ports, but the identity
   **dies with the dongle** (the serial lived in its EEPROM), so a replacement
   always needs the reconfigure step above.
 - **`usbpath:`** survives swapping a dongle **in the same port** (the new dongle
   inherits the identity transparently), but **breaks if the dongle moves** to a
   different port.

Practical guidance: if you never rearrange USB ports, you may prefer relying on
`usbpath:` identity — keep each dongle in a fixed port and a same-port swap needs
no stamping and no reconfigure. If you do rearrange ports, assign unique serials
and accept the reconfigure step when a serial-identified dongle is replaced.

#### Discovery payload contract

The add-on publishes a single Supervisor discovery message (the Supervisor
collapses an add-on's same-service messages into one). Its `config` object keeps
all the existing single-radio fields unchanged for back-compat and **adds** a
`radios` array describing every launched radio. The field names below are a
cross-repo contract with the [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433)
and must match its discovery consumer verbatim:

```jsonc
{
  "service": "rtl_433",
  "config": {
    // legacy single-radio fields (unchanged; the last-published radio)
    "host": "<addon-hostname>",
    "port": 8434,
    "path": "/ws",
    "secure": false,
    "unique_id": "serial:abcd1234",
    // additive full current roster (one entry per launched radio)
    "radios": [
      { "unique_id": "serial:abcd1234", "port": 8433, "path": "/ws",
        "serial": "abcd1234", "usbpath": "1-1.4" },
      { "unique_id": "usbpath:1-1.2", "port": 8434, "path": "/ws",
        "serial": "", "usbpath": "1-1.2" }
    ]
  }
}
```

Each `radios[]` entry carries:

 - **`unique_id`** — the stable per-radio key (`serial:…`, `usbpath:…`, or
   `template:…`), the same value derived in [How it works](#how-it-works).
 - **`port`** and **`path`** — the radio's assigned TCP port and WebSocket path.
 - **`serial`** and **`usbpath`** — **both** stable identifiers, so a consumer can
   correlate a same-port hardware swap; either may be an empty string (a
   `template:`-identity radio has both empty).

`host` is shared by every radio and stays at the top level only; the per-radio
connection is therefore `ws://<host>:<entry.port><entry.path>`. The legacy
single-radio fields (`host`, `port`, `path`, `secure`, `unique_id`) remain
present and unchanged, so an integration that reads only those keeps working.

> [!WARNING]
> `port` is assigned `BASE_PORT + i` (starting at `8433`) in dongle enumeration
> order, so it **shifts when the set of connected dongles changes** and is **not**
> a stable key. Consumers must key on `unique_id`, never on `host:port`.

The `radios` array reflects the **radios present at this start**, not a durable
inventory. A dongle that is momentarily missing on one start (a USB glitch or a
slow enumeration) is simply absent from that roster, so a consumer should not read
a transient absence as a permanent removal — treat a *new, unbound* radio as the
replacement signal rather than the mere absence of a known one.

### Non-RTL-SDR radios (SoapySDR / HackRF)

Auto-detection only finds **RTL-SDR** dongles, so SoapySDR/HackRF (and other non-RTL-SDR) devices must be declared manually. Create a config file in the add-on config directory that contains its own `device` line with the appropriate device string — for example `hackrf.conf`:

```
device    driver=hackrf
frequency 433.92M
```

Any config file that does **not** match a detected RTL-SDR radio but **does** contain a `device` line is launched as its own radio. The file name is up to you (it becomes the radio's log label); the `device` line selects the SDR. As with overrides, the file is appended to the internal default (so you do not need to add the `output http://...` line yourself), and the add-on injects the `device` line ahead of the default's output line. These manually-declared radios are launched **after** any auto-detected RTL-SDR dongles and are assigned the next free ports.

### Logging

Two independent options in the add-on's Configuration tab control what rtl_433 writes to the add-on log:

 - **Log received messages** appends `output kv` to each radio's config, so decoded sensor events appear in the log. Useful for confirming that sensors are being received.
 - **Log diagnostic messages** appends `output log` to each radio's config, so rtl_433's own status/diagnostic messages appear in the log. Useful for troubleshooting the radios themselves.

Both default to off and can be enabled independently.

### Signal level data

The baked-in default config enables rtl_433's **level reporting**
(`report_meta level`, the config-file equivalent of the `-M level` CLI flag), so
every decoded message carries the radio's per-transmission **frequency**,
**RSSI**, **SNR**, and **noise**. The
[rtl_433 integration for Home Assistant](https://github.com/rtl-433-hass/rtl_433)
surfaces these as optional per-device diagnostic sensors (disabled by default —
enable the ones you want from each device page) for charting signal strength and
reception quality. No add-on configuration is required.

### Breaking change / migration

Earlier versions of this add-on read config files from `/config/rtl_433/` in the **Home Assistant config directory**. That location is **no longer read**. Move any per-radio tuning into `<id>.conf` files in the **add-on config directory** (`/addon_configs/rtl433/`) as described above. There is no longer a separate config file for the default case — the default is baked into the image.

### Limitation

Auto-detection enumerates **RTL-SDR** dongles only (via the kernel's USB device table). Non-RTL-SDR SDRs such as SoapySDR or HackRF devices are **not** auto-detected; run them by declaring each one manually in a config file with its own `device` line, as described in [Non-RTL-SDR radios](#non-rtl-sdr-radios-soapysdr--hackrf) above.

## Credit

This add-on is based on James Fry's [rtl4332mqtt Hass.IO Add-on](https://github.com/james-fry/hassio-addons/tree/master/rtl4332mqtt), which is in turn based on Chris Kacerguis' project here: [https://github.com/chriskacerguis/honeywell2mqtt](https://github.com/chriskacerguis/honeywell2mqtt), which is in turn based on Marco Verleun's rtl2mqtt image here: [https://github.com/roflmao/rtl2mqtt](https://github.com/roflmao/rtl2mqtt).
