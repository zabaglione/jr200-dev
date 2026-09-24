# SPDX-License-Identifier: MIT
"""Single-tick rule fixtures for the BRICK PULSE self-test.

Each fixture starts an arena (level index), overrides state fields or bricks,
sets the held direction and runs one tick. The same list drives the Python
model (tests) and src/fixtures.inc (built by make_fixtures.py).
"""

FIXTURES = [
    # name, level, held, {field: value}, {brick index: hits}
    ('catch-wide', 0, 0, {'item': 1, 'ix': 14, 'iy': 16, 'clock': 1}, {}),
    ('catch-slow', 0, 0, {'item': 2, 'ix': 14, 'iy': 16, 'clock': 1}, {}),
    ('catch-guard', 0, 0, {'item': 3, 'ix': 14, 'iy': 16, 'clock': 1}, {}),
    ('miss-item', 0, 0, {'item': 1, 'ix': 2, 'iy': 16, 'clock': 1}, {}),
    ('wide-expires', 0, 0, {'wide': 1, 'width': 10}, {}),
    ('slow-skips-odd', 0, 0, {'slow': 5, 'clock': 0}, {}),
    ('slow-moves-even', 0, 0, {'slow': 5, 'clock': 1}, {}),
    ('guard-saves', 0, 0, {'guard': 1, 'x': 1, 'y': 15, 'dy': 1}, {}),
    ('bomb-jams', 0, 0, {'bomb': 16, 'bx': 14, 'clock': 1}, {}),
    ('bomb-guarded', 0, 0, {'guard': 1, 'bomb': 16, 'bx': 14, 'clock': 1}, {}),
    ('bomb-misses', 0, 0, {'bomb': 16, 'bx': 2, 'clock': 1}, {}),
    ('jam-ends', 0, 0, {'jam': 1, 'width': 4, 'paddle': 26}, {}),
    ('drone-destroyed', 2, 0, {'enemy': 1, 'ex': 14, 'x': 13, 'y': 11, 'dy': 0}, {}),
    ('drone-damaged', 2, 0, {'enemy': 2, 'ex': 14, 'x': 13, 'y': 11, 'dy': 0}, {}),
    ('drone-turns', 2, 0, {'ex': 27, 'ed': 1, 'clock': 1}, {}),
    ('bomb-spawns', 5, 0, {'clock': 31, 'ex': 9}, {}),
    ('armor-hit', 0, 0, {'x': 0, 'y': 2, 'dy': 0}, {0: 3}),
    ('brick-breaks-drops', 1, 0, {'x': 11, 'y': 3, 'dy': 0, 'broken': 2}, {}),
    ('drop-while-falling', 1, 0, {'x': 11, 'y': 3, 'dy': 0, 'broken': 2, 'item': 2,
                                  'ix': 3, 'iy': 5}, {}),
    ('drone-required', 0, 0, {'left': 0, 'enemy': 1}, {}),
    ('last-brick-wins', 0, 0, {'left': 1, 'x': 0, 'y': 1, 'dy': 0}, {0: 1, 1: 0, 2: 0, 3: 0,
                                                                     4: 0, 5: 0}),
    ('last-ball-lost', 0, 0, {'hp': 1, 'x': 0, 'y': 15, 'dy': 1}, {}),
    ('ball-lost-serves', 0, 0, {'hp': 2, 'x': 0, 'y': 15, 'dy': 1, 'paddle': 20}, {}),
    ('corner-top-right', 0, 0, {'x': 29, 'y': 9, 'dy': 0, 'dx': 1}, {}),
    ('corner-top-left', 0, 0, {'x': 0, 'y': 0, 'dy': 0, 'dx': 0}, {}),
    ('paddle-left-edge', 0, 0, {'x': 11, 'y': 15, 'dy': 1, 'dx': 1}, {}),
    ('paddle-right-edge', 0, 0, {'x': 18, 'y': 15, 'dy': 1, 'dx': 0}, {}),
    ('paddle-middle-steep', 0, 0, {'x': 16, 'y': 15, 'dy': 1, 'dx': 0}, {}),
    ('steep-skips-x', 0, 0, {'steep': 1, 'steps': 0, 'x': 10, 'y': 12, 'dy': 1}, {}),
    ('hold-first-tick', 0, 4, {'repeat': 1}, {}),
    ('hold-moves', 0, 4, {'repeat': 0}, {}),
    ('hold-left-edge', 0, 3, {'paddle': 1}, {}),
    ('hold-right-edge', 0, 4, {'paddle': 24}, {}),
    ('release-clears-repeat', 0, 0, {'repeat': 1}, {}),
]
