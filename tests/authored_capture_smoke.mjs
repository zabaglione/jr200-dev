// SPDX-License-Identifier: BSD-3-Clause
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {verifyAuthoredScreen} from '../tools/authored_capture.mjs';

const source = new URL('../sdk/font_data.inc', import.meta.url);
const rows = [...readFileSync(source, 'utf8').matchAll(/^\s*\.db\s+([^;\n]+)/gm)];
assert.equal(rows.length, 64);
const glyphs = rows.flatMap(row => row[1].split(',').map(value => Number(value.trim())));
const memory = new Uint8Array(0x10000);
memory.set(glyphs, 0xd100);
memory.fill(0x20, 0xc100, 0xc100 + 768);
memory.fill(0x07, 0xc500, 0xc500 + 768);
const emulator = {_jr200_system_peek: address => memory[address]};

verifyAuthoredScreen(emulator, source);
memory[0xd101] ^= 1;
assert.throws(() => verifyAuthoredScreen(emulator, source),
  /active glyphs differ from authored font/);
memory[0xd101] ^= 1;
memory[0xc100] = 0x10;
assert.throws(() => verifyAuthoredScreen(emulator, source),
  /non-authored standard glyph/);
memory[0xc500] = 0x40;
verifyAuthoredScreen(emulator, source);
assert.throws(() => verifyAuthoredScreen(emulator, new URL('missing.inc', import.meta.url)),
  /authored font source cannot be read/);
process.stdout.write('authored capture guard: OK\n');
