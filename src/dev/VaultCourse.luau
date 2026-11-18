--!strict
-- Builds Workspace.VaultCourse: side-by-side lanes for testing the toolbox vault (src/client/Vault.client.luau,
-- rules/vault.toml). Run in Edit mode:
--   require(game:GetService("ReplicatedStorage").DevTools.VaultCourse:Clone()).build()
-- or build(Vector3.new(x, y, z)) to put it somewhere else. Every lane runs along -Z: start on the blue pad,
-- hold W, press Space near the obstacle. A sign at each start says what the lane tests and what should happen.
-- Heights are measured from the floor (the vault measures from the feet): step 1-2, normal 2-4, nothing
-- above 4.0 (rules/vault.toml; the high climb is off for now).
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local VaultCourse = {}

-- Beside the place's SpawnLocation (x -42.6, z 691), clear of it; 0.1 up so the floor does not z-fight
-- with the Baseplate.
VaultCourse.ORIGIN = Vector3.new(-175, 0.1, 700)
VaultCourse.LANE_WIDTH = 10
VaultCourse.RUNUP = 30 -- start pad to obstacle

-- name, obstacle size (x = across the lane, y = height, z = depth), what should happen, extra
type Lane = { name: string, size: Vector3, expect: string, count: number?, gap: number?, tag: string? }
VaultCourse.LANES = {
	{ name = "Curb 0.8", size = Vector3.new(6, 0.8, 1.5), expect = "too low: just run over it" },
	{ name = "Step 1.5", size = Vector3.new(6, 1.5, 1.5), expect = "step vault" },
	{ name = "Normal 2", size = Vector3.new(6, 2, 1.5), expect = "normal vault (the small ledge)" },
	{ name = "Normal 3", size = Vector3.new(6, 3, 1.5), expect = "normal vault" },
	{ name = "Deep 3 x 4", size = Vector3.new(6, 3, 4), expect = "normal vault over a deep box" },
	{ name = "Ledge 4.3", size = Vector3.new(6, 4.3, 1.5), expect = "over the 4.0 cap: no vault (high climb off)" },
	{ name = "Ledge 5", size = Vector3.new(6, 5, 1.5), expect = "over the cap: no vault" },
	{ name = "Wall 8", size = Vector3.new(6, 8, 1.5), expect = "too tall: no vault, you stop" },
	{ name = "Post 2", size = Vector3.new(1.5, 2, 1.5), expect = "narrow post: vault only if aimed at it" },
	{ name = "Chain 3x2", size = Vector3.new(6, 2, 1.5), expect = "three ledges in a row", count = 3, gap = 9 },
	{
		name = "Unvaultable 3",
		size = Vector3.new(6, 3, 1.5),
		expect = "tagged Unvaultable: no vault",
		tag = "Unvaultable",
	},
} :: { Lane }

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A sign facing the runner at the lane start: lane name + expected result.
local function sign(parent: Instance, pos: Vector3, title: string, expect: string)
	local board = part(parent, "Sign", Vector3.new(7, 2.4, 0.3), pos, Color3.fromRGB(30, 32, 40))
	board.CanCollide, board.CanQuery = false, false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the runner starts on the +Z side, looking -Z, so this face is toward them
	gui.CanvasSize = Vector2.new(700, 240)
	gui.Parent = board
	local function label(text: string, y: number, h: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, y)
		l.Size = UDim2.fromScale(0.94, h)
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextWrapped = true
		l.Text = text
		l.Parent = gui
	end
	label(title, 0.05, 0.45, 64, Color3.fromRGB(255, 220, 120))
	label(expect, 0.5, 0.45, 36, Color3.fromRGB(230, 235, 245))
end

function VaultCourse.build(origin: Vector3?): Model
	local o = origin or VaultCourse.ORIGIN
	local old = Workspace:FindFirstChild("VaultCourse")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "VaultCourse"
	local lanes = VaultCourse.LANES
	local w = VaultCourse.LANE_WIDTH
	local length = VaultCourse.RUNUP + 50
	local width = #lanes * w + 4

	-- Floor slab (top at o.Y), with a darker stripe between lanes so they read apart.
	part(
		m,
		"Floor",
		Vector3.new(width, 2, length),
		o + Vector3.new(width / 2 - 2, -1, -length / 2 + 5),
		Color3.fromRGB(70, 76, 86)
	)

	for i, lane in lanes do
		local x = o.X + (i - 1) * w + w / 2
		local startZ = o.Z
		local obstacleZ = startZ - VaultCourse.RUNUP
		local folder = Instance.new("Folder")
		folder.Name = string.format("%02d %s", i, lane.name)
		folder.Parent = m

		part(
			folder,
			"Divider",
			Vector3.new(0.4, 0.05, length - 10),
			Vector3.new(x + w / 2, o.Y + 0.025, startZ - length / 2 + 5),
			Color3.fromRGB(50, 54, 62)
		)
		local pad = part(
			folder,
			"Start",
			Vector3.new(4, 0.2, 4),
			Vector3.new(x, o.Y + 0.1, startZ),
			Color3.fromRGB(80, 160, 255)
		)
		pad.CanCollide = false
		sign(folder, Vector3.new(x, o.Y + 7.5, startZ - 3), lane.name, lane.expect) -- high: you run under it

		for k = 1, lane.count or 1 do
			local z = obstacleZ - (k - 1) * (lane.gap or 0)
			local box = part(
				folder,
				"Obstacle",
				lane.size,
				Vector3.new(x, o.Y + lane.size.Y / 2, z - lane.size.Z / 2),
				if lane.tag then Color3.fromRGB(200, 70, 70) else Color3.fromRGB(215, 170, 90)
			)
			if lane.tag then
				CollectionService:AddTag(box, lane.tag)
			end
		end
	end

	-- One spawn marker at the first lane start (for MapProbe and for teleporting there).
	local spawn =
		part(m, "CourseStart", Vector3.new(2, 0.2, 2), o + Vector3.new(w / 2, 0.1, 4), Color3.fromRGB(80, 160, 255))
	spawn.CanCollide, spawn.CanQuery, spawn.Transparency = false, false, 0.5
	CollectionService:AddTag(spawn, "MapSpawn")

	m.Parent = Workspace
	return m
end

return VaultCourse
