--!strict
-- Movement physics from rules/movement.toml. Pure: no requires, no Roblox APIs.
-- Every map check (can you jump there, how long is this fall, how long from A to B) uses these.
-- Roblox characters keep full walk speed in the air, so horizontal reach = walkSpeed * air time.

export type MoveRules = {
	walkSpeed: number,
	jumpHeight: number,
	gravity: number,
	maxSlopeAngle: number,
	stepHeight: number,
	characterHeight: number,
	characterWidth: number,
	eyeHeight: number,
	jumpMargin: number,
	maxSafeFall: number,
	minCleanDrop: number,
}

local Movement = {}

-- Take-off speed of a jump: v = sqrt(2 g h).
function Movement.jumpVelocity(m: MoveRules): number
	return math.sqrt(2 * m.gravity * m.jumpHeight)
end

-- Seconds in the air for a jump that lands `dh` studs higher (negative = lower).
-- nil when dh is above the jump peak.
function Movement.jumpAirTime(m: MoveRules, dh: number): number?
	if dh > m.jumpHeight then
		return nil
	end
	local v = Movement.jumpVelocity(m)
	return (v + math.sqrt(v * v - 2 * m.gravity * dh)) / m.gravity
end

-- Furthest horizontal distance a jump covers when landing dh higher. Uses jumpMargin.
function Movement.jumpReach(m: MoveRules, dh: number): number
	if dh > m.jumpHeight * m.jumpMargin then
		return 0
	end
	local t = Movement.jumpAirTime(m, dh)
	return if t then m.walkSpeed * t * m.jumpMargin else 0
end

-- Seconds to fall d studs from standing still: t = sqrt(2 d / g).
function Movement.fallTime(m: MoveRules, d: number): number
	return math.sqrt(2 * math.max(d, 0) / m.gravity)
end

-- Speed on landing after falling d studs.
function Movement.landingSpeed(m: MoveRules, d: number): number
	return math.sqrt(2 * m.gravity * math.max(d, 0))
end

function Movement.walkTime(m: MoveRules, dist: number): number
	return dist / m.walkSpeed
end

-- Classifies a drop height: "step", "awkward", "clean" or "unsafe".
function Movement.dropKind(m: MoveRules, d: number): string
	if d <= m.stepHeight then
		return "step"
	elseif d < m.minCleanDrop then
		return "awkward"
	elseif d <= m.maxSafeFall then
		return "clean"
	end
	return "unsafe"
end

-- Steepest walkable surface as the minimum Y of its normal.
function Movement.minWalkNormalY(m: MoveRules): number
	return math.cos(math.rad(m.maxSlopeAngle))
end

return Movement
