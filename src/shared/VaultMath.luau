--!strict
-- Vault timing for the toolbox vault (src/client/Vault.client.luau). Pure: rules (rules/vault.toml) and numbers in.
--
-- The push fires after push.delay OR as soon as the body is within push.atDistance of the obstacle's near face,
-- whichever comes first. Why (designer 2026-11-17): the vault now keeps the run-up speed, so in the 0.12 s delay
-- the body ran ~2.4 studs closer and the push came too late for the feet to clear the top (measured: 2 stud
-- ledge -0.20, 4.5 stud -0.72). Firing by distance puts the push back where it was when the body still braked.
local VaultMath = {}

-- Half the size of a box along a direction. dots = the direction dotted with the box's own X, Y, Z axes,
-- size = the box size {x, y, z}.
function VaultMath.halfExtent(dots: { number }, size: { number }): number
	return (math.abs(dots[1]) * size[1] + math.abs(dots[2]) * size[2] + math.abs(dots[3]) * size[3]) / 2
end

-- Distance from the body to the box's near face along the facing. along = (box centre - body) dotted with the
-- facing, half = halfExtent along the facing. Negative = already over the box.
function VaultMath.faceDistance(along: number, half: number): number
	return along - half
end

function VaultMath.pushNow(v: any, elapsed: number, faceDistance: number): boolean
	return elapsed >= v.push.delay or faceDistance <= v.push.atDistance
end

-- Forward speed during the vault, eased so it never snaps (designer 2026-11-17: the boost felt choppy, too
-- instant: it jumped 20 -> 60 at the push and 60 -> 22 at the exit in one frame each).
--   before the push: the run-up speed (entry);
--   after it: eases OUT from entry up to the push speed (peak) over feel.rampUp seconds, fast then settling;
--   the last feel.settle seconds: smoothstep from there down to the exit (sprint) speed, so the hand-off to
--   the sprint has no jump and no kink.
-- sincePush < 0 = not pushed yet. left = seconds until the vault ends.
function VaultMath.forwardSpeed(
	v: any,
	sincePush: number,
	left: number,
	entry: number,
	peak: number,
	exit: number
): number
	if sincePush < 0 then
		return entry
	end
	local r = math.clamp(sincePush / v.feel.rampUp, 0, 1)
	local rising = entry + (peak - entry) * (1 - (1 - r) * (1 - r))
	local f = math.clamp(1 - left / v.feel.settle, 0, 1)
	f = f * f * (3 - 2 * f)
	return rising + (exit - rising) * f
end

-- Can the vault end? Not before the clip's end (sinceEnd < 0). After it, only once the body is clear of the
-- obstacle, or feel.maxOverrun seconds late at most. Why (playtest 2026-11-17): with the eased speed the short
-- step clip ended with the body still inside its box, and the box turning solid again bumped it 0.8 up.
function VaultMath.canFinish(v: any, sinceEnd: number, clear: boolean): boolean
	return sinceEnd >= 0 and (clear or sinceEnd >= v.feel.maxOverrun)
end

-- Is the body clear of the obstacle, so its collision can come back? farAhead = distance from the body to the far
-- face (negative = past it). Clear once a whole leg length past the far face, or with the feet above the top and
-- still a leg length of top ahead (landing on a deep box). Why (playtest 2026-11-17): "feet above the top" alone
-- turned the box solid over its back edge, and the trailing legs snagged it on the way down (24 -> 15).
function VaultMath.clearOf(farAhead: number, feetAboveTop: boolean, legLength: number): boolean
	return farAhead < -legLength or (feetAboveTop and farAhead > legLength)
end

-- The sprint speed the vault hands back: run-up speed plus the parkour vault gain, inside the speed limits, and
-- never less than the run-up speed (designer 2026-11-17: no speed loss in or out; only speed.max caps it).
function VaultMath.exitSpeed(parkour: any, entry: number): number
	return math.min(math.max(entry + parkour.gain.vault, parkour.speed.base), parkour.speed.max)
end

-- The top forward speed of the vault: the push's own speed, or the run-up speed if that is faster, so a fast
-- run-up is never braked by a slower push.
function VaultMath.peakSpeed(push: number, entry: number): number
	return math.max(push, entry)
end

return VaultMath
