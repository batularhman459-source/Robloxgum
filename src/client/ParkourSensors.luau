--!strict
-- Measures the world around the character with raycasts and returns plain tables for Parkour.luau.
-- No decisions here: this only answers "where is the ground, is there a wall at my side, what is ahead".
local Workspace = game:GetService("Workspace")

local Sensors = {}
Sensors.__index = Sensors

export type Sensors = typeof(setmetatable(
	{} :: {
		char: Model,
		hrp: BasePart,
		hum: Humanoid,
		p: any,
		params: RaycastParams,
	},
	Sensors
))

function Sensors.new(char: Model, hrp: BasePart, hum: Humanoid, p: any): Sensors
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	return setmetatable({ char = char, hrp = hrp, hum = hum, p = p, params = params }, Sensors)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zero
end
Sensors.flat = flat

-- Distance from the bottom of the root part down to the feet. R15 uses HipHeight; R6 always reports
-- HipHeight 0 because its 2 stud legs hold the body up (playtest: the vault box read as 1 stud high).
function Sensors.legLength(self: Sensors): number
	if self.hum.RigType == Enum.HumanoidRigType.R6 then
		local leg = self.char:FindFirstChild("Left Leg")
		return if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	end
	return self.hum.HipHeight
end

function Sensors.feetY(self: Sensors): number
	return self.hrp.Position.Y - self.hrp.Size.Y / 2 - self:legLength()
end

function Sensors.heightAboveGround(self: Sensors): number
	local hit = Workspace:Raycast(self.hrp.Position, Vector3.new(0, -200, 0), self.params)
	if not hit then
		return 200
	end
	return math.max(0, self:feetY() - hit.Position.Y)
end

-- Free space above the feet, measured up to `limit` studs (returns limit when nothing is above).
-- Three rays (centre, front, back) so a bar the body is half under still counts.
function Sensors.headroom(self: Sensors, limit: number?): number
	local up = limit or 20
	local feet = Vector3.new(self.hrp.Position.X, self:feetY() + 0.1, self.hrp.Position.Z)
	local look = flat(self.hrp.CFrame.LookVector) * (self.hrp.Size.Z / 2)
	local best = up
	for _, offset in { Vector3.zero, look, -look } do
		local hit = Workspace:Raycast(feet + offset, Vector3.new(0, up, 0), self.params)
		if hit then
			best = math.min(best, hit.Distance + 0.1)
		end
	end
	return best
end

-- Wall on one side (side = 1 right, -1 left), as {normal, distance from the body side, id}.
function Sensors.wall(self: Sensors, side: number): any?
	local right = flat(self.hrp.CFrame.RightVector)
	local half = self.hrp.Size.X / 2
	local hit = Workspace:Raycast(self.hrp.Position, right * side * (half + self.p.wallRun.reach), self.params)
	if not hit or math.abs(hit.Normal.Y) > 0.3 then
		return nil
	end
	local n = flat(hit.Normal)
	return {
		normal = { x = n.X, z = n.Z },
		distance = hit.Distance - half,
		id = hit.Instance:GetFullName(),
		side = side,
	}
end

-- Best wall on either side, or nil.
function Sensors.anyWall(self: Sensors): any?
	local l, r = self:wall(-1), self:wall(1)
	if l and r then
		return if l.distance <= r.distance then l else r
	end
	return l or r
end

-- What is ahead in direction `dir` (flat unit vector): {topHeight above feet, distance, topClear}.
function Sensors.obstacle(self: Sensors, dir: Vector3): any?
	local v = self.p.vault
	local feet = self:feetY()
	local origin = Vector3.new(self.hrp.Position.X, feet + 0.6, self.hrp.Position.Z)
	local hit = Workspace:Raycast(origin, dir * (v.detectDistance + self.hrp.Size.Z / 2), self.params)
	if not hit or math.abs(hit.Normal.Y) > 0.3 then
		return nil
	end
	-- Find the top: cast down just past the front face.
	local probe = hit.Position + dir * 0.6 + Vector3.new(0, v.maxHeight + 2, 0)
	local top = Workspace:Raycast(probe, Vector3.new(0, -(v.maxHeight + 2.6), 0), self.params)
	if not top then
		return nil
	end
	local topHeight = top.Position.Y - feet
	-- Room on top for the body to pass over (2.5 studs) and no wall right behind the edge.
	local clearUp = not Workspace:Raycast(top.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 2.5, 0), self.params)
	local clearAhead = not Workspace:Raycast(
		Vector3.new(origin.X, top.Position.Y + 1.2, origin.Z),
		dir * (hit.Distance + 2),
		self.params
	)
	-- Depth: step forward along the top until it drops away (or give up past maxDepth).
	local depth = v.maxDepth + 1
	local k = 0.6
	while k <= v.maxDepth + 1 do
		local probeAt = hit.Position + dir * k + Vector3.new(0, v.maxHeight + 2, 0)
		local down = Workspace:Raycast(probeAt, Vector3.new(0, -(v.maxHeight + 2.6), 0), self.params)
		if not down or down.Position.Y < top.Position.Y - 0.8 then
			depth = k - 0.25
			break
		end
		k += 0.5
	end
	-- Landing: nothing at body height between the top and the landing point.
	local landClear = true
	if depth <= v.maxDepth then
		local from = top.Position + Vector3.new(0, 1.5, 0)
		landClear = not Workspace:Raycast(from, dir * (depth + v.landDistance), self.params)
	end
	return {
		topHeight = topHeight,
		distance = hit.Distance - self.hrp.Size.Z / 2,
		depth = depth,
		topClear = clearUp and clearAhead,
		landClear = landClear,
	}
end

-- A wall straight ahead at chest height, close enough to run into.
function Sensors.bonkWall(self: Sensors, dir: Vector3): boolean
	local hit = Workspace:Raycast(self.hrp.Position, dir * (self.hrp.Size.Z / 2 + 0.8), self.params)
	return hit ~= nil and math.abs(hit.Normal.Y) < 0.3 and flat(hit.Normal):Dot(dir) < -0.7
end

return Sensors
