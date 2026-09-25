// SPDX-License-Identifier: BSD-3-Clause
// Exercise the pinned distribution's joystick ABI with synthetic ROM and FONT.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

if (process.argv.length !== 3) {
  throw new Error('Usage: node tools/runner_joystick_smoke.mjs <jr200_codec.mjs>');
}
const { default: createCodec } = await import(pathToFileURL(resolve(process.argv[2])).href);
const machine = await createCodec();
assert.equal(machine._jr200_system_api_version(), 9);
machine._jr200_system_clear();

const rom = new Uint8Array(machine.HEAPU8.buffer, machine._jr200_system_rom_ptr(), 16384);
const font = new Uint8Array(machine.HEAPU8.buffer, machine._jr200_system_font_ptr(), 2048);
rom.fill(0);
font.fill(0x5a);
rom.set([0x86, 0x2a, 0xb7, 0xc1, 0x00, 0x20, 0xfe], 8192);
rom.set([0xe0, 0x00], 16382);
assert.equal(machine._jr200_system_boot(rom.length, font.length), 1);
machine._jr200_system_write(0xc81e, 1);

function pulseControl(bit) {
  machine._jr200_system_write(0xc803, bit);
  machine._jr200_system_write(0xc803, 0);
  machine._jr200_system_write(0xc803, bit);
  machine._jr200_system_tick(100);
}
function clearKeyIrq() {
  machine._jr200_system_read(0xc81c);
}

pulseControl(0x02);
assert.equal(machine._jr200_system_peek(0xc801), 0x5a);
clearKeyIrq();
for (let index = 0; index < 2048; index += 1) {
  pulseControl(0x01);
  clearKeyIrq();
}
assert.equal(machine._jr200_system_field(5), 1);
assert.equal(machine._jr200_system_set_joystick(0, 0xea), 1);
assert.equal(machine._jr200_system_set_joystick(1, 0xd5), 1);
assert.equal(machine._jr200_system_set_joystick(2, 0xff), 0);
assert.equal(machine._jr200_system_set_joystick(0, 0x100), 0);

pulseControl(0x02);
clearKeyIrq();
pulseControl(0x01);
assert.equal(machine._jr200_system_peek(0xc801), 0xea);
clearKeyIrq();
pulseControl(0x01);
assert.equal(machine._jr200_system_peek(0xc801), 0xd5);
clearKeyIrq();

console.log('Packaged runner joystick ABI: passed (synthetic ROM/FONT, 1P EA, 2P D5)');
