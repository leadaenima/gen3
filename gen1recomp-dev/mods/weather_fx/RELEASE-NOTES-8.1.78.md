# Weather FX 8.1.78 — Rendered-World Rain Coverage

## What changed

The fronts-OFF rain contract is now explicit: an authored active rain weather must occupy the complete world that the voxel renderer can currently show. Rain is not a local player bubble and it is not a circle that can be walked out of.

When **WEATHER FRONTS = OFF**:

- **3D WEATHER DISTANCE = 100%** uses the live voxel render distance exactly.
- 75%, 50%, and 25% reduce only Weather FX precipitation reach.
- Procedural rain is distributed over an **absolute world-space grid** spanning the complete 2R × 2R voxel render window rather than a player/focus-centred disk.
- The visible grid is chosen from the voxel camera position only to cover the currently rendered window. Each rain cell keeps identity from its absolute world coordinates, including positional jitter, fall phase and personal drift, so camera/player motion does not translate the storm.
- One guard-cell layer surrounds every side of the requested render window to prevent edge gaps during grid-window handoffs.
- Rain population budgeting uses full render-window area rather than πR² so the outer edges/corners do not lose density.
- CPU fallback mirrors the square rendered-world coverage and uses a square-safe recycle bound.

When **WEATHER FRONTS = ON**, the inherited regional/front-owned precipitation behavior is unchanged.

## Preserved fixes

8.1.78 retains the 8.1.77 map-edge/turn monotonic rain clock and CPU fallback fixes, the 8.1.76 ledge continuity/stable vertical rain column and tapered translucent blue-grey water streak, the 8.1.75 rain continuity latch, the 8.1.74 uniform fronts-OFF weather behavior, the 8.1.73 map-entry reprime and snow/blizzard fountain protections, the 8.1.72 3D WEATHER DISTANCE control, and the 8.1.69 SNOW ACCUMULATION toggle.

## Qualification

The new `tests/rain_rendered_world_8178_test.lua` executable regression validates exact voxel-distance ownership, full X/Z render-window coverage, turn-independent absolute cells, full-square rain budgeting, procedural ownership, and explicit rain shutdown. It passes 14/14 on 8.1.78. Exact 8.1.77 fails 10/14, providing a negative control for the new behavior.

No fresh live-game framebuffer was captured in this pass. Final visual confirmation remains the user's in-game map-edge/turn/walking test on the real host.
