"""OrigamiVerse asset pipeline: builds original low-poly paper props and exports optimized GLB files.

Run headless:
  blender --background --factory-startup --python pipeline/blender/build_assets.py -- <out_dir>

Every model is generated from code (no third-party meshes or textures), flat shaded, with a handful of
materials so the glTF stays tiny and imports cleanly into Godot. Animated models carry glTF node animations
(e.g. Kami's idle tail sway) that Godot plays with AnimationPlayer.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(os.path.dirname(__file__), "out"))
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- helpers

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    scene = bpy.context.scene
    scene.render.fps = 30
    return scene


_MATS = {}


def mat(name, color, rough=0.85, emission=None, strength=0.0, metallic=0.0):
    key = (name, tuple(color), emission and tuple(emission), strength)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    _MATS[key] = m
    return m


def srgb(hexstr):
    h = hexstr.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def mesh_object(name, verts, faces, materials, face_mats=None, parent=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for m in materials:
        obj.data.materials.append(m)
    if face_mats:
        for poly, mi in zip(me.polygons, face_mats):
            poly.material_index = mi
    for poly in me.polygons:
        poly.use_smooth = False
    # Closed shells get outward normals; open pieces (ears, eyes) stay as authored and render double-sided.
    bm = bmesh.new()
    bm.from_mesh(me)
    if all(e.is_manifold for e in bm.edges) and len(bm.faces) > 3:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
    bm.free()
    if parent:
        obj.parent = parent
    return obj


def bm_object(name, bm, materials, parent=None):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for m in materials:
        obj.data.materials.append(m)
    for poly in me.polygons:
        poly.use_smooth = False
    if parent:
        obj.parent = parent
    return obj


def cone(name, radius, height, sides, materials, z=0.0, tip_offset=(0, 0), parent=None, jitter=0.0, seed=0):
    import random
    rnd = random.Random(seed)
    verts = []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        r = radius * (1 + rnd.uniform(-jitter, jitter))
        verts.append((math.cos(a) * r, math.sin(a) * r, z))
    verts.append((tip_offset[0], tip_offset[1], z + height))
    verts.append((0, 0, z))
    tip = sides
    base = sides + 1
    faces = [(i, (i + 1) % sides, tip) for i in range(sides)]
    faces += [((i + 1) % sides, i, base) for i in range(sides)]
    return mesh_object(name, verts, faces, materials, None, parent)


def prism(name, radius, height, sides, materials, z=0.0, parent=None, top_scale=1.0, face_mats=None):
    verts = []
    for ring, (zz, s) in enumerate([(z, 1.0), (z + height, top_scale)]):
        for i in range(sides):
            a = 2 * math.pi * i / sides + math.pi / sides
            verts.append((math.cos(a) * radius * s, math.sin(a) * radius * s, zz))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, 2 * sides)))
    return mesh_object(name, verts, faces, materials, face_mats, parent)


def ico(name, radius, materials, subdiv=1, scale=(1, 1, 1), loc=(0, 0, 0), parent=None, seed=0, jitter=0.12):
    import random
    rnd = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in bm.verts:
        v.co *= 1 + rnd.uniform(-jitter, jitter)
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
        v.co += Vector(loc)
    return bm_object(name, bm, materials, parent)


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent:
        e.parent = parent
    return e


def export(name, animations=False):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_animations=animations,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
        export_lights=False,
        export_cameras=False,
        export_extras=False,
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
    )
    size = os.path.getsize(path)
    print(f"[asset] {name}.glb  {size / 1024:.1f} KB")
    return path


def keyframes(obj, data_path, frames_values, index=-1):
    for f, v in frames_values:
        if index >= 0:
            getattr(obj, data_path)[index] = v
            obj.keyframe_insert(data_path=data_path, index=index, frame=f)
        else:
            setattr(obj, data_path, v)
            obj.keyframe_insert(data_path=data_path, frame=f)
    if obj.animation_data and obj.animation_data.action:
        for fc in _fcurves(obj.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"


def _fcurves(action):
    # Blender 4.4+ layered actions keep fcurves in channelbags; older versions expose action.fcurves.
    if hasattr(action, "fcurves") and len(action.fcurves) > 0:
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


def name_action(obj, action_name):
    if obj.animation_data and obj.animation_data.action:
        obj.animation_data.action.name = action_name


# ---------------------------------------------------------------- models

PAPER = srgb("f6f1e6")


def build_kami():
    """Kami, the origami fox: ridge-folded body, triangular mask face, tall ears, faceted brush tail.
    Modeled facing +Y (Blender), which is Godot's forward (-Z) after the glTF Y-up conversion."""
    reset_scene()
    orange = mat("fox_orange", srgb("ef7b39"), 0.8)
    shade = mat("fox_orange_dark", srgb("d4602a"), 0.8)
    cream = mat("fox_cream", srgb("fcf2df"), 0.85)
    ink = mat("fox_ink", srgb("2a2238"), 0.55)
    root = empty("Kami")
    body = empty("Body", (0, 0, 0), root)
    # Body: triangular prism with the paper ridge on top, tapering toward the tail.
    bv = [(-0.12, 0.10, 0.13), (0.12, 0.10, 0.13), (0.0, 0.12, 0.33),     # front triangle
          (-0.09, -0.17, 0.15), (0.09, -0.17, 0.15), (0.0, -0.17, 0.30)]  # rear triangle
    bf = [(0, 2, 1), (3, 4, 5), (0, 3, 5, 2), (1, 2, 5, 4), (0, 1, 4, 3)]
    mesh_object("Torso", bv, bf, [orange, shade, cream], [2, 1, 0, 1, 2], body)
    # Legs: tapered prisms with ink paws.
    for i, (x, y) in enumerate([(-0.075, 0.06), (0.075, 0.06), (-0.06, -0.13), (0.06, -0.13)]):
        lv = [(x - 0.025, y - 0.02, 0.0), (x + 0.025, y - 0.02, 0.0), (x, y + 0.025, 0.0),
              (x - 0.03, y - 0.025, 0.16), (x + 0.03, y - 0.025, 0.16), (x, y + 0.03, 0.16)]
        lf = [(0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5), (0, 2, 1), (3, 4, 5)]
        mesh_object("Leg%d" % i, lv, lf, [ink, orange], [1, 1, 1, 0, 1], body)
    # Head on a pivot so it can tilt.
    head = empty("Head", (0, 0.12, 0.36), body)
    hv = [(-0.15, 0.0, 0.07), (0.15, 0.0, 0.07),   # 0, 1 temples
          (0.0, 0.03, 0.10),                        # 2 forehead
          (0.0, 0.20, -0.06),                       # 3 snout tip
          (0.0, -0.05, 0.02),                       # 4 back of head
          (-0.07, 0.07, -0.07), (0.07, 0.07, -0.07)]  # 5, 6 jaw
    hf = [(0, 2, 3), (2, 1, 3),         # cheeks (orange)
          (0, 3, 5), (1, 6, 3),         # lower cheeks (cream)
          (5, 3, 6), (0, 5, 4), (1, 4, 6), (5, 6, 4),  # chin and underside
          (0, 4, 2), (2, 4, 1)]         # back of head
    mesh_object("Face", hv, hf, [orange, cream, shade], [0, 0, 1, 1, 1, 2, 2, 1, 2, 2], head)
    mesh_object("Nose", [(-0.022, 0.19, -0.05), (0.022, 0.19, -0.05), (0.0, 0.215, -0.07), (0.0, 0.2, -0.035)],
                [(0, 3, 1), (1, 3, 2), (2, 3, 0), (0, 1, 2)], [ink], None, head)
    for s in (-1, 1):
        # Eyes: thin dark slits on the cheek planes.
        ev = [(s * 0.055, 0.075, 0.055), (s * 0.095, 0.05, 0.05), (s * 0.07, 0.07, 0.072)]
        mesh_object("Eye", ev, [(0, 1, 2) if s < 0 else (0, 2, 1)], [ink], None, head)
        # Ears: folded triangles with a cream inner face and a little thickness.
        ear = [(s * 0.15, 0.0, 0.07), (s * 0.03, 0.02, 0.10), (s * 0.13, -0.01, 0.30), (s * 0.10, -0.05, 0.10)]
        ef = [(0, 2, 1), (1, 2, 3), (3, 2, 0), (0, 1, 3)]
        if s > 0:
            ef = [tuple(reversed(f)) for f in ef]
        mesh_object("Ear", ear, ef, [cream, orange], [0, 1, 1, 1], head)
    # Tail: faceted lozenge with a cream tip, on a pivot that sways.
    tail = empty("Tail", (0, -0.16, 0.23), body)
    tv = [(0.0, 0.0, 0.0),
          (-0.08, -0.14, 0.10), (0.0, -0.13, 0.20), (0.08, -0.14, 0.10), (0.0, -0.15, 0.02),
          (-0.045, -0.25, 0.22), (0.0, -0.24, 0.29), (0.045, -0.25, 0.22), (0.0, -0.26, 0.17),
          (0.0, -0.34, 0.36)]
    tf = [(0, 2, 1), (0, 3, 2), (0, 4, 3), (0, 1, 4),
          (1, 2, 6, 5), (2, 3, 7, 6), (3, 4, 8, 7), (4, 1, 5, 8),
          (5, 6, 9), (6, 7, 9), (7, 8, 9), (8, 5, 9)]
    mesh_object("TailMesh", tv, tf, [orange, shade, cream], [0, 1, 1, 0, 0, 1, 1, 0, 2, 2, 2, 2], tail)
    # Idle: tail sway, gentle breathing and a curious head tilt. 2 s loop at 30 fps.
    keyframes(tail, "rotation_euler", [(1, 0.0), (16, 0.4), (31, -0.4), (46, 0.4), (61, 0.0)], index=2)
    keyframes(body, "location", [(1, 0.0), (31, 0.012), (61, 0.0)], index=2)
    keyframes(head, "rotation_euler", [(1, 0.0), (21, 0.14), (41, -0.08), (61, 0.0)], index=1)
    for o in (tail, body, head):
        name_action(o, "idle")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 61
    export("kami", animations=True)


