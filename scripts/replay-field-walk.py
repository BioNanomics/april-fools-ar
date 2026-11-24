#!/usr/bin/env python3
"""Rebuild a field walk from original observations; never read the saved summary.

Inventory uses the shipped C ABI reducer. Observed positions use the recording's
registration controls, not a newly solved or independently surveyed field map.
YAML is the default report format; JSON remains available.
"""
import argparse
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 16 * 1024 * 1024
class ReplayError(Exception):
    pass
class Mat4(C.Structure):
    _fields_ = [('values', C.c_double * 16)]
class StringView(C.Structure):
    _fields_ = [('data', C.c_char_p), ('size', C.c_size_t)]
class WalkRow(C.Structure):
    _fields_ = [('family', C.c_char_p), ('tag_id', C.c_int32),
                ('observation_count', C.c_uint64), ('accepted_count', C.c_uint64),
                ('rejected_count', C.c_uint64), ('first_seen_s', C.c_double),
                ('last_seen_s', C.c_double)]
def finite(value):
    try:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    except OverflowError:
        return False
def number(value, fallback=None):
    return float(value) if finite(value) else fallback
def vector(value, count):
    return value if isinstance(value, list) and len(value) == count and all(finite(v) for v in value) else None
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReplayError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result
def parse_json(text):
    def invalid(token):
        raise ReplayError(f'Nonfinite JSON value: {token}')
    return json.loads(text, object_pairs_hook=unique_object, parse_constant=invalid)
def read_file(path):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or not 0 <= before.st_size <= LIMIT:
            raise ReplayError(f'Not bounded regular metadata: {path.name}')
        chunks = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                raise ReplayError(f'Metadata changed while reading: {path.name}')
            chunks.append(chunk); remaining -= len(chunk)
        after = os.fstat(descriptor)
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ReplayError(f'Metadata changed while reading: {path.name}')
        return b''.join(chunks)
    finally:
        os.close(descriptor)
