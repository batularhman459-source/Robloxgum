--!strict
-- Builds the real Roblox UI from a spec + theme.
-- The same code runs in Studio (env = Roblox globals) and in Lune (env = @lune/roblox), so the
-- .rbxm file and the in-game UI can never differ. Defaults come from UiLayout.resolve.
-- Pure: no requires, no services. Everything it needs is passed in.

local UiBuilder = {}

local ALIGN_X = { start = "Left", center = "Center", ["end"] = "Right" }
local ALIGN_Y = { start = "Top", center = "Center", ["end"] = "Bottom" }
local FULL = { 1, 0, 1, 0 }

local function new(env: any, class: string, props: { [string]: any }, parent: any): any
	local inst = env.Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function udim2(env: any, v: { number }): any
	return env.UDim2.new(v[1], v[2], v[3], v[4])
end

local function rgb(env: any, c: { number }): any
	return env.Color3.fromRGB(c[1], c[2], c[3])
end

local function corner(env: any, radius: number, parent: any)
	new(env, "UICorner", { CornerRadius = env.UDim.new(0, radius) }, parent)
end

local function font(env: any, theme: any, weight: string): any
	return env.Font.new("rbxasset://fonts/families/" .. theme.text.font .. ".json", env.Enum.FontWeight[weight])
end

