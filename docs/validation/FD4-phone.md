# FD.4 phone test handoff — November 24, 2026

Installed and launched **0.11.0 (34)** on the user's iPhone after completing the FD.1–FD.4 software work and checks. The signed Release app was built from clean source commit `8d2972f7fd3cd7b05424340e79c36500a93d92c9` at `2026-11-24T05:51:06Z`. Codesign, embedded JavaScript, app identity and all four bundled YAML package hashes passed verification. Installed-app metadata matched the prepared version/build; the bounded native launch command succeeded.

## Try on the phone

1. Open **Fields** and choose the correct field/season/variant. FRC REBUILT has separate welded and AndyMark definitions. Auto sizing does not identify the field.
2. Use **Measure** to confirm the field floor, then return to Tag debug and hold a fixed reference tag in view. Passing initial height/tilt/printed-up checks produces a provisional single-tag alignment; mismatches show expected and observed values. Missing height remains unverified, with a separate explicit manual option.
3. **Start recording**, walk past tags, then **Stop & save**. In Saved sessions, use **Tags seen** to inspect nominal/observed positions, source references and YAML/JSON/CSV summaries. **Open observation** opens the source time paused in the recorded player. Recorded overlays retain expected tag geometry while playing or seeking.

DECODE targets 20/24 are eligible fixed anchors; Obelisk tags are not. BIOBUZZ members move and do not provide permanent global anchors. Height/tilt checks do not independently prove an anchor's horizontal placement or heading.

## Software evidence completed before installation

- Field catalog: 13 Ruby tests / 129 assertions; clean reproducible imports and generated catalog checks.
- Shared core: 7 CTest targets; plain C header and AddressSanitizer/UndefinedBehaviorSanitizer checks.
- Native simulator: 150 existing checks and 30 new field/parser/store/registration/overlay checks.
- Actual Release app simulator: 2 native accessibility/bridge workflows, including real catalog selection, full YAML accessibility text and JSON import with keyboard dismissal.
- Playback: 34 passed, 1 optional private-recording fixture skipped; exact paused observation seeking and recorded field-state tests.
- Host source replay/MP4 transport: 11 checks, including byte-exact YAML sidecars and inventory reconstruction without using the saved derived summary.
- React Native: 90 Jest tests, TypeScript, and lint with no errors (three existing warnings).

See [FD.1](FD.1.md), [FD.2](FD.2.md), [FD.3](FD.3.md) and [FD.4](FD.4.md) for commands, fixtures and local result locations. All task-owned simulators were deleted after their checks.

## Physical session and interpretation

The installation used the shared global device lease and a persistent owner with failure-safe cleanup. Only bounded install, installed-metadata and launch commands ran. No WDA/XCTest/Appium session or remote screen/keyboard capture was started. All owned deployment processes exited; the guard returned **released** without errors before this report or Git work. Existing recordings/settings were retained; no test recording or temporary settings were created on the phone.

This establishes installation/build identity and launch, not camera performance or surveyed field accuracy. Independent physical motion, height/tilt/size accuracy, field coverage and physical accessibility acceptance remain FD.6/user testing. FD.5 robot consumers and FD.7 future-season/visualization work remain deferred.
