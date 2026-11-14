--!strict
-- Pure game logic: no requires, no Roblox services.

export type UpgradeRules = {
	baseCost: number,
	growth: number,
	maxLevel: number,
}

local Upgrades = {}

-- Cost to buy `level` (level 1 is the first purchase). Nil when past max level.
function Upgrades.cost(rules: UpgradeRules, level: number): number?
	if level < 1 or level > rules.maxLevel then
		return nil
	end
	return math.floor(rules.baseCost * rules.growth ^ (level - 1))
end

-- Total cost to go from level 0 up to `level`.
function Upgrades.totalCost(rules: UpgradeRules, level: number): number
	local total = 0
	for l = 1, math.min(level, rules.maxLevel) do
		total += Upgrades.cost(rules, l) :: number
	end
	return total
end

return Upgrades
