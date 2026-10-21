"""Builds the studded voxel T-rex (orange, big open jaw full of teeth, magenta mouth, cream belly,
dark stripes and claws), like the game's key art.

The dino is sculpted from smooth implicit shapes (ellipsoids, tapered capsules, rounded boxes) in
"design units", sampled on a 1-stud voxel grid, and every exposed voxel face (except undersides)
gets a real 3D stud, so the studs show in Roblox whatever the material.

Run:  blender.exe --background --factory-startup --python trex_voxel.py -- [--no-render]
Objects are named <Group>_<HEX> (Body, Head, Jaw, Tail, LegFL/LegFR = legs, LegBL/LegBR = arms);
groups over the Roblox triangle limit are split into numbered slabs (Body1_..., Body2_...).
Z up, front = -Y, 1 unit = 1 stud.
"""
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

SCALE = 1.0  # voxels per design unit (smaller = chunkier, fewer studs)
STUD_R, STUD_H, STUD_SEGS = 0.3, 0.16, 8
MAX_TRIS = 18000  # per object (Roblox's MeshPart limit is 20k)

ORANGE, ORANGE_DARK, CREAM = "F28A1E", "D2601A", "F6DBA0"
MOUTH, TONGUE, TEETH = "B8276E", "EE6AA6", "FFFFFF"
CLAW, EYE, PUPIL = "3B2A22", "FFFFFF", "1E1A22"
NO_STUDS = {TEETH, CLAW, EYE, PUPIL}

JAW_HINGE = Vector((0, -13.5, 22.4))
JAW_OPEN = math.radians(50)


# ---------------------------------------------------------------- implicit shapes (design units)

def ellipsoid(q, c, r):
    d = q - c
    return (d.x / r[0]) ** 2 + (d.y / r[1]) ** 2 + (d.z / r[2]) ** 2 <= 1


def capsule(q, a, b, ra, rb):
    """Tapered capsule; also returns t (0 at a, 1 at b) and the offset from the axis."""
    ab = b - a
    t = max(0.0, min(1.0, (q - a).dot(ab) / ab.length_squared))
    axis = a + ab * t
    off = q - axis
    return off.length <= ra + (rb - ra) * t, t, off


def rbox(q, c, half, r):
    d = q - c
    qx, qy, qz = abs(d.x) - (half[0] - r), abs(d.y) - (half[1] - r), abs(d.z) - (half[2] - r)
    outside = Vector((max(qx, 0), max(qy, 0), max(qz, 0))).length
    return outside + min(max(qx, qy, qz), 0) - r <= 0


def rot_x(v, angle):
    c, s = math.cos(angle), math.sin(angle)
    return Vector((v.x, v.y * c - v.z * s, v.y * s + v.z * c))


def stripe(q):
    """Dark diagonal bands across the back."""
    return (q.y * 0.9 - q.z * 0.35) % 5.2 < 1.5


# ---------------------------------------------------------------- the dino: design point -> (group, color) or None

TORSO_C, TORSO_TILT = Vector((0, 0, 16)), math.radians(12)
TAIL = [((0, 8, 16), 6.0), ((0, 15, 15), 4.6), ((0, 22, 13.5), 3.1), ((0, 29, 12.6), 1.8), ((0, 34.5, 12.3), 0.7)]


