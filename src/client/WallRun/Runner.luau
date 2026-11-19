--!strict
-- The "FREE R6 Wall Run" package by SKATER STUDIOS (designer 2026-11-19: "use this instead of yours"), ported from a
-- StarterCharacterScripts LocalScript to a module that sets itself up on each character (src/client/WallRun/init).
-- Behaviour is the package's, except the controls (designer 2026-11-19): you stick to a wall on contact in the air,
-- press jump to jump off, a run lasts up to run.maxDuration. Changes from the package, each marked "PORT:":
--   * numbers come from rules/wallrun.toml (Modules/Config);
--   * clips are this project's uploads of the package's own KeyframeSequences (Client.Anims, anim/r6/Clips.luau);
--   * the run uses the momentum speed (the ParkourSpeed attribute) instead of a fixed 30;
--   * the field of view zoom is added on top of the speed field of view (SpeedFeel sets it fresh every frame) instead
--     of resetting it to a stored base;
--   * it tells ParkourController what it does: the "WallRunSide" attribute while running, "WallJumps" counts jumps.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = script.Parent:WaitForChild("Modules")
local Packages = script.Parent:WaitForChild("Packages")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Config = require(Modules:WaitForChild("Config"))
local Raycaster = require(Modules:WaitForChild("Raycaster"))
local Trails = require(Modules:WaitForChild("Trails"))
local Sounds = require(Modules:WaitForChild("Sounds"))
local Trove = require(Packages:WaitForChild("Trove"))
local Signal = require(Packages:WaitForChild("Signal"))
local Shake = require(Packages:WaitForChild("Shake"))
local Spring = require(Packages:WaitForChild("Spring"))
local PID = require(Packages:WaitForChild("PID"))
local Log = require(Packages:WaitForChild("Log"))

local Logger = Log.new()

local function Info(Message: string)
	Logger:AtInfo():Log(Message:lower())
end

local function Warn(Message: string)
	Logger:AtWarning():Log(Message:lower())
end

local LocalPlayer = Players.LocalPlayer

