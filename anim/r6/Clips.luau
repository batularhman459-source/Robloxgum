--!strict
-- R6 animation clips. EMPTY on purpose: all animations were removed on 2026-11-15 to start from
-- scratch (Roblox's default R6 animations play meanwhile). The vault movement itself is code
-- (Parkour.vaultPlan / vaultOffset) and stays.
--
-- How to add a clip again:
--   Clips.Name = { loop = false, priority = "Action", bake = { fps = 60, lag = { head = 0.03 } },
--                  keys = { { t = 0, pose = { root = { pitch = 10 }, rarm = { fwd = 30 } } }, ... } }
--   or import one: Clips.Name = { import = "file.rbxm", sequence = "SeqName", loop = true, priority = "Movement" }
-- Angle conventions: anim/r6/R6Pose.luau. Build: .\anim\build.ps1. Judge on the avatar with
-- DevTools.AnimShowcase. Lessons from earlier attempts: .claude/skills/playtest Lessons.

local Clips = {}

return Clips
