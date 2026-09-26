# SPDX-License-Identifier: MIT
"""CHAIN SUIT rules model (jr100dev games/chain_suit/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: target, round, draws, discards, scoring,
points, hand, cursor, flipping, score, blink, then b[5] ranks, c[5] suits and
d[5] matching marks.

`frames` counts the animation frames an action plays (not part of the state).
"""
from itertools import product

LEVELS = 1
BEST_PLAN = [[0, 2], [0, 2], [4, 0]]     # plan(): 48 points
LOSS = 'TOTAL BELOW 25'
FIELDS = ('target', 'round', 'draws', 'discards', 'scoring', 'points', 'hand', 'cursor',
          'flipping', 'score', 'blink')
HANDS = ('NO PAIR', 'ONE PAIR', 'TWO PAIRS', 'THREE OF A KIND', 'FULL HOUSE',
         'FOUR OF A KIND', 'FIVE OF A KIND', 'FLUSH / SAME SUIT')
REDRAW_FRAMES = 6 + 6 + 6 + 8
SCORE_FRAMES = 2 * (12 + 12) + 60


def evaluate(b, c):
    """(points, hand, d) of five ranks b and suits c."""
    pairs = largest = 0
    d = [0] * 5
    for i in range(5):
        count = 0
        for j in range(5):
            if b[i] == b[j]:
                count += 1
                if i < j:
                    pairs += 1
        d[i] = 1 if count > 1 else 0
        largest = max(largest, count)
    points, hand = 3, 0
    if pairs == 1:
        points, hand = 8, 1
    if pairs >= 2:
        points, hand = 16, 2
        if largest == 3:
            hand = 4 if pairs == 4 else 3
        if largest == 4:
            hand = 5
        if largest == 5:
            hand = 6
    if all(s == c[0] for s in c):
        points, hand = 25, 7
        d = [1] * 5
    return points, hand, d


class ChainSuit:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 5
        self.c = [0] * 5
        self.d = [0] * 5
        self.frames = 0

    def evaluate(self):
        self.points, self.hand, self.d = evaluate(self.b, self.c)

    def deal(self):
        for i in range(5):
            self.b[i] = 1 + (self.round * 3 + i * 5 + self.draws * 7) % 13
            self.c[i] = (i + self.round + self.draws) % 4
        self.discards = 2
        self.scoring = 0
        self.evaluate()

    def init(self):
        self.target = 25
        self.deal()

    def act(self, action):
        self.frames = 0
        if action == 3:
            self.cursor = (self.cursor + 4) % 5
        if action == 4:
            self.cursor = (self.cursor + 1) % 5
        if action == 1 and self.discards:
            self.draws += 1
            self.b[self.cursor] = 1 + (self.draws * 7 + self.cursor * 3 + self.round) % 13
            self.c[self.cursor] = (self.draws + self.cursor) % 4
            self.discards -= 1
            self.flipping = 0
            self.evaluate()
            self.frames += REDRAW_FRAMES
        if action == 5:
            self.scoring = 1
            self.score += self.points
            self.blink = 0
            self.frames += SCORE_FRAMES
            self.round += 1
            if self.round == 3:
                if self.score >= self.target:
                    self.port.win()
                else:
                    self.port.lose(LOSS)
            else:
                self.deal()

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.c + self.d).hex()


def plan():
    """Redraw choices per hand (lists of card positions) with the highest total."""
    from port_model import PortModel
    options = [[]] + [[a] for a in range(5)] + [list(p) for p in product(range(5), repeat=2)]
    best = None
    for choice in product(options, repeat=3):
        port = PortModel(ChainSuit(), LEVELS)
        port.new_level()
        g = port.game
        for hand in choice:
            for pos in hand:
                g.cursor = pos
                g.act(1)
            g.act(5)
        if best is None or g.score > best[0] or (g.score == best[0] and
                                                 sum(map(len, choice)) < best[2]):
            best = (g.score, [list(h) for h in choice], sum(map(len, choice)))
    return best[1], best[0]
