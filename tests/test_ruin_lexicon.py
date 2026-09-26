# SPDX-License-Identifier: BSD-3-Clause
"""RUIN LEXICON: upstream inscriptions, dials and tries, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/ruin-lexicon'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

rl = load_game_model('ruin-lexicon')


def new_port():
    return PortModel(rl.RuinLexicon(), rl.LEVELS)


class RuinLexiconRuleTests(unittest.TestCase):
    def test_every_inscription_has_one_answer_from_its_clues(self):
        for level in range(rl.LEVELS):
            self.assertEqual(rl.solve(level), rl.TABLE[level * 4:level * 4 + 4])

    def test_dials_wrap_through_one_to_four(self):
        port = new_port()
        port.key(0x0d)
        for _ in range(4):
            port.key(ord('w'))
        self.assertEqual(port.game.b[0], 1)
        port.key(ord('s'))
        self.assertEqual(port.game.b[0], 4)

    def test_five_wrong_tries_lose(self):
        port = new_port()
        port.key(0x0d)
        for _ in range(5):
            port.key(0x0d)
        self.assertEqual((port.mode, port.loss, port.game.errors), (3, rl.LOSS, 5))


class RuinLexiconExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_ruins_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-ruins']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '13'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), rl.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
