# SPDX-License-Identifier: MIT
"""TRACE BLADE self-test data (sdk/selftest.inc): rule fixtures and one input
script per room. Each script is the upstream levels.json route followed by
F (cut); all thirty rooms are cut. src/selftest.inc is generated from this
file by tests/make_selftest.py.
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'trace_blade_levels_st', Path(__file__).resolve().parent / 'levels.py')
_levels = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_levels)

LIMIT = 10
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('wall-refused', 0, ('act', 3), {}),
    ('used-cell-refused', 0, ('act', 1), {'x': 1, 'y': 2, 'path_len': 1, ('path', 1): 25,
                                          ('visited', 25): 1}),
    ('early-cut-refused', 0, ('act', 8), {}),
    ('undo-at-start-refused', 0, ('act', 6), {}),
    ('menu-opens', 0, ('act', 5), {'menu': 3}),
    ('menu-wraps-up', 0, ('act', 1), {'sub': 1}),
    ('menu-wraps-down', 0, ('act', 2), {'sub': 1, 'menu': 4}),
    ('reset-question-no', 0, ('act', 5), {'sub': 3}),
    ('reset-question-yes', 0, ('act', 5), {'sub': 3, 'choice': 1, 'x': 2, 'path_len': 1,
                                           ('path', 1): 14, ('visited', 14): 1}),
]
SCRIPTS = [[(0, ('act', 'WSAD'.index(c) + 1)) for c in room[2]] + [(0, ('act', 8))]
           for room in _levels.LEVELS]
