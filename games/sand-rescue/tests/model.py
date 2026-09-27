# SPDX-License-Identifier: MIT
"""SAND RESCUE rules model (jr100dev games/sand_rescue/rules.py 2.0.0).

LAYOUT is the RAM layout of src/main.asm from GAME_STATE: the fields, b[15]
(near need, far need, soak, near step, far step for the three channels) and
c[6] (water given to the three near and three far crops). The tables are
upstream game.json dataTables.

Upstream carryCampaign: clearing a field keeps water + tank and the total
(checkpoint) for the next field; a loss or a restart begins again at field 1.
KEEP (class-wide, like the port's RAM outside the stage state) holds
(cleared field, water, total) until the next field consumes it.
"""

LEVELS = 6
NEAR_NEED = [2, 2, 2, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 3, 2, 3, 2, 3]
FAR_NEED = [4, 3, 5, 4, 5, 3, 5, 4, 3, 4, 5, 4, 5, 4, 5, 5, 5, 4]
SOAK = [1, 2, 3, 2, 1, 2, 3, 2, 1, 1, 3, 2, 2, 1, 3, 3, 2, 1]
NEAR_STEP = [3, 4, 3, 4, 3, 5, 5, 3, 4, 3, 5, 4, 4, 5, 3, 5, 4, 3]
FAR_STEP = [10, 11, 12, 12, 10, 11, 11, 12, 10, 10, 12, 11, 12, 11, 10, 11, 10, 12]
QUOTAS = [14, 17, 19, 21, 24, 26]
LAYOUT = [('water', 1), ('total', 1), ('quota', 1), ('interval', 1), ('fill', 1), ('gate', 1),
          ('score', 1), ('flow', 1), ('tank', 1), ('route', 1), ('step', 1), ('notice', 1),
          ('opening', 1), ('notice_time', 1), ('growing', 1), ('reward', 1), ('age', 1),
          ('waste', 1), ('drying', 1), ('b', 15), ('c', 6)]
SIZE = sum(n for _, n in LAYOUT)
LOSS = 'NO WATER LEFT FOR THE HARVEST'


class SandRescue:
    port = None
    KEEP = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.held = 0

    def init(self):
        keep, SandRescue.KEEP = SandRescue.KEEP, None
        if self.port.level and not (keep and keep[0] + 1 == self.port.level):
            self.port.level = 0
        level = self.port.level
        self.water = 108 if level == 0 else keep[1]
        self.total = 0 if level == 0 else keep[2]
        self.quota = QUOTAS[level]
        self.interval = 5 - level // 2
        self.fill = self.interval
        b = self.b
        for i in range(3):
            k = level * 3 + i
            b[i], b[3 + i], b[6 + i] = NEAR_NEED[k], FAR_NEED[k], SOAK[k]
            b[9 + i], b[12 + i] = NEAR_STEP[k], FAR_STEP[k]

    def act(self, action):
        if action in (3, 4):
            self.gate = (self.gate + (2 if action == 3 else 1)) % 3
        elif action == 1 and self.score >= self.quota and self.flow == 0:
            self.total = (self.total + self.score) & 0xff
            SandRescue.KEEP = (self.port.level, (self.water + self.tank) & 0xff, self.total)
            self.port.win()
        elif action == 5 and self.flow == 0 and self.tank:
            self.route = self.gate
            self.flow = self.tank
            self.tank = 0
            self.step = 0
            self.notice = 0
            self.opening = 0

    def irrigate(self, i):
        b, c = self.b, self.c
        for _ in range(5):
            if self.flow and c[i] < b[i]:
                self.flow -= 1
                c[i] += 1
                if c[i] == b[i]:
                    self.reward = 3 if i < 3 else b[i] * 2
                    self.score = (self.score + self.reward) & 0xff
                    self.notice = 1
                    self.notice_time = 12
        self.growing = 0

    def tick(self):
        b = self.b
        self.age = (self.age + 1) & 0xff
        if self.notice_time:
            self.notice_time -= 1
        if self.flow:
            self.step += 1
            r = self.route
            if self.step == b[9 + r]:
                self.irrigate(r)
            elif self.step == b[9 + r] + 3:
                loss = min(self.flow, b[6 + r])
                self.flow -= loss
                self.waste = (self.waste + loss) & 0xff
                self.notice = 2
                self.notice_time = 8
                self.drying = 0
            elif self.step == b[12 + r]:
                self.irrigate(3 + r)
            elif self.step > b[12 + r] + 2:
                self.waste = (self.waste + self.flow) & 0xff
                self.flow = 0
        if self.water:
            self.fill -= 1
            if self.fill == 0:
                self.fill = self.interval
                self.water -= 1
                if self.tank < 9:
                    self.tank += 1
                else:
                    self.waste = (self.waste + 1) & 0xff
                    self.notice = 3
                    self.notice_time = 8
        if self.water == 0 and self.tank == 0 and self.flow == 0 and self.score < self.quota:
            self.port.lose(LOSS)

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(out).hex()
