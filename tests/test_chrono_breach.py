# SPDX-License-Identifier: BSD-3-Clause
"""CHRONO BREACH: upstream turn rules, menu, sectors, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/chrono-breach'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, PortModel, check_expectations, load_game_model  # noqa: E402

cm = load_game_model('chrono-breach')


def make():
    return PortModel(cm.ChronoBreach(), cm.LEVELS, False, cm.KEYS)


def started():
    port = make()
    port.key(13)
    return port.game, port


def play_route(game, route):
    """Upstream actions: 9-12 fire N/S/W/E after aiming from the menu."""
    for action in route:
        if action > 8:
            game.facing = action - 8
            action = 8
        game.act(action)


class ChronoBreachRuleTests(unittest.TestCase):
    def test_sectors_are_closed_with_one_start_and_exit(self):
        self.assertEqual(cm.LEVELS, 20)
        for sector in cm.SECTORS:
            self.assertTrue(all((x, 0) in sector.walls and (x, 9) in sector.walls
                                for x in range(12)))
            self.assertTrue(all((0, y) in sector.walls and (11, y) in sector.walls
                                for y in range(10)))
            self.assertTrue(1 <= len(sector.guards) <= 6)

    def test_upstream_rule_checks(self):
        # check_rules.py: a border turns the aim for free; the menu and aiming never
        # advance time; reset restores the sector; the third shot is refused for free.
        game, port = started()
        game.act(3)
        game.act(3)
        self.assertEqual((game.x, game.turns, game.facing), (1, 1, 3))
        guards = list(game.guards)
        for action in (5, 4, 4, 6):
            game.act(action)
        self.assertEqual((game.guards, game.turns, game.sub), (guards, 1, cm.PLAY))
        for action in (5, 2, 2, 5, 3, 5):
            game.act(action)
        self.assertEqual((game.x, game.y, game.turns, game.ammo), (2, 4, 0, 2))
        game.act(8)
        game.act(8)
        turns = game.turns
        game.act(8)
        self.assertEqual((game.ammo, game.turns), (0, turns))

    def test_first_volley_and_death_in_the_lane(self):
        game, port = started()
        game.act(7)
        self.assertEqual((game.phase, game.bolts[:3]), (0, [7, 4, 3]))
        for _ in range(5):
            game.act(7)
        self.assertEqual((port.mode, port.loss), (LOST, cm.DEATH_MESSAGE))

    def test_every_upstream_route_clears_within_par(self):
        for level, sector in enumerate(cm.SECTORS):
            game, port = started()
            port.level = level
            game.init()
            play_route(port.game, sector.route)
            self.assertEqual(port.mode, CLEAR, sector.name)
            self.assertLessEqual(port.game.turns, sector.par, sector.name)

    def test_questions_default_to_no(self):
        game, port = started()
        for action in (5, 2, 2, 5, 5):
            game.act(action)
        self.assertEqual((game.sub, port.mode), (cm.MENU, PLAY))
        for action in (2, 5, 3, 5):
            game.act(action)
        self.assertEqual(port.mode, 0)

    def test_levels_include_is_generated(self):
        result = subprocess.run([sys.executable, str(PROJECT / 'tests/make_levels.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class ChronoBreachExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_replays_are_model_predictions(self):
        check_expectations(self, self.expectations, make)

    def test_all_sectors_and_retry(self):
        memory = self.memory('synthetic-all-sectors')
        self.assertEqual((memory['mode'], memory['level'], memory['deaths']),
                         (f'{CLEAR:02x}', f'{19:02x}', '00'))
        self.assertEqual(self.memory('synthetic-lost')['deaths'], '01')
        retry = self.memory('synthetic-lost-retry')
        self.assertEqual((retry['mode'], retry['deaths']), (f'{PLAY:02x}', '01'))

    def test_three_voice_title_and_jingles_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear', 'synthetic-lost',
                     'synthetic-all-sectors'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
