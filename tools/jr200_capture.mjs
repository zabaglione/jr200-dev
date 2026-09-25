// SPDX-License-Identifier: BSD-3-Clause
// Record game-only frames and PCM from a tested replay with the locked WASM bundle.
// ROM-backed clips verify installed game glyphs and omit boot/MLOAD/BASIC frames.
// Rendered frames are otherwise unchanged, including any ROM/FONT glyphs.
import {createHash} from 'node:crypto';
import {closeSync, openSync, readFileSync, writeFileSync, writeSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyAuthoredScreen} from './authored_capture.mjs';
import {applyReplayEvent, prepareReplaySystem} from './replay_system.mjs';

function die(message, code = 2) {
  process.stderr.write(`Capture failed: ${message}\n`);
  process.exit(code);
}

const args = {};
for (let index = 2; index < process.argv.length; index += 2) {
  args[process.argv[index].replace(/^--/, '')] = process.argv[index + 1];
}
for (const key of ['bundle', 'request', 'frames', 'pcm', 'summary', 'system-api', 'fps']) {
  if (!args[key]) die(`--${key} is required`);
}
const request = JSON.parse(readFileSync(args.request, 'utf8'));
if (!['synthetic-injection', 'rom-cassette'].includes(request.mode)) die('invalid replay mode');
const startCycle = Number(args['start-cycle'] ?? 0);
if (!Number.isInteger(startCycle) || startCycle < 0 ||
    startCycle >= request.max_cycles) die('invalid capture start cycle');
if (request.mode === 'rom-cassette' &&
    (!args['self-font-data'] || startCycle === 0)) {
  die('ROM recording requires authored font source and game-only start cycle');
}
if (request.mode === 'synthetic-injection' && args['self-font-data']) {
  die('synthetic recording cannot use authored font source');
}
const artifact = readFileSync(request.artifact.path);
if (createHash('sha256').update(artifact).digest('hex') !== request.artifact.sha256) {
  die('artifact digest mismatch');
}
const imported = await import(pathToFileURL(path.join(args.bundle, 'jr200_codec.mjs')).href);
const module = await imported.default();
if (module._jr200_codec_api_version() !== 1 ||
    module._jr200_system_api_version() !== Number(args['system-api'])) die('API mismatch', 5);
const segments = request.segments.map(segment => ({
  address: segment.address,
  bytes: Buffer.from(segment.bytes, 'hex'),
}));
try {
  prepareReplaySystem(module, request, artifact, segments);
} catch (error) {
  die(error.message, 5);
}

const clock = 1339285;
const fps = Number(args.fps);
const frameCycles = Math.round(clock / fps);
const framesOut = openSync(args.frames, 'w');
const pcmOut = openSync(args.pcm, 'w');
const frameHash = createHash('sha256');
const pcmHash = createHash('sha256');
const pixels = 320 * 224;
const rgba = Buffer.alloc(pixels * 4);
let elapsed = 0;
let frames = 0;
let pcmFrames = 0;
let nextFrame = startCycle;
let eventIndex = 0;
const events = request.replay;

function drainPcm(record) {
  for (;;) {
    const count = module._jr200_system_pcm_drain(4096);
    if (count === 0) return;
    const start = module._jr200_system_pcm_buffer_ptr();
    const bytes = Buffer.from(module.HEAPU8.slice(start, start + count * 2));
    if (record) {
      writeSync(pcmOut, bytes);
      pcmHash.update(bytes);
      pcmFrames += count;
    }
  }
}

function captureFrame() {
  if (request.mode === 'rom-cassette') {
    try {
      verifyAuthoredScreen(module, args['self-font-data']);
    } catch (error) {
      die(`ROM capture refused at cycle ${elapsed}, frame ${frames}: ${error.message}`);
    }
  }
  module._jr200_system_render();
  const view = new DataView(module.HEAPU8.buffer, module._jr200_system_framebuffer_ptr(),
    pixels * 4);
  for (let index = 0; index < pixels; ++index) {
    const color = view.getUint32(index * 4, true);
    rgba[index * 4] = (color >>> 16) & 0xff;
    rgba[index * 4 + 1] = (color >>> 8) & 0xff;
    rgba[index * 4 + 2] = color & 0xff;
    rgba[index * 4 + 3] = 0xff;
  }
  writeSync(framesOut, rgba);
  frameHash.update(rgba);
  frames += 1;
}

while (elapsed < request.max_cycles && module._jr200_system_debug_field(1) === 0) {
  if (elapsed >= nextFrame) {
    drainPcm(frames > 0);
    captureFrame();
    nextFrame += frameCycles;
  }
  while (eventIndex < events.length && events[eventIndex].cycle <= elapsed) {
    const event = events[eventIndex++];
    try {
      applyReplayEvent(module, event);
    } catch (error) {
      die(error.message);
    }
  }
  let target = Math.min(nextFrame, request.max_cycles);
  if (eventIndex < events.length) target = Math.min(target, events[eventIndex].cycle);
  const budget = Math.max(1, target - elapsed);
  const ran = module._jr200_system_run(budget);
  if (ran === 0 && module._jr200_system_debug_field(1) === 0) die('no progress', 7);
  elapsed += ran;
}
drainPcm(frames > 0);
captureFrame();
closeSync(framesOut);
closeSync(pcmOut);
writeFileSync(args.summary, `${JSON.stringify({
  frames, fps, frame_cycles: frameCycles, elapsed_cycles: elapsed,
  mode: request.mode, start_cycle: startCycle,
  pcm_frames: pcmFrames, pcm_rate: module._jr200_system_pcm_sample_rate(),
  frames_sha256: frameHash.digest('hex'), pcm_sha256: pcmHash.digest('hex'),
  stopped_at_return: module._jr200_system_debug_field(1) !== 0,
}, null, 2)}\n`);
