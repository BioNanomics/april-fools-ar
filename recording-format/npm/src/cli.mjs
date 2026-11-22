#!/usr/bin/env node
import { extractTrack, inspectRecording, packSession, unpackRecording } from './index.mjs';
import YAML from 'yaml';

const usage = `April Fools AR recording tools (Node 22+)

  ar-recording pack SESSION_DIRECTORY OUTPUT.mp4
  ar-recording unpack RECORDING.mp4 NEW_OUTPUT_DIRECTORY
  ar-recording list RECORDING.mp4
  ar-recording extract RECORDING.mp4 afar.session|afar.frames|afar.events|afar.files OUTPUT

All output destinations must be new; their parent directory must already exist.
Packing in Node is limited to 256 MiB source sessions; the app uses its streaming writer.
Inspect/extract/unpack stream recordings below 4 GiB, with bounded YAML/movie headers.
`;

try {
  const [command, ...args] = process.argv.slice(2);
  if (command === '--help' || command === '-h' || !command) {
    process.stdout.write(usage);
  } else {
    let result;
    if (command === 'pack' && args.length === 2) result = await packSession(...args);
    else if (command === 'unpack' && args.length === 2) result = await unpackRecording(...args);
    else if (command === 'list' && args.length === 1) result = await inspectRecording(...args);
    else if (command === 'extract' && args.length === 3) result = await extractTrack(...args);
    else throw new Error(`Invalid command or arguments.\n\n${usage}`);
    process.stdout.write(YAML.stringify(result, { aliasDuplicateObjects: false, lineWidth: 0 }));
  }
} catch (error) {
  process.stderr.write(`ar-recording: ${error.message}\n`);
  process.exitCode = 1;
}
