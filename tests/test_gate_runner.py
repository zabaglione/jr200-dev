# SPDX-License-Identifier: BSD-3-Clause
"""GATE RUNNER: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/gate-runner'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

gr = load_game_model('gate-runner')
data = load_selftest('gate-runner')
ST = SelfTest(gr.GateRunner, gr.LEVELS, gr.LAYOUT, gr.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:gr.SIZE].hex()


class GateRunnerRuleTests(unittest.TestCase):
    def test_courses_follow_upstream_init(self):
        for level in range(gr.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.x, game.hp, game.limit, game.rate),
                             (15, 3, 9 if level == 0 else 12, 6 - level // 2))

    def test_even_courses_mirror_the_gates(self):
        game, _ = ST.start(1)
        k = 2
        self.assertEqual(game.b[:8], [gr.KINDS[k], 32 - gr.RIGHTS[k], 32 - gr.LEFTS[k],
                                      gr.OTHER_KINDS[k], 32 - gr.OTHER_RIGHTS[k],
                                      32 - gr.OTHER_LEFTS[k], 30 - gr.PRIZES[k], gr.PRIZE_AIR[k]])

    def test_running_straight_falls_into_the_pits(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.hp), (LOST, gr.LOSS[2], 0))

    def test_scripts_take_every_crystal(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(course=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.hp, game.coins), (CLEAR, 3, game.limit))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, game.x, game.hp, game.hit, game.coins)
        self.assertEqual(result['tick-held-right'][1], 16)
        self.assertEqual(result['tick-held-left-edge'][1], 2)
        self.assertEqual(result['gate-wall-hit'][2:4], (2, 1))
        self.assertEqual(result['gate-wall-edge'][2:4], (3, 0))
        self.assertEqual(result['gate-pit-jumped'][2:4], (3, 0))
        self.assertEqual(result['gate-beam-jumped-into'][2:4], (2, 3))
        self.assertEqual(result['gate-crystal'][4], 1)
        self.assertEqual(result['gate-crystal-in-air'][4], 1)
        self.assertEqual(result['gate-last-hull'][0], LOST)
        self.assertEqual(result['gate-last-wins'][0], CLEAR)

    def test_selftest_include_is_generated(self):
        resugr = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'gate-runner', '--check'], capture_output=True, text=True)
        self.assertEqual(resugr.returncode, 0, resugr.stderr)


class GateRunnerExpectationTests(unittest.TestCase):
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
        self.assertEqual(bytes.fromhex(memory['status']).decode(), gr.LOSS[2])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-hold-right')['x'], '1c')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
