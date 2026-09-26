# SPDX-License-Identifier: BSD-3-Clause
"""ORCHARD DAYS: upstream growth, rain, well and quotas, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/orchard-days'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

od = load_game_model('orchard-days')


def new_port():
    return PortModel(od.OrchardDays(), od.LEVELS)


def press(port, target):
    port.game.cursor = target
    port.game.act(5)


class OrchardDaysRuleTests(unittest.TestCase):
    def test_quota_and_rain_period_per_season(self):
        port = new_port()
        for level, values in enumerate(((18, 4), (24, 5), (30, 6))):
            port.level = level
            port.new_level()
            self.assertEqual((port.game.quota, port.game.period), values)

    def test_berry_ripens_after_two_waterings(self):
        port = new_port()
        port.key(0x0d)
        for target in (0, 0, 0):
            press(port, target)
        game = port.game
        self.assertEqual((game.b[0], game.water, game.day), (3, 4, 3))
        press(port, 0)
        self.assertEqual((game.fruit, game.seeds, game.b[0], game.notice), (3, 8, 0, 2))

    def test_rain_grows_every_plant_and_fills_water(self):
        port = new_port()
        port.key(0x0d)
        press(port, 17)
        for target in (0, 1, 2, 3):
            press(port, target)     # day 4 rains
        game = port.game
        self.assertEqual((game.day, game.b[:4], game.water), (4, [2, 2, 2, 2], 9))

    def test_crop_choice_and_full_well_cost_no_day(self):
        port = new_port()
        port.key(0x0d)
        press(port, 17)
        press(port, 19)
        press(port, 19)     # water 9: refused
        self.assertEqual((port.game.crop, port.game.day, port.game.water), (1, 1, 9))

    def test_every_season_has_a_plan(self):
        for level in range(od.LEVELS):
            self.assertIsNotNone(od.best_plan(level))


class OrchardDaysExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_seasons_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-seasons']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '02'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), od.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
