# SPDX-License-Identifier: BSD-3-Clause
"""Original cover scenes for the JR-200 game titles."""

from canvas import K, B, R, M, G, C, Y, W


def pendulum_port(c):
    c.rect(0, 0, 64, 30, B)
    c.ellipse(44, 2, 13, 13, Y)
    c.poly([(0, 20), (8, 16), (22, 18), (35, 16), (64, 20), (64, 30), (0, 30)], C)
    for x, y in [(3, 22), (15, 26), (30, 25), (36, 21), (55, 27), (47, 22)]:
        c.rect(x, y, 7, 1, B)
    c.poly([(35, 20), (64, 19), (60, 25), (43, 25)], K)
    c.rect(39, 18, 25, 2, Y)
    c.rect(55, 13, 9, 5, W)
    c.rect(61, 8, 2, 5, R)
    c.rect(0, 0, 7, 27, K)
    c.line(1, 4, 29, 4, Y, 3)
    c.line(27, 4, 20, 18, W)
    c.ellipse(18, 15, 5, 4, Y)
    c.line(20, 18, 25, 24, R, 3)
    c.line(22, 21, 27, 18, W, 2)
    c.line(25, 24, 31, 23, R, 2)
    for x, y in [(27, 25), (31, 24), (35, 22), (39, 19)]:
        c.pixel(x, y, W)
    return C


def phase_pairs(c):
    c.rect(0, 0, 64, 30, M)
    for y in range(1, 29, 4):
        c.line(0, y, 63, y - 5, B)
    c.poly([(0, 28), (15, 7), (57, 4), (64, 21), (60, 30), (0, 30)], K)
    for y in (7, 13, 19, 25):
        for x in (16, 24, 32, 40):
            c.rect(x + (y - 7) // 3, y, 7, 5, B)
    for x, y, color in [(14, 8, C), (37, 13, Y)]:
        c.rect(x + 2, y + 2, 14, 15, K)
        c.rect(x, y, 14, 15, color)
        c.rect(x + 1, y + 1, 12, 12, W)
    for y, bits in enumerate((5, 5, 7, 1, 1)):
        for x, bit in enumerate((4, 2, 1)):
            if bits & bit:
                c.rect(18 + x * 2, 10 + y * 2, 2, 2, B)
    for y, bits in enumerate((7, 4, 7, 5, 7)):
        for x, bit in enumerate((4, 2, 1)):
            if bits & bit:
                c.rect(41 + x * 2, 15 + y * 2, 2, 2, M)
    c.rect(31, 15, 5, 1, Y)
    c.rect(33, 13, 1, 5, Y)
    return C


def potion_path(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 11), (18, 3), (46, 3), (64, 11), (64, 30), (0, 30)], M)
    c.poly([(8, 30), (25, 17), (39, 17), (55, 30)], K)
    c.rect(29, 4, 7, 5, G)
    c.line(29, 9, 21, 20, W, 2)
    c.line(35, 9, 43, 20, W, 2)
    c.ellipse(20, 17, 24, 12, W)
    c.ellipse(22, 19, 20, 8, G)
    c.line(25, 24, 36, 24, C)
    c.rect(28, 8, 9, 2, W)
    for x, y, color in [(5, 14, C), (13, 18, Y), (48, 15, R), (56, 18, Y)]:
        c.rect(x + 1, y - 3, 4, 3, W)
        c.rect(x, y, 6, 8, K)
        c.rect(x + 1, y + 2, 4, 5, color)
    for x, y in [(30, 1), (39, 3), (26, 13), (33, 20), (37, 22)]:
        c.pixel(x, y, C)
    return G


def prism_trace(c):
    c.rect(0, 0, 64, 30, B)
    for k in range(-24, 63, 7):
        c.line(k, 29, k + 20, 12, K)
    c.poly([(0, 8), (6, 6), (14, 6), (14, 13), (6, 13), (0, 11)], M)
    c.line(13, 9, 32, 9, W, 2)
    c.line(31, 9, 31, 22, C, 2)
    c.line(32, 22, 51, 22, C, 2)
    c.line(51, 22, 51, 6, C, 2)
    c.line(29, 6, 35, 12, W, 2)
    c.line(29, 24, 35, 19, W, 2)
    c.line(48, 25, 54, 19, W, 2)
    c.poly([(51, 0), (58, 5), (51, 11), (44, 5)], Y)
    c.poly([(51, 2), (55, 5), (51, 8), (47, 5)], W)
    for x, y in [(18, 8), (26, 9), (33, 16), (42, 23), (52, 14)]:
        c.pixel(x, y, Y)
    return C


