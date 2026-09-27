# SPDX-License-Identifier: BSD-3-Clause
"""sdk/ranked.inc model: upstream progress codes and the campaign key flow."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ranked_model as rm  # noqa: E402

# Codes from upstream games/native/password.py (zabaglione/jr100dev@9a3921c).
VECTORS = [
    (0, [0] * 40, 0x41, 'AAQA'),
    (12, [3] * 10 + [2, 1] + [0] * 28, 0x41, 'KQGMKQ'),
    (20, [3] * 20 + [0] * 20, 0x41, 'MFNHK'),
    (39, [3] * 40, 0x62, 'TJFAE'),
    (5, [1, 2, 3, 0] * 10, 0x83, 'AGHQHQHQHQHQHQHQHQHQHQGK'),
    (33, [3] * 32 + [2] + [0] * 7, 0xA4, 'TCAKDD'),
]


class Stub:
    """A game that clears on RETURN with a set number of moves and runes."""

    port = None

    def reset(self):
        self.moves = self.overflow = self.runes = self.stars = 0
        self.par = 3

    def init(self):
        pass

    def act(self, action):
        if action == 1:
            self.moves += 1
        if action == 2:
            self.runes = 3
        if action == 5:
            self.port.rank_clear()


def keys(port, text):
    for ch in text:
        port.key({'\n': 0x0d, ' ': 0x20, '<': 0x08}.get(ch, ord(ch)))


class RankedCodeTests(unittest.TestCase):
    def test_upstream_vectors(self):
        for level, ratings, tag, code in VECTORS:
            values = rm.encode(level, ratings, tag)
            self.assertEqual(rm.letters(values), code)
            self.assertEqual(rm.decode(values, tag, 40), (level, ratings))

    def test_damaged_codes_and_other_games_are_refused(self):
        values = rm.encode(12, [3] * 10 + [2, 1] + [0] * 28, 0x41)
        self.assertIsNone(rm.decode(values[:-1] + [values[-1] ^ 1], 0x41, 40))
        self.assertIsNone(rm.decode(values, 0x62, 40))
        self.assertIsNone(rm.decode(values[:3], 0x41, 40))


class RankedFlowTests(unittest.TestCase):
    def new(self):
        return rm.RankedPortModel(Stub(), 40, 0x41)

    def test_rating_keeps_the_best(self):
        port = self.new()
        keys(port, '\nw\n')                # play; one move within par 3, no runes
        self.assertEqual((port.mode, port.game.stars, port.best[0]), (rm.CLEAR, 2, 2))
        keys(port, ' d\n')                 # retry (confirmed)
        keys(port, 'wwww\n')               # over par: one star, BEST stays 2
        self.assertEqual((port.game.stars, port.best[0]), (1, 2))
        keys(port, ' d\ns\n')              # both runes within par: three stars
        self.assertEqual(port.best[0], 3)

    def test_map_wraps_and_plays(self):
        port = self.new()
        keys(port, 'fwa')
        self.assertEqual((port.mode, port.level), (rm.MAP, 34))
        keys(port, 'sdd\n')
        self.assertEqual((port.mode, port.level), (rm.PLAY, 1))

    def test_password_restores_level_and_ratings(self):
        port = self.new()
        keys(port, 'xKQGMKQ\n')
        self.assertEqual((port.mode, port.level, port.best[:12]),
                         (rm.MAP, 12, [3] * 10 + [2, 1]))

    def test_password_editing_and_cancel(self):
        port = self.new()
        keys(port, 'xkqgmkz-')              # lower case types, Z is not a letter
        self.assertEqual(rm.letters(port.buffer), 'KQGM')
        keys(port, '\n')
        self.assertEqual((port.mode, port.error), (rm.PASSWORD, 1))
        keys(port, 'X')
        self.assertEqual(port.mode, rm.TITLE)


if __name__ == '__main__':
    unittest.main()
