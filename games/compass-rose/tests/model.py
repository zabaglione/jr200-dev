# SPDX-License-Identifier: MIT
"""COMPASS ROSE rules model (jr100dev games/compass_rose/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: facing, pos, origin, target, fuel, digs,
surveys, survey_pos, north, east, band, scanning, digging, dig_frame, then one
byte per cell: bit 0 visited (upstream b), bit 1 rock (c), bit 2 dug (d).
"""
from collections import deque

GOALS = [13, 63, 60, 59, 61, 3, 57, 50, 58, 52]
LEVELS = 10
START = 27
OUT_OF_SUPPLIES = 'OUT OF TRAVEL SUPPLIES'
NO_DIGS = 'NO DIGS REMAIN'
EXTRA_KEYS = {'x': 7}
FIELDS = ('facing', 'pos', 'origin', 'target', 'fuel', 'digs', 'surveys', 'survey_pos',
          'north', 'east', 'band', 'scanning', 'digging', 'dig_frame')


def distance(a, b):
    return abs(a // 8 - b // 8) + abs(a % 8 - b % 8)


def move(pos, action):
    if action == 1 and pos >= 8:
        return pos - 8
    if action == 2 and pos < 56:
        return pos + 8
    if action == 3 and pos % 8:
        return pos - 1
    if action == 4 and pos % 8 < 7:
        return pos + 1
    return pos


def rocks(level):
    c = [0] * 64
    for i in range(6):
        c[17 + i] = 1 if i != level % 6 else 0
        c[41 + i] = 1 if i != (level + 3) % 6 else 0
    c[GOALS[level]] = 0
    return c


class CompassRose:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 64
        self.c = [0] * 64
        self.d = [0] * 64

    def init(self):
        level = self.port.level
        self.facing = 2
        self.pos = self.origin = START
        self.target = GOALS[level]
        self.fuel = 32
        self.digs = 3
        self.c = rocks(level)
        self.b[self.pos] = 1
        self.surveys = 4
        self.survey()

    def survey(self):
        t, p = self.target, self.pos
        self.north = 1 if t // 8 < p // 8 else (2 if t // 8 > p // 8 else 0)
        self.east = 1 if t % 8 < p % 8 else (2 if t % 8 > p % 8 else 0)
        self.survey_pos = p
        dist = distance(p, t)
        self.band = 0 if dist <= 2 else (1 if dist <= 5 else 2)

    def act(self, action):
        if action == 7 and self.surveys and self.fuel > 2:
            self.surveys -= 1
            self.fuel -= 2
            self.scanning = 0
            self.survey()
        if action < 5:
            self.facing = action
            target = move(self.pos, action)
            if target == self.pos or self.c[target]:
                return
            self.pos = self.origin = target
            self.b[self.pos] = 1
            self.fuel -= 1
            if self.fuel == 0:
                self.port.lose(OUT_OF_SUPPLIES)
        if action == 5:
            self.dig_frame = 2
            self.digging = 0
            self.d[self.pos] = 1
            if self.pos == self.target:
                self.port.win()
            else:
                self.digs -= 1
                if self.digs == 0:
                    self.port.lose(NO_DIGS)

    def state_bytes(self):
        cells = [self.b[i] | self.c[i] << 1 | self.d[i] << 2 for i in range(64)]
        return bytes([getattr(self, name) for name in FIELDS] + cells).hex()


def path(level, start=START):
    """Shortest list of actions (1-4) from start to the goal around the rocks."""
    c = rocks(level)
    goal = GOALS[level]
    prev = {start: None}
    queue = deque([start])
    while queue:
        pos = queue.popleft()
        if pos == goal:
            break
        for action in (1, 2, 3, 4):
            nxt = move(pos, action)
            if nxt != pos and not c[nxt] and nxt not in prev:
                prev[nxt] = (pos, action)
                queue.append(nxt)
    actions = []
    pos = goal
    while prev[pos]:
        pos, action = prev[pos]
        actions.append(action)
    return actions[::-1]
