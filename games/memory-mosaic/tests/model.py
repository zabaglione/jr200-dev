# SPDX-License-Identifier: MIT
"""MEMORY MOSAIC rules model (jr100dev games/memory_mosaic/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: origin, seed, first, second, turning, left,
limit, cursor, chain, best, errors, notice, pose, then b[16] and c[16].

origin is upstream's entropy(), sampled at each stage start from the title
song position; the model receives it from the recorded run (as upstream's
checks do) and predicts every other byte.
"""

LEVELS = 10
LOSS = 'TOO MANY PAIRS DID NOT MATCH'


def move(pos, action, width=4, height=4):
    if action == 1 and pos >= width:
        return pos - width
    if action == 2 and pos < width * (height - 1):
        return pos + width
    if action == 3 and pos % width > 0:
        return pos - 1
    if action == 4 and pos % width < width - 1:
        return pos + 1
    return pos


def deal(origin, level):
    seed = origin ^ ((level * 17) & 0xff)
    b = [i // 2 for i in range(16)]
    for i in range(15):
        seed = (seed * 109 + 89) & 255
        j = seed % (16 - i)
        b[15 - i], b[j] = b[j], b[15 - i]
    return seed, b


class MemoryMosaic:
    port = None
    origins = []

    def __init__(self):
        self.reset()
        self.samples = list(self.origins)

    def reset(self):
        self.origin = self.seed = self.first = self.second = self.turning = 0
        self.left = self.limit = self.cursor = self.chain = self.best = 0
        self.errors = self.notice = self.pose = 0
        self.b = [0] * 16
        self.c = [0] * 16

    def init(self):
        self.origin = self.samples.pop(0) if self.samples else 0
        self.seed, self.b = deal(self.origin, self.port.level)
        self.first = self.second = self.turning = 255
        self.left = 8
        self.limit = 12 - self.port.level // 3

    def turn(self, pos, reveal):
        self.pose = 5 if reveal else 1
        self.c[pos] = reveal

    def act(self, action):
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5:
            self.notice = 0
            if self.second != 255:
                if self.b[self.first] != self.b[self.second]:
                    self.turn(self.first, 0)
                    self.turn(self.second, 0)
                self.first = self.second = 255
            elif not self.c[self.cursor]:
                self.turn(self.cursor, 1)
                if self.first == 255:
                    self.first = self.cursor
                else:
                    self.second = self.cursor
                    if self.b[self.first] == self.b[self.second]:
                        self.left -= 1
                        self.chain += 1
                        self.best = max(self.best, self.chain)
                        self.notice = 1
                    else:
                        self.errors += 1
                        self.chain = 0
                        self.notice = 2
                    if not self.left:
                        self.port.win()
                    elif self.errors >= self.limit:
                        self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([self.origin, self.seed, self.first, self.second, self.turning,
                      self.left, self.limit, self.cursor, self.chain, self.best,
                      self.errors, self.notice, self.pose] + self.b + self.c).hex()
