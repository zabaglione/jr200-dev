# SPDX-License-Identifier: MIT
"""LUNAR TOUCHDOWN self-test data (sdk/selftest.inc): rule fixtures and one
input script per site. The scripts were found by a depth-first search over
tests/model.py (sites 2 and 4 on the narrow star pad) and land on every site;
src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
FIXTURES = [
    # name, level, operation, {field: value}
    ('tick-falls', 0, 'tick', {}),
    ('tick-gravity-every-third', 0, 'tick', {'time': 2, 'speed': 1}),
    ('tick-speed-capped', 0, 'tick', {'time': 5, 'speed': 5}),
    ('tick-flame-fades', 0, 'tick', {'flame': 2}),
    ('tick-no-wind-site-1', 0, 'tick', {'time': 3}),
    ('tick-wind-pushes-right', 1, 'tick', {'time': 3, 'wind': 1}),
    ('tick-wind-pushes-left', 2, 'tick', {'time': 3, 'wind': 0, 'x': 9}),
    ('tick-wind-edge', 1, 'tick', {'time': 3, 'wind': 1, 'x': 28}),
    ('tick-wind-turns-16', 1, 'tick', {'time': 15}),
    ('tick-wind-turns-12', 4, 'tick', {'time': 11}),
    ('tick-time-wraps', 1, 'tick', {'time': 255}),
    ('left', 0, ('act', 3), {}),
    ('left-edge', 0, ('act', 3), {'x': 0}),
    ('right-edge', 0, ('act', 4), {'x': 28}),
    ('thrust', 0, ('act', 1), {'speed': 3}),
    ('thrust-button', 0, ('act', 5), {'speed': 1}),
    ('thrust-no-fuel', 0, ('act', 1), {'speed': 3, 'fuel': 0}),
    ('land-regular-soft', 0, 'tick', {'height': 29, 'speed': 1, 'x': 8, 'fuel': 9}),
    ('land-regular-edge', 0, 'tick', {'height': 29, 'speed': 2, 'x': 10}),
    ('land-precision', 0, 'tick', {'height': 29, 'speed': 1, 'x': 24, 'fuel': 3}),
    ('crash-speed', 0, 'tick', {'height': 28, 'speed': 3, 'x': 8}),
    ('crash-pad', 0, 'tick', {'height': 29, 'speed': 1, 'x': 11}),
    ('narrow-left-late', 4, 'tick', {'height': 29, 'speed': 2, 'x': 5}),
]
SCRIPTS = [
    [(13, ('act', 1)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4))],
    [(11, ('act', 1)), (2, ('act', 1)), (2, ('act', 1)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4))],
    [(12, ('act', 1)), (1, ('act', 1)), (3, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4))],
    [(11, ('act', 1)), (2, ('act', 1)), (2, ('act', 1)), (3, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4))],
    [(13, ('act', 1)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 1)), (0, ('act', 4)), (1, ('act', 4)), (1, ('act', 4))],
    [(13, ('act', 1)), (1, ('act', 1))],
]
