# SPDX-License-Identifier: MIT
"""STAR LANCE rules model (jr100dev games/star_lance/rules.py 4.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, then
d[24] (three player shots: y, x, power at +0, +8, +16), c[64] (six enemy
bolts: y, x, steps, dx, direction, x error, dy, y error at +0, +8, ... +56)
and b[120] (0-23 hull, 32-55 flash, 64-87 / 96-119 explosion x / y). The self
test stores the first TEST_SIZE bytes (everything up to the hull; the flash
and explosion bytes only drive the drawing). `held` is the
upstream buttons() mask (D 1, A 2, W 4, RETURN 16). Values are bytes like
the upstream native rules.
"""

LEVELS = 6
LAYOUT = [('ship', 1), ('hp', 1), ('left', 1), ('shift', 1), ('direction', 1), ('target', 1),
          ('wait', 1), ('tap', 1), ('cool', 1), ('heat', 1), ('jam', 1), ('notice', 1),
          ('time', 1), ('age', 1), ('drop', 1), ('charge', 1), ('shield', 1), ('march', 1),
          ('finish', 1), ('d', 24), ('c', 64), ('b', 120)]
SIZE = sum(n for _, n in LAYOUT)
TEST_SIZE = SIZE - 96
LOSS = {'hit': 'HIT BY ENEMY SHOT', 'fleet': 'THE FLEET BROKE THROUGH'}


class StarLance:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.held = 0

    def init(self):
        level = self.port.level
        self.ship = 14
        self.hp = 3
        self.left = 18
        self.shift = 4
        self.direction = 1
        self.target = 255
        self.wait = 24
        for i in range(24):
            self.b[i] = (2 if i < 8 or level >= 3 and i < 16 else 1) if i % 8 < 6 else 0

    def act(self, action):
        if action == 3:
            self.tap |= 2
        if action == 4:
            self.tap |= 1
        if action == 5:
            self.tap |= 16
        if action == 1:
            self.tap |= 4

    def fire(self, power):
        d = self.d
        for i in range(3):
            if not d[i]:
                d[i], d[i + 8], d[i + 16] = 19, self.ship + 1, power
                self.cool = 4 if power == 1 else 7
                self.heat += 3 if power == 1 else 5
                if self.heat >= 12:
                    self.heat = 12
                    self.jam = 28
                return

    def strike(self, i, power):
        b = self.b
        b[i] = b[i] - power if b[i] > power else 0
        b[i + 32] = 6
        b[i + 64] = (self.shift + i % 8 * 4) & 0xff
        b[i + 96] = 3 + i // 8 * 3 + self.drop
        if not b[i]:
            self.left -= 1
            if self.target == i:
                self.target = 255
                self.wait = 12
                self.heat = self.heat - 4 if self.heat > 4 else 0
                self.jam = 0
                self.notice = 16

    def shots(self):
        d = self.d
        for i in range(3):
            if d[i]:
                d[i] -= 1
                if d[i + 8] >= self.shift and d[i] >= 3 + self.drop:
                    x = d[i + 8] - self.shift
                    y = d[i] - 3 - self.drop
                    if x < 24 and x % 4 < 2 and y < 9 and y % 3 < 2:
                        enemy = y // 3 * 8 + x // 4
                        if self.b[enemy]:
                            self.strike(enemy, d[i + 16])
                            d[i] = 0

    def launch(self, x, y, aim):
        c = self.c
        for i in range(6):
            if not c[i]:
                c[i] = y
                c[i + 8] = x
                c[i + 24] = aim - x if aim >= x else x - aim
                c[i + 16] = max(20 - y, c[i + 24])
                c[i + 32] = 1 if aim >= x else 255
                c[i + 40] = 0
                c[i + 48] = 20 - y
                c[i + 56] = 0
                return

    def attack(self):
        level = self.port.level
        if self.target == 255:
            if self.wait:
                self.wait -= 1
            else:
                best = 255
                for k in range(24):
                    i = 23 - k
                    x = (self.shift + i % 8 * 4) & 0xff
                    distance = abs(x - self.ship)
                    if self.b[i] and distance < best:
                        best = distance
                        self.target = i
                self.charge = 18 - level
        else:
            self.charge -= 1
            if not self.charge:
                x = self.shift + self.target % 8 * 4 + 1
                y = 5 + self.target // 8 * 3 + self.drop
                self.launch(x, y, self.ship + 1)
                if level >= 2:
                    self.launch(x, y, max(self.ship, 4) - 3)
                    self.launch(x, y, min(self.ship + 5, 30))
                self.target = 255
                self.wait = 24 - level * 3

    def bolts(self):
        c = self.c
        hit = False
        for i in range(6):
            if c[i]:
                c[i + 56] = (c[i + 56] + c[i + 48]) & 0xff
                if c[i + 56] >= c[i + 16]:
                    c[i + 56] -= c[i + 16]
                    c[i] += 1
                c[i + 40] = (c[i + 40] + c[i + 24]) & 0xff
                if c[i + 40] >= c[i + 16]:
                    c[i + 40] -= c[i + 16]
                    c[i + 8] = (c[i + 8] + c[i + 32]) & 0xff
                if c[i + 8] > 30:
                    c[i] = 0
                elif c[i] >= 20:
                    if self.ship <= c[i + 8] <= self.ship + 1:
                        hit = True
                    c[i] = 0
        if hit and not self.shield:
            self.hp -= 1
            self.shield = 24

    def tick(self):
        keys = self.held | self.tap
        self.tap = 0
        self.time = (self.time + 1) & 0xff
        self.age += 1
        if self.age == 240:
            self.age = 0
            self.drop += 1
        if self.cool:
            self.cool -= 1
        if self.jam:
            self.jam -= 1
        if self.heat and self.time % (2 if self.jam else 4) == 0:
            self.heat -= 1
        if self.notice:
            self.notice -= 1
        if self.shield:
            self.shield -= 1
        for i in range(24):
            if self.b[i + 32]:
                self.b[i + 32] -= 1
        if keys & 3 == 2 and self.ship > 1:
            self.ship -= 1
        if keys & 3 == 1 and self.ship < 29:
            self.ship += 1
        if not self.cool and not self.jam:
            if keys & 4:
                self.fire(2)
            elif keys & 16:
                self.fire(1)
        self.march += 1
        if self.march == 6:
            self.march = 0
            self.shift = (self.shift + (1 if self.direction else 255)) & 0xff
            if self.shift in (1, 9):
                self.direction ^= 1
        self.shots()
        if self.left:
            self.attack()
            if self.time % 2 == 0:
                self.bolts()
            if not self.hp:
                self.port.lose(LOSS['hit'])
            elif self.drop == 6:
                self.port.lose(LOSS['fleet'])
        else:
            self.finish += 1
            if self.finish == 7:
                self.port.win()

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