def quiet_route(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(0, 0, 64, 3, K)
    c.rect(3, 24, 58, 6, K)
    c.rect(8, 4, 10, 19, M)
    c.rect(10, 6, 6, 16, K)
    c.rect(52, 4, 10, 19, C)
    c.rect(54, 6, 6, 16, K)
    c.poly([(14, 11), (44, 17), (36, 24), (14, 14)], Y)
    c.rect(0, 9, 16, 2, K)
    c.rect(5, 10, 9, 4, K)
    c.pixel(13, 12, R)
    c.ellipse(25, 15, 7, 6, K)
    c.poly([(26, 19), (35, 18), (42, 24), (24, 24)], K)
    c.line(29, 19, 38, 20, K, 3)
    c.rect(37, 18, 7, 4, W)
    c.line(39, 19, 42, 19, R)
    c.pixel(57, 11, C)
    c.line(46, 27, 58, 27, C)
    return Y


def ribbon_snake(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 12), (10, 7), (14, 10), (22, 4), (32, 7), (45, 3), (54, 9), (64, 6), (64, 30), (0, 30)], G)
    c.poly([(0, 22), (21, 15), (48, 14), (64, 20), (64, 30), (0, 30)], K)
    for x, y in [(5, 15), (18, 12), (35, 8), (56, 13), (47, 23), (15, 27)]:
        c.poly([(x, y), (x + 4, y - 3), (x + 8, y), (x + 7, y + 3), (x + 1, y + 3)], B)
        c.line(x + 1, y, x + 4, y - 2, C)
    route = [(3, 25), (10, 21), (26, 21), (30, 16), (22, 12), (23, 7), (40, 7), (48, 12), (55, 12)]
    for start, end in zip(route, route[1:]):
        c.line(*start, *end, M, 4)
        c.line(start[0], start[1] - 1, end[0], end[1] - 1, Y, 2)
    c.ellipse(49, 8, 12, 8, Y)
    c.ellipse(54, 8, 5, 5, W)
    c.pixel(57, 9, K)
    c.line(59, 14, 62, 15, R)
    return Y


def ruin_lexicon(c):
    c.rect(0, 0, 64, 30, B)
    c.ellipse(44, 1, 13, 12, Y)
    c.poly([(0, 21), (17, 12), (33, 20), (54, 13), (64, 15), (64, 30), (0, 30)], M)
    c.poly([(0, 27), (21, 20), (42, 24), (64, 21), (64, 30), (0, 30)], Y)
    for x, y in [(6, 11), (48, 12)]:
        c.rect(x, y, 9, 13, K)
        c.rect(x + 1, y + 1, 6, 1, W)
        c.rect(x + 2, y + 8, 7, 1, B)
    c.poly([(19, 25), (24, 8), (29, 3), (38, 5), (44, 25)], K)
    c.line(24, 10, 29, 5, W, 2)
    c.line(29, 5, 36, 7, W, 2)
    c.line(28, 10, 34, 14, C, 2)
    c.line(34, 14, 27, 18, C, 2)
    c.line(28, 12, 27, 20, C)
    c.line(30, 22, 38, 22, C)
    c.pixel(36, 17, Y)
    return Y


