-- Runs the roblox-animation builder (to_roblox.py --no-verify output) outside Studio and saves the
-- KeyframeSequences as a model file that Rojo syncs to the client (src/client/Anims.rbxm).
--   lune run tools/anim_build <build.luau> <out.rbxm>
-- So animations live in the repo like everything else; nothing is hand-made in Studio.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local buildPath, outPath = process.args[1], process.args[2]

local ReplicatedStorage = roblox.Instance.new("Folder")
ReplicatedStorage.Name = "ReplicatedStorage"

local game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return ReplicatedStorage
		end
		return {} -- KeyframeSequenceProvider: only used by the verify tail, which --no-verify leaves out
	end,
}

local env = setmetatable({
	game = game,
	Instance = roblox.Instance,
	CFrame = roblox.CFrame,
	Enum = roblox.Enum,
}, { __index = _G })

-- Strip a UTF-8 byte-order mark: PowerShell 5's Out-File adds one and Luau can't parse it.
local src = fs.readFile(buildPath):gsub("^\239\187\191", "")
-- The builder ends with a summary loop that calls Keyframe:GetMarkers (Studio only). Cut it off and
-- return our own count; the sequences are all built before it.
local tail = string.find(src, "for _, seq in ipairs(built) do", 1, true)
if tail then
	src = string.sub(src, 1, tail - 1) .. 'return "built " .. #built .. " sequences"'
end
local fn = luau.load(src, { debugName = "anim_build", environment = env })
local summary = fn()

local anims = ReplicatedStorage:FindFirstChild("Anims")
assert(anims, "builder did not create ReplicatedStorage.Anims (use --folder ReplicatedStorage.Anims)")
fs.writeFile(outPath, roblox.serializeModel({ anims }))
print(tostring(summary))
print(string.format("wrote %s with %d animations", outPath, #anims:GetChildren()))
