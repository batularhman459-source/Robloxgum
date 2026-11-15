# Imported animations

| File | Clips used | Used as | Credit |
|---|---|---|---|
| movementanims.rbxm | Sprint | Run (permanent run cycle) | Made in Blender by **godofsun95** ("Credit is appreciated :D", from the dummy's DisplayName). Provided by the designer. |

Walk from the same file is kept but unused.

## What the Sprint clip teaches (studied 2026-11-15 with tools/anim_dump.luau)
- Baked at 60 keys per second with Linear easing: the smoothness is a continuous curve, not
  5 poses with eases (that pose-to-pose look is what read as stiff in our first R6 run).
- Cycle 0.567 s for two steps.
- Constant counter-motion: shoulder twist (root yaw) +-18 deg, head turning the opposite way
  +-16 deg and looking up -12..-16 to counter the 12..15 deg forward lean, roll +-5.
- Arms never hang: 15..22 deg out at all times, swinging +55 forward / -30 back.
- Legs pass under the body with both slightly behind (push-off), big sweep -85..+62.
- Almost no vertical bob (y -0.11..-0.14): the feel comes from twist and swing.