def sand_rescue(c):
    c.rect(0, 0, 64, 30, R)
    c.ellipse(6, 1, 16, 14, Y)
    c.poly([(0, 16), (13, 10), (36, 15), (54, 10), (64, 13), (64, 30), (0, 30)], Y)
    c.poly([(0, 24), (21, 17), (33, 20), (48, 16), (64, 20), (64, 30), (0, 30)], M)
    c.rect(28, 3, 13, 9, K)
    c.rect(29, 8, 11, 3, C)
    c.rect(28, 12, 4, 5, K)
    c.rect(38, 12, 3, 6, K)
    c.line(35, 12, 35, 21, C, 3)
    c.line(35, 19, 13, 28, C, 3)
    c.line(35, 19, 51, 29, C, 3)
    c.line(35, 21, 30, 29, C, 2)
    for x, y in [(10, 22), (18, 22), (23, 26), (43, 24), (48, 22), (55, 25)]:
        c.line(x, y - 3, x, y, G)
        c.line(x - 2, y - 2, x, y - 1, G)
        c.line(x + 2, y - 2, x, y - 1, G)
    return Y


def seed_merge(c):
    c.rect(0, 0, 64, 30, B)
    c.ellipse(21, 2, 24, 21, C)
    c.poly([(0, 20), (21, 16), (41, 16), (64, 20), (64, 30), (0, 30)], G)
    for x in (6, 16, 26, 38, 48, 58):
        c.line(32, 18, x, 29, K)
    for x, y in [(12, 21), (49, 22), (19, 25), (41, 26)]:
        c.ellipse(x, y, 4, 4, Y)
    c.line(31, 24, 33, 9, K, 3)
    c.line(33, 18, 25, 13, K, 2)
    c.line(33, 14, 41, 9, K, 2)
    c.ellipse(17, 8, 13, 7, G)
    c.ellipse(35, 4, 13, 8, G)
    c.ellipse(28, 3, 7, 9, Y)
    c.pixel(31, 5, W)
    return C


def shadow_archive(c):
    c.rect(0, 0, 64, 30, B)
    for x in (2, 9, 49, 56):
        c.rect(x, 2, 7, 26, K)
        for y in range(5, 28, 5):
            c.rect(x + 1, y, 4, 1, C)
    c.poly([(0, 24), (12, 21), (53, 21), (64, 24), (64, 30), (0, 30)], M)
    c.poly([(12, 25), (24, 11), (42, 13), (52, 28)], Y)
    c.ellipse(25, 6, 17, 17, W)
    c.ellipse(26, 7, 15, 15, K)
    c.rect(24, 12, 18, 2, K)
    c.rect(28, 9, 10, 4, K)
    c.rect(28, 10, 10, 1, M)
    c.rect(28, 16, 4, 2, C)
    c.rect(35, 16, 4, 2, C)
    c.rect(32, 16, 3, 1, C)
    c.poly([(35, 22), (40, 20), (48, 29), (42, 30)], W)
    c.rect(17, 24, 15, 4, K)
    c.rect(18, 25, 11, 1, Y)
    return Y


def side_catch(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 24), (54, 0), (64, 0), (64, 30), (0, 30)], M)
    for x in (0, 7, 14, 23, 30):
        c.line(x, 14, x + 12, 14, C, 2)
        c.line(x - 4, 21, x + 12, 21, C)
    c.poly([(16, 16), (21, 10), (37, 7), (47, 11), (49, 17), (42, 23), (25, 24)], Y)
    c.poly([(24, 14), (38, 9), (46, 12), (42, 15)], W)
    c.poly([(22, 16), (30, 16), (26, 22), (20, 22)], R)
    c.line(45, 16, 52, 16, W, 2)
    c.ellipse(54, 12, 7, 8, C)
    c.ellipse(56, 14, 3, 3, W)
    return C


def sigil_deck(c):
    for y in range(0, 29, 3):
        c.line(1, y, 62, 29 - y, B)
    c.poly([(29, 1), (46, 8), (44, 24), (29, 29), (19, 21), (17, 9)], M)
    c.poly([(30, 3), (44, 9), (42, 22), (28, 27), (21, 19), (20, 10)], K)
    c.poly([(32, 5), (35, 13), (41, 14), (36, 18), (36, 24), (31, 20), (26, 24), (26, 18), (22, 14), (28, 13)], C)
    c.ellipse(28, 11, 8, 8, W)
    c.ellipse(30, 13, 4, 4, K)
    for points, color in [([(4, 11), (16, 8), (22, 24), (9, 28)], R),
                          ([(50, 8), (62, 11), (56, 27), (44, 24)], Y)]:
        c.poly(points, color)
    c.line(10, 21, 16, 13, W, 2)
    c.line(12, 16, 17, 19, W, 2)
    c.poly([(51, 14), (56, 15), (56, 20), (50, 23), (48, 18)], W)
    return M


