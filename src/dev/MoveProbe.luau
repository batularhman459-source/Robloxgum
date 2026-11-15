--!strict
-- MoveProbe: measures the real character in play mode, so the map checks use real numbers instead
-- of guesses. Run on the Client (execute_luau, datamodel Client) while playing:
--   return require(game:GetService("ReplicatedStorage").DevTools.MoveProbe:Clone()).run()
-- It builds a private test lane far away (client-only parts), measures walk speed, jump height,
-- air time, step height, body size and eye height, then cleans up and puts the character back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MoveProbe = {}

local LANE = Vector3.new(0, 800, 3000)

local function part(parent: Instance, size: Vector3, pos: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function settle(hum: Humanoid, hrp: BasePart, timeout: number)
	local t0 = os.clock()
	repeat
		task.wait()
	until (hrp.AssemblyLinearVelocity.Magnitude < 0.5 and hum.FloorMaterial ~= Enum.Material.Air)
		or os.clock() - t0 > timeout
end

-- Root part height above the feet: HipHeight on R15, leg length on R6 (which reports HipHeight 0).
local function legs(hum: Humanoid): number
	return if hum.RigType == Enum.HumanoidRigType.R6 then 2 else hum.HipHeight
end

local function placeAt(hum: Humanoid, hrp: BasePart, floorPos: Vector3)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = CFrame.new(
		floorPos + Vector3.new(0, legs(hum) + hrp.Size.Y / 2 + 0.1, 0),
		floorPos + Vector3.new(1, legs(hum) + hrp.Size.Y / 2 + 0.1, 0)
	)
	settle(hum, hrp, 2)
end

function MoveProbe.run(): string
	local player = Players.LocalPlayer
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	local home = hrp.CFrame
	local rulesModule = ReplicatedStorage:WaitForChild("Rules"):WaitForChild("movement")
	local rules = require(rulesModule:Clone() :: ModuleScript) :: any

	local folder = Instance.new("Folder")
	folder.Name = "MoveProbeLane"
	folder.Parent = Workspace
	part(folder, Vector3.new(400, 2, 200), LANE - Vector3.new(0, 1, 0))
	local results: { string } = {}
	local measured: { [string]: number } = {}
	local function rec(key: string, value: number, how: string)
		measured[key] = value
		local cfg = rules[key]
		local cmp = ""
		if type(cfg) == "number" then
			local diff = value - cfg
			cmp = if math.abs(diff) <= math.max(0.05, math.abs(cfg) * 0.03)
				then string.format(" (config %s: matches)", tostring(cfg))
				else string.format(" (config %s: DIFFERS by %+.2f)", tostring(cfg), diff)
		end
		table.insert(results, string.format("- %s = %.2f [measured: play, %s]%s", key, value, how, cmp))
	end

	local ok, err = pcall(function()
		local floorY = LANE.Y
		placeAt(hum, hrp, LANE + Vector3.new(-150, 0, 0))

		-- Body size and eye height.
		local _, size = char:GetBoundingBox()
		rec("characterHeight", size.Y, "character bounding box height")
		rec("characterWidth", hrp.Size.X, "HumanoidRootPart width")
		local head = char:FindFirstChild("Head") :: BasePart?
		if head then
			rec("eyeHeight", head.Position.Y - floorY + hum.CameraOffset.Y, "head centre above floor + CameraOffset")
		end

		-- Walk speed: walk 80 studs, time the steady middle 40.
		local startX = hrp.Position.X
		hum:MoveTo(hrp.Position + Vector3.new(90, 0, 0))
		local t1, t2
		while true do
			RunService.Heartbeat:Wait()
			local d = hrp.Position.X - startX
			if not t1 and d >= 20 then
				t1 = os.clock()
			elseif t1 and d >= 60 then
				t2 = os.clock()
				break
			end
			if os.clock() - (t1 or os.clock()) > 10 then
				break
			end
		end
		if t1 and t2 then
			rec("walkSpeed", 40 / (t2 - t1), "time over 40 studs of steady walking")
		end
		hum:MoveTo(hrp.Position)
		settle(hum, hrp, 2)

		-- Jump: peak height and air time from a standstill.
		local baseY = hrp.Position.Y
		local peak = baseY
		local tStart = os.clock()
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		local leftGround = false
		local tLand = nil
		while os.clock() - tStart < 3 do
			RunService.Heartbeat:Wait()
			peak = math.max(peak, hrp.Position.Y)
			if hum.FloorMaterial == Enum.Material.Air then
				leftGround = true
			elseif leftGround then
				tLand = os.clock()
				break
			end
		end
		rec("jumpHeight", peak - baseY, "peak rise of the root part")
		if tLand then
			table.insert(results, string.format("- jump air time = %.3f s [measured: play]", tLand - tStart))
		end
		rec("gravity", Workspace.Gravity, "Workspace.Gravity")
		settle(hum, hrp, 2)

		-- Step height: walk into steps of rising height with jumping switched off.
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		local climbed = 0
		for i, h in { 0.5, 1, 1.5, 1.8, 2, 2.2, 2.5, 3 } do
			local z = -80 + i * 18
			local stepPos = LANE + Vector3.new(0, h / 2, z)
			local step = part(folder, Vector3.new(10, h, 10), stepPos)
			placeAt(hum, hrp, LANE + Vector3.new(-12, 0, z))
			hum:MoveTo(stepPos + Vector3.new(0, h / 2, 0))
			local t0 = os.clock()
			repeat
				task.wait()
			until os.clock() - t0 > 2.5 or (hrp.Position.Y - LANE.Y) > legs(hum) + hrp.Size.Y / 2 + h - 0.3
			local up = (hrp.Position.Y - LANE.Y) - (legs(hum) + hrp.Size.Y / 2)
			if up >= h - 0.3 then
				climbed = h
			end
			step:Destroy()
		end
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		rec("stepHeight", climbed, "highest step walked onto with jumping off (tested 0.5 to 3)")
	end)

	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	folder:Destroy()
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = home
	if not ok then
		table.insert(results, "- ERROR during measuring: " .. tostring(err))
	end
	MoveProbe.last = measured
	return "## Movement measured in play\n" .. table.concat(results, "\n")
end

return MoveProbe
