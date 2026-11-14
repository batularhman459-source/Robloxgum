--!strict
-- Pure game logic: no requires, no Roblox services. Rules are passed in,
-- so the same code runs in Studio and in the Lune tests.

export type CombatRules = {
	baseDamage: number,
	damagePerLevel: number,
	critChance: number,
	critMultiplier: number,
	attackCooldown: number,
}

local Combat = {}

-- Damage of one hit. `roll` is a number in [0, 1); pass math.random() in game.
function Combat.damage(rules: CombatRules, level: number, roll: number): number
	local base = rules.baseDamage + rules.damagePerLevel * (level - 1)
	if roll < rules.critChance then
		return base * rules.critMultiplier
	end
	return base
end

return Combat
