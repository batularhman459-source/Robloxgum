--!strict
-- Parkour movement on the client. Each frame: measure (ParkourSensors), decide (Parkour.luau, pure and
-- tested), then move the character. Every number comes from rules/parkour.toml + rules/movement.toml.
-- Writes ParkourSpeed / ParkourMove / ParkourWallRun attributes on the character for playtests.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Rules = ReplicatedStorage:WaitForChild("Rules")
local p = require(Rules:WaitForChild("parkour")) :: any
local m = require(Rules:WaitForChild("movement")) :: any
local Parkour = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Parkour"))
local SlideMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlideMath"))
local SlideFeel = require(script.Parent:WaitForChild("SlideFeel"))
local FlipFeel = require(script.Parent:WaitForChild("FlipFeel"))
local CameraKick = require(script.Parent:WaitForChild("CameraKick"))
local SlideState = ReplicatedStorage:WaitForChild("SlideState") :: RemoteEvent -- src/server/SlideNet.server.luau
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
	local stunUntil = 0
	local slideUntil = 0
	local slideDir = Vector3.zero
	-- The slide's speed curve (SlideMath, designer spec 2026-11-17): burst, ease back to the sprint speed, slope
	-- momentum. nil when not sliding. Its look: SlideFeel (pose, camera, rock chips, wind trails).
	local slide: SlideMath.Slide? = nil
	local feel = SlideFeel.new(char, hum, hrp, true)
	local flip = FlipFeel.new(char, hum, hrp) -- the double jump's frontflip (designer 2026-11-18)
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { char }
	-- How much the ground under the body runs downhill along the slide (sin of the slope; - = uphill).
	local function downhill(): number
		-- down to just below the feet: the ground the slide is on
		local reach = hrp.Position.Y - sensors:feetY() + hrp.Size.Y / 2
		local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -reach, 0), groundParams)
		if not hit then
			return 0
		end
		return slideDir:Dot(Vector3.new(hit.Normal.X, 0, hit.Normal.Z))
	end

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
	local slideCollider: BasePart? = nil
	if hum.RigType == Enum.HumanoidRigType.R6 then
		local c = Instance.new("Part")
		c.Name = "SlideCollider"
		c.Size = Vector3.new(p.slide.colliderWidth, p.slide.colliderHeight, p.slide.colliderWidth)
		c.Transparency = 1
		c.CanCollide, c.CanQuery, c.CanTouch, c.Massless, c.CastShadow = false, false, false, true, false
		local floorY = -(hrp.Size.Y / 2 + sensors:legLength())
		c.CFrame = hrp.CFrame * CFrame.new(0, floorY + p.slide.colliderLift + p.slide.colliderHeight / 2, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = hrp, c
		weld.Parent = c
		c.Parent = char
		slideCollider = c
	end
	local low = false
	local function setLow(on: boolean)
		if on == low then
			return
		end
		low = on
		if feel then
			feel:set(on)
		end
		SlideState:FireServer(on) -- so the other players see the slide too
		-- R6 (2026-11-18): its only colliding parts are Torso and Head (taking them out of collision alone dropped
		-- the body through the world, measured), so a small collider low at the hips takes over while sliding:
		-- it holds the body up and still hits walls, and the slide fits under low gaps.
		if slideCollider then
			if on then
				slideCollider.CanCollide = true
			end
			for _, part in upperParts do
				part.CollisionGroup = if on then "SlideBody" else "Default"
			end
			if not on then
				slideCollider.CanCollide = false
			end
		elseif hum.RigType == Enum.HumanoidRigType.R15 then
			hum.HipHeight = if on then lowHip else standHip
			for _, part in upperParts do
				part.CollisionGroup = if on then "SlideBody" else "Default"
			end
		end
	end
	local lastJumpAt = 0
	local bufferedJumpAt: number? = nil

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

	-- The vault is the toolbox Vaulting System (src/client/Vault.client.luau): it sets the character's
	-- "Vaulting" attribute while it runs. This controller stays out of its way meanwhile, and handles a jump
	-- one step later so the vault script has seen the same press first.
	local function vaulting(): boolean
		return char:GetAttribute("Vaulting") == true
	end
	-- The wall run package (src/client/WallRun) sets "WallRunSide" while it runs.
	local function packageWallRun(): boolean
		return char:GetAttribute("WallRunSide") ~= nil
	end

	local function onJump()
		local now = os.clock()
		if now - lastJumpAt < JUMP_DEBOUNCE or now < stunUntil or vaulting() or packageWallRun() then
			return
		end
		-- The press that just jumped off a wall (the wall run package handles it) is not also a double jump: the
		-- double jump stays free for the next press (designer 2026-11-19).
		local wallJumpAt = char:GetAttribute("WallJumpAt")
		if type(wallJumpAt) == "number" and now - wallJumpAt < JUMP_DEBOUNCE then
			return
		end
		-- Space mid-slide: the slide jump, a jump out of the slide where there is room to stand up. No speed
		-- reward (designer 2026-11-18: remove the huge boost): you leave at the sprint speed, plus only what a
		-- downhill added, the same as a cancel.
		if slide and s.grounded and Parkour.canStandUp(m, sensors:headroom()) then
			lastJumpAt = now
			Parkour.carry(p, s, SlideMath.keepSpeed(slide))
			slide = nil
			slideUntil = now
			setLow(false)
			Parkour.applyMove(p, s, "slideJump")
			hrp.AssemblyLinearVelocity = slideDir * s.speed
				+ Vector3.new(0, Parkour.jumpVelocity(m, p.slide.jumpHeight), 0)
			hum.WalkSpeed = s.speed
			peakY = hrp.Position.Y
			setMove("slideJump")
			return
		end
		local kind = Parkour.jumpKind(p, s)
		if not kind then
			bufferedJumpAt = now -- maybe we land in time
			return
		end
		lastJumpAt = now
		local v = hrp.AssemblyLinearVelocity
		if kind == "doubleJump" then
			s.airJumpsUsed += 1
			Parkour.applyMove(p, s, "doubleJump")
			if flip then
				flip:play()
			end
			CameraKick.kick("flip")
			SlideState:FireServer("flip") -- other players see the flip too
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
	end
	local jumpConn = UserInputService.JumpRequest:Connect(function()
		task.defer(onJump)
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

		-- The toolbox vault moves the body itself: leave speed, animation and moves alone until it is done.
		if vaulting() or packageWallRun() then
			anims:stop("Run", 0.1)
			return
		end
		s.heightAboveGround = if grounded then 0 else sensors:heightAboveGround()

		-- Air time and landings.
		if grounded then
			if not wasGrounded then
				local fall = peakY - hrp.Position.Y
				local rollTiming = if slidePressedAt then now - slidePressedAt else nil
				local kind, speed = Parkour.landing(p, s, fall, rollTiming)
				CameraKick.kick("land", CameraKick.landScale(fall)) -- a soft dip, stronger from higher up
				if kind == "roll" then
					Parkour.applyMove(p, s, "landRoll")
					setMove("landRoll")
				elseif kind == "hard" then
					s.speed = math.max(speed, p.speed.base)
					stunUntil = now + p.landing.hardStun
					setMove("hardLanding")
				end
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

		-- The wall run is the "FREE R6 Wall Run" package (src/client/WallRun, designer 2026-11-19): hold Space near a
		-- wall in the air. It moves the body itself; this controller only keeps the momentum (WallRunSide / WallJumps
		-- attributes, below) and stays out of its way while it runs.

		-- Ground moves: slide, bonk.
		if grounded and now >= stunUntil then
			if slideRequested then
				slideRequested = false
				local current = slide
				if current then
					-- Slide cancel (designer 2026-11-18): C again pops you up into the sprint, where there is room to
					-- stand. No speed reward: you leave at the sprint speed, as if the slide had ended (gain.slideCancel).
					if SlideMath.canCancel(p, current) and Parkour.canStandUp(m, sensors:headroom()) then
						Parkour.carry(p, s, SlideMath.keepSpeed(current)) -- a slope's speed only, no cancel reward
						Parkour.applyMove(p, s, "slideCancel")
						slide = nil
						slideUntil = now
						if feel then
							feel:cancel()
						end
						setLow(false)
						hum.WalkSpeed = s.speed
						hrp.AssemblyLinearVelocity = slideDir * s.speed
							+ Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
						setMove("slideCancel")
					elseif logMoves then
						print(string.format("[Parkour] cancel refused (%.2fs into the slide)", current.t))
					end
				elseif Parkour.canSlide(p, s) then
					s.sinceSlide = 0
					slideUntil = now + p.slide.maxDuration
					slideDir = if moving then moveDir else Sensors.flat(hrp.CFrame.LookVector)
					local entry = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
					setLow(true)
					Parkour.applyMove(p, s, "slide")
					slide = SlideMath.new(entry, s.speed)
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
			-- Pressed just before landing: keep it, it slides on touchdown (designer 2026-11-19: after a wall jump and
			-- a double jump you could not slide right when you landed; the press in the air was thrown away).
			local buffered = not grounded and Parkour.slideBuffered(p, slidePressedAt, now)
			if slideRequested and not buffered and logMoves then
				print(
					if grounded
						then "[Parkour] slide refused (stunned after a hard landing)"
						else "[Parkour] slide pressed too early in the air (counts as a roll press)"
				)
			end
			if not buffered then
				slideRequested = false
			end
		end

		-- Slide physics: burst, ease back to the sprint speed, slopes. Ends by SlideMath.done, or off an edge;
		-- the speed it ends with carries into the sprint (capped at speed.max).
		local current = slide
		if current then
			local d = downhill()
			SlideMath.step(p, current, dt, d)
			if SlideMath.done(p, current, d) or (not grounded and s.timeSinceGrounded > p.jump.coyoteTime) then
				Parkour.carry(p, s, SlideMath.keepSpeed(current))
				slide = nil
				slideUntil = now
			end
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
		elseif slide then
			hum.WalkSpeed = slide.speed
			hum:Move(slideDir, false)
		elseif now < slideUntil then
			hum.WalkSpeed = s.speed -- still low under a ceiling: keep going at the sprint speed
			hum:Move(slideDir, false)
		else
			-- Always the momentum speed: with no input the Humanoid stands still anyway. (WalkSpeed 0 made
			-- MoveDirection read zero, so the controller never saw the player start moving.)
			hum.WalkSpeed = s.speed
		end
		-- Run clip (the designer's Evade run, imported 2026-11-15) at Movement priority, above Roblox's
		-- default run. It plays at 1x at the base speed and speeds up with momentum.
		if grounded and moving and not low and now >= stunUntil then
			anims:play("Run", 0.12)
			anims:setSpeed("Run", Parkour.runAnimSpeed(p, s.speed))
		else
			anims:stop("Run", 0.12)
		end

		char:SetAttribute("ParkourSpeed", math.floor(s.speed * 10 + 0.5) / 10)
		char:SetAttribute("ParkourSliding", now < slideUntil)
	end)

	-- Vault done: straight back into the sprint, no stop (designer 2026-11-17). The vault counts as a move
	-- (gain.vault, keeps the flow alive), and the body leaves at the sprint speed along its facing, so the
	-- Humanoid has nothing to brake. Fall height counts from here, so the vault's own arc is no hard landing.
	-- Only a real end (true -> false): the vault script also sets false once at spawn, which logged a fake vault.
	local wasVaulting = vaulting()
	local vaultEndConn = char:GetAttributeChangedSignal("Vaulting"):Connect(function()
		local was = wasVaulting
		wasVaulting = vaulting()
		if not was and wasVaulting then
			-- A vault during a slide cuts the slide at once (designer 2026-11-18): no exit motion, so the vault's
			-- own animation plays, never the vault inside the slide pose. The slide's speed is the vault's entry.
			if slide or low then
				slide = nil
				slideUntil = os.clock()
				if feel then
					feel:interrupt()
				end
				SlideState:FireServer("cut")
				setLow(false)
			end
			return
		end
		if not was or wasVaulting or hum.Health <= 0 then
			return
		end
		local look = Sensors.flat(hrp.CFrame.LookVector)
		local chainBonus = Parkour.afterVault(p, s)
		if logMoves and chainBonus > 0 then
			print(string.format("[Parkour] vault chain x%d: +%.1f", s.vaultChain, chainBonus))
		end
		setMove("vault")
		hum.WalkSpeed = s.speed
		hrp.AssemblyLinearVelocity = look * s.speed + Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		peakY = hrp.Position.Y
		bufferedJumpAt = nil
	end)

	-- Momentum from the wall run package: a run and a wall jump count as moves, a run gives the double jump back,
	-- and fall height counts from where you leave the wall.
	local wallRunConn = char:GetAttributeChangedSignal("WallRunSide"):Connect(function()
		local running = packageWallRun()
		char:SetAttribute("ParkourWallRun", running)
		peakY = hrp.Position.Y
		if running then
			s.airJumpsUsed = 0
			Parkour.applyMove(p, s, "wallRun")
			-- at once: the package reads it for its run speed, and this controller's Heartbeat pauses during the run
			char:SetAttribute("ParkourSpeed", math.floor(s.speed * 10 + 0.5) / 10)
			setMove("wallRun")
		end
	end)
	local wallJumpConn = char:GetAttributeChangedSignal("WallJumps"):Connect(function()
		peakY = hrp.Position.Y
		Parkour.applyMove(p, s, "wallJump")
		char:SetAttribute("ParkourSpeed", math.floor(s.speed * 10 + 0.5) / 10)
		setMove("wallJump")
	end)

	local function disconnectAll()
		jumpConn:Disconnect()
		stepConn:Disconnect()
		vaultEndConn:Disconnect()
		wallRunConn:Disconnect()
		wallJumpConn:Disconnect()
		if feel then
			feel:destroy()
		end
		if flip then
			flip:destroy()
		end
	end
	hum.Died:Connect(disconnectAll)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			disconnectAll()
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
