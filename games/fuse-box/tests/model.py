# SPDX-License-Identifier: MIT
"""FUSE BOX rules model (jr100dev games/fuse_box/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: b[25], d[25], cursor, moves, flipping, flip_frame.
"""

LEVELS = 10


def move(pos, action, width=5, height=5):
    if action == 1 and pos >= width:
        return pos - width
    if action == 2 and pos < width * (height - 1):
        return pos + width
    if action == 3 and pos % width > 0:
        return pos - 1
    if action == 4 and pos % width < width - 1:
        return pos + 1
    return pos


def target(level):
    return [1 if (i * 3 + i // 5 + level) % 7 < 3 else 0 for i in range(25)]


def counts(board):
    rows = [sum(board[i * 5 + j] for j in range(5)) for i in range(5)]
    cols = [sum(board[j * 5 + i] for j in range(5)) for i in range(5)]
    return rows, cols


class FuseBox:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.b = [0] * 25
        self.d = [0] * 25
        self.cursor = self.moves = self.flipping = self.flip_frame = 0

    def init(self):
        self.d = target(self.port.level)

    def act(self, action):
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5:
            # The five-phase flip ends with flip_frame 5 (turning on) or 1 (off).
            self.flip_frame = 5 if self.b[self.cursor] == 0 else 1
            self.b[self.cursor] ^= 1
            self.moves = (self.moves + 1) & 0xff
            if counts(self.b) == counts(self.d):
                self.port.win()

    def state_bytes(self):
        return bytes(self.b + self.d + [self.cursor, self.moves, self.flipping,
                                        self.flip_frame]).hex()
