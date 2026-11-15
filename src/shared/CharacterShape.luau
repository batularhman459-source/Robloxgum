--!strict
-- Narrowing an R6 body sideways. Pure: no requires, no Roblox APIs.
-- A part narrowed by `scale` keeps its height and depth. Joint offsets along X move with the part
-- that owns them: C0 lives in the parent (Torso), C1 in the child (arm/leg/head). Scaling the X of
-- each by its own part's width keeps every limb attached exactly at the torso's (new) edge.

local CharacterShape = {}

-- Width scale for each R6 part from the rules (parts not listed keep 1).
function CharacterShape.scaleFor(c: any, partName: string): number
	if partName == "Torso" then
		return c.torsoWidth
	elseif partName == "Left Arm" or partName == "Right Arm" then
		return c.armWidth
	elseif partName == "Left Leg" or partName == "Right Leg" then
		return c.legWidth
	elseif partName == "Head" then
		return c.headWidth
	end
	return 1
end

-- New X of a joint offset (C0 uses the parent's scale, C1 the child's).
function CharacterShape.offsetX(x: number, scale: number): number
	return x * scale
end

return CharacterShape
