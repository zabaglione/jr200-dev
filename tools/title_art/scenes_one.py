"""Original pixel-art scenes for the first batch of JR-200 titles."""

from canvas import K, B, R, M, G, C, Y, W


def abyss_signal(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(0, 2, 64, 18, B)
    for x in (6, 17, 31, 49, 59):
        c.poly([(x, 3), (x + 5, 3), (x + 15, 22), (x + 8, 22)], C)
    c.rect(0, 24, 64, 6, M)
    c.poly([(0, 25), (10, 21), (18, 25), (27, 22), (37, 26), (48, 22), (64, 25), (64, 30), (0, 30)], B)
    for x, y, w, h in ((3, 22, 10, 6), (48, 23, 13, 7), (18, 26, 8, 4)):
        c.ellipse(x, y, w, h, G)
    c.poly([(39, 15), (63, 6), (63, 24)], C)
    c.ellipse(18, 12, 27, 10, C)
    c.poly([(41, 14), (49, 10), (49, 21), (41, 18)], Y)
    c.ellipse(24, 7, 12, 8, B)
    c.rect(29, 7, 3, 4, Y)
    c.line(31, 7, 34, 3, W, 2)
    c.ellipse(28, 14, 5, 4, Y)
    c.ellipse(30, 15, 2, 2, K)
    for x, y in ((8, 7), (13, 18), (54, 4), (57, 18), (3, 13)):
        c.ellipse(x, y, 2, 2, W)
    c.poly([(8, 19), (13, 16), (17, 19), (13, 22)], C)


def auction_house(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(4, 2, 56, 22, M)
    for x in (8, 20, 32, 44, 56):
        c.rect(x, 1, 3, 22, R)
        c.rect(x + 3, 1, 2, 22, M)
    c.rect(0, 24, 64, 6, R)
    c.rect(8, 22, 48, 3, Y)
    c.rect(14, 25, 36, 5, M)
    c.poly([(16, 14), (22, 8), (28, 14), (22, 20)], C)
    c.poly([(22, 8), (28, 14), (22, 20), (20, 14)], W)
    c.ellipse(43, 16, 8, 7, Y)
    c.ellipse(45, 18, 2, 2, R)
    c.poly([(30, 8), (34, 4), (46, 16), (42, 20)], Y)
    c.poly([(27, 5), (32, 1), (38, 7), (33, 12)], W)
    c.poly([(38, 15), (43, 10), (48, 15), (43, 20)], R)
    c.line(25, 20, 35, 23, C, 2)
    for x in (5, 12, 52, 59):
        c.pixel(x, 6, Y)
        c.pixel(x, 11, Y)


def brick_pulse(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(2, 2, 60, 20, B)
    colors = (R, M, Y, R, C, M, R, Y, M)
    for row, y in enumerate((4, 8, 12)):
        for col in range(9):
            x = 4 + col * 6
            c.rect(x, y, 5, 3, colors[(row * 2 + col) % len(colors)])
            if row == 1 and col in (2, 6):
                c.rect(x + 1, y + 1, 3, 1, W)
    c.line(3, 20, 60, 20, C)
    c.ellipse(39, 21, 4, 4, W)
    c.ellipse(40, 22, 2, 2, Y)
    c.line(41, 22, 50, 17, C, 2)
    c.line(43, 20, 48, 14, W)
    c.poly([(23, 25), (41, 25), (38, 28), (26, 28)], Y)
    c.rect(0, 29, 64, 1, M)
    c.line(12, 23, 18, 18, R, 2)


def cargo_balance(c):
    c.rect(0, 0, 64, 30, B)
    c.ellipse(46, 3, 10, 10, Y)
    c.rect(0, 18, 64, 12, C)
    for x in (4, 17, 29, 44, 56):
        c.line(x, 22, x + 5, 22, W)
        c.line(x + 3, 26, x + 11, 26, B, 2)
    c.poly([(4, 16), (58, 16), (52, 27), (16, 27), (8, 22)], R)
    c.poly([(2, 15), (59, 15), (57, 18), (4, 18)], Y)
    c.line(5, 19, 55, 19, M, 2)
    c.rect(13, 7, 11, 8, Y)
    c.rect(25, 10, 10, 5, W)
    c.rect(37, 6, 11, 9, Y)
    c.line(18, 8, 18, 14, R)
    c.line(30, 11, 30, 14, R)
    c.line(42, 7, 42, 14, R)
    c.line(4, 13, 59, 10, W, 2)
    c.line(31, 11, 31, 3, W)
    c.poly([(27, 5), (31, 1), (35, 5)], C)


def chain_suit(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(0, 23, 64, 7, M)
    for x, y, color in ((7, 7, W), (19, 4, C), (31, 7, Y)):
        c.poly([(x, y + 2), (x + 3, y), (x + 8, y), (x + 11, y + 3), (x + 11, y + 18), (x + 8, y + 21), (x, y + 21)], color)
        c.poly([(x + 2, y + 2), (x + 8, y + 2), (x + 9, y + 4), (x + 9, y + 18), (x + 2, y + 18)], W)
    c.poly([(11, 11), (14, 8), (17, 11), (14, 15)], R)
    c.poly([(23, 9), (26, 6), (29, 9), (26, 13)], M)
    c.ellipse(35, 10, 3, 3, R)
    c.poly([(15, 16), (18, 19), (15, 22), (12, 19)], Y)
    c.poly([(41, 7), (45, 2), (49, 7), (53, 2), (57, 7), (53, 13), (49, 18), (45, 13)], Y)
    c.poly([(45, 19), (50, 19), (52, 25), (43, 25)], R)
    c.line(8, 27, 58, 27, W, 2)


def chrono_breach(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(0, 0, 64, 30, B)
    c.rect(4, 3, 56, 24, K)
    for x, y, w, h in ((5, 4, 16, 4), (27, 4, 13, 5), (45, 4, 14, 4), (5, 19, 12, 7), (24, 22, 15, 4), (44, 20, 15, 6)):
        c.rect(x, y, w, h, M)
        c.line(x, y, x + w - 1, y, C)
    c.ellipse(6, 8, 9, 9, C)
    c.ellipse(8, 10, 5, 5, B)
    c.line(10, 12, 10, 8, W, 2)
    c.line(10, 12, 13, 13, W)
    c.ellipse(20, 12, 6, 7, Y)
    c.rect(21, 17, 4, 4, Y)
    c.line(25, 14, 31, 14, W, 2)
    c.line(30, 14, 46, 14, R, 2)
    c.ellipse(43, 10, 6, 8, R)
    c.pixel(45, 12, Y)
    c.poly([(53, 10), (59, 14), (53, 18)], G)
    c.rect(52, 9, 2, 11, W)
    for x in (29, 34, 39):
        c.pixel(x, 24, Y)


def circuit_works(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(2, 2, 60, 26, B)
    for y in (6, 12, 18, 24):
        c.line(2, y, 61, y, M)
    for x in (8, 18, 28, 38, 48, 58):
        c.line(x, 2, x, 28, M)
    for x in (7, 23, 39):
        c.line(x, 7, x + 4, 7, C, 2)
        c.line(x, 21, x + 4, 21, C, 2)
        c.line(x + 4, 7, x + 4, 21, C, 2)
        c.poly([(x + 4, 5), (x + 11, 9), (x + 11, 19), (x + 4, 23)], Y)
        c.ellipse(x + 8, 8, 7, 12, B)
        c.ellipse(x + 12, 8, 7, 12, Y)
        c.rect(x + 15, 10, 3, 8, Y)
    c.line(25, 14, 31, 14, W, 2)
    c.line(41, 14, 47, 14, W, 2)
    c.line(57, 14, 61, 14, W, 2)
    c.ellipse(59, 11, 5, 6, G)
    for y in (7, 21):
        c.ellipse(3, y - 2, 4, 4, C)
        c.ellipse(19, y - 2, 4, 4, Y)


def compass_rose(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 0), (40, 0), (36, 6), (30, 8), (29, 14), (21, 18), (17, 26), (0, 30)], G)
    c.poly([(64, 0), (53, 0), (57, 7), (54, 13), (60, 18), (55, 24), (64, 29)], C)
    c.line(0, 26, 20, 23, Y)
    c.ellipse(22, 3, 27, 24, K)
    c.ellipse(24, 5, 23, 20, M)
    c.poly([(35, 5), (39, 13), (35, 15), (31, 13)], W)
    c.poly([(35, 25), (31, 16), (35, 14), (39, 16)], R)
    c.poly([(26, 15), (34, 12), (35, 15), (34, 18)], C)
    c.poly([(44, 8), (48, 5), (52, 8), (48, 11)], Y)
    c.line(47, 8, 56, 17, W, 2)
    c.poly([(52, 18), (57, 18), (56, 22), (51, 22)], R)
    c.poly([(48, 21), (53, 18), (57, 22), (52, 26)], Y)
    c.line(48, 21, 54, 21, W)
    c.line(51, 18, 51, 25, W)
    for x, y in ((8, 6), (12, 14), (5, 20), (27, 24), (59, 5)):
        c.pixel(x, y, W)


def corner_crown(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(3, 2, 58, 26, B)
    for x in range(3, 62, 7):
        c.line(x, 2, x, 27, C)
    for y in range(2, 29, 4):
        c.line(3, y, 60, y, C)
    for x, y in ((7, 5), (14, 5), (21, 9), (28, 13), (35, 9), (42, 17), (49, 21), (56, 25), (14, 17), (21, 21), (42, 5), (56, 9)):
        c.ellipse(x, y, 5, 4, W)
    for x, y in ((7, 21), (14, 9), (28, 5), (35, 17), (49, 9), (56, 17), (21, 13), (42, 25)):
        c.ellipse(x, y, 5, 4, K)
    c.ellipse(27, 11, 9, 8, Y)
    c.poly([(25, 11), (27, 6), (30, 10), (33, 5), (34, 12), (31, 16), (27, 16)], R)
    c.rect(28, 16, 6, 2, Y)


def dice_relic(c):
    c.rect(0, 0, 64, 30, B)
    c.poly([(0, 24), (12, 19), (20, 23), (31, 17), (43, 22), (54, 18), (64, 22), (64, 30), (0, 30)], K)
    c.poly([(23, 15), (29, 5), (35, 3), (41, 8), (43, 17), (37, 22), (27, 21)], M)
    c.ellipse(27, 8, 5, 7, R)
    c.ellipse(35, 8, 5, 7, R)
    c.pixel(29, 11, Y)
    c.pixel(37, 11, Y)
    c.poly([(28, 16), (35, 15), (32, 19)], W)
    c.poly([(31, 4), (35, 0), (39, 5), (35, 8)], Y)
    c.poly([(5, 19), (15, 16), (22, 21), (20, 28), (5, 28)], C)
    c.poly([(5, 19), (12, 15), (22, 19), (15, 23)], W)
    for x, y in ((9, 19), (15, 20), (12, 22), (15, 25)):
        c.ellipse(x, y, 2, 2, R)
    c.poly([(42, 21), (51, 17), (60, 21), (60, 28), (45, 28)], Y)
    c.poly([(42, 21), (50, 17), (60, 21), (52, 25)], W)
    for x, y in ((49, 21), (55, 22), (52, 24)):
        c.ellipse(x, y, 2, 2, M)


def echo_parry(c):
    c.rect(0, 0, 64, 30, K)
    c.poly([(0, 0), (32, 0), (32, 30), (0, 30)], B)
    c.poly([(32, 0), (64, 0), (64, 30), (32, 30)], M)
    c.rect(0, 25, 64, 5, K)
    c.ellipse(8, 7, 8, 8, C)
    c.poly([(7, 15), (17, 14), (22, 24), (5, 24)], C)
    c.line(11, 20, 7, 28, W, 2)
    c.line(17, 20, 21, 28, W, 2)
    c.line(18, 15, 28, 10, W, 2)
    c.ellipse(48, 7, 8, 8, R)
    c.poly([(46, 15), (56, 14), (60, 24), (43, 24)], R)
    c.line(48, 20, 44, 28, W, 2)
    c.line(55, 20, 59, 28, W, 2)
    c.line(46, 15, 36, 10, W, 2)
    c.line(21, 9, 43, 18, Y, 2)
    c.line(42, 9, 20, 18, C, 2)
    c.poly([(28, 8), (32, 4), (35, 10), (32, 15)], Y)
    c.pixel(31, 9, W)
    c.line(5, 5, 13, 3, C)
    c.line(50, 3, 60, 6, R)


def five_forge(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(5, 1, 54, 28, B)
    for x in range(8, 58, 7):
        c.line(x, 3, x, 27, C)
    for y in range(3, 28, 4):
        c.line(8, y, 56, y, C)
    for x, y in ((11, 7), (18, 11), (25, 15), (32, 19), (39, 23)):
        c.ellipse(x - 3, y - 2, 7, 5, M)
        c.ellipse(x - 2, y - 2, 5, 4, Y)
    for x, y in ((18, 7), (25, 11), (32, 15), (46, 19), (11, 23), (46, 7), (53, 11)):
        c.ellipse(x - 3, y - 2, 7, 5, K)
        c.pixel(x, y, W)
    c.line(9, 5, 42, 25, R, 2)
    c.ellipse(47, 3, 7, 7, Y)
    c.poly([(47, 5), (49, 1), (51, 5), (55, 5), (52, 8), (53, 11), (49, 9), (46, 11), (47, 8), (44, 5)], Y)


def frost_steps(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(3, 3, 58, 24, C)
    for x, y, w, h in ((3, 3, 58, 4), (3, 3, 5, 24), (56, 3, 5, 24), (3, 23, 58, 4), (16, 7, 5, 11), (25, 3, 5, 10), (37, 13, 5, 10), (47, 7, 5, 10)):
        c.rect(x, y, w, h, W)
        c.line(x, y, x + w - 1, y, Y)
    c.poly([(10, 19), (14, 15), (18, 19), (14, 23)], Y)
    c.poly([(31, 16), (35, 12), (39, 16), (35, 20)], Y)
    c.poly([(43, 8), (46, 5), (49, 8), (46, 11)], Y)
    c.ellipse(9, 7, 5, 5, C)
    c.poly([(9, 6), (15, 7), (10, 10)], W)
    c.line(13, 9, 23, 14, M, 2)
    c.line(21, 13, 27, 13, W)
    c.pixel(11, 8, Y)
    for x, y in ((10, 4), (35, 6), (52, 19), (29, 25), (49, 4)):
        c.pixel(x, y, W)


def fuse_box(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(5, 2, 54, 26, B)
    c.rect(8, 4, 48, 22, M)
    for x in range(12, 53, 9):
        c.line(x, 7, x, 23, C)
    for y in (8, 13, 18, 23):
        c.line(10, y, 54, y, C)
    for row, y in enumerate((8, 13, 18, 23)):
        for col, x in enumerate((12, 21, 30, 39, 48)):
            c.rect(x - 2, y - 2, 5, 4, Y if (row + col) % 3 else W)
            c.line(x - 1, y - 1, x + 1, y + 1, R)
    c.poly([(44, 4), (47, 0), (50, 4), (54, 2), (52, 7), (47, 9), (43, 7)], Y)
    c.pixel(48, 5, W)
    c.line(4, 10, 8, 10, G, 2)
    c.line(56, 20, 60, 20, G, 2)


def gate_runner(c):
    c.rect(0, 0, 64, 30, B)
    c.rect(0, 8, 64, 22, R)
    c.ellipse(45, 2, 13, 11, Y)
    c.poly([(0, 12), (18, 10), (23, 15), (0, 18)], G)
    c.poly([(64, 11), (47, 10), (42, 15), (64, 18)], G)
    c.poly([(21, 13), (43, 13), (64, 30), (0, 30)], K)
    c.line(21, 13, 0, 30, W)
    c.line(43, 13, 64, 30, W)
    c.poly([(29, 13), (35, 13), (36, 18), (28, 18)], Y)
    c.rect(30, 14, 4, 3, B)
    c.poly([(26, 12), (29, 9), (35, 9), (38, 12), (38, 14), (26, 14)], R)
    c.line(28, 14, 24, 17, R, 2)
    c.line(35, 14, 39, 16, R, 2)
    c.line(31, 14, 29, 18, W, 2)
    c.line(34, 14, 37, 18, W, 2)
    c.poly([(47, 18), (50, 14), (53, 18), (50, 22)], C)
    c.line(31, 20, 31, 23, W, 2)
    c.line(31, 25, 31, 28, Y, 2)
    c.line(31, 29, 31, 30, W, 2)


def glyph_shift(c):
    c.rect(0, 0, 64, 30, K)
    c.rect(2, 3, 60, 24, B)
    for x, y, w, h in ((2, 3, 60, 3), (2, 24, 60, 3), (2, 3, 4, 24), (58, 3, 4, 24), (16, 6, 4, 8), (25, 16, 5, 8), (43, 6, 5, 8)):
        c.rect(x, y, w, h, W)
    c.rect(9, 10, 7, 7, R)
    c.rect(10, 9, 5, 9, Y)
    c.line(10, 12, 14, 12, R, 2)
    c.ellipse(33, 9, 11, 11, M)
    c.ellipse(35, 11, 7, 7, R)
    c.ellipse(36, 13, 2, 2, Y)
    c.ellipse(40, 13, 2, 2, Y)
    c.poly([(50, 10), (55, 15), (50, 20), (45, 15)], G)
    c.poly([(50, 12), (53, 15), (50, 18), (47, 15)], C)
    c.line(16, 20, 25, 20, C, 2)
    c.line(30, 20, 40, 20, C, 2)
    c.pixel(21, 18, Y)
    c.pixel(37, 21, Y)


SCENES = {
    "abyss-signal": abyss_signal,
    "auction-house": auction_house,
    "brick-pulse": brick_pulse,
    "cargo-balance": cargo_balance,
    "chain-suit": chain_suit,
    "chrono-breach": chrono_breach,
    "circuit-works": circuit_works,
    "compass-rose": compass_rose,
    "corner-crown": corner_crown,
    "dice-relic": dice_relic,
    "echo-parry": echo_parry,
    "five-forge": five_forge,
    "frost-steps": frost_steps,
    "fuse-box": fuse_box,
    "gate-runner": gate_runner,
    "glyph-shift": glyph_shift,
}
