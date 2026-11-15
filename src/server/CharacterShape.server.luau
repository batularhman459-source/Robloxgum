--!strict
-- Narrows every R6 character sideways on spawn (rules/character.toml). Runs on the server so all
-- players see the same shape. Joints are moved so limbs stay attached at the torso's new edge.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local c = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("character")) :: any
local CharacterShape = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterShape"))

local function withX(cf: CFrame, x: number): CFrame
	local p = cf.Position
	return CFrame.new(x, p.Y, p.Z) * cf.Rotation
end

local function shape(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 or char:GetAttribute("Shaped") then
		return
	end
	char:SetAttribute("Shaped", true)
	for _, part in char:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local scale = CharacterShape.scaleFor(c, part.Name)
			if scale ~= 1 then
				part.Size = Vector3.new(part.Size.X * scale, part.Size.Y, part.Size.Z)
				local mesh = part:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					mesh.Scale = Vector3.new(mesh.Scale.X * scale, mesh.Scale.Y, mesh.Scale.Z)
				end
			end
		end
	end
	for _, motor in char:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local s0 = CharacterShape.scaleFor(c, motor.Part0.Name)
			local s1 = CharacterShape.scaleFor(c, motor.Part1.Name)
			motor.C0 = withX(motor.C0, CharacterShape.offsetX(motor.C0.Position.X, s0))
			motor.C1 = withX(motor.C1, CharacterShape.offsetX(motor.C1.Position.X, s1))
		end
	end
end

local function onPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(shape)
	if player.Character and player:HasAppearanceLoaded() then
		shape(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
