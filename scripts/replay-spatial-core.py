#!/usr/bin/env python3
"""Recompute recorded tag diagnostics from a session directory, legacy ZIP or MP4.

MP4 import delegates to recording-format/npm, preserving the existing container
contract and checksums. Never modifies source recordings. Output is new JSONL,
not an MP4 rewrite; original event order/timestamps remain authoritative.
"""
import argparse
from contextlib import contextmanager
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAX_RECORD_BYTES = 16 * 1024**2
MAX_MANIFEST_BYTES = 16 * 1024**2
MAX_RECORDS = 100000

class Vec2(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double)]
class Vec3(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double), ('z', C.c_double)]
class Matrix(C.Structure):
    _fields_ = [('values', C.c_double * 16)]
class Intrinsics(C.Structure):
    _fields_ = [('values', C.c_double * 9)]
class Plane(C.Structure):
    _fields_ = [('origin', Vec3), ('normal', Vec3)]
class Optional(C.Structure):
    _fields_ = [('available', C.c_uint32), ('value', C.c_double)]
class Pose(C.Structure):
    _fields_ = [('translation_available', C.c_uint32), ('translation', Vec3), ('orientation_available', C.c_uint32),
                ('range_m', Optional), ('plane_angle_rad', Optional), ('bearing_rad', Optional),
                ('reprojection_rms_px', Optional), ('decision_margin', Optional), ('corrected_bits', Optional), ('ambiguous', C.c_int32)]
class Depth(C.Structure):
    _fields_ = [('center_z_m', Optional), ('confidence', Optional)]
class Settings(C.Structure):
    _fields_ = [(key, C.c_double) for key in ['max_range_m', 'max_plane_angle_rad', 'max_reprojection_rms_px',
                                            'warning_depth_difference_m', 'reject_depth_difference_m']]
class Ranges(C.Structure):
    _fields_ = [(key, Optional) for key in ['depth_range_m', 'pose_range_m', 'range_difference_m', 'depth_z_m', 'pose_z_m']] + [('depth_reason', C.c_int), ('pose_reason', C.c_int)]
class Quality(C.Structure):
    _fields_ = [('reason', C.c_int), ('severity', C.c_int), ('accepted_depth_z_m', Optional), ('depth_difference_m', Optional)]
class HeightInput(C.Structure):
    _fields_ = [(key, C.c_uint32) for key in ['floor_available', 'same_segment', 'tracking_usable', 'frame_id_available',
                                            'floor_id_available', 'floor_frame_id_available', 'floor_classification_usable']] + [
        ('timestamp_s', C.c_double), ('frame_age_s', C.c_double), ('floor_timestamp_s', C.c_double), ('floor', Plane),
        ('world_from_optical', Matrix), ('intrinsics', Intrinsics), ('center_available', C.c_uint32), ('center_px', Vec2),
        ('pose', Pose), ('depth', Depth), ('settings', Settings)]
class Height(C.Structure):
    _fields_ = [('available', C.c_uint32), ('reason', C.c_int), ('source', C.c_int), ('severity', C.c_int),
        ('height_m', C.c_double), ('optical_m', Vec3), ('world_m', Vec3), ('floor_foot_world_m', Vec3),
        ('accepted_depth_z_m', Optional), ('depth_difference_m', Optional)]

RANGE_REASONS = ['valid', 'missingDepth', 'poseUnavailable', 'invalidConfidence', 'invalidIntrinsics', 'invalidCenter', 'invalidRange']
QUALITY_REASONS = ['valid', 'trackingLimited', 'poseUnavailable', 'ambiguous', 'tooFar', 'badAngle', 'lowConfidence',
                   'lowConfidence', 'missingDepth', 'depthMismatch', 'depthMismatch']
HEIGHT_REASONS = ['valid', 'floorNotSelected', 'segmentMismatch', 'trackingLimited', 'staleFrame', 'invalidFloor',
                  'invalidPose', 'ambiguousPose', 'tooFar', 'badAngle', 'lowConfidencePose', 'depthMismatch',
                  'invalidCenter', 'invalidGeometry', 'invalidFloorIntersection']
SEVERITIES = ['good', 'neutral', 'warning', 'bad']


def number(v):
    if not isinstance(v, (float, int)) or isinstance(v, bool): return None
    try:
        n = float(v)
    except (OverflowError, ValueError):
        return None
    return n if math.isfinite(n) else None


def object_or_empty(value, label):
    if value is None: return {}
    if not isinstance(value, dict): raise ValueError(f'{label} must be an object')
    return value


