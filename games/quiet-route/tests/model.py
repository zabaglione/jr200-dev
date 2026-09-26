# SPDX-License-Identifier: MIT
"""Independent state model of jr100dev QUIET ROUTE 2.0.0 rules."""

BATTERY_LOSS = 'BATTERY EXHAUSTED'
GUARD_LOSS = 'CAUGHT BY THE GUARD'


def move(pos, action):
    row, col = divmod(pos, 8)
    if action == 1 and row > 0:
        return pos - 8
    if action == 2 and row < 7:
        return pos + 8
    if action == 3 and col > 0:
        return pos - 1
    if action == 4 and col < 7:
        return pos + 1
    return pos


def distance(a, b):
    ay, ax = divmod(a, 8)
    by, bx = divmod(b, 8)
    return abs(ax - bx) + abs(ay - by)


def board_for_level(level):
    board = [int(row in (0, 7) or col in (0, 7))
             for row in range(8) for col in range(8)]
    top_gap = (1 + level * 2) % 6
    bottom_gap = (4 + level) % 6
    for i in range(6):
        board[25 + i] = int(i != top_gap)
        board[41 + i] = int(i != bottom_gap)
    board[14] = 3
    board[54] = 6
    return board


class QuietRoute:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.board = [0] * 64
        self.pos = self.origin = self.guard = self.guard_origin = 0
        self.guard_face = self.direction = self.battery = self.cache = 0
        self.quiet = self.key = self.intel = self.alert = self.facing = 0
        self.loss = None

    def init(self):
        level = self.port.level
        self.board = board_for_level(level)
        self.pos = self.origin = 9
        self.guard = self.guard_origin = 49 + level
        self.guard_face = self.direction = 4
        self.facing = 2
        self.battery = 42 - level * 2
        self.cache = 33 + level

    def act(self, action):
        if action == 5:
            self.quiet ^= 1
            return
        if not 1 <= action <= 4:
            return
        self.facing = action
        nxt = move(self.pos, action)
        if self.board[nxt] == 1:
            return
        self.origin, self.pos = self.pos, nxt
        cost = 2 if self.quiet else 1
        if self.battery <= cost:
            self.origin = self.pos
            self.port.lose(BATTERY_LOSS)
            return
        self.battery -= cost
        if self.pos == 14 and not self.key:
            self.key = 1
        if self.pos == self.cache:
            self.cache = 255
            self.intel = 1
            self.battery = min(50, self.battery + 6)
        if self.pos == 54 and self.key:
            self.origin = self.pos
            self.port.win()
            return
        self.alert = int(distance(self.pos, self.guard) < (2 if self.quiet else 5))
        self.origin = self.pos
        if self.alert:
            py, px = divmod(self.pos, 8)
            gy, gx = divmod(self.guard, 8)
            action = 1 if gy > py else (2 if gy < py else (3 if gx > px else 4))
        else:
            if self.guard == 49:
                self.direction = 4
            if self.guard == 54:
                self.direction = 3
            action = self.direction
        self.guard_face = action
        nxt = move(self.guard, action)
        if self.board[nxt] != 1:
            self.guard_origin, self.guard = self.guard, nxt
        self.guard_origin = self.guard
        if self.pos == self.guard:
            self.port.lose(GUARD_LOSS)

    def state_bytes(self):
        state = (self.board + [self.pos, self.origin, self.guard, self.guard_origin,
                               self.guard_face, self.direction, self.battery, self.cache,
                               self.quiet, self.key, self.intel, self.alert, self.facing])
        return bytes(state).hex()
