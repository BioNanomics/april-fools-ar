// Deliberately small ISO BMFF subset for the draft, nonfragmented capture format.
export const FILES_URI = 'urn:april-fools-ar:recording:1:files:tar';
export const TRACK_NAMES = ['afar.session', 'afar.frames', 'afar.events', 'afar.files'];
export const MAX_ASSET_SAMPLE_BYTES = 1024 * 1024;

function fail(message) { throw new Error(`Invalid or unsupported MP4: ${message}`); }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; }
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16BE(n); return b; }
function u64(n) { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b; }
export function box(type, ...parts) {
  const payload = Buffer.concat(parts);
  const size = payload.length + 8;
  if (size > 0xffffffff) fail('draft writer does not support boxes above 4 GiB');
  return Buffer.concat([u32(size), Buffer.from(type, 'latin1'), payload]);
}
function full(type, payload, flags = 0) { return box(type, u32(flags), payload); }

export function boxes(buffer, start = 0, end = buffer.length) {
  const result = [];
  let cursor = start;
  while (cursor < end) {
    if (end - cursor < 8) fail('truncated box header');
    let size = buffer.readUInt32BE(cursor);
    let header = 8;
    if (size === 0) fail('open-ended boxes are not supported');
    if (size === 1) {
      if (end - cursor < 16) fail('truncated extended box header');
      const value = buffer.readBigUInt64BE(cursor + 8);
      if (value > BigInt(Number.MAX_SAFE_INTEGER)) fail('box size exceeds integer range');
      size = Number(value); header = 16;
    }
    if (size < header || size > end - cursor) fail('box size exceeds its containing bytes');
    const type = buffer.toString('latin1', cursor + 4, cursor + 8);
    result.push({ type, start: cursor, size, header, payload: cursor + header, end: cursor + size });
    if (result.length > 16384) fail('too many boxes');
    cursor += size;
  }
  return result;
}

function children(buffer, parent) { return boxes(buffer, parent.payload, parent.end); }
function one(list, type) {
  const matches = list.filter(value => value.type === type);
  if (matches.length !== 1) fail(`expected exactly one ${type} box`);
  return matches[0];
}
function requireBytes(atom, offset, length) {
  if (offset < atom.payload || offset + length > atom.end) fail(`truncated ${atom.type}`);
}
function version(buffer, atom) {
  requireBytes(atom, atom.payload, 4);
  const v = buffer[atom.payload];
  if (v > 1) fail(`unsupported ${atom.type} version`);
  return v;
}
function exactFullZero(buffer, atom) {
  requireBytes(atom, atom.payload, 4);
  if (buffer.readUInt32BE(atom.payload) !== 0) fail(`unsupported ${atom.type} flags or version`);
}
function integer64(buffer, at) {
  const n = buffer.readBigUInt64BE(at);
  if (n > BigInt(Number.MAX_SAFE_INTEGER)) fail('duration exceeds integer range');
  return Number(n);
}
function cstring(buffer, at, end) {
  const nul = buffer.indexOf(0, at);
  if (nul < at || nul >= end) fail('unterminated string');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  return [decoder.decode(buffer.subarray(at, nul)), nul + 1];
}

export function movieInfo(buffer) {
  const top = boxes(buffer);
  if (!top.length || top[0].type !== 'ftyp') fail('expected a leading ftyp box');
  if (top.some(b => ['moof', 'mfra', 'sidx', 'styp'].includes(b.type))) fail('fragmented/indexed source is not supported');
  const moov = one(top, 'moov');
  return { top, ...parseMovie(buffer, moov, buffer.length) };
}

/** Parse a bounded, standalone moov while validating absolute sample offsets against its file. */
export function parseMovieBox(buffer, fileSize) {
  const top = boxes(buffer);
  if (top.length !== 1 || top[0].type !== 'moov') fail('expected a single movie box');
  return parseMovie(buffer, top[0], fileSize);
}

