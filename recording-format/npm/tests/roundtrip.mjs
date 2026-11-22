import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, readdir, rm, symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parse, parseAllDocuments } from 'yaml';
import {
  packSession,
  inspectRecording,
  extractTrack,
  unpackRecording,
} from '../src/index.mjs';

const sha256 = data => createHash('sha256').update(data).digest('hex');
const trackNames = ['afar.session', 'afar.frames', 'afar.events', 'afar.files'];
const cli = fileURLToPath(new URL('../src/cli.mjs', import.meta.url));

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${command} failed:\n${result.stderr}`);
  return result.stdout;
}

async function filesUnder(root, prefix = '') {
  const result = [];
  for (const entry of await readdir(path.join(root, prefix), { withFileTypes: true })) {
    const name = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) result.push(...await filesUnder(root, name));
    else result.push(name);
  }
  return result.sort();
}

async function fixture(root, faststart) {
  const source = path.join(root, 'source');
  await mkdir(path.join(source, 'frames'), { recursive: true });
  await mkdir(path.join(source, 'depth'));
  const video = path.join(source, 'rgb.mp4');
  run('ffmpeg', [
    '-v', 'error', '-f', 'lavfi', '-i', 'color=c=blue:s=64x48:r=5',
    '-t', '0.6', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
    ...(faststart ? ['-movflags', '+faststart'] : []), video,
  ]);
  run('ffmpeg', ['-v', 'error', '-i', video, '-frames:v', '1', '-update', '1', path.join(source, 'frames/frame-2.jpg')]);
  // Keep noncanonical NaN bits and negative zero to catch numeric re-encoding.
  const depth = Buffer.from('0000a03f4523c17f0000008000004040', 'hex');
  await writeFile(path.join(source, 'depth/frame-2.f32'), depth);
  await writeFile(path.join(source, 'depth/frame-2.confidence.u8'), Buffer.from([2, 0, 1, 2]));
  const frames = [
    { frameId: 'frame-1', segmentId: 'segment-1', timestamp: 12000.125, videoPTSSeconds: 0, videoAppended: true },
    { frameId: 'frame-2', segmentId: 'segment-1', timestamp: 12000.225, videoPTSSeconds: 0.1,
      videoAppended: false, rgbImagePath: 'frames/frame-2.jpg', depthPath: 'depth/frame-2.f32',
      confidencePath: 'depth/frame-2.confidence.u8', depthWidth: 2, depthHeight: 2 },
  ];
  // Event order differs from source-time order; do not sort during conversion.
  const events = [
    { type: 'bookmark', frameId: 'frame-2', timestamp: 12000.225, note: 'Tag 4 — café 🦀\nyes: on\n---\ntrue' },
    { type: 'aprilTagDetections', frameId: 'frame-1', timestamp: 12000.125, detections: [], analysisSucceeded: true },
  ];
  await writeFile(path.join(source, 'frames.jsonl'), frames.map(record => JSON.stringify(record)).join('\n') + '\n');
  await writeFile(path.join(source, 'events.jsonl'), events.map(record => JSON.stringify(record)).join('\n') + '\n');
  await writeFile(path.join(source, 'empty.bin'), Buffer.alloc(0));
  const inventory = [];
  for (const name of await filesUnder(source)) {
    const data = await readFile(path.join(source, name));
    inventory.push({ path: name, bytes: data.length, sha256: sha256(data) });
  }
  const manifest = {
    schemaVersion: 1, id: 'synthetic-session', sessionId: 'synthetic-session',
    name: 'YAML readability — café 🦀', finalized: true,
    createdAt: '2026-11-22T20:00:00Z', durationSeconds: 0.6,
    firstARFrameTimestamp: 12000.125, fileInventory: inventory,
  };
  await writeFile(path.join(source, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  return { source, frames, events, manifest };
}

function yamlRecords(data) {
  return parseAllDocuments(data.toString('utf8')).map(doc => {
    assert.deepEqual(doc.errors, []);
    return doc.toJS();
  });
}

for (const faststart of [false, true]) {
  test(`source session survives npm and FFmpeg extraction (${faststart ? 'faststart' : 'moov at end'})`, async t => {
    const root = await mkdtemp(path.join(os.tmpdir(), 'afar-format-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const { source, frames, events, manifest } = await fixture(root, faststart);
    const movie = path.join(root, 'capture.mp4');
    await packSession(source, movie);
    const info = await inspectRecording(movie);
    assert.equal(info.format, 'april-fools-ar-recording');
    assert.equal(info.version, 1);
    assert.equal(info.draft, false);
    assert.deepEqual(info.session, manifest);
    assert.equal(info.tracks.length, 5);
    assert.deepEqual(info.tracks.filter(track => trackNames.includes(track.name)).map(track => track.name).sort(), trackNames.toSorted());

    const streams = JSON.parse(run('ffprobe', [
      '-v', 'error', '-show_entries', 'stream=index,codec_type,codec_tag_string:stream_tags=handler_name',
      '-of', 'json', movie,
    ])).streams;
    const metadata = streams.filter(stream => trackNames.includes(stream.tags?.handler_name));
    assert.equal(metadata.length, 4);
    for (const stream of metadata) {
      assert.equal(stream.codec_type, 'data');
      assert.equal(stream.codec_tag_string, stream.tags.handler_name === 'afar.files' ? 'urim' : 'mett');
      const name = stream.tags.handler_name;
      const stockOutput = path.join(root, `${name}.ffmpeg`);
      const libraryOutput = path.join(root, `${name}.npm`);
      run('ffmpeg', ['-v', 'error', '-i', movie, '-map', `0:m:handler_name:${name}`, '-c', 'copy', '-f', 'data', stockOutput]);
      await extractTrack(movie, name, libraryOutput);
      assert.deepEqual(await readFile(stockOutput), await readFile(libraryOutput), `FFmpeg matches npm for ${name}`);
    }
    assert.deepEqual(yamlRecords(await readFile(path.join(root, 'afar.frames.ffmpeg'))), frames);
    assert.deepEqual(yamlRecords(await readFile(path.join(root, 'afar.events.ffmpeg'))), events);
    assert.deepEqual(parse(await readFile(path.join(root, 'afar.session.ffmpeg'), 'utf8')).session, manifest);

    const sidecars = path.join(root, 'stock-sidecars');
    await mkdir(sidecars);
    run('tar', ['-xf', path.join(root, 'afar.files.ffmpeg'), '-C', sidecars]);
    assert.deepEqual(await filesUnder(sidecars), (await filesUnder(source)).filter(name => name !== 'rgb.mp4'));
    for (const name of await filesUnder(sidecars)) {
      assert.deepEqual(await readFile(path.join(sidecars, name)), await readFile(path.join(source, name)), name);
    }

    const restored = path.join(root, 'restored');
    await unpackRecording(movie, restored);
    assert.deepEqual(await filesUnder(restored), await filesUnder(source));
    for (const name of await filesUnder(source)) {
      assert.deepEqual(await readFile(path.join(restored, name)), await readFile(path.join(source, name)), `Exact restored ${name}`);
    }
    for (const entry of manifest.fileInventory) {
      assert.equal(sha256(await readFile(path.join(restored, entry.path))), entry.sha256, `Original manifest hash ${entry.path}`);
    }
    if (!faststart) {
      const cliMovie = path.join(root, 'cli-capture.mp4');
      const packed = parse(run(process.execPath, [cli, 'pack', source, cliMovie]));
      assert.equal(packed.format, info.format);
      const listed = parse(run(process.execPath, [cli, 'list', cliMovie]));
      assert.deepEqual(listed.session, manifest);
      const cliEvents = path.join(root, 'cli-events.yaml');
      run(process.execPath, [cli, 'extract', cliMovie, 'afar.events', cliEvents]);
      assert.deepEqual(yamlRecords(await readFile(cliEvents)), events);
      const cliRestored = path.join(root, 'cli-restored');
      run(process.execPath, [cli, 'unpack', cliMovie, cliRestored]);
      assert.deepEqual(await readFile(path.join(cliRestored, 'rgb.mp4')), await readFile(path.join(source, 'rgb.mp4')));
    }
    run('ffmpeg', ['-v', 'error', '-i', movie, '-map', '0:v:0', '-f', 'null', '-']);
    const videoHash = filename => run('ffmpeg', ['-v', 'error', '-i', filename, '-map', '0:v:0', '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-']);
    assert.equal(videoHash(movie), videoHash(path.join(source, 'rgb.mp4')), 'Original H264 bytes preserved');

    await assert.rejects(packSession(source, movie), /exist/i);
    await assert.rejects(unpackRecording(movie, restored), /exist/i);
    await assert.rejects(extractTrack(movie, 'afar.frames', path.join(root, 'afar.frames.npm')), /exist/i);
    await assert.rejects(extractTrack(movie, 'missing.track', path.join(root, 'missing')), /track|unknown|found/i);

    const corruptMovie = Buffer.from(await readFile(movie));
    const rawFrames = await readFile(path.join(root, 'afar.frames.npm'));
    const framesOffset = corruptMovie.indexOf(rawFrames);
    assert.ok(framesOffset > 0);
    corruptMovie[framesOffset + rawFrames.length - 2] ^= 1;
    const corruptPath = path.join(root, 'corrupt.mp4');
    await writeFile(corruptPath, corruptMovie);
    await assert.rejects(unpackRecording(corruptPath, path.join(root, 'corrupt-output')), /checksum|hash|integrity/i);

    // A recomputed outer payload hash must not make a traversal TAR acceptable.
    const originalTar = await readFile(path.join(root, 'afar.files.npm'));
    const unsafeTar = Buffer.from(originalTar);
    unsafeTar.fill(0, 0, 100);
    unsafeTar.write('../escaped', 0, 'utf8');
    unsafeTar.fill(32, 148, 156);
    const headerChecksum = unsafeTar.subarray(0, 512).reduce((sum, byte) => sum + byte, 0);
    unsafeTar.write(headerChecksum.toString(8).padStart(6, '0') + '\0 ', 148, 8, 'ascii');
    const unsafeMovie = Buffer.from(await readFile(movie));
    const tarOffset = unsafeMovie.indexOf(originalTar);
    const digestOffset = unsafeMovie.indexOf(Buffer.from(sha256(originalTar)));
    assert.ok(tarOffset > 0 && digestOffset > 0);
    unsafeTar.copy(unsafeMovie, tarOffset);
    unsafeMovie.write(sha256(unsafeTar), digestOffset, 64, 'ascii');
    const traversalPath = path.join(root, 'traversal.mp4');
    await writeFile(traversalPath, unsafeMovie);
    await assert.rejects(unpackRecording(traversalPath, path.join(root, 'traversal-output')), /unsafe|path|traversal/i);
    assert.ok(!(await readdir(root)).includes('escaped'));

    const sourceCorruption = Buffer.from(await readFile(movie));
    const originalVideo = await readFile(path.join(source, 'rgb.mp4'));
    const mediaMarker = originalVideo.indexOf(Buffer.from('mdat'));
    assert.ok(mediaMarker > 0 && mediaMarker + 8 < originalVideo.length);
    sourceCorruption[mediaMarker + 8] ^= 1;
    const sourceCorruptionPath = path.join(root, 'corrupt-video.mp4');
    await writeFile(sourceCorruptionPath, sourceCorruption);
    await assert.rejects(unpackRecording(sourceCorruptionPath, path.join(root, 'corrupt-video-output')), /checksum|hash|integrity/i);

    const headerCorruption = Buffer.from(await readFile(movie));
    const decoderConfig = headerCorruption.lastIndexOf(Buffer.from('avcC'));
    assert.ok(decoderConfig > originalVideo.length);
    headerCorruption[decoderConfig + 4] ^= 1;
    const headerCorruptionPath = path.join(root, 'corrupt-video-header.mp4');
    await writeFile(headerCorruptionPath, headerCorruption);
    await assert.rejects(inspectRecording(headerCorruptionPath), /original|movie|track|source|mismatch|header/i);

    const unsafeSource = path.join(root, 'unsafe');
    await mkdir(unsafeSource);
    await symlink(source, path.join(unsafeSource, 'linked-source'));
    await writeFile(path.join(unsafeSource, 'manifest.json'), JSON.stringify(manifest));
    await symlink(path.join(source, 'rgb.mp4'), path.join(unsafeSource, 'rgb.mp4'));
    await assert.rejects(packSession(unsafeSource, path.join(root, 'unsafe.mp4')), /link|regular/i);

    // No source records should produce a readable comment, not an invented record.
    const emptyManifest = structuredClone(manifest);
    for (const name of ['frames.jsonl', 'events.jsonl']) {
      await writeFile(path.join(source, name), '');
      const entry = emptyManifest.fileInventory.find(item => item.path === name);
      entry.bytes = 0;
      entry.sha256 = sha256(Buffer.alloc(0));
    }
    await writeFile(path.join(source, 'manifest.json'), JSON.stringify(emptyManifest));
    const emptyMovie = path.join(root, 'empty-records.mp4');
    await packSession(source, emptyMovie);
    for (const name of ['afar.frames', 'afar.events']) {
      const output = path.join(root, `${name}.empty.yaml`);
      run('ffmpeg', ['-v', 'error', '-i', emptyMovie, '-map', `0:m:handler_name:${name}`, '-c', 'copy', '-f', 'data', output]);
      assert.deepEqual(yamlRecords(await readFile(output)), []);
    }
    const emptyRestored = path.join(root, 'empty-restored');
    await unpackRecording(emptyMovie, emptyRestored);
    assert.equal((await readFile(path.join(emptyRestored, 'events.jsonl'))).length, 0);
  });
}

test('malformed input is rejected without creating an output', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'afar-malformed-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bad = path.join(root, 'bad.mp4');
  await writeFile(bad, Buffer.from([0, 0, 0, 99, ...Buffer.from('moov'), 0]));
  await assert.rejects(inspectRecording(bad), /box|truncat|invalid|moov|bounds/i);
  const output = path.join(root, 'output');
  await assert.rejects(unpackRecording(bad, output));
  assert.deepEqual((await readdir(root)).sort(), ['bad.mp4']);
});
