local SpeedFeelMath = require("../src/shared/SpeedFeelMath")

return {
	["speed feel numbers: in order, sprint calm, never excessive"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.ok(r.fov.fromSpeed < r.fov.toSpeed and r.lines.fromSpeed < r.lines.toSpeed, "ranges in order")
		t.ok(r.lines.fromSpeed > p.speed.base, "no lines at plain sprint speed")
		t.ok(r.fov.base + r.fov.add <= 90, "field of view stays sane")
		t.ok(r.fov.smoothing > 0, "smoothed, no snaps")
		for name in r do
			if name ~= "source" then
				t.ok(type(r.source[name]) == "string", "[" .. name .. "] needs a source entry")
			end
		end
	end,

	["speed feel: the field of view grows with speed, smoothly, and tops out"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.eq(SpeedFeelMath.fovExtra(r, r.fov.fromSpeed), 0)
		local sprint = SpeedFeelMath.fovExtra(r, p.speed.base)
		local fast = SpeedFeelMath.fovExtra(r, p.speed.max)
		t.ok(sprint > 0 and fast > sprint, "more at the cap than at the sprint")
		t.eq(SpeedFeelMath.fovExtra(r, 1000), r.fov.add, "tops out")
		local last, worst = 0, 0
		for v = 0, 80 do
			local e = SpeedFeelMath.fovExtra(r, v)
			worst = math.max(worst, e - last)
			t.ok(e >= last - 1e-9, "never shrinks as speed rises")
			last = e
		end
		t.ok(worst < r.fov.add / 5, "no jumps per stud/s")
	end,

	["speed feel: lines only when fast"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.eq(SpeedFeelMath.lineRate(r, p.speed.base), 0, "none at sprint")
		t.eq(SpeedFeelMath.lineRate(r, r.lines.toSpeed), r.lines.rate, "full at toSpeed")
	end,

	["speed feel: follow is frame-rate independent"] = function(t)
		local a = 0
		for _ = 1, 60 do
			a = SpeedFeelMath.follow(a, 10, 1 / 60, 0.25)
		end
		local b = 0
		for _ = 1, 30 do
			b = SpeedFeelMath.follow(b, 10, 1 / 30, 0.25)
		end
		t.ok(math.abs(a - b) < 1e-6, "same after 1 s at 60 and 30 fps")
	end,
}
