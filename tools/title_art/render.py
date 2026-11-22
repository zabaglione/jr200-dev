# SPDX-License-Identifier: BSD-3-Clause
"""Regenerate the title display lists, without an emulator or third-party art."""

import argparse
import json
from itertools import groupby
from pathlib import Path

from canvas import Canvas, K, B, R, M, G, C, Y, W
from scenes_one import SCENES as FIRST_SCENES
from scenes_two import SCENES as SECOND_SCENES
from scenes_three import SCENES as THIRD_SCENES

ROOT = Path(__file__).resolve().parents[2]
SCENES = FIRST_SCENES | SECOND_SCENES | THIRD_SCENES

# Original 3×5 display lettering. Two-letter widths fit beside the longest
# game names; the actual 8×8 game-font marker is also printed in the footer.
LETTERS = {
    'A': '25755', 'B': '65656', 'C': '74447', 'D': '65556', 'E': '74647',
    'F': '74644', 'G': '74557', 'H': '55755', 'I': '72227', 'J': '11157',
    'K': '55655', 'L': '44447', 'M': '57555', 'N': '57775', 'O': '75557',
    'P': '75744', 'Q': '75571', 'R': '75655', 'S': '74717', 'T': '72222',
    'U': '55557', 'V': '55552', 'W': '55575', 'X': '55255', 'Y': '55222',
    'Z': '71247',
}


# Screen layouts are selected per scene: portraits and centered objects get
# side titles; wide tracks, horizons and action scenes keep their full width.
TOP = {
    'auction-house', 'circuit-works', 'frost-steps', 'gate-runner',
    'gravity-well', 'lumen-cross', 'lunar-touchdown', 'memory-mosaic',
    'metro-weave', 'orchard-days', 'pendulum-port', 'phase-pairs',
    'seed-merge', 'star-lance', 'tide-bridge', 'word-foundry',
}
LEFT = {'abyss-signal', 'echo-parry', 'fuse-box', 'iron-script', 'mirror-relic',
        'orbit-dodge', 'prism-trace', 'sigil-deck', 'twenty-one'}
RIGHT = {'dice-relic', 'five-forge', 'loop-ten', 'peg-garden', 'ruin-lexicon',
         'trace-blade'}
OVER_ART = {'compass-rose', 'glyph-shift', 'night-swarm', 'quiet-route',
            'sand-rescue', 'tidal-nets'}
RANKED = {'frost-steps', 'glyph-shift', 'gravity-well', 'magnet-vault'}
DEMO = {'brick-pulse', 'echo-parry', 'gate-runner', 'iron-script',
        'loop-ten', 'lunar-touchdown', 'metro-weave', 'night-swarm',
        'orbit-dodge', 'pendulum-port', 'ribbon-snake', 'sand-rescue',
        'star-lance', 'trace-blade'}


BORDERS = {
    B: {'abyss-signal', 'chrono-breach', 'frost-steps', 'gravity-well',
        'lunar-touchdown', 'night-swarm', 'quiet-route', 'shadow-archive'},
    R: {'brick-pulse', 'echo-parry', 'gate-runner', 'hearth-zero', 'iron-script',
        'star-lance', 'trace-blade'},
    M: {'circuit-works', 'dice-relic', 'glyph-shift', 'loop-ten', 'memory-mosaic',
        'mirror-relic', 'orbit-dodge', 'phase-pairs', 'sigil-deck'},
    G: {'corner-crown', 'five-forge', 'orchard-days', 'peg-garden', 'potion-path',
        'ribbon-snake', 'seed-merge', 'twenty-one'},
    C: {'cargo-balance', 'lumen-cross', 'magnet-vault', 'pendulum-port', 'prism-trace',
        'side-catch', 'tidal-nets', 'tide-bridge'},
    Y: {'auction-house', 'chain-suit', 'compass-rose', 'fuse-box', 'metro-weave',
        'number-vault', 'orbit-draft', 'ruin-lexicon', 'sand-rescue', 'stone-balance',
        'word-foundry'},
}
BORDER_BY_GAME = {game: color for color, games in BORDERS.items() for game in games}


def wordmark(canvas, title, accent, top, left=0, span=64, ink=W):
    width = sum(2 if char == ' ' else 4 for char in title) - 1
    if width > span:
        raise ValueError(f'Wordmark does not fit: {title}')
    x = left + (span - width) // 2
    dots = []
    for char in title:
        if char == ' ':
            x += 2
            continue
        dots.extend((x + dx, top + dy) for dy, bits in enumerate(LETTERS[char])
                    for dx in range(3) if int(bits) & (4 >> dx))
        x += 4
    for dot_x, dot_y in dots:
        canvas.pixel(dot_x + 1, dot_y + 1, accent)
    for dot_x, dot_y in dots:
        canvas.pixel(dot_x, dot_y, ink)


