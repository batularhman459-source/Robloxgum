-- Touch controls added next to Roblox's own jump button. Only mounted on touch devices
-- (ParkourController calls UiRuntime.mount("MobileControls")).
-- Roblox's phone jump button sits about 95 studs from the right and 90 from the bottom, 70 big:
-- the slide button sits to its left at the same height, thumb-sized.
return {
	name = "MobileControls",
	style = "house",
	mount = false,
	displayOrder = 5,
	children = {
		{
			kind = "button",
			name = "SlideButton",
			text = "Slide",
			textSize = 18,
			color = "accent",
			anchor = { 1, 1 },
			pos = { 1, -104, 1, -20 },
			size = { 0, 76, 0, 76 },
			pad = 10, -- default 14 leaves 48 px, "Slide" at 18 px needs ~50
		},
	},
}
