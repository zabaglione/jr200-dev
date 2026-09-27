# SPDX-License-Identifier: MIT
"""LOOP TEN self-test data (sdk/selftest.inc): rule fixtures and one input
script for the whole escape. The script follows upstream replay.py: in each
chamber it walks the shortest safe route to the seal (one step a tick),
lights it, and uses it again to rewind; from the second loop on the anchor
at the start jumps to the first unlit chamber. src/selftest.inc is generated
from this file by tests/make_selftest.py.
"""
from collections import deque
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'loop_ten_model_st', Path(__file__).resolve().parent / 'model.py')
_model = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_model)


def route(room, start, target, radius=1):
    """upstream replay.route(): breadth-first, around walls, gates and hazards."""
    grid = _model.CHAMBERS[room]
    queue, seen = deque([(start, [])]), {start}
    while queue:
        (x, y), path = queue.popleft()
        if abs(x - target[0]) + abs(y - target[1]) <= radius:
            return path
        for action, (dx, dy) in _model.MOVES.items():
            pos = (x + dx, y + dy)
            if not (0 <= pos[0] < 16 and 0 <= pos[1] < 10) or pos in seen:
                continue
            if grid[pos[1] * 16 + pos[0]] in (1, 4, 5):
                continue
            seen.add(pos)
            queue.append((pos, [*path, action]))
    raise AssertionError('no safe route')


def escape():
    ops = []
    for room in range(12):
        if room:
            ops.append(('act', 5))              # the anchor
        ops += [('act', a) for a in route(room, _model.START, _model.SEAL_AT)]
        ops.append(('act', 5))                  # light the seal
        if room < 11:
            ops.append(('act', 5))              # use it again: rewind
    return [(1, op) for op in ops]


LIMIT = 2000
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('step', 0, ('act', 4), {}),
    ('wall', 0, ('act', 3), {'x': 1}),
    ('gate-closed', 0, ('act', 4), {'x': 14}),
    ('gate-open', 0, ('act', 4), {'x': 14, ('flags', 0): 1}),
    ('hazard-rewinds', 0, ('act', 4), {'room': 4, 'x': 6, 'y': 6, ('flags', 0): 15}),
    ('anchor-first-unlit', 0, ('act', 5), {('flags', 0): 0x25, ('flags', 1): 2}),
    ('seal-too-far', 0, ('act', 5), {'x': 10}),
    ('seal-lights', 0, ('act', 5), {'x': 11}),
    ('seal-lit-rewinds', 0, ('act', 5), {'x': 12, 'y': 3, ('flags', 0): 1, 'loops': 3}),
    ('last-seal-wins', 0, ('act', 5), {'room': 11, 'x': 13, ('flags', 0): 255, ('flags', 1): 7}),
    ('manual-rewind', 0, ('act', 6), {'room': 3, 'x': 7, 'loops': 254}),
    ('rewind-count-stops', 0, ('act', 6), {'loops': 255}),
    ('tick-counts-down', 0, 'tick', {}),
    ('seconds-turn', 0, 'tick', {'time': 31, 'seconds': 4}),
    ('time-runs-out', 0, 'tick', {'time': 1, 'room': 2, ('flags', 0): 3}),
    ('held-waits-a-tick', 0, ('held', 2), {'since': 0}),
    ('held-repeats', 0, ('held', 2), {'since': 1}),
    ('held-into-hazard', 0, ('held', 4), {'room': 4, 'x': 6, 'y': 6, 'since': 5}),
]
SCRIPTS = [escape()]
