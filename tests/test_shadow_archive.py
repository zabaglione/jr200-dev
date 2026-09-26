# SPDX-License-Identifier: BSD-3-Clause
"""SHADOW ARCHIVE: upstream cases, clue logic, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/shadow-archive'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

sa = load_game_model('shadow-archive')


def new_port():
    return PortModel(sa.ShadowArchive(), sa.LEVELS)


class ShadowArchiveRuleTests(unittest.TestCase):
    def test_each_case_has_six_distinct_trait_sets(self):
        for level in range(sa.LEVELS):
            self.assertEqual(sorted(sa.SUSPECTS[level * 6:level * 6 + 6]), [1, 2, 3, 4, 5, 6])

    def test_all_three_files_always_identify_the_culprit(self):
        for level in range(sa.LEVELS):
            b = sa.SUSPECTS[level * 6:level * 6 + 6]
            left = sa.contradicted(b, sa.WHO[level], [1, 1, 1])
            self.assertEqual([i for i in range(6) if not left[i]], [sa.WHO[level]])

    def test_two_files_are_enough_for_gold_in_every_case(self):
        self.assertTrue(all(len(sa.fewest_files(level)) == 2 for level in range(sa.LEVELS)))

    def test_reopening_a_file_does_not_count(self):
        port = new_port()
        port.key(0x0d)
        port.key(0x0d)
        port.key(0x0d)
        self.assertEqual((port.game.read, port.game.c), (1, [1, 0, 0]))


class ShadowArchiveExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_cases_gold_rating_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-cases']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '0b'))
        first = self.profiles['synthetic-first-clear']['expect']['memory']
        self.assertEqual(bytes.fromhex(first['rating']).decode(), 'GOLD DETECTIVE')
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), 'THE SUSPECT DOES NOT FIT')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