-- PORT: one wall runner per character (the package lived inside the character as script.Parent).
local function Run(Character: Model)
	local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
	local RootPart = Character:WaitForChild("HumanoidRootPart") :: BasePart
	local Animator = Humanoid:WaitForChild("Animator") :: Animator
	local Camera = workspace.CurrentCamera :: Camera

	local MainTrove = Trove.new()
	local RunTrove = MainTrove:Extend()
	local WallRaycaster = Raycaster.new(Character)
	local LimbTrails = MainTrove:Construct(Trails, Character, Config.TrailLimbs) :: Trails.Trails
	local SoundPlayer = MainTrove:Construct(Sounds, RootPart, Config.Sounds) :: Sounds.Sounds

	local WallRunStarted = MainTrove:Construct(Signal) :: Signal.Signal<Raycaster.Side>
	local WallRunEnded = MainTrove:Construct(Signal) :: Signal.Signal<boolean>
	local WallJumped = MainTrove:Construct(Signal) :: Signal.Signal<Raycaster.Side>

	-- PORT (designer 2026-11-19): no holding. You stick to the wall on contact and press jump to jump off. After a run
	-- times out (the cap), a fresh jump press is needed to stick again, or you would re-stick the same instant.
	local NeedsJump = false
	local IsRunning = false
	local CurrentSide: Raycaster.Side = "Left"
	local RunStartTime = 0
	local LastRunEndTime = -math.huge
	local LastWallNormal = Vector3.zAxis
	local LastTangent = Vector3.zAxis
	local RunVelocity: LinearVelocity? = nil
	local RunOrientation: AlignOrientation? = nil

	local SnapPID = MainTrove:Add(
		PID.new(-Config.MaxSnapCorrection, Config.MaxSnapCorrection, Config.SnapKp, Config.SnapKi, Config.SnapKd)
	)

	local TangentSpring = Spring.new(Vector3.zAxis, Config.TangentSmoothTime, Config.TangentSmoothMaxSpeed)
	local CorrectionSpring = Spring.new(Vector3.zero, Config.CorrectionSmoothTime, Config.CorrectionSmoothMaxSpeed)

	local TiltSpring = Spring.new(0, Config.CameraTiltSmoothTime, Config.CameraTiltMaxSpeed)
	local FovSpring = Spring.new(0, Config.FovSmoothTime, Config.FovMaxSpeed)

	local ShakeTrove = MainTrove:Extend()

	local function ShakeCamera(
		Amplitude: number,
		Frequency: number,
		FadeOutTime: number,
		PositionInfluence: Vector3,
		RotationInfluence: Vector3
	)
		ShakeTrove:Clean()

		local CameraShake = Shake.new()
		CameraShake.Amplitude = Amplitude
		CameraShake.Frequency = Frequency
		CameraShake.FadeInTime = 0
		CameraShake.FadeOutTime = FadeOutTime
		CameraShake.PositionInfluence = PositionInfluence
		CameraShake.RotationInfluence = RotationInfluence
		CameraShake:Start()
		CameraShake:BindToRenderStep(
			Shake.NextRenderName(),
			Enum.RenderPriority.Last.Value,
			function(Position, Rotation)
				Camera.CFrame = Camera.CFrame * CFrame.new(Position) * CFrame.Angles(Rotation.X, Rotation.Y, Rotation.Z)
			end
		)
		ShakeTrove:Add(CameraShake)
	end

	local function ShakeCameraForWallJump()
		ShakeCamera(
			Config.ShakeAmplitude,
			Config.ShakeFrequency,
			Config.ShakeFadeOutTime,
			Config.ShakePositionInfluence,
			Config.ShakeRotationInfluence
		)
	end

	local function NormalizeName(Name: string): string
		local Normalized = Name:lower():gsub("[^%w]", "")
		return Normalized
	end

	-- PORT: the package's clips, uploaded under this account; in Studio the sequence itself is registered if needed.
	local ClipFolder = (LocalPlayer:WaitForChild("PlayerScripts") :: any):WaitForChild("Client"):WaitForChild("Anims")
	local CLIP_NAMES = {
		wallrunleft = "WallRunLeft",
		wallrunright = "WallRunRight",
		walljumpleft = "WallJumpLeft",
		walljumpright = "WallJumpRight",
	}

	local function LoadAnimation(WantedName: string, Priority: Enum.AnimationPriority, Looped: boolean): AnimationTrack?
		local ClipName = CLIP_NAMES[NormalizeName(WantedName)]
		local Sequence = ClipName and ClipFolder:WaitForChild(ClipName, 5)
		if not (Sequence and Sequence:IsA("KeyframeSequence")) then
			Warn(`missing animation "{WantedName}"`)
			return nil
		end
		local Id = Sequence:GetAttribute("AnimationId")
		local Anim = Instance.new("Animation")
		if type(Id) == "string" and Id ~= "" then
			Anim.AnimationId = Id
		elseif RunService:IsStudio() then
			Anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(Sequence)
		else
			Warn(`"{WantedName}" has no uploaded AnimationId`)
			return nil
		end
		local Success, Result = pcall(function()
			return Animator:LoadAnimation(Anim)
		end)
		if not Success then
			Warn(`failed to load animation "{WantedName}": {Result}`)
			return nil
		end
		local Track = Result :: AnimationTrack
		Track.Priority = Priority
		Track.Looped = Looped
		return Track
	end

	-- PORT: the run's speed is the momentum speed (ParkourController's ParkourSpeed attribute).
	local function RunSpeed(): number
		local Speed = Character:GetAttribute("ParkourSpeed")
		return if type(Speed) == "number" and Speed > 0 then Speed else Config.WallRunSpeed
	end

	local RunTracks: { [string]: AnimationTrack? } = {
		Left = LoadAnimation("Wall Run Left", Enum.AnimationPriority.Action, true),
		Right = LoadAnimation("Wall Run Right", Enum.AnimationPriority.Action, true),
	}

	local JumpTracks: { [string]: AnimationTrack? } = {
		Left = LoadAnimation("Wall Jump Left", Enum.AnimationPriority.Action2, false),
		Right = LoadAnimation("Wall Jump Right", Enum.AnimationPriority.Action2, false),
	}

	local function PlayTrack(Track: AnimationTrack?, Label: string)
		if not Track then
			Warn(`cannot play {Label}, track is nil`)
			return
		end

		Track:Play(Config.AnimationFadeTime)

		if Track.Length == 0 then
			Warn(`{Label} has no keyframes (length 0), nothing will move on screen`)
		end
	end

	local function BindStepMarker(Track: AnimationTrack?, Label: string)
		if not Track then
			Warn(`cannot bind step marker for {Label}, track is nil`)
			return
		end

		-- PORT: a footstep on every Config.StepEvery-th marker (designer 2026-11-19: the steps were overwhelming)
		local Steps = 0
		MainTrove:Connect(Track:GetMarkerReachedSignal("Step"), function()
			Steps += 1
			if Steps % Config.StepEvery == 0 then
				SoundPlayer:Play("Step")
			end
		end)
	end

	BindStepMarker(RunTracks.Left, "Run.Left")
	BindStepMarker(RunTracks.Right, "Run.Right")

	local TiltBindName = "WallrunCameraTilt"

	-- PORT: one step after SpeedFeel (Camera + 1), which sets the field of view fresh every frame.
	RunService:BindToRenderStep(TiltBindName, Enum.RenderPriority.Camera.Value + 2, function(DeltaTime: number)
		if IsRunning then
			TiltSpring.Target = if CurrentSide == "Right" then Config.CameraTiltAngle else -Config.CameraTiltAngle
		else
			TiltSpring.Target = 0
		end

		FovSpring.Target = if IsRunning then -Config.FovZoomAmount else 0

		local Tilt = TiltSpring:Update(DeltaTime)
		local FovOffset = FovSpring:Update(DeltaTime)

		if math.abs(Tilt) > 0.01 then
			Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, math.rad(Tilt))
		end

		-- PORT: added on top of the speed field of view, never reset to a stored base.
		if math.abs(FovOffset) > 0.01 then
			Camera.FieldOfView = math.clamp(Camera.FieldOfView + FovOffset, 1, 120)
		end
	end)

	MainTrove:Add(function()
		RunService:UnbindFromRenderStep(TiltBindName)
	end)

	local function ComputeTangent(WallNormal: Vector3): Vector3
		local FlatNormal = Vector3.new(WallNormal.X, 0, WallNormal.Z)
		if FlatNormal.Magnitude < 1e-3 then
			return RootPart.CFrame.LookVector
		end

		local Tangent = FlatNormal.Unit:Cross(Vector3.yAxis)
		if Tangent:Dot(RootPart.CFrame.LookVector) < 0 then
			Tangent = -Tangent
		end

		return Tangent.Unit
	end

	local function SnapTarget(Hit: Raycaster.WallHit): Vector3
		local Point = Hit.Position + Hit.Normal * Config.WallSnapDistance
		return Vector3.new(Point.X, RootPart.Position.Y, Point.Z)
	end

	local function EndRun(Jumped: boolean)
		if not IsRunning then
			return
		end

		IsRunning = false
		LastRunEndTime = os.clock()

		local Track = RunTracks[CurrentSide]
		if Track then
			Track:Stop(Config.AnimationFadeTime)
		end

		Info(`wall run ended ({if Jumped then "jumped" else "fell"})`)

		RunTrove:Clean()
		RunVelocity = nil
		RunOrientation = nil
		Character:SetAttribute("WallRunSide", nil) -- PORT: tells ParkourController

		WallRunEnded:Fire(Jumped)
	end

	local function WallJump()
		-- PORT: lets ParkourController ignore this same jump press (it is the wall jump, not a double jump)
		Character:SetAttribute("WallJumpAt", os.clock())
		local Side = CurrentSide
		local Normal = LastWallNormal
		local Tangent = LastTangent

		EndRun(true)

		RootPart.AssemblyLinearVelocity = Normal * Config.WallJumpAwayForce
			+ Vector3.new(0, Config.WallJumpUpForce, 0)
			+ Tangent * (RunSpeed() * Config.WallJumpForwardKeep)

		Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		Character:SetAttribute("WallJumps", ((Character:GetAttribute("WallJumps") :: number?) or 0) + 1) -- PORT

		PlayTrack(JumpTracks[Side], `Jump.{Side}`)

		WallJumped:Fire(Side)
	end

	local function StartRun(Hit: Raycaster.WallHit)
		IsRunning = true
		CurrentSide = Hit.Side
		RunStartTime = os.clock()
		LastWallNormal = Hit.Normal
		LastTangent = ComputeTangent(Hit.Normal)
		SnapPID:Reset()
		TangentSpring:Reset(LastTangent)
		CorrectionSpring:Reset(Vector3.zero)

		Info(`wall run started ({Hit.Side})`)

		Humanoid.AutoRotate = false
		RunTrove:Add(function()
			Humanoid.AutoRotate = true
		end)

		local OriginalWalkSpeed = Humanoid.WalkSpeed
		Humanoid.WalkSpeed = 0
		Humanoid:Move(Vector3.zero, false)
		RunTrove:Add(function()
			Humanoid.WalkSpeed = OriginalWalkSpeed
		end)

		local OriginalCanCollide: { [BasePart]: boolean } = {}
		for _, Descendant in Character:GetDescendants() do
			if Descendant:IsA("BasePart") then
				OriginalCanCollide[Descendant] = Descendant.CanCollide
				Descendant.CanCollide = false
			end
		end

		RunTrove:Add(function()
			for Part, WasCollidable in OriginalCanCollide do
				if Part.Parent then
					Part.CanCollide = WasCollidable
				end
			end
		end)

		local Target = SnapTarget(Hit)
		local TargetCFrame = CFrame.lookAt(Target, Target + LastTangent)
		RootPart.CFrame = TargetCFrame
		RootPart.AssemblyLinearVelocity = LastTangent * RunSpeed()

		local RunAttachment = RunTrove:Construct(Instance, "Attachment") :: Attachment
		RunAttachment.Name = "WallrunAttachment"
		RunAttachment.Parent = RootPart

		local Velocity = RunTrove:Construct(Instance, "LinearVelocity") :: LinearVelocity
		Velocity.Attachment0 = RunAttachment
		Velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		Velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		Velocity.ForceLimitsEnabled = false
		Velocity.MaxForce = math.huge
		Velocity.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
		Velocity.VectorVelocity = LastTangent * RunSpeed()
		Velocity.Parent = RootPart
		RunVelocity = Velocity

		local Orientation = RunTrove:Construct(Instance, "AlignOrientation") :: AlignOrientation
		Orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		Orientation.Attachment0 = RunAttachment
		Orientation.MaxTorque = math.huge
		Orientation.MaxAngularVelocity = math.huge
		Orientation.Responsiveness = Config.OrientationResponsiveness
		Orientation.CFrame = TargetCFrame
		Orientation.Parent = RootPart
		RunOrientation = Orientation

		Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

		PlayTrack(RunTracks[CurrentSide], `Run.{CurrentSide}`)
		Character:SetAttribute("WallRunSide", CurrentSide) -- PORT: tells ParkourController

		WallRunStarted:Fire(CurrentSide)
	end

	local function CanStartRun(): boolean
		if IsRunning or NeedsJump then
			return false
		end

		if os.clock() - LastRunEndTime < Config.ReattachCooldown then
			return false
		end

		if Config.RequireAirborneToStart and WallRaycaster:IsNearGround(Config.MinStartHeight) then
			return false
		end

		local State = Humanoid:GetState()

		return Humanoid.Health > 0
			and not Humanoid.Sit
			and not Humanoid.PlatformStand
			and State ~= Enum.HumanoidStateType.Swimming
			and State ~= Enum.HumanoidStateType.Climbing
			and State ~= Enum.HumanoidStateType.Dead
	end

	local function UpdateRun(DeltaTime: number)
		local Elapsed = os.clock() - RunStartTime

		local Hit = WallRaycaster:CheckSide(CurrentSide)
		if not Hit then
			EndRun(false)
			return
		end

		if Config.MaxRunDuration > 0 and Elapsed >= Config.MaxRunDuration then
			NeedsJump = true -- PORT: the cap; jump again to stick again (no cooldown)
			EndRun(false)
			return
		end

		if Elapsed > Config.GroundGraceTime and WallRaycaster:IsNearGround(Config.GroundCheckDistance) then
			EndRun(false)
			return
		end

		LastWallNormal = Hit.Normal

		local RawTangent = ComputeTangent(Hit.Normal)
		TangentSpring.Target = RawTangent
		local SmoothedTangent = TangentSpring:Update(DeltaTime)
		LastTangent = if SmoothedTangent.Magnitude > 1e-4 then SmoothedTangent.Unit else RawTangent

		local FlatNormal = Vector3.new(Hit.Normal.X, 0, Hit.Normal.Z)
		local PullDirection = if FlatNormal.Magnitude > 1e-3 then FlatNormal.Unit else Vector3.zero

		local Setpoint = PullDirection:Dot(SnapTarget(Hit))
		local ProcessVariable = PullDirection:Dot(RootPart.Position)
		local RawCorrection = PullDirection * SnapPID:Calculate(Setpoint, ProcessVariable, DeltaTime)
		CorrectionSpring.Target = RawCorrection
		local SmoothedCorrection = CorrectionSpring:Update(DeltaTime)

		if RunVelocity then
			RunVelocity.VectorVelocity = LastTangent * RunSpeed()
				+ Vector3.new(0, Config.WallRunVerticalSpeed, 0)
				+ SmoothedCorrection
		end

		if RunOrientation then
			RunOrientation.CFrame = CFrame.lookAt(RootPart.Position, RootPart.Position + LastTangent)
		end
	end

	local WallRunContext = MainTrove:Construct(Instance, "InputContext") :: InputContext
	WallRunContext.Name = "WallrunContext"
	WallRunContext.Enabled = true
	WallRunContext.Parent = script

	local WallRunAction = Instance.new("InputAction")
	WallRunAction.Name = "WallRun"
	WallRunAction.Type = Enum.InputActionType.Bool
	WallRunAction.Parent = WallRunContext

	local KeyboardBinding = Instance.new("InputBinding")
	KeyboardBinding.Name = "Keyboard"
	KeyboardBinding.KeyCode = Enum.KeyCode.Space
	KeyboardBinding.Parent = WallRunAction

	local GamepadBinding = Instance.new("InputBinding")
	GamepadBinding.Name = "Gamepad"
	GamepadBinding.KeyCode = Enum.KeyCode.ButtonA
	GamepadBinding.Parent = WallRunAction

	if UserInputService.TouchEnabled then
		task.spawn(function()
			local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
			local TouchGui = PlayerGui:WaitForChild("TouchGui", 10)
			if not TouchGui then
				return
			end

			local JumpButton = TouchGui:FindFirstChild("JumpButton", true)
			if JumpButton and JumpButton:IsA("GuiButton") then
				local TouchBinding = Instance.new("InputBinding")
				TouchBinding.Name = "Touch"
				TouchBinding.UIButton = JumpButton
				TouchBinding.Parent = WallRunAction
			else
				Warn("touchgui found but no jumpbutton inside, mobile wall run will not trigger")
			end
		end)
	end

	-- PORT: press jump while running to jump off; any other jump press lets you stick again after a capped run.
	MainTrove:Connect(WallRunAction.Pressed, function()
		if IsRunning then
			WallJump()
		else
			NeedsJump = false
		end
	end)

	MainTrove:Connect(RunService.Heartbeat, function(DeltaTime: number)
		if
			LimbTrails.Active
			and os.clock() - LimbTrails.BurstTime > Config.TrailGroundGrace
			and WallRaycaster:IsNearGround(Config.GroundCheckDistance)
		then
			LimbTrails:Stop()
		end

		if IsRunning then
			UpdateRun(DeltaTime)
			return
		end

		-- PORT: back on the ground, sticking needs no new press
		if NeedsJump and WallRaycaster:IsNearGround(Config.GroundCheckDistance) then
			NeedsJump = false
		end

		if not CanStartRun() then
			return
		end

		local Hit = WallRaycaster:FindWall()
		if not Hit then
			return
		end

		StartRun(Hit)
	end)

	MainTrove:Connect(WallJumped, function(Side: Raycaster.Side)
		TiltSpring:Impulse(if Side == "Right" then -Config.CameraJumpTiltImpulse else Config.CameraJumpTiltImpulse)
		FovSpring:Impulse(Config.FovJumpImpulse)
		ShakeCameraForWallJump()
		LimbTrails:Burst(Config.TrailDuration)
	end)

	Humanoid.Died:Once(function()
		EndRun(false)
		MainTrove:Destroy()
	end)

	-- PORT: the character can also be removed without dying (respawn, leaving).
	MainTrove:Connect(Character.AncestryChanged, function(_, Parent)
		if not Parent then
			EndRun(false)
			MainTrove:Destroy()
		end
	end)

	Info("wallrun ready")
end

return Run
