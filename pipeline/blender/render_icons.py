"""Renders the hero art for the launcher icons, splash emblems and Play feature graphics.

Run headless (Blender 4.5 LTS):

  blender --background --factory-startup --python pipeline/blender/render_icons.py -- \
      apps/foldshift/assets/models store/_renders [foldshift|paperverse|all] [--samples N] [--res PX]

Writes transparent-film PNGs (RGBA, default 1024 px, Cycles + OpenImageDenoise) into <out_dir>:

  foldshift_fg.png   Kami the paper fox peeking over a sheet whose front flap is mid-fold (coral back side
                     flipping up toward the camera), lit warm from behind by the paper lantern.
  paperverse_fg.png  A crisp white origami crane with key + rim lighting so every facet reads, rising above a
                     sheet that carries the crane's crease pattern (mountain red #e8463a, valley blue #2f6be0).

Backgrounds are NOT rendered here. tools/compose_icons.py composes these renders onto the brand gradients and
writes every icon size, the adaptive layers, the splash emblems and the feature graphics, so after editing a
scene just run both scripts again. Kami and the lantern come from the game's own GLBs (<models_dir>); the
crane and both paper sheets are built here as icon-specific geometry so the in-game models stay untouched.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _opt(name, default):
    if name in ARGV:
        i = ARGV.index(name)
        val = ARGV[i + 1]
        del ARGV[i:i + 2]
        return type(default)(val)
    return default


SAMPLES = _opt("--samples", 384)
RES = _opt("--res", 1024)
MODELS = os.path.abspath(ARGV[0] if len(ARGV) > 0 else "apps/foldshift/assets/models")
OUT = os.path.abspath(ARGV[1] if len(ARGV) > 1 else "store/_renders")
WHICH = ARGV[2] if len(ARGV) > 2 else "all"
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- helpers

def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def material(name, hexcol, rough=0.8, emission=None, strength=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    if sheen and "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = sheen
    if emission:
        b.inputs["Emission Color"].default_value = (*srgb(emission), 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def use_gpu(scene):
    """Prefer OptiX/CUDA when available, otherwise stay on the CPU."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
            try:
                prefs.compute_device_type = kind
            except TypeError:
                continue
            prefs.get_devices()
            gpus = [d for d in prefs.devices if d.type == kind]
            if gpus:
                for d in prefs.devices:
                    d.use = d.type == kind
                scene.cycles.device = "GPU"
                print("[icon] rendering on", kind, [d.name for d in gpus])
                return
    except Exception as exc:  # noqa: BLE001 - any failure just means CPU rendering
        print("[icon] GPU unavailable:", exc)
    scene.cycles.device = "CPU"


def setup(world_hex, world_strength):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    use_gpu(scene)
    scene.cycles.samples = SAMPLES
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    scene.cycles.max_bounces = 8
    scene.render.resolution_x = scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    # Standard keeps the brand hex colours saturated (AgX washes flat paper colours toward pastel).
    vs = scene.view_settings
    vs.view_transform = "Standard"
    vs.look = "None"
    # The world only lights the scene (film is transparent); its tint matches the composed background.
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*srgb(world_hex), 1)
    bg.inputs["Strength"].default_value = world_strength
    scene.world = world
    return scene


def area_light(name, loc, target, energy, size, hexcol="ffffff", size_y=None):
    lamp = bpy.data.lights.new(name, "AREA")
    lamp.energy = energy
    lamp.color = srgb(hexcol)
    if size_y:
        lamp.shape = "RECTANGLE"
        lamp.size, lamp.size_y = size, size_y
    else:
        lamp.size = size
    ob = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


def point_light(name, loc, energy, hexcol, radius=0.1):
    lamp = bpy.data.lights.new(name, "POINT")
    lamp.energy = energy
    lamp.color = srgb(hexcol)
    lamp.shadow_soft_size = radius
    ob = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    return ob


def camera(scene, loc, target, lens=50.0):
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    co = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = co


