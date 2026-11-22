# The REFINERY review build — November 22, 2026

April Fools AR by The REFINERY **0.5.0 (17)** was archived, signed with existing local development credentials, installed on an **iPad Pro 11-inch (M5), iPadOS 27.2.1**, and passed a native accessibility smoke test. This is a local review build. Apple organization enrollment, App Store Connect setup, distribution signing/export and TestFlight upload have not been performed.

## Installed artifact

- Bundle identifier: `com.bionanomics.aprilfoolsar`.
- Original-code copyright and MIT license: **2026 BioNanomics**.
- Source base: `03a727d9abb8f2ad7c095df69d75a1a2f6f17c29`, with the branding/privacy changes in a modified working tree.
- Embedded build date: **2026-11-22T19:07:27Z**. The app correctly reports its modified source tree.
- Release archive: `/tmp/refinery-ar-build/AprilFoolsAR.xcarchive`.
- The archive passed `codesign --verify --deep --strict`, bundle/version/build metadata checks and standalone JavaScript-bundle verification. The complete current privacy policy, MIT license and third-party notice strings were verified inside the compiled Hermes bundle.
- The earlier personal-identifier app is a separate installation; its recordings were not migrated, modified or removed.

## Verification

| Check | Result |
| --- | --- |
| TypeScript | Passed, `npx tsc --noEmit`. |
| Lint | Passed with no errors; one existing inline-style warning in the recording controls. |
| JavaScript tests | 36 passed across five suites, including offline policy/notices, tab switching, closing/reopening and explicit website navigation. |
| Native simulator regressions | 113 passed, zero failures, covering production overlay, floor, geometry and debug code. |
| Signed Release archive | Passed; no provisioning updates or device-registration flags used. |
| Native physical iPad smoke | One test passed with zero failures; approximately 45 seconds of test execution. |
| Legal-document freshness | Passed; direct Xcode builds also check for stale bundled legal text. |

The physical test used actual app accessibility elements to verify the app title and branded icon, About access, BioNanomics attribution, offline privacy text, MIT and third-party notices, both About tabs, closing the sheets, version/build/bundle identity, settings, 2×/4×/1× zoom, landscape controls, floor-setup gating, saved sessions and return to capture. It restored the starting orientation, live capture, Tag debug and 1× zoom before terminating the app.

Native observations showed `NORMAL`, `DEPTH LIVE`, `READY TO RECORD`, approximately 30 Hz analysis and AprilTag 4 readouts. These observations establish live sensor/processing availability, not numerical accuracy or a calibrated tag pose. No floor was confirmed, measurement created, recording saved or ZIP exported.

A Device Hub visual check separately confirmed the new header/icon, green controls, landscape workspace and official Refinery logo/privacy screen. Device Hub exposed its host toolbar rather than the target app's accessibility tree, so coordinate interaction was used for that limited visual check. The subsequent passing native XCTest check establishes the app accessibility results above; the visual check alone did not.

An initial native attempt timed out while enabling automation. A second reached and passed the new branding/privacy/license checks before an unrelated system sign-in reminder obstructed a control. The final harness canceled only that exact reminder and passed. No account credentials or account settings were changed.

## Release and evidence

Every physical action used the shared global device lease. All owned host and device test runners exited, and the temporary test-runner app was removed. No Appium or WDA session was used. Device Hub screen sharing was explicitly stopped, keyboard capture was off, and the remaining window showed enabled **View Screen**. Fresh window evidence was accepted after the first evidence expired; the guard completed **`released` with no errors**. The final native-test lease also completed **`released` with no errors**.

No recording/export fixture was created. Settings were opened and canceled, and display zoom/mode were restored. The branded app remains installed for owner review, with no test runner attached.

Raw device identities, lease tokens, screenshots and native trees remain outside the repository:

- `/tmp/refinery-ar-build-final.log` — successful archive and identity checks.
- `/tmp/refinery-native-audit-20261122/Results.xcresult` — 113 passing simulator tests.
- `/tmp/refinery-ipad-test/native-run-3/Results.xcresult` — passing physical test.
- `/tmp/refinery-ipad-test/evidence-3/` — physical screenshots and full accessibility trees.
- `/tmp/refinery-ipad-test/visual/release-verified.json` — verified Device Hub release.
- `/tmp/refinery-ipad-test/native-run-3/release.json` — final native-session release.

## Remaining gates

Before distribution, finish the real-field recording/export and known-reference measurement checks in [the tester checklist](../../TESTER_CHECKLIST.md). Portrait and orientation-transition visual review remains pending for this specific build; the physical smoke covered landscape controls.

After owner sign-off, follow [TestFlight preparation](../TESTFLIGHT.md): confirm the exact BioNanomics legal enrollment entity, set up/select its Apple team, publish the approved [privacy policy](../PRIVACY.md) at a real public URL, create the App Store Connect record, review final privacy/export-compliance answers, build from committed source, validate/upload and complete external beta review. The repository transfer remains with the owner; no destination organization slug or remote was invented.

## Sponsor update — 0.5.1 (18)

Added a **Sponsors** shortcut beside the app title and a Sponsors tab in About. Both recognize **Don Wood Foundation** and **Medical Informatics Engineering**, with explicit links to their verified official websites: `https://www.donwoodfoundation.org/` and `https://mieweb.org/`. No sponsor website is contacted until its link is selected. The tab row wraps on narrow screens.

TypeScript, all 36 JavaScript tests, legal-document freshness and lint passed (the existing inline-style warning remains). The development-signed Release archive passed signature and build-identity verification, and both sponsor names and exact URLs were verified in the compiled JavaScript bundle.

- Archive: `/tmp/refinery-ar-build/AprilFoolsAR-18.xcarchive`.
- Source base: `7a122f170d1463fb148acb7c567438c0313fdd29`, with modified sources.
- Build timestamp: **2026-11-22T19:24:54Z**.
- Local build log: `/tmp/refinery-sponsors-build.log`.

Installed **0.5.1 (18)** and verified its installed version on the iPad. Automatic launch was refused because the iPad was locked; this update has not received another on-device UI test. The owner can unlock the iPad, open April Fools AR and tap **Sponsors**. Installation used a short global lease; no runner or remote capture was started, and the guard returned **`released` with no errors**. Local install/release evidence is under `/tmp/refinery-sponsors-handoff/`. Existing recordings were preserved.
