--!strict
-- Parkour decisions and momentum. Pure: no requires, no Roblox APIs.
-- The client movement controller measures the world (raycasts, ground, walls), puts the result into
-- plain tables and asks this module what to do. All numbers come from rules/parkour.toml (`p`) and
-- rules/movement.toml (`m`), passed in.
--
-- Vectors are plain {x, z} tables (horizontal only). A wall normal points AWAY from the wall.

export type Vec2 = { x: number, z: number }

export type State = {
	grounded: boolean,
	timeSinceGrounded: number, -- seconds since last on the ground (0 while grounded)
	airJumpsUsed: number,
	speed: number, -- current horizontal speed target
	lastMove: string?, -- last move that gave momentum
	repeatCount: number, -- how many times lastMove was done in a row
	sinceLastMove: number, -- seconds since the last move that refreshed the flow
	sinceAnyMove: number, -- seconds since any move at all (spammed repeats included)
	sinceVault: number, -- seconds since the last vault ended
	vaultChain: number, -- vaults in a row, each within vaultChain.window of the last
	sinceSlide: number,
	heightAboveGround: number,
}

local Parkour = {}

function Parkour.newState(p: any): State
	return {
		grounded = true,
		timeSinceGrounded = 0,
		airJumpsUsed = 0,
		speed = p.speed.base,
		lastMove = nil,
		repeatCount = 0,
		sinceLastMove = math.huge,
		sinceAnyMove = math.huge,
		sinceVault = math.huge,
		vaultChain = 0,
		sinceSlide = math.huge,
		heightAboveGround = 0,
	}
end

-- Speed after doing `move`. Repeating the same move gains less each time (repeatFactor), so the
-- fastest flow mixes moves. Never above speed.max, never below speed.base.
function Parkour.gainFor(p: any, s: State, move: string): number
	local base = p.gain[move]
	if not base then
		return 0
	end
	local repeats = if s.lastMove == move then s.repeatCount else 0
	return base * p.gain.repeatFactor ^ repeats
end

-- Does a move. Gains speed (less for repeats) and keeps the flow alive, except that the same move
-- repeated more than gain.maxRefresh times in a row no longer refreshes the flow timer: spamming one
-- move decays back to base (playtest: slide spam held 31.5 forever).
function Parkour.applyMove(p: any, s: State, move: string)
	local gain = Parkour.gainFor(p, s, move)
	s.speed = math.clamp(s.speed + gain, p.speed.base, p.speed.max)
	if s.lastMove == move then
		s.repeatCount += 1
	else
		s.lastMove, s.repeatCount = move, 1
	end
	if s.repeatCount <= p.gain.maxRefresh then
		s.sinceLastMove = 0
	end
	s.sinceAnyMove = 0
end

-- A vault just ended (src/client/Vault.client.luau). It counts as a move and adds gain.vault, plus the chain bonus:
-- from the 2nd vault within vaultChain.window of the last, +step each, up to cap from one chain (designer
-- 2026-11-18). A chain always keeps the flow alive (vaults need real obstacles, so they cannot be spammed). The
-- vault's own forward push is NOT carried over (measured: that turned a 20 run-up into a 23 sprint).
-- Returns the chain bonus it gave.
function Parkour.afterVault(p: any, s: State): number
	local c = p.vaultChain
	s.vaultChain = if s.sinceVault <= c.window then s.vaultChain + 1 else 1
	s.sinceVault = 0
	Parkour.applyMove(p, s, "vault")
	s.sinceLastMove = 0
	local steps = s.vaultChain - 1
	local bonus = if steps >= 1 and steps * c.step <= c.cap then c.step else 0
	s.speed = math.clamp(s.speed + bonus, p.speed.base, p.speed.max)
	return bonus
end

-- A move hands its speed on to the sprint: never slower than the sprint already is, never above speed.max.
-- (Slide end, slide jump.)
function Parkour.carry(p: any, s: State, speed: number)
	s.speed = math.clamp(math.max(s.speed, speed), p.speed.base, p.speed.max)
