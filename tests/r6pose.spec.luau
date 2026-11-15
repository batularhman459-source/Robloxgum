-- Proves the R6 pose directions with real R6 joint math (the R15 clips once shipped with inverted
-- leans that only a screenshot caught). World pose of a part = Part0 * C0 * Transform * C1^-1.
local roblox = require("@lune/roblox")
local R6Pose = require("../anim/r6/R6Pose")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

-- Real R6 C0/C1 (measured on the avatar in Studio 2026-11-15).
local C = {
	rarm = { CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	larm = { CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	rleg = { CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	lleg = { CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	root = { CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
}

-- Direction from the joint to the far end of a limb (its -Y axis) in torso space.
local function limbDown(joint, angles)
	local c0, c1 = C[joint][1], C[joint][2]
	local world = c0 * R6Pose.transform(CFrame, joint, angles) * c1:Inverse()
	return -world.UpVector
end

local function torsoUp(angles)
	local c0, c1 = C.root[1], C.root[2]
	return (c0 * R6Pose.transform(CFrame, "root", angles) * c1:Inverse()).UpVector
end

local function near(t, v, target, msg)
	t.ok((v - target).Magnitude < 1e-4, string.format("%s: got (%.2f, %.2f, %.2f)", msg, v.X, v.Y, v.Z))
end

return {
	["rest pose: limbs hang straight down, torso upright"] = function(t)
		for _, j in { "rarm", "larm", "rleg", "lleg" } do
			near(t, limbDown(j, {}), Vector3.new(0, -1, 0), j .. " at rest")
		end
		near(t, torsoUp({}), Vector3.new(0, 1, 0), "torso at rest")
	end,

	["fwd 90 points every limb forward (-Z)"] = function(t)
		for _, j in { "rarm", "larm", "rleg", "lleg" } do
			near(t, limbDown(j, { fwd = 90 }), Vector3.new(0, 0, -1), j .. " fwd 90")
		end
	end,

	["out 90 points each limb away from the body"] = function(t)
		near(t, limbDown("rarm", { out = 90 }), Vector3.new(1, 0, 0), "right arm out")
		near(t, limbDown("larm", { out = 90 }), Vector3.new(-1, 0, 0), "left arm out")
		near(t, limbDown("rleg", { out = 90 }), Vector3.new(1, 0, 0), "right leg out")
		near(t, limbDown("lleg", { out = 90 }), Vector3.new(-1, 0, 0), "left leg out")
	end,

	["root pitch leans forward, roll leans right"] = function(t)
		local s = math.sin(math.rad(30))
		local c = math.cos(math.rad(30))
		near(t, torsoUp({ pitch = 30 }), Vector3.new(0, c, -s), "pitch 30 tips the top forward (-Z)")
		near(t, torsoUp({ roll = 30 }), Vector3.new(s, c, 0), "roll 30 tips the top to the right (+X)")
	end,

	["mirror swaps sides and flips roll and yaw"] = function(t)
		local m =
			R6Pose.mirror({ root = { roll = 7, yaw = 10, pitch = 14 }, rarm = { fwd = 60 }, lleg = { fwd = -30 } })
		t.eq(m.larm.fwd, 60)
		t.eq(m.rleg.fwd, -30)
		t.eq(m.root.roll, -7)
		t.eq(m.root.yaw, -10)
		t.eq(m.root.pitch, 14, "pitch stays")
	end,
}
