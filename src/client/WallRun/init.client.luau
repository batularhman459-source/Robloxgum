--!strict
-- The wall run: the "FREE R6 Wall Run" package by SKATER STUDIOS (src/client/WallRun/Runner.luau), set up on every
-- character of this player. Packages/ holds the package's own libraries (Trove, Signal, Spring, PID, Shake, Log).
local Players = game:GetService("Players")

local Run = require(script:WaitForChild("Runner"))

local player = Players.LocalPlayer
if player.Character then
	task.spawn(Run, player.Character)
end
player.CharacterAdded:Connect(Run)
