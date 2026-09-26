# SPDX-License-Identifier: BSD-3-Clause
"""FROST STEPS: upstream chambers, slides and ratings on sdk/ranked.inc, replays and sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/frost-steps'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import check_expectations, load_game_model  # noqa: E402
import ranked_model as rm  # noqa: E402

fs = load_game_model('frost-steps')


def new_port():
    return rm.RankedPortModel(fs.FrostSteps(), fs.LEVELS, fs.TAG)


def play(level, route):
    port = new_port()
    port.level = level
    port.new_level()
    for action in route:
        port.game.act(action)
    return port


class FrostStepsRuleTests(unittest.TestCase):
    def test_upstream_routes_rate_three_and_two_stars(self):
        for level in range(fs.LEVELS):
            self.assertEqual(play(level, fs.SOLUTIONS[level]).game.stars, 3, level)
            self.assertEqual(play(level, fs.CLEARS[level]).mode, rm.CLEAR, level)

    def test_a_slide_is_one_move_and_walls_cost_nothing(self):
        port = play(0, [])
        g = port.game
        start = g.pos
        g.act(1)
        slid = g.pos
        self.assertEqual(g.moves, 1 if slid != start else 0)
        g.act(1)                        # against the same wall again
        self.assertEqual((g.pos, g.moves), (slid, 1 if slid != start else 0))


class FrostStepsExpectationTests(unittest.TestCase):
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

    def test_all_forty_chambers_and_password_are_covered(self):
        end = self.profiles['synthetic-chambers-21-40']['expect']['memory']
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
