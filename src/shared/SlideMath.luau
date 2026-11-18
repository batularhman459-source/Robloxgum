--!strict
-- The slide's speed over time and its pose. Pure: rules in (parkour.toml [slide], slide.toml), numbers out.
-- Used by src/client/ParkourController.client.luau (speed) and src/client/SlideFeel.luau (pose).
--
-- Speed (designer spec 2026-11-17): a burst that eases up to slide.burstSpeed in burstRise seconds (no
-- single-frame snap), then eases back down to the exit (sprint) speed by slide.duration on flat ground. Slopes
-- add a bonus on top: downhill builds it (slopeAccel per unit of steepness), uphill eats it, flat ground lets it
-- fade (slopeBonusDecay). A downhill past duration keeps the slide going, up to maxDuration.
local SlideMath = {}

export type Slide = {
	t: number, -- seconds since the slide started
	bonus: number, -- speed won (or lost) on slopes
	entry: number, -- speed going in
	exit: number, -- sprint speed to come out at
	speed: number, -- current slide speed
}

function SlideMath.new(entry: number, exit: number): Slide
	return { t = 0, bonus = 0, entry = entry, exit = exit, speed = entry }
end

-- Speed on flat ground at time t.
function SlideMath.flat(p: any, t: number, entry: number, exit: number): number
	local sl = p.slide
	local burst = math.max(sl.burstSpeed, entry) -- a faster run-up is never braked to the burst
	if t < sl.burstRise then
		local u = t / sl.burstRise
		return entry + (burst - entry) * (1 - (1 - u) * (1 - u))
	end
	local u = math.clamp((t - sl.burstRise) / (sl.duration - sl.burstRise), 0, 1)
	return exit + (burst - exit) * (1 - u) * (1 - u)
end

-- Advances the slide by dt. downhill = slide direction dotted with the ground normal's flat part
-- (= sin of the slope along the slide; + downhill, - uphill, 0 flat). Returns the new speed.
function SlideMath.step(p: any, s: Slide, dt: number, downhill: number): number
	local sl = p.slide
	s.t += dt
	s.bonus += (sl.slopeAccel * downhill - s.bonus / sl.slopeBonusDecay) * dt
	s.speed = math.clamp(SlideMath.flat(p, s.t, s.entry, s.exit) + s.bonus, 0, sl.maxSpeed)
	return s.speed
end

-- Is the slide over? Never before duration unless it slowed under minSpeed (uphill); after duration only
-- once the ground is no longer a downhill; never later than maxDuration.
function SlideMath.done(p: any, s: Slide, downhill: number): boolean
	local sl = p.slide
	if s.t >= sl.maxDuration then
		return true
	end
	if s.t > sl.burstRise and s.speed < sl.minSpeed then
		return true
	end
	return s.t >= sl.duration and downhill < sl.keepDownhill
end

-- The slide pose as R6Pose angle tables (src/shared/R6Pose.luau body terms), from slide.toml [pose].
function SlideMath.pose(f: any): { [string]: { [string]: number } }
	local q = f.pose
	return {
		root = { pitch = q.rootPitch, y = q.rootY },
		head = { pitch = q.headPitch },
		rleg = { fwd = q.rlegFwd, out = q.rlegOut },
		lleg = { fwd = q.llegFwd, out = q.llegOut, twist = q.llegTwist },
		larm = { fwd = q.larmFwd, out = q.larmOut },
		rarm = { fwd = q.rarmFwd, out = q.rarmOut },
	}
end

-- The speed a slide hands on to the sprint, when it ends or is cancelled: the sprint speed plus whatever a downhill
-- added (designer 2026-11-18: sliding down a slope keeps that speed). Flat ground and uphill add nothing.
function SlideMath.keepSpeed(s: Slide): number
	return s.exit + math.max(0, s.bonus)
end

