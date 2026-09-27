# SPDX-License-Identifier: MIT
"""ORBIT DODGE rules model (jr100dev games/orbit_dodge/rules.py 3.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE. Positions 0-7 run
round the orbit; ring 0 is the outer and ring 1 the inner orbit. RINGX/RINGY
are upstream games/native/support.py ringx()/ringy() (drawing only).
"""

LEVELS = 6
LAYOUT = [('hp', 1), ('target', 1), ('limit', 1), ('window', 1), ('ring', 1), ('other', 1),
          ('dual', 1), ('gem', 1), ('gem_ring', 1), ('age', 1), ('pos', 1), ('orbit', 1),
          ('travel', 1), ('waves', 1), ('chain', 1), ('score', 1), ('firing', 1), ('beam', 1)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = 'STRUCK BY AN ORBITAL BEAM'
RINGX = [15, 24, 28, 24, 15, 6, 2, 6]
RINGY = [3, 5, 10, 15, 17, 15, 10, 5]


def rx(i, ring):
    x = RINGX[i]
    return x if ring == 0 else (15 + (x - 15) // 2 if x >= 15 else 15 - (15 - x) // 2)


def ry(i, ring):
    y = RINGY[i]
    return y if ring == 0 else (10 + (y - 10) // 2 if y >= 10 else 10 - (10 - y) // 2)


class OrbitDodge:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, _ in LAYOUT:
            setattr(self, name, 0)
        self.held = 0

    def next_wave(self):
        level = self.port.level
        self.target = (self.target * 5 + 3 + level * 2) % 8
        self.ring = (self.waves + level) % 2
        self.other = (self.target + 3 + self.waves % 3) % 8
        self.dual = 1 if self.waves >= 4 or level >= 2 else 0
        self.gem = (self.target + 1 + self.waves % 2) % 8
        self.gem_ring = self.ring
        self.age = 0

    def init(self):
        level = self.port.level
        self.hp = 3
        self.target = 3
        self.limit = 12 + level * 2
        self.window = 5 if level < 3 else 4
        self.next_wave()

    def act(self, action):
        if action in (3, 1):
            self.pos = (self.pos + 7) % 8
        if action in (4, 2):
            self.pos = (self.pos + 1) % 8
        if action == 5:
            self.orbit ^= 1

    def tick(self):
        self.age = (self.age + 1) & 0xff
        if self.age >= self.window:
            self.beam = 15          # the beam grows 5, 10, 15 while it fires
            hit = self.orbit == self.ring and self.pos == self.target
            if self.dual and self.orbit != self.ring and self.pos == self.other:
                hit = True
            if hit:
                self.hp -= 1
                self.chain = 0
            elif self.orbit == self.gem_ring and self.pos == self.gem:
                self.chain = min(3, self.chain + 1)
                self.score = (self.score + self.chain) & 0xff
            else:
                self.chain = 0
            self.waves += 1
            if self.hp == 0:
                self.port.lose(LOSS)
            elif self.waves >= self.limit:
                self.port.win()
            else:
                self.next_wave()

    def state_bytes(self):
        return bytes(getattr(self, name) for name, _ in LAYOUT).hex()
