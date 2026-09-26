# SPDX-License-Identifier: BSD-3-Clause
"""CHAIN SUIT: upstream deals, redraws and hand values, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/chain-suit'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

cs = load_game_model('chain-suit')


def new_port():
    return PortModel(cs.ChainSuit(), cs.LEVELS)


class ChainSuitRuleTests(unittest.TestCase):
    def test_hand_values(self):
        cases = [([1, 2, 3, 4, 5], [0, 1, 2, 3, 0], 3, 0),
                 ([1, 1, 3, 4, 5], [0, 1, 2, 3, 0], 8, 1),
                 ([1, 1, 3, 3, 5], [0, 1, 2, 3, 0], 16, 2),
                 ([1, 1, 1, 4, 5], [0, 1, 2, 3, 0], 16, 3),
                 ([1, 1, 1, 4, 4], [0, 1, 2, 3, 0], 16, 4),
                 ([1, 1, 1, 1, 5], [0, 1, 2, 3, 0], 16, 5),
                 ([2, 2, 2, 2, 2], [0, 1, 2, 3, 0], 16, 6),
                 ([1, 2, 3, 4, 5], [2, 2, 2, 2, 2], 25, 7)]
        for b, c, points, hand in cases:
            self.assertEqual(cs.evaluate(b, c)[:2], (points, hand), (b, c))

    def test_first_deal_and_redraw(self):
        port = new_port()
        port.key(0x0d)
        g = port.game
        self.assertEqual((g.b, g.c, g.hand), ([1, 6, 11, 3, 8], [0, 1, 2, 3, 0], 0))
        port.key(ord('w'))
        self.assertEqual((g.b[0], g.c[0], g.discards, g.draws), (8, 1, 1, 1))

    def test_redraws_stop_at_two(self):
        port = new_port()
        port.key(0x0d)
        for _ in range(3):
            port.key(ord('w'))
        self.assertEqual((port.game.discards, port.game.draws), (0, 2))

    def test_best_plan_reaches_the_goal(self):
        port = new_port()
        port.key(0x0d)
        for redraws in cs.BEST_PLAN:
            for pos in redraws:
                port.game.cursor = pos
                port.game.act(1)
            port.game.act(5)
        self.assertEqual((port.mode, port.game.score), (2, 48))


class ChainSuitExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_clear_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-clear']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '00'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), cs.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
