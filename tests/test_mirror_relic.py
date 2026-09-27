# SPDX-License-Identifier: BSD-3-Clause
"""MIRROR RELIC: upstream hall, mirror turns, phases, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/mirror-relic'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

mr = load_game_model('mirror-relic')


def new_port():
    return PortModel(mr.MirrorRelic(), mr.LEVELS, extra_keys=mr.EXTRA_KEYS)


class MirrorRelicRuleTests(unittest.TestCase):
    def test_hall_layout_and_relic_phases(self):
        b, c = mr.hall(0)
        self.assertEqual([i for i in range(64) if b[i] == 1 and i % 8 == 3],
                         [3, 11, 27, 35, 51, 59])
        self.assertEqual(b[mr.EXIT], 6)
        self.assertEqual({i: c[i] for i in range(64) if c[i]}, {10: 2, 21: 3, 42: 4})

    def test_clockwise_and_counterclockwise_turns_are_inverse(self):
        for pos in range(64):
            self.assertEqual(mr.turn(mr.turn(pos, 5), 7), pos)
            self.assertEqual(mr.turn(mr.turn(mr.turn(mr.turn(pos, 5), 5), 5), 5), pos)

    def test_turn_changes_phase_and_counts(self):
        port = new_port()
        port.key(0x0d)
        port.key(0x0d)                    # clockwise from 54 (6, 6) to 49 (6, 1)
        self.assertEqual((port.game.pos, port.game.phase, port.game.turns), (49, 1, 1))
        port.key(ord('x'))
        self.assertEqual((port.game.pos, port.game.phase, port.game.turns), (54, 0, 2))

    def test_every_hall_is_solved_within_twenty_turns(self):
        for level in range(mr.LEVELS):
            with self.subTest(level=level):
                solution = mr.solve(level)
                self.assertIsNotNone(solution)
                self.assertLess(sum(1 for a in solution if a in (5, 7)), mr.LIMIT)

    def test_x_key_is_mapped_in_the_game_key_table(self):
        source = (PROJECT / 'src/main.asm').read_text()
        self.assertIn('game_key_table:\n        .db     0x78, 7, 0', source)
        self.assertIn('sdk/keys_ext.inc', source)
        self.assertNotIn('sdk/keys.inc', source)


class MirrorRelicExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_halls_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-halls']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '05'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), mr.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)

    def test_replays_leave_time_for_flights_and_sparkles(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = new_port()
            for event, following in zip(presses, presses[1:] + [None]):
                playing = port.mode == 1 and port.confirm is None
                before = (port.game.turns, port.game.left)
                port.key(int(event['code'], 16))
                if not playing:
                    continue
                end = following['cycle'] if following else profile['max_cycles']
                need = (1400000 if port.game.turns > before[0] else
                        650000 if port.game.left < before[1] else 0)
                self.assertGreaterEqual(end - event['cycle'], need, profile['profile'])


if __name__ == '__main__':
    unittest.main()
