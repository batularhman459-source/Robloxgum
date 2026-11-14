local MapGraph = require("../src/shared/map/MapGraph")
local MapMath = require("../src/shared/map/MapMath")
local Movement = require("../src/shared/Movement")

local CELL = 2

-- Builds surfaces from a list of rectangles {x0, z0, x1, z1, y} in cells.
local function world(rects)
	local s = {}
	for _, r in rects do
		for ix = r[1], r[3] do
			for iz = r[2], r[4] do
				table.insert(
					s,
					{ ix = ix, iz = iz, x = ix * CELL, z = iz * CELL, y = r[5], headroom = 100, partName = r[6] }
				)
			end
		end
	end
	return s
end

local OPEN = {
	blocked = function()
		return false
	end,
	arcClear = function()
		return true
	end,
}

local function find(surfaces, ix, iz, y)
	for i, s in surfaces do
		if s.ix == ix and s.iz == iz and s.y == y then
			return i
		end
	end
	error("no surface at " .. ix .. "," .. iz)
end

local function build(t, rects, probe)
	local m = t.rules("movement")
	local s = world(rects)
	return s, MapGraph.build(s, Movement, m, CELL, probe or OPEN), m
end

return {
	["walking: flat floor is fully reachable and you can get back"] = function(t)
		local s, g, m = build(t, { { 0, 0, 9, 9, 0 } })
		local a = MapGraph.analyze(g, { find(s, 0, 0, 0) })
		t.eq(#a.traps, 0, "no traps")
		t.eq(#a.unreachable, 0, "nothing unreachable")
		local time = MapGraph.route(g, { find(s, 0, 0, 0) }, { [find(s, 9, 0, 0)] = true })
		local expected = 18 / m.walkSpeed
		t.ok(
			math.abs(time - expected) < 0.01,
			string.format("18 studs at %d studs/s = %.2f s, got %s", m.walkSpeed, expected, tostring(time))
		)
	end,

	["unreachable: a ledge 10 studs up can't be reached"] = function(t)
		local s, g = build(t, { { 0, 0, 9, 9, 0 }, { 12, 0, 14, 2, 10 } })
		local a = MapGraph.analyze(g, { find(s, 0, 0, 0) })
		t.eq(#a.unreachable, 1, "one unreachable area")
		t.eq(#a.unreachable[1], 9, "the 3x3 ledge")
	end,

	["trap: a pit you can fall into but never leave"] = function(t)
		-- floor with a 3x3 hole, pit floor 12 studs below
		local s, g = build(t, {
			{ 0, 0, 9, 2, 0 },
			{ 0, 6, 9, 9, 0 },
			{ 0, 3, 2, 5, 0 },
			{ 6, 3, 9, 5, 0 },
			{ 3, 3, 5, 5, -12 },
		})
		local a = MapGraph.analyze(g, { find(s, 0, 0, 0) })
		t.eq(#a.traps, 1, "one trap")
		t.eq(#a.traps[1], 9, "the whole pit floor")
	end,

	["jumps: a 6 stud gap is jumpable, a 12 stud gap is not"] = function(t)
		local s, g = build(t, { { 0, 0, 4, 4, 0 }, { 8, 0, 12, 4, 0 }, { 19, 0, 22, 4, 0 } })
		local a = MapGraph.analyze(g, { find(s, 0, 0, 0) })
		t.ok(a.reachable[find(s, 8, 0, 0)], "6 stud gap (3 empty cells) should be jumpable")
		t.ok(not a.reachable[find(s, 19, 0, 0)], "12 stud gap should not be")
	end,

	["jumps: a 4 stud step up needs a jump and works, a wall blocks it"] = function(t)
		local rects = { { 0, 0, 4, 4, 0 }, { 5, 0, 8, 4, 4 } }
		local s, g = build(t, rects)
		t.ok(MapGraph.analyze(g, { find(s, 0, 0, 0) }).reachable[find(s, 6, 0, 4)], "4 studs up is a jump")
		local walled = {
			blocked = function()
				return true
			end,
			arcClear = function()
				return false
			end,
		}
		local s2, g2 = build(t, rects, walled)
		t.ok(not MapGraph.analyze(g2, { find(s2, 0, 0, 0) }).reachable[find(s2, 6, 0, 4)], "walls block it")
	end,

	["falls: edges record the drop height"] = function(t)
		local s, g, m = build(t, { { 0, 0, 2, 2, 40 }, { 3, 0, 6, 2, 0 } })
		local worst = 0
		for _, edges in g.out do
			for _, e in edges do
				if e.kind == "fall" then
					worst = math.max(worst, e.drop)
				end
			end
		end
		t.eq(worst, 40)
		t.eq(Movement.dropKind(m, worst), "unsafe")
	end,

	["void: walking off the map is recorded"] = function(t)
		local _, g = build(t, { { 0, 0, 2, 2, 0 } })
		t.ok(#g.voids > 0, "edges of a lone platform lead into the void")
	end,

	["floating: parts not connected to the ground"] = function(t)
		-- 1 = ground, 2 sits on 1, 3 sits on 2, 4 floats
		local touching = { { 2 }, { 1, 3 }, { 2 }, {} }
		local result = MapMath.unsupported(4, touching, { [1] = true })
		t.eq(#result, 1)
		t.eq(result[1], 4)
	end,

	["rings: even ring passes, a nudged one is measured"] = function(t)
		local pts = {}
		for i = 0, 7 do
			local a = i * math.pi / 4
			table.insert(pts, { x = math.cos(a) * 20, y = 5, z = math.sin(a) * 20 })
		end
		local even = MapMath.ring(pts)
		t.ok(even.isRing and even.radiusDev < 1e-6 and even.angleDevDeg < 1e-6, "perfect ring")
		pts[3] = { x = pts[3].x, y = 5.3, z = pts[3].z + 0.7 } -- point 3 sits at 90 deg: +z is outward
		local bad = MapMath.ring(pts)
		t.ok(bad.radiusDev > 0.3 and bad.heightDev > 0.2, "nudged ring is measured as uneven")
	end,

	["almost equal heights and almost straight angles are caught"] = function(t)
		t.eq(#MapMath.almostEqual({ 10, 10, 10.1, 14 }, 0.5, 0.01), 2, "10 vs 10.1 twice")
		t.ok(MapMath.offGrid(91.5, 15, 3, 0.1) ~= nil, "91.5 deg is almost 90")
		t.eq(MapMath.offGrid(90, 15, 3, 0.1), nil, "90 is fine")
		t.eq(MapMath.offGrid(37, 15, 3, 0.1), nil, "37 is deliberate, not almost")
	end,

	["overlap depth and volume"] = function(t)
		local a = { min = { x = 0, y = 0, z = 0 }, max = { x = 4, y = 4, z = 4 } }
		local b = { min = { x = 3, y = 0, z = 0 }, max = { x = 8, y = 4, z = 4 } }
		local depth, vol = MapMath.boxOverlap(a, b)
		t.eq(depth, 1)
		t.eq(vol, 16)
	end,
}
