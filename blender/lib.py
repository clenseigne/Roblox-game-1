"""Shared helpers for building game assets in Blender (Z up, front = -Y, 1 unit = 1 stud).

Every mesh object is named  <Part>_<HEX>[_<Material>]  e.g. "Body_E88A3A" or "Body_E8B830_Foil".
Roblox's importer drops material colors, so the Studio colorizer reads them back from the name.
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(ROOT, "assets")
PREVIEW_DIR = os.path.join(ROOT, "previews")
UP = Vector((0, 0, 1))


def V(x, y, z):
    return Vector((x, y, z))


# --------------------------------------------------------------------------- scene

def reset():
    """Empties the scene and all datablocks so each asset builds from scratch."""
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                 bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.images):
        for block in list(coll):
            if getattr(block, "type", None) in ("RENDER_RESULT", "COMPOSITING"):
                continue
            coll.remove(block)


def hex_to_linear(hexcol):
    rgb = [int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]


def material(hexcol, tag=None):
    name = f"M_{hexcol}_{tag or ''}"
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*hex_to_linear(hexcol), 1)
    bsdf.inputs["Roughness"].default_value = 0.55
    if tag in ("Foil", "Metal"):
        bsdf.inputs["Metallic"].default_value = 0.9
        bsdf.inputs["Roughness"].default_value = 0.25
    if tag == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*hex_to_linear(hexcol), 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return mat


def make(part, hexcol, bm, tag=None, smooth=True, angle=60):
    """Turns a bmesh (world coords) into a named, colored object with its origin at its center."""
    name = f"{part}_{hexcol}" + (f"_{tag}" if tag else "")
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    lo = Vector([min(v.co[i] for v in mesh.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in mesh.vertices) for i in range(3)])
    center = (lo + hi) / 2
    mesh.transform(Matrix.Translation(-center))
    for p in mesh.polygons:
        p.use_smooth = smooth
    if smooth:
        try:
            mesh.set_sharp_from_angle(angle=math.radians(angle))
        except AttributeError:
            pass
    obj = bpy.data.objects.new(name, mesh)
    obj.location = center
    obj.data.materials.append(material(hexcol, tag))
    bpy.context.scene.collection.objects.link(obj)
    return obj


# --------------------------------------------------------------------------- primitives (all add into a bmesh)

def lathe(bm, profile, segs=32, deform=None, matrix=Matrix()):
    """Revolves (radius, z) points around Z. r == 0 points become poles.
    deform(r, z, theta) -> (r, z) perturbs ring vertices."""
    rings = []
    for r, z in profile:
        if r == 0:
            rings.append([bm.verts.new(matrix @ Vector((0, 0, z)))])
            continue
        ring = []
        for i in range(segs):
            t = 2 * math.pi * i / segs
            rr, zz = deform(r, z, t) if deform else (r, z)
            ring.append(bm.verts.new(matrix @ Vector((rr * math.cos(t), rr * math.sin(t), zz))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(segs):
                bm.faces.new((a[0], b[(i + 1) % segs], b[i]))
        elif len(b) == 1:
            for i in range(segs):
                bm.faces.new((a[i], a[(i + 1) % segs], b[0]))
        else:
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return bm


def ellipsoid(bm, center, radii, rot=Matrix(), segs=24, rings=12):
    m = Matrix.Translation(center) @ rot.to_4x4() @ Matrix.Diagonal((*radii, 1))
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=m)
    return bm


def cylinder(bm, center, radius, depth, rot=Matrix(), segs=24, radius2=None):
    m = Matrix.Translation(center) @ rot.to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=depth, matrix=m)
    return bm


def rounded_box(bm, center, size, radius, segments=3):
    """Box with rounded edges, built in its own bmesh then merged in."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    tmp.transform(Matrix.Diagonal((*size, 1)))
    bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=radius,
                    segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    tmp.transform(Matrix.Translation(center))
    merge(bm, tmp)
    return bm


def torus(bm, center, major, minor, segs=40, ring_segs=16, zscale=1.0, deform=None):
    """Torus around Z. deform(u, v, point) -> point lets callers sculpt it."""
    verts = []
    for i in range(segs):
        u = 2 * math.pi * i / segs
        row = []
        for j in range(ring_segs):
            v = 2 * math.pi * j / ring_segs
            r = major + minor * math.cos(v)
            p = Vector((r * math.cos(u), r * math.sin(u), minor * math.sin(v) * zscale))
            if deform:
                p = deform(u, v, p)
            row.append(bm.verts.new(center + p))
        verts.append(row)
    for i in range(segs):
        for j in range(ring_segs):
            a, b = verts[i][j], verts[(i + 1) % segs][j]
            c, d = verts[(i + 1) % segs][(j + 1) % ring_segs], verts[i][(j + 1) % ring_segs]
            bm.faces.new((a, b, c, d))
    return bm


def merge(dst, src):
    """Appends src bmesh geometry into dst and frees src."""
    mesh = bpy.data.meshes.new("_tmp")
    src.to_mesh(mesh)
    src.free()
    dst.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    return dst


