# SPDX-License-Identifier: MIT
"""ORBIT DRAFT rules model (jr100dev games/orbit_draft/rules.py 3.0.1).

state_bytes() mirrors the kept state in src/main.asm: level, origin, rng_lo,
rng_hi, spins, target, progress, lines, falling, slide, points, score_lo,
score_hi, chain, glow, notice, tool, phase, cursor, cell, offer, card, flying,
fx, fy, axis, orbit, rotating, then b[16] (255 empty), c[16] and d[21].

Upstream is endless: after a clear, RETURN calls advance() and keeps the board
and score; a loss or a restart calls init(), which starts over at level 0.
origin is upstream's entropy(), sampled by init(); the JR-200 port samples the
title-song driver and the model receives it from the recorded run.

`frames` counts the animation frames an action plays (not part of the state).
"""

LEVELS = 255
LOSS = 'FULL BOARD - NO SPINS'
EMPTY = 255
PATHS = [0, 1, 2, 1, 2, 3, 4, 5, 6, 5, 6, 7, 8, 9, 10, 9, 10, 11, 12, 13, 14, 13, 14, 15,
         0, 4, 8, 1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12, 5, 9, 13, 6, 10, 14, 7, 11, 15,
         0, 5, 10, 1, 6, 11, 4, 9, 14, 5, 10, 15, 2, 5, 8, 3, 6, 9, 6, 9, 12, 7, 10, 13]
FIELDS = ('level', 'origin', 'rng_lo', 'rng_hi', 'spins', 'target', 'progress', 'lines',
          'falling', 'slide', 'points', 'score_lo', 'score_hi', 'chain', 'glow', 'notice',
          'tool', 'phase', 'cursor', 'cell', 'offer', 'card', 'flying', 'fx', 'fy', 'axis',
          'orbit', 'rotating')


def move(pos, action):
    if action == 1 and pos >= 4:
        return pos - 4
    if action == 2 and pos < 16:
        return pos + 4
    if action == 3 and pos % 4:
        return pos - 1
    if action == 4 and pos % 4 < 3:
        return pos + 1
    return pos


