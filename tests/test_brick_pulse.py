# SPDX-License-Identifier: BSD-3-Clause
"""BRICK PULSE: arena data, self-test fixtures/autoplay and model expectations."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/brick-pulse'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from port_model import PortModel, load_game_model  # noqa: E402

bp = load_game_model('brick-pulse')
_spec = importlib.util.spec_from_file_location('bp_fixtures', PROJECT / 'tests/fixtures.py')
fx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fx)


def start(level):
    game = bp.BrickPulse()
    port = PortModel(game, bp.LEVELS, False)
    port.level = level
    port.new_level()
    return game, port


def autopilot(game):
    target = max(0, min(30 - game.width, game.x - game.width // 2))
    if game.paddle > target + 1:
        return 3
    if game.paddle < target - 1:
        return 4
    return 0


def fixture_bytes():
    out = b''
    for _, level, held, values, bricks in fx.FIXTURES:
        game, port = start(level)
        for index, hits in bricks.items():
            game.b[index] = hits
        for name, value in values.items():
            setattr(game, name, value)
        game.held = held
        game.tick()
        out += bytes.fromhex(game.state_bytes()) + bytes([port.mode])
    return out


def autoplay_bytes(limit=20000):
    out = b''
    for level in range(bp.LEVELS):
        game, port = start(level)
        ticks = 0
        while True:
            game.held = autopilot(game)
            game.tick()
            ticks += 1
            if port.mode != 1 or ticks == limit:
                break
        out += bytes.fromhex(game.state_bytes()) + bytes([port.mode, ticks >> 8, ticks & 0xff])
    return out


class BrickPulseRuleTests(unittest.TestCase):
    def test_arena_table_in_source_matches_the_model(self):
        source = (PROJECT / 'src/main.asm').read_text(encoding='utf-8')
        block = source[source.index('bp_arenas:'):source.index('bp_brick_attr:')]
        rows = [list(map(int, re.findall(r'\d+', line.split('.db')[1])))
                for line in block.splitlines() if '.db' in line]
        self.assertEqual(rows, bp.ARENAS)
        self.assertEqual(len(rows), bp.LEVELS)
        self.assertTrue(all(len(row) == 24 and set(row) <= {0, 1, 2, 3} for row in rows))

    def test_drones_from_arena_three_and_bombs_from_arena_six(self):
        for level in range(bp.LEVELS):
            game, _ = start(level)
            self.assertEqual(game.enemy, 0 if level < 2 else 2 + level // 4)
        game, _ = start(4)
        game.clock, game.ex = 31, 9
        game.tick()
        self.assertEqual(game.bomb, 0)          # arena 5: no bombs yet
        game, _ = start(5)
        game.clock, game.ex = 31, 9
        game.tick()
        self.assertEqual((game.bomb, game.bx), (11, 10))

    def test_every_arena_can_be_cleared(self):
        data = autoplay_bytes()
        for level in range(bp.LEVELS):
            with self.subTest(arena=level + 1):
                self.assertEqual(data[level * 54 + 51], 2)

    def test_no_input_loses_all_three_balls(self):
        game, port = start(0)
        while port.mode == 1:
            game.tick()
        self.assertEqual((port.mode, game.hp), (3, 0))

    def test_fixture_include_is_generated_from_the_fixture_list(self):
        result = subprocess.run([sys.executable, str(PROJECT / 'tests/make_fixtures.py'),
                                 '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class BrickPulseExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data = json.loads((PROJECT / 'tests/expectations.json').read_text(encoding='utf-8'))
        cls.profiles = {p['profile']: p for p in data['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        self.assertEqual(memory['fixtures'], fixture_bytes().hex())
        self.assertEqual(memory['autoplay'], autoplay_bytes().hex())

    def test_demo_and_no_input_states_are_model_predictions(self):
        self.assertEqual(self.memory('synthetic-demo-clear')['state'],
                         autoplay_bytes()[:51].hex())
        game, port = start(0)
        while port.mode == 1:
            game.tick()
        self.assertEqual(self.memory('synthetic-no-input-loss')['state'], game.state_bytes())
        fresh, _ = start(0)
        self.assertEqual(self.memory('synthetic-lose-retry')['state'], fresh.state_bytes())
        self.assertEqual(self.memory('synthetic-start')['state'], fresh.state_bytes())

    def test_tap_and_hold_move_the_paddle_as_upstream(self):
        self.assertEqual(self.memory('synthetic-tap')['paddle'], '0e06')   # one step of 2
        self.assertEqual(self.memory('synthetic-hold-right')['paddle'], '1806')  # 30 - 6
        self.assertEqual(self.memory('synthetic-hold-left-release')['paddle'], '0006')

    def test_profiles_fit_the_runner_limits(self):
        for profile in self.profiles.values():
            self.assertLessEqual(profile['max_cycles'], 250_000_000)

    def test_local_rom_replays_match_synthetic_outcomes(self):
        for name in ('lose-retry', 'hold-left-release', 'self-test', 'demo-clear'):
            with self.subTest(profile=name):
                expected = self.profiles[f'synthetic-{name}']['expect']['memory']
                local = self.profiles[f'local-rom-{name}']['expect']['memory']
                self.assertEqual(local, expected)

    def test_help_describes_graceful_exit(self):
        source = (PROJECT / 'src/main.asm').read_text(encoding='utf-8')
        self.assertIn('CTRL+C : BACK TO BASIC', source)
        self.assertNotIn('ESC / CTRL+C', source)


if __name__ == '__main__':
    unittest.main()
