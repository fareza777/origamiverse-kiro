"""Renders the app icons (512x512 Play Store icon + adaptive foreground) from the pipeline's own models.

blender --background --factory-startup --python pipeline/blender/render_icons.py -- <models_dir> <out_dir>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
MODELS, OUT = os.path.abspath(args[0]), os.path.abspath(args[1])
os.makedirs(OUT, exist_ok=True)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def material(name, hexcol, rough=0.8, emission=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexcol), 1)
    b.inputs["Roughness"].default_value = rough
    if emission:
        b.inputs["Emission Color"].default_value = (*srgb(emission), 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def setup(bg_top, bg_bottom):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    bg.inputs[1].default_value = 1.0
    grad = nt.nodes.new("ShaderNodeTexGradient")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*srgb(bg_bottom), 1)
    ramp.color_ramp.elements[1].color = (*srgb(bg_top), 1)
    mapping.inputs["Rotation"].default_value = (0, math.radians(-90), 0)
    nt.links.new(coord.outputs["Window"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    scene.world = world
    # Light: key sun + soft fill.
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = 3.2
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("key", sun)
    so.rotation_euler = (math.radians(48), math.radians(12), math.radians(35))
    scene.collection.objects.link(so)
    fill = bpy.data.lights.new("fill", "AREA")
    fill.energy = 220
    fill.size = 6
    fo = bpy.data.objects.new("fill", fill)
    fo.location = (-4, -5, 5)
    fo.rotation_euler = (math.radians(55), 0, math.radians(-40))
    scene.collection.objects.link(fo)
    return scene


def camera(scene, loc, target, ortho=None, lens=50):
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    co = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co)
    co.location = loc
    d = Vector(target) - Vector(loc)
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
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


def folded_sheet(front, back, angle_deg, size=2.2, y=0.0):
    """A square sheet folded along its diagonal by angle_deg (real geometry, not a texture)."""
    mf = material("front", front, 0.85)
    mb = material("back", back, 0.85)
    h = size / 2
    a = math.radians(angle_deg)
    # Diagonal from (-h, -h) to (h, h); the far triangle rotates up around it.
    axis = Vector((1, 1, 0)).normalized()
    p = Vector((-h, h, 0))
    from mathutils import Matrix
    rot = Matrix.Rotation(-a, 3, axis)
    lifted = rot @ p
    verts = [(-h, -h, 0), (h, -h, 0), (h, h, 0), tuple(lifted)]
    faces = [(0, 1, 2), (0, 2, 3)]
    me = bpy.data.meshes.new("sheet")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("sheet", me)
    bpy.context.scene.collection.objects.link(ob)
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.02
    sol.material_offset = 1
    ob.data.materials.append(mf)
    ob.data.materials.append(mb)
    ob.location.y = y
    return ob


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[icon]", path)


def foldshift_icon():
    scene = setup("f9e3c9", "e8604c")
    scene.render.resolution_x = scene.render.resolution_y = 1024
    sheet = folded_sheet("fbf3e6", "f08a62", 92, 2.6)
    sheet.rotation_euler = (0, 0, math.radians(-45))
    import_glb("kami", (-0.05, -0.15, 0.0), math.radians(205), 2.5)
    import_glb("lantern", (0.62, 0.25, 0.0), 0, 1.05)
    camera(scene, (0.0, -4.3, 1.55), (0.0, 0.2, 0.62), lens=62)
    render(scene, os.path.join(OUT, "foldshift_fg.png"))


def paperverse_icon():
    scene = setup("dfe8ff", "3f4fb8")
    scene.render.resolution_x = scene.render.resolution_y = 1024
    sheet = folded_sheet("f7f3ea", "6b7ff0", 62, 2.4)
    sheet.rotation_euler = (0, 0, math.radians(-45))
    import_glb("crane", (0.0, -0.15, 0.35), math.radians(150), 6.0)
    camera(scene, (1.2, -3.9, 2.4), (0.0, 0.0, 0.62), lens=60)
    render(scene, os.path.join(OUT, "paperverse_fg.png"))

if __name__ == "__main__":
    which = args[2] if len(args) > 2 else "all"
    if which in ("all", "foldshift"):
        foldshift_icon()
    if which in ("all", "paperverse"):
        paperverse_icon()
