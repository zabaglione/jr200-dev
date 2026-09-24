# SPDX-License-Identifier: MIT
"""BRICK PULSE rules model (jr100dev games/brick_pulse/rules.py 2.3.1).

All values wrap at eight bits like the upstream native rules. Observed RAM
layout of src/main.asm: b[24] followed by the state bytes in STATE_FIELDS.
"""

LEVELS = 12
# levels.json: twelve arenas of 24 bricks (0 empty, 1-3 hits).
ARENAS = [
    [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 1, 1, 0, 0, 0, 1, 2, 2, 1, 0, 1, 2, 1, 1, 2, 1, 1, 1, 0, 0, 1, 1],
    [1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 2, 2, 0, 0, 0, 1, 0, 0, 1, 0],
    [2, 0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 0, 1, 2, 2, 1, 0, 0, 0, 1, 1, 0, 0],
    [2, 0, 2, 0, 2, 0, 0, 2, 0, 2, 0, 2, 2, 1, 2, 1, 2, 1, 1, 2, 1, 2, 1, 2],
    [2, 2, 2, 2, 2, 2, 1, 0, 1, 1, 0, 1, 2, 1, 2, 2, 1, 2, 0, 1, 0, 0, 1, 0],
    [0, 0, 3, 3, 0, 0, 0, 3, 2, 2, 3, 0, 3, 2, 1, 1, 2, 3, 2, 1, 0, 0, 1, 2],
    [3, 0, 2, 2, 0, 3, 2, 3, 0, 0, 3, 2, 1, 2, 3, 3, 2, 1, 0, 1, 1, 1, 1, 0],
    [3, 3, 3, 3, 3, 3, 0, 2, 0, 0, 2, 0, 2, 2, 2, 2, 2, 2, 1, 0, 1, 1, 0, 1],
    [3, 0, 3, 0, 3, 0, 0, 3, 0, 3, 0, 3, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 1, 2],
    [3, 2, 3, 3, 2, 3, 2, 3, 2, 2, 3, 2, 3, 2, 1, 1, 2, 3, 2, 2, 3, 3, 2, 2],
    [3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 3, 2, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2],
]
STATE_FIELDS = ('left', 'paddle', 'width', 'hp', 'ex', 'ed', 'enemy', 'x', 'y', 'dy', 'dx',
                'steep', 'repeat', 'item', 'ix', 'iy', 'clock', 'bomb', 'bx', 'guard', 'jam',
                'wide', 'slow', 'caught', 'steps', 'broken', 'bounces')


