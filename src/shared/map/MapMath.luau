--!strict
-- Geometry math for the map checks. Pure: no requires, no Roblox APIs.
-- Studio collects part data with raycasts and overlap queries, this decides what is wrong.

local MapMath = {}

export type Point = { x: number, y: number, z: number }

-- Parts not connected to any root (ground) through touching parts.
-- touching[i] = list of part indices touching part i. Returns the unsupported indices.
function MapMath.unsupported(count: number, touching: { { number } }, roots: { [number]: boolean }): { number }
	local seen: { [number]: boolean } = {}
	local stack = {}
	for r in roots do
		seen[r] = true
		table.insert(stack, r)
	end
	while #stack > 0 do
		local n = table.remove(stack) :: number
		for _, t in touching[n] or {} do
			if not seen[t] then
				seen[t] = true
				table.insert(stack, t)
			end
		end
	end
	local result = {}
	for i = 1, count do
		if not seen[i] then
			table.insert(result, i)
		end
	end
	return result
end

-- How evenly points sit on a ring. Angles are measured around the centroid in the XZ plane.
function MapMath.ring(points: { Point }): any
	local n = #points
	local cx, cy, cz = 0, 0, 0
	for _, p in points do
		cx += p.x
		cy += p.y
		cz += p.z
	end
	cx, cy, cz = cx / n, cy / n, cz / n
	local radii, angles = {}, {}
	local rMean = 0
	for i, p in points do
		radii[i] = math.sqrt((p.x - cx) ^ 2 + (p.z - cz) ^ 2)
		angles[i] = math.atan2(p.z - cz, p.x - cx)
		rMean += radii[i] / n
	end
	local rDev, yDev = 0, 0
	for i, p in points do
		rDev = math.max(rDev, math.abs(radii[i] - rMean))
		yDev = math.max(yDev, math.abs(p.y - cy))
	end
	table.sort(angles)
	local step = 2 * math.pi / n
	local aDev = 0
	for i = 1, n do
		local nextA = if i == n then angles[1] + 2 * math.pi else angles[i + 1]
		aDev = math.max(aDev, math.abs((nextA - angles[i]) - step))
	end
	return {
		center = { x = cx, y = cy, z = cz },
		radius = rMean,
		radiusDev = rDev,
		angleDevDeg = math.deg(aDev),
		heightDev = yDev,
		isRing = n >= 4 and rMean > 0 and rDev / rMean < 0.15,
	}
end

-- Pairs of values that are almost equal but not quite (tol < difference < snap): sloppy alignment.
function MapMath.almostEqual(values: { number }, snap: number, tol: number): { { number } }
	local result = {}
	for i = 1, #values do
		for j = i + 1, #values do
			local d = math.abs(values[i] - values[j])
			if d > tol and d < snap then
				table.insert(result, { i, j, d })
			end
		end
	end
	return result
end

-- Angle in degrees that is close to, but not on, a multiple of `grid` degrees.
function MapMath.offGrid(deg: number, grid: number, snap: number, tol: number): number?
	local off = math.abs(((deg + grid / 2) % grid) - grid / 2)
	if off > tol and off < snap then
		return off
	end
	return nil
end

-- Overlap of two axis-aligned boxes {min = Point, max = Point}. Returns the smallest overlap depth
-- (how far you'd have to push them apart) and the overlap volume; depth <= 0 means no overlap.
function MapMath.boxOverlap(a: any, b: any): (number, number)
	local dx = math.min(a.max.x, b.max.x) - math.max(a.min.x, b.min.x)
	local dy = math.min(a.max.y, b.max.y) - math.max(a.min.y, b.min.y)
	local dz = math.min(a.max.z, b.max.z) - math.max(a.min.z, b.min.z)
	if dx <= 0 or dy <= 0 or dz <= 0 then
		return math.min(dx, dy, dz), 0
	end
	return math.min(dx, dy, dz), dx * dy * dz
end

return MapMath