function parseMovie(buffer, moov, fileSize) {
  const parts = children(buffer, moov);
  if (parts.some(b => ['mvex', 'cmov'].includes(b.type))) fail('fragmented or compressed movie is not supported');
  const mvhd = one(parts, 'mvhd');
  const v = version(buffer, mvhd);
  const timeOffset = mvhd.payload + (v ? 20 : 12);
  requireBytes(mvhd, timeOffset, v ? 12 : 8);
  requireBytes(mvhd, mvhd.end - 4, 4);
  const timescale = buffer.readUInt32BE(timeOffset);
  const duration = v ? integer64(buffer, timeOffset + 4) : buffer.readUInt32BE(timeOffset + 4);
  if (!timescale || !duration || duration > 0xffffffff) fail('draft requires a nonzero movie duration within uint32');
  const tracks = parts.filter(b => b.type === 'trak').map(trak => parseTrack(buffer, trak, fileSize));
  if (!tracks.length || tracks.length > 32) fail('invalid track count');
  if (new Set(tracks.map(t => t.id)).size !== tracks.length) fail('duplicate track IDs');
  return { moov, parts, mvhd, timescale, duration, tracks };
}

function parseTrack(buffer, trak, fileSize) {
  const parts = children(buffer, trak);
  const tkhd = one(parts, 'tkhd');
  const v = version(buffer, tkhd);
  const idOffset = tkhd.payload + (v ? 20 : 12);
  requireBytes(tkhd, idOffset, 4);
  const id = buffer.readUInt32BE(idOffset);
  if (!id) fail('zero track ID');
  const mdia = one(parts, 'mdia');
  const media = children(buffer, mdia);
  const hdlr = one(media, 'hdlr');
  requireBytes(hdlr, hdlr.payload, 24);
  const handler = buffer.toString('latin1', hdlr.payload + 8, hdlr.payload + 12);
  let name = '';
  if (hdlr.end > hdlr.payload + 24) [name] = cstring(buffer, hdlr.payload + 24, hdlr.end);
  const minf = one(media, 'minf');
  const minfParts = children(buffer, minf);
  const dinf = one(minfParts, 'dinf');
  const dref = one(children(buffer, dinf), 'dref');
  exactFullZero(buffer, dref); requireBytes(dref, dref.payload + 4, 4);
  const refs = boxes(buffer, dref.payload + 8, dref.end);
  if (buffer.readUInt32BE(dref.payload + 4) !== 1 || refs.length !== 1 || refs[0].type !== 'url ') fail('external data references are not supported');
  const reference = refs[0]; requireBytes(reference, reference.payload, 4);
  if (buffer.readUInt32BE(reference.payload) !== 1 || reference.size !== reference.header + 4) fail('external data references are not supported');
  const stbl = one(minfParts, 'stbl');
  const table = children(buffer, stbl);
  const stsd = one(table, 'stsd');
  exactFullZero(buffer, stsd); requireBytes(stsd, stsd.payload + 4, 4);
  const entries = boxes(buffer, stsd.payload + 8, stsd.end);
  if (buffer.readUInt32BE(stsd.payload + 4) !== 1 || entries.length !== 1) fail('multiple sample descriptions are not supported');
  const entry = entries[0]; requireBytes(entry, entry.payload, 8);
  if (buffer.readUInt16BE(entry.payload + 6) !== 1) fail('invalid data reference');
  let mimeType, uri;
  if (entry.type === 'mett') {
    let encoding, at;
    [encoding, at] = cstring(buffer, entry.payload + 8, entry.end);
    [mimeType, at] = cstring(buffer, at, entry.end);
    if (encoding || at !== entry.end) fail('encoded/extended mett sample is not supported');
  } else if (entry.type === 'urim') {
    const label = one(boxes(buffer, entry.payload + 8, entry.end), 'uri ');
    exactFullZero(buffer, label);
    let at; [uri, at] = cstring(buffer, label.payload + 4, label.end);
    if (at !== label.end) fail('invalid URI label');
    if (uri === FILES_URI) mimeType = 'application/x-tar';
  }
  const result = { id, name, handler, sampleEntry: entry.type, mimeType, uri, trak };
  if (TRACK_NAMES.includes(name)) {
    if (handler !== 'meta') fail('recording tracks must have a meta handler');
    for (const type of ['stsz', 'stsc', 'stts']) exactFullZero(buffer, one(table, type));
    const stsz = one(table, 'stsz'); requireBytes(stsz, stsz.payload, 12);
    const sampleCount = buffer.readUInt32BE(stsz.payload + 8);
    if (buffer.readUInt32BE(stsz.payload + 4) !== 0 || sampleCount < 1 || sampleCount > (name === 'afar.files' ? 4096 : 1) || stsz.end !== stsz.payload + 12 + sampleCount * 4) fail('unsupported explicit-size data sample table');
    let bytes = 0, maxSampleBytes = 0;
    for (let index = 0; index < sampleCount; index++) {
      const size = buffer.readUInt32BE(stsz.payload + 12 + index * 4);
      if (!size || (sampleCount > 1 && size > MAX_ASSET_SAMPLE_BYTES)) fail('invalid or oversized data sample');
      bytes += size; maxSampleBytes = Math.max(maxSampleBytes, size);
    }
    const stsc = one(table, 'stsc'); requireBytes(stsc, stsc.payload, 20);
    if (stsc.end !== stsc.payload + 20 || [4, 8, 16].some(n => buffer.readUInt32BE(stsc.payload + n) !== 1) || buffer.readUInt32BE(stsc.payload + 12) !== sampleCount) fail('unsupported data chunk layout');
    const stts = one(table, 'stts'); requireBytes(stts, stts.payload, 8);
    const timingEntries = buffer.readUInt32BE(stts.payload + 4);
    if (!timingEntries || timingEntries > sampleCount || stts.end !== stts.payload + 8 + timingEntries * 8) fail('unsupported data sample timing');
    let timedSamples = 0;
    for (let index = 0; index < timingEntries; index++) {
      const count = buffer.readUInt32BE(stts.payload + 8 + index * 8), delta = buffer.readUInt32BE(stts.payload + 12 + index * 8);
      if (!count || !delta) fail('unsupported data sample timing');
      timedSamples += count;
    }
    if (timedSamples !== sampleCount) fail('data sample timing count does not match sample sizes');
    const offsets = table.filter(b => b.type === 'stco' || b.type === 'co64');
    if (offsets.length !== 1) fail('expected one chunk offset table');
    const offsetBox = offsets[0]; exactFullZero(buffer, offsetBox);
    const width = offsetBox.type === 'co64' ? 8 : 4;
    requireBytes(offsetBox, offsetBox.payload, 8 + width);
    if (offsetBox.end !== offsetBox.payload + 8 + width || buffer.readUInt32BE(offsetBox.payload + 4) !== 1) fail('unsupported data chunk count');
    const offset = width === 8 ? integer64(buffer, offsetBox.payload + 8) : buffer.readUInt32BE(offsetBox.payload + 8);
    if (!bytes || offset > fileSize - bytes) fail('data sample is empty or outside the file');
    return { ...result, bytes, offset, sampleCount, maxSampleBytes };
  }
  return result;
}

