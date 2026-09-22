# Weather FX 8.1.65 — Persistent Cross-Map Tornado Roaming

## What is fixed

8.1.64 could preserve and rebase a tornado across a direct current-map transition, but the tornado simulation still depended on the voxel renderer's **current map + immediate neighbors**. If the player moved two or more connected outdoor maps away while a funnel remained behind, that funnel could reach the edge of the available live render snapshot and become effectively pinned there.

8.1.65 separates persistent storm location from the current render root:

- each active 3D funnel keeps `mapId + mapX/mapZ` map-local ownership in addition to its visible root-frame `x/z`;
- when its map falls outside the current+neighbor render set, the same entity keeps aging and moving off-screen instead of freezing;
- off-screen movement follows authored outdoor map connections and respects connection offsets/real outer boundaries;
- remote movement never samples or collides against the player's unrelated current voxel root;
- once the funnel reaches a map that is current or an immediate rendered neighbor, the same entity is reprojected at the correct physical map edge;
- re-entry preserves identity, stage, age, roam lifetime, spin/water state and crossing telemetry instead of respawning;
- fully remote funnels submit no Tornado3D mesh vertices, avoiding invisible geometry work.

## Preserved behavior

- 2D GALE tornadoes remain relocation-only screen events; no 3D world tornado is created in 2D presentation.
- 3D walk-in pickup, the normal 10% committed seeker, native player input lock, escape-safe visited-map transfer, Surf rules, waterspout conversion and gentle landing/rope-out remain unchanged in behavior.
- 8.1.64 SnowPack restoration and precipitation virtualization are unchanged.
- No tornado count, visual density, particle ceiling, or weather catalogue setting was reduced.

## Qualification

- New remote map-roam regression: **12/12 PASS** on 8.1.65. Exact 8.1.64 negative control fails 8 checks.
- New off-screen render-cull regression: **4/4 PASS** on 8.1.65. Exact 8.1.64 negative control fails 2 checks.
- Maintained 3D Gale tornado suite: **38/38 PASS**.
- Tornado pickup semantics: **20/20 PASS**.
- Tornado map persistence: **10/10 PASS**.
- Real transfer: **5/5 PASS**.
- Walk-contact: **8/8 PASS**.
- Safe destinations: **23/23 PASS**.
- Waterspout presentation: **5/5 PASS**.

The exact 8.1.65 delta is qualified through executable Lua/headless contracts and package/static gates in this build environment. 8.1.64's earlier real Gen1Recomp/Voxel Nexus visual proof remains inherited evidence for unchanged presentation paths; this release does not falsely claim a new manual framebuffer capture for the off-screen-only behavior.
