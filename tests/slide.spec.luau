local SlideMath = require("../src/shared/SlideMath")
local Parkour = require("../src/shared/Parkour")
local R6Pose = require("../src/shared/R6Pose")

local DT = 1 / 60

-- Runs a slide on constant ground until it ends; returns the speeds per frame and the slide.
local function run(p, entry, exit, downhill)
	local s = SlideMath.new(entry, exit)
	local speeds = {}
	repeat
		table.insert(speeds, SlideMath.step(p, s, DT, downhill))
	until SlideMath.done(p, s, downhill)
	return speeds, s
end

return {
	["slide numbers: burst above sprint, rise shorter than the slide, jump = a normal jump"] = function(t)
		local p, m = t.rules("parkour"), t.rules("movement")
		local sl = p.slide
		t.ok(sl.burstSpeed > p.speed.max, "the burst is faster than any sprint")
		t.ok(sl.burstRise > 0 and sl.burstRise < sl.duration, "burstRise inside the slide")
		t.ok(sl.duration < sl.maxDuration, "maxDuration longer than a flat slide")
		t.ok(sl.maxSpeed >= sl.burstSpeed, "maxSpeed lets slopes add speed")
		t.ok(sl.minSpeed <= p.speed.base, "a sprint at base speed can slide")
		t.eq(sl.jumpHeight, m.jumpHeight, "slide jump height = movement.jumpHeight (rule agreement)")
		t.ok(p.gain.slideJump >= 0, "the slide jump never takes speed away")
	end,

	["slide: on flat ground it bursts, then eases back to the sprint speed by duration"] = function(t)
		local p = t.rules("parkour")
		local entry, exit = p.speed.base, p.speed.base + p.gain.slide
		local speeds, s = run(p, entry, exit, 0)
		local top = 0
		for _, v in speeds do
			top = math.max(top, v)
		end
		t.ok(math.abs(top - p.slide.burstSpeed) < 1, string.format("peak %.1f near the burst", top))
		t.ok(math.abs(s.t - p.slide.duration) <= DT, string.format("ends at %.2f s", s.t))
		t.ok(math.abs(speeds[#speeds] - exit) < 0.5, string.format("ends at %.1f, the sprint speed", speeds[#speeds]))
	end,

	["slide: no single-frame snap in or out"] = function(t)
		local p = t.rules("parkour")
		local entry = p.speed.base
		local speeds = run(p, entry, entry + p.gain.slide, 0)
		local worst, last = 0, entry
		for _, v in speeds do
			worst = math.max(worst, math.abs(v - last))
			last = v
		end
		t.ok(
			worst < (p.slide.burstSpeed - entry) * 0.5,
			string.format("largest one-frame change %.1f of %.1f", worst, p.slide.burstSpeed - entry)
		)
	end,

	["slide: downhill keeps it going and faster, uphill ends it sooner"] = function(t)
		local p = t.rules("parkour")
		local entry, exit = p.speed.base, p.speed.base + p.gain.slide
		local flat, sFlat = run(p, entry, exit, 0)
		local down, sDown = run(p, entry, exit, 0.4)
		local _, sUp = run(p, entry, exit, -0.5)
		t.ok(sDown.t > sFlat.t, "a downhill slide lasts longer")
		t.ok(sDown.t <= p.slide.maxDuration + DT, "but never past maxDuration")
		t.ok(down[#flat] > flat[#flat], "and is faster at the same moment")
		t.ok(sUp.t < sFlat.t, "an uphill slide ends sooner")
		for _, v in down do
			t.ok(v <= p.slide.maxSpeed, "capped at maxSpeed")
		end
	end,

	["slide: a faster run-up is never braked by the burst"] = function(t)
		local p = t.rules("parkour")
		local fast = p.slide.burstSpeed + 10
		t.ok(SlideMath.flat(p, p.slide.burstRise, fast, p.speed.base) >= fast - 1e-9, "keeps the run-up speed")
	end,

	["slide: its speed carries into the sprint, capped"] = function(t)
		local p = t.rules("parkour")
		local s = Parkour.newState(p)
		Parkour.carry(p, s, p.speed.max + 20)
		t.eq(s.speed, p.speed.max)
		local slow = Parkour.newState(p)
		Parkour.carry(p, slow, 0)
		t.eq(slow.speed, p.speed.base)
	end,

	["slide motion: entry starts standing and ends in the hold pose, exit ends standing"] = function(t)
		local f = t.rules("slide")
		local entry = SlideMath.keys(f, f.entry)
		local exit = SlideMath.keys(f, f.exit)
		local hold = SlideMath.pose(f)
		local first = SlideMath.sample(R6Pose.sampleAxis, entry, 0, 0)
		local last = SlideMath.sample(R6Pose.sampleAxis, entry, SlideMath.length(entry), 0)
		local stand = SlideMath.sample(R6Pose.sampleAxis, exit, SlideMath.length(exit), 0)
		for joint, axes in SlideMath.JOINTS do
			for _, axis in axes do
				t.eq(first[joint][axis], 0, "entry starts standing: " .. joint .. "." .. axis)
				t.eq(stand[joint][axis], 0, "exit ends standing: " .. joint .. "." .. axis)
				t.eq(last[joint][axis], hold[joint][axis] or 0, "entry ends in the hold: " .. joint .. "." .. axis)
			end
		end
	end,

	["slide motion: the entry overshoots the hold lean (anticipation then overshoot, not a straight blend)"] = function(
		t
	)
		local f = t.rules("slide")
		local entry = SlideMath.keys(f, f.entry)
		local most, forward = 0, 0
		for i = 0, 60 do
			local pose = SlideMath.sample(R6Pose.sampleAxis, entry, SlideMath.length(entry) * i / 60, 0)
			most = math.min(most, pose.root.pitch)
			forward = math.max(forward, pose.root.pitch)
		end
		t.ok(most < f.pose.rootPitch, string.format("leans back past the hold (%.0f < %.0f)", most, f.pose.rootPitch))
		t.ok(forward > 0, "a forward lunge first")
	end,

	["slide motion: the exit starts from wherever the body was"] = function(t)
		local f = t.rules("slide")
		local from = SlideMath.pose(f)
		from.root.pitch = -20
		local exit = SlideMath.keys(f, f.exit, from)
		t.eq(SlideMath.sample(R6Pose.sampleAxis, exit, 0, 0).root.pitch, -20)
	end,

	["slide motion: the hold is alive (sway) and leans back more when faster"] = function(t)
		local f = t.rules("slide")
		local function at(time, speed01)
			local pose = SlideMath.pose(f)
			for _, axes in { "root", "head", "rarm", "larm", "rleg", "lleg" } do
				pose[axes] = pose[axes] or {}
			end
			SlideMath.alive(f, pose, time, speed01, 1)
			return pose
		end
		t.ok(at(0.1, 0).rarm.fwd ~= at(0.3, 0).rarm.fwd, "the arm moves over time")
		t.ok(at(0, 1).root.pitch < at(0, 0).root.pitch, "leans back more at burst speed")
	end,

	["slide motion: the run animation fades out at the start and back in at the end"] = function(t)
		local f = t.rules("slide")
		local exitLen = SlideMath.length(SlideMath.keys(f, f.exit))
		t.eq(SlideMath.weight(f, "entry", 0, exitLen), 0)
		t.eq(SlideMath.weight(f, "entry", f.timing.blendIn, exitLen), 1)
		t.eq(SlideMath.weight(f, "hold", 5, exitLen), 1)
		t.eq(SlideMath.weight(f, "exit", 0, exitLen), 1)
		t.eq(SlideMath.weight(f, "exit", exitLen, exitLen), 0)
	end,

	["slide cancel: not in the first moments, then any time"] = function(t)
		local p = t.rules("parkour")
		local s = SlideMath.new(p.speed.base, p.speed.base)
		t.ok(not SlideMath.canCancel(p, s), "not at the start")
		s.t = p.slide.cancelAfter
		t.ok(SlideMath.canCancel(p, s), "from cancelAfter on")
		t.ok(p.slide.cancelAfter < p.slide.duration, "there is time to cancel")
	end,

	["slide cancel: no speed reward, you leave at the sprint speed (designer 2026-11-18)"] = function(t)
		local p = t.rules("parkour")
		local s = Parkour.newState(p)
		local sprint = s.speed
		Parkour.applyMove(p, s, "slideCancel")
		t.eq(s.speed, math.min(p.speed.max, sprint + p.gain.slideCancel))
		t.ok(p.gain.slideCancel >= 0, "a cancel never takes speed away")
	end,

	["camera kick: rises fast, settles to nothing"] = function(t)
		local k = t.rules("slide").kick
		t.eq(SlideMath.kick(k, 0), 0)
		t.eq(SlideMath.kick(k, k.attack), 1)
		t.ok(SlideMath.kick(k, (k.attack + k.time) / 2) < 0.5, "mostly gone halfway")
		t.eq(SlideMath.kick(k, k.time), 0)
		t.ok(k.attack < k.time, "attack inside the kick")
	end,

	["slide: a downhill slide hands its extra speed on, flat and uphill add nothing"] = function(t)
		local p = t.rules("parkour")
		local exit = p.speed.base + p.gain.slide
		local _, flat = run(p, p.speed.base, exit, 0)
		local _, down = run(p, p.speed.base, exit, 0.4)
		local _, up = run(p, p.speed.base, exit, -0.3)
		t.ok(math.abs(SlideMath.keepSpeed(flat) - exit) < 0.5, "flat: the sprint speed")
		t.ok(SlideMath.keepSpeed(down) > exit + 1, "downhill: faster than the sprint")
		t.eq(SlideMath.keepSpeed(up), exit, "uphill: never slower than the sprint")
	end,
}