def classify(q):
    # ---- small details first (they win over the bodies they sit on)
    for sx in (-1, 1):
        leg = "LegFR" if sx > 0 else "LegFL"
        arm = "LegBR" if sx > 0 else "LegBL"
        for t in (-1, 0, 1):
            if ellipsoid(q, Vector((5.2 * sx + t * 1.8, -5.6, 0.85)), (0.8, 1.0, 0.85)):
                return leg, CLAW
        if ellipsoid(q, Vector((4.9 * sx, -13.8, 12.1)), (0.65, 0.75, 0.65)):
            return arm, CLAW
        if ellipsoid(q, Vector((4.8 * sx, -19.1, 27.3)), (0.6, 0.75, 0.75)):
            return "Head", PUPIL
        if ellipsoid(q, Vector((4.35 * sx, -18.4, 27.2)), (0.75, 1.4, 1.25)):
            return "Head", EYE
        if rbox(q, Vector((3.95 * sx, -18.5, 29.0)), (0.95, 2.3, 0.7), 0.3):
            return "Head", ORANGE_DARK  # angry brow

    # upper teeth hang from the snout's lower edge: down both sides and across the front
    if 20.8 <= q.z <= 22.6:
        for y in [-26.9 + 1.7 * i for i in range(8)]:
            for sx in (-1, 1):
                if abs(q.x - 2.85 * sx) <= 0.55 and abs(q.y - y) <= 0.55:
                    return "Head", TEETH
        if abs(q.y + 27.6) <= 0.55 and any(abs(q.x - x) <= 0.55 for x in (-1.4, 0.0, 1.4)):
            return "Head", TEETH

    # ---- lower jaw, opened around the hinge (evaluated in its closed frame)
    j = rot_x(q - JAW_HINGE, -JAW_OPEN) + JAW_HINGE
    if 22.4 <= j.z <= 24.3:
        for y in [-26.0 + 1.7 * i for i in range(7)]:
            for sx in (-1, 1):
                if abs(j.x - 2.55 * sx) <= 0.55 and abs(j.y - y) <= 0.55:
                    return "Jaw", TEETH
    if ellipsoid(j, Vector((0, -19.6, 22.5)), (1.9, 5.0, 0.8)):
        return "Jaw", TONGUE
    if rbox(j, Vector((0, -20.5, 21.0)), (3.3, 7.0, 1.6), 1.0):
        if j.z < 20.0:
            return "Jaw", CREAM
        if j.z > 21.8 and abs(j.x) < 2.2 and j.y > -26.6:
            return "Jaw", MOUTH
        return "Jaw", ORANGE

    # throat wall at the back of the open mouth
    if rbox(q, Vector((0, -14.4, 21.4)), (2.8, 1.3, 2.2), 0.4):
        return "Head", MOUTH

    # ---- head: big boxy skull + narrower snout; palate magenta, stripes on top, nostrils
    in_skull = rbox(q, Vector((0, -17.0, 26.0)), (4.4, 5.6, 3.6), 1.7)
    in_snout = rbox(q, Vector((0, -23.5, 25.2)), (3.5, 4.6, 2.8), 1.3)
    if in_skull or in_snout:
        if q.z < 23.6 and abs(q.x) < 2.5 and -26.8 < q.y < -13.5:
            return "Head", MOUTH
        if ellipsoid(q, Vector((0, -27.3, 27.4)), (2.2, 0.9, 0.7)) and abs(q.x) > 0.8:
            return "Head", CLAW  # nostrils
        if q.z > 28.4 and stripe(q):
            return "Head", ORANGE_DARK
        return "Head", ORANGE

    # ---- legs (thigh, shin, foot, toes) and tiny arms
    for sx in (-1, 1):
        leg = "LegFR" if sx > 0 else "LegFL"
        x = 5.2 * sx
        parts = [
            ellipsoid(q, Vector((x, 2.0, 12.0)), (3.7, 5.4, 6.7)),
            capsule(q, Vector((x, 0.5, 8.0)), Vector((x, 4.0, 3.2)), 2.9, 1.9)[0],
            capsule(q, Vector((x, 4.0, 3.2)), Vector((x, 0.0, 1.4)), 1.8, 1.5)[0],
        ]
        for t in (-1, 0, 1):
            parts.append(capsule(q, Vector((x, 0.0, 1.2)), Vector((x + t * 1.8, -4.8, 1.0)), 1.1, 0.9)[0])
        if any(parts):
            inner = abs(q.x) < 3.2 and q.z < 13
            return leg, CREAM if inner and q.z > 4 else ORANGE
        arm = "LegBR" if sx > 0 else "LegBL"
        if (capsule(q, Vector((4.9 * sx, -8.0, 14.2)), Vector((5.4 * sx, -10.3, 11.6)), 1.4, 1.15)[0]
                or capsule(q, Vector((5.4 * sx, -10.3, 11.6)), Vector((5.0 * sx, -13.0, 12.4)), 1.15, 0.9)[0]):
            return arm, ORANGE

    # ---- neck, torso, hips: cream underneath, stripes on top
    inside, t, off = capsule(q, Vector((0, -6.5, 19.0)), Vector((0, -12.5, 23.2)), 5.1, 4.1)
    if inside:
        if off.z < -2.2:
            return "Body", CREAM
        return "Body", ORANGE_DARK if off.z > 1.5 and stripe(q) else ORANGE
    local = rot_x(q - TORSO_C, -TORSO_TILT)
    if ellipsoid(local, Vector((0, 0, 0)), (7.2, 10.2, 7.6)) or ellipsoid(q, Vector((0, 4.5, 15.2)), (7.0, 6.4, 7.0)):
        if local.z < -3.2:
            return "Body", CREAM
        return "Body", ORANGE_DARK if local.z > 2.5 and stripe(q) else ORANGE

    # ---- tail
    for (a, ra), (b, rb) in zip(TAIL, TAIL[1:]):
        inside, t, off = capsule(q, Vector(a), Vector(b), ra, rb)
        if inside:
            r = ra + (rb - ra) * t
            if off.z < -0.45 * r:
                return "Tail", CREAM
            return "Tail", ORANGE_DARK if off.z > 0.25 * r and stripe(q) else ORANGE
    return None


