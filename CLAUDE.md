# RobloxGame: house rules

Read this first every session. Keep it short. Update it when a rule changes.

## Folder layout
```
rules/            Game numbers (damage, costs, cooldowns) as TOML. Plain numbers + comments only.
                  Rojo syncs each file to ReplicatedStorage.Rules.<name> as a table.
src/shared/       Pure logic (formulas). NO requires, NO Roblox services/globals.
                  Rules are passed in as arguments, so Lune can test it. -> ReplicatedStorage.Shared
src/server/       Server scripts (*.server.luau) and server modules. -> ServerScriptService.Server
src/client/       Client scripts (*.client.luau) and UI. -> StarterPlayer.StarterPlayerScripts.Client
src/shared/ui/     UiLayout (layout engine, defaults) + UiBuilder (builds instances). Pure, env passed in.
ui/specs/         UI specs: plain data, one file per screen. -> ReplicatedStorage.UI.Specs
ui/themes/        UI themes (TOML): Depth Stack, layout limits, palette. -> ReplicatedStorage.UI.Themes
ui/icons.toml     icon name = Roblox asset id. ui/icons/*.png = the images.
ui/STYLES.md      Style library. Read it before designing any UI.
src/shared/map/    MapGraph (walk/jump/fall graph, reach, traps, routes) + MapMath. Pure, tested.
src/shared/Movement.luau  Jump/fall/walk physics from rules/movement.toml.
src/dev/          Studio dev tools -> ReplicatedStorage.DevTools: MapProbe (9 map checks), MoveProbe
                  (real movement in play), TestCourse (map with planted flaws). Always require a :Clone().
maps/             models/*.py (Blender model scripts), budgets.toml, STYLES.md, briefs/, reports/.
tools/            Lune tools: ui.luau (build/check), UiCheck, Preview. icon.ps1 (FLUX icons).
                  mesh.ps1 + blender/ (build, optimise, budget check, render meshes).
tests/            Lune tests: *.spec.luau, run by tests/run.luau. tests/fixtures = test data.
scripts/check.ps1 The 5 gates.
build/, ui/build/ Generated, gitignored.
```

## The 5 gates (must pass before anything touches Studio)
```
.\scripts\check.ps1        # check
.\scripts\check.ps1 -Fix   # reformat with StyLua, then check
```
1. Rojo build  2. Lune tests  3. Selene lint  4. StyLua format check  5. UI checker.
If a gate fails, fix the cause. Never skip a gate, never weaken a test or lint rule to pass.
Tools are pinned in rokit.toml (Rojo, Selene, StyLua, Lune). They live in ~/.rokit/bin.

## Naming and style
- Files: PascalCase modules (`Combat.luau`), `Name.server.luau` / `Name.client.luau` for scripts.
  Rules files: lowercase (`combat.toml`). Keys: camelCase (`baseDamage`).
- `--!strict` at the top of every src file. Typed function signatures.
- Use `game:GetService()`, never `game.Workspace`-style service access.
- Formatting is whatever StyLua outputs (tabs, 120 columns, double quotes). Don't hand-format.
- Small modules, one job each. No global state in shared/.

## Design rules
- **Every tunable number lives in rules/.** No magic numbers for damage, costs, speeds, cooldowns in src/.
- **Logic goes in src/shared and gets a test** in tests/. Server/client scripts only wire things up.
- **The server is the authority.** The client asks, the server checks and decides (damage, currency,
  purchases). Validate every RemoteEvent argument on the server (type, range, rate limit).
- Add a rules sanity check in tests/rules.spec.luau for every new rules file.
- Tests read numbers from the rules files (`t.rules("x")`), never hard-code a rule value: two map tests
  broke when walkSpeed went from 16 to 20 because they had 16 baked in.
- Rules that must agree (movement.walkSpeed = parkour speed.base, rollMaxHeight = maxSafeFall) get a test.
- DataStores: always pcall, retry with backoff, save on PlayerRemoving and BindToClose.

## UI
**From a spec, always deliver 3 things, all from one source** (`ui/specs/<Name>.luau` + theme):
1. Preview image: `lune run tools/ui build <Name>` -> `ui/build/<Name>.preview.png` (4 screen sizes).
2. The UI file: same command -> `ui/build/<Name>.rbxm`.
3. The build script: `UiBuilder` + `src/client/UiMount.client.luau` build it in game (mount = false
   in the spec = code opens it later). Never hand-build UI in Studio, never edit the .rbxm.
Preview and checker use `UiLayout`, the builder uses `UiLayout.resolve`: verified 0px apart in Studio.
**Scaling:** design at scale 1 (phone/laptop pixels). The whole UI scales with the screen via
`UiLayout.scaleFor` ([scale] in the theme: 1 up to 1.5, ~1.4 on Full HD), applied by UiMount on resize.
The checker measures real scaled pixels. Don't add per-element scaling or TextScaled.
Show the user the preview PNG before calling a UI done.

