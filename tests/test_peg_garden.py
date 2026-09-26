# SPDX-License-Identifier: BSD-3-Clause
"""PEG GARDEN: upstream rules, replay expectations and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/peg-garden'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

pg = load_game_model('peg-garden')


def new_port():
    return PortModel(pg.PegGarden(), pg.LEVELS)


def started():
    port = new_port()
    port.key(0x0d)
    return port


class PegGardenRuleTests(unittest.TestCase):
    def test_start_garden_has_rock_corners_and_one_hole(self):
        game = started().game
        self.assertEqual([i for i in range(25) if game.b[i] == 1], [0, 4, 20, 24])
        self.assertEqual([i for i in range(25) if game.b[i] == 0], [12])
        self.assertEqual((game.cursor, game.selected, game.left), (12, 255, 20))

    def test_jump_needs_peg_between_and_empty_landing(self):
        port = started()
        for key in 'wwd':
            port.key(ord(key))
        self.assertEqual(port.game.cursor, 3)
        port.key(0x0d)                         # select 3
        port.key(ord('s'))
        port.key(ord('s'))                     # 3 over 8 into 13: 13 is not empty
        port.key(0x0d)
        self.assertEqual((port.game.left, port.game.selected), (20, 255))
        for key in 'wwa':
            port.key(ord(key))
        port.key(0x0d)                         # select 2
        port.key(ord('s'))
        port.key(ord('s'))
        port.key(0x0d)                         # 2 over 7 into 12
        game = port.game
        self.assertEqual((game.b[2], game.b[7], game.b[12], game.left), (0, 0, 4, 19))

    def test_rocks_and_holes_cannot_be_selected(self):
        port = started()
        port.key(0x0d)                         # the centre hole
        self.assertEqual(port.game.selected, 255)
        for key in 'wwaa':
            port.key(ord(key))
        port.key(0x0d)                         # rock at 0
        self.assertEqual((port.game.cursor, port.game.selected), (0, 255))

    def test_recorded_solution_reaches_the_goal(self):
        expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        profile = next(p for p in expectations['runtime']['profiles']
                       if p['profile'] == 'synthetic-clear')
        port = new_port().run(profile['replay'])
        self.assertEqual((port.mode, port.game.left), (2, 5))


class PegGardenExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)
        source = (PROJECT / 'src/main.asm').read_text()
        self.assertIn('audio.inc', source)
        self.assertNotIn('sdk/sfx.inc', source)
        self.assertIn('JR_AU_SONG_MARK', source)

    def test_jump_replays_leave_time_for_the_hop(self):
        for profile in self.expectations['runtime']['profiles']:
            presses = [e for e in profile['replay'] if e['pressed']]
            port = new_port()
            for event, following in zip(presses, presses[1:] + [None]):
                before = port.game.left if port.mode == 1 else None
                port.key(int(event['code'], 16))
                if before is not None and port.game.left < before:
                    end = following['cycle'] if following else profile['max_cycles']
                    self.assertGreaterEqual(end - event['cycle'], 600000, profile['profile'])


if __name__ == '__main__':
    unittest.main()
