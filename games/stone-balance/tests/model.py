# SPDX-License-Identifier: MIT
"""STONE BALANCE rules model (jr100dev games/stone_balance/rules.py 2.0.0).

state_bytes() mirrors src/main.asm: b[3], pile, take, turn, enemy_pile,
enemy_take, misere.
"""

HEAPS = [2, 3, 7, 3, 3, 7, 4, 3, 6, 5, 3, 7, 6, 3, 7, 2, 5, 6, 3, 5, 7, 4, 5, 7, 5, 5, 7, 6, 5, 6]
NORMAL = [238, 221, 187, 119, 238, 221, 187, 119, 221, 238, 119, 187, 221, 238, 119, 187, 187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238, 238, 221, 187, 119, 238, 221, 187, 119, 221, 238, 119, 187, 221, 238, 119, 187, 187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238]
REVERSE = [221, 238, 187, 119, 221, 238, 187, 119, 238, 221, 119, 187, 238, 221, 119, 187, 187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238, 221, 238, 187, 119, 221, 238, 187, 119, 238, 221, 119, 187, 238, 221, 119, 187, 187, 119, 238, 221, 187, 119, 238, 221, 119, 187, 221, 238, 119, 187, 221, 238]
LEVELS = 10
LOSE_SELF = 'YOU TOOK THE LAST STONE'
LOSE_RIVAL = 'THE RIVAL TOOK THE LAST STONE'


def has_win(b, misere):
    value = (REVERSE if misere else NORMAL)[b[0] * 8 + b[1]]
    return value & (1 << b[2])


def rival_move(b, misere):
    for i in range(3):
        for j in range(3):
            if b[i] >= j + 1:
                trial = b[:]
                trial[i] -= j + 1
                if has_win(trial, misere) == 0:
                    return i, j + 1
    pile = 0
    for i in range(3):
        if b[i]:
            pile = i
    return pile, 1


class StoneBalance:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.b = [0, 0, 0]
        self.pile = self.take = self.turn = self.enemy_pile = self.enemy_take = 0
        self.misere = 0

    def init(self):
        level = self.port.level
        self.misere = 1 if level >= 5 else 0
        self.b = HEAPS[level * 3:level * 3 + 3]
        self.take = 1

    def act(self, action):
        if action == 1:
            self.pile = (self.pile + 2) % 3
        if action == 2:
            self.pile = (self.pile + 1) % 3
        if action == 3:
            self.take = 1 if self.take == 3 else self.take + 1
        if action == 4:
            self.take = 3 if self.take == 1 else self.take - 1
        if action == 5 and self.b[self.pile] >= self.take:
            self.turn = 1
            self.b[self.pile] -= self.take
            if sum(self.b) == 0:
                if self.misere:
                    self.port.lose(LOSE_SELF)
                else:
                    self.port.win()
                return
            self.enemy_pile, self.enemy_take = rival_move(self.b, self.misere)
            self.turn = 2
            self.b[self.enemy_pile] -= self.enemy_take
            if sum(self.b) == 0:
                if self.misere:
                    self.port.win()
                else:
                    self.port.lose(LOSE_RIVAL)

    def state_bytes(self):
        return bytes(self.b + [self.pile, self.take, self.turn, self.enemy_pile,
                               self.enemy_take, self.misere]).hex()


def winning_line(level):
    """Player moves (pile, take) that beat the deterministic rival, or None."""
    misere = level >= 5

    def search(b):
        for pile in range(3):
            for take in (1, 2, 3):
                if b[pile] < take:
                    continue
                after = b[:]
                after[pile] -= take
                if sum(after) == 0:
                    if not misere:
                        return [(pile, take)]
                    continue
                enemy = rival_move(after, misere)
                after[enemy[0]] -= enemy[1]
                if sum(after) == 0:
                    if misere:
                        return [(pile, take)]
                    continue
                rest = search(after)
                if rest is not None:
                    return [(pile, take)] + rest
        return None

    return search(HEAPS[level * 3:level * 3 + 3])
