# SPDX-License-Identifier: BSD-3-Clause
"""ORBIT DRAFT: upstream deals, drops, spins, chains and endless rounds, replays and sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/orbit-draft'
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

od = load_game_model('orbit-draft')


def origins(profile):
    log = bytes.fromhex(profile['expect']['memory']['origins'])
    return list(log[1:1 + log[0]])


def new_port(samples=(0x15,)):
    od.OrbitDraft.origins = list(samples)
    return PortModel(od.OrbitDraft(), od.LEVELS)


class OrbitDraftRuleTests(unittest.TestCase):
    def test_new_game_board_and_offers(self):
        port = new_port([0x33])
        port.key(0x0d)
        g = port.game
        self.assertEqual(g.b[:12], [od.EMPTY] * 12)
        first = g.b[12]
        self.assertEqual(g.b[12:], [(first + i) % 5 for i in range(4)])
        self.assertEqual((g.d[16], g.card, g.spins, g.target), ((first + 4) % 5, g.d[16], 2, 12))

    def test_three_in_a_row_clears_and_scores(self):
        port = new_port()
        port.key(0x0d)
        g = port.game
        g.b = [od.EMPTY] * 12 + [1, 1, od.EMPTY, 4]
        g.card = 1
        g.phase, g.tool, g.cursor = 1, 0, 2
        g.act(5)
        self.assertEqual(g.b[12:], [od.EMPTY, od.EMPTY, od.EMPTY, 4])
        self.assertEqual((g.points, g.progress, g.spins), (6, 6, 3))

    def test_row_spin_wraps_and_spends_a_spin(self):
        port = new_port()
        port.key(0x0d)
        g = port.game
        g.b = [od.EMPTY] * 12 + [0, 1, 2, 3]
        g.phase, g.tool, g.cursor = 1, 1, 12
        g.act(5)
        self.assertEqual((g.b[12:], g.spins), ([3, 0, 1, 2], 1))

    def test_advance_keeps_board_and_score(self):
        port = new_port()
        port.key(0x0d)
        g = port.game
        g.progress, g.target, g.score_lo = 12, 12, 30
        board = list(g.b)
        port.win()
        port.key(0x0d)
        self.assertEqual((port.level, g.level, g.target, g.progress, g.score_lo, g.b),
                         (1, 1, 18, 0, 30, board))


class OrbitDraftExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        for profile in self.expectations['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                validate_expectations(self.expectations, 0x1000, profile['profile'])
                memory = profile['expect']['memory']
                samples = origins(profile) if 'origins' in memory else []
                port = new_port(samples).run(profile['replay'])
                predicted = {'state': port.game.state_bytes(), 'mode': f'{port.mode:02x}',
                             'level': f'{port.level:02x}'}
                for name in ('state', 'mode', 'level'):
                    if name in memory:
                        self.assertEqual(memory[name], predicted[name], name)
                self.assertEqual(port.exited, profile['expect']['stop_reason'] == 'breakpoint')

    def test_second_round_and_loss_are_covered(self):
        memory = self.profiles['synthetic-second-clear']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('02', '01'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), od.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
