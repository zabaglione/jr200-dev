# SPDX-License-Identifier: BSD-3-Clause
"""LUNAR TOUCHDOWN: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/lunar-touchdown'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

lt = load_game_model('lunar-touchdown')
data = load_selftest('lunar-touchdown')
ST = SelfTest(lt.LunarTouchdown, lt.LEVELS, lt.LAYOUT, lt.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:lt.SIZE].hex()


class LunarTouchdownRuleTests(unittest.TestCase):
    def test_sites_follow_upstream_init(self):
        for level in range(lt.LEVELS):
            game, _ = ST.start(level)
            target = 7 + level * 3
            self.assertEqual((game.x, game.target, game.narrow, game.width, game.fuel, game.wind),
                             (3, target, 24 if target < 18 else 5, 3 if level < 3 else 2, 22,
                              level % 2))

    def test_no_thrust_crashes_too_fast(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.height), (LOST, lt.LOSS['speed'], 30))

    def test_scripts_land_on_every_site(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(site=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.landed), (CLEAR, 1))
                if level in (1, 3):
                    self.assertEqual(game.x, game.narrow)
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, port.loss, game.score)
        self.assertEqual(result['land-regular-soft'], (CLEAR, None, 13))
        self.assertEqual(result['land-regular-edge'], (CLEAR, None, 22))
        self.assertEqual(result['land-precision'], (CLEAR, None, 17))
        self.assertEqual(result['crash-speed'][:2], (LOST, lt.LOSS['speed']))
        self.assertEqual(result['crash-pad'][:2], (LOST, lt.LOSS['pad']))

    def test_selftest_include_is_generated(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'lunar-touchdown', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class LunarTouchdownExpectationTests(unittest.TestCase):
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
        self.assertEqual(bytes.fromhex(memory['status']).decode(), lt.LOSS['speed'])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-steer')['x'], '04')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
