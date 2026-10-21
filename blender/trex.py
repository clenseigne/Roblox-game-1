"""Builds a chibi cartoon T-rex in the game's style (soft chubby shapes, kawaii face, pastel colors).

Run:  blender.exe --background --factory-startup --python trex.py -- [--no-render]
Legs and arms are separate objects named like the hippo's legs (LegFL/LegFR = left/right leg,
LegBL/LegBR = left/right arm) so the game's Puppet swings them while it walks.
Z up, front = -Y, 1 unit = 1 stud (the game rescales it).
"""
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import V  # noqa: E402

GREEN, GREEN_DARK, BELLY = "74C65E", "58A84C", "E4F4AE"
SPIKE, CLAW, GUM = "F7B733", "FFFFFF", "4A1E2A"


def rot_to(direction):
    """Rotation taking +Z onto `direction` (for lathed shapes)."""
    return Vector((0, 0, 1)).rotation_difference(direction.normalized()).to_matrix().to_4x4()


def trex():
    # ---------------------------------------------------------------- body + head (one smooth color)
    body = bmesh.new()
    lib.ellipsoid(body, V(0, 0.2, 1.02), (0.84, 0.98, 0.86), Matrix.Rotation(math.radians(-12), 3, "X"), 32, 18)
    lib.ellipsoid(body, V(0, -0.42, 1.55), (0.62, 0.6, 0.62), segs=28, rings=16)  # chest/neck bulge
    lib.ellipsoid(body, V(0, -0.78, 2.05), (0.74, 0.76, 0.62), segs=32, rings=18)  # big round head
    snout = lib.ellipsoid(bmesh.new(), V(0, -1.32, 1.9), (0.6, 0.5, 0.42), segs=28, rings=16)
    lib.merge(body, snout.copy())
    # tail: a fat lathed cone sweeping back and a little up at the tip
    tail_dir = V(0, 1, -0.18)
    lib.lathe(body, [(0, 0), (0.52, 0.02), (0.5, 0.45), (0.4, 0.9), (0.27, 1.3), (0.15, 1.6), (0.06, 1.75), (0, 1.8)],
              segs=28, matrix=Matrix.Translation((0, 0.75, 0.95)) @ rot_to(tail_dir))
    whole = lib.bvh_of(body)
    snout_bvh = lib.bvh_of(snout)
    snout.free()

    # ---------------------------------------------------------------- spikes along the back (before make() frees body)
    spikes = bmesh.new()
    for i, (y, size) in enumerate(((-1.0, 0.16), (-0.62, 0.2), (-0.2, 0.22), (0.25, 0.21), (0.7, 0.18),
                                   (1.12, 0.15), (1.5, 0.11))):
        hit, n = lib._surface(whole, V(0, y, 3.5), V(0, 0, -1))
        tilt = (n + V(0, 0.35, 0)).normalized()  # lean back a little
        lib.lathe(spikes, [(0, -0.05), (size, -0.05), (size * 0.75, size * 0.7), (size * 0.3, size * 1.15), (0, size * 1.3)],
                  segs=16, matrix=Matrix.Translation(hit) @ rot_to(tilt))
    lib.make("Spikes", SPIKE, spikes)
    lib.make("Body", GREEN, body)

    belly = bmesh.new()
    lib.ellipsoid(belly, V(0, -0.38, 0.98), (0.6, 0.52, 0.72), Matrix.Rotation(math.radians(-14), 3, "X"), 28, 14)
    lib.make("Belly", BELLY, belly)

    # ---------------------------------------------------------------- face
    lib.add_face(whole, V(0, -1.2, 2.3), size=0.2, spacing=0.58, direction=V(0, 1, -0.15), smile=False)
    # big toothy grin across the front of the snout, with two little fangs
    pts = []
    for i in range(13):
        a = math.radians(-70 + 140 * i / 12)
        p = V(math.sin(a) * 0.42, -1.6, 1.78 + (1 - math.cos(a)) * 0.16)
        hit, n = lib._surface(snout_bvh, p, V(-math.sin(a) * 0.6, 1, 0))
        pts.append(hit + n * 0.015)
    lib.make("Mouth", GUM, lib.tube(pts, 0.05), angle=80)
    teeth = bmesh.new()
    for x, big in ((-0.3, False), (-0.13, True), (0.13, True), (0.3, False)):
        s = 1.0 if big else 0.75
        hit, n = lib._surface(snout_bvh, V(x, -1.6, 1.74 + abs(x) * 0.25), V(-x * 0.8, 1, 0))
        lib.lathe(teeth, [(0, 0.06 * s), (0.065 * s, 0.06 * s), (0.045 * s, -0.04 * s), (0, -0.11 * s)], segs=12,
                  matrix=Matrix.Translation(hit + n * 0.02))
    lib.make("Teeth", "FFFFFF", teeth)
    nostrils = bmesh.new()
    for k in (-1, 1):
        hit, n = lib._surface(snout_bvh, V(0.17 * k, -1.62, 2.1), V(0, 0.6, -1))
        lib.ellipsoid(nostrils, hit + n * 0.01, (0.06, 0.045, 0.03), n.to_track_quat("Z", "Y").to_matrix(), 12, 8)
    lib.make("Nostrils", "3F7A35", nostrils, angle=80)

    # ---------------------------------------------------------------- legs (chunky thigh + round foot with toe bumps)
    for name, x in (("LegFL", -0.5), ("LegFR", 0.5)):
        leg = bmesh.new()
        lib.ellipsoid(leg, V(x, 0.3, 0.62), (0.34, 0.42, 0.5), segs=24, rings=14)
        lib.ellipsoid(leg, V(x, 0.12, 0.15), (0.33, 0.48, 0.16), segs=24, rings=12)
        for t in (-1, 0, 1):
            lib.ellipsoid(leg, V(x + t * 0.17, -0.3, 0.1), (0.1, 0.12, 0.1), segs=12, rings=8)
        lib.make(name, GREEN_DARK, leg)
    claws = bmesh.new()
    for x in (-0.5, 0.5):
        for t in (-1, 0, 1):
            lib.ellipsoid(claws, V(x + t * 0.17, -0.42, 0.07), (0.055, 0.06, 0.05), segs=10, rings=6)
    lib.make("Claws", CLAW, claws)

    # ---------------------------------------------------------------- tiny arms (bent stubs with a little hand)
    for name, k in (("LegBL", -1), ("LegBR", 1)):
        arm = lib.tube([V(0.42 * k, -0.62, 1.5), V(0.52 * k, -0.86, 1.38), V(0.5 * k, -0.98, 1.22)], 0.09)
        lib.ellipsoid(arm, V(0.5 * k, -1.0, 1.17), (0.1, 0.1, 0.09), segs=12, rings=8)
        lib.make(name, GREEN_DARK, arm)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    lib.reset()
    trex()
    lib.summary("TRexChibi")
    if "--no-render" not in args:
        lib.render_preview("TRexChibi")
        lib.render_preview("TRexChibi_side", view=V(1.6, 0, 0.35))
        lib.render_preview("TRexChibi_front", view=V(0.25, -1.6, 0.35))
        lib.render_preview("TRexChibi_back", view=V(-0.9, 1.2, 0.8))
    if "--icons" in args:
        lib.render_icon("TRexChibi")
    lib.export_fbx("TRexChibi")


if __name__ == "__main__":
    main()
