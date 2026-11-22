import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import YAML from 'yaml';
import { packSession, inspectRecording, unpackRecording } from '../src/index.mjs';
import { appendRecording, boxes, movieInfo, TRACK_NAMES } from '../src/mp4.mjs';

const sha256 = data => createHash('sha256').update(data).digest('hex');

function videoHeader(movie) {
  const track = movieInfo(movie).tracks.find(value => value.handler === 'vide').trak;
  const header = boxes(movie, track.payload, track.end).find(value => value.type === 'tkhd');
  return { header, matrix: header.payload + (movie[header.payload] === 1 ? 52 : 40) };
}

function setRotation(movie, affine) {
  const { matrix } = videoHeader(movie);
  const values = [affine[0] * 65536, affine[1] * 65536, 0,
    affine[2] * 65536, affine[3] * 65536, 0, affine[4] * 65536, affine[5] * 65536, 0x40000000];
  values.forEach((value, index) => movie.writeInt32BE(value, matrix + index * 4));
}

test('declared playback rotations preserve original files and reject unrelated or undeclared changes', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'afar-playback-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const sourceDirectory = path.join(root, 'source');
  await mkdir(sourceDirectory);
  const sourcePath = path.join(sourceDirectory, 'rgb.mp4');
  const ffmpeg = spawnSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=s=64x48:r=5',
    '-t', '0.6', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', sourcePath], { encoding: 'utf8' });
  assert.equal(ffmpeg.status, 0, ffmpeg.stderr);
  const originals = new Map([['rgb.mp4', await readFile(sourcePath)],
    ['frames.jsonl', Buffer.from('{"frameId":"first","interfaceOrientation":1}\n')],
    ['events.jsonl', Buffer.alloc(0)]]);
  for (const [name, bytes] of originals) if (name !== 'rgb.mp4') await writeFile(path.join(sourceDirectory, name), bytes);
  const manifest = Buffer.from(JSON.stringify({ finalized: true, schemaVersion: 1,
    fileInventory: [...originals].map(([name, bytes]) => ({ path: name, bytes: bytes.length, sha256: sha256(bytes) })) }));
  await writeFile(path.join(sourceDirectory, 'manifest.json'), manifest);
  originals.set('manifest.json', manifest);
  const baselinePath = path.join(root, 'original.mp4');
  await packSession(sourceDirectory, baselinePath);
  const baseline = await readFile(baselinePath);
  const info = movieInfo(baseline);
  const payloads = new Map(info.tracks.filter(track => TRACK_NAMES.includes(track.name))
    .map(track => [track.name, baseline.subarray(track.offset, track.offset + track.bytes)]));
  const originalEnvelope = YAML.parse(payloads.get('afar.session').toString('utf8'));
  assert.equal(Object.hasOwn(await inspectRecording(baselinePath), 'playbackTransform'), false);

  function build(declaration, rotation, declare = true) {
    const envelope = structuredClone(originalEnvelope);
    if (declare) envelope.playbackTransform = declaration;
    const result = appendRecording(originals.get('rgb.mp4'), TRACK_NAMES.map(name => ({ name,
      payload: name === 'afar.session' ? Buffer.from(YAML.stringify(envelope)) : payloads.get(name) })));
    if (rotation) setRotation(result, rotation);
    return result;
  }

  const rotations = [[1, 0, 0, 1, 0, 0], [0, 1, -1, 0, 48, 0],
    [-1, 0, 0, -1, 64, 48], [0, -1, 1, 0, 0, 64]];
  for (const [index, rotation] of rotations.entries()) {
    const movie = path.join(root, `rotation-${index}.mp4`);
    const bytes = build(rotation, rotation);
    await writeFile(movie, bytes);
    assert.deepEqual((await inspectRecording(movie)).playbackTransform, rotation);
    assert.deepEqual(bytes.subarray(0, originals.get('rgb.mp4').length), baseline.subarray(0, originals.get('rgb.mp4').length));
    const restored = path.join(root, `restored-${index}`);
    await unpackRecording(movie, restored);
    for (const [name, expected] of originals) assert.deepEqual(await readFile(path.join(restored, name)), expected, name);
  }

  const clockwise = rotations[1];
  const malformed = [null, [0, 1, -1, 0, 48], [0, 1, -1, 0, 49, 0],
    ['0', 1, -1, 0, 48, 0], [1, 1, 0, 1, 0, 0], [0, 1, -1, 0, Infinity, 0],
    [0, 1, -1, 0, 1e99, 0]];
  for (const [index, declaration] of malformed.entries()) {
    const location = path.join(root, `malformed-${index}.mp4`);
    await writeFile(location, build(declaration, clockwise));
    await assert.rejects(inspectRecording(location), /playback transform/i);
  }
  const undeclared = path.join(root, 'undeclared.mp4');
  await writeFile(undeclared, build(null, clockwise, false));
  await assert.rejects(inspectRecording(undeclared), /preserve original/i);

  const mutations = [
    bytes => bytes.writeInt32BE(49 * 65536, videoHeader(bytes).matrix + 24),
    bytes => bytes.writeUInt32BE(65 * 65536, videoHeader(bytes).matrix + 36),
    bytes => { bytes[bytes.lastIndexOf(Buffer.from('avcC')) + 4] ^= 1; },
    bytes => { bytes[originals.get('rgb.mp4').indexOf(Buffer.from('mdat')) + 8] ^= 1; },
  ];
  for (const [index, mutate] of mutations.entries()) {
    const bytes = build(clockwise, clockwise);
    mutate(bytes);
    const location = path.join(root, `tampered-${index}.mp4`);
    await writeFile(location, bytes);
    await assert.rejects(inspectRecording(location), /preserve original|checksum/i);
  }
});
