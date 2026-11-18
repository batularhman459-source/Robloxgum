--!strict
-- Sense-of-speed curves (rules/speedfeel.toml). Pure, tested in tests/speedfeel.spec.luau.
local SpeedFeelMath = {}

-- 0..1 between fromSpeed and toSpeed, eased (smoothstep), so the effect grows gently and settles at the top.
function SpeedFeelMath.amount(fromSpeed: number, toSpeed: number, speed: number): number
	local x = math.clamp((speed - fromSpeed) / (toSpeed - fromSpeed), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Extra field of view (degrees) at a speed.
function SpeedFeelMath.fovExtra(r: any, speed: number): number
	return r.fov.add * SpeedFeelMath.amount(r.fov.fromSpeed, r.fov.toSpeed, speed)
end

-- Wind lines per second at a speed.
function SpeedFeelMath.lineRate(r: any, speed: number): number
	return r.lines.rate * SpeedFeelMath.amount(r.lines.fromSpeed, r.lines.toSpeed, speed)
end

-- Follows a target smoothly: `tau` seconds to close ~63% of the gap, the same at any frame rate.
function SpeedFeelMath.follow(current: number, target: number, dt: number, tau: number): number
	return current + (target - current) * (1 - math.exp(-dt / tau))
end

return SpeedFeelMath
