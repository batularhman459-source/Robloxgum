--!strict
-- Builds every UI spec (ui/specs) into PlayerGui. Specs with mount = false are skipped;
-- code opens those later with UiBuilder.build.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = ReplicatedStorage:WaitForChild("UI")
local sharedUi = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ui")
local UiBuilder = require(sharedUi:WaitForChild("UiBuilder"))
local UiLayout = require(sharedUi:WaitForChild("UiLayout"))
local icons = require(UI:WaitForChild("icons")) :: any
local themes = UI:WaitForChild("Themes")

local env = {
	Instance = Instance,
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	Color3 = Color3,
	ColorSequence = ColorSequence,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	Font = Font,
	Enum = Enum,
}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
for _, module in UI:WaitForChild("Specs"):GetChildren() do
	if module:IsA("ModuleScript") then
		local spec = require(module) :: any
		if spec.mount ~= false then
			local theme = require(themes:WaitForChild(spec.style or "house")) :: any
			local gui = UiBuilder.build(spec, theme, icons, env, UiLayout)
			gui.Parent = playerGui
			-- Rescale whenever the screen changes size (window resize, phone rotation).
			local function rescale()
				local size = gui.AbsoluteSize -- the area below the top bar
				if size.X > 0 and size.Y > 0 then
					UiBuilder.setScale(gui, UiLayout.scaleFor(theme, size.X, size.Y), env)
				end
			end
			gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
			rescale()
		end
	end
end
