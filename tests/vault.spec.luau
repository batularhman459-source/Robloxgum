local VaultMath = require("../src/shared/VaultMath")

return {
	["vault: half extent of a box along a direction"] = function(t)
		t.eq(VaultMath.halfExtent({ 0, 0, 1 }, { 6, 2, 1.5 }), 0.75, "facing straight at the thin side")
		t.eq(VaultMath.halfExtent({ 0, 0, -1 }, { 6, 2, 1.5 }), 0.75, "sign does not matter")
		local d = math.sqrt(0.5)
		t.ok(math.abs(VaultMath.halfExtent({ d, 0, d }, { 2, 2, 2 }) - 2 * d) < 1e-9, "a 45 degree view of a cube")
	end,

	["vault: the push fires by time or by distance, whichever comes first"] = function(t)
		local v = t.rules("vault")
		local far = v.push.atDistance + 2
		t.ok(not VaultMath.pushNow(v, 0, far), "not yet: early and far")
		t.ok(VaultMath.pushNow(v, v.push.delay, far), "delay reached")
		t.ok(VaultMath.pushNow(v, 0, v.push.atDistance), "close enough")
		t.ok(VaultMath.pushNow(v, 0, -1), "already over the box")
		t.eq(VaultMath.faceDistance(5, 0.75), 4.25)
	end,

	["vault: forward speed eases, never snaps, and hands over at the sprint speed"] = function(t)
		local v, p = t.rules("vault"), t.rules("parkour")
		local entry, peak = p.speed.base, v.push.normalForward
		local exit = VaultMath.exitSpeed(p, entry)
		local duration = 0.3
		t.eq(VaultMath.forwardSpeed(v, -1, duration, entry, peak, exit), entry, "before the push: run-up speed")
		t.eq(VaultMath.forwardSpeed(v, 0, duration, entry, peak, exit), entry, "no jump at the push")
		t.eq(VaultMath.forwardSpeed(v, duration, 0, entry, peak, exit), exit, "no jump at the exit")
		-- the biggest change in one 60 fps frame is a small share of the full swing
		local dt, worst, last = 1 / 60, 0, VaultMath.forwardSpeed(v, 0, duration, entry, peak, exit)
		for i = 1, math.floor(duration / dt) do
			local tt = i * dt
			local sp = VaultMath.forwardSpeed(v, tt, math.max(0, duration - tt), entry, peak, exit)
			worst = math.max(worst, math.abs(sp - last))
			last = sp
		end
		t.ok(worst < (peak - entry) * 0.5, string.format("largest one-frame change %.1f", worst))
		t.ok(exit >= entry, "the vault never loses speed")
	end,

	["vault: ends at the clip end only once clear of the obstacle, never too late"] = function(t)
		local v = t.rules("vault")
		t.ok(not VaultMath.canFinish(v, -0.01, true), "not before the clip ends")
		t.ok(VaultMath.canFinish(v, 0, true), "clip done and clear")
		t.ok(not VaultMath.canFinish(v, 0, false), "still over the box: keep going")
		t.ok(VaultMath.canFinish(v, v.feel.maxOverrun, false), "but never longer than maxOverrun")
	end,

	["vault: never slower than the run-up, in or out (only speed.max caps it)"] = function(t)
		local v, p = t.rules("vault"), t.rules("parkour")
		for _, entry in { p.speed.base, p.speed.base + 7, v.push.stepForward + 5 } do
			local peak = VaultMath.peakSpeed(v.push.stepForward, entry)
			local exit = VaultMath.exitSpeed(p, entry)
			t.ok(peak >= entry, "a slow push never brakes a fast run-up")
			t.ok(exit >= math.min(entry, p.speed.max), string.format("exit %.1f keeps entry %.1f", exit, entry))
			local slowest = math.huge
			for i = 0, 30 do
				local tt = i / 100
				slowest = math.min(slowest, VaultMath.forwardSpeed(v, tt, 0.3 - tt, entry, peak, exit))
			end
			t.ok(slowest >= math.min(entry, exit) - 1e-9, string.format("never below the run-up (%.1f)", slowest))
		end
	end,

	["vault: the high band below maxHeight is not empty"] = function(t)
		local v = t.rules("vault")
		t.ok(v.types.normalBelow < v.detect.maxHeight, "the high band is not empty")
	end,

	["vault: the obstacle turns solid only once the body is clear of it"] = function(t)
		local leg = 2
		t.ok(not VaultMath.clearOf(-1.4, true, leg), "feet above the top but at the back edge: not yet (the snag)")
		t.ok(VaultMath.clearOf(-leg - 0.1, false, leg), "a leg length past the far face")
		t.ok(VaultMath.clearOf(leg + 1, true, leg), "on top of a deep box")
		t.ok(not VaultMath.clearOf(1, false, leg), "still inside")
	end,
}
