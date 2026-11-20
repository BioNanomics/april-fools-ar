# REEKON SDK access sprint

Started November 20, 2026. Owner: SDK access research agent. Planning and vendor-access work only; no application implementation or equipment order.

## Objective and authorization

Obtain legitimate access to REEKON's BLE Connection Guide and SDK before selecting or ordering measuring hardware. The user authorized submitting SDK-request forms and necessary outreach using an accurate profile and an explanation of the project. This does not authorize buying equipment, a paid subscription, an NDA, or other material contractual commitments.

The proposed app is iOS first: React Native presentation, native ARKit integration, a shared AprilTag C/C++ core, and later ARCore/Android. BLE readings will support independently defined floor heights and ranges between named endpoints during AprilTag field validation and calibration. Robot-camera diagnostics are another planned workflow.

## Current status

- [x] Locate the official SDK access path.
- [x] Inspect the request form and identify required fields.
- [x] Identify verified name and contact email from connected profiles.
- [x] Verify the remaining profile fields and submit a truthful request.
- [x] Verify visible submission confirmation and record exact submitted fields/text.
- [ ] Obtain access; submission alone does not mean approval.
- [ ] Inspect SDK documentation, examples, protocol semantics, platform support, and distribution terms.
- [x] Search existing open-source REEKON/tape-measure integrations and assess reuse, licensing, maintenance, and exact model/firmware compatibility.
- [ ] Record the hardware/interface decision and any remaining questions before purchase.

## Activity log

### November 20, 2026 — initial investigation

