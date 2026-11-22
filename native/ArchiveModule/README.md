# Native self-contained MP4 export

`ArchiveModule.swift`, `SessionMP4Writer.swift` and `ArchiveModuleBridge.m` belong to the iOS app target. `scripts/configure-ios.rb` includes them automatically. Do not add `tests/` to the app. The module uses Foundation and CryptoKit without an additional runtime package or server.

The existing bridge method name is retained:

```ts
const {url, path, bytes, format, mimeType} =
  await NativeModules.ArchiveModule.archiveSession(folderPath);
// url: local file:// URL for the share sheet
// format: "mp4"; mimeType: "video/mp4"
```

Call the capture module's `exportSession(id)` first and pass its finalized `folderPath`. The writer accepts only one direct UUID directory inside `Documents/AprilFoolsAR/sessions/`. It requires a finalized manifest and verifies the original file inventory; it does not rewrite or finalize source recordings.

Exports run on a background serial queue and appear under `Caches/AprilFoolsAR/exports/` with a unique `.mp4` filename. Failed partial outputs are removed. Completed exports remain available until iOS evicts caches. Original session folders remain untouched, including recordings created before this export format was added.

The MP4 carries the original clean H.264 video, three readable YAML tracks and a TAR track with the original sidecar files. Live overlays stay separate from the video pixels. The exporter preserves the original movie's sample bytes and allows the npm extractor to restore the complete original movie file byte-for-byte. See [the format contract](../../recording-format/FORMAT.md) and [FFmpeg extraction commands](../../recording-format/README.md).

Binary files are streamed in 64 KiB chunks. Metadata has explicit parsing/serialization bounds. Source/export sizes must stay below 4 GiB, with at most 65,534 entries, source JSON/JSONL files limited to 16 MiB and generated YAML/moov payloads limited to 64 MiB. Unsupported movie layouts, unsafe paths, symbolic links and changed source files reject rather than producing a partial recording. An export needs additional cache storage roughly equal to its complete size. Bridge failures reject as `session_export_failed`.

## Validation without a device

```sh
npm ci --prefix recording-format/npm
python3 native/ArchiveModule/tests/validate-mp4.py
npm --prefix recording-format/npm test
```

The native suite compiles the Foundation/CryptoKit writer with a standalone Swift harness, generates synthetic H.264/JPEG/depth recordings, checks normal and fast-start source movies, extracts YAML/TAR through stock FFmpeg, and restores every original byte with the npm reader. It also checks unchanged video sample hashes and rejection/cleanup paths. Swift, FFmpeg/FFprobe, Node 22+ and standard `tar` are required. No simulator or physical device is used by this suite. Production bridge registration is checked by the app build; real-device playback and sharing remain separate acceptance checks.

`SessionZIPWriter.swift` and its original standalone validation harness remain as legacy implementation code. App export calls the MP4 writer; existing ZIP recordings remain readable by `scripts/inspect-session.py`.
