"""Lists the control bones of the rig (names, parent). blender -b <rig>.blend -P anim/tools/list_bones.py"""
import bpy

for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    names = [b.name for b in arm.data.bones]
    fk = sorted(n for n in names if n.startswith("FK_"))
    other = sorted(n for n in names if n.isupper() or n in ("UpTorso", "LowTorso", "ROOT", "TORSO", "HEAD"))
    print("ARMATURE", arm.name, len(names), "bones")
    print("FK:", ", ".join(fk))
    print("TOP:", ", ".join(other))
