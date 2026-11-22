"""Original pixel-art title scenes for a group of JR-200 games."""

from canvas import K, B, R, M, G, C, Y, W


def _stars(c, points, color=C):
    for x, y in points:
        c.pixel(x, y, color)


def gravity_well(c):
    _stars(c, [(5, 3), (14, 2), (55, 4), (60, 8), (9, 26), (56, 27)], W)
    c.poly([(7, 7), (57, 7), (63, 25), (1, 25)], B)
    c.poly([(11, 9), (53, 9), (59, 24), (5, 24)], C)
    c.poly([(13, 11), (51, 11), (55, 22), (9, 22)], B)
    for x in (18, 28, 38, 48):
        c.line(x, 11, x - 2, 22, C)
    for y in (15, 19):
        c.line(9, y, 55, y, C)
    c.poly([(15, 16), (19, 19), (15, 22), (11, 19)], M)
    c.poly([(49, 16), (53, 19), (49, 22), (45, 19)], M)
    c.ellipse(25, 14, 8, 8, W)
    c.ellipse(37, 15, 7, 7, Y)
    c.pixel(27, 16, C)
    c.pixel(39, 17, R)
    c.line(5, 7, 10, 4, Y)
    c.line(58, 7, 54, 4, Y)


def hearth_zero(c):
    c.rect(0, 0, 64, 23, B)
    _stars(c, [(7, 4), (17, 2), (54, 5), (59, 10), (10, 13), (49, 2)], W)
    c.poly([(0, 18), (15, 9), (27, 19), (42, 8), (64, 17), (64, 30), (0, 30)], C)
    c.poly([(0, 23), (14, 18), (27, 24), (40, 17), (64, 23), (64, 30), (0, 30)], W)
    c.ellipse(18, 6, 29, 25, M)
    c.ellipse(22, 9, 21, 21, B)
    c.rect(25, 17, 15, 11, K)
    c.poly([(25, 24), (28, 17), (31, 24), (34, 14), (38, 22), (40, 27), (25, 27)], R)
    c.poly([(29, 25), (32, 20), (34, 24), (36, 17), (39, 26)], Y)
    c.pixel(34, 20, W)
    for x, y in [(22, 26), (25, 28), (40, 27), (43, 25)]:
        c.ellipse(x, y, 4, 3, C)
    c.line(5, 22, 16, 22, B)
    c.line(49, 23, 61, 21, B)


def iron_script(c):
    c.rect(0, 0, 64, 24, B)
    _stars(c, [(5, 4), (12, 8), (51, 3), (58, 8), (4, 14)], C)
    c.rect(0, 24, 64, 6, K)
    for x in range(3, 64, 8):
        c.line(x, 25, x, 29, B)
    c.rect(10, 12, 8, 12, M)
    c.rect(21, 7, 6, 17, C)
    c.rect(37, 11, 8, 13, R)
    c.rect(49, 8, 9, 16, Y)
    c.line(18, 22, 21, 22, W)
    c.line(27, 22, 37, 22, W)
    c.line(45, 22, 49, 22, W)
    c.line(28, 13, 35, 13, R, 2)
    c.line(28, 17, 35, 17, R, 2)
    c.rect(23, 11, 3, 3, W)
    c.rect(24, 16, 3, 3, W)
    c.rect(38, 14, 3, 3, K)
    c.rect(51, 11, 5, 4, M)
    c.rect(52, 17, 3, 3, C)
    c.poly([(5, 24), (8, 20), (11, 24)], Y)
    c.line(4, 26, 60, 26, C)


def loop_ten(c):
    c.rect(0, 0, 64, 30, B)
    _stars(c, [(5, 6), (57, 5), (10, 24), (53, 25), (31, 2)], C)
    c.ellipse(17, 1, 31, 28, M)
    c.ellipse(22, 5, 21, 20, B)
    c.poly([(12, 7), (20, 7), (18, 2)], Y)
    c.poly([(52, 21), (44, 22), (48, 27)], Y)
    c.poly([(8, 20), (14, 17), (14, 22)], C)
    c.poly([(57, 10), (51, 13), (52, 8)], C)
    c.ellipse(27, 9, 11, 11, Y)
    c.ellipse(30, 12, 5, 5, K)
    c.line(32, 14, 32, 10, W, 2)
    c.line(32, 14, 36, 16, W, 2)
    c.rect(2, 23, 11, 5, C)
    c.rect(50, 2, 12, 5, C)
    c.rect(4, 24, 3, 3, W)
    c.rect(55, 3, 3, 3, W)
    c.pixel(21, 14, Y)
    c.pixel(44, 15, Y)


