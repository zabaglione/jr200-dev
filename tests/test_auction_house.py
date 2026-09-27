# SPDX-License-Identifier: BSD-3-Clause
"""AUCTION HOUSE: upstream lots, rival and inspection, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/auction-house'
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

ah = load_game_model('auction-house')


def origins(profile):
    log = bytes.fromhex(profile['expect']['memory']['origins'])
    return list(log[1:1 + log[0]])


def new_port(samples=(0,)):
    ah.AuctionHouse.origins = list(samples)
    return PortModel(ah.AuctionHouse(), ah.LEVELS)


class AuctionHouseRuleTests(unittest.TestCase):
    def test_first_lot_and_goals(self):
        port = new_port([0])
        port.key(0x0d)
        game = port.game
        seed = 89
        self.assertEqual((game.seed, game.market, game.value, game.limit, game.bid),
                         (seed, seed % 3, 24 + seed % 3, 14, 4))
        self.assertEqual([58 + level * 2 - level // 2 for level in range(3)], [58, 60, 61])

    def test_jump_bid_lowers_the_rival_limit(self):
        port = new_port([0])
        port.key(0x0d)
        port.key(ord('d'))
        port.key(0x0d)      # bid 4 + 6 = 10 >= 14 - 4: sold
        game = port.game
        self.assertEqual((game.won, game.round, game.cash), (1, 1, 40 - 10 + 24 + 89 % 3))

    def test_plain_bid_draws_the_rival(self):
        port = new_port([0])
        port.key(0x0d)
        port.key(0x0d)      # bid 6 < 14: rival answers +2
        self.assertEqual((port.game.phase, port.game.bid), (2, 8))

    def test_inspection_costs_one_coin_once(self):
        port = new_port([0])
        port.key(0x0d)
        port.key(ord('d'))
        port.key(ord('d'))
        port.key(0x0d)
        port.key(0x0d)
        game = port.game
        self.assertEqual((game.cash, game.low, game.high, game.phase), (39, game.value,
                                                                        game.value, 6))

    def test_every_origin_has_a_winning_plan(self):
        for level in range(ah.LEVELS):
            for origin in range(256):
                self.assertTrue(ah.plan(level, origin)[2], (level, origin))


class AuctionHouseExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        for profile in self.expectations['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                validate_expectations(self.expectations, 0x1000, profile['profile'])
                memory = profile['expect']['memory']
                samples = origins(profile) if 'origins' in memory else []
                port = new_port(samples).run(profile['replay'])
                predicted = {'state': port.game.state_bytes(), 'mode': f'{port.mode:02x}',
                             'level': f'{port.level:02x}'}
                for name in ('state', 'mode', 'level'):
                    if name in memory:
                        self.assertEqual(memory[name], predicted[name], name)
                self.assertEqual(port.exited, profile['expect']['stop_reason'] == 'breakpoint')

    def test_all_markets_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-markets']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '02'))
        self.assertEqual(len(origins(self.profiles['synthetic-all-markets'])), 3)
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), ah.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
