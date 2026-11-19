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

return {
	["parkour numbers are in range and consistent"] = function(t)
		local p, m = t.rules("parkour"), t.rules("movement")
		t.ok(p.speed.base > 0 and p.speed.max > p.speed.base, "max > base > 0")
		t.eq(m.walkSpeed, p.speed.base, "movement.walkSpeed must equal parkour speed.base (map checks use it)")
		t.eq(p.landing.rollMaxHeight, m.maxSafeFall, "roll limit must match maxSafeFall")
		t.ok(p.speed.bonkFactor > 0 and p.speed.bonkFactor < 1, "bonkFactor 0..1")
		t.ok(p.gain.repeatFactor > 0 and p.gain.repeatFactor < 1, "repeatFactor 0..1")
		t.ok(p.slide.height < m.characterHeight, "slide makes you smaller")
		t.ok(p.landing.safeHeight < p.landing.rollMaxHeight, "safe < roll limit")
		t.ok(
			p.landing.safeHeight >= m.jumpHeight + p.jump.doubleJumpHeight + 2,
			"your own jump + double jump never lands hard (designer 2026-11-18: double-jump landings stopped you)"
		)
		local w = t.rules("wallrun")
		local wallJumpRise = w.jump.upForce ^ 2 / (2 * m.gravity)
		t.ok(
			-- worst case: latching at the top of a normal jump, the wall jump's full rise, then a double jump on top
			p.landing.safeHeight >= m.jumpHeight + wallJumpRise + p.jump.doubleJumpHeight + 2,
			"jump, wall run, wall jump, double jump never lands hard (2026-11-19: it stopped you)"
		)
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
		for _, mv in { "slide", "wallRun", "wallJump" } do
			Parkour.applyMove(p, mixed, mv)
		end
		local _, _, same = setup(t)
		for _ = 1, 3 do
			Parkour.applyMove(p, same, "wallRun")
		end
		t.ok(mixed.speed > same.speed, string.format("mixed %.1f should beat repeated %.1f", mixed.speed, same.speed))
		t.eq(mixed.speed, p.speed.base + p.gain.slide + p.gain.wallRun + p.gain.wallJump)
	end,

	["momentum: a vault keeps the sprint and adds to it (designer: vaults must not kill speed)"] = function(t)
		local p, _, s = setup(t)
		Parkour.applyMove(p, s, "slide")
		local before = s.speed
		s.sinceLastMove = p.speed.flowGrace -- right at the end of the flow window
		Parkour.applyMove(p, s, "vault")
		t.ok(p.gain.vault >= 0, "gain.vault never takes speed away")
		t.eq(s.speed, math.min(p.speed.max, before + p.gain.vault))
		t.eq(s.sinceLastMove, 0, "a vault keeps the flow alive")
	end,

	["momentum: a vault adds only gain.vault to the sprint (designer 2026-11-18: no vault boost)"] = function(t)
		local p, _, s = setup(t)
		local before = s.speed
		Parkour.afterVault(p, s)
		t.eq(s.speed, math.min(p.speed.max, before + p.gain.vault))
	end,

	["vault chain: the 1st vault adds nothing, each next one within the window adds a step, up to the cap"] = function(
		t
	)
		local p, _, s = setup(t)
		local c = p.vaultChain
		local start = s.speed
		t.eq(Parkour.afterVault(p, s), 0, "1st vault: no chain bonus")
		local total = 0
		for _ = 1, 10 do
			Parkour.decay(p, s, c.window * 0.5)
			total += Parkour.afterVault(p, s)
		end
		t.ok(total <= c.cap + 1e-9, string.format("chain bonus %.1f within the cap %.1f", total, c.cap))
		t.ok(total >= c.step, "a chain does pay")
		t.ok(s.speed <= p.speed.max and s.speed > start, "faster, never over the cap")
	end,

	["vault chain: a pause longer than the window starts over"] = function(t)
		local p, _, s = setup(t)
		Parkour.afterVault(p, s)
		Parkour.decay(p, s, p.vaultChain.window + 0.1)
		t.eq(Parkour.afterVault(p, s), 0, "too late: a new chain")
		t.eq(s.vaultChain, 1)
	end,

	["slide: the R6 slide collider fits under the slide height"] = function(t)
		local p = t.rules("parkour")
		local sl = p.slide
		t.ok(sl.colliderLift > 0, "off the floor (no scraping)")
		t.ok(sl.colliderLift + sl.colliderHeight <= sl.height - sl.clearance, "its top stays under the slide height")
		t.ok(sl.colliderWidth > 0, "has a width")
	end,

	["momentum: capped at max, never below base"] = function(t)
		local p, _, s = setup(t)
		for _ = 1, 50 do
			Parkour.applyMove(p, s, "wallRun")
			Parkour.applyMove(p, s, "slide")
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
		Parkour.applyMove(p, s, "wallJump")
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
		local moves = { "slide", "wallRun", "wallJump" }
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

	["jumps: ground, coyote, double, and none left"] = function(t)
		local p, _, s = setup(t)
		t.eq(Parkour.jumpKind(p, s), "jump")
		s.grounded, s.timeSinceGrounded = false, p.jump.coyoteTime * 0.5
		t.eq(Parkour.jumpKind(p, s), "jump", "coyote time")
		s.timeSinceGrounded = 1
		t.eq(Parkour.jumpKind(p, s), "doubleJump")
		s.airJumpsUsed = p.jump.airJumps
		t.eq(Parkour.jumpKind(p, s), nil, "out of air jumps")
	end,

	["slide: needs ground, speed and cooldown"] = function(t)
		local p, _, s = setup(t)
		t.ok(Parkour.canSlide(p, s), "auto-sprint on ground can slide")
		s.sinceSlide = 0
		t.ok(not Parkour.canSlide(p, s), "cooldown")
		s.sinceSlide, s.grounded = 10, false
		t.ok(not Parkour.canSlide(p, s), "not in the air")
	end,

	["real slide: body fits under slide.height, stays low under ceilings"] = function(t)
		local p, m = setup(t)
		local rootHeight = 2 -- R15 HumanoidRootPart
		local hip = Parkour.slideHipHeight(p, rootHeight)
		t.ok(hip + rootHeight <= p.slide.height, "sliding body top must be under slide.height")
		t.ok(hip >= p.slide.minHip, "never below minHip")
		t.ok(not Parkour.canStandUp(m, p.slide.height + p.slide.gapMargin), "under a slide gap you stay low")
		t.ok(Parkour.canStandUp(m, m.characterHeight), "full headroom: stand up")
		t.ok(p.slide.height + p.slide.gapMargin < m.characterHeight, "a slide gap is lower than a standing body")
	end,

	["slide buffer: a slide pressed just before landing still happens, an early one does not"] = function(t)
		local p = t.rules("parkour")
		t.ok(Parkour.slideBuffered(p, 10, 10 + p.slide.bufferTime * 0.5), "pressed just before landing")
		t.ok(not Parkour.slideBuffered(p, 10, 10 + p.slide.bufferTime + 0.01), "too early")
		t.ok(not Parkour.slideBuffered(p, nil, 10), "not pressed")
	end,

	["run animation: normal at the sprint, a little faster when fast, never past the cap"] = function(t)
		local p = t.rules("parkour")
		t.eq(Parkour.runAnimSpeed(p, p.speed.base), 1, "1x at the sprint")
		local fast = Parkour.runAnimSpeed(p, p.speed.max)
		t.ok(fast > 1 and fast <= p.runAnim.max, string.format("%.2fx at the cap", fast))
		t.ok(fast - 1 < p.speed.max / p.speed.base - 1, "grows slower than the speed")
		t.eq(Parkour.runAnimSpeed(p, 1000), p.runAnim.max, "capped")
		t.eq(Parkour.runAnimSpeed(p, 0), 1, "never slower than normal")
	end,

	["landing: safe, rolled and hard"] = function(t)
		local p, _, s = setup(t)
		local run = p.speed.base + 4 -- from the rules (it was a fixed 28, below the 30 sprint)
		s.speed = run
		-- a fall between the safe height and the roll limit (from the rules, not a fixed 20: safeHeight moved
		-- 12 -> 18 -> 24 -> 29)
		local high = (p.landing.safeHeight + p.landing.rollMaxHeight) / 2
		t.eq((Parkour.landing(p, s, p.landing.safeHeight, nil)), "soft")
		local kind, speed = Parkour.landing(p, s, high, p.landing.rollWindow * 0.5)
		t.eq(kind, "roll")
		t.ok(speed > run, "a roll keeps and adds speed")
		kind, speed = Parkour.landing(p, s, high, nil)
		t.eq(kind, "hard")
		t.eq(speed, run * p.landing.hardSpeedFactor, "hard landing halves speed")
		t.eq((Parkour.landing(p, s, high, p.landing.rollWindow * 2)), "hard", "roll pressed too early")
		t.eq((Parkour.landing(p, s, p.landing.rollMaxHeight + 5, 0.1)), "hard", "too high to roll")
	end,
}