export function validateSourceMovie(buffer) {
  const info = movieInfo(buffer);
  if (!info.top.some(b => b.type === 'mdat')) fail('missing media data');
  if (info.tracks.length !== 1 || info.tracks[0].handler !== 'vide' || !['avc1', 'avc3'].includes(info.tracks[0].sampleEntry)) fail('draft source must contain exactly one H.264 video track');
  return info;
}

export function metadataTrack(id, name, payloadBytes, offset, duration, timescale) {
  const sampleCount = name === 'afar.files' ? Math.ceil(payloadBytes / MAX_ASSET_SAMPLE_BYTES) : 1;
  if (!sampleCount || sampleCount > 4096) fail('unsupported data sample count');
  let mediaTimescale = timescale * sampleCount, delta = duration;
  if (mediaTimescale > 0xffffffff) {
    let a = mediaTimescale, b = delta;
    while (b) [a, b] = [b, a % b];
    mediaTimescale /= a; delta /= a;
    if (mediaTimescale > 0xffffffff) fail('metadata time scale exceeds uint32');
  }
  const mediaDuration = delta * sampleCount;
  const matrix = Buffer.concat([u32(0x10000), u32(0), u32(0), u32(0), u32(0x10000), u32(0), u32(0), u32(0), u32(0x40000000)]);
  const tkhd = full('tkhd', Buffer.concat([u32(0), u32(0), u32(id), u32(0), u32(duration), Buffer.alloc(16), matrix, u32(0), u32(0)]), 2);
  const mdhd = mediaDuration > 0xffffffff
    ? full('mdhd', Buffer.concat([u64(0), u64(0), u32(mediaTimescale), u64(mediaDuration), u16(0x55c4), u16(0)]), 0x1000000)
    : full('mdhd', Buffer.concat([u32(0), u32(0), u32(mediaTimescale), u32(mediaDuration), u16(0x55c4), u16(0)]));
  const hdlr = full('hdlr', Buffer.concat([u32(0), Buffer.from('meta'), Buffer.alloc(12), Buffer.from(name + '\0')]));
  const dinf = box('dinf', full('dref', Buffer.concat([u32(1), full('url ', Buffer.alloc(0), 1)])));
  const entry = name === 'afar.files'
    ? box('urim', Buffer.alloc(6), u16(1), full('uri ', Buffer.from(FILES_URI + '\0')))
    : box('mett', Buffer.alloc(6), u16(1), Buffer.from('\0application/yaml\0'));
  const stsd = full('stsd', Buffer.concat([u32(1), entry]));
  const stts = full('stts', Buffer.concat([u32(1), u32(sampleCount), u32(delta)]));
  const stsc = full('stsc', Buffer.concat([u32(1), u32(1), u32(sampleCount), u32(1)]));
  const sizes = Array.from({ length: sampleCount }, (_, index) => u32(Math.min(name === 'afar.files' ? MAX_ASSET_SAMPLE_BYTES : payloadBytes, payloadBytes - index * MAX_ASSET_SAMPLE_BYTES)));
  const stsz = full('stsz', Buffer.concat([u32(0), u32(sampleCount), ...sizes]));
  const offsets = offset <= 0xffffffff ? full('stco', Buffer.concat([u32(1), u32(offset)])) : full('co64', Buffer.concat([u32(1), u64(offset)]));
  const stbl = box('stbl', stsd, stts, stsc, stsz, offsets);
  return box('trak', tkhd, box('mdia', mdhd, hdlr, box('minf', full('nmhd', Buffer.alloc(0)), dinf, stbl)));
}

export function appendRecording(source, namedPayloads) {
  const info = validateSourceMovie(source);
  const prefix = Buffer.from(source);
  prefix.write('free', info.moov.start + 4, 4, 'latin1');
  let offset = source.length + 8;
  const maxID = Math.max(...info.tracks.map(t => t.id));
  if (maxID > 0xfffffff9) fail('track ID space exhausted');
  const tracks = namedPayloads.map(({ name, payload }, index) => {
    const result = metadataTrack(maxID + index + 1, name, payload.length, offset, info.duration, info.timescale);
    offset += payload.length;
    return result;
  });
  const originalChildren = info.parts.map(child => {
    const raw = Buffer.from(source.subarray(child.start, child.end));
    if (child.type === 'mvhd') raw.writeUInt32BE(maxID + tracks.length + 1, raw.length - 4);
    return raw;
  });
  return Buffer.concat([prefix, box('mdat', ...namedPayloads.map(p => p.payload)), box('moov', ...originalChildren, ...tracks)]);
}
