--!strict

local Log = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("Log"))
local Trove = require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("Trove"))

local Logger = Log.new()

local function Info(Message: string)
	Logger:AtInfo():Log(Message:lower())
end

local function Warn(Message: string)
	Logger:AtWarning():Log(Message:lower())
end

local Template = script:WaitForChild("Folder")

local Attachment0Name = "WallJumpTrailAttachment0"
local Attachment1Name = "WallJumpTrailAttachment1"
local TrailName = "WallJumpTrail"

local DefaultLimbs = { "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

local Trails = {}
Trails.__index = Trails

export type Trails = typeof(setmetatable(
	{} :: {
		Character: Model,
		Limbs: { string },
		Instances: { Trail },
		Active: boolean,
		BurstTime: number,
		Trove: Trove.Trove,
		BurstTrove: Trove.Trove,
	},
	Trails
))

local function BuildTrail(Limb: BasePart, OwnerTrove: Trove.Trove): Trail?
	local Clone = Template:Clone()

	local Attachments: { Attachment } = {}
	for _, Descendant in Clone:GetDescendants() do
		if Descendant:IsA("Attachment") then
			table.insert(Attachments, Descendant)
		end
	end

	table.sort(Attachments, function(A: Attachment, B: Attachment): boolean
		return A.Name < B.Name
	end)

	local TrailInstance = Clone:FindFirstChildWhichIsA("Trail", true) :: Trail?

	if #Attachments < 2 or not TrailInstance then
		Clone:Destroy()
		Warn(
			`trail template invalid for {Limb.Name}: found {#Attachments} attachments and trail={TrailInstance ~= nil}`
		)
		return nil
	end

	local Attachment0 = Attachments[1]
	local Attachment1 = Attachments[2]

	Attachment0.Name = Attachment0Name
	Attachment1.Name = Attachment1Name
	Attachment0.Parent = Limb
	Attachment1.Parent = Limb

	TrailInstance.Name = TrailName
	TrailInstance.Attachment0 = Attachment0
	TrailInstance.Attachment1 = Attachment1
	TrailInstance.Enabled = false
	TrailInstance.Parent = Limb

	Clone:Destroy()

	OwnerTrove:Add(Attachment0)
	OwnerTrove:Add(Attachment1)
	OwnerTrove:Add(TrailInstance)

	return TrailInstance
end

function Trails.new(Character: Model, Limbs: { string }?): Trails
	local self = setmetatable({}, Trails)

	self.Character = Character
	self.Limbs = Limbs or DefaultLimbs
	self.Instances = {}
	self.Active = false
	self.BurstTime = 0
	self.Trove = Trove.new()
	self.BurstTrove = self.Trove:Extend()

	for _, LimbName in self.Limbs do
		local Limb = Character:FindFirstChild(LimbName)

		if not Limb or not Limb:IsA("BasePart") then
			Warn(`limb "{LimbName}" not found on {Character.Name}, skipped`)
			continue
		end

		local Created = BuildTrail(Limb, self.Trove)
		if Created then
			table.insert(self.Instances, Created)
		end
	end

	Info(`built {#self.Instances} of {#self.Limbs} limb trails`)

	self.Trove:AttachToInstance(Character)

	return self
end

function Trails.SetEnabled(self: Trails, Enabled: boolean)
	for _, TrailInstance in self.Instances do
		TrailInstance.Enabled = Enabled
	end
end

function Trails.Burst(self: Trails, Duration: number)
	self.BurstTrove:Clean()
	self.Active = true
	self.BurstTime = os.clock()
	self:SetEnabled(true)

	self.BurstTrove:Add(task.delay(Duration, function()
		self.Active = false
		self:SetEnabled(false)
	end))
end

function Trails.Stop(self: Trails)
	if not self.Active then
		return
	end

	self.BurstTrove:Clean()
	self.Active = false
	self:SetEnabled(false)
end

function Trails.Destroy(self: Trails)
	self.Trove:Destroy()
	table.clear(self.Instances)
end

return Trails
