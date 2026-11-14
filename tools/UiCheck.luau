-- UI checker. Runs every spec on 4 real screen sizes and enforces the house rules.
-- Rules: screens, thumb, spacing, fit, contrast, centre, tiny, separator, stroke.
local UiLayout = require("../src/shared/ui/UiLayout")

local UiCheck = {}

-- Roblox reports these sizes in points (what UI offsets use).
UiCheck.SCREENS = {
	{ name = "Phone", w = 844, h = 390 },
	{ name = "Tablet", w = 1180, h = 820 },
	{ name = "Laptop", w = 1366, h = 768 },
	{ name = "Full HD", w = 1920, h = 1080 },
}

-- Joining bits of info with these is a dead giveaway. Use separate labels instead.
UiCheck.SEPARATORS = { "•", "·", "∙", "●", "◦", "|", " - ", " – ", " — " }

local CHAR_WIDTH = 0.56 -- average glyph width as a fraction of text size (bold Builder Sans)

local function lum(c: { number }, m: number): number
	local function ch(v: number): number
		v = math.min(255, v * m) / 255
		return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end

local function contrast(a: number, b: number): number
	local hi, lo = math.max(a, b), math.min(a, b)
	return (hi + 0.05) / (lo + 0.05)
end

local function gap(a: any, b: any): number
	local dx = math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
	local dy = math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
	return math.max(dx, dy) -- negative = overlapping
end

local function inside(inner: any, outer: any): boolean
	return inner.x >= outer.x - 0.01
		and inner.y >= outer.y - 0.01
		and inner.x + inner.w <= outer.x + outer.w + 0.01
		and inner.y + inner.h <= outer.y + outer.h + 0.01
end

local function isAncestor(a: any, b: any): boolean
	local p = b.parent
	while p do
		if p == a then
			return true
		end
		p = p.parent
	end
	return false
end

local function depthAncestor(n: any): any
	local p = n
	while p and p.kind ~= "screen" do
		if UiLayout.DEPTH[p.kind] then
			return p
		end
		p = p.parent
	end
	return nil
end

local function visibleAncestor(n: any): any
	local p = n.parent
	while p and p.kind == "group" do
		p = p.parent
	end
	return p
end

local function fmt(n: number): string
	return string.format("%.1f", n):gsub("%.0$", "")
end

