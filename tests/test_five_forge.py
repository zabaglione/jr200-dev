# SPDX-License-Identifier: BSD-3-Clause
"""FIVE FORGE: upstream lines, rival choice and fives, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/five-forge'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

ff = load_game_model('five-forge')


def new_port():
    return PortModel(ff.FiveForge(), ff.LEVELS)


class FiveForgeRuleTests(unittest.TestCase):
    def test_ray_directions_pair_opposites(self):
        for pos in (0, 9, 27, 63):
            for axis in range(4):
                there = ff.ray(pos, axis * 2)
                if there != 255:
                    self.assertEqual(ff.ray(there, axis * 2 + 1), pos)

    def test_line_counts_the_cell_itself(self):
        b = [0] * 64
        b[26] = b[28] = 1
        self.assertEqual(ff.line(b, 27, 1), 3)
        self.assertEqual(ff.line(b, 27, 2), 1)

    def test_rival_blocks_an_immediate_five(self):
        b = [0] * 64
        for cell in (8, 9, 10, 11):
            b[cell] = 1
        self.assertIn(ff.rival_choice(b), (12,))

    def test_rival_takes_its_own_five_first(self):
        b = [0] * 64
        for cell in (8, 9, 10, 11):
            b[cell] = 1
        for cell in (40, 41, 42, 43):
            b[cell] = 2
        self.assertEqual(ff.rival_choice(b), 44)

    def test_plan_wins_and_marks_the_five(self):
        port = new_port()
        port.key(0x0d)
        for cell in ff.WINNING_MOVES:
            port.game.cursor = cell
            port.game.act(5)
        g = port.game
        self.assertEqual((port.mode, g.winner), (2, 1))
        self.assertEqual(sorted(i for i in range(64) if g.d[i]), [13, 20, 27, 34, 41])


class FiveForgeExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_clear_and_rival_five_are_covered(self):
        memory = self.profiles['synthetic-all-clear']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '00'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), ff.RIVAL_FIVE)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
