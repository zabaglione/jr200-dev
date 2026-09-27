# SPDX-License-Identifier: BSD-3-Clause
"""DICE RELIC: upstream combat, PRNG and workshop, replays and sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/dice-relic'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import CLEAR, LOST, PortModel, check_expectations, load_game_model  # noqa: E402

dr = load_game_model('dice-relic')
EXPECTATIONS = json.loads((PROJECT / 'tests/expectations.json').read_text())
SEED = bytes.fromhex(next(p for p in EXPECTATIONS['runtime']['profiles']
                          if p['profile'] == 'synthetic-start')['expect']['memory']['state'])[10]


def make(seed=SEED):
    dr.DiceRelic.ORIGIN = seed
    return PortModel(dr.DiceRelic(), dr.LEVELS, False)


def started(seed=SEED):
    port = make(seed)
    port.key(13)
    return port.game, port


class DiceRelicRuleTests(unittest.TestCase):
    def test_prng_and_first_roll(self):
        game, _ = started(0x35)
        rng, dice = 0x35, []
        for i in range(3):
            rng = ((rng << 1) ^ (0x1d if rng & 128 else 0)) & 255
            dice.append([1, 2, 3, 4, 5, 6][rng % 6])
        self.assertEqual((game.rng, game.dice, game.turn, game.hp), (rng, dice, 1, 42))

    def test_upstream_combat_fixtures(self):
        # check_rules.py: attack, guard after two dice, heavy fourth turn, heal cap.
        game, _ = started()
        game.dice, game.used = [6, 4, 2], 3
        game.selected, game.choice = 2, 1
        game.act(5)
        self.assertEqual((game.hp, game.shield, game.turn), (41, 0, 2))
        game, _ = started()
        game.dice, game.used, game.turn = [6, 4, 2], 3, 4
        game.selected, game.choice = 2, 1
        game.act(5)
        self.assertEqual(game.hp, 39)
        game, _ = started()
        game.dice, game.hp = [6, 4, 2], 41
        game.choice = 2
        game.act(5)
        self.assertEqual((game.hp, game.selected, game.roles), (42, 1, [3, 0, 0]))

    def test_spent_dice_and_second_reroll_are_refused(self):
        game, _ = started()
        game.act(5)
        game.act(3)
        game.act(5)
        self.assertEqual(game.error, 1)
        game, _ = started()
        for action in (1, 5, 5):                # REROLL twice
            game.act(action)
        self.assertEqual((game.rerolls, game.error), (0, 1))

    def test_workshop_prices_and_cap(self):
        game, _ = started()
        game.sub, game.coins = dr.WORKSHOP, 3
        game.faces[7] = 8
        for action in (4, 2, 5, 5):             # die 2, face 2, FORGE
            game.act(action)
        self.assertEqual((game.faces[7], game.coins, game.sub), (9, 0, dr.WORKSHOP))
        for action in (5, 5):                   # FORGE again: no gold
            game.act(action)
        self.assertEqual((game.error, game.sub), (1, dr.SERVICES))
        game.coins = 2
        for action in (4, 5):                   # HEAL at full HP
            game.act(action)
        self.assertEqual((game.error, game.coins), (1, 2))

    def test_king_ends_the_run_and_hp_zero_loses(self):
        game, port = started()
        game.battle, game.enemy_hp = 8, 1
        game.act(5)
        self.assertEqual(port.mode, CLEAR)
        game, port = started()
        game.hp, game.used, game.selected = 1, 3, 2
        game.act(5)
        self.assertEqual(port.mode, LOST)


class DiceRelicExpectationTests(unittest.TestCase):
    def test_replays_are_model_predictions(self):
        check_expectations(self, EXPECTATIONS, make)

    def test_nine_battles(self):
        profiles = {p['profile']: p['expect']['memory'] for p in EXPECTATIONS['runtime']['profiles']}
        run = bytes.fromhex(profiles['synthetic-nine-battles']['state'])
        self.assertEqual((profiles['synthetic-nine-battles']['mode'], run[3], run[4]),
                         (f'{CLEAR:02x}', 8, 0))

    def test_three_voice_title_and_jingles_and_silent_exit(self):
        profiles = {p['profile']: p for p in EXPECTATIONS['runtime']['profiles']}
        for name in ('synthetic-title', 'synthetic-nine-battles'):
            self.assertEqual(profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
