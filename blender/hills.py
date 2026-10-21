"""Cartoon hill kit for the hub's sides (low-poly cliffs with chunky grass caps, like the reference).

Run:  blender.exe --background --factory-startup --python hills.py -- [--no-render]
One FBX (assets/HillKit.fbx) holds every piece, laid out in a row along X. Each object is named
<Piece>-<Part>_<HEX>; Studio's BuildHills splits the import into one model per piece:
  CliffA / CliffB / CliffC  faceted brown rock pillar (flat shaded, zigzag ledges) + rounded
                            bright-green grass cap that overhangs it
  Pine                      trunk + four jagged stacked cones
  Mushroom                  stem, red cap, white spots
  Boulder, Pebble           lilac-grey low-poly rocks
  Barrel                    bulged wooden barrel with metal bands
  Fence                     two posts and two rails
  Tuft                      a few yellow-green grass blades
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import V  # noqa: E402

GRASS = "3FE23A"
ROCK = "A9653F"
TRUNK = "6E3F27"
PINE = "4CBF2E"
CAP_RED = "E2342B"
STEM = "F3E7CF"
SPOT = "FFFFFF"
STONE = "A79FB6"
WOOD = "C4874B"
WOOD_DARK = "8E5A2E"
BAND = "8E8E9C"
FENCE = "B4613F"
TUFT = "BCCB4C"


def piece_name(piece, part):
    return f"{piece}-{part}"


# --------------------------------------------------------------------------- cliffs

def outline(rng, n, rx, ry):
    """Irregular convex-ish footprint: n points around an ellipse with jittered radius."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * (i + rng.uniform(-0.18, 0.18)) / n
        k = rng.uniform(0.86, 1.08)
        pts.append((math.cos(a) * rx * k, math.sin(a) * ry * k))
    return pts


def rock_pillar(rng, ox, oy, rx, ry, height, n=9, bands=3):
    """Flat-shaded faceted pillar: rings stacked up, every ring's vertices alternately raised and
    lowered (zigzag ledges) and pushed in/out, tapering slightly upward."""
    bm = bmesh.new()
    base = outline(rng, n, rx, ry)
    rings = []
    levels = bands * 2 + 1
    for li in range(levels):
        t = li / (levels - 1)
        z = t * height
        out = 1.0 - 0.08 * t
        if li % 2 == 1:  # ledge rings bulge out a little
            out += 0.06
        ring = []
        for i, (x, y) in enumerate(base):
            zig = (1 if i % 2 == 0 else -1) * height * 0.07 if 0 < li < levels - 1 else 0
            k = out * rng.uniform(0.95, 1.05)
            ring.append(bm.verts.new(V(ox + x * k, oy + y * k, z + zig)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])  # zigzag quads aren't planar: keep facets clean
    return bm, [(ox + x * 0.92, oy + y * 0.92) for x, y in base]