def build_crane():
    reset_scene()
    white = mat("crane_paper", srgb("fffaf0"), 0.75)
    gold = mat("crane_gold", srgb("f2b440"), 0.4, metallic=0.6)
    root = empty("Crane")
    body = [(0, -0.09, 0.05), (0.035, 0, 0.0), (0, 0.09, 0.05), (-0.035, 0, 0.0), (0, 0, 0.09)]
    mesh_object("Body", body, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)], [white], None, root)
    for s in (-1, 1):
        w = [(0, -0.05, 0.07), (0, 0.06, 0.07), (s * 0.20, 0.0, 0.14)]
        mesh_object("Wing", w, [(0, 1, 2) if s > 0 else (0, 2, 1)], [gold], None, root)
        w2 = [(0, -0.05, 0.07), (0, 0.06, 0.07), (s * 0.20, 0.0, 0.14)]
        mesh_object("WingBack", w2, [(0, 2, 1) if s > 0 else (0, 1, 2)], [white], None, root)
    neck = [(0, -0.07, 0.05), (0.012, -0.06, 0.06), (0, -0.19, 0.17), (-0.012, -0.06, 0.06)]
    mesh_object("Neck", neck, [(0, 1, 2), (1, 3, 2), (3, 0, 2)], [white], None, root)
    head = [(0, -0.19, 0.17), (0.01, -0.18, 0.17), (0, -0.24, 0.15)]
    mesh_object("Head", head, [(0, 1, 2), (0, 2, 1)], [white], None, root)
    tail = [(0, 0.07, 0.05), (0.012, 0.06, 0.06), (0, 0.2, 0.15), (-0.012, 0.06, 0.06)]
    mesh_object("Tail", tail, [(0, 1, 2), (1, 3, 2), (3, 0, 2)], [white], None, root)
    export("crane")


