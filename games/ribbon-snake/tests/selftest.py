# SPDX-License-Identifier: MIT
"""RIBBON SNAKE self-test data (sdk/selftest.inc): rule fixtures and one input
script per garden. The scripts were found by a search over tests/model.py and
clear every garden; src/selftest.inc is generated from this file by
tests/make_selftest.py.
"""

LIMIT = 1000
HELD = False
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('tick-moves-down', 0, 'tick', {}),
    ('turn-right', 0, ('act', 4), {}),
    ('reverse-ignored', 0, ('act', 1), {}),
    ('brake', 0, ('act', 5), {}),
    ('brake-while-slow', 0, ('act', 5), {'slow': 3}),
    ('brake-none-left', 0, ('act', 5), {'brakes': 0}),
    ('slow-skips-even', 0, 'tick', {'slow': 3}),
    ('slow-moves-odd', 0, 'tick', {'slow': 2}),
    ('edge-loses', 0, 'tick', {'dir': 3}),
    ('edge-bottom-loses', 0, 'tick', {('b', 0): 60, ('b', 1): 52, ('b', 2): 44}),
    ('rock-loses', 0, 'tick', {('d', 16): 1}),
    ('body-loses', 0, 'tick', {'length': 5, 'dir': 4, ('b', 0): 9, ('b', 1): 17,
                                ('b', 2): 18, ('b', 3): 10, ('b', 4): 2}),
    ('tail-follows', 0, 'tick', {'length': 4, 'dir': 4, ('b', 0): 9, ('b', 1): 17,
                                  ('b', 2): 18, ('b', 3): 10}),
    ('tail-blocks-when-eating', 0, 'tick', {'length': 4, 'dir': 4, 'food': 10, ('b', 0): 9,
                                             ('b', 1): 17, ('b', 2): 18, ('b', 3): 10}),
    ('eat-grows', 0, 'tick', {'food': 16}),
    ('eat-last-wins', 0, 'tick', {'food': 16, 'eaten': 7}),
    ('eat-places-food', 3, 'tick', {'food': 16, 'eaten': 4}),
]
SCRIPTS = [
    [(2, ('act', 4)), (2, ('act', 2)), (1, ('act', 4)), (5, ('act', 2)), (2, ('act', 3)), (3, ('act', 1)), (6, ('act', 3)), (3, ('act', 2)), (1, ('act', 4)), (5, ('act', 2)), (1, ('act', 3)), (2, ('act', 2)), (1, ('act', 3)), (1, ('act', 2)), (2, ('act', 3)), (3, ('act', 2)), (1, ('act', 4))],
    [(2, ('act', 4)), (1, ('act', 2)), (1, ('act', 4)), (3, ('act', 2)), (2, ('act', 3)), (4, ('act', 2)), (1, ('act', 4)), (5, ('act', 1)), (4, ('act', 3)), (1, ('act', 1)), (2, ('act', 3)), (2, ('act', 1)), (1, ('act', 4)), (3, ('act', 2)), (1, ('act', 4)), (1, ('act', 2)), (1, ('act', 4)), (1, ('act', 2)), (2, ('act', 3)), (3, ('act', 2)), (2, ('act', 3)), (3, ('act', 2)), (1, ('act', 4)), (5, ('act', 1)), (6, ('act', 3))],
    [(1, ('act', 4)), (1, ('act', 2)), (3, ('act', 4)), (3, ('act', 2)), (2, ('act', 3)), (3, ('act', 1)), (7, ('act', 4)), (5, ('act', 2)), (2, ('act', 3)), (4, ('act', 2)), (2, ('act', 3)), (2, ('act', 2)), (1, ('act', 4)), (5, ('act', 2)), (2, ('act', 3)), (3, ('act', 1)), (7, ('act', 4)), (5, ('act', 2)), (2, ('act', 3)), (5, ('act', 2)), (2, ('act', 3))],
    [(5, ('act', 4)), (5, ('act', 1)), (6, ('act', 3)), (3, ('act', 2)), (1, ('act', 4)), (5, ('act', 2)), (1, ('act', 3)), (2, ('act', 2)), (1, ('act', 3)), (1, ('act', 2)), (3, ('act', 3)), (4, ('act', 2)), (1, ('act', 4)), (3, ('act', 1)), (1, ('act', 4)), (3, ('act', 1)), (1, ('act', 3)), (1, ('act', 1)), (5, ('act', 3)), (2, ('act', 2)), (1, ('act', 3)), (1, ('act', 2)), (1, ('act', 3)), (2, ('act', 2)), (2, ('act', 4)), (4, ('act', 2)), (1, ('act', 3)), (2, ('act', 2)), (1, ('act', 4))],
    [(6, ('act', 4)), (6, ('act', 1)), (3, ('act', 3)), (1, ('act', 1)), (3, ('act', 3)), (2, ('act', 2)), (1, ('act', 3)), (3, ('act', 2)), (4, ('act', 4)), (2, ('act', 1)), (2, ('act', 4)), (3, ('act', 2)), (3, ('act', 3)), (4, ('act', 1)), (1, ('act', 4)), (3, ('act', 2)), (1, ('act', 4)), (3, ('act', 1)), (6, ('act', 3)), (3, ('act', 2)), (1, ('act', 3)), (4, ('act', 2)), (4, ('act', 4)), (2, ('act', 1)), (2, ('act', 4)), (4, ('act', 2)), (2, ('act', 3)), (3, ('act', 2)), (1, ('act', 3)), (1, ('act', 1)), (7, ('act', 4)), (5, ('act', 2)), (5, ('act', 3)), (1, ('act', 1)), (1, ('act', 3)), (1, ('act', 1)), (4, ('act', 3)), (5, ('act', 2)), (2, ('act', 4))],
    [(0, ('act', 4)), (1, ('act', 1)), (1, ('act', 4)), (6, ('act', 2)), (2, ('act', 3)), (4, ('act', 2)), (3, ('act', 3)), (3, ('act', 2)), (1, ('act', 4)), (5, ('act', 1)), (1, ('act', 4)), (1, ('act', 2)), (2, ('act', 3)), (3, ('act', 1)), (6, ('act', 3)), (3, ('act', 1)), (1, ('act', 4)), (4, ('act', 2)), (2, ('act', 4)), (1, ('act', 2)), (4, ('act', 3)), (2, ('act', 1)), (2, ('act', 3)), (1, ('act', 2)), (3, ('act', 4)), (3, ('act', 1)), (1, ('act', 4)), (1, ('act', 1)), (6, ('act', 3)), (3, ('act', 2)), (1, ('act', 3)), (2, ('act', 2)), (1, ('act', 4)), (4, ('act', 2)), (4, ('act', 3)), (2, ('act', 1))],
]
