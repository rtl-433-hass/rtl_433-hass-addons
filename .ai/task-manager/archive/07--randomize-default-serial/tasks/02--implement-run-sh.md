---
id: 2
group: "implementation"
dependencies: [1]
status: "completed"
created: "2026-06-03"
skills:
  - bash
---
# Implement serial-randomization helpers and startup orchestration in run.sh

## Objective
Add two pure helper functions and one best-effort orchestration block to `rtl_433/run.sh` so that, when `randomize_default_serial` is enabled, every connected dongle still carrying a factory-default serial is flashed (via `rtl_eeprom`) with a unique random 8-hex-character serial early in startup, after which the add-on re-enumerates once so the new serials are used for the rest of the boot.

## Skills Required
- `bash` — writing main-guard-sourceable helpers and `bashio`-based option handling consistent with the existing `run.sh` conventions.

## Acceptance Criteria
- [ ] New helper `_serial_is_default <serial>` returns success for empty, `00000000`, and `00000001`; failure otherwise. Placed near `_serial_is_usable` with a matching comment block.
- [ ] New helper `generate_random_serial` prints exactly 8 lowercase hex characters from a kernel entropy source.
- [ ] `main()` reads the `randomize_default_serial` option with the same `bashio::config.true` pattern as the other booleans, defaulting to `false`.
- [ ] A flashing block runs only when the option is `true`, runs **after** `mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)` and **before** the PPM measurement pre-pass / launch loop, flashes only default-serial dongles by enumeration index with a unique serial, then re-enumerates `rtlsdr_devices` exactly once if anything was flashed.
- [ ] Every flashing step is best-effort: a missing `rtl_eeprom`, a flash failure, or a serial that never reappears is warned and never aborts startup.
- [ ] When the option is `false`, no `rtl_eeprom` call is reachable and behaviour is unchanged.
- [ ] `pre-commit run --all-files` passes (shellcheck clean) and the existing `bats -r tests/` suite still passes.

## Technical Requirements
- `rtl_eeprom -d <index> -s <serial>` writes a new serial and prompts for interactive confirmation; the confirmation must be auto-answered and the call time-bounded so it cannot hang startup.
- Default-serial dongles are addressed by **enumeration index** (`-d <i>`), because their serial is not usable as a selector. This mirrors the serial-or-index convention already used by the PPM and noise-floor passes.
- Generated serials must not collide with a serial already present among the enumerated dongles or already assigned earlier in the same pass.

## Input Dependencies
- Task 1: the `randomize_default_serial` option must exist in `config.json` for `bashio::config.true` to read.

## Output Artifacts
- `_serial_is_default` and `generate_random_serial` helpers (consumed by Task 3 tests).
- The startup flashing/re-enumeration behaviour (described by Task 4 docs).

## Implementation Notes
<details>
<summary>Step-by-step</summary>

**1. Add the two helpers near `_serial_is_usable` (after the `_serial_is_usable` function, around line 133).**

```bash
# Decide whether a USB serial is a factory-default placeholder that the
# randomize_default_serial option should replace. This is intentionally
# narrower than _serial_is_usable: it matches only the empty/missing serial and
# the two well-known factory defaults, not every technically-unusable value.
# Args: <serial>.
_serial_is_default() {
    local serial="$1"
    case "$serial" in
        ""|00000000|00000001) return 0 ;;
    esac
    return 1
}

# Print a random 8-character lowercase-hex serial drawn from the kernel entropy
# source. Used to give a factory-default dongle a unique identity. The caller is
# responsible for rejecting a value that collides with an existing/just-assigned
# serial (see the flashing pass in main()).
generate_random_serial() {
    od -An -N4 -tx1 /dev/urandom | tr -dc '0-9a-f'
}
```

**2. Read the option in `main()`** — add after the `detect_noise_floor` option block (around line 485), following the existing pattern:

```bash
    # Read the "Randomize default serial" add-on option (default off). When true,
    # every detected dongle still carrying a factory-default serial is flashed
    # with a unique random serial via rtl_eeprom before any process claims it,
    # then the dongles are re-enumerated once. When false, none of this runs.
    randomize_default_serial="false"
    if bashio::config.true 'randomize_default_serial'
    then
        randomize_default_serial="true"
    fi
```

