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

-- One radial speed line at age t of its life: where it sits on the screen and how visible it is.
-- line = { angle (radians), inner (0..1), length (0..1), life (s) }, w/h = screen size in pixels.
-- Returns centre x, centre y (pixels), length (pixels), rotation (degrees), transparency (1 = invisible).
function SpeedFeelMath.radialLine(
	r: any,
	line: any,
	t: number,
	w: number,
	h: number
): (number, number, number, number, number)
	local l = r.lines
	local half = math.sqrt(w * w + h * h) / 2
	local u = math.clamp(t / line.life, 0, 1)
	local inner = (line.inner + l.travel * u) * half
	local length = line.length * half
	local mid = inner + length / 2
	local cx, cy = w / 2 + math.cos(line.angle) * mid, h / 2 + math.sin(line.angle) * mid
	local vis = if u < l.fadeIn then u / l.fadeIn else (1 - u) / (1 - l.fadeIn)
	local transparency = 1 - (1 - l.transparency) * math.clamp(vis, 0, 1)
	return cx, cy, length, math.deg(line.angle), transparency
end

return SpeedFeelMath
