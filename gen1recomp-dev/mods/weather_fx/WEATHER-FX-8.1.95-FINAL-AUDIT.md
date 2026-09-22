# Weather FX 8.1.95 Final Audit

## Scope

Built directly from exact Weather FX 8.1.94. Runtime behavior changes only the RAVE illuminated-fog response in `lib/voxel_atmos/CinematicAtmos.lua`; `manifest.json` advances the release identity to 8.1.95. New regression tooling covers the fog/strobe behavior without changing gameplay systems.

## Illuminated fog repair

The existing RAVE fog lattice remains bounded and player-local. Laser/fog intersection is still computed from live world-space beam centerlines. 8.1.95 increases the beam-hit colour/luminance lift and optical density only when an actual intersection exists. Non-intersecting fog retains the normal RAVE fog response.

Focused executable coverage passes 13/13: strengthened intersection response, visible beam-colour lift, bounded luminous energy, bounded optical density, full centerline hit, no false light outside beam radius, production fog volume construction, live intersection energy, and real draw submission.

## Strobe qualification

The production `laser_floor` show remains synchronized to its 160-BPM song playhead. Focused testing proves a visible ON phase, exact zero-beam OFF phase, and re-opened ON phase on the next musical beat. This is a hard fixture gate rather than a brightness-only pulse.

## Real Battle Art 1.10.4 framebuffer evidence

A fresh Gen1Recomp 0.2.53 / LÖVE 11.5 / Pokémon Yellow run used the user-supplied Battle Art Voxel Fork 1.10.4 and the exact 8.1.95 runtime `CinematicAtmos.lua` hash (`3f883ed334ffe2eead735d886a0211c56480b0762ed184543b1b751652bdeea7`).

Observed live RAVE state:
- active song: Laser Floor, 160 BPM, `laser_floor`
- fog volumes: 40
- beam-hit fog vertices: 80
- maximum live beam/fog hit strength: 0.73389580215759
- production fog draw observations: 19/19 successful
- strobe fixture sequence: 56 ON -> 0 OFF -> 0 held OFF -> 56 ON return

Direct 1024x768 framebuffer captures demonstrate the illuminated fog and the strobe ON/OFF/return phases. These are real LÖVE framebuffer captures, not generated reference images.

## Regression

- RAVE fog/strobe focused regression: **13/13 PASS**.
- Maintained developer sweep: **107/107 programs PASS**.
- The maintained sweep includes 8.1.94 song/BPM synchronization, RAVE audio/shuffle ownership, Battle Art NPC lightning, full-render-distance snow, Battle Art water ownership, precipitation, fronts, tornadoes, celestial systems, audio, battles, seasons, settings and performance/compatibility guards.

## Truth boundary

The live test uses software OpenGL under the preserved Gen1Recomp/LÖVE test environment, so it is direct framebuffer proof of functionality, not a claim about subjective brightness or FPS on every physical GPU/display.

## Exact-package qualification

The frozen installable ZIP is extracted to a clean directory and re-qualified from those exact bytes. Required gates: CRC/path/collision/zero-byte integrity, source/package byte comparison, 107-program maintained sweep, 13/13 RAVE fog/strobe regression, 47/47 song/BPM/package synchronization, 8/8 target LÖVE 11.5 OGG decode, and 128/128 runtime LuaJIT compile. All pass before release.
