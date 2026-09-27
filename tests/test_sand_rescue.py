# SPDX-License-Identifier: BSD-3-Clause
"""SAND RESCUE: upstream rules, campaign carry, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/sand-rescue'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

sr = load_game_model('sand-rescue')
data = load_selftest('sand-rescue')
ST = SelfTest(sr.SandRescue, sr.LEVELS, sr.LAYOUT, sr.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:sr.SIZE].hex()


def fresh():
    """The port starts with nothing kept (start and the T key clear the record)."""
    sr.SandRescue.KEEP = None


def drain_then_pour():
    """synthetic-loss: let the tank overflow until the reserve is empty, pour once into A."""
    fresh()
    game, port = ST.start(0)
    while game.water:
        game.tick()
    game.act(5)
    while port.mode == PLAY:
        game.tick()
    return game, port


class SandRescueRuleTests(unittest.TestCase):
    def setUp(self):
        fresh()

    def test_first_field_follows_upstream_init(self):
        game, _ = ST.start(0)
        self.assertEqual((game.water, game.total, game.quota, game.interval, game.fill),
                         (108, 0, 14, 5, 5))

    def test_a_full_tank_never_loses_by_itself(self):
        game, port = ST.start(0)
        for _ in range(2000):
            game.tick()
        self.assertEqual((port.mode, game.water, game.tank), (PLAY, 0, 9))

    def test_draining_and_one_pour_loses(self):
        game, port = drain_then_pour()
        self.assertEqual((port.mode, port.loss, game.score), (LOST, sr.LOSS, 11))

    def test_a_later_field_without_a_clear_begins_again(self):
        game, port = ST.start(3)
        self.assertEqual((port.level, game.water, game.quota), (0, 108, 14))

    def test_scripts_carry_the_campaign_through_six_fields(self):
        totals = []
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(field=level + 1):
                game, port, ticks = ST.play(level, script)
                self.assertEqual((port.mode, port.level), (CLEAR, level))
                self.assertGreaterEqual(game.score, game.quota)
                self.assertLess(ticks, data.LIMIT)
                totals.append(game.total)
        self.assertEqual(totals[-1], 131)
        self.assertEqual(totals, sorted(totals))

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = game, port
        self.assertEqual(result['tick-overflow'][0].tank, 9)
        self.assertEqual(result['pour'][0].flow, 6)
        self.assertEqual(result['pour-empty'][0].flow, 0)
        self.assertEqual(result['water-gone-loses'][1].mode, LOST)
        self.assertEqual(result['water-gone-target-met'][1].mode, PLAY)
        self.assertEqual(result['leave-too-early'][1].mode, PLAY)
        self.assertEqual(result['leave-while-flowing'][1].mode, PLAY)
        self.assertEqual(result['leave-wins'][1].mode, CLEAR)
        carried, port = result['next-field-carries']
        self.assertEqual((port.level, carried.water, carried.total), (1, 94, 17))
        self.assertEqual(result['restart-begins-again'][1].level, 0)

    def test_selftest_include_is_generated(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'sand-rescue', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class SandRescueExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def setUp(self):
        fresh()

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        self.assertEqual(memory['fixtures'], ST.fixtures_bytes(data.FIXTURES).hex())
        fresh()
        self.assertEqual(memory['autoplay'], ST.scripts_bytes(data.SCRIPTS).hex())
        self.assertEqual((memory['mode'], memory['quiet']), ('00', '00'))

    def test_timed_replays_observe_model_states(self):
        for name in ('synthetic-start', 'synthetic-lose-retry'):
            fresh()
            self.assertEqual(self.memory(name)['state'], state(ST.start(0)[0]), name)
        game, _ = drain_then_pour()
        memory = self.memory('synthetic-loss')
        self.assertEqual(memory['lost-mode'], '03')
        self.assertEqual((memory['water'], memory['tank'], memory['score']),
                         ('00', '00', f'{game.score:02x}'))
        self.assertEqual(bytes.fromhex(memory['status']).decode(), sr.LOSS)
        fresh()
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-gate')['gate'], '01')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
