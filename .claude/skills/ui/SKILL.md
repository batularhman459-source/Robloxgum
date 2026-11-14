---
name: ui
description: Build Roblox UI from a spec: preview image, .rbxm file and build script from one source, with the Depth Stack and the 6-rule UI checker on 4 screen sizes. Use for any UI, HUD, menu, shop, popup or icon work, and when the user sends a UI spec or a UI reference image.
---

# UI

The full rules are in CLAUDE.md > UI. In short:
1. Read `ui/STYLES.md`, pick a style.
2. Write `ui/specs/<Name>.luau` (plain data). Icons by name only.
3. `lune run tools/ui build <Name>` until it passes, look at `ui/build/<Name>.preview.png`, show the user.
4. Icons: `.\tools\icon.ps1 -Name <icon> -Subject "<what>" -NoUpload`, look at the PNG, show the user,
   upload only after they say yes.
5. Reference images: recreate as spec + theme, then add a `ui/STYLES.md` entry.

## Lessons (add one every time something is noticed; keep the why)
- White text on the yellow primary fails contrast: use textDark on bright colors.
- Roblox AbsolutePosition is measured below the top bar: add `GuiService:GetGuiInset().Y` when comparing
  with the layout engine (the engine measures from the screen top).
- UIScale on a Root frame sized 1/scale keeps scale positions reaching the screen edges: verified 0 px.
- FLUX adds sparkles and decorations: the shared prompt forbids them and the cut keeps only the
  biggest connected shape.
- The flood-fill cut keeps white inside icons (gear hole stays white): fine on dark buttons.
- The preview shows local icon PNGs before upload, so icons are judged in place first.
