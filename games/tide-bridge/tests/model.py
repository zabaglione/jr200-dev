# SPDX-License-Identifier: MIT
"""TIDE BRIDGE rules model (jr100dev games/tide_bridge/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: pos, origin, facing, cursor, moves, axis,
walking, half, arrived, hop, then b[36] (3 plank, 0 water).

`frames` counts the animation frames an action plays (not part of the state).
"""
from itertools import combinations

LEVELS = 3
START = 30
GATE = 5
LIMIT = 30
FIELDS = ('pos', 'origin', 'facing', 'cursor', 'moves', 'axis', 'walking', 'half',
          'arrived', 'hop')


def move(pos, action):
    if action == 1 and pos >= 6:
        return pos - 6
    if action == 2 and pos < 30:
        return pos + 6
    if action == 3 and pos % 6:
        return pos - 1
    if action == 4 and pos % 6 < 5:
        return pos + 1
    return pos


def board(level):
    return [3 if (i // 6 + i % 6 + level) % 3 == 0 else 0 for i in range(36)]


def route(b):
    """Upstream breadth-first search from the shore: the cells to the gate, or None."""
    parent = {START: None}
    queue = [START]
    for p in queue:
        for action in (1, 2, 3, 4):
            n = move(p, action)
            if n not in parent and (b[n] or n == GATE):
                parent[n] = p
                queue.append(n)
    if GATE not in parent:
        return None
    cells = []
    target = GATE
    while target != START:
        cells.append(target)
        target = parent[target]
    return cells[::-1]


def toggle(b, axis, line):
    for i in range(6):
        n = line * 6 + i if axis == 0 else i * 6 + line
        b[n] = 0 if b[n] else 3


class TideBridge:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 36
        self.frames = 0

    def init(self):
        self.b = board(self.port.level)
        self.pos = self.origin = START
        self.facing = 2

    def act(self, action):
        self.frames = 0
        if action == 1:
            self.cursor = (self.cursor + 5) % 6
        if action == 2:
            self.cursor = (self.cursor + 1) % 6
        if action in (3, 4):
            self.axis ^= 1
        if action == 5:
            toggle(self.b, self.axis, self.cursor)
            self.moves += 1
            self.connected()
            if self.moves >= LIMIT and self.port.mode == 1:
                self.port.lose()

    def connected(self):
        cells = route(self.b)
        if cells is None:
            return
        self.walking = 1
        self.frames += 8
        for target in cells:
            self.facing = 1 if target < self.pos else 2
            if target // 6 == self.pos // 6:
                self.facing = 3 if target < self.pos else 4
            self.origin = self.pos
            self.pos = target
            self.frames += 6
        self.arrived = 1
        self.facing = 5
        self.hop = 0
        self.frames += 32 + 6
        self.port.win()

    def state_bytes(self):
        return bytes([getattr(self, name) for name in FIELDS] + self.b).hex()


def plan(level):
    """Fewest (axis, line) toggles that link the shore to the gate.

    No proper subset links, so no earlier toggle in the list wins early."""
    lines = [(axis, line) for axis in (0, 1) for line in range(6)]
    for size in range(1, 13):
        for chosen in combinations(lines, size):
            b = board(level)
            for axis, line in chosen:
                toggle(b, axis, line)
            if route(b):
                return list(chosen)
    return None