**3. Add the flashing/re-enumeration block** immediately after the enumeration line
`mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)` (around line 511), before the `radio_ports=()` parallel-array declarations:

```bash
    # Optionally normalise factory-default serials before anything claims a
    # device. rtl_eeprom writes persist and reset the dongle (triggering kernel
    # re-enumeration), so flash every default-serial dongle up front and then
    # re-enumerate once so the freshly assigned serials are used for identity,
    # override matching, PPM, noise-floor, and launch. Best-effort throughout: a
    # missing rtl_eeprom or a failed/ineffective flash is warned and the dongle
    # keeps whatever identity it had.
    if [ "$randomize_default_serial" = "true" ] && [ "${#rtlsdr_devices[@]}" -gt 0 ]
    then
        if ! command -v rtl_eeprom >/dev/null 2>&1
        then
            bashio::log.warning "randomize_default_serial is on but rtl_eeprom is not available; skipping serial randomization."
        else
            flashed_any="false"
            # Space-padded set of serials to avoid (already present + assigned).
            existing_serials=" "
            for entry in "${rtlsdr_devices[@]}"
            do
                existing_serials+="${entry%%$'\t'*} "
            done
            for i in "${!rtlsdr_devices[@]}"
            do
                [ "$i" -ge "$MAX_RADIOS" ] && break
                entry="${rtlsdr_devices[$i]}"
                serial="${entry%%$'\t'*}"
                _serial_is_default "$serial" || continue

                # Pick a random serial not already present or assigned this pass.
                new_serial=""
                for _attempt in 1 2 3 4 5
                do
                    cand="$(generate_random_serial)"
                    case "$existing_serials" in
                        *" ${cand} "*) continue ;;
                    esac
                    new_serial="$cand"
                    break
                done
                if [ -z "$new_serial" ]
                then
                    bashio::log.warning "Radio at index ${i}: could not generate a unique serial; leaving its default serial unchanged."
                    continue
                fi

                bashio::log.info "Radio at index ${i}: flashing random serial ${new_serial} (was default '${serial}')."
                # rtl_eeprom prompts for confirmation; auto-answer 'y' and bound
                # the call so a stuck write cannot hang startup. A non-zero exit
                # is tolerated (best-effort).
                if printf 'y\n' | timeout 30 rtl_eeprom -d "$i" -s "$new_serial" >/dev/null 2>&1
                then
                    existing_serials+="${new_serial} "
                    flashed_any="true"
                else
                    bashio::log.warning "Radio at index ${i}: rtl_eeprom failed to write serial ${new_serial} (non-fatal; keeping default)."
                fi
            done

            if [ "$flashed_any" = "true" ]
            then
                # The EEPROM write resets the dongle; give the kernel a moment to
                # re-enumerate, then refresh the device list exactly once so the
                # new serials flow through the rest of startup.
                bashio::log.info "Re-enumerating RTL-SDR dongles after serial flash..."
                sleep 2
                mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)
            fi
        fi
    fi
```

**4. shellcheck notes**
- `existing_serials`, `flashed_any`, `new_serial`, `cand`, `entry`, `serial`, `i` are global (no `local`) on purpose inside `main()`, consistent with the rest of `main()` (its variables are intentionally global — see the comment above `main()`).
- The loop variable `_attempt` is unused inside the loop body; the leading underscore is the existing convention for an intentionally-unused variable. If shellcheck still flags SC2034, it is acceptable to use `for _ in 1 2 3 4 5` instead.
- Keep the `printf 'y\n' | timeout 30 rtl_eeprom ...` pipeline on one line so shellcheck's pipe handling is unambiguous.

**5. Verify**
- `pre-commit run --all-files` (or at least `shellcheck rtl_433/run.sh`) passes.
- `bats -r tests/` still passes (no regressions).
- Trace the disabled path: with `randomize_default_serial="false"` the entire block is skipped and no `rtl_eeprom` call is reachable.

</details>
