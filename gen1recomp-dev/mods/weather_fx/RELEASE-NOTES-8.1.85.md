# Weather FX 8.1.85 — Block Cloud Bank Style

Built directly from exact Weather FX 8.1.84.

## New player control
**WORLD & CLOUDS → CLOUD BANK STYLE**

- **VOLUMETRIC** — default; preserves the exact 8.1.84 rounded atmospheric cloud-bank renderer.
- **BLOCKY** — renders the same cloud bank as flat, shallow, slightly translucent rectangular world-space tiles with a pixel/voxel silhouette.

## Behavior contract
BLOCKY is a presentation style, not a second weather simulation. It inherits the same authoritative cloud descriptors as VOLUMETRIC, including:

- cloud height and CLOUD DENSITY;
- WindEngine advection and long-session/map persistence;
- WEATHER FRONTS and remote front geometry;
- rain/snow/hail cloud-deck origins;
- lightning cloud tops;
- tornado cloud attachment/descent;
- cloud transmission used by sun/god-ray occlusion;
- 3D world depth testing.

The block geometry is deliberately flat: each descriptor becomes a deterministic 5x3 rectangular tile silhouette on a single shallow plane. Alpha is bounded below full opacity so the clouds remain slightly translucent. Closed storm decks fill their tile grids so sealed weather remains visually continuous.

If a compatible host refuses the small block-cloud shader/mesh, Weather FX fails open to the proven volumetric renderer rather than making clouds disappear.

No precipitation counts, weather distances, 2D/3D ownership rules, snow smoothing, weather-selector synchronization, water, wind, lightning, tornado, audio, celestial behavior or quality ceilings are intentionally changed from 8.1.84.
