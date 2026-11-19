--!strict
-- Toolbox "Vaulting System" (Creator Store model by RasyidFZ (3366383258) and PurpleShade198 (9739741809),
-- inserted by the designer 2026-11-17), ported into the project with the same behaviour:
--   * jump near an obstacle in front: a hitbox finds the closest collidable part ahead;
--   * its top height picks the vault type (step / normal / high climb) and its clip;
--   * the character is held (rotation locked), the obstacle is anchored and made
--     non-collidable on this client, a velocity push fires shortly into the clip, and everything is
--     restored just before the clip ends.
-- Designer changes 2026-11-17: silent (the model's vault sound is gone), forward speed held for the whole
-- vault, the push also fires by distance to the obstacle (so the feet still clear it), and on exit ParkourController puts the body straight back into its sprint (no stop).
-- Changes from the model: numbers come from rules/vault.toml; the clips are this project's copies of the
-- model's KeyframeSequences (anim/r6/Clips.luau), because the model's Animation ids belong to another
-- account; strict types; the deprecated Blacklist filter is Exclude; it runs from StarterPlayerScripts and
-- sets itself up on every character (the model expected StarterCharacterScripts). ParkourController reads the
-- "Vaulting" attribute: it stays out of the way while it is true and takes over the speed when it ends.
local CollectionService = game:GetService("CollectionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local VaultMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VaultMath"))
local v = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("vault")) :: any
local parkourRules = require(ReplicatedStorage:WaitForChild("Rules"):WaitForChild("parkour")) :: any
local CameraKick = require(script.Parent:WaitForChild("CameraKick"))

