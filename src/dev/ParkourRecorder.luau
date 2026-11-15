--!strict
-- Records the parkour controller while keys are pressed (Client, play mode). Usage:
--   local R = require(game:GetService("ReplicatedStorage").DevTools.ParkourRecorder) -- NOT a clone: start and stop share state
--   R.place(Vector3) -- put the character at a lane position, facing +X, camera behind
--   R.start()        -- then send keys with the keyboard tool
--   return R.stop()  -- report: moves with times, speeds, heights, wall-run times, landings
-- State lives in this module; require it without :Clone() so separate execute_luau calls share it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ParkourRecorder = {}
local active: any = nil

local function parts()
	local c = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
	return c, c:WaitForChild("HumanoidRootPart") :: BasePart, c:WaitForChild("Humanoid") :: Humanoid
end

function ParkourRecorder.place(pos: Vector3)
	local c, hrp, hum = parts()
	hrp.AssemblyLinearVelocity = Vector3.zero
	local legs = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else hum.HipHeight -- R6 reports HipHeight 0
	local stand = pos + Vector3.new(0, legs + hrp.Size.Y / 2 + 0.1, 0)
	hrp.CFrame = CFrame.lookAt(stand, stand + Vector3.new(1, 0, 0))
	local cam = Workspace.CurrentCamera
	cam.CFrame = CFrame.lookAt(stand + Vector3.new(-12, 5, 0), stand + Vector3.new(10, 0, 0))
	task.wait(0.6)
	return c:GetAttribute("ParkourSpeed")
end

function ParkourRecorder.start()
	local c, hrp = parts()
	local rec = {
		t0 = os.clock(),
		x0 = hrp.Position.X,
		y0 = hrp.Position.Y,
		events = {},
		maxSpeed = 0,
		maxY = hrp.Position.Y,
		wallRunStart = nil :: number?,
		wallRuns = {},
		lastCount = c:GetAttribute("ParkourMoveCount"),
	}
	active = rec
	rec.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - rec.t0
		local v = hrp.AssemblyLinearVelocity
		local hs = Vector3.new(v.X, 0, v.Z).Magnitude
		rec.maxSpeed = math.max(rec.maxSpeed, hs)
		rec.maxY = math.max(rec.maxY, hrp.Position.Y)
		local move = c:GetAttribute("ParkourMove")
		local count = c:GetAttribute("ParkourMoveCount")
		if count ~= rec.lastCount then
			rec.lastCount = count
			table.insert(
				rec.events,
				string.format(
					"%.2fs %s (x=%.1f y=%.1f speed=%s)",
					t,
					tostring(move),
					hrp.Position.X - rec.x0,
					hrp.Position.Y - rec.y0,
					tostring(c:GetAttribute("ParkourSpeed"))
				)
			)
		end
		local wr = c:GetAttribute("ParkourWallRun") == true
		if wr and not rec.wallRunStart then
			rec.wallRunStart = t
		elseif not wr and rec.wallRunStart then
			table.insert(rec.wallRuns, t - rec.wallRunStart)
			rec.wallRunStart = nil
		end
	end)
end

function ParkourRecorder.stop(): string
	local rec = active
	if not rec then
		return "not recording"
	end
	rec.conn:Disconnect()
	active = nil
	local c, hrp = parts()
	local wr = {}
	for _, d in rec.wallRuns do
		table.insert(wr, string.format("%.2fs", d))
	end
	return string.format(
		"moves: %s\nmax horizontal speed %.1f | highest point +%.1f | travelled x %.1f | wall runs: %s | speed now %s",
		#rec.events > 0 and table.concat(rec.events, "; ") or "none",
		rec.maxSpeed,
		rec.maxY - rec.y0,
		hrp.Position.X - rec.x0,
		#wr > 0 and table.concat(wr, ", ") or "none",
		tostring(c:GetAttribute("ParkourSpeed"))
	)
end

return ParkourRecorder
