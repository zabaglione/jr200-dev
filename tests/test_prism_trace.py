# SPDX-License-Identifier: BSD-3-Clause
"""PRISM TRACE: upstream mirrors, beam trace and receiver, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/prism-trace'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

pt = load_game_model('prism-trace')


def new_port():
    return PortModel(pt.PrismTrace(), pt.LEVELS)


class PrismTraceRuleTests(unittest.TestCase):
    def test_the_first_beam_misses_the_receiver(self):
        port = new_port()
        port.key(0x0d)
        self.assertEqual(port.mode, 1)
        self.assertEqual(port.game.c[21] & 4, 4)      # the beam enters from the left

    def test_mirrors_turn_the_beam(self):
        self.assertEqual([pt.SLASH[d] for d in (1, 2, 3, 4)], [4, 3, 2, 1])
        self.assertEqual([pt.BACKSLASH[d] for d in (1, 2, 3, 4)], [3, 4, 1, 2])

    def test_empty_cells_do_not_turn(self):
        port = new_port()
        port.key(0x0d)
        before = port.game.state_bytes()
        port.game.act(5)                               # cursor 0 holds no mirror
        self.assertEqual(port.game.state_bytes(), before)

    def test_plan_is_minimal_and_wins_on_the_last_turn(self):
        plan = pt.plan()
        port = new_port()
        port.key(0x0d)
        for n, cell in enumerate(plan):
            port.game.cursor = cell
            port.game.act(5)
            self.assertEqual(port.mode, 2 if n == len(plan) - 1 else 1)
        self.assertTrue(port.game.c[pt.RECEIVER])


class PrismTraceExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_clear_is_covered(self):
        memory = self.profiles['synthetic-all-clear']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '00'))

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
