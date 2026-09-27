# SPDX-License-Identifier: MIT
"""PENDULUM PORT rules model (jr100dev games/pendulum_port/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE. A jump is resolved
inside act() (the upstream flight and landing effects stop the clock).
"""

LEVELS = 6
LAYOUT = [('hp', 1), ('rope', 1), ('target', 1), ('width', 1), ('swing', 1),
          ('direction', 1), ('ports', 1), ('score', 1), ('dest', 1), ('airborne', 1)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = 'THE JUMP MISSED THE PORT'


class PendulumPort:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, _ in LAYOUT:
            setattr(self, name, 0)
        self.held = 0
        self.effects = []

    def new_port(self):
        level = self.port.level
        self.target = 4 + (self.ports * 7 + level * 3 + 6) % 9
        self.width = 1 if level < 3 or self.ports % 3 else 0
        self.swing = 0
        self.direction = 1

    def init(self):
        self.hp = 3
        self.rope = 2
        self.new_port()

    def landing(self):
        if self.direction:
            return min(15, self.swing + self.rope)
        return self.swing - self.rope if self.swing >= self.rope else 0

    def act(self, action):
        if action == 3 and self.rope > 1:
            self.rope -= 1
        if action == 4 and self.rope < 3:
            self.rope += 1
        if action == 5:
            self.dest = self.landing()
            self.airborne = 1
            self.airborne = 2
            if self.dest + self.width >= self.target and self.dest <= self.target + self.width:
                self.score = (self.score + (2 if self.dest == self.target else 1)) & 0xff
                self.ports += 1
                if self.ports == 6 + self.port.level:
                    self.port.win()
                else:
                    self.new_port()
            else:
                self.hp -= 1
                if self.hp == 0:
                    self.port.lose(LOSS)
            self.airborne = 0

    def tick(self):
        if self.swing == 15:
            self.direction = 0
        if self.swing == 0:
            self.direction = 1
        self.swing = self.swing + 1 if self.direction else self.swing - 1

    def state_bytes(self):
        return bytes(getattr(self, name) for name, _ in LAYOUT).hex()
