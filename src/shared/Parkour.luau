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
	wallRunning: boolean,
	wallRunTime: number,
	sinceSlide: number,
	sinceVault: number,
	heightAboveGround: number,
	lastWallId: string?,
	sinceLeftWall: number,
}

export type Wall = { normal: Vec2, distance: number, id: string }
export type Obstacle = {
	topHeight: number, -- top above the feet
	distance: number, -- from the body front to the obstacle's near face
	depth: number, -- obstacle thickness along the run direction
	topClear: boolean, -- room on top for the body to pass
	landClear: boolean, -- nothing in the way of the landing
}
export type VaultPlan = { distance: number, rise: number, peakAt: number, duration: number }

local Parkour = {}

local function dot(a: Vec2, b: Vec2): number
	return a.x * b.x + a.z * b.z
end

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
		wallRunning = false,
		wallRunTime = 0,
		sinceSlide = math.huge,
		sinceVault = math.huge,
		heightAboveGround = 0,
		lastWallId = nil,
		sinceLeftWall = math.huge,
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

-- Speed falls back towards base once the flow breaks (no fresh move for flowGrace seconds).
-- The repeat chain only resets after a real pause (no move at all for flowGrace), so a spammed
-- move can't restart its full gain every time speed reaches base (that made a +3.5 sawtooth).
function Parkour.decay(p: any, s: State, dt: number)
	s.sinceLastMove += dt
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

-- Which jump a jump press means right now: "vault", "jump", "wallJump", "doubleJump" or nil.
-- vaultReady = an obstacle close ahead passes canVault (vaulting is on the jump button, never automatic).
-- Coyote time lets a jump happen just after running off an edge.
function Parkour.jumpKind(p: any, s: State, vaultReady: boolean?): string?
	if s.wallRunning then
		return "wallJump"
	end
	if vaultReady and s.grounded then
		return "vault"
	end
	if s.grounded or s.timeSinceGrounded <= p.jump.coyoteTime then
		return "jump"
	end
	if s.airJumpsUsed < p.jump.airJumps then
		return "doubleJump"
	end
	return nil
end

-- Can a wall run start against `wall`, moving in `dir` (unit)? Returns ok and a reason when not.
function Parkour.canWallRun(p: any, s: State, wall: Wall?, dir: Vec2): (boolean, string)
	local w = p.wallRun
	if s.grounded then
		return false, "grounded"
	end
	if not wall then
		return false, "no wall"
	end
	if wall.distance > w.reach then
		return false, "wall too far"
	end
	if s.speed < w.minSpeed then
		return false, "too slow"
	end
	if s.heightAboveGround < w.minHeight then
		return false, "too low"
	end
	if wall.id == s.lastWallId and s.sinceLeftWall < w.sameWallCooldown then
		return false, "same wall"
	end
	-- Moving along the wall: the angle between run direction and the wall surface is small.
	-- |dot(dir, normal)| = sin(angle). Moving away from the wall (dot > 0) never starts a run.
	local d = dot(dir, wall.normal)
	if d > 0.1 then
		return false, "moving away"
	end
	if math.abs(d) > math.sin(math.rad(w.maxAngle)) then
		return false, "angle too steep"
	end
	return true, "ok"
end

-- Whether a wall run must end now.
function Parkour.wallRunEnds(p: any, s: State, wall: Wall?, grounded: boolean): boolean
	return grounded or not wall or wall.distance > p.wallRun.reach or s.wallRunTime >= p.wallRun.maxDuration
end

-- Direction along the wall to run in: the move direction with the into-wall part removed.
function Parkour.wallRunDirection(dir: Vec2, normal: Vec2): Vec2
	local d = dot(dir, normal)
	local x, z = dir.x - normal.x * d, dir.z - normal.z * d
	local len = math.sqrt(x * x + z * z)
	if len < 1e-6 then
		return { x = -normal.z, z = normal.x }
	end
	return { x = x / len, z = z / len }
end

-- Launch velocity of a wall jump: up by wallJump.height, away from the wall by wallJump.push,
-- keeping the along-wall run speed. With allowBurst = 0 the horizontal speed is clamped to
-- speed.max; with 1 it may briefly go over (a punchy burst). Returns horizontal {x, z} and up speed.
function Parkour.wallJumpVelocity(p: any, m: any, s: State, runDir: Vec2, normal: Vec2): (Vec2, number)
	local up = math.sqrt(2 * m.gravity * p.wallJump.height)
	local x = runDir.x * s.speed + normal.x * p.wallJump.push
	local z = runDir.z * s.speed + normal.z * p.wallJump.push
	local len = math.sqrt(x * x + z * z)
	if p.wallJump.allowBurst == 0 and len > p.speed.max then
		x, z = x / len * p.speed.max, z / len * p.speed.max
	end
	return { x = x, z = z }, up
end

-- Vertical take-off speed for a jump of `height` studs.
function Parkour.jumpVelocity(m: any, height: number): number
	return math.sqrt(2 * m.gravity * height)
end

-- Is the obstacle ahead a vault (not a step, not a wall)?
function Parkour.canVault(p: any, s: State, ob: Obstacle?): (boolean, string)
	local v = p.vault
	if not ob then
		return false, "nothing ahead"
	end
	if ob.distance > v.detectDistance then
		return false, "too far"
	end
	if ob.topHeight < v.minHeight then
		return false, "just a step"
	end
	if ob.topHeight > v.maxHeight then
		return false, "a wall"
	end
	if ob.depth > v.maxDepth then
		return false, "too deep"
	end
	if not ob.topClear then
		return false, "no room on top"
	end
	if not ob.landClear then
		return false, "no room to land"
	end
	if s.speed < v.minSpeed then
		return false, "too slow"
	end
	if s.sinceVault < v.cooldown then
		return false, "cooldown"
	end
	return true, "ok"
end

-- The path of a vault. legLength = feet to the bottom of the torso (2 on R6).
-- distance: forward travel (approach + obstacle + landing); rise: how far the body goes up so the torso
-- clears the top by vault.clearance; peakAt: 0..1, where the arc peaks (over the obstacle's middle);
-- duration: distance / speed, kept within vault.minDuration..maxDuration.
function Parkour.vaultPlan(p: any, s: State, ob: Obstacle, legLength: number): VaultPlan
	local v = p.vault
	local distance = ob.distance + ob.depth + v.landDistance
	local rise = math.max(0.3, ob.topHeight + v.clearance - legLength)
	local peakAt = math.clamp((ob.distance + ob.depth / 2) / distance, 0.2, 0.8)
	local duration = math.clamp(distance / math.max(s.speed, p.speed.base), v.minDuration, v.maxDuration)
	return { distance = distance, rise = rise, peakAt = peakAt, duration = duration }
end

-- Where the body is along a vault at t (0..1): forward distance and height above the start.
-- Forward moves at a steady speed; height rises on a quarter sine to the peak and comes back down on
-- another, so the arc is smooth at the top and lands with no bump.
function Parkour.vaultOffset(plan: VaultPlan, t: number): (number, number)
	t = math.clamp(t, 0, 1)
	local up
	if t <= plan.peakAt then
		up = plan.rise * math.sin(math.pi / 2 * t / plan.peakAt)
	else
		up = plan.rise * math.cos(math.pi / 2 * (t - plan.peakAt) / (1 - plan.peakAt))
	end
	return plan.distance * t, up
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
