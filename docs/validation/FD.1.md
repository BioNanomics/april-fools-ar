# FD.1 — YAML field catalog

Implemented in the isolated `codex/field-definitions-fd4` checkout. No physical-device actions are part of this validation.

## Sources and delivered artifacts

- Four normalized YAML packages: FRC 2026 REBUILT welded/AndyMark, FTC 2025–2026 DECODE and FTC 2026–2027 BIOBUZZ.
- `fields/source-lock.yaml` pins exact WPILib JSON and FTC source-extraction byte hashes. The FTC Vision 12.0.0 source JAR SHA-256 is `756294f8307da88b85a73c5a804dbc20f65dd60af97534ed3dea8f38e528aba8`.
- `fields/size-standards.yaml` preserves six Auto candidates, their 10%/3% tolerances, older explicit size presets and the complete mixed-size CENTERSTAGE map.
- A strict YAML/JSON parser/validator/converter, deterministic source importer and resource bundle command under `scripts/field-definitions/`.
- Canonical full `field.yaml` plus split manifest/tags/clusters. The generated bundle carries exact YAML bytes and package SHA-256 alongside machine-interchange JSON.

## Reproduction

```sh
ruby scripts/field-definitions/field_tool.rb import --check
ruby scripts/field-definitions/field_tool.rb validate
ruby scripts/field-definitions/test_field_tool.rb
ruby scripts/field-definitions/field_tool.rb bundle --output fields/bundle
```

Result on November 24, 2026: four packages validate; regeneration is byte-exact; **13 tests, 129 assertions, zero failures/errors/skips**. The generated Swift/TypeScript/core size sources also match the canonical YAML.

Checks include all 32 IDs in each FRC variant, distinct official dimensions, representative source poses, independent printed-up/normal basis expectations, DECODE inch conversion and fixed/non-anchor semantics, all 16 BIOBUZZ member-local definitions, exact YAML/hash restoration, YAML/JSON semantic round trips, null/false/zero preservation, source hash locks, unsupported families/versions, invalid scale/rotation/membership and unsafe/duplicate/nonfinite YAML or JSON.

## Review and limitations

The pinned FTC `computeRobotPose` source establishes that FTC metadata already describes the raw detector tag frame. Applying the WPILib basis conversion to FTC would be wrong. The original source pose/units/basis remain alongside normalized matrices.

BIOBUZZ targets move and have no permanent field poses or localization eligibility. DECODE Obelisk tags remain size-known but position-unavailable. Unknown FTC dimensions stay null. No field art or ForceField source is bundled. No FRC 2027 source is invented.

Source notices are bundled with resources. Parser validation and synthetic numeric comparisons are not physical size/placement accuracy evidence. Native parser/consumer parity and app lifecycle validation belong to FD.2–FD.4 and are reported separately.
