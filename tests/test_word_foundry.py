# SPDX-License-Identifier: BSD-3-Clause
"""WORD FOUNDRY: upstream word data, ladder rules, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/word-foundry'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

wf = load_game_model('word-foundry')
UPSTREAM = json.loads('''{"words": [67,65,84,67,79,84,67,79,71,68,79,71,68,79,84,68,65,84,66,65,84,66,79,84,
 66,65,71,66,79,71,66,73,71,68,73,71,80,73,71,80,73,84,83,73,84,83,65,84]}''')


def new_port():
    return PortModel(wf.WordFoundry(), wf.LEVELS)


class WordFoundryRuleTests(unittest.TestCase):
    def test_words_match_upstream_data_table(self):
        self.assertEqual(''.join(wf.WORDS).encode(), bytes(UPSTREAM['words']))
        source = (PROJECT / 'src/main.asm').read_text()
        self.assertIn('.db     "' + ''.join(wf.WORDS) + '"', source)

    def test_par_is_the_shortest_ladder_through_via(self):
        for level in range(wf.LEVELS):
            with self.subTest(level=level):
                self.assertEqual(len(wf.solution(level)), wf.PARS[level])

    def test_target_before_via_does_not_win(self):
        port = new_port()
        port.level = 1
        port.new_level()                      # COT -> COG (goal) before DIG (via)
        port.game.cursor = 2
        port.key(0x0d)
        self.assertEqual((port.game.word, port.game.forged, port.mode), (2, 0, 1))

    def test_only_one_letter_changes_are_accepted(self):
        port = new_port()
        port.key(0x0d)
        port.game.cursor = 3                  # CAT -> DOG
        port.key(0x0d)
        self.assertEqual((port.game.word, port.game.steps), (0, 0))

    def test_limit_is_par_plus_two(self):
        port = new_port()
        port.key(0x0d)
        for word in [6, 0, 6, 0, 6, 0, 6]:
            port.game.cursor = word
            port.key(0x0d)
        self.assertEqual((port.mode, port.loss, port.game.steps), (3, wf.LOSS, 7))


class WordFoundryExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_ladders_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-ladders']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '0f'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), wf.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)

    def test_changes_leave_time_for_the_effects(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = new_port()
            for event, following in zip(presses, presses[1:] + [None]):
                steps = port.game.steps if port.mode == 1 and port.confirm is None else None
                forged = port.game.forged
                port.key(int(event['code'], 16))
                if steps is not None and port.game.steps > steps:
                    end = following['cycle'] if following else profile['max_cycles']
                    need = 1500000 if port.game.forged > forged else 850000
                    self.assertGreaterEqual(end - event['cycle'], need, profile['profile'])


if __name__ == '__main__':
    unittest.main()