end

-- Speed falls back towards base once the flow breaks (no fresh move for flowGrace seconds).
-- The repeat chain only resets after a real pause (no move at all for flowGrace), so a spammed
-- move can't restart its full gain every time speed reaches base (that made a +3.5 sawtooth).
function Parkour.decay(p: any, s: State, dt: number)
	s.sinceLastMove += dt
	s.sinceVault += dt
	s.sinceAnyMove += dt
	if s.sinceLastMove > p.speed.flowGrace and s.speed > p.speed.base then
		s.speed = math.max(p.speed.base, s.speed - p.speed.decayPerSecond * dt)
	end
	if s.sinceAnyMove > p.speed.flowGrace then
		s.lastMove, s.repeatCount = nil, 0
	end
end

-- Running straight into a wall.
function Parkour.bonk(p: any, s: State)
	s.speed = math.max(p.speed.base, s.speed * p.speed.bonkFactor)
	s.lastMove, s.repeatCount = nil, 0
end

-- Which jump a jump press means right now: "jump", "doubleJump" or nil. (Vaulting is the toolbox Vaulting System,
-- src/client/Vault.client.luau, and the wall run and wall jump are the FREE R6 Wall Run package, src/client/WallRun.)
function Parkour.jumpKind(p: any, s: State): string?
	if s.grounded or s.timeSinceGrounded <= p.jump.coyoteTime then
		return "jump"
	end
	if s.airJumpsUsed < p.jump.airJumps then
		return "doubleJump"
	end
	return nil
end

-- Vertical take-off speed for a jump of `height` studs.
function Parkour.jumpVelocity(m: any, height: number): number
	return math.sqrt(2 * m.gravity * height)
end

-- Is a slide pressed in the air (pressedAt) still waiting to happen on touchdown at `now`? (designer 2026-11-19)
function Parkour.slideBuffered(p: any, pressedAt: number?, now: number): boolean
	return pressedAt ~= nil and now - pressedAt >= 0 and now - pressedAt <= p.slide.bufferTime
end

-- The run clip's playback speed at a running speed: grows runAnim.scale as fast as the speed does above the base,
-- never past runAnim.max (designer 2026-11-19: limbs must not move really fast when you speed up).
function Parkour.runAnimSpeed(p: any, speed: number): number
	local a = p.runAnim
	return math.clamp(1 + (speed / p.speed.base - 1) * a.scale, 1, a.max)
end

function Parkour.canSlide(p: any, s: State): boolean
	return s.grounded and s.speed >= p.slide.minSpeed and s.sinceSlide >= p.slide.cooldown
end

-- Hip height while sliding, so the body (root part of height rootHeight) stays under slide.height.
function Parkour.slideHipHeight(p: any, rootHeight: number): number
	return math.max(p.slide.minHip, p.slide.height - rootHeight - p.slide.clearance)
end

-- A slide ends only where there is room to stand: under a low ceiling you stay low and keep going.
-- headroom = free space above the feet.
function Parkour.canStandUp(m: any, headroom: number): boolean
	return headroom >= m.characterHeight
end

-- What a landing does. fallHeight in studs, rollTiming = seconds between pressing slide and
-- touching down (nil if not pressed). Returns kind ("soft", "roll", "hard") and the speed after.
function Parkour.landing(p: any, s: State, fallHeight: number, rollTiming: number?): (string, number)
	local l = p.landing
	if fallHeight <= l.safeHeight then
		return "soft", s.speed
	end
	local rolled = rollTiming ~= nil and rollTiming >= 0 and rollTiming <= l.rollWindow
	if rolled and fallHeight <= l.rollMaxHeight then
		local gain = Parkour.gainFor(p, s, "landRoll")
		return "roll", math.clamp(s.speed + gain, p.speed.base, p.speed.max)
	end
	return "hard", math.max(p.speed.base * l.hardSpeedFactor, s.speed * l.hardSpeedFactor)
end

return Parkour
