--!strict
-- How the slide looks and sounds. Every number is in rules/slide.toml; the motion math is src/shared/SlideMath.
--   * motion: entry (lunge, lean back past the hold, settle) -> a living hold (sway, lean that follows speed)
--     -> exit (push up over the legs, stand). Each frame, right after the Animator, each R6 joint's Transform
--     (the animation channel) is lerped from what the run animation wrote toward the slide's pose. C0 is never
--     touched (fix 2026-11-17: storing C0 at spawn and restoring it undid the server's body narrowing,
--     src/server/CharacterShape.server.luau, and left gaps between the arms and the torso);
--   * VFX: a dust cloud from under the body, rock chips on real arcs (thrown, fall, bounce, tumble), a flat scrape
--     mark on the ground, wind lines streaming past, thin wind trails on the limbs. Ground colour drives the dust,
--     chips and scrape. Only Roblox's built-in particle textures (no uploads);
--   * sound: only a looped scrape whose pitch follows the speed (designer 2026-11-18: no pops going in, out or
--     jumping out, so the start whoosh, exit step and jump whoosh are gone);
--   * camera (own character only): Humanoid.CameraOffset down, field of view up.
-- Runs on every client for every sliding character (src/client/SlideView.client.luau), so all players see it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Rules = ReplicatedStorage:WaitForChild("Rules")
local f = require(Rules:WaitForChild("slide")) :: any
local p = require(Rules:WaitForChild("parkour")) :: any
local m = require(Rules:WaitForChild("movement")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local R6Pose = require(Shared:WaitForChild("R6Pose")) :: any
local SlideMath = require(Shared:WaitForChild("SlideMath"))

local SlideFeel = {}
SlideFeel.__index = SlideFeel

-- R6Pose joint name -> (part that holds the Motor6D, Motor6D name)
local MOTORS = {
	root = { "HumanoidRootPart", "RootJoint" },
	head = { "Torso", "Neck" },
	rarm = { "Torso", "Right Shoulder" },
	larm = { "Torso", "Left Shoulder" },
	rleg = { "Torso", "Right Hip" },
	lleg = { "Torso", "Left Hip" },
}
local TRAIL_LIMBS = { "Right Leg", "Left Leg", "Right Arm", "Left Arm" }
local ENTRY = SlideMath.keys(f, f.entry)

type Chip = { part: BasePart, vel: Vector3, spin: Vector3, age: number, bounced: boolean, size: number }

local function tween(obj: Instance, time: number, props: { [string]: any })
	TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function range(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function sound(parent: Instance, id: number, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume
	s.Looped = looped
	s.RollOffMaxDistance = f.sound.rollOff
	s.Parent = parent
	return s
end

function SlideFeel.new(char: Model, hum: Humanoid, hrp: BasePart, isLocal: boolean): any
	if hum.RigType ~= Enum.HumanoidRigType.R6 then
		return nil -- the pose is R6-only (the game is R6)
	end
	local self = setmetatable({}, SlideFeel) :: any
	self.char, self.hum, self.hrp, self.isLocal = char, hum, hrp, isLocal
	self.joints = {}
	for name, where in MOTORS do
		local holder = char:FindFirstChild(where[1])
		local motor = holder and holder:FindFirstChild(where[2])
		if motor and motor:IsA("Motor6D") then
			table.insert(self.joints, { name = name, motor = motor })
		end
	end
	self.phase = "idle" -- idle / entry / hold / exit
	self.phaseT = 0
	self.slideT = 0
	self.exitKeys = nil
	self.entryKeys = ENTRY
	self.entryWeightFrom = 0
	self.lastPose = nil
	self.currentPose = nil
	self.speed01 = 0
	self.chips = {} :: { Chip }
	self.chipClock = 0
	self.groundClock = 0
	self.groundColor = Color3.fromRGB(120, 120, 120)
	self.groundMaterial = Enum.Material.Slate
	self.groundY = hrp.Position.Y - 3
	self.instances = {} :: { Instance }

	local leg = char:FindFirstChild("Left Leg")
	local legLength = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	local floorY = -(hrp.Size.Y / 2 + legLength) -- the floor, in HRP space

	-- Dust: from just above the floor behind the hips, thrown back and up.
	local dustAt = Instance.new("Attachment")
	dustAt.Name = "SlideDust"
	dustAt.CFrame = CFrame.new(0, floorY + 0.3, 0.6)
	dustAt.Parent = hrp
	local d = f.dust
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "SlideDust"
	dust.Texture = d.texture
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(d.lifeMin, d.lifeMax)
	dust.Size = NumberSequence.new(d.sizeStart, d.sizeEnd)
	dust.Transparency = NumberSequence.new(d.transparencyStart, 1)
	dust.Speed = NumberRange.new(d.speedMin, d.speedMax)
	dust.Drag = d.drag
	dust.Acceleration = Vector3.new(0, d.rise, 0)
	dust.EmissionDirection = Enum.NormalId.Back
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.LightInfluence = 1
	dust.Parent = dustAt
	self.dust = dust

	-- Wind lines: from a box around the body (an invisible massless part welded to it), streaming backwards.
	local box = Instance.new("Part")
	box.Name = "SlideStreakBox"
	box.Size = Vector3.new(3, 3, 2)
	box.Transparency = 1
	box.CanCollide, box.CanQuery, box.CanTouch, box.Massless, box.CastShadow = false, false, false, true, false
	box.CFrame = hrp.CFrame * CFrame.new(0, -0.8, -1.5)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = hrp, box
	weld.Parent = box
	box.Parent = char
	local st = f.streaks
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "SlideStreaks"
	streaks.Texture = st.texture
	streaks.Rate = 0
	streaks.Lifetime = NumberRange.new(st.lifeMin, st.lifeMax)
	streaks.Speed = NumberRange.new(st.speedMin, st.speedMax)
	streaks.Size = NumberSequence.new(st.size)
	streaks.Squash = NumberSequence.new(st.squash)
	streaks.Transparency = NumberSequence.new(st.transparency, 1)
	streaks.LightEmission = st.lightEmission
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.EmissionDirection = Enum.NormalId.Back
	streaks.SpreadAngle = Vector2.new(st.spread, st.spread)
	streaks.Shape = Enum.ParticleEmitterShape.Box
	streaks.Parent = box
	self.streaks = streaks
	table.insert(self.instances, box)
	table.insert(self.instances, dustAt)

	-- Scrape mark: a Trail between two attachments on the floor, either side of the hips; it lies flat.
	local sc = f.scrape
	local s0 = Instance.new("Attachment")
	s0.Position = Vector3.new(-sc.width / 2, floorY + 0.05, 0.3)
	s0.Parent = hrp
	local s1 = Instance.new("Attachment")
	s1.Position = Vector3.new(sc.width / 2, floorY + 0.05, 0.3)
	s1.Parent = hrp
	local scrape = Instance.new("Trail")
	scrape.Name = "SlideScrape"
	scrape.Attachment0, scrape.Attachment1 = s0, s1
	scrape.Lifetime = sc.lifetime
	scrape.Transparency = NumberSequence.new(sc.transparency, 1)
	scrape.FaceCamera = false
	scrape.LightInfluence = 1
	scrape.Enabled = false
	scrape.Parent = hrp
	self.scrape = scrape
	for _, inst in { s0, s1, scrape } do
		table.insert(self.instances, inst)
	end

	-- Thin wind trails on the limbs.
	self.trails = {}
	for _, limbName in TRAIL_LIMBS do
		local limb = char:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			local tip = -limb.Size.Y / 2 + 0.2
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(-f.trail.width / 2, tip, 0)
			a0.Parent = limb
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(f.trail.width / 2, tip, 0)
			a1.Parent = limb
			local trail = Instance.new("Trail")
			trail.Name = "SlideWind"
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
			trail.Transparency = NumberSequence.new(f.trail.transparency, 1)
			trail.Lifetime = f.trail.lifetime
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.Enabled = false
			trail.Parent = limb
			table.insert(self.trails, trail)
			for _, inst in { a0, a1, trail } do
				table.insert(self.instances, inst)
			end
		end
	end

	-- Sounds, on the body so other players hear them where it is.
	local snd = f.sound
	self.sScrape = sound(hrp, snd.scrapeId, 0, true)
	for _, s in { self.sScrape } do
		table.insert(self.instances, s)
	end

	self.chipFolder = Instance.new("Folder")
	self.chipFolder.Name = "SlideChips"
	self.chipFolder.Parent = Workspace
	table.insert(self.instances, self.chipFolder)

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = { char, self.chipFolder }

	if isLocal then
		self.renderName = "SlideCamera" .. tostring(math.random(1, 1e9))
		RunService:BindToRenderStep(self.renderName, Enum.RenderPriority.Camera.Value + 2, function(dt)
			self:_cameraFrame(dt)
		end)
	end

	-- After the Animator (it writes Transform before PreSimulation), so the slide's pose wins this frame.
	self.conn = RunService.PreSimulation:Connect(function(dt)
		self:_step(dt)
	end)
	return self
end

function SlideFeel._ground(self: any)
	local hit = Workspace:Raycast(self.hrp.Position, Vector3.new(0, -8, 0), self.rayParams)
	if hit and hit.Instance:IsA("BasePart") then
		self.groundColor = (hit.Instance :: BasePart).Color
		self.groundMaterial = hit.Material
		self.groundY = hit.Position.Y
	end
	local dustColor = self.groundColor:Lerp(Color3.new(1, 1, 1), f.dust.lighten)
	self.dust.Color = ColorSequence.new(dustColor)
	self.scrape.Color = ColorSequence.new(self.groundColor:Lerp(Color3.new(0, 0, 0), f.scrape.darken))
end

function SlideFeel.set(self: any, on: boolean)
	local sliding = self.phase == "entry" or self.phase == "hold"
	if on == sliding then
		return
	end
	local snd = f.sound
	if on then
		-- Sliding again during an exit: start the entry from where the body is, already fully posed.
		local midExit = self.phase == "exit" and self.currentPose
		self.entryKeys = if midExit then SlideMath.keys(f, f.entry, self.currentPose) else ENTRY
		self.phase, self.phaseT, self.slideT = "entry", 0, 0
		self.entryWeightFrom = if midExit then 1 else 0
		self.exitScale = 1
		self.kickT, self.kickScale = 0, 1
		self:_ground()
		self.dust:Emit(f.dust.burst)
		for _ = 1, f.debris.burst do
			self:_chip()
		end
		self.sScrape.Volume = 0
		self.sScrape:Play()
		tween(self.sScrape, snd.scrapeFadeIn, { Volume = snd.scrapeVolume })
	else
		self.phase, self.phaseT = "exit", 0
		self.exitKeys = SlideMath.keys(f, f.exit, self.lastPose)
		self.dust:Emit(f.dust.exitBurst)
		if self.cancelled then
			self.cancelled = false
			self.exitScale = f.timing.cancelSpeed
			self.kickT, self.kickScale = 0, f.kick.cancelScale
		end
		tween(self.sScrape, snd.scrapeFadeOut, { Volume = 0 })
	end
	self.scrape.Enabled = on
	for _, trail in self.trails do
		trail.Enabled = on
	end
	self:_camera(on)
end

-- Cut the slide at once, with no exit motion (a vault started during the slide: its own animation must play).
function SlideFeel.interrupt(self: any)
	if self.phase == "idle" then
		return
	end
	self.phase = "idle"
	self.cancelled = false
	self.sScrape:Stop()
	self.dust.Rate, self.streaks.Rate = 0, 0
	self.scrape.Enabled = false
	for _, trail in self.trails do
		trail.Enabled = false
	end
	self:_camera(false)
end

-- Slide cancel: the next set(false) plays a faster exit and a smaller camera kick.
function SlideFeel.cancel(self: any)
	self.cancelled = true
end

-- The slide jump: silent now (designer 2026-11-18: no pop), the exit motion comes from set(false).
function SlideFeel.jump(_self: any) end

function SlideFeel._camera(self: any, on: boolean)
	if not self.isLocal then
		return
	end
	local c = f.camera
	local t = if on then c.tweenIn else c.tweenOut
	tween(self.hum, t, { CameraOffset = if on then Vector3.new(0, c.offsetY, 0) else Vector3.zero })
	self.camOn = on -- field of view, tilt and kick: _cameraFrame, every frame after the camera scripts
end

-- After Roblox's camera has placed the camera this frame: field of view and tilt follow the slide (eased), plus the
-- kick (a punch of field of view, roll and shake that settles; slide.toml [kick]).
function SlideFeel._cameraFrame(self: any, dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local c = f.camera
	local rate = if self.camOn then dt / c.tweenIn else -dt / c.tweenOut
	self.camW = math.clamp((self.camW or 0) + rate, 0, 1)
	local w = self.camW * self.camW * (3 - 2 * self.camW)
	self.kickT = (self.kickT or math.huge) + dt
	local k = SlideMath.kick(f.kick, self.kickT) * (self.kickScale or 1)
	if w <= 0 and k <= 0 then
		return
	end
	-- Added on top of the speed field of view (src/client/SpeedFeel.client.luau sets it fresh every frame, one
	-- render step earlier), so the two never fight.
	camera.FieldOfView += c.fovAdd * w + f.kick.fovPunch * k
	local shake = f.kick.shake * k
	local offset = Vector3.new((math.random() * 2 - 1) * shake, (math.random() * 2 - 1) * shake, 0)
	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(c.tilt * w + f.kick.roll * k))
end

function SlideFeel._step(self: any, dt: number)
	self:_chips(dt)
	if self.phase == "idle" then
		return
	end
	self.phaseT += if self.phase == "exit" then dt * (self.exitScale or 1) else dt
	self.slideT += dt
	local h = (self.hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	self.speed01 = math.clamp((h - p.speed.base) / (p.slide.burstSpeed - p.speed.base), 0, 1)

	-- Motion.
	local pose, amount
	local lead = f.timing.legLead
	local exitLength = if self.exitKeys then SlideMath.length(self.exitKeys) else 0
	if self.phase == "entry" then
		local len = SlideMath.length(self.entryKeys)
		pose = SlideMath.sample(R6Pose.sampleAxis, self.entryKeys, self.phaseT, lead)
		amount = math.clamp(self.phaseT / len, 0, 1)
		if self.phaseT >= len then
			self.phase, self.phaseT = "hold", 0
		end
	elseif self.phase == "hold" then
		pose = SlideMath.sample(R6Pose.sampleAxis, ENTRY, SlideMath.length(ENTRY), 0)
		amount = 1
	else
		pose = SlideMath.sample(R6Pose.sampleAxis, self.exitKeys, self.phaseT, -lead)
		amount = 0
	end
	if self.phase ~= "exit" then
		SlideMath.alive(f, pose, self.slideT, self.speed01, amount)
		self.lastPose = pose
	end
	self.currentPose = pose
	local w = SlideMath.weight(f, self.phase, self.phaseT, exitLength)
	if self.phase == "entry" then
		w = math.max(w, self.entryWeightFrom)
	end
	for _, j in self.joints do
		j.motor.Transform = j.motor.Transform:Lerp(R6Pose.transform(CFrame, j.name, pose[j.name]), w)
	end
	if self.phase == "exit" and self.phaseT >= exitLength then
		self.phase = "idle"
		self.sScrape:Stop()
		self.dust.Rate, self.streaks.Rate = 0, 0
		return
	end

	-- Effects that follow the speed while sliding.
	local sliding = self.phase ~= "exit"
	self.groundClock += dt
	if self.groundClock > 0.2 then
		self.groundClock = 0
		self:_ground()
	end
	self.dust.Rate = if sliding then f.dust.ratePerSpeed * h else 0
	self.streaks.Rate = if sliding then f.streaks.rate * (0.4 + 0.6 * self.speed01) else 0
	self.sScrape.PlaybackSpeed = f.sound.scrapePitchMin
		+ (f.sound.scrapePitchMax - f.sound.scrapePitchMin) * self.speed01
	if sliding then
		self.chipClock += dt * f.debris.ratePerSpeed * h
		while self.chipClock >= 1 do
			self.chipClock -= 1
			self:_chip()
		end
	end
end

-- One rock chip: thrown up and back from under the body, with spin.
function SlideFeel._chip(self: any)
	local db = f.debris
	local size = range(db.minSize, db.maxSize)
	local look = (self.hrp.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local right = self.hrp.CFrame.RightVector
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Size = Vector3.new(size, size * range(0.6, 1), size * range(0.7, 1.2))
	part.Material = self.groundMaterial
	part.Color = self.groundColor:Lerp(Color3.new(0, 0, 0), db.darken * math.random())
	local start = Vector3.new(self.hrp.Position.X, self.groundY + size / 2, self.hrp.Position.Z)
		+ right * range(-0.8, 0.8)
		+ look * range(-0.5, 1)
	part.CFrame = CFrame.new(start) * CFrame.Angles(range(0, 6), range(0, 6), range(0, 6))
	part.Parent = self.chipFolder
	local vel = Vector3.new(0, range(db.upMin, db.upMax), 0)
		- look * range(db.backMin, db.backMax)
		+ right * range(-db.side, db.side)
		+ self.hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.3
	table.insert(self.chips, {
		part = part,
		vel = vel,
		spin = Vector3.new(range(-15, 15), range(-15, 15), range(-15, 15)),
		age = 0,
		bounced = false,
		size = size,
	})
end

-- Flies every chip: gravity, one bounce off the ground, tumble, fade out.
function SlideFeel._chips(self: any, dt: number)
	local db = f.debris
	local keep = {}
	for _, c in self.chips do
		c.age += dt
		if c.age >= db.life then
			c.part:Destroy()
			continue
		end
		c.vel -= Vector3.new(0, m.gravity * dt, 0)
		local pos = c.part.Position + c.vel * dt
		local floor = self.groundY + c.size / 2
		if pos.Y < floor and c.vel.Y < 0 then
			pos = Vector3.new(pos.X, floor, pos.Z)
			if c.bounced then
				c.vel = Vector3.new(c.vel.X * 0.5, 0, c.vel.Z * 0.5)
				c.spin *= 0.5
			else
				c.bounced = true
				c.vel = Vector3.new(c.vel.X * 0.6, -c.vel.Y * db.bounce, c.vel.Z * 0.6)
			end
		end
		c.part.CFrame = CFrame.new(pos)
			* c.part.CFrame.Rotation
			* CFrame.Angles(c.spin.X * dt, c.spin.Y * dt, c.spin.Z * dt)
		local fade = c.age / db.life
		c.part.Transparency = fade * fade
		table.insert(keep, c)
	end
	self.chips = keep
end

function SlideFeel.destroy(self: any)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	for _, c in self.chips do
		c.part:Destroy()
	end
	for _, inst in self.instances do
		inst:Destroy()
	end
	if self.renderName then
		RunService:UnbindFromRenderStep(self.renderName)
	end
	if self.isLocal then
		self.hum.CameraOffset = Vector3.zero
	end
end

return SlideFeel
