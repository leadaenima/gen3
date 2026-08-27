# Fullscreen A Touchpad

On a phone, tap anywhere that is not already a virtual button to press
**A**. Hold that finger down and A re-taps a few times per second, so
text and menus keep advancing. The on-screen d-pad, A, B, START and
SELECT keep first refusal: those glyphs still do their own jobs.

**Persona: the Tool Builder.** Wrap `input.pointer` and `input.step`,
inject source-safe A taps through `mod.input`, and leave every other
control alone.

## Try it

Copy this folder to `mods/touchpad_a` if it is not already there, then
enable **Fullscreen A Touchpad** in the in-game mod manager (F10 on
desktop). On a phone it is discovered the same way as any other mod.

- Tap the playfield, the letterbox, or any gap between virtual buttons:
  that is one A press.
- Hold there: A repeats (default 5 taps per second; change **HOLD TAPS /
  SEC** in the mod's options).
- Tap the drawn A/B/d-pad/START/SELECT glyphs: those still press their
  own buttons. This mod never steals a pointer that began on the pad.

A second option, **MOUSE CLICKS**, lets a desktop mouse stand in for a
finger so you can try this without a phone (`POKEPORT_TOUCH=1` still
drives the overlay; turn MOUSE CLICKS on if you want click-to-A there
too).

## What it demonstrates

| Seam | Where |
|---|---|
| `hooks:wrap("input.pointer")` | `main.lua` — uncaptured touches and mouse |
| `hooks:wrap("input.step")` | `main.lua` — hold-to-repeat on the logic clock |
| `mod.input:tap` | `main.lua` — one wasPressed edge per fire, no hold |
| `mod.options:define` / `:get` | `main.lua` — enable, mouse, and repeat rate |

The overlay captures any pointer that *begins* on a virtual control for
that pointer's whole life. A tap that begins on empty glass stays
visible to this mod even if you later slide onto a drawn button, which
is why the repeat keeps going until you lift.

## Credits

- gen1recomp — `input.pointer`, `input.step` and `mod.input`
