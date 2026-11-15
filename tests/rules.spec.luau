-- Sanity checks on the plain-number rules, so a typo in rules/ is caught before Studio.
local CharacterShape = require("../src/shared/CharacterShape")

return {
	["character: widths in range, every one has a source"] = function(t)
		local c = t.rules("character")
		for _, k in { "torsoWidth", "armWidth", "legWidth", "headWidth" } do
			t.ok(c[k] >= 0.5 and c[k] <= 1.2, k .. " must be 0.5..1.2")
			t.ok(type(c.source[k]) == "string", k .. " needs a source")
		end
	end,

	["character: narrowed arms and legs stay attached at the torso edge"] = function(t)
		local c = t.rules("character")
		-- R6 right shoulder: C0 x = +1 (torso edge), C1 x = -0.5 (arm's inner half). Arm centre lands at
		-- C0.x - C1.x; it must be the new torso half-width + the new arm half-width.
		local armCentre = CharacterShape.offsetX(1, c.torsoWidth) - CharacterShape.offsetX(-0.5, c.armWidth)
		t.ok(math.abs(armCentre - (1 * c.torsoWidth + 0.5 * c.armWidth)) < 1e-9, "arm sits right at the torso edge")
		-- R6 right hip: C0 x = +1, C1 x = +0.5: leg centre = torso half-width - leg half-width (under the torso).
		local legCentre = CharacterShape.offsetX(1, c.torsoWidth) - CharacterShape.offsetX(0.5, c.legWidth)
		t.ok(math.abs(legCentre - (1 * c.torsoWidth - 0.5 * c.legWidth)) < 1e-9, "leg sits under the torso side")
		t.eq(CharacterShape.scaleFor(c, "HumanoidRootPart"), 1, "root part (hitbox) unchanged")
	end,

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
