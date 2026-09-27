# SPDX-License-Identifier: MIT
"""TRACE BLADE rules model (jr100dev games/trace_blade/src/main.asm 1.6.1).

Upstream has no Python rules module; this model follows the upstream M6800
source (PLAN_INPUT, ADD_STEP, UNDO, MENU_INPUT, EXECUTE, EXEC_TICK,
RESET_PATH) and its check_rules.py / replay.py.

state_bytes() mirrors src/main.asm: x, y, path_len, targets, marked, combo,
menu, sub (0 plan, 1 menu, 2 cut, 3 reset question, 4 title question),
choice, error, then map[108] (0 floor, 1 wall, 2 target, 3 exit),
visited[108] and path[108] (cell = y * 12 + x; path[0] is the start 13).

`frames` counts the animation frames an action plays (not part of the state).
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'trace_blade_levels', Path(__file__).resolve().parent / 'levels.py')
_levels = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_levels)

LEVELS = len(_levels.LEVELS)
ROOMS = [[' .#*X'.index(c) - 1 for c in room[1]] for room in _levels.LEVELS]
SOLUTIONS = [['WSAD'.index(c) + 1 for c in room[2]] for room in _levels.LEVELS]
NAMES = [room[0] for room in _levels.LEVELS]
START = 13
STEP_FRAMES = 5         # upstream EXEC_TICK advances every 5 ticks
CUT_FRAMES = 12         # a target's burst
KEYS = {'f': 8}
MOVES = {1: -12, 2: 12, 3: -1, 4: 1}
LAYOUT = [('x', 1), ('y', 1), ('path_len', 1), ('targets', 1), ('marked', 1),
          ('combo', 1), ('menu', 1), ('sub', 1), ('choice', 1), ('error', 1),
          ('map', 108), ('visited', 108), ('path', 108)]
SIZE = sum(n for _, n in LAYOUT)
TEST_SIZE = 118         # the self test stores the scalars and the map
PLAN, MENU, CUT, ASK_RESET, ASK_TITLE = range(5)


class TraceBlade:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.frames = 0

    def init(self):
        self.map = list(ROOMS[self.port.level])
        self.targets = self.map.count(2)
        self.reset_path()

    def reset_path(self):
        self.visited = [0] * 108
        self.x = self.y = 1
        self.visited[START] = 1
        self.path[0] = START
        self.sub = PLAN
        self.path_len = self.marked = self.combo = self.error = 0

    def invalid(self):
        self.error = 1

    def act(self, action):
        self.frames = 0
        if self.sub == PLAN:
            if action == 5:
                self.sub, self.menu = MENU, 0
            elif action == 6:
                self.undo()
            elif action == 8:
                self.execute()
            elif action in MOVES:
                self.step(action)
        elif self.sub == MENU:
            if action == 1:
                self.menu = (self.menu - 1) % 5
            elif action == 2:
                self.menu = (self.menu + 1) % 5
            elif action == 6:
                self.sub = PLAN
            elif action == 5:
                if self.menu == 0:
                    self.execute()
                elif self.menu == 1:
                    self.undo()
                elif self.menu == 2:
                    self.sub, self.choice = ASK_RESET, 0
                elif self.menu == 3:
                    self.sub, self.choice = ASK_TITLE, 0
                else:
                    self.sub = PLAN
        elif self.sub in (ASK_RESET, ASK_TITLE):
            if action == 3:
                self.choice = 1
            elif action == 4:
                self.choice = 0
            elif action == 6 or (action == 5 and not self.choice):
                self.sub = MENU
            elif action == 5:
                if self.sub == ASK_RESET:
                    self.reset_path()
                else:
                    self.port.mode = 0      # title

    def step(self, action):
        cell = self.y * 12 + self.x + MOVES[action]
        if self.map[cell] == 1 or self.visited[cell]:
            self.invalid()
            return
        self.visited[cell] = 1
        self.path_len += 1
        self.path[self.path_len] = cell
        if self.map[cell] == 2:
            self.marked += 1
        self.y, self.x = divmod(cell, 12)
        self.error = 0

    def undo(self):
        if not self.path_len:
            self.invalid()
            return
        cell = self.path[self.path_len]
        self.visited[cell] = 0
        if self.map[cell] == 2:
            self.marked -= 1
        self.path_len -= 1
        self.y, self.x = divmod(self.path[self.path_len], 12)
        self.sub = PLAN
        self.error = 0

    def execute(self):
        if self.marked != self.targets or self.map[self.y * 12 + self.x] != 3:
            self.invalid()
            return
        self.sub, self.combo = CUT, 0
        for position in range(1, self.path_len + 1):
            cell = self.path[position]
            self.y, self.x = divmod(cell, 12)
            self.frames += STEP_FRAMES
            if self.map[cell] == 2:
                self.map[cell] = 0
                self.combo += 1
                self.frames += CUT_FRAMES
        self.port.win()

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(v & 0xff for v in out).hex()
