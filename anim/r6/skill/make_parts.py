"""Box GLBs of the R6 body parts at the sizes in rig.json (for the skill's r6_clip.py renderer).

  blender --background --python-exit-code 1 --python anim/r6/skill/make_parts.py -- anim/r6/skill/rig.json build/r6parts

r6_clip.py asserts each mesh's bbox centre equals the part's rest position from the C0/C1 chain, so
every box is built AT that rest position. Its import map is Blender = Q * Roblox with
Q: (X, Y, Z) -> (-X, Z, Y), so a Roblox point (x, y, z) is built at Blender (-x, z, y).
"""
import bpy, json, os, sys
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
rig = json.load(open(args[0]))
out = os.path.abspath(args[1])
os.makedirs(out, exist_ok=True)


def cf(d):
    m = Matrix([list(r) for r in d["rows"]]).to_4x4()
    m.translation = Vector(d["pos"])
    return m


rest = {"HumanoidRootPart": Matrix.Translation(Vector(rig["hrp"]))}
pending = list(rig["joints"])
while pending:
    j = next(j for j in pending if j["part0"] in rest)
    rest[j["part1"]] = rest[j["part0"]] @ cf(j["c0"]) @ cf(j["c1"]).inverted()
    pending.remove(j)

for part, spec in rig["parts"].items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sx, sy, sz = rig["sizes"][part]
    x, y, z = rest[part].translation
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-x, z, y))
    ob = bpy.context.active_object
    ob.scale = (sx, sz, sy)
    bpy.ops.object.transform_apply(location=True, scale=True)
    path = os.path.join(out, spec["glb"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    print(f"wrote {path} size {sx, sy, sz} at roblox {round(x, 3), round(y, 3), round(z, 3)}", flush=True)
