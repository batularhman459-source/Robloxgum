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
-- R6: run cycle at its 4 beats, then the vault at its 4 beats.
AnimShowcase.LIST = {
	{ "Run", 0.0 },
	{ "Run", 0.1 },
	{ "Run", 0.2 },
	{ "Run", 0.3 },
	{ "Vault", 0.08 },
	{ "Vault", 0.2 },
	{ "Vault", 0.32 },
	{ "Vault", 0.44 },
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
		-- Label above each clone so screenshots identify themselves.
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(110, 26)
		tag.StudsOffset = Vector3.new(0, 3.2, 0)
		tag.AlwaysOnTop = true
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 0.3
		text.BackgroundColor3 = Color3.new(0, 0, 0)
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextScaled = true
		text.Text = string.format("%d %s %.2f", i, item[1], item[2])
		text.Parent = tag
		tag.Adornee = root
		tag.Parent = dummy
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
