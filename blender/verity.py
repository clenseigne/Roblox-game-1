"""Builds Verity: the grinning yellow smiley ball (smooth, glossy) with hollow dark eye sockets and
a huge grin packed with individual white teeth. The Meadow's wild encounter.

Run:  blender.exe --background --factory-startup --python verity.py -- [--no-render]
Z up, front = -Y, ~4 studs across (the game rescales it).
"""
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
from lib import V  # noqa: E402

R = 2.0  # ball radius
YELLOW, SOCKET, SOCKET_RIM, LIP, GUM, TOOTH = "F2CF14", "2E2A16", "B8960C", "3A2C10", "3E1414", "FBFBF4"


def on_ball(theta: float, phi: float, r: float = R) -> Vector:
    """Point on the ball: theta = left/right angle from the front, phi = up/down angle."""
    return V(r * math.cos(phi) * math.sin(theta), -r * math.cos(phi) * math.cos(theta), R + r * math.sin(phi))


def facing(p: Vector) -> Matrix:
    """Rotation whose Z points out of the ball at p (for flattened ellipsoids hugging the surface)."""
    n = (p - V(0, 0, R)).normalized()
    return n.to_track_quat("Z", "Y").to_matrix()


def verity():
    ball = lib.ellipsoid(bmesh.new(), V(0, 0, R), (R, R, R), segs=48, rings=28)
    lib.make("Body", YELLOW, ball)

    # hollow eye sockets: a dark oval sunk into a slightly darker rim
    rims, sockets = bmesh.new(), bmesh.new()
    for k in (-1, 1):
        p = on_ball(math.radians(17 * k), math.radians(22), R * 0.975)
        lib.ellipsoid(rims, p, (0.36, 0.52, 0.09), facing(p), 20, 10)
        p2 = on_ball(math.radians(17 * k), math.radians(22), R * 1.0)
        lib.ellipsoid(sockets, p2, (0.27, 0.43, 0.08), facing(p2), 20, 10)
    lib.make("SocketRim", SOCKET_RIM, rims)
    lib.make("Sockets", SOCKET, sockets)

    # the grin: a dark mouth crescent, gum line, then a row of teeth top and bottom
    mouth, gums, teeth = bmesh.new(), bmesh.new(), bmesh.new()
    n = 15
    for i in range(n + 1):
        u = i / n
        th = math.radians(-62 + 124 * u)
        curve = (1 - (2 * u - 1) ** 2)  # deepest in the middle
        phi_mid = math.radians(-14 - 10 * curve)
        p = on_ball(th, phi_mid, R * 0.99)
        lib.ellipsoid(mouth, p, (0.26, 0.2 + 0.32 * curve, 0.08), facing(p), 12, 8)
    lib.make("Mouth", GUM, mouth)
    lip = []
    for i in range(25):
        u = i / 24
        th = math.radians(-70 + 140 * u)
        curve = 1 - (2 * u - 1) ** 2
        lip.append(on_ball(th, math.radians(-8 - 3 * curve), R * 1.004))
    lib.make("Lip", LIP, lib.tube(lip, 0.05), angle=80)
    for row, dphi, size in (("top", 0, 1.0), ("bottom", 1, 0.9)):
        count = 13 if row == "top" else 12
        for i in range(count):
            u = (i + 0.5) / count
            th = math.radians(-58 + 116 * u)
            curve = 1 - (2 * u - 1) ** 2
            if row == "top":
                phi = math.radians(-14.5 - 5 * curve)
            else:
                phi = math.radians(-24 - 12 * curve)
            p = on_ball(th, phi, R * 1.0)
            w = 0.3 * size * (0.85 + 0.2 * curve)
            h = 0.42 * size * (0.75 + 0.35 * curve)
            tooth = lib.rounded_box(bmesh.new(), V(0, 0, 0), (w, 0.14, h), 0.05, 2)
            tooth.transform(Matrix.Translation(p) @ facing(p).to_4x4() @ Matrix.Rotation(math.radians(90), 4, "X"))
            lib.merge(teeth, tooth)
    lib.make("Teeth", TOOTH, teeth)
    # shine
    shine = bmesh.new()
    p = on_ball(math.radians(-34), math.radians(50), R * 1.001)
    lib.ellipsoid(shine, p, (0.28, 0.15, 0.03), facing(p), 16, 8)
    lib.make("Shine", "FFF2A6", shine)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    lib.reset()
    verity()
    lib.summary("Verity")
    if "--no-render" not in args:
        lib.render_preview("Verity", size=520, view=V(0.15, -1.6, 0.25), fill=2.4)
        lib.render_preview("Verity_34", size=520, view=V(-0.9, -1.3, 0.4), fill=2.4)
    lib.export_fbx("Verity")


if __name__ == "__main__":
    main()
