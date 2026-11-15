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

-- Vault: the side (speed) vault from the reference (both vaults read at 30 fps). The BODY travels on the
-- path from Parkour.vaultOffset; this clip only poses the limbs and torso on top of it and is played
-- at whatever speed makes it last exactly the vault's duration. Phases as a share of the clip:
--   0.00 gather   crouch, start turning, arms opening
--   0.28 plant    reaching the obstacle: side-on, left hand onto the top
--   0.45 over     at the arc's peak over the middle: leaning onto the hand, legs tucked and swung
--                 to the right, right arm flung up
--   0.62 clear    pushing off the hand, unrolling
--   0.85 land     low and compact, arms out (the reference lands crouched, then straightens)
--   1.00 run-out  matches the start of the Sprint run so the hand-off is seamless
local VAULT_LENGTH = 0.45
local function at(u: number): number
	return u * VAULT_LENGTH
end

Clips.Vault = {
	loop = false,
	priority = "Action",
	bake = { fps = 60, lag = { head = 0.03, larm = 0.02, rarm = 0.03 } },
	keys = {
		{
			t = at(0),
			pose = {
				root = { pitch = 22, roll = -8, yaw = -15, y = -0.25 },
				head = { pitch = -16, yaw = 12 },
				larm = { fwd = 45, out = 30 },
				rarm = { fwd = -5, out = 70 },
				rleg = { fwd = 45 },
				lleg = { fwd = -15 },
			},
		},
		{
			t = at(0.28),
			pose = {
				root = { pitch = 32, roll = -32, yaw = -55, y = 0 },
				head = { pitch = -14, yaw = 40, roll = 15 },
				larm = { fwd = 60, out = 10 },
				rarm = { fwd = 25, out = 105 },
				rleg = { fwd = 70, out = 25 },
				lleg = { fwd = 50, out = 5 },
			},
		},
		{
			t = at(0.45),
			pose = {
				root = { pitch = 22, roll = -50, yaw = -72, y = 0 },
				head = { pitch = -8, yaw = 55, roll = 28 },
				larm = { fwd = 10, out = 8 }, -- straight down: the body's weight is on this hand
				rarm = { fwd = 10, out = 125 },
				rleg = { fwd = 95, out = 55 },
				lleg = { fwd = 80, out = -18 }, -- crossing towards the right with the other leg
			},
		},
		{
			t = at(0.62),
			pose = {
				root = { pitch = 18, roll = -25, yaw = -40, y = 0 },
				head = { pitch = -12, yaw = 30, roll = 15 },
				larm = { fwd = -20, out = 50 },
				rarm = { fwd = 15, out = 110 },
				rleg = { fwd = 55, out = 25 },
				lleg = { fwd = 30 },
			},
		},
		{
			t = at(0.85),
			pose = {
				root = { pitch = 30, roll = 10, yaw = -12, y = -0.4 },
				head = { pitch = -20, yaw = 10 },
				larm = { fwd = -10, out = 70 },
				rarm = { fwd = 20, out = 80 },
				rleg = { fwd = 55 },
				lleg = { fwd = -5 },
			},
		},
		{
			t = at(1),
			pose = {
				root = { pitch = 15, roll = 5, yaw = -17, y = -0.12 },
				head = { pitch = -16, yaw = 16 },
				larm = { fwd = -30, out = 22 },
				rarm = { fwd = 35, out = 30 },
				rleg = { fwd = -50 },
				lleg = { fwd = 60 },
			},
		},
	},
}

return Clips
