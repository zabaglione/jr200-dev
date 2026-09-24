# SPDX-License-Identifier: BSD-3-Clause
"""HEARTH ZERO: resource rules, three cold waves and model-derived expectations."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/hearth-zero'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

hz = load_game_model('hearth-zero')


def started(level=0):
    game = hz.HearthZero()
    port = PortModel(game, hz.LEVELS)
    port.level = level
    port.new_level()
    return game, port


def work(game, job):
    game.choice = job
    game.act(5)


class HearthZeroRuleTests(unittest.TestCase):
    def test_start_and_weather_table(self):
        game, _ = started()
        self.assertEqual((game.food, game.wood, game.heat), (10, 8, 12))
        self.assertEqual(len(hz.WEATHER), hz.LEVELS * hz.DAYS)
        self.assertTrue(all(4 <= cold <= 7 for cold in hz.WEATHER))

    def test_every_wave_can_be_survived(self):
        for level in range(hz.LEVELS):
            with self.subTest(wave=level + 1):
                plan = hz.survive(level)
                self.assertEqual(len(plan), hz.DAYS)
                game, port = started(level)
                for job in plan:
                    work(game, job)
                self.assertEqual((port.mode, game.day), (2, hz.DAYS))

    def test_caps_and_costs(self):
        game, _ = started()
        game.wood = game.food = 28
        game.heat = 20
        work(game, hz.WOOD)
        self.assertEqual(game.wood, 30)
        work(game, hz.FOOD)
        self.assertEqual(game.food, 30 - 2 - 2 + 2)  # capped at 30, then two meals
        game.heat = 20
        work(game, hz.FIRE)
        self.assertLessEqual(game.heat, 24)

    def test_refusals_leave_the_day_unchanged(self):
        game, _ = started()
        game.wood = 2
        work(game, hz.FIRE)
        self.assertEqual((game.notice, game.day, game.wood), (1, 0, 2))
        game.wood, game.insulation = 20, 2
        work(game, hz.WALL)
        self.assertEqual((game.notice, game.day, game.insulation), (2, 0, 2))

    def test_food_is_checked_before_heat_and_equal_heat_loses(self):
        game, port = started()
        game.food, game.heat = 1, 24
        work(game, hz.WOOD)
        self.assertEqual((port.mode, port.loss), (3, hz.NO_FOOD))
        game, port = started()
        game.heat = hz.WEATHER[0]      # heat equal to tonight's cold is not enough
        work(game, hz.WOOD)
        self.assertEqual((port.mode, port.loss, game.heat), (3, hz.NO_HEAT, 0))

    def test_insulation_lowers_the_night_cost(self):
        game, _ = started()
        work(game, hz.WALL)
        self.assertEqual(game.heat, 12 - (hz.WEATHER[0] - 1))


class HearthZeroExpectationTests(unittest.TestCase):
    def test_memory_expectations_are_model_predictions(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        check_expectations(self, expectations,
                           lambda: PortModel(hz.HearthZero(), hz.LEVELS))

    def test_waves_and_losses_are_replayed(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        profiles = {p['profile']: p['expect']['memory'] for p in expectations['runtime']['profiles']}
        self.assertEqual((profiles['synthetic-all-waves']['mode'],
                          profiles['synthetic-all-waves']['level']), ('04', '02'))
        self.assertEqual(bytes.fromhex(profiles['synthetic-lose-heat']['status']).decode(),
                         hz.NO_HEAT)
        self.assertEqual(bytes.fromhex(profiles['synthetic-lose-food']['status']).decode(),
                         hz.NO_FOOD)
        self.assertEqual(bytes.fromhex(profiles['synthetic-start']['forecast']).decode(),
                         '4   5   6')


if __name__ == '__main__':
    unittest.main()