def lumen_cross(c):
    c.rect(0, 0, 64, 30, B)
    _stars(c, [(3, 4), (60, 4), (4, 26), (59, 25)], C)
    c.rect(7, 2, 50, 26, C)
    c.rect(9, 4, 46, 22, B)
    tiles = [
        [K, C, K, C, K],
        [C, K, Y, K, C],
        [K, Y, W, Y, K],
        [C, K, Y, K, C],
        [K, C, K, C, K],
    ]
    for row, colors in enumerate(tiles):
        for col, color in enumerate(colors):
            x, y = 11 + col * 8, 5 + row * 4
            c.rect(x, y, 6, 3, color)
            c.line(x, y, x + 5, y, W if color == Y else C)
    c.line(31, 2, 31, 27, W, 2)
    c.line(8, 14, 55, 14, W, 2)
    c.ellipse(27, 10, 10, 9, Y)
    c.ellipse(30, 12, 4, 4, W)


def lunar_touchdown(c):
    c.rect(0, 0, 64, 25, B)
    _stars(c, [(4, 5), (13, 2), (21, 8), (49, 4), (59, 10), (8, 15), (43, 9)], W)
    c.ellipse(44, 1, 14, 12, C)
    c.ellipse(48, 1, 11, 10, B)
    c.poly([(0, 23), (12, 19), (22, 23), (35, 18), (48, 22), (64, 17), (64, 30), (0, 30)], C)
    c.poly([(0, 27), (18, 24), (31, 27), (47, 23), (64, 26), (64, 30), (0, 30)], W)
    c.rect(25, 9, 14, 8, Y)
    c.poly([(23, 12), (25, 8), (39, 8), (42, 12), (38, 16), (26, 16)], Y)
    c.rect(29, 11, 6, 4, B)
    c.line(25, 15, 22, 20, W, 2)
    c.line(39, 15, 42, 20, W, 2)
    c.line(21, 20, 25, 20, C, 2)
    c.line(40, 20, 44, 20, C, 2)
    c.poly([(28, 17), (31, 17), (30, 23), (27, 20)], R)
    c.poly([(34, 17), (37, 17), (38, 20), (35, 23)], R)
    c.rect(45, 25, 12, 2, M)
    c.line(47, 24, 55, 24, Y, 2)


def magnet_vault(c):
    c.rect(0, 0, 64, 30, K)
    c.poly([(4, 8), (60, 8), (64, 28), (0, 28)], B)
    c.ellipse(14, 1, 36, 26, M)
    c.ellipse(20, 5, 24, 19, B)
    c.rect(23, 0, 18, 8, K)
    c.rect(18, 2, 7, 9, C)
    c.rect(39, 2, 7, 9, R)
    c.rect(22, 7, 4, 4, W)
    c.rect(38, 7, 4, 4, Y)
    c.poly([(19, 12), (27, 12), (30, 17), (22, 18)], M)
    c.poly([(45, 12), (37, 12), (34, 17), (42, 18)], M)
    c.rect(20, 21, 9, 7, Y)
    c.rect(35, 21, 9, 7, Y)
    c.line(20, 23, 29, 23, R)
    c.line(35, 23, 44, 23, R)
    c.poly([(7, 25), (13, 21), (17, 25)], C)
    c.poly([(47, 25), (52, 20), (58, 25)], C)
    c.pixel(31, 19, W)


