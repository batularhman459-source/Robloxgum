--!strict
-- R6 animation clips. All earlier clips were removed on 2026-11-15 to start from scratch; Run is
-- the designer's imported Evade run. Everything else still plays Roblox's defaults. The vault
-- movement itself is code (Parkour.vaultPlan / vaultOffset).
--
-- How to add a clip again:
--   Clips.Name = { loop = false, priority = "Action", bake = { fps = 60, lag = { head = 0.03 } },
--                  keys = { { t = 0, pose = { root = { pitch = 10 }, rarm = { fwd = 30 } } }, ... } }
--   or import one: Clips.Name = { import = "file.rbxm", sequence = "SeqName", loop = true, priority = "Movement" }
-- Angle conventions: anim/r6/R6Pose.luau. Build: .\anim\build.ps1. Judge on the avatar with
-- DevTools.AnimShowcase. Lessons from earlier attempts: .claude/skills/playtest Lessons.

local Clips = {}

-- The designer's run (Evade Animations pack, imported into Studio 2026-11-15; dumped and rebuilt
-- verbatim with tools/anim_from_json). 0.65 s loop, 25 keys.
Clips.Run = { import = "EvadeRun.rbxm", sequence = "Run", loop = true, priority = "Movement" }

return Clips