**Depth Stack** on every panel and button (UiBuilder adds it, don't build it by hand):
1. shadow shifted blue  2. gradient on the face  3. lift (white sheen from the top)
4. outline with ONE thickness everywhere (`depth.strokeThickness`). No other stroke widths, ever.

**Checker** (gate 5, `tools/UiCheck.luau`), on Phone 844x390, Tablet 1180x820, Laptop 1366x768, Full HD 1920x1080:
screens (fits, clear of top bar), thumb (buttons >= 44px), spacing (nothing within 6px of anything,
incl. outline + shadow; text fits; contrast), centre (almost-centred within 8px must be within 1.5px),
tiny (text >= 14px, no empty panels/groups, no box < 16px), separator (no "•", "·", "|", " - " joins:
use separate labels). Fix the spec, never loosen a limit to pass.

**Spec rules:** kinds = panel, button, text, icon, group. pos/size = {scaleX, offsetX, scaleY, offsetY}.
Colors only by palette name. Unknown keys are rejected. Names unique per spec.

**Icons:** never emojis or random asset ids. `.\tools\icon.ps1 -Name coin -Subject "a shiny gold coin"`
makes one with FLUX (Cloudflare Workers AI), cuts the background, uploads it, writes ui/icons.toml.
Needs `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `ROBLOX_API_KEY` env vars. Keep the shared
style prompt in icon.ps1 so every icon matches. Check the PNG before using it.

**Style library:** every reference design the user sends: recreate it as spec + theme, adapt it to
these rules, then add an entry to `ui/STYLES.md` (template inside). Use STYLES.md for every new UI.

## Maps
Use the `map` skill (.claude/skills/map). Maps are spaces players move through: reach, way back,
sight lines, falls and A-to-B times are measured by MapProbe (raycasts + rules/movement.toml), never
eyeballed. All 9 checks pass before a map is done. Every number has a source, every guess is listed.
Meshes come from Blender scripts through `tools/mesh.ps1`; nothing over its triangle budget is imported.

## SyphoDev skill pack (installed in ~/.claude/skills, source C:\Users\ghada\Documents\roblox-ai-skills)
In THIS project our own pipelines are the source of truth:
- UI: our `ui` skill + tools/ui.luau + UiCheck (not roblox-ui).
- Maps: our `map` skill + MapProbe (not roblox-map). Port good checks from roblox-map into MapProbe instead.
- Code: our layout and 5 gates (not roblox-code's Knit scaffold).
Use the pack for what we don't have: roblox-vfx, roblox-sfx, roblox-animation, roblox-texture-gen,
roblox-3d-model (image/text to mesh; still run our mesh budget check before import),
roblox-market-scout agent, and create-roblox-game for brand-new projects in Documents\RobloxGames.
Its env vars: CF_ACCOUNT_ID / CF_API_TOKEN (copies of CLOUDFLARE_*), ROBLOX_USER_ID, ROBLOX_GAMES_HOME,
ROBLOX_VFX_LIB, BLENDER. Python 3.12 is at %LOCALAPPDATA%\Programs\Python\Python312\python.exe.
Uploads through pack scripts follow our rule: ask first, every time.
Pack lessons: it targets Blender 4.x; we run 5.3, so 5 scripts are patched (see roblox-animation/LOCAL.md),
re-apply after `git pull`. Never run downloaded .blend files with --enable-autoexec. Studio's Assistant HTTP
allowlist blocks localhost: VFX harvests go through an exported .rbxm + Lune (roblox-vfx/LOCAL.md).
VFX library: 1652 harvested recipes from the user's own packs.

## Skills learn
Every skill has a **Lessons** section. Whenever something is noticed (a bug, a false alarm, a look
that reads as generated, a Studio quirk), add one line with the why to the relevant skill's Lessons
before finishing the task. This applies to every skill, not just maps.

## Playtesting
- Use the `/playtest` skill (.claude/skills/playtest). It runs the gates, starts play, does a scripted
  movement test, and reports numbers + screenshots, then stops play.
- Saving/DataStores need "Enable Studio Access to API Services" on (Game Settings > Security).
- After a Studio plugin update, restart Studio before testing.

## Don't touch
- `build/`, `roblox.yml`, `*.lock`: generated.
- `rokit.toml` versions: only change them on purpose and with a note why.
- Anything in Studio that Rojo manages (Rules, Shared, Server, Client): edit the files, not Studio.
- Live game settings, game passes, developer products, prices, groups (Open Cloud key can do it):
  ask first, every time.
- Never print or commit the API key. It is in `$env:ROBLOX_API_KEY`.
