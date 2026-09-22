# Weather FX 8.1.97 — Full Player Settings Audit + RAVE Accessibility

Weather FX 8.1.97 is built directly from exact 8.1.96 and focuses on the player-facing settings system rather than adding another weather family.

## Settings cleanup

- Removed **WEATHER VISUALS**, which duplicated the ability of **BATTLE WEATHER** to turn battle weather presentation off.
- **BATTLE WEATHER** now cleanly owns `OFF / SUBTLE / FULL` visual presentation.
- **WEATHER RULES** remains independent and continues to control battle mechanics rather than graphics.
- Renamed **3D WEATHER DISTANCE** to **3D PRECIP DISTANCE**. It controls falling 3D precipitation reach relative to the live voxel render distance; **EFFECT DISTANCE** remains the broader expensive-detail/performance radius.

## New RAVE controls

- **RAVE STROBE — OFF / REDUCED / FULL**
  - OFF removes full-rig blackout strobing while retaining moving lasers, illuminated fog, colors, and beat-reactive motion.
  - REDUCED keeps the center rig continuously visible and softens the surrounding authored strobe.
  - FULL preserves the song-specific authored show.
- **RAVE MUSIC — OFF / 50% / 75% / 100% / 125%**
  - This sits underneath **WEATHER VOLUME**, so the master Weather FX volume remains authoritative.
  - OFF stops the streamed RAVE decoder and immediately returns native game-music ownership.
  - The RAVE visual rig retains its safe fallback timing when no soundtrack is playing.

## Audit result

The final schema contains **79 distinct player-facing controls**. The audit verifies unique keys/labels, exactly one submenu placement per control, valid choices/defaults, runtime consumption, immediate live-change behavior, complete descriptions, and simultaneous maximum-setting validity.

All fixes from 8.1.96 and earlier remain intact, including pause-menu weather visibility/freeze, RAVE illuminated fog and strobe rendering, Battle Art NPC lightning, full-render-distance snow, and Battle Art water ownership.
