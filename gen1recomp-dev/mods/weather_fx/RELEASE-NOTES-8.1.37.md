# Weather FX 8.1.37 — Integrated Storm Cloud Bank

## Why this release exists
8.1.36 solved distant-front persistence and replaced flat front cards with volumetric ellipsoid/anvil shells, but that presentation still belonged to a separate renderer. In real first-person captures the approaching storm could read as a pile of dark overlapping rounded primitives floating apart from the established Weather FX cloud bank. 8.1.37 removes that visual split instead of trying to repaint the old primitives.

## Storm-front cloud integration
- **One cloud system:** distant front cloud mass is appended to the same descriptor list that feeds the ordinary Weather FX cloud bank. It therefore uses the exact same irregular soft-puff renderer, day/night tint, storm shading, sunlight/rim response, depth buffer and cloud-transmission/god-ray occlusion path.
- **One altitude authority:** front centers use the same `deckY0 * CLOUD HEIGHT - landscapeDrop + hash * deckYSpan` equation as the live bank. A local closed deck wins during handoff; before one exists, the incoming weather family's deck supplies the same equation.
- **No vertical blob stack:** the old formation/growth/mature 48/92/118-unit tower offsets are gone. Formation is one horizontal row; mature fronts become a staggered two-row X/Z bank with deterministic overlap and ordinary deck-height variation only.
- **No dark ellipsoid material:** the dedicated `vKind > 5.5` storm shell, tessellated ellipsoid generator and special black/charcoal cloud material are removed. Storm clouds can still become naturally darker as the authoritative local weather profile transitions toward rain/thunderstorm, but they are not painted as a separate black object.
- **Stable physical identity:** descriptors are deterministic from the real finite StormCell id/stage and travel direction, use a bounded reuse pool, and preserve the 8.1.36 cloud-first lifecycle/near-field fade instead of rerolling as the player approaches.
- **Real front thickness:** mature fronts gain depth by adding a staggered second row in horizontal world space, not by stacking spheres upward. The line of cloud mass follows the real front velocity/cross-front axes.

## Distant rain and lightning
The distant-weather stream is now precipitation/fog/lightning-only. Rain/snow/fog curtain tops and remote bolt origins resolve from the same per-front deck used by the integrated clouds, so hydrometeors visibly descend from the cloud bank. Existing remote lightning, strike coordinate ownership and true-distance thunder remain intact.

## Preserved from 8.1.36
- finite fronts persist long enough to reach the player corridor and crossfade continuously into local ownership;
- cloud identity can lead the precipitation core;
- seasonal weather hard gates/weights remain unchanged;
- celestial event qualification and connected-map building light pollution remain unchanged;
- complete Weather FX water ownership, seasonal walkable ice, Surf safety and ORIGINAL handoff remain unchanged;
- the zero-quality-loss connected-water wave/foam optimizations remain unchanged.

## Performance / quality contract
DistantWeather remains capped at four observed fronts. A mature front contributes ten ordinary cloud descriptors; formation contributes four. Each descriptor uses the existing cloud-bank puff path and bounded pools. This replaces the old per-front tessellated shell workload rather than layering a second cloud system on top. No player-visible quality tier, cloud-height option, cloud-bank density, precipitation population or draw-distance setting is reduced.

## Qualification
`tests/storm_cloudbank_integration_8137_test.lua` proves the mature/formation descriptor counts, shared-bank identity, exact deck-band bounds, horizontal front spread/depth, lifecycle alpha, local-deck handoff authority and removal of the old ellipsoid/dark-material path. The inherited 8.1.36 handoff regression still proves that a remote descriptor survives continuously until local storm volume owns the fully overlapped corridor. Current runtime/package gates additionally require that `lib/voxel_atmos/CinematicAtmos.lua` is the only gameplay runtime delta from frozen 8.1.36.

Weather FX 8.1.37 does not claim to repair Gen1Recomp's separate out-of-bounds behavior.
