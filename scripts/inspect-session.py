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


def inspect(path: Path, require_tags: bool = False, require_debug: bool = False) -> dict:
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
        tag_events = [e for e in events if e.get('type') == 'aprilTagDetections']
        detected_ids = set()
        detection_count = 0
        failed_tag_analyses = 0
        pose_count = 0
        debug_statuses = {}
        def finite_number(value):
            return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        for event in tag_events:
            if event.get('analysisSucceeded') is False:
                failed_tag_analyses += 1
            if not event.get('frameId') or not event.get('segmentId'):
                errors.append('AprilTag analysis lacks source frame/segment identity')
            for field, size in [('intrinsicsColumnMajor', 9), ('cameraToWorldColumnMajor', 16), ('displayTransform', 6)]:
                values = event.get(field, [])
                if len(values) != size or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in values):
                    errors.append(f'Invalid AprilTag source geometry: {field}')
            if not isinstance(event.get('timestamp'), (int, float)):
                errors.append('AprilTag analysis lacks a source timestamp')
            for detection in event.get('detections', []):
                detection_count += 1
                tag_id = detection.get('id')
                if not isinstance(tag_id, int) or tag_id < 0:
                    errors.append('Invalid AprilTag ID')
                else:
                    detected_ids.add(tag_id)
                corners = detection.get('corners', [])
                if len(corners) != 4 or any(len(p) != 2 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in p) for p in corners):
                    errors.append('Invalid AprilTag corner coordinates')
                if not detection.get('family') or 'hamming' not in detection or 'decisionMargin' not in detection:
                    errors.append('AprilTag detection lacks family/quality fields')
                pose = detection.get('pose')
                if isinstance(pose, dict):
                    pose_count += 1
                    for field, size in [('translation', 3), ('rotationRowMajor', 9), ('eulerDegrees', 3)]:
                        values = pose.get(field, [])
                        if len(values) != size or not all(finite_number(v) for v in values):
                            errors.append(f'Invalid AprilTag optical pose: {field}')
                    translation = pose.get('translation', [])
                    if len(translation) == 3 and all(finite_number(v) for v in translation):
                        if translation[2] <= 0:
                            errors.append('AprilTag optical pose is behind the camera')
                        distance = pose.get('rangeMeters')
                        if not finite_number(distance) or abs(distance - math.hypot(*translation)) > 1e-6:
                            errors.append('AprilTag pose range is inconsistent with translation')
                    rms = pose.get('reprojectionRMSEPixels')
                    if not finite_number(rms) or rms < 0:
                        errors.append('Invalid AprilTag pixel reprojection RMS')
                debug = detection.get('debug')
                if isinstance(debug, dict):
                    state = debug.get('status', 'unknown')
                    debug_statuses[state] = debug_statuses.get(state, 0) + 1
                    center, z, delta = (debug.get(k) for k in ['centerDepthMeters', 'opticalPoseZMeters', 'depthDifferenceMeters'])
                    if all(finite_number(v) for v in [center, z, delta]) and abs(delta - abs(center - z)) > 1e-6:
                        errors.append('Debug depth mismatch compares inconsistent values')
                    if debug.get('valid'):
                        if state != 'valid' or debug.get('centerConfidence') not in [1, 2] or debug.get('tracking') != 'normal' or not all(finite_number(v) for v in [center, z, delta]):
                            errors.append('Debug valid flag has missing or rejected sensor evidence')
        if require_tags and not detection_count:
            errors.append('No AprilTag detections; this check requires a known visible tag')
        if require_debug and (not pose_count or not debug_statuses):
            errors.append('No solved AprilTag pose/debug records; this check requires a visible calibrated tag')
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
                "aprilTagAnalyzedFrames": len(tag_events), "aprilTagDetections": detection_count,
                "aprilTagIDs": sorted(detected_ids),
                "aprilTagFailedAnalyses": failed_tag_analyses,
                "aprilTagPoses": pose_count, "debugStatuses": debug_statuses,
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
    parser.add_argument("--require-tags", action="store_true", help="Require at least one decoded tag for the known-tag device check")
    parser.add_argument("--require-debug", action="store_true", help="Require solved poses and debug records for a calibrated-tag device check")
    args = parser.parse_args()
    try:
        result = inspect(args.session, require_tags=args.require_tags, require_debug=args.require_debug)
        print(json.dumps(result, indent=2))
        sys.exit(1 if result["validationErrors"] else 0)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(json.dumps({"validationErrors": [str(error)]}, indent=2))
        sys.exit(1)
