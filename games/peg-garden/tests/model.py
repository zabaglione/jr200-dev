# SPDX-License-Identifier: MIT
"""PEG GARDEN rules model (jr100dev games/peg_garden/rules.py 1.5.1).

state_bytes() mirrors src/main.asm: b[25], cursor, selected, left, jumping, jump.
"""

LEVELS = 1
GOAL = 5


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


class PegGarden:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.b = [0] * 25
        self.cursor = self.left = self.jumping = self.jump = 0
        self.selected = 0

    def init(self):
        for i in range(25):
            inner = 0 < i % 5 < 4 or 0 < i // 5 < 4
            self.b[i] = 4 if inner else 1
        self.b[12] = 0
        self.cursor = 12
        self.selected = 255
        self.left = 20

    def act(self, action):
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5:
            if self.selected == 255:
                if self.b[self.cursor] == 4:
                    self.selected = self.cursor
            else:
                for a in range(4):
                    mid = move(self.selected, a + 1)
                    end = move(mid, a + 1)
                    if (mid != self.selected and end != mid and end == self.cursor
                            and self.b[mid] == 4 and self.b[end] == 0):
                        self.b[mid] = 0
                        self.b[self.selected] = 0
                        self.jump = end
                        self.b[end] = 4
                        self.left -= 1
                self.selected = 255
                if self.left <= GOAL:
                    self.port.win()

    def state_bytes(self):
        return bytes(self.b + [self.cursor, self.selected, self.left,
                               self.jumping, self.jump]).hex()
