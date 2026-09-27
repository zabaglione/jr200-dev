# SPDX-License-Identifier: BSD-3-Clause
"""ABYSS SIGNAL: upstream turn rules, panel and photos, sea data, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/abyss-signal'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, PortModel, check_expectations, load_game_model  # noqa: E402

am = load_game_model('abyss-signal')


def make():
    return PortModel(am.AbyssSignal(), am.LEVELS, False, am.KEYS)


def started():
    port = make()
    port.key(13)
    return port.game, port


class AbyssSignalRuleTests(unittest.TestCase):
    def test_sea_matches_upstream_world(self):
        self.assertEqual((len(am.GRID), {len(row) for row in am.GRID}), (32, {32}))
        self.assertEqual(am.GRID[2][2], 6)
        for i, (x, y) in enumerate(am.SITES):
            self.assertEqual(am.GRID[y][x], 7 + i)
        self.assertTrue(all(am.GRID[0][x] == 1 and am.GRID[31][x] == 1 for x in range(32)))

    def test_moves_currents_and_rocks(self):
        game, _ = started()
        game.act(1)
        game.act(1)                             # into the rock above row 1
        self.assertEqual((game.x, game.y, game.hull, game.oxygen, game.turn), (2, 1, 4, 218, 2))
        game.act(7)
        self.assertEqual((game.oxygen, game.turn), (217, 3))

    def test_quiet_costs_two_and_slows_the_hunter(self):
        game, _ = started()
        for action in (5, 2, 2, 5):             # panel, QUIET MODE
            game.act(action)
        self.assertEqual((game.quiet, game.sub, game.turn), (1, am.SEA, 0))
        game.act(4)
        self.assertEqual(game.oxygen, 218)

    def test_record_needs_a_site_in_range(self):
        game, _ = started()
        for action in (5, 2, 5):
            game.act(action)
        self.assertEqual((game.status, game.flags, game.turn, game.sub), (1, 0, 0, am.SEA))
        game.x, game.y = 7, 5
        for action in (5, 2, 5):
            game.act(action)
        self.assertEqual((game.flags, game.photo, game.samples, game.sub), (1, 0, 1, am.PHOTO))
        game.act(4)                             # the photo waits for RETURN or SPACE
        self.assertEqual((game.x, game.sub), (7, am.PHOTO))
        game.act(6)
        self.assertEqual(game.sub, am.SEA)

    def test_questions_default_to_no(self):
        game, port = started()
        game.act(4)
        for action in (5, 1, 1, 5, 5):          # panel, RESTART, answer NO
            game.act(action)
        self.assertEqual((game.x, game.sub), (3, am.PANEL))
        for action in (5, 3, 5):                # RESTART again, YES
            game.act(action)
        self.assertEqual((game.x, game.turn, game.sub), (2, 0, am.SEA))
        for action in (5, 1, 5, 3, 5):          # TITLE, YES
            game.act(action)
        self.assertEqual(port.mode, 0)

    def test_hull_loss_ends_the_dive(self):
        game, port = started()
        for _ in range(7):
            game.act(1)
        self.assertEqual((port.mode, port.loss, game.hull), (LOST, 'CONNECTION LOST', 0))

    def test_world_include_is_generated(self):
        result = subprocess.run([sys.executable, str(PROJECT / 'tests/make_world.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class AbyssSignalExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_replays_are_model_predictions(self):
        check_expectations(self, self.expectations, make)

    def test_survey_returns_home_like_upstream(self):
        memory = self.memory('synthetic-survey')
        state = bytes.fromhex(memory['state'])
        self.assertEqual(memory['mode'], f'{CLEAR:02x}')
        self.assertEqual((state[0], state[1], state[2], state[3], state[4]), (2, 2, 80, 4, 31))
        self.assertEqual(self.memory('synthetic-lost')['mode'], f'{LOST:02x}')
        self.assertEqual(self.memory('synthetic-lost-retry')['mode'], f'{PLAY:02x}')

    def test_three_voice_title_and_jingles_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-survey', 'synthetic-lost'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
