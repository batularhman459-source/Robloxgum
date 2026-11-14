--!strict
-- Movement graph of a map. Pure: no requires, no Roblox APIs.
-- Input: walkable surfaces sampled on a grid (Studio does this with raycasts) and a probe table with
-- raycast callbacks. Output: a graph with walk, jump and fall edges built from Movement physics,
-- plus analysis (reachable, can-get-back, traps, unreachable areas, fastest routes).
-- The same code runs in Lune tests with fake surfaces and fake probes.

export type Surface = {
	x: number, -- cell centre, studs
	y: number, -- floor height
	z: number,
	ix: number, -- grid cell
	iz: number,
	headroom: number, -- free space above the floor
	partName: string?,
}

export type Edge = { to: number, kind: string, cost: number, drop: number? }

export type Probe = {
	blocked: (a: Surface, b: Surface) -> boolean, -- wall between a and b at body height
	arcClear: (a: Surface, b: Surface, apexY: number) -> boolean, -- jump arc has no ceiling/wall
	tick: (() -> ())?, -- called often, Studio uses it to yield
}

local MapGraph = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function key(ix: number, iz: number): string
	return ix .. "," .. iz
end

local function hdist(a: Surface, b: Surface): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- Builds the graph. M = Movement module, m = movement rules, cell = grid size in studs.
function MapGraph.build(surfaces: { Surface }, M: any, m: any, cell: number, probe: Probe): any
	local byCell: { [string]: { number } } = {}
	for i, s in surfaces do
		local k = key(s.ix, s.iz)
		byCell[k] = byCell[k] or {}
		table.insert(byCell[k], i)
	end

	local out: { { Edge } } = {}
	local inn: { { Edge } } = {}
	local voids: { { from: number, x: number, z: number } } = {}
	for i in surfaces do
		out[i], inn[i] = {}, {}
	end
	local function add(from: number, to: number, kind: string, cost: number, drop: number?)
		table.insert(out[from], { to = to, kind = kind, cost = cost, drop = drop })
		table.insert(inn[to], { to = from, kind = kind, cost = cost, drop = drop })
	end
	local function tick()
		if probe.tick then
			probe.tick()
		end
	end

	local standable = function(s: Surface): boolean
		return s.headroom >= m.characterHeight
	end

	-- Walk and fall edges to the 8 neighbours.
	local edgeOf: { [number]: boolean } = {}
	for i, s in surfaces do
		tick()
		if not standable(s) then
			continue
		end
		for d, dir in DIRS do
			local list = byCell[key(s.ix + dir[1], s.iz + dir[2])]
			local walkTo, fallTo = nil, nil
			for _, j in list or {} do
				local t = surfaces[j]
				local dy = t.y - s.y
				if math.abs(dy) <= m.stepHeight and standable(t) then
					if not walkTo or math.abs(dy) < math.abs(surfaces[walkTo].y - s.y) then
						walkTo = j
					end
				elseif dy < -m.stepHeight and standable(t) and (not fallTo or t.y > surfaces[fallTo].y) then
					fallTo = j
				end
			end
			if walkTo and not probe.blocked(s, surfaces[walkTo]) then
				add(i, walkTo, "walk", M.walkTime(m, hdist(s, surfaces[walkTo])))
			elseif d <= 4 then
				edgeOf[i] = true
				-- Off the edge: fall onto the highest floor below, or into the void.
				local over = { x = s.x + dir[1] * cell, y = s.y, z = s.z + dir[2] * cell, ix = 0, iz = 0, headroom = 0 }
				if not probe.blocked(s, over :: any) then
					if fallTo then
						local drop = s.y - surfaces[fallTo].y
						add(i, fallTo, "fall", M.walkTime(m, cell / 2) + M.fallTime(m, drop), drop)
					elseif not walkTo then
						table.insert(voids, { from = i, x = over.x, z = over.z })
					end
				end
			end
		end
	end

	-- Jump edges, only from surfaces at an edge. Gap = centre distance minus one cell (GUESS: the
	-- player can stand anywhere in a cell, so they take off from its far side).
	local maxReach = M.jumpReach(m, -m.maxSafeFall) + cell
	local r = math.ceil(maxReach / cell)
	for i, s in surfaces do
		if not edgeOf[i] then
			continue
		end
		local walkNeighbours = {}
		for _, e in out[i] do
			walkNeighbours[e.to] = true
		end
		for dx = -r, r do
			for dz = -r, r do
				if math.abs(dx) <= 1 and math.abs(dz) <= 1 then
					continue
				end
				for _, j in byCell[key(s.ix + dx, s.iz + dz)] or {} do
					tick()
					local t = surfaces[j]
					if walkNeighbours[j] or not standable(t) then
						continue
					end
					local dh = t.y - s.y
					local gap = hdist(s, t) - cell
					if dh <= m.jumpHeight * m.jumpMargin and gap <= M.jumpReach(m, dh) then
						if probe.arcClear(s, t, s.y + m.jumpHeight) then
							-- In the air you still only move at walk speed: never faster than walking.
							local cost = math.max(M.jumpAirTime(m, dh) :: number, M.walkTime(m, hdist(s, t)))
							add(i, j, "jump", cost, if dh < 0 then -dh else nil)
						end
					end
				end
			end
		end
	end

	return { nodes = surfaces, out = out, inn = inn, voids = voids }
