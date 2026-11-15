-- Rebuilds a KeyframeSequence from a JSON dump taken in Studio (Studio can't save files through the
-- MCP, so a sequence is dumped as data and rebuilt here, pose for pose, CFrames verbatim).
--   lune run tools/anim_from_json <dump.json> <out.rbxm>
-- Dump shape: { name, loop, priority, keys = { { t, name, p = { { n, cf = {12 numbers}, w, es, ed, c } } } } }
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local CFrame, Instance, Enum = roblox.CFrame, roblox.Instance, roblox.Enum

local src, out = process.args[1], process.args[2]
assert(src and out, "usage: lune run tools/anim_from_json <dump.json> <out.rbxm>")
local dump = serde.decode("json", fs.readFile(src))

local function addPoses(list: { any }, parent: any)
	for _, p in list do
		local pose = Instance.new("Pose")
		pose.Name = p.n
		pose.CFrame = CFrame.new(table.unpack(p.cf))
		pose.Weight = p.w
		pose.EasingStyle = Enum.PoseEasingStyle[p.es]
		pose.EasingDirection = Enum.PoseEasingDirection[p.ed]
		pose.Parent = parent
		addPoses(p.c, pose)
	end
end

local seq = Instance.new("KeyframeSequence")
seq.Name = dump.name
seq.Loop = dump.loop
seq.Priority = Enum.AnimationPriority[dump.priority]
for _, k in dump.keys do
	local kf = Instance.new("Keyframe")
	kf.Name = k.name
	kf.Time = k.t
	addPoses(k.p, kf)
	kf.Parent = seq
end

fs.writeFile(out, roblox.serializeModel({ seq }))
print(string.format("wrote %s: %s, %d keys, %.2fs", out, dump.name, #dump.keys, dump.keys[#dump.keys].t))
