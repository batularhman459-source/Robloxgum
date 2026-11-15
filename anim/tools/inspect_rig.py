"""Describes a rig .blend: armatures with bone names/parents/rest direction, meshes, actions, custom
properties and embedded text scripts (names only, never run).
blender -b <rig>.blend -P anim/tools/inspect_rig.py   (embedded scripts stay disabled without --enable-autoexec)"""
import bpy

print("OBJECTS")
for o in bpy.data.objects:
    print(f"  {o.type:9s} {o.name}  parent={o.parent.name if o.parent else '-'}")
for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    print(f"ARMATURE {arm.name}: {len(arm.data.bones)} bones")
    for b in arm.data.bones:
        head, tail = b.head_local, b.tail_local
        d = (tail - head).normalized()
        print(f"  {b.name:28s} parent={b.parent.name if b.parent else '-':20s} dir=({d.x:+.2f},{d.y:+.2f},{d.z:+.2f}) len={b.length:.2f}")
    if arm.animation_data and arm.animation_data.action:
        print(f"  action on armature: {arm.animation_data.action.name}")
    for pb in arm.pose.bones:
        props = [k for k in pb.keys() if not k.startswith("_")]
        if props:
            print(f"  custom props on {pb.name}: {props}")
print("ACTIONS", [a.name for a in bpy.data.actions])
print("TEXTS (embedded scripts, NOT run):", [t.name for t in bpy.data.texts])
