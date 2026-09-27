# SPDX-License-Identifier: MIT
"""METRO WEAVE self-test data (sdk/selftest.inc): rule fixtures and one input
script per shift, all with origin 0 (upstream entropy() is fixed in the self
test and the demo). The scripts set the points for the train nearest each
point and choose express sends by a short lookahead over tests/model.py;
they finish every shift without losing a heart. src/selftest.inc is
generated from this file by tests/make_selftest.py.
"""

LIMIT = 2000
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('tick-first', 0, 'tick', {}),
    ('select-point-2', 0, ('act', 2), {}),
    ('switch-point-1', 0, ('act', 4), {}),
    ('switch-point-2', 0, ('act', 4), {'cursor': 1}),
    ('stop-point-1', 0, ('act', 3), {}),
    ('express-blocked-near-start', 0, ('act', 5), {}),
    ('express-sent', 0, ('act', 5), {('b', 0): 9}),
    ('express-capacity', 0, ('act', 5), {('b', 0): 9, 'active': 2}),
    ('express-shift-over', 0, ('act', 5), {('b', 0): 9, 'issued': 8}),
    ('point-1-routes-down', 0, 'tick', {('b', 0): 8, ('c', 0): 1}),
    ('point-1-held', 0, 'tick', {('b', 0): 8, ('c', 2): 1}),
    ('point-2-routes', 0, 'tick', {('b', 0): 17, ('b', 3): 10, ('b', 6): 1, ('c', 1): 1}),
    ('point-2-held', 0, 'tick', {('b', 0): 17, ('b', 3): 10, ('b', 6): 1, ('c', 3): 1}),
    ('descends', 0, 'tick', {('b', 0): 12, ('b', 3): 7, ('b', 6): 1}),
    ('platform-busy', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('c', 8): 5}),
    ('brakes-behind', 0, 'tick', {('b', 0): 10, ('b', 1): 12, ('b', 4): 5, 'active': 2}),
    ('express-counts-down', 0, 'tick', {('b', 0): 10, ('b', 15): 1, ('b', 12): 5}),
    ('express-goes-late', 0, 'tick', {('b', 0): 10, ('b', 15): 1, ('b', 12): 0}),
    ('arrive-right', 0, 'tick', {('b', 0): 25, ('b', 3): 5, 'active': 1, 'chain': 1}),
    ('arrive-express', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('b', 15): 1, ('b', 12): 9,
                                   'active': 1, 'chain': 2, 'score': 10}),
    ('arrive-wrong', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('b', 9): 2, 'active': 1,
                                 'chain': 2}),
    ('arrive-late', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('b', 15): 2, 'active': 1}),
    ('arrive-wrong-last-heart', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('b', 9): 1,
                                            'active': 1, 'hp': 1}),
    ('arrive-late-last-heart', 0, 'tick', {('b', 0): 25, ('b', 3): 5, ('b', 15): 2,
                                           'active': 1, 'hp': 1}),
    ('shift-short-of-quota', 0, 'tick', {('b', 0): 25, ('b', 3): 5, 'active': 1, 'done': 7,
                                         'score': 10}),
    ('shift-bronze', 0, 'tick', {('b', 0): 25, ('b', 3): 5, 'active': 1, 'done': 7,
                                 'score': 30}),
    ('shift-silver', 0, 'tick', {('b', 0): 25, ('b', 3): 5, 'active': 1, 'done': 7,
                                 'score': 42}),
    ('shift-gold', 1, 'tick', {('b', 0): 25, ('b', 3): 5, 'active': 1, 'done': 7,
                               'score': 58, ('b', 9): 0}),
    ('auto-dispatch', 2, 'tick', {('b', 0): 12, 'cool': 1}),
    ('busy-clears', 0, 'tick', {('c', 9): 1, ('c', 10): 3}),
]
SCRIPTS = [
    [(3, ('act', 5)), (4, ('act', 4)), (17, ('act', 5)), (1, ('act', 4)), (2, ('act', 5)), (4, ('act', 4)), (17, ('act', 5)), (4, ('act', 5)), (3, ('act', 1)), (0, ('act', 4)), (17, ('act', 5)), (1, ('act', 1)), (0, ('act', 4)), (11, ('act', 5)), (1, ('act', 4)), (6, ('act', 1)), (0, ('act', 4))],
    [(3, ('act', 5)), (3, ('act', 5)), (1, ('act', 4)), (12, ('act', 1)), (0, ('act', 4)), (5, ('act', 1)), (0, ('act', 4)), (3, ('act', 5)), (3, ('act', 5)), (1, ('act', 4)), (12, ('act', 1)), (0, ('act', 4)), (5, ('act', 1)), (0, ('act', 4)), (3, ('act', 5)), (4, ('act', 4))],
    [(0, ('act', 4)), (3, ('act', 5)), (3, ('act', 5)), (10, ('act', 1)), (0, ('act', 4)), (3, ('act', 4)), (5, ('act', 1)), (0, ('act', 4)), (4, ('act', 5)), (8, ('act', 4)), (12, ('act', 4)), (12, ('act', 4))],
]