local function addLayout(env: any, inst: any, r: any)
	if r.pad > 0 then
		local p = env.UDim.new(0, r.pad)
		new(env, "UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p }, inst)
	end
	if r.list then
		local horiz = r.list.dir == "x"
		new(env, "UIListLayout", {
			FillDirection = if horiz then env.Enum.FillDirection.Horizontal else env.Enum.FillDirection.Vertical,
			Padding = env.UDim.new(0, r.list.gap),
			SortOrder = env.Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = env.Enum.HorizontalAlignment[ALIGN_X[if horiz then r.list.align else r.list.cross]],
			VerticalAlignment = env.Enum.VerticalAlignment[ALIGN_Y[if horiz then r.list.cross else r.list.align]],
		}, inst)
	end
end

local function textLabel(env: any, theme: any, name: string, text: string, r: any, box: any, parent: any): any
	return new(env, "TextLabel", {
		Name = name,
		Text = text,
		RichText = false,
		TextWrapped = false,
		BackgroundTransparency = 1,
		TextSize = r.textSize,
		FontFace = font(env, theme, r.weight),
		TextColor3 = rgb(env, r.textColor),
		TextXAlignment = env.Enum.TextXAlignment[ALIGN_X[r.align]],
		TextYAlignment = env.Enum.TextYAlignment.Center,
		Size = box.Size,
		Position = box.Position,
		AnchorPoint = box.AnchorPoint,
		LayoutOrder = box.LayoutOrder,
	}, parent)
end

local function iconLabel(env: any, icons: any, name: string, icon: string, props: { [string]: any }, parent: any): any
	props.Name = name
	props.BackgroundTransparency = 1
	props.ScaleType = env.Enum.ScaleType.Fit
	props.Image = if icons[icon] then "rbxassetid://" .. tostring(icons[icon]) else ""
	return new(env, "ImageLabel", props, parent)
end

-- The Depth Stack: shadow (blue-shifted), face with gradient, lift (top sheen), one outline thickness.
-- Returns the container and the Content frame where children go.
local function depthStack(env: any, theme: any, s: any, r: any, box: any, parent: any): (any, any)
	local D = theme.depth
	local t = D.strokeThickness
	local container = new(env, "Frame", {
		Name = s.name,
		BackgroundTransparency = 1,
		Size = box.Size,
		Position = box.Position,
		AnchorPoint = box.AnchorPoint,
		LayoutOrder = box.LayoutOrder,
	}, parent)

	local shadow = new(env, "Frame", {
		Name = "Shadow",
		BackgroundColor3 = rgb(env, D.shadowColor),
		BackgroundTransparency = D.shadowTransparency,
		BorderSizePixel = 0,
		Size = env.UDim2.new(1, 2 * t, 1, 2 * t),
		Position = env.UDim2.new(0, D.shadowOffsetX - t, 0, D.shadowOffsetY - t),
		ZIndex = 1,
	}, container)
	corner(env, D.cornerRadius + t, shadow)

	local face = new(env, if s.kind == "button" then "TextButton" else "Frame", {
		Name = "Face",
		BackgroundColor3 = rgb(env, r.color),
		BorderSizePixel = 0,
		Size = udim2(env, FULL),
		ZIndex = 2,
	}, container)
	if s.kind == "button" then
		face.Text = ""
		face.AutoButtonColor = true
	end
	corner(env, D.cornerRadius, face)
	new(env, "UIStroke", {
		Thickness = t,
		Color = rgb(env, D.strokeColor),
		ApplyStrokeMode = env.Enum.ApplyStrokeMode.Border,
		LineJoinMode = env.Enum.LineJoinMode.Round,
	}, face)
	new(env, "UIGradient", {
		Color = env.ColorSequence.new(
			env.Color3.new(D.gradientTop, D.gradientTop, D.gradientTop),
			env.Color3.new(D.gradientBottom, D.gradientBottom, D.gradientBottom)
		),
		Rotation = 90,
	}, face)

	local lift = new(env, "Frame", {
		Name = "Lift",
		BackgroundColor3 = env.Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = udim2(env, FULL),
		ZIndex = 1,
	}, face)
	corner(env, D.cornerRadius, lift)
	new(env, "UIGradient", {
		Transparency = env.NumberSequence.new({
			env.NumberSequenceKeypoint.new(0, D.liftTransparency),
			env.NumberSequenceKeypoint.new(D.liftHeight, 1),
			env.NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, lift)

	local content = new(env, "Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = udim2(env, FULL),
		ZIndex = 2,
	}, face)
	addLayout(env, content, r)
	return container, content
end

-- Builds a ScreenGui from a spec. env = table of Roblox constructors (Instance, UDim2, ...).
function UiBuilder.build(spec: any, theme: any, icons: any, env: any, UiLayout: any): any
	local gui = env.Instance.new("ScreenGui")
	gui.Name = spec.name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = env.Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = env.Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = spec.displayOrder or 0

	-- Everything lives in Root, which UiBuilder.setScale sizes to 1/scale and scales back up,
	-- so the whole UI grows with the screen while scale positions still reach the edges.
	local root = new(env, "Frame", { Name = "Root", BackgroundTransparency = 1, Size = udim2(env, FULL) }, gui)
	new(env, "UIScale", { Name = "Scale", Scale = 1 }, root)

	local function walk(list: any, parent: any)
		for i, s in list do
			local r = UiLayout.resolve(s, theme)
			local box = {
				Size = udim2(env, s.size),
				Position = udim2(env, r.pos),
				AnchorPoint = env.Vector2.new(r.anchor[1], r.anchor[2]),
				LayoutOrder = i,
			}
			local content
			if UiLayout.DEPTH[s.kind] then
				local _, c = depthStack(env, theme, s, r, box, parent)
				content = c
				if s.text then
					textLabel(env, theme, "Label", s.text, r, { Size = udim2(env, FULL) }, c)
				elseif s.icon then
					iconLabel(env, icons, "Icon", s.icon, {
						Size = env.UDim2.new(0, r.iconSize, 0, r.iconSize),
						Position = env.UDim2.new(0.5, 0, 0.5, 0),
						AnchorPoint = env.Vector2.new(0.5, 0.5),
					}, c)
				end
			elseif s.kind == "text" then
				textLabel(env, theme, s.name, s.text, r, box, parent)
			elseif s.kind == "icon" then
				iconLabel(env, icons, s.name, s.icon, {
					Size = box.Size,
					Position = box.Position,
					AnchorPoint = box.AnchorPoint,
					LayoutOrder = box.LayoutOrder,
				}, parent)
			else -- group
				content = new(env, "Frame", {
					Name = s.name,
					BackgroundTransparency = 1,
					Size = box.Size,
					Position = box.Position,
					AnchorPoint = box.AnchorPoint,
					LayoutOrder = box.LayoutOrder,
				}, parent)
				addLayout(env, content, r)
			end
			if s.children and content then
				walk(s.children, content)
			end
		end
	end

	walk(spec.children or {}, root)
	return gui
end

-- Applies a UI scale (from UiLayout.scaleFor) to a built ScreenGui.
function UiBuilder.setScale(gui: any, scale: number, env: any)
	local root = gui:FindFirstChild("Root")
	local uiScale = root and root:FindFirstChild("Scale")
	if not uiScale then
		error("setScale: " .. gui.Name .. " was not built by UiBuilder (no Root/Scale)")
	end
	root.Size = env.UDim2.new(1 / scale, 0, 1 / scale, 0)
	uiScale.Scale = scale
end

return UiBuilder
