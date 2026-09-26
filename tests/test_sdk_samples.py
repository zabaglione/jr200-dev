# SPDX-License-Identifier: BSD-3-Clause
import json
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from ci_plan import select, validate_registry
from emulator_runner import validate_expectations
from game_project import address, operation, validate_project


ROOT = Path(__file__).resolve().parents[1]
PROJECTS = {
    'screen-sample': ('samples/screen', ('sdk/jr200.inc', 'sdk/screen.inc')),
    'input-sample': ('samples/input', ('sdk/input.inc', 'sdk/jr200.inc')),
    'joystick-sample': (
        'samples/joystick',
        ('sdk/joystick.inc', 'sdk/jr200.inc', 'sdk/screen.inc'),
    ),
    'sound-sample': (
        'samples/sound',
        ('sdk/jr200.inc', 'sdk/sound.inc', 'sdk/timing.inc'),
    ),
    'chord-sample': (
        'samples/chord',
        ('sdk/audio.inc', 'sdk/audio_notes.inc', 'sdk/frame.inc', 'sdk/jr200.inc'),
    ),
    'game-loop-sample': (
        'samples/game-loop',
        ('sdk/input.inc', 'sdk/jr200.inc', 'sdk/screen.inc',
         'sdk/sound.inc', 'sdk/timing.inc'),
    ),
    'port-fixture-sample': (
        'samples/port-fixture',
        ('sdk/effect.inc', 'sdk/font.inc', 'sdk/font_data.inc', 'sdk/frame.inc', 'sdk/gfx.inc',
         'sdk/jr200.inc', 'sdk/keyrepeat.inc', 'sdk/keys.inc', 'sdk/keyscan.inc',
         'sdk/math.inc', 'sdk/pcg.inc',
         'sdk/port.inc', 'sdk/session.inc', 'sdk/sfx.inc', 'sdk/sound.inc'),
    ),
}
PORT_CONSUMERS = ['brick-pulse', 'circuit-works', 'corner-crown', 'hearth-zero', 'lumen-cross', 'port-fixture-sample']
AUDIO_GAMES = ['auction-house', 'cargo-balance', 'compass-rose', 'fuse-box', 'memory-mosaic', 'mirror-relic', 'number-vault', 'peg-garden', 'shadow-archive', 'stone-balance', 'tidal-nets', 'word-foundry']
KEYS_EXT_GAMES = ['compass-rose', 'mirror-relic']
SFX_GAME_CONSUMERS = [*PORT_CONSUMERS, 'quiet-route', 'seed-merge']
PORT_GAME_CONSUMERS = sorted([*SFX_GAME_CONSUMERS, *AUDIO_GAMES])


