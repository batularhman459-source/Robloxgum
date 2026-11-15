--!strict
-- Builds Workspace.ParkourLane: a straight test lane for the parkour moves, running along +X from
-- ORIGIN. Run in Edit mode: require(game:GetService("ReplicatedStorage").DevTools.ParkourLane:Clone()).build()
-- Stations (x from ORIGIN): 0 start, 30 vault box (3 high), 60-140 wall-run wall on the left (z = -6),
-- 160 gap of 13 studs (single jump ~10.8 is not enough, double jump is), 200 tower 20 high (fall test).
-- Slide test on the right half (z 2..14): bar at x 90 then a 6 stud tunnel at x 94..100, both 3 studs high.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ParkourLane = {}

ParkourLane.ORIGIN = Vector3.new(0, 0, 700)

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = ParkourLane.ORIGIN + pos
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color or Color3.fromRGB(150, 155, 165)
	p.Parent = parent
	return p
end

function ParkourLane.build(): Model
	local old = Workspace:FindFirstChild("ParkourLane")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "ParkourLane"
	local green = Color3.fromRGB(110, 140, 90)

	part(m, "FloorA", Vector3.new(185, 2, 30), Vector3.new(72.5, -1, 0), green) -- x -20 .. 165
	part(m, "FloorB", Vector3.new(80, 2, 30), Vector3.new(218, -1, 0), green) -- x 178 .. 258 (13 stud gap)
	part(m, "GapPit", Vector3.new(13, 1, 30), Vector3.new(171.5, -10.5, 0))
	part(m, "GapStairs", Vector3.new(4, 9, 30), Vector3.new(176, -6, 0)) -- climb out of the pit (no trap)
	part(m, "VaultBox", Vector3.new(2, 3, 16), Vector3.new(30, 1.5, 0), Color3.fromRGB(200, 160, 90))
	part(m, "WallRunWall", Vector3.new(80, 14, 1), Vector3.new(100, 7, -6.5), Color3.fromRGB(90, 110, 170))
	-- Slide gap: a bar across the right half of the lane (z 2..14) whose underside is 3 studs up.
	-- Standing (5.5 tall) you hit it; sliding (2.5) you pass under. Low tunnel after it: 3 high, 6 long.
	part(m, "LowBar", Vector3.new(2, 2, 12), Vector3.new(90, 4, 8), Color3.fromRGB(220, 80, 80))
	part(m, "LowTunnel", Vector3.new(6, 2, 12), Vector3.new(97, 4, 8), Color3.fromRGB(220, 80, 80))
	part(m, "TowerLeg", Vector3.new(6, 20, 6), Vector3.new(215, 10, 9))
	part(m, "TowerTop", Vector3.new(10, 1, 10), Vector3.new(215, 20.5, 9))

	local spawn = part(m, "LaneStart", Vector3.new(2, 0.2, 2), Vector3.new(0, 0.1, 0), Color3.fromRGB(80, 160, 255))
	spawn.CanCollide, spawn.CanQuery, spawn.Transparency = false, false, 0.5
	CollectionService:AddTag(spawn, "MapSpawn")

	m.Parent = Workspace
	return m
end

return ParkourLane
