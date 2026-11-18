local RateLimit = require("../src/shared/RateLimit")

return {
	["rate limit: allows max per window, then refuses, then allows again once the window has passed"] = function(t)
		local l = RateLimit.new(3, 1)
		t.ok(RateLimit.allow(l, 0), "1")
		t.ok(RateLimit.allow(l, 0.1), "2")
		t.ok(RateLimit.allow(l, 0.2), "3")
		t.ok(not RateLimit.allow(l, 0.3), "4th in the window refused")
		t.ok(not RateLimit.allow(l, 0.9), "still inside the window")
		t.ok(RateLimit.allow(l, 1.05), "the first one left the window")
	end,

	["rate limit: refused events do not count"] = function(t)
		local l = RateLimit.new(1, 1)
		t.ok(RateLimit.allow(l, 0))
		for i = 1, 10 do
			t.ok(not RateLimit.allow(l, i * 0.05))
		end
		t.ok(RateLimit.allow(l, 1.0), "spam did not extend the block")
	end,
}
