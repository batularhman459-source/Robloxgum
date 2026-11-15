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
- Parkour moves: build `DevTools.ParkourLane` (Edit), then in play `DevTools.ParkourRecorder` (require it
  WITHOUT :Clone() so start/stop share state) + `user_keyboard_input` holding W and pressing Space / C.
  It drives the real controller like a player; read moves, speeds and heights from the report.
- Track moves with the ParkourMoveCount attribute, not the move name: two hard landings in a row
  have the same name and looked like "nothing happened".
- Humanoid.WalkSpeed = 0 makes MoveDirection read zero: never use it to mean "standing still".
- Wall-run tuning came from measuring: keeping the jump's upward speed climbed over a 14 stud wall;
  gravity 0.25 hit the floor after 0.5 s. Measure first, then change the rule number with a note.
- Keyboard timing through the tool jitters by ~0.1 s: give timing-window tests (rolls) some slack.
- Test the fix over time, not once: the first slide-spam fix still pulsed (+3.5 sawtooth every time
  speed hit base). A 10 s simulated-play test in Lune caught it before Studio did.
- Shrinking a character: CanCollide on Head/torso doesn't stick (the Humanoid forces it back every
  frame). Lower HipHeight + put the upper body in the SlideBody collision group (server-registered).
- Launching a character from the ground (vault): set HumanoidStateType.Freefall first. In Running
  the Humanoid snaps it back to the floor (vault landed in front of the box); Jumping adds the
  Humanoid's own 7.2 stud jump on top (vault peaked +7 over a 3 stud box).
- Judge animations on the real avatar: `DevTools.AnimShowcase` freezes every clip on clones in a row
  for one screenshot. The quick Blender previews were too small and grey to read, and they hid
  that body leans were inverted in game.
- After Studio restarts, the Rojo plugin is disconnected until Connect is clicked: new files simply
  don't show up. Check StarterPlayerScripts/ReplicatedStorage for them before testing.
- R6 reports HipHeight 0 (its 2 stud legs hold it up): anything measuring "feet" from HipHeight is
  2 studs off on R6 (the vault box read as 1 stud). Use Sensors.legLength.
- screen_capture sometimes ignores camera_position and BillboardGui labels don't show in captures:
  for animation checks, capture the real character mid-move (keyDown W, capture, keyUp).
- Animation smoothness: 5 poses with an ease each reads stiff (pose-to-pose). Good clips are dense
  curves (the designer's Sprint: 60 keys/s, Linear). Author few poses, then bake them (R6Pose.bake)
  with follow-through lag on head and arms. Study clips with `lune run tools/anim_dump <rbxm>`.
- Study a reference video at its real frame rate (ffmpeg fps=30, cropped, tiled): at 4 fps the
  speed vault looked like a forward dive; at 30 fps it was clearly a sideways vault onto one hand.
- Moving a character along a scripted path (vault): Humanoid in the Physics state, CFrame set every
  Heartbeat, ALL body parts out of world collision. In Physics the Humanoid turns collision on for
  arms and legs and physics pushed them up out of the box by 1.8 studs per step. Diagnose with
  PreSimulation vs PostSimulation positions: pre = where you put it, post = where physics moved it.
- One Space press also triggers the Humanoid's own jump: set Jump = false and disable the Jumping
  state while a scripted move uses the jump button.
- Ask the player to keep Output open (Fenster > Ausgabe in German Studio): the controller prints
  every move and every refusal reason in Studio, and the log survives stopping Play.
- Getting a clip out of Studio: the MCP can't save files, so dump the KeyframeSequence as JSON with execute_luau and rebuild it verbatim with `lune run tools/anim_from_json` (2026-11-15, Evade run).
- Frozen anchored clones (AnimShowcase-style, HRP at a fixed y) of a low, crouched clip look sunk into the floor; judge such a clip on the moving player before calling it broken (2026-11-15).
