--!strict
-- Short camera kicks for the moves (rules/camera.toml): a field-of-view punch, a roll, a dip and a shake that rise fast
-- and settle (SlideMath.kick's curve). Several kicks add up. Applied after everything else that moves the camera
-- (Roblox's camera, SpeedFeel at Camera + 1, the slide and wall run at Camera + 2), and only ever added on top.
-- Used by ParkourController (flip, landing) and Vault.client (vault). Designer 2026-11-19: camera that fits the wall run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local r = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("camera")) :: any
local SlideMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlideMath"))

local CameraKick = {}

type Kick = { k: any, t: number, scale: number, side: number }
local active: { Kick } = {}

-- Starts the kick named in rules/camera.toml, at `scale` (0..1, default 1) of its strength.
function CameraKick.kick(name: string, scale: number?)
	local k = r[name]
	if not k then
		return
	end
	table.insert(active, { k = k, t = 0, scale = scale or 1, side = if math.random() < 0.5 then -1 else 1 })
end

-- The landing kick's strength for a fall height: none below land.minFall, full from land.fullFall.
function CameraKick.landScale(fall: number): number
	local l = r.land
	return math.clamp((fall - l.minFall) / (l.fullFall - l.minFall), 0, 1)
end

RunService:BindToRenderStep("CameraKick", Enum.RenderPriority.Camera.Value + 3, function(dt)
	if #active == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local fov, roll, dip, shake = 0, 0, 0, 0
	local keep = {}
	for _, e in active do
		e.t += dt
		if e.t < e.k.time then
			local w = SlideMath.kick(e.k, e.t) * e.scale
			fov += e.k.fov * w
			roll += e.k.roll * w * e.side
			dip += e.k.dip * w
			shake += e.k.shake * w
			table.insert(keep, e)
		end
	end
	active = keep
	camera.FieldOfView += fov
	local offset = Vector3.new((math.random() * 2 - 1) * shake, (math.random() * 2 - 1) * shake - dip, 0)
	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(roll))
end)

return CameraKick
