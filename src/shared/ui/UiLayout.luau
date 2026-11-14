--!strict
-- UI layout engine. Pure: no requires, no Roblox APIs.
-- Turns a UI spec + theme into pixel boxes for one screen size. The checker and the preview use it.
-- UiBuilder uses resolve() too, so the real UI and this engine agree on every default.

export type Rect = { x: number, y: number, w: number, h: number }

local UiLayout = {}

UiLayout.KINDS = { panel = true, button = true, text = true, icon = true, group = true }
UiLayout.DEPTH = { panel = true, button = true }

local TOP_KEYS = { name = true, style = true, displayOrder = true, mount = true, children = true }
local COMMON_KEYS =
	{ kind = true, name = true, pos = true, size = true, anchor = true, children = true, list = true, pad = true }
local KIND_KEYS = {
	panel = { color = true },
	button = {
		color = true,
		text = true,
		icon = true,
		iconSize = true,
		textSize = true,
		textColor = true,
		weight = true,
	},
	text = { text = true, textSize = true, textColor = true, weight = true, align = true },
	icon = { icon = true },
	group = {},
}
local ALIGNS = { start = true, center = true, ["end"] = true }

-- The one place where defaults live.
function UiLayout.resolve(s: any, theme: any): any
	local L, T = theme.layout, theme.text
	local list = nil
	if s.list then
		list = {
			dir = s.list.dir or "y",
			gap = s.list.gap or L.gap,
			align = s.list.align or "center",
			cross = s.list.cross or "center",
		}
	end
	return {
		anchor = s.anchor or { 0, 0 },
		pos = s.pos or { 0, 0, 0, 0 },
		pad = s.pad or (if UiLayout.DEPTH[s.kind] then L.padding else 0),
		list = list,
		color = theme.palette[s.color or (if s.kind == "button" then "primary" else "panel")],
		textColor = theme.palette[s.textColor or "text"],
		textSize = s.textSize or T.size,
		weight = s.weight or T.weight,
		align = s.align or "center",
		iconSize = s.iconSize or L.iconSize,
	}
end

local function isUDim2(v: any): boolean
	if type(v) ~= "table" or #v ~= 4 then
		return false
	end
	for _, n in v do
		if type(n) ~= "number" then
			return false
		end
	end
	return true
end

-- Returns a list of problems with the spec's shape. Empty list = valid.
function UiLayout.validate(spec: any, theme: any): { string }
	local errs = {}
	local function err(path: string, msg: string)
		table.insert(errs, path .. ": " .. msg)
	end
	if type(spec) ~= "table" then
		return { "spec must be a table" }
	end
	local top = tostring(spec.name or "?")
	for k in spec do
		if not TOP_KEYS[k] then
			err(top, "unknown top-level key '" .. tostring(k) .. "'")
		end
	end
	if type(spec.name) ~= "string" then
		err(top, "missing name")
	end
	local seen = {}
	local function walk(list: any, path: string, parentHasList: boolean)
		for i, s in list do
			local p = path .. "/" .. tostring(s.name or ("#" .. i))
			local allowed = KIND_KEYS[s.kind]
			if not allowed then
				err(p, "unknown kind '" .. tostring(s.kind) .. "'")
				continue
			end
			for k in s do
				if not COMMON_KEYS[k] and not allowed[k] then
					err(p, "key '" .. tostring(k) .. "' is not allowed on a " .. s.kind)
				end
			end
			if type(s.name) ~= "string" then
				err(p, "missing name")
			elseif seen[s.name] then
				err(p, "duplicate name (names must be unique in a spec)")
			end
			seen[s.name or ""] = true
			if not isUDim2(s.size) then
				err(p, "size must be {scaleX, offsetX, scaleY, offsetY}")
			end
			if s.pos ~= nil and not isUDim2(s.pos) then
				err(p, "pos must be {scaleX, offsetX, scaleY, offsetY}")
			end
			if s.pos == nil and not parentHasList then
				err(p, "needs pos (or a parent with list)")
			end
			if s.color and not theme.palette[s.color] then
				err(p, "unknown color '" .. tostring(s.color) .. "'")
			end
			if s.textColor and not theme.palette[s.textColor] then
				err(p, "unknown textColor '" .. tostring(s.textColor) .. "'")
			end
			if s.kind == "text" and type(s.text) ~= "string" then
				err(p, "text needs a text string")
			end
			if s.kind == "button" and s.text and s.icon then
				err(p, "button has text and icon: use children with a list instead")
			end
			if s.list then
				if s.list.dir and s.list.dir ~= "x" and s.list.dir ~= "y" then
					err(p, "list.dir must be 'x' or 'y'")
				end
				if (s.list.align and not ALIGNS[s.list.align]) or (s.list.cross and not ALIGNS[s.list.cross]) then
					err(p, "list.align / list.cross must be start, center or end")
				end
			end
			if s.children then
				if s.kind == "text" or s.kind == "icon" then
					err(p, s.kind .. " can't have children")
				elseif s.kind == "button" and (s.text or s.icon) then
					err(p, "button with text/icon can't also have children")
				else
					walk(s.children, p, s.list ~= nil)
				end
			end
		end
	end
	walk(spec.children or {}, top, false)
	return errs
