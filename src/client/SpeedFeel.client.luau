--!strict
-- Sense of speed for this player (rules/speedfeel.toml, curves in src/shared/SpeedFeelMath.luau):
--   * the field of view widens smoothly with horizontal speed. It is set fresh every frame right after Roblox's
--     camera; the slide adds its own bit on top one step later (src/client/SlideFeel.luau);
--   * wind lines stream past the screen edges when fast: a particle ring on an invisible part held in front of the
--     camera, the lines flying towards and past it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local r = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("speedfeel")) :: any
local SpeedFeelMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpeedFeelMath"))

local player = Players.LocalPlayer

-- The wind-line ring: a thin invisible disc (a cylinder part, its axis along X), its emitter spawning on the rim
-- (Surface) and shooting the lines along the axis, which points back at the camera.
local l = r.lines
local ring = Instance.new("Part")
ring.Name = "SpeedLines"
ring.Shape = Enum.PartType.Cylinder
ring.Size = Vector3.new(0.2, l.radius * 2, l.radius * 2)
ring.Transparency = 1
ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
local lines = Instance.new("ParticleEmitter")
lines.Texture = l.texture
lines.Rate = 0
lines.Lifetime = NumberRange.new(l.lifeMin, l.lifeMax)
lines.Speed = NumberRange.new(l.speedMin, l.speedMax)
lines.Size = NumberSequence.new(l.width)
lines.Squash = NumberSequence.new(l.squash)
lines.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, l.transparency),
	NumberSequenceKeypoint.new(1, 1),
})
lines.LightEmission = l.lightEmission
lines.LightInfluence = 0
lines.Orientation = Enum.ParticleOrientation.VelocityParallel
lines.Shape = Enum.ParticleEmitterShape.Disc
lines.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
lines.EmissionDirection = Enum.NormalId.Right -- along the cylinder's axis, turned to face the camera below
lines.LockedToPart = true -- the lines move with the camera, so they read as screen-space streaks
lines.Parent = ring

local fov = r.fov.base
RunService:BindToRenderStep("SpeedFeel", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local speed = 0
	if hrp and hrp:IsA("BasePart") then
		speed = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	end
	fov = SpeedFeelMath.follow(fov, r.fov.base + SpeedFeelMath.fovExtra(r, speed), dt, r.fov.smoothing)
	camera.FieldOfView = fov

	if ring.Parent ~= camera then
		ring.Parent = camera
	end
	-- In front of the camera, its axis (X) pointing back at the camera.
	ring.CFrame = camera.CFrame * CFrame.new(0, 0, -l.distance) * CFrame.Angles(0, -math.pi / 2, 0)
	lines.Rate = SpeedFeelMath.lineRate(r, speed)
end)
