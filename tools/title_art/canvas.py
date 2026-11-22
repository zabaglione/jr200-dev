# SPDX-License-Identifier: BSD-3-Clause
"""Drawing primitives for the JR-200's 4×4-pixel colour quadrants."""

K, B, R, M, G, C, Y, W = range(8)


class Canvas:
    def __init__(self, width=64, height=30):
        self.width = width
        self.height = height
        self.rows = [bytearray(width) for _ in range(height)]

    def pixel(self, x, y, color):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.rows[y][x] = color

    def rect(self, x, y, width, height, color):
        left, right = max(x, 0), min(x + width, self.width)
        if right <= left:
            return
        for row in range(max(y, 0), min(y + height, self.height)):
            self.rows[row][left:right] = bytes([color]) * (right - left)

    def ellipse(self, x, y, width, height, color):
        for row in range(max(y, 0), min(y + height, self.height)):
            dy = (2 * (row - y) + 1 - height) * width
            for column in range(max(x, 0), min(x + width, self.width)):
                dx = (2 * (column - x) + 1 - width) * height
                if dx * dx + dy * dy <= (width * height) ** 2:
                    self.rows[row][column] = color

    def poly(self, points, color):
        edges = list(zip(points, points[1:] + points[:1]))
        for y in range(max(0, min(p[1] for p in points)),
                       min(self.height, max(p[1] for p in points) + 1)):
            scan = y + 0.5
            intersections = sorted(x1 + (scan - y1) * (x2 - x1) / (y2 - y1)
                                   for (x1, y1), (x2, y2) in edges
                                   if min(y1, y2) <= scan < max(y1, y2))
            for left, right in zip(intersections[::2], intersections[1::2]):
                for x in range(max(0, int(left)), min(self.width, int(right) + 1)):
                    if left <= x + 0.5 < right:
                        self.rows[y][x] = color

    def line(self, x1, y1, x2, y2, color, width=1):
        dx, dy = abs(x2 - x1), -abs(y2 - y1)
        sx, sy = (1 if x1 < x2 else -1), (1 if y1 < y2 else -1)
        error = dx + dy
        while True:
            self.rect(x1 - width // 2, y1 - width // 2, width, width, color)
            if (x1, y1) == (x2, y2):
                return
            doubled = 2 * error
            if doubled >= dy:
                error += dy
                x1 += sx
            if doubled <= dx:
                error += dx
                y1 += sy
