# SPDX-License-Identifier: MIT
"""POTION PATH rules model (jr100dev games/potion_path/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: x, y, tx, ty, ingredient, notice,
pouring, doses, then b[64] (poison cells) and c[4] (ingredients left).

`frames` counts the animation frames an action plays (not part of the state).
"""
from collections import deque

ORDERS = [
    1, 2, 3, 1, 5, 7, 7, 6, 1, 1, 3, 0, 4, 3, 6, 2, 0, 4, 1, 7, 3, 6, 5, 5, 7, 4, 1, 6, 3,
    5, 5, 4, 6, 7, 0, 2, 2, 1, 4, 0]
HAZARDS = [
    0, 22, 40, 4, 255, 255, 255, 3, 37, 31, 2, 255, 255, 255, 15, 37, 36, 58, 255, 255,
    255, 47, 7, 53, 37, 255, 255, 255, 37, 10, 35, 36, 255, 255, 255, 56, 12, 18, 32, 49,
    255, 255, 50, 56, 38, 32, 31, 255, 255, 14, 1, 12, 63, 50, 255, 255, 21, 15, 19, 51,
    29, 255, 255, 1, 35, 49, 60, 38, 255, 255, 49, 19, 13, 17, 48, 41, 255, 25, 36, 2, 5,
    39, 62, 255, 3, 40, 6, 38, 62, 10, 255, 39, 28, 5, 43, 20, 46, 255, 36, 62, 46, 5, 33,
    7, 255, 53, 5, 24, 34, 2, 7, 3, 49, 58, 0, 30, 15, 8, 47, 45, 33, 50, 47, 2, 52, 17,
    44, 42, 4, 17, 23, 31, 55, 1, 43, 17, 34, 40, 21, 19]
PARS = [
    2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6]
LEVELS = 20
LOSS = 'TWELVE DOSES MISSED THE RECIPE'
FIELDS = ('x', 'y', 'tx', 'ty', 'ingredient', 'notice', 'pouring', 'doses')
NAMES = ('ASH', 'MOSS', 'SALT', 'ROOT')


def step(x, y, ingredient):
    """Upstream's move for an ingredient, or None off the board."""
    if ingredient == 0:
        return (x - 2, y) if x >= 2 else None
    if ingredient == 1:
        return (x + 1, y + 2) if x < 7 and y < 6 else None
    if ingredient == 2:
        return (x, y - 1) if y else None
    return (x + 3, y + 1) if x < 5 and y < 7 else None


def poison(level):
    b = [0] * 64
    for i in range(7):
        cell = HAZARDS[level * 7 + i]
        if cell != 255:
            b[cell] = 1
    return b


class PotionPath:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 64
        self.c = [0] * 4
        self.frames = 0

    def init(self):
        level = self.port.level
        self.x = self.y = 3
        self.tx, self.ty = ORDERS[level * 2], ORDERS[level * 2 + 1]
        self.b = poison(level)
        self.c = [4] * 4

    def act(self, action):
        self.frames = 0
        if action in (1, 3):
            self.ingredient = (self.ingredient + 3) % 4
        if action in (2, 4):
            self.ingredient = (self.ingredient + 1) % 4
        if action != 5:
            return
        if not self.c[self.ingredient]:
            self.notice = 1
            return
        self.notice = 0
        target = step(self.x, self.y, self.ingredient)
        if target is None:
            return
        nx, ny = target
        if self.b[ny * 8 + nx]:
            self.notice = 2
            return
        self.c[self.ingredient] -= 1
        self.frames += 30
        self.x, self.y = nx, ny
        self.doses += 1
        if (self.x, self.y) == (self.tx, self.ty):
            self.frames += 12
            self.port.win()
        elif self.doses >= 12:
            self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.c).hex()


def solve(level):
    """Fewest ingredients from the start to the order (breadth-first, stocks of four)."""
    b = poison(level)
    goal = (ORDERS[level * 2], ORDERS[level * 2 + 1])
    start = (3, 3, (4, 4, 4, 4))
    prev = {start: None}
    queue = deque([start])
    while queue:
        state = queue.popleft()
        x, y, stock = state
        if (x, y) == goal:
            path = []
            while prev[state]:
                state, used = prev[state]
                path.append(used)
            return path[::-1]
        for ingredient in range(4):
            if not stock[ingredient]:
                continue
            target = step(x, y, ingredient)
            if target is None or b[target[1] * 8 + target[0]]:
                continue
            left = list(stock)
            left[ingredient] -= 1
            nxt = (target[0], target[1], tuple(left))
            if nxt not in prev:
                prev[nxt] = (state, ingredient)
                queue.append(nxt)
    return None
