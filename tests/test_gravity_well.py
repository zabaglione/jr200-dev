# SPDX-License-Identifier: BSD-3-Clause
"""GRAVITY WELL: upstream wells, tilts and ratings on sdk/ranked.inc, replays and sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/gravity-well'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import check_expectations, load_game_model  # noqa: E402
import ranked_model as rm  # noqa: E402

fs = load_game_model('gravity-well')


def new_port():
    return rm.RankedPortModel(fs.GravityWell(), fs.LEVELS, fs.TAG)


def play(level, route):
    port = new_port()
    port.level = level
    port.new_level()
    for action in route:
        port.game.act(action)
    return port


class GravityWellRuleTests(unittest.TestCase):
    def test_upstream_routes_rate_three_and_two_stars(self):
        for level in range(fs.LEVELS):
            self.assertEqual(play(level, fs.SOLUTIONS[level]).game.stars, 3, level)
            self.assertEqual(play(level, fs.CLEARS[level]).mode, rm.CLEAR, level)

    def test_both_balls_roll_until_blocked(self):
        port = play(0, [])
        g = port.game
        g.b, g.c = [0] * 64, [0] * 128
        g.b[8:16] = [1] * 8                      # a wall along row 1
        g.c[40], g.c[48] = 1, 1                  # two balls in column 0
        g.c[45] = 1
        g.act(1)                                 # tilt up: all stop under the wall
        self.assertEqual([i for i in range(64) if g.c[i]], [16, 21, 24])
        self.assertEqual((g.moves, g.frames), (1, 6))
        self.assertEqual(g.c[64:], list(range(64)))
        g.act(1)                                 # nothing rolls: no move is spent
        self.assertEqual((g.moves, g.frames), (1, 0))


class GravityWellExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_best_ratings_are_model_predictions(self):
        sys.path.insert(0, str(ROOT / 'tools'))
        from emulator_runner import expand_replay_profile
        by_name = {p['profile']: p for p in self.expectations['runtime']['profiles']}
        for name, profile in self.profiles.items():
            with self.subTest(profile=name):
                port = new_port().run(expand_replay_profile(profile, by_name)['replay'])
                self.assertEqual(profile['expect']['memory']['best'], bytes(port.best).hex())

    def test_all_forty_stages_and_password_are_covered(self):
        end = self.profiles['synthetic-wells-31-40']['expect']['memory']
        self.assertEqual((end['mode'], end['best']), ('04', '03' * 40))
        restored = self.profiles['synthetic-password']['expect']['memory']
        self.assertEqual((restored['mode'], restored['level']), ('06', '0c'))

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
