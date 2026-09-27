# SPDX-License-Identifier: MIT
"""ORBIT DODGE self-test data (sdk/selftest.inc): rule fixtures and one input
script per sector. The scripts fly to the gem one tick into every wave (the
gem is never under a beam) and finish every sector with a gold orbit;
src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
FIXTURES = [
    # name, level, operation, {field: value}
    ('tick-counts-down', 0, 'tick', {}),
    ('fire-hits-target', 0, 'tick', {'age': 4, 'pos': 2, 'orbit': 0, 'target': 2, 'ring': 0}),
    ('fire-hits-other-ring', 2, 'tick', {'age': 4, 'pos': 6, 'orbit': 1, 'other': 6, 'ring': 0}),
    ('fire-single-ignores-other', 0, 'tick', {'age': 4, 'pos': 6, 'orbit': 1, 'other': 6,
                                               'ring': 0, 'gem': 1}),
    ('fire-gem-chain', 0, 'tick', {'age': 4, 'pos': 5, 'orbit': 1, 'gem': 5, 'gem_ring': 1,
                                   'ring': 1, 'target': 4, 'chain': 1, 'score': 7}),
    ('fire-gem-chain-cap', 0, 'tick', {'age': 4, 'pos': 5, 'gem': 5, 'gem_ring': 0, 'chain': 3}),
    ('fire-miss-resets-chain', 0, 'tick', {'age': 4, 'pos': 7, 'gem': 5, 'chain': 2}),
    ('fire-last-hull', 0, 'tick', {'age': 4, 'hp': 1, 'pos': 2, 'target': 2, 'ring': 0}),
    ('fire-last-wave-wins', 0, 'tick', {'age': 4, 'waves': 11, 'pos': 7, 'gem': 5}),
    ('fire-fast-window', 3, 'tick', {'age': 3, 'pos': 7, 'gem': 5}),
    ('fire-next-wave-dual', 0, 'tick', {'age': 4, 'waves': 3, 'pos': 7}),
    ('score-wraps', 0, 'tick', {'age': 4, 'pos': 5, 'gem': 5, 'gem_ring': 0, 'chain': 3,
                                'score': 254}),
    ('left', 0, ('act', 3), {}),
    ('up-is-left', 0, ('act', 1), {'pos': 4}),
    ('right-wraps', 0, ('act', 4), {'pos': 7}),
    ('down-is-right', 0, ('act', 2), {'pos': 3}),
    ('orbit-switch', 0, ('act', 5), {}),
    ('orbit-switch-back', 0, ('act', 5), {'orbit': 1}),
]
SCRIPTS = [
    [(1, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4))],
    [(1, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 3)), (0, ('act', 3))],
    [(1, ('act', 3)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5)), (5, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (5, ('act', 5))],
    [(1, ('act', 5)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4))],
    [(1, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4)), (0, ('act', 4))],
    [(1, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3)), (4, ('act', 5)), (4, ('act', 5)), (0, ('act', 3)), (0, ('act', 3))],
]
