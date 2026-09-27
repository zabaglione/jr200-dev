# SPDX-License-Identifier: BSD-3-Clause
"""LOOP TEN: rules model, chambers, self-test fixtures and escape script, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/loop-ten'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

lt = load_game_model('loop-ten')
data = load_selftest('loop-ten')
ST = SelfTest(lt.LoopTen, lt.LEVELS, lt.LAYOUT, lt.SIZE, data.LIMIT)


class LoopTenRuleTests(unittest.TestCase):
    def test_chambers_share_the_upstream_layout(self):
        self.assertEqual(len(lt.CHAMBERS), 12)
        for room, cells in enumerate(lt.CHAMBERS):
            with self.subTest(room=room + 1):
                self.assertEqual(len(cells), 160)
                self.assertEqual(cells[4 * 16 + 2], lt.ANCHOR)
                self.assertEqual(cells[4 * 16 + 12], lt.SEAL)
                self.assertEqual(cells[4 * 16 + 15], lt.GATE)
                self.assertEqual(cells.count(lt.HAZARD), 0 if room < 4 else 1)

    def test_ten_seconds_then_the_loop_restarts(self):
        game, port = ST.start(0)
        game.flags = [0x25, 0x02]
        game.room, game.x = 3, 7
        for _ in range(99):
            game.tick()
        self.assertEqual((game.loops, game.time, game.seconds), (1, 1, 1))
        game.tick()
        self.assertEqual((game.room, game.x, game.y, game.loops, game.time),
                         (0, 2, 4, 2, 100))
        self.assertEqual(game.flags, [0x25, 0x02])

    def test_held_direction_repeats_after_a_tick(self):
        game, _ = ST.start(0)
        game.act(2)
        game.held = 2
        game.tick()
        self.assertEqual(game.y, 5)
        for _ in range(5):
            game.tick()
        self.assertEqual(game.y, 8)             # the wall below stops it

    def test_upstream_rule_checks(self):
        # check_rules.py: closed and open gates, the anchor, a hazard keeps the seals.
        game, port = ST.start(0)
        for action in data.route(0, lt.START, lt.SEAL_AT):
            game.act(action)
        game.act(5)
        self.assertEqual(game.flags, [1, 0])
        game.x, game.y = 14, 4                  # next to the now open gate
        game.act(4)
        self.assertEqual((game.room, game.x), (1, 1))
        game.x = 14
        game.act(4)
        self.assertEqual((game.room, game.x), (1, 14))
        game.act(6)
        game.act(5)
        self.assertEqual(game.room, 1)
        game.room, game.x, game.y = 4, 6, 6
        game.act(4)
        self.assertEqual((game.room, game.flags, game.loops), (0, [1, 0], 3))

    def test_escape_script_lights_every_seal(self):
        game, port, ticks = ST.play(0, data.SCRIPTS[0])
        self.assertEqual((port.mode, game.flags, game.loops), (CLEAR, [255, 15], 12))
        self.assertLess(ticks, data.LIMIT)

    def test_generated_includes_are_current(self):
        for command in ([sys.executable, str(PROJECT / 'tests/make_rooms.py'), '--check'],
                        [sys.executable, str(ROOT / 'tests/make_selftest.py'), 'loop-ten', '--check']):
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


class LoopTenExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        self.assertEqual(memory['fixtures'], ST.fixtures_bytes(data.FIXTURES).hex())
        self.assertEqual(memory['autoplay'], ST.scripts_bytes(data.SCRIPTS).hex())
        self.assertEqual((memory['mode'], memory['quiet']), ('00', '00'))

    def test_demo_escapes_like_the_model(self):
        game, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']),
                         (bytes.fromhex(game.state_bytes())[:lt.SIZE].hex(), '02'))

    def test_timed_replays_observe_timing_free_values(self):
        expected = {'synthetic-start': ('000204', '01'), 'synthetic-walk': ('000301', '01'),
                    'synthetic-hold': ('000208', '01'), 'synthetic-rewind': ('000204', '02'),
                    'synthetic-time-out': ('000204', '02')}
        for name, (where, loops) in expected.items():
            memory = self.memory(name)
            self.assertEqual((memory['where'], memory['loops'], memory['mode']),
                             (where, loops, f'{PLAY:02x}'), name)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