local player = Players.LocalPlayer

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	local isVaulting = false
	local rotationConn: RBXScriptConnection? = nil
	character:SetAttribute("Vaulting", false)

	-- The clips: an uploaded id (AnimationId attribute on the sequence) when there is one, otherwise in
	-- Studio the sequence itself, registered locally (no upload needed to test).
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local clipFolder = (player:WaitForChild("PlayerScripts") :: any):WaitForChild("Client"):WaitForChild("Anims")
	local function loadClip(name: string): AnimationTrack?
		local seq = clipFolder:WaitForChild(name, 5)
		if not (seq and seq:IsA("KeyframeSequence")) then
			warn("Vault: no clip " .. name)
			return nil
		end
		local id = seq:GetAttribute("AnimationId")
		local animation = Instance.new("Animation")
		if type(id) == "string" and id ~= "" then
			animation.AnimationId = id
		elseif RunService:IsStudio() then
			animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
		else
			warn("Vault: clip " .. name .. " has no uploaded AnimationId yet")
			return nil
		end
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		return track
	end
	local VaultAnims: { [string]: AnimationTrack? } = {
		STEP = loadClip("StepVault"),
		NORMAL = loadClip("NormalVault"),
		HIGH = loadClip("HighClimb"),
	}

	local function lockRotation()
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + rootPart.CFrame.LookVector)
	end

	-- The closest collidable, vaultable part in a box in front of the character, roughly faced.
	local function getVaultTarget(): BasePart?
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local d = v.detect
		local boxCFrame = rootPart.CFrame * CFrame.new(0, d.hitboxUp, -d.forwardDistance / 2)
		local parts = Workspace:GetPartBoundsInBox(
			boxCFrame,
			Vector3.new(d.hitboxWidth, d.hitboxHeight, d.forwardDistance),
			params
		)
		local closest: BasePart? = nil
		local closestDist = math.huge
		for _, part in parts do
			if part.CanCollide and not CollectionService:HasTag(part, "Unvaultable") then
				local toPart = part.Position - rootPart.Position
				if rootPart.CFrame.LookVector:Dot(toPart.Unit) >= d.facingDot and toPart.Magnitude < closestDist then
					closest = part
					closestDist = toPart.Magnitude
				end
			end
		end
		return closest
	end

	local function performVault()
		if isVaulting or humanoid.FloorMaterial == Enum.Material.Air then
			return
		end
		local hitPart = getVaultTarget()
		if not hitPart then
			return
		end
		-- never vault other characters
		local model = hitPart:FindFirstAncestorWhichIsA("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return
		end

		-- Height of the top above the GROUND under the feet (fixes 2026-11-17: the model measured from the root
		-- part, 3 studs up on R6, so 2 stud ledges were never vaulted; and measuring from the feet let a 5 stud
		-- ledge through the 4.5 cap, because Space fires JumpRequest again a frame into the normal jump, with the
		-- feet already 0.9 up). No ground within detect.groundProbe below the feet: already in the air, no vault.
		local leg = character:FindFirstChild("Left Leg")
		local legLength = if humanoid.RigType == Enum.HumanoidRigType.R6
				and leg
				and leg:IsA("BasePart")
			then leg.Size.Y
			else humanoid.HipHeight
		local feetY = rootPart.Position.Y - rootPart.Size.Y / 2 - legLength
		local groundParams = RaycastParams.new()
		groundParams.FilterType = Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances = { character }
		local ground = Workspace:Raycast(
			rootPart.Position,
			Vector3.new(0, feetY - rootPart.Position.Y - v.detect.groundProbe, 0),
			groundParams
		)
		if not ground then
			return
		end
		local diff = hitPart.Position.Y + hitPart.Size.Y / 2 - ground.Position.Y
		if diff < v.detect.minHeight or diff > v.detect.maxHeight then
			return
		end
		local vaultType = if diff < v.types.stepBelow
			then "STEP"
			elseif diff < v.types.normalBelow then "NORMAL"
			else "HIGH"
		local anim = VaultAnims[vaultType]
		if not anim then
			return
		end

		isVaulting = true
		character:SetAttribute("Vaulting", true)
		local oldSpeed = humanoid.WalkSpeed
		local oldJump = humanoid.JumpHeight
		humanoid.JumpHeight = 0
		-- Each frame, right before physics: lock the rotation and hold a forward speed for the WHOLE vault
		-- (designer 2026-11-17: the vault must not kill momentum), eased by VaultMath.forwardSpeed: run-up speed,
		-- up to the push speed, back down to the sprint speed at the exit. WalkSpeed follows that speed instead
		-- of the model's 0: with 0 the Humanoid braked inside the physics step (playtest: 20 -> 0 in 2 frames
		-- before the push). Vertical speed is left to gravity, so the arc is still the push's own.
		local forwardDir = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		local entrySpeed = (rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
		humanoid.WalkSpeed = entrySpeed

		local wasAnchored = hitPart.Anchored
		local wasCollide = hitPart.CanCollide
		hitPart.Anchored = true
		hitPart.CanCollide = false

		-- The push: after push.delay, or earlier once the body is push.atDistance from the near face
		-- (src/shared/VaultMath.luau says why).
		local pushedAt: number? = nil
		local startedAt = os.clock()
		local endAt = math.huge -- set once the clip plays (below)
		-- Ease out to the sprint speed ParkourController will hand back (fix 2026-11-18: a vault out of a 45 slide
		-- eased to 45 and then dropped to the sprint in one frame).
		local sprint = character:GetAttribute("ParkourSpeed")
		local exitSpeed = VaultMath.exitSpeed(parkourRules, if type(sprint) == "number" then sprint else entrySpeed)
		local peakSpeed = entrySpeed
		local function push()
			pushedAt = os.clock()
			local p = v.push
			local forward, up
			if vaultType == "STEP" then
				forward, up = p.stepForward, p.stepUp
			elseif vaultType == "NORMAL" then
				forward, up = p.normalForward, p.normalUp
			else
				forward, up = p.highForward, p.highUp
			end
			peakSpeed = VaultMath.peakSpeed(forward, entrySpeed)
			CameraKick.kick("vault") -- designer 2026-11-19: camera that fits the wall run
			-- the forward part eases up from the run-up speed (below); the up kick is the push's own
			rootPart.AssemblyLinearVelocity = forwardDir * entrySpeed + Vector3.new(0, up, 0)
		end
		local function faceDistance(): number
			local look = rootPart.CFrame.LookVector
			local cf, size = hitPart.CFrame, hitPart.Size
			local half = VaultMath.halfExtent(
				{ look:Dot(cf.XVector), look:Dot(cf.YVector), look:Dot(cf.ZVector) },
				{ size.X, size.Y, size.Z }
			)
			return VaultMath.faceDistance((hitPart.Position - rootPart.Position):Dot(look), half)
		end

		local finished = false
		local function finish()
			if finished then
				return
			end
			finished = true
			anim:Stop()
			humanoid.WalkSpeed = oldSpeed
			humanoid.JumpHeight = oldJump
			if rotationConn then
				rotationConn:Disconnect()
				rotationConn = nil
			end
			hitPart.Anchored = wasAnchored
			hitPart.CanCollide = wasCollide
			isVaulting = false
			character:SetAttribute("Vaulting", false)
		end
		-- Is the body clear of the obstacle, so its collision can come back? (VaultMath.clearOf)
		local function clearOfObstacle(): boolean
			local look = rootPart.CFrame.LookVector
			local cf, size = hitPart.CFrame, hitPart.Size
			local half = VaultMath.halfExtent(
				{ look:Dot(cf.XVector), look:Dot(cf.YVector), look:Dot(cf.ZVector) },
				{ size.X, size.Y, size.Z }
			)
			local farAhead = (hitPart.Position - rootPart.Position):Dot(look) + half
			local feetNow = rootPart.Position.Y - rootPart.Size.Y / 2 - legLength
			return VaultMath.clearOf(farAhead, feetNow > hitPart.Position.Y + hitPart.Size.Y / 2, legLength)
		end

		rotationConn = RunService.PreSimulation:Connect(function()
			lockRotation()
			local now = os.clock()
			if not isVaulting then
				return
			end
			if VaultMath.canFinish(v, now - endAt, clearOfObstacle()) then
				finish()
				return
			end
			if not pushedAt and VaultMath.pushNow(v, now - startedAt, faceDistance()) then
				push()
				return
			end
			local speed = VaultMath.forwardSpeed(
				v,
				if pushedAt then now - pushedAt else -1,
				endAt - now,
				entrySpeed,
				peakSpeed,
				exitSpeed
			)
			humanoid.WalkSpeed = speed
			rootPart.AssemblyLinearVelocity = forwardDir * speed + Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
		end)
		anim:Play()
		-- A clip's Length reads 0 until it has loaded (playtest 2026-11-17: the first high climb of a session
		-- ended after 0.15 s in mid-air), so wait for it before timing the end.
		local waited = 0
		while anim.Length <= 0 and waited < 0.5 do
			waited += task.wait()
		end
		endAt = startedAt + anim.Length - v.push.endEarly

		-- The end is checked each frame above: at the clip's end, or a little later while the body is still over
		-- the obstacle (VaultMath.canFinish).
	end

	-- Keyboard, gamepad and mobile all raise JumpRequest.
	local jumpConn = UserInputService.JumpRequest:Connect(performVault)
	humanoid.Died:Connect(function()
		jumpConn:Disconnect()
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			jumpConn:Disconnect()
		end
	end)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
