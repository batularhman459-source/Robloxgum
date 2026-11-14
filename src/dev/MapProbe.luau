--!strict
-- MapProbe: measures a map in Studio with raycasts and runs the 9 map checks.
-- Run in Edit mode (execute_luau). Clone it, or Studio runs a cached old version:
--   return require(game:GetService("ReplicatedStorage").DevTools.MapProbe:Clone()).run({ root = workspace.MyMap })
-- Options: root (Model/Folder, required), cell (grid size, default = characterWidth), viz (true = draw
-- the result in Workspace.MapProbeViz, cleared with MapProbe.clearViz()).
--
-- Tags (CollectionService) on parts inside root:
--   MapSpawn       where players start (SpawnLocations count too)
--   MapWaypoint    named point (attribute Label) for A-to-B travel times and sight lines
--   MapNoAccess    volume players must never reach
--   MapGround      counts as ground for the floating check (Terrain and the lowest floor count anyway)
--   MapFloating    intentionally floating, skip it
--   MapUnreachable intentionally unreachable surface, skip it
--   MapRing        model whose parts must form an even ring
--   MapMerge       model whose parts may overlap
-- Waypoint attributes for sight lines: SightTo = "<other label>", Sight = "open" | "closed".
--
-- Every number in the report carries its source: [config], [studio], [raycast], [derived], [GUESS].
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

-- Studio caches require() in edit mode, so Rojo edits wouldn't show up. Require fresh copies.
local function fresh(module: Instance): any
	return require(module:Clone() :: ModuleScript)
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Movement = fresh(Shared:WaitForChild("Movement"))
local MapGraph = fresh(Shared:WaitForChild("map"):WaitForChild("MapGraph"))
local MapMath = fresh(Shared:WaitForChild("map"):WaitForChild("MapMath"))

local MapProbe = {}

local MAX_CELLS = 60000
local SURFACES_PER_CELL = 6

local GUESSES = {
	"Jump gaps are measured edge-to-edge as centre distance minus one grid cell (player can stand anywhere in a cell).",
	"Jump arcs are checked with 2 straight sphere casts (take-off to apex, apex to landing) at body-centre height, sphere 90 % of characterWidth, not a full curve.",
	"Unreachable spots that sit right next to reachable floor (within one cell, same height) are counted as tight spots, not unreachable places.",
	"Walls are checked with 2 horizontal rays (knee and head height) between cell centres; gaps thinner than one cell can be missed.",
	"Floating check counts parts as touching when their bounding boxes come within 0.05 studs (rotated parts are over-counted as touching).",
	"Overlap depth uses axis-aligned bounding boxes; for rotated parts it is an upper estimate.",
	"Sight lines use 5 rays to a character-sized target; partial cover counts as open when 3 or more rays get through.",
}

local function tagged(root: Instance, tag: string): { BasePart }
	local list = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(root) then
			table.insert(list, inst)
		end
	end
	return list
end

local function hasTagUp(inst: Instance, tag: string, root: Instance): boolean
	local p: Instance? = inst
	while p and p ~= root.Parent do
		if CollectionService:HasTag(p, tag) then
			return true
		end
		p = p.Parent
	end
	return false
end

local function insideVolume(part: BasePart, pos: Vector3): boolean
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

local function f1(n: number): string
	return string.format("%.1f", n)
end

local function f2(n: number): string
	return string.format("%.2f", n)
end

local function at(v: Vector3 | { x: number, y: number, z: number }): string
	local x = (v :: any).X or (v :: any).x
	local y = (v :: any).Y or (v :: any).y
	local z = (v :: any).Z or (v :: any).z
	return string.format("(%d, %d, %d)", math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5))
end

