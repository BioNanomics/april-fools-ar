# Self-contained MP4 recordings

This folder defines the single-file export for April Fools AR. The MP4 keeps its clean camera video and carries readable **YAML** metadata plus the original images and numeric sensor files. A recipient can inspect the metadata with stock FFmpeg, without an npm package, Rust library, or app installation.

**Status: version 1, adopted for app exports.** The iOS app records durable session folders and automatically saves a complete MP4 with the native streaming writer when recording stops. Play previews that saved file; Share sends the same file. The video stays free of burned-in tag outlines, measurements and other screen graphics; their recorded geometry stays available for later processing. A normal player shows the camera video. Offline overlay playback is not yet implemented. Device playback and metadata retention through particular sharing destinations require acceptance checks.

## Files in this folder

- [FORMAT.md](FORMAT.md): version-1 container, YAML, binary storage, clocks, and integrity rules.
- [npm/](npm/): a local Node library and command-line packer/extractor. It does not require FFmpeg at runtime; readers stream the video and binary payloads.
- [Native writer](../native/ArchiveModule/SessionMP4Writer.swift): the app's Swift exporter, with streaming binary I/O.
- `npm/tests/roundtrip.mjs`: byte-for-byte round-trip and stock-FFmpeg compatibility checks using synthetic input.

Start with npm. A Rust implementation can use the same format and fixtures later; no crate is implemented yet. The npm package is local and unpublished.

## Make and open a recording

Requires Node 22 or later. FFmpeg and FFprobe are additionally required for the integration tests and the manual commands below.

```sh
npm ci --prefix recording-format/npm

node recording-format/npm/src/cli.mjs pack /path/to/finalized-session capture.mp4
node recording-format/npm/src/cli.mjs list capture.mp4
node recording-format/npm/src/cli.mjs unpack capture.mp4 restored-session
```

`unpack` creates a new directory containing the original session files, including the byte-exact original `rgb.mp4`. It verifies the stored SHA-256 checksums. Existing output paths are rejected. App exports and the streaming readers support files below 4 GiB. The optional Node `pack` helper remains an in-memory implementation limited to 256 MiB source sessions; the app uses the streaming native writer. See the format document and library exports for metadata and entry-count limits.

The CLI prints its structured results in YAML as well. FFprobe's discovery output uses JSON because FFprobe does not have a YAML writer; this does not change the embedded YAML payloads.

## Extract YAML with FFmpeg alone

First list the streams and their names:

```sh
ffprobe -v error -show_entries stream=index,codec_type,codec_tag_string:stream_tags=handler_name -of json capture.mp4
```

The metadata payloads themselves are YAML. Select a track by its `handler_name`:

```sh
ffmpeg -i capture.mp4 -map '0:m:handler_name:afar.session' -c copy -f data session.yaml
ffmpeg -i capture.mp4 -map '0:m:handler_name:afar.frames' -c copy -f data frames.yaml
ffmpeg -i capture.mp4 -map '0:m:handler_name:afar.events' -c copy -f data events.yaml
```

These commands produce readable YAML directly. `session.yaml` contains the session details, format version and integrity information. `frames.yaml` and `events.yaml` contain multiple YAML documents separated by `---`, in original record order. Source timestamps, frame IDs and coordinate segments remain in the records; the FFmpeg raw-data output does not preserve MP4 packet timestamps.

FFmpeg may report an unknown codec for the metadata tracks. It can still copy the opaque sample bytes with `-c copy -f data`; it does not need to decode YAML. Large binary payloads are split into small MP4 packets, so extracting the archive does not require a single archive-sized packet allocation.

## Extract the original sidecar files with standard tools

JPEG images and Float32 depth maps stay binary. They are carried in an uncompressed TAR data track, together with the exact original JSON/JSONL files from the current recorder:

```sh
ffmpeg -i capture.mp4 -map '0:m:handler_name:afar.files' -c copy -f data files.tar
tar -tf files.tar
mkdir restored-sidecars
tar -xf files.tar -C restored-sidecars
```

This needs FFmpeg and ordinary `tar`, with no custom extraction code. The archive omits `rgb.mp4` to avoid duplicating the video. To get a playable standalone video with FFmpeg:

```sh
ffmpeg -i capture.mp4 -map 0:v:0 -c copy camera.mp4
```

Remuxed `camera.mp4` has a different container and will not match the original movie's file checksum. Use the npm `unpack` command when exact restoration of the original recording is required.

The metadata tracks are extraction-oriented. Ordinary video conversion/editing can discard them, and FFmpeg need not support writing these opaque tracks back into MP4. Share the original file for analysis.

## Library use

```js
import {
  packSession,
  inspectRecording,
  extractTrack,
  unpackRecording,
} from './recording-format/npm/src/index.mjs';

await packSession('/path/to/finalized-session', 'capture.mp4');
const recording = await inspectRecording('capture.mp4');
await extractTrack('capture.mp4', 'afar.events', 'events.yaml');
await unpackRecording('capture.mp4', 'restored-session');
```

Run the checks:

```sh
npm --prefix recording-format/npm test
```

Validate the native writer against the npm reader and stock FFmpeg on macOS:

```sh
python3 native/ArchiveModule/tests/validate-mp4.py
```

Synthetic fixtures establish file preservation and FFmpeg extraction, not camera alignment, LiDAR accuracy or acceptance by every movie player. Keep the original file when sharing for analysis; a destination that converts it as a video may discard embedded data.

## References

- [Existing capture format](../docs/capture-format.md) describes the source session data.
- [FFmpeg data muxer](https://ffmpeg.org/ffmpeg-formats.html#Raw-muxers) accepts a selected stream and writes its bytes without decoding them.
- [FFmpeg stream selection](https://ffmpeg.org/ffmpeg.html#Stream-selection) explains explicit stream mapping.
- [RFC 9512](https://www.rfc-editor.org/rfc/rfc9512.html) registers the `application/yaml` media type.
- [MP4 Registration Authority](https://mp4ra.org/) lists the existing MP4 extension mechanisms and registered sample entries.
