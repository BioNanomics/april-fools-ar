#!/usr/bin/env python3
"""Container-to-calculation tests; generated video tests transport, not accuracy."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('replay', ROOT / 'scripts/replay-spatial-core.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
LIBRARY = os.environ.get('AFSC_LIBRARY')
TOOLS = Path(os.environ.get('AFSC_RECORDING_TOOLS_ROOT', str(ROOT)))

@unittest.skipUnless(LIBRARY, 'Set AFSC_LIBRARY to the CMake-built shared library')
class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='afsc-replay-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'session'
        self.source.mkdir()
        self.frames = [dict(frameId='same-id', segmentId=f'segment-{i}', timestamp=float(i), videoPTSSeconds=i / 10,
                            videoAppended=i != 2) for i in (1, 2)]
        identity = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,2,0,1]
        self.events = []
        for i in (2, 1):  # Completion order intentionally differs from capture-time order.
            self.events.append(dict(type='aprilTagDetections', frameId='same-id', segmentId=f'segment-{i}', timestamp=float(i),
                tracking='normal', intrinsicsColumnMajor=[100,0,0,0,100,0,50,50,1], cameraToWorldColumnMajor=identity,
                debugSettings={}, floorSnapshot=dict(id='floor', frameId='floor-frame', segmentId=f'segment-{i}', timestamp=.1,
                    classification='floor', originWorldMeters=[0,0,0], normalWorld=[0,1,0], operatorConfirmed=True),
                detections=[dict(id=4, center=[50,50], decisionMargin=50, hamming=0,
                    pose=dict(translation=[0,0,1], eulerDegrees=[0,0,0], rangeMeters=1, planeAngleDegrees=0,
                        opticalAxisAngleDegrees=0, reprojectionRMSEPixels=0, ambiguous=False),
                    depth=dict(centerDepthMeters=1 if i == 1 else None, centerConfidence=2 if i == 1 else None),
                    floorHeight=dict(frameAgeSeconds=.05))]))
        self.write_metadata()

    def write_metadata(self):
        (self.source/'frames.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in self.frames))
        (self.source/'events.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in self.events))
        # Exact binary bit patterns (NaN and negative zero) must survive MP4 extraction.
        (self.source/'depth.f32').write_bytes(bytes.fromhex('4523c17f000000800000803f'))
        inventory = [dict(path=p.name, bytes=p.stat().st_size, sha256=replay.sha256(p))
                     for p in self.source.iterdir() if p.name != 'manifest.json']
        manifest = dict(schemaVersion=1, finalized=True, sessionId='replay-fixture',
                        application=dict(version='fixture', build='1', buildCommit='a'*40, buildDateUTC='2026-11-22T00:00:00Z'),
                        clock='ARFrame.timestamp seconds since boot', fileInventory=inventory,
                        calculationCore=dict(version='0.1.0', abiVersion=1))
        (self.source/'manifest.json').write_text(json.dumps(manifest))

    def run_replay(self, source=None, name='output.jsonl'):
        output = self.root/name
        count = replay.replay(source or self.source, Path(LIBRARY), output, TOOLS)
        self.assertEqual(count, 2)
        return [json.loads(x) for x in output.read_text().splitlines()]

    def test_optional_depth_height_order_and_provenance(self):
        rows = self.run_replay()
        self.assertEqual(rows[0]['sourceApplication']['buildCommit'], 'a'*40)
        self.assertEqual([x['timestamp'] for x in rows[1:-1]], [2,1])
        self.assertFalse(rows[1]['videoAppended'])
        self.assertEqual(rows[1]['videoPTSSeconds'], .2)
        self.assertEqual(rows[1]['recorded'], self.events[0]['detections'][0])
        for row in rows[1:-1]:
            self.assertTrue(row['sourceFramePresent'])
            height = row['recomputed']['floorHeight']
            self.assertTrue(height['available'])
            self.assertAlmostEqual(height['meters'], 2)
            self.assertEqual(height['floorFootWorldMeters'], [0,0,-1])
            self.assertEqual(row['recomputed']['cameraRanges']['tagRangeMeters'], 1)
        self.assertIsNone(rows[1]['recomputed']['cameraRanges']['lidarRangeMeters'])
        self.assertEqual(rows[2]['recomputed']['cameraRanges']['lidarRangeMeters'], 1)
        self.assertEqual(self.run_replay(name='again.jsonl'), rows)

    def test_legacy_zip_matches_directory(self):
        archive = self.root/'legacy.zip'
        with zipfile.ZipFile(archive,'w') as z:
            for p in self.source.iterdir(): z.write(p, 'nested/'+p.name)
        self.assertEqual(self.run_replay()[1:], self.run_replay(archive,'zip.jsonl')[1:])

    def test_old_capture_does_not_invent_frame_age(self):
        del self.events[0]['detections'][0]['floorHeight']['frameAgeSeconds']
        self.write_metadata()
        rows = self.run_replay()
        self.assertEqual(rows[1]['recomputed']['floorHeight'], dict(replayable=False,reason='sourceFrameAgeUnavailable'))

    def test_source_and_existing_output_preserved(self):
        before = {p.name:p.read_bytes() for p in self.source.iterdir()}
        self.run_replay()
        with self.assertRaisesRegex(ValueError,'already exists'): self.run_replay()
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.source.iterdir()})

    def test_checksum_and_duplicate_frame_rejection(self):
        with (self.source/'events.jsonl').open('a') as f: f.write('{}\n')
        with self.assertRaisesRegex(ValueError,'integrity'): self.run_replay()
        self.frames.append(self.frames[0])
        self.write_metadata()
        with self.assertRaisesRegex(ValueError,'Duplicate'): self.run_replay()
        self.assertFalse((self.root/'output.jsonl').exists())

    def test_zip_traversal_rejected(self):
        archive=self.root/'unsafe.zip'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('../escape','bad')
        with self.assertRaisesRegex(ValueError,'Unsafe'): self.run_replay(archive)
        self.assertFalse((self.root/'escape').exists())

    def test_explicit_null_floor_snapshot_does_not_resurrect_recorded_floor(self):
        event = self.events[0]
        event['detections'][0]['floorHeight']['floor'] = event['floorSnapshot']
        event['floorSnapshot'] = None
        self.write_metadata()
        height = self.run_replay()[1]['recomputed']['floorHeight']
        self.assertFalse(height['available'])
        self.assertEqual(height['reason'], 'floorNotSelected')
        del event['floorSnapshot']
        self.write_metadata()
        self.assertTrue(self.run_replay(name='legacy-floor.jsonl')[1]['recomputed']['floorHeight']['available'])

    def test_output_cannot_modify_source_session(self):
        before = {p.name: p.read_bytes() for p in self.source.iterdir()}
        for output in [self.source/'new.jsonl', self.source/'derived'/'new.jsonl']:
            with self.assertRaisesRegex(ValueError, 'outside the source'):
                replay.replay(self.source, Path(LIBRARY), output, TOOLS)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.source.iterdir()})
        alias = self.root/'source-alias'
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'outside the source'):
            replay.replay(alias, Path(LIBRARY), alias/'new.jsonl', TOOLS)

    def test_malformed_detection_objects_fail_without_output(self):
        for key, value in [('pose', []), ('depth', 'invalid'), ('floorHeight', []),
                           ('floorHeight', {'floor': ['invalid'], 'frameAgeSeconds': .05})]:
            with self.subTest(key=key, value=value):
                detection = self.events[0]['detections'][0]
                original = detection[key]
                detection[key] = value
                # A missing event floor snapshot exposes a malformed legacy floor.
                snapshot = self.events[0].pop('floorSnapshot') if isinstance(value, dict) else None
                self.write_metadata()
                with self.assertRaisesRegex(ValueError, 'object'): self.run_replay()
                self.assertFalse((self.root/'output.jsonl').exists())
                detection[key] = original
                if snapshot is not None: self.events[0]['floorSnapshot'] = snapshot
        self.events[0]['detections'] = 'invalid'
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, 'array'): self.run_replay()

    def test_malformed_settings_and_floor_snapshot_fail_without_output(self):
        for settings in [[], 'invalid', {'maxDistanceMeters': None}, {'maxPlaneAngleDegrees': '60'},
                         {'maxReprojectionErrorPixels': True}]:
            with self.subTest(settings=settings):
                self.events[0]['debugSettings'] = settings
                self.write_metadata()
                with self.assertRaisesRegex(ValueError, 'object|finite number'): self.run_replay()
                self.assertFalse((self.root/'output.jsonl').exists())
        self.events[0]['debugSettings'] = {}
        self.events[0]['floorSnapshot'] = []
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, 'Floor snapshot must be an object'): self.run_replay()

    def test_bounded_metadata_and_manifest_reads(self):
        oversized = self.root/'oversized.jsonl'
        oversized.write_bytes(b'{"value":"' + b'x'*128 + b'"}\n')
        with mock.patch.object(replay, 'MAX_RECORD_BYTES', 64):
            with self.assertRaisesRegex(ValueError, 'record limit'): list(replay.records(oversized))
        oversized.write_text('{}\n{}\n{}\n')
        with mock.patch.object(replay, 'MAX_RECORDS', 2):
            with self.assertRaisesRegex(ValueError, 'record limit'): list(replay.records(oversized))
        with mock.patch.object(replay, 'MAX_MANIFEST_BYTES', 16):
            with self.assertRaisesRegex(ValueError, 'manifest size'): self.run_replay()
        self.assertFalse((self.root/'output.jsonl').exists())

    def test_malformed_manifest_inventory_and_frame_identity(self):
        manifest_path = self.source/'manifest.json'
        original = json.loads(manifest_path.read_text())
        for manifest in [[], dict(original, fileInventory={}), dict(original, fileInventory=[None]),
                         dict(original, fileInventory=[{'path': None, 'bytes': 0, 'sha256': ''}])]:
            with self.subTest(manifest=manifest):
                manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError): self.run_replay()
                self.assertFalse((self.root/'output.jsonl').exists())
        self.frames[0]['frameId'] = ['invalid']
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, 'identities'): self.run_replay()

    @unittest.skipUnless(shutil.which('ffmpeg') and (TOOLS/'recording-format/npm/src/cli.mjs').is_file(), 'MP4 tools unavailable')
    def test_mp4_import_extract_and_replay_match(self):
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=blue:s=64x48:r=5','-t','0.6',
                        '-c:v','libx264','-pix_fmt','yuv420p',str(self.source/'rgb.mp4')],check=True)
        self.write_metadata()
        cli=TOOLS/'recording-format/npm/src/cli.mjs'
        movie=self.root/'capture.mp4'
        subprocess.run(['node',str(cli),'pack',str(self.source),str(movie)],check=True,capture_output=True)
        original_hash=replay.sha256(movie)
        direct=self.run_replay()
        imported=self.run_replay(movie,'mp4.jsonl')
        self.assertEqual(direct[1:],imported[1:])
        self.assertEqual(original_hash,replay.sha256(movie))
        restored=self.root/'restored'
        subprocess.run(['node',str(cli),'unpack',str(movie),str(restored)],check=True,capture_output=True)
        self.assertEqual({p.name:p.read_bytes() for p in self.source.iterdir()},
                         {p.name:p.read_bytes() for p in restored.iterdir()})
        self.assertEqual(direct[1:],self.run_replay(restored,'restored.jsonl')[1:])
        corrupted=self.root/'corrupt.mp4'
        payload=bytearray(movie.read_bytes())
        marker=payload.find((self.source/'events.jsonl').read_bytes())
        self.assertGreater(marker,0)
        payload[marker+10]^=1
        corrupted.write_bytes(payload)
        with self.assertRaisesRegex(ValueError,'integrity/extraction'): self.run_replay(corrupted,'bad.jsonl')
        self.assertFalse((self.root/'bad.jsonl').exists())

if __name__ == '__main__': unittest.main()