def frame_identity(record):
    identity = (record.get('segmentId'), record.get('frameId'))
    if any(not isinstance(value, str) or not value for value in identity):
        raise ValueError('Source frame and segment identities must be nonempty strings')
    return identity


def finite_setting(settings, name, default):
    value = number(settings.get(name, default))
    if value is None: raise ValueError(f'Debug setting {name} must be a finite number')
    return value


def parse_json(payload):
    return json.loads(payload, parse_constant=lambda v: (_ for _ in ()).throw(ValueError(f'Nonfinite JSON: {v}')))


def read_manifest(path):
    with path.open('rb') as handle:
        payload = handle.read(MAX_MANIFEST_BYTES + 1)
    if len(payload) > MAX_MANIFEST_BYTES: raise ValueError('Session manifest size limit exceeded')
    manifest = parse_json(payload)
    if not isinstance(manifest, dict): raise ValueError('Session manifest must be an object')
    return manifest

def optional(v, degrees=False):
    n = number(v)
    return Optional(n is not None, (math.radians(n) if degrees else n) if n is not None else 0)

def value(v):
    return v.value if v.available else None

def vector(v, size):
    return v if isinstance(v, list) and len(v) == size and all(number(x) is not None for x in v) else None

def vec3(v):
    return Vec3(*(vector(v, 3) or [math.nan] * 3))

def xyz(v):
    return [v.x, v.y, v.z]

