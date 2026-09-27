# SPDX-License-Identifier: MIT
"""PHASE PAIRS rules model (jr100dev games/phase_pairs/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: cursor, left, first, errors, reject,
merging, ax, ay, bx, by, cx, cy, then b[16] (numbers, 0 removed) and c[16]
(neighbours that make ten with the first pick).

LEVELS_DATA and SOLUTIONS are upstream levels.json and solutions.json.
`frames` counts the animation frames an action plays (not part of the state).
"""

LEVELS = 10
FIELDS = ('cursor', 'left', 'first', 'errors', 'reject', 'merging', 'ax', 'ay', 'bx', 'by',
          'cx', 'cy')
LEVELS_DATA = [
    [6, 4, 6, 4, 6, 4, 1, 3, 1, 3, 9, 7, 9, 7, 8, 2],
    [8, 3, 7, 5, 2, 4, 6, 5, 7, 6, 4, 7, 3, 4, 6, 3],
    [9, 1, 9, 3, 5, 5, 1, 7, 6, 7, 5, 5, 4, 3, 3, 7],
    [8, 2, 6, 4, 5, 5, 2, 6, 6, 4, 8, 4, 4, 6, 5, 5],
    [1, 9, 4, 6, 8, 2, 2, 8, 3, 9, 5, 5, 7, 1, 9, 1],
    [6, 4, 8, 2, 9, 1, 2, 8, 6, 9, 9, 1, 4, 1, 3, 7],
    [6, 6, 6, 7, 4, 4, 4, 3, 5, 5, 1, 4, 5, 5, 9, 6],
    [2, 8, 9, 1, 6, 5, 5, 9, 4, 6, 4, 1, 4, 6, 9, 1],
    [2, 8, 7, 3, 8, 2, 6, 4, 8, 2, 3, 7, 2, 8, 3, 7],
    [3, 9, 1, 2, 7, 6, 4, 8, 2, 4, 6, 9, 8, 5, 5, 1],
]
SOLUTIONS = [
    [[0, 1], [2, 3], [4, 5], [6, 10], [7, 11], [8, 12], [9, 13], [14, 15]],
    [[0, 4], [1, 2], [3, 7], [5, 9], [6, 10], [8, 12], [11, 15], [13, 14]],
    [[0, 1], [2, 6], [3, 7], [4, 5], [8, 12], [9, 13], [10, 11], [14, 15]],
    [[0, 1], [2, 3], [4, 5], [6, 10], [7, 11], [8, 9], [12, 13], [14, 15]],
    [[0, 1], [2, 3], [4, 5], [6, 7], [8, 12], [9, 13], [10, 11], [14, 15]],
    [[0, 1], [2, 6], [3, 7], [4, 5], [8, 12], [9, 13], [10, 11], [14, 15]],
    [[0, 4], [1, 5], [2, 6], [3, 7], [8, 9], [10, 14], [11, 15], [12, 13]],
    [[0, 1], [2, 3], [4, 8], [5, 6], [7, 11], [9, 10], [12, 13], [14, 15]],
    [[0, 4], [1, 5], [2, 3], [6, 7], [8, 12], [9, 13], [10, 11], [14, 15]],
    [[0, 4], [1, 2], [3, 7], [5, 9], [6, 10], [8, 12], [11, 15], [13, 14]],
]


def move(pos, action):
    if action == 1 and pos >= 4:
        return pos - 4
    if action == 2 and pos < 12:
        return pos + 4
    if action == 3 and pos % 4:
        return pos - 1
    if action == 4 and pos % 4 < 3:
        return pos + 1
    return pos


def toward(value, target):
    return value + 1 if value < target else value - 1 if value > target else value


class PhasePairs:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 16
        self.c = [0] * 16
        self.frames = 0

    def init(self):
        self.b = list(LEVELS_DATA[self.port.level])
        self.left = 16
        self.first = 255

    def act(self, action):
        self.frames = 0
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action != 5 or not self.b[self.cursor]:
            return
        if self.first == 255:
            self.first = self.cursor
            for a in range(4):
                n = move(self.first, a + 1)
                if n != self.first and self.b[n] + self.b[self.first] == 10:
                    self.c[n] = 1
            return
        valid = any(self.first != self.cursor and move(self.first, a + 1) == self.cursor
                    for a in range(4))
        if valid and self.b[self.first] + self.b[self.cursor] == 10:
            self.ax = 2 + self.first % 4 * 4
            self.ay = 4 + self.first // 4 * 4
            self.bx = 2 + self.cursor % 4 * 4
            self.by = 4 + self.cursor // 4 * 4
            self.cx = (self.ax + self.bx) // 2
            self.cy = (self.ay + self.by) // 2
            self.ax, self.ay = toward(self.ax, self.cx), toward(self.ay, self.cy)
            self.bx, self.by = toward(self.bx, self.cx), toward(self.by, self.cy)
            self.frames += 4 + 9 + 16
            self.b[self.first] = self.b[self.cursor] = 0
            self.left -= 2
            self.merging = 0
        else:
            self.errors += 1
            self.frames += 18
            self.reject = 0
        self.first = 255
        self.c = [0] * 16
        if self.left == 0:
            self.port.win()
        elif self.errors >= 6:
            self.port.lose()

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.c).hex()
