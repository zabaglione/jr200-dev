# SPDX-License-Identifier: MIT
"""NUMBER VAULT rules model (jr100dev games/number_vault/rules.py 2.1.0).

state_bytes() mirrors src/main.asm: origin, secret, cursor, exact, near, tries,
b[4] dials, d[4] code, then the six-row history c[32..67].

origin is upstream's entropy(): an external input sampled at each stage start.
The JR-200 port samples the title-song driver (how long the title was shown);
the model receives it from the recorded run, as upstream's checks do, and
predicts every other byte from the rules.
"""
from itertools import product

LEVELS = 10
LOSS = 'TEN CODES DID NOT OPEN THE VAULT'


def code(origin, level):
    secret = origin ^ ((level * 23 + 17) & 0xff)
    return secret, [1 + (secret >> (i * 2)) % 4 for i in range(4)]


def score(guess, secret):
    exact = sum(1 for g, s in zip(guess, secret) if g == s)
    used_g = [g == s for g, s in zip(guess, secret)]
    used_s = used_g[:]
    near = 0
    for i in range(4):
        if used_g[i]:
            continue
        for j in range(4):
            if not used_g[i] and not used_s[j] and guess[i] == secret[j]:
                used_g[i] = used_s[j] = True
                near += 1
    return exact, near


def solve(secret):
    """First consistent guess in order, starting from 1122: at most six tries."""
    history = []
    candidates = [list(c) for c in product((1, 2, 3, 4), repeat=4)]
    guess = [1, 1, 2, 2]
    while True:
        result = score(guess, secret)
        history.append(guess)
        if result == (4, 0):
            return history
        candidates = [c for c in candidates if score(guess, c) == result]
        guess = candidates[0]


class NumberVault:
    port = None
    origins = []            # one sampled entropy value per stage start, in order

    def __init__(self):
        self.reset()
        self.samples = list(self.origins)

    def reset(self):
        self.origin = self.secret = self.cursor = self.exact = self.near = self.tries = 0
        self.b = [0] * 4
        self.d = [0] * 4
        self.hist = [0] * 36

    def init(self):
        self.origin = self.samples.pop(0) if self.samples else 0
        self.secret, self.d = code(self.origin, self.port.level)
        self.b = [1, 1, 1, 1]

    def act(self, action):
        if action == 3:
            self.cursor = (self.cursor + 3) % 4
        if action == 4:
            self.cursor = (self.cursor + 1) % 4
        if action == 1:
            self.b[self.cursor] = self.b[self.cursor] % 4 + 1
        if action == 2:
            self.b[self.cursor] = (self.b[self.cursor] + 2) % 4 + 1
        if action == 5:
            self.exact, self.near = score(self.b, self.d)
            self.hist = self.hist[6:] + self.b + [self.exact, self.near]
            self.tries += 1
            if self.exact == 4:
                self.port.win()
            elif self.tries >= 10:
                self.port.lose(LOSS)

    def state_bytes(self):
        return bytes([self.origin, self.secret, self.cursor, self.exact, self.near,
                      self.tries] + self.b + self.d + self.hist).hex()
