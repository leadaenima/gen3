# Weather FX 8.1.56 — Seamless Battle Precipitation Handoff

Built directly from exact Weather FX 8.1.55.

## Fixed

- **No more battle-entry snow dump.** `WorldPrecip` detects a live battle immediately from `Battle.current()` instead of waiting on the former one-second Scene cache.
- **No battle-camera particle re-anchor.** World precipitation suspends before reading transition camera/focus coordinates or running stream carry, so the battle camera cannot drag the overworld snow/rain pool into view.
- **No stale 3D world precipitation over battle.** The WorldPrecip draw path also fails closed while battle authority is live.
- **No flat-world precipitation over the battle opening.** `Scene.drawScale()` disables only the outgoing world precipitation layer as soon as the battle starts, even before the Scene stack has finished changing to `battle`.
- **No stop/restart into battle weather.** `BattleDraw.begin()` primes battle channels from finalized `battle.field.weather`, so an outdoor snowstorm/rainstorm is already at its correct battle intensity on the first battle frame.
- **Moves/abilities still transition naturally.** Weather introduced after battle start continues to use the existing eased channel transition.

## Preserved

Snow/blizzard particle density and ceilings are unchanged. 8.1.55 fixed world-anchor snow motion and dedicated presentation clock are unchanged. 8.1.54 full-visual GPU precipitation virtualization and bounded CPU interaction probes are unchanged. Snow ground collision/settling/banks/footprints remain intentionally disabled.
