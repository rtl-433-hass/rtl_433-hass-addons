---
id: 1
group: "testing-infrastructure"
dependencies: []
status: "completed"
created: 2026-06-01
skills:
  - bash
---
# Add a source-guard (`main`) to `rtl_433/run.sh`

## Objective
Refactor `rtl_433/run.sh` so the file can be **sourced** to load its pure helper functions without executing the main body, while behaving **identically** when executed normally in the container. This is the prerequisite that makes the helper functions unit-testable.

## Skills Required
- `bash` — shell refactoring with attention to scoping, `BASH_SOURCE`/`$0` idioms, and shellcheck cleanliness.

## Acceptance Criteria
- [ ] The four pure helper functions remain defined at top level (available on source): `enumerate_rtlsdr_devices`, `_serial_is_usable`, `resolve_radio_unique_id`, `radio_match_id`.
- [ ] All executable top-level statements (option reads, `mkdir`, `mapfile`, the two launch loops, the `publish_discovery` call, and the final `wait`/`sleep`) run only when the script is executed directly, not when sourced.
- [ ] A guard at the end invokes the main body only when executed directly: `if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi`.
- [ ] `bash -n rtl_433/run.sh` succeeds and `shellcheck` (via `pre-commit run --all-files`) passes.
- [ ] `bash -c 'source rtl_433/run.sh; type enumerate_rtlsdr_devices _serial_is_usable resolve_radio_unique_id radio_match_id'` reports all four as functions, and sourcing produces **no** side effects (no `rtl_433` launched, no `mkdir`, no `mapfile` of real hardware).
- [ ] Container execution behavior is unchanged (same variables, same order, same launches).

## Technical Requirements
Bash. The guard idiom `[ "${BASH_SOURCE[0]}" = "$0" ]` is true when the script is executed (including under the `#!/usr/bin/with-contenv bashio` shebang, where both equal the script path) and false when sourced from a BATS test.

## Input Dependencies
None.

## Output Artifacts
- Modified `rtl_433/run.sh` that is safely sourceable.

## Implementation Notes

<details>
<summary>Detailed implementation steps</summary>

1. **Read `rtl_433/run.sh` fully first.** Confirm the current structure:
   - Top: comment block + variable assignments (`conf_directory`, `default_conf`, `tpms_disables_conf`, `render_dir`, `BASE_PORT`, `MAX_RADIOS`, `SYSFS_USB_BASE`, `RTLSDR_KNOWN_IDS`).
   - Top-level function definitions: `enumerate_rtlsdr_devices()`, `_serial_is_usable()`, `resolve_radio_unique_id()`, `radio_match_id()`.
   - Then **executable** statements begin at the `disable_tpms="false"` block, followed by the `log_received_messages` / `log_diagnostic_messages` blocks, `mkdir -p "$render_dir"`, `mapfile -t rtlsdr_devices < <(enumerate_rtlsdr_devices)`, the `radio_ports=()` / `radio_tags=()` / `radio_unique_ids=()` / `matched_ids=" "` / `rtl_433_pids=()` initializations, the `launch_radio()` function definition, the detected-device `for` loop, the orphan-config `for` loop, the `publish_discovery()` function definition, the `publish_discovery` call, and the final `wait -n`/`sleep infinity` `if` block.

2. **Wrap the executable region in a `main()` function.** Insert `main() {` immediately before the `disable_tpms="false"` block, and a closing `}` immediately after the final `wait`/`sleep` `if` block (the last statement in the file before the guard you add in step 4).
   - The `launch_radio()` and `publish_discovery()` function definitions that currently live inside this region should remain inside `main()` (they become nested function definitions). This is valid bash: `main()` defines `launch_radio` before the loops that call it, and `publish_discovery` before its call, so they are available at the right time. This keeps the diff minimal and avoids reordering.
   - The four pure helpers (`enumerate_rtlsdr_devices`, `_serial_is_usable`, `resolve_radio_unique_id`, `radio_match_id`) and all bare variable assignments stay **outside** `main()`, at top level.

3. **Do NOT add `local` to any variable inside `main()`.** Variables such as `disable_tpms`, `log_*`, `rtlsdr_devices`, `radio_ports`, etc. must remain global so the nested and top-level helper functions continue to read them exactly as before. Preserve statement order.

4. **Add the guard at the very end of the file** (after the `main()` closing brace):
   ```bash
   if [ "${BASH_SOURCE[0]}" = "$0" ]; then
       main "$@"
   fi
   ```

5. **Re-indent** the moved block by one level (4 spaces) for readability. Indentation is cosmetic for shellcheck; if re-indentation risks introducing errors, prioritize correctness — shellcheck/`bash -n` is the gate, not indentation.

6. **Why sourcing is safe without `bashio`:** the shebang (`#!/usr/bin/with-contenv bashio`) is a comment when the file is sourced, and no `bashio::*` call exists at top level — all `bashio` usage is inside `main()`. So `source rtl_433/run.sh` under plain `bash` (as BATS does) defines the pure functions without error.

7. **Verify:**
   - `bash -n rtl_433/run.sh`
   - `bash -c 'source rtl_433/run.sh; type enumerate_rtlsdr_devices _serial_is_usable resolve_radio_unique_id radio_match_id'` → all four are functions; nothing else runs.
   - `pre-commit run --all-files` → shellcheck passes (watch for SC2034 on variables only used inside nested functions; if shellcheck flags a genuinely-used variable, add a targeted `# shellcheck disable=SC2034` with a one-line reason, matching the existing style in the file).

8. **Commit** with a Conventional Commit message, e.g. `refactor(rtl_433): guard run.sh main body so functions are sourceable`.
</details>
