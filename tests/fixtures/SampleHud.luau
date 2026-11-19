-- Test fixture only: the placeholder HUD (coins, shop, upgrades, rebirth, settings) we tried out, removed from the
-- game 2026-11-19 (designer). Kept here because tests/ui.spec.luau uses it to prove the Depth Stack and scaling.
-- Example HUD. A UI spec is plain data: no Roblox code.
-- pos / size = {scaleX, offsetX, scaleY, offsetY} (like UDim2). anchor = {x, y}.
-- kinds: panel, button (both get the Depth Stack), text, icon, group (invisible container).
return {
	name = "Hud",
	style = "house",
	children = {
		{
			kind = "panel",
			name = "CoinBar",
			pos = { 0, 16, 0, 12 },
			size = { 0, 180, 0, 52 },
			list = { dir = "x", align = "start", gap = 8 },
			children = {
				{ kind = "icon", name = "CoinIcon", icon = "coin", size = { 0, 24, 0, 24 } },
				{
					kind = "text",
					name = "CoinText",
					text = "1,250",
					textSize = 20,
					align = "start",
					size = { 0, 110, 0, 24 },
				},
			},
		},
		{
			kind = "button",
			name = "SettingsButton",
			icon = "settings",
			anchor = { 1, 0 },
			pos = { 1, -16, 0, 12 },
			size = { 0, 52, 0, 52 },
			color = "panel",
		},
		{
			kind = "group",
			name = "MenuBar",
			anchor = { 0.5, 1 },
			pos = { 0.5, 0, 1, -16 },
			size = { 0, 388, 0, 56 },
			list = { dir = "x", gap = 14 },
			children = {
				{
					kind = "button",
					name = "ShopButton",
					text = "Shop",
					textSize = 20,
					color = "primary",
					textColor = "textDark",
					size = { 0, 120, 0, 56 },
				},
				{
					kind = "button",
					name = "UpgradesButton",
					text = "Upgrades",
					textSize = 20,
					color = "accent",
					size = { 0, 120, 0, 56 },
				},
				{
					kind = "button",
					name = "RebirthButton",
					text = "Rebirth",
					textSize = 20,
					color = "danger",
					size = { 0, 120, 0, 56 },
				},
			},
		},
	},
}
