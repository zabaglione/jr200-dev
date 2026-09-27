# SPDX-License-Identifier: BSD-3-Clause
"""TRACE BLADE: rules model, rooms, self-test fixtures and routes, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/trace-blade'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, END, PortModel, check_expectations, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

tb = load_game_model('trace-blade')
data = load_selftest('trace-blade')
ST = SelfTest(tb.TraceBlade, tb.LEVELS, tb.LAYOUT, tb.TEST_SIZE, data.LIMIT)


def make():
    return PortModel(tb.TraceBlade(), tb.LEVELS, False, tb.KEYS)


class TraceBladeRuleTests(unittest.TestCase):
    def test_rooms_are_closed_and_start_on_floor(self):
        self.assertEqual(tb.LEVELS, 30)
        for level, room in enumerate(tb.ROOMS):
            with self.subTest(room=level + 1):
                self.assertEqual(len(room), 108)
                self.assertEqual(room[tb.START], 0)
                self.assertEqual(room.count(3), 1)
                border = [room[i] for i in range(12)] + [room[96 + i] for i in range(12)]
                border += [room[r * 12] for r in range(9)] + [room[r * 12 + 11] for r in range(9)]
                self.assertEqual(set(border), {1})

    def test_upstream_routes_cut_every_room(self):
        port = make()
        port.key(13)
        for level, route in enumerate(tb.SOLUTIONS):
            with self.subTest(room=level + 1):
                for action in route:
                    port.game.act(action)
                    self.assertEqual(port.game.error, 0)
                port.key(ord('f'))
                self.assertEqual(port.mode, CLEAR)
                self.assertEqual(port.game.combo, port.game.targets)
                self.assertNotIn(2, port.game.map)
                port.key(13)
        self.assertEqual(port.mode, END)

    def test_upstream_rule_checks(self):
        # check_rules.py: a wall, an early cut, undo of a marked target, menu reset.
        game, port = ST.start(0)
        game.act(3)
        self.assertEqual((game.path_len, game.error), (0, 1))
        game.act(8)
        self.assertEqual((port.mode, game.path_len), (PLAY, 0))
        route = tb.SOLUTIONS[0]
        game.act(route[0])
        visited = list(game.visited)
        game.act({1: 2, 2: 1, 3: 4, 4: 3}[route[0]])
        self.assertEqual((game.path_len, game.visited), (1, visited))
        game.act(6)
        self.assertEqual((game.path_len, game.x, game.y), (0, 1, 1))
        for action in route:
            game.act(action)
        self.assertEqual(game.marked, game.targets)
        for _ in route:
            game.act(6)
        self.assertEqual((game.marked, game.path_len), (0, 0))
        game.act(route[0])
        for action in (5, 2, 2, 5, 3, 5):       # menu, RESET, YES
            game.act(action)
        self.assertEqual((game.path_len, game.marked, game.sub), (0, 0, 0))

    def test_question_defaults_to_no_and_title_leaves(self):
        game, port = ST.start(0)
        for action in (5, 2, 2, 2, 5, 5):       # menu, TITLE, answer NO
            game.act(action)
        self.assertEqual((port.mode, game.sub), (PLAY, 1))
        for action in (5, 3, 5):                # TITLE again, YES
            game.act(action)
        self.assertEqual(port.mode, 0)

    def test_rooms_include_is_generated(self):
        result = subprocess.run([sys.executable, str(PROJECT / 'tests/make_rooms.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_selftest_include_is_generated(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'trace-blade', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class TraceBladeExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_replays_are_model_predictions(self):
        check_expectations(self, self.expectations, make)

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        blob = ST.fixtures_bytes(data.FIXTURES) + ST.scripts_bytes(data.SCRIPTS)
        got = memory['results'] + ''.join(memory[f'results-{n}'] for n in range(2, 10)
                                          if f'results-{n}' in memory)
        self.assertEqual(got, blob.hex())
        self.assertEqual((memory['mode'], memory['quiet']), ('00', '00'))

    def test_ten_rooms_at_normal_speed(self):
        memory = self.memory('synthetic-ten-rooms')
        self.assertEqual((memory['mode'], memory['level']), ('01', '0a'))

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-menu-cut', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
