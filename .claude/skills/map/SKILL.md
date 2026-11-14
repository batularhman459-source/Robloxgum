---
name: map
description: Design, build and measure Roblox maps as spaces players move through, not piles of parts. Measures reach, way back, sight lines, fall heights and A-to-B times with raycasts and real movement numbers, runs the 9 map checks, and builds polished Blender meshes within triangle budgets. Use for any map, level, area, course or environment work, and when the user says map, level, measure the map or /map.
---

# Map

A map is a space a player moves through. Every claim about it (you can get there, you can get back,
you can see across, this fall is fine, A to B takes 9 s) is **measured**, never eyeballed.

## Rules
- Movement numbers come from `rules/movement.toml`. Each has a source; GUESS values get measured with
  MoveProbe before a map is called done. Never type a jump height or speed into map code.
- Every number in a report carries its source: [config], [studio], [raycast], [derived], [measured: play], [GUESS].
- Every assumption goes in the report's Guesses list. Unknown is written as unknown.
- The checks live in code (`src/shared/map/*` pure + tested, `src/dev/MapProbe.luau` in Studio).
  Never judge reachability or falls by looking at a screenshot.

## Workflow
1. **References first.** For every inspiration or screenshot the user gives: describe its space
   (routes, landmarks, sight lines, density, scale, palette, silhouettes), recreate the key idea, and
   add an entry to `maps/STYLES.md`. New maps start from a STYLES.md entry, not from nothing.
2. **Brief before building.** Write `maps/briefs/<Name>.md`: spawn, goals, main route and loops, target
   A-to-B times, intended sight lines (open/closed), no-access areas, intended falls, landmarks.
3. **Blockout** in Studio under `Workspace.Maps.<Name>` (a Model). Tag it so the probe knows intent:
   `MapSpawn`, `MapWaypoint` (attr Label, optional SightTo + Sight), `MapNoAccess`, `MapGround`,
   `MapFloating`, `MapUnreachable`, `MapRing`, `MapMerge` (see MapProbe header).
4. **Measure** (Edit mode, execute_luau):
   `return require(game:GetService("ReplicatedStorage").DevTools.MapProbe:Clone()).run({ root = workspace.Maps.<Name>, viz = true })`
   Always `:Clone()` (Studio caches require). Screenshot the viz from above, then `.clearViz()`.
   Fix the map until all 9 checks pass. Compare measured times and sight lines with the brief.
5. **Art pass with meshes.** Models are Blender scripts in `maps/models/<Name>.py` using
   `tools/blender/lib.py`. `.\tools\mesh.ps1 -Name <Name>` builds, optimises, checks the triangle
   budget (`maps/budgets.toml`), refuses anything over, and renders `_shaded.png` + `_wire.png`.
   Look at both renders before importing. Uploading a model to Roblox: ask the user first, every time.
6. **Re-measure** after meshes replace blockout parts (collision changes).
7. **Movement check** in play mode when movement or avatars change:
   `return require(game:GetService("ReplicatedStorage").DevTools.MoveProbe:Clone()).run()` (Client).
   Put measured values into `rules/movement.toml` with source `measured: MoveProbe <date>`.
8. Save the report to `maps/reports/<Name>.md` and show the user the result and the viz screenshot.

## The 9 checks
1. Floating platforms: parts not connected to the ground through touching parts.
2. Floating tops: anything hovering just above what's under it (roofs, props, caps), gap > 0.03.
3. Unreachable places: walkable areas no route reaches (tight spots next to reachable floor excluded).
4. Shouldn't-reach places: `MapNoAccess` volumes a route reaches, with the route time.
5. No way out: areas you can get into (often by falling) but never back from.
6. Sight lines: waypoint pairs measured open/closed vs `Sight` attribute, plus openness from spawns.
7. Overlaps: parts inside parts deeper than 0.05 studs.
8. Uneven rings, circles and platforms: ring radius/spacing/height deviations, almost-level tops,
   rotations almost-but-not-quite on a 15 degree grid.
9. Falls: longer than `maxSafeFall` (fail), and awkward drops between stepHeight and minCleanDrop (warn).
Plus measured info: A-to-B times both ways, longest fall, void edges, view distance from spawn.

## Look and feel (not typical AI work)
- No scattered parts. Every object has a reason: it guides, frames a view, blocks, or rewards.
- Paths have a width and a rhythm; landmarks are visible from decision points (prove it with sight lines).
- Meshes: bevelled edges, one object per color, chiselled rocks (plane cuts), muted house palette
  (`lib.PALETTE`). No noise-blob rocks, no perfect grids of identical props, no random rotations.
- Props sit on surfaces (the probe's floating and hover checks enforce it).

## Lessons (add one every time something is noticed; keep the why)
- Raycasts can't see a part from the inside: a floor running under a wall or box looked standable.
  Standing space is tested with GetPartsInPart on a body-sized box.
- That body box must be lifted on slopes (half-width x slope), or every ramp cell fails.
- Thin rays slipped through a 0.3 stud gap under a roof: jump arcs use Spherecast at character width.
- Jump cost must never be faster than walking (air speed = walk speed), or routes cheat with jumps.
- Studio caches `require` in Edit mode, Rojo edits don't show up: always require a `:Clone()`.
- Rojo must be restarted after `default.project.json` changes.
- Group findings per part (one ledge = one finding), or one ramp produces ten lines.
- Test fixtures need checking too: the first ramp sloped the wrong way and sat on top of the pit.
- Noise-displaced spheres make blobby, stripy rocks (the generated look). Chisel with plane cuts.
- Floating check for meshes is per model, not per piece (a lantern's arm is allowed up high).
- Units: 1 Blender unit = 1 stud is still a GUESS until the first imported mesh is measured in Studio.
