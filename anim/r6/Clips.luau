--!strict
-- R6 parkour clips as body-space poses (see R6Pose.luau for the angle conventions).
-- Reference: the user's TikTok (vault + run). What makes it read well:
--   run   - forward lean, arms bent-wide and pumping, a side-to-side ROLL and shoulder twist every
--           step, the body bobbing down on contact and up on the passing pose
--   vault - speed vault: body pitches almost flat over the obstacle, arms flung wide like wings,
--           legs tucked and swinging through, a strong sideways roll, landing straight into the run
-- Timing is Roblox timing (fast). Run: 0.4 s cycle at base speed (20 studs/s, ~4 studs a step);
-- the controller speeds it up with momentum.
local R6Pose = require("./R6Pose")

local LEAN = 14 -- forward lean while running (root pitch); legs get it added back so they stay planted

-- Right leg forward, left arm forward: contact pose.
local RUN_A = {
	root = { pitch = LEAN, roll = -7, yaw = 10, y = -0.18 },
	head = { pitch = -10, yaw = -9, roll = 4 },
	larm = { fwd = 62, out = 22, twist = 10 },
	rarm = { fwd = -48, out = 24 },
	rleg = { fwd = 46 + LEAN },
	lleg = { fwd = -38 + LEAN },
}
-- Passing pose: legs under the body, body at its highest.
local PASS_A = {
	root = { pitch = LEAN, roll = 0, yaw = 0, y = 0.16 },
	head = { pitch = -10 },
	larm = { fwd = 12, out = 20 },
	rarm = { fwd = -8, out = 22 },
	rleg = { fwd = 4 + LEAN },
	lleg = { fwd = 14 + LEAN, out = 4 },
}
local RUN_B = R6Pose.mirror(RUN_A)
local PASS_B = R6Pose.mirror(PASS_A)

local Clips = {}

Clips.Run = {
	loop = true,
	priority = "Movement",
	keys = {
		{ t = 0.0, pose = RUN_A },
		{ t = 0.1, pose = PASS_A },
		{ t = 0.2, pose = RUN_B },
		{ t = 0.3, pose = PASS_B },
		{ t = 0.4, pose = RUN_A },
	},
}

Clips.Vault = {
	loop = false,
	priority = "Action",
	keys = {
		{ t = 0.0, pose = RUN_A },
		-- Plant: pitching forward, lead hand reaching for the obstacle, other arm flung out.
		{
			t = 0.08,
			pose = {
				root = { pitch = 48, roll = 18, yaw = 10 },
				head = { pitch = -28, roll = -8 },
				larm = { fwd = 75, out = 55 },
				rarm = { fwd = 25, out = 95 },
				rleg = { fwd = 70 },
				lleg = { fwd = 35, out = 10 },
			},
		},
		-- Over the top: nearly flat, arms wide like wings, legs tucked and swinging through, big roll.
		{
			t = 0.2,
			pose = {
				root = { pitch = 74, roll = 34, yaw = 18, y = 0.3 },
				head = { pitch = -48, roll = -14 },
				larm = { fwd = 25, out = 110 },
				rarm = { fwd = 15, out = 118 },
				rleg = { fwd = 100, out = 22 },
				lleg = { fwd = 85, out = 30 },
			},
		},
		-- Coming down: unrolling, one leg reaching for the ground, arms still out for balance.
		{
			t = 0.32,
			pose = {
				root = { pitch = 28, roll = 10, yaw = 6 },
				head = { pitch = -14 },
				larm = { fwd = 30, out = 70 },
				rarm = { fwd = 5, out = 75 },
				rleg = { fwd = 45 },
				lleg = { fwd = -15, out = 8 },
			},
		},
		-- Land straight into the run.
		{ t = 0.45, pose = RUN_B },
	},
}

return Clips
