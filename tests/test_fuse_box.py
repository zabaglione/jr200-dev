# SPDX-License-Identifier: BSD-3-Clause
"""FUSE BOX: upstream panel generation, count rule, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/fuse-box'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

fb = load_game_model('fuse-box')


def new_port():
    return PortModel(fb.FuseBox(), fb.LEVELS)


class FuseBoxRuleTests(unittest.TestCase):
    def test_first_panel_target_counts(self):
        rows, cols = fb.counts(fb.target(0))
        self.assertEqual(rows, [2, 3, 2, 2, 2])
        self.assertEqual(cols, [3, 2, 2, 2, 2])

    def test_every_panel_has_switches_and_differs(self):
        targets = [tuple(fb.target(level)) for level in range(fb.LEVELS)]
        self.assertEqual(len(set(targets)), 7)          # the formula repeats every 7 levels
        for target in targets:
            self.assertGreater(sum(target), 0)

    def test_any_wiring_with_matching_counts_wins(self):
        target = fb.target(0)
        board = None
        for r1 in range(5):
            for r2 in range(r1 + 1, 5):
                for c1 in range(5):
                    for c2 in range(5):
                        cells = (r1 * 5 + c1, r2 * 5 + c2, r1 * 5 + c2, r2 * 5 + c1)
                        if board is None and [target[i] for i in cells] == [1, 1, 0, 0]:
                            board = target[:]
                            for i in cells:
                                board[i] ^= 1
        self.assertIsNotNone(board)
        self.assertNotEqual(board, target)
        port = new_port()
        port.key(0x0d)
        for cell in (i for i in range(25) if board[i]):
            port.game.cursor = cell
            port.key(0x0d)
        self.assertEqual(port.mode, 2)

    def test_second_flip_turns_a_switch_back_off(self):
        port = new_port()
        port.key(0x0d)
        port.key(0x0d)
        self.assertEqual((port.game.b[0], port.game.flip_frame), (1, 5))
        port.key(0x0d)
        self.assertEqual((port.game.b[0], port.game.flip_frame, port.game.moves), (0, 1, 2))


class FuseBoxExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_clue_colours_follow_the_model_counts(self):
        profile = self.profiles['synthetic-partial']
        port = new_port().run(profile['replay'])
        rows, cols = fb.counts(port.game.b)
        want_rows, want_cols = fb.counts(port.game.d)
        memory = profile['expect']['memory']
        for i in range(5):
            self.assertEqual(memory[f'row-clue-{i}'], '20' if rows[i] == want_rows[i] else '07')
            self.assertEqual(memory[f'col-clue-{i}'], '20' if cols[i] == want_cols[i] else '07')
        self.assertIn('20', [memory[f'row-clue-{i}'] for i in range(5)])

    def test_all_panels_are_cleared(self):
        memory = self.profiles['synthetic-all-panels']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)

    def test_flip_replays_leave_time_for_the_flip(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = new_port()
            for event, following in zip(presses, presses[1:] + [None]):
                playing = port.mode == 1 and port.confirm is None
                port.key(int(event['code'], 16))
                if playing and event['code'] == '0x0d':
                    end = following['cycle'] if following else profile['max_cycles']
                    self.assertGreaterEqual(end - event['cycle'], 500000, profile['profile'])


if __name__ == '__main__':
    unittest.main()
