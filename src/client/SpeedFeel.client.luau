--!strict
-- Sense of speed for this player (rules/speedfeel.toml, curves in src/shared/SpeedFeelMath.luau):
--   * the field of view widens smoothly with horizontal speed. It is set fresh every frame right after Roblox's
--     camera; the slide adds its own bit on top one step later (src/client/SlideFeel.luau);
--   * radial anime speed lines: thin straight lines drawn on the screen (a ScreenGui overlay, no assets), each
--     pointing at the centre, spawning toward the edges, sliding outward and fading. How many follows the speed.
--     (The first version used 3D particle streaks; the designer found them "like rain going all over the place".)
-- This is an effect overlay, not a menu: it has no spec/preview by design (ui/ specs are for menus and HUDs).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local r = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("speedfeel")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpeedFeelMath = require(Shared:WaitForChild("SpeedFeelMath"))
local UiLayout = require(Shared:WaitForChild("ui"):WaitForChild("UiLayout")) :: any
local theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Themes"):WaitForChild("house")) :: any

local player = Players.LocalPlayer
local l = r.lines

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedLines"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = -1 -- under the HUD
gui.Parent = player:WaitForChild("PlayerGui")

type Line = { frame: Frame, angle: number, inner: number, length: number, life: number, age: number }
local lines: { Line } = {}
local pool: { Frame } = {}
local spawnClock = 0

local function newLine(): Line
	local frame: Frame = table.remove(pool)
		or (function(): Frame
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.BorderSizePixel = 0
			f.Parent = gui
			return f
		end)()
	frame.Visible = true
	local function range(a: number, b: number): number
		return a + math.random() * (b - a)
	end
	return {
		frame = frame,
		angle = math.random() * 2 * math.pi,
		inner = range(l.innerMin, l.innerMax),
		length = range(l.lengthMin, l.lengthMax),
		life = range(l.lifeMin, l.lifeMax),
		age = 0,
	}
end

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

	-- Lines: spawn at the speed's rate, move and fade the live ones, recycle the dead ones.
	local size = gui.AbsoluteSize
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return
	end
	local thickness = l.thickness * UiLayout.scaleFor(theme, w, h)
	spawnClock += dt * SpeedFeelMath.lineRate(r, speed)
	while spawnClock >= 1 do
		spawnClock -= 1
		table.insert(lines, newLine())
	end
	local keep = {}
	for _, line in lines do
		line.age += dt
		if line.age >= line.life then
			line.frame.Visible = false
			table.insert(pool, line.frame)
			continue
		end
		local cx, cy, length, rot, transparency = SpeedFeelMath.radialLine(r, line, line.age, w, h)
		line.frame.Position = UDim2.fromOffset(cx, cy)
		line.frame.Size = UDim2.fromOffset(length, thickness)
		line.frame.Rotation = rot
		line.frame.BackgroundTransparency = transparency
		table.insert(keep, line)
	end
	lines = keep
end)