def tube(points, radius, resolution=3):
    """Round tube along a polyline (world coords), returned as a bmesh."""
    curve = bpy.data.curves.new("_tube", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for sp, p in zip(spline.points, points):
        sp.co = (*p, 1)
    obj = bpy.data.objects.new("_tube", curve)
    bpy.context.scene.collection.objects.link(obj)
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    bpy.data.meshes.remove(mesh)
    return bm


def solidify(bm, thickness):
    """Gives an open surface thickness (outward along normals)."""
    tmp = bpy.data.meshes.new("_solid")
    bm.to_mesh(tmp)
    bm.free()
    obj = bpy.data.objects.new("_solid", tmp)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("s", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    out = bmesh.new()
    out.from_mesh(mesh)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(tmp)
    bpy.data.meshes.remove(mesh)
    return out


def bvh_of(bm):
    bm.normal_update()  # fresh faces have zero normals until updated
    return BVHTree.FromBMesh(bm)


# --------------------------------------------------------------------------- cute face

def _surface(bvh, point, direction):
    """Casts toward the body from outside; returns (hit, normal)."""
    d = direction.normalized()
    hit, normal, _, _ = bvh.ray_cast(point - d * 20, d)
    if hit is None:
        raise RuntimeError(f"face ray missed the body at {tuple(point)}")
    if normal.dot(d) > 0:
        normal = -normal
    return hit, normal


def _face_frame(n, down):
    """Rotation whose Z is the surface normal and Y points away from the chin."""
    y_axis = (-down - n * n.dot(-down)).normalized()
    return Matrix((y_axis.cross(n), y_axis, n)).transposed()


def add_face(bvh, base, size=0.17, spacing=0.42, direction=Vector((0, 1, 0)),
             side=Vector((1, 0, 0)), down=Vector((0, 0, -1)), smile=True, blush=True, prefix=""):
    """Kawaii face: tall oval eyes with pupils and shine, a small smile, pink cheeks.
    base = point on the body between the eyes; direction = ray toward the body;
    down = which way is 'chin' on the face (for faces on flat tops)."""
    s = size
    eyes, pupils, shines, cheeks = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    side = side.normalized()
    down = down.normalized()
    for k in (-1, 1):
        hit, n = _surface(bvh, base + side * (k * spacing / 2), direction)
        rot = _face_frame(n, down)
        up = rot @ Vector((0, 1, 0))
        right = rot @ Vector((1, 0, 0))
        ellipsoid(eyes, hit + n * (0.12 * s), (0.78 * s, s, 0.5 * s), rot, 20, 12)
        ellipsoid(pupils, hit + n * (0.42 * s) - up * (0.12 * s),
                  (0.56 * s, 0.72 * s, 0.32 * s), rot, 18, 10)
        ellipsoid(shines, hit + n * (0.74 * s) + up * (0.18 * s) + right * (0.16 * s),
                  (0.2 * s, 0.24 * s, 0.1 * s), rot, 10, 6)
        if blush:
            hit2, n2 = _surface(bvh, base + side * (k * (spacing / 2 + 1.05 * s)) + down * (1.05 * s), direction)
            ellipsoid(cheeks, hit2 + n2 * 0.01, (0.62 * s, 0.36 * s, 0.1 * s), _face_frame(n2, down), 14, 8)
    make(prefix + "Eyes", "FFFFFF", eyes, angle=80)
    make(prefix + "Pupils", "241B2F", pupils, angle=80)
    make(prefix + "Shine", "FFFFFF", shines, angle=80, tag="Neon")
    if blush:
        make(prefix + "Blush", "FF8FAB", cheeks, angle=80)
    if smile:
        pts = []
        for i in range(9):
            a = math.radians(-60 + 120 * i / 8)
            # Arc whose ends curl up toward the eyes.
            offset = side * (math.sin(a) * 0.62 * s) + down * (1.2 * s - (1 - math.cos(a)) * 0.55 * s)
            hit, n = _surface(bvh, base + offset, direction)
            pts.append(hit + n * 0.015)
        make(prefix + "Mouth", "4A1E2A", tube(pts, 0.055 * s * 1.6), angle=80)


# --------------------------------------------------------------------------- render + export

def bounds():
    bpy.context.view_layer.update()  # new objects' matrix_world is stale until updated
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def render_icon(name, size=256, view=Vector((0.45, -1.5, 0.75))):
    """Transparent icon for UI (inventory slots, roll reel) -> art/icons/<name>.png"""
    scene = bpy.context.scene
    render_preview(name, size, view, transparent=True,
                   out_dir=os.path.join(ROOT, "art", "icons"), fill=3.0)
    scene.render.film_transparent = False


def render_preview(name, size=640, view=Vector((0.75, -1.5, 0.85)), transparent=False,
                   out_dir=None, fill=3.6):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = transparent
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*hex_to_linear("F2B279"), 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    scene.world = world
    scene.view_settings.view_transform = "Standard"

    lo, hi = bounds()
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    cam.location = center + view.normalized() * radius * fill
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(40), math.radians(-20), math.radians(-25))
    scene.collection.objects.link(sun)

    out_dir = out_dir or PREVIEW_DIR
    os.makedirs(out_dir, exist_ok=True)
    scene.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)


def export_fbx(name):
    os.makedirs(ASSET_DIR, exist_ok=True)
    path = os.path.join(ASSET_DIR, f"{name}.fbx")
    bpy.ops.export_scene.fbx(filepath=path, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_ALL", mesh_smooth_type="FACE")
    return path


def summary(name):
    lo, hi = bounds()
    parts = sorted(o.name for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"ASSET {name} size={tuple(round(v, 2) for v in hi - lo)} parts={parts}")
