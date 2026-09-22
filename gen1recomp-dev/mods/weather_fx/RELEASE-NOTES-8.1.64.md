# Weather FX 8.1.64 — Complete Player/Visual/Performance/System Audit + Live SnowPack Restore

## Player-facing repair

- Restores live 3D SnowPack ground interaction that had been safety-disconnected in 8.1.54.
- Persistent snow banks now accumulate from the procedural/GPU snow field through a bounded exact-support interaction sampler.
- Real walking through sufficiently deep accumulated snow creates persistent drawable footprints.
- Water remains rejected; frozen-water/ice and exact supported terrain remain eligible through SnowPack's existing support resolver.
- The repair does **not** return the visual snow population to CPU simulation.

## Performance bounds retained

- <=96 CPU snow interaction probes while the complete visual population remains GPU/procedural.
- <=24 aggregate exact-support deposition samples per second.
- 2,048 SnowPack cells maximum.
- six patches maximum per terrain cell.
- 192 persistent footprints maximum.
- MAX authored snow/blizzard visual ceilings remain unchanged.

## Comprehensive requalification

- All 68 player-facing settings re-audited and exercised.
- All 29 weather definitions requalified through the real player option path in 2D and 3D.
- Real-host special-event proof includes post-rain rainbow state/render, winter aurora state/render and a forced-but-real Lightning scheduler/bolt render.
- Celestial, rainbow, aurora, lightning/NPC lightning, storm-front and tornado behavior contracts all pass.
- Performance, engine/system, compatibility, settings and render-pipeline batteries pass after the SnowPack repair.

MIST remains intentionally AUTO-only; it is part of the natural weather catalogue rather than the manual WEATHER ladder.
