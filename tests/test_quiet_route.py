# SPDX-License-Identifier: BSD-3-Clause
"""QUIET ROUTE: fixed upstream rules and runtime replay expectations."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402
from game_project import validate_project  # noqa: E402

qr = load_game_model('quiet-route')
ROUTES = [
    'dddddsaaaassdddssd',
    'dddddsaassddss',
    'dddddsssaaaaa\rssddddd',
    'swdddddsaaaassssdddd',
    'dddddsaassassddd',
    'dddddsss\raa\rssdd',
]


class QuietRouteRuleTests(unittest.TestCase):
    def test_six_wall_arrangements_and_start_state(self):
        first_gaps = [1, 3, 5, 1, 3, 5]
        second_gaps = [4, 5, 0, 1, 2, 3]
        for level in range(6):
            with self.subTest(level=level):
                port = PortModel(qr.QuietRoute(), 6)
                port.level = level
                port.new_level()
                game = port.game
                self.assertEqual((game.pos, game.guard, game.battery, game.cache),
                                 (9, 49 + level, 42 - 2 * level, 33 + level))
                self.assertEqual([i for i in range(6) if game.board[25 + i] == 0],
                                 [first_gaps[level]])
                self.assertEqual([i for i in range(6) if game.board[41 + i] == 0],
                                 [second_gaps[level]])
                self.assertEqual((game.board[14], game.board[54]), (3, 6))

    def test_footstep_and_battery_boundaries(self):
        self.assertEqual([qr.distance(9, pos) for pos in (10, 11, 12, 13, 14)],
                         [1, 2, 3, 4, 5])
        self.assertEqual([int(qr.distance(9, pos) < 5) for pos in (12, 13, 14)],
                         [1, 1, 0])
        self.assertEqual([int(qr.distance(9, pos) < 2) for pos in (10, 11, 12)],
                         [1, 0, 0])
        port = PortModel(qr.QuietRoute(), 6)
        port.key(13)
        port.key(13)
        self.assertEqual(port.game.quiet, 1)
        port.key(ord('d'))
        self.assertEqual(port.game.battery, 40)
        port.key(13)
        port.key(ord('a'))
        self.assertEqual(port.game.battery, 39)

    def test_all_six_routes_reach_campaign_end(self):
        port = PortModel(qr.QuietRoute(), 6)
        port.key(13)
        for level, route in enumerate(ROUTES):
            with self.subTest(level=level):
                self.assertEqual(port.level, level)
                for key in route:
                    port.key(ord(key))
                self.assertEqual(port.mode, 2)
                self.assertEqual((port.game.key, port.game.pos), (1, 54))
                port.key(13)
        self.assertEqual((port.mode, port.level), (4, 5))

    def test_cache_guard_and_battery_failure(self):
        for path, mode, message in (
            ('sdssa', 1, None),
            ('swsdssddd', 3, qr.GUARD_LOSS),
            ('\rswswswswswswswswswsws', 3, qr.BATTERY_LOSS),
        ):
            with self.subTest(path=path):
                port = PortModel(qr.QuietRoute(), 6)
                port.key(13)
                for key in path:
                    port.key(ord(key))
                self.assertEqual((port.mode, port.loss), (mode, message))
                if path == 'sdssa':
                    self.assertEqual((port.game.intel, port.game.cache), (1, 255))
                    self.assertEqual(port.game.battery, 43)


class QuietRouteExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        validate_project(ROOT / 'games/quiet-route', ROOT / 'rules/jr200.json', ROOT)
        cls.data = json.loads((ROOT / 'games/quiet-route/tests/expectations.json').read_text())

    def test_synthetic_replays_match_independent_model(self):
        for profile in self.data['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                runtime = validate_expectations(self.data, 0x1000, profile['profile'])
                if profile['mode'] != 'synthetic-injection':
                    continue
                port = PortModel(qr.QuietRoute(), 6)
                port.run(runtime['replay'])
                expected = profile['expect']['memory']
                if 'state' in expected:
                    self.assertEqual(expected['state'], port.game.state_bytes())
                if 'mode' in expected:
                    self.assertEqual(expected['mode'], f'{port.mode:02x}')
                if 'level' in expected:
                    self.assertEqual(expected['level'], f'{port.level:02x}')
                self.assertEqual(port.exited, profile['expect']['stop_reason'] == 'breakpoint')
                self.assertLessEqual(runtime['max_cycles'], 300_000_000)

    def test_rom_replays_use_the_verified_synthetic_inputs(self):
        profiles = {p['profile']: p for p in self.data['runtime']['profiles']}
        for dest, source in (('local-rom-play', 'synthetic-start'),
                             ('local-rom-goal', 'synthetic-route-0'),
                             ('local-rom-caught', 'synthetic-caught')):
            with self.subTest(dest=dest):
                self.assertEqual(profiles[dest]['replay_from'], source)
                self.assertEqual(profiles[dest]['expect']['memory'],
                                 profiles[source]['expect']['memory'])

    def test_visual_and_audio_baselines_are_recorded(self):
        profiles = {p['profile']: p for p in self.data['runtime']['profiles']}
        for name in ('synthetic-title', 'synthetic-start', 'synthetic-route-0',
                     'synthetic-all-six', 'synthetic-cache', 'synthetic-caught',
                     'synthetic-battery', 'local-rom-title', 'local-rom-play',
                     'local-rom-goal'):
            self.assertIsNotNone(profiles[name]['expect']['framebuffer_sha256'])


if __name__ == '__main__':
    unittest.main()
