# SPDX-License-Identifier: MIT
"""ECHO PARRY rules model (jr100dev games/echo_parry/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE. PATTERN is the
upstream game.json dataTables.pattern (0 high, 1 low attack).
"""

LEVELS = 6
PATTERN = [0, 1, 1, 0, 1, 0, 0, 1]
LAYOUT = [('hp', 1), ('enemy', 1), ('attack', 1), ('stance', 1), ('phase', 1), ('guarded', 1),
          ('evade', 1), ('combo', 1), ('age', 1), ('turn', 1), ('feint', 1), ('counter', 1)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = {'parry': 'WRONG GUARD OR EARLY PARRY', 'window': 'MISSED THE PARRY WINDOW'}


class EchoParry:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, _ in LAYOUT:
            setattr(self, name, 0)
        self.held = 0

    def init(self):
        level = self.port.level
        self.hp = 4
        self.enemy = 6 + level
        self.attack = PATTERN[level % 8]

    def act(self, action):
        if action == 1:
            self.stance = 0
        if action == 2:
            self.stance = 1
        if action == 3 and self.phase < 2 and not self.guarded:
            self.evade = 1
            self.guarded = 1
            self.combo = 0
        if action == 5:
            if self.phase == 1 and self.stance == self.attack and not self.guarded:
                self.combo = min(3, self.combo + 1)
                damage = 2 if self.age == 1 or self.combo == 3 else 1
                self.enemy = self.enemy - damage if self.enemy >= damage else 0
                self.guarded = 1
                self.counter = damage
                if self.enemy == 0:
                    self.port.win()
                self.counter = 0
            elif not self.guarded:
                self.hp -= 1
                self.combo = 0
                self.guarded = 1
                if self.hp == 0:
                    self.port.lose(LOSS['parry'])

    def tick(self):
        level = self.port.level
        self.age = (self.age + 1) & 0xff
        if self.phase == 0 and self.age == 2 and level >= 2 and self.turn % 3 == 1:
            self.attack ^= 1
            self.feint = 1
        if self.phase == 0 and self.age >= (4 if level < 4 else 3):
            self.phase = 1
            self.age = 0
        elif self.phase == 1 and self.age >= 2:
            if not self.guarded:
                self.hp -= 1
                self.combo = 0
                if self.hp == 0:
                    self.port.lose(LOSS['window'])
                    return
            self.phase = 2
            self.age = 0
        elif self.phase == 2 and self.age >= 3:
            self.phase = 0
            self.age = 0
            self.turn = (self.turn + 1) & 0xff
            self.attack = PATTERN[(self.turn + level * 3) % 8]
            self.guarded = 0
            self.evade = 0
            self.feint = 0

    def state_bytes(self):
        return bytes(getattr(self, name) for name, _ in LAYOUT).hex()
