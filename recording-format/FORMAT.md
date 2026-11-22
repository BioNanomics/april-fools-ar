# April Fools AR recording, version 1

This is the app's export transport for the existing [schema-1 capture session](../docs/capture-format.md). It is not a new camera calibration or coordinate system. The writer produces a conventional, nonfragmented MP4 with its original video and four additional metadata tracks. The main video contains the clean camera feed without burned-in overlays or audio. Live tag and measurement graphics remain separate from its pixels, preserving the imagery for later processing. The recorded geometry supports future overlay viewers; pixel-identical replay of the complete app UI is not part of this version.

The version identifies the container contract. It does not replace `session.schemaVersion`, which identifies the source capture schema. This format has not been registered as an industry interchange standard. New exports set `draft: false`; readers also accept `draft: true` from the earlier compatible prototype.

## Track directory

| Handler name | Sample entry | Payload | Purpose |
| --- | --- | --- | --- |
| `afar.session` | `mett` | UTF-8 `application/yaml` | One document: format, session details, source-video restoration and payload integrity |
| `afar.frames` | `mett` | UTF-8 `application/yaml` | YAML document stream of camera-frame records |
| `afar.events` | `mett` | UTF-8 `application/yaml` | YAML document stream of events, notes, detections and measurements |
| `afar.files` | `urim` | Uncompressed POSIX USTAR | Exact original sidecar files, including metadata JSON/JSONL, JPEGs and binary depth/confidence |

All four tracks use the `meta` handler type and have no visual or audio dimensions. Track IDs are unique within the movie. Identify a payload by the handler name, rather than a fixed stream index or track ID. The existing video track is preserved.

Each YAML payload is carried as one complete sample. New writers split the TAR payload into contiguous samples of at most 1 MiB in a single chunk, so a video demuxer does not have to allocate the entire archive as one packet. Concatenating those sample bytes reproduces the exact ordinary TAR file. Readers also accept the earlier prototype's single-sample TAR tracks.

This is an extraction container, not a promise of frame-by-frame metadata delivery in a movie player. Semantic time is stored in YAML and the original sidecar records. Metadata track durations cover the movie; their packet times are storage timing rather than sensor acquisition times. A TAR track with multiple samples scales its media clock to represent equal-duration samples without changing the movie's duration. If the media clock cannot fit the supported integer range, the writer rejects that unusual source timescale.

### Text entries

The `mett` sample entry uses the standard six reserved bytes and two-byte self-contained data-reference index, an empty NUL-terminated `content_encoding` and NUL-terminated MIME format `application/yaml`. There is no private binary prefix before the YAML bytes.

### Binary entry

The `urim` sample entry uses the standard reserved bytes and data-reference index, followed by a `uri ` FullBox (version and flags zero) with this NUL-terminated payload identifier:

```text
urn:april-fools-ar:recording:1:files:tar
```

The URI identifies the version-1 TAR contract; it is not a URL that must be fetched and is not a claim of formal namespace registration. There is no custom binary prefix before the TAR bytes or between its samples. This lets FFmpeg's raw-data muxer emit an ordinary TAR archive.

## YAML model

Use YAML 1.2 with JSON-compatible values: mappings with string keys, sequences, strings, finite numbers, booleans and null. Do not introduce application-specific tags or object construction. Writer output does not require anchors or aliases. Readers must constrain input sizes and alias expansion.

`afar.session` contains one mapping with these fields:

```yaml
format: april-fools-ar-recording
version: 1
draft: false
session:
  # Complete original manifest, including its capture schema and fileInventory.
  schemaVersion: 1
  finalized: true
  name: Field walk
sourceVideo:
  bytes: 123456
  sha256: <64 lowercase hexadecimal characters>
  moovOffset: 120000
payloads:
  afar.frames:
    bytes: 2345
    sha256: <64 lowercase hexadecimal characters>
    mimeType: application/yaml
  afar.events:
    bytes: 3456
    sha256: <64 lowercase hexadecimal characters>
    mimeType: application/yaml
  afar.files:
    bytes: 45678
    sha256: <64 lowercase hexadecimal characters>
    mimeType: application/x-tar
```

The numbers and digest placeholders above are illustrative. The actual `session` mapping contains the full original manifest, not just the example fields. Preserve build identity, coordinate conventions, errors and dropped-frame diagnostics. The session envelope does not hash itself; its payload digests provide corruption checks, not authenticity or a digital signature.

`afar.frames` and `afar.events` contain one YAML document for each original JSONL record, in the original file order. Each document begins with `---`. A stream with no source records contains only `# No records.` and a newline, so its MP4 sample is nonempty without adding a YAML document. For example:

```yaml
---
frameId: frame-42
segmentId: segment-1
timestamp: 12000.225
videoPTSSeconds: 0.1
videoAppended: false
rgbImagePath: frames/frame-42.jpg
```

Keep source records and their keys unchanged during JSON-to-YAML conversion. In particular:

- An AR timestamp is monotonic seconds since boot; it is not Unix time. Preserve wall-clock strings separately.
- A frame record may have `videoAppended: false`. Do not discard it or invent a matching movie frame.
- Detection processing can finish after later camera frames. Preserve original event order and source timestamps independently; do not sort the event stream by timestamp.
- Frame IDs, coordinate-segment IDs, missing-data reasons and paths stay attached to their source records.
- Camera poses, intrinsics, transforms, depth units and confidence categories keep the existing capture conventions.

