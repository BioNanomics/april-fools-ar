// Small, uncompressed POSIX ustar subset. No links, PAX extensions or devices.
const decoder = new TextDecoder('utf-8', { fatal: true });
const BLOCK = 512;
export function safePath(value) {
  if (typeof value !== 'string' || !value || value.includes('\\') || value.includes(':') || /[\x00-\x1f\x7f]/u.test(value)) throw new Error('Unsafe payload path');
  const parts = value.split('/');
  if (parts.some(part => !part || part === '.' || part === '..')) throw new Error(`Unsafe payload path: ${value}`);
  if (Buffer.byteLength(value) > 256) throw new Error('Payload path exceeds draft ustar limit');
  return value;
}
export function pathKey(value) { return safePath(value).normalize('NFC').toLowerCase(); }
function writeOctal(header, at, width, value) {
  const text = value.toString(8);
  if (text.length > width - 1) throw new Error('Payload exceeds ustar numeric range');
  header.write(text.padStart(width - 1, '0') + '\0', at, width, 'ascii');
}
function splitName(value) {
  if (Buffer.byteLength(value) <= 100) return [value, ''];
  const boundaries = [...value.matchAll(/\//gu)].map(match => match.index).reverse();
  for (const boundary of boundaries) {
    const prefix = value.slice(0, boundary), name = value.slice(boundary + 1);
    if (Buffer.byteLength(prefix) <= 155 && Buffer.byteLength(name) <= 100) return [name, prefix];
  }
  throw new Error('Payload path cannot fit draft ustar header');
}
function string(header, at, width) {
  const field = header.subarray(at, at + width);
  const nul = field.indexOf(0);
  return decoder.decode(nul < 0 ? field : field.subarray(0, nul));
}
function octal(header, at, width) {
  const text = string(header, at, width).trim();
  if (!/^[0-7]+$/u.test(text)) throw new Error('Invalid ustar numeric field');
  const value = Number.parseInt(text, 8);
  if (!Number.isSafeInteger(value)) throw new Error('Invalid ustar numeric range');
  return value;
}
function validateEntries(entries, maxFiles) {
  if (entries.length > maxFiles) throw new Error('Too many payload files/directories');
  const names = new Map();
  for (const entry of entries) {
    safePath(entry.path);
    const key = pathKey(entry.path);
    if (key === 'rgb.mp4') throw new Error('Video must not be duplicated in the sidecar archive');
    if (names.has(key)) throw new Error(`Duplicate/colliding payload path: ${entry.path}`);
    names.set(key, entry);
  }
  for (const entry of entries) {
    const components = entry.path.split('/');
    for (let n = 1; n < components.length; n++) {
      const ancestor = names.get(pathKey(components.slice(0, n).join('/')));
      if (ancestor && !ancestor.directory) throw new Error('File is also used as a payload directory');
    }
  }
}

export function writeTar(entries, maxFiles) {
  validateEntries(entries, maxFiles);
  const parts = [];
  for (const entry of entries) {
    const header = Buffer.alloc(BLOCK);
    const [name, prefix] = splitName(entry.path);
    header.write(name, 0, 100, 'utf8');
    writeOctal(header, 100, 8, entry.directory ? 0o755 : 0o644);
    writeOctal(header, 108, 8, 0); writeOctal(header, 116, 8, 0);
    const bytes = entry.directory ? 0 : entry.data.length;
    writeOctal(header, 124, 12, bytes); writeOctal(header, 136, 12, 0);
    header.fill(32, 148, 156); header[156] = entry.directory ? 53 : 48;
    header.write('ustar\0', 257, 6, 'ascii'); header.write('00', 263, 2, 'ascii');
    header.write(prefix, 345, 155, 'utf8');
    const checksum = header.reduce((a, b) => a + b, 0);
    header.write(checksum.toString(8).padStart(6, '0') + '\0 ', 148, 8, 'ascii');
    parts.push(header);
    if (bytes) parts.push(entry.data, Buffer.alloc((BLOCK - bytes % BLOCK) % BLOCK));
  }
  parts.push(Buffer.alloc(BLOCK * 2));
  return Buffer.concat(parts);
}

export function readTar(buffer, maxFiles) {
  if (buffer.length % BLOCK !== 0) throw new Error('Truncated ustar archive');
  const entries = [];
  let cursor = 0, ended = false;
  while (cursor < buffer.length) {
    const header = buffer.subarray(cursor, cursor + BLOCK);
    if (header.every(value => value === 0)) {
      if (buffer.length - cursor < BLOCK * 2 || !buffer.subarray(cursor).every(value => value === 0)) throw new Error('Invalid ustar terminator');
      ended = true; break;
    }
    const expected = octal(header, 148, 8);
    const actual = header.reduce((sum, value, index) => sum + (index >= 148 && index < 156 ? 32 : value), 0);
    if (expected !== actual) throw new Error('ustar checksum mismatch');
    if (!header.subarray(257, 263).equals(Buffer.from('ustar\0')) || string(header, 263, 2) !== '00') throw new Error('Unsupported archive extension; expected POSIX ustar');
    const prefix = string(header, 345, 155), name = string(header, 0, 100);
    const path = prefix ? `${prefix}/${name}` : name;
    const kind = header[156];
    if (![0, 48, 53].includes(kind) || string(header, 157, 100)) throw new Error('Archive links, devices and extensions are not supported');
    const bytes = octal(header, 124, 12), directory = kind === 53;
    if (directory && bytes !== 0) throw new Error('Directory archive entry contains data');
    const start = cursor + BLOCK;
    if (bytes > buffer.length - start) throw new Error('Truncated ustar file');
    const padded = Math.ceil(bytes / BLOCK) * BLOCK;
    if (start + padded > buffer.length || !buffer.subarray(start + bytes, start + padded).every(v => v === 0)) throw new Error('Invalid ustar file padding');
    entries.push({ path, directory, data: buffer.subarray(start, start + bytes) });
    if (entries.length > maxFiles) throw new Error('Too many payload files/directories');
    cursor = start + padded;
  }
  if (!ended) throw new Error('Missing ustar terminator');
  validateEntries(entries, maxFiles);
  return entries;
}