def build_lantern():
    reset_scene()
    paper = mat("lantern_paper", srgb("ffd27a"), 0.7, emission=srgb("ffb347"), strength=2.5)
    wood = mat("lantern_wood", srgb("3b2a3d"), 0.6)
    root = empty("Lantern")
    sides = 8
    rings = [(0.08, 0.13), (0.16, 0.17), (0.30, 0.19), (0.44, 0.17), (0.52, 0.12)]
    verts = []
    for z, r in rings:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((math.cos(a) * r, math.sin(a) * r, z))
    faces = []
    for k in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((k * sides + i, k * sides + j, (k + 1) * sides + j, (k + 1) * sides + i))
    mesh_object("Shade", verts, faces, [paper], None, root)
    prism("Base", 0.14, 0.05, sides, [wood], z=0.04, parent=root)
    prism("Cap", 0.13, 0.05, sides, [wood], z=0.51, parent=root)
    prism("Post", 0.03, 0.04, 6, [wood], z=0.0, parent=root)
    prism("Hook", 0.02, 0.10, 6, [wood], z=0.56, parent=root)
    export("lantern")


def build_seal():
    reset_scene()
    wax = mat("seal_wax", srgb("c8423b"), 0.35)
    root = empty("Seal")
    prism("Disc", 0.24, 0.035, 12, [wax], z=0.0, parent=root, top_scale=0.92)
    prism("Stamp", 0.13, 0.03, 6, [wax], z=0.035, parent=root, top_scale=0.8)
    export("seal")


