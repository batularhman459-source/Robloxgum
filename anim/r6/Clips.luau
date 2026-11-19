--!strict
-- R6 animation clips. Run is the designer's imported Evade run; everything else plays Roblox's defaults.
-- The vault is the toolbox Vaulting System, which brings its own clips (anim/r6/imported/ToolboxVault.rbxm).
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
Clips.Run = {
	import = "EvadeRun.rbxm",
	sequence = "Run",
	loop = true,
	priority = "Movement",
	id = "rbxassetid://124107817748632", -- uploaded 2026-11-18 (designer approved)
}

-- The toolbox Vaulting System's clips (Creator Store model by RasyidFZ and PurpleShade198, inserted by the
-- designer 2026-11-17), dumped from Studio and rebuilt verbatim with tools/anim_from_json. Played by
-- src/client/Vault.client.luau. Its own Animation ids belong to another account and would not load in
-- this game once published, so Step and Normal were uploaded under this account on 2026-11-18 (ids below).
Clips.StepVault = {
	import = "StepVaultAnimation.rbxm",
	sequence = "StepVaultAnimation",
	loop = false,
	priority = "Action",
	id = "rbxassetid://139090871664396", -- uploaded 2026-11-18
}
Clips.NormalVault = {
	import = "NormalVaultAnimation.rbxm",
	sequence = "NormalVaultAnimation",
	loop = false,
	priority = "Action",
	id = "rbxassetid://80967627624275", -- uploaded 2026-11-18
}

-- The wall run (designer 2026-11-19: "use this instead of yours"): the "FREE R6 Wall Run" package by SKATER STUDIOS,
-- its four KeyframeSequences extracted verbatim (Step markers kept), uploaded under this account 2026-11-19.
-- Played by src/client/WallRun (the package's script, ported).
Clips.WallRunLeft = {
	import = "WallRunLeft.rbxm",
	sequence = "WallRunLeft",
	loop = true,
	priority = "Action",
	id = "rbxassetid://72452355877926",
}
Clips.WallRunRight = {
	import = "WallRunRight.rbxm",
	sequence = "WallRunRight",
	loop = true,
	priority = "Action",
	id = "rbxassetid://80180683542825",
}
Clips.WallJumpLeft = {
	import = "WallJumpLeft.rbxm",
	sequence = "WallJumpLeft",
	loop = false,
	priority = "Action2",
	id = "rbxassetid://86254189532011",
}
Clips.WallJumpRight = {
	import = "WallJumpRight.rbxm",
	sequence = "WallJumpRight",
	loop = false,
	priority = "Action2",
	id = "rbxassetid://100555087718500",
}

return Clips