# ---------------------------------------------------------------- voxelize + mesh

def voxelize():
    lo = Vector((-10, -30, -1)) * SCALE
    hi = Vector((10, 37, 33)) * SCALE
    grid = {}
    for i in range(math.floor(lo.x), math.ceil(hi.x)):
        for j in range(math.floor(lo.y), math.ceil(hi.y)):
            for k in range(0, math.ceil(hi.z)):
                c = Vector((i + 0.5, j + 0.5, k + 0.5)) / SCALE
                hit = classify(c)
                if hit:
                    grid[(i, j, k)] = hit
    return grid


FACES = [  # (neighbor offset, the 4 corners of that face of a unit cube at the origin)
    ((1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
    ((-1, 0, 0), ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))),
    ((0, 1, 0), ((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))),
    ((0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
    ((0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
    ((0, 0, -1), ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))),
]


def build(grid):
    # faces[(group, color)] = list of (voxel, face index)
    faces = {}
    for v, key in grid.items():
        for fi, (d, _) in enumerate(FACES):
            if (v[0] + d[0], v[1] + d[1], v[2] + d[2]) not in grid:
                faces.setdefault(key, []).append((v, fi))
    stud_tris = STUD_SEGS * 2 + (STUD_SEGS - 2)
    totals = {}
    for (group, color), items in faces.items():
        tris = sum(2 + (stud_tris if color not in NO_STUDS and fi != 5 else 0) for _, fi in items)
        totals[group] = totals.get(group, 0) + tris
    for (group, color), items in sorted(faces.items()):
        chunks = max(1, math.ceil(totals[group] / MAX_TRIS))
        ys = sorted({v[1] for v, _ in items})
        for n in range(chunks):
            name = group if chunks == 1 else f"{group}{n + 1}"
            # slab by y so a split group stays in tidy pieces
            y0 = min(v[1] for (gg, cc), its in faces.items() if gg == group for v, _ in its)
            y1 = max(v[1] for (gg, cc), its in faces.items() if gg == group for v, _ in its) + 1
            a = y0 + (y1 - y0) * n / chunks
            b = y0 + (y1 - y0) * (n + 1) / chunks
            part = [(v, fi) for v, fi in items if a <= v[1] < b]
            if not part:
                continue
            bm = bmesh.new()
            for v, fi in part:
                d, corners = FACES[fi]
                base = Vector(v)
                bm.faces.new([bm.verts.new(base + Vector(c)) for c in corners])
                if color in NO_STUDS or fi == 5:
                    continue
                n_vec = Vector(d)
                center = base + Vector((0.5, 0.5, 0.5)) + n_vec * (0.5 + STUD_H / 2)
                rot = Vector((0, 0, 1)).rotation_difference(n_vec).to_matrix().to_4x4()
                bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=STUD_SEGS,
                                      radius1=STUD_R, radius2=STUD_R, depth=STUD_H,
                                      matrix=Matrix.Translation(center) @ rot)
            bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
            lib.make(name, color, bm, smooth=False)
    return totals


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    lib.reset()
    grid = voxelize()
    totals = build(grid)
    print("VOXELS", len(grid), "TRIS", totals)
    lib.summary("TRex")
    if "--no-render" not in args:
        lib.render_preview("TRex", size=800, view=lib.V(-1.1, -1.3, 0.45))
        lib.render_preview("TRex_side", view=lib.V(-1.6, 0, 0.2))
        lib.render_preview("TRex_front", view=lib.V(-0.35, -1.6, 0.3))
        lib.render_preview("TRex_top", view=lib.V(0.05, 0.2, 1.6))
    lib.export_fbx("TRex")


if __name__ == "__main__":
    main()
