# SPDX-License-Identifier: BSD-3-Clause
"""TIDE BRIDGE: upstream planks, toggles, search and walk, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/tide-bridge'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

tb = load_game_model('tide-bridge')


def new_port():
    return PortModel(tb.TideBridge(), tb.LEVELS)


class TideBridgeRuleTests(unittest.TestCase):
    def test_boards_start_unlinked(self):
        for level in range(tb.LEVELS):
            board = tb.board(level)
            self.assertEqual(board.count(3), 12)
            self.assertIsNone(tb.route(board))

    def test_toggle_flips_a_whole_row_or_column(self):
        board = tb.board(0)
        tb.toggle(board, 0, 2)
        self.assertEqual(board[12:18], [0 if v else 3 for v in tb.board(0)[12:18]])
        tb.toggle(board, 1, 4)
        self.assertEqual([board[i * 6 + 4] for i in (0, 1)], [0 if tb.board(0)[4] else 3,
                                                             0 if tb.board(0)[10] else 3])

    def test_route_follows_upstream_search_order(self):
        board = [3] * 36
        # up is tried first, so the hero climbs column 0 and then walks the top row.
        self.assertEqual(tb.route(board), [24, 18, 12, 6, 0, 1, 2, 3, 4, 5])

    def test_plans_are_minimal_and_win_only_on_the_last_change(self):
        for level in range(tb.LEVELS):
            plan = tb.plan(level)
            port = new_port()
            port.level = level
            port.new_level()
            for n, (axis, line) in enumerate(plan):
                port.game.axis, port.game.cursor = axis, line
                port.game.act(5)
                self.assertEqual(port.mode, 2 if n == len(plan) - 1 else 1)
            self.assertEqual((port.game.pos, port.game.facing, port.game.arrived), (5, 5, 1))


class TideBridgeExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_tides_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-tides']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '02'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(lost['mode'], '03')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
