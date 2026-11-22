import { constants } from 'node:fs';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import YAML from 'yaml';
import { appendRecording, boxes, FILES_URI, movieInfo, parseMovieBox, TRACK_NAMES, validateSourceMovie } from './mp4.mjs';
import { pathKey, safePath, writeTar } from './tar.mjs';

export const LIMITS = Object.freeze({
  maxSessionBytes: 256 * 1024 * 1024,
  maxRecordingBytes: 0xfffffffe,
  maxSourceVideoBytes: 0xfffffffe,
  maxMetadataBytes: 16 * 1024 * 1024,
  maxYAMLBytes: 64 * 1024 * 1024,
  maxMoovBytes: 64 * 1024 * 1024,
  maxEntries: 65534,
  maxRecords: 100000,
});
const FORMAT = 'april-fools-ar-recording';
const decoder = new TextDecoder('utf-8', { fatal: true });
const digest = data => createHash('sha256').update(data).digest('hex');
function requireObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Expected ${label} to be an object`);
  return value;
}
function json(data, label) {
  if (data.length > LIMITS.maxMetadataBytes) throw new Error(`${label} exceeds metadata limit`);
  return requireObject(JSON.parse(decoder.decode(data)), label);
}
function jsonLines(data, label) {
  if (data.length > LIMITS.maxMetadataBytes) throw new Error(`${label} exceeds metadata limit`);
  const result = [];
  for (const line of decoder.decode(data).split(/\r?\n/u)) {
    if (!line.trim()) continue;
    result.push(requireObject(JSON.parse(line), label));
    if (result.length > LIMITS.maxRecords) throw new Error(`${label} exceeds record limit`);
  }
  return result;
}
function yaml(value) {
  return YAML.stringify(value, { aliasDuplicateObjects: false, lineWidth: 0 });
}
function boundedYAML(text) {
  const buffer = Buffer.from(text);
  if (buffer.length > LIMITS.maxYAMLBytes) throw new Error('Generated YAML exceeds metadata limit');
  return buffer;
}
function yamlStream(records) {
  return boundedYAML(records.length ? records.map(record => `---\n${yaml(record)}`).join('') : '# No records.\n');
}
function parseYAML(data, stream = false) {
  if (data.length > LIMITS.maxYAMLBytes) throw new Error('YAML exceeds metadata limit');
  const documents = YAML.parseAllDocuments(decoder.decode(data), { uniqueKeys: true, strict: true });
  if (documents.length > LIMITS.maxRecords) throw new Error('Too many YAML documents');
  const values = documents.map(document => {
    if (document.errors.length) throw document.errors[0];
    return document.toJS({ maxAliasCount: 0 });
  });
  if (stream) return values;
  if (values.length !== 1) throw new Error('Expected exactly one session YAML document');
  return requireObject(values[0], 'session envelope');
}
async function readRegular(file, limit) {
  const handle = await fs.open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await handle.stat();
    if (!before.isFile() || !Number.isSafeInteger(before.size) || before.size > limit) throw new Error(`File exceeds draft limit or is not regular: ${file}`);
    const data = Buffer.alloc(before.size);
    let cursor = 0;
    while (cursor < data.length) {
      const { bytesRead } = await handle.read(data, cursor, data.length - cursor, cursor);
      if (!bytesRead) throw new Error(`File changed or was truncated while reading: ${file}`);
      cursor += bytesRead;
    }
    const probe = Buffer.alloc(1);
    const extra = await handle.read(probe, 0, 1, cursor);
    const after = await handle.stat();
    if (extra.bytesRead || before.size !== after.size || before.mtimeMs !== after.mtimeMs) throw new Error(`File changed while reading: ${file}`);
    return data;
  } finally { await handle.close(); }
}
async function assertAbsent(location) {
  try { await fs.lstat(location); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
  throw new Error(`Destination already exists: ${location}`);
}
async function writeNewFile(location, data) {
  const destination = path.resolve(location);
  await assertAbsent(destination);
  const parent = path.dirname(destination);
  const parentInfo = await fs.stat(parent);
  if (!parentInfo.isDirectory()) throw new Error('Output parent must be an existing directory');
  const temporary = path.join(parent, `.${path.basename(destination)}.${randomUUID()}.tmp`);
  try {
    await fs.writeFile(temporary, data, { flag: 'wx', mode: 0o600 });
    // Hard-link publication is atomic and refuses a concurrently created destination.
    await fs.link(temporary, destination);
  } finally { await fs.rm(temporary, { force: true }); }
  return destination;
}
async function sessionFiles(directory) {
  const root = path.resolve(directory);
  const rootInfo = await fs.lstat(root);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) throw new Error('Session must be a regular directory, not a symbolic link');
  const entries = [];
  let total = 0;
  async function visit(relative) {
    const location = relative ? path.join(root, relative) : root;
    const names = (await fs.readdir(location)).sort();
    for (const name of names) {
      const logical = relative ? `${relative}/${name}` : name;
      safePath(logical);
      const absolute = path.join(root, logical);
      const stat = await fs.lstat(absolute);
      if (stat.isSymbolicLink()) throw new Error(`Symbolic links are not supported: ${logical}`);
      if (stat.isDirectory()) {
        entries.push({ path: logical, directory: true, data: Buffer.alloc(0) });
        if (entries.length > LIMITS.maxEntries) throw new Error('Too many session files/directories');
        await visit(logical);
      } else if (stat.isFile()) {
        total += stat.size;
        if (total > LIMITS.maxSessionBytes) throw new Error('Session exceeds 256 MiB draft in-memory limit');
        entries.push({ path: logical, directory: false, data: await readRegular(absolute, LIMITS.maxSessionBytes) });
      } else throw new Error(`Special files are not supported: ${logical}`);
      if (entries.length > LIMITS.maxEntries) throw new Error('Too many session files/directories');
    }
  }
  await visit('');
  const names = new Set();
  for (const entry of entries) {
    const key = pathKey(entry.path);
    if (names.has(key)) throw new Error(`Duplicate/colliding session path: ${entry.path}`);
    names.add(key);
  }
  return { root, entries };
}
function fileMap(entries) {
  return new Map(entries.filter(e => !e.directory).map(e => [e.path, e.data]));
}
function required(files, name) {
  const value = files.get(name);
  if (!value) throw new Error(`Missing required session file: ${name}`);
  return value;
}
function verifyInventory(manifest, files) {
  if (manifest.fileInventory === undefined) return;
  if (!Array.isArray(manifest.fileInventory) || manifest.fileInventory.length > LIMITS.maxEntries) throw new Error('Invalid source file inventory');
  const seen = new Set();
  for (const entry of manifest.fileInventory) {
    requireObject(entry, 'inventory entry');
    safePath(entry.path);
    if (seen.has(pathKey(entry.path))) throw new Error('Duplicate source inventory entry');
    seen.add(pathKey(entry.path));
    const data = required(files, entry.path);
    if (entry.bytes !== data.length || entry.sha256 !== digest(data)) throw new Error(`Source inventory checksum/length mismatch: ${entry.path}`);
  }
}
function payloadInfo(data, mimeType) { return { bytes: data.length, sha256: digest(data), mimeType }; }
function publicInfo(loaded) {
  const { envelope, info } = loaded;
  return {
    format: envelope.format, version: envelope.version, draft: envelope.draft,
    session: envelope.session, sourceVideo: envelope.sourceVideo, payloads: envelope.payloads,
    ...(Object.hasOwn(envelope, 'playbackTransform') ? { playbackTransform: envelope.playbackTransform } : {}),
    tracks: info.tracks.map(track => ({ id: track.id, name: track.name, sampleEntry: track.sampleEntry, mimeType: track.mimeType, bytes: track.bytes, sampleCount: track.sampleCount, maxSampleBytes: track.maxSampleBytes })),
  };
}

/** Package a finalized session directory. The current app's recorder is unchanged. */
export async function packSession(sessionDirectory, outputPath) {
  const output = path.resolve(outputPath), root = path.resolve(sessionDirectory);
  const relativeOutput = path.relative(root, output);
  if (!relativeOutput || (!relativeOutput.startsWith(`..${path.sep}`) && relativeOutput !== '..' && !path.isAbsolute(relativeOutput))) throw new Error('Output must be outside the source session directory');
  await assertAbsent(output);
  const { entries } = await sessionFiles(root);
  const files = fileMap(entries), source = required(files, 'rgb.mp4');
  const sourceInfo = validateSourceMovie(source);
  const session = json(required(files, 'manifest.json'), 'manifest.json');
  if (session.finalized !== true) throw new Error('Source session must be finalized');
  verifyInventory(session, files);
  const frames = yamlStream(jsonLines(required(files, 'frames.jsonl'), 'frames.jsonl'));
  const events = yamlStream(jsonLines(required(files, 'events.jsonl'), 'events.jsonl'));
  const archive = writeTar(entries.filter(entry => entry.path !== 'rgb.mp4'), LIMITS.maxEntries);
  const envelope = {
    format: FORMAT, version: 1, draft: false,
    session,
    sourceVideo: { bytes: source.length, sha256: digest(source), moovOffset: sourceInfo.moov.start },
    payloads: {
      'afar.frames': payloadInfo(frames, 'application/yaml'),
      'afar.events': payloadInfo(events, 'application/yaml'),
      'afar.files': payloadInfo(archive, 'application/x-tar'),
    },
  };
  const sessionYAML = boundedYAML(yaml(envelope));
  const recording = appendRecording(source, [
    { name: 'afar.session', payload: sessionYAML }, { name: 'afar.frames', payload: frames },
    { name: 'afar.events', payload: events }, { name: 'afar.files', payload: archive },
  ]);
  if (recording.length > LIMITS.maxRecordingBytes) throw new Error('Packaged recording exceeds the 4 GiB format limit');
  const result = validateRecording(recording);
  await writeNewFile(output, recording);
  return { ...publicInfo(result), outputPath: output, bytes: recording.length };
}

function validateRecording(buffer) {
  const info = movieInfo(buffer);
  const dataTracks = info.tracks.filter(track => TRACK_NAMES.includes(track.name));
  if (dataTracks.length !== TRACK_NAMES.length || new Set(dataTracks.map(t => t.name)).size !== TRACK_NAMES.length || info.tracks.length !== 5) throw new Error('Expected one video track and four unique afar data tracks');
  const tracks = new Map(dataTracks.map(t => [t.name, t]));
  const samples = new Map();
  for (const name of TRACK_NAMES) {
    const track = tracks.get(name);
    if ((name === 'afar.files' && (track.sampleEntry !== 'urim' || track.uri !== FILES_URI)) || (name !== 'afar.files' && (track.sampleEntry !== 'mett' || track.mimeType !== 'application/yaml'))) throw new Error(`Invalid sample description for ${name}`);
    samples.set(name, buffer.subarray(track.offset, track.offset + track.bytes));
  }
  const envelope = parseYAML(samples.get('afar.session'));
  if (envelope.format !== FORMAT || envelope.version !== 1 || typeof envelope.draft !== 'boolean') throw new Error('Unsupported recording envelope format/version');
  requireObject(envelope.session, 'original manifest');
  if (envelope.session.finalized !== true) throw new Error('Embedded source session is not finalized');
  const original = requireObject(envelope.sourceVideo, 'sourceVideo');
  if (!Number.isSafeInteger(original.bytes) || original.bytes <= 0 || original.bytes > LIMITS.maxSourceVideoBytes || original.bytes >= buffer.length || !Number.isSafeInteger(original.moovOffset) || original.moovOffset < 0 || !/^[a-f0-9]{64}$/u.test(original.sha256)) throw new Error('Invalid source-video restoration metadata');
  const prefixParts = boxes(buffer, 0, original.bytes);
  const oldMovie = prefixParts.find(atom => atom.start === original.moovOffset && atom.type === 'free');
  if (!oldMovie) throw new Error('Original movie box is not a top-level free box');
  const appendices = info.top.filter(atom => atom.start >= original.bytes);
  if (appendices.length !== 2 || appendices[0].type !== 'mdat' || appendices[0].start !== original.bytes || appendices[1].type !== 'moov' || appendices[1].end !== buffer.length) throw new Error('Invalid appended recording layout');
  let cursor = appendices[0].payload;
  for (const name of TRACK_NAMES) {
    const track = tracks.get(name);
    if (track.offset !== cursor) throw new Error('Data sample overlaps or is outside the recording appendix');
    cursor += track.bytes;
  }
  if (cursor !== appendices[0].end) throw new Error('Unexpected bytes in recording data appendix');
  const payloads = requireObject(envelope.payloads, 'payload inventory');
  if (Object.keys(payloads).sort().join('|') !== ['afar.events', 'afar.files', 'afar.frames'].join('|')) throw new Error('Unexpected payload inventory');
  for (const name of TRACK_NAMES.slice(1)) {
    const descriptor = requireObject(payloads[name], `payload ${name}`), data = samples.get(name);
    const expectedMime = name === 'afar.files' ? 'application/x-tar' : 'application/yaml';
    if (descriptor.bytes !== data.length || descriptor.sha256 !== digest(data) || descriptor.mimeType !== expectedMime) throw new Error(`Payload checksum/length/type mismatch: ${name}`);
  }
  const source = Buffer.from(buffer.subarray(0, original.bytes));
  source.write('moov', original.moovOffset + 4, 4, 'latin1');
  if (digest(source) !== original.sha256) throw new Error('Restored source-video checksum mismatch');
  const sourceInfo = validateSourceMovie(source);
  validateMoviePreservation(buffer, source, info, sourceInfo, dataTracks, envelope);
  return { envelope, info, samples, source };
}
// Large recordings are read by range. Only movie headers and YAML are buffered.
const COPY_BYTES = 1024 * 1024;
async function readRange(handle, offset, bytes, limit = COPY_BYTES) {
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(bytes) || bytes < 0 || bytes > limit) throw new Error('Requested recording range exceeds its limit');
  const data = Buffer.alloc(bytes);
  let cursor = 0;
  while (cursor < bytes) {
    const { bytesRead } = await handle.read(data, cursor, bytes - cursor, offset + cursor);
    if (!bytesRead) throw new Error('Recording was truncated while reading');
    cursor += bytesRead;
  }
  return data;
}
async function scanBoxes(handle, start, end) {
  const result = [];
  let cursor = start;
  while (cursor < end) {
    if (end - cursor < 8) throw new Error('Invalid MP4: truncated box header');
    const raw = await readRange(handle, cursor, 8);
    let size = raw.readUInt32BE(0), header = 8;
    if (!size) throw new Error('Invalid MP4: open-ended boxes are not supported');
    if (size === 1) {
      if (end - cursor < 16) throw new Error('Invalid MP4: truncated extended box header');
      const extended = (await readRange(handle, cursor + 8, 8)).readBigUInt64BE();
      if (extended > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Invalid MP4: oversized box');
      size = Number(extended); header = 16;
    }
    if (size < header || size > end - cursor) throw new Error('Invalid MP4: box exceeds containing bytes');
    result.push({ type: raw.toString('latin1', 4), start: cursor, size, header, payload: cursor + header, end: cursor + size });
    if (result.length > 16384) throw new Error('Invalid MP4: too many boxes');
    cursor += size;
  }
  return result;
}
async function transfer(handle, offset, bytes, output = null, patch = null) {
  const hash = createHash('sha256');
  const chunk = Buffer.alloc(Math.min(COPY_BYTES, bytes));
  let cursor = 0;
  while (cursor < bytes) {
    const wanted = Math.min(chunk.length, bytes - cursor);
    const { bytesRead } = await handle.read(chunk, 0, wanted, offset + cursor);
    if (!bytesRead) throw new Error('Recording was truncated while copying');
    const data = chunk.subarray(0, bytesRead);
    if (patch) {
      const left = Math.max(offset + cursor, patch.offset), right = Math.min(offset + cursor + bytesRead, patch.offset + patch.data.length);
      if (right > left) patch.data.copy(data, left - offset - cursor, left - patch.offset, right - patch.offset);
    }
    hash.update(data);
    if (output) {
      let written = 0;
      while (written < data.length) {
        const { bytesWritten } = await output.write(data, written, data.length - written);
        if (!bytesWritten) throw new Error('Output stopped accepting recording bytes');
        written += bytesWritten;
      }
    }
    cursor += bytesRead;
  }
  return hash.digest('hex');
}
async function assertZeroRange(handle, offset, bytes) {
  let cursor = 0;
  while (cursor < bytes) {
    const data = await readRange(handle, offset + cursor, Math.min(COPY_BYTES, bytes - cursor));
    if (!data.every(byte => byte === 0)) throw new Error('Invalid ustar padding or terminator');
    cursor += data.length;
  }
}
function sourcePatch(envelope) {
  return { offset: envelope.sourceVideo.moovOffset + 4, data: Buffer.from('moov') };
}
function trackWithPlaybackTransform(track, affine) {
  if (!Array.isArray(affine) || affine.length !== 6 || !affine.every(Number.isFinite)) throw new Error('Invalid playback transform');
  const root = boxes(track);
  if (root.length !== 1 || root[0].type !== 'trak') throw new Error('Invalid playback video track');
  const headers = boxes(track, root[0].payload, root[0].end).filter(atom => atom.type === 'tkhd');
  if (headers.length !== 1) throw new Error('Invalid playback video track header');
  const header = headers[0], version = track[header.payload];
  if (version > 1) throw new Error('Unsupported playback video track header');
  const matrixOffset = header.payload + (version === 1 ? 52 : 40);
  if (matrixOffset + 44 > header.end) throw new Error('Truncated playback video track header');
  const width = track.readUInt32BE(matrixOffset + 36) / 65536;
  const height = track.readUInt32BE(matrixOffset + 40) / 65536;
  const rotations = [[1, 0, 0, 1, 0, 0], [0, 1, -1, 0, height, 0],
    [-1, 0, 0, -1, width, height], [0, -1, 1, 0, 0, width]];
  if (!rotations.some(candidate => candidate.every((value, index) => affine[index] === value))) throw new Error('Playback transform must be a canonical quarter-turn rotation');
  const fixed = value => {
    const scaled = value * 65536;
    if (!Number.isInteger(scaled) || scaled < -0x80000000 || scaled > 0x7fffffff) throw new Error('Playback transform exceeds signed 16.16 range');
    return scaled;
  };
  const matrix = [fixed(affine[0]), fixed(affine[1]), 0, fixed(affine[2]), fixed(affine[3]), 0,
    fixed(affine[4]), fixed(affine[5]), 0x40000000];
  const result = Buffer.from(track);
  matrix.forEach((value, index) => result.writeInt32BE(value, matrixOffset + index * 4));
  return result;
}
function validateMoviePreservation(movie, sourceMovie, info, sourceInfo, dataTracks, envelope) {
  const originalChildren = info.parts.filter(atom => !dataTracks.some(track => track.trak.start === atom.start));
  if (originalChildren.length !== sourceInfo.parts.length) throw new Error('Replacement movie changes the original movie structure');
  const hasPlaybackTransform = Object.hasOwn(envelope, 'playbackTransform');
  for (let index = 0; index < originalChildren.length; index++) {
    const actual = originalChildren[index], expected = sourceInfo.parts[index];
    if (actual.type !== expected.type || actual.size !== expected.size) throw new Error('Replacement movie changes an original movie box');
    const actualBytes = Buffer.from(movie.subarray(actual.start, actual.end));
    let expectedBytes = sourceMovie.subarray(expected.start, expected.end);
    if (actual.type === 'trak' && hasPlaybackTransform) expectedBytes = trackWithPlaybackTransform(expectedBytes, envelope.playbackTransform);
    if (actual.type === 'mvhd') {
      const nextID = Math.max(...sourceInfo.tracks.map(track => track.id)) + TRACK_NAMES.length + 1;
      if (actualBytes.readUInt32BE(actualBytes.length - 4) !== nextID) throw new Error('Invalid replacement movie next track ID');
      expectedBytes.copy(actualBytes, actualBytes.length - 4, expectedBytes.length - 4);
    }
    if (!actualBytes.equals(expectedBytes)) throw new Error('Replacement movie does not preserve original video/metadata boxes');
  }
}
async function inspectHandle(handle, size) {
  const top = await scanBoxes(handle, 0, size);
  if (!top.length || top[0].type !== 'ftyp' || top.some(atom => ['moof', 'mfra', 'sidx', 'styp'].includes(atom.type))) throw new Error('Invalid or unsupported MP4 layout');
  const movies = top.filter(atom => atom.type === 'moov');
  if (movies.length !== 1) throw new Error('Expected exactly one MP4 movie box');
  const movie = await readRange(handle, movies[0].start, movies[0].size, LIMITS.maxMoovBytes);
  const info = { top, ...parseMovieBox(movie, size) };
  const dataTracks = info.tracks.filter(track => TRACK_NAMES.includes(track.name));
  if (dataTracks.length !== 4 || new Set(dataTracks.map(track => track.name)).size !== 4 || info.tracks.length !== 5) throw new Error('Expected one video track and four unique afar data tracks');
  const tracks = new Map(dataTracks.map(track => [track.name, track]));
  const samples = new Map();
  for (const name of TRACK_NAMES) {
    const track = tracks.get(name);
    if ((name === 'afar.files' && (track.sampleEntry !== 'urim' || track.uri !== FILES_URI)) || (name !== 'afar.files' && (track.sampleEntry !== 'mett' || track.mimeType !== 'application/yaml'))) throw new Error(`Invalid sample description for ${name}`);
    if (name !== 'afar.files') samples.set(name, await readRange(handle, track.offset, track.bytes, LIMITS.maxYAMLBytes));
  }
  const envelope = parseYAML(samples.get('afar.session'));
  if (envelope.format !== FORMAT || envelope.version !== 1 || typeof envelope.draft !== 'boolean') throw new Error('Unsupported recording envelope format/version');
  requireObject(envelope.session, 'original manifest');
  if (envelope.session.finalized !== true) throw new Error('Embedded source session is not finalized');
  const original = requireObject(envelope.sourceVideo, 'sourceVideo');
  if (!Number.isSafeInteger(original.bytes) || original.bytes <= 0 || original.bytes > LIMITS.maxSourceVideoBytes || original.bytes >= size || !Number.isSafeInteger(original.moovOffset) || original.moovOffset < 0 || !/^[a-f0-9]{64}$/u.test(original.sha256)) throw new Error('Invalid source-video restoration metadata');
  const prefix = await scanBoxes(handle, 0, original.bytes);
  const oldMovie = prefix.find(atom => atom.start === original.moovOffset && atom.type === 'free');
  if (!oldMovie || prefix[0]?.type !== 'ftyp' || !prefix.some(atom => atom.type === 'mdat')) throw new Error('Invalid original movie prefix');
  const appendices = top.filter(atom => atom.start >= original.bytes);
  if (appendices.length !== 2 || appendices[0].type !== 'mdat' || appendices[0].start !== original.bytes || appendices[1].type !== 'moov' || appendices[1].end !== size) throw new Error('Invalid appended recording layout');
  let cursor = appendices[0].payload;
  for (const name of TRACK_NAMES) {
    const track = tracks.get(name);
    if (track.offset !== cursor) throw new Error('Data sample overlaps or is outside the recording appendix');
    cursor += track.bytes;
  }
  if (cursor !== appendices[0].end) throw new Error('Unexpected bytes in recording data appendix');
  const payloads = requireObject(envelope.payloads, 'payload inventory');
  if (Object.keys(payloads).sort().join('|') !== ['afar.events', 'afar.files', 'afar.frames'].join('|')) throw new Error('Unexpected payload inventory');
  for (const name of TRACK_NAMES.slice(1)) {
    const descriptor = requireObject(payloads[name], `payload ${name}`), track = tracks.get(name);
    const expectedMime = name === 'afar.files' ? 'application/x-tar' : 'application/yaml';
    const sha256 = samples.has(name) ? digest(samples.get(name)) : await transfer(handle, track.offset, track.bytes);
    if (descriptor.bytes !== track.bytes || descriptor.sha256 !== sha256 || descriptor.mimeType !== expectedMime) throw new Error(`Payload checksum/length/type mismatch: ${name}`);
  }
  if (await transfer(handle, 0, original.bytes, null, sourcePatch(envelope)) !== original.sha256) throw new Error('Restored source-video checksum mismatch');
  const sourceMovie = await readRange(handle, oldMovie.start, oldMovie.size, LIMITS.maxMoovBytes);
  sourceMovie.write('moov', 4, 4, 'latin1');
  const sourceInfo = parseMovieBox(sourceMovie, original.bytes);
  if (sourceInfo.tracks.length !== 1 || sourceInfo.tracks[0].handler !== 'vide' || !['avc1', 'avc3'].includes(sourceInfo.tracks[0].sampleEntry)) throw new Error('Original movie must have one H.264 track');
  validateMoviePreservation(movie, sourceMovie, info, sourceInfo, dataTracks, envelope);
  return { handle, size, envelope, info, tracks, samples };
}
async function withRecording(recordingPath, operation) {
  const handle = await fs.open(recordingPath, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await handle.stat();
    if (!before.isFile() || !Number.isSafeInteger(before.size) || before.size > LIMITS.maxRecordingBytes) throw new Error('Recording is not a regular file below the 4 GiB limit');
    const assertUnchanged = async () => {
      const after = await handle.stat();
      if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw new Error('Recording changed while reading');
    };
    const loaded = await inspectHandle(handle, before.size);
    loaded.assertUnchanged = assertUnchanged;
    const result = await operation(loaded);
    await assertUnchanged();
    return result;
  } finally { await handle.close(); }
}

/** Inspect and verify all track and source-video hashes using bounded file reads. */
export async function inspectRecording(recordingPath) {
  return withRecording(recordingPath, async loaded => publicInfo(loaded));
}

/** Dump the exact bytes from a named data track, streaming binary assets. */
export async function extractTrack(recordingPath, handlerName, outputPath) {
  if (!TRACK_NAMES.includes(handlerName)) throw new Error(`Unknown recording data track: ${handlerName}`);
  const destination = path.resolve(outputPath);
  await assertAbsent(destination);
  return withRecording(recordingPath, async loaded => {
    const parent = path.dirname(destination);
    if (!(await fs.stat(parent)).isDirectory()) throw new Error('Output parent must be an existing directory');
    const temporary = path.join(parent, `.${path.basename(destination)}.${randomUUID()}.tmp`);
    const output = await fs.open(temporary, 'wx', 0o600);
    try {
      const track = loaded.tracks.get(handlerName);
      const sha256 = await transfer(loaded.handle, track.offset, track.bytes, output);
      await output.close();
      const descriptor = loaded.envelope.payloads[handlerName];
      if (descriptor && sha256 !== descriptor.sha256) throw new Error('Track changed while copying');
      await loaded.assertUnchanged();
      await fs.link(temporary, destination);
      return { outputPath: destination, bytes: track.bytes, sha256 };
    } finally { await output.close().catch(() => {}); await fs.rm(temporary, { force: true }); }
  });
}

function tarString(header, at, bytes) {
  const field = header.subarray(at, at + bytes), nul = field.indexOf(0);
  return decoder.decode(nul < 0 ? field : field.subarray(0, nul));
}
function tarOctal(header, at, bytes) {
  const value = tarString(header, at, bytes).trim();
  if (!/^[0-7]+$/u.test(value)) throw new Error('Invalid ustar numeric field');
  const number = Number.parseInt(value, 8);
  if (!Number.isSafeInteger(number)) throw new Error('Invalid ustar numeric range');
  return number;
}
async function tarEntries(loaded) {
  const track = loaded.tracks.get('afar.files'), entries = [], names = new Map(), implicitDirectories = new Set();
  if (track.bytes % 512) throw new Error('Truncated ustar archive');
  let cursor = track.offset;
  const end = track.offset + track.bytes;
  while (cursor < end) {
    const header = await readRange(loaded.handle, cursor, 512);
    if (header.every(byte => byte === 0)) {
      if (end - cursor < 1024) throw new Error('Invalid ustar terminator');
      await assertZeroRange(loaded.handle, cursor, end - cursor);
      return entries;
    }
    const actual = header.reduce((sum, byte, index) => sum + (index >= 148 && index < 156 ? 32 : byte), 0);
    if (tarOctal(header, 148, 8) !== actual) throw new Error('ustar checksum mismatch');
    if (!header.subarray(257, 263).equals(Buffer.from('ustar\0')) || tarString(header, 263, 2) !== '00') throw new Error('Unsupported archive extension; expected POSIX ustar');
    const prefix = tarString(header, 345, 155), name = tarString(header, 0, 100);
    const logical = safePath(prefix ? `${prefix}/${name}` : name), key = pathKey(logical);
    const kind = header[156], directory = kind === 53, bytes = tarOctal(header, 124, 12);
    if (![0, 48, 53].includes(kind) || tarString(header, 157, 100)) throw new Error('Archive links, devices and extensions are not supported');
    if (directory && bytes) throw new Error('Directory archive entry contains data');
    if (key === 'rgb.mp4' || names.has(key) || (!directory && implicitDirectories.has(key))) throw new Error('Duplicate/colliding payload path or archived video');
    const parts = logical.split('/');
    for (let index = 1; index < parts.length; index++) {
      const ancestor = pathKey(parts.slice(0, index).join('/'));
      if (names.has(ancestor) && !names.get(ancestor).directory) throw new Error('File is also used as a payload directory');
      implicitDirectories.add(ancestor);
    }
    const offset = cursor + 512, padded = Math.ceil(bytes / 512) * 512;
    if (padded > end - offset) throw new Error('Truncated ustar file');
    await assertZeroRange(loaded.handle, offset + bytes, padded - bytes);
    const entry = { path: logical, directory, offset, bytes };
    entries.push(entry); names.set(key, entry);
    if (entries.length > LIMITS.maxEntries) throw new Error('Too many payload files/directories');
    cursor = offset + padded;
  }
  throw new Error('Missing ustar terminator');
}
function verifyRestoredInventory(manifest, files) {
  if (manifest.fileInventory === undefined) return;
  if (!Array.isArray(manifest.fileInventory) || manifest.fileInventory.length > LIMITS.maxEntries) throw new Error('Invalid source file inventory');
  const seen = new Set();
  for (const entry of manifest.fileInventory) {
    requireObject(entry, 'inventory entry'); safePath(entry.path);
    const key = pathKey(entry.path);
    if (seen.has(key)) throw new Error('Duplicate source inventory entry');
    seen.add(key);
    const restored = files.get(entry.path);
    if (!restored || restored.bytes !== entry.bytes || restored.sha256 !== entry.sha256) throw new Error(`Source inventory checksum/length mismatch: ${entry.path}`);
  }
}

/** Restore source files and the original movie without buffering movie/TAR payloads. */
export async function unpackRecording(recordingPath, outputDirectory) {
  const destination = path.resolve(outputDirectory);
  await assertAbsent(destination);
  return withRecording(recordingPath, async loaded => {
    const entries = await tarEntries(loaded);
    const sourceFiles = new Map(entries.filter(entry => !entry.directory).map(entry => [entry.path, entry]));
    const readMetadata = async name => {
      const entry = required(sourceFiles, name);
      return readRange(loaded.handle, entry.offset, entry.bytes, LIMITS.maxMetadataBytes);
    };
    const originalManifest = json(await readMetadata('manifest.json'), 'manifest.json');
    if (!isDeepStrictEqual(originalManifest, loaded.envelope.session)) throw new Error('Original manifest does not match session envelope');
    for (const [name, sourcePath] of [['afar.frames', 'frames.jsonl'], ['afar.events', 'events.jsonl']]) {
      if (!isDeepStrictEqual(jsonLines(await readMetadata(sourcePath), sourcePath), parseYAML(loaded.samples.get(name), true))) throw new Error(`YAML records do not match original ${sourcePath}`);
    }
    const parent = path.dirname(destination);
    if (!(await fs.stat(parent)).isDirectory()) throw new Error('Output parent must be an existing directory');
    const temporary = await fs.mkdtemp(path.join(parent, '.ar-recording-'));
    try {
      const restored = new Map();
      for (const entry of entries) {
        const location = path.join(temporary, entry.path);
        if (entry.directory) await fs.mkdir(location, { recursive: true });
        else {
          await fs.mkdir(path.dirname(location), { recursive: true });
          const output = await fs.open(location, 'wx', 0o600);
          try {
            const sha256 = await transfer(loaded.handle, entry.offset, entry.bytes, output);
            restored.set(entry.path, { bytes: entry.bytes, sha256 });
          } finally { await output.close(); }
        }
      }
      const output = await fs.open(path.join(temporary, 'rgb.mp4'), 'wx', 0o600);
      let sourceHash;
      try { sourceHash = await transfer(loaded.handle, 0, loaded.envelope.sourceVideo.bytes, output, sourcePatch(loaded.envelope)); }
      finally { await output.close(); }
      if (sourceHash !== loaded.envelope.sourceVideo.sha256) throw new Error('Source movie changed while copying');
      restored.set('rgb.mp4', { bytes: loaded.envelope.sourceVideo.bytes, sha256: sourceHash });
      verifyRestoredInventory(originalManifest, restored);
      await loaded.assertUnchanged();
      await assertAbsent(destination);
      await fs.rename(temporary, destination);
      return { outputDirectory: destination, files: restored.size, sourceVideo: loaded.envelope.sourceVideo, session: originalManifest };
    } catch (error) { await fs.rm(temporary, { recursive: true, force: true }); throw error; }
  });
}
