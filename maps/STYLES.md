# Map style library

Every inspiration or screenshot the user sends gets studied, the key idea recreated in our system,
and an entry written here. New maps start from an entry. Entries describe **space**, not just looks.

## Entry template
```
## <Style name>
Source: <reference>                 Example map: Workspace.Maps.<Name>, brief maps/briefs/<Name>.md
Feel: <3-6 words>
Space: main route shape (loop / hub / linear), path widths, open vs closed ratio, verticality
Numbers (measured with MapProbe on our recreation): typical A-to-B, longest sight line, jump gaps, fall heights
Landmarks: what you can see from where, how they guide
Palette + materials: lib.PALETTE keys, Roblox materials
Silhouettes + props: shapes that repeat, density per 100 studs^2, triangle budget classes used
Kept from reference / changed for our rules / do / don't
```

---

## House (default, until the first reference arrives)
Feel: readable, warm, hand-made.
Space: hub with loops, main paths 12-16 studs wide, side paths 6-8; every area has two ways out.
Numbers: jumps at most 75 % of the measured max gap; falls on main routes under minCleanDrop or a
clear drop above it; landmarks visible from every junction.
Palette: lib.PALETTE (stone, wood, leaf, roof, glow). Bevelled props, chiselled rocks.
Don't: scattered parts, perfect grids of props, random rotations, props floating or sunk into floors.
