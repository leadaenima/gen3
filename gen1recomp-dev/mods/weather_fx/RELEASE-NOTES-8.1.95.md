# Weather FX 8.1.95 — RAVE Illuminated Fog + Strobe Qualification

Built directly from exact Weather FX 8.1.94.

## Illuminated RAVE fog
- Strengthens only the optical response of laser-hit RAVE fog while keeping the existing bounded 5x5/two-layer fog lattice and beam-intersection logic.
- Fog outside a live beam remains unlit. Fog intersecting a beam receives bounded beam-colour lift plus increased optical density, making the illuminated body visible in the real 3D framebuffer instead of reading as a nearly invisible tint.
- No raymarch, world simulation, precipitation budget, weather scheduling, or gameplay authority was added.

## Strobe
- Retains the 8.1.94 per-song strobe choreography and re-qualifies it against the real production fixture path.
- Laser Floor at 160 BPM visibly hard-gates the fixture population ON -> 0 -> ON as its musical phase advances; the OFF phase is a real zero-fixture gate, not a small brightness reduction.
- Song-specific BPM/playhead synchronization and all eight unique light-show identities remain unchanged.

## Real Battle Art qualification
- Tested in Gen1Recomp 0.2.53 / LÖVE 11.5 with Pokémon Yellow and the user-supplied Battle Art Voxel Fork 1.10.4.
- Live RAVE scene produced 40 fog volumes, 80 beam-hit fog vertices, max intersection strength 0.73389580215759, and 19/19 successful production fog draw observations.
- Live strobe sequence produced 56 fixtures ON, 0 OFF, held at 0 through the OFF interval, then returned to 56 ON.
- Direct 1024x768 LÖVE framebuffer captures were recorded for no-fog reference, illuminated fog, strobe ON, strobe OFF, and strobe return-ON.

## Preserved
- 8.1.94 eight-song streamed shuffle and exact per-song BPM light shows.
- 8.1.93 Battle Art NPC lightning actor bridge plus flash/char/smoke reaction.
- 8.1.92 full-render-distance 3D snow.
- 8.1.91 one-pixel snow and Battle Art water-ownership repairs.
