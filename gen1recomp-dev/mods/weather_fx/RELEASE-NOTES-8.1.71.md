# Weather FX 8.1.71 — Fronts-Off Exact Voxel Render Distance

## Change requested

When **WEATHER FRONTS is OFF**, rain, snow, and hail must render as far as the voxel renderer's current render-distance setting. This exact-distance rule must not alter the regional/front-owned path when **WEATHER FRONTS is ON**.

## Implementation

- `WorldPrecip` reads the live `Voxel3D.far` value (or camera far fallback) from the current precipitation metadata before calculating stream radii.
- With fronts OFF, snow radius = voxel far distance, rain radius = voxel far distance, and hail inherits that same precipitation radius.
- The fronts-OFF path bypasses Weather FX's old 750-unit snow/rain ceiling and does not apply the 1.15× front overlap multiplier.
- With fronts ON, the existing quality/front radius ceilings are preserved.
- Changing the voxel render distance is reflected on the same WorldPrecip update rather than waiting for a later draw-frame observation.

## Preserved

- 8.1.70 vertical-plume / hail-tube fail-open procedural validation.
- 8.1.70 corrected snow/grain wind routing.
- 8.1.69 SNOW ACCUMULATION ON/OFF setting.
- 8.1.68 distributed/coalesced accumulation shape, persistence, and approved heights.