-- Slide cancel (designer 2026-11-18: C again stands you up, keeping the slide's speed + gain.slideCancel). Not in
-- the first slide.cancelAfter seconds, so tapping C twice cannot farm the burst.
function SlideMath.canCancel(p: any, s: Slide): boolean
	return s.t >= p.slide.cancelAfter
end

-- The camera kick's strength 0..1 at t seconds after it started (slide.toml [kick]): a fast rise to the peak in
-- `attack`, then an ease-out back to 0 by `time`.
function SlideMath.kick(k: any, t: number): number
	if t < 0 or t >= k.time then
		return 0
	elseif t < k.attack then
		return t / k.attack
	end
	local u = (t - k.attack) / (k.time - k.attack)
	return (1 - u) * (1 - u)
end

-- ===== The slide's motion: entry -> hold -> exit (designer feedback 2026-11-17: "too stiff, entry and exit not
-- good"). Keys come from slide.toml [[entry]] / [[exit]]; R6Pose.sampleAxis is passed in (shared/ has no requires).

export type Pose = { [string]: { [string]: number } }
export type Key = { t: number, pose: Pose }
local JOINTS = {
	root = { "pitch", "roll", "yaw", "y" },
	head = { "pitch", "roll", "yaw", "y" },
	rarm = { "fwd", "out", "twist" },
	larm = { "fwd", "out", "twist" },
	rleg = { "fwd", "out", "twist" },
	lleg = { "fwd", "out", "twist" },
}
SlideMath.JOINTS = JOINTS

-- Rules keys -> R6Pose keys: `hold = true` becomes the [pose]; a missing pose is standing ({}).
function SlideMath.keys(f: any, list: { any }, from: Pose?): { Key }
	local out = {}
	for i, k in list do
		local pose = if k.hold then SlideMath.pose(f) else (k.pose or {})
		if i == 1 and from then
			pose = from -- the exit starts from wherever the body is
		end
		table.insert(out, { t = k.t, pose = pose })
	end
	return out
end

function SlideMath.length(keys: { Key }): number
	return keys[#keys].t
end

-- Samples every joint axis at t. The legs are sampled legShift seconds later (+) or earlier (-) than the rest.
function SlideMath.sample(sampleAxis: any, keys: { Key }, t: number, legShift: number): Pose
	local len = SlideMath.length(keys)
	local out: Pose = {}
	for joint, axes in JOINTS do
		local tt = if joint == "rleg" or joint == "lleg" then t + legShift else t
		tt = math.clamp(tt, 0, len)
		local a = {}
		for _, axis in axes do
			a[axis] = sampleAxis(keys, joint, axis, tt)
		end
		out[joint] = a
	end
	return out
end

-- Adds the hold's life to a pose: sway (sine motions, t = seconds into the hold) scaled by `amount` 0..1, and the
-- lean that follows speed (speed01: 0 at sprint speed, 1 at the full burst). Changes the pose in place.
function SlideMath.alive(f: any, pose: Pose, t: number, speed01: number, amount: number)
	local w = f.sway
	local function wave(amp: number, hz: number): number
		return amp * math.sin(t * hz * 2 * math.pi) * amount
	end
	pose.root.roll = (pose.root.roll or 0) + wave(w.rootRollAmp, w.rootRollHz)
	pose.root.pitch = (pose.root.pitch or 0) + w.leanAtBurst * math.clamp(speed01, 0, 1) * amount
	pose.rarm.fwd = (pose.rarm.fwd or 0) + wave(w.rarmAmp, w.rarmHz)
	pose.larm.fwd = (pose.larm.fwd or 0) + wave(w.larmAmp, w.larmHz)
	pose.head.yaw = (pose.head.yaw or 0) + wave(w.headYawAmp, w.headYawHz)
end

-- How much the slide owns the joints (vs the run animation) at time t of a phase, eased.
function SlideMath.weight(f: any, phase: string, t: number, exitLength: number): number
	local x
	if phase == "entry" then
		x = math.clamp(t / f.timing.blendIn, 0, 1)
	elseif phase == "exit" then
		x = math.clamp((exitLength - t) / f.timing.blendOut, 0, 1)
	else
		x = 1
	end
	return x * x * (3 - 2 * x)
end

return SlideMath
