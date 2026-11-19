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
-- HipHeight 0 because its 2 stud legs hold the body up (playtest: a 3 stud box read as 1 stud high).
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

-- A wall straight ahead at chest height, close enough to run into.
function Sensors.bonkWall(self: Sensors, dir: Vector3): boolean
	local hit = Workspace:Raycast(self.hrp.Position, dir * (self.hrp.Size.Z / 2 + 0.8), self.params)
	return hit ~= nil and math.abs(hit.Normal.Y) < 0.3 and flat(hit.Normal):Dot(dir) < -0.7
end

return Sensors
