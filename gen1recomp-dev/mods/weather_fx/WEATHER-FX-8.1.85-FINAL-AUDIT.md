# Weather FX 8.1.85 Final Audit

## Baseline
Exact Weather FX 8.1.84.

## Change
Adds one player-facing setting, **CLOUD BANK STYLE**, and one dedicated 3D block-cloud renderer.

### VOLUMETRIC
Default. Uses the exact inherited 8.1.84 rounded/volumetric cloud presentation.

### BLOCKY
Uses the already-authored local/front cloud descriptor field and converts each descriptor into a deterministic 5x3 rectangular tile silhouette. Tiles are horizontal world-space geometry, not camera-facing sprites or a screen overlay. They are intentionally flat, slightly translucent, depth-tested against the voxel scene, and move only because the underlying cloud descriptors move.

## Authority preservation
The style switch does not create or own weather state. Both styles share:
- cloud lattice identity and map persistence;
- wind advection;
- CLOUD HEIGHT and CLOUD DENSITY;
- local and WEATHER FRONTS descriptors;
- precipitation deck origins;
- lightning and tornado cloud attachment;
- cloud transmission/occlusion calculations.

BLOCKY falls back to VOLUMETRIC if its shader/mesh path is unavailable on a host.

## Player settings
Schema increases from 76 to **77** settings. The new row is in **WORLD & CLOUDS** and has exactly two choices: `volumetric` and `blocky`.

## Runtime delta vs exact 8.1.84
Intended runtime Lua delta:
- `lib/Settings.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

Release metadata/tests also change for 8.1.85 qualification.

## Focused proof
- cloud-bank style regression: **20/20 PASS**;
- negative control on exact 8.1.84: **2 PASS / 17 FAIL**, exit 1, proving the new functionality is absent there;
- settings runtime: **735/735 PASS**;
- settings descriptions/menu: **1,884/1,884 PASS**;
- settings runtime/consumer audit: **269/269 PASS**;
- simultaneous maximum-settings profile: **10/10 PASS**;
- inherited developer sweep plus new gate: **85/85 programs PASS** on the source tree.

No live-game framebuffer visual claim is made unless separately captured.
