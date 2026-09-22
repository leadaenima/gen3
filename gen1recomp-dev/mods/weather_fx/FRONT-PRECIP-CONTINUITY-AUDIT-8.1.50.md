# Weather FX 8.1.50 — Front Precipitation Continuity Audit

## Scope

The reported defect was visual continuity: a regional rain/snow front could approach as a long-range precipitation sheet and then visibly change when the player-local 3D precipitation system became authoritative. The acceptance criterion is stricter than “both effects exist”: **a player watching the front approach must not be able to identify a far/near effect swap**.

## Implementation

The physical StormCell is now the common identity for both sides of the handoff.

`lib/voxel_atmos/CinematicAtmos.lua` no longer creates rain/snow/blizzard front cards for hydrometeors. It generates bounded, deterministic world-space particle quads inside the actual moving front slab. Rain uses streak morphology in the same physical size family as local WorldPrecip rain. Snow uses flake morphology in the same 0.17–0.48 world-size family as local snow; blizzard flakes gain gust shear but remain individual flakes.

`lib/DistantWeather.lua` preserves the remote field through a broad 62% penetration overlap. Remote authority is alpha/density handoff only; particle identities/coordinates are stable. The local WeatherState/WorldPrecip system remains the near-field authority and is not replaced.

## Automated qualification

Dedicated 8.1.50 regression: `tests/front_precip_continuity_8150_test.lua`.

It proves:

- rain front = dense discrete 3D rain vertices, not the old rain card;
- snow front = discrete 3D flakes, not the old snow card;
- blizzard = wind-sheared flakes, not the old blizzard wall;
- front particles occupy real depth behind the moving leading edge;
- handoff reduces opacity without moving/replacing particle identities;
- the 62% overlap is present in the production DistantWeather path.

The test was also copied onto untouched exact 8.1.49 as a negative-control check. Exact 8.1.49 failed **6 of 9** assertions, including all rain/snow/blizzard discrete-particle requirements. The current 8.1.50 candidate passes **9/9**, demonstrating the test detects the actual change rather than merely restating existing behavior.

Inherited front/cloud suites also pass after the change, including storm handoff volume, shared cloud-bank integration, physical front scale/rendering and winter snow-front scheduling.

## Real Gen1Recomp qualification

Stack:

- Gen1Recomp 0.2.53 Linux x86_64 AppImage;
- user-supplied Pokémon Yellow ROM / existing legal test cache;
- Voxel Nexus 2.0.12;
- Weather FX 8.1.50 candidate runtime, installed over the exact 8.1.49 test identity for controlled qualification.

The final rain and snow drivers placed one controlled regional StormCell in Pallet Town and advanced it toward the fixed player at **3 world units/second**, updating WeatherState at 30 Hz. Frames/logs were sampled at cell-centre distances 450, 370, 330, 300, 250 and 180.

### Rain

- d=450: remote shaft 1.00000; local rain 0
- d=370: remote shaft 1.00000; local rain 0
- d=330: remote shaft 0.95066; local rain 0
- d=300: remote shaft 0.82206; local rain 0
- d=250: remote shaft 0.51075; local rain **1,626**
- d=180: remote shaft 0.09788; local rain **8,819**

### Snow

- d=450: remote shaft 1.00000; local snow 0
- d=370: remote shaft 1.00000; local snow 0
- d=330: remote shaft 0.95066; local snow 0
- d=300: remote shaft 0.82206; local snow 0
- d=250: remote shaft 0.51075; local snow **8,841**
- d=180: remote shaft 0.09788; local snow **49,702**

The six-frame rain and six-frame snow contact sheets were manually inspected. The far front contains small world-space drops/flakes before local precipitation exists; as it reaches the player those hydrometeors become increasingly apparent while local precipitation rises underneath them. There is no frame in the qualified sequence where a broad precipitation sheet vanishes and a separate local effect appears.

## Honesty boundary

The live sequence is a controlled physical StormCell approach in the actual Gen1Recomp/Yellow/Voxel Nexus render stack, not a claim that every random naturally generated front path in every supported voxel host has been watched by a human from horizon to dissipation. Cross-host source/runtime regressions remain part of the full release suite. Driver-specific GPU appearance on every device still depends on that device.

Audio is unrelated to this change and is not requalified as a listening test here.
