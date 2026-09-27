# SPDX-License-Identifier: MIT
"""SHADOW ARCHIVE rules model (jr100dev games/shadow_archive/rules.py 2.1.0).

state_bytes() mirrors src/main.asm: culprit, mode_choice, choice, file,
accusing, read, then b[6] suspects and c[3] opened files.
"""
from itertools import combinations

SUSPECTS = [1, 2, 3, 4, 5, 6, 5, 2, 6, 4, 3, 1, 3, 4, 6, 1, 5, 2, 6, 3, 4, 5, 2, 1, 4, 5, 2, 6, 3, 1, 1, 3, 6, 2, 4, 5, 3, 4, 1, 6, 2, 5, 4, 6, 3, 5, 1, 2, 1, 2, 5, 6, 4, 3, 4, 5, 6, 1, 2, 3, 3, 6, 1, 2, 4, 5, 1, 5, 2, 6, 3, 4]
WHO = [2, 1, 3, 0, 1, 4, 0, 5, 0, 2, 5, 5]
LEVELS = 12
LOSS = 'THE SUSPECT DOES NOT FIT THE FILES'


class ShadowArchive:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.culprit = self.mode_choice = self.choice = self.file = 0
        self.accusing = self.read = 0
        self.b = [0] * 6
        self.c = [0] * 3

    def init(self):
        level = self.port.level
        self.culprit = WHO[level]
        self.b = SUSPECTS[level * 6:level * 6 + 6]

    def act(self, action):
        if action in (1, 2):
            self.mode_choice ^= 1
        if action in (3, 4):
            if self.mode_choice:
                self.choice = (self.choice + (5 if action == 3 else 1)) % 6
            else:
                self.file = (self.file + (2 if action == 3 else 1)) % 3
        if action == 5:
            if self.mode_choice:
                self.accusing = 1
                if self.choice == self.culprit:
                    self.port.win()
                else:
                    self.port.lose(LOSS)
            elif not self.c[self.file]:
                self.c[self.file] = 1
                self.read += 1

    def state_bytes(self):
        return bytes([self.culprit, self.mode_choice, self.choice, self.file, self.accusing,
                      self.read] + self.b + self.c).hex()


def contradicted(b, culprit, opened):
    return [any(opened[t] and (b[i] >> t & 1) != (b[culprit] >> t & 1) for t in range(3))
            for i in range(6)]


def fewest_files(level):
    """Smallest file set (in order) that leaves only the culprit uncontradicted."""
    b = SUSPECTS[level * 6:level * 6 + 6]
    culprit = WHO[level]
    for size in range(4):
        for files in combinations(range(3), size):
            opened = [1 if t in files else 0 for t in range(3)]
            if contradicted(b, culprit, opened).count(False) == 1:
                return list(files)
    raise ValueError(level)
