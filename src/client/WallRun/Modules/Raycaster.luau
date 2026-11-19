--!strict

local Config = require(script.Parent:WaitForChild("Config"))

export type Side = "Left" | "Right"

export type WallHit = {
	Instance: BasePart,
	Position: Vector3,
	Normal: Vector3,
	Distance: number,
	Side: Side,
}

local Raycaster = {}
Raycaster.__index = Raycaster

export type Raycaster = typeof(setmetatable(
	{} :: {
		Params: RaycastParams,
		Root: BasePart,
	},
	Raycaster
))

local function IsRunnableWall(Result: RaycastResult): boolean
	local Part = Result.Instance
	if not Part:IsA("BasePart") or not Part.CanCollide then
		return false
	end
	return math.abs(Result.Normal.Y) <= Config.MaxWallNormalY
end

function Raycaster.new(Character: Model): Raycaster
	local self = setmetatable({}, Raycaster)

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = { Character }
	Params.IgnoreWater = true
	Params.RespectCanCollide = true

	self.Params = Params
	self.Root = Character:WaitForChild("HumanoidRootPart") :: BasePart

	return self
end

function Raycaster.CastSide(self: Raycaster, Direction: Vector3, Side: Side): WallHit?
	local RootCFrame = self.Root.CFrame
	local Forward = RootCFrame.LookVector
	local Offsets = { Config.RayForwardOffset, 0, -Config.RayForwardOffset }

	local Best: WallHit? = nil

	for _, Offset in Offsets do
		local Origin = RootCFrame.Position + Forward * Offset
		local Result = workspace:Raycast(Origin, Direction * Config.WallDetectionDistance, self.Params)

		if Result and IsRunnableWall(Result) then
			local Distance = (Result.Position - Origin).Magnitude
			if Best == nil or Distance < Best.Distance then
				Best = {
					Instance = Result.Instance :: BasePart,
					Position = Result.Position,
					Normal = Result.Normal,
					Distance = Distance,
					Side = Side,
				}
			end
		end
	end

	return Best
end

function Raycaster.FindWall(self: Raycaster): WallHit?
	local RightVector = self.Root.CFrame.RightVector
	local Left = self:CastSide(-RightVector, "Left")
	local Right = self:CastSide(RightVector, "Right")

	if Left and Right then
		return if Left.Distance <= Right.Distance then Left else Right
	end

	return Left or Right
end

function Raycaster.CheckSide(self: Raycaster, Side: Side): WallHit?
	local RightVector = self.Root.CFrame.RightVector
	local Direction = if Side == "Left" then -RightVector else RightVector
	return self:CastSide(Direction, Side)
end

function Raycaster.IsNearGround(self: Raycaster, Distance: number): boolean
	local Result = workspace:Raycast(self.Root.Position, Vector3.new(0, -Distance, 0), self.Params)
	return Result ~= nil
end

return Raycaster
