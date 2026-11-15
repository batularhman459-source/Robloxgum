-- Builds the R6 parkour clips (anim/r6/Clips.luau) into KeyframeSequences and saves them as
-- src/client/Anims.rbxm, which Rojo syncs to the client. The clips are the single source.
--   lune run tools/r6_build
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Clips = require("../anim/r6/Clips")
local R6Pose = require("../anim/r6/R6Pose")

local CFrame, Instance, Enum = roblox.CFrame, roblox.Instance, roblox.Enum

local function pose(name: string, cf: any, parent: any): any
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	-- InOut is symmetric, so the legacy In/Out swap of PoseEasingDirection can't bite.
	p.EasingStyle = Enum.PoseEasingStyle.Cubic
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

for _, name in names do
	local clip = Clips[name]
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = clip.loop
	seq.Priority = Enum.AnimationPriority[clip.priority]
	for _, key in clip.keys do
		local kf = Instance.new("Keyframe")
		kf.Name = "KF" .. tostring(key.t)
		kf.Time = key.t
		local root = pose("HumanoidRootPart", CFrame.new(), kf)
		local torso = pose("Torso", R6Pose.transform(CFrame, "root", key.pose.root), root)
		for _, joint in { "head", "rarm", "larm", "rleg", "lleg" } do
			pose(R6Pose.JOINTS[joint].part, R6Pose.transform(CFrame, joint, key.pose[joint]), torso)
		end
		kf.Parent = seq
	end
	seq.Parent = folder
	print(
		string.format(
			"%-10s %d keys, %.2fs, %s, loop=%s",
			name,
			#clip.keys,
			clip.keys[#clip.keys].t,
			clip.priority,
			tostring(clip.loop)
		)
	)
end

fs.writeFile("src/client/Anims.rbxm", roblox.serializeModel({ folder }))
print("wrote src/client/Anims.rbxm")