function MapProbe.run(opts: any): string
	local root: Instance = opts.root
	assert(root, "MapProbe.run needs opts.root")
	local m = table.clone(fresh(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("movement")))
	local src = m.source
	local lines: { string } = {}
	local fails, warns = 0, 0
	local function out(s: string)
		table.insert(lines, s)
	end
	local checks: { { name: string, ok: boolean, detail: { string } } } = {}
	local function check(name: string, items: { string }, isWarn: boolean?)
		local ok = #items == 0
		if not ok then
			if isWarn then
				warns += 1
			else
				fails += 1
			end
		end
		table.insert(checks, { name = name, ok = ok or isWarn == true, detail = items })
	end
	local extraGuesses: { string } = {}

	-- 1. Movement numbers: config, compared with the live Studio settings.
	out("## Movement numbers")
	local live = {
		walkSpeed = StarterPlayer.CharacterWalkSpeed,
		jumpHeight = StarterPlayer.CharacterJumpHeight,
		gravity = Workspace.Gravity,
		maxSlopeAngle = StarterPlayer.CharacterMaxSlopeAngle,
	}
	for _, k in
		{
			"walkSpeed",
			"jumpHeight",
			"gravity",
			"maxSlopeAngle",
			"stepHeight",
			"characterHeight",
			"characterWidth",
			"eyeHeight",
			"maxSafeFall",
		}
	do
		local line = string.format("- %s = %s [config: rules/movement.toml, %s]", k, tostring(m[k]), src[k])
		if live[k] and math.abs(live[k] - m[k]) > 1e-3 then
			line ..= string.format("  MISMATCH: Studio has %s [studio]", tostring(live[k]))
		end
		out(line)
		if string.find(src[k] or "", "GUESS", 1, true) then
			table.insert(extraGuesses, k .. " = " .. tostring(m[k]) .. ": " .. src[k])
		end
	end
	if StarterPlayer.CharacterUseJumpPower then
		out("- MISMATCH: StarterPlayer uses JumpPower, config assumes JumpHeight [studio]")
	end
	out(string.format("- jump take-off speed %s studs/s [derived: sqrt(2 g jumpHeight)]", f1(Movement.jumpVelocity(m))))
	out(
		string.format(
			"- flat jump: %s s in the air, %s studs far, counted as %s with the %d %% margin [derived]",
			f2(Movement.jumpAirTime(m, 0) :: number),
			f1(m.walkSpeed * (Movement.jumpAirTime(m, 0) :: number)),
			f1(Movement.jumpReach(m, 0)),
			m.jumpMargin * 100
		)
	)

	-- 2. Parts and bounds.
	local parts: { BasePart } = {}
	local solid: { BasePart } = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
			if inst.CanCollide and inst.Transparency < 1 then
				table.insert(solid, inst)
			end
		end
	end
	assert(#solid > 0, "no solid parts under " .. root:GetFullName())
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in solid do
		local cf, size = p.CFrame, p.Size
		local half = (cf.RightVector * size.X / 2):Abs()
			+ (cf.UpVector * size.Y / 2):Abs()
			+ (cf.LookVector * size.Z / 2):Abs()
		minV, maxV = minV:Min(p.Position - half), maxV:Max(p.Position + half)
	end
	local cell = opts.cell or m.characterWidth
	while ((maxV.X - minV.X) / cell) * ((maxV.Z - minV.Z) / cell) > MAX_CELLS do
		cell *= 1.5
	end
	if cell ~= (opts.cell or m.characterWidth) then
		table.insert(
			extraGuesses,
			string.format(
				"Map is big: grid cell raised to %s studs, details smaller than that can be missed.",
				f1(cell)
			)
		)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { root, Workspace.Terrain }
	params.RespectCanCollide = true

	local calls = 0
	local function tick()
		calls += 1
		if calls % 300 == 0 then
			task.wait()
		end
	end

	-- 3. Sample walkable surfaces: rays straight down through every cell, several floors per cell.
	local minNormalY = Movement.minWalkNormalY(m)
	local surfaces = {}

	-- Standing space test with real part shapes (GetPartsInPart). Rays can't see a part from the
	-- inside, so without this a floor running under a wall or ramp would count as standable.
	local body = Instance.new("Part")
	body.Name = "MapProbeBody"
	body.Archivable = false
	body.Anchored, body.CanCollide, body.CanTouch, body.CanQuery = true, false, false, false
	body.Transparency = 1
	body.Size = Vector3.new(m.characterWidth * 0.6, m.characterHeight - 0.4, m.characterWidth * 0.6)
	body.Parent = Workspace
	local solidParams = OverlapParams.new()
	solidParams.FilterType = Enum.RaycastFilterType.Include
	solidParams.FilterDescendantsInstances = { root, Workspace.Terrain }
	solidParams.RespectCanCollide = true
	local function bodyFits(floor: Vector3, normal: Vector3): boolean
		-- On a slope the box corners would dip into the floor: lift it by half-width * slope.
		local slope = math.sqrt(math.max(0, 1 - normal.Y ^ 2)) / math.max(normal.Y, 0.05)
		local lift = 0.3 + (body.Size.X / 2) * math.sqrt(2) * slope
		body.CFrame = CFrame.new(floor + Vector3.new(0, lift + body.Size.Y / 2, 0))
		return #Workspace:GetPartsInPart(body, solidParams) == 0
	end
	local ix0, iz0 = math.floor(minV.X / cell), math.floor(minV.Z / cell)
	local ix1, iz1 = math.ceil(maxV.X / cell), math.ceil(maxV.Z / cell)
	local topY = maxV.Y + 5
	local depth = topY - minV.Y + 10
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
			local origin = Vector3.new(x, topY, z)
			for _ = 1, SURFACES_PER_CELL do
				tick()
				local hit = Workspace:Raycast(origin, Vector3.new(0, -(origin.Y - minV.Y + 10), 0), params)
				if not hit then
					break
				end
				if hit.Normal.Y >= minNormalY then
					-- Headroom from a ray up; 0 when a body doesn't fit (part shapes, see bodyFits).
					local up = Workspace:Raycast(hit.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, 50, 0), params)
					local headroom = if up then up.Distance else 50
					if not bodyFits(hit.Position, hit.Normal) then
						headroom = 0
					end
					table.insert(surfaces, {
						ix = ix,
						iz = iz,
						x = x,
						y = hit.Position.Y,
						z = z,
						headroom = headroom,
						partName = hit.Instance:GetFullName(),
						part = hit.Instance,
					})
				end
				origin = hit.Position - Vector3.new(0, 0.05, 0)
				if origin.Y < topY - depth then
					break
				end
			end
		end
	end

	body:Destroy()

	-- 4. Movement graph from the surfaces, with raycast probes.
	local knee, head = m.stepHeight + 0.25, m.characterHeight - 0.5
	local probe = {
		tick = tick,
		blocked = function(a: any, b: any): boolean
			for _, h in { knee, head } do
				local from = Vector3.new(a.x, a.y + h, a.z)
				local dir = Vector3.new(b.x - a.x, 0, b.z - a.z)
				local hit = Workspace:Raycast(from, dir, params)
				if hit and hit.Normal.Y < minNormalY then
					return true
				end
			end
			return false
		end,
		arcClear = function(a: any, b: any, apexY: number): boolean
			local mid = Vector3.new((a.x + b.x) / 2, apexY + m.characterHeight / 2, (a.z + b.z) / 2)
			local p0 = Vector3.new(a.x, a.y + m.characterHeight / 2, a.z)
			local p1 = Vector3.new(b.x, b.y + m.characterHeight / 2, b.z)
			-- A sphere as wide as the character, so it can't slip through gaps a body can't.
			local r = m.characterWidth / 2 * 0.9
			return not Workspace:Spherecast(p0, r, mid - p0, params)
				and not Workspace:Spherecast(mid, r, p1 - mid, params)
		end,
	}
	local g = MapGraph.build(surfaces, Movement, m, cell, probe)

	-- Start points: the floor under each spawn.
	local spawns: { BasePart } = tagged(root, "MapSpawn")
	for _, inst in root:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			table.insert(spawns, inst)
		end
	end
	local function nodeUnder(pos: Vector3): number?
		local best, bestD = nil, math.huge
		for i, s in surfaces do
			local dxz = math.sqrt((s.x - pos.X) ^ 2 + (s.z - pos.Z) ^ 2)
			if dxz <= cell and s.y <= pos.Y + 1 and pos.Y - s.y < bestD then
				best, bestD = i, pos.Y - s.y
			end
		end
		return best
	end
	local starts = {}
	for _, sp in spawns do
		local n = nodeUnder(sp.Position + Vector3.new(0, sp.Size.Y / 2, 0))
		if n then
			table.insert(starts, n)
		end
	end
	local result = MapGraph.analyze(g, starts)

	local reachableCount = 0
	for _ in result.reachable do
		reachableCount += 1
	end
	local area = cell * cell

	out("")
	out("## Measured")
	out(
		string.format(
			"- grid %s studs, %d walkable surface samples, %d reachable from %d spawn(s) [raycast]",
			f1(cell),
			#surfaces,
			reachableCount,
			#starts
		)
	)
	if #starts == 0 then
		out("- NO SPAWN found under the root: tag a part MapSpawn or add a SpawnLocation. Reach checks skipped.")
	end

	-- Travel times between waypoints.
	local waypoints = tagged(root, "MapWaypoint")
	local wpNode: { [string]: number } = {}
	for _, wp in waypoints do
		local n = nodeUnder(wp.Position + Vector3.new(0, wp.Size.Y / 2, 0))
		if n then
			wpNode[wp:GetAttribute("Label") or wp.Name] = n
		end
	end
	if #waypoints > 0 then
		out("- travel times, fastest route, A -> B / B -> A [derived: route over measured graph]:")
		local labels = {}
		for label in wpNode do
			table.insert(labels, label)
		end
		table.sort(labels)
		for i = 1, #labels do
			for j = i + 1, #labels do
				local a, b = wpNode[labels[i]], wpNode[labels[j]]
				local t1, _, k1 = MapGraph.route(g, { a }, { [b] = true })
				local t2 = MapGraph.route(g, { b }, { [a] = true })
				local how = ""
				if k1 then
					local counts = {}
					for _, k in k1 do
						counts[k] = (counts[k] or 0) + 1
					end
					how = string.format(" (%d jumps, %d falls)", counts.jump or 0, counts.fall or 0)
				end
				out(
					string.format(
						"  - %s -> %s: %s / %s%s",
						labels[i],
						labels[j],
						if t1 then f1(t1) .. " s" else "NO ROUTE",
						if t2 then f1(t2) .. " s" else "NO ROUTE",
						how
					)
				)
			end
		end
	end

	-- Openness from each spawn: can you see across it?
	for si, sp in spawns do
		local eye = sp.Position + Vector3.new(0, sp.Size.Y / 2 + m.eyeHeight, 0)
		local dists, open = {}, 0
		for a = 0, 71 do
			local dir = Vector3.new(math.cos(math.rad(a * 5)), 0, math.sin(math.rad(a * 5)))
			local hit = Workspace:Raycast(eye, dir * 512, params)
			table.insert(dists, if hit then hit.Distance else 512)
			if not hit then
				open += 1
			end
		end
		table.sort(dists)
		out(
			string.format(
				"- view from spawn %d: median sight distance %s studs, %d %% of directions open past 512 studs [raycast, 72 rays at eye height]",
				si,
				f1(dists[36]),
				math.floor(open / 72 * 100 + 0.5)
			)
		)
	end

	local function where(cluster: { number }): string
		local sx, sy, sz = 0, 0, 0
		for _, n in cluster do
			local s = surfaces[n]
			sx += s.x
			sy += s.y
			sz += s.z
		end
		local k = #cluster
		return string.format(
			"%s, %s studs^2, on %s",
			at({ x = sx / k, y = sy / k, z = sz / k }),
			f1(k * area),
			surfaces[cluster[1]].partName
		)
	end

	-- CHECK: unreachable places.
	local unreach = {}
	local cellIndex: { [string]: { number } } = {}
	for i, s in surfaces do
		local k = s.ix .. "," .. s.iz
		cellIndex[k] = cellIndex[k] or {}
		table.insert(cellIndex[k], i)
	end
	-- A spot is "tight" when reachable floor at the same height is right next to it: the player is
	-- already there, the grid just can't fit a body in that exact cell.
	local function tight(n: number): boolean
		local s = surfaces[n]
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, j in cellIndex[(s.ix + dx) .. "," .. (s.iz + dz)] or {} do
					if result.reachable[j] and math.abs(surfaces[j].y - s.y) <= m.stepHeight then
						return true
					end
				end
			end
		end
		return false
	end
	local tightCount = 0
	for _, c in result.unreachable do
		local intentional = hasTagUp(surfaces[c[1]].part, "MapUnreachable", root)
		local allTight = true
		for _, n in c do
			if not tight(n) then
				allTight = false
				break
			end
		end
		if allTight then
			tightCount += #c
		elseif #c >= 2 and not intentional then
			table.insert(unreach, "unreachable area at " .. where(c) .. " [raycast + derived]")
		end
	end
	out(
		string.format(
			"- %d tight spots next to reachable floor (too narrow for a body in that cell) [raycast]",
			tightCount
		)
	)
	if #starts > 0 then
		check("Unreachable places", unreach)
	end

	-- CHECK: places players shouldn't reach.
	local noAccess = {}
	for _, vol in tagged(root, "MapNoAccess") do
		local inside: { [number]: boolean } = {}
		local any = false
		for i in result.reachable do
			local s = surfaces[i]
			if insideVolume(vol, Vector3.new(s.x, s.y + 1, s.z)) then
				inside[i] = true
				any = true
			end
		end
		if any then
			local t, _, kinds = MapGraph.route(g, starts, inside)
			table.insert(
				noAccess,
				string.format(
					"%s is reachable: %s s from spawn via %s [derived]",
					vol:GetFullName(),
					if t then f1(t) else "?",
					if kinds then table.concat(kinds, ">") else "?"
				)
			)
		end
	end
	check("Places players shouldn't reach", noAccess)

	-- CHECK: no way out (traps).
	local traps = {}
	for _, c in result.traps do
		table.insert(traps, "no way back from " .. where(c) .. " [derived]")
	end
	if #starts > 0 then
		check("No way out after a fall", traps)
	end

	-- CHECK: falls the movement system can't handle, and awkward drops.
	-- Group falls by where they start (part) and how high they are, so one ledge is one finding.
	local unsafe, awkward = {}, {}
	local worstFall = 0
	local groupsByKey: { [string]: any } = {}
	local order: { string } = {}
	for i in result.reachable do
		for _, e in g.out[i] do
			if e.drop and e.drop > m.stepHeight then
				worstFall = math.max(worstFall, e.drop)
				local kind = Movement.dropKind(m, e.drop)
				if kind == "unsafe" or kind == "awkward" then
					local s = surfaces[i]
					local k = kind .. "|" .. s.partName -- one finding per ledge part, worst drop shown
					local grp = groupsByKey[k]
					if not grp then
						grp = {
							kind = kind,
							part = s.partName,
							drop = e.drop,
							cells = 0,
							at = s,
							how = e.kind,
							seen = {},
						}
						groupsByKey[k] = grp
						table.insert(order, k)
					end
					if not grp.seen[i] then
						grp.seen[i] = true
						grp.cells += 1
					end
					if e.drop > grp.drop then
						grp.drop, grp.at = e.drop, s
					end
				end
			end
		end
	end
	table.sort(order)
	for _, k in order do
		local grp = groupsByKey[k]
		if grp.kind == "unsafe" then
			table.insert(
				unsafe,
				string.format(
					"up to %s stud fall off %s (%d edge cells, worst at %s), lands at %s studs/s [raycast + derived: sqrt(2 g h)], limit %s [config]",
					f1(grp.drop),
					grp.part,
					grp.cells,
					at(grp.at),
					f1(Movement.landingSpeed(m, grp.drop)),
					tostring(m.maxSafeFall)
				)
			)
		else
			table.insert(
				awkward,
				string.format(
					"up to %s stud drop off %s (%d edge cells, worst at %s), between stepHeight %s and minCleanDrop %s [config]",
					f1(grp.drop),
					grp.part,
					grp.cells,
					at(grp.at),
					tostring(m.stepHeight),
					tostring(m.minCleanDrop)
				)
			)
		end
	end
	out(
		string.format(
			"- longest reachable fall %s studs, %s s [raycast + derived]",
			f1(worstFall),
			f2(Movement.fallTime(m, worstFall))
		)
	)
	local voidCount = 0
	for _, v in g.voids do
		if result.reachable[v.from] then
			voidCount += 1
		end
	end
	out(string.format("- %d edge cells where a player can walk off into the void [raycast]", voidCount))
	check("Falls longer than the movement system handles", unsafe)
	check("Awkward short drops (warning)", awkward, true)

	-- CHECK: sight lines.
	local sightItems = {}
	local byLabel: { [string]: BasePart } = {}
	for _, wp in waypoints do
		byLabel[wp:GetAttribute("Label") or wp.Name] = wp
	end
	for _, wp in waypoints do
		local toLabel = wp:GetAttribute("SightTo")
		local target = toLabel and byLabel[toLabel]
		if target then
			local eye = wp.Position + Vector3.new(0, wp.Size.Y / 2 + m.eyeHeight, 0)
			local base = target.Position + Vector3.new(0, target.Size.Y / 2, 0)
			local through = 0
			for _, o in
				{
					Vector3.new(0, 2.5, 0),
					Vector3.new(1, 2.5, 0),
					Vector3.new(-1, 2.5, 0),
					Vector3.new(0, 4.5, 0),
					Vector3.new(0, 0.5, 0),
				}
			do
				local to = base + o
				if not Workspace:Raycast(eye, to - eye, params) then
					through += 1
				end
			end
			local isOpen = through >= 3
			local expect = wp:GetAttribute("Sight")
			local label = string.format(
				"%s -> %s: %s (%d/5 rays clear) [raycast]",
				wp:GetAttribute("Label") or wp.Name,
				toLabel,
				if isOpen then "open" else "closed",
				through
			)
			out("- sight line " .. label)
			if expect and ((expect == "open") ~= isOpen) then
				table.insert(sightItems, label .. ", expected " .. tostring(expect))
			end
		end
	end
	check("Sight lines as designed", sightItems)

	-- Geometry checks over all parts.
	local index: { [BasePart]: number } = {}
	for i, p in parts do
		index[p] = i
	end
	local function aabb(p: BasePart): any
		local cf, size = p.CFrame, p.Size
		local half = (cf.RightVector * size.X / 2):Abs()
			+ (cf.UpVector * size.Y / 2):Abs()
			+ (cf.LookVector * size.Z / 2):Abs()
		local lo, hi = p.Position - half, p.Position + half
		return { min = { x = lo.X, y = lo.Y, z = lo.Z }, max = { x = hi.X, y = hi.Y, z = hi.Z } }
	end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { root }

	-- CHECK: floating platforms and floating things (not connected to the ground).
	local touching: { { number } } = {}
	local roots: { [number]: boolean } = {}
	local lowest = minV.Y
	for i, p in parts do
		tick()
		touching[i] = {}
		for _, q in Workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.new(0.1, 0.1, 0.1), overlapParams) do
			local j = index[q :: BasePart]
			if j and j ~= i then
				table.insert(touching[i], j)
			end
		end
		local box = aabb(p)
		local bottom = Vector3.new(p.Position.X, box.min.y, p.Position.Z)
		local terrainHit = Workspace:Raycast(bottom + Vector3.new(0, 0.1, 0), Vector3.new(0, -0.3, 0), params)
		if
			CollectionService:HasTag(p, "MapGround")
			or p.Name == "Baseplate"
			or box.min.y <= lowest + 0.05
			or (terrainHit and terrainHit.Instance == Workspace.Terrain)
		then
			roots[i] = true
		end
	end
	local floatingPlatforms, floatingThings = {}, {}
	for _, i in MapMath.unsupported(#parts, touching, roots) do
		local p = parts[i]
		if
			not hasTagUp(p, "MapFloating", root)
			and not CollectionService:HasTag(p, "MapNoAccess")
			and not CollectionService:HasTag(p, "MapSpawn")
			and not CollectionService:HasTag(p, "MapWaypoint")
		then
			local walkable = p.CanCollide and p.CFrame.UpVector:Abs().Y > 0.7
			table.insert(
				if walkable then floatingPlatforms else floatingThings,
				string.format(
					"%s at %s touches nothing that reaches the ground [overlap query]",
					p:GetFullName(),
					at(p.Position)
				)
			)
		end
	end
	check("Floating platforms", floatingPlatforms)

	-- CHECK: things hovering just above what's under them (roofs, props, tops).
	local hovering = {}
	for _, p in parts do
		tick()
		if
			CollectionService:HasTag(p, "MapNoAccess")
			or CollectionService:HasTag(p, "MapSpawn")
			or CollectionService:HasTag(p, "MapWaypoint")
		then
			continue
		end
		local box = aabb(p)
		local gaps = {}
		for _, c in { { 0, 0 }, { -0.4, -0.4 }, { 0.4, -0.4 }, { -0.4, 0.4 }, { 0.4, 0.4 } } do
			local o = Vector3.new(
				p.Position.X + c[1] * (box.max.x - box.min.x),
				box.min.y - 0.01,
				p.Position.Z + c[2] * (box.max.z - box.min.z)
			)
			local hp = RaycastParams.new()
			hp.FilterType = Enum.RaycastFilterType.Include
			hp.FilterDescendantsInstances = { root, Workspace.Terrain }
			local hit = Workspace:Raycast(o, Vector3.new(0, -1, 0), hp)
			if hit and hit.Instance ~= p then
				table.insert(gaps, hit.Distance + 0.01)
			end
		end
		table.sort(gaps)
		if #gaps > 0 and gaps[1] > 0.03 then
			table.insert(
				hovering,
				string.format(
					"%s hovers %s studs above what's below it at %s [raycast]",
					p:GetFullName(),
					f2(gaps[1]),
					at(p.Position)
				)
			)
		end
	end
	for _, s in floatingThings do
		table.insert(hovering, s)
	end
	check("Floating tops and hovering parts", hovering)

	-- CHECK: overlaps (parts inside parts).
	local overlaps = {}
	local seenPair: { [string]: boolean } = {}
	for i, p in parts do
		tick()
		if hasTagUp(p, "MapMerge", root) or not p.CanCollide then
			continue
		end
		for _, q in Workspace:GetPartsInPart(p, overlapParams) do
			local j = index[q :: BasePart]
			if j and j ~= i and (q :: BasePart).CanCollide and not hasTagUp(q, "MapMerge", root) then
				local k = math.min(i, j) .. ":" .. math.max(i, j)
				if not seenPair[k] then
					seenPair[k] = true
					local d, vol = MapMath.boxOverlap(aabb(p), aabb(q :: BasePart))
					if d > 0.05 then
						table.insert(
							overlaps,
							string.format(
								"%s and %s overlap %s studs deep, %s studs^3 [overlap query + GUESS bbox]",
								p:GetFullName(),
								q:GetFullName(),
								f2(d),
								f1(vol)
							)
						)
					end
				end
			end
		end
	end
	check("Overlaps (parts inside parts)", overlaps)

	-- CHECK: uneven rings, circles and platforms.
	local uneven = {}
	local groups: { [Instance]: { BasePart } } = {}
	for _, p in parts do
		local parent = p.Parent :: Instance
		groups[parent] = groups[parent] or {}
		table.insert(groups[parent], p)
	end
	for parent, list in groups do
		local bySize: { [string]: { BasePart } } = {}
		for _, p in list do
			local k = string.format("%.2f,%.2f,%.2f", p.Size.X, p.Size.Y, p.Size.Z)
			bySize[k] = bySize[k] or {}
			table.insert(bySize[k], p)
		end
		for _, same in bySize do
			if #same < 3 then
				continue
			end
			local pts, tops = {}, {}
			for _, p in same do
				table.insert(pts, { x = p.Position.X, y = p.Position.Y, z = p.Position.Z })
				table.insert(tops, aabb(p).max.y)
			end
			local ring = MapMath.ring(pts)
			local forced = CollectionService:HasTag(parent, "MapRing")
			if (forced or ring.isRing) and #same >= 4 then
				if ring.radiusDev > 0.05 or ring.angleDevDeg > 0.5 or ring.heightDev > 0.05 then
					table.insert(
						uneven,
						string.format(
							"ring %s (%d parts): radius off by up to %s studs, spacing off by %s deg, height off by %s studs [measured positions]",
							parent:GetFullName(),
							#same,
							f2(ring.radiusDev),
							f2(ring.angleDevDeg),
							f2(ring.heightDev)
						)
					)
				end
			else
				for _, pair in MapMath.almostEqual(tops, 0.5, 0.02) do
					table.insert(
						uneven,
						string.format(
							"%s and %s: tops almost level but %s studs apart [measured positions]",
							same[pair[1]]:GetFullName(),
							same[pair[2]]:GetFullName(),
							f2(pair[3])
						)
					)
					if #uneven > 20 then
						break
					end
				end
			end
		end
	end
	for _, p in parts do
		local _, ry = p.CFrame:ToOrientation()
		local off = MapMath.offGrid(math.deg(ry), 15, 2, 0.05)
		if off then
			table.insert(
				uneven,
				string.format("%s is rotated %s deg off a clean angle [measured rotation]", p:GetFullName(), f2(off))
			)
		end
	end
	check("Uneven rings, circles and platforms", uneven)

	-- Report.
	local report = {
		string.format("# Map report: %s", root:GetFullName()),
		string.format(
			"Result: %s (%d failed, %d warnings, 9 checks)",
			if fails == 0 then "PASS" else "FAIL",
			fails,
			warns
		),
		"",
		"## Checks",
	}
	for _, c in checks do
		table.insert(
			report,
			string.format(
				"- [%s] %s%s",
				if #c.detail == 0 then "PASS" else (if c.ok then "WARN" else "FAIL"),
				c.name,
				if #c.detail > 0 then " (" .. #c.detail .. ")" else ""
			)
		)
		for k, d in c.detail do
			if k > 10 then
				table.insert(report, string.format("  - ... %d more", #c.detail - 10))
				break
			end
			table.insert(report, "  - " .. d)
		end
	end
	table.insert(report, "")
	for _, l in lines do
		table.insert(report, l)
	end
	table.insert(report, "")
	table.insert(report, "## Guesses (assumptions the numbers rely on)")
	for _, gs in GUESSES do
		table.insert(report, "- " .. gs)
	end
	for _, gs in extraGuesses do
		table.insert(report, "- " .. gs)
	end

	MapProbe.last = { graph = g, result = result, surfaces = surfaces, cell = cell, root = root }
	if opts.viz then
		MapProbe.viz()
	end
	return table.concat(report, "\n")
end

-- Draws the last result: green = reachable, red = reachable but no way back, grey = unreachable.
function MapProbe.viz()
	MapProbe.clearViz()
	local last = MapProbe.last
	assert(last, "run MapProbe.run first")
	local folder = Instance.new("Folder")
	folder.Name = "MapProbeViz"
	folder.Archivable = false
	local colors = { Color3.fromRGB(60, 220, 100), Color3.fromRGB(240, 60, 60), Color3.fromRGB(140, 140, 150) }
	local rows: { [string]: { any } } = {}
	for i, s in last.surfaces do
		local status = if last.result.reachable[i] then (if last.result.canReturn[i] then 1 else 2) else 3
		local k = s.iz .. ":" .. math.floor(s.y * 10) .. ":" .. status
		rows[k] = rows[k] or {}
		table.insert(rows[k], { s = s, status = status })
	end
	for _, row in rows do
		table.sort(row, function(a, b)
			return a.s.ix < b.s.ix
		end)
		local runStart = 1
		for i = 2, #row + 1 do
			if i > #row or row[i].s.ix ~= row[i - 1].s.ix + 1 then
				local a, b = row[runStart].s, row[i - 1].s
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				p.Material = Enum.Material.Neon
				p.Transparency = 0.35
				p.Color = colors[row[runStart].status]
				p.Size = Vector3.new((b.ix - a.ix + 1) * last.cell - 0.2, 0.2, last.cell - 0.2)
				p.Position = Vector3.new((a.x + b.x) / 2, a.y + 0.15, a.z)
				p.Parent = folder
				runStart = i
			end
		end
	end
	folder.Parent = Workspace
end

function MapProbe.clearViz()
	local old = Workspace:FindFirstChild("MapProbeViz")
	if old then
		old:Destroy()
	end
end

return MapProbe