def star_lance(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 22), (45, 0), (64, 0), (64, 30), (0, 30)], K)
    for x, y in [(2, 3), (6, 11), (12, 7), (13, 18), (20, 4), (22, 22), (39, 5), (55, 4), (58, 19), (60, 26), (4, 25), (44, 27)]:
        c.pixel(x, y, C)
    for x, y in [(11, 8), (55, 8)]:
        c.poly([(x, y), (x + 5, y + 4), (x + 2, y + 4), (x, y + 7),
                (x - 2, y + 4), (x - 5, y + 4)], C)
        c.pixel(x, y + 3, W)
    for x, y in [(24, 6), (42, 6)]:
        c.poly([(x - 6, y + 1), (x + 6, y + 1), (x + 5, y + 4),
                (x + 2, y + 5), (x, y + 8), (x - 2, y + 5), (x - 5, y + 4)], M)
        c.rect(x - 5, y, 2, 3, W)
        c.rect(x + 4, y, 2, 3, W)
    c.line(33, 6, 33, 21, Y, 2)
    c.poly([(17, 25), (27, 21), (31, 15), (33, 13), (35, 15), (39, 21), (49, 25), (40, 28), (26, 28)], C)
    c.poly([(28, 24), (33, 15), (38, 24)], W)
    c.rect(31, 27, 5, 3, R)
    return C


def stone_balance(c):
    c.rect(0, 0, 64, 30, M)
    c.ellipse(18, 2, 27, 21, R)
    c.poly([(0, 23), (13, 17), (28, 24), (48, 17), (64, 23), (64, 30), (0, 30)], K)
    c.poly([(24, 25), (32, 11), (40, 25)], B)
    c.rect(22, 25, 21, 2, Y)
    c.line(8, 19, 55, 13, W, 2)
    c.line(13, 18, 13, 25, Y)
    c.line(49, 14, 49, 21, Y)
    c.rect(4, 25, 18, 2, Y)
    c.rect(43, 21, 13, 2, Y)
    for x, y, w, h in [(6, 20, 8, 5), (13, 21, 7, 4), (11, 16, 6, 5), (45, 13, 10, 8)]:
        c.ellipse(x, y, w, h, C)
        c.line(x + 2, y + 1, x + w - 3, y + 1, W)
    return Y


def tidal_nets(c):
    c.rect(0, 0, 64, 30, C)
    c.ellipse(46, 2, 12, 12, Y)
    c.poly([(0, 13), (16, 10), (32, 13), (50, 11), (64, 13), (64, 30), (0, 30)], B)
    c.poly([(0, 12), (35, 13), (30, 18), (6, 18)], K)
    c.rect(0, 12, 34, 1, W)
    c.rect(8, 7, 12, 5, R)
    c.rect(10, 8, 7, 2, W)
    c.line(24, 13, 24, 3, K, 2)
    c.line(24, 4, 41, 7, K)
    c.poly([(40, 8), (39, 16), (45, 27), (51, 27), (55, 16), (43, 8)], C)
    for x in range(42, 55, 3):
        c.line(x, 14, 49, 26, W)
    for x, y in [(14, 22), (24, 25), (55, 24), (31, 21)]:
        c.ellipse(x, y, 7, 3, Y)
        c.poly([(x, y + 1), (x - 3, y - 1), (x - 3, y + 3)], Y)
    return C


