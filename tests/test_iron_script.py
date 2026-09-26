# SPDX-License-Identifier: BSD-3-Clause
"""IRON SCRIPT: upstream rules, self-test fixtures and scripts, replays and sound."""
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/iron-script'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, load_game_model  # noqa: E402
from selftest_model import SelfTest  # noqa: E402
from make_selftest import load_selftest  # noqa: E402

ir = load_game_model('iron-script')
data = load_selftest('iron-script')
ST = SelfTest(ir.IronScript, ir.LEVELS, ir.LAYOUT, ir.SIZE, data.LIMIT)


def state(game):
    return bytes.fromhex(game.state_bytes())[:ir.SIZE].hex()


class IronScriptRuleTests(unittest.TestCase):
    def test_rooms_follow_upstream_levels(self):
        for level in range(ir.LEVELS):
            game, _ = ST.start(level)
            d = ir.LEVELS_DATA[level]
            self.assertEqual((game.b, game.pos, game.facing, game.ammo, game.beam),
                             (d[:64], d[64], d[65], d[66], 255))
            self.assertLessEqual(len(ir.SOLUTIONS[level]), d[67])

    def test_scripts_type_the_upstream_solutions(self):
        for level, script in enumerate(data.SCRIPTS):
            with self.subTest(room=level + 1):
                game, port, ticks = ST.play(level, script)
                program = ir.SOLUTIONS[level]
                self.assertEqual(game.c[:len(program)], program)
                self.assertEqual(port.mode, CLEAR)
                self.assertLess(ticks, data.LIMIT)

    def test_the_program_survives_a_failed_run(self):
        game, port = ST.start(0)
        game.c[0] = 1                            # walk into the wall
        game.act(5)
        game.tick()
        self.assertEqual((game.running, game.notice, game.c[0], port.mode), (0, 1, 1, PLAY))
        game.act(5)                              # the world resets, the program stays
        self.assertEqual((game.running, game.pos, game.c[0]), (1, ir.LEVELS_DATA[0][64], 1))

    def test_fixtures_reach_their_outcomes(self):
        result = {}
        for name, level, op, values in data.FIXTURES:
            game, port = ST.fixture(level, op, values)
            result[name] = game, port
        self.assertEqual(result['run-stopped'][0].notice, 9)
        self.assertEqual(result['step-into-door'][0].notice, 3)
        self.assertEqual(result['step-into-sentry'][0].notice, 2)
        self.assertEqual(result['use-switch'][0].gate, 1)
        self.assertEqual(result['fire-destroys-sentry'][0].b[12], 0)
        self.assertEqual(result['fire-armor'][0].b[12], 5)
        self.assertEqual(result['fire-no-ammo'][0].notice, 5)
        self.assertEqual((result['replay-pair'][0].pos, result['replay-pair'][0].sub), (10, 1))
        self.assertEqual(result['replay-of-replay'][0].notice, 7)
        self.assertEqual(result['laser-on'][0].notice, 4)
        self.assertEqual(result['laser-off'][0].running, 1)
        self.assertEqual(result['terminal'][1].mode, CLEAR)
        self.assertEqual(result['program-ends'][0].notice, 8)

    def test_selftest_include_is_generated(self):
        resuir = subprocess.run([sys.executable, str(ROOT / 'tests/make_selftest.py'),
                                 'iron-script', '--check'], capture_output=True, text=True)
        self.assertEqual(resuir.returncode, 0, resuir.stderr)


class IronScriptExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def memory(self, name):
        return self.profiles[name]['expect']['memory']

    def test_self_test_results_are_model_predictions(self):
        memory = self.memory('synthetic-self-test')
        fixtures = ''.join(memory[k] for k in sorted(memory, key=lambda k: (len(k), k))
                           if k.startswith('fixtures'))
        self.assertEqual(fixtures, ST.fixtures_bytes(data.FIXTURES).hex())
        self.assertEqual(memory['autoplay'], ST.scripts_bytes(data.SCRIPTS).hex())
        self.assertEqual((memory['mode'], memory['quiet']), ('00', '00'))

    def test_timed_replays_observe_model_states(self):
        start, _ = ST.start(0)
        self.assertEqual(self.memory('synthetic-start')['state'], state(start))
        self.assertEqual(self.memory('synthetic-retry')['state'], state(start))
        run, _ = ST.start(0)
        run.act(5)
        while run.running:
            run.tick()
        memory = self.memory('synthetic-empty-run')
        self.assertEqual((memory['state'], memory['mode']), (state(run), '01'))
        self.assertEqual(bytes.fromhex(memory['message']).decode(), 'PROGRAM ENDED')
        demo, port, _ = ST.play(0, data.SCRIPTS[0])
        memory = self.memory('synthetic-demo-clear')
        self.assertEqual((memory['state'], memory['mode']), (state(demo), '02'))
        self.assertEqual(self.memory('synthetic-edit')['program'], '000200')

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-demo-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
