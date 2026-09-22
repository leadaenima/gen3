# Weather FX 8.2.11 — Gen1Recomp + Gen2Recomped Six-Game Compatibility

Built directly from exact Weather FX 8.2.10.

## Supported games
One install now explicitly supports Pokémon Red, Blue, Yellow, Gold, Silver, and Crystal across the Gen1Recomp / Gen2Recomped host family.

## Compatibility work
- Added one call-time host/edition authority for Red, Blue, Yellow, Gold, Silver, and Crystal so generation-specific engine proxies are never guessed from an optional companion mod.
- Fixed the Gen2 OPTIONS integration: the WEATHER row is now selected by the running generation, not by presence of the unrelated `CRYSTAL_251` mod.
- Added native Gen2 battle-weather interoperability. Gen2Recomped's `RAIN`, `SUN`, `SANDSTORM`, and `HAIL` remain owned by the host's cartridge-accurate battle mechanics while Weather FX renders them without double-applying damage, accuracy, residual, charge, or speed behavior.
- Overworld weather seeded into Gen2 battles now uses native `RAIN`/`SUN` vocabulary when appropriate and environmental weather is marked persistent instead of being accidentally consumed by the host's five-turn move-weather countdown.
- Weather FX-only battle conditions use a separate sidecar field on Gen2 so the native Gen2 weather module cannot misinterpret custom weather IDs.
- Battle visuals accept both Weather FX and native Gen2 weather vocabularies, including weather changed by Rain Dance, Sunny Day, Sandstorm, and compatible host systems.
- Gen2 legendary availability and tornado generation handling now use the same edition authority.

## Preserved
All existing 8.2.10 weather rendering, 2D/3D ownership, precipitation density, clouds, snow, water, lightning, tornadoes, RAVE, celestial systems, settings, Gen1 battle behavior, and performance budgets are preserved.

## Qualification
- Six-edition runtime contract: 41/41 PASS.
- Gen2 battle ownership regression: 20/20 PASS.
- Static Gen2Recomp contract: 18/18 PASS.
- Existing `test_mod.py --lua`: 201/201 PASS.
- Settings/runtime audit: 280/280 PASS.
- Feature integrity: 514/514 PASS.
- Revision gate: 80/80 PASS.
- Maintained developer sweep: 137/137 programs PASS.

No fresh cartridge-backed live playthrough of all six retail games is claimed by these automated checks; the compatibility layer is qualified against the current Gen2Recomped public APIs and Weather FX's maintained executable regression suite.