end

local function inset(r: Rect, d: number): Rect
	return { x = r.x + d, y = r.y + d, w = r.w - 2 * d, h = r.h - 2 * d }
end
UiLayout.inset = inset

local function union(a: Rect, b: Rect): Rect
	local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
	return { x = x, y = y, w = math.max(a.x + a.w, b.x + b.w) - x, h = math.max(a.y + a.h, b.y + b.h) - y }
end

-- UI scale for a screen. W x safeH = the area below the Roblox top bar.
-- The one formula: UiMount uses it in game, layout() uses it for the checker and preview.
function UiLayout.scaleFor(theme: any, W: number, safeH: number): number
	local S = theme.scale
	return math.clamp(math.min(W / S.refWidth, safeH / S.refHeight), S.min, S.max)
end

-- Lays out a spec on a W x H screen. Returns the screen node and a flat list of all nodes
-- (parents always before their children). All boxes are in real screen pixels.
-- node.rect = the element box, node.outer = everything visible (outline + shadow),
-- node.content = inside the padding, node.shadow = the shadow box (depth elements only),
-- node.scale = the UI scale (multiply theme sizes like textSize by it to get real pixels).
-- Mirrors UiBuilder: everything sits in a Root frame of size 1/scale with a UIScale of scale.
function UiLayout.layout(spec: any, theme: any, W: number, H: number): (any, { any })
	local D, L = theme.depth, theme.layout
	local k = UiLayout.scaleFor(theme, W, H - L.safeTop)
	local screen = { x = 0, y = 0, w = W / k, h = (H - L.safeTop) / k } -- unscaled design space
	local root = { kind = "screen", name = spec.name, rect = screen, outer = screen, content = screen, children = {} }
	local nodes = {}

	local function place(list: any, parent: any, listCfg: any)
		local P = parent.content
		local items = {}
		for i, s in list do
			local r = UiLayout.resolve(s, theme)
			items[i] = { s = s, r = r, w = s.size[1] * P.w + s.size[2], h = s.size[3] * P.h + s.size[4], x = 0, y = 0 }
		end
		if listCfg then
			local horiz = listCfg.dir == "x"
			local total = listCfg.gap * math.max(#items - 1, 0)
			for _, it in items do
				total += if horiz then it.w else it.h
			end
			local main = if horiz then P.w else P.h
			local cross = if horiz then P.h else P.w
			local cursor = if listCfg.align == "start"
				then 0
				elseif listCfg.align == "end" then main - total
				else (main - total) / 2
			for _, it in items do
				local m = if horiz then it.w else it.h
				local c = if horiz then it.h else it.w
				local co = if listCfg.cross == "start"
					then 0
					elseif listCfg.cross == "end" then cross - c
					else (cross - c) / 2
				if horiz then
					it.x, it.y = P.x + cursor, P.y + co
				else
					it.x, it.y = P.x + co, P.y + cursor
				end
				cursor += m + listCfg.gap
			end
		else
			for _, it in items do
				local pos, a = it.r.pos, it.r.anchor
				it.x = P.x + pos[1] * P.w + pos[2] - a[1] * it.w
				it.y = P.y + pos[3] * P.h + pos[4] - a[2] * it.h
			end
		end
		for _, it in items do
			local s = it.s
			local rect = { x = it.x, y = it.y, w = it.w, h = it.h }
			local node = {
				spec = s,
				kind = s.kind,
				name = s.name,
				resolved = it.r,
				rect = rect,
				outer = rect,
				content = inset(rect, it.r.pad),
				parent = parent,
				children = {},
			}
			if UiLayout.DEPTH[s.kind] then
				local stroked = inset(rect, -D.strokeThickness)
				local shadow = {
					x = stroked.x + D.shadowOffsetX,
					y = stroked.y + D.shadowOffsetY,
					w = stroked.w,
					h = stroked.h,
				}
				node.shadow = shadow
				node.outer = union(stroked, shadow)
			end
			table.insert(parent.children, node)
			table.insert(nodes, node)
			if s.children then
				place(s.children, node, it.r.list)
			end
		end
	end

	place(spec.children or {}, root, nil)

	-- Design space -> real screen pixels.
	local function toScreen(r: Rect?): Rect?
		if not r then
			return nil
		end
		return { x = r.x * k, y = r.y * k + L.safeTop, w = r.w * k, h = r.h * k }
	end
	for _, n in { root, table.unpack(nodes) } do
		n.rect = toScreen(n.rect)
		n.outer = toScreen(n.outer)
		n.content = toScreen(n.content)
		n.shadow = toScreen(n.shadow)
		n.scale = k
	end
	return root, nodes
end

return UiLayout
