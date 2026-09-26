# SPDX-License-Identifier: BSD-3-Clause
"""Machine-independent model of sdk/ranked.inc (JR100dev ranked campaigns).

Upstream: games/native/campaign_runtime.asm, password.asm and password.py of
zabaglione/jr100dev. Modes: 0 title, 1 play, 2 clear, 4 all clear, 5 help,
6 stage map, 7 password. BEST (one rating 0-3 per stage) survives retries,
the title and the map; it is cleared only when the program starts.

Game models implement init(), act(action) and state_bytes() and keep the
ranked fields moves, overflow, runes and stars; they call port.rank_clear()
like upstream's ranked_clear(). Keys are raw codes: in password entry the
letters type (case-insensitive), '-' or BACKSPACE erases, RETURN loads and X
cancels; everywhere else the usual actions apply, with X (7) and F (8).
"""
from __future__ import annotations

ALPHABET = 'ACDEFGHJKMNPQRTW'
TITLE, PLAY, CLEAR, END, HELP, MAP, PASSWORD = 0, 1, 2, 4, 5, 6, 7
EXIT_KEYS = (0x1b, 0x03)
ACTIONS = {ord('w'): 1, ord('s'): 2, ord('a'): 3, ord('d'): 4, 0x0d: 5, 0x20: 6,
           ord('x'): 7, ord('f'): 8}


def crc(values, tag):
    result = tag
    for value in values:
        result ^= value << 4
        for _ in range(4):
            result = ((result << 1) ^ (7 if result & 128 else 0)) & 255
    return result


def encode(level, ratings, tag):
    """Upstream password.encode(): the level and forty two-bit ratings."""
    pairs = [ratings[i] * 4 + ratings[i + 1] for i in range(0, len(ratings), 2)]
    prefix = 0
    while prefix < len(pairs) and pairs[prefix] == 15:
        prefix += 1
    end = len(pairs)
    while end > prefix and pairs[end - 1] == 0:
        end -= 1
    header = level | (128 + (64 if prefix >= 16 else 0) if prefix else 0)
    values = [header >> 4, header & 15]
    if prefix:
        values.append(prefix & 15)
    values += pairs[prefix:end]
    check = crc(values, tag)
    values += [check >> 4, check & 15]
    return values


def decode(values, tag, stages):
    """Upstream P_RESTORE: (level, ratings) or None for a rejected code."""
    if len(values) < 4 or crc(values, tag):
        return None
    header = values[0] * 16 + values[1]
    if header & 63 >= stages:
        return None
    pos, prefix = 2, 0
    if header & 128:
        if len(values) < 5:
            return None
        prefix = values[2] | (16 if header & 64 else 0)
        if not 1 <= prefix <= stages // 2:
            return None
        pos = 3
    elif header & 64:
        return None
    body = values[pos:-2]
    if prefix + len(body) > stages // 2:
        return None
    ratings = [3] * (prefix * 2)
    for value in body:
        ratings += [value >> 2, value & 3]
    return header & 63, ratings + [0] * (stages - len(ratings))


def letters(values):
    return ''.join(ALPHABET[v] for v in values)


class RankedPortModel:
    def __init__(self, game, levels: int, tag: int):
        self.game = game
        self.levels = levels
        self.tag = tag
        self.mode = TITLE
        self.level = 0
        self.best = [0] * levels
        self.confirm = None
        self.confirm_then = None
        self.exited = False
        self.buffer: list[int] = []
        self.error = 0
        self.back = TITLE
        game.port = self

    # upstream ranked_clear(): stars from moves, par and runes, then win()
    def rank_clear(self) -> None:
        g = self.game
        g.stars = 1
        if g.moves <= g.par and not g.overflow:
            g.stars = 3 if g.runes == 3 else 2
        self.best[self.level] = max(self.best[self.level], g.stars)
        self.mode = CLEAR

    def new_level(self) -> None:
        self.mode = PLAY
        self.game.reset()
        self.game.init()

    def code(self) -> str:
        return letters(encode(self.level, self.best, self.tag))

    def key(self, code: int) -> None:
        if self.exited:
            return
        if code in EXIT_KEYS:
            self.exited = True
            return
        if self.confirm is not None:
            action = ACTIONS.get(code | 0x20 if 0x41 <= code <= 0x5a else code, 0)
            if action == 6:
                self.confirm = None
            elif action == 5:
                choice, self.confirm = self.confirm, None
                if choice:
                    self.confirm_then()
            elif action:
                self.confirm = (action - 1) & 1
            return
        if self.mode == PASSWORD:
            self.password_key(code)
            return
        low = code | 0x20 if 0x41 <= code <= 0x5a else code
        action = ACTIONS.get(low, 0)
        if action == 0:
            return
        if self.mode == HELP:
            self.mode = TITLE
        elif self.mode == MAP:
            self.map_key(action)
        elif action == 8:
            if self.mode == PLAY:
                self.ask(self.open_map)
            else:
                self.open_map()
        elif self.mode == TITLE:
            if action == 7:
                self.open_password()
            elif action == 5:
                self.new_level()
            else:
                self.mode = HELP
        elif action == 6:
            self.ask(self.new_level)
        elif self.mode == PLAY:
            self.game.act(action)
        elif action == 5:
            if self.mode == CLEAR:
                if self.level + 1 < self.levels:
                    self.level += 1
                    self.new_level()
                else:
                    self.mode = END
            else:
                self.mode = TITLE

    def ask(self, then) -> None:
        self.confirm = 0
        self.confirm_then = then

    def open_map(self) -> None:
        self.mode = MAP

    def map_key(self, action: int) -> None:
        n = self.levels
        if action == 7:
            self.open_password()
        elif action == 5:
            self.new_level()
        elif action == 6:
            self.mode = TITLE
        elif action in (1, 2, 3, 4):
            self.level = (self.level + {1: -5, 2: 5, 3: -1, 4: 1}[action]) % n

    def open_password(self) -> None:
        self.back = self.mode
        self.mode = PASSWORD
        self.buffer = []
        self.error = 0

    def password_key(self, code: int) -> None:
        upper = code & 0xdf if 0x61 <= code <= 0x7a else code
        if code == 0x0d:
            restored = decode(self.buffer, self.tag, self.levels)
            if restored is None:
                self.error = 1
            else:
                self.level, self.best = restored
                self.mode = MAP
        elif code in (0x08, ord('-')):
            if self.buffer:
                self.buffer.pop()
            self.error = 0
        elif upper == ord('X'):
            self.mode = MAP if self.back == MAP else TITLE
        elif chr(upper) in ALPHABET:
            if len(self.buffer) >= 24:
                self.error = 1
            else:
                self.buffer.append(ALPHABET.index(chr(upper)))
                self.error = 0

    def run(self, replay: list[dict]) -> 'RankedPortModel':
        for event in replay:
            if event['kind'] == 'key' and event['pressed']:
                self.key(int(event['code'], 16) if isinstance(event['code'], str)
                         else event['code'])
        return self
