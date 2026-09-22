# Weather FX 8.1.41 — Reachable World-Scale Storm Fronts

## Why this release exists

The persistent world-front engine was already moving real weather through connected world space, but three presentation/lifecycle choices made it feel wrong from the player's perspective:

- `DistantWeather` deliberately drove a remote front's `nearFade` to zero over the final 320 world units, so the front visibly dissolved as the player approached it;
- generated systems were comparatively small and the 3D cloud-bank presentation was capped to a small patch even when the physical footprint was larger; and
- translation/lifetime targeting was centered on the original player position and the storm center, which could make fronts move too quickly, weaken before useful contact, or miss a player who had continued travelling.

8.1.41 repairs those problems as one world-scale storm-front system.

## Four physical front scales

New fronts are classified as **cell, regional, broad or synoptic**. Every class uses an elongated cross-front footprint rather than a near-round blob:

- **Cell:** localized weather, roughly 280–520 units deep and 420–760 units across;
- **Regional:** roughly 500–860 deep and 820–1,440 across;
- **Broad:** roughly 760–1,280 deep and 1,450–2,500 across;
- **Synoptic:** roughly 1,050–1,810 deep and 2,500–4,400 across.

Large fronts also move more slowly than compact cells, so a broad horizon-spanning system reads as mass weather rather than a fast travelling object.

## Slower, reachable world motion

The old roughly 5.5–18.5 world-unit/second motion has been replaced by a much slower size-dependent envelope. Generated fronts are bounded to about 0.75–4.10 world units/second at spawn, with the live target speed remaining in the same slow range.

Spawn distance and lifetime are now solved from the **leading edge**. The system gets enough life to bring its precipitation footprint to the player while it is still meteorologically useful instead of merely ensuring that the center could eventually cross the old target point.

Before contact, an incoming front may make a bounded real-world course correction toward the player's current connected-world position. It does not teleport or camera-lock: the correction has a finite per-second travel budget and stops once the footprint reaches the player. This makes both directions of interaction possible: the storm can reach a stationary/travelling player, and a player who walks toward it can physically intercept it sooner.

## No more approach disappearance

The old zero-at-contact `nearFade` is gone. A front retains full remote cloud visibility until its physical footprint reaches the player. Once the player is actually inside the system, cloud density hands off gradually to the local bank but retains a visible remote floor; the precipitation curtain can retire more aggressively inside the footprint to avoid double rain. The meteorological object itself therefore remains continuous instead of vanishing before arrival.

## World-scale 3D presentation

The integrated 8.1.37 shared cloud-bank renderer is preserved. It now:

- anchors the distant bank on the nearest physical leading edge rather than hiding the visible formation at the cell center;
- scales bank width from the true cross-front radius rather than the former small hard cap;
- increases descriptor coverage for broad and synoptic systems, with a mature synoptic front using sixteen bounded shared-bank descriptors; and
- keeps all remote fronts inside the same live cloud-deck altitude authority used by ordinary Weather FX clouds.

No legacy standalone dark storm-volume renderer is reintroduced.

## Preserved systems

8.1.41 changes only `lib/StormCells.lua`, `lib/DistantWeather.lua` and `lib/voxel_atmos/CinematicAtmos.lua` relative to the exact 8.1.40 runtime baseline. The 8.1.40 exclusive VOID-water handoff, 8.1.39 universal voxel-host water ownership, 8.1.38 living ponds, physical water, ice, Surf safety, precipitation, lightning, seasons and celestial systems remain intact.
