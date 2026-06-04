---
id: 4
group: "docs"
dependencies: [2]
status: "completed"
created: 2026-06-04
skills:
  - technical-writing
---
# Document the discovery contract, port instability, and Repairs pointer (README)

## Objective
Update `rtl_433/README.md` so the cross-repo discovery contract is explicit and
both repos stay aligned: document the discovery-payload `radios` roster shape and
field names, warn that the per-radio `port` (`BASE_PORT + i`) is **not** a stable
key (the integration must key on `unique_id`), and extend the existing "Replacing
a radio" section to point at the companion integration's Repairs-based
replacement flow.

## Skills Required
`technical-writing` — clear, accurate Markdown documentation matching the
README's existing voice and structure.

## Acceptance Criteria
- [ ] A discovery-contract reference documents the `config.radios[]` entry shape
      with the exact field names (`unique_id`, `port`, `path`, `serial`,
      `usbpath`) and notes that `host` is shared at the top level.
- [ ] The docs state that `port` is assigned `BASE_PORT + i` and is not stable;
      the stable key is `unique_id`.
- [ ] The "Replacing a radio" section references the integration's Repairs flow
      (a new radio is detected by diffing the roster across an add-on restart).
- [ ] The note that the roster reflects "radios present at this start" (not a
      durable inventory) is included, so a transient absence is not mistaken for a
      removal.
- [ ] Field names match Task 2's implementation and the integration's
      `async_step_hassio` consumer verbatim.
- [ ] No hand-edits to `CHANGELOG.md` (release-please owns it); no `[Unreleased]`
      section added.
- [ ] `pre-commit run --all-files` passes (markdown/yaml/json linters).

## Technical Requirements
- Edit `rtl_433/README.md` only.
- Keep terminology consistent with the plan's "Discovery payload contract"
  subsection and with `../rtl_433/RADIO_REPLACEMENT_PLAN.md`.

## Input Dependencies
- Task 2: the final discovery payload field names/shape (so docs match code).

## Output Artifacts
- README documentation of the discovery contract, port-instability caveat, and
  the Repairs-flow pointer in "Replacing a radio".

## Implementation Notes

<details>
<summary>Step-by-step</summary>

1. **Locate the existing section.** `rtl_433/README.md` already has a "Replacing a
   radio" section (added in plan 08) with an "Identity trade-off (`serial:` vs
   `usbpath:`)" subsection. Build on it; do not duplicate it.

2. **Add a discovery-contract reference.** Document the payload `config` shape,
   reusing the contract from the plan (`.ai/strikethroo/archive/...plan-09....md`
   "Discovery payload contract" subsection). Show the `radios[]` entry fields
   (`unique_id`, `port`, `path`, `serial`, `usbpath`) and that the connection is
   `ws://<host>:<entry.port><entry.path>`. State that the legacy single-radio
   fields remain for back-compat.

3. **Port-instability warning.** One or two sentences: ports are assigned
   `BASE_PORT + i` in enumeration order and shift when the set of dongles changes,
   so consumers must key on `unique_id`, never `host:port`.

4. **Repairs-flow pointer.** In "Replacing a radio", add that the companion
   [rtl_433 integration](https://github.com/rtl-433-hass/rtl_433) can surface the
   replacement as a Home Assistant **Repairs** issue — it detects a new radio by
   diffing the discovery roster across the (already-required) add-on restart.
   Keep the manual procedure too; the Repairs flow is the guided alternative.

5. **Transient-absence caveat.** Note the roster reflects the radios present at
   that start, so a momentarily-missing dongle should not be read as a permanent
   removal.

6. **Lint:** `pre-commit run --all-files`.
</details>
