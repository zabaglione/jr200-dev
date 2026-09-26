# SPDX-License-Identifier: BSD-3-Clause
"""TIDAL NETS: upstream tides, nets and quotas, replays and three-voice sound."""
import json
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/tidal-nets'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PortModel, check_expectations, load_game_model  # noqa: E402

tn = load_game_model('tidal-nets')


def new_port():
    return PortModel(tn.TidalNets(), tn.LEVELS)


class TidalNetsRuleTests(unittest.TestCase):
    def test_tide_cycle_and_quotas(self):
        self.assertEqual([tn.tide_of(c, 0) for c in range(6)],
                         [(1, 1), (7, 2), (7, 1), (1, 2), (7, 1), (7, 2)])
        port = new_port()
        for level, quota in enumerate((30, 33, 36)):
            port.level = level
            port.new_level()
            self.assertEqual((port.game.quota, port.game.rope), (quota, 12))

    def test_deep_fish_drift_twice_as_far(self):
        (fish, deep, rope, casts, catch), gain = tn.cast((3, 1, 12, 0, 0), 0, 4, 0)
        # tide 1, force 1: the shoal lands on 4 (+2 under the net), the deep fish on 3.
        self.assertEqual((gain, rope, casts), (2, 11, 1))
        self.assertEqual((fish, deep), ((4 * 3 + 5) % 8, (3 * 5 + 3) % 8))

    def test_wide_net_needs_two_rope(self):
        port = new_port()
        port.key(0x0d)
        port.game.rope = 1
        port.key(ord('w'))
        port.key(0x0d)
        self.assertEqual((port.game.notice, port.game.casts, port.game.rope), (7, 0, 1))

    def test_every_trip_has_a_quota_plan(self):
        for level in range(tn.LEVELS):
            self.assertIsNotNone(tn.plan(level))


class TidalNetsExpectationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expectations = json.loads((PROJECT / 'tests/expectations.json').read_text())
        cls.profiles = {p['profile']: p for p in cls.expectations['runtime']['profiles']}

    def test_memory_expectations_are_model_predictions(self):
        check_expectations(self, self.expectations, new_port)

    def test_all_trips_and_loss_are_covered(self):
        memory = self.profiles['synthetic-all-trips']['expect']['memory']
        self.assertEqual((memory['mode'], memory['level']), ('04', '02'))
        lost = self.profiles['synthetic-lose']['expect']['memory']
        self.assertEqual(bytes.fromhex(lost['status']).decode(), tn.LOSS)

    def test_three_voice_title_and_jingle_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-clear'):
            self.assertEqual(self.profiles[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.profiles['synthetic-exit']['expect']['memory']
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
