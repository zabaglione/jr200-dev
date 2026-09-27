# SPDX-License-Identifier: MIT
"""RIBBON SNAKE rules model (jr100dev games/ribbon_snake/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, the
body b (head first) and the rocks d. The previous body c is drawing-only and
lies after them. `effects` records upstream impact/sparkle/glide calls.
"""

LEVELS = 6
LAYOUT = [('length', 1), ('dir', 1), ('brakes', 1), ('goal', 1), ('slow', 1), ('food', 1),
          ('eaten', 1), ('sliding', 1), ('b', 20), ('d', 64)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = {'edge': 'THE HEAD HIT THE EDGE', 'rock': 'THE HEAD HIT A ROCK',
        'body': 'THE HEAD HIT ITS OWN BODY'}


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


class RibbonSnake:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.c = [0] * 20
        self.held = 0
        self.effects = []

    def food_place(self):
        level = self.port.level
        for k in range(64):
            p = (self.eaten * 13 + k * 7 + 26 + level * 9) % 64
            found = self.d[p] or p in self.b[:self.length]
            if not found:
                self.food = p
                return

    def init(self):
        level = self.port.level
        self.length = 3
        self.b[0], self.b[1], self.b[2] = 8, 0, 1
        self.dir = 2
        self.brakes = 3
        self.goal = 8 + level
        for i in range(2 + level):
            self.d[18 + (i * 11 + level * 3) % 30] = 1
        self.food_place()

    def act(self, action):
        if action == 5 and self.brakes and not self.slow:
            self.brakes -= 1
            self.slow = 8
            self.effects.append(('sound', 2))
        if 1 <= action <= 4:
            opposite = {1: 2, 2: 1, 3: 4, 4: 3}[self.dir]
            if action != opposite:
                self.dir = action

    def tick(self):
        if self.slow:
            self.slow -= 1
            if self.slow % 2 == 0:
                return
        head = self.b[0]
        p = move(head, self.dir)
        if p == head:
            self.effects.append(('impact', head))
            self.port.lose(LOSS['edge'])
            return
        if self.d[p]:
            self.effects.append(('impact', p))
            self.port.lose(LOSS['rock'])
            return
        eating = p == self.food
        if p in self.b[:self.length - 1 + eating]:
            self.effects.append(('impact', p))
            self.port.lose(LOSS['body'])
            return
        self.c[:self.length] = self.b[:self.length]
        self.c[self.length] = self.b[self.length - 1]
        for i in range(self.length, 0, -1):
            self.b[i] = self.b[i - 1]
        self.b[0] = p
        self.effects.append(('glide', 3))
        if eating:
            self.length += 1
            self.effects.append(('sparkle', p))
            self.eaten += 1
            self.food_place()
            self.effects.append(('sound', 1))
            if self.eaten == self.goal:
                self.port.win()

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
