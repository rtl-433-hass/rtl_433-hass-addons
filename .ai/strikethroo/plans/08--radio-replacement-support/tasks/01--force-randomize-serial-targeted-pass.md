---
id: 1
group: "radio-replacement"
dependencies: []
status: "pending"
created: 2026-06-03
skills:
  - shell
---
# Implement force_randomize_serial targeted EEPROM stamp in run.sh

## Objective
Add a targeted "force re-stamp" capability to `rtl_433/run.sh`: a new
`force_randomize_serial` option that, given **one** dongle's USB port path,
writes a fresh random serial to that dongle's EEPROM **regardless** of whether
its current serial is a factory default, then halts with re-plug instructions
and prints the new `serial:<new>` identity. Refactor the per-radio stamp body
out of `flash_default_serials` into a shared helper so the all-defaults pass and
the targeted pass share one correct write path.

## Skills Required
- `shell` — bash/POSIX scripting following `run.sh` conventions and bashio logging.

## Acceptance Criteria
- [ ] A shared helper (e.g. `_stamp_radio_serial`) encapsulates the per-radio
      stamp: collision-free random serial pick + bounded retrying
      `rtl_eeprom -d <index> -s <new>` write + standard logging.
- [ ] `flash_default_serials` is refactored to call the shared helper; its
      default-only semantics (gated on `_serial_is_default`) and avoid-set
      seeding are unchanged.
- [ ] `flash_targeted_serial <portpath_selector>` resolves the selector to the
      target via `enumerate_rtlsdr_devices`, maps it to the **librtlsdr index**
      via `enumerate_rtlsdr_by_index`, and writes via the shared helper.
- [ ] The targeted pass refuses (logs, no write) when the port path matches zero
      or >1 connected dongles, or when the target cannot be mapped to exactly one
      librtlsdr index (ambiguous/sole-default rule).
- [ ] The targeted pass writes even when the target's current serial is
      **non-default** (it is NOT gated on `_serial_is_default`).
- [ ] `main()` reads `force_randomize_serial`; when non-empty it runs the
      maintenance mode (targeted pass) and halts using the existing flash-and-halt
      message block (re-plug instructions).
- [ ] The flash-and-halt summary prints the **new** `serial:<new>` for each
      stamped radio.
- [ ] `shellcheck rtl_433/run.sh` passes with no new findings.

Use your internal Todo tool to track these and keep on track.

## Technical Requirements
- File: `rtl_433/run.sh`.
- Reuse existing helpers: `enumerate_rtlsdr_devices` (sysfs, `serial<TAB>portpath`),
  `enumerate_rtlsdr_by_index` (librtlsdr order, `index<TAB>serial`),
  `_portpath_for_serial`, `_serial_is_default`, `generate_random_serial`.
- Constants already defined: `EEPROM_WRITE_ATTEMPTS=3`, `EEPROM_WRITE_RETRY_DELAY=2`,
  `MAX_RADIOS=10`.
- `main()` is `main()`-guarded so functions are sourced by BATS without running
  the entrypoint — keep new functions sourceable (no top-level side effects).

## Input Dependencies
None.

## Output Artifacts
- New/updated functions in `rtl_433/run.sh`: shared stamp helper,
  `flash_targeted_serial`, refactored `flash_default_serials`, updated `main()`
  gating and flash-and-halt summary. Consumed by Task 2 (surfacing builds on the
  same main()), Task 4 (BATS), and Task 5 (README).

## Implementation Notes

