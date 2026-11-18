local FlipMath = require("../src/shared/FlipMath")
local SlideMath = require("../src/shared/SlideMath")
local R6Pose = require("../src/shared/R6Pose")

return {
	["flip: starts standing, turns once fully forward, ends standing"] = function(t)
		local r = t.rules("flip")
		local keys = FlipMath.keys(r)
		local len = FlipMath.length(keys)
		local first = SlideMath.sample(R6Pose.sampleAxis, keys, 0, 0)
		local last = SlideMath.sample(R6Pose.sampleAxis, keys, len, 0)
		for joint, axes in SlideMath.JOINTS do
			for _, axis in axes do
				t.eq(first[joint][axis], 0, "starts standing: " .. joint .. "." .. axis)
				local want = if joint == "root" and axis == "pitch" then 360 else 0
				t.eq(last[joint][axis], want, "ends standing: " .. joint .. "." .. axis)
			end
		end
	end,

	["flip: always turning forward (no rocking back), and fast"] = function(t)
		local r = t.rules("flip")
		local keys = FlipMath.keys(r)
		local len = FlipMath.length(keys)
		local last = -1
		for i = 0, 100 do
			local pitch = SlideMath.sample(R6Pose.sampleAxis, keys, len * i / 100, 0).root.pitch
			t.ok(pitch >= last - 1e-6, string.format("pitch %.1f after %.1f", pitch, last))
			last = pitch
		end
		t.ok(len > r.timing.blendIn + r.timing.blendOut, "room to blend in and out")
		for i = 2, #r.keys do
			t.ok(r.keys[i].t > r.keys[i - 1].t, "keys in time order")
		end
	end,

	["flip: the jump animation fades out and back in"] = function(t)
		local r = t.rules("flip")
		local len = FlipMath.length(FlipMath.keys(r))
		t.eq(FlipMath.weight(r, 0, len), 0)
		t.eq(FlipMath.weight(r, len / 2, len), 1)
		t.eq(FlipMath.weight(r, len, len), 0)
	end,

	["flip numbers: effects and sound are sane, every section has a source"] = function(t)
		local r = t.rules("flip")
		t.ok(r.ring.life > 0 and r.ring.sizeStart < r.ring.sizeEnd and r.ring.scale > 0, "ring grows")
		t.ok(string.find(r.ring.texture, "^rbxassetid://%d+$") ~= nil, "ring texture is an asset id")
		t.ok(r.sound.id > 0 and r.sound.volume > 0 and r.sound.pitchMin <= r.sound.pitchMax, "sound")
		for name in r do
			if name ~= "source" then
				t.ok(type(r.source[name]) == "string", "[" .. name .. "] needs a source entry")
			end
		end
	end,
}
