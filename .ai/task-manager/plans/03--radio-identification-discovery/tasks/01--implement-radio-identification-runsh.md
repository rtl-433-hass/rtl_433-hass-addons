---
id: 1
group: "radio-identification"
dependencies: []
status: "pending"
created: 2026-05-31
skills:
  - bash
complexity_score: 5.0
complexity_notes: "Single file/single skill (bash in run.sh) but moderate technical depth: sysfs enumeration, a layered pure resolver, JSON-safe hand-built payload without jq. Kept as one task so run.sh is never left in a half-wired state."
---
# Implement stable radio identification and advertise `unique_id` in run.sh

## Objective
Add stable per-radio identity to the rtl_433 add-on: enumerate connected RTL-SDR dongles from sysfs, resolve a layered `unique_id` for each launched radio (serial → USB port path → template tag), and include that `unique_id` in each Supervisor discovery payload. All changes are confined to `rtl_433/run.sh`.

## Skills Required
- `bash` (arrays, sysfs reads, defensive globbing, `printf`-built JSON)

## Acceptance Criteria
- [ ] A sysfs enumeration helper lists connected RTL-SDR dongles (filtered by the known librtlsdr VID:PID table), capturing each device's serial and USB port path, ordered deterministically.
- [ ] The enumeration base path is overridable via an env var (default `/sys/bus/usb/devices`) so it can be exercised against a mock tree; a missing/empty tree yields an empty enumeration without error.
- [ ] A pure resolver function returns exactly one identifier per radio using the layered strategy: `serial:<serial>` (usable serial), else `usbpath:<portpath>`, else `template:<tag>`.
- [ ] A serial is treated as usable only when non-empty, not `00000000`/`00000001`, not a bare short reserved integer (`^[0-9]{1,3}$`), and unique within the enumerated set.
- [ ] The launch loop populates a new `radio_unique_ids` parallel array (alongside `radio_ports`/`radio_tags`) without changing existing port assignment, ordering, or the rtl_433 launch invocation.
- [ ] `publish_discovery()` emits `"unique_id": "<value>"` inside the `config` object of every POSTed payload, and the value is sanitized to a JSON-safe allowlist before interpolation.
- [ ] `bash -n rtl_433/run.sh` passes and `pre-commit run --all-files` passes (shellcheck/hadolint).
- [ ] Resolver behaves correctly under the table-driven and mock-sysfs checks listed in Implementation Notes.

## Technical Requirements
- Target file: `rtl_433/run.sh` (bashio/bash). No new packages: `jq`, `rtl_test`, `rtl_eeprom` are NOT available. `curl`, `sed`, `bashio` are.
- sysfs is available because `config.json` sets `usb: true` and `udev: true`. Device nodes live at `/sys/bus/usb/devices/<portpath>/` with `idVendor`, `idProduct`, and optional `serial` files.
- Preserve the existing best-effort posture: identity resolution must never abort the script or stop radios from launching.

## Input Dependencies
None.

## Output Artifacts
- Modified `rtl_433/run.sh` containing: `enumerate_rtlsdr_devices` (or similar) helper, a pure `resolve_radio_unique_id` helper, a populated `radio_unique_ids` array, and an extended `publish_discovery()` payload.

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

**1. sysfs enumeration helper**

Add a function that scans USB device nodes and emits `serial<TAB>portpath` lines for RTL-SDR devices only.

- Make the base path overridable for testing:
  ```bash
  SYSFS_USB_BASE="${SYSFS_USB_BASE:-/sys/bus/usb/devices}"
  ```
- A USB *device* node has an `idVendor` file and a name without a colon (interfaces look like `1-1.4:1.0`; root hubs look like `usb1`). Skip anything without `idVendor` and anything whose basename contains `:`.
- Read `idVendor`/`idProduct` (4-hex-digit lowercase, e.g. `0bda`/`2838`) and keep only entries whose `vid:pid` is in the known librtlsdr table below. Read `serial` if present (else empty). The **port path** is the directory basename (e.g. `1-1.4`) — stable per physical port.
- Sort the output deterministically with `sort -V` on the port path to approximate librtlsdr's index ordering.
- If `$SYSFS_USB_BASE` doesn't exist or matches no device nodes, output nothing and return 0 (graceful no-op). Guard the glob so the literal pattern isn't processed when empty (`[ -e "$d" ] || continue`).