The original JSON/JSONL bytes also live in `afar.files`. They retain the original serialization and file checksums independently of the readable YAML conversion. Binary Float32 data must not be converted through YAML numbers; doing so could change NaN payload bits or other original bytes.

## Original files

`afar.files` is an uncompressed USTAR archive containing all regular source-session files except the root `rgb.mp4`. Include the exact original `manifest.json`, `frames.jsonl` and `events.jsonl`, plus JPEGs, depth/confidence buffers and other regular sidecar files. Use relative POSIX paths. The prototype rejects names it cannot represent safely with USTAR, rather than renaming them.

Readers reject absolute paths, `.` or `..` components, backslashes, ambiguous names, duplicate paths, symlinks, hardlinks and other special entries. The archive cannot supply `rgb.mp4`; the extractor restores it from the source-video prefix. Extract into a new directory and do not overwrite an existing destination. Verify archive checksums, payload lengths and SHA-256 hashes before reporting success.

The TAR choice is deliberate: `ffmpeg -c copy -f data files.tar` followed by ordinary `tar -xf` restores sidecar files without custom extraction code. FFmpeg alone dumps a track; it does not recreate the file hierarchy stored inside that track.

## Preserving the original video

The writer copies the original `rgb.mp4` without moving any source bytes, then:

1. Changes its original top-level movie box's four-byte type from `moov` to `free`.
2. Appends an `mdat` box containing the four payloads.
3. Appends a replacement `moov` containing the original movie's tracks and the four metadata tracks. It updates the next available track ID.

Original video sample offsets remain correct. `sourceVideo.bytes` gives the length of the original file, `sourceVideo.moovOffset` identifies the original movie-box header, and `sourceVideo.sha256` hashes the original, unmodified `rgb.mp4`.

To restore the movie exactly, copy that prefix, restore the four type bytes to `moov`, and verify the original length and SHA-256. The npm extractor does this without decoding or remuxing the video. It also verifies the original manifest's file inventory after restoring all files.

FFmpeg can instead remux the visible video track into a playable standalone MP4. This preserves its compressed video samples but changes movie-container bytes, so the result is not the original file for checksum purposes. Editing or remuxing the package can also invalidate the prefix-restoration information; retain the original package for exact restoration.

## Implementations and limits

The app's native Swift writer streams video and TAR file contents in bounded chunks. Node readers stream input and restored binary files as well. The exported file must remain below 4 GiB, with at most 65,534 file/directory entries. Source JSON/JSONL files are capped at 16 MiB each; generated/read YAML payloads and movie metadata boxes are capped at 64 MiB each, with at most 100,000 records per metadata stream. Metadata is held in bounded memory for parsing and serialization. These are implementation limits, not fundamental MP4 container limits.

The optional Node `packSession` helper remains an in-memory implementation capped at 256 MiB of original session files. This cap does not apply to the app's native writer or the streaming Node readers.

Source movies must have exactly one H.264 video track (`avc1` or `avc3`), a self-contained, ordinary nonfragmented layout with one top-level `moov`, explicit box sizes and supported movie/track headers. Reject unsupported structures rather than silently producing an incomplete export, including fragmented movies, compressed movie metadata, external media references and an already wrapped recording. Box lengths, metadata sample offsets and payload lengths must be in range. The source movie is assumed to contain valid video sample tables; the writer preserves those tables and video bytes but does not fully validate the original video chunk offsets or decode the movie. The reader supports this format's explicit sample sizes and one contiguous chunk per metadata track, not arbitrary MP4 media decoding.

The app exports this format through **Saved sessions → Export MP4**. Existing local session directories retain the original schema, and the analysis inspector continues to accept legacy ZIP exports. Check a real finalized iOS session, interrupted export, metadata retention on intended sharing paths and playback in the intended viewers before treating those device-specific acceptance checks as passed.

## Interoperability evidence

The repository's integration test generates normal and fast-start H.264 source movies, wraps YAML and TAR payloads, and checks:

- FFprobe finds the four named data tracks.
- Stock FFmpeg extracts each payload byte-for-byte with stream copy and decodes the video.
- Ordinary `tar` restores the sidecar files.
- The npm extractor restores every source file and its original checksum, including the movie, Unicode notes, a metadata-only frame and noncanonical Float32 NaN bits.
- Invalid input, changed payloads, unsafe source links and existing destinations are rejected.

Direct extraction was initially verified with FFmpeg 8.1.2. Its unknown-codec diagnostics for `mett`/`urim` do not prevent raw stream copying. This does not establish support for writing these opaque tracks back to MP4 with FFmpeg, nor acceptance by every movie player.

## Primary references

- [MPEG conformance definitions for sample entries](https://github.com/MPEGGroup/FileFormatConformance/blob/main/data/standard_features/14496-12/codecs.json), including `mett` and `urim`.
- [MPEG conformance box definitions](https://github.com/MPEGGroup/FileFormatConformance/blob/main/data/standard_features/14496-12/boxes.json), including `uri `.
- [MP4 registered sample entries](https://mp4ra.org/registered-types/codecs).
- [FFmpeg raw muxers](https://ffmpeg.org/ffmpeg-formats.html#Raw-muxers): `data` copies a selected stream's bytes without interpreting its codec.
- [RFC 9512](https://www.rfc-editor.org/rfc/rfc9512.html): YAML media type and interoperability considerations.
