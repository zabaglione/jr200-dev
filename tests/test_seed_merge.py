# SPDX-License-Identifier: BSD-3-Clause
"""SEED MERGE: pinned upstream facts and an independent 2048-style oracle."""
from itertools import product
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, load_game_model  # noqa: E402
from game_project import validate_project  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

sm = load_game_model('seed-merge')


def reference_slide(values):
    """A second implementation: compact, merge each input once, compact."""
    compact = [value for value in values if value]
    result = []
    pos = 0
    while pos < len(compact):
        if pos + 1 < len(compact) and compact[pos] == compact[pos + 1]:
            result.append(compact[pos] + 1)
            pos += 2
        else:
            result.append(compact[pos])
            pos += 1
    return result + [0] * (4 - len(result))


class SeedMergeRuleTests(unittest.TestCase):
    def test_initial_positions_and_seed(self):
        game = sm.SeedMerge()
        game.init()
        self.assertEqual(game.seed, 181)
        self.assertEqual([i for i, value in enumerate(game.board) if value], [4, 5])
        self.assertEqual((game.best, game.moves), (1, 0))

    def test_every_single_line_matches_an_independent_oracle(self):
        for action in range(1, 5):
            for values in product(range(5), repeat=4):
                with self.subTest(action=action, values=values):
                    game = sm.SeedMerge()
                    game.board = [0] * 16
                    positions = sm.line_positions(1, action)
                    for pos, value in zip(positions, values):
                        game.board[pos] = value
                    game.settle(action)
                    for line in range(4):
                        cells = sm.line_positions(line, action)
                        for p, n in zip(cells, cells[1:]):
                            if game.board[p] and game.board[p] == game.board[n]:
                                game.board[p] += 1
                                game.board[n] = 0
                    game.settle(action)
                    self.assertEqual([game.board[p] for p in positions], reference_slide(values))

    def test_invalid_move_does_not_spawn_or_increment_moves(self):
        game = sm.SeedMerge()
        port = PortModel(game, 1)
        port.key(0x0d)
        game.board = [1, 1, 0, 0] + [0] * 12
        for _ in range(3):
            game.act(1)  # Both seeds are already on the top row.
        self.assertEqual((game.seed, game.moves), (181, 0))
        self.assertEqual(game.board[:4], [1, 1, 0, 0])

    def test_one_turn_cannot_merge_a_result_again(self):
        game = sm.SeedMerge()
        port = PortModel(game, 1)
        game.board = [1, 1, 2, 0] + [0] * 12
        game.seed = 0
        game.best = 2
        game.act(3)
        self.assertEqual(game.board[:2], [2, 2])
        self.assertEqual((game.best, game.moves), (2, 1))
        self.assertEqual(game.board.count(1), 1)  # New seed only, not a second merge.
        self.assertEqual(port.mode, 0)  # Direct rule calls do not start the port UI.

    def test_win_and_no_moves_loss(self):
        game = sm.SeedMerge()
        port = PortModel(game, 1)
        port.key(0x0d)
        game.board = [5, 5, 1, 2] + [0] * 12
        game.best = 5
        game.act(3)
        self.assertEqual((game.best, port.mode), (6, 2))
        game = sm.SeedMerge()
        port = PortModel(game, 1)
        port.key(0x0d)
        game.board = [1, 2, 3, 4, 2, 3, 4, 1,
                      3, 4, 1, 2, 4, 1, 2, 3]
        game.best = 4
        game.act(1)
        self.assertEqual((port.mode, port.loss), (3, sm.LOSS))


class SeedMergeExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = validate_project(ROOT / 'games/seed-merge', ROOT / 'rules/jr200.json', ROOT)
        cls.expectations = json.loads(
            (ROOT / 'games/seed-merge/tests/expectations.json').read_text(encoding='utf-8'))

    def test_replay_memory_is_predicted_by_the_independent_model(self):
        for profile in self.expectations['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                runtime = validate_expectations(self.expectations, 0x1000,
                                                profile['profile'])
                if profile['mode'] != 'synthetic-injection':
                    continue
                port = PortModel(sm.SeedMerge(), 1).run(runtime['replay'])
                expected = profile['expect']['memory']
                if 'state' in expected:
                    self.assertEqual(expected['state'], port.game.state_bytes())
                if 'mode' in expected:
                    self.assertEqual(expected['mode'], f'{port.mode:02x}')
                self.assertEqual(port.exited,
                                 profile['expect']['stop_reason'] == 'breakpoint')

    def test_rom_replays_reuse_the_accepted_synthetic_inputs(self):
        profiles = {p['profile']: p for p in self.expectations['runtime']['profiles']}
        for destination, source in (('local-rom-play', 'synthetic-start'),
                                    ('local-rom-goal', 'synthetic-win'),
                                    ('local-rom-lose', 'synthetic-lose')):
            with self.subTest(destination=destination):
                self.assertEqual(profiles[destination]['replay_from'], source)
                self.assertEqual(profiles[destination]['expect']['memory'],
                                 profiles[source]['expect']['memory'])

    def test_win_loss_and_gallery_baselines_are_present(self):
        profiles = {p['profile']: p for p in self.expectations['runtime']['profiles']}
        self.assertEqual(profiles['synthetic-win']['expect']['memory']['mode'], '02')
        self.assertEqual(profiles['synthetic-lose']['expect']['memory']['mode'], '03')
        for name in ('synthetic-title', 'synthetic-start', 'synthetic-right',
                     'synthetic-win', 'synthetic-lose'):
            self.assertIsNotNone(profiles[name]['expect']['framebuffer_sha256'])


if __name__ == '__main__':
    unittest.main()
