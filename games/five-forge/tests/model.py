# SPDX-License-Identifier: MIT
"""FIVE FORGE rules model (jr100dev games/five_forge/rules.py 1.6.1).

state_bytes() mirrors src/main.asm: cursor, stones, last, placing, pose,
winner, blink, then one byte per cell: bits 0-1 the stone (1 you, 2 rival),
bit 2 part of the completed five (upstream d).

`frames` counts the animation frames an action plays (not part of the state).
"""

LEVELS = 1
RIVAL_FIVE = 'RIVAL COMPLETED FIVE'
BOARD_FULL = 'BOARD FULL - NO FIVE'
FIELDS = ('cursor', 'stones', 'last', 'placing', 'pose', 'winner', 'blink')
WINNING_MOVES = [27, 20, 13, 34, 41]    # plan(5); re-run it if the rival changes
PLACE_FRAMES = 8 * 3 + 12
COMPLETE_FRAMES = 3 * (12 + 16) + 24


def ray(pos, direction):
    x, y = pos % 8, pos // 8
    if direction == 0:
        return pos + 1 if x < 7 else 255
    if direction == 1:
        return pos - 1 if x > 0 else 255
    if direction == 2:
        return pos + 8 if y < 7 else 255
    if direction == 3:
        return pos - 8 if y > 0 else 255
    if direction == 4:
        return pos + 9 if x < 7 and y < 7 else 255
    if direction == 5:
        return pos - 9 if x > 0 and y > 0 else 255
    if direction == 6:
        return pos + 7 if x > 0 and y < 7 else 255
    return pos - 7 if x < 7 and y > 0 else 255


def move(pos, action):
    if action == 1 and pos >= 8:
        return pos - 8
    if action == 2 and pos < 56:
        return pos + 8
    if action == 3 and pos % 8:
        return pos - 1
    if action == 4 and pos % 8 < 7:
        return pos + 1
    return pos


def count_ray(b, pos, direction, mark):
    count = 0
    p = pos
    for _ in range(7):
        p = ray(p, direction)
        if p == 255 or b[p] != mark:
            return count
        count += 1
    return count


def line(b, pos, mark):
    return max(1 + count_ray(b, pos, d * 2, mark) + count_ray(b, pos, d * 2 + 1, mark)
               for d in range(4))


def rival_choice(b):
    """Upstream's rival: the first empty cell with the best attack * 3 + defence."""
    best, chosen = 0, 255
    for i in range(64):
        if b[i] == 0:
            attack, defense = line(b, i, 2), line(b, i, 1)
            value = attack * 3 + defense
            if defense >= 5:
                value = 100
            if attack >= 5:
                value = 120
            if value > best:
                best, chosen = value, i
    return chosen


class FiveForge:
    port = None

    def __init__(self):
        self.reset()

    def reset(self):
        for name in FIELDS:
            setattr(self, name, 0)
        self.b = [0] * 64
        self.d = [0] * 64
        self.frames = 0

    def init(self):
        self.cursor = 27

    def place(self, pos, mark):
        self.b[pos] = mark
        self.stones += 1
        self.last = pos
        self.pose = (mark - 1) * 4 + 4
        self.placing = 0
        self.frames += PLACE_FRAMES

    def complete(self, pos, mark):
        if line(self.b, pos, mark) < 5:
            return False
        self.d[pos] = 1
        for axis in range(4):
            if 1 + count_ray(self.b, pos, axis * 2, mark) + \
                    count_ray(self.b, pos, axis * 2 + 1, mark) >= 5:
                for side in range(2):
                    p = pos
                    for _ in range(7):
                        p = ray(p, axis * 2 + side)
                        if p == 255 or self.b[p] != mark:
                            break
                        self.d[p] = 1
        self.winner = mark
        self.blink = 0
        self.frames += COMPLETE_FRAMES
        if mark == 1:
            self.port.win()
        else:
            self.port.lose(RIVAL_FIVE)
        return True

    def act(self, action):
        self.frames = 0
        if action < 5:
            self.cursor = move(self.cursor, action)
        if action == 5 and self.b[self.cursor] == 0:
            self.place(self.cursor, 1)
            if self.complete(self.cursor, 1):
                return
            chosen = rival_choice(self.b)
            if chosen != 255:
                self.place(chosen, 2)
                self.complete(chosen, 2)
            elif self.stones >= 64:
                self.port.lose(BOARD_FULL)

    def state_bytes(self):
        cells = [self.b[i] | self.d[i] << 2 for i in range(64)]
        return bytes([getattr(self, name) for name in FIELDS] + cells).hex()


def rival_reply(b, pos):
    """Board after your stone at pos and the rival's answer, and whether either made five."""
    b = b[:]
    b[pos] = 1
    if line(b, pos, 1) >= 5:
        return b, 1
    chosen = rival_choice(b)
    b[chosen] = 2
    return b, 2 if line(b, chosen, 2) >= 5 else 0


def plan(depth=8):
    """Your moves that make five against the rival, found by depth-first search."""
    def candidates(b):
        near = set()
        for i in range(64):
            if b[i]:
                for d in range(8):
                    p = ray(i, d)
                    if p != 255 and b[p] == 0:
                        near.add(p)
        return sorted(near) if near else [27]

    def search(b, left):
        for pos in candidates(b):
            nb, result = rival_reply(b, pos)
            if result == 1:
                return [pos]
            if result == 2 or left == 1:
                continue
            rest = search(nb, left - 1)
            if rest:
                return [pos] + rest
        return None

    for limit in range(1, depth + 1):
        found = search([0] * 64, limit)
        if found:
            return found
    return None
