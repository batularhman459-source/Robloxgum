-- A deliberately bad UI: each element breaks one checker rule. Used by tests/ui.spec.luau.
return {
	name = "BadUi",
	children = {
		-- thumb: too small to tap
		{
			kind = "button",
			name = "TinyButton",
			text = "Go",
			textSize = 14,
			pos = { 0, 20, 0, 20 },
			size = { 0, 40, 0, 40 },
			pad = 4,
			textColor = "textDark",
		},
		-- spacing: two panels 2px apart
		{
			kind = "panel",
			name = "PanelA",
			pos = { 0, 20, 0, 100 },
			size = { 0, 100, 0, 60 },
			children = { { kind = "text", name = "AText", text = "A", pos = { 0, 0, 0, 0 }, size = { 1, 0, 1, 0 } } },
		},
		{
			kind = "panel",
			name = "PanelB",
			pos = { 0, 122, 0, 100 },
			size = { 0, 100, 0, 60 },
			children = { { kind = "text", name = "BText", text = "B", pos = { 0, 0, 0, 0 }, size = { 1, 0, 1, 0 } } },
		},
		-- centre: 4px off centre
		{
			kind = "panel",
			name = "AlmostCentred",
			anchor = { 0.5, 0 },
			pos = { 0.5, 4, 0, 200 },
			size = { 0, 200, 0, 60 },
			children = { { kind = "text", name = "CText", text = "Hi", pos = { 0, 0, 0, 0 }, size = { 1, 0, 1, 0 } } },
		},
		-- tiny: 10px text and an empty panel
		{
			kind = "panel",
			name = "SmallTextPanel",
			pos = { 0, 500, 0, 100 },
			size = { 0, 200, 0, 60 },
			children = {
				{
					kind = "text",
					name = "SmallText",
					text = "fine print",
					textSize = 10,
					pos = { 0, 0, 0, 0 },
					size = { 1, 0, 1, 0 },
				},
			},
		},
		{ kind = "panel", name = "EmptyPanel", pos = { 0, 500, 0, 200 }, size = { 0, 80, 0, 60 } },
		-- separator: info joined with a bullet
		{
			kind = "panel",
			name = "InfoPanel",
			pos = { 0, 20, 0, 290 },
			size = { 0, 400, 0, 60 },
			children = {
				{
					kind = "text",
					name = "InfoText",
					text = "2 Players • 4:40 Remaining",
					pos = { 0, 0, 0, 0 },
					size = { 1, 0, 1, 0 },
				},
			},
		},
		-- screens: hangs off the right edge on the phone
		{
			kind = "panel",
			name = "OffScreen",
			pos = { 0, 760, 0, 20 },
			size = { 0, 120, 0, 60 },
			children = { { kind = "text", name = "OText", text = "Off", pos = { 0, 0, 0, 0 }, size = { 1, 0, 1, 0 } } },
		},
	},
}