def memory_mosaic(c):
    c.rect(0, 0, 64, 30, B)
    _stars(c, [(3, 3), (60, 4), (4, 26), (59, 27)], W)
    colors = [M, C, R, Y, C, G, Y, M, R, Y, C, G, Y, M, G, R]
    for index, color in enumerate(colors):
        row, col = divmod(index, 4)
        x, y = 6 + col * 13, 2 + row * 7
        c.rect(x, y, 11, 6, color)
        c.line(x, y, x + 10, y, W)
        c.line(x, y, x, y + 5, W)
        if index in (5, 10):
            c.poly([(x + 5, y + 1), (x + 8, y + 3), (x + 5, y + 5), (x + 2, y + 3)], W)
            c.pixel(x + 5, y + 3, Y)
        elif index % 4 == 0:
            c.ellipse(x + 3, y + 1, 5, 4, W)
            c.ellipse(x + 4, y + 2, 3, 2, color)
        elif index % 4 == 1:
            c.poly([(x + 5, y + 1), (x + 9, y + 3), (x + 5, y + 5), (x + 1, y + 3)], Y)
        elif index % 4 == 2:
            c.line(x + 2, y + 4, x + 5, y + 1, W, 2)
            c.line(x + 5, y + 1, x + 8, y + 4, W, 2)
        else:
            c.ellipse(x + 3, y + 1, 5, 5, Y)
            c.pixel(x + 5, y + 3, W)
    c.line(4, 1, 60, 1, Y)
    c.line(4, 29, 60, 29, Y)


def metro_weave(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 0), (18, 0), (18, 14), (0, 14)], C)
    c.rect(3, 4, 5, 10, M)
    c.rect(10, 2, 6, 12, Y)
    c.rect(47, 0, 17, 14, C)
    c.rect(51, 3, 7, 7, Y)
    c.ellipse(4, 15, 12, 10, B)
    c.poly([(0, 24), (22, 18), (41, 23), (64, 15), (64, 30), (0, 30)], K)
    c.line(0, 24, 64, 19, W, 2)
    c.line(0, 28, 64, 23, W, 2)
    c.line(4, 25, 4, 28, C)
    c.line(13, 24, 13, 27, C)
    c.line(22, 23, 22, 26, C)
    c.line(31, 22, 31, 25, C)
    c.line(40, 21, 40, 24, C)
    c.line(49, 20, 49, 23, C)
    c.line(58, 19, 58, 22, C)
    c.line(27, 20, 40, 10, Y, 2)
    c.line(34, 21, 45, 13, Y, 2)
    c.poly([(7, 15), (32, 15), (37, 19), (37, 23), (7, 23)], R)
    c.rect(11, 16, 6, 4, W)
    c.rect(20, 16, 6, 4, W)
    c.rect(29, 16, 5, 4, Y)
    c.ellipse(10, 21, 5, 5, K)
    c.ellipse(29, 20, 5, 5, K)
    c.poly([(48, 14), (52, 9), (56, 14)], Y)
    c.ellipse(54, 14, 7, 7, M)