def tide_bridge(c):
    c.rect(0, 0, 64, 30, B)
    c.ellipse(44, 1, 14, 13, W)
    c.poly([(0, 17), (13, 10), (22, 15), (46, 12), (64, 8), (64, 30), (0, 30)], C)
    c.poly([(0, 20), (18, 15), (21, 19), (10, 30), (0, 30)], G)
    c.poly([(44, 15), (52, 11), (64, 11), (64, 30), (55, 27)], G)
    c.rect(52, 5, 9, 10, K)
    c.rect(54, 7, 5, 8, Y)
    c.rect(55, 9, 3, 6, K)
    for x, y, width in [(12, 24, 17), (22, 21, 14), (30, 18, 13), (39, 15, 12)]:
        c.rect(x + 1, y + 1, width, 3, B)
        c.rect(x, y, width, 2, Y)
        c.line(x, y + 2, x + width - 1, y + 2, K)
    for x, y in [(25, 26), (35, 24), (49, 25), (29, 16)]:
        c.rect(x, y, 6, 1, W)
    return C


def trace_blade(c):
    c.rect(0, 0, 64, 30, B)
    for y in range(2, 29, 6):
        for x in range(-3 + y // 3, 64, 8):
            c.rect(x, y, 7, 5, K)
    for x, y in [(7, 17), (19, 9), (40, 21), (49, 7), (54, 16)]:
        c.poly([(x, y - 4), (x + 4, y), (x, y + 4), (x - 4, y)], M)
        c.pixel(x, y, Y)
    c.poly([(4, 27), (15, 23), (31, 18), (39, 9), (57, 2), (52, 10), (37, 22), (30, 27), (16, 29)], C)
    c.poly([(17, 24), (36, 8), (56, 1), (51, 8), (28, 22), (22, 27)], W)
    c.line(16, 20, 26, 28, Y, 2)
    c.line(20, 24, 13, 29, R, 3)
    return C


def twenty_one(c):
    c.rect(0, 0, 64, 30, G)
    c.ellipse(2, -9, 60, 45, K)
    c.ellipse(3, -8, 58, 43, G)
    c.poly([(10, 6), (25, 2), (35, 23), (18, 28)], K)
    c.poly([(11, 5), (24, 2), (32, 21), (18, 26)], W)
    c.poly([(20, 8), (26, 12), (24, 18), (18, 14)], R)
    c.rect(29, 5, 17, 22, K)
    c.rect(27, 3, 17, 22, W)
    c.ellipse(30, 11, 11, 8, K)
    c.poly([(35, 8), (41, 16), (30, 16)], K)
    c.rect(34, 17, 3, 4, K)
    for x, y, color in [(51, 18, R), (47, 23, Y), (56, 23, C)]:
        c.ellipse(x, y, 8, 5, K)
        c.ellipse(x, y - 1, 8, 4, color)
        c.line(x + 2, y + 1, x + 5, y + 1, W)
    return G


def word_foundry(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 17), (11, 8), (25, 11), (31, 5), (49, 6), (64, 13), (64, 30), (0, 30)], M)
    c.poly([(13, 21), (51, 21), (40, 26), (37, 28), (22, 28), (22, 25)], K)
    c.rect(14, 19, 34, 2, C)
    c.rect(27, 23, 8, 7, K)
    c.poly([(20, 8), (32, 1), (39, 5), (27, 14)], W)
    c.poly([(24, 12), (27, 14), (23, 24), (20, 21)], Y)
    for x, y in [(32, 15), (40, 10), (46, 15), (53, 8), (34, 11), (12, 14)]:
        c.pixel(x, y, Y)
        c.pixel(x + 1, y + 1, W)
    for x, color in [(37, Y), (45, R), (53, Y)]:
        c.rect(x, 21, 6, 6, K)
        c.rect(x, 19, 6, 6, color)
        c.pixel(x + 2, 21, W)
    return Y


SCENES = {
    'pendulum-port': pendulum_port, 'phase-pairs': phase_pairs,
    'potion-path': potion_path, 'prism-trace': prism_trace,
    'quiet-route': quiet_route, 'ribbon-snake': ribbon_snake,
    'ruin-lexicon': ruin_lexicon, 'sand-rescue': sand_rescue,
    'seed-merge': seed_merge, 'shadow-archive': shadow_archive,
    'side-catch': side_catch, 'sigil-deck': sigil_deck,
    'star-lance': star_lance, 'stone-balance': stone_balance,
    'tidal-nets': tidal_nets, 'tide-bridge': tide_bridge,
    'trace-blade': trace_blade, 'twenty-one': twenty_one,
    'word-foundry': word_foundry,
}
