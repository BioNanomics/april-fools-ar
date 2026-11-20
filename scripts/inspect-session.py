#!/usr/bin/env python3
"""Inspect a real April Fools AR directory or ZIP without optional dependencies."""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import struct
import sys
import zipfile


def inspect(path: Path) -> dict:
    archive = zipfile.ZipFile(path) if path.is_file() else None
    prefix = ""
    if archive and "manifest.json" not in archive.namelist():
        manifests = [n for n in archive.namelist() if n.endswith("/manifest.json")]
        if len(manifests) != 1:
            raise ValueError("Expected one session manifest in ZIP")
        prefix = manifests[0][:-len("manifest.json")]

    def read(name: str, limit=None) -> bytes:
        parts = PurePosixPath(name)
        if parts.is_absolute() or ".." in parts.parts:
            raise ValueError(f"Unsafe manifest path: {name}")
        if archive:
            with archive.open(prefix + name) as handle:
                return handle.read() if limit is None else handle.read(limit)
        location = (path / name).resolve()
        location.relative_to(path.resolve())
        with location.open('rb') as handle:
            return handle.read() if limit is None else handle.read(limit)

    try:
        manifest = json.loads(read("manifest.json"))
        frames = [json.loads(line) for line in read("frames.jsonl").splitlines() if line]
        events = [json.loads(line) for line in read("events.jsonl").splitlines() if line]
        errors = []
        if not manifest.get("finalized"):
            errors.append("Session was not finalized")
        if not frames:
            errors.append("No camera metadata frames")
        ids = [f.get("frameId") for f in frames]
        if len(set(ids)) != len(ids):
            errors.append("Duplicate frame IDs")
        video_bytes = archive.getinfo(prefix + 'rgb.mp4').file_size if archive else (path / 'rgb.mp4').stat().st_size
        video_header = read("rgb.mp4", 32)
        if video_bytes < 32 or video_header[4:8] != b"ftyp":
            errors.append("RGB video is missing a valid MP4 header")
        samples = []
        for frame in frames:
            if "rgbImagePath" in frame:
                rgb = read(frame["rgbImagePath"], 2)
                if not rgb.startswith(b"\xff\xd8"):
                    errors.append(f"Invalid JPEG: {frame['rgbImagePath']}")
            if "depthPath" not in frame:
                continue
            width, height = int(frame["depthWidth"]), int(frame["depthHeight"])
            raw = read(frame["depthPath"])
            if len(raw) != width * height * 4:
                errors.append(f"Incorrect depth byte count: {frame['depthPath']}")
                continue
            values = [v[0] for v in struct.iter_unpack("<f", raw)]
            valid = [v for v in values if math.isfinite(v) and v > 0]
            confidence = None
            if "confidencePath" in frame:
                confidence = read(frame["confidencePath"])
                if len(confidence) != width * height:
                    errors.append(f"Incorrect confidence byte count: {frame['confidencePath']}")
                if any(v > 2 for v in confidence):
                    errors.append("Unknown confidence category")
            if len(samples) < 3:
                samples.append({"frameId": frame.get("frameId"), "size": [width, height],
                                "validFraction": round(len(valid) / len(values), 4),
                                "minMeters": min(valid) if valid else None,
                                "maxMeters": max(valid) if valid else None,
                                "confidencePresent": confidence is not None})
        depth_count = sum("depthPath" in f for f in frames)
        if not depth_count:
            errors.append("No saved numeric depth frames")
        verified = 0
        for entry in manifest.get('fileInventory', []):
            name = entry['path']
            parts = PurePosixPath(name)
            if parts.is_absolute() or '..' in parts.parts:
                raise ValueError(f'Unsafe inventory path: {name}')
            stream = archive.open(prefix + name) if archive else (path / name).open('rb')
            hasher, length = hashlib.sha256(), 0
            with stream:
                while chunk := stream.read(1024 * 1024):
                    hasher.update(chunk)
                    length += len(chunk)
            if length != entry['bytes'] or hasher.hexdigest() != entry['sha256']:
                errors.append(f'File inventory checksum/length mismatch: {name}')
            else:
                verified += 1
        if not manifest.get('fileInventory'):
            errors.append('No payload checksum inventory')
        return {"sessionId": manifest.get("sessionId", manifest.get("id")),
                "name": manifest.get("name"), "finalized": manifest.get("finalized"),
                "metadataFrames": len(frames), "depthFrames": depth_count,
                "events": len(events), "eventTypes": sorted(set(e.get("type", "unknown") for e in events)),
                "videoBytes": video_bytes, "depthSamples": samples,
                "verifiedPayloadFiles": verified,
                "manifestErrors": manifest.get("errors", []), "validationErrors": errors,
                "manifestSHA256": hashlib.sha256(read("manifest.json")).hexdigest()}
    finally:
        if archive:
            archive.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    args = parser.parse_args()
    try:
        result = inspect(args.session)
        print(json.dumps(result, indent=2))
        sys.exit(1 if result["validationErrors"] else 0)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(json.dumps({"validationErrors": [str(error)]}, indent=2))
        sys.exit(1)
