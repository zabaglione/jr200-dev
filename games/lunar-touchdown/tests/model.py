# SPDX-License-Identifier: MIT
"""LUNAR TOUCHDOWN rules model (jr100dev games/lunar_touchdown/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE. Values are bytes
like the upstream native rules (time wraps at 256).
"""

LEVELS = 6
LAYOUT = [('x', 1), ('target', 1), ('narrow', 1), ('width', 1), ('fuel', 1), ('wind', 1),
          ('speed', 1), ('flame', 1), ('time', 1), ('height', 1), ('middle', 1),
          ('descending', 1), ('landed', 1), ('score', 1)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = {'speed': 'DESCENT SPEED TOO HIGH', 'pad': 'MISSED BOTH LANDING PADS'}


class LunarTouchdown:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, _ in LAYOUT:
            setattr(self, name, 0)
        self.held = 0

    def init(self):
        level = self.port.level
        self.x = 3
        self.target = 7 + level * 3
        self.narrow = 24 if self.target < 18 else 5
        self.width = 3 if level < 3 else 2
        self.fuel = 22
        self.wind = 1 if level % 2 else 0

    def act(self, action):
        if action == 3 and self.x > 0:
            self.x -= 1
        if action == 4 and self.x < 28:
            self.x += 1
        if action in (1, 5) and self.fuel:
            self.speed = self.speed - 2 if self.speed >= 2 else 0
            self.fuel -= 1
            self.flame = 2

    def tick(self):
        level = self.port.level
        self.time = (self.time + 1) & 0xff
        if self.flame:
            self.flame -= 1
        if self.time % 3 == 0:
            self.speed = min(5, self.speed + 1)
        if level and self.time % 4 == 0:
            if self.wind and self.x < 28:
                self.x += 1
            elif not self.wind and self.x > 0:
                self.x -= 1
        if self.time % (16 if level < 3 else 12) == 0:
            self.wind ^= 1
        old = self.height
        self.height = min(30, self.height + self.speed)
        self.middle = (old + self.height) // 2
        self.descending = 0
        if self.height >= 30:
            self.height = 30
            regular = self.target <= self.x <= self.target + self.width
            precision = self.x == self.narrow
            if (regular or precision) and self.speed <= 2:
                self.landed = 1
                self.score = self.fuel + (10 if precision else 0) + (4 if self.speed <= 1 else 0)
                self.port.win()
            elif self.speed > 2:
                self.port.lose(LOSS['speed'])
            else:
                self.port.lose(LOSS['pad'])

    def state_bytes(self):
        return bytes(getattr(self, name) for name, _ in LAYOUT).hex()
