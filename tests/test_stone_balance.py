# SPDX-License-Identifier: BSD-3-Clause
"""STONE BALANCE: upstream heaps and win tables, the rival, replays and sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/stone-balance'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

sb = load_game_model('stone-balance')


def new_port():
    return PortModel(sb.StoneBalance(), sb.LEVELS)


def grundy(b, misere):
    """Independent reference: is the player to move winning (take 1-3, 3 heaps)?"""
    from functools import lru_cache

    @lru_cache(None)
    def win(state):
        if sum(state) == 0:
            return misere          # the previous player took the last stone
        for i in range(3):
            for take in (1, 2, 3):
                if state[i] >= take:
                    after = list(state)
                    after[i] -= take
                    if not win(tuple(after)):
                        return True
        return False
    return win(tuple(b))


class StoneBalanceRuleTests(unittest.TestCase):
    def test_upstream_tables_agree_with_a_game_tree_search(self):
        for misere in (0, 1):
            for b0 in range(8):
                for b1 in range(8):
                    for b2 in range(8):
                        with self.subTest(misere=misere, b=(b0, b1, b2)):
                            self.assertEqual(bool(sb.has_win([b0, b1, b2], misere)),
                                             grundy((b0, b1, b2), misere))

    def test_rule_switches_at_stage_six(self):
        port = new_port()
        port.key(0x0d)
        self.assertEqual((port.game.b, port.game.misere), ([2, 3, 7], 0))
        port.level = 5
        port.new_level()
        self.assertEqual((port.game.b, port.game.misere), ([2, 5, 6], 1))

    def test_every_stage_has_a_winning_line(self):
        for level in range(sb.LEVELS):
            with self.subTest(level=level):
                self.assertIsNotNone(sb.winning_line(level))

    def test_take_keys_cycle_like_upstream(self):
        port = new_port()
        port.key(0x0d)
        takes = []
        for key in 'aaadddd':
            port.key(ord(key))
            takes.append(port.game.take)
        self.assertEqual(takes, [2, 3, 1, 3, 2, 1, 3])


class StoneBalanceExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_stages_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-stages']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), sb.LOSE_RIVAL)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)

    def test_takes_leave_time_for_both_flights(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = new_port()
            for event, following in zip(presses, presses[1:] + [None]):
                before = sum(port.game.b) if port.mode == 1 and port.confirm is None else None
                port.key(int(event['code'], 16))
                if before is not None and sum(port.game.b) < before and port.mode == 1:
                    end = following['cycle'] if following else profile['max_cycles']
                    self.assertGreaterEqual(end - event['cycle'], 3400000, profile['profile'])


if __name__ == '__main__':
    unittest.main()
