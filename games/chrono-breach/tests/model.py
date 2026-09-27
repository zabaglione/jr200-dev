# SPDX-License-Identifier: MIT
"""CHRONO BREACH rules model (jr100dev games/chrono_breach/src 1.6.1).

The world step follows upstream src/turn.asm, which upstream solve.py
models as an independent search: a move (facing changes even into a wall,
which costs no time), a strike by moving onto a guard, a four-cell shot in
the facing (no time without ammo), bolts advancing in slot order (walls
remove them, the player dies, the first living guard in the cell dies),
guards firing every third action into the first free of 16 slots (the first
action already fires: the phase starts at 2), and the clear on the exit once
no guard lives. Unlike solve.py, which stops at a death, the step finishes
like the assembly does and the sector is then lost. The menu (FIRE, WAIT,
RESET, TITLE, BACK; A/D aim N/S/W/E) and the NO-first questions follow
upstream src/main.asm.

state_bytes() mirrors src/main.asm: x, y, facing, ammo, turns, phase, alive
(guards left), menu, sub (0 play, 1 menu, 2 reset question, 3 title
question), choice, guards[6 x (x, y, direction, alive)], bolts[16 x (x, y,
direction)] (direction 0 is an empty slot).
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'chrono_breach_levels', Path(__file__).resolve().parent / 'levels.py')
_levels = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_levels)

LEVELS = len(_levels.SECTORS)
DELTA = {1: (0, -1), 2: (0, 1), 3: (-1, 0), 4: (1, 0)}
KEYS = {'f': 8, 'x': 7}
LAYOUT = [('x', 1), ('y', 1), ('facing', 1), ('ammo', 1), ('turns', 1), ('phase', 1),
          ('alive', 1), ('menu', 1), ('sub', 1), ('choice', 1), ('guards', 24), ('bolts', 48)]
SIZE = sum(n for _, n in LAYOUT)
PLAY, MENU, ASK_RESET, ASK_TITLE = range(4)
BURST_FRAMES = 12                    # a guard's glow, shards and dust
DEATH_MESSAGE = 'CAUGHT IN THE CROSSFIRE'


class Sector:
    def __init__(self, entry):
        self.name, self.ammo, self.par, rows, self.route = entry
        self.walls = {(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == '#'}
        self.guards = [(x, y, '^v<>'.index(c) + 1) for y, r in enumerate(rows)
                       for x, c in enumerate(r) if c in '^v<>']
        self.start = next((x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == '@')
        self.exit = next((x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == 'X')


SECTORS = [Sector(entry) for entry in _levels.SECTORS]


class ChronoBreach:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.frames = 0

    @property
    def sector(self):
        return SECTORS[self.port.level]

    def init(self):
        """LOAD_LEVEL."""
        s = self.sector
        self.reset()
        self.x, self.y = s.start
        self.facing, self.phase, self.ammo = 4, 2, s.ammo
        self.alive = len(s.guards)
        for i, (gx, gy, direction) in enumerate(s.guards):
            self.guards[i * 4:i * 4 + 4] = [gx, gy, direction, 1]
        self.dead = False

    # ------------------------------------------------------------ helpers
    def hit_guard(self, x, y):
        for i in range(6):
            g = self.guards[i * 4:i * 4 + 4]
            if g[3] and (g[0], g[1]) == (x, y):
                self.guards[i * 4 + 3] = 0
                self.alive -= 1
                self.frames += BURST_FRAMES
                return True
        return False

    def hit_player(self, x, y):
        if (x, y) != (self.x, self.y):
            return False
        self.dead = True
        return True

    # ------------------------------------------------------------ input
    def act(self, action):
        self.frames = 0
        self.dead = False
        if self.sub == PLAY:
            if action in (5, 6):
                self.sub, self.menu = MENU, 0
            else:
                self.take_action(action)
        elif self.sub == MENU:
            if action == 6:
                self.sub = PLAY
            elif action == 1:
                self.menu = (self.menu - 1) % 5
            elif action == 2:
                self.menu = (self.menu + 1) % 5
            elif action == 3:
                self.facing = self.facing - 1 or 4
            elif action == 4:
                self.facing = self.facing % 4 + 1
            elif action == 5:
                if self.menu in (0, 1):
                    self.sub = PLAY
                    self.take_action(8 if self.menu == 0 else 7)
                elif self.menu == 4:
                    self.sub = PLAY
                else:
                    self.sub, self.choice = ASK_RESET + self.menu - 2, 0
        else:
            if action == 3:
                self.choice = 1
            elif action == 4:
                self.choice = 0
            elif action == 6 or (action == 5 and not self.choice):
                self.sub = MENU
            elif action == 5:
                if self.sub == ASK_RESET:
                    self.init()
                else:
                    self.port.mode = 0          # title

    def take_action(self, action):
        if action == 8:
            if not self.ammo:
                return
            self.ammo -= 1
            dx, dy = DELTA[self.facing]
            x, y = self.x, self.y
            for _ in range(4):
                x, y = x + dx, y + dy
                self.frames += 1
                if (x, y) in self.sector.walls or self.hit_guard(x, y):
                    break
        elif action in DELTA:
            self.facing = action
            dx, dy = DELTA[action]
            if (self.x + dx, self.y + dy) in self.sector.walls:
                return
            self.x, self.y = self.x + dx, self.y + dy
            self.frames += 2
            self.hit_guard(self.x, self.y)
            for i in range(16):
                b = self.bolts[i * 3:i * 3 + 3]
                if b[2] and (b[0], b[1]) == (self.x, self.y):
                    self.hit_player(self.x, self.y)
        elif action != 7:
            return
        self.advance()

    def advance(self):
        walls = self.sector.walls
        self.turns = min(self.turns + 1, 255)
        for i in range(16):
            bx, by, direction = self.bolts[i * 3:i * 3 + 3]
            if not direction:
                continue
            dx, dy = DELTA[direction]
            x, y = bx + dx, by + dy
            if (x, y) in walls or self.hit_player(x, y) or self.hit_guard(x, y):
                self.bolts[i * 3 + 2] = 0
            else:
                self.bolts[i * 3:i * 3 + 2] = [x, y]
        self.phase += 1
        if self.phase == 3:
            self.phase = 0
            for i in range(6):
                gx, gy, direction, alive = self.guards[i * 4:i * 4 + 4]
                if not alive:
                    continue
                dx, dy = DELTA[direction]
                x, y = gx + dx, gy + dy
                if (x, y) in walls or self.hit_player(x, y) or self.hit_guard(x, y):
                    continue
                for slot in range(16):
                    if not self.bolts[slot * 3 + 2]:
                        self.bolts[slot * 3:slot * 3 + 3] = [x, y, direction]
                        break
        if self.dead:
            self.port.lose(DEATH_MESSAGE)
        elif not self.alive and (self.x, self.y) == self.sector.exit:
            self.port.win()

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(v & 0xff for v in out).hex()
