--!strict
-- Builds UI specs into PlayerGui at runtime, with screen scaling. Shared by UiMount (auto-mounted
-- specs) and code that opens a spec itself (specs with mount = false, e.g. MobileControls).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = ReplicatedStorage:WaitForChild("UI")
local sharedUi = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ui")
local UiBuilder = require(sharedUi:WaitForChild("UiBuilder"))
local UiLayout = require(sharedUi:WaitForChild("UiLayout"))
local icons = require(UI:WaitForChild("icons")) :: any
local themes = UI:WaitForChild("Themes")
local specs = UI:WaitForChild("Specs")

local UiRuntime = {}

UiRuntime.env = {
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

-- Builds a spec (ModuleScript or its name) into PlayerGui and keeps it scaled to the screen.
function UiRuntime.mount(specOrName: ModuleScript | string): ScreenGui?
	local module = if typeof(specOrName) == "string" then specs:FindFirstChild(specOrName) else specOrName
	if not module or not module:IsA("ModuleScript") then
		warn("UiRuntime: no UI spec named " .. tostring(specOrName))
		return nil
	end
	local spec = require(module) :: any
	local theme = require(themes:WaitForChild(spec.style or "house")) :: any
	local gui = UiBuilder.build(spec, theme, icons, UiRuntime.env, UiLayout)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function rescale()
		local size = gui.AbsoluteSize -- the area below the top bar
		if size.X > 0 and size.Y > 0 then
			UiBuilder.setScale(gui, UiLayout.scaleFor(theme, size.X, size.Y), UiRuntime.env)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()
	return gui
end

-- Every spec without mount = false.
function UiRuntime.mountAll()
	for _, module in specs:GetChildren() do
		if module:IsA("ModuleScript") and (require(module) :: any).mount ~= false then
			UiRuntime.mount(module)
		end
	end
end

return UiRuntime
