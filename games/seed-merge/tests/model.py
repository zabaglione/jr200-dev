# SPDX-License-Identifier: MIT
"""Independent state model for the JR100dev SEED MERGE 1.5.1 rules.

The 16 board bytes store exponents: 1 is a seed worth 2, 6 is 64.
State layout mirrors the first 19 bytes of the JR-200 port's GAME_STATE.
"""

LOSS = 'NO MORE MOVES'


def line_positions(line, action):
    if action == 1:  # up
        return [offset * 4 + line for offset in range(4)]
    if action == 2:  # down
        return [(3 - offset) * 4 + line for offset in range(4)]
    if action == 3:  # left
        return [line * 4 + offset for offset in range(4)]
    if action == 4:  # right
        return [line * 4 + 3 - offset for offset in range(4)]
    raise ValueError(action)


def can_move(board):
    if 0 in board:
        return True
    return any(
        board[i] == board[i + delta]
        for i in range(16)
        for delta in (1, 4)
        if (delta == 1 and i % 4 < 3) or (delta == 4 and i < 12)
    )


class SeedMerge:
    def __init__(self):
        self.port = None
        self.reset()

    def reset(self):
        self.board = [0] * 16
        self.seed = self.best = self.moves = 0

    def spawn(self):
        self.seed = (self.seed * 5 + 1) & 255
        for offset in range(16):
            pos = (self.seed + offset) % 16
            if self.board[pos] == 0:
                self.board[pos] = 1
                return pos
        return None

    def init(self):
        self.seed = 7
        self.spawn()
        self.spawn()
        self.best = 1

    def settle(self, action):
        changed = False
        for _ in range(3):
            for line in range(4):
                positions = line_positions(line, action)
                for p, n in zip(positions, positions[1:]):
                    if self.board[p] == 0 and self.board[n] != 0:
                        self.board[p], self.board[n] = self.board[n], 0
                        changed = True
        return changed

    def act(self, action):
        if not 1 <= action <= 4:
            return
        changed = self.settle(action)
        for line in range(4):
            positions = line_positions(line, action)
            for p, n in zip(positions, positions[1:]):
                if self.board[p] != 0 and self.board[p] == self.board[n]:
                    self.board[p] += 1
                    self.board[n] = 0
                    self.best = max(self.best, self.board[p])
                    changed = True
        changed |= self.settle(action)
        if changed:
            self.spawn()
            self.moves = (self.moves + 1) & 255
        if self.best >= 6:
            self.port.win()
        elif not can_move(self.board):
            self.port.lose(LOSS)

    def state_bytes(self):
        return bytes(self.board + [self.seed, self.best, self.moves]).hex()
