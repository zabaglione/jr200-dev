# SPDX-License-Identifier: MIT
"""MIRROR RELIC rules model (jr100dev games/mirror_relic/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: facing, pos, origin, left, turns, phase,
rotating, then b[64] and c[64].
"""
from collections import deque

RELICS = [10, 21, 42, 0, 14, 49, 17, 6, 61, 8, 23, 40, 2, 13, 57, 16, 7, 48]
PASSAGES = [19, 43, 26, 29]
LEVELS = 6
EXIT = 53
LIMIT = 20
LOSS = 'TWENTY ROTATIONS BEFORE EXIT'
EXTRA_KEYS = {'x': 7}


def move(pos, action, width=8, height=8):
    if action == 1 and pos >= width:
        return pos - width
    if action == 2 and pos < width * (height - 1):
        return pos + width
    if action == 3 and pos % width > 0:
        return pos - 1
    if action == 4 and pos % width < width - 1:
        return pos + 1
    return pos


def turn(pos, action):
    if action == 5:
        return (pos % 8) * 8 + 7 - pos // 8
    return (7 - pos % 8) * 8 + pos // 8


def hall(level):
    b = [1 if i % 8 == 3 or i // 8 == 3 else 0 for i in range(64)]
    for i in PASSAGES:
        b[i] = 0
    b[EXIT] = 6
    c = [0] * 64
    for k in range(3):
        c[RELICS[level * 3 + k]] = 1 + (level + 1 + k) % 4
    return b, c


class MirrorRelic:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.b = [0] * 64
        self.c = [0] * 64
        self.facing = self.pos = self.origin = self.left = 0
        self.turns = self.phase = self.rotating = 0

    def init(self):
        self.facing = 2
        self.b, self.c = hall(self.port.level)
        self.pos = self.origin = 54
        self.left = 3

    def act(self, action):
        if action < 5:
            self.facing = action
            n = move(self.pos, action)
            if self.b[n] != 1:
                self.origin = self.pos = n
        if action in (5, 7):
            n = turn(self.pos, action)
            if self.b[n] != 1:
                self.pos = self.origin = n
                self.turns += 1
                self.phase = (self.phase + (1 if action == 5 else 3)) % 4
        if self.c[self.pos] == self.phase + 1:
            self.c[self.pos] = 0
            self.left -= 1
        if self.pos == EXIT and self.left == 0:
            self.port.win()
        elif self.turns >= LIMIT:
            self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([self.facing, self.pos, self.origin, self.left, self.turns,
                      self.phase, self.rotating] + self.b + self.c).hex()


def solve(level):
    """Fewest actions (1-4 walk, 5 clockwise, 7 counterclockwise) to win."""
    b, c = hall(level)
    relic = {p: v for p, v in enumerate(c) if v}
    start = (54, 0, 0, 0)            # pos, phase, collected mask, turns
    order = sorted(relic)
    previous = {start: None}
    queue = deque([start])
    while queue:
        state = queue.popleft()
        pos, phase, mask, turns = state
        for action in (1, 2, 3, 4, 5, 7):
            npos, nphase, nturns = pos, phase, turns
            if action < 5:
                n = move(pos, action)
                if b[n] != 1:
                    npos = n
            else:
                n = turn(pos, action)
                if b[n] != 1:
                    npos = n
                    nturns += 1
                    nphase = (phase + (1 if action == 5 else 3)) % 4
            nmask = mask
            if npos in relic and not mask & (1 << order.index(npos)) \
                    and relic[npos] == nphase + 1:
                nmask |= 1 << order.index(npos)
            if npos == EXIT and nmask == 7:
                path = [action]
                while previous[state]:
                    state, act = previous[state]
                    path.append(act)
                return path[::-1]
            if nturns >= LIMIT:
                continue
            key = (npos, nphase, nmask, nturns)
            if key not in previous:
                previous[key] = (state, action)
                queue.append(key)
    return None