end

-- Every node reachable from `starts` (or that can reach them when reverse = true).
function MapGraph.reach(g: any, starts: { number }, reverse: boolean?): { [number]: boolean }
	local adj = if reverse then g.inn else g.out
	local seen: { [number]: boolean } = {}
	local stack = table.clone(starts)
	for _, s in starts do
		seen[s] = true
	end
	while #stack > 0 do
		local n = table.remove(stack) :: number
		for _, e in adj[n] do
			if not seen[e.to] then
				seen[e.to] = true
				table.insert(stack, e.to)
			end
		end
	end
	return seen
end

-- Splits a set of nodes into areas connected by walking (in either direction).
function MapGraph.clusters(g: any, set: { [number]: boolean }): { { number } }
	local seen: { [number]: boolean } = {}
	local result = {}
	for n in set do
		if seen[n] then
			continue
		end
		local area, stack = {}, { n }
		seen[n] = true
		while #stack > 0 do
			local c = table.remove(stack) :: number
			table.insert(area, c)
			for _, list in { g.out[c], g.inn[c] } do
				for _, e in list do
					if e.kind == "walk" and set[e.to] and not seen[e.to] then
						seen[e.to] = true
						table.insert(stack, e.to)
					end
				end
			end
		end
		table.sort(area)
		table.insert(result, area)
	end
	table.sort(result, function(a, b)
		return #a > #b
	end)
	return result
end

-- Fastest route from any of `from` to any of `to`. Returns seconds and the node path, or nil.
function MapGraph.route(g: any, from: { number }, to: { [number]: boolean }): (number?, { number }?, { string }?)
	local dist: { [number]: number } = {}
	local prev: { [number]: number } = {}
	local via: { [number]: string } = {}
	local open: { number } = {}
	for _, s in from do
		dist[s] = 0
		table.insert(open, s)
	end
	while #open > 0 do
		local bi = 1
		for i = 2, #open do
			if dist[open[i]] < dist[open[bi]] then
				bi = i
			end
		end
		local n = table.remove(open, bi) :: number
		if to[n] then
			local path, kinds = { n }, {}
			while prev[path[1]] do
				table.insert(kinds, 1, via[path[1]])
				table.insert(path, 1, prev[path[1]])
			end
			return dist[n], path, kinds
		end
		for _, e in g.out[n] do
			local d = dist[n] + e.cost
			if dist[e.to] == nil or d < dist[e.to] then
				if dist[e.to] == nil then
					table.insert(open, e.to)
				end
				dist[e.to], prev[e.to], via[e.to] = d, n, e.kind
			end
		end
	end
	return nil
end

-- The movement checks. starts = spawn nodes. Returns reachable set, can-return set, traps and
-- unreachable areas (each a list of node clusters, biggest first).
function MapGraph.analyze(g: any, starts: { number }): any
	local reachable = MapGraph.reach(g, starts)
	local canReturn = MapGraph.reach(g, starts, true)
	local trapped, unreachable = {}, {}
	for i, s in g.nodes do
		if reachable[i] and not canReturn[i] then
			trapped[i] = true
		elseif not reachable[i] and s.headroom >= 0 then
			unreachable[i] = true
		end
	end
	return {
		reachable = reachable,
		canReturn = canReturn,
		traps = MapGraph.clusters(g, trapped),
		unreachable = MapGraph.clusters(g, unreachable),
	}
end

return MapGraph
