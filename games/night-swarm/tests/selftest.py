# SPDX-License-Identifier: MIT
"""NIGHT SWARM self-test data (sdk/selftest.inc): rule fixtures and one input
script per wave. The scripts were found by a one-tick search with a greedy
rollout over tests/model.py and survive every wave at full hull;
src/selftest.inc is generated from this file by tests/make_selftest.py.
"""

LIMIT = 1000
E = 255
FIXTURES = [
    # name, level, operation, {field or (list, index): value}
    ('tick-first', 0, 'tick', {}),
    ('tick-march-row-first', 0, 'tick', {'time': 2, ('b', 1): 1}),
    ('tick-march-column', 0, 'tick', {'time': 2, ('b', 0): 1}),
    ('tick-march-same-column', 0, 'tick', {'time': 2, ('b', 0): 59}),
    ('tick-march-hits', 0, 'tick', {'time': 2, ('b', 0): 28, ('b', 3): 26}),
    ('tick-march-last-hull', 0, 'tick', {'time': 2, 'hp': 1, ('b', 0): 28}),
    ('tick-spawn-armored', 0, 'tick', {'time': 3}),
    ('tick-spawn-plain', 1, 'tick', {'time': 3, 'spawn': 2}),
    ('tick-spawn-full', 0, 'tick', {'time': 3, ('b', 0): 0, ('b', 1): 1, ('b', 2): 2,
                                    ('b', 3): 3, ('b', 4): 4, ('b', 5): 5, ('b', 6): 6,
                                    ('b', 7): 16}),
    ('tick-spawn-fast', 3, 'tick', {'time': 2}),
    ('tick-autofire-armor', 0, 'tick', {'time': 0, ('b', 2): 29, ('c', 2): 2}),
    ('tick-autofire-kill-salvage', 0, 'tick', {'time': 0, 'kills': 3, ('b', 2): 35, ('c', 2): 1}),
    ('tick-autofire-out-of-range', 0, 'tick', {'time': 0, ('b', 2): 30, ('c', 2): 1}),
    ('tick-autofire-wins', 0, 'tick', {'time': 0, 'kills': 11, ('b', 5): 19, ('c', 5): 1}),
    ('tick-cooldown', 0, 'tick', {'cooldown': 5}),
    ('tick-portal-right', 0, 'tick', {'time': 3, 'spawn': 1}),
    ('tick-portal-bottom', 0, 'tick', {'time': 3, 'spawn': 5}),
    ('tick-portal-left', 0, 'tick', {'time': 3, 'spawn': 8}),
    ('move-north-west', 0, ('act', 9), {}),
    ('move-south-east', 0, ('act', 12), {}),
    ('move-corner', 0, ('act', 10), {'pos': 7}),
    ('move-west', 0, ('act', 3), {}),
    ('move-salvage', 0, ('act', 4), {'cell': 28, 'hp': 2, 'cooldown': 5}),
    ('move-salvage-full-hull', 0, ('act', 2), {'cell': 35, 'cooldown': 1}),
    ('pulse', 0, ('act', 5), {('b', 0): 24, ('c', 0): 1, ('b', 1): 45, ('c', 1): 2,
                              ('b', 2): 63, ('c', 2): 1}),
    ('pulse-cooling', 0, ('act', 5), {'cooldown': 1, ('b', 0): 24, ('c', 0): 1}),
    ('pulse-wins', 0, ('act', 5), {'kills': 10, ('b', 0): 24, ('c', 0): 1, ('b', 1): 26,
                                   ('c', 1): 1, ('b', 2): 29, ('c', 2): 1}),
]
SCRIPTS = [
    [(0, ('act', 1)), (17, ('act', 5)), (4, ('act', 12)), (5, ('act', 5)), (1, ('act', 3)), (1, ('act', 3)), (4, ('act', 12)), (1, ('act', 1)), (3, ('act', 10)), (1, ('act', 12)), (2, ('act', 1)), (1, ('act', 5)), (1, ('act', 4)), (3, ('act', 2)), (4, ('act', 5)), (9, ('act', 2)), (2, ('act', 5))],
    [(7, ('act', 1)), (0, ('act', 5)), (4, ('act', 4)), (2, ('act', 1)), (2, ('act', 5)), (5, ('act', 12)), (3, ('act', 5)), (1, ('act', 2)), (5, ('act', 4)), (1, ('act', 2)), (2, ('act', 5)), (8, ('act', 5)), (8, ('act', 11)), (0, ('act', 5)), (4, ('act', 1)), (4, ('act', 1)), (0, ('act', 5)), (7, ('act', 1)), (1, ('act', 5))],
    [(4, ('act', 12)), (8, ('act', 2)), (1, ('act', 2)), (2, ('act', 1)), (1, ('act', 5)), (8, ('act', 1)), (0, ('act', 5)), (4, ('act', 2)), (4, ('act', 5)), (1, ('act', 4)), (1, ('act', 5)), (4, ('act', 2)), (2, ('act', 9)), (4, ('act', 3)), (0, ('act', 5)), (4, ('act', 10)), (1, ('act', 1)), (1, ('act', 5)), (1, ('act', 3)), (5, ('act', 1)), (3, ('act', 5)), (12, ('act', 5)), (1, ('act', 4))],
    [(0, ('act', 11)), (4, ('act', 2)), (4, ('act', 1)), (8, ('act', 1)), (0, ('act', 5)), (4, ('act', 12)), (4, ('act', 1)), (2, ('act', 5)), (9, ('act', 1)), (1, ('act', 5)), (4, ('act', 1)), (4, ('act', 5)), (1, ('act', 4)), (1, ('act', 12)), (2, ('act', 2)), (3, ('act', 4)), (1, ('act', 5)), (8, ('act', 2)), (2, ('act', 5))],
    [(5, ('act', 1)), (6, ('act', 1)), (1, ('act', 5)), (4, ('act', 2)), (5, ('act', 3)), (2, ('act', 5)), (4, ('act', 12)), (1, ('act', 11)), (4, ('act', 5)), (4, ('act', 10)), (4, ('act', 5)), (5, ('act', 12)), (3, ('act', 5)), (4, ('act', 2)), (7, ('act', 5)), (9, ('act', 5))],
    [(4, ('act', 2)), (4, ('act', 10)), (4, ('act', 2)), (2, ('act', 10)), (1, ('act', 5)), (1, ('act', 11)), (7, ('act', 4)), (1, ('act', 1)), (2, ('act', 5)), (4, ('act', 2)), (2, ('act', 2)), (7, ('act', 5)), (1, ('act', 3)), (1, ('act', 5)), (9, ('act', 2)), (1, ('act', 5)), (1, ('act', 9)), (7, ('act', 3)), (1, ('act', 10)), (2, ('act', 5)), (4, ('act', 1)), (2, ('act', 5)), (7, ('act', 2)), (1, ('act', 5))],
]
