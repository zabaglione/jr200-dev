# SPDX-License-Identifier: MIT
"""LUMEN CROSS rules model (jr100dev games/lumen_cross/rules.py 2.0.0).

The model mirrors the RAM layout of src/main.asm for the observed bytes:
b[25], cursor, moves, flash, pose, ready.
"""

PARS = [4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9]
LEVELS = 18
LIMIT = 60
LOSS = 'SIXTY SWITCHES WERE NOT ENOUGH'


def cross_cells(pos):
    cells = [pos]
    if pos >= 5:
        cells.append(pos - 5)
    if pos < 20:
        cells.append(pos + 5)
    if pos % 5 > 0:
        cells.append(pos - 1)
    if pos % 5 < 4:
        cells.append(pos + 1)
    return cells


def stage_presses(level):
    return [(level * 7 + i * 11 + 3) % 25 for i in range(4 + level // 3)]


def stage_board(level):
    board = [0] * 25
    for pos in stage_presses(level):
        for cell in cross_cells(pos):
            board[cell] ^= 1
    return board


def solutions(board):
    """All press sets that clear the board (light chasing over the first row)."""
    found = []
    for first in range(32):
        work = board[:]
        presses = [0] * 25
        for column in range(5):
            if first >> column & 1:
                presses[column] = 1
                for cell in cross_cells(column):
                    work[cell] ^= 1
        for row in range(1, 5):
            for column in range(5):
                if work[(row - 1) * 5 + column]:
                    pos = row * 5 + column
                    presses[pos] = 1
                    for cell in cross_cells(pos):
                        work[cell] ^= 1
        if not any(work):
            found.append([pos for pos in range(25) if presses[pos]])
    return found


class LumenCross:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.board = [0] * 25
        self.cursor = self.moves = self.flash = self.pose = self.ready = 0

    def toggle(self, pos):
        self.board[pos] ^= 1
        if self.ready:
            # Five poses; the last one stays in RAM after the effect.
            self.pose = 5 if self.board[pos] else 1

    def cross(self, pos):
        for cell in cross_cells(pos):
            self.toggle(cell)

    def init(self):
        for pos in stage_presses(self.port.level):
            self.cross(pos)
        self.ready = 1

    def act(self, action):
        if action == 1 and self.cursor >= 5:
            self.cursor -= 5
        if action == 2 and self.cursor < 20:
            self.cursor += 5
        if action == 3 and self.cursor % 5 > 0:
            self.cursor -= 1
        if action == 4 and self.cursor % 5 < 4:
            self.cursor += 1
        if action == 5:
            self.cross(self.cursor)
            self.moves = (self.moves + 1) & 0xff
            if not any(self.board):
                self.port.win()
            elif self.moves >= LIMIT:
                self.port.lose(LOSS)

    def state_bytes(self):
        return bytes(self.board + [self.cursor, self.moves, self.flash, self.pose,
                                   self.ready]).hex()


def route(start, target):
    """W/A/S/D keys that move the cursor from start to target."""
    keys = []
    row, column = divmod(start, 5)
    target_row, target_column = divmod(target, 5)
    keys += ['s'] * max(0, target_row - row) + ['w'] * max(0, row - target_row)
    keys += ['d'] * max(0, target_column - column) + ['a'] * max(0, column - target_column)
    return keys


def solve_keys(level, cursor=0):
    """Minimal-press solution as key names, visiting cells in index order."""
    best = min(solutions(stage_board(level)), key=len)
    keys = []
    for pos in best:
        keys += route(cursor, pos) + ['ret']
        cursor = pos
    return keys, cursor


def route_step(cursor, key):
    row, column = divmod(cursor, 5)
    if key == 'w' and row > 0:
        return cursor - 5
    if key == 's' and row < 4:
        return cursor + 5
    if key == 'a' and column > 0:
        return cursor - 1
    if key == 'd' and column < 4:
        return cursor + 1
    return cursor
