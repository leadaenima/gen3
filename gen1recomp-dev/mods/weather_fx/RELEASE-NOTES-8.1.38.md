# Weather FX 8.1.38 — Living Ponds / Complete Void Ocean

## Why this release exists

Two water presentation gaps remained after the Professional Physical Water series. Small authored ponds still read as opaque broad-water surfaces, so there was no sense of shallow depth or life below the surface. Separately, the 8.1.34 `VOID FILL = WATER` repair correctly replaced Gen1Recomp/Voxel Nexus's finite three-block / 96px synthetic apron, but current Voxel Nexus also draws a much larger `WorldUnderlay`. Past that finite apron, the player could therefore still see a flat/native-looking outer water strip at the horizon.

8.1.38 closes both gaps without granting synthetic water any gameplay authority.

## Living translucent ponds

- Only **authored connected bodies classified as `POND`** enter the new pond pass. Lakes, rivers, seas and all visual-only water stay on their existing appropriate paths.
- The real host reflection/water shader is retained, but pond surface alpha is **46–54%**: smaller ponds are clearest, while larger pond-class bodies keep slightly more reflective mass.
- A shallow procedural silt/stone bed is drawn below the surface so transparency reveals bounded depth rather than empty void.
- Each pond gets **2–6 tiny deterministic 3D fish**, with a hard connected-world cap of **24 whole fish**. The fish are decorative environmental geometry, not Pokémon encounters or saved entities.
- Every fish loops wholly inside one authoritative authored **16px water cell**. It cannot swim through a bank, into a road, or into synthetic void water.
- Fish remain below the physical surface and are suppressed once pond ice reaches the substantial-closing stage.
- The pond pass bypasses the voxel host's optional opaque curved-water depth prepass so that bed/fish detail is not hidden before the translucent reflective surface is drawn. Existing terrain depth still occludes submerged detail correctly.
- The specialized pond draw is **fail-open**: if it cannot complete on a host, Weather FX immediately hands those pond draws back to the ordinary host water path instead of leaving a hole.

## Complete `VOID FILL = WATER` ownership

- The exact inherited **three-block / 96px** synthetic apron and neighbour overlap masking remain intact.
- When the live overworld uses `VOID FILL = WATER`, Weather FX additionally publishes one presentation-only **outer sea** extending to **32768 world units**, matching the current Voxel Nexus `WorldUnderlay.RANGE`.
- The outer sea cuts holes for every loaded real map rectangle and begins outside the already-owned finite apron, preventing duplicate water over authored terrain.
- It reuses the finite void sea's exact tide and physical wave state, so the 96px apron and far horizon belong to one continuous moving sea instead of meeting a static strip.
- Distance-adaptive indexed tessellation keeps detailed geometry near the playable world while aggressively coarsening the far horizon. The final representative 8.1.38 contract fixture uses **5,576 vertices / 32,472 indices**, but only **576 near-corridor vertices** receive live CPU physical-wave displacement; the far field stays on the shared tide datum and receives reflective/fine wave detail from the existing host Water shader. These are topology/workload diagnostics, not a whole-game FPS claim.

## Gameplay safety

The outer sea is strictly **presentation-only**. It never enters the authored water-cell map and therefore cannot create:

- Surf destinations or Surf permission;
- movement/collision support;
- freezing or load-bearing ice;
- SnowPack support;
- puddle/hydrology state;
- encounters, warps or progression.

`WATER STYLE = ORIGINAL` remains an immediate ownership release: the host's untouched water and world-underlay presentation return without a restart. Changing live `VOID FILL` away from WATER removes both the finite synthetic apron and the outer Weather FX sea.

## Runtime scope

The intended gameplay-runtime delta from exact 8.1.37 is exactly three modules:

- `lib/ConnectedWater.lua` — presentation-only outer-sea authority and shared wave/tide publication;
- `lib/voxel_atmos/ConnectedWater3D.lua` — adaptive outer physical mesh, translucent pond bed/fish/surface pass and diagnostics;
- `lib/DramalessAtmos.lua` — shared multi-host water routing that separates ponds from ordinary water and fails open safely.

All 8.1.37 Integrated Storm Cloud Bank behavior and the earlier Professional Physical Water, persistent whitewater, seasonal ice, Surf safety, weather, celestial, audio, battle, season and performance contracts are retained.

## Qualification boundary

The dedicated 8.1.38 regression proves pond classification, alpha bounds, bed/fish ordering, whole-fish workload cap, authored-cell confinement, ice suppression, visual-only exclusion, complete outer-sea ownership, 32768 radius, exact 96px handoff, map holes, shared wave/tide state, gameplay exclusion, multi-host routing and fail-open behavior. The inherited connected-water, void-water and player-safety suites are also retained.

The final release is additionally qualified on the actual Gen1Recomp 0.2.53 / LÖVE 11.5 rendering path with Pokémon Yellow and the preserved Voxel Nexus 2.0.8 package. Visual A/B captures compare 8.1.37 against 8.1.38 at the outside-water horizon and at an authored Fuchsia City pond. Known inherited optional/private Voxel Nexus namespace probes remain diagnostic warnings; they are not introduced by this water revision.
