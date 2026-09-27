# SPDX-License-Identifier: MIT
"""LOOP TEN rules model (jr100dev games/loop_ten/src/main.asm and clock.asm 1.6.1).

Upstream has no Python rules module; this model follows the upstream M6800
source (REWIND, GAME_INPUT, MOVE_TEST, GATE, HAZARD, INTERACT, the anchor
scan, TIMER_TICK and the held-key repeat) and its check_rules.py / replay.py.

Upstream counts 60 ticks a second: ten seconds are 600 ticks and a held
direction repeats every 6 ticks. One tick here is 6 upstream ticks (0.1 s):
`time` starts at 100, a held direction repeats every tick once the key has
been held for a tick, and `seconds` is ceil(time / 10) as upstream draws it.
Effects pause the clock, as upstream FX_BEGIN/FX_END freeze gameplay time.

state_bytes() mirrors src/main.asm: room, x, y, flags (2, seal i is bit i),
loops, time, since (ticks since the last move), held, seconds.
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'loop_ten_rooms', Path(__file__).resolve().parent / 'rooms.py')
_rooms = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rooms)

LEVELS = 1
CHAMBERS = [['.#S.GH.A'.index(c) if c != 'A' else 6 for c in cells]
            for _, cells in _rooms.ROOMS]
NAMES = [name for name, _ in _rooms.ROOMS]
WALL, SEAL, GATE, HAZARD, ANCHOR = 1, 2, 4, 5, 6
START = (2, 4)
SEAL_AT = (12, 4)
LOOP_TICKS = 100
MOVES = {1: (0, -1), 2: (0, 1), 3: (-1, 0), 4: (1, 0)}
LAYOUT = [('room', 1), ('x', 1), ('y', 1), ('flags', 2), ('loops', 1), ('time', 1),
          ('since', 1), ('held', 1), ('seconds', 1)]
SIZE = sum(n for _, n in LAYOUT)


class LoopTen:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)

    def init(self):
        self.flags = [0, 0]
        self.loops = 0
        self.rewind()

    def rewind(self):
        self.room = 0
        self.loops = min(self.loops + 1, 255)
        self.x, self.y = START
        self.time = LOOP_TICKS
        self.seconds = 10
        self.since = 0

    def lit(self, room):
        return self.flags[room >> 3] >> (room & 7) & 1

    def act(self, action):
        self.since = 0
        if action == 6:
            self.rewind()
        elif action == 5:
            self.interact()
        elif action in MOVES:
            self.move(action)

    def move(self, action):
        dx, dy = MOVES[action]
        x, y = self.x + dx, self.y + dy
        cell = CHAMBERS[self.room][y * 16 + x]
        if cell == WALL:
            return False
        if cell == HAZARD:
            self.rewind()
            return True
        if cell == GATE:
            if self.lit(self.room):
                self.room += 1
                self.x, self.y = 1, 4
        else:
            self.x, self.y = x, y
        return False

    def interact(self):
        if (self.x, self.y) == START:
            for room in range(12):
                if not self.lit(room):
                    self.room = room
                    return
            return
        if abs(self.x - SEAL_AT[0]) + abs(self.y - SEAL_AT[1]) > 1:
            return
        if self.lit(self.room):
            self.rewind()
            return
        self.flags[self.room >> 3] |= 1 << (self.room & 7)
        if self.room == 11:
            self.port.win()

    def tick(self):
        self.time -= 1
        if self.time == 0:
            self.rewind()
            return
        self.seconds = (self.time + 9) // 10
        self.since = min(self.since + 1, 255)
        if self.held in MOVES and self.since >= 2 and not self.move(self.held):
            self.since = 1      # a rewind (hazard) restarts the count at 0

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(v & 0xff for v in out).hex()
