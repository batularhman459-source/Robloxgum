--!strict
-- Lets every player see everyone's slide (2026-11-17). The sliding client fires ReplicatedStorage.SlideState with
-- true / false (or "jump" for the slide jump, counted in "SlideJumps"; "cut" when a vault cuts the slide,
-- counted in "SlideCuts"); the server checks it (a boolean, from a living character, at most slide.net.maxPerSecond per
-- second) and sets the character's "Sliding" attribute, which replicates to all clients. Each client then draws
-- the pose and effects itself (src/client/SlideView.client.luau + SlideFeel.luau). Cosmetic only: the slide's
-- movement is the client's own character physics, as for all movement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local f = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("slide")) :: any
local RateLimit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RateLimit"))

local remote = Instance.new("RemoteEvent")
remote.Name = "SlideState"
remote.Parent = ReplicatedStorage

local limits: { [Player]: RateLimit.Limit } = {}

-- msg: true / false (sliding or not), or "jump" (the slide jump: other clients play its whoosh).
remote.OnServerEvent:Connect(function(player: Player, msg: unknown)
	if typeof(msg) ~= "boolean" and msg ~= "jump" and msg ~= "cut" then
		return
	end
	local limit = limits[player]
	if not limit then
		limit = RateLimit.new(f.net.maxPerSecond, 1)
		limits[player] = limit
	end
	if not RateLimit.allow(limit, os.clock()) then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		return
	end
	if msg == "jump" then
		char:SetAttribute("SlideJumps", ((char:GetAttribute("SlideJumps") :: number?) or 0) + 1)
	elseif msg == "cut" then
		-- a vault cut the slide: other clients drop the slide pose at once instead of playing its exit
		char:SetAttribute("SlideCuts", ((char:GetAttribute("SlideCuts") :: number?) or 0) + 1)
	else
		char:SetAttribute("Sliding", msg)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	limits[player] = nil
end)
