# Field-definition and walk simulator checks

This standalone XCTest host compiles the real field codec, package validator,
walk state and C++ spatial core. It bundles the four committed field packages.
Synthetic source frames exist only in this test target; no camera or physical
device session is started.

Run with a dedicated simulator:

```sh
ruby native/FieldDefinitionTests/run-field-tests.rb --device-id YOUR_SIMULATOR_UUID
```

Optional `--work-dir` preserves a named build directory, log and result bundle.
The harness never selects or shuts down an unrelated simulator. Its caller owns
creation and cleanup of the dedicated simulator.

Coverage includes YAML/JSON equivalence and malformed input; package hashes and
immutable imports; actual FRC/FTC sources and fixed/moving semantics; independently
constructed camera/tag geometry; stable first anchoring; expected/observed height
and tilt warnings; upside-down and sloped tags; missing-floor/manual behavior;
source-frame deduplication, recording boundaries, segment resets, summary replay
and disagreement without field rekeying. Passing these tests establishes software
behavior, not physical sensor accuracy or a field survey.

## Full app accessibility and bridge checks

With a working Node 22+ on `PATH` and the normal iOS Pods/build prerequisites:

```sh
ruby native/FieldDefinitionTests/run-app-ui-tests.rb --work-dir /tmp/april-field-app-ui
```

This second harness builds the actual Release simulator app with embedded
JavaScript, creates its own iOS 26 iPhone simulator, installs that app, and drives
its native accessibility controls through XCTest UI automation. It verifies all
four catalog choices, field selection/status through the real native bridge,
readable YAML content in accessibility, and JSON import followed by normalized
YAML display. The import check uses the app's accessible Hide keyboard action.
It never injects camera or tag observations into the product app.

Screenshots and full accessibility trees are attached to the result bundle and
exported under the printed `artifacts` directory with readable filenames. The
owned simulator is deleted on exit. An optional `--app-path` accepts an already
verified current Release **simulator** app to avoid rebuilding it; it does not
accept a device build or operate a physical phone. Camera/AR accuracy remains a
physical follow-up rather than a simulator result.
