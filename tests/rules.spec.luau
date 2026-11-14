-- Sanity checks on the plain-number rules, so a typo in rules/ is caught before Studio.
return {
	["combat numbers are in range"] = function(t)
		local c = t.rules("combat")
		t.ok(c.baseDamage > 0, "baseDamage must be > 0")
		t.ok(c.damagePerLevel >= 0, "damagePerLevel must be >= 0")
		t.ok(c.critChance >= 0 and c.critChance <= 1, "critChance must be 0..1")
		t.ok(c.critMultiplier >= 1, "critMultiplier must be >= 1")
		t.ok(c.attackCooldown > 0, "attackCooldown must be > 0")
	end,

	["every upgrade has sane numbers"] = function(t)
		for name, u in t.rules("upgrades") do
			t.ok(u.baseCost > 0, name .. ".baseCost must be > 0")
			t.ok(u.growth >= 1, name .. ".growth must be >= 1")
			t.ok(
				u.maxLevel >= 1 and u.maxLevel == math.floor(u.maxLevel),
				name .. ".maxLevel must be a whole number >= 1"
			)
		end
	end,
}
