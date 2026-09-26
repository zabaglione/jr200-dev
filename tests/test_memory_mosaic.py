# SPDX-License-Identifier: BSD-3-Clause
"""MEMORY MOSAIC: upstream shuffle and pair rules, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/memory-mosaic'
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'tools'))
from port_model import PortModel, load_game_model  # noqa: E402
from emulator_runner import validate_expectations  # noqa: E402

mm = load_game_model('memory-mosaic')


def origins(profile):
    log = bytes.fromhex(profile['expect']['memory']['origins'])
    return list(log[1:1 + log[0]])


def port_for(profile):
    mm.MemoryMosaic.origins = origins(profile)
    return PortModel(mm.MemoryMosaic(), mm.LEVELS)


class MemoryMosaicRuleTests(unittest.TestCase):
    def test_every_deal_holds_eight_pairs(self):
        for origin in range(256):
            for level in range(mm.LEVELS):
                self.assertEqual(sorted(mm.deal(origin, level)[1]), [i // 2 for i in range(16)])

    def test_miss_limit_falls_every_three_tables(self):
        mm.MemoryMosaic.origins = [0] * 10
        limits = []
        for level in range(mm.LEVELS):
            port = PortModel(mm.MemoryMosaic(), mm.LEVELS)
            port.level = level
            port.new_level()
            limits.append(port.game.limit)
        self.assertEqual(limits, [12, 12, 12, 11, 11, 11, 10, 10, 10, 9])

    def test_unmatched_pair_closes_on_the_next_return(self):
        mm.MemoryMosaic.origins = [9]
        port = PortModel(mm.MemoryMosaic(), mm.LEVELS)
        port.key(0x0d)
        b = port.game.b
        other = next(i for i in range(1, 16) if b[i] != b[0])
        port.key(0x0d)
        port.game.cursor = other
        port.key(0x0d)
        self.assertEqual((port.game.errors, port.game.c[0], port.game.c[other]), (1, 1, 1))
        port.key(0x0d)
        self.assertEqual((port.game.c[0], port.game.c[other], port.game.first), (0, 0, 255))


class MemoryMosaicExpectationTests(unittest.TestCase):
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

    def test_all_tables_and_loss_are_covered(self):
        campaign = self.profiles['synthetic-all-tables']
        self.assertEqual(len(origins(campaign)), 10)
        memory = campaign['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '09'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), mm.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