- Opened the official [BLE Connection Guide and SDK for REEKON Tools](https://support.reekon.tools/hc/en-us/articles/35510332936596-BLE-Connection-Guide-and-SDK-for-REEKON-Tools). It links to the request form and lists `dev@reekon.tools` for developer feedback. The current listed guide is v1.5, October 2026, adding T1R functions and measurement-modifier/group opcodes. Its v1.2 notes mention the Position Service for the currently displayed tape reading.
- Followed the official short link, <https://forms.gle/Li3K4YFVc1LWYEr48>, to the [REEKON SDK Request Form](https://docs.google.com/forms/d/e/1FAIpQLSf05v3qLPnsbM08SkLeKr7sslHzWclNu34_6TRO3Wicc3BSdw/viewform).
- Opened the form in Chrome. Required fields: Email, First Name, Last Name, Company Name, Company Website, Country, Describe your intended use. Google sign-in is optional for saving progress. No payment, NDA, or agreement-acceptance control is visible on the form.
- A parallel read-only profile check verified **Doug Horner** and **horner@mieweb.com** against both connected GitHub and Outlook profiles, also matching local Git configuration. Organization, country, and a suitable public website are being checked; an email domain alone is not treated as employer authorization.
- Before submission, identified the work as an independent/personal project to avoid implying employer sponsorship.
- At approximately 11:43 UTC, completed the form using verified profile information: Doug Horner, horner@mieweb.com, United States, public profile <https://github.com/horner>. The public profile separately lists Medical Informatics Engineering, Inc. and Fort Wayne, IN, but this request deliberately describes the independent personal project rather than implying company sponsorship.
- The user also requested existing open-source tape-measure integration research. A parallel read-only search inspected REEKON protocol implementations/wrappers, native iOS/Android examples, app integrations, model/firmware coverage, licenses, and maintenance evidence. Findings appear below; no source compatibility is assumed from a project name alone.

### November 20, 2026, approximately 11:44 UTC — request submitted

- Submitted the official request form once. The resulting page at the form's `/formResponse` URL visibly states: **“Your response has been recorded.”** No agreement acceptance, payment, or Google account sign-in was required.
- Preserved the confirmation tab as a browser deliverable and saved a [confirmation screenshot](/tmp/reekon-sdk-submission-confirmation.jpg). Captured evidence shows the REEKON SDK Request Form heading and recorded-response message.
- **Access is not yet approved or obtained.** The confirmation contains no SDK link or promised response time. The single immediate mailbox check is recorded below; vendor response remains pending.
- At approximately 11:45 UTC, searched the connected Outlook mailbox used for the request with `REEKON received>=2026-11-20`; zero matching messages were returned. No SDK approval, automatic download link, or new terms were received in this check. A vendor reply may arrive later; no recurring monitoring has been scheduled.

### Exact submitted form fields

| Required field | Exact value |
| --- | --- |
| Email | horner@mieweb.com |
| First Name | Doug |
| Last Name | Horner |
| Company Name | Independent developer (personal robotics project) |
| Company Website | https://github.com/horner |
| Country | United States |

## Open-source integration research

Read-only source review completed November 20, 2026 by the parallel research agent. No projects were executed and no device connections were attempted. Repository last-pushed dates below are maintenance signals, not proof that a driver works.

| Project | Source and license evidence | Observed implementation and maintenance | Reuse decision |
| --- | --- | --- | --- |
| [MagicTape](https://github.com/murra133/MagicTape) | [MIT license](https://github.com/murra133/MagicTape/blob/main/LICENSE.md). README advertises an unofficial REEKON T1 Bluetooth wrapper and tape/phone coordinate workflow. | Last pushed September 22, 2024. The central [BLEContext.tsx](https://github.com/murra133/MagicTape/blob/main/src/phone/components/Bluetooth/BLEContext.tsx) file is empty; the Bluetooth UI imports that missing context and expects live/capture callbacks. Dependencies include `react-native-ble-plx` ^3.2.1, Expo 51 and React Native 0.74.5. | Relevant React Native workflow/reference, but **not a working or verified REEKON protocol implementation**. T1M/T1R and firmware coverage are not established. Do not use it as evidence that SDK access or the integration is solved. |
| [Measures-That-Matter](https://github.com/gitedmond/Measures-That-Matter) | [MIT license](https://github.com/gitedmond/Measures-That-Matter/blob/main/LICENSE). | Last pushed October 29, 2024. [T1-Listener.cs](https://github.com/gitedmond/Measures-That-Matter/blob/main/GRASSHOPPER/T1-Listener.cs) implements a Windows global keyboard-hook listener for HID text. Its separate Python RangeFinder/Bleak code appears laser/Bosch-oriented and is not verified as REEKON-compatible. | Useful example of keyboard-mode ingestion and desktop design-tool integration, **not structured BLE telemetry or an iOS driver**. |
| [jkamm/Measures-That-Matter](https://github.com/jkamm/Measures-That-Matter) | [MIT license](https://github.com/jkamm/Measures-That-Matter/blob/main/LICENSE), fork of the preceding project. | Last pushed November 1, 2024; adds a CSV measurement logger. Underlying REEKON capture remains HID-oriented. | Possible logging/workflow reference; does not supply the missing native BLE protocol implementation. |
| [kerf](https://github.com/loewj-reekon/kerf) | [MIT license](https://github.com/loewj-reekon/kerf/blob/main/LICENSE). | Last pushed November 1, 2026. README describes a simulated tape; `src/lib/tape.ts` uses `MockTape` and randomly generated readings. | Recent interface/demo reference only. **No hardware BLE driver** was established from this source. |

The public [REEKON-Tools GitHub organization](https://github.com/REEKON-Tools) displayed no public repositories when checked. The focused search did **not** verify a working public T1/T1M/T1R SDK/GATT wrapper or a Swift, Kotlin, or Capacitor integration. This is a bounded search result, not proof that none exists privately or elsewhere.

The official SDK request explicitly asks for sample integrations and official open-source implementations. Inspect any supplied examples against the selected model/firmware and the official protocol. Carry forward MIT attribution if any source is reused; the projects' MIT licenses do not grant rights to redistribute REEKON's separately supplied private SDK/documentation.

**Implication for the app:** keep the planned native BLE provider boundary. Generic React Native BLE plumbing and HID examples may help later, but source inspection found no validated drop-in REEKON driver. The hardware/interface decision remains pending official SDK access and an on-device interoperability test.

## Exact submitted intended-use text

> I am developing an iOS-first AprilTag field inspection and calibration app for robotics. The planned stack is a React Native interface with native ARKit integration and a shared AprilTag C/C++ geometry/calibration core; Android with ARCore is planned later. I want to receive measurements directly over BLE, offline, to associate explicitly selected measurements with named endpoints: for example, plumb heights from a defined floor datum to a tag center/corner, inter-tag ranges, and offsets from control points. The app will also support robot-camera diagnostics. A distance reading will be treated as a scalar constraint, not as an automatically known 3D position or direction.
>
> I am considering purchasing a T1M Utility or T1 Tomahawk, and potentially a T1R Range, but would like to inspect the latest BLE Connection Guide/SDK and terms before ordering hardware or choosing the native interface. Please provide access and confirm supported models/firmware; direct iOS and Android integration; saved/live measurement events and Position Service access; units, datum/reference and offset metadata; offline operation; and any SDK or protocol redistribution requirements. Links to current documentation and sample integrations, including any official open-source implementations, would be very helpful. This is an independent personal project; no employer sponsorship is implied, and this request does not commit to a hardware purchase or paid service.

## SDK inspection checklist

Not started: no private guide or SDK has been delivered. Public vendor release notes establish that an integration path exists, but do not establish detailed event formats, full metadata coverage, SDK redistribution terms, or successful iPhone interoperability.

- [ ] Record exact SDK/guide version and retrieval date; retain private materials privately.
- [ ] Confirm model and minimum firmware support for T1M, T1, and T1R.
- [ ] Identify service/characteristic definitions, read/write/notify behavior, live versus saved events, acknowledgments, duplicate/reconnect behavior, and device identity.
- [ ] Confirm units, precision, measurement kind, front/rear/hook/reference selection, offsets, relative zero, errors, and acquisition timestamps; record what is absent.
- [ ] Confirm Core Bluetooth/native iOS and Android BLE compatibility, sample languages, offline access, and whether a vendor app/account is required.
- [ ] Review license, documentation confidentiality, protocol use, shipped-library redistribution, attribution, fees, and approval requirements without accepting material terms.
- [ ] Ask targeted vendor questions about unresolved details before choosing equipment.

## Blockers and next action

The official request has been recorded and the focused open-source review is complete. The immediate mailbox check found no response. Await a vendor reply to **horner@mieweb.com**; no further submission or duplicate email was sent, and no recurring monitoring was scheduled. Once access arrives, inspect the SDK checklist above before selecting or ordering equipment. Vendor approval, detailed SDK terms, exact supported firmware, and actual iPhone interoperability remain unverified.
