# SPDX-License-Identifier: MIT
"""ECHO PARRY self-test data (sdk/selftest.inc): rule fixtures and one input
script per duel. The scripts match the guard to the attack and parry in the
late window (double damage); they win every duel. src/selftest.inc is
generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
FIXTURES = [
    # name, level, operation, {field: value}
    ('tick-ready', 0, 'tick', {}),
    ('tick-attack-starts', 0, 'tick', {'age': 3}),
    ('tick-attack-starts-fast', 4, 'tick', {'age': 2}),
    ('tick-feint', 2, 'tick', {'age': 1, 'turn': 1}),
    ('tick-no-feint-early-duel', 1, 'tick', {'age': 1, 'turn': 1}),
    ('tick-window-missed', 0, 'tick', {'phase': 1, 'age': 1}),
    ('tick-window-missed-last-heart', 0, 'tick', {'phase': 1, 'age': 1, 'hp': 1}),
    ('tick-window-guarded', 0, 'tick', {'phase': 1, 'age': 1, 'guarded': 1}),
    ('tick-recovery-ends', 3, 'tick', {'phase': 2, 'age': 2, 'turn': 4, 'guarded': 1,
                                        'evade': 1, 'feint': 1}),
    ('guard-high', 0, ('act', 1), {'stance': 1}),
    ('guard-low', 0, ('act', 2), {}),
    ('evade', 0, ('act', 3), {'phase': 1, 'combo': 2}),
    ('evade-too-late', 0, ('act', 3), {'phase': 2}),
    ('parry-early', 0, ('act', 5), {'phase': 1, 'age': 0}),
    ('parry-late-double', 0, ('act', 5), {'phase': 1, 'age': 1}),
    ('parry-third-chain', 1, ('act', 5), {'phase': 1, 'age': 0, 'combo': 2, 'attack': 0}),
    ('parry-wrong-guard', 0, ('act', 5), {'phase': 1, 'stance': 1}),
    ('parry-too-soon', 0, ('act', 5), {'phase': 0}),
    ('parry-twice', 0, ('act', 5), {'phase': 1, 'guarded': 1}),
    ('parry-last-heart', 0, ('act', 5), {'phase': 2, 'hp': 1}),
    ('parry-finishes', 0, ('act', 5), {'phase': 1, 'age': 1, 'enemy': 1}),
]
SCRIPTS = [
    [(5, ('act', 5)), (9, ('act', 2)), (0, ('act', 5)), (9, ('act', 5))],
    [(5, ('act', 2)), (0, ('act', 5)), (9, ('act', 5)), (9, ('act', 1)), (0, ('act', 5)), (9, ('act', 5))],
    [(5, ('act', 2)), (0, ('act', 5)), (9, ('act', 1)), (0, ('act', 5)), (9, ('act', 5)), (9, ('act', 2)), (0, ('act', 5))],
    [(5, ('act', 5)), (9, ('act', 5)), (9, ('act', 5)), (9, ('act', 2)), (0, ('act', 5)), (9, ('act', 5))],
    [(4, ('act', 2)), (0, ('act', 5)), (8, ('act', 5)), (8, ('act', 1)), (0, ('act', 5)), (8, ('act', 2)), (0, ('act', 5)), (8, ('act', 5))],
    [(4, ('act', 5)), (8, ('act', 2)), (0, ('act', 5)), (8, ('act', 5)), (8, ('act', 5)), (8, ('act', 5)), (8, ('act', 5))],
]
