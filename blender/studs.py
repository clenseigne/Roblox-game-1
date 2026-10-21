"""Generates a seamless 1-stud tile normal map (OpenGL / Y+) for the Studs MaterialVariant.

Run:  python studs.py   ->  assets/studs_normal.png, previews/studs_preview.png
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 256
STUD_R, EDGE = 0.29, 0.035     # stud radius and its rounded rim width, in tile units
SEAM = 0.035                   # shallow groove at tile borders so plates read as blocks
STRENGTH = 2.8


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def height(u, v):
    r = math.hypot(u - 0.5, v - 0.5)
    stud = 1.0 - smoothstep(STUD_R - EDGE, STUD_R + EDGE * 0.4, r)
    # slight dome + inner ring like classic studs
    stud *= 1.0 + 0.04 * (1 - r / STUD_R) - 0.05 * math.exp(-((r - STUD_R * 0.55) / 0.03) ** 2)
    edge = min(u, v, 1 - u, 1 - v)
    seam = -0.25 * (1 - smoothstep(0, SEAM, edge))
    return stud * 0.6 + seam


def main():
    h = [[height((x + 0.5) / SIZE, (y + 0.5) / SIZE) for x in range(SIZE)] for y in range(SIZE)]
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            dx = (h[y][(x + 1) % SIZE] - h[y][(x - 1) % SIZE]) * SIZE / 2 / STRENGTH / 10
            dy = (h[(y + 1) % SIZE][x] - h[(y - 1) % SIZE][x]) * SIZE / 2 / STRENGTH / 10
            nx, ny, nz = -dx, dy, 1.0  # image y grows down; OpenGL normal maps want +Y up
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            px[x, y] = tuple(int((c / ln * 0.5 + 0.5) * 255) for c in (nx, ny, nz))
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    img.save(os.path.join(ROOT, "assets", "studs_normal.png"))

    # quick lit preview of a 6x6 patch
    prev = Image.new("RGB", (SIZE * 2, SIZE * 2))
    pp = prev.load()
    light = (-0.5, 0.6, 0.62)
    for y in range(SIZE * 2):
        for x in range(SIZE * 2):
            r, g, b = px[(x * 3) % SIZE, (y * 3) % SIZE]
            n = [(c / 255 - 0.5) * 2 for c in (r, g, b)]
            d = max(0.0, n[0] * light[0] + n[1] * light[1] + n[2] * light[2])
            pp[x, y] = (int(150 * (0.35 + d)), int(200 * (0.35 + d)), int(90 * (0.35 + d)))
    os.makedirs(os.path.join(ROOT, "previews"), exist_ok=True)
    prev.save(os.path.join(ROOT, "previews", "studs_preview.png"))


if __name__ == "__main__":
    main()
