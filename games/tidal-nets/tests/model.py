# SPDX-License-Identifier: MIT
"""TIDAL NETS rules model (jr100dev games/tidal_nets/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: fish, deep, rope, quota, tide, force,
cursor, wide, casts, catch, notice.
"""
from functools import lru_cache

LEVELS = 3
LOSS = 'THE FISHING TRIP MISSED QUOTA'


def tide_of(casts, level):
    return (1 if (casts + level) % 3 == 0 else 7), 1 + (casts + level) % 2


def cast(state, level, cursor, wide):
    """One cast from (fish, deep, rope, casts, catch); returns (new state, gain) or None."""
    fish, deep, rope, casts, catch = state
    cost = 2 if wide else 1
    if rope < cost:
        return None
    tide, force = tide_of(casts, level)
    landing = (fish + tide * force) % 8
    below = (deep + tide * force * 2) % 8
    gain = 0
    if cursor == landing or wide and (cursor + 1) % 8 == landing:
        gain += 2
    if cursor == below or wide and (cursor + 1) % 8 == below:
        gain += 4
    fish = (landing * 3 + 5 + level) % 8
    deep = (below * 5 + 3 + level) % 8
    return (fish, deep, rope - cost, casts + 1, catch + gain), gain


class TidalNets:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.fish = self.deep = self.rope = self.quota = self.tide = self.force = 0
        self.cursor = self.wide = self.casts = self.catch = self.notice = 0

    def init(self):
        level = self.port.level
        self.fish = (3 + level * 2) % 8
        self.deep = (1 + level * 3) % 8
        self.rope = 12
        self.quota = 30 + level * 3
        self.tide, self.force = tide_of(0, level)

    def act(self, action):
        if action == 3:
            self.cursor = (self.cursor + 7) % 8
        if action == 4:
            self.cursor = (self.cursor + 1) % 8
        if action in (1, 2):
            self.wide ^= 1
        if action == 5:
            level = self.port.level
            result = cast((self.fish, self.deep, self.rope, self.casts, self.catch), level,
                          self.cursor, self.wide)
            if result is None:
                self.notice = 7
                return
            (self.fish, self.deep, self.rope, self.casts, self.catch), gain = result
            self.notice = gain
            self.tide, self.force = tide_of(self.casts, level)
            if self.catch >= self.quota:
                self.port.win()
            elif self.casts == 9 or self.rope == 0:
                self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([self.fish, self.deep, self.rope, self.quota, self.tide, self.force,
                      self.cursor, self.wide, self.casts, self.catch, self.notice]).hex()


def plan(level):
    """(cursor, wide) casts that reach the quota, or None."""
    quota = 30 + level * 3

    @lru_cache(None)
    def best(state):
        fish, deep, rope, casts, catch = state
        if catch >= quota:
            return ()
        if casts == 9 or rope == 0:
            return None
        for wide in (1, 0):
            for cursor in range(8):
                result = cast(state, level, cursor, wide)
                if result is None:
                    continue
                rest = best(result[0])
                if rest is not None:
                    return ((cursor, wide),) + rest
        return None

    start = ((3 + level * 2) % 8, (1 + level * 3) % 8, 12, 0, 0)
    found = best(start)
    return list(found) if found is not None else None
