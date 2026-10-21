"""Builds the Meadow's wild monsters in the same studded voxel style as the T-rex (trex_voxel.py):
Slime, Shroom, Boar and Beetle. Each is sculpted from implicit shapes in voxel units, sampled on a
1-stud grid, and every exposed face (except undersides) gets a stud.

Run:  blender.exe --background --factory-startup --python monsters_voxel.py -- [Name ...] [--no-render]
Parts: Body..., Eyes / Pupils (so the game's Puppet blinks them), LegFL/LegFR/LegBL/LegBR (so it
swings them). Z up, front = -Y.
"""
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
import trex_voxel as tv  # noqa: E402
from trex_voxel import capsule, ellipsoid, rbox  # noqa: E402

EYE, PUPIL, WHITE = tv.EYE, tv.PUPIL, "FFFFFF"
MOUTH = "4A1E2A"


def eyes(q, left, right, r, pupil_off, pupil_r):
    """Big round cartoon eyes: returns ("Pupils"/"Eyes", color) or None."""
    for c in (left, right):
        if ellipsoid(q, c + pupil_off, pupil_r):
            return "Pupils", PUPIL
        if ellipsoid(q, c, r):
            return "Eyes", EYE
    return None


# ---------------------------------------------------------------- monsters (design point -> (group, color))

def slime(q):
    hit = eyes(q, Vector((-1.9, -3.9, 5.6)), Vector((1.9, -3.9, 5.6)), (1.3, 0.9, 1.6), Vector((0, -0.7, -0.2)), (0.8, 0.5, 1.0))
    if hit:
        return hit
    if ellipsoid(q, Vector((0, -4.6, 3.4)), (1.5, 0.7, 0.55)):
        return "Body", MOUTH
    # jelly body: dome with a wider base and a little bobble on top
    if ellipsoid(q, Vector((0, 0, 4.2)), (5.2, 4.8, 4.4)) and q.z >= 0 or ellipsoid(q, Vector((0, 0, 1.2)), (5.8, 5.4, 1.4)):
        if q.z > 6.2 and q.x < -1:
            return "Body", "A8F08A"  # shine
        return "Body", "62C85A" if q.z > 1.4 else "4FA848"
    if ellipsoid(q, Vector((0.6, 0.4, 9.0)), (1.1, 1.1, 1.2)):
        return "Body", "7EDB6E"
    return None


def shroom(q):
    hit = eyes(q, Vector((-1.3, -2.9, 3.9)), Vector((1.3, -2.9, 3.9)), (1.0, 0.75, 1.3), Vector((0, -0.6, -0.15)), (0.6, 0.45, 0.8))
    if hit:
        return hit
    for sx, leg in ((-1, "LegFL"), (1, "LegFR")):
        if ellipsoid(q, Vector((1.8 * sx, -0.8, 0.8)), (1.6, 2.0, 0.9)):
            return leg, "D9C29A"
    # cap: a big red dome with white spots, flat underneath
    if ellipsoid(q, Vector((0, 0, 7.2)), (5.6, 5.6, 3.6)) and q.z >= 6.2:
        spots = [(-3, -3, 9), (2.5, -3.5, 8.5), (0, -1, 10.6), (-4, 1.5, 8.6), (3.6, 2, 8.6), (0, 4, 9.2), (-1.5, -5, 7.4)]
        for sx, sy, sz in spots:
            if (q - Vector((sx, sy, sz))).length < 1.3:
                return "Body", WHITE
        return "Body", "E04848" if q.z > 6.9 else "B83A3A"
    if q.z < 6.6 and q.z > 5.7 and ellipsoid(q, Vector((0, 0, 6.2)), (5.6, 5.6, 0.6)):
        return "Body", "F0D8B0"  # gills under the cap
    if capsule(q, Vector((0, 0, 0.8)), Vector((0, 0, 6.2)), 3.3, 2.9)[0]:
        if ellipsoid(q, Vector((0, -3.1, 2.4)), (0.9, 0.7, 0.5)):
            return "Body", MOUTH
        return "Body", "F2E2C2"
    return None