def sha256(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()

def safe_path(root, name):
    if not isinstance(name, str) or not name: raise ValueError('Session path must be a nonempty string')
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts or '\\' in name:
        raise ValueError(f'Unsafe session path: {name}')
    target = (root / name).resolve()
    target.relative_to(root.resolve())
    return target

@contextmanager
def session_directory(source, tools_root=ROOT):
    source = source.resolve()
    if source.is_dir():
        yield source
        return
    with tempfile.TemporaryDirectory(prefix='afsc-replay-') as temporary:
        restored = Path(temporary) / 'session'
        if source.suffix.lower() == '.mp4':
            cli = tools_root / 'recording-format/npm/src/cli.mjs'
            if not cli.is_file() or not shutil.which('node'):
                raise ValueError('MP4 import requires Node 22+ and recording-format/npm (run npm ci there)')
            result = subprocess.run(['node', str(cli), 'unpack', str(source), str(restored)], capture_output=True, text=True)
            if result.returncode:
                raise ValueError('MP4 integrity/extraction failed: ' + result.stderr.strip())
        elif source.suffix.lower() == '.zip':
            restored.mkdir()
            with zipfile.ZipFile(source) as archive:
                if len(archive.infolist()) > 65534 or sum(i.file_size for i in archive.infolist()) >= 4 * 1024**3:
                    raise ValueError('Legacy ZIP exceeds entry/size limit')
                names = set()
                for info in archive.infolist():
                    target = safe_path(restored, info.filename)
                    if info.filename in names or (info.external_attr >> 16) & 0o170000 == 0o120000:
                        raise ValueError('Duplicate or symbolic-link ZIP entry')
                    names.add(info.filename)
                    if info.is_dir(): target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.open(info) as src, target.open('xb') as dst: shutil.copyfileobj(src, dst)
            manifests = list(restored.rglob('manifest.json'))
            if len(manifests) != 1: raise ValueError('Expected one session manifest')
            restored = manifests[0].parent
        else:
            raise ValueError('Expected a session directory, .zip or .mp4 recording')
        yield restored


def records(path):
    # Read a bounded byte line before decoding; iteration over a text file can
    # allocate an arbitrarily large line before a post-read length check.
    with path.open('rb') as handle:
        for index in range(MAX_RECORDS + 1):
            line = handle.readline(MAX_RECORD_BYTES + 1)
            if not line: return
            if index >= MAX_RECORDS or len(line) > MAX_RECORD_BYTES:
                raise ValueError('Metadata record limit exceeded')
            if line.strip():
                record = parse_json(line)
                if not isinstance(record, dict): raise ValueError('Metadata records must be objects')
                yield record

class Core:
    def __init__(self, path):
        self.library = C.CDLL(str(path.resolve()))
        lib = self.library
        lib.afsc_abi_version.restype = C.c_uint32
        if lib.afsc_abi_version() != 1: raise ValueError('Unsupported spatial core ABI; replay reader requires ABI 1')
        lib.afsc_version.restype = C.c_char_p
        lib.afsc_camera_ranges.argtypes = [C.POINTER(Pose), C.POINTER(Depth), C.POINTER(Intrinsics), C.c_uint32, Vec2]
        lib.afsc_camera_ranges.restype = Ranges
        lib.afsc_pose_quality.argtypes = [C.POINTER(Pose), C.POINTER(Depth), C.POINTER(Settings), C.c_uint32]
        lib.afsc_pose_quality.restype = Quality
        lib.afsc_floor_height.argtypes = [C.POINTER(HeightInput)]
        lib.afsc_floor_height.restype = Height

    def evaluate(self, detection, event):
        if not isinstance(detection, dict): raise ValueError('Tag detections must be objects')
        p = object_or_empty(detection.get('pose'), 'Tag pose')
        d = object_or_empty(detection.get('depth'), 'Tag depth')
        translation = vector(p.get('translation'), 3)
        pose = Pose(bool(translation), vec3(translation), bool(vector(p.get('eulerDegrees'), 3)),
                    optional(p.get('rangeMeters')), optional(p.get('planeAngleDegrees'), True),
                    optional(p.get('opticalAxisAngleDegrees'), True), optional(p.get('reprojectionRMSEPixels')),
                    optional(detection.get('decisionMargin')), optional(detection.get('hamming')),
                    1 if p.get('ambiguous') is True else 0 if p.get('ambiguous') is False else -1)
        depth = Depth(optional(d.get('centerDepthMeters')), optional(d.get('centerConfidence')))
        k = Intrinsics((C.c_double * 9)(*(vector(event.get('intrinsicsColumnMajor'), 9) or [math.nan] * 9)))
        center = vector(detection.get('center'), 2)
        center_point = Vec2(*(center or [math.nan] * 2))
        s = object_or_empty(event.get('debugSettings'), 'Debug settings')
        settings = Settings(finite_setting(s, 'maxDistanceMeters', 5),
                            math.radians(finite_setting(s, 'maxPlaneAngleDegrees', 60)),
                            finite_setting(s, 'maxReprojectionErrorPixels', 3),
                            finite_setting(s, 'warningDepthDifferenceMeters', .10),
                            finite_setting(s, 'rejectDepthDifferenceMeters', .15))
        lib = self.library
        ranges = lib.afsc_camera_ranges(C.byref(pose), C.byref(depth), C.byref(k), bool(center), center_point)
        quality = lib.afsc_pose_quality(C.byref(pose), C.byref(depth), C.byref(settings), event.get('tracking') == 'normal')
        result = {'cameraRanges': {'lidarRangeMeters': value(ranges.depth_range_m), 'tagRangeMeters': value(ranges.pose_range_m),
                  'distanceDeltaMeters': value(ranges.range_difference_m), 'lidarDepthZMeters': value(ranges.depth_z_m),
                  'tagDepthZMeters': value(ranges.pose_z_m), 'lidarReason': RANGE_REASONS[ranges.depth_reason], 'tagReason': RANGE_REASONS[ranges.pose_reason]},
                  'quality': {'status': QUALITY_REASONS[quality.reason], 'severity': SEVERITIES[quality.severity],
                              'depthDifferenceMeters': value(quality.depth_difference_m)}}
        recorded_height = object_or_empty(detection.get('floorHeight'), 'Recorded floor height')
        # Explicit null means no selected floor in this exact frame. Legacy
        # captures may recover the basis only when the snapshot key is absent.
        floor = event['floorSnapshot'] if 'floorSnapshot' in event else recorded_height.get('floor')
        if floor is not None and not isinstance(floor, dict): raise ValueError('Floor snapshot must be an object')
        age = number(recorded_height.get('frameAgeSeconds'))
        if age is None:
            result['floorHeight'] = {'replayable': False, 'reason': 'sourceFrameAgeUnavailable'}
        else:
            h = HeightInput()
            h.floor_available = isinstance(floor, dict)
            floor = floor or {}
            h.same_segment = floor.get('segmentId') == event.get('segmentId')
            h.tracking_usable = event.get('tracking') == 'normal'
            h.frame_id_available = bool(event.get('frameId'))
            h.floor_id_available = bool(floor.get('id'))
            h.floor_frame_id_available = bool(floor.get('frameId'))
            h.floor_classification_usable = floor.get('classification') in ('floor', 'unclassified')
            h.timestamp_s = number(event.get('timestamp')) if number(event.get('timestamp')) is not None else math.nan
            h.frame_age_s = age
            h.floor_timestamp_s = number(floor.get('timestamp')) if number(floor.get('timestamp')) is not None else math.nan
            h.floor = Plane(vec3(floor.get('originWorldMeters')), vec3(floor.get('normalWorld')))
            transform = vector(event.get('cameraToWorldColumnMajor'), 16) or [math.nan] * 16
            h.world_from_optical = Matrix((C.c_double * 16)(*[v * (-1 if i // 4 in (1, 2) else 1) for i, v in enumerate(transform)]))
            h.intrinsics, h.center_available, h.center_px, h.pose, h.depth, h.settings = k, bool(center), center_point, pose, depth, settings
            height = lib.afsc_floor_height(C.byref(h))
            result['floorHeight'] = {'replayable': True, 'available': bool(height.available), 'reason': HEIGHT_REASONS[height.reason],
                                     'meters': height.height_m if height.available else None,
                                     'worldMeters': xyz(height.world_m) if height.available else None,
                                     'floorFootWorldMeters': xyz(height.floor_foot_world_m) if height.available else None}
        return result


def replay(source, library, output, tools_root=ROOT):
    if output.exists(): raise ValueError('Replay output already exists; source files are never overwritten')
    if source.is_dir() and output.resolve().is_relative_to(source.resolve()):
        raise ValueError('Replay output must be outside the source session directory')
    core = Core(library)
    temporary_output = None
    try:
        with session_directory(source, tools_root) as folder:
            manifest_path = safe_path(folder, 'manifest.json')
            manifest = read_manifest(manifest_path)
            if manifest.get('schemaVersion') != 1 or manifest.get('finalized') is not True:
                raise ValueError('Replay requires a finalized capture-schema-1 session')
            inventory = manifest.get('fileInventory', [])
            if not isinstance(inventory, list) or len(inventory) > 65534:
                raise ValueError('Session inventory must be a bounded array')
            inventoried = set()
            for item in inventory:
                if not isinstance(item, dict): raise ValueError('Session inventory entries must be objects')
                path = safe_path(folder, item.get('path'))
                size, digest = item.get('bytes'), item.get('sha256')
                if not isinstance(size, int) or isinstance(size, bool) or size < 0 or not isinstance(digest, str):
                    raise ValueError('Session inventory entry has invalid size or checksum')
                if path in inventoried: raise ValueError('Duplicate session inventory path')
                inventoried.add(path)
                if path.stat().st_size != size or sha256(path) != digest:
                    raise ValueError('Session inventory integrity mismatch: ' + item['path'])
            frames = {}
            for frame in records(safe_path(folder, 'frames.jsonl')):
                key = frame_identity(frame)
                if key in frames: raise ValueError('Duplicate source frame identity')
                frames[key] = frame
            output.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=output.parent, delete=False) as handle:
                temporary_output = Path(handle.name)
                def emit(record): handle.write(json.dumps(record, allow_nan=False, separators=(',', ':')) + '\n')
                emit({'type': 'spatialCoreReplay', 'schemaVersion': 1, 'sourceName': source.name,
                      'sourceManifestSHA256': sha256(manifest_path), 'sourceApplication': manifest.get('application'),
                      'sourceCalculationCore': manifest.get('calculationCore'), 'sourceClock': manifest.get('clock'),
                      'coreVersion': core.library.afsc_version().decode(), 'coreABIVersion': 1,
                      'timestampPolicy': 'Original source seconds/clock retained; MP4 packet timestamps are not sensor time'})
                count = 0
                for index, event in enumerate(records(safe_path(folder, 'events.jsonl'))):
                    if event.get('type') != 'aprilTagDetections': continue
                    frame = frames.get(frame_identity(event))
                    # Detection events carry the exact source camera model; never substitute a later frame.
                    detections = event.get('detections', [])
                    if not isinstance(detections, list): raise ValueError('Event detections must be an array')
                    for detection_index, detection in enumerate(detections):
                        result = core.evaluate(detection, event)
                        emit({'type': 'replayedTag', 'sourceEventIndex': index, 'sourceDetectionIndex': detection_index,
                              'frameId': event.get('frameId'), 'segmentId': event.get('segmentId'), 'timestamp': event.get('timestamp'),
                              'videoPTSSeconds': frame.get('videoPTSSeconds') if frame else None,
                              'videoAppended': frame.get('videoAppended') if frame else None,
                              'sourceFramePresent': frame is not None, 'recorded': detection, 'recomputed': result})
                        count += 1
                emit({'type': 'replayComplete', 'detections': count})
            os.link(temporary_output, output)  # atomic create, refuses to overwrite existing input/output
            return count
    finally:
        if temporary_output: temporary_output.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--core-library', type=Path, required=True, help='CMake-built libafsc shared library')
    parser.add_argument('--output', type=Path, required=True, help='New replay JSONL file')
    parser.add_argument('--recording-tools-root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        count = replay(args.source, args.core_library, args.output, args.recording_tools_root)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Replay failed: {error}\n')
    print(f'Replayed {count} tag observations into {args.output}')

if __name__ == '__main__': main()