class OrbitDraft:
    port = None
    origins = []            # one sampled entropy value per init(), in order

    def __init__(self):
        self.clear()
        self.samples = list(self.origins)
        self.frames = 0

    def clear(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 16
        self.c = [0] * 16
        self.d = [0] * 21

    def reset(self):
        """The port clears only its own work area; the upstream state is kept."""

    # --- upstream rules -------------------------------------------------
    def deal(self):
        for _ in range(4):
            low = self.rng_lo & 1
            self.rng_lo = (self.rng_lo >> 1) | ((self.rng_hi & 1) << 7)
            self.rng_hi >>= 1
            if low:
                self.rng_hi ^= 180
        return (self.rng_lo ^ self.rng_hi) % 5

    def init(self):
        if self.port.level == (self.level + 1) & 255 and self.port.level:
            self.advance()
            return
        self.clear()
        self.port.level = 0
        self.origin = self.samples.pop(0) if self.samples else 0
        self.rng_lo = self.origin | 1
        self.rng_hi = self.origin ^ 165
        self.spins = 2
        self.target = 12
        self.b = [EMPTY] * 16
        first = self.deal()
        for i in range(4):
            self.b[12 + i] = (first + i) % 5
        for i in range(5):
            self.d[16 + i] = self.deal()
        self.d[16] = (first + 4) % 5
        self.d[17] = (first + self.d[17] % 4) % 5
        self.card = self.d[16]

    def advance(self):
        self.level = min(self.level + 1, 254)
        self.target = min(self.target + 6, 60)
        self.progress = 0

    def evaluate(self):
        self.lines = 0
        self.c = [0] * 16
        for i in range(24):
            a, m, e = PATHS[i * 3:i * 3 + 3]
            if self.b[a] != EMPTY and self.b[a] == self.b[m] == self.b[e]:
                self.lines += 1
                self.c[a] = self.c[m] = self.c[e] = 1

    def settle(self):
        for _ in range(3):
            changed = 0
            for i in range(16):
                self.d[i] = 0
            for i in range(12):
                source = 11 - i
                if self.b[source] != EMPTY and self.b[source + 4] == EMPTY:
                    self.d[source] = 1
                    changed = 1
            if not changed:
                return
            self.slide = 4
            self.frames += 9
            for i in range(12):
                source = 11 - i
                if self.d[source]:
                    self.b[source + 4] = self.b[source]
                    self.b[source] = EMPTY
            self.falling = 0

    def credit(self):
        self.progress = min((self.progress + self.points) & 255, 99)
        self.score_lo = (self.score_lo + self.points) & 255
        if self.score_lo >= 100:
            if self.score_hi == 99:
                self.score_lo = 99
            else:
                self.score_lo -= 100
                self.score_hi += 1

    def resolve(self):
        self.chain = self.points = 0
        for _ in range(5):
            self.evaluate()
            if not self.lines:
                self.settle()
                self.evaluate()
            if not self.lines:
                return
            self.chain += 1
            self.frames += 15
            count = 0
            for i in range(16):
                if self.c[i]:
                    self.b[i] = EMPTY
                    count += 1
                self.c[i] = 0
            self.glow = 0
            self.points = (count * 2 * self.chain + (self.lines - 1) * 2) & 255
            self.credit()
            self.spins = min(self.spins + 1, 4)
            self.frames += 10
            self.settle()

    def finish(self):
        if self.progress >= self.target:
            self.port.win()
        elif EMPTY not in self.b:
            if not self.spins:
                self.port.lose(LOSS)
            else:
                if not self.tool:
                    self.phase = 1
                    self.cursor = 17
                self.notice = 2

    def place(self):
        target = EMPTY
        for row in range(4):
            pos = row * 4 + self.cursor % 4
            if self.b[pos] == EMPTY:
                target = pos
        if target == EMPTY:
            self.notice = 3
            return
        self.fx = 2 + target % 4 * 5
        self.fy = 3 + (4 + target // 4 * 4 - 3) * 4 // 4
        self.flying = 0
        self.frames += 15
        self.b[target] = self.card
        self.resolve()
        self.d[16 + self.offer] = self.d[18]
        self.d[18], self.d[19] = self.d[19], self.d[20]
        self.d[20] = self.deal()
        self.card = self.d[16 + self.offer]
        self.phase = 0
        self.finish()

    def rotate(self):
        if not self.spins:
            self.notice = 1
            return
        self.axis = self.tool - 1
        self.orbit = self.cursor // 4 if not self.axis else self.cursor % 4
        first = self.orbit * 4 if not self.axis else self.orbit
        stride = 1 if not self.axis else 4
        if all(self.b[first + i * stride] == self.b[first] for i in range(4)):
            self.notice = 4
            return
        self.slide = 3 * (5 if not self.axis else 4) // 3
        self.frames += 16
        last = first + 3 * stride
        saved = self.b[last]
        for i in range(3):
            self.b[last - i * stride] = self.b[last - (i + 1) * stride]
        self.b[first] = saved
        self.rotating = 0
        self.spins -= 1
        self.resolve()
        self.finish()

    def act(self, action):
        self.frames = 0
        self.notice = 0
        if not self.phase:
            if action in (3, 4):
                self.offer = 1 - self.offer
                self.card = self.d[16 + self.offer]
            if action == 5:
                self.phase = 1
                self.cursor = self.cell
            if action == 2:
                self.phase = 1
                self.cursor = 16
            return
        if action < 5:
            self.cursor = min(move(self.cursor, action), 18)
            if self.cursor < 16:
                self.cell = self.cursor
        if action == 5:
            if self.cursor >= 16:
                self.tool = self.cursor - 16
                self.cursor = self.cell
                if not self.tool:
                    self.phase = 0
            elif not self.tool:
                self.place()
            else:
                self.rotate()

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.c + self.d).hex()
