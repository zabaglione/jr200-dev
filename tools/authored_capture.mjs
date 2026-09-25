// SPDX-License-Identifier: BSD-3-Clause
// Verify that the game's authored font is installed before ROM-backed capture.
// The visible screen is captured unchanged, including ROM/FONT glyphs.
import {readFileSync} from 'node:fs';

export function verifyAuthoredScreen(module, sourcePath) {
  let source;
  try {
    source = readFileSync(sourcePath, 'utf8');
  } catch {
    throw new Error('authored font source cannot be read');
  }
  const rows = [...source.matchAll(/^\s*\.db\s+([^;\n]+)/gm)];
  if (rows.length !== 64) throw new Error('authored font must contain 64 glyphs');
  const expected = [];
  for (const row of rows) {
    const values = row[1].split(',').map(value => value.trim());
    if (values.length !== 8 || values.some(value => !/^0x[0-9a-f]{2}$/i.test(value))) {
      throw new Error('authored font has an invalid glyph row');
    }
    expected.push(...values.map(value => Number(value)));
  }
  for (let index = 0; index < expected.length; ++index) {
    if (module._jr200_system_peek(0xd100 + index) !== expected[index]) {
      throw new Error('active glyphs differ from authored font');
    }
  }
}
