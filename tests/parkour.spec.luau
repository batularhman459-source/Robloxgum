local Parkour = require("../src/shared/Parkour")

local function setup(t)
	local p, m = t.rules("parkour"), t.rules("movement")
	local s = Parkour.newState(p)
	return p, m, s
end

local function airborne(s, height)
	s.grounded = false
	s.timeSinceGrounded = 0.5
	s.heightAboveGround = height or 6
end

local ALONG = { x = 1, z = 0 } -- running along +x
local WALL_LEFT = { normal = { x = 0, z = 1 }, distance = 1.5, id = "W1" } -- wall at -z, normal points +z

return {
	["parkour numbers are in range and consistent"] = function(t)
		local p, m = t.rules("parkour"), t.rules("movement")
		t.ok(p.speed.base > 0 and p.speed.max > p.speed.base, "max > base > 0")
		t.eq(m.walkSpeed, p.speed.base, "movement.walkSpeed must equal parkour speed.base (map checks use it)")
		t.eq(p.landing.rollMaxHeight, m.maxSafeFall, "roll limit must match maxSafeFall")
		t.ok(p.speed.bonkFactor > 0 and p.speed.bonkFactor < 1, "bonkFactor 0..1")
		t.ok(p.gain.repeatFactor > 0 and p.gain.repeatFactor < 1, "repeatFactor 0..1")
		t.ok(p.vault.minHeight < p.vault.maxHeight, "vault min < max")
		t.ok(p.vault.minHeight >= m.stepHeight * 0.5, "vault starts near step height")
		t.ok(p.vault.maxHeight < m.jumpHeight, "anything you can vault you could also jump onto")
		t.ok(p.wallRun.minSpeed <= p.speed.base, "auto-sprint alone is fast enough to wall run")
		t.ok(p.slide.height < m.characterHeight, "slide makes you smaller")
		t.ok(p.landing.safeHeight < p.landing.rollMaxHeight, "safe < roll limit")
		t.ok(p.wallJump.allowBurst == 0 or p.wallJump.allowBurst == 1, "allowBurst is a 0/1 switch")
		t.ok(
			p.gain.maxRefresh >= 1 and p.gain.maxRefresh == math.floor(p.gain.maxRefresh),
			"maxRefresh whole number >= 1"
		)
		for name, section in p do
			if name ~= "source" then
				t.ok(type(p.source[name]) == "string", "[" .. name .. "] needs a source entry")
				for k, v in section do
					t.ok(type(v) == "number" and v >= 0, name .. "." .. k .. " must be a number >= 0")
				end
			end
		end
	end,

	["momentum: mixing moves builds speed, repeating one move gains less"] = function(t)
		local p, _, mixed = setup(t)
		for _, mv in { "slide", "wallRun", "wallJump", "vault" } do
			Parkour.applyMove(p, mixed, mv)
		end
		local _, _, same = setup(t)
		for _ = 1, 4 do
			Parkour.applyMove(p, same, "wallRun")
		end
		t.ok(mixed.speed > same.speed, string.format("mixed %.1f should beat repeated %.1f", mixed.speed, same.speed))
		t.eq(mixed.speed, p.speed.base + p.gain.slide + p.gain.wallRun + p.gain.wallJump + p.gain.vault)
	end,

	["momentum: capped at max, never below base"] = function(t)
		local p, _, s = setup(t)
		for _ = 1, 50 do
			Parkour.applyMove(p, s, "wallRun")
			Parkour.applyMove(p, s, "vault")
		end
		t.eq(s.speed, p.speed.max, "capped")
		Parkour.bonk(p, s)
		t.ok(s.speed < p.speed.max and s.speed >= p.speed.base, "bonk loses speed")
		for _ = 1, 20 do
			Parkour.bonk(p, s)
		end
		t.eq(s.speed, p.speed.base, "never below base")
	end,

	["momentum: speed holds during flow grace, then decays to base"] = function(t)
		local p, _, s = setup(t)
		Parkour.applyMove(p, s, "slide")
		Parkour.applyMove(p, s, "vault")
		local fast = s.speed
		Parkour.decay(p, s, p.speed.flowGrace * 0.9)
		t.eq(s.speed, fast, "no decay inside the grace time")
		for _ = 1, 200 do
			Parkour.decay(p, s, 0.05)
		end
		t.eq(s.speed, p.speed.base, "back to base")
		t.eq(s.lastMove, nil, "flow broken resets the repeat chain")
	end,

	["spam: mashing one move decays back to base (playtest bug: slide spam held 31.5)"] = function(t)
		local p, _, s = setup(t)
		-- 10 s of play, one slide every 0.5 s, decay ticking every 0.05 s.
		for step = 1, 200 do
			if step % 10 == 0 then
				Parkour.applyMove(p, s, "slide")
			end
			Parkour.decay(p, s, 0.05)
		end
		t.ok(
			s.speed <= p.speed.base + p.gain.slide,
			string.format("spam should sit near base %d, got %.1f", p.speed.base, s.speed)
		)
	end,

	["flow: mixing moves at the same pace keeps the speed up"] = function(t)
		local p, _, s = setup(t)
		local moves = { "slide", "vault", "wallRun", "wallJump" }
		for step = 1, 200 do
			if step % 10 == 0 then
				Parkour.applyMove(p, s, moves[(step // 10) % #moves + 1])
			end
			Parkour.decay(p, s, 0.05)
		end
		t.ok(
			s.speed >= p.speed.max - 1,
			string.format("mixed flow should stay near max %d, got %.1f", p.speed.max, s.speed)
		)
	end,

	["spam: a few repeats still count as flow"] = function(t)
		local p, _, s = setup(t)
		for _ = 1, p.gain.maxRefresh do
			Parkour.applyMove(p, s, "slide")
		end
		t.eq(s.sinceLastMove, 0, "repeats up to maxRefresh refresh the flow timer")
		s.sinceLastMove = 0.5
		Parkour.applyMove(p, s, "slide")
		t.eq(s.sinceLastMove, 0.5, "one more repeat does not")
	end,

	["wall jump burst: allowed with allowBurst = 1, clamped with 0"] = function(t)
		local p, m, s = setup(t)
		s.speed = p.speed.max
		local h = Parkour.wallJumpVelocity(p, m, s, ALONG, WALL_LEFT.normal)
		local burst = math.sqrt(h.x ^ 2 + h.z ^ 2)
		t.eq(p.wallJump.allowBurst, 1, "designer chose burst on")
		t.ok(burst > p.speed.max, "burst goes over the cap")
		local strict = table.clone(p)
		strict.wallJump = table.clone(p.wallJump)
		strict.wallJump.allowBurst = 0
		local c = Parkour.wallJumpVelocity(strict, m, s, ALONG, WALL_LEFT.normal)
		t.ok(math.abs(math.sqrt(c.x ^ 2 + c.z ^ 2) - p.speed.max) < 1e-9, "clamped to exactly the cap")
	end,

	["jumps: ground, coyote, double, wall, and none left"] = function(t)
		local p, _, s = setup(t)
		t.eq(Parkour.jumpKind(p, s), "jump")
		s.grounded, s.timeSinceGrounded = false, p.jump.coyoteTime * 0.5
		t.eq(Parkour.jumpKind(p, s), "jump", "coyote time")
		s.timeSinceGrounded = 1
		t.eq(Parkour.jumpKind(p, s), "doubleJump")
		s.airJumpsUsed = p.jump.airJumps
		t.eq(Parkour.jumpKind(p, s), nil, "out of air jumps")
		s.wallRunning = true
		t.eq(Parkour.jumpKind(p, s), "wallJump", "wall jump always allowed while wall running")
	end,

	["wall run: starts along a close wall in the air"] = function(t)
		local p, _, s = setup(t)
		airborne(s)
		local ok, why = Parkour.canWallRun(p, s, WALL_LEFT, ALONG)
		t.ok(ok, "should start: " .. why)
	end,

	["wall run: refuses for every wrong condition"] = function(t)
		local p, _, s = setup(t)
		local cases = {
			{
				"grounded",
				function(st)
					st.grounded = true
				end,
				WALL_LEFT,
				ALONG,
			},
			{ "no wall", nil, nil, ALONG },
			{ "wall too far", nil, { normal = WALL_LEFT.normal, distance = 10, id = "W1" }, ALONG },
			{
				"too slow",
				function(st)
					st.speed = p.wallRun.minSpeed - 1
				end,
				WALL_LEFT,
				ALONG,
			},
			{
				"too low",
				function(st)
					st.heightAboveGround = 1
				end,
				WALL_LEFT,
				ALONG,
			},
			{ "moving away", nil, WALL_LEFT, { x = 0, z = 1 } },
			{ "angle too steep", nil, WALL_LEFT, { x = 0.3, z = -0.954 } },
			{
				"same wall",
				function(st)
					st.lastWallId, st.sinceLeftWall = "W1", 0.1
				end,
				WALL_LEFT,
				ALONG,
			},
		}
		for _, c in cases do
			local st = Parkour.newState(p)
			airborne(st)
			if c[2] then
				c[2](st)
			end
			local ok, why = Parkour.canWallRun(p, st, c[3], c[4])
			t.ok(not ok and why == c[1], "expected '" .. c[1] .. "', got " .. tostring(ok) .. " / " .. why)
		end
		local _ = s
	end,

	["wall run: ends on time, ground or losing the wall; direction runs along the wall"] = function(t)
		local p, _, s = setup(t)
		airborne(s)
		t.ok(not Parkour.wallRunEnds(p, s, WALL_LEFT, false), "keeps going")
		s.wallRunTime = p.wallRun.maxDuration
		t.ok(Parkour.wallRunEnds(p, s, WALL_LEFT, false), "time up")
		s.wallRunTime = 0
		t.ok(Parkour.wallRunEnds(p, s, nil, false), "wall gone")
		t.ok(Parkour.wallRunEnds(p, s, WALL_LEFT, true), "touched ground")
		local d = Parkour.wallRunDirection({ x = 0.8, z = -0.6 }, WALL_LEFT.normal)
		t.ok(math.abs(d.z) < 1e-9 and math.abs(d.x - 1) < 1e-9, "into-wall part removed")
	end,

	["wall jump pushes away from the wall and keeps run speed"] = function(t)
		local p, m, s = setup(t)
		local h, up = Parkour.wallJumpVelocity(p, m, s, ALONG, WALL_LEFT.normal)
		t.eq(h.x, s.speed, "keeps along-wall speed")
		t.eq(h.z, p.wallJump.push, "pushed away from the wall")
		t.ok(math.abs(up - math.sqrt(2 * m.gravity * p.wallJump.height)) < 1e-9, "up speed from height")
	end,

	["vault: only obstacles between step and wall height, with room on top"] = function(t)
		local p, _, s = setup(t)
		local function ob(h, dist, clear)
			return { topHeight = h, distance = dist or 2, topClear = clear ~= false }
		end
		t.ok((Parkour.canVault(p, s, ob(3))), "3 studs: vault")
		t.eq(select(2, Parkour.canVault(p, s, ob(1))), "just a step")
		t.eq(select(2, Parkour.canVault(p, s, ob(6))), "a wall")
		t.eq(select(2, Parkour.canVault(p, s, ob(3, 10))), "too far")
		t.eq(select(2, Parkour.canVault(p, s, ob(3, 2, false))), "no room on top")
		s.speed = p.vault.minSpeed - 1
		t.eq(select(2, Parkour.canVault(p, s, ob(3))), "too slow")
	end,

	["slide: needs ground, speed and cooldown"] = function(t)
		local p, _, s = setup(t)
		t.ok(Parkour.canSlide(p, s), "auto-sprint on ground can slide")
		s.sinceSlide = 0
		t.ok(not Parkour.canSlide(p, s), "cooldown")
		s.sinceSlide, s.grounded = 10, false
		t.ok(not Parkour.canSlide(p, s), "not in the air")
	end,

	["landing: safe, rolled and hard"] = function(t)
		local p, _, s = setup(t)
		s.speed = 28
		t.eq((Parkour.landing(p, s, p.landing.safeHeight, nil)), "soft")
		local kind, speed = Parkour.landing(p, s, 20, p.landing.rollWindow * 0.5)
		t.eq(kind, "roll")
		t.ok(speed > 28, "a roll keeps and adds speed")
		kind, speed = Parkour.landing(p, s, 20, nil)
		t.eq(kind, "hard")
		t.eq(speed, 28 * p.landing.hardSpeedFactor, "hard landing halves speed")
		t.eq((Parkour.landing(p, s, 20, p.landing.rollWindow * 2)), "hard", "roll pressed too early")
		t.eq((Parkour.landing(p, s, p.landing.rollMaxHeight + 5, 0.1)), "hard", "too high to roll")
	end,
}
