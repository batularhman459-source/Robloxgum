--!strict
-- Plays the parkour animations (KeyframeSequences in the sibling Anims model, built from anim/specs).
-- Published game: each sequence needs an uploaded id in its AnimationId attribute.
-- Studio: sequences without one are registered locally (KeyframeSequenceProvider), no upload needed.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local ParkourAnims = {}
ParkourAnims.__index = ParkourAnims

local ids: { [string]: string } = {}
local folder = script.Parent:WaitForChild("Anims")
for _, seq in folder:GetChildren() do
	if seq:IsA("KeyframeSequence") then
		local id = seq:GetAttribute("AnimationId")
		if type(id) == "string" and id ~= "" then
			ids[seq.Name] = id
		elseif RunService:IsStudio() then
			ids[seq.Name] = KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
		end
	end
end

export type Player = typeof(setmetatable({} :: { tracks: { [string]: AnimationTrack } }, ParkourAnims))

-- Loads every clip on a character's Animator.
function ParkourAnims.new(hum: Humanoid): Player
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local tracks = {}
	for name, id in ids do
		local a = Instance.new("Animation")
		a.AnimationId = id
		tracks[name] = (animator :: Animator):LoadAnimation(a)
	end
	return setmetatable({ tracks = tracks }, ParkourAnims)
end

function ParkourAnims.play(self: Player, name: string, fade: number?)
	local t = self.tracks[name]
	if t and not t.IsPlaying then
		t:Play(fade or 0.08)
	end
end

function ParkourAnims.stop(self: Player, name: string, fade: number?)
	local t = self.tracks[name]
	if t and t.IsPlaying then
		t:Stop(fade or 0.12)
	end
end

function ParkourAnims.isLoaded(self: Player): number
	local n = 0
	for _ in self.tracks do
		n += 1
	end
	return n
end

return ParkourAnims
