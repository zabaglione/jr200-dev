# SPDX-License-Identifier: BSD-3-Clause
"""TWENTY ONE: upstream shuffle, totals, dealer and payouts, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/twenty-one'
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

to = load_game_model('twenty-one')


def origins(profile):
    log = bytes.fromhex(profile['expect']['memory']['origins'])
    return list(log[1:1 + log[0]])


def new_port(samples=(0,)):
    to.TwentyOne.origins = list(samples)
    return PortModel(to.TwentyOne(), to.LEVELS)


class TwentyOneRuleTests(unittest.TestCase):
    def test_totals_count_aces_as_eleven_when_safe(self):
        self.assertEqual(to.total([0, 12]), 21)          # ace and king
        self.assertEqual(to.total([0, 0, 8]), 21)        # ace, ace, nine
        self.assertEqual(to.total([0, 9, 11]), 21)       # ace, ten, queen
        self.assertEqual(to.total([10, 11, 1]), 22)      # jack, queen, two

    def test_shuffle_is_a_permutation(self):
        port = new_port([0x5a])
        port.key(0x0d)
        self.assertEqual(sorted(port.game.d), list(range(52)))
        self.assertEqual((port.game.np, port.game.nd, port.game.drawn), (2, 2, 4))

    def test_double_needs_two_cards_and_four_coins(self):
        port = new_port([0x5a])
        port.key(0x0d)
        port.game.coins = 3
        port.game.choice = 2
        before = port.game.state_bytes()
        port.game.act(5)
        self.assertEqual(port.game.state_bytes(), before)

    def test_every_origin_has_a_winning_plan(self):
        for origin in range(0, 256, 5):
            self.assertIsNotNone(to.plan(origin), origin)


class TwentyOneExpectationTests(unittest.TestCase):
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

    def test_clear_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-clear']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '00'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), to.NO_COINS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
