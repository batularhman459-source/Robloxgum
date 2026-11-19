--!strict
-- What OTHER players see and hear of someone's wall run (designer 2026-11-19: "others should see the trails and hear
-- the footsteps"). The wall run itself only runs on its owner's client; its animations replicate on their own, so
-- this listens to that character's Animator: a footstep on every Config.StepEvery-th "Step" marker of a wall-run clip,
-- and the limb trails burst when a wall-jump clip starts, exactly like the owner's own Runner does. No network traffic
-- of its own. Used by src/client/SlideView.client.luau for every other player's character.
local Players = game:GetService("Players")

local Config = require(script.Parent:WaitForChild("Config"))
local Trails = require(script.Parent:WaitForChild("Trails"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local RUN_CLIPS = { "WallRunLeft", "WallRunRight" }
local JUMP_CLIPS = { "WallJumpLeft", "WallJumpRight" }

-- The uploaded ids of the wall run's clips, from this client's Anims folder (anim/r6/Clips.luau stamps them).
local function ids(names: { string }): { [string]: boolean }
	local folder = (Players.LocalPlayer:WaitForChild("PlayerScripts") :: any)
		:WaitForChild("Client")
		:WaitForChild("Anims")
	local out = {}
	for _, name in names do
		local seq = folder:WaitForChild(name, 5)
		local id = seq and seq:GetAttribute("AnimationId")
		if type(id) == "string" then
			out[id] = true
		end
	end
	return out
end

local function view(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	local runIds, jumpIds = ids(RUN_CLIPS), ids(JUMP_CLIPS)
	local trails = Trails.new(character, Config.TrailLimbs)
	local sounds = Sounds.new(root, { Step = Config.Sounds.Step })
	local steps = 0
	local connections: { RBXScriptConnection } = {}
	table.insert(
		connections,
		animator.AnimationPlayed:Connect(function(track: AnimationTrack)
			local id = track.Animation and track.Animation.AnimationId or ""
			if runIds[id] then
				table.insert(
					connections,
					track:GetMarkerReachedSignal("Step"):Connect(function()
						steps += 1
						if steps % Config.StepEvery == 0 then
							sounds:Play("Step")
						end
					end)
				)
			elseif jumpIds[id] then
				trails:Burst(Config.TrailDuration)
			end
		end)
	)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, c in connections do
				c:Disconnect()
			end
			-- the trails clean themselves up with the character (Trails attaches its Trove to it)
			sounds:Destroy()
		end
	end)
end

return view