def grass_cap(foot, top, thick, over=1.16, segs=48):
    """Rounded slab over a footprint: smooth radius around (from the rock's top outline), a soft
    bulging rim, and a gently domed top."""
    n = len(foot)
    cx = sum(p[0] for p in foot) / n
    cy = sum(p[1] for p in foot) / n
    angs = []
    for x, y in foot:
        angs.append((math.atan2(y - cy, x - cx) % (2 * math.pi), math.hypot(x - cx, y - cy)))
    angs.sort()

    def radius(a):
        # periodic smooth interpolation (cosine) between footprint radii, then softened
        for i in range(len(angs)):
            a0, r0 = angs[i]
            a1, r1 = angs[(i + 1) % len(angs)]
            if i == len(angs) - 1:
                a1 += 2 * math.pi
            aa = a if a >= a0 else a + 2 * math.pi
            if a0 <= aa <= a1:
                t = (aa - a0) / (a1 - a0)
                t = (1 - math.cos(t * math.pi)) / 2
                return r0 + (r1 - r0) * t
        return angs[0][1]

    avg = sum(r for _, r in angs) / len(angs)
    # profile: (radius scale, z) from under the rim, round the bulge, over the domed top
    # a chunky, boxy-rounded slab: tucked-in underside, near-vertical sides, rounded top edge, flat top
    prof = [(0.82, -thick * 0.5), (0.96, -thick * 0.44), (1.03, -thick * 0.3), (1.05, -thick * 0.1),
            (1.05, thick * 0.18), (1.02, thick * 0.36), (0.95, thick * 0.47), (0.84, thick * 0.52),
            (0.5, thick * 0.55), (0.0, thick * 0.56)]
    bm = bmesh.new()
    rings = []
    for k, z in prof:
        if k == 0:
            rings.append([bm.verts.new(V(cx, cy, top + z))])
            continue
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            r = (radius(a) * 0.85 + avg * 0.15) * over * k
            ring.append(bm.verts.new(V(cx + math.cos(a) * r, cy + math.sin(a) * r, top + z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(b) == 1:
            for i in range(segs):
                bm.faces.new((a[i], a[(i + 1) % segs], b[0]))
        else:
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    return bm


def cliff(name, seed, x0, pillars):
    """pillars: list of (dx, dy, rx, ry, height). Each gets its own rock and cap."""
    rng = random.Random(seed)
    rocks, caps = bmesh.new(), bmesh.new()
    for dx, dy, rx, ry, h in pillars:
        r, foot = rock_pillar(rng, x0 + dx, dy, rx, ry, h, n=rng.choice((7, 8)), bands=2)
        lib.merge(rocks, r)
        lib.merge(caps, grass_cap(foot, h, thick=min(rx, ry) * 0.8))
    lib.make(piece_name(name, "Rock"), ROCK, rocks, smooth=False)
    lib.make(piece_name(name, "Grass"), GRASS, caps, smooth=True, angle=80)


# --------------------------------------------------------------------------- props

def pine(x0):
    trunk = lib.cylinder(bmesh.new(), V(x0, 0, 2.6), 0.55, 5.2, segs=8, radius2=0.38)
    lib.make(piece_name("Pine", "Trunk"), TRUNK, trunk, smooth=False)
    leaves = bmesh.new()
    tiers = [(3.0, 3.0, 3.4), (5.2, 2.5, 3.0), (7.2, 2.0, 2.6), (9.0, 1.4, 2.6)]
    for z, r, h in tiers:
        segs = 10
        ring = []
        bm = leaves
        tip = bm.verts.new(V(x0, 0, z + h))
        for i in range(segs):
            a = 2 * math.pi * i / segs
            rr = r * (1.0 if i % 2 == 0 else 0.78)  # jagged skirt
            ring.append(bm.verts.new(V(x0 + math.cos(a) * rr, math.sin(a) * rr, z - (0.25 if i % 2 == 0 else 0))))
        inner = [bm.verts.new(V(x0 + math.cos(2 * math.pi * i / segs) * r * 0.35, math.sin(2 * math.pi * i / segs) * r * 0.35, z + 0.1))
                 for i in range(segs)]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((ring[i], ring[j], tip))
            bm.faces.new((ring[j], ring[i], inner[i], inner[j]))
    lib.make(piece_name("Pine", "Leaves"), PINE, leaves, smooth=False)


def mushroom(x0):
    stem = lib.lathe(bmesh.new(), [(0, 0), (0.32, 0), (0.28, 0.6), (0.24, 1.0), (0, 1.0)], segs=12, matrix=Matrix.Translation(V(x0, 0, 0)))
    lib.make(piece_name("Mushroom", "Stem"), STEM, stem)
    cap = lib.lathe(bmesh.new(), [(0.0, 0.85), (0.62, 0.82), (0.8, 0.95), (0.72, 1.25), (0.45, 1.5), (0, 1.58)], segs=20,
                    matrix=Matrix.Translation(V(x0, 0, 0)))
    lib.make(piece_name("Mushroom", "Cap"), CAP_RED, cap)
    spots = bmesh.new()
    for a, h, s in ((0.3, 1.38, 0.13), (2.2, 1.3, 0.11), (4.1, 1.42, 0.1), (5.3, 1.2, 0.09), (1.2, 1.15, 0.08)):
        r = 0.72 if h < 1.3 else 0.5
        p = V(x0 + math.cos(a) * r, math.sin(a) * r, h)
        lib.ellipsoid(spots, p, (s, s, s * 0.5), segs=10, rings=6)
    lib.make(piece_name("Mushroom", "Spots"), SPOT, spots)


def boulder(name, seed, x0, size):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in bm.verts:
        v.co = V(v.co.x * size * rng.uniform(0.85, 1.15), v.co.y * size * 0.9 * rng.uniform(0.85, 1.15),
                 max(v.co.z, -0.35) * size * 0.75 * rng.uniform(0.9, 1.1))
        v.co += V(x0, 0, size * 0.3)
    lib.make(piece_name(name, "Stone"), STONE, bm, smooth=False)


def barrel(x0):
    body = lib.lathe(bmesh.new(), [(0, 0.1), (0.78, 0.1), (0.9, 0.7), (0.95, 1.1), (0.9, 1.5), (0.8, 2.05),
                                   (0.68, 2.05), (0.68, 1.9), (0, 1.9)], segs=16, matrix=Matrix.Translation(V(x0, 0, 0)))
    lib.make(piece_name("Barrel", "Wood"), WOOD, body, smooth=False)
    bands = bmesh.new()
    for z, r in ((0.35, 0.86), (1.7, 0.88)):
        lib.torus(bands, V(x0, 0, z), r, 0.1, segs=16, ring_segs=6, zscale=1.6)
    lib.make(piece_name("Barrel", "Bands"), BAND, bands)
    lid = lib.cylinder(bmesh.new(), V(x0, 0, 1.92), 0.66, 0.06, segs=16)
    lib.make(piece_name("Barrel", "Lid"), WOOD_DARK, lid, smooth=False)


def fence(x0):
    bm = bmesh.new()
    for dx in (-1.6, 1.6):
        lib.rounded_box(bm, V(x0 + dx, 0, 1.0), (0.34, 0.34, 2.0), 0.06, 1)
    for z in (0.75, 1.5):
        lib.rounded_box(bm, V(x0, 0, z), (3.6, 0.2, 0.28), 0.05, 1)
    lib.make(piece_name("Fence", "Wood"), FENCE, bm, smooth=False)


def tuft(x0):
    rng = random.Random(3)
    bm = bmesh.new()
    for i in range(6):
        a = 2 * math.pi * i / 6 + rng.uniform(-0.3, 0.3)
        lean = V(math.cos(a), math.sin(a), 0) * rng.uniform(0.25, 0.5)
        h = rng.uniform(0.9, 1.4)
        base = V(x0 + math.cos(a) * 0.12, math.sin(a) * 0.12, 0)
        side = V(-math.sin(a), math.cos(a), 0) * 0.09
        v1 = bm.verts.new(base - side)
        v2 = bm.verts.new(base + side)
        v3 = bm.verts.new(base + lean + V(0, 0, h))
        bm.faces.new((v1, v2, v3))
    lib.make(piece_name("Tuft", "Blades"), TUFT, lib.solidify(bm, 0.04) or bm, smooth=False)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    lib.reset()
    # the reference's pair: a tall pillar and a shorter one tucked beside it
    cliff("CliffA", 11, 0, [(-6, 0, 9, 8, 24), (8, 2, 7, 6.5, 17)])
    cliff("CliffB", 23, 40, [(0, 0, 11, 9, 20)])
    cliff("CliffC", 37, 80, [(-9, 1, 8, 7, 14), (2, -1, 8, 7.5, 22), (12, 3, 6.5, 6, 30)])
    pine(110)
    mushroom(118)
    boulder("Boulder", 5, 124, 2.2)
    boulder("Pebble", 9, 130, 0.9)
    barrel(135)
    fence(141)
    tuft(147)
    lib.summary("HillKit")
    if "--no-render" not in args:
        lib.render_preview("HillKit", size=1400, view=V(0.2, -1.5, 0.45), fill=1.9)
    path = lib.export_fbx("HillKit")
    print("EXPORTED", path)


if __name__ == "__main__":
    main()
