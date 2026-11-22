#!/usr/bin/env python3
"""Compile the native exporter and verify real MP4/YAML/TAR interoperability.

Requires macOS Swift/CryptoKit, FFmpeg/FFprobe, Node 22+, and `npm ci --prefix
recording-format/npm`. All movie/sensor fixtures are synthetic; no device access.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid


REPOSITORY = Path(__file__).resolve().parents[3]
TRACKS = ("afar.session", "afar.frames", "afar.events", "afar.files")
MAX_BINARY_PACKET_BYTES = 1024 * 1024
# Real AR-frame values require all 17 significant digits. Include adjacent
# binary64 values and exponent extremes to catch NSNumber.stringValue rounding.
PRECISE_NUMBERS = [0.38682788610458374, -0.11663296073675156,
                   1.1928783112731773, math.nextafter(1.0, 2.0), math.pi,
                   1.2345678901234568e-20, 5e-324, 1.7976931348623157e308]


def run(arguments, *, cwd=None, accepted=(0,)):
    result = subprocess.run([str(argument) for argument in arguments], cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode not in accepted:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(map(str, arguments))}\n{result.stderr}\n{result.stdout}")
    return result.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_payloads(directory):
    return {location.relative_to(directory).as_posix(): location.read_bytes()
            for location in directory.rglob("*") if location.is_file()}


def fixture(sessions, *, faststart):
    source = sessions / str(uuid.uuid4()).upper()
    (source / "frames").mkdir(parents=True)
    (source / "depth").mkdir()
    (source / "empty-directory").mkdir()
    video = source / "rgb.mp4"
    run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x48:r=5",
         "-t", "0.6", "-c:v", "libx264", "-pix_fmt", "yuv420p",
         *(["-movflags", "+faststart"] if faststart else []), video])
    run(["ffmpeg", "-v", "error", "-i", video, "-frames:v", "1", "-update", "1", source / "frames/frame-2.jpg"])
    # Original noncanonical NaN bits and negative zero must survive without decoding.
    (source / "depth/frame-2.f32").write_bytes(bytes.fromhex("0000a03f4523c17f0000008000004040"))
    (source / "depth/frame-2.confidence.u8").write_bytes(bytes((2, 0, 1, 2)))
    (source / "zero-length.bin").write_bytes(b"")
    (source / ".hidden").write_text("preserved hidden file\n", encoding="utf-8")
    (source / "frames/été-タグ.txt").write_text("Unicode path and contents ✓\n", encoding="utf-8")
    # Force the native binary track across several bounded MP4 samples.
    large_bytes = 2 * MAX_BINARY_PACKET_BYTES + 31
    pattern = bytes(range(251))
    (source / "large-binary.bin").write_bytes((pattern * ((large_bytes + len(pattern) - 1) // len(pattern)))[:large_bytes])
    frames = [
        {"frameId": "frame-1", "segmentId": "segment-1", "timestamp": 12000.125,
         "videoPTSSeconds": 0, "videoAppended": True, "tracking": "normal",
         "precisionCases": PRECISE_NUMBERS},
        {"frameId": "frame-2", "segmentId": "segment-1", "timestamp": 12000.225,
         "videoPTSSeconds": 0.1, "videoAppended": False, "rgbImagePath": "frames/frame-2.jpg",
         "depthPath": "depth/frame-2.f32", "confidencePath": "depth/frame-2.confidence.u8",
         "depthWidth": 2, "depthHeight": 2, "testNull": None, "testZero": 0,
         "testOne": 1, "testFalse": False, "testTrue": True,
         "intrinsicsColumnMajor": [500.5, 0, 0, 0, 500.5, 0, 32, 24, 1]},
    ]
    events = [
        {"type": "bookmark", "frameId": "frame-2", "timestamp": 12000.225,
         "note": "Tag 4 — café 🦀\nyes: on\n---\ntrue", "rgbImagePath": "frames/frame-2.jpg"},
        {"type": "aprilTagDetections", "frameId": "frame-1", "timestamp": 12000.125,
         "detections": [], "analysisSucceeded": True, "precisionCases": PRECISE_NUMBERS},
    ]
    for name, records in (("frames.jsonl", frames), ("events.jsonl", events)):
        (source / name).write_text("".join(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records), encoding="utf-8")
    inventory = [{"path": name, "bytes": len(data), "sha256": digest(data)}
                 for name, data in sorted(file_payloads(source).items())]
    manifest = {
        "schemaVersion": 1, "id": source.name, "sessionId": source.name,
        "name": "Native YAML — café 🦀", "finalized": True,
        "createdAt": "2026-11-22T20:00:00Z", "durationSeconds": 0.6,
        "firstARFrameTimestamp": 12000.125, "fileInventory": inventory,
        "captureDefaults": {"jpegQuality": 0.94, "videoFPS": 30},
        "debugSettings": {"showPoseAxes": True, "showImperialHeight": False},
        "yamlScalarCases": {
            "strings": ["on", "true", "null", "3.14", "2026-11-22", "", "\\escape", '"quotes"'],
            "numbers": [0, 1, -1, 1.25, 1e-7, 1e23, *PRECISE_NUMBERS],
            "emptyObject": {}, "emptyArray": [],
            "a: b": "value", "? key": "value", "line\nbreak": "value",
        },
    }
    (source / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return source, frames, events, manifest


def node_json(node, script, *arguments):
    return json.loads(run([node, "--input-type=module", "-e", script, *arguments]))


def compare_inspection(source, movie):
    inspector = REPOSITORY / "scripts/inspect-session.py"
    original = json.loads(run([sys.executable, inspector, source], accepted=(0, 1)))
    wrapped = json.loads(run([sys.executable, inspector, movie], accepted=(0, 1)))
    assert original == wrapped, "Direct MP4 inspection differs from original source-directory inspection"


def validate_fixture(work, executable, node, *, faststart):
    mode = "faststart" if faststart else "moov-at-end"
    case = work / mode
    sessions, exports = case / "sessions", case / "exports"
    sessions.mkdir(parents=True)
    source, frames, events, manifest = fixture(sessions, faststart=faststart)
    originals = file_payloads(source)
    exported = json.loads(run([executable, "export", sessions, source, exports]))
    movie = Path(exported["path"])
    assert movie.stat().st_size == exported["bytes"]
    assert file_payloads(source) == originals, "Native exporter changed source files"

    streams = json.loads(run(["ffprobe", "-v", "error", "-show_entries",
                              "stream=index,codec_type,codec_tag_string:stream_tags=handler_name",
                              "-of", "json", movie]))["streams"]
    metadata = {stream["tags"]["handler_name"]: stream for stream in streams
                if stream.get("tags", {}).get("handler_name") in TRACKS}
    assert set(metadata) == set(TRACKS)
    for name, stream in metadata.items():
        assert stream["codec_type"] == "data"
        assert stream["codec_tag_string"] == ("urim" if name == "afar.files" else "mett")
        allocation_limit = ["-max_alloc", str(2 * MAX_BINARY_PACKET_BYTES)] if name == "afar.files" else []
        run(["ffmpeg", "-v", "error", *allocation_limit, "-i", movie, "-map", f"0:m:handler_name:{name}",
             "-c", "copy", "-f", "data", case / name])
    binary_packets = json.loads(run(["ffprobe", "-v", "error", "-select_streams",
                                    "m:handler_name:afar.files", "-show_packets",
                                    "-show_entries", "packet=size", "-of", "json", movie]))["packets"]
    assert len(binary_packets) >= 3, "Binary fixture did not exercise several MP4 samples"
    packet_sizes = [int(packet["size"]) for packet in binary_packets]
    assert all(0 < size <= MAX_BINARY_PACKET_BYTES for size in packet_sizes), "Native binary packet exceeds 1 MiB"
    assert sum(packet_sizes) == (case / "afar.files").stat().st_size

    yaml_module = (REPOSITORY / "recording-format/npm/node_modules/yaml/dist/index.js").as_uri()
    parse_yaml = """const YAML = await import(process.argv[1]);
