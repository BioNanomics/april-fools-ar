# Saved-session deletion

Version **0.8.2 (28)** adds **Delete** beside Play and Share in Saved sessions. Its confirmation names the session and explains that removal of its video and original capture data is permanent. Cancel preserves the recording. Deletion removes the raw capture folder, saved MP4, integrity receipt and matching abandoned staging directories. Unfinished captures from earlier runs can be removed; the current recording and finalization are protected.

The native store uses the same process and file locks as MP4 preparation. It validates deletion targets before removal, retains the source until artifact cleanup succeeds and leaves ordinary failures available for retry. The UI locks conflicting actions during confirmation/deletion, removes the card only on success and ignores a stale list response that could otherwise restore it.

## Validation

- All **57 React tests across five suites** passed in an isolated snapshot of the staged deletion commit, including confirmation/cancel, targeted removal, failure/retry, unfinished and active-session handling, pending action locks, Android dismissal behavior and stale refresh responses. The earlier combined working tree, including other pending features, passed 63 tests across six suites.
- TypeScript, bundled legal-document freshness and diff whitespace checks passed. ESLint reported zero errors and the three existing warnings.
- `python3 native/ArchiveModule/tests/validate-saved-recording.py` passed in both the isolated staged snapshot and combined working tree: full artifact removal, repeated deletion, missing artifacts, unfinished/corrupt captures, unrelated-session retention, symlink/path protections and serialization with concurrent preparation, alongside existing saved-recording lifecycle and orientation checks.
- The production Release simulator build from the combined implementation working tree succeeded with installed package metadata **0.8.2 (28)**.
- A native XCTest accessibility check passed on a dedicated **iPhone 17 Pro / iOS 26 simulator**. Play, Share and Delete were accessible, hittable and at least 44 points in both dimensions. Cancel preserved all seeded files; confirmed deletion removed only the selected session's folder, MP4, receipt and staging directory. Refresh and app relaunch kept it absent while preserving the sibling recording. Five host filesystem checkpoints passed, and canonical screenshots were visually inspected.

Local simulator evidence: `/tmp/april-session-delete-validation/Results.xcresult`, `filesystem-results.json`, `screenshots/` and `test.log`.

Only synthetic recordings were used. The task simulator was shut down, deleted and verified absent afterward. No physical device was installed, launched or captured for this change. Previously exported or backed-up copies and legacy cached exports remain managed separately, as described in the privacy policy.