class BrickPulse:
    def __init__(self):
        self.port = None
        self.held = 0
        self.reset()

    def reset(self):
        self.b = [0] * 24
        for name in STATE_FIELDS:
            setattr(self, name, 0)
        self.effects = []

    # Upstream effects stop the clock; the model only records them.
    def impact(self, x, y):
        self.effects.append(('impact', x & 0xff, y & 0xff))

    def vanish(self, x, y):
        self.effects.append(('vanish', x & 0xff, y & 0xff))

    def init(self):
        level = self.port.level
        for i in range(24):
            self.b[i] = ARENAS[level][i]
            if self.b[i]:
                self.left += 1
        self.paddle = 12
        self.width = 6
        self.hp = 3
        self.ex = 6
        self.ed = 1
        if level >= 2:
            self.enemy = 2 + level // 4
        self.serve()

    def serve(self):
        self.x = (self.paddle + self.width // 2) & 0xff
        self.y = 14
        self.dy = 0
        self.dx = 1
        self.steep = 0

    def move_paddle(self, direction):
        if direction == 3:
            self.paddle = self.paddle - 2 if self.paddle >= 2 else 0
        if direction == 4:
            self.paddle = min(30 - self.width, self.paddle + 2)

    def act(self, action):
        if action in (3, 4):
            self.move_paddle(action)
            self.repeat = 1

    def drop(self, kind, x, y):
        if not self.item:
            self.item, self.ix, self.iy = kind, x, y

    def hazards(self):
        if self.enemy:
            if self.clock % 2 == 0:
                if self.ex == 2:
                    self.ed = 1
                if self.ex == 27:
                    self.ed = 0
                self.ex = (self.ex + 1 if self.ed else self.ex - 1) & 0xff
            if self.port.level >= 5 and self.clock % 32 == 0 and not self.bomb:
                self.bomb = 10
                self.bx = self.ex
        if self.bomb and self.clock % 2 == 0:
            self.bomb += 1
            if self.bomb == 17:
                if self.paddle <= self.bx < self.paddle + self.width:
                    if self.guard:
                        self.guard = 0
                    else:
                        self.jam = 48
                        self.wide = 0
                        self.width = 4
                    self.impact(self.bx + 1, 18)
                self.bomb = 0
        if self.item and self.clock % 2 == 0:
            self.iy += 1
            if self.iy == 17:
                if self.paddle <= self.ix < self.paddle + self.width:
                    if self.item == 1:
                        self.jam = 0
                        self.wide = 96
                        self.width = 10
                        self.paddle = min(20, self.paddle)
                    if self.item == 2:
                        self.slow = 96
                    if self.item == 3:
                        self.guard = 1
                    self.caught = (self.caught + 1) & 0xff
                self.item = 0

    def ball(self):
        if self.x == 0:
            self.dx = 1
        if self.x == 29:
            self.dx = 0
        if not self.steep or self.steps % 2 == 0:
            self.x = (self.x + 1 if self.dx else self.x - 1) & 0xff
        if self.y == 0:
            self.dy = 1
        self.y = (self.y + 1 if self.dy else self.y - 1) & 0xff
        if self.y < 8:
            i = self.x // 5 + (self.y // 2) * 6
            if self.b[i]:
                if self.b[i] == 1:
                    self.vanish(1 + i % 6 * 5, 2 + i // 6 * 2)
                self.b[i] -= 1
                if self.b[i]:
                    self.impact(1 + i % 6 * 5, 2 + i // 6 * 2)
                self.dy ^= 1
                if not self.b[i]:
                    self.left -= 1
                    self.broken = (self.broken + 1) & 0xff
                    if self.broken % 3 == 0:
                        self.drop((self.broken // 3 + self.port.level) % 3 + 1, self.x, self.y)
        if (self.enemy and self.y == 10 and ((self.x + 1) & 0xff) >= self.ex
                and self.x <= ((self.ex + 1) & 0xff)):
            self.enemy -= 1
            self.dy ^= 1
            if self.enemy:
                self.impact(self.ex, 12)
            else:
                self.vanish(self.ex, 12)
            if not self.enemy:
                self.drop(3, self.ex, 10)
        if self.y == 16:
            if self.paddle <= self.x < self.paddle + self.width:
                self.dy = 0
                self.bounces = (self.bounces + 1) & 0xff
                middle = self.paddle + self.width // 2
                self.steep = 1 if self.x == middle or self.x + 1 == middle else 0
                self.dx = 0 if self.x < middle else 1
            elif self.guard:
                self.guard = 0
                self.dy = 0
            else:
                self.hp -= 1
                self.impact(self.x + 1, 18)
                if self.hp:
                    self.serve()

    def tick(self):
        direction = self.held
        if direction in (3, 4):
            if self.repeat:
                self.repeat -= 1
            else:
                self.move_paddle(direction)
        else:
            self.repeat = 0
        self.clock = (self.clock + 1) & 0xff
        if self.jam:
            self.jam -= 1
            if not self.jam:
                self.width = 6
                self.paddle = min(24, self.paddle)
        if self.wide:
            self.wide -= 1
            if not self.wide:
                self.width = 6
        if self.slow:
            self.slow -= 1
        self.hazards()
        if self.hp:
            if not self.slow or self.clock % 2 == 0:
                self.steps = (self.steps + 1) & 0xff
                self.ball()
        if self.hp == 0:
            self.port.lose()
        elif self.left == 0 and not self.enemy:
            self.port.win()

    def state_bytes(self):
        return bytes(self.b + [getattr(self, name) & 0xff for name in STATE_FIELDS]).hex()
