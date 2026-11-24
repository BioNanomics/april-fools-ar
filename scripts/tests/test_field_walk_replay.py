#!/usr/bin/env python3
"""Original-source walk replay and exact field YAML MP4 transport tests.

The generated video exercises transport only, not physical field accuracy.
"""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('field_replay', ROOT/'scripts/replay-field-walk.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
LIBRARY = os.environ.get('AFSC_LIBRARY')
IDENTITY = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
WORLD_FROM_FIELD = [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1]

def multiply(left, right):
    return [sum(left[k*4+r]*right[c*4+k] for k in range(4)) for c in range(4) for r in range(4)]

@unittest.skipUnless(LIBRARY, 'Set AFSC_LIBRARY to the CMake-built shared library')
class FieldReplayTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='afar-field-replay-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root/'source'
        self.source.mkdir()
        self.yaml = (ROOT/'fields/frc-2026-rebuilt-welded/field.yaml').read_bytes()
        self.definition = json.loads(replay.ruby_document(self.yaml))
        self.tag = next(t for t in self.definition['tags'] if t['id'] == 1)
        self.tag2 = next(t for t in self.definition['tags'] if t['id'] == 2)
        self.package_hash = hashlib.sha256(self.yaml).hexdigest()
        self.field = dict(packageId=self.definition['id'], packageSha256=self.package_hash,
            alignment='checked', anchorId=1, segmentId='segment-a',
            worldFromFieldColumnMajor=WORLD_FROM_FIELD,
            checks=dict(height=dict(status='pass'), tilt=dict(status='pass'), gravity=dict(status='pass')))
        self.events = [dict(type='segment',segmentId='segment-a',timestamp=100),
            dict(type='fieldWalkStarted',packageId=self.definition['id'],packageSha256=self.package_hash,
                 segmentId='segment-a',timestamp=100,field=copy.deepcopy(self.field)),
            self.observation('later',102), self.observation('earlier',101),
            self.observation('earlier',101),  # Same source observation, not another sighting.
            self.observation('metadata-only',103,identifier=2),
            self.observation('unknown',104,identifier=999,usable=False)]
        self.frames = [dict(frameId='later',segmentId='segment-a',timestamp=102,videoPTSSeconds=0,videoAppended=True),
            dict(frameId='metadata-only',segmentId='segment-a',timestamp=103,videoPTSSeconds=.2,videoAppended=False)]
        # Intentionally not a valid saved report. Replay must not parse it.
        self.saved_yaml = b'\xef\xbb\xbf# original sidecar bytes\r\nnot: [a saved summary\r\n'
        (self.source/'field-definition.yaml').write_bytes(self.yaml)
        (self.source/'field-walk-summary.yaml').write_bytes(self.saved_yaml)
        self.write_metadata()

    def observation(self, frame, timestamp, identifier=1, usable=True, segment='segment-a'):
        tag = self.tag if identifier != 2 else self.tag2
        # Independent matrix construction: a world camera from which the tag
        # lies two meters along the optical Z axis at its declared field pose.
        world_tag = multiply(WORLD_FROM_FIELD,tag['fieldFromTagColumnMajor'])
        inverse_optical = IDENTITY.copy(); inverse_optical[14] = -2
        optical_to_ar = [1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,0,1]
        camera = multiply(multiply(world_tag,inverse_optical),optical_to_ar)
        detection = dict(id=identifier,family='tag36h11',decisionMargin=80,hamming=0,
            pose=dict(translation=[0,0,2],rotationRowMajor=[1,0,0,0,1,0,0,0,1],rangeMeters=2,
                reprojectionRMSEPixels=.5,planeAngleDegrees=0,ambiguous=False,tagSizeMeters=tag['poseSizeMeters']),
            debug=dict(status='valid'),floorHeight=dict(available=False),gravityOrientation=dict(tiltFromVerticalDegrees=0))
        if not usable:
            detection.pop('pose')
        return dict(type='aprilTagDetections',analysisSucceeded=True,frameId=frame,segmentId=segment,
            timestamp=timestamp,tracking='normal',cameraToWorldColumnMajor=camera,debugSettings={},
            fieldProcessingAgeSeconds=.02,fieldRegistrationAllowed=True,detections=[detection])

    def write_metadata(self):
        for name, records in [('events.jsonl',self.events),('frames.jsonl',self.frames)]:
            (self.source/name).write_text(''.join(json.dumps(row)+'\n' for row in records))
        inventory = [dict(path=p.name,bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                     for p in self.source.iterdir() if p.name != 'manifest.json']
        manifest = dict(schemaVersion=1,id='field-source-fixture',sessionId='field-source-fixture',
            finalized=True,createdAt='2026-11-24T00:00:00Z',durationSeconds=.6,firstARFrameTimestamp=100,
            fileInventory=inventory,fieldDefinition=dict(id=self.definition['id'],packageSha256=self.package_hash,
                                                       definition=self.definition))
        (self.source/'manifest.json').write_text(json.dumps(manifest))

    def report(self, source=None):
        return replay.replay_folder(source or self.source,LIBRARY)

    def rows(self, report=None):
        return {r['id']:r for r in (report or self.report())['field']['seenTags']}

    def test_original_inventory_nominal_geometry_timestamps_and_metadata_only_frames(self):
        report = self.report(); rows = self.rows(report)
        self.assertEqual(report['field']['packageSha256'],self.package_hash)
        self.assertEqual(report['field']['seenCount'],3)
        self.assertEqual(report['field']['expectedCount'],len(self.definition['tags']))
        self.assertFalse(report['replay']['savedSummaryUsed'])
        self.assertIn('not re-solved',report['replay']['positions'])
        self.assertFalse(report['accuracyValidated'])
        self.assertEqual((rows[1]['count'],rows[1]['acceptedCount'],rows[1]['rejectedCount']),(2,2,0))
        self.assertEqual((rows[1]['firstSeen'],rows[1]['lastSeen']),(101,102))
        # Source completion order controls latest evidence; reducer source clock
        # independently controls first/last sightings.
        self.assertEqual(rows[1]['frameId'],'earlier')
        self.assertEqual(rows[1]['timestamp'],101)
        self.assertEqual(rows[1]['nominalPosition'],self.tag['fieldFromTagColumnMajor'][12:15])
        self.assertEqual(rows[1]['comparisonStatus'],'assumed-anchor')
        for actual, expected in zip(rows[1]['observedPosition'],rows[1]['nominalPosition']):
            self.assertAlmostEqual(actual,expected,places=10)
        self.assertEqual(rows[2]['count'],1)
        self.assertEqual(rows[2]['acceptedCount'],1)
        self.assertEqual(rows[2]['frameId'],'metadata-only')
        self.assertEqual(rows[2]['nominalPosition'],self.tag2['fieldFromTagColumnMajor'][12:15])
        self.assertEqual((rows[999]['count'],rows[999]['rejectedCount']),(1,1))
        self.assertIsNone(rows[999]['nominalPosition'])
        self.assertIsNone(rows[999]['observedPosition'])

    def test_missing_or_corrupt_saved_summary_is_never_an_input(self):
        original = self.report()
        (self.source/'field-walk-summary.yaml').unlink()
        self.assertEqual(self.report(),original)
        (self.source/'field-walk-summary.yaml').write_bytes(b'\x00\xffbad yaml')
        self.assertEqual(self.report(),original)

    def test_legacy_capture_without_a_pinned_package_reports_unavailable(self):
        path=self.source/'manifest.json'; manifest=json.loads(path.read_bytes())
        manifest.pop('fieldDefinition'); path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(replay.ReplayError,'no pinned field definition'):
            self.report()

    def test_acceptance_policy_rejects_stale_unavailable_and_print_size_conflict(self):
        for frame, change in [('stale',dict(fieldProcessingAgeSeconds=.41)),
                              ('generation',dict(fieldRegistrationAllowed=False)),
                              ('limited',dict(tracking='limited'))]:
            self.events.append(dict(self.observation(frame,105),**change))
        missing = self.observation('missing',106); missing.pop('fieldProcessingAgeSeconds')
        self.events.append(missing)
        conflict = self.observation('print-size',107); conflict['detections'][0]['pose']['tagSizeMeters'] *= 1.04
        self.events.append(conflict)
        self.write_metadata(); report=self.report(); row=self.rows(report)[1]
        self.assertEqual((row['count'],row['acceptedCount'],row['rejectedCount']),(7,2,5))
        self.assertEqual(report['replay']['missingProcessingAgeEvents'],1)
        self.assertIn('print size',row['reason'])

    def test_recorded_controls_clear_geometry_on_reset_and_never_cross_segments(self):
        self.events.extend([dict(type='fieldRegistrationInvalidated',timestamp=105,segmentId='segment-a',
            packageId=self.definition['id'],packageSha256=self.package_hash,
            field=dict(self.field,alignment='invalidated',worldFromFieldColumnMajor=None)),
            self.observation('after-reset',106)])
        self.write_metadata(); self.assertIsNone(self.rows()[1]['observedPosition'])
        self.events.extend([dict(type='fieldRegistrationChanged',timestamp=107,segmentId='segment-a',
            packageId=self.definition['id'],packageSha256=self.package_hash,field=self.field),
            self.observation('new-segment',108,segment='segment-b')])
        self.write_metadata(); self.assertIsNone(self.rows()[1]['observedPosition'])
        # Same raw frame ID in a different segment remains a separate sighting.
        self.events.append(self.observation('earlier',109,segment='segment-b'))
        self.write_metadata(); self.assertEqual(self.rows()[1]['count'],5)

    def test_yaml_hash_source_inventory_and_symlink_integrity(self):
        path=self.source/'field-definition.yaml'; path.write_bytes(self.yaml+b'# changed\n')
        with self.assertRaisesRegex(replay.ReplayError,'integrity'): self.report()
        self.write_metadata()
        with self.assertRaisesRegex(replay.ReplayError,'Pinned YAML hash'): self.report()
        path.unlink(); path.symlink_to(ROOT/'fields/frc-2026-rebuilt-welded/field.yaml')
        with self.assertRaises(OSError): self.report()

    def test_final_generic_invalidation_clears_reported_registration_without_a_field_control(self):
        for event in [dict(type='segment',segmentId='segment-b',timestamp=105),
                      dict(type='trackingChanged',tracking='limited',segmentId='segment-a',timestamp=105),
                      dict(type='settingsChanged',segmentId='segment-a',timestamp=105),
                      dict(type='floorConfirmed',segmentId='segment-a',timestamp=105)]:
            with self.subTest(type=event['type']):
                self.events.append(event); self.write_metadata()
                report=self.report()
                self.assertEqual(report['field']['alignment'],'unaligned')
                self.assertIsNone(report['field']['worldFromFieldColumnMajor'])
                self.assertIsNone(report['field']['anchorId'])
                self.assertEqual(self.rows(report)[1]['count'],2)
                self.assertIn('Replay invalidated',report['field']['reason'])
                self.events.pop()

    def test_warning_snapshot_cannot_rekey_or_revive_geometry(self):
        other = WORLD_FROM_FIELD.copy(); other[12]=100
        warning = dict(type='fieldAnchorWarning',timestamp=105,segmentId='segment-a',
            packageId=self.definition['id'],packageSha256=self.package_hash,
            field=dict(self.field,reason='Disagreement retained.',worldFromFieldColumnMajor=other))
        self.events.append(warning); self.write_metadata()
        report=self.report()
        self.assertEqual(report['field']['worldFromFieldColumnMajor'],WORLD_FROM_FIELD)
        self.assertEqual(report['field']['reason'],'Disagreement retained.')
        self.events.insert(-1,dict(type='trackingChanged',tracking='limited',timestamp=104.5,segmentId='segment-a'))
        self.write_metadata(); report=self.report()
        self.assertIsNone(report['field']['worldFromFieldColumnMajor'])
        self.assertEqual(report['field']['alignment'],'unaligned')

    def test_cli_default_yaml_json_and_source_output_protection(self):
        before={p.name:p.read_bytes() for p in self.source.iterdir()}
        output=self.root/'replayed.yaml'
        args=[str(self.source),'--core-library',LIBRARY,'--output',str(output)]
        self.assertEqual(replay.main(args),0)
        report=json.loads(replay.ruby_document(output.read_bytes()))
        self.assertEqual(report,self.report())
        self.assertNotEqual(output.read_bytes()[:1],b'{')
        with self.assertRaisesRegex(replay.ReplayError,'new file'): replay.main(args)
        alias=self.root/'output-alias'; alias.symlink_to(self.source,target_is_directory=True)
        for output in [self.source/'in-source.yaml',alias/'aliased.yaml']:
            with self.assertRaisesRegex(replay.ReplayError,'outside the source'):
                replay.main([str(self.source),'--core-library',LIBRARY,'--output',str(output)])
        json_output=self.root/'replayed.json'
        replay.main([str(self.source),'--core-library',LIBRARY,'--output',str(json_output),'--format','json'])
        self.assertEqual(json.loads(json_output.read_bytes()),report)
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.source.iterdir()})

    def test_malformed_original_records_fail_without_guessing(self):
        for key, value in [('pose','bad'),('debug','bad'),('floorHeight','bad'),('gravityOrientation','bad')]:
            with self.subTest(key=key):
                original=self.events[2]['detections'][0][key]
                self.events[2]['detections'][0][key]=value; self.write_metadata()
                with self.assertRaisesRegex(replay.ReplayError,'object'): self.report()
                self.events[2]['detections'][0][key]=original
        self.events[2]['timestamp']=-1; self.write_metadata()
        with self.assertRaisesRegex(replay.ReplayError,'clock'): self.report()

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('node'),'MP4 tools unavailable')
    def test_original_mp4_preserves_field_yaml_bytes_and_regenerates_equivalent_inventory(self):
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=blue:s=64x48:r=5',
            '-t','0.6','-c:v','libx264','-pix_fmt','yuv420p',str(self.source/'rgb.mp4')],check=True)
        self.write_metadata(); before={p.name:p.read_bytes() for p in self.source.iterdir()}
        cli=ROOT/'recording-format/npm/src/cli.mjs'; movie=self.root/'original.mp4'; restored=self.root/'restored'
        subprocess.run(['node',str(cli),'pack',str(self.source),str(movie)],check=True,capture_output=True)
        subprocess.run(['node',str(cli),'unpack',str(movie),str(restored)],check=True,capture_output=True)
        for name in ['field-definition.yaml','field-walk-summary.yaml','events.jsonl','frames.jsonl','manifest.json']:
            self.assertEqual((restored/name).read_bytes(),before[name],name)
        self.assertEqual(self.report(restored),self.report())
        output=self.root/'movie-replay.json'
        replay.main([str(movie),'--core-library',LIBRARY,'--output',str(output),'--format','json'])
        self.assertEqual(json.loads(output.read_text()),self.report())
        self.assertEqual(before,{p.name:p.read_bytes() for p in self.source.iterdir()})

if __name__ == '__main__':
    unittest.main()
