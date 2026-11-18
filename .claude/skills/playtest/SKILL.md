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
- Clones placed with PivotTo sink 1.5 studs: an R6 model pivots at the head, not the root (roblox-animation trap 42); place by HumanoidRootPart.CFrame instead (2026-11-15).
- hum:Move() from execute_luau is overridden by the PlayerModule every frame (character stays put): drive tests with user_keyboard_input (W + Space) and log from a Heartbeat connection into attributes, read back in a later call (2026-11-15).
- screen_capture right after keyboard input can show a stale frame; trust the logged numbers, capture only frozen poses (2026-11-15).
- Keyboard W moves relative to the CAMERA: set workspace.CurrentCamera.CFrame behind the character facing the target before sending W, or the run goes sideways and Space just jumps (2026-11-15).
- After a gates run, confirm the change reached Studio (read a new rule value / Source in Edit, wait for it) BEFORE starting play: one vault test ran the old code because Rojo synced just after play started (2026-11-15).
- A rigid R6 arm reaches 1.5 from the shoulder joint: any procedural hand plant caps how high the body may pass over the plant point (vault bodyLift 0.7 left the hand 0.46 in the air; 0.3 = 0.1). Measure the hand end vs the target in play, never assume (2026-11-15).
- A move clip must follow the BODY, not a clock: drive it with TimePosition from path progress (Parkour.vaultClipTime) and sync marks; a clip only sped to the move's length put the hand plant and leg sweep at the wrong place on every obstacle (2026-11-17).
- Where Space is pressed decides the timing: pressed 1.66 from a ledge the legs had ~4 frames to clear it. A take-off point + approach phase gives every vault the same geometry (2026-11-17).
- Humanoid:ChangeState(Physics) is not visible to GetState() in the same Heartbeat: a state check right after starting a move aborted every vault started from Heartbeat (2026-11-17).
- Snap detector: max per-frame rotation of each limb relative to the root, logged in play. Baseline a plain run first (R6 Evade run: 23-27 deg/frame at speed 20) before calling a number a snap (2026-11-17).
- A tilted R6 limb is a block: its lower edge sits half its thickness * the tilt below the end point. Aim and clearance checks on the end point alone let a hand corner sink 0.3-0.4 into a ledge (2026-11-17).
- Studio test helpers made with execute_luau (ModuleScripts in ReplicatedStorage) are not Rojo-managed: delete them after the test (2026-11-17).
- A sine-shaped jump arc eases INTO the ground and reads as floating: use a ballistic parabola (fastest at take-off and touchdown) and carry its touchdown speed into the fall (2026-11-17).
- R6 vault styles are limited by rigid limbs: a head-first dive needs the hands (1.5 reach) near the top, so the arc stays low; straight trailing legs swing down THROUGH the ledge, a straddle keeps them beside it; and the hard fall must start only once past the far face (hang ends fallClear past it), measured 2026-11-17.
- Toolbox/free movement scripts often set WalkSpeed 0 and then push the root: the Humanoid brakes that push to zero within ~6 frames. Hold the push's horizontal velocity each frame instead; and check what they measure heights from (root part = 3 studs up on R6) (2026-11-17).
- Holding a velocity from RenderStepped does not survive WalkSpeed 0: the Humanoid brakes inside the physics step (20 -> 0 in 2 frames). Set it in PreSimulation AND set WalkSpeed to the held speed. Keeping run-up speed also moves a timed push closer to the obstacle, so re-measure body clearance after any momentum change (2026-11-17).
- Speed changes that snap in one frame (20 -> 60 -> 22) read as choppy even when the totals are right: ease the push up (ease-out) and the exit down (smoothstep) and check the biggest frame-to-frame change in the log, not just the speeds. Easing costs distance, so a short clip can end over its obstacle: end only once the body is clear, with a cap (2026-11-17).
- One Space press can fire JumpRequest again a frame into the normal jump: anything measured from the feet then reads 0.9 studs low (a 5 stud ledge passed a 4.5 cap). Measure heights from a ground raycast, not the current feet. And turn a vaulted obstacle solid again only a leg length past its far face: 'feet above the top' snagged the trailing legs on its back edge (2026-11-17).
- Procedural R6 poses (C0 lerp + fading Transform in PreSimulation) are judged in phases: the full pose can clear the floor while the blend does not, because the body drop and the limb swing share one weight. Give limbs a lead and the root drop a lag, and compare against plain running (R6 run legs already dip ~0.4 into the floor) (2026-11-17).
- Never store Motor6D C0 at spawn to restore later: the server's CharacterShape narrowing replicates after the client's scripts start, so 'restoring' put the arms back at the old wide spot (visible gaps). Pose through Transform (the animation channel) instead; it is also the channel any client can drive for every character (2026-11-17).
- R6 has no knees, so any frame where the body is dropped needs the legs swung out front: leaning the torso forward while low (or swinging a leg from behind to in front while the body drops) puts the legs into the floor. Check every keyed transition with FK on the real rig (lowest leg corner per sampled t), not just the end poses (2026-11-17).
- After Studio restarts, check Rojo is connected before any playtest (compare a fresh rules value in the Edit DM with the file): the first 2026-11-18 run tested the old slide because rojo serve was not running (2026-11-18).
- To remove a speed boost, zeroing the gain is not enough: check every hand-off that carries a MEASURED speed into the sprint (the vault's eased push was still at 23 when it ended, so a 20 run-up left at 23). Log ParkourSpeed for ~1 s after the move (2026-11-18).
- Two scripts writing Camera.FieldOfView fight (each snapping it back to its own base). One owner sets it fresh every frame (SpeedFeel, Camera+1); others ADD on top one render step later (SlideFeel, Camera+2) (2026-11-18).
- A move that starts during another (vault during a slide) must cut the first one's procedural pose at once: its exit blend would otherwise draw over the new animation. Check torso drop at the switch frame (1.45 -> 0.00) (2026-11-18).
- R6 needs a colliding part to stand: moving Torso + Head to a no-world collision group dropped the body through the map (HRP y 4 -> -217 in 1.5 s). For slide-under-gaps weld a small low collider and switch it on first (2026-11-18).
- Never call CharacterAdded:Wait() in execute_luau when the character may already exist: it hangs the call, it timed out and Studio's MCP connection dropped (2026-11-18).
- A 2 stud box is walk-over height for R6 (the Humanoid steps up anything near leg height), so 'did the wall stop the slide' needs a real wall (8 studs) (2026-11-18).
