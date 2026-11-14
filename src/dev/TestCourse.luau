--!strict
-- Builds Workspace.TestCourse: a small map with one planted flaw per map check, to prove MapProbe
-- finds them. Run in Edit mode: require(game:GetService("ReplicatedStorage").DevTools.TestCourse).build()
-- Every flaw is named after the check that must catch it.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TestCourse = {}

local ORIGIN = Vector3.new(400, 0, 0) -- away from the baseplate

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = ORIGIN + pos
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(150, 155, 165)
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function marker(parent: Instance, name: string, pos: Vector3, tag: string, attrs: { [string]: any }?): Part
	local p = part(parent, name, Vector3.new(1, 0.2, 1), pos + Vector3.new(0, 0.1, 0), {
		CanCollide = false,
		CanQuery = false,
		Transparency = 0.5,
		Color = Color3.fromRGB(80, 160, 255),
	})
	CollectionService:AddTag(p, tag)
	for k, v in attrs or {} do
		p:SetAttribute(k, v)
	end
	return p
end

function TestCourse.build(): Model
	local old = Workspace:FindFirstChild("TestCourse")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "TestCourse"

	-- Floor 120 x 80 with a 10 x 10 hole at x 20..30, z -5..5. Top of the floor is y = 0.
	local floorProps = { Color = Color3.fromRGB(110, 140, 90) }
	part(m, "FloorWest", Vector3.new(80, 2, 80), Vector3.new(-20, -1, 0), floorProps)
	part(m, "FloorEast", Vector3.new(30, 2, 80), Vector3.new(45, -1, 0), floorProps)
	part(m, "FloorNorth", Vector3.new(10, 2, 35), Vector3.new(25, -1, 22.5), floorProps)
	part(m, "FloorSouth", Vector3.new(10, 2, 35), Vector3.new(25, -1, -22.5), floorProps)

	-- [No way out] Pit under the hole: 12 studs deep, higher than any jump.
	part(m, "TrapPitWallN", Vector3.new(10, 12, 1), Vector3.new(25, -8, 5.5))
	part(m, "TrapPitWallS", Vector3.new(10, 12, 1), Vector3.new(25, -8, -5.5))
	part(m, "TrapPitWallE", Vector3.new(1, 12, 12), Vector3.new(30.5, -8, 0))
	part(m, "TrapPitWallW", Vector3.new(1, 12, 12), Vector3.new(19.5, -8, 0))
	part(m, "TrapPitBottom", Vector3.new(12, 1, 12), Vector3.new(25, -14.5, 0))

	marker(m, "Spawn", Vector3.new(-50, 0, 0), "MapSpawn")
	marker(m, "A", Vector3.new(-40, 0, -20), "MapWaypoint", { Label = "A", SightTo = "B", Sight = "open" })
	marker(m, "B", Vector3.new(-40, 0, 20), "MapWaypoint", { Label = "B" })
	-- [Sight lines] A wall between A and B, but A expects an open view of B.
	part(m, "SightBlockingWall", Vector3.new(16, 10, 1), Vector3.new(-40, 5, 0))

	-- [Floating platforms] Platform in mid air, touching nothing.
	part(m, "FloatingPlatform", Vector3.new(8, 1, 8), Vector3.new(0, 6, -25))

	-- [Floating tops] A hut whose roof hovers 0.3 studs above its walls.
	part(m, "HutWallN", Vector3.new(10, 8, 1), Vector3.new(0, 4, 24.5))
	part(m, "HutWallS", Vector3.new(10, 8, 1), Vector3.new(0, 4, 15.5))
	part(m, "HutWallE", Vector3.new(1, 8, 8), Vector3.new(4.5, 4, 20))
	part(m, "HutWallW", Vector3.new(1, 8, 8), Vector3.new(-4.5, 4, 20))
	part(m, "HoveringRoof", Vector3.new(11, 1, 11), Vector3.new(0, 8.8, 20))

	-- [Unreachable] Ledge on a 20 stud pillar.
	part(m, "Pillar", Vector3.new(4, 20, 4), Vector3.new(-20, 10, 30))
	part(m, "UnreachableLedge", Vector3.new(10, 1, 10), Vector3.new(-20, 20.5, 30))

	-- [Shouldn't reach] Area behind the course is reachable but marked no-access.
	local noAccess = part(m, "NoAccessZone", Vector3.new(10, 8, 10), Vector3.new(52, 4, 30), {
		CanCollide = false,
		CanQuery = false,
		Transparency = 0.8,
		Color = Color3.fromRGB(180, 60, 220),
	})
	CollectionService:AddTag(noAccess, "MapNoAccess")

	-- [Overlaps] Two crates pushed 1.5 studs into each other.
	part(m, "OverlapCrateA", Vector3.new(4, 4, 4), Vector3.new(-30, 2, -30))
	part(m, "OverlapCrateB", Vector3.new(4, 4, 4), Vector3.new(-27.5, 2, -30))

	-- [Uneven ring] 8 pillars in a ring, one pushed out 0.6 and up 0.3.
	local ring = Instance.new("Model")
	ring.Name = "PillarRing"
	CollectionService:AddTag(ring, "MapRing")
	for i = 0, 7 do
		local a = i * math.pi / 4
		local r, y = 10, 3
		if i == 2 then
			r, y = 10.6, 3.3
		end
		part(
			ring,
			"RingPillar" .. i,
			Vector3.new(1.5, 6, 1.5),
			Vector3.new(15 + math.cos(a) * r, y, -28 + math.sin(a) * r)
		)
	end
	ring.Parent = m

	-- [Unsafe fall] Ramp up to a 40 stud tower; stepping off the back is a 40 stud fall.
	local ramp = Instance.new("WedgePart")
	ramp.Name = "TowerRamp"
	ramp.Anchored = true
	ramp.Size = Vector3.new(8, 40, 70)
	-- Ramp starts at the east edge of the floor (x = 60) and climbs to x = 130, on its own ground.
	ramp.CFrame = CFrame.new(ORIGIN + Vector3.new(95, 20, 0)) * CFrame.Angles(0, math.rad(90), 0)
	ramp.Color = Color3.fromRGB(150, 155, 165)
	ramp.Parent = m
	part(m, "TowerGround", Vector3.new(80, 2, 30), Vector3.new(100, -1, 0), floorProps)
	part(m, "TowerTop", Vector3.new(8, 1, 8), Vector3.new(134, 39.5, 0))
	part(m, "TowerLeg", Vector3.new(4, 39, 4), Vector3.new(134, 19.5, 0))

	-- [Awkward drop] A 3 stud box: jumping on is fine, stepping off is a stumble.
	part(m, "AwkwardBox", Vector3.new(6, 3, 6), Vector3.new(-10, 1.5, -10))

	m.Parent = Workspace
	return m
end

return TestCourse
