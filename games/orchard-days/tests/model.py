# SPDX-License-Identifier: MIT
"""ORCHARD DAYS rules model (jr100dev games/orchard_days/rules.py 2.0.0).

state_bytes() mirrors src/main.asm: seeds, water, quota, period, cursor, crop,
notice, gain, fruit, day, rain, growing, then b[16] growth, c[16] crop (1 apple)
and d[16] watered-today flags.

`frames` counts the animation frames an action plays (not part of the state);
replays use it to leave enough time before the next key.
"""

LEVELS = 3
LOSS = 'THE SEASON ENDED BELOW QUOTA'
FIELDS = ('seeds', 'water', 'quota', 'period', 'cursor', 'crop', 'notice', 'gain', 'fruit',
          'day', 'rain', 'growing')
FLIGHT = 15     # five frames of animate(3)


def move(pos, action, width=4, height=5):
    if action == 1 and pos >= width:
        return pos - width
    if action == 2 and pos < width * (height - 1):
        return pos + width
    if action == 3 and pos % width:
        return pos - 1
    if action == 4 and pos % width < width - 1:
        return pos + 1
    return pos


class OrchardDays:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 16
        self.c = [0] * 16
        self.d = [0] * 16
        self.frames = 0

    def init(self):
        level = self.port.level
        self.seeds = 8
        self.water = 6
        self.quota = 18 + level * 6
        self.period = 4 + level

    def need(self, i):
        return 5 if self.c[i] else 3

    def act(self, action):
        self.frames = 0
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action != 5:
            return
        self.notice = 0
        cur = self.cursor
        if cur >= 16:
            if cur < 18:
                self.crop = cur - 16
                return
            if cur == 18:
                self.notice = 3
            else:
                if self.water >= 9:
                    return
                self.water = min(9, self.water + 3)
                self.notice = 4
        else:
            if self.b[cur] == 0:
                if self.seeds == 0:
                    self.notice = 5
                    return
                self.frames += FLIGHT
                self.seeds -= 1
                self.b[cur] = 1
                self.c[cur] = self.crop
            elif self.b[cur] < self.need(cur):
                if self.water == 0:
                    self.notice = 6
                    return
                self.water -= 1
                self.notice = 1
                self.frames += FLIGHT
                self.d[cur] = 1
            else:
                self.b[cur] = 0
                self.notice = 2
                self.gain = 7 if self.c[cur] else 3
                self.frames += FLIGHT
                self.fruit += self.gain
                self.seeds += 1
        self.day += 1
        self.rain = 1 if self.day % self.period == 0 else 0
        if self.rain:
            self.water = min(9, self.water + 4)
            self.frames += 12
        for i in range(16):
            if self.b[i] and self.b[i] < self.need(i) and (self.d[i] or self.rain):
                self.b[i] += 1
                self.growing = i + 1
                self.frames += 4
            self.d[i] = 0
        self.growing = 0
        self.rain = 0
        if self.fruit >= self.quota:
            self.port.win()
        elif self.day >= 28:
            self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([getattr(self, name) for name in FIELDS] + self.b + self.c + self.d).hex()


def plan(level, plots=4, crop=1):
    """Greedy season: plant `plots` plots of `crop`, water the ripest, harvest, draw water.

    Returns the list of targets to confirm (0-15 plots, 16-19 tools) or None."""
    from port_model import PortModel
    port = PortModel(OrchardDays(), LEVELS)
    port.level = level
    port.new_level()
    game = port.game
    targets = []

    def press(target):
        targets.append(target)
        game.cursor = target
        game.act(5)

    if crop != game.crop:
        press(16 + crop)
    while port.mode == 1:
        ripe = [i for i in range(16) if game.b[i] and game.b[i] >= game.need(i)]
        growing = [i for i in range(16) if game.b[i] and game.b[i] < game.need(i)]
        empty = [i for i in range(plots) if game.b[i] == 0]
        if ripe:
            press(ripe[0])
        elif empty and game.seeds:
            press(empty[0])
        elif growing and game.water:
            press(max(growing, key=lambda i: game.b[i]))
        elif game.water < 9:
            press(19)
        else:
            press(18)
    return targets if port.mode == 2 else None


def best_plan(level):
    """The shortest greedy season over plot counts and crops."""
    found = [p for plots in range(1, 17) for crop in (0, 1)
             for p in [plan(level, plots, crop)] if p]
    return min(found, key=len) if found else None
