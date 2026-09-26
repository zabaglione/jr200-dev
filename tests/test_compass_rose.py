# SPDX-License-Identifier: BSD-3-Clause
"""COMPASS ROSE: upstream rocks, bearings and supplies, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/compass-rose'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

cr = load_game_model('compass-rose')


def new_port():
    return PortModel(cr.CompassRose(), cr.LEVELS, extra_keys=cr.EXTRA_KEYS)


class CompassRoseRuleTests(unittest.TestCase):
    def test_first_bearing_and_rock_gaps(self):
        port = new_port()
        port.key(0x0d)
        game = port.game
        # goal 13 (row 1, column 5) from 27 (row 3, column 3): north, east, MID.
        self.assertEqual((game.north, game.east, game.band), (1, 2, 1))
        self.assertEqual([game.c[17 + i] for i in range(6)], [0, 1, 1, 1, 1, 1])
        self.assertEqual([game.c[41 + i] for i in range(6)], [1, 1, 1, 0, 1, 1])

    def test_survey_costs_two_and_keeps_bearing_until_asked(self):
        port = new_port()
        port.key(0x0d)
        port.key(ord('d'))
        self.assertEqual((port.game.survey_pos, port.game.fuel), (27, 31))
        port.key(ord('x'))
        self.assertEqual((port.game.survey_pos, port.game.fuel, port.game.surveys),
                         (28, 29, 3))

    def test_rocks_and_edges_cost_nothing(self):
        port = new_port()
        port.key(0x0d)
        port.key(ord('w'))
        self.assertEqual((port.game.pos, port.game.fuel, port.game.facing), (27, 32, 1))

    def test_every_site_is_reachable_within_supplies(self):
        for level in range(cr.LEVELS):
            self.assertLess(len(cr.path(level)) + 2, 32)


class CompassRoseExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_sites_and_both_losses_are_covered(self):
        memory = self.profiles['synthetic-all-sites']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))
        for name, text in (('synthetic-lose', cr.NO_DIGS),
                           ('synthetic-lose-supplies', cr.OUT_OF_SUPPLIES)):
            status = self.profiles[name]['expect']['memory']['status']
            self.assertEqual(bytes.fromhex(status).decode(), text)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
