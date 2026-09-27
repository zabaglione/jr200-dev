# SPDX-License-Identifier: MIT
"""WORD FOUNDRY rules model (jr100dev games/word_foundry/rules.py 2.0.0).

state_bytes() mirrors src/main.asm: word, goal, via, limit, cursor, steps, forged,
old, changing, lift, effect, effect_phase, d[16] (the ladder history).
"""

WORDS = ['CAT', 'COT', 'COG', 'DOG', 'DOT', 'DAT', 'BAT', 'BOT',
         'BAG', 'BOG', 'BIG', 'DIG', 'PIG', 'PIT', 'SIT', 'SAT']
STARTS = [0, 1, 3, 5, 9, 11, 13, 15, 7, 2, 8, 10, 4, 12, 14, 6]
GOALS = [12, 2, 14, 10, 1, 14, 11, 4, 0, 9, 13, 13, 1, 13, 13, 8]
VIA = [1, 11, 6, 1, 12, 7, 4, 10, 13, 13, 4, 1, 13, 1, 2, 2]
PARS = [5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 5]
LEVELS = 16
LOSS = 'WORD LADDER RAN OUT OF STEPS'


def diff(a, b):
    return sum(1 for x, y in zip(WORDS[a], WORDS[b]) if x != y)


def move(pos, action, width=4, height=4):
    if action == 1 and pos >= width:
        return pos - width
    if action == 2 and pos < width * (height - 1):
        return pos + width
    if action == 3 and pos % width > 0:
        return pos - 1
    if action == 4 and pos % width < width - 1:
        return pos + 1
    return pos


def shortest(start, goal):
    """Breadth-first word path (list of words after start)."""
    previous = {start: None}
    queue = [start]
    while queue:
        word = queue.pop(0)
        if word == goal:
            break
        for other in range(16):
            if other not in previous and diff(word, other) == 1:
                previous[other] = word
                queue.append(other)
    path = []
    word = goal
    while word != start:
        path.append(word)
        word = previous[word]
    return path[::-1]


def solution(level):
    return shortest(STARTS[level], VIA[level]) + shortest(VIA[level], GOALS[level])


class WordFoundry:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.word = self.goal = self.via = self.limit = 0
        self.cursor = self.steps = self.forged = self.old = 0
        self.changing = self.lift = self.effect = self.effect_phase = 0
        self.d = [0] * 16

    def init(self):
        level = self.port.level
        self.word = STARTS[level]
        self.goal = GOALS[level]
        self.via = VIA[level]
        self.limit = PARS[level] + 2
        self.d[0] = self.word

    def act(self, action):
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5:
            if diff(self.word, self.cursor) == 1:
                self.old = self.word
                self.lift = 2
                self.word = self.cursor
                self.steps += 1
                self.d[self.steps] = self.word
                if self.word == self.via:
                    self.forged = 1
                    self.effect_phase = 2
                if self.word == self.goal and self.forged:
                    self.port.win()
                elif self.steps == self.limit:
                    self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([self.word, self.goal, self.via, self.limit, self.cursor, self.steps,
                      self.forged, self.old, self.changing, self.lift, self.effect,
                      self.effect_phase] + self.d).hex()
