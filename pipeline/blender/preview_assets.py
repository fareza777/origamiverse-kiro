"""Renders a contact sheet of the generated GLBs for visual QA.

blender --background --factory-startup --python pipeline/blender/preview_assets.py -- <models_dir> <out.png>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
models_dir, out_png = os.path.abspath(args[0]), os.path.abspath(args[1])
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
only = args[2] if len(args) > 2 else ""
files = sorted(f for f in os.listdir(models_dir) if f.endswith(".glb") and only in f)
cols = 5
for i, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(models_dir, f))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    # Normalize size so every asset is readable in the sheet.
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    bpy.context.view_layer.update()
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                mins = Vector(map(min, mins, w))
                maxs = Vector(map(max, maxs, w))
    size = max((maxs - mins).length, 1e-3)
    s = 1.6 / size
    x, y = (i % cols) * 2.0, -(i // cols) * 2.2
    for r in roots:
        r.scale = (s, s, s)
        r.location = (x - (mins.x + maxs.x) / 2 * s, y - (mins.y + maxs.y) / 2 * s, -mins.z * s)
rows = (len(files) + cols - 1) // cols
bpy.ops.mesh.primitive_plane_add(size=40, location=(4, -2, 0))
ground = bpy.context.object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.93, 0.9, 0.84, 1)
ground.data.materials.append(gm)
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 3.5
so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
scene.collection.objects.link(so)
cam = bpy.data.cameras.new("cam")
cam.type = "ORTHO"
cam.ortho_scale = cols * 2.2
co = bpy.data.objects.new("cam", cam)
scene.collection.objects.link(co)
co.location = (4, -2 - rows * 1.1 + 13, 9)
co.rotation_euler = (math.radians(55), 0, math.radians(180))
scene.camera = co
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.95, 0.93, 0.88, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
scene.world = world
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.resolution_x = 1600
scene.render.resolution_y = 300 + rows * 330
scene.render.filepath = out_png
bpy.ops.render.render(write_still=True)
print("[preview]", out_png)
