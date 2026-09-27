# SPDX-License-Identifier: BSD-3-Clause
"""ECHO PARRY: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/echo-parry'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

ep = load_game_model('echo-parry')
data = load_selftest('echo-parry')
ST = SelfTest(ep.EchoParry, ep.LEVELS, ep.LAYOUT, ep.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:ep.SIZE].hex()


class EchoParryRuleTests(unittest.TestCase):
    def test_duels_follow_upstream_init(self):
        for level in range(ep.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.hp, game.enemy, game.attack),
                             (4, 6 + level, ep.PATTERN[level % 8]))

    def test_no_guard_loses_four_hearts(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.hp), (LOST, ep.LOSS['window'], 0))

    def test_scripts_win_every_duel(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(duel=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.enemy, game.hp), (CLEAR, 0, 4))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, game.enemy, game.hp, game.combo)
        self.assertEqual(result['parry-early'], (PLAY, 5, 4, 1))
        self.assertEqual(result['parry-late-double'], (PLAY, 4, 4, 1))
        self.assertEqual(result['parry-third-chain'], (PLAY, 5, 4, 3))
        self.assertEqual(result['parry-wrong-guard'], (PLAY, 6, 3, 0))
        self.assertEqual(result['parry-twice'], (PLAY, 6, 4, 0))
        self.assertEqual(result['parry-finishes'][:2], (CLEAR, 0))
        self.assertEqual(result['tick-window-missed-last-heart'][0], LOST)
        game, _ = ST.fixture(2, 'tick', {'age': 1, 'turn': 1})
        self.assertEqual((game.attack, game.feint), (1 - ep.PATTERN[2], 1))

    def test_selftest_include_is_generated(self):
        resuep = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'echo-parry', '--check'], capture_output=True, text=True)
        self.assertEqual(resuep.returncode, 0, resuep.stderr)


class EchoParryExpectationTests(unittest.TestCase):
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
        self.assertEqual(bytes.fromhex(memory['status']).decode(), ep.LOSS['window'])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-guard')['stance'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
