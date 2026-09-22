# Weather FX 8.1.88 — Weather-World Interaction

Built directly from exact Weather FX 8.1.87.

## World interaction upgrade

8.1.88 adapts the strongest weather/world-interaction ideas identified in the Terrarium reference into Weather FX's existing authorities rather than importing a second weather engine.

- Rain striking raised voxel support can feed a bounded roof-runoff path that resolves toward stable nearby eaves. Eave beads hang briefly, fall in world space, and can continue after rainfall has stopped while retained roof water drains.
- Tree canopies retain intercepted rain and shed delayed branch drips. The existing permeable-canopy contract remains intact: drops selected to pass through the crown continue toward the true ground rather than being re-caught at canopy height.
- Rain impacts now resolve surface response from the same live support classifier used by Weather FX snow/terrain interaction. Water receives broad ripples without fake wet deposits; grass absorbs into smaller short impacts; ice receives a sharp response; pavement/stone/metal/wood/roof and ordinary soil use bounded differentiated impact profiles.
- Strong world wind can create one travelling gust-front descriptor and depth-tested 3D gust band. Its center and direction live in canonical world coordinates, so camera heading/pitch cannot move or respawn it. Visual character follows the active environment: rain spray, loose snow, dust, ash, or restrained leaf/air disturbance.
- Existing cloud-aware solar shafts receive a restrained post-rain clearing gain. Weather FX still uses its established cloud-transmission tests and sunlight authority; recent rain only increases the opportunity/intensity of shafts when the sun is genuinely breaking through.
- Environment SDK v5 publishes vegetation wet load, snow load, sag, wind bend, gust phase/strength, retained roof/canopy water, post-rain shaft state, and the live gust-front descriptor. Companion voxel renderers can react without Weather FX modifying their meshes or taking NPC/gameplay ownership.


## 2D weather + options synchronization repair

Two release-blocking live-use defects found during 8.1.88 qualification are also fixed:

- **2D OVERLAY now owns the final frame.** On voxel hosts, forced classic 2D weather no longer paints into an intermediate `worldPresent` target and then marks the frame as already handled. That could make every 2D weather family disappear when the host later replaced/composited that world target. Forced 2D now deliberately defers to the final `present()` compositor. First-person remains 3D-authoritative.
- **OPTIONS WEATHER no longer needs Mod Manager to wake up.** Weather FX now polls the engine WEATHER ladder from the always-running HUD seam, so an OPTIONS edit is observed even if a UI mod or generation-specific menu bypasses the decorated row callback.
- Re-registering the Weather FX option schema no longer wipes already-live runtime mirrors while the loader option cache is stale.
- The custom Weather FX OPTIONS submenu mirrors edits into the real `src.core.Game` mod-loader caches even when the screen is handed a lightweight game facade without `.mods`. Opening Mod Manager is therefore no longer required to make those settings become live.

## Performance/ownership constraints

- Secondary drip pool is capped at 128 beads.
- Expensive roof-edge searches are capped at 3 per precipitation update; each search walks at most four cells in each tested direction.
- Post-rain residual source discovery uses at most two local support samples per update and never scans the map for roofs or trees.
- The gust-front mesh is only 8 segments / 48 vertices while active.
- Weather-world state is O(1) and updates every frame so moving gusts do not stair-step.
- Existing weather selection, WindEngine, EnvironmentSurface, SnowPack, cloud rendering, precipitation ownership, NPC behavior, and companion geometry remain authoritative in their existing domains.

## Qualification

- New 8.1.88 focused tests: 36/36 PASS.
- Segmented maintained developer sweep: 92/92 programs PASS (83 Lua programs, 8 Python tools, plus `test_mod.py --lua`).
- `test_mod.py --lua`: 191 passed, 0 failed, 0 skipped.
- Shipped runtime Lua parse: 128/128 PASS.
- LuaJIT WorldPrecip update guard: 51 estimated direct upvalues; ship ceiling 55, hard ceiling 60.
- 8.1.87 negative control: all 8 expected-absence checks PASS.
- Existing rain ledge/map-edge/rendered-world, RAVE world-space, battle weather, snow, clouds, lightning/tornado, celestial, water/wind, audio, settings, performance, and voxel-host checks remained green.
- 2D/options negative control on the pre-fix 8.1.88 candidate: 0/4 PASS, proving all four repaired behaviors were absent.

No fresh live-game framebuffer/device session was available for this update. Qualification is executable harness/source/package evidence and does not claim a manual visual playtest of the new effects.
