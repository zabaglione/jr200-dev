# SPDX-License-Identifier: BSD-3-Clause
"""PENDULUM PORT: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/pendulum-port'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

pp = load_game_model('pendulum-port')
data = load_selftest('pendulum-port')
ST = SelfTest(pp.PendulumPort, pp.LEVELS, pp.LAYOUT, pp.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:pp.SIZE].hex()


class PendulumPortRuleTests(unittest.TestCase):
    def test_swing_bounces_between_0_and_15(self):
        game, _ = ST.start(0)
        seen = []
        for _ in range(32):
            game.tick()
            seen.append(game.swing)
        self.assertEqual(seen, list(range(1, 16)) + list(range(14, -1, -1)) + [1, 2])

    def test_targets_and_narrow_decks_follow_upstream(self):
        for level in range(pp.LEVELS):
            game, _ = ST.start(level)
            for ports in range(6 + level):
                game.ports = ports
                game.new_port()
                self.assertEqual(game.target, 4 + (ports * 7 + level * 3 + 6) % 9)
                self.assertEqual(game.width, 0 if level >= 3 and ports % 3 == 0 else 1)

    def test_scripts_clear_every_route(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(route=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.ports, game.hp), (CLEAR, 6 + level, 3))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, game.score, game.hp, game.ports)
        self.assertEqual(result['jump-centre'], (PLAY, 2, 3, 1))
        self.assertEqual(result['jump-edge'], (PLAY, 1, 3, 1))
        self.assertEqual(result['jump-miss'], (PLAY, 0, 2, 0))
        self.assertEqual(result['narrow-deck-miss'], (PLAY, 0, 2, 0))
        self.assertEqual(result['last-rope-loses'][:1], (LOST,))
        self.assertEqual(result['last-port-wins'][:1], (CLEAR,))
        self.assertEqual(result['score-wraps'][1], 1)

    def test_selftest_include_is_generated(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'pendulum-port', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class PendulumPortExpectationTests(unittest.TestCase):
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
        memory = self.memory('synthetic-loss')
        self.assertEqual((memory['lost-mode'], memory['hp']), ('03', '00'))
        self.assertEqual(bytes.fromhex(memory['status']).decode(), pp.LOSS)
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-rope')['rope'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
