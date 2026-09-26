# SPDX-License-Identifier: BSD-3-Clause
"""METRO WEAVE: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/metro-weave'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

mw = load_game_model('metro-weave')
data = load_selftest('metro-weave')
ST = SelfTest(mw.MetroWeave, mw.LEVELS, mw.LAYOUT, mw.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:mw.SIZE].hex()


def with_origin(origin, build):
    """Upstream entropy(): the model takes the origin the emulator sampled."""
    saved = mw.MetroWeave.ORIGIN
    mw.MetroWeave.ORIGIN = origin
    try:
        return build()
    finally:
        mw.MetroWeave.ORIGIN = saved


class MetroWeaveRuleTests(unittest.TestCase):
    def test_shifts_follow_upstream_init(self):
        for level in range(mw.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.hp, game.capacity, game.interval, game.quota, game.issued),
                             (3, min(3, 2 + level), 24 - level * 8, 24 + level * 6, 1))

    def test_the_seed_follows_the_origin(self):
        a = with_origin(0, lambda: ST.start(0)[0])
        b = with_origin(0x40, lambda: ST.start(0)[0])
        self.assertEqual((a.origin, b.origin), (0, 0x40))
        self.assertNotEqual(a.state_bytes(), b.state_bytes())

    def test_no_switching_loses(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.hp), (LOST, mw.LOSS[2], 0))

    def test_scripts_finish_every_shift(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(shift=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.hp, game.done), (CLEAR, 3, 8))
                self.assertGreaterEqual(game.score, game.quota)
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = game, port
        self.assertEqual(result['express-sent'][0].b[16], 1)
        self.assertEqual(result['express-blocked-near-start'][0].issued, 1)
        self.assertEqual(result['point-1-routes-down'][0].b[6], 1)
        self.assertEqual(result['point-1-held'][0].b[0], 8)
        self.assertEqual(result['point-2-routes'][0].b[6], 2)
        self.assertEqual(result['platform-busy'][0].b[0], 25)
        self.assertEqual(result['brakes-behind'][0].b[0], 10)
        self.assertEqual(result['express-goes-late'][0].b[15], 2)
        self.assertEqual((result['arrive-express'][0].score, result['arrive-express'][0].chain),
                         (22, 3))
        self.assertEqual(result['arrive-wrong'][0].hp, 2)
        self.assertEqual(result['arrive-late-last-heart'][1].loss, mw.LOSS[3])
        self.assertEqual(result['shift-short-of-quota'][1].loss, mw.LOSS['quota'])
        self.assertEqual([result[k][0].medal for k in ('shift-bronze', 'shift-silver',
                                                       'shift-gold')], [1, 2, 3])

    def test_selftest_include_is_generated(self):
        resumw = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'metro-weave', '--check'], capture_output=True, text=True)
        self.assertEqual(resumw.returncode, 0, resumw.stderr)


class MetroWeaveExpectationTests(unittest.TestCase):
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
        for name in ('synthetic-start', 'synthetic-lose-retry'):
            observed = self.memory(name)['state']
            origin = bytes.fromhex(observed)[1]
            start = with_origin(origin, lambda: ST.start(0)[0])
            self.assertEqual(observed, state(start), name)
        memory = self.memory('synthetic-no-input-loss')
        origin = bytes.fromhex(memory['state'])[1]

        def lose():
            game, port = ST.start(0)
            while port.mode == PLAY:
                game.tick()
            return game
        self.assertEqual((memory['state'], memory['mode']), (state(with_origin(origin, lose)), '03'))
        self.assertEqual(bytes.fromhex(memory['status']).decode(), mw.LOSS[2])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-select')['cursor'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
