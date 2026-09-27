# SPDX-License-Identifier: MIT
"""IRON SCRIPT rules model (jr100dev games/iron_script/rules.py 2.0.1).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, b[64]
(the room: 0 floor, 1 wall, 3 terminal, 4 switch, 5 sentry, 6 door, 7 laser,
8 armored sentry) and c[12] (the program: 0 wait, 1-4 move, 5 fire, 6 use,
7 replay the previous two). LEVELS_DATA is upstream levels.json (d[64]
start, d[65] facing, d[66] ammo, d[67] program length, d[68] laser phase);
SOLUTIONS is upstream solutions.json. A run steps one command per tick.
"""

LEVELS = 24
LAYOUT = [('pos', 1), ('origin', 1), ('facing', 1), ('ammo', 1), ('gate', 1),
          ('door_pose', 1), ('steps', 1), ('pc', 1), ('sub', 1), ('notice', 1), ('beam', 1),
          ('running', 1), ('cursor', 1), ('active', 1), ('b', 64), ('c', 12)]
SIZE = sum(n for _, n in LAYOUT)
LEVELS_DATA = [
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 5, 0, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 0, 0, 0, 0, 1, 1, 1, 1, 6, 1, 1, 1, 1, 1, 1, 1, 0, 0, 5, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 8, 3, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 5, 6, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 3, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 7, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 0, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 7, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 0, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 7, 0, 5, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 7, 5, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 0, 8, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 0, 8, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 5, 5, 3, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 6, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 7, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 0, 9, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 6, 5, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 4, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 35, 1, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 8, 0, 3, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 5, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 5, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 3, 0, 5, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 8, 0, 1, 1, 1, 1, 1, 1, 1, 6, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 0, 7, 0, 0, 1, 1, 1, 1, 1, 1, 1, 6, 1, 1, 1, 1, 1, 3, 0, 5, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 7, 0, 7, 5, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 1, 1, 1, 1, 1, 1, 1, 7, 1, 1, 1, 1, 1, 1, 1, 0, 0, 8, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 5, 0, 1, 1, 1, 1, 1, 1, 0, 7, 1, 1, 1, 1, 3, 0, 5, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 5, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 1, 10, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 7, 0, 8, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 0],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 0, 7, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 3, 0, 8, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 2, 12, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 4, 6, 7, 5, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 8, 1, 1, 0, 0, 0, 0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 4, 3, 12, 1],
]
SOLUTIONS = [
    [4, 6, 4, 5, 4, 4, 4],
    [4, 6, 4, 2, 2, 4, 5, 4, 4],
    [4, 6, 4, 4, 5, 5, 4, 4],
    [4, 6, 4, 2, 2, 4, 4, 4],
    [0, 4, 4, 4, 7],
    [0, 4, 4, 2, 2, 4, 4, 4],
    [4, 4, 4, 5, 4, 4],
    [4, 6, 4, 5, 4, 4, 4],
    [4, 4, 4, 7, 2, 2, 2, 7],
    [4, 2, 4, 2, 7, 4, 2, 7],
    [4, 4, 5, 4, 7, 4],
    [0, 4, 4, 4, 7, 2, 2, 2, 7],
    [1, 3, 6, 4, 1, 5, 1, 3, 3],
    [2, 2, 4, 4, 5, 4, 1, 4, 7],
    [4, 4, 5, 4, 4, 4, 2, 5, 2, 3, 3],
    [4, 6, 4, 4, 5, 5, 4, 4, 2, 2],
    [0, 4, 6, 4, 4, 7, 2, 5, 2, 3, 3],
    [5, 4, 4, 4, 7],
    [4, 6, 4, 4, 2, 2, 4, 5, 5, 4, 2],
    [4, 4, 4, 5, 4, 2, 5, 2, 3, 3],
    [4, 6, 4, 4, 7, 2, 5, 2, 2, 7],
    [4, 6, 4, 4, 4, 5, 5, 4, 2, 2],
    [4, 6, 4, 4, 7, 2, 5, 5, 2, 3, 3],
    [4, 6, 5, 4, 4, 7, 2, 5, 2, 7, 2],
]


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


class IronScript:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.d = [0] * 69
        self.held = 0

    def reset_world(self):
        d = self.d
        self.b = d[:64]
        self.pos = self.origin = d[64]
        self.facing = d[65]
        self.ammo = d[66]
        self.gate = 0
        self.door_pose = 1
        self.steps = 0
        self.pc = 0
        self.sub = 0
        self.notice = 0
        self.beam = 255

    def init(self):
        self.d = list(LEVELS_DATA[self.port.level])
        self.reset_world()

    def stop(self, reason):
        self.notice = reason
        self.running = 0
        self.cursor = min(self.pc, self.d[67] - 1)

    def act(self, action):
        if self.running:
            if action == 5:
                self.stop(9)
            return
        if action == 3 and self.cursor > 0:
            self.cursor -= 1
        if action == 4 and self.cursor < self.d[67] - 1:
            self.cursor += 1
        if action == 1:
            self.c[self.cursor] = (self.c[self.cursor] + 1) & 7
        if action == 2:
            self.c[self.cursor] = (self.c[self.cursor] + 7) & 7
        if action == 5:
            self.reset_world()
            self.running = 1

    def shoot(self):
        if self.ammo == 0:
            self.stop(5)
            return
        self.ammo -= 1
        target = self.pos
        b = self.b
        for _ in range(7):
            target = move(target, self.facing)
            if b[target] == 1 or (b[target] == 6 and not self.gate):
                self.beam = 255
                return
            self.beam = target
            if b[target] in (5, 8):
                if b[target] == 8:
                    b[target] = 5
                    self.notice = 10
                else:
                    b[target] = 0
                    self.notice = 11
                self.beam = 255
                return
        self.beam = 255

    def tick(self):
        if not self.running:
            return
        c, b, d = self.c, self.b, self.d
        self.active = self.pc
        if c[self.pc] == 7:
            if self.pc < 2 or c[self.pc - 1] == 7 or c[self.pc - 2] == 7:
                self.stop(7)
                return
            self.active = self.pc - 2 + self.sub
        command = c[self.active]
        self.steps = (self.steps + 1) & 0xff
        self.notice = 0
        if 0 < command < 5:
            self.facing = command
            target = move(self.pos, command)
            obstacle = b[target]
            if obstacle in (1, 5, 8) or (obstacle == 6 and not self.gate):
                self.notice = 1 if obstacle == 1 else (3 if obstacle == 6 else 2)
                self.stop(self.notice)
                return
            self.pos = self.origin = target
        elif command == 5:
            self.shoot()
        elif command == 6:
            if b[self.pos] != 4:
                self.stop(6)
                return
            self.gate = 1 - self.gate
            self.notice = 12
            self.door_pose = 4 if self.gate else 1
        if not self.running:
            return
        if b[self.pos] == 7 and (self.steps + d[68]) & 1:
            self.notice = 4
            self.stop(4)
            return
        if b[self.pos] == 3:
            self.running = 0
            self.port.win()
            return
        if c[self.pc] == 7 and self.sub == 0:
            self.sub = 1
        else:
            self.sub = 0
            self.pc += 1
        if self.pc >= d[67]:
            self.stop(8)

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