def mirror_relic(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(3, 2, 58, 26, K)
    c.line(32, 2, 32, 28, C, 2)
    c.line(3, 15, 61, 15, C, 2)
    c.line(4, 4, 29, 4, B)
    c.line(35, 4, 59, 4, B)
    c.line(4, 26, 29, 26, B)
    c.line(35, 26, 59, 26, B)
    c.ellipse(21, 1, 23, 27, Y)
    c.ellipse(24, 4, 17, 21, M)
    c.ellipse(27, 6, 11, 17, C)
    c.line(31, 8, 31, 21, W, 2)
    c.line(28, 15, 39, 4, Y)
    c.line(36, 7, 25, 18, Y)
    c.poly([(9, 7), (12, 4), (15, 7), (12, 10)], R)
    c.poly([(49, 7), (52, 4), (55, 7), (52, 10)], R)
    c.poly([(9, 22), (12, 19), (15, 22), (12, 25)], Y)
    c.poly([(49, 22), (52, 19), (55, 22), (52, 25)], Y)
    c.pixel(12, 7, W)
    c.pixel(52, 22, W)


def night_swarm(c):
    c.rect(0, 0, 64, 30, B)
    _stars(c, [(4, 7), (12, 3), (52, 5), (59, 11), (6, 24), (55, 26), (30, 3)], W)
    c.ellipse(17, 1, 30, 28, M)
    c.ellipse(22, 5, 20, 20, B)
    for x, y in [(5, 3), (47, 2), (2, 17), (52, 17), (10, 23), (44, 24)]:
        c.poly([(x + 3, y), (x + 6, y + 3), (x + 3, y + 6), (x, y + 3)], R)
        c.pixel(x + 3, y + 3, Y)
    c.poly([(28, 7), (33, 13), (29, 14), (25, 13)], C)
    c.poly([(27, 12), (32, 12), (37, 20), (32, 18), (27, 22), (29, 16)], W)
    c.poly([(29, 17), (32, 17), (31, 26), (29, 21)], Y)
    c.line(10, 8, 24, 14, C)
    c.line(52, 8, 38, 14, C)
    c.line(11, 22, 25, 17, C)
    c.line(53, 22, 39, 17, C)
    c.pixel(25, 15, Y)
    c.pixel(38, 15, Y)


def number_vault(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(3, 3, 58, 24, B)
    c.ellipse(12, 1, 40, 28, M)
    c.ellipse(16, 4, 32, 22, C)
    c.ellipse(21, 7, 22, 16, B)
    c.ellipse(25, 9, 14, 12, K)
    c.ellipse(28, 10, 8, 8, Y)
    c.ellipse(30, 12, 4, 4, W)
    c.line(31, 14, 36, 9, R, 2)
    c.line(15, 14, 22, 14, W, 2)
    c.line(41, 14, 49, 14, W, 2)
    for x, color in [(20, R), (29, Y), (38, G), (47, C)]:
        c.ellipse(x, 5, 7, 7, color)
        c.ellipse(x + 2, 7, 3, 3, W)
        c.line(x + 3, 2, x + 3, 5, W)
    c.rect(7, 23, 7, 3, R)
    c.rect(17, 23, 7, 3, Y)
    c.rect(27, 23, 7, 3, G)
    c.rect(37, 23, 7, 3, C)
    c.rect(47, 23, 7, 3, W)
    c.poly([(7, 15), (10, 12), (13, 15), (10, 18)], Y)
    c.poly([(51, 15), (54, 12), (57, 15), (54, 18)], Y)


def orbit_dodge(c):
    c.rect(0, 0, 64, 30, K)
    _stars(c, [(4, 5), (10, 2), (56, 6), (60, 24), (9, 26), (47, 3)], W)
    c.ellipse(8, 2, 48, 25, B)
    c.ellipse(14, 5, 36, 19, K)
    c.ellipse(19, 6, 27, 18, C)
    c.ellipse(23, 8, 18, 13, B)
    c.ellipse(4, 1, 56, 28, M)
    c.ellipse(8, 4, 48, 22, K)
    c.ellipse(13, 2, 38, 26, C)
    c.ellipse(18, 5, 28, 20, K)
    c.poly([(12, 5), (18, 8), (13, 11)], W)
    c.line(13, 8, 20, 8, R, 2)
    c.poly([(53, 17), (49, 13), (55, 12)], W)
    c.line(50, 15, 43, 16, R, 2)
    c.poly([(32, 2), (35, 5), (32, 8), (29, 5)], Y)
    c.pixel(32, 5, W)
    c.pixel(30, 15, Y)
    c.pixel(46, 9, Y)


def orbit_draft(c):
    c.rect(0, 0, 64, 30, B)
    _stars(c, [(3, 5), (60, 4), (5, 25), (58, 25)], C)
    c.poly([(8, 4), (55, 4), (60, 26), (4, 26)], M)
    suits = [C, Y, R, C, Y, R, G, Y, R, C, Y, R, G, C, R, Y]
    for index, color in enumerate(suits):
        row, col = divmod(index, 4)
        x, y = 10 + col * 11, 6 + row * 5
        c.rect(x, y, 9, 4, color)
        c.line(x, y, x + 8, y, W)
        if index in (1, 5, 9):
            c.poly([(x + 4, y), (x + 8, y + 2), (x + 4, y + 4), (x, y + 2)], W)
        elif index % 2 == 0:
            c.ellipse(x + 3, y + 1, 3, 2, W)
        else:
            c.line(x + 2, y + 3, x + 4, y + 1, W, 2)
            c.line(x + 4, y + 1, x + 7, y + 3, W, 2)
    c.poly([(2, 13), (7, 10), (6, 16)], Y)
    c.poly([(61, 13), (56, 10), (57, 16)], Y)
    c.poly([(29, 1), (35, 1), (32, 5)], W)
    c.poly([(29, 29), (35, 29), (32, 25)], W)
    c.line(15, 8, 38, 8, Y, 2)


def orchard_days(c):
    c.rect(0, 0, 64, 24, B)
    c.ellipse(49, 2, 10, 10, Y)
    _stars(c, [(5, 4), (20, 3), (36, 6), (59, 14)], W)
    c.poly([(0, 18), (15, 14), (27, 19), (41, 13), (64, 18), (64, 30), (0, 30)], G)
    c.poly([(0, 23), (18, 19), (32, 23), (48, 18), (64, 22), (64, 30), (0, 30)], C)
    for x, y in [(9, 10), (25, 8), (43, 10)]:
        c.rect(x + 4, y + 8, 4, 8, R)
        c.ellipse(x, y, 13, 11, G)
        c.ellipse(x + 2, y + 11, 4, 4, R)
        c.ellipse(x + 8, y + 12, 4, 4, R)
        c.pixel(x + 4, y + 12, W)
    c.ellipse(1, 15, 9, 7, M)
    c.ellipse(3, 16, 3, 3, Y)
    c.ellipse(6, 17, 3, 3, Y)
    c.line(2, 2, 7, 8, C, 2)
    c.line(16, 1, 21, 7, C, 2)
    c.line(33, 2, 38, 8, C, 2)
    c.line(57, 12, 54, 18, C, 2)
    c.line(5, 27, 60, 27, W)


def peg_garden(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(20, 2, 24, 26, G)
    c.rect(6, 9, 52, 12, G)
    c.poly([(0, 2), (14, 2), (18, 8), (9, 9), (4, 14), (0, 13)], C)
    c.poly([(64, 2), (50, 2), (46, 8), (55, 9), (60, 14), (64, 13)], C)
    c.poly([(0, 28), (14, 28), (18, 22), (9, 21), (4, 16), (0, 17)], C)
    c.poly([(64, 28), (50, 28), (46, 22), (55, 21), (60, 16), (64, 17)], C)
    holes = [(25, 5), (32, 5), (39, 5), (25, 11), (32, 11), (39, 11),
             (11, 14), (18, 14), (25, 14), (32, 14), (39, 14), (46, 14), (53, 14),
             (25, 17), (32, 17), (39, 17), (25, 23), (32, 23), (39, 23)]
    for x, y in holes:
        c.ellipse(x, y, 5, 5, K)
    for x, y in [(25, 5), (39, 5), (25, 11), (39, 11), (11, 14), (18, 14),
                 (39, 14), (46, 14), (25, 17), (32, 23), (39, 23)]:
        c.ellipse(x + 1, y + 1, 3, 3, Y)
        c.pixel(x + 2, y + 1, W)
    c.line(18, 14, 31, 14, W, 2)
    c.poly([(31, 12), (35, 14), (31, 16)], W)
    c.line(5, 5, 11, 8, Y)
    c.line(59, 24, 53, 21, Y)


SCENES = {
    "gravity-well": gravity_well,
    "hearth-zero": hearth_zero,
    "iron-script": iron_script,
    "loop-ten": loop_ten,
    "lumen-cross": lumen_cross,
    "lunar-touchdown": lunar_touchdown,
    "magnet-vault": magnet_vault,
    "memory-mosaic": memory_mosaic,
    "metro-weave": metro_weave,
    "mirror-relic": mirror_relic,
    "night-swarm": night_swarm,
    "number-vault": number_vault,
    "orbit-dodge": orbit_dodge,
    "orbit-draft": orbit_draft,
    "orchard-days": orchard_days,
    "peg-garden": peg_garden,
}
