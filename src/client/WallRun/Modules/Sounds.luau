--!strict

local Config = require(script.Parent:WaitForChild("Config"))
local Log = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("Log"))
local Trove = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("Trove"))

local Logger = Log.new()

local function Warn(Message: string)
	Logger:AtWarning():Log(Message:lower())
end

local Sounds = {}
Sounds.__index = Sounds

export type Sounds = typeof(setmetatable(
	{} :: {
		Parent: BasePart,
		Definitions: { [string]: Config.SoundDefinition },
		Registry: { [string]: Sound },
		Trove: Trove.Trove,
	},
	Sounds
))

function Sounds.new(Parent: BasePart, Definitions: { [string]: Config.SoundDefinition }): Sounds
	local self = setmetatable({}, Sounds)

	self.Parent = Parent
	self.Definitions = Definitions
	self.Registry = {}
	self.Trove = Trove.new()

	for Name, Definition in Definitions do
		local SoundInstance = Instance.new("Sound")
		SoundInstance.Name = `Wallrun{Name}`
		SoundInstance.SoundId = `rbxassetid://{Definition.Id}`
		SoundInstance.Volume = Definition.Volume
		SoundInstance.RollOffMaxDistance = Definition.MaxDistance or 120
		SoundInstance.Parent = Parent

		self.Registry[Name] = SoundInstance
		self.Trove:Add(SoundInstance)
	end

	return self
end

function Sounds.Play(self: Sounds, Name: string)
	local SoundInstance = self.Registry[Name]
	local Definition = self.Definitions[Name]

	if not SoundInstance or not Definition then
		Warn(`no sound registered under "{Name}"`)
		return
	end

	if not SoundInstance.IsLoaded then
		Warn(`sound "{Name}" is not loaded yet, id {Definition.Id} may be invalid or still downloading`)
	end

	local Variance = Definition.PitchVariance
	if Variance then
		SoundInstance.PlaybackSpeed = 1 + (math.random() * 2 - 1) * Variance
	end

	SoundInstance.TimePosition = 0
	SoundInstance:Play()
end

function Sounds.Stop(self: Sounds, Name: string)
	local SoundInstance = self.Registry[Name]
	if SoundInstance then
		SoundInstance:Stop()
	end
end

function Sounds.Destroy(self: Sounds)
	self.Trove:Destroy()
	table.clear(self.Registry)
end

return Sounds
