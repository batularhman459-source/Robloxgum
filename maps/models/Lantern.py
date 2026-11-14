"""Street lantern: stone base, wooden post, metal cage with a warm glow. Prop budget.
Built from primitives with small bevels so edges catch light. One object per color."""
import math

import lib

BUDGET = "prop"


def build():
    lib.reset()
    lib.box("Base", (1.6, 1.6, 0.5), (0, 0, 0.25), "stoneDark", bevel=0.08)
    lib.box("BaseTop", (1.2, 1.2, 0.3), (0, 0, 0.65), "stone", bevel=0.06)
    lib.cylinder("Post", 0.22, 6.0, (0, 0, 3.8), "wood", verts=8, bevel=0.03)
    lib.box("Arm", (0.25, 1.6, 0.25), (0, 0.6, 6.4), "woodDark", bevel=0.03)
    lib.cylinder("Chain", 0.05, 0.6, (0, 1.25, 6.0), "metal", verts=6, bevel=0)
    lib.cylinder("CageTop", 0.55, 0.15, (0, 1.25, 5.6), "metal", verts=8, bevel=0.02)
    lib.cylinder("Glow", 0.38, 0.9, (0, 1.25, 5.05), "glow", verts=8, bevel=0.02)
    lib.cylinder("CageBottom", 0.5, 0.12, (0, 1.25, 4.55), "metal", verts=8, bevel=0.02)
    # Cage bars: one object (same color) so it stays one MeshPart.
    bars = []
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        bars.append(lib.box(f"Bar{i}", (0.07, 0.07, 1.0), (math.cos(a) * 0.45, 1.25 + math.sin(a) * 0.45, 5.07), "metal", bevel=0))
    import bpy
    for b in bars:
        b.select_set(True)
    bpy.context.view_layer.objects.active = bars[0]
    bpy.ops.object.join()
    bars[0].name = "CageBars"
