// SPDX-License-Identifier: BSD-3-Clause
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {deflateSync} from 'node:zlib';

const RUNNER_VERSION = '0.3.0';
const CONTRACT_VERSION = 1;
const MAX_CYCLES = 250_000_000;
const MAX_OBSERVATION = 4096;

function die(message, code = 2) {
  process.stderr.write(`Runner failed: ${message}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  if (argv.length === 1 && argv[0] === '--version') {
    process.stdout.write(`jr200-wasm-runner ${RUNNER_VERSION} contract ${CONTRACT_VERSION}\n`);
    process.exit(0);
  }
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!['--bundle', '--request', '--result', '--screenshot', '--system-api'].includes(key) ||
        value === undefined || value.length === 0 || result[key.slice(2)] !== undefined) {
      die('invalid command line');
    }
    result[key.slice(2)] = value;
  }
  if (![4, 5].includes(Object.keys(result).length) ||
      !result.bundle || !result.request || !result.result || !result['system-api']) {
    die('bundle, request, result, and system API are required');
  }
  return result;
}

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    die('request JSON cannot be read');
  }
}

function integer(value, minimum, maximum, label) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    die(`invalid ${label}`);
  }
  return value;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function uint32(value) {
  const output = Buffer.alloc(4);
  output.writeUInt32BE(value >>> 0);
  return output;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; ++bit) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(kind, payload) {
  const label = Buffer.from(kind, 'ascii');
  const body = Buffer.from(payload);
  return Buffer.concat([uint32(body.length), label, body,
    uint32(crc32(Buffer.concat([label, body])))]);
}

function encodePngRgba(width, height, pixels) {
  if (pixels.length !== width * height * 4) die('invalid framebuffer size', 7);
  const stride = width * 4;
  const rows = [];
  for (let offset = 0; offset < pixels.length; offset += stride) {
    rows.push(Buffer.from([0]), Buffer.from(pixels.subarray(offset, offset + stride)));
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 6, 0, 0, 0], 8);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', deflateSync(Buffer.concat(rows), {level: 9})),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function bytesFromHex(value, label) {
  if (typeof value !== 'string' || value.length % 2 !== 0 || !/^[0-9a-f]*$/.test(value)) {
    die(`invalid ${label}`);
  }
  return Uint8Array.from(Buffer.from(value, 'hex'));
}

function validateRequest(value) {
  const fields = ['schema_version', 'runner_contract_version', 'profile', 'mode',
    'artifact', 'entry_address', 'max_cycles', 'return_address', 'segments',
    'replay', 'observations', 'breakpoints', 'assets'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join() !== fields.sort().join() ||
      value.schema_version !== 1 || value.runner_contract_version !== CONTRACT_VERSION ||
      typeof value.profile !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(value.profile) ||
      !['synthetic-injection', 'rom-cassette'].includes(value.mode)) {
    die('invalid request contract');
  }
  if (!value.artifact || Object.keys(value.artifact).sort().join() !== 'path,sha256' ||
      typeof value.artifact.path !== 'string' ||
      !/^[0-9a-f]{64}$/.test(value.artifact.sha256)) {
    die('invalid artifact contract');
  }
  integer(value.entry_address, 0, 0xffff, 'entry address');
  integer(value.max_cycles, 1, MAX_CYCLES, 'cycle limit');
  integer(value.return_address, 0, 0xffff, 'return address');
  if (!Array.isArray(value.segments) || !Array.isArray(value.replay) ||
      !Array.isArray(value.observations) || !Array.isArray(value.breakpoints) ||
      !value.assets || typeof value.assets !== 'object' || Array.isArray(value.assets)) {
    die('invalid request arrays or assets');
  }
  let previousCycle = -1;
  for (const event of value.replay) {
    if (!event || typeof event !== 'object' ||
        !['key', 'nmi', 'joystick'].includes(event.kind)) {
      die('invalid replay event');
    }
    integer(event.cycle, 0, value.max_cycles, 'replay cycle');
    if (event.cycle < previousCycle) die('replay events are not sorted');
    previousCycle = event.cycle;
    if (event.kind === 'key') {
      integer(event.code, 0, 0xff, 'key code');
      if (typeof event.pressed !== 'boolean') die('invalid key state');
    } else if (event.kind === 'joystick') {
      integer(event.player, 0, 1, 'joystick player');
      integer(event.state, 0, 0xff, 'joystick state');
    }
  }
  for (const observation of value.observations) {
    if (!observation || typeof observation !== 'object' ||
        typeof observation.name !== 'string' || !/^[a-z][a-z0-9_-]{0,31}$/.test(observation.name)) {
      die('invalid observation');
    }
    integer(observation.address, 0, 0xffff, 'observation address');
    integer(observation.length, 1, MAX_OBSERVATION, 'observation length');
    if (observation.address + observation.length > 0x10000) die('observation leaves memory');
  }
  for (const address of value.breakpoints) integer(address, 0, 0xffff, 'breakpoint');
  return value;
}

function validateSegments(request) {
  if (request.mode !== 'synthetic-injection') {
    if (request.segments.length !== 0) die('ROM cassette mode cannot inject segments');
    return [];
  }
  if (request.segments.length === 0) die('synthetic mode requires segments');
  const segments = request.segments.map(segment => {
    if (!segment || typeof segment !== 'object' ||
        Object.keys(segment).sort().join() !== 'address,bytes') die('invalid segment');
    const address = integer(segment.address, 0, 0xffff, 'segment address');
    const bytes = bytesFromHex(segment.bytes, 'segment bytes');
    if (bytes.length === 0 || address + bytes.length > 0x10000) die('segment leaves memory');
    return {address, bytes};
  });
  const occupied = new Set();
  for (const segment of segments) {
    for (let offset = 0; offset < segment.bytes.length; ++offset) {
      const address = segment.address + offset;
      if (occupied.has(address)) die('overlapping segments');
      occupied.add(address);
    }
  }
  return segments;
}

function registers(module) {
  const names = ['pc', 'sp', 'x', 'a', 'b', 'cc', 'waiting'];
  return Object.fromEntries(names.map((name, field) =>
    [name, module._jr200_system_cpu_register(field)]));
}

function applyEvent(module, event) {
  if (event.kind === 'nmi') {
    module._jr200_system_pulse_nmi();
  } else if (event.kind === 'joystick') {
    if (typeof module._jr200_system_set_joystick !== 'function' ||
        module._jr200_system_set_joystick(event.player, event.state) !== 1) {
      die('joystick replay requires emulator system API 8', 5);
    }
  } else {
    module._jr200_system_set_key(event.code, event.pressed ? 1 : 0);
  }
}

function runReplay(module, request) {
  let elapsed = 0;
  for (const event of request.replay) {
    if (module._jr200_system_debug_field(1) !== 0) break;
    const budget = event.cycle - elapsed;
    if (budget > 0) elapsed += module._jr200_system_run(budget);
    if (elapsed < event.cycle && module._jr200_system_debug_field(1) === 0) {
      die('runner made no progress', 7);
    }
    if (module._jr200_system_debug_field(1) !== 0) break;
    applyEvent(module, event);
  }
  if (elapsed < request.max_cycles && module._jr200_system_debug_field(1) === 0) {
    elapsed += module._jr200_system_run(request.max_cycles - elapsed);
  }
  return elapsed;
}

const args = parseArgs(process.argv.slice(2));
const request = validateRequest(readJson(args.request));
const artifact = readFileSync(request.artifact.path);
if (sha256(artifact) !== request.artifact.sha256) die('artifact digest mismatch');
const segments = validateSegments(request);

let module;
try {
  const imported = await import(pathToFileURL(path.join(args.bundle, 'jr200_codec.mjs')).href);
  module = await imported.default();
} catch {
  die('emulator module cannot be loaded', 5);
}
const expectedSystemApi = integer(Number(args['system-api']), 1, 0xffff, 'system API');
if (module._jr200_codec_api_version() !== 1 ||
    module._jr200_system_api_version() !== expectedSystemApi) {
  die('emulator API version mismatch', 5);
}
module.HEAPU8.set(artifact, module._jr200_input_ptr());
if (module._jr200_inspect(artifact.length, 0) !== 0) die('emulator rejected CJR input');

module._jr200_system_clear();
if (request.mode === 'synthetic-injection') {
  if (Object.keys(request.assets).length !== 0) die('synthetic mode cannot use ROM assets');
  if (request.return_address < 0x0808 || request.return_address > 0x7fff) {
    die('synthetic return address cannot host a caller trampoline');
  }
  const trampolineAddress = request.return_address - 6;
  const stackTop = trampolineAddress - 1;
  if (segments.some(segment =>
    segment.address <= request.return_address - 1 &&
    segment.address + segment.bytes.length - 1 >= trampolineAddress)) {
    die('synthetic caller trampoline overlaps an injected segment');
  }
  for (const segment of segments) {
    for (let offset = 0; offset < segment.bytes.length; ++offset) {
      module._jr200_system_poke(segment.address + offset, segment.bytes[offset]);
    }
  }
  const trampoline = [0x8e, stackTop >> 8, stackTop & 0xff,
    0xbd, request.entry_address >> 8, request.entry_address & 0xff];
  trampoline.forEach((value, offset) =>
    module._jr200_system_poke(trampolineAddress + offset, value));
  module._jr200_system_poke(0xfffe, trampolineAddress >> 8);
  module._jr200_system_poke(0xffff, trampolineAddress & 0xff);
  module._jr200_system_cpu_reset();
} else {
  if (Object.keys(request.assets).sort().join() !== 'font_path,rom_path') {
    die('ROM cassette mode requires ROM and font assets', 3);
  }
  let rom;
  let font;
  try {
    rom = readFileSync(request.assets.rom_path);
    font = readFileSync(request.assets.font_path);
  } catch {
    die('local ROM or font asset is missing', 3);
  }
  if (rom.length !== module._jr200_system_rom_capacity() ||
      font.length !== module._jr200_system_font_capacity()) {
    die('local ROM or font size is incompatible', 5);
  }
  module.HEAPU8.set(rom, module._jr200_system_rom_ptr());
  module.HEAPU8.set(font, module._jr200_system_font_ptr());
  if (module._jr200_system_boot(rom.length, font.length) !== 1) {
    die('emulator rejected local ROM or font', 5);
  }
  module.HEAPU8.set(artifact, module._jr200_system_tape_input_ptr());
  if (module._jr200_system_tape_mount(artifact.length) !== 0) {
    die('emulator rejected cassette input');
  }
}

const uniqueBreakpoints = new Set(request.breakpoints);
if (request.mode === 'synthetic-injection') uniqueBreakpoints.add(request.return_address);
for (const address of uniqueBreakpoints) {
  if (module._jr200_system_debug_add_breakpoint(address) !== 1) {
    die('breakpoint capacity exceeded');
  }
}
const elapsed = runReplay(module, request);
module._jr200_system_render();
const memory = Object.fromEntries(request.observations.map(observation => {
  const bytes = Uint8Array.from({length: observation.length}, (_, offset) =>
    module._jr200_system_peek(observation.address + offset));
  return [observation.name, Buffer.from(bytes).toString('hex')];
}));
const framebufferStart = module._jr200_system_framebuffer_ptr();
const framebufferPixels = 320 * 224;
const framebufferView = new DataView(
  module.HEAPU8.buffer, framebufferStart, framebufferPixels * 4);
const framebuffer = Buffer.alloc(framebufferPixels * 4);
for (let index = 0; index < framebufferPixels; ++index) {
  const color = framebufferView.getUint32(index * 4, true);
  const offset = index * 4;
  framebuffer[offset] = (color >>> 16) & 0xff;
  framebuffer[offset + 1] = (color >>> 8) & 0xff;
  framebuffer[offset + 2] = color & 0xff;
  framebuffer[offset + 3] = (color >>> 24) & 0xff;
}
if (args.screenshot) {
  if (request.mode !== 'synthetic-injection') {
    die('screenshots are restricted to synthetic mode');
  }
  writeFileSync(args.screenshot, encodePngRgba(320, 224, framebuffer), {flag: 'wx'});
}
const pcmAvailable = module._jr200_system_field(4);
const pcmCount = module._jr200_system_pcm_drain(
  Math.min(pcmAvailable, module._jr200_system_pcm_capacity()));
const pcmStart = module._jr200_system_pcm_buffer_ptr();
const pcmBytes = module.HEAPU8.slice(pcmStart, pcmStart + pcmCount * 2);
const pcmView = new DataView(pcmBytes.buffer, pcmBytes.byteOffset, pcmBytes.byteLength);
let pcmNonzero = 0;
let pcmPeak = 0;
for (let offset = 0; offset < pcmBytes.byteLength; offset += 2) {
  const sample = pcmView.getInt16(offset, true);
  if (sample !== 0) pcmNonzero += 1;
  pcmPeak = Math.max(pcmPeak, Math.abs(sample));
}
const stopCode = module._jr200_system_debug_field(1);
const stopNames = {0: 'cycle-limit', 1: 'breakpoint', 2: 'read-watchpoint',
  3: 'write-watchpoint', 4: 'step'};
const result = {
  schema_version: 1,
  runner_contract_version: CONTRACT_VERSION,
  runner_version: RUNNER_VERSION,
  status: 'passed',
  profile: request.profile,
  mode: request.mode,
  evidence: request.mode === 'synthetic-injection' ? 'emulator' : 'emulator_with_local_rom',
  artifact_sha256: request.artifact.sha256,
  elapsed_cycles: elapsed,
  stop: {
    reason: stopNames[stopCode] ?? 'unknown',
    address: module._jr200_system_debug_field(2),
  },
  registers: registers(module),
  memory,
  framebuffer_sha256: sha256(framebuffer),
  pcm: {
    frames: pcmCount,
    nonzero_frames: pcmNonzero,
    peak: pcmPeak,
    sha256: sha256(pcmBytes),
    dropped_low: module._jr200_system_pcm_dropped(0),
    dropped_high: module._jr200_system_pcm_dropped(1),
  },
  cassette: {
    state: module._jr200_system_tape_field(0),
    mode: module._jr200_system_tape_field(1),
    remote: module._jr200_system_tape_field(2) !== 0,
    read_started: module._jr200_system_tape_field(12) !== 0,
  },
  hardware: 'not_run',
};
writeFileSync(args.result, `${JSON.stringify(result, null, 2)}\n`, {encoding: 'utf8', flag: 'wx'});
process.stdout.write(`Runner result: passed (${request.mode}, ${elapsed} cycles)\n`);
