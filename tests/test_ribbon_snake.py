# SPDX-License-Identifier: BSD-3-Clause
"""RIBBON SNAKE: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/ribbon-snake'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

rs = load_game_model('ribbon-snake')
data = load_selftest('ribbon-snake')
ST = SelfTest(rs.RibbonSnake, rs.LEVELS, rs.LAYOUT, rs.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:rs.SIZE].hex()


class RibbonSnakeRuleTests(unittest.TestCase):
    def test_gardens_follow_upstream_init(self):
        for level in range(rs.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.length, game.b[:3], game.dir, game.brakes, game.goal),
                             (3, [8, 0, 1], 2, 3, 8 + level))
            self.assertEqual(sum(game.d), 2 + level)
            self.assertFalse(game.d[game.food])

    def test_brake_halves_speed_for_four_moves(self):
        game, _ = ST.start(0)
        game.act(5)
        self.assertEqual((game.brakes, game.slow), (2, 8))
        heads = []
        for _ in range(8):
            game.tick()
            heads.append(game.b[0])
        self.assertEqual(heads, [16, 16, 24, 24, 32, 32, 40, 40])
        game.act(1)                              # reversing is ignored
        self.assertEqual(game.dir, 2)

    def test_scripts_clear_every_garden(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(garden=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.eaten), (CLEAR, game.goal))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        outcome = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            outcome[name] = (port.mode, port.loss)
        self.assertEqual(outcome['edge-loses'], (LOST, rs.LOSS['edge']))
        self.assertEqual(outcome['rock-loses'], (LOST, rs.LOSS['rock']))
        self.assertEqual(outcome['body-loses'], (LOST, rs.LOSS['body']))
        self.assertEqual(outcome['tail-blocks-when-eating'], (LOST, rs.LOSS['body']))
        self.assertEqual(outcome['tail-follows'], (PLAY, None))
        self.assertEqual(outcome['eat-last-wins'], (CLEAR, None))

    def test_selftest_include_is_generated(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'ribbon-snake', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class RibbonSnakeExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        self.assertEqual(memory['fixtures'], ST.fixtures_bytes(data.FIXTURES).hex())
        self.assertEqual(memory['autoplay'], ST.scripts_bytes(data.SCRIPTS).hex())
        self.assertEqual((memory['mode'], memory['quiet']), ('00', '00'))

    def test_timed_replays_observe_model_states(self):
        start, _ = ST.start(0)
        self.assertEqual(self.memory('synthetic-start')['state'], state(start))
        self.assertEqual(self.memory('synthetic-lose-retry')['state'], state(start))
        lost, port = ST.start(0)
        while port.mode == PLAY:
            lost.tick()
        memory = self.memory('synthetic-no-input-loss')
        self.assertEqual((memory['state'], memory['mode']), (state(lost), '03'))
        self.assertEqual(bytes.fromhex(memory['status']).decode(), rs.LOSS['edge'])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-turn')['dir'], '04')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
