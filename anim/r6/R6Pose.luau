--!strict
-- R6 pose math: body-space angles -> Motor6D Transform CFrames. No Roblox services; CFrame is passed in
-- so it runs in Lune (build) and could run in Studio.
--
-- Body space: the character faces -Z, +X is its right, +Y up. Angles in degrees.
--   root / head:  pitch + = lean forward, roll + = lean to the character's right, yaw + = turn right,
--                 y = move the whole body up/down (root only, studs)
--   arms / legs:  fwd + = swing forward, out + = swing away from the body (sideways), twist + = turn out
-- The joint frames (C0) are the standard R6 ones, measured on the real avatar in Studio 2026-11-15.
-- Each body rotation M about the joint is turned into the joint's own frame: T = C0r^-1 * M * C0r.

local R6Pose = {}

-- Rotation part of each joint's C0 as (r00 r01 r02 r10 r11 r12 r20 r21 r22), and the Part1 each moves.
R6Pose.JOINTS = {
	root = { part = "Torso", r = { -1, 0, 0, 0, 0, 1, 0, 1, 0 } },
	head = { part = "Head", r = { -1, 0, 0, 0, 0, 1, 0, 1, 0 } },
	rarm = { part = "Right Arm", r = { 0, 0, 1, 0, 1, 0, -1, 0, 0 } },
	larm = { part = "Left Arm", r = { 0, 0, -1, 0, 1, 0, 1, 0, 0 } },
	rleg = { part = "Right Leg", r = { 0, 0, 1, 0, 1, 0, -1, 0, 0 } },
	lleg = { part = "Left Leg", r = { 0, 0, -1, 0, 1, 0, 1, 0, 0 } },
}
R6Pose.ORDER = { "root", "head", "rarm", "larm", "rleg", "lleg" }

local function rad(d: number?): number
	return math.rad(d or 0)
end

-- Body-space transform for one joint from its angle table.
function R6Pose.bodyTransform(CFrame: any, joint: string, a: any): any
	a = a or {}
	if joint == "root" or joint == "head" then
		-- Rx(+) tilts the top backwards, Rz(+) tilts it left, Ry(+) turns left: flip all three.
		local rot = CFrame.Angles(0, -rad(a.yaw), 0) * CFrame.Angles(-rad(a.pitch), 0, 0) * CFrame.Angles(0, 0, -rad(a.roll))
		return CFrame.new(0, a.y or 0, 0) * rot
	end
	-- Limbs hang down (-Y): Rx(+) swings them forward (-Z), Rz(+) swings them to +X (right).
	local side = if joint == "rarm" or joint == "rleg" then 1 else -1
	local twist = CFrame.Angles(0, -side * rad(a.twist), 0)
	return CFrame.Angles(rad(a.fwd), 0, 0) * CFrame.Angles(0, 0, side * rad(a.out)) * twist
end

-- Motor6D Transform (what a Pose stores) for one joint.
function R6Pose.transform(CFrame: any, joint: string, a: any): any
	local r = R6Pose.JOINTS[joint].r
	local c0r = CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	return c0r:Inverse() * R6Pose.bodyTransform(CFrame, joint, a) * c0r
end

local AXES = {
	root = { "pitch", "roll", "yaw", "y" },
	head = { "pitch", "roll", "yaw", "y" },
	rarm = { "fwd", "out", "twist" },
	larm = { "fwd", "out", "twist" },
	rleg = { "fwd", "out", "twist" },
	lleg = { "fwd", "out", "twist" },
}
R6Pose.AXES = AXES

-- Value of one joint axis at time t: a smooth spline through the authored keys (Hermite with
-- finite-difference tangents, i.e. Catmull-Rom for uneven timing). Missing values count as 0.
function R6Pose.sampleAxis(keys: any, joint: string, axis: string, t: number): number
	local n = #keys
	local function v(i: number): number
		local p = keys[i].pose[joint]
		return (p and p[axis]) or 0
	end
	local function time(i: number): number
		return keys[i].t
	end
	if t <= time(1) then
		return v(1)
	elseif t >= time(n) then
		return v(n)
	end
	local i = 1
	while time(i + 1) < t do
		i += 1
	end
	local function tangent(k: number): number
		local a, b = math.max(k - 1, 1), math.min(k + 1, n)
		return (v(b) - v(a)) / (time(b) - time(a))
	end
	local h = time(i + 1) - time(i)
	local s = (t - time(i)) / h
	local s2, s3 = s * s, s * s * s
	return (2 * s3 - 3 * s2 + 1) * v(i)
		+ (s3 - 2 * s2 + s) * h * tangent(i)
		+ (-2 * s3 + 3 * s2) * v(i + 1)
		+ (s3 - s2) * h * tangent(i + 1)
end

-- Bakes authored keys into dense keys (fps per second) so the clip plays as one smooth curve
-- instead of pose-to-pose. lag[joint] = seconds that joint trails behind (follow-through).
function R6Pose.bake(keys: any, fps: number, lag: { [string]: number }?): any
	local duration = keys[#keys].t
	local frames = math.max(1, math.floor(duration * fps + 0.5))
	local out = {}
	for f = 0, frames do
		local t = duration * f / frames
		local pose = {}
		for joint, axes in AXES do
			local tt = math.clamp(t - ((lag and lag[joint]) or 0), 0, duration)
			local a = {}
			for _, axis in axes do
				a[axis] = R6Pose.sampleAxis(keys, joint, axis, tt)
			end
			pose[joint] = a
		end
		table.insert(out, { t = t, pose = pose })
	end
	return out
end

-- Mirror a pose left <-> right (for the second half of a run cycle).
function R6Pose.mirror(pose: any): any
	local function copy(t: any): any
		if not t then
			return nil
		end
		local c = table.clone(t)
		if c.roll then
			c.roll = -c.roll
		end
		if c.yaw then
			c.yaw = -c.yaw
		end
		return c
	end
	return {
		root = copy(pose.root),
		head = copy(pose.head),
		rarm = pose.larm and table.clone(pose.larm),
		larm = pose.rarm and table.clone(pose.rarm),
		rleg = pose.lleg and table.clone(pose.lleg),
		lleg = pose.rleg and table.clone(pose.rleg),
	}
end

return R6Pose
