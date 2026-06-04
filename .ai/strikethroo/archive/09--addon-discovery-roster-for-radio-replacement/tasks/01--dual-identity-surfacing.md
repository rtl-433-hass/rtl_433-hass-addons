---
id: 1
group: "addon-runsh"
dependencies: []
status: "completed"
created: 2026-06-04
skills:
  - bash
---
# Surface both serial and usbpath per radio (run.sh) + portpath in radios.status

## Objective
Make **both** stable identifiers — the USB `serial` and the USB `portpath` —
available per launched radio inside `rtl_433/run.sh`, so a later task can emit a
discovery roster that lets the integration correlate a same-port hardware swap.
Today only one identifier is kept (`resolve_radio_unique_id` selects `serial:`
*or* `usbpath:`), and the `radio_serials` parallel array carries only the serial.
Also surface the port path in the human-readable `radios.status` file via a new
`portpath=` field. This is the foundation the discovery roster (Task 2) consumes.

## Skills Required
`bash` — shell scripting in the `main()`-guarded `rtl_433/run.sh`, following the
existing parallel-array and helper conventions.

## Acceptance Criteria
- [ ] A new parallel array (e.g. `radio_portpaths`) is declared alongside
      `radio_ports`/`radio_tags`/`radio_unique_ids`/`radio_serials` (run.sh ~L973).
- [ ] `launch_radio` accepts the radio's USB port path and appends it to the new
      array, kept index-aligned with the other parallel arrays.
- [ ] The detected-dongle launch loop passes the real `portpath`; the
      explicitly-declared (SoapySDR/HackRF) launch loop passes an empty string
      (those radios have no sysfs port path — `template:` identity, both
      identifiers empty, must not error).
- [ ] `surface_radio_status` writes a `portpath=<value>` field on each radio's
      line in `radios.status` (tab-separated, consistent with the existing
      `radio=/unique_id=/host=/port=/serial=` fields).
- [ ] No change to the selected `unique_id` semantics or to any existing field.
- [ ] `pre-commit run --all-files` passes (shellcheck clean).

## Technical Requirements
- Edit only `rtl_433/run.sh`.
- Preserve `main()`-guarding so `tests/rtl_433/test_run.bats` can still source the
  file without executing the entrypoint.
- Keep the new array index-aligned with the existing parallel arrays at every
  append site.

## Input Dependencies
None — this is the foundation task.

## Output Artifacts
- A populated `radio_portpaths` parallel array (index-aligned with
  `radio_serials`/`radio_unique_ids`/`radio_ports`) available to
  `publish_discovery` and `surface_radio_status`.
- A `portpath=` field in `radios.status`.

## Implementation Notes

<details>
<summary>Step-by-step</summary>

All edits are in `rtl_433/run.sh`.

1. **Declare the new parallel array.** Near the other parallel arrays (~L973):
   ```bash
   radio_ports=()
   radio_tags=()
   radio_unique_ids=()
   radio_serials=()
   radio_portpaths=()   # NEW: index-aligned USB port path ("" when none)
   ```

2. **Thread the port path through `launch_radio`.** `launch_radio` currently
   takes 8 positional args ending with `$8 serial`. Add a 9th, `portpath`:
   ```bash
   launch_radio() {
       local port="$1" tag="$2" device_line="$3" override_file="$4" uid="$5" source_label="${6:-$4}" ppm="${7:-}" serial="${8:-}" portpath="${9:-}"
       ...
       radio_ports+=("$port")
       radio_tags+=("$tag")
       radio_unique_ids+=("$uid")
       radio_serials+=("$serial")
       radio_portpaths+=("$portpath")   # NEW
   }
   ```

3. **Pass the port path at both call sites.**
   - Detected-dongle loop (~L1324): the loop already has `portpath="${entry#*$'\t'}"`.
     Append it as the 9th arg:
     ```bash
     launch_radio "$port" "$match_id" "device ${selector}" "$expected_file" "$unique_id" "$expected_file" "$radio_ppm" "$serial" "$portpath"
     ```
   - Explicitly-declared loop (~L1373): these radios have no sysfs port path —
     pass an empty 9th arg (note this call has fewer args today; keep its
     existing args and append `""`):
     ```bash
     launch_radio "$port" "$tag" "device ${device_value}" "$stripped" "$unique_id" "$f" "" "" ""
     ```
     (Confirm the positional alignment: ppm and serial are empty for explicit
     radios, and portpath is empty.)

4. **Add `portpath=` to `radios.status`.** In `surface_radio_status`
   (~L1483-1494), read the new array and add the field to the file printf:
   ```bash
   serial="${radio_serials[$i]:-}"
   portpath="${radio_portpaths[$i]:-}"
   printf 'radio=%s\tunique_id=%s\thost=%s\tport=%s\tserial=%s\tportpath=%s\n' \
       "$tag" "$uid" "${host:-}" "$port" "$serial" "$portpath"
   ```
   Declare `portpath` in the function's `local` list. The per-radio log line may
   be left as-is (optional to extend).

5. **Lint:** run `pre-commit run --all-files` and fix any shellcheck findings
   (e.g. quote the new variable).
</details>
