local SpeedFeelMath = require("../src/shared/SpeedFeelMath")

return {
	["speed feel numbers: in order, sprint calm, never excessive"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.ok(r.fov.fromSpeed < r.fov.toSpeed and r.lines.fromSpeed < r.lines.toSpeed, "ranges in order")
		t.ok(SpeedFeelMath.lineRate(r, p.speed.base) < r.lines.rate * 0.25, "only a few lines at plain sprint speed")
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

	["speed feel: lines grow with speed"] = function(t)
		local r, p = t.rules("speedfeel"), t.rules("parkour")
		t.eq(SpeedFeelMath.lineRate(r, r.lines.fromSpeed), 0, "none below fromSpeed")
		t.ok(SpeedFeelMath.lineRate(r, p.speed.max) > SpeedFeelMath.lineRate(r, p.speed.base), "more when faster")
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

	["speed lines: straight radial lines, pointing at the centre, sliding outward, never in the middle"] = function(t)
		local r = t.rules("speedfeel")
		local l = r.lines
		t.ok(l.innerMin >= 0.4, "the middle of the screen stays clear")
		t.ok(l.fadeIn > 0 and l.fadeIn < 1 and l.thickness > 0, "fades in and out, has a thickness")
		local w, h = 1366, 768
		local half = math.sqrt(w * w + h * h) / 2
		local line = { angle = math.rad(30), inner = l.innerMin, length = l.lengthMin, life = 0.2 }
		local x0, y0, _, rot, tr0 = SpeedFeelMath.radialLine(r, line, 0, w, h)
		local x1, y1, _, _, trMid = SpeedFeelMath.radialLine(r, line, 0.2 * l.fadeIn, w, h)
		local x2, y2, _, _, tr2 = SpeedFeelMath.radialLine(r, line, 0.2, w, h)
		t.ok(math.abs(rot - 30) < 1e-9, "rotated to point at the centre")
		local function dist(x, y)
			return math.sqrt((x - w / 2) ^ 2 + (y - h / 2) ^ 2)
		end
		t.ok(dist(x2, y2) > dist(x1, y1) and dist(x1, y1) > dist(x0, y0), "slides outward")
		t.ok(math.abs(math.atan2(y2 - h / 2, x2 - w / 2) - line.angle) < 1e-9, "stays on its ray (straight)")
		t.ok(dist(x0, y0) - l.lengthMin * half / 2 >= l.innerMin * half - 1e-6, "starts away from the centre")
		t.eq(tr0, 1, "invisible when born")
		t.ok(math.abs(trMid - l.transparency) < 1e-9, "fully shown after the fade in")
		t.eq(tr2, 1, "gone at the end")
	end,
}
