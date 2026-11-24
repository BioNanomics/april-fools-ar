# Recording preparation memory investigation

November 22, 2026, with analysis completed November 23 UTC. Reported app: **0.7.1 (24)**, clean source `408a796`. The user reported a closure around **11:06 PM America/Indianapolis** when ending a recording and another when opening the latest capture.

## Finding

Recording preparation has a reproducible memory defect. Foundation temporaries from JSON parsing and scalar serialization accumulated across the entire metadata conversion. File read buffers also accumulated across streaming and checksum loops. Both Stop & Save and Play enter the affected preparation path.

The latest capture starts at 11:06:50 PM, lasts 34.50 seconds, and is finalized with no manifest errors. It contains 1,035 indexed video frames, 1,041 events and 343,506,768 bytes of source payload. The copied frame/event JSONL and original video match their manifest sizes and SHA256s. JSON is valid, with finite numbers and nesting depth seven.

There was no published MP4/receipt for this capture. Reopening it left an empty private packaging directory at 11:17:18 PM. The writer creates its output file only after metadata conversion and preliminary hashing, so this evidence places the failed attempt before player presentation.

## Reproduction

All measurements below are optimized Swift on Apple Silicon macOS, not physical iPhone memory measurements.

| Experiment | Before peak RSS | Fixed peak RSS |
| --- | ---: | ---: |
| Exact original frame/event JSONL conversion | 3,812,753,408 B (3.55 GiB) | 64,782,336 B (61.8 MiB) |
| Full-size native export, with per-record pooling already present | 794,312,704 B | 85,508,096 B |
| Saved-recording preparation, with fixed writer but unpooled verification hash | 449,003,520 B | 88,604,672 B |

The first experiment uses the actual copied metadata. Before/after frame and event YAML sizes and hashes match exactly.

The full-size experiments use the exact original JSONL/video. Unfetched JPEG/depth sidecars are explicitly **synthetic sparse zero files** matching the original sizes/paths; only a temporary manifest contains their replacement hashes. This measures the source file count and streaming volume, not the photographic contents. Every before/after export and store result is the same 363,364,445-byte MP4, SHA256 `ff37f50c7011af06c9c3eceddcd3747da6113e552d9b050d16f27dc053c8a690`.

The accumulation mechanism and use of local autorelease pools agree with Apple's [heap-memory analysis guidance](https://developer.apple.com/videos/play/wwdc2024/10173/) and [autorelease-pool guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html).

## Correction and checks

`SessionMP4Writer` now drains parsing/serialization temporaries per JSONL record and read/consumer temporaries per file chunk. `SavedRecordingStore` drains movie-verification buffers per chunk. `CaptureRecorder` does the same while checksumming finalized source files. Cancellation, integrity checks, serialization and source bytes retain their existing behavior.

- A new synthetic regression checks dense floating-point metadata plus a 160 MiB sidecar. Save and fresh-process reopen pass below the 256 MiB RSS budget, with observed peaks of 30.1 MiB and 9.9 MiB. The same regression against the pre-fix `44d2692` source fails during save and terminates the child once sampled RSS reaches 341.0 MiB, avoiding an unbounded failing run.
- Native MP4 integration passes for normal and fast-start movies, exact numeric round trips, empty streams, exact source restoration, unchanged compressed video, cancellation, invalid input and size limits.
- Saved-recording tests pass for reuse, relaunch, concurrency, interrupted publication, cancellation, path containment, source integrity and playback orientation.
- Unsigned iOS Release build passes, including the capture checksum path. Local output: `/tmp/april-fools-recording-memory-build/`; build log: `/tmp/april-fools-recording-memory-build.log`.
- `git diff --check` and Python syntax checks pass.

```sh
python3 native/ArchiveModule/tests/validate-recording-memory.py
python3 native/ArchiveModule/tests/validate-recording-memory.py --source-ref 44d2692
python3 native/ArchiveModule/tests/validate-mp4.py
python3 native/ArchiveModule/tests/validate-saved-recording.py
APRIL_BUILD_DIR=/tmp/april-fools-recording-memory-build ./scripts/build-ios.sh --unsigned
```

The old-source memory command is expected to fail. Physical save/play acceptance remains outstanding.

## Signed iPhone handoff

At the user's request, **0.7.1 (25)** was installed in place and launched successfully. The package reuses the validated Release artifact, with its package/embedded build number advanced from 24 to 25. Its compile date, base commit `44d2692`, `workingTreeDirty: true`, and native binary UUID remain unchanged. The existing development identity/profile were reused; the final nested signatures were verified before device access. Matching symbols and the exact three-file memory fix were preserved privately for future crash analysis.

The installed-app query confirmed version/build 0.7.1 (25). The complete Documents file listing, entry sizes and directory flags matched before/after installation. No recording was started, altered or deleted. No screen sharing or WDA/XCTest runner was started. Every owned deployment command exited and the global device guard returned `released` with no errors. Private installation evidence is under `/tmp/april-recording-memory-handoff-20261123/`.

The user will test reopening the previously failing capture, closing/reopening playback, and stopping/saving a new recording. Successful installation and launch do not establish these acceptance results.

## Device evidence and limits

Crash reports were copied without deleting them from the phone. Device Hub and the complete crash-log listing contain four already-investigated November 20 exception crashes and two November 22 CPU warnings from builds 13/16. Those CPU reports explicitly took no action; their dominant stacks are AprilTag detection and they do not establish a termination. The available November 22 Jetsam report does not list this app. The final refresh still contains no app exception or Jetsam report for the recent incident window.

The memory defect is proven and strongly explains termination during this recording's preparation. **The exact iOS termination reason remains unconfirmed without a corresponding current report.** Player dismissal and a device-only AVKit fault have not been established as causes.

Private reports, matching symbols, original capture subset, hashes and probe results are preserved locally under the Git-ignored `crash-reports/2026-11-22/`. No user footage or device identifiers are committed. Device Hub's final fresh window inventory showed View Screen enabled, keyboard capture off and no live-view controls; the global guard verified this and returned `released`. Subsequent read-only retrieval leases also returned `released`. No WDA/XCTest runner was installed or left running.
