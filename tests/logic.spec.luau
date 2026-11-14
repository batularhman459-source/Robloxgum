local Combat = require("../src/shared/Combat")
local Upgrades = require("../src/shared/Upgrades")

return {
	["normal hit uses base damage plus level"] = function(t)
		local c = t.rules("combat")
		t.eq(Combat.damage(c, 1, 0.99), c.baseDamage)
		t.eq(Combat.damage(c, 3, 0.99), c.baseDamage + 2 * c.damagePerLevel)
	end,

	["crit multiplies damage"] = function(t)
		local c = t.rules("combat")
		t.eq(Combat.damage(c, 1, 0), c.baseDamage * c.critMultiplier)
	end,

	["upgrade costs grow and stop at max level"] = function(t)
		for name, u in t.rules("upgrades") do
			t.eq(Upgrades.cost(u, 1), u.baseCost, name .. " level 1")
			t.eq(Upgrades.cost(u, 0), nil, name .. " level 0")
			t.eq(Upgrades.cost(u, u.maxLevel + 1), nil, name .. " past max")
			for l = 2, u.maxLevel do
				t.ok(Upgrades.cost(u, l) >= Upgrades.cost(u, l - 1), name .. " cost must not drop at level " .. l)
			end
		end
	end,

	["total cost adds up"] = function(t)
		local u = { baseCost = 10, growth = 2, maxLevel = 3 }
		t.eq(Upgrades.totalCost(u, 3), 10 + 20 + 40)
		t.eq(Upgrades.totalCost(u, 99), 70, "capped at max level")
	end,
}
