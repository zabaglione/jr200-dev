# SPDX-License-Identifier: MIT
"""METRO WEAVE rules model (jr100dev games/metro_weave/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, b[18]
(three trains: x, y, track, destination, deadline, express at +0, +3, ...
+15) and c[19] (0-1 points, 2-3 stops, 8-10 platform busy timers, 16-18 the
next destinations). Upstream's entropy() origin is an input: the model takes
it from `ORIGIN` (the self test and the demo use 0; normal play samples it).
"""

LEVELS = 3
LAYOUT = [('hp', 1), ('origin', 1), ('seed', 1), ('capacity', 1), ('interval', 1),
          ('quota', 1), ('issued', 1), ('active', 1), ('cool', 1), ('notice', 1),
          ('notice_time', 1), ('cursor', 1), ('arrival', 1), ('done', 1), ('reward', 1),
          ('chain', 1), ('score', 1), ('medal', 1), ('age', 1), ('b', 18), ('c', 19)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = {3: 'EXPRESS LATE', 2: 'WRONG PLATFORM', 'quota': 'NOT ENOUGH POINTS THIS SHIFT'}


class MetroWeave:
    port = None
    ORIGIN = 0

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.held = 0

    def rand(self):
        self.seed = (self.seed * 5 + 1) & 0xff
        return self.seed

    def init(self):
        level = self.port.level
        self.hp = 3
        self.origin = self.ORIGIN
        self.seed = self.origin ^ ((37 + level * 17) & 0xff)
        self.capacity = min(3, 2 + level)
        self.interval = 24 - level * 8
        self.quota = 24 + level * 6
        for i in range(3):
            self.c[16 + i] = self.rand() % 3
        self.dispatch(0)

    def dispatch(self, express):
        b, c = self.b, self.c
        if self.issued == 8 or self.active == self.capacity:
            return
        for i in range(3):
            if b[i] and b[i] < 5:
                return
        for i in range(3):
            if b[i] == 0:
                b[i], b[3 + i], b[6 + i], b[9 + i], b[12 + i], b[15 + i] = 2, 5, 0, c[16], 32, express
                c[16], c[17] = c[17], c[18]
                c[18] = self.rand() % 3
                self.issued += 1
                self.active += 1
                self.cool = self.interval
                self.notice = 4 if express else 0
                self.notice_time = 8
                return

    def act(self, action):
        c = self.c
        if action in (1, 2):
            self.cursor ^= 1
        elif action == 3:
            c[2 + self.cursor] ^= 1
        elif action == 4:
            c[self.cursor] ^= 1
        elif action == 5:
            self.dispatch(1)

    def arrive(self, i):
        b, c = self.b, self.c
        self.arrival = i + 1
        c[8 + b[6 + i]] = 12
        self.done += 1
        self.active -= 1
        self.reward = 0
        if b[6 + i] != b[9 + i]:
            self.notice = 2
        elif b[15 + i] == 2:
            self.notice = 3
        else:
            self.notice = 1
            self.chain = min(3, self.chain + 1)
            self.reward = (4 if b[15 + i] else 2) * self.chain
            self.score = (self.score + self.reward) & 0xff
        self.notice_time = 10
        if not self.reward:
            self.hp -= 1
            self.chain = 0
        if self.hp == 0:
            self.port.lose(LOSS[3] if self.notice == 3 else LOSS[2])
            return
        if self.done == 8:
            if self.score < self.quota:
                self.port.lose(LOSS['quota'])
            else:
                self.medal = 3 if self.score >= 60 else (2 if self.score >= 44 else 1)
                self.port.win()
            return
        b[i] = 0

    def advance_train(self, i):
        b, c = self.b, self.c
        if b[15 + i] == 1:
            if b[12 + i]:
                b[12 + i] -= 1
            else:
                b[15 + i] = 2
        if b[i] == 8 and b[3 + i] == 5:
            if c[2]:
                return
            b[6 + i] = c[0]
        if b[i] == 17 and b[3 + i] == 10:
            if c[3]:
                return
            b[6 + i] = 1 + c[1]
        if b[i] == 25 and c[8 + b[6 + i]]:
            return
        nx = b[i] + 1
        ny = b[3 + i] + (1 if b[3 + i] < 5 + b[6 + i] * 5 else 0)
        for j in range(3):
            if j != i and b[j]:
                if abs(nx - b[j]) < 3 and abs(ny - b[3 + j]) < 2:
                    return
        b[i] = nx
        b[3 + i] = ny
        if nx == 26:
            self.arrive(i)

    def tick(self):
        self.arrival = 0
        self.age = (self.age + 1) & 0xff
        if self.notice_time:
            self.notice_time -= 1
        if self.cool:
            self.cool -= 1
        for i in range(3):
            if self.c[8 + i]:
                self.c[8 + i] -= 1
        for i in range(3):
            if self.b[i]:
                self.advance_train(i)
                if self.port.mode != 1:
                    return
        if self.cool == 0:
            self.dispatch(0)

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
