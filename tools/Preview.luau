-- Renders a spec to an HTML sheet showing all 4 screen sizes, using the same layout engine as the
-- checker. tools/ui.luau screenshots it with Edge to make the preview PNG.
-- Elements the checker flagged get a red dashed outline.
local UiLayout = require("../src/shared/ui/UiLayout")

local Preview = {}

local WEIGHTS =
	{ Thin = 100, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900 }
local JUSTIFY = { start = "flex-start", center = "center", ["end"] = "flex-end" }
local CELL = 1000 -- max width of one screen in the sheet
local LABEL = 36

local function css(c: { number }, m: number?): string
	local k = m or 1
	local function ch(v: number): number
		return math.clamp(math.floor(v * k + 0.5), 0, 255)
	end
	return string.format("rgb(%d,%d,%d)", ch(c[1]), ch(c[2]), ch(c[3]))
end

local function box(r: any): string
	return string.format("left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;", r.x, r.y, r.w, r.h)
end

local function esc(s: string): string
	local out = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return out
end

local function textDiv(r: any, rect: any, text: string, theme: any): string
	return string.format(
		'<div class="t" style="%sjustify-content:%s;font-size:%.2fpx;font-weight:%d;color:%s">%s</div>',
		box(rect),
		JUSTIFY[r.align],
		r.textSize,
		WEIGHTS[r.weight] or 700,
		css(r.textColor),
		esc(text)
	)
end

local function iconDiv(rect: any, name: string, iconFiles: any): string
	if iconFiles[name] then
		return string.format('<img class="i" style="%s" src="%s">', box(rect), iconFiles[name])
	end
	return string.format('<div class="i missing" style="%s">%s</div>', box(rect), esc(name))
end

local function screenHtml(spec: any, theme: any, sc: any, iconFiles: any, failed: any): string
	local D, L = theme.depth, theme.layout
	local _, nodes = UiLayout.layout(spec, theme, sc.w, sc.h)
	local parts = {}
	for _, n in nodes do
		-- Everything in real screen pixels (the UI is scaled by n.scale).
		local k = n.scale
		local t = D.strokeThickness * k
		local radius = D.cornerRadius * k
		local r = table.clone(n.resolved)
		r.textSize *= k
		r.iconSize *= k
		if UiLayout.DEPTH[n.kind] then
			table.insert(
				parts,
				string.format(
					'<div class="s" style="%sbackground:%s;opacity:%.2f;border-radius:%.2fpx"></div>',
					box(n.shadow),
					css(D.shadowColor),
					1 - D.shadowTransparency,
					radius + t
				)
			)
			table.insert(
				parts,
				string.format(
					'<div class="f" style="%sbackground:linear-gradient(%s,%s);border-radius:%.2fpx;box-shadow:0 0 0 %.2fpx %s"></div>',
					box(n.rect),
					css(r.color, D.gradientTop),
					css(r.color, D.gradientBottom),
					radius,
					t,
					css(D.strokeColor)
				)
			)
			table.insert(
				parts,
				string.format(
					'<div class="f" style="%sbackground:linear-gradient(rgba(255,255,255,%.2f) 0%%,rgba(255,255,255,0) %.0f%%);border-radius:%.2fpx"></div>',
					box(n.rect),
					1 - D.liftTransparency,
					D.liftHeight * 100,
					radius
				)
			)
			if n.spec.text then
				table.insert(parts, textDiv(r, n.content, n.spec.text, theme))
			elseif n.spec.icon then
				local c = n.content
				local ir = {
					x = c.x + (c.w - r.iconSize) / 2,
					y = c.y + (c.h - r.iconSize) / 2,
					w = r.iconSize,
					h = r.iconSize,
				}
				table.insert(parts, iconDiv(ir, n.spec.icon, iconFiles))
			end
		elseif n.kind == "text" then
			table.insert(parts, textDiv(r, n.rect, n.spec.text, theme))
		elseif n.kind == "icon" then
			table.insert(parts, iconDiv(n.rect, n.spec.icon, iconFiles))
		end
		if failed[n.name] then
			table.insert(parts, string.format('<div class="bad" style="%s"></div>', box(n.outer)))
		end
	end
	local scale = math.min(1, CELL / sc.w)
	return string.format(
		[[<div class="cell"><div class="label"><b>%s</b><span>%d × %d</span></div>
<div class="frame" style="width:%.0fpx;height:%.0fpx"><div class="screen" style="width:%dpx;height:%dpx;transform:scale(%.4f)">
<div class="topbar" style="height:%dpx"></div>%s</div></div></div>]],
		sc.name,
		sc.w,
		sc.h,
		sc.w * scale,
		sc.h * scale,
		sc.w,
		sc.h,
		scale,
		L.safeTop,
		table.concat(parts, "\n")
	)
end

-- Returns html, sheet width, sheet height.
function Preview.render(spec: any, theme: any, screens: any, iconFiles: any, failed: any): (string, number, number)
	local cells = {}
	local rowH = { 0, 0 }
	for i, sc in screens do
		table.insert(cells, screenHtml(spec, theme, sc, iconFiles, failed))
		local row = math.ceil(i / 2)
		rowH[row] = math.max(rowH[row] or 0, sc.h * math.min(1, CELL / sc.w) + LABEL)
	end
	local width = CELL * 2 + 3 * 24
	local height = (rowH[1] or 0) + (rowH[2] or 0) + 3 * 24
	local html = string.format(
		[[<!doctype html><html><head><meta charset="utf-8"><title>%s preview</title><style>
*{box-sizing:border-box;margin:0}
body{background:#0e1020;font-family:"Segoe UI",system-ui,sans-serif;padding:24px;display:grid;grid-template-columns:%dpx %dpx;gap:24px;align-items:start}
.label{color:#c9cde0;font-size:15px;height:%dpx;display:flex;gap:10px;align-items:center}
.label span{color:#7d84a6}
.frame{position:relative;overflow:hidden;border-radius:6px}
.screen{position:absolute;left:0;top:0;transform-origin:0 0;background:linear-gradient(#7fb2e6,#bcd8f0 55%%,#6f8f5a 55%%,#58764a)}
.topbar{position:absolute;left:0;right:0;top:0;background:rgba(10,12,24,.35)}
.s,.f,.t,.i,.bad{position:absolute}
.t{display:flex;align-items:center;white-space:nowrap;line-height:1}
.i{object-fit:contain}
.missing{border:2px dashed rgba(255,255,255,.7);border-radius:6px;color:#fff;font-size:9px;display:flex;align-items:center;justify-content:center}
.bad{outline:2px dashed #ff2d55;outline-offset:2px}
</style></head><body>%s</body></html>]],
		esc(spec.name),
		CELL,
		CELL,
		LABEL,
		table.concat(cells, "\n")
	)
	return html, width, math.ceil(height)
end

return Preview
