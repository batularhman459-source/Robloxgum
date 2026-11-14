# UI style library

Every UI design you send as an example or inspiration gets recreated in our system, adapted to the
house rules, and recorded here. New UIs pick a style from this file instead of being invented from scratch.

## How a style gets added
1. Read the reference: layout, hierarchy, color roles, shape language, type, what makes it feel good.
2. Recreate it as a spec in `ui/specs/` with a theme in `ui/themes/<style>.toml`.
   Always keep the house rules: Depth Stack, one outline thickness, thumb-size buttons, no separators.
3. `lune run tools/ui build <Spec>` until the checker passes, then compare the preview with the reference.
4. Write the entry below: the tokens, plus what was kept, what was changed and why.

## Entry template
```
## <Style name>
Source: <what it was based on>       Theme: ui/themes/<file>.toml       Example spec: ui/specs/<Spec>.luau
Feel: <3-6 words>
Palette roles: panel / primary / success / danger / accent / text / textDark (hex)
Shape: corner radius, outline thickness, shadow offset + color, gradient strength, lift strength
Type: font, weights, sizes used (title / body / button / number)
Layout: margins from screen edge, gaps, padding, where things sit
Kept from reference: ...
Changed for our rules: ...
Do: ...
Don't: ...
```

---

## House
Source: our own default.       Theme: ui/themes/house.toml       Example spec: ui/specs/Hud.luau
Feel: chunky, friendly, readable, toy-like.
Palette roles: panel #222A4E, primary #FFBE28, success #28AA5A, danger #DC3C3C, accent #466EF0,
text #FFFFFF, textDark #161828. Outline #111426, shadow #18204E (navy, blue-shifted).
Shape: radius 12, outline 3 px everywhere, shadow 4 px down at 40 % transparency,
face gradient 100 % → 80 % brightness, lift = white sheen 35 % at the top fading out by half height.
Type: Builder Sans Bold. Numbers 20, buttons 20, body 18, minimum 14.
Layout: 16 px from screen edges, 12 px below the top bar, 14 px padding, 12–14 px gaps.
Do: dark text on yellow; white text on panel, accent, danger. One primary action per screen.
Don't: white text on primary/yellow (fails contrast), separators like "•", text under 14 px, extra outline widths.
