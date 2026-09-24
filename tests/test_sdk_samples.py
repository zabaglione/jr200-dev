# SPDX-License-Identifier: BSD-3-Clause
import json
from pathlib import Path
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
    'game-loop-sample': (
        'samples/game-loop',
        ('sdk/input.inc', 'sdk/jr200.inc', 'sdk/screen.inc',
         'sdk/sound.inc', 'sdk/timing.inc'),
    ),
    'port-fixture-sample': (
        'samples/port-fixture',
        ('sdk/font.inc', 'sdk/font_data.inc', 'sdk/frame.inc', 'sdk/gfx.inc',
         'sdk/jr200.inc', 'sdk/keys.inc', 'sdk/math.inc', 'sdk/pcg.inc',
         'sdk/port.inc', 'sdk/session.inc', 'sdk/sfx.inc', 'sdk/sound.inc'),
    ),
}
PORT_CONSUMERS = ['corner-crown', 'lumen-cross', 'port-fixture-sample']


class SampleContractTests(unittest.TestCase):
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
                'game-loop-sample', 'input-sample', 'joystick-sample', 'relic-dive',
                'screen-sample', 'side-catch', 'sound-sample', *PORT_CONSUMERS]),
            'sdk/joystick.inc': ['joystick-sample'],
            'sdk/screen.inc': [
                'game-loop-sample', 'joystick-sample', 'screen-sample', 'side-catch'],
            'sdk/input.inc': ['game-loop-sample', 'input-sample', 'side-catch'],
            'sdk/sound.inc': sorted([
                'game-loop-sample', 'relic-dive', 'side-catch', 'sound-sample',
                *PORT_CONSUMERS]),
            'sdk/timing.inc': ['game-loop-sample', 'side-catch', 'sound-sample'],
        }
        for module in ('font', 'font_data', 'frame', 'gfx', 'keys', 'math', 'pcg',
                       'port', 'session', 'sfx'):
            cases[f'sdk/{module}.inc'] = PORT_CONSUMERS
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
