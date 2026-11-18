--!strict
-- Draws OTHER players' slides (pose, wind trails, rock chips: SlideFeel) and double-jump flips (FlipFeel) on this
-- client. Their "Sliding"
-- attribute is set by the server (src/server/SlideNet.server.luau). This player's own slide is driven straight
-- from ParkourController, with no network delay, so it is skipped here.
local Players = game:GetService("Players")

local SlideFeel = require(script.Parent:WaitForChild("SlideFeel"))
local FlipFeel = require(script.Parent:WaitForChild("FlipFeel"))

local function watch(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and hum:IsA("Humanoid") and hrp and hrp:IsA("BasePart")) then
		return
	end
	local feel = SlideFeel.new(char, hum, hrp, false)
	if not feel then
		return
	end
	local function update()
		feel:set(char:GetAttribute("Sliding") == true)
	end
	local conn = char:GetAttributeChangedSignal("Sliding"):Connect(update)
	local cutConn = char:GetAttributeChangedSignal("SlideCuts"):Connect(function()
		feel:interrupt()
	end)
	local flip = FlipFeel.new(char, hum, hrp)
	local flipConn = char:GetAttributeChangedSignal("Flips"):Connect(function()
		if flip then
			flip:play()
		end
	end)
	update()
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			conn:Disconnect()
			cutConn:Disconnect()
			flipConn:Disconnect()
			if flip then
				flip:destroy()
			end
			feel:destroy()
		end
	end)
end

local function onPlayer(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)
