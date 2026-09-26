# SPDX-License-Identifier: BSD-3-Clause
"""POTION PATH: upstream orders, poison, ingredients and pars, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/potion-path'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

pp = load_game_model('potion-path')


def new_port():
    return PortModel(pp.PotionPath(), pp.LEVELS)


class PotionPathRuleTests(unittest.TestCase):
    def test_ingredient_moves_stop_at_the_edges(self):
        self.assertEqual(pp.step(3, 3, 0), (1, 3))
        self.assertIsNone(pp.step(1, 3, 0))
        self.assertEqual(pp.step(3, 3, 1), (4, 5))
        self.assertIsNone(pp.step(3, 6, 1))
        self.assertEqual(pp.step(3, 3, 2), (3, 2))
        self.assertIsNone(pp.step(3, 0, 2))
        self.assertEqual(pp.step(3, 3, 3), (6, 4))
        self.assertIsNone(pp.step(5, 3, 3))

    def test_shortest_brews_match_every_upstream_par(self):
        self.assertEqual([len(pp.solve(level)) for level in range(pp.LEVELS)], pp.PARS)

    def test_poison_landing_uses_nothing(self):
        port = new_port()
        port.level = 0
        port.new_level()
        g = port.game
        g.b[(3 - 1) * 8 + 3] = 1          # poison right above the flask
        g.ingredient = 2
        g.act(5)
        self.assertEqual((g.notice, g.c[2], g.doses, g.y), (2, 4, 0, 3))


class PotionPathExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_orders_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-orders']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '13'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), pp.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
