--!strict
-- The double jump's frontflip timeline (rules/flip.toml). Pure: rules in, numbers out. Sampling uses
-- R6Pose.sampleAxis, passed in (shared/ has no requires); the keys are plain {t, pose} like R6Pose's.
local FlipMath = {}

export type Key = { t: number, pose: { [string]: { [string]: number } } }

function FlipMath.keys(r: any): { Key }
	local out = {}
	for _, k in r.keys do
		table.insert(out, { t = k.t, pose = k.pose or {} })
	end
	return out
end

function FlipMath.length(keys: { Key }): number
	return keys[#keys].t
end

-- How much the flip owns the joints (vs the jump animation) at time t, eased in and out.
function FlipMath.weight(r: any, t: number, length: number): number
	local x = math.min(math.clamp(t / r.timing.blendIn, 0, 1), math.clamp((length - t) / r.timing.blendOut, 0, 1))
	return x * x * (3 - 2 * x)
end

return FlipMath
