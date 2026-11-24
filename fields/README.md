# Field definitions

The committed working format is **YAML**. Every field tool also accepts the equivalent JSON model. The app bundle's generated JSON is an interchange/build artifact; each package also carries its exact canonical YAML and byte hash for storage, display and recording snapshots.

## Current catalog

| Package ID | Fixed anchors | Other definitions |
| --- | ---: | --- |
| `frc-2026-rebuilt-welded` | 32 | Official welded dimensions: 16.541 × 8.069 m. |
| `frc-2026-rebuilt-andymark` | 32 | Official AndyMark dimensions: 16.518 × 8.043 m. |
| `ftc-2025-2026-decode` | 2 | Obelisk IDs 21–23 retain size/identity without fixed field poses. |
| `ftc-2026-2027-biobuzz` | 0 | Four moving clusters, 16 physical tags, member-local geometry. |

FRC 2027 is deliberately absent. Older FTC/FRC **size-only** presets remain in `size-standards.yaml`; they do not imply complete field layouts.

## Commands

Use macOS Ruby's standard `psych`, `json` and `digest` libraries; no gem download or network is needed to validate, convert or regenerate checked-in sources.

```sh
ruby scripts/field-definitions/field_tool.rb import
ruby scripts/field-definitions/field_tool.rb import --check
ruby scripts/field-definitions/generate_sizes.rb --check
ruby scripts/field-definitions/field_tool.rb validate
ruby scripts/field-definitions/test_field_tool.rb
ruby scripts/field-definitions/field_tool.rb convert fields/ftc-2025-2026-decode/field.yaml --format json --output /tmp/decode.json
ruby scripts/field-definitions/field_tool.rb convert /tmp/decode.json --output /tmp/decode.yaml
ruby scripts/field-definitions/field_tool.rb bundle --output fields/bundle
```

`import` derives packages from the hash-pinned snapshots in `sources/`. `import --check` compares every generated YAML artifact byte-for-byte. A source change fails the pinned hash check and requires source/geometry review. The source JAR, URLs and extraction command are in `source-lock.yaml`; the full JAR need not be committed.

`size-standards.yaml` is the source of truth for sizes, presets and Auto tolerances. `import` also regenerates the Swift `TagFieldCatalog` block, the TypeScript UI module and the C core fallback header from it; `--check` and `bundle` reject stale generated size sources. Manual edits to generated code are not retained.

`validate` accepts a full `field.yaml` or equivalent JSON file. An error identifies the filename, field and cause. `convert` validates a full normalized package and writes YAML by default. Upstream WPILib geometry is imported by the reproducible source importer, not mistaken for a normalized package.

## Contract, version 1

`catalog.yaml` is a package-ID/path index. Each package has a complete `field.yaml` and reproducible split `manifest.yaml`, `tags.yaml` and `clusters.yaml` views. `field.yaml` is the canonical snapshot/hash boundary. `packageSha256` is SHA-256 of its exact UTF-8 bytes; it is not the source file hash and does not include itself.

Required package fields include `schemaVersion`, `id`, `program`, full season start/end years, `competitionYear`, `game`, `variant`, `coordinateFrame`, `tagFrame`, `lengthUnit`, `angleUnit`, `floorElevationMeters`, `source`, `tags` and `clusters`. Source metadata records URL/revision/hash and the original units/basis. Dimensions may be null when the pinned tag source does not supply them; FTC image extents are not promoted to surveyed field dimensions.

Lengths are meters; angles are radians; quaternion arrays are `[w,x,y,z]`. `fieldPose` and `fieldFromTagColumnMajor` are the normalized field-from-raw-detector-tag transform, with raw tag **X printed-right, Y printed-down, Z into print**. `sourcePose` keeps original numeric components in the explicitly declared `source.sourceLengthUnit` and `source.sourceTagFrame`.

- WPILib source tag axes are X outward, Y printed-right, Z up. Import multiplies the source orientation by the explicit detector-to-WPILib basis; translation stays in the blue-origin +Z-up field frame.
- FTC source quaternions already map raw detector tag axes into the FTC centered +Z-up field frame. This is verified by the pinned SDK's `computeRobotPose`: it multiplies metadata field-from-tag directly by inverse raw camera-from-tag. Import converts inches to meters and normalizes quaternion roundoff, without another tag-basis rotation.
- Cluster member transforms use raw detector cluster axes and the SDK's local offsets. No zero/identity field placeholders are imported as permanent cluster poses.

Each tag has integer `id`, `family`, `name`, `poseSizeMeters`, `placement`, `localizationEligible`, optional `clusterId`, optional normalized pose/matrix and source pose. Fixed tags also carry derived `expectedHeightMeters` and `expectedTiltRadians`; unavailable positions/expectations are explicit null. Height is tag center above the stated field floor. Plane tilt is 0 for vertical and π/2 for horizontal, derived from the unit tag normal and field up, not camera incidence.

Cluster members point to a named cluster, have their own physical size, and have `clusterFromTagColumnMajor` local geometry. A cluster aiming origin can differ from every printed tag center. A cluster-only sighting must not mark its members seen.

`size-standards.yaml` defines all supported Auto candidates and per-candidate tolerance, plus explicit FTC/FRC presets and CENTERSTAGE's per-ID map. These are size rules, not evidence of field membership or surveyed position.

## YAML subset and validation

The portable YAML 1.2 subset uses string mapping keys, nested maps/sequences, quoted strings, finite JSON numbers, lowercase `true`/`false` and `null`; scalar arrays may use JSON flow syntax. Canonical output uses alphabetic keys and two-space indentation. Plain `yes`/`on` remain strings rather than YAML 1.1 booleans. Applications should use quoted season labels.

Explicit tags, aliases/anchors, merge keys, duplicate keys, nonfinite geometry, multiple documents and excessive size/depth are rejected before conversion. Validation also rejects unsupported schema/family/units, missing metric size, duplicate physical identities, invalid quaternion/matrix rotation, pose/matrix disagreement, broken cluster memberships and moving targets presented as fixed anchors. JSON follows the same duplicate-key and semantic checks.

See `NOTICE.md` and `sources/WPILib-LICENSE.md` for source redistribution terms. The generated bundle includes both files. These definitions and synthetic checks establish transport/geometry consistency, not physical-camera or field accuracy.