def build_trees():
    reset_scene()
    leaf = mat("tree_leaf", srgb("6dbb7a"), 0.85)
    leaf2 = mat("tree_leaf_dark", srgb("3f9a6b"), 0.85)
    trunk = mat("tree_trunk", srgb("9a6a4a"), 0.9)
    root = empty("Pine")
    prism("Trunk", 0.06, 0.25, 5, [trunk], parent=root)
    for i, (z, r, h) in enumerate([(0.2, 0.42, 0.55), (0.5, 0.33, 0.5), (0.78, 0.22, 0.42)]):
        cone("Tier%d" % i, r, h, 7, [leaf if i % 2 == 0 else leaf2], z=z, parent=root, jitter=0.08, seed=i)
    export("tree_pine")

    reset_scene()
    leaf = mat("tree_leaf", srgb("8fd27c"), 0.85)
    trunk = mat("tree_trunk", srgb("9a6a4a"), 0.9)
    root = empty("Round")
    prism("Trunk", 0.06, 0.4, 5, [trunk], parent=root, top_scale=0.7)
    ico("Crown", 0.36, [leaf], 1, (1, 1, 0.9), (0, 0, 0.62), root, seed=3)
    ico("Crown2", 0.22, [leaf], 1, (1, 1, 0.9), (0.18, 0.08, 0.48), root, seed=5)
    export("tree_round")

    reset_scene()
    blossom = mat("blossom", srgb("f5a8c0"), 0.85)
    trunk = mat("tree_trunk_dark", srgb("6b4a5a"), 0.9)
    root = empty("Blossom")
    prism("Trunk", 0.05, 0.45, 5, [trunk], parent=root, top_scale=0.6)
    ico("Crown", 0.32, [blossom], 1, (1.1, 1.1, 0.75), (0, 0, 0.62), root, seed=8, jitter=0.18)
    export("tree_blossom")


def build_rocks_clouds_mountains():
    reset_scene()
    rock = mat("rock", srgb("b9b2a6"), 0.95)
    root = empty("Rock")
    ico("Rock", 0.3, [rock], 1, (1.2, 1.0, 0.6), (0, 0, 0.12), root, seed=11, jitter=0.2)
    export("rock")

    reset_scene()
    cloud = mat("cloud", srgb("ffffff"), 0.95)
    root = empty("Cloud")
    for i, (x, y, z, r) in enumerate([(0, 0, 0, 0.5), (0.5, 0.1, -0.05, 0.38), (-0.5, -0.05, -0.08, 0.34), (0.15, -0.2, 0.15, 0.32)]):
        ico("Puff%d" % i, r, [cloud], 1, (1, 1, 0.65), (x, y, z), root, seed=20 + i, jitter=0.1)
    export("cloud")

    reset_scene()
    m1 = mat("mountain", srgb("a7b8d8"), 0.95)
    snow = mat("snow", srgb("f3f4fb"), 0.9)
    root = empty("Mountain")
    cone("Peak", 2.2, 3.2, 7, [m1], parent=root, jitter=0.15, seed=31, tip_offset=(0.2, 0.1))
    cone("Snow", 0.75, 1.1, 7, [snow], z=2.15, parent=root, jitter=0.1, seed=32, tip_offset=(0.2, 0.1))
    export("mountain")


