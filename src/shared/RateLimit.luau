--!strict
-- A sliding-window rate limit: at most `max` events per `window` seconds. Pure (time passed in), so it is tested
-- in Lune. Used by the server to check RemoteEvents (CLAUDE.md: validate every RemoteEvent argument and rate).
local RateLimit = {}

export type Limit = { max: number, window: number, times: { number } }

function RateLimit.new(max: number, window: number): Limit
	return { max = max, window = window, times = {} }
end

-- Records an event at `now` if allowed; returns whether it was.
function RateLimit.allow(l: Limit, now: number): boolean
	local kept = {}
	for _, t in l.times do
		if now - t < l.window then
			table.insert(kept, t)
		end
	end
	l.times = kept
	if #kept >= l.max then
		return false
	end
	table.insert(kept, now)
	return true
end

return RateLimit