def ruby_document(data, output=False):
    code = ('print FieldDefinitions.yaml(JSON.parse(STDIN.read))' if output else
            'print JSON.generate(FieldDefinitions.load_text(STDIN.read))')
    result = subprocess.run(['ruby', '-r', str(ROOT / 'scripts/field-definitions/field_tool.rb'), '-e', code],
                            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ReplayError(result.stderr.decode('utf-8', errors='replace')[-4000:])
    return result.stdout.decode('utf-8')
def load_core(path):
    lib = C.CDLL(str(Path(path).resolve()))
    lib.afsc_abi_version.restype = C.c_uint32
    lib.afsc_version.restype = C.c_char_p
    if lib.afsc_abi_version() != 1:
        raise ReplayError('Unsupported spatial-core ABI')
    lib.afsc_field_walk_create.argtypes = [C.c_size_t, C.c_size_t]; lib.afsc_field_walk_create.restype = C.c_void_p
    lib.afsc_field_walk_destroy.argtypes = [C.c_void_p]
    lib.afsc_field_walk_observe.argtypes = [C.c_void_p, StringView, C.c_int32, StringView, StringView, C.c_double, C.c_uint32]
    lib.afsc_field_walk_observe.restype = C.c_int
    lib.afsc_field_walk_count.argtypes = [C.c_void_p]; lib.afsc_field_walk_count.restype = C.c_size_t
    lib.afsc_field_walk_row.argtypes = [C.c_void_p, C.c_size_t, C.POINTER(WalkRow)]; lib.afsc_field_walk_row.restype = C.c_uint32
    for name in ['afsc_field_inverse', 'afsc_field_compose', 'afsc_field_observed_tag']:
        function = getattr(lib, name)
        function.argtypes = ([Mat4] if name.endswith('inverse') else [Mat4, Mat4]) + [C.POINTER(Mat4)]
        function.restype = C.c_uint32
    return lib
def matrix(lib, values):
    if vector(values, 16) is None:
        return None
    result, inverse = Mat4((C.c_double * 16)(*values)), Mat4()
    return result if lib.afsc_field_inverse(result, C.byref(inverse)) else None
def pose_matrix(lib, pose):
    translation, rotation = vector(pose.get('translation'), 3), vector(pose.get('rotationRowMajor'), 9)
    if translation is None or rotation is None:
        return None
    return matrix(lib, [rotation[0], rotation[3], rotation[6], 0,
                        rotation[1], rotation[4], rotation[7], 0,
                        rotation[2], rotation[5], rotation[8], 0, *translation, 1])
def source_string(value):
    return isinstance(value, str) and bool(value) and '\0' not in value and len(value.encode('utf-8')) <= 256
def object_value(value, name):
    if not isinstance(value, dict):
        raise ReplayError(f'{name} must be an object')
    return value

def replay_folder(folder, core_path):
    folder = Path(folder)
    if folder.is_symlink() or not folder.is_dir():
        raise ReplayError('Expected a regular capture directory')
    manifest = parse_json(read_file(folder / 'manifest.json').decode('utf-8'))
    object_value(manifest, 'Manifest')
    if manifest.get('finalized') is not True or manifest.get('schemaVersion') != 1:
        raise ReplayError('A finalized schema-1 capture is required')
    descriptor = manifest.get('fieldDefinition')
    if not isinstance(descriptor, dict):
        raise ReplayError('Capture has no pinned field definition; no field identity is inferred')
    inventory = manifest.get('fileInventory')
    if not isinstance(inventory, list) or len(inventory) > 100000:
        raise ReplayError('Missing or excessive source inventory')
    if any(not isinstance(entry, dict) for entry in inventory):
        raise ReplayError('Invalid source inventory entry')
    def verified(name):
        data = read_file(folder / name)
        entries = [entry for entry in inventory if entry.get('path') == name]
        if len(entries) != 1 or entries[0].get('bytes') != len(data) or entries[0].get('sha256') != hashlib.sha256(data).hexdigest():
            raise ReplayError(f'Source integrity mismatch: {name}')
        return data
    yaml = verified('field-definition.yaml')
    package_hash = hashlib.sha256(yaml).hexdigest()
    if descriptor.get('packageSha256') != package_hash:
        raise ReplayError('Pinned YAML hash differs from the capture field definition')
    definition = parse_json(ruby_document(yaml))
    object_value(definition, 'Pinned definition')
    package_id = definition.get('id')
    if descriptor.get('id') != package_id or definition.get('schemaVersion') != 1:
        raise ReplayError('Pinned package identity/schema mismatch')
    tags = {}
    if not isinstance(definition.get('tags'), list):
        raise ReplayError('Pinned definition tags must be an array')
    for tag in definition['tags']:
        object_value(tag, 'Pinned tag')
        identity = (tag.get('family'), tag.get('id'))
        if identity in tags:
            raise ReplayError('Duplicate physical tag identity in field definition')
        tags[identity] = tag
    data = verified('events.jsonl')
    events = [parse_json(line) for line in data.decode('utf-8').splitlines() if line.strip()]
    if len(events) > 100000 or any(not isinstance(row, dict) for row in events):
        raise ReplayError('Too many or invalid source events')
    # Frames are not an observation filter: videoAppended:false and writer-omitted
    # frames can still have valid source observations in events.jsonl.
    verified('frames.jsonl')
    lib = load_core(core_path)
    walk = lib.afsc_field_walk_create(512, 100000)
    if not walk:
        raise ReplayError('Cannot allocate the bounded walk reducer')
    entries, registration_events = {}, []
    registration, active_segment, active_field = None, None, {}
    missing_timing = 0
    def invalidate_registration(reason):
        nonlocal registration, active_field
        registration = None
        active_field = dict(active_field, alignment='unaligned', anchorId=None,
                            segmentId=None, worldFromFieldColumnMajor=None,
                            reason='Replay invalidated alignment: '+reason)
    try:
        for event in events:  # Preserve completion order, not movie-frame proximity.
            kind, segment = event.get('type'), event.get('segmentId')
            if kind == 'segment':
                if segment != active_segment:
                    invalidate_registration('coordinate segment changed')
                active_segment = segment
            elif kind in ['measurementsInvalidated', 'fieldRegistrationInvalidated']:
                invalidate_registration('recorded state was invalidated')
            elif kind == 'trackingChanged' and event.get('tracking') != 'normal':
                invalidate_registration('tracking is unavailable')
            elif kind in ['settingsChanged', 'floorConfirmed', 'floorReferenceChanged']:
                invalidate_registration('settings or confirmed floor changed')
            if kind in ['fieldWalkStarted', 'fieldRegistrationChanged', 'fieldRegistrationInvalidated', 'fieldAnchorWarning']:
                if event.get('packageId') != package_id or event.get('packageSha256') != package_hash:
                    raise ReplayError('Recorded field control changes the pinned package identity')
                field = event.get('field', {})
                if not isinstance(field, dict):
                    raise ReplayError('Invalid recorded registration control')
                registration_events.append(event)
                if kind == 'fieldAnchorWarning':
                    # Warning snapshots are evidence, never alignment controls.
                    active_field = dict(active_field)
                    for key in ['reason', 'checks', 'warnings']:
                        if key in field:
                            active_field[key] = field[key]
                else:
                    active_field = field
                    candidate = matrix(lib, field.get('worldFromFieldColumnMajor'))
                    registration = (candidate, field.get('segmentId'), field.get('anchorId')) if (
                        candidate is not None and field.get('alignment') in ['provisional', 'checked', 'degraded', 'unverified']) else None
            if kind != 'aprilTagDetections' or event.get('analysisSucceeded') is not True:
                continue
            timestamp, frame = number(event.get('timestamp')), event.get('frameId')
            if timestamp is None or timestamp < 0 or not source_string(segment) or not source_string(frame):
                raise ReplayError('Observation lacks valid source clock/frame/segment identity')
            settings = object_value(event.get('debugSettings', {}), 'Source settings')
            age = number(event.get('fieldProcessingAgeSeconds'))
            allowed = event.get('fieldRegistrationAllowed') is True
            if allowed and registration is not None and (
                    event.get('tracking') != 'normal' or registration[1] != segment):
                invalidate_registration('source tracking or coordinate segment changed')
            if age is None:
                missing_timing += 1
            camera = matrix(lib, event.get('cameraToWorldColumnMajor'))
            if camera is None:
                # Native FieldWalkState returns before inventory on an invalid
                # camera transform. Never manufacture geometry/counts here.
                continue
            rows = event.get('detections', [])
            if not isinstance(rows, list) or len(rows) > 1024:
                raise ReplayError('Invalid or excessive detections')
            for detection in rows:
                if not isinstance(detection, dict):
                    raise ReplayError('Invalid detection record')
                identifier = number(detection.get('id'))
                if identifier is None or identifier != int(identifier) or not 0 <= identifier <= 65535:
                    continue
                identifier = int(identifier)
                family = detection.get('family', 'tag36h11')
                if not source_string(family) or len(family.encode('utf-8')) > 31:
                    raise ReplayError('Invalid family identity')
                tag = tags.get((family, identifier))
                pose = object_value(detection.get('pose') or {}, 'Source pose')
                optical = pose_matrix(lib, pose)
                debug = object_value(detection.get('debug') or {}, 'Source diagnostics')
                height = object_value(detection.get('floorHeight') or {}, 'Source height')
                orientation = object_value(detection.get('gravityOrientation') or {}, 'Source orientation')
                usable = (allowed and event.get('tracking') == 'normal' and age is not None and 0 <= age <= .4
                    and optical is not None and camera is not None and pose.get('ambiguous') is False
                    and debug.get('status') in ['valid', 'missingDepth']
                    and number(pose.get('rangeMeters'), math.inf) <= number(settings.get('maxDistanceMeters'), 5)
                    and number(pose.get('reprojectionRMSEPixels'), math.inf) <= number(settings.get('maxReprojectionErrorPixels'), 3)
                    and number(pose.get('planeAngleDegrees'), math.inf) <= number(settings.get('maxPlaneAngleDegrees'), 60)
                    and number(detection.get('decisionMargin'), 0) > 0 and number(detection.get('hamming')) == 0)
                applied = number(pose.get('tagSizeMeters'))
                reference_size = number(tag.get('poseSizeMeters')) if tag else None
                size_conflict = reference_size is not None and abs((applied if applied is not None else reference_size)-reference_size) > max(.00001, reference_size*.03)
                f, s, r = family.encode(), segment.encode(), frame.encode()
                result = lib.afsc_field_walk_observe(walk, StringView(f,len(f)), identifier, StringView(s,len(s)), StringView(r,len(r)), timestamp, int(usable and not size_conflict))
                if result == 3:
                    raise ReplayError('Source exceeds bounded walk inventory capacity')
                if result == 0:
                    raise ReplayError('Invalid source observation identity')
                if result != 1:
                    continue
                nominal = vector(tag.get('fieldFromTagColumnMajor'),16) if tag else None
                row = {'id':identifier,'family':family,'name':tag.get('name') if tag else 'Unknown field tag',
                    'frameId':frame,'segmentId':segment,'timestamp':timestamp,
                    'nominalPosition':nominal[12:15] if nominal else None,'observedPosition':None,
                    'expectedHeightMeters':tag.get('expectedHeightMeters') if tag else None,
                    'expectedTiltDegrees':number(tag.get('expectedTiltRadians'))*180/math.pi if tag and finite(tag.get('expectedTiltRadians')) else None,
                    'observedHeightMeters':height.get('meters') if height.get('available') is True else None,
                    'observedTiltDegrees':orientation.get('tiltFromVerticalDegrees'),
                    'tagSizeResolution':detection.get('tagSizeResolution'),'poseSizeMeters':applied,
                    'reason':('ID is unknown to this field definition.' if not tag else 'Applied print size differs from reference; placement is unresolved.' if size_conflict else 'Moving/unknown target has no fixed nominal position.' if nominal is None else 'Observed; placement is an estimate.')}
                if usable and registration is not None and registration[1] == segment:
                    world_tag, inverse, field_tag = Mat4(), Mat4(), Mat4()
                    if lib.afsc_field_observed_tag(camera,optical,C.byref(world_tag)) and lib.afsc_field_inverse(registration[0],C.byref(inverse)) and lib.afsc_field_compose(inverse,world_tag,C.byref(field_tag)):
                        row['observedPosition'] = list(field_tag.values)[12:15]
                        row['registrationAnchorId'] = registration[2]
                        row['registrationAssumption'] = 'single-tag anchor; not independent survey truth'
                        row['comparisonStatus'] = 'assumed-anchor' if registration[2] == identifier else 'independent-of-initial-anchor-only'
                entries[(family,identifier)] = row
        for index in range(lib.afsc_field_walk_count(walk)):
            source = WalkRow()
            if not lib.afsc_field_walk_row(walk,index,C.byref(source)):
                raise ReplayError('Core could not return its walk inventory')
            row = entries[(source.family.decode(),source.tag_id)]
            row.update(count=source.observation_count,acceptedCount=source.accepted_count,rejectedCount=source.rejected_count,
                       firstSeen=source.first_seen_s,lastSeen=source.last_seen_s)
        rows = sorted(entries.values(),key=lambda row:(row['id'],row['family']))
        field = dict(active_field)
        field.update(packageId=package_id,packageSha256=package_hash,seenTags=rows,seenCount=len(rows),expectedCount=len(tags))
        return {'schemaVersion':1,'field':field,'coordinateFrame':definition.get('coordinateFrame'),
                'registrationEvents':registration_events,'accuracyValidated':False,
                'replay':{'sourceCaptureId':manifest.get('id'),'sourceEventOrder':'original completion order',
                    'inventory':'regenerated from original aprilTagDetections with the shared C reducer',
                    'positions':'source poses projected through recorded registration controls; alignment was not re-solved',
                    'savedSummaryUsed':False,'missingProcessingAgeEvents':missing_timing,
                    'calculationCore':lib.afsc_version().decode(),'abiVersion':lib.afsc_abi_version()}}
    finally:
        lib.afsc_field_walk_destroy(walk)

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path,help='Finalized session directory or original MP4')
    parser.add_argument('--core-library',required=True,type=Path,help='Built AFSpatialCore shared library')
    parser.add_argument('--output',required=True,type=Path,help='New report path outside the source capture')
    parser.add_argument('--format',choices=['yaml','json'],default='yaml')
    parser.add_argument('--node',default='node',help='Node22+ for existing MP4 extraction CLI')
    args = parser.parse_args(argv)
    source, destination = args.capture.absolute(), args.output.absolute()
    if destination.exists() or destination.is_symlink() or not destination.parent.is_dir():
        raise ReplayError('Output must be a new file in an existing directory')
    resolved_source, resolved_destination = source.resolve(), destination.resolve()
    if source.is_dir() and (resolved_destination == resolved_source or resolved_source in resolved_destination.parents):
        raise ReplayError('Output must be outside the source capture')
    with tempfile.TemporaryDirectory(prefix='afar-field-replay-') as temporary:
        if source.suffix.lower() == '.mp4':
            folder = Path(temporary)/'extracted'
            result = subprocess.run([args.node,str(ROOT/'recording-format/npm/src/cli.mjs'),'unpack',str(source),str(folder)],
                                    stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
            if result.returncode:
                raise ReplayError('Original MP4 extraction failed: '+result.stderr.decode(errors='replace')[-4000:])
        else:
            folder = source
        report = replay_folder(folder,args.core_library)
        text = json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n'
        if args.format == 'yaml':
            text = ruby_document(text.encode(),output=True)
        with destination.open('x',encoding='utf-8') as stream:
            stream.write(text)
    print(f'Regenerated {report["field"]["seenCount"]} seen tags: {destination}')
    return 0
if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ReplayError,OSError,ValueError,KeyError,TypeError) as error:
        print('Field replay: '+str(error),file=sys.stderr)
        sys.exit(1)
