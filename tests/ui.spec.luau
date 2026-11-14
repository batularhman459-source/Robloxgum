local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local UiBuilder = require("../src/shared/ui/UiBuilder")
local UiCheck = require("../tools/UiCheck")
local UiLayout = require("../src/shared/ui/UiLayout")

local theme = serde.decode("toml", fs.readFile("ui/themes/house.toml"))
local ENV = {
	Instance = roblox.Instance,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	Font = roblox.Font,
	Enum = roblox.Enum,
}

local function rules(result): { [string]: boolean }
	local set = {}
	for _, e in result.errors do
		set[e.rule] = true
	end
	return set
end

return {
	["example Hud passes every check"] = function(t)
		local spec = require("../ui/specs/Hud")
		t.eq(#UiLayout.validate(spec, theme), 0, "Hud spec valid")
		local result = UiCheck.run(spec, theme, {})
		t.eq(#result.errors, 0, UiCheck.format("Hud", result))
	end,

	["checker catches all 6 kinds of mistakes"] = function(t)
		local spec = require("./fixtures/BadUi")
		t.eq(#UiLayout.validate(spec, theme), 0, "BadUi spec valid")
		local found = rules(UiCheck.run(spec, theme, {}))
		for _, rule in { "screens", "thumb", "spacing", "centre", "tiny", "separator" } do
			t.ok(found[rule], "checker missed rule: " .. rule)
		end
	end,

	["checker catches low contrast and text that doesn't fit"] = function(t)
		local spec = {
			name = "X",
			children = {
				{
					kind = "button",
					name = "B",
					text = "Way too long label",
					color = "primary",
					pos = { 0, 20, 0, 20 },
					size = { 0, 100, 0, 50 },
				},
			},
		}
		local found = rules(UiCheck.run(spec, theme, {}))
		t.ok(found.contrast, "white on yellow should fail contrast")
		t.ok(found.fit, "long label should not fit")
	end,

	["UI scale: 1 on phone and laptop, bigger on Full HD, capped at max"] = function(t)
		local safe = theme.layout.safeTop
		t.eq(UiLayout.scaleFor(theme, 844, 390 - safe), 1, "phone")
		t.eq(UiLayout.scaleFor(theme, 1366, 768 - safe), 1, "laptop")
		local fhd = UiLayout.scaleFor(theme, 1920, 1080 - safe)
		t.ok(fhd > 1.3 and fhd < 1.5, "full hd should be about 1.4, got " .. fhd)
		t.eq(UiLayout.scaleFor(theme, 3840, 2160 - safe), theme.scale.max, "4k capped")
	end,

	["scaled layout keeps edge margins and grows sizes"] = function(t)
		local spec = require("../ui/specs/Hud")
		local _, phone = UiLayout.layout(spec, theme, 844, 390)
		local _, fhd = UiLayout.layout(spec, theme, 1920, 1080)
		local k = fhd[1].scale
		t.eq(phone[1].rect.w * k, fhd[1].rect.w, "CoinBar width scales")
		t.eq(fhd[1].rect.x, 16 * k, "CoinBar left margin scales")
	end,

	["validate rejects unknown keys and kinds"] = function(t)
		local spec = {
			name = "X",
			children = {
				{ kind = "blob", name = "A" },
				{ kind = "panel", name = "B", size = { 0, 1, 0, 1 }, pos = { 0, 0, 0, 0 }, glow = true },
			},
		}
		t.eq(#UiLayout.validate(spec, theme), 2)
	end,

	["every outline in the built UI has the one theme thickness"] = function(t)
		local gui = UiBuilder.build(require("../ui/specs/Hud"), theme, {}, ENV, UiLayout)
		local strokes = 0
		for _, inst in gui:GetDescendants() do
			if inst.ClassName == "UIStroke" then
				strokes += 1
				t.eq(inst.Thickness, theme.depth.strokeThickness, inst:GetFullName())
			end
		end
		t.ok(strokes == 5, "expected 5 depth stacks, got " .. strokes)
	end,

	["every panel and button gets the full depth stack"] = function(t)
		local gui = UiBuilder.build(require("../ui/specs/Hud"), theme, {}, ENV, UiLayout)
		for _, name in { "CoinBar", "SettingsButton", "ShopButton", "UpgradesButton", "RebirthButton" } do
			local c = gui:FindFirstChild(name, true)
			t.ok(c ~= nil, name .. " missing")
			t.ok(c:FindFirstChild("Shadow") ~= nil, name .. " shadow")
			local face = c:FindFirstChild("Face")
			t.ok(face:FindFirstChildOfClass("UIGradient") ~= nil, name .. " gradient")
			t.ok(face:FindFirstChild("Lift") ~= nil, name .. " lift")
			t.ok(face:FindFirstChildOfClass("UIStroke") ~= nil, name .. " outline")
		end
	end,
}
