# SPDX-License-Identifier: MIT
"""SAND RESCUE self-test data (sdk/selftest.inc): rule fixtures and one input
script per field. The fields are played in order as one campaign (each
starts with the water and total the previous one carried). The scripts pour
the tank into the channel with the best points per water once it holds
enough, and leave a field at its target; they clear all six fields (total
131). src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 3000
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('tick-first', 0, 'tick', {}),
    ('tick-refills', 0, 'tick', {'fill': 1}),
    ('tick-overflow', 0, 'tick', {'fill': 1, 'tank': 9}),
    ('gate-left-wraps', 0, ('act', 3), {}),
    ('gate-right', 0, ('act', 4), {'gate': 1}),
    ('pour', 0, ('act', 5), {'tank': 6, 'gate': 2, 'notice': 3}),
    ('pour-empty', 0, ('act', 5), {}),
    ('pour-while-flowing', 0, ('act', 5), {'tank': 4, 'flow': 2}),
    ('flow-steps', 0, 'tick', {'flow': 5, 'step': 1}),
    ('flow-near-crop', 0, 'tick', {'flow': 5, 'step': 2}),
    ('flow-near-partial', 0, 'tick', {'flow': 1, 'step': 2}),
    ('flow-soaks', 0, 'tick', {'flow': 5, 'step': 5}),
    ('flow-far-crop', 0, 'tick', {'flow': 6, 'step': 9, ('c', 0): 2}),
    ('flow-runs-out', 0, 'tick', {'flow': 2, 'step': 12}),
    ('water-gone-loses', 0, 'tick', {'water': 0}),
    ('water-gone-target-met', 0, 'tick', {'water': 0, 'score': 14}),
    ('leave-too-early', 0, ('act', 1), {'score': 13}),
    ('leave-while-flowing', 0, ('act', 1), {'score': 14, 'flow': 1}),
    ('leave-wins', 0, ('act', 1), {'score': 17, 'total': 0, 'water': 90, 'tank': 4}),
    ('next-field-carries', 1, 'tick', {}),
    ('restart-begins-again', 3, 'tick', {}),
]
SCRIPTS = [
    [(35, ('act', 5)), (10, ('act', 4)), (0, ('act', 4)), (0, ('act', 5)), (3, ('act', 1))],
    [(45, ('act', 4)), (0, ('act', 5)), (40, ('act', 4)), (0, ('act', 4)), (0, ('act', 5)), (12, ('act', 1))],
    [(32, ('act', 4)), (0, ('act', 5)), (28, ('act', 4)), (0, ('act', 5)), (10, ('act', 1))],
    [(28, ('act', 5)), (32, ('act', 4)), (0, ('act', 4)), (0, ('act', 5)), (11, ('act', 1))],
    [(24, ('act', 4)), (0, ('act', 5)), (11, ('act', 4)), (0, ('act', 4)), (0, ('act', 5)), (19, ('act', 5)), (12, ('act', 1))],
    [(27, ('act', 4)), (0, ('act', 5)), (24, ('act', 4)), (0, ('act', 5)), (12, ('act', 4)), (0, ('act', 5)), (8, ('act', 1))],
]
