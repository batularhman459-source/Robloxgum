--!strict
-- The double jump's frontflip, its effects and its sound (rules/flip.toml, timeline in src/shared/FlipMath.luau):
--   * motion: a tuck frontflip, one full forward turn about the torso in 0.4 s. Each frame, right after the
--     Animator, the R6 joints' Transform is lerped from the jump animation toward the flip pose (like the slide,
--     src/client/SlideFeel.luau: C0 is never touched);
--   * VFX at the take-off point: one animated anime shockwave ring from the designer's own VFX pack (Anime/Shoot-01,
--     designer 2026-11-18: "pick one fitting from my packs"), lying flat under the feet and left where you kicked off;
--   * sound: a soft whoosh, a little pitch variation each time.
-- Runs for every character on every client: ParkourController plays the local one, SlideView.client the others.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local r = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("flip")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local R6Pose = require(Shared:WaitForChild("R6Pose")) :: any
local SlideMath = require(Shared:WaitForChild("SlideMath"))
local FlipMath = require(Shared:WaitForChild("FlipMath"))

local FlipFeel = {}
FlipFeel.__index = FlipFeel

local MOTORS = {
	root = { "HumanoidRootPart", "RootJoint" },
	head = { "Torso", "Neck" },
	rarm = { "Torso", "Right Shoulder" },
	larm = { "Torso", "Left Shoulder" },
	rleg = { "Torso", "Right Hip" },
	lleg = { "Torso", "Left Hip" },
}
local KEYS = FlipMath.keys(r)
local LENGTH = FlipMath.length(KEYS)

local function range(a: number, b: number): number
	return a + math.random() * (b - a)
end

function FlipFeel.new(char: Model, hum: Humanoid, hrp: BasePart): any
	if hum.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end
	local self = setmetatable({}, FlipFeel) :: any
	self.hrp = hrp
	self.t = nil -- seconds into the flip, nil when not flipping
	self.joints = {}
	for name, where in MOTORS do
		local holder = char:FindFirstChild(where[1])
		local motor = holder and holder:FindFirstChild(where[2])
		if motor and motor:IsA("Motor6D") then
			table.insert(self.joints, { name = name, motor = motor })
		end
	end
	self.instances = {}

	local leg = char:FindFirstChild("Left Leg")
	local legLength = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	self.feetY = -(hrp.Size.Y / 2 + legLength)

	-- The ring (the designer's pack Anime/Shoot-01): one flipbook particle at the feet, emitted straight down so its
	-- face lies flat, left in the world where you kicked off the air.
	local g = r.ring
	local ringAt = Instance.new("Attachment")
	ringAt.Name = "FlipRing"
	ringAt.Position = Vector3.new(0, self.feetY, 0)
	ringAt.Parent = hrp
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = g.texture
	ring.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	ring.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ring.EmissionDirection = Enum.NormalId.Bottom
	ring.SpreadAngle = Vector2.zero
	ring.Speed = NumberRange.new(0.01)
	ring.Rate = 0
	ring.Lifetime = NumberRange.new(g.life)
	ring.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, g.sizeStart * g.scale),
		NumberSequenceKeypoint.new(0.5, g.sizeMid * g.scale),
		NumberSequenceKeypoint.new(1, g.sizeEnd * g.scale),
	})
	ring.Rotation = NumberRange.new(-360, 360)
	ring.Brightness = g.brightness
	ring.LightEmission = g.lightEmission
	ring.LightInfluence = 0
	ring.ZOffset = g.zOffset
	ring.LockedToPart = false
	ring.Parent = ringAt
	self.ring = ring
	table.insert(self.instances, ringAt)

	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(r.sound.id)
	s.Volume = r.sound.volume
	s.RollOffMaxDistance = r.sound.rollOff
	s.Parent = hrp
	self.sound = s

	for _, inst in { s } do
		table.insert(self.instances, inst)
	end

	-- After the Animator, so the flip's pose wins this frame.
	self.conn = RunService.PreSimulation:Connect(function(dt)
		self:_step(dt)
	end)
	return self
end

-- Starts a flip: the motion, the ring and puff at the take-off point, the whoosh.
function FlipFeel.play(self: any)
	self.t = 0
	self.ring:Emit(1)
	self.sound.PlaybackSpeed = range(r.sound.pitchMin, r.sound.pitchMax)
	self.sound:Play()
end

function FlipFeel._step(self: any, dt: number)
	if not self.t then
		return
	end
	self.t += dt
	if self.t >= LENGTH then
		self.t = nil
		return
	end
	local pose = SlideMath.sample(R6Pose.sampleAxis, KEYS, self.t, 0)
	local w = FlipMath.weight(r, self.t, LENGTH)
	for _, j in self.joints do
		j.motor.Transform = j.motor.Transform:Lerp(R6Pose.transform(CFrame, j.name, pose[j.name]), w)
	end
end

function FlipFeel.destroy(self: any)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	for _, inst in self.instances do
		inst:Destroy()
	end
end

return FlipFeel