const fs = await import('node:fs/promises');
const text = await fs.readFile(process.argv[2], 'utf8');
const docs = YAML.parseAllDocuments(text);
for (const doc of docs) if (doc.errors.length) throw doc.errors[0];
process.stdout.write(JSON.stringify(docs.map(doc => doc.toJS({maxAliasCount: 0}))));"""
    session_yaml = node_json(node, parse_yaml, yaml_module, case / "afar.session")[0]
    assert session_yaml["format"] == "april-fools-ar-recording"
    assert session_yaml["version"] == 1 and session_yaml["draft"] is False
    assert session_yaml["session"] == manifest
    assert node_json(node, parse_yaml, yaml_module, case / "afar.frames") == frames
    assert node_json(node, parse_yaml, yaml_module, case / "afar.events") == events
    for name in TRACKS[1:]:
        payload = (case / name).read_bytes()
        assert session_yaml["payloads"][name]["bytes"] == len(payload)
        assert session_yaml["payloads"][name]["sha256"] == digest(payload)

    sidecars = case / "sidecars"
    sidecars.mkdir()
    run(["tar", "-xf", case / "afar.files", "-C", sidecars])
    assert file_payloads(sidecars) == {name: data for name, data in originals.items() if name != "rgb.mp4"}
    assert (sidecars / "empty-directory").is_dir()

    npm_module = (REPOSITORY / "recording-format/npm/src/index.mjs").as_uri()
    restored = case / "restored"
    inspected = node_json(node, """const api = await import(process.argv[1]);
