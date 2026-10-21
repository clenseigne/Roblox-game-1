"""Builds the hippo pet, the cookie coin and the slot-machine lever.

Run:  blender.exe --background --factory-startup --python props.py -- [Name ...] [--no-render]
Hippo parts are separate objects (Body, LegFL/FR/BL/BR, Tail, Ears...) so Studio can animate them.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import V  # noqa: E402

LAVENDER, LAV_DARK, LAV_LIGHT, SNOUT = "9C8FD6", "8576C4", "CFC6F2", "B9ADEB"


def hippo():
    body = bmesh.new()
    lib.ellipsoid(body, V(0, 0.2, 0.98), (0.98, 1.18, 0.82), segs=32, rings=18)  # belly-heavy torso
    lib.ellipsoid(body, V(0, -0.82, 1.32), (0.74, 0.62, 0.6), segs=28, rings=16)  # head
    snout = lib.ellipsoid(bmesh.new(), V(0, -1.32, 1.1), (0.74, 0.46, 0.44), segs=28, rings=16)
    combo = bmesh.new()
    lib.merge(combo, body.copy())
    lib.merge(combo, snout.copy())
    bvh = lib.bvh_of(combo)
    snout_bvh = lib.bvh_of(snout)
    combo.free()
    lib.make("Body", LAVENDER, body)
    lib.make("Snout", SNOUT, snout)
    belly = lib.ellipsoid(bmesh.new(), V(0, -0.12, 0.74), (0.8, 0.9, 0.58), segs=28, rings=14)
    lib.make("Belly", LAV_LIGHT, belly)

    nostrils = bmesh.new()
    for k in (-1, 1):
        hit, n = lib._surface(snout_bvh, V(0.24 * k, -1.3, 1.36), V(0, 0.55, -1))
        lib.ellipsoid(nostrils, hit + n * 0.01, (0.085, 0.06, 0.04), n.to_track_quat("Z", "Y").to_matrix(), 12, 8)
    lib.make("Nostrils", "4B3C7A", nostrils, angle=80)
    teeth = bmesh.new()
    for k in (-1, 1):
        lib.rounded_box(teeth, V(0.2 * k, -1.66, 0.78), (0.13, 0.08, 0.15), 0.035, 2)
    lib.make("Teeth", "FFFFFF", teeth)
    ears = bmesh.new()
    for k in (-1, 1):
        lib.ellipsoid(ears, V(0.44 * k, -0.7, 1.86), (0.15, 0.09, 0.17), lib.Matrix.Rotation(math.radians(20 * k), 3, "Y"), 14, 8)
    lib.make("Ears", LAV_DARK, ears)

    for name, x, y in (("LegFL", -0.56, -0.48), ("LegFR", 0.56, -0.48),
                       ("LegBL", -0.56, 0.78), ("LegBR", 0.56, 0.78)):
        leg = lib.lathe(bmesh.new(), [
            (0, 0), (0.22, 0), (0.29, 0.05), (0.31, 0.15), (0.3, 0.55), (0, 0.55)],
            segs=20, matrix=Matrix.Translation((x, y, 0)))
        lib.make(name, LAV_DARK, leg)
    tail = lib.tube([V(0, 1.3, 1.05), V(0, 1.45, 0.98), V(0, 1.52, 0.86)], 0.06)
    lib.ellipsoid(tail, V(0, 1.53, 0.8), (0.09, 0.09, 0.11), segs=10, rings=6)
    lib.make("Tail", LAV_DARK, tail)
    lib.add_face(bvh, V(0, -1.0, 1.55), size=0.17, spacing=0.5, direction=V(0, 1, -0.25), smile=False)


def coin():
    """Chunky gold coin standing on its edge (spins around Z in game) with a little
    embossed burger on both faces."""
    stand = Matrix.Rotation(math.radians(90), 4, "X")  # faces point along +-Y
    face = lib.lathe(bmesh.new(), [
        (0, -0.1), (0.5, -0.1), (0.5, 0.1), (0, 0.1)], segs=48, matrix=stand)
    lib.make("Gold", "FFD84A", face)
    rim = lib.torus(bmesh.new(), V(0, 0, 0), 0.52, 0.11, segs=48, ring_segs=14, zscale=1.15)
    rim.transform(stand)
    lib.make("Rim", "F7BE2A", rim)

    bun, patty, lettuce = bmesh.new(), bmesh.new(), bmesh.new()
    for side in (-1, 1):
        y = 0.1 * side
        lib.ellipsoid(bun, V(0, y, 0.11), (0.27, 0.05, 0.15), segs=20, rings=10)       # top bun dome
        lib.ellipsoid(bun, V(0, y, -0.2), (0.25, 0.045, 0.06), segs=18, rings=8)       # bottom bun
        lib.ellipsoid(patty, V(0, y, -0.09), (0.28, 0.05, 0.07), segs=18, rings=8)
        for i in range(7):
            x = -0.24 + 0.08 * i
            lib.ellipsoid(lettuce, V(x, y, 0.0 - 0.015 * (i % 2)), (0.055, 0.052, 0.04), segs=10, rings=6)
    lib.make("Bun", "D6802E", bun)
    lib.make("Patty", "5C301A", patty)
    lib.make("Lettuce", "66C233", lettuce)
    shine = bmesh.new()
    for side in (-1, 1):
        lib.ellipsoid(shine, V(-0.3, 0.115 * side, 0.3), (0.05, 0.02, 0.1),
                      Matrix.Rotation(math.radians(-40), 3, "Y"), 10, 6)
    lib.make("Shine", "FFF6C8", shine, tag="Neon")


def lever():
    lib.make("Rod", "C9C9D6", lib.tube([V(0, 0, 0), V(0, 0, 1.5)], 0.08), tag="Metal")
    lib.make("Knob", "E8213A", lib.ellipsoid(bmesh.new(), V(0, 0, 1.62), (0.24, 0.24, 0.24), segs=20, rings=12))
    lib.make("Hub", "4B3C7A", lib.ellipsoid(bmesh.new(), V(0, 0, 0), (0.22, 0.22, 0.22), segs=16, rings=10))


PROPS = {"Hippo": hippo, "Coin": coin, "Lever": lever}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    render = "--no-render" not in args
    names = [a for a in args if not a.startswith("--")] or list(PROPS)
    for name in names:
        lib.reset()
        PROPS[name]()
        lib.summary(name)
        if render:
            lib.render_preview(name)
        if "--icons" in args:
            lib.render_icon(name)
        lib.export_fbx(name)


if __name__ == "__main__":
    main()
