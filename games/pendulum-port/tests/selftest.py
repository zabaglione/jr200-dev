# SPDX-License-Identifier: MIT
"""PENDULUM PORT self-test data (sdk/selftest.inc): rule fixtures and one input
script per route. The scripts were found by a search over tests/model.py
(release when the landing mark meets the deck centre) and clear every route;
src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
FIXTURES = [
    # name, level, operation, {field: value}
    ('tick-swings-out', 0, 'tick', {}),
    ('tick-turns-at-15', 0, 'tick', {'swing': 15}),
    ('tick-turns-at-0', 0, 'tick', {'swing': 0, 'direction': 0}),
    ('tick-swings-back', 0, 'tick', {'swing': 7, 'direction': 0}),
    ('rope-shorter', 0, ('act', 3), {}),
    ('rope-shortest', 0, ('act', 3), {'rope': 1}),
    ('rope-longer', 0, ('act', 4), {}),
    ('rope-longest', 0, ('act', 4), {'rope': 3}),
    ('jump-centre', 0, ('act', 5), {'swing': 5, 'target': 7}),
    ('jump-edge', 0, ('act', 5), {'swing': 6, 'target': 7}),
    ('jump-miss', 0, ('act', 5), {'swing': 2, 'target': 7}),
    ('jump-clamps-at-15', 0, ('act', 5), {'swing': 14, 'rope': 3, 'target': 12}),
    ('jump-back-floor', 0, ('act', 5), {'swing': 1, 'direction': 0, 'rope': 3, 'target': 4}),
    ('jump-back', 0, ('act', 5), {'swing': 9, 'direction': 0, 'target': 7}),
    ('narrow-deck-miss', 3, ('act', 5), {'swing': 6, 'target': 7, 'width': 0}),
    ('last-rope-loses', 0, ('act', 5), {'hp': 1, 'swing': 2, 'target': 7}),
    ('last-port-wins', 2, ('act', 5), {'ports': 7, 'swing': 5, 'target': 7}),
    ('next-port', 3, ('act', 5), {'ports': 2, 'swing': 5, 'target': 7}),
    ('score-wraps', 0, ('act', 5), {'score': 255, 'swing': 5, 'target': 7}),
]
SCRIPTS = [
    [(7, ('act', 4)), (0, ('act', 5)), (5, ('act', 5)), (3, ('act', 5)), (1, ('act', 5)), (8, ('act', 5)), (6, ('act', 5))],
    [(1, ('act', 4)), (0, ('act', 5)), (8, ('act', 5)), (6, ('act', 5)), (4, ('act', 5)), (2, ('act', 5)), (9, ('act', 5)), (7, ('act', 5))],
    [(4, ('act', 4)), (0, ('act', 5)), (2, ('act', 5)), (9, ('act', 5)), (7, ('act', 5)), (5, ('act', 5)), (3, ('act', 5)), (1, ('act', 5)), (8, ('act', 5))],
    [(7, ('act', 4)), (0, ('act', 5)), (5, ('act', 5)), (3, ('act', 5)), (1, ('act', 5)), (8, ('act', 5)), (6, ('act', 5)), (4, ('act', 5)), (2, ('act', 5)), (9, ('act', 5))],
    [(1, ('act', 4)), (0, ('act', 5)), (8, ('act', 5)), (6, ('act', 5)), (4, ('act', 5)), (2, ('act', 5)), (9, ('act', 5)), (7, ('act', 5)), (5, ('act', 5)), (3, ('act', 5)), (1, ('act', 5))],
    [(4, ('act', 4)), (0, ('act', 5)), (2, ('act', 5)), (9, ('act', 5)), (7, ('act', 5)), (5, ('act', 5)), (3, ('act', 5)), (1, ('act', 5)), (8, ('act', 5)), (6, ('act', 5)), (4, ('act', 5)), (2, ('act', 5))],
]