const info = await api.inspectRecording(process.argv[2]);
await api.unpackRecording(process.argv[2], process.argv[3]);
process.stdout.write(JSON.stringify(info));""", npm_module, movie, restored)
    assert inspected["session"] == manifest
    assert file_payloads(restored) == originals, "npm did not restore every native source byte"
    assert (restored / "empty-directory").is_dir()
    for entry in manifest["fileInventory"]:
        assert digest((restored / entry["path"]).read_bytes()) == entry["sha256"]

    run(["ffmpeg", "-v", "error", "-i", movie, "-map", "0:v:0", "-f", "null", "-"])
    def video_hash(location):
        return run(["ffmpeg", "-v", "error", "-i", location, "-map", "0:v:0", "-c", "copy", "-f", "hash", "-hash", "sha256", "-"])
    assert video_hash(movie) == video_hash(source / "rgb.mp4")
    compare_inspection(source, movie)

    # Legacy capture correction belongs only in the active track header. The
    # source prefix and every original file must still restore byte-for-byte.
    rotated_result = json.loads(run([executable, "export", sessions, source, exports,
                                     "[0,1,-1,0,48,0]"]))
    rotated = Path(rotated_result["path"])
    rotation = json.loads(run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                              "-show_entries", "stream_side_data=rotation,displaymatrix",
                              "-of", "json", rotated]))["streams"][0]["side_data_list"][0]
    assert rotation["rotation"] == -90, "Playback transform did not rotate sensor pixels clockwise"
    assert rotated.read_bytes()[:len(originals["rgb.mp4"])] == movie.read_bytes()[:len(originals["rgb.mp4"])]
    rotated_restored = case / "rotated-restored"
    node_json(node, """const api = await import(process.argv[1]);
const result = await api.unpackRecording(process.argv[2], process.argv[3]);
process.stdout.write(JSON.stringify(result));""", npm_module, rotated, rotated_restored)
    assert file_payloads(rotated_restored) == originals, "Playback rotation changed original source bytes"
    assert video_hash(rotated) == video_hash(source / "rgb.mp4")
    if not faststart:
        print(run([executable, "check", sessions, source, exports]).strip())
        empty_source = sessions / str(uuid.uuid4()).upper()
        shutil.copytree(source, empty_source)
        empty_manifest = json.loads((empty_source / "manifest.json").read_text(encoding="utf-8"))
        for name in ("frames.jsonl", "events.jsonl"):
            (empty_source / name).write_bytes(b"")
            entry = next(item for item in empty_manifest["fileInventory"] if item["path"] == name)
            entry.update(bytes=0, sha256=digest(b""))
        (empty_source / "manifest.json").write_text(json.dumps(empty_manifest, ensure_ascii=False), encoding="utf-8")
        empty_export = json.loads(run([executable, "export", sessions, empty_source, exports]))
        empty_movie = Path(empty_export["path"])
        for name in ("afar.frames", "afar.events"):
            output = case / (name + ".empty")
            run(["ffmpeg", "-v", "error", "-i", empty_movie, "-map", f"0:m:handler_name:{name}", "-c", "copy", "-f", "data", output])
            assert node_json(node, parse_yaml, yaml_module, output) == []
        empty_restored = case / "empty-restored"
        node_json(node, """const api = await import(process.argv[1]);
const result = await api.unpackRecording(process.argv[2], process.argv[3]);
process.stdout.write(JSON.stringify(result));""", npm_module, empty_movie, empty_restored)
        assert file_payloads(empty_restored) == file_payloads(empty_source)
        compare_inspection(empty_source, empty_movie)
        print("PASS: empty native YAML record streams and direct MP4 inspection match their original sessions.")
    print(f"PASS: Swift → FFmpeg YAML/TAR → npm exact restoration ({mode}); binary samples ≤1 MiB, compressed video unchanged.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default=os.environ.get("NODE", "node"), help="Node 22+ executable")
    parser.add_argument("--keep", type=Path, help="Create and retain fixtures under this NEW directory")
    arguments = parser.parse_args()
    node = shutil.which(arguments.node)
    if node is None:
        raise RuntimeError("Node 22+ executable not found: " + arguments.node)
    # inspect-session.py launches `node` itself; honor the selected test runtime.
    os.environ["PATH"] = str(Path(node).parent) + os.pathsep + os.environ.get("PATH", "")
    if arguments.keep:
        arguments.keep.mkdir(parents=True, exist_ok=False)
        work = arguments.keep.resolve()
    else:
        work = Path(tempfile.mkdtemp(prefix="april-fools-ar-native-mp4-"))
    try:
        executable = work / "validate-native-mp4"
        run(["swiftc", REPOSITORY / "native/ArchiveModule/SessionMP4Writer.swift",
             REPOSITORY / "native/ArchiveModule/tests/ValidateMP4.swift", "-o", executable])
        for faststart in (False, True):
            validate_fixture(work, executable, node, faststart=faststart)
        print("PASS: native MP4 format integration (synthetic inputs; no device or accuracy claim).")
        if arguments.keep:
            print(f"Fixtures retained at {work}")
    finally:
        if not arguments.keep:
            shutil.rmtree(work)


if __name__ == "__main__":
    main()
