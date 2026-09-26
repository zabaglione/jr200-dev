# SPDX-License-Identifier: MIT
"""GATE RUNNER self-test data (sdk/selftest.inc): rule fixtures and one input
script per course. Held operations set the direction held down (A = 3,
D = 4, 0 released). The scripts were found by a depth-first search over
tests/model.py, gate by gate, and take every crystal without a hit;
src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('tick-runs', 0, 'tick', {}),
    ('tick-held-right', 0, ('held', 4), {}),
    ('tick-held-left-edge', 0, ('held', 3), {'x': 2}),
    ('tick-held-right-edge', 0, ('held', 4), {'x': 28}),
    ('tick-air-falls', 0, 'tick', {'air': 5}),
    ('tick-notice-fades', 0, 'tick', {'notice_time': 3, 'notice': 4}),
    ('tick-next-gates', 0, 'tick', {'age': 19, 'gates': 3}),
    ('tick-next-gates-mirrored', 1, 'tick', {'age': 19, 'gates': 5}),
    ('gate-wall-hit', 0, 'tick', {'age': 17, 'x': 12}),
    ('gate-wall-dodged', 0, 'tick', {'age': 17, 'x': 20}),
    ('gate-wall-edge', 0, 'tick', {'age': 17, 'x': 9}),
    ('gate-pit-falls', 0, 'tick', {'age': 17, ('b', 0): 2, ('b', 1): 2, ('b', 2): 30}),
    ('gate-pit-jumped', 0, 'tick', {'age': 17, 'air': 5, ('b', 0): 2, ('b', 1): 2, ('b', 2): 30}),
    ('gate-beam-ducked', 0, 'tick', {'age': 17, ('b', 0): 3, ('b', 1): 2, ('b', 2): 30}),
    ('gate-beam-jumped-into', 0, 'tick', {'age': 17, 'air': 4, ('b', 0): 3, ('b', 1): 2,
                                           ('b', 2): 30}),
    ('gate-other-wall', 0, 'tick', {'age': 17, 'x': 20, ('b', 3): 1, ('b', 4): 19,
                                     ('b', 5): 25}),
    ('gate-crystal', 0, 'tick', {'age': 17, 'x': 5}),
    ('gate-crystal-too-far', 0, 'tick', {'age': 17, 'x': 7}),
    ('gate-crystal-in-air', 1, 'tick', {'age': 17, 'x': 22, 'air': 4, ('b', 6): 21,
                                         ('b', 7): 1, ('b', 1): 2, ('b', 2): 3}),
    ('gate-last-hull', 0, 'tick', {'age': 17, 'x': 12, 'hp': 1}),
    ('gate-last-wins', 0, 'tick', {'age': 17, 'x': 20, 'gates': 8}),
    ('step-left', 0, ('act', 3), {}),
    ('step-right', 0, ('act', 4), {}),
    ('jump', 0, ('act', 5), {}),
    ('jump-w', 0, ('act', 1), {}),
    ('jump-in-air', 0, ('act', 5), {'air': 3}),
]
SCRIPTS = [
    [(9, ('held', 3)), (22, ('held', 4)), (5, ('act', 5)), (16, ('held', 0)), (1, ('held', 3)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 4)), (21, ('held', 3)), (13, ('held', 4)), (9, ('act', 5)), (18, ('held', 3)), (2, ('act', 5)), (21, ('held', 0)), (16, ('held', 4)), (3, ('act', 5))],
    [(16, ('act', 5)), (1, ('held', 3)), (8, ('held', 0)), (1, ('held', 4)), (18, ('held', 3)), (31, ('held', 4)), (1, ('act', 5)), (13, ('held', 0)), (1, ('held', 3)), (6, ('act', 5)), (4, ('held', 0)), (1, ('held', 4)), (29, ('held', 3)), (6, ('act', 5)), (15, ('held', 0)), (1, ('held', 4)), (4, ('act', 5)), (8, ('held', 0)), (1, ('held', 3)), (28, ('held', 4)), (24, ('held', 0)), (16, ('held', 3)), (3, ('act', 5))],
    [(14, ('held', 4)), (21, ('held', 3)), (1, ('act', 5)), (13, ('held', 0)), (1, ('held', 4)), (6, ('act', 5)), (4, ('held', 0)), (1, ('held', 3)), (29, ('held', 4)), (6, ('act', 5)), (15, ('held', 0)), (1, ('held', 3)), (4, ('act', 5)), (8, ('held', 0)), (1, ('held', 4)), (28, ('held', 3)), (24, ('held', 0)), (16, ('held', 4)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 3)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 4))],
    [(11, ('held', 3)), (5, ('act', 5)), (4, ('held', 0)), (1, ('held', 4)), (29, ('held', 3)), (6, ('act', 5)), (15, ('held', 0)), (1, ('held', 4)), (4, ('act', 5)), (8, ('held', 0)), (1, ('held', 3)), (28, ('held', 4)), (24, ('held', 0)), (16, ('held', 3)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 4)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 3)), (21, ('held', 4)), (13, ('held', 3)), (9, ('act', 5))],
    [(15, ('held', 3)), (1, ('act', 5)), (10, ('held', 0)), (1, ('held', 4)), (9, ('act', 5)), (20, ('held', 3)), (14, ('held', 0)), (1, ('held', 4)), (9, ('held', 0)), (1, ('held', 3)), (30, ('held', 4)), (5, ('act', 5)), (16, ('held', 0)), (1, ('held', 3)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 4)), (21, ('held', 3)), (13, ('held', 4)), (9, ('act', 5)), (18, ('held', 3)), (2, ('act', 5)), (21, ('held', 0))],
    [(9, ('held', 3)), (24, ('held', 4)), (24, ('held', 0)), (16, ('held', 3)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 4)), (3, ('act', 5)), (16, ('held', 0)), (1, ('held', 3)), (21, ('held', 4)), (13, ('held', 3)), (9, ('act', 5)), (18, ('held', 4)), (2, ('act', 5)), (21, ('held', 0)), (16, ('held', 3)), (3, ('act', 5)), (15, ('held', 0)), (1, ('held', 4)), (4, ('act', 5))],
]
