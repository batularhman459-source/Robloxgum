--!strict
-- Parkour movement on the client. Each frame: measure (ParkourSensors), decide (Parkour.luau, pure and
-- tested), then move the character. Every number comes from rules/parkour.toml + rules/movement.toml.
-- Writes ParkourSpeed / ParkourMove / ParkourWallRun attributes on the character for playtests.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Rules = ReplicatedStorage:WaitForChild("Rules")
local p = require(Rules:WaitForChild("parkour")) :: any
local m = require(Rules:WaitForChild("movement")) :: any
local Parkour = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Parkour"))
local Sensors = require(script.Parent:WaitForChild("ParkourSensors"))
local ParkourAnims = require(script.Parent:WaitForChild("ParkourAnims"))
local UiRuntime = require(script.Parent:WaitForChild("UiRuntime"))

local player = Players.LocalPlayer
local JUMP_DEBOUNCE = 0.18 -- input debounce, not a gameplay number
local slideRequested = false
local slidePressedAt: number? = nil

local function onCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	local sensors = Sensors.new(char, hrp, hum, p)
	local anims = ParkourAnims.new(hum)
	local s = Parkour.newState(p)

	hum.UseJumpPower = false
	hum.JumpHeight = m.jumpHeight
	hum.MaxSlopeAngle = m.maxSlopeAngle

	local wasGrounded = true
	local peakY = hrp.Position.Y
	local wallSide = 0
	local wallVy = 0
	local stunUntil = 0
	local slideUntil = 0
	local slideDir = Vector3.zero

	-- Real slide: hips down so the body fits under slide.height, upper body out of world collision.
	local standHip = hum.HipHeight
	local lowHip = Parkour.slideHipHeight(p, hrp.Size.Y)
	local upperParts: { BasePart } = {}
	for _, name in { "Head", "UpperTorso", "Torso" } do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(upperParts, part)
		end
	end
	local low = false
	local function setLow(on: boolean)
		if on == low then
			return
		end
		low = on
		-- R15 only for now: R6 ignores HipHeight (it would raise the body) and its only colliding parts
		-- are Torso and Head, so removing them from collision would drop it through the floor. The R6
		-- slide-under-gaps (a small low collider) is a planned rebuild.
		if hum.RigType == Enum.HumanoidRigType.R15 then
			hum.HipHeight = if on then lowHip else standHip
			for _, part in upperParts do
				part.CollisionGroup = if on then "SlideBody" else "Default"
			end
		end
	end
	local lastJumpAt = 0
	local bufferedJumpAt: number? = nil

	-- Vault: the body follows Parkour.vaultOffset over the obstacle while the Vault clip plays, timed
	-- to the same duration. Colliding parts leave world collision for the vault (the path is measured
	-- to clear the obstacle), and the Humanoid is put in its Physics state so it can't fight the path.
	local vault: any = nil
	-- ALL body parts: in the Physics state the Humanoid turns collision on for arms and legs too, and
	-- they got pushed up out of the box by up to 1.8 studs each physics step (measured 2026-11-15).
	local collidingParts: { BasePart } = {}
	for _, part in char:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(collidingParts, part)
		end
	end

	local moveCount = 0
	local logMoves = RunService:IsStudio() -- Studio only: the Output log survives stopping Play
	local function setMove(name: string)
		moveCount += 1
		char:SetAttribute("ParkourMove", name)
		char:SetAttribute("ParkourMoveCount", moveCount) -- lets playtests see repeats of the same move
		if logMoves then
			print(string.format("[Parkour] %s speed=%.1f", name, s.speed))
		end
	end

	local function stopWallRun()
		if s.wallRunning then
			s.wallRunning = false
			s.sinceLeftWall = 0
		end
		char:SetAttribute("ParkourWallRun", false)
	end

	local function startVault(dir: Vector3, ob: any)
		local plan = Parkour.vaultPlan(p, s, ob, sensors:legLength())
		vault = { t0 = os.clock(), plan = plan, start = hrp.Position, dir = dir }
		if logMoves then
			print(
				string.format(
					"[Parkour] vault plan: obstacle top %.2f, %.2f away, depth %.2f, legs %.2f -> distance %.2f, rise %.2f, peakAt %.2f, %.2fs",
					ob.topHeight,
					ob.distance,
					ob.depth,
					sensors:legLength(),
					plan.distance,
					plan.rise,
					plan.peakAt,
					plan.duration
				)
			)
		end
		s.sinceVault = 0
		Parkour.applyMove(p, s, "vault")
		for _, part in collidingParts do
			part.CollisionGroup = "SlideBody"
		end
		-- The same Space press also asks the Humanoid for its own jump: cancel it and block jumping
		-- for the vault (playtest: the body went +3.4 up where the path only rises 1.5).
		hum.Jump = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		anims:stop("Run", 0.05)
		anims:play("Vault", 0.05)
		anims:setSpeed("Vault", anims:length("Vault", plan.duration) / plan.duration)
		setMove("vault")
	end

	local function endVault()
		for _, part in collidingParts do
			part.CollisionGroup = "Default"
		end
		local dir = vault.dir
		vault = nil
		hum.Jump = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		hrp.AssemblyLinearVelocity = dir * s.speed
	end

	local jumpConn = UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		if now - lastJumpAt < JUMP_DEBOUNCE or now < stunUntil or vault then
			return
		end
		-- Vault check: an obstacle close ahead (only on the ground; vaulting is never automatic).
		local vaultReady, vaultDir, vaultOb = false, Vector3.zero, nil
		if s.grounded then
			local md = Sensors.flat(hum.MoveDirection)
			vaultDir = if md.Magnitude > 0.1 then md else Sensors.flat(hrp.CFrame.LookVector)
			vaultOb = sensors:obstacle(vaultDir)
			local ok, why = Parkour.canVault(p, s, vaultOb)
			vaultReady = ok
			if logMoves and vaultOb and not ok then
				print(
					string.format(
						"[Parkour] vault refused: %s (top %.1f, %.1f away, depth %.1f)",
						why,
						vaultOb.topHeight,
						vaultOb.distance,
						vaultOb.depth
					)
				)
			end
		end
		local kind = Parkour.jumpKind(p, s, vaultReady)
		if not kind then
			bufferedJumpAt = now -- maybe we land in time
			return
		end
		lastJumpAt = now
		local v = hrp.AssemblyLinearVelocity
		if kind == "vault" then
			startVault(vaultDir, vaultOb)
		elseif kind == "wallJump" then
			local wall = sensors:wall(wallSide)
			local normal = if wall
				then wall.normal
				else {
					x = -sensors.flat(hrp.CFrame.RightVector).X * wallSide,
					z = -sensors.flat(hrp.CFrame.RightVector).Z * wallSide,
				}
			local look = Sensors.flat(hrp.CFrame.LookVector)
			local runDir = Parkour.wallRunDirection({ x = look.X, z = look.Z }, normal)
			stopWallRun()
			s.lastWallId = if wall then wall.id else s.lastWallId
			Parkour.applyMove(p, s, "wallJump")
			local h, up = Parkour.wallJumpVelocity(p, m, s, runDir, normal)
			hrp.AssemblyLinearVelocity = Vector3.new(h.x, up, h.z)
			setMove("wallJump")
		elseif kind == "doubleJump" then
			s.airJumpsUsed += 1
			Parkour.applyMove(p, s, "doubleJump")
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, Parkour.jumpVelocity(m, p.jump.doubleJumpHeight), v.Z)
			peakY = hrp.Position.Y
			setMove("doubleJump")
		elseif kind == "jump" and not s.grounded then
			-- Coyote jump: the Humanoid won't jump in the air, so launch it ourselves.
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, Parkour.jumpVelocity(m, m.jumpHeight), v.Z)
			s.timeSinceGrounded = math.huge
			setMove("jump")
		else
			setMove("jump") -- normal ground jump: the Humanoid does it
		end
	end)

	local stepConn = RunService.Heartbeat:Connect(function(dt)
		if hum.Health <= 0 then
			return
		end
		local now = os.clock()
		local grounded = hum.FloorMaterial ~= Enum.Material.Air
		local moveDir = Sensors.flat(hum.MoveDirection)
		local moving = moveDir.Magnitude > 0.1

		s.sinceSlide += dt
		s.sinceVault += dt
		s.sinceLeftWall += dt

		-- During a vault the body follows the planned path; nothing else runs.
		if vault then
			local t = (now - vault.t0) / vault.plan.duration
			if t >= 1 then
				endVault()
			else
				local fwd, up = Parkour.vaultOffset(vault.plan, t)
				local pos = vault.start + vault.dir * fwd + Vector3.new(0, up, 0)
				hrp.CFrame = CFrame.lookAt(pos, pos + vault.dir)
				hrp.AssemblyLinearVelocity = vault.dir * (vault.plan.distance / vault.plan.duration)
				char:SetAttribute("ParkourSpeed", math.floor(s.speed * 10 + 0.5) / 10)
				return
			end
		end
		s.heightAboveGround = if grounded then 0 else sensors:heightAboveGround()

		-- Air time and landings.
		if grounded then
			if not wasGrounded then
				local fall = peakY - hrp.Position.Y
				local rollTiming = if slidePressedAt then now - slidePressedAt else nil
				local kind, speed = Parkour.landing(p, s, fall, rollTiming)
				if kind == "roll" then
					Parkour.applyMove(p, s, "landRoll")
					setMove("landRoll")
				elseif kind == "hard" then
					s.speed = math.max(speed, p.speed.base)
					stunUntil = now + p.landing.hardStun
					setMove("hardLanding")
				end
				stopWallRun()
				if bufferedJumpAt and now - bufferedJumpAt <= p.jump.jumpBuffer then
					hum.Jump = true
				end
				bufferedJumpAt = nil
			end
			s.timeSinceGrounded = 0
			s.airJumpsUsed = 0
			peakY = hrp.Position.Y
		else
			s.timeSinceGrounded += dt
			peakY = math.max(peakY, hrp.Position.Y)
		end
		s.grounded = grounded
		wasGrounded = grounded

		Parkour.decay(p, s, dt)

		-- Wall run: keep going or end.
		if s.wallRunning then
			local wall = sensors:wall(wallSide)
			if Parkour.wallRunEnds(p, s, wall, grounded) then
				if wall then
					s.lastWallId = wall.id
				end
				stopWallRun()
			else
				s.wallRunTime += dt
				local look = if moving then moveDir else Sensors.flat(hrp.CFrame.LookVector)
				local dir = Parkour.wallRunDirection({ x = look.X, z = look.Z }, wall.normal)
				wallVy = math.max(wallVy - m.gravity * p.wallRun.gravityFactor * dt, -p.wallRun.maxSlideDownSpeed)
				-- Hold the body at the wall: small pull towards it so it doesn't drift off.
				local pull = -0.5
				hrp.AssemblyLinearVelocity =
					Vector3.new(dir.x * s.speed + wall.normal.x * pull, wallVy, dir.z * s.speed + wall.normal.z * pull)
			end
		elseif not grounded and moving then
			local wall = sensors:anyWall()
			local ok = Parkour.canWallRun(p, s, wall, { x = moveDir.X, z = moveDir.Z })
			if ok and wall then
				s.wallRunning, s.wallRunTime = true, 0
				wallSide = wall.side
				-- Keep a little of the jump's rise, never the whole launch (first playtest climbed over a 14 stud wall).
				wallVy = math.clamp(hrp.AssemblyLinearVelocity.Y, 0, p.wallRun.entryUpSpeed)
				Parkour.applyMove(p, s, "wallRun")
				char:SetAttribute("ParkourWallRun", true)
				setMove("wallRun")
			end
		end

		-- Ground moves: slide, vault, bonk.
		if grounded and now >= stunUntil then
			if slideRequested then
				slideRequested = false
				if Parkour.canSlide(p, s) then
					s.sinceSlide = 0
					slideUntil = now + p.slide.duration
					slideDir = if moving then moveDir else Sensors.flat(hrp.CFrame.LookVector)
					setLow(true)
					Parkour.applyMove(p, s, "slide")
					setMove("slide")
				elseif logMoves then
					print(string.format("[Parkour] slide refused (speed %.1f, cooldown %.2fs)", s.speed, s.sinceSlide))
				end
			end
			if moving and now >= slideUntil and sensors:bonkWall(moveDir) and s.speed > p.speed.base + 0.5 then
				Parkour.bonk(p, s)
				setMove("bonk")
			end
		else
			if slideRequested and logMoves then
				print(
					if grounded
						then "[Parkour] slide refused (stunned after a hard landing)"
						else "[Parkour] slide pressed in the air (counts as a roll press)"
				)
			end
			slideRequested = false
		end

		-- Slide time up: stand only where there is room, otherwise stay low and keep sliding.
		if low and now >= slideUntil then
			if Parkour.canStandUp(m, sensors:headroom()) then
				setLow(false)
			else
				slideUntil = now + dt
			end
		end

		-- Speed: auto-sprint at the momentum speed; stunned = stop; sliding = locked direction.
		if now < stunUntil then
			hum.WalkSpeed = 0
		elseif now < slideUntil then
			hum.WalkSpeed = s.speed
			hum:Move(slideDir, false)
		else
			-- Always the momentum speed: with no input the Humanoid stands still anyway. (WalkSpeed 0 made
			-- MoveDirection read zero, so the controller never saw the player start moving.)
			hum.WalkSpeed = s.speed
		end
		-- Our run cycle replaces Roblox's default run (it plays at Movement priority, above the default
		-- Animate script) and speeds up with momentum.
		local running = grounded and moving and not low and now >= stunUntil
		if running then
			anims:play("Run", 0.12)
			anims:setSpeed("Run", s.speed / p.speed.base)
		else
			anims:stop("Run", 0.12)
		end

		char:SetAttribute("ParkourSpeed", math.floor(s.speed * 10 + 0.5) / 10)
		char:SetAttribute("ParkourSliding", now < slideUntil)
	end)

	hum.Died:Connect(function()
		jumpConn:Disconnect()
		stepConn:Disconnect()
	end)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			jumpConn:Disconnect()
			stepConn:Disconnect()
		end
	end)
end

-- Slide input: keyboard C / Left Ctrl, gamepad B, mobile button (UI spec MobileControls).
local function requestSlide()
	slideRequested = true
	slidePressedAt = os.clock()
end
ContextActionService:BindAction("ParkourSlide", function(_, state)
	if state == Enum.UserInputState.Begin then
		requestSlide()
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)

if UserInputService.TouchEnabled then
	local gui = UiRuntime.mount("MobileControls")
	local button = gui and gui:FindFirstChild("SlideButton", true)
	local face = button and button:FindFirstChild("Face")
	if face and face:IsA("GuiButton") then
		face.Activated:Connect(requestSlide)
	end
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