Known librtlsdr VID:PID table (embed as a lookup set):
```
0bda:2832 0bda:2838
0413:6680 0413:6f0f
0458:707f
0ccd:00a9 0ccd:00b3 0ccd:00b4 0ccd:00b5 0ccd:00b7 0ccd:00b8 0ccd:00c0 0ccd:00c6 0ccd:00d3 0ccd:00d7 0ccd:00e0
1554:5020
15f4:0131 15f4:0133
185b:0620 185b:0650 185b:0680
1b80:d393 1b80:d394 1b80:d395 1b80:d397 1b80:d398 1b80:d39d 1b80:d3a4 1b80:d3a8 1b80:d3af 1b80:d3b0
1d19:1101 1d19:1102 1d19:1103 1d19:1104
1f4d:a803 1f4d:b803 1f4d:c803 1f4d:d286 1f4d:d803
1209:2832
```

Capture the enumeration once before the launch loop into an array, e.g.:
```bash
mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)
```
Each element is `serial<TAB>portpath` (serial possibly empty).

**2. Pure resolver**

`resolve_radio_unique_id <device_value> <tag>` — uses the `rtlsdr_devices` array (in scope) and returns one string on stdout.

- Parse `<device_value>` (the template's `device` line value, already extracted by run.sh):
  - If it starts with `:` → serial selector; strip the leading `:` and find the enumerated entry whose serial matches.
  - Else if it matches `^[0-9]+$` → index selector; take that 0-based index into `rtlsdr_devices`.
  - Else (SoapySDR/HackRF/driver= strings, empty, etc.) → unresolved.
- From the resolved entry (if any), apply the layered choice:
  1. **Usable serial** → `serial:<serial>`. Usable = non-empty AND not `00000000`/`00000001` AND not `^[0-9]{1,3}$` AND unique among all serials in `rtlsdr_devices`.
  2. Else if port path non-empty → `usbpath:<portpath>`.
  3. Else (no match at all) → `template:<tag>`.
- Sanitize the final value to a JSON-safe allowlist before returning: keep `[A-Za-z0-9:._-]`, replace anything else with `_` (e.g. `tr -c 'A-Za-z0-9:._-' '_'`). sysfs serials/port paths already fall within this set; tags derived from filenames are normalized here.
- Keep the function pure (no globals mutated, no I/O beyond reading the in-scope array) so a future enumeration-driven launch can reuse it.

**3. Wire into the launch loop**

- Add `radio_unique_ids=()` next to `radio_ports=()` / `radio_tags=()` (around line 116-117).
- Inside the per-template loop, after `tag=...` is computed, call the resolver and append:
  ```bash
  unique_id="$(resolve_radio_unique_id "$device" "$tag")"
  radio_unique_ids+=("$unique_id")
  ```
  (`$device` is already in scope from the existing `device="${entry%%$'\t'*}"`.)
- Optionally extend the existing `bashio::log.info` line to mention the resolved id for operator visibility (no new log line required).
- Do NOT change port math, sorting, `MAX_RADIOS` handling, or the `rtl_433 -c` invocation.

**4. Discovery payload**

In `publish_discovery()`:
- Add `uid="${radio_unique_ids[$i]}"` alongside the existing `port`/`tag` reads in the loop.
- Extend the `printf` template to include `unique_id` in `config` (values are already sanitized, so plain `%s` interpolation is safe):
  ```bash
  printf -v body \
    '{"service": "rtl_433", "config": {"host": "%s", "port": %s, "path": "/ws", "secure": false, "unique_id": "%s"}}' \
    "$host" "$port" "$uid"
  ```

**5. Validation to run before marking complete**

- `bash -n rtl_433/run.sh`
- `pre-commit run --all-files` (or at least `shellcheck rtl_433/run.sh`).
- Resolver table-driven checks (source the functions in a scratch script that defines `rtlsdr_devices` directly):
  - serial `:7858A1`, table has `7858A1\t1-1.2` (unique) → `serial:7858A1`
  - device `0`, table has `00000001\t1-1.2` and `00000001\t1-1.4` → `usbpath:1-1.2`; device `1` → `usbpath:1-1.4`
  - device `driver=rtl_tcp`, tag `living_room`, no match → `template:living_room`
  - empty table, tag `garage` → `template:garage`
- Mock sysfs check: create a temp dir with `<tmp>/1-1.4/{idVendor=0bda,idProduct=2838,serial=ABCD12}` and a non-RTL-SDR node `<tmp>/1-1.5/{idVendor=1d6b,idProduct=0002}`; run `SYSFS_USB_BASE=<tmp> enumerate_rtlsdr_devices` and confirm only `ABCD12\t1-1.4` is returned.
- JSON validity: build one sample `body` and confirm `printf '%s' "$body" | python3 -c 'import json,sys; json.load(sys.stdin)'` succeeds.
</details>
