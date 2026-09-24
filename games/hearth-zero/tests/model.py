# SPDX-License-Identifier: MIT
"""HEARTH ZERO rules model (jr100dev games/hearth_zero/rules.py 2.1.0).

Observed RAM layout of src/main.asm: food, wood, heat, insulation, choice,
notice, phase, day, fire_frame, effect, effect_kind, effect_x, effect_y.
"""

LEVELS = 3
DAYS = 12
# game.json dataTables.weather: 12 nights for each of the three cold waves.
WEATHER = [4, 5, 6, 4, 7, 5, 4, 6, 5, 7, 4, 6, 5, 4, 7, 5, 6, 4, 7, 4, 6, 5, 7, 5, 4, 6, 5, 7,
           4, 6, 5, 7, 6, 4, 7, 6]
WOOD, FOOD, FIRE, WALL = range(4)
NO_FOOD = 'NO FOOD LEFT FOR THE NIGHT'
NO_HEAT = 'THE NIGHT EXTINGUISHED THE HEARTH'
FLIGHT_KIND = [4, 1, 3, 6]


class HearthZero:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.food = self.wood = self.heat = self.insulation = 0
        self.choice = self.notice = self.phase = self.day = self.fire_frame = 0
        self.effect = self.effect_kind = self.effect_x = self.effect_y = 0

    def init(self):
        self.food = 10
        self.wood = 8
        self.heat = 12

    def cold(self, offset=0):
        return WEATHER[self.port.level * DAYS + self.day + offset]

    def act(self, action):
        if action in (1, 3):
            self.choice = (self.choice + 3) % 4
        if action in (2, 4):
            self.choice = (self.choice + 1) % 4
        if action != 5:
            return
        self.notice = 0
        if self.choice == FIRE and self.wood < 3:
            self.notice = 1
            return
        if self.choice == WALL and (self.wood < 4 or self.insulation >= 2):
            self.notice = 2
            return
        self.phase = 1
        # flight(2 + choice * 8, 19, 5, 12, kind): the effect ends at (5, 12).
        self.effect_kind = FLIGHT_KIND[self.choice]
        self.effect_x, self.effect_y, self.effect = 5, 12, 0
        if self.choice == WOOD:
            self.wood = min(30, self.wood + 7)
        elif self.choice == FOOD:
            self.food = min(30, self.food + 7)
        elif self.choice == FIRE:
            self.wood -= 3
            self.heat = min(24, self.heat + 9)
        else:
            self.wood -= 4
            self.insulation += 1
        self.phase = 2
        cost = (self.cold() - self.insulation) & 0xff
        self.fire_frame = 0          # frames 0, 1, 0
        if self.food < 2:
            self.port.lose(NO_FOOD)
            return
        self.food -= 2
        if self.heat <= cost:
            self.heat = 0
            self.port.lose(NO_HEAT)
            return
        self.heat -= cost
        self.day += 1
        self.phase = 0
        if self.day == DAYS:
            self.port.win()

    def state_bytes(self):
        return bytes([self.food, self.wood, self.heat, self.insulation, self.choice,
                      self.notice, self.phase, self.day, self.fire_frame, self.effect,
                      self.effect_kind, self.effect_x, self.effect_y]).hex()


def plan_keys(choices, start=0):
    """W/S/A/D keys that select each job in turn and press RETURN."""
    keys = []
    cursor = start
    for job in choices:
        delta = (job - cursor) % 4
        keys += ['d'] * delta if delta <= 2 else ['a']
        keys.append('ret')
        cursor = job
    return keys


def survive(level):
    """Depth-first search for twelve job choices that survive the cold wave."""
    import sys
    sys.setrecursionlimit(10000)
    from itertools import product  # noqa: F401 - documented alternative

    def search(state, path):
        food, wood, heat, wall, day = state
        if day == DAYS:
            return path
        cold = WEATHER[level * DAYS + day]
        for job in (FIRE, WOOD, FOOD, WALL):
            f, w, h, i = food, wood, heat, wall
            if job == FIRE and w < 3 or job == WALL and (w < 4 or i >= 2):
                continue
            if job == WOOD:
                w = min(30, w + 7)
            elif job == FOOD:
                f = min(30, f + 7)
            elif job == FIRE:
                w -= 3
                h = min(24, h + 9)
            else:
                w -= 4
                i += 1
            cost = cold - i
            if f < 2 or h <= cost:
                continue
            found = search((f - 2, w, h - cost, i, day + 1), path + [job])
            if found:
                return found
        return None

    return search((10, 8, 12, 0, 0), [])
