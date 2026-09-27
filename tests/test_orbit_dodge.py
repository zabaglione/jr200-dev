# SPDX-License-Identifier: BSD-3-Clause
"""ORBIT DODGE: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/orbit-dodge'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

od = load_game_model('orbit-dodge')
data = load_selftest('orbit-dodge')
ST = SelfTest(od.OrbitDodge, od.LEVELS, od.LAYOUT, od.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:od.SIZE].hex()


class OrbitDodgeRuleTests(unittest.TestCase):
    def test_sectors_follow_upstream_init(self):
        for level in range(od.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.hp, game.limit, game.window, game.target, game.dual),
                             (3, 12 + level * 2, 5 if level < 3 else 4, (18 + level * 2) % 8,
                              1 if level >= 2 else 0))
            self.assertNotEqual(game.gem, game.target)

    def test_ring_places_match_upstream_support(self):
        self.assertEqual([od.rx(i, 0) for i in range(8)], [15, 24, 28, 24, 15, 6, 2, 6])
        self.assertEqual([od.ry(i, 1) for i in range(8)], [7, 8, 10, 12, 13, 12, 10, 8])

    def test_standing_still_survives_sector_one(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, game.hp, game.waves), (CLEAR, 1, 12))

    def test_scripts_collect_every_gem(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(sector=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.hp), (CLEAR, 3))
                self.assertEqual(game.score, 3 * game.limit - 3)      # chains 1, 2, 3, 3, ...
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, game.hp, game.chain, game.score)
        self.assertEqual(result['fire-hits-target'][:2], (PLAY, 2))
        self.assertEqual(result['fire-hits-other-ring'][:2], (PLAY, 2))
        self.assertEqual(result['fire-single-ignores-other'][:2], (PLAY, 3))
        self.assertEqual(result['fire-gem-chain'], (PLAY, 3, 2, 9))
        self.assertEqual(result['fire-last-hull'][0], LOST)
        self.assertEqual(result['fire-last-wave-wins'][0], CLEAR)
        self.assertEqual(result['score-wraps'][3], 1)

    def test_selftest_include_is_generated(self):
        resuod = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'orbit-dodge', '--check'], capture_output=True, text=True)
        self.assertEqual(resuod.returncode, 0, resuod.stderr)


class OrbitDodgeExpectationTests(unittest.TestCase):
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
        self.assertEqual(self.memory('synthetic-retry')['state'], state(start))
        idle, port = ST.start(0)
        while port.mode == PLAY:
            idle.tick()
        memory = self.memory('synthetic-no-input-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(idle), '02'))
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-orbit')['orbit'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
