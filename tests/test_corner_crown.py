# SPDX-License-Identifier: BSD-3-Clause
"""CORNER CROWN: upstream rule facts and model-derived runtime expectations."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/corner-crown'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

cc = load_game_model('corner-crown')


def started():
    game = cc.CornerCrown()
    port = PortModel(game, cc.LEVELS)
    port.key(0x0d)
    return game, port


class CornerCrownRuleTests(unittest.TestCase):
    def test_in_game_exit_hint_uses_graceful_key(self):
        source = (PROJECT / 'src/main.asm').read_text(encoding='utf-8')
        self.assertIn('"SPACE RESTART / CTRL+C EXIT"', source)
        self.assertNotIn('"SPACE RESTART / ESC TO BASIC"', source)

    def test_opening_and_legal_moves(self):
        game, _ = started()
        self.assertEqual((game.white, game.black, game.cursor), (2, 2, 19))
        self.assertEqual(game.legal(1), [19, 26, 37, 44])
        self.assertEqual(game.legal(2), [20, 29, 34, 43])

    def test_rays_do_not_wrap_around_edges(self):
        for pos in range(64):
            x, y = pos % 8, pos // 8
            for direction in range(8):
                target = cc.ray(pos, direction)
                if target == 255:
                    continue
                self.assertLessEqual(abs(target % 8 - x), 1)
                self.assertLessEqual(abs(target // 8 - y), 1)
        self.assertEqual(cc.ray(7, 0), 255)
        self.assertEqual(cc.ray(8, 1), 255)
        self.assertEqual(cc.ray(56, 6), 255)

    def test_illegal_square_changes_nothing(self):
        game, port = started()
        before = game.state_bytes()
        game.cursor = 0
        self.assertEqual(game.act(5), 'illegal')
        self.assertEqual(game.state_bytes()[:128], before[:128])
        self.assertEqual(port.mode, 1)

    def test_multi_direction_capture(self):
        game, _ = started()
        game.b = [0] * 64
        # You at the ends, rival between them in three directions from 27.
        for pos in (26, 19, 35):
            game.b[pos] = 2
        for pos in (25, 11, 43):
            game.b[pos] = 1
        self.assertEqual(game.flips(27, 1, 0), 3)
        game.flips(27, 1, 1)
        self.assertEqual([game.b[p] for p in (26, 19, 35, 27)], [1, 1, 1, 1])

    def test_pass_when_no_legal_move_then_rival_moves(self):
        game, port = started()
        game.b = [0] * 64
        game.b[0], game.b[1] = 2, 1   # you cannot move; the rival can take 2
        game.cursor = 40
        self.assertEqual(game.legal(1), [])
        self.assertEqual(game.legal(2), [2])
        game.act(5)
        self.assertEqual(game.b[:3], [2, 2, 2])
        self.assertEqual(port.mode, 3)  # neither side can move: 0 vs 3 loses

    def test_tie_loses_and_more_discs_win(self):
        for white, expected in ((1, 3), (2, 2)):
            game, port = started()
            game.b = [0] * 64
            game.b[0] = 1
            game.b[63] = 2
            if white == 2:
                game.b[7] = 1
            game.act(5)
            self.assertEqual(port.mode, expected)

    def test_rival_prefers_the_first_biggest_capture(self):
        game, _ = started()
        counts = [(game.flips(i, 2, 0), i) for i in range(64)]
        best = max(c for c, _ in counts)
        self.assertEqual(min(i for c, i in counts if c == best), 20)


class CornerCrownExpectationTests(unittest.TestCase):
    def test_memory_expectations_are_model_predictions(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        check_expectations(self, expectations,
                           lambda: PortModel(cc.CornerCrown(), cc.LEVELS))

    def test_required_scenarios_are_covered(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        profiles = {p['profile']: p['expect'] for p in expectations['runtime']['profiles']}
        self.assertEqual(profiles['synthetic-win']['memory']['mode'], '02')
        self.assertEqual(profiles['synthetic-pass-lose']['memory']['mode'], '03')
        self.assertEqual(profiles['synthetic-win-end']['memory']['mode'], '04')
        win_state = bytes.fromhex(profiles['synthetic-win']['memory']['state'])
        loss_state = bytes.fromhex(profiles['synthetic-pass-lose']['memory']['state'])
        self.assertEqual((win_state[65], win_state[66]), (39, 25))
        self.assertEqual((loss_state[65], loss_state[66]), (10, 54))
        self.assertEqual((win_state[:64].count(1), win_state[:64].count(2)), (39, 25))
        self.assertEqual(profiles['synthetic-exit']['stop_reason'], 'breakpoint')
        self.assertIsNotNone(profiles['synthetic-illegal-sound']['pcm'])
        self.assertEqual(profiles['local-rom-first-turn']['cassette'],
                         {'state': 6, 'mode': 1, 'remote': False})


if __name__ == '__main__':
    unittest.main()
