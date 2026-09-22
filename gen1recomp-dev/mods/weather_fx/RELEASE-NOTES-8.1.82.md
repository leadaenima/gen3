# Weather FX 8.1.82 — Player Control Expansion

Built directly from exact Weather FX 8.1.81.

## New player controls

- **LIGHTNING FREQUENCY** — RARE / LOW / NORMAL / HIGH / EXTREME. NORMAL preserves the previous authored strike cadence. It affects both the main storm scheduler and regional storm cells.
- **TORNADO DURATION** — SHORT / NORMAL / LONG. NORMAL preserves the previous mature roam duration. Only mature 3D roaming time changes; cloud descent, formation, waterspout conversion, pickup/transfer safety and rope dissipation are unchanged.
- **CLOUD DENSITY** — LOW / NORMAL / HIGH / VERY HIGH. NORMAL is an exact no-op. It adjusts persistent cloud-cell occupancy and visible puff density without changing precipitation amount or weather timing.
- **NIGHT SKY BRIGHTNESS** — LOW / NORMAL / HIGH. It scales stars, planets, constellations and the Milky Way while preserving their relative hierarchy. Sun, moon, aurora, meteors, cloud occlusion and celestial motion are not changed.
- **WEATHER SCREEN EFFECTS** — FULL / REDUCED / OFF. It controls camera-sized 2D/battle grading, lightning wash, psychic wash, compatibility veil and glare. World-space precipitation, clouds, tornadoes, physical lightning bolts, thunder and 3D physical lighting remain active.
- **WET GROUND** is expanded to DEFAULT / OFF / LOW / NORMAL / HIGH. The old stored `on` value is retained as NORMAL for save compatibility. The setting changes visible wetness/puddle strength, not rainfall or surface simulation.

The settings schema is now **76** rows: five new rows plus one expanded existing row.

## Preservation contract

All new defaults reproduce 8.1.81 behavior. Rain/hail/snow caps, weather distance, quality ceilings, weather fronts, wind-driven water, tornado cloud attachment/descent, animations, audio behavior, settings persistence and assets remain preserved unless the player explicitly changes one of the new controls.

## Qualification

Release-specific player-control gate: 50/50 PASS. Current settings runtime: 731/731 PASS. Complete descriptions: 1,869/1,869 PASS. Full menu interaction: 2,226/2,226 PASS. Current runtime consumer audit: 267/267 PASS. Simultaneous MAX profile: 10/10 PASS. 8.1.81 resource gate: 26/26 PASS. 8.1.80 frame-reuse gate: 29/29 PASS. Revision: 80/80 PASS. Performance invariants: 66/66 PASS. 3D pipeline: 117/117 PASS. Feature integrity: 505/505 PASS. Voxel-host compatibility: 27/27 PASS. Maintained Lua suite: 191/191 PASS.

One inherited `celestial_occlusion_brightness_test.lua` static assertion still reports the same 9 PASS / 1 FAIL on exact 8.1.81 and 8.1.82; it is not introduced by this release and is not used as evidence for the new night-brightness control.

No fresh live-game framebuffer or physical-device FPS measurement was captured for 8.1.82. No such claim is made.
