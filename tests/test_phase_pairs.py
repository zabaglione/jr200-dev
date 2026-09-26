# SPDX-License-Identifier: BSD-3-Clause
"""PHASE PAIRS: upstream boards, neighbour pairs and misses, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/phase-pairs'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

ph = load_game_model('phase-pairs')


def new_port(level=0):
    port = PortModel(ph.PhasePairs(), ph.LEVELS)
    port.level = level
    port.new_level()
    return port


def pick(port, *cells):
    for cell in cells:
        port.game.cursor = cell
        port.game.act(5)


class PhasePairsRuleTests(unittest.TestCase):
    def test_upstream_solutions_clear_every_board(self):
        for level in range(ph.LEVELS):
            port = new_port(level)
            for a, b in ph.SOLUTIONS[level]:
                pick(port, a, b)
            self.assertEqual((port.mode, port.game.errors), (2, 0), level)

    def test_first_pick_marks_neighbours_that_make_ten(self):
        port = new_port()
        pick(port, 5)                   # a 4: only cell 4 (a 6) makes ten
        self.assertEqual([i for i in range(16) if port.game.c[i]], [4])

    def test_rejections_count_as_misses(self):
        port = new_port()
        pick(port, 0, 15)               # not neighbours
        pick(port, 0, 4)                # neighbours, 6 + 6
        self.assertEqual((port.game.errors, port.game.left, port.game.first), (2, 16, 255))


class PhasePairsExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations,
                           lambda: PortModel(ph.PhasePairs(), ph.LEVELS))

    def test_all_rounds_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-rounds']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(lost['mode'], '03')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
