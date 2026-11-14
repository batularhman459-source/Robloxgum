"""Renders a preview of an optimised model: shaded view next to a wireframe view, so the triangle
density is visible. blender -b <model.blend> -P tools/blender/render.py -- <out.png>
"""
import math
import sys

import bpy
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
scene = bpy.context.scene
meshes = [o for o in scene.objects if o.type == "MESH"]
lo = Vector((min(min((o.matrix_world @ Vector(c)).x for c in o.bound_box) for o in meshes),
             min(min((o.matrix_world @ Vector(c)).y for c in o.bound_box) for o in meshes),
             min(min((o.matrix_world @ Vector(c)).z for c in o.bound_box) for o in meshes)))
hi = Vector((max(max((o.matrix_world @ Vector(c)).x for c in o.bound_box) for o in meshes),
             max(max((o.matrix_world @ Vector(c)).y for c in o.bound_box) for o in meshes),
             max(max((o.matrix_world @ Vector(c)).z for c in o.bound_box) for o in meshes)))
center, size = (lo + hi) / 2, (hi - lo).length

cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.lens = 50
cam = bpy.data.objects.new("PreviewCam", cam_data)
scene.collection.objects.link(cam)
direction = Vector((1, -1.2, 0.75)).normalized()
cam.location = center + direction * size * 1.9
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam

scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x, scene.render.resolution_y = 700, 700
scene.render.film_transparent = False
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "MATERIAL"
shading.show_cavity = True
shading.show_object_outline = True
shading.show_shadows = True
scene.world = scene.world or bpy.data.worlds.new("World")
scene.world.color = (0.18, 0.2, 0.26)

base = out.replace(".png", "")
scene.render.filepath = base + "_shaded.png"
bpy.ops.render.render(write_still=True)

# Wireframe pass: same camera, wireframe modifier so every triangle shows.
for o in meshes:
    mod = o.modifiers.new("Wire", "WIREFRAME")
    mod.thickness = size * 0.002
    mod.use_replace = True
shading.color_type = "SINGLE"
shading.single_color = (0.85, 0.9, 1.0)
scene.render.filepath = base + "_wire.png"
bpy.ops.render.render(write_still=True)
print("RENDERED " + base)
