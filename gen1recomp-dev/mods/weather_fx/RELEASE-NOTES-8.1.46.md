# Weather FX 8.1.46 — Seamless Water + Adaptive Low-End Performance + Correct Constellation Dimming

## Why this release exists

8.1.46 combines three player-reported fixes that affect the same presentation/performance layer: the visible two-water seam introduced by 8.1.45's far-VOID optimization, QUALITY PRESET not governing enough of the systems added over time, and constellation building-proximity dimming that could appear reversed when a town lacked explicit building metadata.

## 1. Voxel Nexus far-water continuity without restoring the lag

8.1.45 correctly removed Voxel Nexus' second expensive FULL water transaction for the synthetic 32,768-world-unit VOID ocean, but its ordinary scene-shader fast path changed the far material too much. Near water remained bright/reflective while the horizon could become dark teal and flatter, reading as two different bodies of water.

8.1.46 uses Voxel Nexus' own **SKY-only Water shader** for only the synthetic far VOID ocean. It preserves the same Weather FX physical mesh, generated water texture, tide datum, native water-shader family, day tint, Fresnel response, reflected sky bands, sun/moon body reflection, live wave-normal phase and voxel-grid material variant as the near FULL path.

The performance fix remains intact: the far ocean requires **no `Voxel3D.beginWater` framebuffer/depth capture and no FULL screen-space reflection ray march**. The exact 96px near VOID handoff plus every authored lake, river and pond stays on the normal FULL reflective path. `WATER=OFF` follows the same plain-water fallback as near water; if the SKY-only material is unavailable, ownership fails open to the prior FULL outer-water path rather than silently changing appearance. 8.1.45 exclusive Nexus tide ownership and 8.1.44 public Battle Art ownership remain intact.

## 2. QUALITY PRESET is now a whole-mod performance authority

QUALITY PRESET now has six clear choices: **AUTO (recommended), MAX, HIGH, MEDIUM, LOW and POTATO**. Manual tiers are literal and do not drift. AUTO adapts only Weather FX workload; it never changes game speed, weather duration, encounter logic or world time.

The preset now governs the major scalable systems added across Weather FX development:

- local and world-space precipitation budgets and 3D presentation radius;
- cloud/atmosphere descriptor detail;
- generated Weather FX material resolution, including physical water/ice/foam/ripple and fog noise textures;
- voxel-water reflection cost;
- aurora curtain tessellation/sheet count while preserving researched morphology and colours;
- celestial disc layer detail while retaining the full constellation/planet catalogue;
- Weather FX shadow-map precision/recast thresholds;
- snowpack/footprint draw budgets;
- background environmental/simulation cadence;
- existing particle populations and low-end performance-governor budgets.

LOW uses the matching SKY + CELESTIAL water-reflection LOD; POTATO uses SIMPLE physical water and substantially reduces generated texture resolution, effect radius, particles and aurora geometry. MAX keeps the authored maximum visual path.

### New PERFORMANCE submenu controls

- **AUTO PERFORMANCE — BALANCED / AGGRESSIVE / OFF**: active only while QUALITY is AUTO. BALANCED protects visible quality longer. AGGRESSIVE reacts sooner and permits deeper trims for weak phones/handhelds. OFF freezes AUTO's current/start tier and disables adaptive trimming.
- **PERFORMANCE TARGET — 60 / 50 / 40 / 30 FPS**: the target used by adaptive Weather FX budgets. It never alters game/weather speed.
- **TEXTURE DETAIL — FOLLOW QUALITY / FULL / HIGH / MEDIUM / LOW / MINIMUM**.
- **WATER REFLECTIONS — FOLLOW QUALITY / FULL / SKY + CELESTIAL / SIMPLE**.
- **EFFECT DISTANCE — FOLLOW QUALITY / FAR / MEDIUM / NEAR / MINIMUM**.
- **SIMULATION DETAIL — FOLLOW QUALITY / FULL / BALANCED / LIGHT / MINIMUM**.

All advanced rows default to **FOLLOW QUALITY**. The menu shows their current effective value, so changing the master preset visibly changes what they resolve to without destructively overwriting a player's explicit advanced override. Returning to AUTO resets the adaptive tier to a safe start point and then responds to sustained pressure with hysteresis/slow recovery rather than frame-to-frame oscillation.

## 3. Constellations now brighten in the correct direction around buildings

8.1.43's equal maximum-brightness contract is preserved: all 25 constellations / 8,507 traced stars still share the exact same unobstructed peak tiers.

The remaining direction bug came from fallback light-pollution sources. When explicit building metadata was unavailable, the old building-light scanner could synthesize town-centre/corner emitters. A player could therefore walk physically away from the visible building while internally approaching an invented emitter, making constellations dim instead of brighten.

8.1.46 removes those fake town-centre/corner emitters. In voxel mode, building light pollution can use real visible building/roof footprints; door/warp entrances remain a conservative secondary source for structures whose roof semantics are unavailable. Trees and cliffs are not treated as electrically lit buildings.

The invariant is now explicit: with the same time/cloud conditions, **constellation brightness increases monotonically as the player moves away from buildings**, reaching the shared 8.1.43 maximum in unobstructed wilderness. Real terrain/building depth occlusion and cloud attenuation remain unchanged.

## Preservation

No weather family, constellation subject, planet, aurora eligibility rule, storm-front reachability, authored water body, pond/fish behavior, ice/Surf safety, lightning timing, tornado gameplay, audio behavior or progression mechanic is removed. Advanced overrides are opt-in; existing installs default to FOLLOW QUALITY. `WATER STYLE = ORIGINAL` still restores native host water ownership.
