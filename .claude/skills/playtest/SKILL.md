---
name: playtest
description: One-command playtest in Roblox Studio. Runs the 5 gates, starts play, runs a scripted movement test, collects numbers (positions, distances, timings, FPS, errors) and screenshots, stops play and reports. Use when the user says playtest, test in Studio, or /playtest. Optional args: a list of waypoints "x,y,z; x,y,z" or instance paths.
---

# Playtest

Run these steps in order. Stop and report on the first hard failure.

## 1. Gates
Run `.\scripts\check.ps1`. If any gate fails, stop: report which one and why. Don't start play.

## 2. Find Studio
`list_roblox_studios`. Use the one with this place open (ask if there are several). Then `get_studio_state`.
If it is already in play mode, `start_stop_play` with `is_start: false` first.

## 3. Start play
`start_stop_play` with `is_start: true`. Poll `get_studio_state` until the `Client` datamodel is available.
Then wait for the character with `execute_luau` (Client):
```lua
local p = game:GetService("Players").LocalPlayer
local c = p.Character or p.CharacterAdded:Wait()
local hrp = c:WaitForChild("HumanoidRootPart", 10)
return hrp and tostring(hrp.Position) or "NO CHARACTER"
```
Record the spawn position.

## 4. Baseline screenshot
`screen_capture` with `capture_id: "Playtest_Start"`.

## 5. Scripted movement test
Waypoints: from the args, otherwise a square around spawn: (+20,0,0), (+20,0,+20), (0,0,+20), back to spawn.
Time is measured **inside Studio**, from the moment the character starts moving until it stops,
so tool-call delay never counts as walking time.

For each waypoint:
1. Arm a watcher with `execute_luau` (Client), filling in the target:
   ```lua
   local TARGET = Vector3.new(X, Y, Z)
   local RunService = game:GetService("RunService")
   local c = game:GetService("Players").LocalPlayer.Character
   local hrp, hum = c.HumanoidRootPart, c.Humanoid
   if _G.__ptConn then _G.__ptConn:Disconnect() end
   local r = { moveStart = nil, moveEnd = nil, armed = os.clock() }
   _G.__pt = r
   _G.__ptConn = RunService.Heartbeat:Connect(function()
   	local speed = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
   	if not r.moveStart and speed > 1 then r.moveStart = os.clock() end
   	if r.moveStart and speed < 0.5 then r.moveEnd = os.clock() end
   	if r.moveStart and speed >= 0.5 then r.moveEnd = nil end
   	if os.clock() - r.armed > 30 then _G.__ptConn:Disconnect() end
   end)
   return "armed"
   ```
2. `character_navigation` (Client) to the point (or `instance_path`), `speed_multiplier: 1`.
3. Read the result with `execute_luau` (Client):
   ```lua
   local TARGET = Vector3.new(X, Y, Z)
   local c = game:GetService("Players").LocalPlayer.Character
   local p, hum, r = c.HumanoidRootPart.Position, c.Humanoid, _G.__pt
   if _G.__ptConn then _G.__ptConn:Disconnect() end
   local flatOff = ((p - TARGET) * Vector3.new(1, 0, 1)).Magnitude
   local walk = if r.moveStart then (r.moveEnd or os.clock()) - r.moveStart else -1
   return string.format("reached=%.1f,%.1f,%.1f off=%.1f walk_s=%.2f state=%s hp=%d",
   	p.X, p.Y, p.Z, flatOff, walk, hum:GetState().Name, hum.Health)
   ```
   `off` ignores height, because the target Y is the root part and the character stands lower.
   `walk_s = -1` means it never started moving.
4. A waypoint fails if `off` > 4 studs, `walk_s` > 15, or `walk_s` = -1.
After the last waypoint, `screen_capture` with `capture_id: "Playtest_End"`.

## 6. Numbers
`execute_luau` (Client):
```lua
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")
local frames, t0 = 0, os.clock()
local conn = RunService.RenderStepped:Connect(function() frames += 1 end)
task.wait(2)
conn:Disconnect()
return string.format("fps=%.1f mem_mb=%.0f ping_ms=%.0f",
	frames / (os.clock() - t0), Stats:GetTotalMemoryUsageMb(),
	game:GetService("Players").LocalPlayer:GetNetworkPing() * 1000)
```
Studio throttles FPS when its window is in the background. Under 30 fps, say so and note that it
is probably throttling, not a real problem, unless the user had Studio in front.
Then `get_console_output`: count errors and warnings and keep the first 5 of each, plus the
`[Server]` / `[Client]` startup lines.

## 7. Stop
Always `start_stop_play` with `is_start: false`, even when an earlier step failed.

## 8. Report
Give a short report:
- Verdict: PASS / FAIL (and the first failure reason).
- Gates: 5/5.
- Table: waypoint | target | reached | off by (studs) | time (s) | ok.
- fps, memory, ping.
- Errors/warnings with counts and the first lines.
- Screenshots: Playtest_Start, Playtest_End.
Don't fix anything during the playtest. List what looks wrong and ask before changing anything.

## Lessons (add one every time something is noticed; keep the why)
- Time walking inside Studio (Heartbeat watcher), never across tool calls: tool delay showed up as
  a 16.7 s "walk" that really took 1.5 s.
- FPS reads ~15 when Studio is in the background (Roblox throttles it): not a real problem.
- `rbxassetid://203785492 Asset type does not match` warnings come from Roblox/avatar, not our code.
