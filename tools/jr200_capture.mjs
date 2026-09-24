// SPDX-License-Identifier: BSD-3-Clause
// Record frames and PCM of one ROM-less synthetic replay with the locked WASM
// bundle. Output: raw 320x224 RGBA frames, mono s16le PCM and a JSON summary.
// Used only to make gallery videos; the runner remains the test authority.
import {createHash} from 'node:crypto';
import {closeSync, openSync, readFileSync, writeFileSync, writeSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

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
if (request.mode !== 'synthetic-injection') die('only synthetic replays can be recorded');
const artifact = readFileSync(request.artifact.path);
if (createHash('sha256').update(artifact).digest('hex') !== request.artifact.sha256) {
  die('artifact digest mismatch');
}
const imported = await import(pathToFileURL(path.join(args.bundle, 'jr200_codec.mjs')).href);
const module = await imported.default();
if (module._jr200_system_api_version() !== Number(args['system-api'])) die('API mismatch', 5);

module._jr200_system_clear();
const trampoline = request.return_address - 6;
for (const segment of request.segments) {
  const bytes = Buffer.from(segment.bytes, 'hex');
  bytes.forEach((value, offset) => module._jr200_system_poke(segment.address + offset, value));
}
[0x8e, (trampoline - 1) >> 8, (trampoline - 1) & 0xff, 0xbd,
  request.entry_address >> 8, request.entry_address & 0xff]
  .forEach((value, offset) => module._jr200_system_poke(trampoline + offset, value));
module._jr200_system_poke(0xfffe, trampoline >> 8);
module._jr200_system_poke(0xffff, trampoline & 0xff);
module._jr200_system_cpu_reset();
module._jr200_system_debug_add_breakpoint(request.return_address);

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
let nextFrame = 0;
let eventIndex = 0;
const events = request.replay;

function drainPcm() {
  for (;;) {
    const count = module._jr200_system_pcm_drain(4096);
    if (count === 0) return;
    const start = module._jr200_system_pcm_buffer_ptr();
    const bytes = Buffer.from(module.HEAPU8.slice(start, start + count * 2));
    writeSync(pcmOut, bytes);
    pcmHash.update(bytes);
    pcmFrames += count;
  }
}

function captureFrame() {
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
    drainPcm();
    captureFrame();
    nextFrame += frameCycles;
  }
  while (eventIndex < events.length && events[eventIndex].cycle <= elapsed) {
    const event = events[eventIndex++];
    if (event.kind === 'key') module._jr200_system_set_key(event.code, event.pressed ? 1 : 0);
  }
  let target = Math.min(nextFrame, request.max_cycles);
  if (eventIndex < events.length) target = Math.min(target, events[eventIndex].cycle);
  const budget = Math.max(1, target - elapsed);
  const ran = module._jr200_system_run(budget);
  if (ran === 0 && module._jr200_system_debug_field(1) === 0) die('no progress', 7);
  elapsed += ran;
}
drainPcm();
captureFrame();
closeSync(framesOut);
closeSync(pcmOut);
writeFileSync(args.summary, `${JSON.stringify({
  frames, fps, frame_cycles: frameCycles, elapsed_cycles: elapsed,
  pcm_frames: pcmFrames, pcm_rate: module._jr200_system_pcm_sample_rate(),
  frames_sha256: frameHash.digest('hex'), pcm_sha256: pcmHash.digest('hex'),
  stopped_at_return: module._jr200_system_debug_field(1) !== 0,
}, null, 2)}\n`);