def build_night_props():
    reset_scene()
    skin = mat("pumpkin", srgb("f28c28"), 0.7, emission=srgb("ff9a2e"), strength=0.4)
    glow = mat("pumpkin_glow", srgb("ffe08a"), 0.5, emission=srgb("ffcf5a"), strength=4.0)
    stem = mat("stem", srgb("4c7a3a"), 0.8)
    root = empty("Pumpkin")
    body = ico("Body", 0.28, [skin], 1, (1.15, 1.15, 0.85), (0, 0, 0.24), root, seed=41, jitter=0.05)
    prism("Stem", 0.04, 0.12, 5, [stem], z=0.45, parent=root, top_scale=0.6)
    # Carved face: glowing triangles just in front of the body.
    face = [(-0.15, -0.29, 0.30), (-0.05, -0.30, 0.30), (-0.10, -0.30, 0.38),
            (0.05, -0.30, 0.30), (0.15, -0.29, 0.30), (0.10, -0.30, 0.38),
            (-0.16, -0.28, 0.17), (0.16, -0.28, 0.17), (0.0, -0.30, 0.10)]
    mesh_object("Face", face, [(0, 2, 1), (3, 5, 4), (6, 8, 7)], [glow], None, root)
    export("pumpkin")

    reset_scene()
    ghost_m = mat("ghost", srgb("f4f1ff"), 0.6, emission=srgb("cfc6ff"), strength=0.6)
    eye = mat("ghost_eye", srgb("2a2238"), 0.5)
    root = empty("Ghost")
    sides = 10
    verts = [(0, 0, 0.62)]
    for z, r in [(0.48, 0.16), (0.30, 0.22), (0.10, 0.24)]:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((math.cos(a) * r, math.sin(a) * r, z))
    for i in range(sides):
        a = 2 * math.pi * (i + 0.5) / sides
        verts.append((math.cos(a) * 0.25, math.sin(a) * 0.25, -0.02 if i % 2 else 0.06))
    faces = [(0, 1 + i, 1 + (i + 1) % sides) for i in range(sides)]
    for k in range(2):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((1 + k * sides + i, 1 + (k + 1) * sides + i, 1 + (k + 1) * sides + j, 1 + k * sides + j))
    hem = 1 + 3 * sides
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((1 + 2 * sides + i, hem + i, 1 + 2 * sides + j))
    mesh_object("Sheet", verts, faces, [ghost_m], None, root)
    for s in (-1, 1):
        ev = [(s * 0.06, -0.205, 0.40), (s * 0.10, -0.19, 0.40), (s * 0.08, -0.2, 0.46)]
        mesh_object("Eye", ev, [(0, 2, 1) if s > 0 else (0, 1, 2)], [eye], None, root)
    keyframes(root, "location", [(1, 0.0), (31, 0.08), (61, 0.0)], index=2)
    name_action(root, "float")
    bpy.context.scene.frame_end = 61
    export("ghost", animations=True)


def build_flowers():
    reset_scene()
    petal = mat("petal", srgb("f7d35c"), 0.8)
    petal2 = mat("petal_pink", srgb("f08aa6"), 0.8)
    stemm = mat("stem", srgb("4c9a5a"), 0.8)
    root = empty("Flowers")
    import random
    rnd = random.Random(5)
    for k in range(5):
        x, y = rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25)
        h = rnd.uniform(0.12, 0.22)
        mesh_object("Stem", [(x - 0.008, y, 0), (x + 0.008, y, 0), (x, y, h)], [(0, 1, 2), (0, 2, 1)], [stemm], None, root)
        m = petal if k % 2 == 0 else petal2
        pv = [(x, y, h)]
        for i in range(5):
            a = 2 * math.pi * i / 5
            pv.append((x + math.cos(a) * 0.05, y + math.sin(a) * 0.05, h + 0.01))
        mesh_object("Bloom", pv, [(0, 1 + i, 1 + (i + 1) % 5) for i in range(5)] + [(0, 1 + (i + 1) % 5, 1 + i) for i in range(5)], [m], None, root)
    export("flowers")


if __name__ == "__main__":
    build_kami()
    build_crane()
    build_lantern()
    build_seal()
    build_trees()
    build_rocks_clouds_mountains()
    build_night_props()
    build_flowers()
    print("[asset] done ->", OUT)