def fit(canvas, illustration, left, top, width, height):
    for row in range(height):
        original = illustration.rows[row * illustration.height // height]
        canvas.rows[top + row][left:left + width] = bytes(
            original[column * illustration.width // width] for column in range(width))


def title_cells(slug, title, scene):
    illustration = Canvas()
    accent = scene(illustration)
    if type(accent) is not int:
        colors = [color for row in illustration.rows for color in row]
        accent = max((B, M, C, Y), key=colors.count)
    screen = Canvas(64, 48)
    ink = Y if accent in (B, M) else W
    if slug == 'side-catch':
        # The opening screen doubles as the playing field.
        fit(screen, illustration, 0, 6, 64, 16)
        wordmark(screen, title, accent, 0)
    elif slug in LEFT or slug in RIGHT:
        art_left, title_left = (27, 0) if slug in LEFT else (0, 37)
        fit(screen, illustration, art_left, 1, 37, 40)
        border = 25 if slug in LEFT else 38
        screen.rect(border, 1, 1, 39, accent)
        for row, word in enumerate(title.split()):
            wordmark(screen, word, accent, 13 + row * 8, title_left, 27, ink)
    elif slug in TOP:
        wordmark(screen, title, accent, 1, ink=ink)
        screen.rect(0, 8, 64, 1, accent)
        fit(screen, illustration, 0, 9, 64, 32)
    elif slug in OVER_ART:
        fit(screen, illustration, 0, 0, 64, 41)
        screen.poly([(0, 29), (63, 27), (64, 37), (0, 40)], K)
        wordmark(screen, title, accent, 31, ink=ink)
    else:
        fit(screen, illustration, 0, 0, 64, 32)
        screen.rect(0, 32, 64, 1, accent)
        wordmark(screen, title, accent, 35, ink=ink)
    cells = []
    for y in range(0, screen.height, 2):
        for x in range(0, screen.width, 2):
            upper, lower = screen.rows[y:y + 2]
            cells.append((upper[x] | (upper[x + 1] << 3),
                          0x80 | lower[x] | (lower[x + 1] << 3)))
    if slug == 'side-catch':
        # Preserve native text attributes for its direct player/score writes.
        cells[32 * 12:] = [(0x20, W)] * (32 * 12)
    elif slug in RANKED:
        put_line(cells, 20, title, 0x0f)
        # The campaign SDK supplies its own controls and password in these rows.
        cells[32 * 21:] = [(0x20, W)] * (32 * 3)
    else:
        # A small native text marker is also used by Web Emulator auto-launch.
        put_line(cells, 21, title, 0x0f)
        controls = ('RETURN START  P DEMO  H HELP' if slug in DEMO
                    else 'RETURN START   OTHER KEY HELP')
        put_line(cells, 23, controls, W)
    return cells


def put_line(cells, row, text, attr):
    start = row * 32
    cells[start:start + 32] = [(ord(char), attr) for char in text.center(32)]


def pack(cells):
    """Store repeated cells as count + pair and changing spans as literal runs."""
    output = bytearray()
    literal = []

    def write_literals():
        if literal:
            output.append(0x80 | len(literal))
            output.extend(value for pair in literal for value in pair)
            literal.clear()

    for pair, run in groupby(cells):
        count = sum(1 for _ in run)
        if count == 1:
            literal.append(pair)
            if len(literal) == 127:
                write_literals()
        else:
            write_literals()
            while count:
                length = min(127, count)
                output.extend((length, *pair))
                count -= length
    write_literals()
    output.append(0)
    return output


def source(project):
    metadata = json.loads((project / 'game.json').read_text())
    title = metadata['title']
    data = bytes([BORDER_BY_GAME[project.name]]) + pack(
        title_cells(project.name, title, SCENES[project.name]))
    rows = [f'; SPDX-License-Identifier: {metadata["license"]}',
            '; Generated by tools/title_art/render.py from original scene artwork.',
            'game_title_art:']
    rows.extend('        .db     ' + ', '.join(f'0x{value:02x}' for value in data[start:start + 16])
                for start in range(0, len(data), 16))
    return '\n'.join([*rows, ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('game', nargs='*', metavar='GAME')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for slug in args.game or sorted(SCENES):
        if slug not in SCENES:
            parser.error(f'Unknown game: {slug}')
        project = ROOT / 'games' / slug
        art = project / 'src/title_art.inc'
        expected = source(project)
        if args.check:
            if art.read_text() != expected:
                parser.exit(1, f'Stale title artwork: {slug}\n')
        else:
            art.write_text(expected)


if __name__ == '__main__':
    main()