-- Returns { errors = {{rule, msg, screens = {...}}}, warnings = {...}, failed = {[name] = true} }
function UiCheck.run(spec: any, theme: any, icons: any)
	local L, D = theme.layout, theme.depth
	local result = { errors = {}, warnings = {}, failed = {} }
	local index = {}

	local function report(list: any, rule: string, msg: string, screen: string, who: { string }?)
		local key = rule .. "|" .. msg
		local entry = index[key]
		if not entry then
			entry = { rule = rule, msg = msg, screens = {} }
			index[key] = entry
			table.insert(list, entry)
		end
		table.insert(entry.screens, screen)
		for _, name in who or {} do
			result.failed[name] = true
		end
	end

	-- Things that don't depend on screen size.
	if D.strokeThickness ~= math.floor(D.strokeThickness) or D.strokeThickness < 1 then
		report(result.errors, "stroke", "strokeThickness must be a whole number >= 1", "all")
	end

	for _, sc in UiCheck.SCREENS do
		local function err(rule: string, msg: string, ...: string)
			report(result.errors, rule, msg, sc.name, { ... })
		end
		local function warn(rule: string, msg: string)
			report(result.warnings, rule, msg, sc.name)
		end
		local root, nodes = UiLayout.layout(spec, theme, sc.w, sc.h)
		local safe = UiLayout.inset(root.rect, L.minGap)

		for _, n in nodes do
			local s = n.spec
			-- Sizes in real screen pixels (the UI is scaled by n.scale).
			local r = table.clone(n.resolved)
			r.textSize *= n.scale
			r.iconSize *= n.scale
			local visual = n.kind ~= "group"

			-- 1. Fits on every screen.
			if visual and not inside(n.outer, safe) then
				err("screens", string.format("%s goes off screen or into the top bar", n.name), n.name)
			end

			-- 2. Thumb size.
			if n.kind == "button" and (n.rect.w < L.minTouch or n.rect.h < L.minTouch) then
				err(
					"thumb",
					string.format(
						"%s is %sx%s, buttons need at least %dx%d",
						n.name,
						fmt(n.rect.w),
						fmt(n.rect.h),
						L.minTouch,
						L.minTouch
					),
					n.name
				)
			end

			-- 3. Nothing touches: stays inside its parent with room to spare.
			local va = visibleAncestor(n)
			if visual and va and va.kind ~= "screen" and not inside(n.outer, UiLayout.inset(va.rect, L.minGap)) then
				err(
					"spacing",
					string.format("%s touches the edge of %s (keep %dpx inside)", n.name, va.name, L.minGap),
					n.name
				)
			end

			-- 3b. Text fits its box (or it would spill and touch things).
			local text = if n.kind == "text" or (n.kind == "button" and s.text) then s.text else nil
			if text then
				local box = if n.kind == "button" then n.content else n.rect
				local need = utf8.len(text) * r.textSize * CHAR_WIDTH
				if need > box.w + 0.01 or r.textSize * 1.2 > box.h + 0.01 then
					err(
						"fit",
						string.format(
							"text '%s' in %s needs about %sx%s, box is %sx%s",
							text,
							n.name,
							fmt(need),
							fmt(r.textSize * 1.2),
							fmt(box.w),
							fmt(box.h)
						),
						n.name
					)
				end
				-- 3c. Not blended: readable against what's behind it.
				local bg = depthAncestor(n)
				if bg then
					local mid = (D.gradientTop + D.gradientBottom) / 2
					local ratio = contrast(lum(r.textColor, 1), lum(bg.resolved.color, mid))
					local need2 = if r.textSize >= L.largeText then L.minContrastLarge else L.minContrast
					if ratio < need2 then
						err(
							"contrast",
							string.format(
								"text in %s blends into %s (contrast %.1f, needs %.1f)",
								n.name,
								bg.name,
								ratio,
								need2
							),
							n.name
						)
					end
				else
					warn("contrast", string.format("text %s sits on the game world with no panel behind it", n.name))
				end
				-- 5. No tiny text.
				if r.textSize < L.minTextSize then
					err(
						"tiny",
						string.format("text in %s is %spx, minimum is %dpx", n.name, fmt(r.textSize), L.minTextSize),
						n.name
					)
				end
				-- 6. No separator-joined info.
				for _, sep in UiCheck.SEPARATORS do
					if string.find(text, sep, 1, true) then
						err(
							"separator",
							string.format("text '%s' joins info with '%s': use separate labels", text, sep),
							n.name
						)
						break
					end
				end
				if text:gsub("%s", "") == "" then
					err("tiny", string.format("%s has empty text", n.name), n.name)
				end
			end

			-- Icon inside a button must fit.
			if
				n.kind == "button"
				and s.icon
				and (r.iconSize > n.content.w + 0.01 or r.iconSize > n.content.h + 0.01)
			then
				err(
					"fit",
					string.format(
						"icon in %s is %spx but only %sx%s fits",
						n.name,
						fmt(r.iconSize),
						fmt(n.content.w),
						fmt(n.content.h)
					),
					n.name
				)
			end
			local iconName = if n.kind == "icon" or n.kind == "button" then s.icon else nil
			if iconName and not icons[iconName] then
				warn("icon", string.format("icon '%s' has no uploaded asset yet (shows empty in game)", iconName))
			end

			-- 5. No random boxes.
			if n.kind == "group" and #n.children == 0 then
				err("tiny", string.format("%s is an empty group", n.name), n.name)
			end
			if n.kind == "panel" and #n.children == 0 then
				err("tiny", string.format("%s is an empty panel (random box)", n.name), n.name)
			end
			if n.rect.w < L.minElement or n.rect.h < L.minElement then
				err(
					"tiny",
					string.format("%s is only %sx%s (minimum %dpx)", n.name, fmt(n.rect.w), fmt(n.rect.h), L.minElement),
					n.name
				)
			end

			-- 4. Centred to 1.5px: almost-centred counts as a mistake.
			local P = n.parent.content
			local dx = (n.rect.x + n.rect.w / 2) - (P.x + P.w / 2)
			local dy = (n.rect.y + n.rect.h / 2) - (P.y + P.h / 2)
			if math.abs(dx) > L.centerTolerance and math.abs(dx) < L.centerSnap then
				err("centre", string.format("%s is %spx off centre horizontally", n.name, fmt(dx)), n.name)
			end
			if math.abs(dy) > L.centerTolerance and math.abs(dy) < L.centerSnap and n.parent.kind ~= "screen" then
				err("centre", string.format("%s is %spx off centre vertically", n.name, fmt(dy)), n.name)
			end
		end

		-- 3. Nothing touches anything else.
		for i = 1, #nodes do
			local a = nodes[i]
			if a.kind ~= "group" then
				for j = i + 1, #nodes do
					local b = nodes[j]
					if b.kind ~= "group" and not isAncestor(a, b) and not isAncestor(b, a) then
						local g = gap(a.outer, b.outer)
						if g < L.minGap then
							local what = if g < 0 then "overlap" else string.format("are %spx apart", fmt(g))
							err(
								"spacing",
								string.format("%s and %s %s (minimum %dpx)", a.name, b.name, what, L.minGap),
								a.name,
								b.name
							)
						end
					end
				end
			end
		end
	end

	return result
end

function UiCheck.format(specName: string, result: any): string
	local out = {}
	local all = #UiCheck.SCREENS
	local function where(e: any): string
		if #e.screens >= all or e.screens[1] == "all" then
			return "all screens"
		end
		return table.concat(e.screens, ", ")
	end
	if #result.errors == 0 then
		table.insert(out, string.format("UI %s: PASS on %d screen sizes", specName, all))
	else
		table.insert(out, string.format("UI %s: %d problem(s)", specName, #result.errors))
		for _, e in result.errors do
			table.insert(out, string.format("  FAIL [%s] %s  (%s)", e.rule, e.msg, where(e)))
		end
	end
	for _, w in result.warnings do
		table.insert(out, string.format("  warn [%s] %s", w.rule, w.msg))
	end
	return table.concat(out, "\n")
end

return UiCheck
