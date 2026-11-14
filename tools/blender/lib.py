"""Shared helpers for model scripts in maps/models. Run inside Blender (bpy).

Units: 1 Blender unit = 1 stud (GUESS until the first import is measured in Studio).
One object per color: Roblox turns each object into its own MeshPart with its own Color.
"""
import math
import random

import bmesh
import bpy

# House palette for map meshes (sRGB 0-255). Muted, slightly warm, readable from far away.
PALETTE = {
    "stone": (128, 124, 118),
    "stoneDark": (92, 88, 84),
    "wood": (122, 84, 52),
    "woodDark": (84, 56, 36),
    "metal": (70, 74, 82),
    "leaf": (86, 132, 72),
    "leafDark": (60, 100, 56),
    "glow": (255, 206, 120),
    "roof": (150, 70, 56),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    r, g, b = (c / 255 for c in PALETTE[name])
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (r ** 2.2, g ** 2.2, b ** 2.2, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = mat.diffuse_color
        bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def finish(obj, color, bevel=0.0, segments=1):
    """Applies a small bevel (catches light, avoids the blocky AI look), color and smooth-by-angle."""
    obj.data.materials.clear()
    obj.data.materials.append(material(color))
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, loc, color, bevel=0.06, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, color, bevel)


def cylinder(name, radius, depth, loc, color, verts=8, bevel=0.04, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, color, bevel)


def rock(name, radius, loc, color, seed=1, cuts=14, squash=0.7):
    """Chiselled rock: a sphere cut by random planes, like a stone knapped by hand. Big flat
    facets read well from far away and stay cheap. (Noise-displaced spheres look blobby and
    stripy: the generated look. Don't use them for rocks.)"""
    from mathutils import Vector

    random.seed(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(cuts):
        n = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.6, 1))).normalized()
        depth = radius * random.uniform(0.55, 0.85)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=n * depth, plane_no=n, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    for v in bm.verts:
        v.co.z *= squash
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 8])
    bm.to_mesh(obj.data)
    bm.free()
    obj.rotation_euler = (0, 0, random.uniform(0, math.tau))
    bottom = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    obj.location = (loc[0], loc[1], loc[2] - bottom - 0.12 * radius)  # sink into the ground, never float
    return finish(obj, color, bevel=0.04 * radius, segments=1)
