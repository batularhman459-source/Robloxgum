"""Optimise and check a model before it may be imported into Roblox.

blender -b --factory-startup -P tools/blender/check.py -- <model.py> <out.fbx> <budgets.toml>

1. Runs the model script (its build() makes the objects, BUDGET names the budget class).
2. Per object: apply transforms, weld close vertices, delete loose geometry, recalc normals.
3. If the total is over budget: decimate everything by the same ratio, then re-count.
4. Measures defects (non-manifold edges, zero-area faces, missing UVs, materials per object).
5. Exports the optimised FBX and prints one line: MESHREPORT {json}. Exit code 1 = refused.
"""
import importlib.util
import json
import sys
import tomllib

import bmesh
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
model_path, out_path, budgets_path = args[0], args[1], args[2]
with open(budgets_path, "rb") as f:
    budgets = tomllib.load(f)

spec = importlib.util.spec_from_file_location("model", model_path)
model = importlib.util.module_from_spec(spec)
sys.path.insert(0, "tools/blender")
spec.loader.exec_module(model)
budget_class = getattr(model, "BUDGET", "prop")
budget = budgets["budget"][budget_class]
hard = budgets["hardLimit"]
merge = budgets["mergeDistance"]

model.build()


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


meshes = [o for o in bpy.data.objects if o.type == "MESH"]
report = {"model": model_path, "budgetClass": budget_class, "budget": budget, "objects": [], "problems": [], "notes": []}

before = 0
for obj in meshes:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    before += tris(obj)
report["trianglesBefore"] = before

if before > budget:
    ratio = budget / before * 0.97
    report["notes"].append(f"over budget ({before} > {budget}): decimated every object to {ratio:.3f}")
    for obj in meshes:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)

total = 0
for obj in meshes:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
    zero_area = sum(1 for face in bm.faces if face.calc_area() < 1e-8)
    bm.free()
    t = tris(obj)
    total += t
    dims = obj.dimensions
    entry = {
        "name": obj.name,
        "triangles": t,
        "size": [round(dims.x, 2), round(dims.z, 2), round(dims.y, 2)],  # studs, Roblox order X, Y(up), Z
        "materials": len(obj.data.materials),
        "nonManifoldEdges": non_manifold,
        "zeroAreaFaces": zero_area,
        "hasUV": len(obj.data.uv_layers) > 0,
    }
    report["objects"].append(entry)
    if t > hard:
        report["problems"].append(f"{obj.name}: {t} triangles is over the Roblox limit {hard}")
    if entry["materials"] > 1:
        report["problems"].append(f"{obj.name}: {entry['materials']} materials, use one object per color")
    if zero_area:
        report["problems"].append(f"{obj.name}: {zero_area} zero-area faces")
    if non_manifold:
        report["notes"].append(f"{obj.name}: {non_manifold} non-manifold edges (fine for props, bad for collision)")
report["triangles"] = total
# The model as a whole must stand on its origin (pieces like a lantern's arm are allowed up high).
model_bottom = min((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
report["bottom"] = round(model_bottom, 3)
if model_bottom > 0.05:
    report["problems"].append(f"model's lowest point is {model_bottom:.2f} studs above its origin: it would float")
if total > budget:
    report["problems"].append(f"still {total} triangles after decimating, budget {budget}")
report["ok"] = len(report["problems"]) == 0

if report["ok"]:
    bpy.ops.export_scene.fbx(
        filepath=out_path,
        use_selection=False,
        object_types={"MESH"},
        apply_unit_scale=True,
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
    )
    bpy.ops.wm.save_as_mainfile(filepath=out_path.replace(".fbx", ".blend"))

print("MESHREPORT " + json.dumps(report))
sys.exit(0 if report["ok"] else 1)
