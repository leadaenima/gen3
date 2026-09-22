# Weather FX 8.1.96 — Pause-Menu Weather

## Player-facing changes

- **2D weather now remains visible when the START/pause menu is open.** Pause screens are treated as overlays over the live world rather than as unknown full-screen screens.
- New in-game WEATHER setting: **PAUSE MENU WEATHER**.
  - **ANIMATED** (default): weather remains visible and keeps moving while the pause menu is open.
  - **FROZEN**: the current weather remains visible, but Weather FX animation stops until the player leaves the pause menu. It resumes from the same visual phase instead of respawning/restarting the effect.
- FROZEN applies to classic 2D precipitation/fog/wind phases and the 3D weather presentation, including procedural precipitation, voxel atmosphere, visible tornado motion, and RAVE light-show motion.
- **FROZEN is a true Weather FX hold:** Weather FX weather evolution receives a zero update delta while the pause stack is open, preventing live channel changes from adding/removing particles behind an otherwise frozen frame. The host game/input continue normally. Existing audio sources are not forcibly cut; visual weather resumes from the exact held state when the pause stack closes.

## UI safety

Only recognized START/pause-menu screens and their pause descendants are transparent to Weather FX. Unknown non-pause menus remain fail-closed, preserving the existing protection against weather being painted over arbitrary UI.

## Final live qualification

- Tested in a real Gen1Recomp 0.2.53 / LÖVE 11.5 Pokémon Yellow session with Battle Art Voxel Fork 1.10.4 installed.
- With Battle Art's VOXEL pipeline set to OFF (the actual flat/2D presentation path), HEAVY RAIN remains visibly rendered while the native START menu is open.
- ANIMATED mode visibly changes precipitation across pause-menu frames.
- FROZEN mode produced two framebuffer captures separated by 30 live frames with **0 changed RGB pixels**.
- After closing START, precipitation resumed motion immediately from the held state.
