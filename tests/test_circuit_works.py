# SPDX-License-Identifier: BSD-3-Clause
"""CIRCUIT WORKS: gate truth tables, 22 puzzles and model-derived expectations."""
import itertools
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/circuit-works'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

cw = load_game_model('circuit-works')
OPS = [lambda a, b: a and b, lambda a, b: a or b, lambda a, b: a != b]


class CircuitWorksRuleTests(unittest.TestCase):
    def test_assembly_targets_match_independent_model(self):
        source = (PROJECT / 'src/main.asm').read_text()
        table = source.split('cw_targets:', 1)[1].split('cw_kind_attr:', 1)[0]
        values = [int(value) for row in re.findall(r'\.db\s+([0-9, ]+)', table)
                  for value in row.split(',')]
        self.assertEqual(values, cw.TARGETS)

    def test_all_27_chains_match_an_independent_boolean_evaluation(self):
        for p, q, r in itertools.product(range(3), repeat=3):
            for a, b, c in itertools.product((0, 1), repeat=3):
                expected = int(OPS[r](OPS[q](OPS[p](a, b), c), a))
                self.assertEqual(cw.output(a, b, c, p, q, r), expected)

    def test_input_order_is_a_b_c_from_the_row_index(self):
        self.assertEqual([cw.inputs(i) for i in range(8)],
                         list(itertools.product((0, 1), repeat=3)))

    def test_every_puzzle_has_its_target_chain_as_a_solution(self):
        self.assertEqual(len(cw.TARGETS), cw.LEVELS * 3)
        for level in range(cw.LEVELS):
            with self.subTest(puzzle=level + 1):
                target = tuple(cw.TARGETS[level * 3:level * 3 + 3])
                self.assertIn(target, cw.solutions(level))

    def test_default_gates_partially_match_puzzle_two(self):
        game = cw.CircuitWorks()
        port = PortModel(game, cw.LEVELS)
        port.key(0x0d)
        game.act(5)
        self.assertEqual(port.mode, 2)       # puzzle 1 is the all-AND chain
        port.key(0x0d)
        game.act(5)
        self.assertEqual((port.mode, game.correct, game.tested, game.tests), (1, 5, 8, 1))  # rows 000-011 and 111 match

    def test_tests_counter_saturates_at_99(self):
        game = cw.CircuitWorks()
        port = PortModel(game, cw.LEVELS)
        port.level = 1
        port.new_level()
        for _ in range(120):
            game.act(5)
        self.assertEqual(game.tests, 99)


class CircuitWorksExpectationTests(unittest.TestCase):
    def test_help_describes_graceful_exit(self):
        source = (PROJECT / 'src/main.asm').read_text()
        self.assertIn('SPACE RESTART / CTRL+C EXIT', source)
        self.assertNotIn('ESC TO BASIC', source)

    def test_memory_expectations_are_model_predictions(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        check_expectations(self, expectations,
                           lambda: PortModel(cw.CircuitWorks(), cw.LEVELS))

    def test_all_puzzles_are_replayed(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        profiles = {p['profile']: p['expect'] for p in expectations['runtime']['profiles']}
        final = profiles['synthetic-all-stages']['memory']
        self.assertEqual((final['mode'], final['level']), ('04', f'{cw.LEVELS - 1:02x}'))
        self.assertEqual(profiles['synthetic-partial']['memory']['matched'], '3035')
        self.assertEqual(profiles['local-rom-first-clear']['memory']['state'],
                         profiles['synthetic-first-clear']['memory']['state'])
        self.assertEqual(profiles['local-rom-first-clear']['memory']['mode'], '02')


if __name__ == '__main__':
    unittest.main()
