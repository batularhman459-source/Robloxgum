--!strict
-- R6 parkour clips as body-space poses (see R6Pose.luau for the angle conventions).
-- Authored clips are baked into smooth 60 keys/s curves (R6Pose.bake); imported clips are used as-is.
-- Lessons from the Sprint clip (imported/CREDITS.md): dense curves not pose-to-pose, constant
-- counter-motion (shoulder twist vs head), arms never hanging, follow-through on head and arms.

local Clips = {}

-- Run: the designer's Sprint clip by godofsun95, used as-is (see imported/CREDITS.md). Our own
-- 5-pose run read as stiff; this one is baked at 60 keys/s.
Clips.Run = {
	import = "movementanims.rbxm",
	sequence = "Sprint",
	loop = true,
	priority = "Movement",
}

-- Vault: a SIDE (speed) vault, studied frame by frame from the reference at 30 fps (frames 7-17):
--   take-off  body turns ~70 deg left (side-on), crouches, left hand reaches down to the wall top
--   over      leans hard onto the planted left hand (~50 deg roll), legs tuck and swing over to the
--             RIGHT side, right arm flung up and out
--   down      body diagonal, unrolling over ~0.2 s, left arm swings out low, right arm high; still a
--             little tilted when the feet land, runs out of it
-- Baked into a 60 keys/s curve with follow-through (head and arms trail the body), like the Sprint.
Clips.Vault = {
	loop = false,
	priority = "Action",
	bake = { fps = 60, lag = { head = 0.035, larm = 0.025, rarm = 0.03 } },
	keys = {
		-- Last stride in: arms already opening wide (the reference spreads them before the wall).
		{
			t = 0.0,
			pose = {
				root = { pitch = 14, roll = 4, yaw = -8, y = -0.12 },
				head = { pitch = -14, yaw = 8 },
				larm = { fwd = 30, out = 55 },
				rarm = { fwd = -10, out = 65 },
				rleg = { fwd = 40 },
				lleg = { fwd = -30 },
			},
		},
		-- Take-off: turning side-on to the left, crouched, left hand reaching down for the wall top.
		{
			t = 0.07,
			pose = {
				root = { pitch = 30, roll = -18, yaw = -45, y = -0.3 },
				head = { pitch = -18, yaw = 35, roll = 10 },
				larm = { fwd = 70, out = 25 },
				rarm = { fwd = 20, out = 95 },
				rleg = { fwd = 65 },
				lleg = { fwd = 55, out = 10 },
			},
		},
		-- Over: side-on, leaning onto the planted left hand, legs tucked and swung to the right.
		{
			t = 0.17,
			pose = {
				root = { pitch = 25, roll = -50, yaw = -70, y = 0.25 },
				head = { pitch = -10, yaw = 55, roll = 30 },
				larm = { fwd = 15, out = 10 }, -- straight down onto the wall
				rarm = { fwd = 10, out = 125 },
				rleg = { fwd = 95, out = 55 },
				lleg = { fwd = 80, out = 25 },
			},
		},
		-- Legs passing over, body starting to unroll.
		{
			t = 0.25,
			pose = {
				root = { pitch = 18, roll = -28, yaw = -40, y = 0.15 },
				head = { pitch = -12, yaw = 30, roll = 18 },
				larm = { fwd = -15, out = 50 },
				rarm = { fwd = 15, out = 115 },
				rleg = { fwd = 55, out = 30 },
				lleg = { fwd = 25, out = 15 },
			},
		},
		-- Coming down diagonal: left arm swinging out low, right arm high, right leg reaching for the ground.
		{
			t = 0.35,
			pose = {
				root = { pitch = 14, roll = 18, yaw = -12, y = -0.05 },
				head = { pitch = -14, yaw = 10, roll = -10 },
				larm = { fwd = -20, out = 75 },
				rarm = { fwd = 20, out = 95 },
				rleg = { fwd = 30, out = 8 },
				lleg = { fwd = -20 },
			},
		},
		-- Land and run out of it (matches the start of the Sprint's stride: arms wide, slight tilt left).
		{
			t = 0.47,
			pose = {
				root = { pitch = 14, roll = 5, yaw = -12, y = -0.12 },
				head = { pitch = -15, yaw = 12 },
				larm = { fwd = -25, out = 40 },
				rarm = { fwd = 30, out = 45 },
				rleg = { fwd = -40 },
				lleg = { fwd = 50 },
			},
		},
	},
}

return Clips
