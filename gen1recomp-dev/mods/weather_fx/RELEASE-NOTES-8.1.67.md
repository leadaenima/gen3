# Weather FX 8.1.67 — Live Voxel Snow/Ledge + 2D Gale/Celestial Hotfix

## Built from

Exact Weather FX 8.1.66: `weather_fx-core-8.1.66.zip`, SHA-256 `6086d5ec95952d310c6aafd0926375e187c0cf3b5bf10d18e7fb9c6f189b3e65`.

## Snow accumulation / voxel repaint

Real Gen1Recomp + Voxel Nexus framebuffer testing exposed two support bugs that headless 8.1.66 qualification did not catch. First, SnowPack could inherit WorldPrecip's camera/focus Y as its fallback floor in third-person, lifting physical snow away from the terrain. Second, an authored raised ledge could be flattened by a stale/host-wrapper TileShape answer or lose all six bounded cell patch slots to ordinary ground in a mixed ground/ledge cell.

8.1.67 now:

- resolves fallback floor height from `VoxelScene.groundAt(map, player.cellX, player.cellY)` when that authoritative voxel support is available;
- refreshes TileShape authority as an in-place map hydrates instead of keeping an older shape table forever;
- preserves explicit authored TileShape pins and never downgrades a proven raised voxel support to flat ground;
- keeps the six-patch-per-cell performance cap while guaranteeing that a newly encountered distinct support (for example a height-6 ledge) can replace a duplicate from an overrepresented ground support;
- keeps raised scenery repaint-only: ledges/roofs/trees do not regain detached mound/cap geometry;
- extends the depth-resolved conformal pass to raised/ledge geometry that is rendered outside the base terrain draw;
- retains physical depth only on load-bearing ground/grass/ice where real thickness belongs;
- melts coverage back to the untouched original world materials.

The live Route 4 qualification uses real Yellow ledge tiles 54/55. The host and SnowPack both resolve their top at 6 world units while adjacent ordinary ground remains 0.

## 2D Gale tornadoes + frequency control

The 2D relocation path used a minimum opportunity clamp of 120 seconds. NORMAL/default is now exactly **90 seconds / 1.5 minutes**. At each opportunity the independent CARRY CHANCE is rolled; NORMAL CARRY CHANCE remains **10%**. A failed 10% roll simply waits until the next opportunity. No valid previously visited/escape-safe destination still means no visible relocation tornado.

New in-game **TORNADO FREQUENCY** choices:

- RARE — 180 seconds
- NORMAL — 90 seconds
- OFTEN — 60 seconds
- EXTREME — 30 seconds

The frequency setting changes opportunity spacing, not the relocation probability, destination safety rules, active-tornado cap, or direct-contact 3D pickup behavior.

## Celestial rendering independence

New **CELESTIAL RENDERING** menu choices:

- MATCH WEATHER
- 2D SKY
- 3D WORLD

This separates sky/celestial ownership from precipitation presentation. Players can explicitly select **2D weather + 3D world-space sun/moon/stars/planets/constellations**.

When 2D SKY is used inside a voxel scene, sun/moon screen coordinates now come from the actual voxel camera basis. Camera yaw therefore changes where a fixed world-space body appears on screen instead of dragging the sun or moon along with the camera.

## Preserved behavior

8.1.66 conformal tree/terrain snow repaint, 8.1.65 remote tornado roaming, existing safe tornado transfer, water/ice, weather fronts, 29-weather catalogue, weather audio, gameplay collision/encounters/battle/progression authority and existing quality/performance ceilings remain preserved unless described above.
