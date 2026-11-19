-- Sanity checks on the plain-number rules, so a typo in rules/ is caught before Studio.
local CharacterShape = require("../src/shared/CharacterShape")

return {
	["vault (toolbox Vaulting System): numbers in range, every section has a source"] = function(t)
		local v = t.rules("vault")
		t.ok(v.detect.minHeight < v.types.stepBelow, "a step vault is possible")
		t.ok(
			v.types.stepBelow < v.types.normalBelow and v.types.normalBelow <= v.detect.maxHeight,
			"type bands in order"
		)
		t.ok(v.detect.facingDot > 0 and v.detect.facingDot <= 1, "facingDot 0..1")
		t.ok(v.push.delay >= 0 and v.push.endEarly >= 0, "timings")
		t.ok(
			v.push.atDistance > 0 and v.push.atDistance < v.detect.forwardDistance,
			"push.atDistance inside the detect reach"
		)
		t.ok(v.feel.rampUp > 0 and v.feel.settle > 0 and v.feel.maxOverrun > 0, "feel times > 0")
		for name in v do
			if name ~= "source" then
				t.ok(type(v.source[name]) == "string", "[" .. name .. "] needs a source entry")
			end
		end
	end,

	["slide feel: numbers in range, every section has a source"] = function(t)
		local f = t.rules("slide")
		t.ok(f.timing.blendIn > 0 and f.timing.blendOut > 0 and f.timing.legLead >= 0, "timing")
		t.ok(f.pose.rootY < 0, "the body drops")
		t.ok(f.camera.offsetY < 0 and f.camera.fovAdd > 0, "camera goes down and wider")
		t.ok(f.debris.minSize > 0 and f.debris.minSize <= f.debris.maxSize and f.debris.life > 0, "debris")
		t.ok(f.debris.bounce >= 0 and f.debris.bounce < 1, "a bounce loses speed")
		t.ok(f.dust.lifeMin <= f.dust.lifeMax and f.dust.ratePerSpeed > 0, "dust")
		t.ok(f.trail.lifetime > 0 and f.trail.transparency >= 0 and f.trail.transparency < 1, "trail")
		t.ok(f.sound.scrapePitchMin <= f.sound.scrapePitchMax, "scrape pitch range")
		for _, key in { "scrapeId" } do
			t.ok(type(f.sound[key]) == "number" and f.sound[key] > 0, "sound." .. key .. " is an asset id")
		end
		for i = 2, #f.entry do
			t.ok(f.entry[i].t > f.entry[i - 1].t, "entry keys in time order")
		end
		for i = 2, #f.exit do
			t.ok(f.exit[i].t > f.exit[i - 1].t, "exit keys in time order")
		end
		t.ok(f.net.maxPerSecond >= 2, "a whole slide (on + off) fits in the rate limit")
		for name in f do
			if name ~= "source" then
				t.ok(type(f.source[name]) == "string", "[" .. name .. "] needs a source entry")
			end
		end
	end,

	["speed feel + vault chain: present and sane (details in speedfeel.spec / parkour.spec)"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.ok(r.fov.add > 0 and r.lines.rate > 0, "speed feel on")
		t.ok(p.vaultChain.window > 0 and p.vaultChain.step > 0 and p.vaultChain.cap >= p.vaultChain.step, "vault chain")
	end,

	["flip: present (details in flip.spec)"] = function(t)
		local r = t.rules("flip")
		t.ok(#r.keys >= 2 and r.timing.blendIn > 0, "flip keys and timing")
	end,

	["wall run (FREE R6 Wall Run package): numbers sane, every section has a source"] = function(t)
		local r = t.rules("wallrun")
		t.ok(r.detect.distance > 0 and r.run.maxDuration > 0 and r.run.minStartHeight > 0, "detect, run, a cap")
		t.ok(r.run.verticalSpeed == 0, "level (designer: keep the players on one height)")
		t.ok(r.jump.awayForce > 0 and r.jump.upForce > 0, "wall jump")
		t.ok(#r.camera.shakePosition == 3 and #r.camera.shakeRotation == 3, "shake vectors")
		t.ok(r.sound.stepEvery >= 1 and r.sound.stepVolume > 0, "footsteps on, at least every marker")
		for _, k in { "stepId" } do
			t.ok(type(r.sound[k]) == "number" and r.sound[k] > 0, "sound." .. k)
		end
		for name in r do
			if name ~= "source" then
				t.ok(type(r.source[name]) == "string", "[" .. name .. "] needs a source entry")
			end
		end
	end,

	["camera kicks: every kick sane, softer than the wall run, every section has a source"] = function(t)
		local c, w = t.rules("camera"), t.rules("wallrun")
		for _, name in { "vault", "flip", "land" } do
			local k = c[name]
			t.ok(k.attack > 0 and k.attack < k.time, name .. ": attack inside the kick")
			t.ok(k.fov >= 0 and k.dip >= 0 and k.shake >= 0, name .. ": no negative strengths")
			t.ok(k.roll < w.camera.tiltAngle, name .. ": rolls less than the wall run tilts (medium)")
			t.ok(type(c.source[name]) == "string", name .. " needs a source")
		end
		t.ok(c.land.minFall < c.land.fullFall, "landing kick range")
	end,

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