The single hard correctness invariant (from PR #98): the index passed to
`rtl_eeprom -d <index>` MUST come from `enumerate_rtlsdr_by_index` (librtlsdr's
own order), never from the sysfs `rtlsdr_devices` array position. Read the index
and serial from the same enumeration the write targets.

<details>
<summary>Detailed implementation guidance</summary>

**1. Extract the shared stamp helper.** In `flash_default_serials` the per-radio
body (lines ~285–327: pick a unique serial in 5 attempts, log "writing random
serial…", run the bounded retrying `printf 'y\n' | timeout 30 rtl_eeprom -d <idx>
-s <new>` with `EEPROM_WRITE_ATTEMPTS`/`EEPROM_WRITE_RETRY_DELAY`, update
`existing_serials`, return success/new serial) becomes a helper. Suggested shape:

```sh
# Stamp one dongle (by librtlsdr index) with a fresh unique random serial.
# Args: <index> <current_serial> <portpath> <avoid_set>
# Echoes the new serial on success (and a trailing newline); returns non-zero on
# failure (no unique serial could be generated, or the write failed after retries).
_stamp_radio_serial() {
    local idx="$1" serial="$2" portpath="$3" avoid="$4"
    local new_serial="" cand attempt wrote=0
    for _ in 1 2 3 4 5; do
        cand="$(generate_random_serial)"
        case "$avoid" in *" ${cand} "*) continue ;; esac
        new_serial="$cand"; break
    done
    if [ -z "$new_serial" ]; then
        bashio::log.warning "Radio at index ${idx}${portpath:+ (${portpath})}: could not generate a unique serial; leaving its serial unchanged."
        return 1
    fi
    bashio::log.info "Radio at index ${idx}${portpath:+ (${portpath})}: writing random serial ${new_serial} to EEPROM (was '${serial:-empty}')."
    for attempt in $(seq 1 "$EEPROM_WRITE_ATTEMPTS"); do
        if printf 'y\n' | timeout 30 rtl_eeprom -d "$idx" -s "$new_serial" >/dev/null 2>&1; then
            wrote=1; break
        fi
        if [ "$attempt" -lt "$EEPROM_WRITE_ATTEMPTS" ]; then
            bashio::log.warning "Radio at index ${idx}: EEPROM write attempt ${attempt} failed; retrying in ${EEPROM_WRITE_RETRY_DELAY}s."
            sleep "$EEPROM_WRITE_RETRY_DELAY"
        fi
    done
    if [ "$wrote" -eq 1 ]; then printf '%s' "$new_serial"; return 0; fi
    bashio::log.warning "Radio at index ${idx}: rtl_eeprom failed to write serial ${new_serial} after ${EEPROM_WRITE_ATTEMPTS} attempts (non-fatal)."
    return 1
}
```

Then `flash_default_serials` keeps its avoid-set seeding, full enumeration, the
`_serial_is_default "$serial" || continue` gate, `_portpath_for_serial`, and the
`MAX_RADIOS` guard, but replaces the inline pick+write with a call to the helper,
appending the returned serial to `existing_serials` and incrementing
`flashed_count` on success. **Keep `flash_default_serials`'s stdout contract**:
it must still print only the flashed count (helper logging goes to bashio/stderr;
capture the helper's echoed serial into a local, do not let it leak to stdout).

**2. Collect stamped serials for the summary.** Both passes need to report the
new `serial:<new>` per radio. Simplest: have each pass accumulate
`"<idx>\t<new_serial>"` lines into a shell variable/array that `main()` reads
when printing the flash-and-halt summary, OR have each pass echo a machine-
parseable stamped list on stdout that `main()` captures. Choose one and keep it
consistent for both `flash_default_serials` and `flash_targeted_serial`. Whatever
the channel, the summary must print, per stamped radio, the literal
`serial:<new>` the radio will advertise after replug.

**3. `flash_targeted_serial <portpath_selector>`:**

```sh
flash_targeted_serial() {
    local selector="$1" existing_serials=" " entry s p target_serial="" matches=0
    local enumeration line idx eserial map_idx="" map_count=0 new_serial

    for entry in "${rtlsdr_devices[@]}"; do existing_serials+="${entry%%$'\t'*} "; done

    # Resolve selector (USB port path) -> exactly one connected dongle's serial.
    for entry in "${rtlsdr_devices[@]}"; do
        s="${entry%%$'\t'*}"; p="${entry#*$'\t'}"
        if [ "$p" = "$selector" ]; then matches=$((matches+1)); target_serial="$s"; fi
    done
    if [ "$matches" -ne 1 ]; then
        bashio::log.warning "force_randomize_serial: port path '${selector}' matched ${matches} connected dongles; refusing to write."
        return 1
    fi

    # Map target -> exactly one librtlsdr index.
    enumeration="$(enumerate_rtlsdr_by_index)"
    while IFS=$'\t' read -r idx eserial; do
        [ -n "$idx" ] || continue
        if _serial_is_default "$target_serial"; then
            # Sole-default rule: accept only if this index is default AND it is the only default.
            if _serial_is_default "$eserial"; then map_idx="$idx"; map_count=$((map_count+1)); fi
        else
            if [ "$eserial" = "$target_serial" ]; then map_idx="$idx"; map_count=$((map_count+1)); fi
        fi
    done <<< "$enumeration"

    if [ "$map_count" -ne 1 ]; then
        bashio::log.warning "force_randomize_serial: target at '${selector}' (serial '${target_serial:-empty}') mapped to ${map_count} librtlsdr indices; refusing to write to avoid stamping the wrong radio."
        return 1
    fi

    new_serial="$(_stamp_radio_serial "$map_idx" "$target_serial" "$selector" "$existing_serials")" || return 1
    # record "$map_idx<TAB>$new_serial" for the summary (see step 2)
    printf '%s' "$new_serial"
}
```

Note: when the target serial is a shared default, the sole-default acceptance
must require that exactly ONE index in the enumeration is default — if more than
one default index exists, `map_count` > 1 and the pass refuses (matches the Risk
mitigation). Verify the loop counts ALL default indices, not just the target's.

**4. `main()` gating.** Mirror the `randomize_default_serial` block (run.sh
~685–763). Read the option:

```sh
force_randomize_serial="$(bashio::config 'force_randomize_serial')"
[ "$force_randomize_serial" = "null" ] && force_randomize_serial=""
```

After `mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)`, add a branch:
when `force_randomize_serial` is non-empty, check `command -v rtl_eeprom`,
call `flash_targeted_serial "$force_randomize_serial"`, then print the
flash-and-halt summary (reuse the existing message block: the numbered re-plug
instructions, but reference turning OFF 'Force randomize serial'), include the
new `serial:<new>` line(s), and block on the same
`trap 'exit 0' TERM INT; while true; do sleep 3600 & wait "$!"; done` loop. If
both options are set, run the targeted pass; keep the existing
`randomize_default_serial` block as-is (deterministic, documented precedence).
Factor the shared halt message/loop if it reduces duplication, but do not change
the wording the existing option relies on for its BATS coverage.

**Constraints:** no top-level execution (keep `main()`-guard intact); all human
messages via `bashio::log.*` (stderr); functions must be sourceable by BATS with
`enumerate_rtlsdr_*` and `rtl_eeprom` stubbed.
</details>
