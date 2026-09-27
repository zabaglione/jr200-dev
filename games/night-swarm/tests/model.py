# SPDX-License-Identifier: MIT
"""NIGHT SWARM rules model (jr100dev games/night_swarm/rules.py 3.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, then
b[8] (foe cells, 255 empty), c[8] (their armor) and d[8] (the cells they
marched from). move8() and distance() are upstream games/native/support.py.
Values are bytes like the upstream native rules (time wraps at 256).
"""

LEVELS = 6
EMPTY = 255
LAYOUT = [('pos', 1), ('origin', 1), ('facing', 1), ('hp', 1), ('limit', 1), ('period', 1),
          ('cell', 1), ('time', 1), ('cooldown', 1), ('spawn', 1), ('portal', 1), ('entry', 1),
          ('kills', 1), ('salvage', 1), ('pulse', 1), ('marching', 1),
          ('b', 8), ('c', 8), ('d', 8)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = 'THE SWARM BROKE THROUGH'


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


def move8(pos, action):
    if action == 9:
        return move(move(pos, 1), 3)
    if action == 10:
        return move(move(pos, 1), 4)
    if action == 11:
        return move(move(pos, 2), 3)
    if action == 12:
        return move(move(pos, 2), 4)
    return move(pos, action)


def distance(a, b):
    return abs(a % 8 - b % 8) + abs(a // 8 - b // 8)


class NightSwarm:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.held = 0

    def spawn_preview(self):
        level = self.port.level
        self.portal = (self.spawn % 28 * 9) % 28
        self.portal = (self.portal + level * 7) % 28
        if self.portal < 8:
            self.entry = self.portal
        elif self.portal < 14:
            self.entry = (self.portal - 7) * 8 + 7
        elif self.portal < 22:
            self.entry = 63 - (self.portal - 14)
        else:
            self.entry = (28 - self.portal) * 8

    def init(self):
        level = self.port.level
        self.pos = self.origin = 27
        self.facing = 2
        self.hp = 4
        self.limit = 12 + level * 2
        self.period = 4 if level < 3 else 3
        self.cell = EMPTY
        self.b = [EMPTY] * 8
        self.spawn_preview()

    def hurt(self, i):
        if self.c[i] > 1:
            self.c[i] -= 1
        else:
            if self.kills % 4 == 3:
                self.cell = self.b[i]
            self.b[i] = EMPTY
            self.kills += 1
        if self.kills >= self.limit:
            self.port.win()

    def act(self, action):
        if action < 5 or action >= 9:
            self.facing = action if action < 5 else (3 if action in (9, 11) else 4)
            self.pos = move8(self.pos, action)
            self.origin = self.pos
            if self.pos == self.cell:
                self.cell = EMPTY
                self.hp = min(4, self.hp + 1)
                self.cooldown = 0
                self.salvage += 1
        if action == 5 and self.cooldown == 0:
            self.pulse = 0
            for i in range(8):
                if self.port.mode == 1 and self.b[i] != EMPTY and distance(self.pos, self.b[i]) <= 3:
                    self.hurt(i)
            self.cooldown = 8

    def tick(self):
        level = self.port.level
        self.time = (self.time + 1) & 0xff
        if self.cooldown:
            self.cooldown -= 1
        if self.time % 3 == 0:
            for i in range(8):
                self.d[i] = self.b[i]
                if self.b[i] != EMPTY:
                    p = self.b[i]
                    if (self.time + i) % 2 == 0 and p // 8 != self.pos // 8:
                        p = p + 8 if p // 8 < self.pos // 8 else p - 8
                    elif p % 8 != self.pos % 8:
                        p = p + 1 if p % 8 < self.pos % 8 else p - 1
                    elif p // 8 != self.pos // 8:
                        p = p + 8 if p // 8 < self.pos // 8 else p - 8
                    self.b[i] = p
            hit = False
            for i in range(8):
                if self.b[i] == self.pos:
                    self.b[i] = EMPTY
                    hit = True
            if hit:
                self.hp -= 1
                if self.hp == 0:
                    self.port.lose(LOSS)
                    return
        if self.time % self.period == 0:
            for i in range(8):
                if self.b[i] == EMPTY:
                    self.b[i] = self.entry
                    self.c[i] = 2 if (self.spawn + level) % 3 != 0 else 1
                    self.d[i] = self.b[i]
                    break
            self.spawn = (self.spawn + 1) & 0xff
            self.spawn_preview()
        if self.time % 4 == 1:
            for i in range(8):
                if self.port.mode == 1 and self.b[i] != EMPTY and distance(self.pos, self.b[i]) <= 2:
                    self.hurt(i)
                    break

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
