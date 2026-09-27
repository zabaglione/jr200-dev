# SPDX-License-Identifier: BSD-3-Clause
"""CARGO BALANCE: upstream crates, torque and limits, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/cargo-balance'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

cb = load_game_model('cargo-balance')


def new_port():
    return PortModel(cb.CargoBalance(), cb.LEVELS)


class CargoBalanceRuleTests(unittest.TestCase):
    def test_wind_and_limit_per_voyage(self):
        port = new_port()
        seen = []
        for level in range(cb.LEVELS):
            port.level = level
            port.new_level()
            seen.append((port.game.wind, port.game.tolerance))
        self.assertEqual(seen, [(0, 10), (1, 10), (2, 9), (0, 9), (1, 8), (2, 8)])

    def test_outer_holds_triple_torque_and_double_fare(self):
        port = new_port()
        port.key(0x0d)
        port.key(0x0d)      # crate 1 into hold 0
        port.key(ord('a'))  # hold 3
        port.key(0x0d)      # crate 2 into hold 3
        self.assertEqual((port.game.left, port.game.right, port.game.fare), (3, 6, 6))

    def test_full_hold_refuses_the_crate(self):
        port = new_port()
        port.key(0x0d)
        port.game.c[0] = 4
        port.key(0x0d)
        self.assertEqual((port.game.notice, port.game.loads), (1, 0))

    def test_every_voyage_has_a_plan(self):
        for level in range(cb.LEVELS):
            self.assertIsNotNone(cb.plan(level))


class CargoBalanceExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_voyages_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-voyages']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '05'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), cb.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