def boar(q):
    hit = eyes(q, Vector((-1.6, -7.7, 6.5)), Vector((1.6, -7.7, 6.5)), (0.95, 0.75, 1.0), Vector((0, -0.55, 0)), (0.55, 0.45, 0.65))
    if hit:
        return hit
    for sx in (-1, 1):
        if capsule(q, Vector((1.2 * sx, -8.2, 3.9)), Vector((1.7 * sx, -8.9, 5.8)), 0.55, 0.35)[0]:
            return "Body", WHITE  # tusks
        if ellipsoid(q, Vector((2.3 * sx, -4.8, 8.4)), (0.9, 0.6, 1.3)):
            return "Body", "6E4228"  # ears
    for name, x, y in (("LegFL", -2.2, -3.2), ("LegFR", 2.2, -3.2), ("LegBL", -2.2, 4.6), ("LegBR", 2.2, 4.6)):
        inside, t, _ = capsule(q, Vector((x, y, 3.6)), Vector((x, y, 0.5)), 1.3, 1.15)
        if inside:
            return name, "3A2418" if q.z < 1.3 else "8C5634"
    if rbox(q, Vector((0, -8.4, 4.8)), (1.7, 1.0, 1.3), 0.6):
        if abs(q.x) > 0.5 and abs(q.x) < 1.3 and q.y < -9.0 and abs(q.z - 4.8) < 0.6:
            return "Body", "5A2A2A"  # nostrils
        return "Body", "E89A90"
    if ellipsoid(q, Vector((0, -5.6, 5.6)), (3.0, 3.0, 3.0)) or ellipsoid(q, Vector((0, 1.0, 5.2)), (3.8, 6.2, 3.7)):
        if q.z > 7.6 and abs(q.x) < 1.4:
            return "Body", "4E2E1C"  # dark mane stripe
        return "Body", "A26840" if q.z > 3.4 else "C08860"
    if capsule(q, Vector((0, 7.0, 6.0)), Vector((0, 8.0, 7.4)), 0.5, 0.35)[0]:
        return "Body", "8C5634"  # tail
    return None


def beetle(q):
    hit = eyes(q, Vector((-1.3, -6.5, 3.9)), Vector((1.3, -6.5, 3.9)), (0.8, 0.65, 0.85), Vector((0, -0.5, 0)), (0.45, 0.4, 0.5))
    if hit:
        return "Eyes", "FFE14A" if hit[0] == "Eyes" else PUPIL
    if capsule(q, Vector((0, -6.6, 4.0)), Vector((0, -9.2, 7.2)), 1.0, 0.4)[0] or capsule(q, Vector((0, -8.6, 6.4)), Vector((0, -8.0, 7.9)), 0.5, 0.3)[0]:
        return "Body", "26305A"  # horn
    for name, x, y in (("LegFL", -3.6, -2.4), ("LegFR", 3.6, -2.4), ("LegBL", -3.6, 3.6), ("LegBR", 3.6, 3.6)):
        sx = 1 if x > 0 else -1
        if capsule(q, Vector((x - sx * 1.6, y, 2.6)), Vector((x + sx * 0.6, y - 0.4, 0.4)), 0.6, 0.5)[0]:
            return name, "1E2440"
    for sx in (-1, 1):  # middle legs ride with the body
        if capsule(q, Vector((2.0 * sx, 0.6, 2.6)), Vector((4.4 * sx, 0.4, 0.4)), 0.6, 0.5)[0]:
            return "Body", "1E2440"
    if ellipsoid(q, Vector((0, -4.6, 3.6)), (2.4, 2.0, 2.0)):
        return "Body", "2A3466"
    if ellipsoid(q, Vector((0, 1.2, 3.9)), (4.4, 5.6, 3.2)):
        if abs(q.x) < 0.5 and q.z > 4.5:
            return "Body", "1E2A5A"  # wing-case seam
        if q.z > 6.2 and q.x < -1.2:
            return "Body", "9CC4FF"  # shine
        return "Body", "3E6EDC" if q.z > 2.8 else "2C4EA8"
    return None


MONSTERS = {
    "Slime": (slime, (-7, -7, 0), (7, 7, 11)),
    "Shroom": (shroom, (-7, -7, 0), (7, 7, 11)),
    "Boar": (boar, (-5, -11, 0), (5, 10, 10)),
    "Beetle": (beetle, (-6, -11, 0), (6, 8, 9)),
}


def voxelize(classify, lo, hi):
    grid = {}
    for i in range(lo[0], hi[0]):
        for j in range(lo[1], hi[1]):
            for k in range(lo[2], hi[2]):
                hit = classify(Vector((i + 0.5, j + 0.5, k + 0.5)))
                if hit:
                    grid[(i, j, k)] = hit
    return grid


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in args if not a.startswith("--")] or list(MONSTERS)
    for name in names:
        classify, lo, hi = MONSTERS[name]
        lib.reset()
        grid = voxelize(classify, lo, hi)
        tv.build(grid)
        print("VOXELS", name, len(grid))
        lib.summary(name)
        if "--no-render" not in args:
            lib.render_preview(name, size=420, view=lib.V(-1.2, -1.4, 0.7), fill=2.6)
        lib.export_fbx(name)


if __name__ == "__main__":
    main()
