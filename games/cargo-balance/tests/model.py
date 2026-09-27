# SPDX-License-Identifier: MIT
"""CARGO BALANCE rules model (jr100dev games/cargo_balance/rules.py 2.0.0).

state_bytes() mirrors src/main.asm: weight, wind, tolerance, cursor, left,
right, loads, fare, notice, then b[16] crates and c[4] hold counts.
"""

CARGO = [1, 2, 3, 1, 3, 2, 2, 1, 3, 2, 1, 3, 2, 3, 1, 2, 1, 3, 3, 2, 1, 3, 2, 1, 3, 1, 2, 3, 2, 1, 1, 3, 2, 1, 3, 2, 1, 3, 2, 2, 3, 1, 3, 1, 2, 2, 1, 3, 2, 1, 3, 3, 1, 2, 1, 2, 3, 3, 2, 1, 3, 2, 1, 1, 2, 3, 2, 3, 1, 1, 3, 2]
LEVELS = 6
LOSS = 'THE LOAD TIPPED THE SHIP'


def tipped(left, right, wind, tolerance):
    return left + wind > right + tolerance or right > left + wind + tolerance


class CargoBalance:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.weight = self.wind = self.tolerance = self.cursor = 0
        self.left = self.right = self.loads = self.fare = self.notice = 0
        self.b = [0] * 16
        self.c = [0] * 4

    def init(self):
        level = self.port.level
        self.weight = CARGO[level * 12]
        self.wind = level % 3
        self.tolerance = 10 - level // 2

    def act(self, action):
        if action == 3:
            self.cursor = (self.cursor + 3) % 4
        if action == 4:
            self.cursor = (self.cursor + 1) % 4
        if action == 5 and self.c[self.cursor] >= 4:
            self.notice = 1
        elif action == 5:
            self.notice = 0
            hold = self.cursor
            self.b[hold * 4 + self.c[hold]] = self.weight
            self.c[hold] += 1
            torque = self.weight * (3 if hold in (0, 3) else 1)
            if hold < 2:
                self.left += torque
            else:
                self.right += torque
            self.loads += 1
            self.fare += self.weight * (2 if hold in (0, 3) else 1)
            if tipped(self.left, self.right, self.wind, self.tolerance):
                self.port.lose(LOSS)
            elif self.loads == 12:
                self.port.win()
            if self.loads < 12:
                self.weight = CARGO[self.port.level * 12 + self.loads]

    def state_bytes(self):
        return bytes([self.weight, self.wind, self.tolerance, self.cursor, self.left,
                      self.right, self.loads, self.fare, self.notice] + self.b + self.c).hex()


def plan(level, prefer_fare=True):
    """Holds for the twelve crates that never tip the ship (outer holds first)."""
    wind = level % 3
    tolerance = 10 - level // 2
    crates = CARGO[level * 12:level * 12 + 12]
    order = (0, 3, 1, 2) if prefer_fare else (1, 2, 0, 3)

    def search(index, left, right, counts):
        if index == 12:
            return []
        for hold in order:
            if counts[hold] >= 4:
                continue
            torque = crates[index] * (3 if hold in (0, 3) else 1)
            nleft, nright = (left + torque, right) if hold < 2 else (left, right + torque)
            if tipped(nleft, nright, wind, tolerance):
                continue
            ncounts = counts[:]
            ncounts[hold] += 1
            rest = search(index + 1, nleft, nright, ncounts)
            if rest is not None:
                return [hold] + rest
        return None

    return search(0, 0, 0, [0, 0, 0, 0])
