# SPDX-License-Identifier: MIT
"""RUIN LEXICON rules model (jr100dev games/ruin_lexicon/rules.py 2.1.0).

state_bytes() mirrors src/main.asm: cursor, turning, check, errors, then b[4]
(your values) and d[4] (the inscription's values).

`frames` counts the animation frames an action plays (not part of the state).
"""

TABLE = [1, 2, 4, 3, 1, 3, 2, 4, 1, 3, 4, 2, 1, 4, 2, 3, 1, 4, 3, 2, 2, 1, 3, 4, 2, 3, 1, 4,
         2, 3, 4, 1, 2, 4, 1, 3, 2, 4, 3, 1, 3, 1, 2, 4, 3, 1, 4, 2, 3, 2, 1, 4, 3, 2, 4, 1,
         3, 4, 2, 1, 4, 1, 2, 3, 4, 1, 3, 2, 4, 2, 1, 3, 4, 2, 3, 1, 4, 3, 1, 2]
LEVELS = 20
LOSS = 'FIVE DICTIONARIES REJECTED'
FIELDS = ('cursor', 'turning', 'check', 'errors')


class RuinLexicon:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 4
        self.d = [0] * 4
        self.frames = 0

    def init(self):
        level = self.port.level
        self.d = TABLE[level * 4:level * 4 + 4]
        self.b = [1] * 4

    def act(self, action):
        self.frames = 0
        if action == 3:
            self.cursor = (self.cursor + 3) % 4
        if action == 4:
            self.cursor = (self.cursor + 1) % 4
        if action in (1, 2):
            self.frames += 4
        if action == 1:
            self.b[self.cursor] = self.b[self.cursor] % 4 + 1
        if action == 2:
            self.b[self.cursor] = (self.b[self.cursor] + 2) % 4 + 1
        if action == 5:
            self.frames += 32
            self.check = 0
            if self.b == self.d:
                self.port.win()
            else:
                self.errors += 1
                if self.errors == 5:
                    self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.d).hex()


def clues(level):
    """The three pair sums and whether A < D, as the inscription shows them."""
    d = TABLE[level * 4:level * 4 + 4]
    return [d[i] + d[i + 1] for i in range(3)], d[0] < d[3]


def solve(level):
    """The only permutation of 1-4 that fits the clues (the upstream tables are unique)."""
    from itertools import permutations
    sums, less = clues(level)
    fits = [list(p) for p in permutations((1, 2, 3, 4))
            if [p[i] + p[i + 1] for i in range(3)] == sums and (p[0] < p[3]) == less]
    assert len(fits) == 1, (level, fits)
    return fits[0]
