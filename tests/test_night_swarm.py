# SPDX-License-Identifier: BSD-3-Clause
"""NIGHT SWARM: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/night-swarm'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

ns = load_game_model('night-swarm')
data = load_selftest('night-swarm')
ST = SelfTest(ns.NightSwarm, ns.LEVELS, ns.LAYOUT, ns.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:ns.SIZE].hex()


class NightSwarmRuleTests(unittest.TestCase):
    def test_waves_follow_upstream_init(self):
        for level in range(ns.LEVELS):
            game, _ = ST.start(level)
            self.assertEqual((game.pos, game.hp, game.limit, game.period, game.cell, game.b),
                             (27, 4, 12 + level * 2, 4 if level < 3 else 3, 255, [255] * 8))

    def test_portals_run_round_the_edge(self):
        game, _ = ST.start(0)
        entries = set()
        for spawn in range(28):
            game.spawn = spawn
            game.spawn_preview()
            entries.add(game.entry)
        edge = {i for i in range(64) if i < 8 or i >= 56 or i % 8 in (0, 7)}
        self.assertEqual(entries, edge)

    def test_eight_way_moves_stop_at_edges(self):
        self.assertEqual([ns.move8(27, a) for a in (1, 2, 3, 4, 9, 10, 11, 12)],
                         [19, 35, 26, 28, 18, 20, 34, 36])
        self.assertEqual(ns.move8(7, 10), 7)
        self.assertEqual(ns.move8(0, 11), 8)

    def test_no_input_loses(self):
        game, port = ST.start(0)
        while port.mode == PLAY:
            game.tick()
        self.assertEqual((port.mode, port.loss, game.hp), (LOST, ns.LOSS, 0))

    def test_scripts_survive_every_wave(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(wave=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, game.kills, game.hp), (CLEAR, 12 + level * 2, 4))
                self.assertLess(ticks, data.LIMIT)

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = (port.mode, game.hp, game.kills, game.cell)
        self.assertEqual(result['tick-march-hits'], (PLAY, 3, 0, 255))
        self.assertEqual(result['tick-march-last-hull'][0], LOST)
        self.assertEqual(result['tick-autofire-kill-salvage'], (PLAY, 4, 4, 35))
        self.assertEqual(result['tick-autofire-wins'][0], CLEAR)
        self.assertEqual(result['move-salvage'], (PLAY, 3, 0, 255))
        self.assertEqual(result['pulse'][2], 1)
        self.assertEqual(result['pulse-cooling'][2], 0)
        self.assertEqual(result['pulse-wins'][:3], (CLEAR, 4, 12))

    def test_selftest_include_is_generated(self):
        resuns = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'night-swarm', '--check'], capture_output=True, text=True)
        self.assertEqual(resuns.returncode, 0, resuns.stderr)


class NightSwarmExpectationTests(unittest.TestCase):
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

    def test_timed_replays_observe_model_states(self):
        start, _ = ST.start(0)
        self.assertEqual(self.memory('synthetic-start')['state'], state(start))
        self.assertEqual(self.memory('synthetic-lose-retry')['state'], state(start))
        lost, port = ST.start(0)
        while port.mode == PLAY:
            lost.tick()
        memory = self.memory('synthetic-no-input-loss')
        self.assertEqual((memory['state'], memory['mode']), (state(lost), '03'))
        self.assertEqual(bytes.fromhex(memory['status']).decode(), ns.LOSS)
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-diagonal')['pos'], '12')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
