local Movement = require("../src/shared/Movement")

local function near(t, a, b, eps, msg)
	t.ok(math.abs(a - b) <= (eps or 0.01), string.format("%s: expected %.3f, got %.3f", msg or "near", b, a))
end

return {
	["movement numbers are in range and every one has a source"] = function(t)
		local m = t.rules("movement")
		for _, key in
			{
				"walkSpeed",
				"jumpHeight",
				"gravity",
				"stepHeight",
				"characterHeight",
				"characterWidth",
				"eyeHeight",
				"maxSafeFall",
				"minCleanDrop",
			}
		do
			t.ok(type(m[key]) == "number" and m[key] > 0, key .. " must be > 0")
			t.ok(type(m.source[key]) == "string", key .. " needs a [source] entry")
		end
		t.ok(m.jumpMargin > 0 and m.jumpMargin <= 1, "jumpMargin 0..1")
		t.ok(m.stepHeight < m.minCleanDrop and m.minCleanDrop < m.maxSafeFall, "step < cleanDrop < safeFall")
		t.ok(m.maxSlopeAngle > 0 and m.maxSlopeAngle < 90, "maxSlopeAngle 0..90")
	end,

	["default jump: peak 7.2, about 0.54 s in the air, distance = speed x air time"] = function(t)
		local m = t.rules("movement")
		near(t, Movement.jumpVelocity(m), 53.15, 0.01, "take-off speed")
		near(t, Movement.jumpAirTime(m, 0) :: number, 0.5418, 0.001, "air time")
		-- 20 studs/s auto-sprint -> about 10.8 studs (was 8.7 at Roblox's default 16)
		near(t, m.walkSpeed * (Movement.jumpAirTime(m, 0) :: number), m.walkSpeed * 0.5418, 0.01, "flat jump distance")
		t.eq(Movement.jumpAirTime(m, 8), nil, "can't land above the peak")
	end,

	["higher landings are shorter, lower landings reach further"] = function(t)
		local m = t.rules("movement")
		t.ok(Movement.jumpReach(m, 4) < Movement.jumpReach(m, 0), "up is shorter")
		t.ok(Movement.jumpReach(m, -10) > Movement.jumpReach(m, 0), "down is further")
		t.eq(Movement.jumpReach(m, 7), 0, "7 studs up is past the jump margin")
	end,

	["falls"] = function(t)
		local m = t.rules("movement")
		near(t, Movement.fallTime(m, 30), 0.553, 0.001, "30 stud fall time")
		t.eq(Movement.dropKind(m, 1.5), "step")
		t.eq(Movement.dropKind(m, 3), "awkward")
		t.eq(Movement.dropKind(m, 10), "clean")
		t.eq(Movement.dropKind(m, 50), "unsafe")
	end,
}
