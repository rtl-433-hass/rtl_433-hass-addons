---
id: 5
group: "remove-mqtt-http"
dependencies: [2, 3]
status: "pending"
created: "2026-05-30"
skills:
  - technical-writing
---
# Update documentation for HTTP output and discovery

## Objective
Update user- and agent-facing documentation to reflect the removal of MQTT and the new HTTP/per-radio-port/discovery model, including a clear breaking-change note.

## Skills Required
- `technical-writing`: clear README/CHANGELOG updates for Home Assistant add-on users.

## Acceptance Criteria
- [ ] `rtl_433/README.md` replaces the MQTT connection-string guidance with the `output http` form and explains per-radio stable ports (8433+) and the integration's `ws://host:port/ws` connection.
- [ ] A `CHANGELOG.md` entry is added for both add-ons noting the breaking removal of MQTT, `retain`, and `rtl_433_conf_file`, and the new HTTP + Supervisor-discovery behaviour.
- [ ] `rtl_433-next/README.md` is updated if it carries configuration guidance.
- [ ] `AGENTS.md` is updated only if the option/service surface it documents changed materially (otherwise left as-is, with a note that no change was needed).
- [ ] Documentation mentions that the rtl_433 Home Assistant integration (`github.com/rtl-433-hass/rtl_433`) is the consumer, and that auto-discovery is best-effort until the integration adds Supervisor discovery support.

## Technical Requirements
Markdown docs. Keep the existing tone and structure. Reference the rtl_433 HTTP output syntax (`output http://0.0.0.0:<port>`, default 8433) and the integration's WebSocket connection.

## Input Dependencies
- Task 2 and Task 3: the implemented behaviour the docs describe (template format, port scheme, discovery).

## Output Artifacts
Updated `rtl_433/README.md`, `rtl_433-next/README.md` (if applicable), `rtl_433/CHANGELOG.md`, `rtl_433-next/CHANGELOG.md`, and `AGENTS.md` (if needed).

## Implementation Notes

<details>
<summary>Detailed implementation guidance</summary>

1. **`rtl_433/README.md`:** In the Configuration section, replace the "minimum that you need to specify… MQTT connection" guidance and the `output mqtt://HOST:PORT,user=…` examples with the HTTP equivalent: explain that the add-on now generates an `output http://0.0.0.0:<port>` line per radio, that each radio gets a stable port starting at 8433 (assigned in sorted `device` order, up to 10 radios), and that the Home Assistant rtl_433 integration connects to `ws://<addon-host>:<port>/ws`. Remove the paragraph describing the `retain` option. Update the "How it works" section that currently says the add-on publishes to MQTT. Keep the protocol/frequency/convert guidance (still valid), but drop `convert si`'s MQTT-discovery framing if it references MQTT.

2. **CHANGELOG (both add-ons):** add a top entry (follow the existing `## [x.y.z] - date` style, or an Unreleased section if release-please manages versions) describing: "BREAKING: removed MQTT output, the `retain` option, and the legacy `rtl_433_conf_file` option. The add-on now exposes each radio via rtl_433's HTTP/WebSocket API on a stable port (8433+) and publishes radios to Home Assistant discovery. Use the rtl_433 integration to consume the data." Note that since release-please derives versions from Conventional Commits, a manual version bump is not required — keep the changelog note consistent with that workflow.

3. **`rtl_433-next/README.md`:** if it contains configuration guidance, mirror the relevant README changes; otherwise leave structural content and only fix MQTT references.

4. **`AGENTS.md`:** the Structure section lists `config.json`/`run.sh`/`CHANGELOG.md` generically and needs no change. Only update if you added option/service descriptions there. State explicitly in your task output whether a change was needed (per the POST_PLAN documentation question).

5. Ensure all markdown passes any markdown/whitespace pre-commit hooks.
</details>
