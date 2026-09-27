# SPDX-License-Identifier: MIT
"""AUCTION HOUSE rules model (jr100dev games/auction_house/rules.py 3.0.0).

state_bytes() mirrors src/main.asm: origin, seed, market, value, low, high,
limit, bid, choice, inspected, phase, cash, goal, round, won, hammer.

origin is upstream's entropy(): an external input sampled at each market start.
The JR-200 port samples the title-song driver; the model receives it from the
recorded run, as upstream's checks do, and predicts every other byte.
"""

LOTS = [24, 22, 26, 14, 4, 18, 16, 22, 26, 8, 30, 26, 32, 22, 6, 16, 14, 20, 22, 4,
        28, 24, 30, 18, 6, 20, 18, 24, 22, 8]
LEVELS = 3
LOSS = 'THE AUCTION ENDED BELOW TARGET'
FIELDS = ('origin', 'seed', 'market', 'value', 'low', 'high', 'limit', 'bid', 'choice',
          'inspected', 'phase', 'cash', 'goal', 'round', 'won', 'hammer')


class AuctionHouse:
    port = None
    origins = []            # one sampled entropy value per market start, in order

    def __init__(self):
        self.reset()
        self.samples = list(self.origins)
        self.sounds = []

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)

    def lot(self):
        offset = self.round * 5
        self.seed = (self.seed * 109 + 89) & 255
        self.market = self.seed % 3
        self.value = LOTS[offset] + self.market
        self.low = LOTS[offset + 1]
        self.high = LOTS[offset + 2] + 2
        self.limit = LOTS[offset + 3] + self.port.level
        self.bid = LOTS[offset + 4]
        self.choice = self.inspected = self.phase = 0

    def init(self):
        level = self.port.level
        self.origin = self.samples.pop(0) if self.samples else 0
        self.seed = self.origin ^ ((level * 37) & 255)
        self.cash = 40
        self.goal = 58 + level * 2 - level // 2
        self.lot()

    def settle(self):
        self.round += 1
        if self.round == 6:
            if self.cash >= self.goal:
                self.port.win()
            else:
                self.port.lose(LOSS)
        else:
            self.lot()

    def act(self, action):
        if 1 <= action < 5:
            self.choice = (self.choice + (3 if action in (1, 3) else 1)) % 4
        if action != 5:
            return
        if self.choice == 2:
            if not self.inspected and self.cash > 1:
                self.cash -= 1
                self.inspected = 1
                self.phase = 6
                self.low = self.high = self.value
            return
        if self.choice == 3:
            self.phase = 4
            self.settle()
            return
        step = 6 if self.choice == 1 else 2
        if self.cash >= self.bid + step:
            self.bid += step
            self.phase = 1
            if self.bid >= self.limit - (4 if self.choice == 1 else 0):
                self.phase = 3
                self.hammer = 2
                self.cash = min(99, self.cash - self.bid + self.value)
                self.won += 1
                self.settle()
            else:
                self.phase = 2
                self.bid += 2
        else:
            self.phase = 5

    def state_bytes(self):
        return bytes(getattr(self, name) for name in FIELDS).hex()


def lot_plan(level, round_, seed, cash):
    """Best choice sequence for one lot: (final cash, [choices]); choices 0..3.

    Most cash first, then the fewest key presses."""
    offset = round_ * 5
    value = LOTS[offset] + seed % 3
    limit = LOTS[offset + 3] + level
    outcomes = []

    def search(bid, cash_now, inspected, path):
        outcomes.append((cash_now, path + [3]))
        if not inspected and cash_now > 1:
            search(bid, cash_now - 1, 1, path + [2])
        for choice, step in ((0, 2), (1, 6)):
            if cash_now < bid + step:
                continue
            nbid = bid + step
            if nbid >= limit - (4 if choice == 1 else 0):
                outcomes.append((min(99, cash_now - nbid + value), path + [choice]))
            else:
                search(nbid + 2, cash_now, inspected, path + [choice])

    search(LOTS[offset + 4], cash, 0, [])
    return min(outcomes, key=lambda o: (-o[0], len(o[1])))


def plan(level, origin):
    """Choice sequences for the six lots of a market, following lot_plan greedily."""
    seed = origin ^ ((level * 37) & 255)
    cash = 40
    lots = []
    for round_ in range(6):
        seed = (seed * 109 + 89) & 255
        cash, choices = lot_plan(level, round_, seed, cash)
        lots.append(choices)
    goal = 58 + level * 2 - level // 2
    return lots, cash, cash >= goal
