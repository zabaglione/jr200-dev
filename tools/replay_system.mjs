// SPDX-License-Identifier: BSD-3-Clause
// Shared CPU setup and input injection for the fixed runner and gallery capture.
import {readFileSync} from 'node:fs';

export function prepareReplaySystem(module, request, artifact, segments) {
  module.HEAPU8.set(artifact, module._jr200_input_ptr());
  if (module._jr200_inspect(artifact.length, 0) !== 0) {
    throw new Error('emulator rejected CJR input');
  }
  module._jr200_system_clear();
  if (request.mode === 'synthetic-injection') {
    if (Object.keys(request.assets).length !== 0) {
      throw new Error('synthetic mode cannot use ROM assets');
    }
    if (request.return_address < 0x0808 || request.return_address > 0x7fff) {
      throw new Error('synthetic return address cannot host a caller trampoline');
    }
    const trampolineAddress = request.return_address - 6;
    const stackTop = trampolineAddress - 1;
    if (segments.some(segment =>
      segment.address <= request.return_address - 1 &&
      segment.address + segment.bytes.length - 1 >= trampolineAddress)) {
      throw new Error('synthetic caller trampoline overlaps an injected segment');
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
  } else if (request.mode === 'rom-cassette') {
    if (Object.keys(request.assets).sort().join() !== 'font_path,rom_path') {
      throw new Error('ROM cassette mode requires ROM and font assets');
    }
    let rom;
    let font;
    try {
      rom = readFileSync(request.assets.rom_path);
      font = readFileSync(request.assets.font_path);
    } catch {
      throw new Error('local ROM or font asset is missing');
    }
    if (rom.length !== module._jr200_system_rom_capacity() ||
        font.length !== module._jr200_system_font_capacity()) {
      throw new Error('local ROM or font size is incompatible');
    }
    module.HEAPU8.set(rom, module._jr200_system_rom_ptr());
    module.HEAPU8.set(font, module._jr200_system_font_ptr());
    if (module._jr200_system_boot(rom.length, font.length) !== 1) {
      throw new Error('emulator rejected local ROM or font');
    }
    module.HEAPU8.set(artifact, module._jr200_system_tape_input_ptr());
    if (module._jr200_system_tape_mount(artifact.length) !== 0) {
      throw new Error('emulator rejected cassette input');
    }
  } else {
    throw new Error('unsupported replay mode');
  }
  const breakpoints = new Set(request.breakpoints);
  if (request.mode === 'synthetic-injection') breakpoints.add(request.return_address);
  for (const address of breakpoints) {
    if (module._jr200_system_debug_add_breakpoint(address) !== 1) {
      throw new Error('breakpoint capacity exceeded');
    }
  }
}

export function applyReplayEvent(module, event) {
  if (event.kind === 'nmi') {
    module._jr200_system_pulse_nmi();
  } else if (event.kind === 'joystick') {
    if (typeof module._jr200_system_set_joystick !== 'function' ||
        module._jr200_system_set_joystick(event.player, event.state) !== 1) {
      throw new Error('joystick replay requires emulator system API 9');
    }
  } else if (event.kind === 'key') {
    module._jr200_system_set_key(event.code, event.pressed ? 1 : 0);
  } else {
    throw new Error('invalid replay event');
  }
}
