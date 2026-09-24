# SPDX-License-Identifier: BSD-3-Clause
"""LUMEN CROSS: upstream rule facts and model-derived runtime expectations."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/lumen-cross'
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(PROJECT / 'tests'))
import model as lc  # noqa: E402
from port_model import PortModel  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402
from game_project import validate_project  # noqa: E402


class LumenCrossRuleTests(unittest.TestCase):
    def test_every_stage_is_solvable_and_par_is_the_minimum(self):
        self.assertEqual(len(lc.PARS), lc.LEVELS)
        for level in range(lc.LEVELS):
            with self.subTest(stage=level + 1):
                board = lc.stage_board(level)
                self.assertTrue(any(board))
                found = lc.solutions(board)
                self.assertEqual(len(found), 4)  # 5x5 lights-out kernel has dimension 2
                self.assertEqual(min(map(len, found)), lc.PARS[level])

    def test_cross_stays_on_the_board(self):
        self.assertEqual(sorted(lc.cross_cells(0)), [0, 1, 5])
        self.assertEqual(sorted(lc.cross_cells(24)), [19, 23, 24])
        self.assertEqual(sorted(lc.cross_cells(4)), [3, 4, 9])
        self.assertEqual(sorted(lc.cross_cells(12)), [7, 11, 12, 13, 17])
        for pos in range(25):
            self.assertTrue(all(0 <= cell < 25 for cell in lc.cross_cells(pos)))

    def test_double_press_restores_the_board(self):
        game = lc.LumenCross()
        port = PortModel(game, lc.LEVELS)
        port.key(0x0d)
        before = list(game.board)
        for _ in range(2):
            game.act(5)
        self.assertEqual(game.board, before)

    def test_sixty_presses_lose(self):
        game = lc.LumenCross()
        port = PortModel(game, lc.LEVELS)
        port.key(0x0d)
        for _ in range(59):
            game.act(5)
        self.assertEqual(port.mode, 1)
        game.act(5)
        self.assertEqual((port.mode, port.loss), (3, lc.LOSS))


class LumenCrossExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = validate_project(PROJECT, ROOT / 'rules/jr200.json', ROOT)
        cls.expectations = json.loads(
            (PROJECT / 'tests/expectations.json').read_text(encoding='utf-8'))

    def test_memory_expectations_are_model_predictions(self):
        for profile in self.expectations['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                runtime = validate_expectations(self.expectations, 0x1000, profile['profile'])
                self.assertLessEqual(runtime['max_cycles'], 250_000_000)
                port = PortModel(lc.LumenCross(), lc.LEVELS).run(profile['replay'])
                memory = profile['expect']['memory']
                predicted = {'state': port.game.state_bytes(), 'mode': f'{port.mode:02x}',
                             'level': f'{port.level:02x}'}
                for name in ('state', 'mode', 'level'):
                    if name in memory:
                        self.assertEqual(memory[name], predicted[name], name)
                exited = profile['expect']['stop_reason'] == 'breakpoint'
                self.assertEqual(port.exited, exited)

    def test_required_scenarios_are_covered(self):
        profiles = {p['profile']: p for p in self.expectations['runtime']['profiles']}
        final = profiles['synthetic-all-stages']['expect']['memory']
        self.assertEqual((final['mode'], final['level']), ('04', f'{lc.LEVELS - 1:02x}'))
        self.assertEqual(bytes.fromhex(final['status']).decode(), 'ALL STAGES CLEAR - THANK YOU')
        lost = profiles['synthetic-limit-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), lc.LOSS)
        first = profiles['synthetic-first-clear']['expect']['memory']
        self.assertEqual(bytes.fromhex(first['perfect']).decode(), 'PERFECT CIRCUIT')
        for name in ('synthetic-title', 'synthetic-start', 'synthetic-first-clear'):
            self.assertIsNotNone(profiles[name]['expect']['framebuffer_sha256'])
        exit_memory = profiles['synthetic-exit']['expect']['memory']
        self.assertEqual(exit_memory['key-mask'], '00')

    def test_press_replays_leave_time_for_the_flip_effect(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = PortModel(lc.LumenCross(), lc.LEVELS)
            for event, following in zip(presses, presses[1:] + [None]):
                playing = port.mode == 1 and port.confirm is None
                port.key(int(event['code'], 16))
                if playing and event['code'] == '0x0d':
                    cells = len(lc.cross_cells(port.game.cursor))
                    end = following['cycle'] if following else profile['max_cycles']
                    self.assertGreaterEqual(end - event['cycle'], 280000 * cells,
                                            profile['profile'])


if __name__ == '__main__':
    unittest.main()
