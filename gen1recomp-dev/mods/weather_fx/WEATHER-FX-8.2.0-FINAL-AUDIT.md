# Weather FX 8.2.0 Final Audit

## Scope

Built directly from exact Weather FX 8.1.99. This release addresses four live-player issues: global 3D cloud-bank loss while looking upward, the requested 2× RAVE volumetric cloud population, RAVE presentation while WEATHER RENDERING is 2D plus battle laser continuity, and the remaining player-following SNOW/BLIZZARD emitter that reset the whole visible snow field when its origin moved.

## Runtime delta

Exactly four shipped runtime Lua files change versus exact 8.1.99:

- `lib/BattleDraw.lua`
- `lib/DramalessAtmos.lua`
- `lib/ProceduralSnowField.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

No runtime Lua files are added or removed.

## Global 3D cloud zenith continuity

Cloud descriptor discovery now uses the stable gameplay/world precipitation anchor rather than a camera eye/focus midpoint. A bounded world-space overhead admission shoulder applies to every 3D cloud family, including non-sealed/broken banks, so steep upward pitch can no longer make nearby physical cloud cells disappear merely because their centers leave the ordinary projected-NDC path.

The RAVE cloud profile separately applies a 2.0 volumetric lobe multiplier after quality/player cloud-density scaling. This doubles the actual rendered volumetric primitive population for the same admitted RAVE cloud descriptors rather than merely enlarging or recoloring them.

## RAVE in 2D weather and battles

RAVE is treated as a presentation rig independent of precipitation ownership. With WEATHER RENDERING set to 2D, classic 2D precipitation/weather remains authoritative while RAVE fog, floor pools and lasers remain active in the voxel scene. The independent 3D CLOUDS feature continues to control whether the world-space cloud bank is drawn; ordinary 3D rain/snow, puddles, rays and full-weather fog are not enabled by the RAVE exception.

World-backed battles snapshot/carry the pre-battle RAVE presentation independently of `battle.field.weather`, preserving battle precipitation/mechanics while keeping the RAVE laser show. Opaque/classic battle canvases that hide the world scene receive a bounded additive 12-beam RAVE fallback.

## SNOW / BLIZZARD continuous field

The finite 24-unit snapped snow field and old/new 1.6-second whole-population handoff are removed from the runtime. Each procedural snow identity now occupies a stable point in a periodic world tile and independently selects its nearest periodic copy. The live player focus selects copies; it no longer recenters or cross-fades the complete population. This removes the moving overhead field origin and the whole-screen snow disappear/reappear event when crossing former anchor boundaries.

The 8.1.99 native `love_InstanceID` path remains intact and MAX BLIZZARD retains the full 200,000-flake target.

## Qualification

- New global cloud/RAVE/snow regression: **16/16 PASS**.
- Negative control against exact 8.1.99: **12/16 new checks FAIL as required**.
- Updated continuous snow-motion regression: **13/13 PASS**.
- Inherited RAVE/snow continuity: **12/12 PASS**.
- Maintained developer sweep: **116/116 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Shipped runtime Lua compile: **129/129 PASS**.

## Truth boundary

These are deterministic source/runtime/package-harness checks. This environment does not provide a fresh interactive Gen1Recomp framebuffer/player session on the user's exact GPU/driver, so the reported cloud-edge behavior, battle presentation and snow-field continuity still require the user's live-device visual confirmation after installation.
