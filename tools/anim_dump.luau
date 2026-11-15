-- Dumps the KeyframeSequences in an .rbxm as readable body angles, to study how a clip is made.
--   lune run tools/anim_dump <file.rbxm> [SequenceName]
-- Per keyframe: time, then per joint the body-space angles (same conventions as anim/r6/R6Pose.luau:
-- limbs fwd/out, root/head pitch/roll/yaw, y) and the easing. Also prints per-joint ranges.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local R6Pose = require("../anim/r6/R6Pose")
local CFrame = roblox.CFrame

local path, only = process.args[1], process.args[2]
local JOINT_OF_PART = {}
for joint, info in R6Pose.JOINTS do
	JOINT_OF_PART[info.part] = joint
end

-- Body-space transform from a Pose CFrame: M = C0r * T * C0r^-1 (inverse of R6Pose.transform).
local function bodyAngles(joint, cf)
	local r = R6Pose.JOINTS[joint].r
	local c0r = CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	local m = c0r * cf * c0r:Inverse()
	local rx, ry, rz = m:ToEulerAnglesYXZ() -- m = Ry * Rx * Rz
	local d = function(v)
		return math.floor(math.deg(v) * 10 + 0.5) / 10
	end
	if joint == "root" or joint == "head" then
		return string.format("pitch %6.1f roll %6.1f yaw %6.1f y %5.2f", -d(rx), -d(rz), -d(ry), m.Position.Y),
			{ -d(rx), -d(rz), -d(ry) }
	end
	local side = if joint == "rarm" or joint == "rleg" then 1 else -1
	-- limbs: Rx(fwd) * Rz(side*out); YXZ order gives ry ~ 0 for these
	return string.format("fwd %6.1f out %6.1f twist %5.1f", d(rx), side * d(rz), d(ry)), { d(rx), side * d(rz), d(ry) }
end

local model = roblox.deserializeModel(fs.readFile(path))
local seqs = {}
for _, root in model do
	for _, d in { root, table.unpack(root:GetDescendants()) } do
		if d.ClassName == "KeyframeSequence" and (not only or d.Name == only) then
			table.insert(seqs, d)
		end
	end
end

for _, seq in seqs do
	local kfs = {}
	for _, k in seq:GetChildren() do
		if k.ClassName == "Keyframe" then
			table.insert(kfs, k)
		end
	end
	table.sort(kfs, function(a, b)
		return a.Time < b.Time
	end)
	print(
		string.format(
			"\n=== %s: %d keyframes, length %.3fs, loop %s, priority %s",
			seq.Name,
			#kfs,
			kfs[#kfs].Time,
			tostring(seq.Loop),
			tostring(seq.Priority)
		)
	)
	local ranges = {}
	for _, k in kfs do
		print(string.format("-- t=%.3f", k.Time))
		for _, p in k:GetDescendants() do
			if p.ClassName == "Pose" and JOINT_OF_PART[p.Name] then
				local joint = JOINT_OF_PART[p.Name]
				local text, v = bodyAngles(joint, p.CFrame)
				print(
					string.format(
						"   %-5s %s  [%s %s w%.1f]",
						joint,
						text,
						tostring(p.EasingStyle):gsub("Enum.PoseEasingStyle.", ""),
						tostring(p.EasingDirection):gsub("Enum.PoseEasingDirection.", ""),
						p.Weight
					)
				)
				ranges[joint] = ranges[joint] or { {}, {}, {} }
				for i = 1, 3 do
					table.insert(ranges[joint][i], v[i])
				end
			end
		end
	end
	print("-- ranges (min..max) per axis:")
	for joint, axes in ranges do
		local parts = {}
		for i = 1, 3 do
			table.sort(axes[i])
			table.insert(parts, string.format("%.0f..%.0f", axes[i][1], axes[i][#axes[i]]))
		end
		print(string.format("   %-5s %s", joint, table.concat(parts, "  ")))
	end
end
