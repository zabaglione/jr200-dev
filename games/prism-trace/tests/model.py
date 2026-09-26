# SPDX-License-Identifier: MIT
"""PRISM TRACE rules model (jr100dev games/prism_trace/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: cursor, turns, then b[49] (1 '/', 2 '\\'),
c[49] (beam sides: 1 up, 2 down, 4 left, 8 right) and d[49] (entry sides seen).

`frames` counts the animation frames an action plays (not part of the state).
"""
from itertools import combinations

LEVELS = 1
START, RECEIVER = 21, 6
MIRRORS = {23: 1, 37: 1, 40: 2, 12: 1, 8: 2, 1: 2}
INCOMING = {1: 2, 2: 1, 3: 8, 4: 4}
SLASH = {1: 4, 2: 3, 3: 2, 4: 1}
BACKSLASH = {1: 3, 2: 4, 3: 1, 4: 2}


def move(pos, action):
    if action == 1 and pos >= 7:
        return pos - 7
    if action == 2 and pos < 42:
        return pos + 7
    if action == 3 and pos % 7:
        return pos - 1
    if action == 4 and pos % 7 < 6:
        return pos + 1
    return pos


def trace(b):
    """(c, d, reached, frames) of the beam through mirrors b (frames as when turned)."""
    c, d = [0] * 49, [0] * 49
    p, direction, frames = START, 4, 0
    for _ in range(64):
        incoming = INCOMING[direction]
        if d[p] & incoming:
            return c, d, False, frames
        d[p] |= incoming
        if p == RECEIVER:
            c[p] = incoming
            return c, d, True, frames + 4
        if b[p] == 1:
            direction = SLASH[direction]
        elif b[p] == 2:
            direction = BACKSLASH[direction]
        c[p] |= incoming | 1 << (direction - 1)
        frames += 4 if b[p] else 1
        n = move(p, direction)
        if n == p:
            return c, d, False, frames
        p = n
    return c, d, False, frames


class PrismTrace:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.cursor = self.turns = 0
        self.b = [0] * 49
        self.c = [0] * 49
        self.d = [0] * 49
        self.frames = 0

    def run_trace(self):
        self.c, self.d, reached, frames = trace(self.b)
        if self.turns:
            self.frames += frames
        if reached:
            self.port.win()

    def init(self):
        for cell, kind in MIRRORS.items():
            self.b[cell] = kind
        self.run_trace()

    def act(self, action):
        self.frames = 0
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5 and self.b[self.cursor]:
            self.b[self.cursor] = 3 - self.b[self.cursor]
            self.turns += 1
            self.run_trace()

    def state_bytes(self):
        return bytes([self.cursor, self.turns] + self.b + self.c + self.d).hex()


def plan():
    """Fewest mirrors to turn; no smaller set reaches the receiver, so none wins early."""
    cells = sorted(MIRRORS)
    for size in range(1, len(cells) + 1):
        for chosen in combinations(cells, size):
            b = [0] * 49
            for cell, kind in MIRRORS.items():
                b[cell] = 3 - kind if cell in chosen else kind
            if trace(b)[2]:
                return list(chosen)
    return None
