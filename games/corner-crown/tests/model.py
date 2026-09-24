# SPDX-License-Identifier: MIT
"""CORNER CROWN rules model (jr100dev games/corner_crown/rules.py 1.5.1).

Observed RAM layout of src/main.asm: b[64], cursor, white, black, placed,
placing, flip, flipping, flip_frame.
"""

LEVELS = 1
EMPTY, YOU, RIVAL = 0, 1, 2


def ray(pos, direction):
    x, y = pos % 8, pos // 8
    if direction == 0:
        return pos + 1 if x < 7 else 255
    if direction == 1:
        return pos - 1 if x > 0 else 255
    if direction == 2:
        return pos + 8 if y < 7 else 255
    if direction == 3:
        return pos - 8 if y > 0 else 255
    if direction == 4:
        return pos + 9 if x < 7 and y < 7 else 255
    if direction == 5:
        return pos - 9 if x > 0 and y > 0 else 255
    if direction == 6:
        return pos + 7 if x > 0 and y < 7 else 255
    return pos - 7 if x < 7 and y > 0 else 255


def move(pos, action):
    if action == 1 and pos >= 8:
        return pos - 8
    if action == 2 and pos < 56:
        return pos + 8
    if action == 3 and pos % 8 > 0:
        return pos - 1
    if action == 4 and pos % 8 < 7:
        return pos + 1
    return pos


class CornerCrown:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.b = [0] * 64
        self.cursor = self.white = self.black = 0
        self.placed = self.placing = self.flip = self.flipping = self.flip_frame = 0
        self.flipped = 0  # discs turned in the last act (for replay timing only)

    def ray_count(self, pos, direction, mark):
        p = ray(pos, direction)
        count = 0
        for _ in range(7):
            if p == 255 or self.b[p] == 0:
                return 0
            if self.b[p] == mark:
                return count
            count += 1
            p = ray(p, direction)
        return 0

    def flips(self, pos, mark, apply):
        if self.b[pos] != 0:
            return 0
        if apply:
            self.placed = pos
            self.placing = mark
        total = 0
        for direction in range(8):
            count = self.ray_count(pos, direction, mark)
            total += count
            if apply:
                p = pos
                for _ in range(count):
                    p = ray(p, direction)
                    self.flip = p
                    self.flip_frame = 5 if mark == 2 else 1  # last of five phases
                    self.b[p] = mark
                    self.flipping = 0
                    self.totals()
                    self.flipped += 1
        if apply and total:
            self.b[pos] = mark
            self.placing = 0
            self.totals()
        return total & 0xff

    def available(self, mark):
        return any(self.b[i] == 0 and self.flips(i, mark, 0) for i in range(64))

    def totals(self):
        self.white = sum(1 for v in self.b if v == 1)
        self.black = sum(1 for v in self.b if v == 2)

    def init(self):
        self.b[27] = 2
        self.b[28] = 1
        self.b[35] = 1
        self.b[36] = 2
        self.cursor = 19
        self.totals()

    def act(self, action):
        self.flipped = 0
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5:
            count = self.flips(self.cursor, 1, 0)
            if count == 0 and self.available(1):
                return 'illegal'
            if count:
                self.flips(self.cursor, 1, 1)
            best = 0
            chosen = 255
            for i in range(64):
                count = self.flips(i, 2, 0)
                if count > best:
                    best = count
                    chosen = i
            if chosen != 255:
                self.flips(chosen, 2, 1)
            self.totals()
            if not self.available(1) and not self.available(2):
                if self.white > self.black:
                    self.port.win()
                else:
                    self.port.lose()
            return 'moved'
        return None

    def legal(self, mark):
        return [i for i in range(64) if self.b[i] == 0 and self.flips(i, mark, 0)]

    def state_bytes(self):
        return bytes(self.b + [self.cursor, self.white, self.black, self.placed,
                               self.placing, self.flip, self.flipping,
                               self.flip_frame]).hex()


def route(start, target):
    keys = []
    row, column = divmod(start, 8)
    target_row, target_column = divmod(target, 8)
    keys += ['s'] * max(0, target_row - row) + ['w'] * max(0, row - target_row)
    keys += ['d'] * max(0, target_column - column) + ['a'] * max(0, column - target_column)
    return keys
