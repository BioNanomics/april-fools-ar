# Native session ZIP export

Add `ArchiveModule.swift`, `SessionZIPWriter.swift` and `ArchiveModuleBridge.m` to the iOS app target. Do not add `tests/` to the app. React Native's existing React module/header search paths are required; this module adds no package dependency or UIKit code.

JavaScript interface:

```ts
const {url, path, bytes} = await NativeModules.ArchiveModule.archiveSession(folderPath);
// url: a local file:// URL suitable for the iOS share sheet
// path: absolute cache path; bytes: complete ZIP size
```

Call the capture module's `exportSession(id)` first and pass its finalized `folderPath`. The archive module accepts only one direct UUID directory inside the app's `Documents/AprilFoolsAR/sessions/`. It does not finalize or change capture data. The capture module owns the active/finalizing-session guard; callers must not modify the session during archival.

Exports run on a background serial queue and appear under `Caches/AprilFoolsAR/exports/` with a unique `.zip` filename. Original session files remain untouched. Failed partial archives are deleted. Completed archives remain available for sharing until iOS evicts caches or the caller removes them after sharing.

ZIP entries use STORE (no compression), UTF-8 names, CRC32, signed data descriptors and a conventional central directory/end record. File contents are read in 64 KiB chunks. Hidden files, nested regular files, zero-byte files and empty directories are included; symlinks are excluded. Unsupported special files or ambiguous portable paths (including backslash/colon names) reject instead of being silently renamed. Source containment and file metadata are rechecked while writing. Finalized immutable capture data is still required; this is not a filesystem snapshot/locking service.

ZIP64 is intentionally unsupported: entries/archive offsets/total size must remain below 4 GiB and there must be fewer than 65,535 entries. Large inputs reject honestly rather than producing corrupt output. Uncompressed export needs enough additional cache disk space for a full copy; write failures reject the promise as `session_archive_failed`.

## Standalone validation

Run from the repository root on macOS (Swift + `/usr/bin/unzip`; no simulator or React needed):

```sh
swiftc native/ArchiveModule/SessionZIPWriter.swift native/ArchiveModule/tests/ValidateArchive.swift -o /tmp/april-fools-ar-validate-archive
/tmp/april-fools-ar-validate-archive
```

The harness builds an actual session fixture, runs `unzip -t`, extracts and compares every payload byte, tests Unicode and hidden entries, checks symlink exclusion and empty directories, and verifies traversal/outside-root/symlink-source/ZIP64 rejection. Its temporary files, including a sparse 4 GiB boundary file, are removed afterward. Production root selection and React registration require the separate iOS app build.
