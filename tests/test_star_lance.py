# SPDX-License-Identifier: BSD-3-Clause
"""STAR LANCE: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/star-lance'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

sl = load_game_model('star-lance')
data = load_selftest('star-lance')
ST = SelfTest(sl.StarLance, sl.LEVELS, sl.LAYOUT, sl.TEST_SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:sl.SIZE].hex()


class StarLanceRuleTests(unittest.TestCase):
    def test_waves_follow_upstream_init(self):
        for level in range(sl.LEVELS):
            game, _ = ST.start(level)
            armored = 16 if level >= 3 else 8
            self.assertEqual(game.b[:24], [(2 if i < armored else 1) if i % 8 < 6 else 0
                                           for i in range(24)])
            self.assertEqual((game.ship, game.hp, game.left, game.shift, game.target),
                             (14, 3, 18, 4, 255))

    def test_standing_still_is_shot_down(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.hp), (LOST, sl.LOSS['hit'], 0))

    def test_scripts_clear_every_wave(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(wave=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.hp, game.left), (CLEAR, 3, 0))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = game, port
        self.assertEqual(result['tap-right-then-tick'][0].ship, 15)
        self.assertEqual(result['hold-both-still'][0].ship, 14)
        self.assertEqual(result['fire-heavy-wins-over-light'][0].d[16], 2)
        self.assertEqual((result['fire-overheats'][0].heat, result['fire-overheats'][0].jam),
                         (12, 28))
        self.assertEqual(result['shot-hits-armor'][0].b[0], 1)
        self.assertEqual(result['shot-heavy'][0].b[1], 0)
        game = result['shot-stops-charge'][0]
        self.assertEqual((game.target, game.heat, game.jam, game.notice), (255, 5, 0, 16))
        self.assertEqual(result['enemy-launches-three'][0].c[:3], [11, 11, 11])
        self.assertEqual(result['bolt-hits'][0].hp, 2)
        self.assertEqual(result['bolt-shielded'][0].hp, 3)
        self.assertEqual(result['bolt-hits-last-hull'][1].mode, LOST)
        self.assertEqual(result['fleet-breaks-through'][1].loss, sl.LOSS['fleet'])
        self.assertEqual(result['last-ship-finishes'][1].mode, CLEAR)

    def test_selftest_include_is_generated(self):
        resusl = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'star-lance', '--check'], capture_output=True, text=True)
        self.assertEqual(resusl.returncode, 0, resusl.stderr)


class StarLanceExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        fixtures = ''.join(memory[k] for k in sorted(memory, key=lambda k: (len(k), k))
                           if k.startswith('fixtures'))
        self.assertEqual(fixtures, ST.fixtures_bytes(data.FIXTURES).hex())
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
        self.assertEqual(bytes.fromhex(memory['status']).decode(), sl.LOSS['hit'])
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-hold-left')['ship'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
