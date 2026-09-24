# SPDX-License-Identifier: MIT
"""CIRCUIT WORKS rules model (jr100dev games/circuit_works/rules.py 2.1.0).

Observed RAM layout of src/main.asm: c[3], d[8], b[8], cursor, probe, running,
signal, pulse, correct, tested, tests.
"""

LEVELS = 22
AND, OR, XOR = 0, 1, 2
# game.json dataTables.targets: three gate kinds per puzzle.
TARGETS = [0, 0, 0, 0, 0, 1, 0, 0, 2, 0, 1, 0, 0, 1, 1, 0, 1, 2, 0, 2, 0, 0, 2, 2, 1, 0, 0,
           1, 0, 1, 1, 0, 2, 1, 1, 1, 1, 1, 2, 1, 2, 0, 1, 2, 1, 1, 2, 2, 2, 0, 0, 2, 0, 2,
           2, 1, 0, 2, 1, 2, 2, 2, 0, 2, 2, 2]


def gate(a, b, kind):
    if kind == 0:
        return a & b
    if kind == 1:
        return a | b
    return a ^ b


def output(a, b, c, p, q, r):
    return gate(gate(gate(a, b, p), c, q), a, r)


def inputs(i):
    return i // 4, i // 2 % 2, i % 2


def wanted(level):
    p, q, r = TARGETS[level * 3:level * 3 + 3]
    return [output(*inputs(i), p, q, r) for i in range(8)]


def solutions(level):
    table = wanted(level)
    return [(p, q, r) for p in range(3) for q in range(3) for r in range(3)
            if [output(*inputs(i), p, q, r) for i in range(8)] == table]


class CircuitWorks:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.c = [0, 0, 0]
        self.d = [0] * 8
        self.b = [0] * 8
        self.cursor = self.probe = self.running = self.signal = self.pulse = 0
        self.correct = self.tested = self.tests = 0

    def init(self):
        self.d = wanted(self.port.level)
        self.probe = 255
        self.running = 255

    def act(self, action):
        if action == 1:
            self.cursor = (self.cursor + 2) % 3
        if action == 2:
            self.cursor = (self.cursor + 1) % 3
        if action == 3:
            self.c[self.cursor] = (self.c[self.cursor] + 2) % 3
        if action == 4:
            self.c[self.cursor] = (self.c[self.cursor] + 1) % 3
        if action == 5:
            self.correct = 0
            self.tested = 0
            for i in range(8):
                self.probe = i
                a, b, c = inputs(i)
                self.signal = a
                for stage in range(3):
                    self.running = stage
                    operand = b if stage == 0 else (c if stage == 1 else a)
                    self.signal = gate(self.signal, operand, self.c[stage])
                    self.pulse = 2
                self.b[i] = self.signal
                self.tested += 1
                if self.b[i] == self.d[i]:
                    self.correct += 1
            self.running = 255
            self.probe = 255
            self.tests = min(self.tests + 1, 99)
            if self.correct == 8:
                self.port.win()

    def state_bytes(self):
        return bytes(self.c + self.d + self.b + [
            self.cursor, self.probe, self.running, self.signal, self.pulse,
            self.correct, self.tested, self.tests]).hex()


def gate_keys(current, target, cursor=0):
    """Keys that set gates to target from current, ending on RETURN."""
    keys = []
    for stage in range(3):
        while cursor != stage:
            keys.append('s')
            cursor = (cursor + 1) % 3
        delta = (target[stage] - current[stage]) % 3
        keys += ['d'] * delta if delta == 1 else (['a'] if delta == 2 else [])
    return keys + ['ret'], cursor
