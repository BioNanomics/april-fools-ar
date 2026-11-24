# FD.2 — Portable field geometry and size policy

Implemented behind the additive plain C interface in `native/SpatialCore/include/afsc_fields.h`, with Swift adapters. The existing ABI version and +Y-up measurement APIs retain their meaning. New field transforms explicitly use their declared +Z-up source field frames.

## Shared implementation

- Checked rigid transform creation/composition/inversion, optical-to-AR camera conversion, raw detector/WPILib tag basis conversion, transformed points and gravity-in-tag vectors.
- Gravity-consistent field registration, preserving independent pre-alignment residuals.
- Per-check height/tilt/full-gravity anchor status with pass/fail/unavailable, source eligibility/segment requirements and explicit missing data.
- Shared Auto width resolution and metric-pose rescaling; native `TagDebugMath` now calls these functions instead of duplicating their numerical implementation.
- A bounded portable walk reducer deduplicates observations by source segment/frame/family/ID and separates accepted/rejected counts.

The canonical YAML size catalog generates the Swift `TagFieldCatalog` data block, `FieldSizeCatalog.generated.ts` and `afsc_size_standards_generated.h`. Both the app-supplied candidate array and the core's compatibility fallback therefore derive from the same YAML source. Explicit FTC/FRC/Custom modes remain usable without LiDAR. Auto requires its matching-frame depth/quality inputs and never substitutes the global reference width for an unresolved detection.

Swift retains dictionary formatting and evidence strings. It preserves applied width/source, continuous inferred edge, reference scale, chosen tolerance and the depth/confidence context. Translation/range/separation scale linearly; object-space errors scale quadratically; angular/pixel diagnostics retain their meaning. Explicit CENTERSTAGE unknown-ID handling, precise manual/AR overrides, old settings migration and Apply/Cancel behavior remain covered.

## Reproduction and results

```sh
ruby scripts/field-definitions/field_tool.rb import --check
ruby scripts/field-definitions/test_field_tool.rb
cmake -S native/SpatialCore -B /tmp/afsc-fields-build -DBUILD_TESTING=ON -DAFSC_BUILD_JNI=OFF -DAFSC_BUILD_EXAMPLES=OFF
cmake --build /tmp/afsc-fields-build --parallel 4
ctest --test-dir /tmp/afsc-fields-build --output-on-failure
PATH=/Users/horner/.nvm/versions/node/v22.20.0/bin:$PATH npx tsc --noEmit
PATH=/Users/horner/.nvm/versions/node/v22.20.0/bin:$PATH npm test -- --runInBand __tests__/TagSizeSettings.test.tsx
xcrun swiftc -typecheck -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios17.0-simulator \
  -import-objc-header native/SpatialCore/include/afsc.h \
  native/ARCapture/TagDebugMath.swift
```

On November 24, 2026:

- Field data/generated-source checks: **13 tests, 129 assertions**, no failures/errors/skips.
- Shared CMake/CTest suite: **7/7 passed**, including field geometry/anchor/size/inventory checks, prior geometry/gravity/measurement/projection regressions and the actual AprilTag detector/pose smoke tests.
- TypeScript: passed.
- Targeted settings Jest suite: **14/14 passed**.
- Standalone iOS-simulator Swift typechecking of the shared size-policy adapter: passed.
- ESLint and Prettier checks of the changed settings UI/generated catalog: passed.

The system Homebrew Node executable could not start because a linked simdjson dylib was missing. Checks used the already available Node 22 toolchain above; this is a host toolchain issue, not a field-data or application failure.

## Interpretation

The field tests use independently constructed transform/anchor cases and explicit expected numeric values, including into-print versus outward tag normal, quaternion ordering, height/tilt/gravity mismatch, missing floor, upside-down print and a horizontally displaced tag that still passes height/tilt sanity checks. Passing a single-tag check retains provisional/anchor-dependent status.

These are host, settings UI and compile-time adapter results. Full native simulator workflow results belong to the FD.3/FD.4 evidence. No robot bindings or deployment are required in current scope, and no physical-camera accuracy is established by these checks. A physical phone session must remain separate and use the shared iOS device lease/release procedure.
