-- Builds the R6 parkour clips (anim/r6/Clips.luau) into KeyframeSequences and saves them as
-- src/client/Anims.rbxm, which Rojo syncs to the client. The clips are the single source.
--   lune run tools/r6_build
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Clips = require("../anim/r6/Clips")
local R6Pose = require("../anim/r6/R6Pose")

local CFrame, Instance, Enum = roblox.CFrame, roblox.Instance, roblox.Enum

local function pose(name: string, cf: any, parent: any, style: any): any
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	-- InOut is symmetric, so the legacy In/Out swap of PoseEasingDirection can't bite.
	p.EasingStyle = style
	p.EasingDirection = Enum.PoseEasingDirection.InOut
	p.Parent = parent
	return p
end

local folder = Instance.new("Folder")
folder.Name = "Anims"
local names = {}
for name in Clips do
	table.insert(names, name)
end
table.sort(names)

-- An imported clip: copy a KeyframeSequence out of an .rbxm in anim/r6/imported, renamed, with our
-- loop and priority.
local function importClip(name: string, clip: any): any
	local model = roblox.deserializeModel(fs.readFile("anim/r6/imported/" .. clip.import))
	for _, root in model do
		for _, d in { root, table.unpack(root:GetDescendants()) } do
			if d.ClassName == "KeyframeSequence" and d.Name == clip.sequence then
				local seq = d:Clone()
				seq.Name = name
				seq.Loop = clip.loop
				seq.Priority = Enum.AnimationPriority[clip.priority]
				return seq
			end
		end
	end
	error("no sequence " .. clip.sequence .. " in " .. clip.import)
end

-- A clip authored with the roblox-animation skill (anim/r6/skill/<Name>.clip.json, rendered and checked
-- by its r6_clip.py): resolved.json holds the exact Pose CFrames that were judged, used verbatim.
-- Easing map = the skill's r6_joint.ROBLOX_EASE (Roblox's Pose In/Out enum is reversed, traps.md #36).
local SKILL_EASE = {
	linear = { "Linear", "In" },
	constant = { "Constant", "In" },
	["in"] = { "Cubic", "Out" },
	out = { "Cubic", "In" },
	smooth = { "Cubic", "InOut" },
}
local JOINT_PART = {
	RootJoint = "Torso",
	Neck = "Head",
	["Right Shoulder"] = "Right Arm",
	["Left Shoulder"] = "Left Arm",
	["Right Hip"] = "Right Leg",
	["Left Hip"] = "Left Leg",
}

local function resolvedClip(name: string, clip: any): any
	local res = serde.decode("json", fs.readFile("anim/r6/skill/" .. clip.resolved))
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = clip.loop
	seq.Priority = Enum.AnimationPriority[clip.priority]
	for _, k in res.keys do
		local ease = SKILL_EASE[k.ease] or error("unknown ease " .. tostring(k.ease))
		local style, dir = Enum.PoseEasingStyle[ease[1]], Enum.PoseEasingDirection[ease[2]]
		local kf = Instance.new("Keyframe")
		kf.Name = "KF" .. tostring(k.t)
		kf.Time = k.t
		local function jointPose(joint: string, parent: any): any
			local pc = k.poses[joint]
			local r = pc.rows
			local cf = CFrame.new(
				pc.pos[1],
				pc.pos[2],
				pc.pos[3],
				r[1][1],
				r[1][2],
				r[1][3],
				r[2][1],
				r[2][2],
				r[2][3],
				r[3][1],
				r[3][2],
				r[3][3]
			)
			return pose(JOINT_PART[joint], cf, parent, style)
		end
		local root = pose("HumanoidRootPart", CFrame.new(), kf, style)
		root.Weight = 0 -- container only
		local torso = jointPose("RootJoint", root)
		for _, joint in { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" } do
			local p = jointPose(joint, torso)
			p.EasingDirection = dir
		end
		torso.EasingDirection = dir
		kf.Parent = seq
	end
	-- Clip marks (e.g. the vault's plant / peak / land) as attributes the game syncs to: Mark_<name> = seconds.
	for _, mk in res.markers or {} do
		seq:SetAttribute("Mark_" .. mk[1], mk[2])
	end
	return seq
end

for _, name in names do
	local clip = Clips[name]
	if clip.resolved then
		local seq = resolvedClip(name, clip)
		seq.Parent = folder
		print(
			string.format("%-10s from skill %s, %s, loop=%s", name, clip.resolved, clip.priority, tostring(clip.loop))
		)
		continue
	end
	if clip.import then
		local seq = importClip(name, clip)
		seq.Parent = folder
		print(
			string.format(
				"%-10s imported %s from %s, %s, loop=%s",
				name,
				clip.sequence,
				clip.import,
				clip.priority,
				tostring(clip.loop)
			)
		)
		continue
	end
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = clip.loop
	seq.Priority = Enum.AnimationPriority[clip.priority]
	local keys = clip.keys
	local easing = Enum.PoseEasingStyle.Cubic
	if clip.bake then
		keys = R6Pose.bake(clip.keys, clip.bake.fps, clip.bake.lag)
		easing = Enum.PoseEasingStyle.Linear -- dense keys: the curve is in the samples
	end
	for _, key in keys do
		local kf = Instance.new("Keyframe")
		kf.Name = "KF" .. tostring(key.t)
		kf.Time = key.t
		local root = pose("HumanoidRootPart", CFrame.new(), kf, easing)
		local torso = pose("Torso", R6Pose.transform(CFrame, "root", key.pose.root), root, easing)
		for _, joint in { "head", "rarm", "larm", "rleg", "lleg" } do
			pose(R6Pose.JOINTS[joint].part, R6Pose.transform(CFrame, joint, key.pose[joint]), torso, easing)
		end
		kf.Parent = seq
	end
	seq.Parent = folder
	print(
		string.format(
			"%-10s %d authored -> %d keys, %.2fs, %s, loop=%s",
			name,
			#clip.keys,
			#keys,
			clip.keys[#clip.keys].t,
			clip.priority,
			tostring(clip.loop)
		)
	)
end

fs.writeFile("src/client/Anims.rbxm", roblox.serializeModel({ folder }))
print("wrote src/client/Anims.rbxm")
