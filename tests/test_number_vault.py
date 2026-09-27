# SPDX-License-Identifier: BSD-3-Clause
"""NUMBER VAULT: upstream scoring, code derivation, replays and three-voice sound."""
from itertools import product
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/number-vault'
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

nv = load_game_model('number-vault')


def origins(profile):
    log = bytes.fromhex(profile['expect']['memory']['origins'])
    return list(log[1:1 + log[0]])


def port_for(profile):
    nv.NumberVault.origins = origins(profile)
    return PortModel(nv.NumberVault(), nv.LEVELS)


class NumberVaultRuleTests(unittest.TestCase):
    def test_scoring_counts_each_code_digit_once(self):
        self.assertEqual(nv.score([1, 1, 2, 2], [1, 2, 1, 2]), (2, 2))
        self.assertEqual(nv.score([1, 1, 1, 1], [1, 2, 3, 4]), (1, 0))
        self.assertEqual(nv.score([4, 3, 2, 1], [1, 2, 3, 4]), (0, 4))
        self.assertEqual(nv.score([2, 2, 1, 1], [1, 1, 3, 2]), (0, 3))

    def test_code_is_derived_from_origin_and_stage(self):
        secret, digits = nv.code(0x09, 0)
        self.assertEqual(secret, 0x09 ^ 17)
        self.assertEqual(digits, [1 + (secret >> (2 * i)) % 4 for i in range(4)])

    def test_solver_opens_every_code_within_ten_tries(self):
        worst = max(len(nv.solve(list(code))) for code in product((1, 2, 3, 4), repeat=4))
        self.assertLessEqual(worst, 6)

    def test_ten_wrong_codes_lose(self):
        nv.NumberVault.origins = [0x09]
        port = PortModel(nv.NumberVault(), nv.LEVELS)
        port.key(0x0d)
        self.assertNotEqual(port.game.d, [1, 1, 1, 1])
        for _ in range(10):
            port.key(0x0d)
        self.assertEqual((port.mode, port.loss, port.game.tries), (3, nv.LOSS, 10))


class NumberVaultExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        for profile in self.expectations['runtime']['profiles']:
            with self.subTest(profile=profile['profile']):
                validate_expectations(self.expectations, 0x1000, profile['profile'])
                port = port_for(profile).run(profile['replay'])
                memory = profile['expect']['memory']
                predicted = {'state': port.game.state_bytes(), 'mode': f'{port.mode:02x}',
                             'level': f'{port.level:02x}'}
                for name in ('state', 'mode', 'level'):
                    if name in memory:
                        self.assertEqual(memory[name], predicted[name], name)
                self.assertEqual(port.exited, profile['expect']['stop_reason'] == 'breakpoint')

    def test_every_stage_start_records_one_origin(self):
        campaign = self.profiles['synthetic-all-vaults']
        self.assertEqual(len(origins(campaign)), 10)
        memory = campaign['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
