# SPDX-License-Identifier: BSD-3-Clause
import json
import re
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from game_project import operation, validate_project
from png_rgba import decode_rgba


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/relic-dive'


class RelicDiveContractTests(unittest.TestCase):
    def test_acceptance_profiles_separate_normal_load_from_synthetic_play(self):
        expectations = json.loads(
            (PROJECT / 'tests/expectations.json').read_text(encoding='utf-8'))
        profiles = {item['profile']: item for item in expectations['runtime']['profiles']}
        for name in ('synthetic-title', 'synthetic-gameplay', 'synthetic-combat',
                     'synthetic-menu', 'synthetic-menu-wait', 'synthetic-suspend',
                     'synthetic-resume', 'synthetic-return', 'synthetic-audio',
                     'synthetic-stairs-arrival', 'synthetic-floor-transition',
                     'synthetic-defeat', 'synthetic-retry'):
            self.assertEqual(profiles[name]['mode'], 'synthetic-injection')
        for name in ('local-rom-scroll', 'local-rom-basic-return',
                     'local-rom-screen-restore'):
            self.assertEqual(profiles[name]['mode'], 'rom-cassette')
            self.assertIn('mload\r', [event.get('text')
                                      for event in profiles[name]['replay']])
        returned = profiles['local-rom-basic-return']
        self.assertEqual(returned['expect']['memory']['basic-return-proof'], 'a5')
        self.assertEqual(returned['expect']['pc'], '0x4a68')
        restored = profiles['local-rom-screen-restore']
        self.assertEqual(restored['expect']['pc'], '0x1274')
        self.assertEqual(profiles['local-rom-goal']['expect']['memory']['kills'], '01')
        for sector, marker in (('top', '41'), ('middle', '42'), ('bottom', '43')):
            self.assertEqual(restored['expect']['memory'][f'saved-{sector}'], marker)
            self.assertEqual(restored['expect']['memory'][f'restored-{sector}'], marker)
        self.assertEqual(profiles['synthetic-stairs-arrival']['expect']['memory']['view-y'], '00')
        self.assertEqual(profiles['synthetic-floor-transition']['expect']['memory']['gen-floor'], '01')
        self.assertEqual(profiles['synthetic-defeat']['expect']['memory']['state'][:2], '08')
        self.assertEqual(profiles['synthetic-retry']['expect']['memory']['turns'], '0000')

    def test_project_contract_and_mit_license(self):
        spec = validate_project(PROJECT)
        self.assertEqual(spec.config['id'], 'relic-dive')
        self.assertEqual(spec.metadata['license'], 'MIT')
        license_text = (PROJECT / 'LICENSE').read_text(encoding='utf-8')
        self.assertIn('MIT License', license_text)
        self.assertIn('JR-800 Web Emulator contributors', license_text)

    def test_upstream_revision_and_generated_source_are_recorded(self):
        provenance = (PROJECT / 'UPSTREAM.md').read_text(encoding='utf-8')
        self.assertIn('9a3921c4371d84c55fc468879dbed2f00fe42960', provenance)
        self.assertIn('games/relic_dive', provenance)
        generated = (PROJECT / 'src/generated.inc').read_text(encoding='utf-8')
        self.assertIn('SPDX-License-Identifier: MIT', generated)

    def test_every_assembly_source_declares_mit(self):
        for path in sorted((PROJECT / 'src').iterdir()):
            if path.suffix not in ('.asm', '.inc'):
                continue
            with self.subTest(path=path.name):
                self.assertTrue(
                    path.read_text(encoding='utf-8').startswith(
                        '; SPDX-License-Identifier: MIT\n'))

    def test_runtime_storage_stays_in_jr200_user_ram(self):
        constants_text = (PROJECT / 'src/constants.inc').read_text(encoding='utf-8')
        constants = {
            name: int(value, 16)
            for name, value in re.findall(
                r'^([A-Z][A-Z0-9_]*):\s+\.equ\s+0x([0-9A-Fa-f]+)$',
                constants_text, re.MULTILINE)
        }
        for name in (
                'FRAMEBUFFER', 'STATE_BEGIN', 'STATE_END', 'SAVE_PCG',
                'SAVE_ATTRIBUTES', 'SAVE_FONT', 'FAST_BEGIN', 'FAST_END', 'ENEMY_START',
                'STACK_TOP'):
            self.assertGreaterEqual(constants[name], 0x5000, name)
            self.assertLessEqual(constants[name], 0x7fff, name)
        self.assertEqual(constants['ENEMY_START'], constants['FLOORS'] + 0x0600)

    def test_port_uses_m6800_and_jr200_interfaces(self):
        sources = [
            path for path in (PROJECT / 'src').iterdir()
            if path.suffix in ('.asm', '.inc')
        ]
        operations = {
            mnemonic
            for path in sources
            for line in path.read_text(encoding='utf-8').splitlines()
            if (mnemonic := operation(line)) is not None
        }
        self.assertNotIn('adx', operations)
        platform = (PROJECT / 'src/platform.asm').read_text(encoding='utf-8')
        self.assertNotRegex(platform, r'\[0xC80[0-9A-F]\]')
        self.assertNotIn('0xCC02', platform)
        self.assertIn('JR200_KEY_IRQ_STATUS', platform)
        self.assertIn('jr_sound_c_start', platform)
        self.assertIn('JR200_SCREEN_ATTRIBUTES', platform)
        self.assertIn('SAVE_SCREEN_CODES', platform)
        self.assertIn('SAVE_FONT', platform)
        self.assertIn('jr_font_data', platform)
        self.assertIn('JR200_SCREEN_CODES + 0x200', platform)
        self.assertNotIn('ADDA 0x91', platform)
        self.assertIn('JR200_SCREEN_CODES - FRAMEBUFFER', platform)
        self.assertIn('STRIKE_ATTR', platform)
        self.assertIn('return_probe:', (PROJECT / 'src/main.asm').read_text(encoding='utf-8'))
        ui = (PROJECT / 'src/ui.asm').read_text(encoding='utf-8')
        self.assertIn('LDX JR200_PCG_BANK1', ui)
        generated = (PROJECT / 'src/generated.inc').read_text(encoding='utf-8')
        self.assertIn('TITLE_SPARK_ADDRESS: .equ 0xC470', generated)
        dungeon = (PROJECT / 'src/dungeon.asm').read_text(encoding='utf-8')
        self.assertNotIn('FLOORS + ENEMY_START', dungeon)
        self.assertIn('FRAMEBUFFER + 11 * 32 + 8', dungeon)
        self.assertNotIn('LDAA 0x31', dungeon)
        self.assertNotIn('LDAA 0x40', dungeon)
        self.assertIn('LDAA JR200_CHAR_SPACE', dungeon)
        self.assertNotIn('LDAA 0x40', ui)
        self.assertIn('LDAA JR200_CHAR_SPACE', ui)
        items = (PROJECT / 'src/items.asm').read_text(encoding='utf-8')
        stairs = items[items.index('STAIRS_ACTION:'):items.index('STAIRS_DONE:')]
        self.assertIn('JSR GENERATE_WORLD', stairs)
        for path in sources:
            text = path.read_text(encoding='utf-8')
            for match in re.finditer(r'\[(0x[0-9A-Fa-f]+)', text):
                with self.subTest(path=path.name, address=match.group(1)):
                    self.assertGreaterEqual(int(match.group(1), 16), 0x5000)

    def test_captures_use_expected_color_groups(self):
        title_colors = self.capture_colors('title.png')
        self.assertTrue({
            (0, 0, 0, 255),
            (0, 255, 255, 255),
            (255, 255, 0, 255),
        }.issubset(title_colors))
        gameplay_colors = self.capture_colors('gameplay.png')
        self.assertTrue({
            (0, 0, 0, 255),
            (0, 0, 255, 255),
            (0, 255, 0, 255),
            (0, 255, 255, 255),
        }.issubset(gameplay_colors))

    def test_present_keeps_wall_attribute_during_both_transitions(self):
        platform = (PROJECT / 'src/platform.asm').read_text(encoding='utf-8')
        present = platform[platform.index('PRESENT:'):platform.index('STRIKE_SCENE:')]
        self.assertNotIn('LDS FRAMEBUFFER - 1', present)
        self.assertIn('LDX FRAMEBUFFER\n    STX [COLOR_CODE_PTR]', present)
        commit = present[present.index('COLOR_STORE:'):present.index('COLOR_CHECK_DONE:')]
        self.assertIn('CMPA WALL_SCREEN_CODE\n    BNE COLOR_ATTRIBUTE_FIRST', commit)
        self.assertIn(
            'LDAA [COLOR_CODE]\n    CMPA WALL_SCREEN_CODE\n'
            '    BEQ COLOR_ATTRIBUTE_FIRST', commit)
        self.assertIn('STAA [X]\n    BRA COLOR_ATTRIBUTE_WRITE', commit)
        attribute_first = commit.index('COLOR_ATTRIBUTE_FIRST:')
        attribute_write = commit.index('LDX [COLOR_ATTR_PTR]', attribute_first)
        character_write = commit.index('LDX [COLOR_SCREEN_PTR]', attribute_write)
        self.assertLess(attribute_write, character_write)

    @staticmethod
    def capture_colors(name):
        width, height, pixels = decode_rgba((PROJECT / 'media' / name).read_bytes())
        if (width, height) != (320, 224):
            raise AssertionError((width, height))
        return {tuple(pixels[offset:offset + 4])
                for offset in range(0, len(pixels), 4)}


if __name__ == '__main__':
    unittest.main()
