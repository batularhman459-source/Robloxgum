--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = ReplicatedStorage:WaitForChild("Rules")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local combatRules = require(Rules:WaitForChild("combat")) :: any
local upgradeRules = require(Rules:WaitForChild("upgrades")) :: any
local Combat = require(Shared:WaitForChild("Combat"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

print(
	string.format(
		"[Server] Rules loaded. Hit at level 1: %d. First damage upgrade costs: %d",
		Combat.damage(combatRules, 1, 1),
		Upgrades.cost(upgradeRules.damage, 1) or -1
	)
)
