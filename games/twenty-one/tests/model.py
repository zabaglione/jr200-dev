# SPDX-License-Identifier: MIT
"""TWENTY ONE rules model (jr100dev games/twenty_one/rules.py 2.0.0).

state_bytes() mirrors src/main.asm: origin, seed, coins, drawn, np, nd, player,
dealer, result, choice, reveal, wager, gain, round, ready, then b[12] your
cards, c[12] the dealer's cards and d[52] the deck.

origin is upstream's entropy(), sampled when the table opens. The JR-200 port
samples the title-song driver; the model receives it from the recorded run,
as upstream's checks do, and predicts every other byte.

`frames` counts the animation frames an action plays (not part of the state).
"""

LEVELS = 1
NO_COINS = 'NO COINS LEFT AT THE TABLE'
BELOW = 'SEVEN HANDS ENDED BELOW 12'
FIELDS = ('origin', 'seed', 'coins', 'drawn', 'np', 'nd', 'player', 'dealer', 'result',
          'choice', 'reveal', 'wager', 'gain', 'round', 'ready')
DEAL_FRAMES = 5 * 3 + 8


def total(cards):
    value = aces = 0
    for card in cards:
        rank = card % 13 + 1
        value += min(10, rank)
        aces += rank == 1
    if aces and value <= 11:
        value += 10
    return value


class TwentyOne:
    port = None
    origins = []            # one sampled entropy value per table start, in order

    def __init__(self):
        self.reset()
        self.samples = list(self.origins)

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 12
        self.c = [0] * 12
        self.d = [0] * 52
        self.frames = 0

    def shuffle(self):
        self.d = list(range(52))
        for i in range(51):
            self.seed = (self.seed * 109 + 89) & 255
            j = self.seed % (52 - i)
            self.d[51 - i], self.d[j] = self.d[j], self.d[51 - i]
        self.drawn = 0

    def deal(self, who):
        if self.drawn == 52:
            self.shuffle()
        value = self.d[self.drawn]
        self.drawn += 1
        if who == 0:
            self.b[self.np] = value
            self.np += 1
            self.player = total(self.b[:self.np])
        else:
            self.c[self.nd] = value
            self.nd += 1
            self.dealer = total(self.c[:self.nd])
        if self.ready:
            self.frames += DEAL_FRAMES

    def hand(self):
        self.np = self.nd = self.player = self.dealer = 0
        self.result = self.choice = self.reveal = 0
        self.wager = 2
        for who in (0, 1, 0, 1):
            self.deal(who)

    def init(self):
        self.origin = self.samples.pop(0) if self.samples else 0
        self.seed = self.origin
        self.coins = 10
        self.shuffle()
        self.hand()
        self.ready = 1

    def finish(self):
        self.reveal = 1
        natural = self.player == 21 and self.np == 2
        dealer_natural = self.dealer == 21 and self.nd == 2
        if self.player <= 21 and (self.dealer > 21 or self.player > self.dealer
                                  or natural and not dealer_natural):
            self.gain = 3 if natural else self.wager
            self.coins += self.gain
            self.result = 1
        elif self.player > 21 or self.player < self.dealer or dealer_natural and not natural:
            self.coins -= self.wager
            self.result = 2 if self.player > 21 else 3
        else:
            self.result = 4
        self.frames += 42
        self.round += 1
        if self.coins < 2:
            self.port.lose(NO_COINS)
        elif self.round == 7:
            if self.coins >= 12:
                self.port.win()
            else:
                self.port.lose(BELOW)
        else:
            self.hand()

    def stand(self):
        self.reveal = 1
        self.choice = 3
        self.frames += 12
        for _ in range(9):
            if self.dealer < 17:
                self.deal(1)
        self.finish()

    def act(self, action):
        self.frames = 0
        if action < 5:
            self.choice = (self.choice + (2 if action in (1, 3) else 1)) % 3
        if action == 5:
            if self.choice == 0:
                self.deal(0)
                if self.player > 21:
                    self.finish()
            elif self.choice == 1:
                self.stand()
            elif self.np == 2 and self.coins >= 4:
                self.wager = 4
                self.deal(0)
                if self.player > 21:
                    self.finish()
                else:
                    self.stand()

    def state_bytes(self):
        return bytes([getattr(self, n) for n in FIELDS] + self.b + self.c + self.d).hex()


def plan(origin, goal=12):
    """Choices (0 hit, 1 stand, 2 double) that end seven hands with `goal` coins."""
    import copy
    from port_model import PortModel
    TwentyOne.origins = [origin]
    port = PortModel(TwentyOne(), LEVELS)
    port.new_level()

    def search(p, path):
        if p.mode == 2:
            return path
        if p.mode != 1:
            return None
        g = p.game
        options = [1, 0] + ([2] if g.np == 2 and g.coins >= 4 else [])
        for choice in options:
            q = copy.deepcopy(p)
            q.game.choice = choice
            q.game.act(5)
            found = search(q, path + [choice])
            if found:
                return found
        return None

    return search(port, [])