def import_glb(name, loc=(0, 0, 0), rot_z=0.0, scale=1.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.rotation_mode = "XYZ"
            o.location = loc
            o.rotation_euler = (0, 0, rot_z)
            o.scale = (scale, scale, scale)
    return new


def mesh(name, verts, faces, mats, face_mats=None, uvs=None, thickness=0.0, back_mat=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(m)
    if face_mats:
        for poly, mi in zip(me.polygons, face_mats):
            poly.material_index = mi
    if uvs:
        layer = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                layer.data[li].uv = uvs[vi]
    for poly in me.polygons:
        poly.use_smooth = False
    if thickness:
        sol = ob.modifiers.new("solid", "SOLIDIFY")
        sol.thickness = thickness
        sol.offset = -1
        if back_mat is not None:
            ob.data.materials.append(back_mat)
            sol.material_offset = len(mats)
            sol.material_offset_rim = 0
    return ob


def frame_subject(scene, margin=0.04):
    """Zoom and shift the camera so every mesh vertex lands inside the frame with `margin` to spare.
    Keeps renders uncropped whatever the scene layout, so compose_icons.py always gets the whole subject."""
    from bpy_extras.object_utils import world_to_camera_view
    cam = scene.camera
    deps = bpy.context.evaluated_depsgraph_get()
    for _ in range(3):
        bpy.context.view_layer.update()
        xs, ys = [], []
        for ob in scene.objects:
            if ob.type != "MESH":
                continue
            ev = ob.evaluated_get(deps)
            for v in ev.to_mesh().vertices:
                p = world_to_camera_view(scene, cam, ev.matrix_world @ v.co)
                xs.append(p.x)
                ys.append(p.y)
            ev.to_mesh_clear()
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        k = (1 - 2 * margin) / max(max(xs) - min(xs), max(ys) - min(ys))
        cam.data.lens *= k
        cam.data.shift_x += (cx - 0.5) * k
        cam.data.shift_y += (cy - 0.5) * k


def render(scene, name):
    frame_subject(scene)
    path = os.path.join(OUT, name)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[icon]", path)


# ---------------------------------------------------------------- FoldShift

FS_FOLD = 110  # flap angle in degrees: 0 = flat, 180 = folded flat onto the island

def foldshift_icon():
    """Kami stands on a paper island whose front corner is mid-fold: the coral back flips up toward camera."""
    scene = setup("ffd2b8", 0.35)
    front = material("paper_front", "fbf4e8", 0.75, sheen=0.3)
    back = material("paper_back", "e8604c", 0.65, sheen=0.3)
    # Diamond sheet (|x| + |y| <= r). The near corner folds up FS_FOLD degrees around the crease y = c, so
    # its back side faces the camera. Real geometry: two faces sharing the crease edge.
    r, d = 1.42, 0.72
    c = -r + d
    a = math.radians(FS_FOLD)
    tip = (0.0, c - d * math.cos(a), d * math.sin(a))
    verts = [(-r, 0, 0), (-d, c, 0), (d, c, 0), (r, 0, 0), (0, r, 0), tip]
    sheet = mesh("sheet", verts, [(0, 1, 2, 3, 4), (1, 5, 2)], [front], thickness=0.035, back_mat=back)
    sheet.rotation_euler = (0, 0, math.radians(54))
    # Kami stands in the middle of the island; turned so the brush tail reads beside the body, not as a
    # third ear, and looking toward the flap that is folding up.
    import_glb("kami", (-0.3, 0.26, 0.0), math.radians(212), 2.8)
    # Lantern behind Kami on the left; its glow rims the fox and warms the paper.
    import_glb("lantern", (-0.98, 0.66, 0.0), math.radians(10), 1.15)
    point_light("lantern_glow", (-0.98, 0.66, 0.36), 75, "ffa646", 0.14)
    # Key from the upper left, warm rim from behind right, soft fill from the front right.
    area_light("key", (-3.4, -4.0, 4.8), (0, 0, 0.5), 420, 2.6, "fff4e8")
    area_light("rim", (2.8, 3.4, 2.8), (0, 0, 0.9), 380, 1.6, "ffc890")
    area_light("fill", (3.2, -4.6, 1.6), (0, 0, 0.5), 90, 4.0, "ffe6d6")
    camera(scene, (0.0, -6.2, 2.7), (0.0, 0.0, 0.62), lens=58)
    render(scene, "foldshift_fg.png")


# ---------------------------------------------------------------- PaperVerse

MOUNTAIN, VALLEY = "e8463a", "2f6be0"


def crane_creases():
    """Bird-base crane crease pattern on the unit square: (p, q, kind) with kind M (mountain) or V (valley)."""
    t = math.tan(math.radians(22.5)) / 2  # 0.2071: where the 22.5 degree kite lines meet the midlines
    segs = [((0, 0), (1, 1), "V"), ((0, 1), (1, 0), "V"),
            ((0.5, 0), (0.5, 1), "M"), ((0, 0.5), (1, 0.5), "M")]
    mids = [(0.5, t), (1 - t, 0.5), (0.5, 1 - t), (t, 0.5)]
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for i, c in enumerate(corners):
        segs.append((c, mids[i], "V"))           # kite folds toward the two neighbouring midline points
        segs.append((c, mids[(i - 1) % 4], "V"))
    for i in range(4):
        segs.append((mids[i], mids[(i + 1) % 4], "M"))  # the petal-fold diamond
    return segs


def crease_texture(size=2048, width=0.012):
    """Paper texture with anti-aliased crease lines, rasterised with numpy (no PIL inside Blender)."""
    import numpy as np
    paper = np.array(srgb("dedcf0") + [1.0], dtype=np.float32)
    cols = {"M": np.array(srgb(MOUNTAIN) + [1.0], np.float32), "V": np.array(srgb(VALLEY) + [1.0], np.float32)}
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    u, v = (xs + 0.5) / size, (ys + 0.5) / size
    img = np.broadcast_to(paper, (size, size, 4)).copy()
    px = 1.0 / size
    for kind in ("V", "M"):  # mountains drawn last so they sit on top where lines cross
        cover = np.zeros((size, size), np.float32)
        for (p, q, k) in crane_creases():
            if k != kind:
                continue
            p, q = np.array(p, np.float32), np.array(q, np.float32)
            d = q - p
            tt = np.clip(((u - p[0]) * d[0] + (v - p[1]) * d[1]) / float(d @ d), 0, 1)
            dist = np.hypot(u - (p[0] + tt * d[0]), v - (p[1] + tt * d[1]))
            cover = np.maximum(cover, np.clip((width / 2 - dist) / px + 0.5, 0, 1))
        img = img * (1 - cover[..., None]) + cols[kind] * cover[..., None]
    # Thin border so the sheet edge reads against the indigo background.
    edge = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    rim = np.clip((0.006 - edge) / px + 0.5, 0, 1)[..., None]
    img = img * (1 - rim * 0.25)
    # Float buffers are scene-linear, which matches the srgb() conversion above.
    image = bpy.data.images.new("creases", size, size, alpha=True, float_buffer=True)
    image.pixels.foreach_set(img.astype(np.float32).ravel())
    return image


def crease_material():
    m = bpy.data.materials.new("crease_paper")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.8
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = crease_texture()
    tex.interpolation = "Cubic"
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    return m


def crease_sheet(size, fold_deg):
    """Square sheet with the crane crease pattern, valley-folded slightly along one diagonal."""
    h = size / 2
    # Vertices: four corners + centre; the (0,1)-(1,0) diagonal is the fold line.
    uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
    pts = [Vector(((x - 0.5) * size, (y - 0.5) * size, 0)) for x, y in uv]
    axis = (pts[1] - pts[3]).normalized()
    rot = Matrix.Rotation(math.radians(fold_deg), 3, axis)
    pts[0] = rot @ pts[0]
    pts[2] = Matrix.Rotation(math.radians(-fold_deg), 3, axis) @ pts[2]
    faces = [(0, 1, 3), (1, 2, 3)]
    back = material("crease_back", "c9cdf2", 0.8)
    ob = mesh("crease_sheet", [tuple(p) for p in pts], faces, [crease_material()], uvs=uv,
              thickness=0.02, back_mat=back)
    return ob


def build_crane(paper):
    """A traditional crane: puffed diamond body, two raised faceted wings, thin neck + head, tail.
    Body runs along +X (head side). Every flap has a ridge so key and rim light give two distinct tones."""
    def wedge(name, base_lo, base_hi, tip, half):
        lo_l, lo_r = Vector(base_lo) + Vector((0, half, 0)), Vector(base_lo) - Vector((0, half, 0))
        hi_l, hi_r = Vector(base_hi) + Vector((0, half * 0.6, 0)), Vector(base_hi) - Vector((0, half * 0.6, 0))
        v = [lo_l, hi_l, lo_r, hi_r, Vector(tip)]
        f = [(0, 1, 4), (3, 2, 4), (2, 0, 4), (1, 3, 4)]
        return mesh(name, [tuple(p) for p in v], f, [paper])

    F, B = (0.34, 0, 0.0), (-0.34, 0, 0.0)
    top, keel = (0, 0, 0.07), (0, 0, -0.22)
    sl, sr = (0, 0.095, -0.03), (0, -0.095, -0.03)
    body = [F, B, top, keel, sl, sr]
    bf = [(0, 2, 5), (2, 1, 5), (0, 4, 2), (2, 4, 1), (0, 5, 3), (5, 1, 3), (0, 3, 4), (3, 1, 4)]
    parts = [mesh("crane_body", body, bf, [paper])]
    parts.append(wedge("crane_neck", (0.14, 0, -0.17), (0.34, 0, 0.0), (0.84, 0, 0.70), 0.05))
    parts.append(wedge("crane_head", (0.78, 0, 0.61), (0.86, 0, 0.72), (1.04, 0, 0.57), 0.035))
    parts.append(wedge("crane_tail", (-0.14, 0, -0.17), (-0.34, 0, 0.0), (-0.96, 0, 0.66), 0.05))
    for s in (1, -1):
        wf, wb = (0.26, 0, 0.04), (-0.24, 0, 0.04)
        ridge = (0.0, s * 0.10, 0.16)
        tip = (-0.10, s * 0.74, 1.02)
        v = [wf, ridge, tip, wb]
        f = [(0, 1, 2), (1, 3, 2)] if s > 0 else [(0, 2, 1), (1, 2, 3)]
        w = mesh("crane_wing", v, f, [paper])
        sol = w.modifiers.new("solid", "SOLIDIFY")
        sol.thickness = 0.008
        parts.append(w)
    root = bpy.data.objects.new("Crane", None)
    bpy.context.scene.collection.objects.link(root)
    for p in parts:
        p.parent = root
    return root


def paperverse_icon():
    """Bright white crane rising above a crease-pattern sheet, lit for crisp facets."""
    scene = setup("3a3a9e", 0.45)
    sheet = crease_sheet(2.2, 10)
    sheet.rotation_euler = (0, 0, math.radians(45 - 10))
    paper = material("crane_paper", "f2f2fa", 0.55, sheen=0.3)
    crane = build_crane(paper)
    crane.location = (0.0, 0.15, 0.62)
    crane.rotation_euler = (0, math.radians(-4), math.radians(-20))
    crane.scale = (1.75, 1.75, 1.75)
    # Key: soft light from the front left so left-facing facets go white and the rest fall to lavender.
    # Rim: small hard lights from behind so wing and neck edges catch a bright line.
    area_light("key", (-4.4, -3.4, 3.0), (0, 0, 0.9), 450, 1.6, "fffaf4")
    area_light("rim", (3.0, 3.8, 2.8), (0, 0, 1.1), 420, 0.8, "d6deff")
    area_light("rim2", (-3.4, 3.2, 2.4), (0, 0, 1.1), 160, 0.8, "f0d2ff")
    camera(scene, (0.4, -6.6, 2.6), (0.0, 0.1, 0.62), lens=56)
    render(scene, "paperverse_fg.png")


if __name__ == "__main__":
    if WHICH in ("all", "foldshift"):
        foldshift_icon()
    if WHICH in ("all", "paperverse"):
        paperverse_icon()