class SampleContractTests(unittest.TestCase):
    def test_joystick_instructions_match_default_runner_api(self):
        lock = json.loads((ROOT / 'emulator.lock.json').read_text(encoding='utf-8'))
        readme = (ROOT / 'samples/joystick/README.md').read_text(encoding='utf-8')
        self.assertIn(
            f"system API {lock['build']['system_api_version']}", readme)
        self.assertIn('上記コマンドは既定のlockを使って', readme)
        self.assertNotIn('--lock /absolute/path/to/', readme)

    def test_samples_have_exact_recursive_sdk_dependencies(self):
        for target, (relative, expected_sdk) in PROJECTS.items():
            with self.subTest(target=target):
                spec = validate_project(
                    ROOT / relative, ROOT / 'rules/jr200.json', ROOT)
                self.assertEqual(spec.config['id'], target)
                self.assertEqual(spec.sdk_inputs, expected_sdk)
                self.assertEqual(spec.metadata['verification']['hardware'], 'not_run')

    def test_every_runtime_profile_has_a_valid_bounded_contract(self):
        for target, (relative, _) in PROJECTS.items():
            with self.subTest(target=target):
                project = ROOT / relative
                spec = validate_project(
                    project, ROOT / 'rules/jr200.json', ROOT)
                expectations = json.loads(
                    (project / 'tests/expectations.json').read_text(encoding='utf-8'))
                entry = address(spec.config['entry_address'], 'entry address')
                names = [item['profile']
                         for item in expectations['runtime']['profiles']]
                for name in names:
                    runtime = validate_expectations(expectations, entry, name)
                    self.assertLessEqual(runtime['max_cycles'], 100_000_000)
                    self.assertEqual(runtime['profile'], name)

    def test_sdk_does_not_take_over_stack_or_interrupt_contracts(self):
        forbidden = {'lds', 'cli', 'sei', 'swi', 'rti'}
        # session.inc owns the stack/IRQ mask for a whole game session and
        # gfx.inc borrows S (under that mask) to copy the shadow screen.
        owners = {'sdk/session.inc': {'lds', 'sei'}, 'sdk/gfx.inc': {'lds'}}
        paths = sorted((ROOT / 'sdk').glob('*.inc'))
        paths += sorted((ROOT / 'samples').glob('*/src/*.asm'))
        for path in paths:
            instructions = {item for line in path.read_text(encoding='utf-8').splitlines()
                            if (item := operation(line)) is not None}
            name = path.relative_to(ROOT).as_posix()
            with self.subTest(path=name):
                self.assertFalse(instructions & (forbidden - owners.get(name, set())))

    def test_joystick_sample_uses_rom_font_profile_and_both_ports(self):
        project = ROOT / 'samples/joystick'
        expectations = json.loads(
            (project / 'tests/expectations.json').read_text(encoding='utf-8'))
        profiles = expectations['runtime']['profiles']
        self.assertEqual([item['mode'] for item in profiles], ['rom-cassette'])
        runtime = validate_expectations(expectations, 0x1000)
        joystick = [item for item in runtime['replay']
                    if item['kind'] == 'joystick']
        self.assertEqual(joystick, [
            {'kind': 'joystick', 'cycle': 24000000,
             'player': 0, 'state': 0xea},
            {'kind': 'joystick', 'cycle': 24000000,
             'player': 1, 'state': 0xd5},
        ])

    def test_port_fixture_covers_key_hold_repeat_release_and_exit(self):
        project = ROOT / 'samples/port-fixture'
        expectations = json.loads(
            (project / 'tests/expectations.json').read_text(encoding='utf-8'))
        profiles = {item['profile']: item
                    for item in expectations['runtime']['profiles']}
        self.assertEqual(
            profiles['synthetic-keyrepeat-tap']['expect']['memory']['scan'],
            '0100010101')
        self.assertEqual(
            profiles['synthetic-keyrepeat']['expect']['memory']['scan'],
            '010c011c01')
        for name in ('synthetic-keyrepeat-tap', 'synthetic-keyrepeat'):
            self.assertEqual(
                profiles[name]['expect']['memory']['repeat-state'], '000000')
        for name in ('synthetic-keyrepeat-exit',
                     'synthetic-keyrepeat-ctrl-c-exit'):
            exit_profile = profiles[name]
            self.assertEqual(exit_profile['expect']['stop_reason'], 'breakpoint')
            self.assertEqual(exit_profile['expect']['pc'], '0x7ff0')
            self.assertEqual(exit_profile['expect']['memory']['key-mask'], '00')
        effect = profiles['synthetic-nonblocking-effect']
        self.assertEqual(effect['expect']['memory']['effect'], '011401012d')
        self.assertEqual(effect['expect']['memory']['effect-state'], '0014')
        effect_exit = profiles['synthetic-effect-exit']
        self.assertEqual(effect_exit['expect']['stop_reason'], 'breakpoint')
        self.assertEqual(effect_exit['expect']['memory']['effect-attr'], '00')
        self.assertIn('JSR     jr_keyrepeat_poll',
                      (project / 'src/main.asm').read_text(encoding='utf-8'))

    def test_keyscan_state_is_disjoint_from_copy_and_repeat_state(self):
        def offset(source, symbol):
            match = re.search(
                rf'^{symbol}:\s+\.equ\s+JR_RT \+ (\d+)\s*$',
                source, re.MULTILINE)
            self.assertIsNotNone(match, symbol)
            return int(match.group(1))

        scan = (ROOT / 'sdk/keyscan.inc').read_text(encoding='utf-8')
        repeat = (ROOT / 'sdk/keyrepeat.inc').read_text(encoding='utf-8')
        effect = (ROOT / 'sdk/effect.inc').read_text(encoding='utf-8')
        session = (ROOT / 'sdk/session.inc').read_text(encoding='utf-8')
        copy_sp = offset(session, 'JR_RT_COPY_SP')
        scan_state = {offset(scan, symbol) for symbol in
                      ('JR_RT_SCAN_BASE', 'JR_RT_SCAN_KEY')}
        repeat_state = {offset(repeat, symbol) for symbol in
                        ('JR_RT_REPEAT_PREV', 'JR_RT_REPEAT_COUNT',
                         'JR_RT_REPEAT_CURRENT')}
        effect_state = {offset(effect, symbol) for symbol in
                        ('JR_RT_EFFECT_REMAIN', 'JR_RT_EFFECT_PHASE')}
        self.assertFalse(scan_state & {copy_sp, copy_sp + 1})
        self.assertFalse(scan_state & repeat_state)
        self.assertFalse(effect_state & (scan_state | repeat_state |
                                         {copy_sp, copy_sp + 1}))
        self.assertTrue(all(0 <= item < 64 for item in
                            scan_state | repeat_state | effect_state))
        self.assertNotIn('jr_frame_wait', effect)
        self.assertNotIn('jr_keys_poll', effect)
        self.assertNotIn('jr_keyscan', effect)

        fixture = (ROOT / 'samples/port-fixture/src/main.asm').read_text(
            encoding='utf-8').split('fx_scan_run:\n', 1)[1].split('game_act:\n', 1)[0]
        self.assertLess(fixture.index('JSR     jr_keyscan\n'),
                        fixture.index('JSR     jr_pcg_load\n'))
        self.assertLess(fixture.index('JSR     jr_pcg_load\n'),
                        fixture.index('JSR     jr_keyrepeat_poll\n'))


class SdkImpactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value = json.loads((ROOT / 'ci/targets.json').read_text(encoding='utf-8'))
        validate_registry(value)
        cls.registry = value

    def assert_builds(self, path, expected):
        plan = select(self.registry, [path])
        self.assertEqual(plan['build_candidates'], expected)
        self.assertEqual(plan['test_candidates'], expected)

    def test_shared_module_changes_rebuild_only_consumers(self):
        cases = {
            'sdk/jr200.inc': sorted([
                'chord-sample', 'game-loop-sample', 'input-sample', 'joystick-sample', 'relic-dive',
                'screen-sample', 'side-catch', 'sound-sample', *PORT_GAME_CONSUMERS]),
            'sdk/joystick.inc': ['joystick-sample'],
            'sdk/screen.inc': [
                'game-loop-sample', 'joystick-sample', 'screen-sample', 'side-catch'],
            'sdk/input.inc': ['game-loop-sample', 'input-sample', 'side-catch'],
            'sdk/sound.inc': sorted([
                'game-loop-sample', 'relic-dive', 'side-catch', 'sound-sample',
                *PORT_GAME_CONSUMERS]),
            'sdk/timing.inc': ['game-loop-sample', 'side-catch', 'sound-sample'],
        }
        for module in ('font', 'font_data', 'frame', 'gfx', 'math', 'port', 'session'):
            cases[f'sdk/{module}.inc'] = PORT_GAME_CONSUMERS
        cases['sdk/keys.inc'] = [g for g in PORT_GAME_CONSUMERS if g not in KEYS_EXT_GAMES]
        cases['sdk/keys_ext.inc'] = KEYS_EXT_GAMES
        cases['sdk/sfx.inc'] = SFX_GAME_CONSUMERS
        cases['sdk/frame.inc'] = sorted(['chord-sample', *PORT_GAME_CONSUMERS])
        cases['sdk/audio.inc'] = sorted(['chord-sample', *AUDIO_GAMES])
        cases['sdk/audio_notes.inc'] = sorted(['chord-sample', *AUDIO_GAMES])
        cases['sdk/pcg.inc'] = sorted([*PORT_CONSUMERS, *AUDIO_GAMES])
        cases['sdk/font.inc'] = sorted([*PORT_GAME_CONSUMERS, 'side-catch'])
        cases['sdk/font_data.inc'] = sorted([*PORT_GAME_CONSUMERS, 'relic-dive', 'side-catch'])
        cases['sdk/session.inc'] = sorted([*PORT_GAME_CONSUMERS, 'side-catch'])
        cases['sdk/keyscan.inc'] = ['brick-pulse', 'port-fixture-sample']
        cases['sdk/keyrepeat.inc'] = ['port-fixture-sample']
        cases['sdk/effect.inc'] = ['port-fixture-sample']
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assert_builds(path, expected)

    def test_sample_source_and_test_changes_keep_owner_scope(self):
        self.assert_builds('samples/input/src/main.asm', ['input-sample'])
        self.assert_builds('samples/joystick/src/main.asm', ['joystick-sample'])
        plan = select(self.registry, ['samples/input/tests/expectations.json'])
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(plan['test_candidates'], ['input-sample'])
        plan = select(self.registry, ['samples/joystick/tests/expectations.json'])
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(plan['test_candidates'], ['joystick-sample'])


if __name__ == '__main__':
    unittest.main()
