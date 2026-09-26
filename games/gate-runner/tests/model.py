# SPDX-License-Identifier: MIT
"""GATE RUNNER rules model (jr100dev games/gate_runner/rules.py 3.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, then
b[24] (the current gate at 0-7 and the next at 16-23: kind, left, right,
other kind, other left, other right, crystal column, crystal in the air).
The tables are upstream game.json dataTables. `held` is the direction the
player holds (0, 3 or 4), read once per tick like upstream held().
"""

LEVELS = 6
KINDS = [1, 2, 2, 1, 3, 2, 3, 1, 2, 2, 1, 1]
LEFTS = [11, 2, 2, 2, 2, 2, 2, 13, 2, 10, 2, 2]
RIGHTS = [20, 16, 30, 8, 30, 30, 16, 23, 30, 22, 20, 20]
OTHER_KINDS = [0, 1, 0, 1, 0, 1, 2, 0, 0, 0, 0, 1]
OTHER_LEFTS = [2, 22, 2, 15, 2, 9, 16, 2, 2, 2, 2, 26]
OTHER_RIGHTS = [2, 30, 2, 30, 2, 17, 30, 2, 2, 2, 2, 30]
PRIZES = [5, 10, 17, 10, 20, 24, 23, 6, 11, 16, 25, 22]
PRIZE_AIR = [0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0]
HEIGHTS = [0, 0, 1, 2, 3, 3, 2, 1, 0]
WIDTHS = [2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 14, 14]
FLOORS = [5, 5, 6, 6, 7, 7, 8, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
LAYOUT = [('x', 1), ('hp', 1), ('limit', 1), ('speed', 1), ('rate', 1), ('air', 1),
          ('clock', 1), ('notice_time', 1), ('pace', 1), ('age', 1), ('hit', 1),
          ('notice', 1), ('gates', 1), ('coins', 1), ('b', 24)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = {1: 'HIT THE WALL', 2: 'FELL INTO THE PIT', 3: 'JUMPED INTO THE LOW BEAM'}


class GateRunner:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.held = 0

    def load_gate(self, event, slot):
        level = self.port.level
        k = (event + level * 2) % 12
        b = self.b
        b[slot:slot + 8] = [KINDS[k], LEFTS[k], RIGHTS[k], OTHER_KINDS[k], OTHER_LEFTS[k],
                            OTHER_RIGHTS[k], PRIZES[k], PRIZE_AIR[k]]
        if level % 2:
            b[slot + 1], b[slot + 2] = 32 - b[slot + 2], 32 - b[slot + 1]
            b[slot + 4], b[slot + 5] = 32 - b[slot + 5], 32 - b[slot + 4]
            b[slot + 6] = 30 - b[slot + 6]

    def init(self):
        level = self.port.level
        self.x = 15
        self.hp = 3
        self.limit = 9 if level == 0 else 12
        self.speed = 1
        self.rate = 6 - level // 2
        self.load_gate(0, 0)
        self.load_gate(1, 16)

    def shift(self, action):
        if action == 3 and self.x > 2:
            self.x -= 1
        elif action == 4 and self.x < 28:
            self.x += 1

    def act(self, action):
        self.shift(action)
        if action in (1, 5) and self.air == 0:
            self.air = 8

    def collides(self, slot):
        b = self.b
        if self.x + 2 <= b[slot + 1] or self.x >= b[slot + 2]:
            return 0
        kind = b[slot]
        height = HEIGHTS[self.air]
        if kind == 1 or (kind == 2 and height < 2) or (kind == 3 and height >= 2):
            return kind
        return 0

    def tick(self):
        self.clock = (self.clock + 1) & 0xff
        if self.notice_time:
            self.notice_time -= 1
        self.shift(self.held)
        if self.air:
            self.air -= 1
        self.pace += 1
        if self.pace < self.speed:
            return
        self.pace = 0
        self.age += 1
        if self.age == 20:
            self.age = 0
            self.load_gate(self.gates, 0)
            self.load_gate(self.gates + 1, 16)
            return
        if self.age == 18:
            self.hit = max(self.collides(0), self.collides(3))
            if self.hit:
                self.hp -= 1
                self.notice = self.hit
                self.notice_time = 18
                if self.hp == 0:
                    self.port.lose(LOSS[self.hit])
                    return
            else:
                delta = abs(self.x - self.b[6])
                if delta <= 1 and (HEIGHTS[self.air] >= 2) == self.b[7]:
                    self.coins += 1
                    self.notice = 4
                    self.notice_time = 12
            self.gates += 1
            if self.gates == self.limit:
                self.port.win()

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
