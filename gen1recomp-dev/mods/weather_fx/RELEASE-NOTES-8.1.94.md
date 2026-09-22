# Weather FX 8.1.94 — RAVE Soundtrack Shuffle

Built directly from exact Weather FX 8.1.93.

## RAVE music
- Adds eight original electronic tracks: 2 techno, 2 rave, 2 dubstep, 2 house.
- Full songs use streamed LÖVE Sources instead of the static weather-bed cache.
- Fisher-Yates shuffle bag plays every title before reshuffling and prevents an immediate repeat across bag boundaries.
- Finished songs automatically advance to the next shuffled title.
- Enter/exit uses short fades; leaving RAVE, disabling weather, leaving the world, or invalidating audio releases the source cleanly.
- WEATHER SFX volume controls RAVE music; WEATHER SFX=OFF also declines soundtrack ownership.
- Native map/battle music is muted only while an actual RAVE source is owned and audible, then restores through the engine's normal `music.volume` path without Weather FX selecting/restarting native music.
- Each song now owns its **own light show**. The light rig reads the active streamed source playhead and that song's exact composition BPM, so downbeats, offbeats, laser gates, floor pools, fog illumination, cloud colour pulses and sky/ray washes stay synchronized to the music.
- The eight shows have distinct fixture grammars and palettes: Neon Conveyor uses parallel lane chases; Steel Pulse uses hard opposing banks; Pixel Rush uses quarter-beat pixel snaps; Laser Floor uses dense spiral/floor choreography; Voxel Wobble uses broad half-time pendulum banks; Subspace Drop uses quantized radial bursts; Route 4 AM uses smooth four-on-floor fans; Moonlit Club uses mirrored soft club banks.
- Authored song arrangement bars are mirrored by the show: techno hoover-hit bars open the rig, rave breakdown/roll bars pull back then punch, dubstep breakdown/drop bars change density, and house chord-break bars soften before the return.
- Audio timing remains presentation-only. Per-song BPM/playhead synchronization cannot alter weather scheduling, gameplay, lightning authority, or precipitation simulation. If streamed audio is unavailable, the proven legacy 128-BPM visual clock remains the fail-open fallback.

## Packaging repair
- Corrects the stale 8.1.93 manifest identity. This package declares version 8.1.94.

## Preserved
- 8.1.93 Battle Art 1.10.4 NPC lightning actor bridge and flash/smoke reaction.
- 8.1.92 full-render-distance 3D snow.
- 8.1.91 point-snow and Battle Art water ownership repairs.
