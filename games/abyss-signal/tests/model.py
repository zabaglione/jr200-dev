# SPDX-License-Identifier: MIT
"""ABYSS SIGNAL rules model (jr100dev games/abyss_signal/model.py 1.6.1).

advance() is the upstream turn rule (action 1-4 move, 7 wait, 8 sonar,
9 record, 10 quiet toggle). AbyssSignal wraps it with the upstream screens
of src/main.asm: the control panel (SONAR PING, RECORD SITE, QUIET MODE,
WAIT, RESTART, TITLE; W/S wrap, RETURN picks, SPACE closes), the discovery
photo after a record (RETURN or SPACE returns), the NO-first RESTART and
TITLE questions, and STATUS (no site in range), which upstream keeps
outside its Python model.

state_bytes() mirrors src/main.asm: x, y, oxygen, hull, flags, sight,
noise, quiet, turn, hx, hy, grace, samples, sub (0 sea, 1 panel,
2 photo, 3 restart question, 4 title question), menu, choice, photo, status.
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'abyss_signal_world', Path(__file__).resolve().parent / 'world.py')
world = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(world)

LEVELS = 1
GRID = [[int(c, 16) for c in row] for row in world.MAP]
SITES = [(x, y) for _, x, y in world.SITES]
DIR = {1: (0, -1), 2: (0, 1), 3: (-1, 0), 4: (1, 0)}
CURRENTS = {2: 4, 3: 2, 4: 3, 5: 1}
KEYS = {'f': 8, 'x': 7}
LAYOUT = [('x', 1), ('y', 1), ('oxygen', 1), ('hull', 1), ('flags', 1), ('sight', 1),
          ('noise', 1), ('quiet', 1), ('turn', 1), ('hx', 1), ('hy', 1), ('grace', 1),
          ('samples', 1), ('sub', 1), ('menu', 1), ('choice', 1), ('photo', 1), ('status', 1)]
SIZE = len(LAYOUT)
SEA, PANEL, PHOTO, ASK_RESTART, ASK_TITLE = range(5)
PANEL_ACTIONS = {0: 8, 1: 9, 2: 10, 3: 7}


def advance(s, action):
    """Upstream model.advance() on this object; returns the upstream mode (1, 3, 4, 5)."""
    if action == 10:
        s.quiet ^= 1
        return 1
    if action == 9:
        site = next((i for i, (x, y) in enumerate(SITES)
                     if not (s.flags >> i & 1) and abs(s.x - x) + abs(s.y - y) <= 1), None)
        if site is None:
            return 1
        s.flags |= 1 << site
        s.oxygen = max(0, s.oxygen - 2)
    elif action == 8:
        s.oxygen = max(0, s.oxygen - 2)
        s.sight = 7
        s.noise = 9
    else:
        s.oxygen = max(0, s.oxygen - 1 - s.quiet)
        if action in DIR:
            dx, dy = DIR[action]
            nx, ny = s.x + dx, s.y + dy
            if GRID[ny][nx] == 1:
                s.hull = max(0, s.hull - 1)
            else:
                s.x, s.y = nx, ny
    s.turn = (s.turn + 1) % 256
    s.sight = max(0, s.sight - 1)
    s.noise = max(0, s.noise - 1)
    s.grace = max(0, s.grace - 1)
    tile = GRID[s.y][s.x]
    if tile in CURRENTS:
        dx, dy = DIR[CURRENTS[tile]]
        nx, ny = s.x + dx, s.y + dy
        if GRID[ny][nx] != 1:
            s.x, s.y = nx, ny
            s.oxygen = max(0, s.oxygen - 1)
    if s.turn % (4 if s.quiet else 2) == 0:
        target = ((s.x, s.y) if abs(s.x - s.hx) + abs(s.y - s.hy) <= 6 or s.noise
                  else ((22, 20) if s.turn & 16 else (18, 14)))
        tx, ty = target
        nx = s.hx + (tx > s.hx) - (tx < s.hx)
        if nx != s.hx and GRID[s.hy][nx] != 1:
            s.hx = nx
        else:
            ny = s.hy + (ty > s.hy) - (ty < s.hy)
            if GRID[ny][s.hx] != 1:
                s.hy = ny
    if abs(s.x - s.hx) + abs(s.y - s.hy) <= 1 and not s.grace:
        s.hull = max(0, s.hull - 1)
        s.grace = 4
    if not s.hull or not s.oxygen:
        return 4
    if s.flags == 31 and (s.x, s.y) == world.BASE:
        return 5
    if action == 9:
        return 3
    return 1


class AbyssSignal:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, _ in LAYOUT:
            setattr(self, name, 0)

    def init(self):
        self.reset()
        self.x, self.y = world.BASE
        self.oxygen, self.hull = world.OXYGEN, world.HULL
        self.hx, self.hy = world.HUNTER

    def turn_action(self, action):
        """One upstream action from the sea (keys) or the panel."""
        self.sub = SEA
        if action in (1, 2, 3, 4, 7):
            self.status = 0                     # NAVIGATE clears it
        if action == 9:
            site = next((i for i, (x, y) in enumerate(SITES)
                         if not (self.flags >> i & 1)
                         and abs(self.x - x) + abs(self.y - y) <= 1), None)
            if site is None:
                self.status = 1
                return
            self.photo = site
            self.samples += 1
        mode = advance(self, action)
        if mode == 4:
            self.port.lose('CONNECTION LOST')
        elif mode == 5:
            self.port.win()
        elif mode == 3:
            self.sub = PHOTO

    def act(self, action):
        if self.sub == SEA:
            if action in (5, 6):
                self.sub, self.menu = PANEL, 0
            elif action in (1, 2, 3, 4, 7, 8, 9, 10):
                self.turn_action(action)
        elif self.sub == PANEL:
            if action == 1:
                self.menu = (self.menu - 1) % 6
            elif action == 2:
                self.menu = (self.menu + 1) % 6
            elif action == 6:
                self.sub = SEA
            elif action == 5:
                if self.menu in PANEL_ACTIONS:
                    self.turn_action(PANEL_ACTIONS[self.menu])
                else:
                    self.sub, self.choice = ASK_RESTART + self.menu - 4, 0
        elif self.sub == PHOTO:
            if action in (5, 6):
                self.sub = SEA
        else:
            if action == 3:
                self.choice = 1
            elif action == 4:
                self.choice = 0
            elif action == 6 or (action == 5 and not self.choice):
                self.sub = PANEL
            elif action == 5:
                if self.sub == ASK_RESTART:
                    self.init()
                else:
                    self.port.mode = 0          # title

    def state_bytes(self):
        return bytes(getattr(self, name) & 0xff for name, _ in LAYOUT).hex()
