"""Builds every food critter (with cute faces), renders previews and exports FBX.

Run:  blender.exe --background --factory-startup --python foods.py -- [Name ...] [--no-render]
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import V  # noqa: E402


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


# --------------------------------------------------------------------------- foods

def apple():
    body = lib.lathe(bmesh.new(), [
        (0, 0.14), (0.3, 0.03), (0.62, 0.06), (0.88, 0.3), (1.0, 0.68), (0.98, 1.02),
        (0.88, 1.32), (0.66, 1.52), (0.36, 1.58), (0.14, 1.5), (0, 1.42),
    ], segs=40)
    bvh = lib.bvh_of(body)
    lib.make("Body", "E8383D", body)
    stem = lib.tube([V(0, 0, 1.38), V(0.02, 0, 1.6), V(0.08, 0, 1.78)], 0.065)
    lib.make("Stem", "6B3E26", stem)
    leaf = lib.ellipsoid(bmesh.new(), V(0.3, 0.02, 1.74), (0.34, 0.15, 0.045),
                         rot("Z", 15) @ rot("Y", -28), 20, 10)
    lib.make("Leaf", "5BBF3A", leaf)
    lib.add_face(bvh, V(0, 0, 0.82), size=0.2, spacing=0.5)


def carrot():
    def grooves(r, z, t):
        return r * (1 - 0.045 * max(0.0, math.sin(z * 15)) ** 3), z
    body = lib.lathe(bmesh.new(), [
        (0, 0), (0.1, 0.06), (0.26, 0.36), (0.44, 0.86), (0.57, 1.32),
        (0.62, 1.6), (0.57, 1.8), (0.38, 1.9), (0, 1.92),
    ], segs=36, deform=grooves)
    bvh = lib.bvh_of(body)
    lib.make("Body", "FF8A1F", body)
    leaves = bmesh.new()
    for ang, tilt in ((0, 0), (120, 28), (240, 28), (60, -24)):
        r = rot("Z", ang) @ rot("X", tilt)
        lib.ellipsoid(leaves, V(0, 0, 1.88) + r @ V(0, 0, 0.34), (0.13, 0.07, 0.38), r, 16, 10)
    lib.make("Leaves", "4CAF3A", leaves)
    lib.add_face(bvh, V(0, 0, 1.28), size=0.17, spacing=0.42)


def donut():
    c = V(0, 0, 0.34)
    dough = lib.torus(bmesh.new(), c, 0.74, 0.36, zscale=0.92)

    def frosting_shape(u, v, p):
        floor = 0.02 + 0.07 * math.sin(6 * u) + 0.045 * math.sin(13 * u + 1.3)
        return V(p.x, p.y, max(p.z, floor))
    frost = lib.torus(bmesh.new(), c, 0.74, 0.39, zscale=0.92, deform=frosting_shape)
    combo = bmesh.new()
    lib.merge(combo, dough.copy())
    lib.merge(combo, frost.copy())
    bvh = lib.bvh_of(combo)
    combo.free()
    lib.make("Dough", "E8A55A", dough)
    lib.make("Frosting", "FF7EB6", frost)

    random.seed(3)
    colors = ("FFF27A", "6FD3FF", "B48CFF")
    sprinkles = {k: bmesh.new() for k in colors}
    for i in range(46):
        u = random.uniform(0, 2 * math.pi)
        v = random.uniform(math.radians(35), math.radians(145))
        # skip the face area (front, -Y)
        if abs(((u + math.pi / 2) + math.pi) % (2 * math.pi) - math.pi) < 0.6:
            continue
        r = 0.74 + 0.4 * math.cos(v)
        p = c + V(r * math.cos(u), r * math.sin(u), 0.4 * math.sin(v) * 0.92)
        n = V(math.cos(v) * math.cos(u), math.cos(v) * math.sin(u), math.sin(v)).normalized()
        frame = n.to_track_quat("Z", "Y").to_matrix() @ rot("Z", random.uniform(0, 180)) @ rot("Y", 90)
        lib.cylinder(sprinkles[colors[i % 3]], p, 0.032, 0.15, frame, segs=8)
    for k, bm in sprinkles.items():
        lib.make(f"Sprinkles{colors.index(k) + 1}", k, bm, angle=80)
    lib.add_face(bvh, V(0, -0.86, 0.45), size=0.16, spacing=0.42, direction=V(0, 1, -0.6))


def taco():
    R = 1.1
    rU = 2 * R / math.pi
    shell = bmesh.new()
    nx, nt = 26, 18
    grid = []
    for i in range(nx + 1):
        x = -0.985 * R + 1.97 * R * i / nx
        w = math.sqrt(max(R * R - x * x, 1e-4))
        row = []
        for j in range(nt + 1):
            t = -w + 2 * w * j / nt
            th = t / rU
            row.append(shell.verts.new((x, rU * math.sin(th), rU * (1 - math.cos(th)))))
        grid.append(row)
    for i in range(nx):
        for j in range(nt):
            shell.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    shell = lib.solidify(shell, 0.08)
    bvh = lib.bvh_of(shell)
    lib.make("Shell", "F2C14E", shell, angle=70)

    meat = bmesh.new()
    for x in (-0.45, 0, 0.45):
        lib.ellipsoid(meat, V(x, 0, 0.42), (0.42, 0.36, 0.26), segs=16, rings=10)
    lib.make("Meat", "8A4A2A", meat)
    lettuce = bmesh.new()
    for k, x in enumerate([-0.72 + 0.18 * i for i in range(9)]):
        y = 0.18 if k % 2 else -0.18
        lib.ellipsoid(lettuce, V(x, y, 0.7 - 0.25 * (x / 0.9) ** 2), (0.17, 0.2, 0.11),
                      rot("X", 25 if y > 0 else -25), 14, 8)
    lib.make("Lettuce", "6CC94A", lettuce)
    tomato = bmesh.new()
    for x, y in ((-0.4, 0.05), (0.08, -0.12), (0.5, 0.1)):
        lib.rounded_box(tomato, V(x, y, 0.78 - 0.25 * (x / 0.9) ** 2), (0.2, 0.2, 0.16), 0.05, 2)
    lib.make("Tomato", "E8403A", tomato)
    cheese = bmesh.new()
    random.seed(5)
    for i in range(7):
        x = random.uniform(-0.6, 0.6)
        z = 0.82 - 0.25 * (x / 0.9) ** 2
        lib.merge(cheese, lib.tube([V(x - 0.12, random.uniform(-0.15, 0.15), z),
                                    V(x + 0.12, random.uniform(-0.15, 0.15), z + 0.04)], 0.035, 2))
    lib.make("Cheese", "FFD23F", cheese)
    lib.add_face(bvh, V(0, 0, 0.36), size=0.16, spacing=0.4)


def sushi():
    rice = lib.rounded_box(bmesh.new(), V(0, 0, 0.32), (1.5, 0.92, 0.62), 0.24, 3)
    for v in rice.verts:  # lumpy rice
        v.co += v.normal * 0.025 * noise.noise(v.co * 7)
    band = lib.rounded_box(bmesh.new(), V(0.5, 0, 0.45), (0.3, 1.0, 0.92), 0.08, 2)
    bvh = lib.bvh_of(rice)
    lib.make("Rice", "FAF7F0", rice)
    lib.make("Nori", "1F3B2A", band)

    def drape(bm, lift=0.0):
        for v in bm.verts:
            v.co.z -= 0.14 * (v.co.x / 0.9) ** 2 - lift
        return bm
    fish = drape(lib.rounded_box(bmesh.new(), V(0, 0, 0.72), (1.78, 1.02, 0.22), 0.1, 3))
    lib.make("Salmon", "FF8C5A", fish)
    stripes = bmesh.new()
    for x in (-0.6, -0.3, 0.0, 0.3, 0.6):
        s = lib.rounded_box(bmesh.new(), V(0, 0, 0), (0.07, 0.98, 0.03), 0.015, 1)
        s.transform(Matrix.Translation(V(x, 0, 0.835 - 0.14 * (x / 0.9) ** 2)) @ Matrix.Rotation(math.radians(18), 4, "Z"))
        lib.merge(stripes, s)
    lib.make("Stripes", "FFE1CF", stripes)
    lib.add_face(bvh, V(-0.08, 0, 0.3), size=0.15, spacing=0.38)


def pizza():
    tip = V(0, -1.0, 0)
    L, half = 1.85, math.radians(26)
    outline = [tip] + [tip + L * V(math.sin(a), math.cos(a), 0)
                       for a in [-half + 2 * half * i / 10 for i in range(11)]]

    def slab(z0, h, inset, bumpy=False):
        bm = bmesh.new()
        cen = sum(outline, V(0, 0, 0)) / len(outline)
        pts = [cen + (p - cen) * inset for p in outline]
        bottom = [bm.verts.new((p.x, p.y, z0)) for p in pts]
        top = [bm.verts.new((p.x, p.y, z0 + h)) for p in pts]
        bm.faces.new(bottom[::-1])
        bm.faces.new(top)
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3, use_grid_fill=True)
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.03, segments=2, affect="EDGES", clamp_overlap=True)
        if bumpy:
            for v in bm.verts:
                if v.co.z < z0 + h * 0.5:
                    v.co.z -= 0.06 * max(0.0, math.sin(v.co.x * 9 + v.co.y * 3))
        return bm
    dough = slab(0, 0.2, 1.0)
    cheese = slab(0.18, 0.08, 0.95, bumpy=True)
    combo = bmesh.new()
    lib.merge(combo, dough.copy())
    lib.merge(combo, cheese.copy())
    bvh = lib.bvh_of(combo)
    combo.free()
    lib.make("Dough", "F2C27A", dough, angle=50)
    lib.make("Cheese", "FFD23F", cheese, angle=50)
    arc = [tip + (L - 0.05) * V(math.sin(a), math.cos(a), 0) + V(0, 0, 0.2)
           for a in [-half * 1.02 + 2.04 * half * i / 16 for i in range(17)]]
    lib.make("Crust", "D99A4E", lib.tube(arc, 0.19, 4))
    pep = bmesh.new()
    for x, y in ((0.0, -0.58), (-0.42, 0.52), (0.4, 0.48), (0.02, 0.62)):
        lib.cylinder(pep, V(x, y, 0.29), 0.16, 0.05, segs=20)
    lib.make("Pepperoni", "D7392E", pep, angle=50)
    lib.add_face(bvh, V(0, 0.05, 0.3), size=0.14, spacing=0.36, direction=V(0, 0.35, -1),
                 down=V(0, -1, 0))


def burger():
    lib.make("BottomBun", "DB8C3D", lib.lathe(bmesh.new(), [
        (0, 0), (0.82, 0), (0.93, 0.02), (0.99, 0.08), (1.02, 0.18),
        (1.01, 0.28), (0.97, 0.35), (0.90, 0.38), (0, 0.38)]))

    def patty_deform(r, z, t):
        n = noise.noise(V(math.cos(t) * 3, math.sin(t) * 3, z * 6))
        return r + 0.035 * n * (r / 1.08), z
    lib.make("Patty", "5C301A", lib.lathe(bmesh.new(), [
        (0, 0.38), (0.96, 0.38), (1.05, 0.41), (1.09, 0.48), (1.10, 0.55),
        (1.08, 0.62), (1.03, 0.665), (0.95, 0.68), (0, 0.68)], deform=patty_deform))
    cheese = bmesh.new()
    bmesh.ops.create_cube(cheese, size=1.0)
    bmesh.ops.subdivide_edges(cheese, edges=cheese.edges[:], cuts=10, use_grid_fill=True)
    for v in cheese.verts:
        x, y, z = v.co.x * 1.92, v.co.y * 1.92, v.co.z * 0.045
        d = math.hypot(x, y)
        v.co = V(x, y, 0.70 + z - 0.9 * max(0.0, d - 0.95) ** 2)
    cheese.transform(Matrix.Rotation(math.radians(45), 4, "Z"))
    lib.make("Cheese", "FFC21F", cheese, angle=35)
    lib.make("Tomato", "E0291F", lib.lathe(bmesh.new(), [
        (0, 0.72), (0.99, 0.72), (1.04, 0.74), (1.06, 0.765), (1.04, 0.79), (0.99, 0.81), (0, 0.81)]))

    def lettuce_deform(r, z, t):
        k = (r / 1.18) ** 3
        return r + 0.05 * math.sin(13 * t + 1.0) * (r / 1.18), z + 0.07 * math.sin(9 * t) * k
    lib.make("Lettuce", "66C233", lib.lathe(bmesh.new(), [
        (0, 0.81), (0.6, 0.81), (1.12, 0.81), (1.18, 0.835), (1.12, 0.86), (0.6, 0.86), (0, 0.86)],
        segs=72, deform=lettuce_deform))
    z0, rad, h = 0.86, 1.03, 0.62
    prof = [(0, z0), (0.88, z0), (0.97, z0 + 0.03), (1.02, z0 + 0.09)]
    for i in range(13):
        a = math.radians(90 * i / 12)
        prof.append((0 if i == 12 else rad * math.cos(a), z0 + 0.1 + h * math.sin(a)))
    top = lib.lathe(bmesh.new(), prof)
    bvh = lib.bvh_of(top)
    lib.make("TopBun", "D6802E", top)
    seeds = bmesh.new()
    golden = math.pi * (3 - math.sqrt(5))
    random.seed(7)
    for i in range(22):
        r = 0.8 * math.sqrt((i + 0.5) / 22)
        t = i * golden
        x, y = r * math.cos(t), r * math.sin(t)
        if y < -0.25 and abs(x) < 0.6:  # keep the face clear
            continue
        z = z0 + 0.1 + h * math.sqrt(max(0.0, 1 - (r / rad) ** 2))
        n = V(x / rad ** 2, y / rad ** 2, (z - z0 - 0.1) / h ** 2).normalized()
        m = (Matrix.Translation((x, y, z + 0.005)) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4()
             @ Matrix.Rotation(random.uniform(0, math.pi), 4, "Z") @ Matrix.Diagonal((0.075, 0.042, 0.028, 1)))
        bmesh.ops.create_icosphere(seeds, subdivisions=1, radius=1.0, matrix=m)
    lib.make("Seeds", "FAEBB8", seeds, angle=80)
    lib.add_face(bvh, V(0, 0, 1.22), size=0.17, spacing=0.44)


def golden_cake():
    def tier(r, z0, hgt):
        return lib.lathe(bmesh.new(), [
            (0, z0), (r - 0.06, z0), (r, z0 + 0.06), (r + 0.01, z0 + hgt * 0.5),
            (r, z0 + hgt - 0.05), (r - 0.06, z0 + hgt), (0, z0 + hgt)], segs=40)

    def frosting(r, top, seed):
        def drip(rr, z, t):
            if z < top - 0.05:
                return rr, z - 0.16 * max(0.0, math.sin(7 * t + seed)) ** 2
            return rr, z
        return lib.lathe(bmesh.new(), [
            (0, top + 0.06), (r + 0.03, top + 0.04), (r + 0.06, top - 0.02),
            (r + 0.06, top - 0.09), (r - 0.04, top - 0.09), (0, top - 0.09)], segs=56, deform=drip)
    low = tier(0.95, 0, 0.72)
    up = tier(0.64, 0.72, 0.56)
    combo = bmesh.new()
    lib.merge(combo, low.copy())
    bvh = lib.bvh_of(combo)
    combo.free()
    cake = bmesh.new()
    lib.merge(cake, low)
    lib.merge(cake, up)
    lib.make("Cake", "F2C230", cake, tag="Foil")
    icing = bmesh.new()
    lib.merge(icing, frosting(0.95, 0.72, 0.0))
    lib.merge(icing, frosting(0.64, 1.28, 1.7))
    lib.make("Icing", "FFF6E0", icing)
    cherry = lib.ellipsoid(bmesh.new(), V(0, 0, 1.5), (0.17, 0.17, 0.16), segs=20, rings=12)
    lib.make("Cherry", "E8213A", cherry)
    lib.make("CherryStem", "4E8A2E", lib.tube([V(0, 0, 1.62), V(0.04, 0, 1.76), V(0.12, 0, 1.84)], 0.025))
    stars = bmesh.new()
    for ang in (20, 160, 215, 325):
        p = V(0.98 * math.cos(math.radians(ang)), 0.98 * math.sin(math.radians(ang)), 0.36)
        lib.ellipsoid(stars, p, (0.07, 0.07, 0.07), segs=10, rings=6)
    lib.make("Gems", "7FE3FF", stars, tag="Neon")
    lib.add_face(bvh, V(0, 0, 0.34), size=0.21, spacing=0.54)


FOODS = {
    "Apple": apple, "Carrot": carrot, "Donut": donut, "Taco": taco,
    "Sushi": sushi, "Pizza": pizza, "Burger": burger, "GoldenCake": golden_cake,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    render = "--no-render" not in args
    names = [a for a in args if not a.startswith("--")] or list(FOODS)
    for name in names:
        lib.reset()
        FOODS[name]()
        lib.summary(name)
        if render:
            lib.render_preview(name)
        if "--icons" in args:
            lib.render_icon(name)
        lib.export_fbx(name)


if __name__ == "__main__":
    main()
