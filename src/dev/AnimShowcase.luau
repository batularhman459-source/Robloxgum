--!strict
-- Poses clones of the player's character in a row, each frozen at the key moment of one parkour
-- animation, so all clips can be judged in one screenshot on the real avatar (Client, play mode):
--   return require(game:GetService("ReplicatedStorage").DevTools.AnimShowcase:Clone()).show()
-- Then screen_capture with the camera it returns. Clear with .clear().
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AnimShowcase = {}

AnimShowcase.BASE = Vector3.new(30, 3.2, 760)
AnimShowcase.SPACING = 7
-- clip, time to freeze at (its key moment)
AnimShowcase.LIST = {
	{ "SlideHold", 0.1 },
	{ "Vault", 0.12 },
	{ "WallRunR", 0.0 },
	{ "WallRunL", 0.25 },
	{ "WallJump", 0.1 },
	{ "DoubleJump", 0.12 },
	{ "LandRoll", 0.15 },
	{ "HardLanding", 0.1 },
}

function AnimShowcase.clear()
	local old = Workspace:FindFirstChild("AnimShowcase")
	if old then
		old:Destroy()
	end
end

-- Returns a description of the camera positions for two close-up shots (4 clips each).
function AnimShowcase.show(): string
	AnimShowcase.clear()
	local player = Players.LocalPlayer
	local char = player.Character or player.CharacterAdded:Wait()
	local anims = (player:WaitForChild("PlayerScripts") :: any).Client:WaitForChild("Anims", 5)
	local folder = Instance.new("Folder")
	folder.Name = "AnimShowcase"
	folder.Parent = Workspace
	char.Archivable = true
	for i, item in AnimShowcase.LIST do
		local seq = anims:FindFirstChild(item[1])
		if not seq or not seq:IsA("KeyframeSequence") then
			warn("AnimShowcase: no clip " .. item[1])
			continue
		end
		local dummy = char:Clone()
		char.Archivable = true
		for _, d in dummy:GetDescendants() do
			if d:IsA("BaseScript") then
				d:Destroy()
			end
		end
		dummy.Name = item[1]
		local root = dummy:FindFirstChild("HumanoidRootPart")
		local hum = dummy:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not root or not root:IsA("BasePart") or not animator then
			dummy:Destroy()
			continue
		end
		root.Anchored = true
		-- Facing -X (left in a camera looking down -Z from +Z), so forward = left in the shot.
		dummy:PivotTo(
			CFrame.new(AnimShowcase.BASE + Vector3.new((i - 1) * AnimShowcase.SPACING, 0, 0))
				* CFrame.Angles(0, math.rad(90), 0)
		)
		dummy.Parent = folder
		local a = Instance.new("Animation")
		a.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
		local track = animator:LoadAnimation(a)
		track:Play(0)
		task.wait(0.05)
		track.TimePosition = item[2]
		track:AdjustSpeed(0)
	end
	char.Archivable = false
	local b, sp = AnimShowcase.BASE, AnimShowcase.SPACING
	return string.format(
		"characters face LEFT. shot A camera (%.1f, 5, %.1f) look (%.1f, 3, %.1f): clips 1-4 | shot B camera (%.1f, 5, %.1f) look (%.1f, 3, %.1f): clips 5-8",
		b.X + sp * 1.5,
		b.Z + 16,
		b.X + sp * 1.5,
		b.Z,
		b.X + sp * 5.5,
		b.Z + 16,
		b.X + sp * 5.5,
		b.Z
	)
end

return AnimShowcase
