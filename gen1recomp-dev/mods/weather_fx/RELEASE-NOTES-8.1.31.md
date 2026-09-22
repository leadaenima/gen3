# Weather FX 8.1.31 — Real Rolling Water

8.1.31 is built directly from the preserved 8.1.30 Realistic Progressive Ice baseline. It does not replace cartridge water authority, Surf logic, collision, freeze/thaw, tides, shoreline classification, SnowPack behavior, or any unrelated Weather FX system.

## Real crests and troughs

Voxel Realism's relief water shader represents its vertical field internally as `0..WAVE_HEIGHT`. 8.1.30 increased that field but still left the base plane at the hydrosphere datum, so the result could read as raised bumps on a sheet. 8.1.31 deliberately lowers the relief base by half of the active peak-to-trough height on compatible Voxel Realism water renderers. The same shader field therefore becomes `-H/2..+H/2` around the physical tide datum: troughs genuinely fall below mean water while crests rise above it.

At the strongest connected-water sea state the authored peak-to-trough span reaches 8 world pixels (one cartridge tile). Calm water remains under two pixels peak-to-trough. The physical/gameplay water datum is unchanged.

## Structured traveling sea

The compatible Voxel Realism wave source is tuned as a directional sea rather than three equal-frequency bumps:

- 68 px dominant rolling swell, 68% of the field;
- 46 px oblique cross-sea, 22%;
- 24 px light opposing chop, 10%;
- 250 px moving group envelope so waves arrive in sets;
- 190 px cross-crest bend so long crests curve rather than forming ruler-straight wallpaper;
- 10 Hz one-world-pixel phase steps, retaining the host's voxel/pixel presentation style while slowing the large swell.

Only a meaningful 15-degree wind-sector change recompiles the train directions. Height and reflection slope remain uniforms, so ordinary wind-strength changes do not rebuild shaders.

## Shoreline safety

True troughs can fall below the cartridge's normal `-2` water datum. A bounded, depth-tested perimeter seal is generated only along connected-water boundary edges and only below that datum. It prevents a trough from exposing void space beneath host shoreline walls without painting over land or changing collision. Load-bearing ice remains wave-free.

## Surf/player wave riding

On a compatible Voxel Realism host, Weather FX mirrors the exact smooth wave equation in Lua and samples it under a Surfing player. The resulting lift is applied only to the player's returned **presentation pose** during the host render. That same pose drives the first-person eye, so the player and camera ride the water together.

The bob is smoothed and capped for comfort. It never writes player `px/py`, cells, map position, collision state, Surf state, or warp state. Tornado carry remains higher-priority and suppresses wave bob while airborne.

## Compatibility/fail-open behavior

The centered-wave system activates only when the host exposes the exact structured relief seams (`_trainSource`, `_waveTime`, swell and bend tables) needed to prove the `0..H` convention. A host exposing only the older train/height seam receives the already-proven 8.1.30 directional-wave behavior instead; Weather FX does not guess a different host's height convention.

Hot teardown restores the host's original wave trains, height, swell, bend, FPS, pixels-per-step, reflection slope and lean.

## In-game WATER STYLE handoff

The Weather FX in-game **ATMOSPHERE** submenu now includes **WATER STYLE**:

- **WEATHER FX** (default) — connected hydrosphere, real rolling waves, tides, rain ripples, progressive freeze/ice and presentation-only Surf wave riding.
- **ORIGINAL** — immediately releases water rendering back to the voxel host and restores every host wave tuning value Weather FX changed. Weather FX ice-walking and frozen-water presentation are also masked while ORIGINAL is selected so apparently liquid native water can never become invisibly walkable.

The switch is persisted through the normal mod-options store, applies live without restarting, and can be changed back to WEATHER FX at any time. Rain, snow, clouds, lighting, audio and all non-water Weather FX systems remain active in ORIGINAL mode.

## Real Gen1Recomp / Pokémon Yellow live qualification

The final candidate was installed into the preserved Gen1Recomp 0.2.53 / LÖVE 11.5 runtime with Pokémon Yellow and Voxel Realism 3.1.3-RECOVERED-ALL-IN-ONE-1.9.1. The camera was forced to FIRST and the player was placed at Pallet Town's south-west shoreline, looking directly across cartridge water cells.

At the deliberately forced strongest sea-state qualification point, the live connected hydrosphere reported 4 bodies / 1,583 cells, wind strength 1.50000, connected-water wave 1.44420, and host relief height 7.98765 world pixels. The resulting first-person frame visibly contains rising crests and falling troughs instead of the old above-datum bump sheet.

The live WATER STYLE control was changed through Gen1Recomp's real ManagerState option writer, not by editing Weather FX internals. ORIGINAL immediately changed the active live renderer to disabled and restored this host's native water height to 5.5. Switching back to WEATHER FX in the same process re-enabled connected water and restored the ~7.99 px strong-wave relief with all 4 / 1,583 connected cells still present.

Known Voxel Realism 1.9.1 host warnings remain inherited and outside this water release: its bundled Stadium runtime cannot resolve the external stadium2.importer namespace in this synthetic host layout, save.created still probes removed src.render.GBCFX, and optional ForestAtmos/Voxel probes are absent. None prevented the water renderer, WATER STYLE handoff, or live captures from completing with process exit 0.
