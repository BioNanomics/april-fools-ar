import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdtemp, open, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import YAML from 'yaml';
import { appendRecording, box, boxes, metadataTrack, parseMovieBox, TRACK_NAMES } from '../src/mp4.mjs';
import { writeTar } from '../src/tar.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function child(buffer, atom, type) {
  return boxes(buffer, atom.payload, atom.end).find(value => value.type === type);
}

test('streaming readers restore a >512 MiB movie and >64 MiB TAR with bounded allocations', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'afar-streaming-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const tinyPath = path.join(root, 'tiny.mp4');
  run('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=32x32:r=1', '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', tinyPath]);
  const tiny = await readFile(tinyPath);
  const sourceMoov = boxes(tiny).find(atom => atom.type === 'moov');
  // A large, valid free box proves input size is independent of video decoding
  // and forces the old whole-file reader past its 512 MiB cap.
  const paddingBytes = 513 * 1024 * 1024;
  const freeHeader = Buffer.alloc(8);
  freeHeader.writeUInt32BE(paddingBytes, 0); freeHeader.write('free', 4);
  const originalHash = createHash('sha256').update(tiny).update(freeHeader);
  const zeros = Buffer.alloc(1024 * 1024);
  for (let remaining = paddingBytes - 8; remaining > 0; remaining -= Math.min(zeros.length, remaining)) originalHash.update(zeros.subarray(0, Math.min(zeros.length, remaining)));
  const sourceBytes = tiny.length + paddingBytes, sourceSHA = originalHash.digest('hex');
  const assetBytes = 65 * 1024 * 1024;
  const assetHash = createHash('sha256');
  for (let remaining = assetBytes; remaining > 0; remaining -= Math.min(zeros.length, remaining)) assetHash.update(zeros.subarray(0, Math.min(zeros.length, remaining)));
  const manifest = {
    schemaVersion: 1, finalized: true, id: 'streaming-fixture', name: 'Large sparse video',
    fileInventory: [
      { path: 'rgb.mp4', bytes: sourceBytes, sha256: sourceSHA },
      { path: 'frames.jsonl', bytes: 0, sha256: sha(Buffer.alloc(0)) },
      { path: 'events.jsonl', bytes: 0, sha256: sha(Buffer.alloc(0)) },
      { path: 'depth/big.f32', bytes: assetBytes, sha256: assetHash.digest('hex') },
    ],
  };
  const comment = Buffer.from('# No records.\n');
  const smallTar = writeTar([
    { path: 'manifest.json', data: Buffer.from(JSON.stringify(manifest)) },
    { path: 'frames.jsonl', data: Buffer.alloc(0) },
    { path: 'events.jsonl', data: Buffer.alloc(0) },
    { path: 'depth', directory: true, data: Buffer.alloc(0) },
  ], 65534);
  const assetHeader = Buffer.from(writeTar([{ path: 'depth/big.f32', data: Buffer.alloc(0) }], 65534).subarray(0, 512));
  assetHeader.write(assetBytes.toString(8).padStart(11, '0') + '\0', 124, 12, 'ascii');
  assetHeader.fill(32, 148, 156);
  const checksum = assetHeader.reduce((sum, byte) => sum + byte, 0);
  assetHeader.write(checksum.toString(8).padStart(6, '0') + '\0 ', 148, 8, 'ascii');
  const tarPrefix = Buffer.concat([smallTar.subarray(0, -1024), assetHeader]);
  const terminator = Buffer.alloc(1024), tarBytes = tarPrefix.length + assetBytes + terminator.length;
  const tarHasher = createHash('sha256').update(tarPrefix);
  for (let remaining = assetBytes; remaining > 0; remaining -= Math.min(zeros.length, remaining)) tarHasher.update(zeros.subarray(0, Math.min(zeros.length, remaining)));
  const tarSHA = tarHasher.update(terminator).digest('hex');
  const smallTarPlaceholder = Buffer.concat([tarPrefix, terminator]);
  const descriptor = (data, mimeType) => ({ bytes: data.length, sha256: sha(data), mimeType });
  const envelope = {
    format: 'april-fools-ar-recording', version: 1, draft: false, session: manifest,
    sourceVideo: { bytes: sourceBytes, sha256: sourceSHA, moovOffset: sourceMoov.start },
    payloads: {
      'afar.frames': descriptor(comment, 'application/yaml'),
      'afar.events': descriptor(comment, 'application/yaml'),
      'afar.files': { bytes: tarBytes, sha256: tarSHA, mimeType: 'application/x-tar' },
    },
  };
  const smallPackage = appendRecording(tiny, [
    { name: 'afar.session', payload: Buffer.from(YAML.stringify(envelope)) },
    { name: 'afar.frames', payload: comment }, { name: 'afar.events', payload: comment },
    { name: 'afar.files', payload: smallTarPlaceholder },
  ]);
  const top = boxes(smallPackage), movieAtom = top.find(atom => atom.type === 'moov');
  let movie = Buffer.from(smallPackage.subarray(movieAtom.start, movieAtom.end));
  const info = parseMovieBox(movie, 0xfffffffe);
  for (const track of info.tracks.filter(track => TRACK_NAMES.includes(track.name))) {
    const mdia = child(movie, track.trak, 'mdia'), minf = child(movie, mdia, 'minf'), stbl = child(movie, minf, 'stbl');
    const stco = child(movie, stbl, 'stco');
    movie.writeUInt32BE(track.offset + paddingBytes, stco.payload + 8);
  }
  const assets = info.tracks.find(track => track.name === 'afar.files');
  movie = box('moov', ...info.parts.map(atom => atom.start === assets.trak.start
    ? metadataTrack(assets.id, assets.name, tarBytes, assets.offset + paddingBytes, info.duration, info.timescale)
    : movie.subarray(atom.start, atom.end)));
  const appendix = top.find(atom => atom.type === 'mdat' && atom.start === tiny.length);
  const recording = path.join(root, 'large.mp4');
  const file = await open(recording, 'wx');
  try {
    await file.write(smallPackage.subarray(0, tiny.length), 0, tiny.length, 0);
    await file.write(freeHeader, 0, freeHeader.length, tiny.length);
    const payload = Buffer.from(smallPackage.subarray(appendix.start, appendix.end - terminator.length));
    payload.writeUInt32BE(appendix.size + assetBytes, 0);
    await file.write(payload, 0, payload.length, sourceBytes);
    await file.write(terminator, 0, terminator.length, sourceBytes + payload.length + assetBytes);
    await file.write(movie, 0, movie.length, sourceBytes + appendix.size + assetBytes);
  } finally { await file.close(); }
  const library = new URL('../src/index.mjs', import.meta.url).href;
  const output = path.join(root, 'restored');
  const dump = path.join(root, 'files.tar');
  const result = run(process.execPath, ['--max-old-space-size=96', '--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import { createReadStream } from 'node:fs';
    import { stat, readFile } from 'node:fs/promises';
    import { createHash } from 'node:crypto';
    import { inspectRecording, extractTrack, unpackRecording } from ${JSON.stringify(library)};
    const originalAlloc = Buffer.alloc;
    Buffer.alloc = function(size, ...args) { assert.ok(size <= 64 * 1024 * 1024, 'unbounded allocation'); return originalAlloc(size, ...args); };
    const info = await inspectRecording(${JSON.stringify(recording)});
    assert.equal(info.sourceVideo.bytes, ${sourceBytes});
    await extractTrack(${JSON.stringify(recording)}, 'afar.files', ${JSON.stringify(dump)});
    const unpacked = await unpackRecording(${JSON.stringify(recording)}, ${JSON.stringify(output)});
    assert.equal(unpacked.files, 5);
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(${JSON.stringify(path.join(output, 'rgb.mp4'))})) hash.update(chunk);
    assert.equal(hash.digest('hex'), ${JSON.stringify(sourceSHA)});
    assert.equal((await stat(${JSON.stringify(path.join(output, 'rgb.mp4'))})).size, ${sourceBytes});
    assert.equal((await readFile(${JSON.stringify(path.join(output, 'events.jsonl'))})).length, 0);
    assert.ok((await stat(${JSON.stringify(path.join(output, 'depth'))})).isDirectory());
    assert.equal((await stat(${JSON.stringify(path.join(output, 'depth/big.f32'))})).size, ${assetBytes});
    console.log('streamed exact source');
  `]);
  assert.match(result, /streamed exact source/);
  const extractedHash = createHash('sha256');
  for await (const chunk of createReadStream(dump)) extractedHash.update(chunk);
  assert.equal(extractedHash.digest('hex'), tarSHA);
  const packets = JSON.parse(run('ffprobe', ['-v', 'error', '-select_streams', 'm:handler_name:afar.files', '-show_packets', '-show_entries', 'packet=size', '-of', 'json', recording])).packets;
  assert.equal(packets.length, Math.ceil(tarBytes / (1024 * 1024)));
  assert.ok(packets.every(packet => Number(packet.size) <= 1024 * 1024));
  assert.equal(packets.reduce((sum, packet) => sum + Number(packet.size), 0), tarBytes);
  const stockDump = path.join(root, 'stock-files.tar');
  run('ffmpeg', ['-v', 'error', '-max_alloc', String(2 * 1024 * 1024), '-i', recording, '-map', '0:m:handler_name:afar.files', '-c', 'copy', '-f', 'data', stockDump]);
  const stockHash = createHash('sha256');
  for await (const chunk of createReadStream(stockDump)) stockHash.update(chunk);
  assert.equal(stockHash.digest('hex'), tarSHA, 'stock FFmpeg extracts TAR with a 2 MiB allocation limit');
});
