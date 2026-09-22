> Current release: **8.2.14** removes the former RAVE weather mode from Weather FX. The RAVE selector entry, soundtrack, strobe/music settings, 3D laser/fog/floor rig, battle carryover, and bundled rave audio are no longer part of Weather FX; the standalone Poke Rave mod is unaffected.

> Current release: **8.2.4** fixes the remaining full-path 3D snow performance failures found by executable audit: accumulation OFF now truly bypasses SnowPack/support work for pure snow, accumulation ON stages slow ground/support work near 10 Hz, procedural GPU snow uses only tiny interaction telemetry, and failed GPU snow is capped to per-quality CPU budgets instead of ever routing the 100k/200k logical storm through CPU simulation. 8.2.3 screen-space LOD, smooth per-frame movement, full render distance, no-emitter continuity, and all RAVE/cloud/celestial/battle fixes remain intact.

> Current release: **8.1.93** repairs 3D NPC lightning on the current Battle Art voxel fork by observing Battle Art's exact host-resolved actor list through its public `CharacterRenderers.afterActors` seam before Weather FX world lightning is allocated. NPC strikes now use the same position/support/lift/facing records Battle Art actually rendered, without a second `pose()` call or any NPC/gameplay mutation. The configured CHARACTER STRIKES / STRIKE CHANCE behavior remains default ON / 10%. All 8.1.92 snow-distance and 8.1.91 Battle Art water fixes are retained.

> Current release: **8.1.92** makes the 3D snow field follow the live voxel render distance even with WEATHER FRONTS ON. At the default **3D WEATHER DISTANCE = 100%**, snow reaches the exact host far plane instead of stopping at the old 750-unit front radius, so the player cannot walk into a dry ring before the rendered world ends. 25/50/75% remain intentional distance reductions. The 8.1.91 one-pixel snow and Battle Art water fixes are retained.

> Current release: **8.1.91** fixes the remaining one-pixel 3D snow fountain by making player-local snow the exclusive nearby presentation owner, and fixes current Battle Art water overlap by correctly distinguishing its modern Water API from Voxel Nexus and invalidating compiled host wave relief when Weather FX takes physical-water ownership. It retains all 8.1.90 feature-aware runtime, BLOCKY-cloud and full RAVE upgrades.

> Current release: **8.1.88** adds physical weather/world interaction (roof runoff, canopy after-drips, material impacts, travelling gust fronts, post-rain shafts and vegetation-load interoperability) and fixes two live-use blockers: forced **2D OVERLAY** now renders on the final frame in voxel hosts, and OPTIONS WEATHER changes no longer require opening Mod Manager before they become active.

> Current release: **8.1.78** makes WEATHER FRONTS OFF rain a complete rendered-world field: 100% exactly matches the live voxel render distance and absolute world-grid rain covers the full rendered X/Z window instead of a player-centred circle.

## 8.1.68 — Distributed Coalescing Snow Banks

8.1.68 fixes the visible snow-accumulation lines and startup burst around the player. Aggregate snowfall now ramps in over 45 seconds, spreads support samples across a wide golden-angle field, merges overlapping same-surface deposits into broad flatter banks, preserves bank mass for the entire active snowfall, while preserving the exact 8.1.67 snow accumulation height profile. See `RELEASE-NOTES-8.1.68.md`.

## 8.1.67 — Live Voxel Snow/Ledge + 2D Gale/Celestial Hotfix

8.1.67 fixes the live snow height/ledge path exposed by real Gen1Recomp framebuffer qualification, gives 2D Gale a 90-second NORMAL tornado opportunity cadence with a player-facing TORNADO FREQUENCY control, fixes camera-locked 2D sun/moon projection, and adds independent CELESTIAL RENDERING so 2D weather can use the full 3D celestial system. See `RELEASE-NOTES-8.1.67.md`.

## 8.1.65 — Persistent Cross-Map Tornado Roaming

8.1.65 fixes 3D Gale tornadoes becoming pinned when the player travels beyond the renderer's current-map + immediate-neighbor field. Funnels now keep map-local world ownership, continue through authored outdoor connections while off-screen, consume no Tornado3D geometry until visible again, and re-enter as the same persistent storm entity. See `RELEASE-NOTES-8.1.65.md`.

## 8.1.64 — Complete Player/Visual/Performance/System Audit + Live SnowPack Restore

8.1.64 restores bounded live 3D SnowPack accumulation/banks/footprints while preserving procedural/GPU precipitation performance, and requalifies all player settings, the full 29-weather 2D/3D catalogue, major events, performance and system/engine contracts. See `RELEASE-NOTES-8.1.64.md` and `WEATHER-FX-8.1.64-COMPLETE-PLAYER-VISUAL-PERFORMANCE-SYSTEM-AUDIT.md`.

# Weather FX 8.1.63 — Tornado Pickup Ownership / Committed Seeker

## What is fixed

- **2D remains screen-space only.** No 3D/world-space tornado is created in 2D presentation. When the configured pickup chance succeeds, controls lock before the funnel approaches, the funnel sweeps left-to-right, carries the player through blackout to a different proven-safe visited map, sweeps the player into the destination, then releases controls.
- **3D walk-in pickup is physical.** Walking into the visible footprint of an ordinary mature roaming funnel triggers suction/pickup independently of the 10% seeker roll.
- **3D seeker is now committed.** The NORMAL 10% roll creates one seeker at the normal 150–250px spawn distance. It homes toward the live player and static scenery can no longer kick it sideways forever. Ordinary non-seeker tornadoes retain scenery deflection.
- **Native control ownership is complete.** Weather FX asserts `player.inputLocked` for the full 2D sweep and 3D pickup/carry/landing and also guards Gen1Recomp's overworld input seam, preventing directional input, Voxel Nexus FreeMove, A, or START from being accepted during carry—including the frame after `setMap` reconstructs/reset player state.
- **Pickup matches the visible funnel.** Both walk-in contact and committed seeker capture use a minimum 30px physical footprint instead of an invisible 13–14px centre bullseye.

## Real-runtime qualification

Using preserved Gen1Recomp 0.2.53 / LÖVE 11.5, the preserved user-provided Pokémon Yellow input, and exact Voxel Nexus 2.0.16:

- **2D:** zero 3D tornado objects; `approach → sweepout → blackout → sweepin → exit`; Pallet Town → Viridian City; real UP + START attempts rejected during source and destination carry; controls restored after drop.
- **3D walk-in:** ordinary non-seeker at 32px; real held UP moved the player into the footprint (`py 224 → 222`); pickup began with `player touched active tornado / suction pickup`; visible lift increased `2.32 → 5.49`; movement + START rejected; Pallet Town → Viridian City; controls restored after landing.
- **3D seeker:** NORMAL pickup chance verified as 0.10; seeker spawned at exactly 150px; with the player stationary it closed `150 → 0` in 484 logic observations, began pickup by itself, visible lift increased `2.00 → 3.88`, movement + START were rejected, and Route 1 → Viridian City completed before landing/unlock.

The permanent 8.1.63 regression deliberately marks the seeker's entire approach corridor as solid scenery. Exact 8.1.62 fails that corrected pickup-semantics test (11 failures); 8.1.63 passes 20/20.

# Weather FX 8.1.62 — Tornado Walk-In Contact

- Fixed the remaining real-player 3D tornado contact defect: walking into a roaming mature funnel now reliably starts the existing safe relocation sequence.
- Gameplay collision reads the live overworld player before the voxel render snapshot, so a copied/stale renderer pose cannot make the tornado miss the player.
- Contact matches the visible ground circulation (debris/waterspout footprint + player body) instead of requiring the player anchor to enter the old 14px core.
- Swept relative-motion contact prevents fast/free-move traversal from tunneling through a tornado between update samples.
- The 10% CARRY CHANCE still controls seeker/hunting tornadoes; deliberate physical contact with any mature active 3D funnel is hazardous independent of that random roll.
- 8.1.61's verified live Gen1/Gen2 map-transfer authority, visited-map safety, 2D tornado relocation, Surf safety, persistence, and unrelated weather systems are preserved.

# Weather FX 8.1.61 — Tornado Real Map Transfer

**New in 8.1.61:** fixes the actual shared 2D/3D tornado carry bridge. A tornado carry now performs a real live-overworld map swap and verifies that the destination became active instead of accepting a queued warp request as proof. Tornado destinations also use Weather FX's own persisted, escape-safe outdoor visit history rather than relying only on Gen1Recomp's fly-town visit table.

See `RELEASE-NOTES-8.1.61.md`.

# Weather FX 8.1.60 — 2D NPC Lightning / Visible Strike Smoke

**New in 8.1.60:** 2D lightning can now visibly strike real on-screen outdoor NPCs. The normal lightning event is preserved; the existing CHARACTER STRIKES chance may redirect that bolt to the NPC's live head/upper-body screen position. A struck NPC gets the cartoon electrocution/charred reaction and a readable smoke plume, then returns to normal automatically. The same smoke visibility repair is applied to 3D NPC strikes without changing the existing 10% / 3-second house rule or NPC gameplay state.

See `RELEASE-NOTES-8.1.60.md`.

# Weather FX 8.1.59 — Snow Point-Plume Repair

**New in 8.1.59:** fixes the narrow vertical snow fountain visible during 3D snowfall. The real full-world snow field was correct; a second distant StormCell snow slab could remain visible during the local handoff and perspective-compress into a tiny column. Remote snow now fades only when local WorldPrecip has genuinely become visible, then retires completely once local snow owns the view. The authored broad snowfall population, density, anchors and motion are unchanged.

The shared voxel bridge also resolves Weather FX's private `DistantFrontPrecip` GPU backend directly instead of first probing the host and unnecessarily taking the CPU fallback.

See `RELEASE-NOTES-8.1.59.md`.

# Weather FX 8.1.57 — 2D Gale Relocation Tornado

**New in 8.1.57:** Flat 2D Gale can now produce a real relocation tornado. The event is never decorative: Weather FX first approves a carry and chooses an escape-safe map the player has already visited. Only then does the tornado enter from the left, cross the screen, engulf the player, relocate them through the existing safe warp path, and continue off the right side on the destination map. No carry = no 2D tornado. Other windy weather cannot spawn it.

# Weather FX 8.1.56 — Seamless Battle Precipitation Handoff

**Current preserved baseline:** **8.1.56**. Entering a battle during snow/rain no longer lets the overworld precipitation field jump into the battle camera, stop, then restart as a separate battle layer. Battle ownership is frame-live, the world field freezes before any transition-camera re-anchor, and the battle compositor begins from the already-active battle weather on its first frame. 8.1.55 snow motion/density and 8.1.54 GPU virtualization are unchanged.

See `RELEASE-NOTES-8.1.56.md`.

# Weather FX 8.1.55 — Smooth World-Anchored Snow Motion

**Current preserved baseline:** **8.1.55**. Snow and blizzard now fall on a dedicated monotonic presentation clock and stream through fixed world-space snow fields instead of dragging a procedural volume with the player. Crossing a snow streaming boundary transfers the unchanged particle population between two immutable world anchors, removing the visible snap-back/recentre and close-range stutter introduced when 8.1.54 made the GPU field the complete visible snow layer. Particle counts are unchanged. Snow ground collision remains temporarily disabled.

See `RELEASE-NOTES-8.1.55.md` and `PERFORMANCE-AUDIT-8.1.55.md`.

---

# Weather FX 8.1.54 — Full-Visual Precipitation Virtualization / Snow Collision Suspension

**Current preserved baseline:** **8.1.54**. On a driver-proven procedural precipitation backend, the GPU now owns the complete visual rain/snow/hail/sand/ash population while Lua retains only bounded interaction probes (rain <=96, snow <=96; hail/sand/ash zero visual cards). Authored particle ceilings are unchanged. Retired CPU pools are compacted after handoff. Broken snow ground collision/settling/banks/footprints are temporarily disabled while falling snow remains fully visible. See `RELEASE-NOTES-8.1.54.md` and `PERFORMANCE-AUDIT-8.1.54.md`.

---

# Weather FX 8.1.53 — Spatial Cloud-Sun Terrain Lighting

8.1.53 fixes cloud-broken sunlight incorrectly brightening the entire rendered voxel map. Player-local cloud transmission now affects only the local sky/discs/rays; shared world sunlight uses bounded regional cloud coverage, while terrain receives rotated cloud-body shadow masks in world space. This means sunlight through a gap stays spatial instead of becoming a map-wide light switch. The pass remains low-end bounded (maximum 18 cloud descriptors × 4 terrain lobes) and preserves every 8.1.52 storm-front/audio/persistence behavior and all prior quality/population limits.

See `RELEASE-NOTES-8.1.53.md`.

# Weather FX 8.1.52 — Independent World-Space Storm Fronts / Physical Audio & Cloud Continuity

8.1.52 makes storm fronts persistent world-space entities instead of player/camera-following weather effects. Front rain audio remains at full spatial gain through the physical precipitation footprint and fades only after exit; indoor building occlusion now retains at least 40% of that distance-adjusted weather bed. Front clouds move every frame and form/part continuously without teleport-filling the sky, while remote rain uses a monotonic downward world-space clock. CYCLE is now a persistent fallback only when WEATHER FRONTS is OFF: enabled fronts suspend the CYCLE timer and own world weather, while choosing a named weather automatically turns fronts OFF. The 8.1.51 9,000-particle MAX front budget, 62% handoff and zero-upload instancing path are preserved.

See `RELEASE-NOTES-8.1.52.md`, `RELEASE-NOTES-8.1.51.md`, and `PERFORMANCE-AUDIT-8.1.51.md`.

## Weather FX 8.1.47 — Flat-Voxel Zero-Quality-Loss Runtime Pruning

8.1.47 removes continuous CPU/GC work that does not feed the current voxel renderer while preserving the exact 8.1.46 visual and gameplay contract. Four advisory SDK/debug systems are now on-demand, the 75-cell volumetric descriptor is virtualized with exact aggregate output, static building/tree/water footprint classification is cached for WindFlow/Hydrology, and manual QUALITY no longer runs AUTO-only predictive/router bookkeeping. No authored graphics, particles, textures, water/reflections, clouds/fronts, celestial detail, constellations, aurora, snow/leaves, audio or gameplay behavior is reduced. See `RELEASE-NOTES-8.1.47.md`.


## Weather FX 8.1.46 — Seamless Water + Adaptive Low-End Performance + Correct Constellation Dimming

8.1.46 fixes the visible Voxel Nexus near/far VOID-water material seam without restoring the laggy second FULL reflection transaction; the far 32K synthetic ocean now uses Voxel Nexus' matching SKY-only water shader while the 96px handoff and authored water remain FULL reflective.

It also makes **QUALITY PRESET** a real whole-mod authority across particles, 3D precipitation radius, cloud/atmosphere detail, generated water/ice/fog texture resolution, water reflection cost, aurora geometry, celestial disc layers, Weather FX shadow precision, effect distance and background simulation cadence. **AUTO (recommended)** can adapt between POTATO and HIGH using BALANCED or AGGRESSIVE policy and a player-selected 60/50/40/30 FPS target. The new PERFORMANCE submenu exposes advanced FOLLOW QUALITY overrides for TEXTURES, WATER REFLECTIONS, EFFECT RANGE and SIMULATION without destructively changing manual choices.

Finally, constellation building dimming is corrected: fake town-centre/corner light sources are removed, voxel hosts can use real visible building/roof footprints, and all 25 constellations now become monotonically brighter as the player moves away from buildings while preserving their exact equal 8.1.43 wilderness maximum.

See `RELEASE-NOTES-8.1.46.md`.

# Weather FX 8.1.45 — Voxel Nexus Exclusive Water + VOID Performance

8.1.45 fixes Voxel Nexus' remaining old-water bleed by aligning its curved water depth and reflection submissions to the single Weather FX tide owner. It also removes a redundant FULL reflection/depth pass from the presentation-only far VOID ocean while preserving full reflective water on the 96px handoff and every authored/near body. Public Battle Art 8.1.44 ownership and all physical-water/weather/celestial quality remain preserved. See `RELEASE-NOTES-8.1.45.md`.

---

# Weather FX 8.1.44 — Public Battle Art Exclusive Water Ownership

**Current preserved baseline:** **8.1.44 — Public Battle Art Exclusive Water Ownership.**

8.1.44 fixes the remaining water overlap on the **public Battle Art Voxel Fork 1.10.1**. Public Battle Art and Voxel Nexus share the legacy `BATTLE_ART_VOXEL_FORK` id but expose different water capability surfaces. Weather FX now fingerprints the public host independently, enables its true tessellated Weather FX physical-water path, disables Battle Art's own 0..5px geometric relief only after replacement preparation succeeds, preserves Battle Art's reflection/depth pass, and retains the 8.1.40 outer-underlay suppression. `WATER STYLE = ORIGINAL` and failed preparation remain fail-open. See `RELEASE-NOTES-8.1.44.md`.

---

# Weather FX 8.1.43 — Exact Constellation Peak Brightness

**Current preserved baseline:** **8.1.43 — Exact Constellation Peak Brightness.**

8.1.43 audits all 25 traced constellations and removes the remaining maximum-brightness mismatch. The old density-based per-subject gain spread is gone: every constellation now uses the same 1.0 gain, the preserved .96/.73 landmark/trace hierarchy, and a minimally adjusted color tint with exact shared Rec.709 display luminance. At clear deep night away from buildings, all landmark stars now peak identically and all secondary trace stars peak identically. Geometry, color identity, cloud/building dimming, occlusion and twinkle remain intact. See `RELEASE-NOTES-8.1.43.md` and `CONSTELLATION-BRIGHTNESS-AUDIT-8.1.43.csv`.

---

# Weather FX 8.1.42 — Winter Snowstorms + Research-Grounded Aurora

**Current preserved baseline:** **8.1.42 — Winter Snowstorms + Research-Grounded Aurora.**

8.1.42 adds a researched season-weighted aurora system and gives frozen world fronts their own snowstorm presentation. Winter remains the primary aurora season, while every non-winter night has a deterministic 5% natural aurora chance. Aurora is built from layered thin spherical curtains with folds/rays, altitude-structured green/purple-red emission, cloud occlusion and strong-event overhead corona geometry; it is not a flat green sky ribbon. BLIZZARD and THUNDERSNOW now approach as wind-driven multi-band whiteout walls with blowing ground snow while retaining 8.1.41's slow reachable world-front motion and interception guarantees. See `RELEASE-NOTES-8.1.42.md`.

---

# Weather FX 8.1.41 — Reachable World-Scale Storm Fronts

**Current preserved baseline:** **8.1.41 — Reachable World-Scale Storm Fronts.**

8.1.41 makes distant storms behave like reachable world weather. Fronts no longer fade away during the final approach, move far more slowly, and now vary from localized cells through regional/broad systems to multi-map synoptic fronts. Leading-edge lifetime and bounded connected-world interception steering let a storm genuinely reach the player, while a player walking toward it can enter the same physical footprint sooner. The 3D bank is anchored on the incoming edge and scales with the true front width instead of collapsing large systems into a small cloud patch. See `RELEASE-NOTES-8.1.41.md`.

---

# Weather FX 8.1.40 — Exclusive Void-Water Handoff

**Current preserved baseline:** **8.1.40 — Exclusive Void-Water Handoff.**

8.1.40 fixes the remaining visible overlap between Voxel Nexus/Battle-Art's old outer VOID fill and Weather FX physical water. The host's huge `WorldUnderlay.draw()` pass is separate from `VoxelScene.drawWater`; Weather FX now preflights its VOID ocean and, only after successful preparation, suppresses that outer host underlay for the frame. The host's loaded-map safety footprints remain active, and `WATER STYLE = ORIGINAL` immediately restores the native underlay/water path. See `RELEASE-NOTES-8.1.40.md`.

---

# Weather FX 8.1.39 — Universal Voxel Void-Water Ownership

**Current preserved baseline:** **8.1.39 — Universal Voxel Void-Water Ownership.**

8.1.39 makes `VOID FILL = WATER` a Weather FX capability across every supported voxel renderer instead of a Voxel-Nexus-only last-mile hook. Battle Art / Voxel Nexus, Dramatic Shape, Dramaless Shape, Potato Voxel and the Stadium2/Gen2 overworld bridge all feed the same physical finite apron + presentation-only outer sea. Gen1 and Gen2 outdoor maps share the same authority; an optional host underlay range is consumed when present, and a no-`drawWater` compatibility path still draws only synthetic VOID water. `WATER STYLE = ORIGINAL` remains a complete fail-open handoff. See `RELEASE-NOTES-8.1.39.md`.

8.1.38 living ponds remain intact: authored ponds are translucent/reflective with shallow beds and bounded tiny 3D fish; lakes, rivers and seas retain Professional Physical Water.

---

## Weather FX 8.1.37 — World Front Continuity / Zero-Quality-Loss Performance

8.1.36 makes distant fronts physically persistent and volumetric, lets cloud/electrical structure arrive before precipitation, adds seasonal climatology and celestial-event qualification, completes Weather FX ownership of Voxel Realism water fragments, preserves seasonal load-bearing ice/thaw, fixes connected-map star/constellation light-pollution continuity, and substantially reduces water CPU/allocation cost without reducing visual quality or populations. See `RELEASE-NOTES-8.1.36.md` for executed benchmark and scope details.

8.1.35 removes the visible white-square/teleport artifact from Professional Physical Water. Whitecaps now have stable analytic identities that travel with the wave, grow/fade smoothly, and render as tapered irregular ribbons instead of rectangular threshold quads. Curling lips remain attached to the same moving crest. River rapid foam advects downstream and shoreline breakers use stable edge identities rather than time-bucket rerolls.

The repair applies equally to authored water and the 8.1.34 Voxel Realism `VOID FILL = WATER` replacement. `WATER STYLE = WEATHER FX / ORIGINAL`, physical 3D waves, reflections, Surf bob, tides, rain ripples, ice and gameplay safety remain unchanged. See `RELEASE-NOTES-8.1.35.md`.

---

# Weather FX 8.1.34 — Void Water Unification

8.1.34 extends Professional Physical Water to Gen1Recomp/Voxel Realism **VOID FILL = WATER**. The voxel host's synthetic current-map water apron is now reconstructed as a visual-only exposed sea and sent through Weather FX's actual tessellated 3D water renderer instead of remaining a flat blue strip. The reconstruction matches Voxel Realism's three-block / 96px apron and its connected-neighbour body masks.

The existing **ATMOSPHERE → WATER STYLE = WEATHER FX / ORIGINAL** player setting controls this water too. WEATHER FX replaces the flat void-water pass; ORIGINAL immediately restores the host's untouched water, including void water. Live VOID FILL WATER/TREES/BLACK changes take effect without a map transition. The synthetic sea never enters gameplay hydrology, collision, Surf, freezing/ice support, SnowPack or progression. See `RELEASE-NOTES-8.1.34.md`.

---

# Weather FX 8.1.33 — Professional Physical Water

8.1.33 fixes the connected-water presentation problem where a mathematically active water system could still read to the player as a flat blue rectangle. On the structured Voxel Realism host, Weather FX now submits a genuine tessellated 3D water mesh whose vertices move vertically and horizontally with a Gerstner-inspired multi-train wave spectrum. Cartridge water tiles still own the shoreline and gameplay collision; only the presentation surface moves.

The new renderer adds body-aware lake/sea/river/pond response, calm-water heave, large rolling crests and troughs, shoreline-pinned orbital motion, crest whitecaps, raised curling foam lips, directional river rapids, shoreline breaking foam, rain rings, preserved reflections, and Surf/player visual bob sampled from the same rendered wave. Unsupported/older hosts retain the 8.1.32 fail-open reflective-relief water path. No unrelated quality, particle population, settings range, ice behavior, or gameplay progression logic is reduced. See `RELEASE-NOTES-8.1.33.md`.

---

# Weather FX 8.1.32 — Mega Performance Audit / Zero-Quality-Loss Water Hot Path

8.1.32 preserves the complete 8.1.31 Real Rolling Water + Native Water Handoff behavior and removes proven steady-state CPU/GC waste from the connected-water path. Stable host/private module handles are cached for the lifetime of the Weather FX instance, structured water reads the hydrosphere wind vector directly rather than allocating a diagnostics snapshot, and reflective-water draw rows/translation matrices are reused on the verified Voxel Realism structured-water API. Unknown/older host APIs retain the conservative compatibility path. No authored visual population, particle count, wave relief, ripple cap, ice quality, celestial count, cloud quality, shadow quality, or setting range is reduced. See `RELEASE-NOTES-8.1.32.md`.
## 8.1.27 live-host repair

8.1.27 was the focused real-host repair built from 8.1.26 after running Pokemon Yellow in Gen1Recomp 0.2.53/LÖVE 11.5 with Voxel Realism 1.8.1. It fixed projection-safe overhead clouds, live stream-mesh growth, a dead puddle shader uniform, and the NightSky vec4→vec2 texcoord validation failure.

## 8.1.26 celestial realism + player-experience repair

Weather FX 8.1.26 is a player-experience repair release built from 8.1.25. It restores a detailed sun/moon presentation even on hosts that refuse the analytic body shader, routes 2D celestial bodies through the same detailed renderer, widens and smooths the direct-look sun optics ramp, fixes reversed physical sky-band interpolation, strengthens low-sun horizon scattering, and re-audits 2D/3D weather plus all player settings. No particle/cloud/star/constellation population or quality reductions are part of this repair.

## 8.1.25 constellation uniformity

Weather FX 8.1.25 preserves the 8.1.24 zero-quality-loss performance architecture while normalizing whole-constellation perceived brightness, spreading the closest constellation anchors farther apart, and making constellation dimming near buildings use the same BuildingLight star-scale response as ordinary stars. The approved 25-subject catalogue and complete traced star population are preserved.

## 8.1.24 zero-quality-loss performance architecture

Weather FX 8.1.24 keeps the complete 8.1.23 player experience and focuses only on removing redundant CPU/GC work. No particles, clouds, stars, constellations, planets, draw distance, quality tiers, StormCells, shadows or weather timing are reduced. Climate/support grids reuse deterministic cell data, frame consumers share exact snapshots, StormCells cache lifecycle coefficients, and static celestial/cloud-occlusion geometry work is reused instead of regenerated. See `RELEASE-NOTES-8.1.24.md` for the full preserved-output contract.

## 8.1.23 player fallback controls

The in-game **ATMOSPHERE** submenu also exposes **WATER STYLE = WEATHER FX / ORIGINAL**. **WEATHER FX** is the default connected hydrosphere with real rolling crest/trough waves, tides, rain ripples, progressive ice, and presentation-only Surf wave riding. **ORIGINAL** immediately hands rendering back to the voxel host and restores every host water tuning value Weather FX changed; Weather FX ice-walking/frozen-water presentation is masked at the same time so native-looking liquid can never become invisibly walkable. The switch persists, applies live without a restart, and does not disable rain, snow, clouds, lighting, audio, or other non-water Weather FX systems.

The in-game Weather FX menus now expose **CLOUD HEIGHT = RAISED / ORIGINAL**. RAISED preserves the 8.1.22 150% cloud deck; ORIGINAL restores the exact pre-8.1.22 altitude for lower-end devices. The rendered cloud bank, precipitation origins, world-lightning tops and tornado attachment all use the same selected height. The existing **WEATHER FRONTS** row is also upgraded into the spatial-weather master switch: OFF disables regional fronts, finite StormCells and mesoscale/localized weather together, returning the active weather to uniform full-map coverage while ordinary weather-to-weather transitions continue normally. No setting changes particle velocity, weather lifetime, game speed or transition-animation speed.

## 8.1.22 realistic moving storm cells

Weather is now physically localized in continuous world space across connected maps. A storm can occupy half of one map and half of the next, can be compact or several maps wide, has an irregular strong core and weaker edge, moves with the shared wind, and follows a five-stage lifecycle from cloud formation through dissipation. A wider/downwind cloud precursor makes approaching systems visible before rain reaches the player. The strict 3D cloud bank is 50% higher and precipitation, lightning and tornado geometry use the same raised deck. Existing 8.1.21 player controls, 8.1.20 lifetime-only WEATHER DURATION, and the 8.1.19 Weather FX-owned shadow engine are preserved.

## 8.1.21 player controls

Adds six fully wired controls: RAIN INTENSITY, WIND INTENSITY, LIGHTNING FLASH, STORM DARKNESS, TORNADO PLAYER PICKUP, and THUNDER VOLUME. These are independent controls: rain density does not change fall speed; lightning flash does not change strike frequency; tornado pickup does not change tornado spawn rate; thunder volume preserves distance/indoor acoustics.

> **8.1.20 weather-duration testing control:** Added WEATHER DURATION = NORMAL / 2X / 4X / 10X / 20X to the in-game Weather FX WEATHER submenu. Higher values make each weather expire sooner for transition testing only. Particle, wind, cloud, audio, game-time and transition speeds are unchanged; the current active weather/front timers rescale immediately.

> **8.1.18 regression-hardening / frozen-8.1.17 runtime:** The executable Weather FX runtime and shipped assets are byte-for-byte frozen to the user-approved 8.1.17 baseline. This revision adds only regression tests, semantic snapshots, package guards and test documentation; it intentionally changes no weather, rendering, celestial, audio, gameplay, settings or compatibility behavior.

> **8.1.17 constellation brightness balance:** All 25 constellations now use the exact midpoint between the original brightness (.92 primary / .64 trace) and the newer atlas brightness (1.00 / .82): **.96 primary / .73 trace**. Smooth 4–48 tile building-distance dimming/brightening remains intact. All 8.1.16 celestial, moon, sun, lens-flare, god-ray and sunrise/sunset work is preserved.

> **8.1.16 professional celestial-quality pass:** The 3D sun now reconstructs a coherent multi-scale photosphere with granulation, faculae, active-region umbra/penumbra, photographic limb darkening and cloud/geometry-gated optical bloom plus subtle lens-ghost circles when the player looks into it. The moon now uses continuous highland/maria texture, ten physical crater-relief fields, a subdued ejecta system and stronger earthshine/terminator detail. All 25 constellations share one vivid brightness hierarchy and now dim/brighten smoothly with the existing 4–48 tile BuildingLight field. Sunrise/sunset keep the 8.1.15 first-limb god-ray ramp and add stronger directional forward scattering on cloud edges.

> **8.1.15 celestial optics overhaul:** The active 3D sun/moon now use one continuous analytic body pass instead of tiled cells, removing the visible grid/seam artifact. Their base angular sizes are reduced 40% and no longer swell toward zenith. Solar god rays begin from the first visible limb and ramp continuously through sunrise/sunset independently of moon-vs-sun shadow ownership. Cloud banks now react directionally to the real solar vector with sun-facing edge scatter, warm low/facing regions, cooler backsides and physical ray attenuation through cloud descriptors instead of a flat pasted-on tint.
>

> **8.1.14 night-event + tornado-contact update:** Normal shooting stars are now limited to four isolated one-star events distributed across each full night. Meteor showers roll once at nightfall with a 10% chance, receive one random time in that night, and can happen at most once before dawn. Any sufficiently formed active 3D tornado now triggers the guarded suction/carry relocation sequence when the player physically touches its funnel footprint; the existing safe-outdoor/visited-map/Surf landing checks remain mandatory.
# Weather FX Core 8.1.13

> **8.1.13 lightning skeleton + exact constellation atlas repair:** NPC lightning x-ray skeleton flashes are now visible across ordinary 30/60 FPS sampling with thicker high-contrast bone geometry, longer readable flash phases and both supported voxel-host VP upload forms. The 14 later-added Pokémon constellations are no longer simplified redraws: their dense native star geometry is sampled directly from the approved **Pokémon Constellation Atlas.png** mockup (pinned SHA-256 `c4463a5a51b23cc400e1a99721006d567b48877bf17625cc28845e0826e14dc4`). Atlas line samples are brighter and overlap enough to reproduce the mockup silhouettes clearly while keeping the same celestial anchors, night/moonrise timing, cloud fade and world-space sky rotation.

> **8.1.12 weather/sky/precipitation reaction repair:** WEATHER OFF is a true hard disable; stars and constellations begin at moonrise and peak at quarter-night; precipitation guarantees a cloud-bearing bank/fallback path; distant snow anchor handoffs are smoothed; hail uses pellet geometry with broken-up far-field alignment; NPC strikes gain stronger flash/smoke feedback.


> **8.1.11 player-runtime integration repair:** Fixes the live handoffs that could pass isolated unit tests yet fail during ordinary play: slow/AUTO-stretched scheduler passes now run, extreme-low-FPS samples reach the adaptive governors, advanced climate uses the actual player position, shared voxel sky integration has a real host-library accessor, Kanto route-front matching is boundary-safe, AUTO/CYCLE transitions and clocks persist across saves, battle-created weather receives a fresh authoritative dwell, sunny fronts retire at night, host clock and seasons stay aligned, clock-source/day-length edits preserve sky phase, 2D weather continues around dialogue/route text, and Gold OPTIONS detection uses the actual Gen2 capability. A dedicated player-runtime regression suite guards these cross-module paths.

> **8.1.10 full settings/snow/game-speed audit:** Adds **SNOW INTENSITY** (OFF through 500%) and raises the current settings surface to **54 controls across 11 submenus**. Snow and Blizzard authored density is restored, the old generic 2.0 snow-channel clamp and one-strength WorldPrecip snow ceiling are removed, and SNOW INTENSITY OFF stays an exact zero all the way through 3D update/draw. The reported Snow/Blizzard ground-fog layer was traced to stale cinematic profile fog values; current 3D ground mist now requires an actual authored fog channel. Weather FX also no longer clamps the host `movement.speed` result to one frame, so voxel/base-game fractional fast-speed settings retain their ratios. Existing quality/hard caps are unchanged.

> **8.1.9 weather authority / persistence / sky repair:** Fixed the rain-family weather authority so ordinary **RAIN** again produces visible rainfall immediately, **HEAVY RAIN** remains heavier than ordinary rain without inventing lightning, and **PRIMAL HEAVY RAIN** restores its own thunder/lightning path at the intended 6 strikes/minute. Persistent outdoor cloud banks and 3D tornadoes now survive connected outdoor map changes, tornadoes can cross connected maps like the player, and sealed storm decks stay visible overhead instead of disappearing when the camera looks upward. The 14 added Pokémon constellations have been retraced at the same fidelity tier as the older sky set, the Poké Ball constellation has been redrawn to read more clearly, Smooth Sky is verified end-to-end, and the moon presentation path now uses the new phase-disc path cleanly without mixing the old disc.

> **8.1.8 settings/time authority + constellation rollback:** The grouped in-game menu now pushes edits through the live Weather FX setting mirror, current loader caches and the option-change event path together. Manual **QUALITY** tiers are exact and immediately invalidate the live 3D allocation budget; **PARTICLE HARD CAP** does the same. Manual **INTENSITY / FOG / SAND / DUST** edits now retarget the live effect quickly instead of waiting several seconds for the natural storm-easing constant, while ordinary weather formation/clearing remains gradual. Explicit voxel-host **DAY / NIGHT / DUSK / DAWN** pins are now treated as real clock commands: selecting NIGHT immediately updates the celestial source and restores both ordinary stars and the retained constellation geometry. The disliked 8.1.7 compact full-Kanto/Johto constellation batch has been removed; Weather FX is back to the earlier **25 high-detail constellation subjects / 3,186 constellation stars** from 8.1.6.
>
> **8.1.7 historical (reverted in 8.1.8):** The two supplied regional sheets now populate the native sky catalogue with **every Pokémon #001–#251 exactly once**. The 24 Pokémon already present keep their existing high-detail traces unchanged; the other **227 species** are added as compact traced silhouettes sampled from the supplied Kanto/Johto sheets. The result is **251 Pokémon constellations + the existing Poké Ball extra = 252 unique sky subjects / 8,634 constellation stars**. No species is duplicated. These are native star traces, not bitmap overlays, so they inherit the same sidereal world rotation, night/day fade, building light-pollution response, cloud attenuation, strict-3D depth occlusion, twinkle and quality behavior as the older constellations.
>
> **8.1.6 expanded Pokémon constellations:** The original 11 traced constellations remain intact and the second user-outline sheet adds **14 new, non-duplicate native star traces**: Poliwag, Ekans, Weedle, Pidgeotto, Rattata, Fearow, Sandshrew, Nidorino, Oddish, Vulpix, Bellsprout, Diglett, Meowth, and Psyduck. The night sky now contains **25 unique constellations / 3,186 traced constellation stars**. Charmander, Squirtle, Bulbasaur, Pikachu, Jigglypuff, and Poké Ball remain single-instance only. The new drawings are star geometry, not bitmap overlays, so they use the same sidereal rotation, time/building brightness fade, cloud attenuation, strict-3D depth occlusion, twinkle, and quality-independent identity behavior as the existing constellations.
>






> **8.1.5 immediate 3D rain visibility:** The 8.1.4 FPV camera fix was necessary but not sufficient: newly selected rain still created every physical drop at the cloud-bank ceiling at once, so a real forward-facing camera could see an apparently empty storm even though the renderer submitted geometry. The first `0 -> raining` frame now seeds the already-budgeted physical near field across realistic fall ages from the **same live cloud bank down through the fall column**, while keeping drops at the cloud origin. Every normal recycle still restarts at the cloud bank. Rain therefore appears immediately as falling world-space precipitation when selected, without adding particles, lowering quality, or turning it into a camera overlay.
>
> **8.1.4 3D rain visibility repair:** Fixed a live FPV/voxel regression where `WorldPrecip` could treat the host's player/world `focus` anchor as the camera look ray and CPU-cull every cloud-bank rain streak above the player. Rain now prefers the host's real horizontal `lookFlat` (or an explicit camera-forward vector); when no trustworthy view vector exists it skips CPU rear-culling and lets the GPU frustum/depth path clip instead. A zero-vertex near-rain pass is no longer reported healthy unless a trustworthy rear-cull actually explains it. The root SafeCall export is also bound with pcall-compatible argument semantics. New regressions require manual `RAIN_LIGHT` to spawn from the cloud-deck band and submit nonzero 3D vertices under the exact FPV player-anchor camera shape that failed in 8.1.3.
>
> **8.1.3 silent-failure hardening:** Weather FX now routes the seven largest host/render fail-soft seams through one allocation-free `SafeCall` authority. Optional-host failures still cannot crash the game, but they are now counted per module, rate-limited into the log, exposed by `engineHealth()`, and shown in FULL DEBUG HUD instead of being silently swallowed across dozens of unrelated protected calls. The strict audit's previous seven robustness MED findings are removed; only three live-only verification items remain (actual per-host 3D composition, real hot-unload, and final sun/moon visual orientation). All 8.1.2 tornado safety, rainbow and natural-wind behavior is unchanged.
>
> **8.1.2 safe tornado landings + post-rain rainbows + natural wind walking:** Tornado carry destinations are now **outdoor overworld only** and must pass an exact-cell escape proof to a real outdoor map connection; flat/empty/visited alone is not accepted, and building/cave/interior/doorway landing cells are rejected. Water-only landings—and land areas whose only proven exit requires swimming—are eligible only when the live overworld confirms Surf is available; Surf is active before control returns, and a failed activation returns the player to the saved origin rather than stranding them. Strict 3D/FPV can now form a large depth-tested primary rainbow after recent rain only when the low visible sun and clearing cloud transmission physically agree; it eases in/out and remains behind cloud/weather. Walking also consumes the existing natural WindEngine/WindFlow: strong headwind can slow normal walking by at most 10%, tailwind can assist by at most 4%, crosswind/calm are near-neutral, and bike/Surf are untouched. These add two player controls, bringing the current grouped surface to **53 player controls across 11 in-game submenus**.
>
> **8.1.1 truth-audit / host-integration repair:** A cold-source audit found two real 8.1.0 integration defects that its old mocks did not catch. Tornado mode now follows the *selected* presentation (a live voxel host with WX PRESENT=2D stays on the visible 2D funnel path; FPV still intentionally uses strict 3D), and tornado carry now uses the supported generation-aware `mod.world:warpTo(mapId, x, y, facing, opts)` API with explicit destination coordinates instead of the old one-argument private warp stub. In 8.1.2, carry candidates are further restricted to already-visited **outdoor overworld** maps with an exact landing cell that can actually escape to another outdoor map. Legacy voxel compatibility backdrops no longer invent mountain ridges or rolling relief: continuation geometry is flat. New regression contracts intentionally reject missing warp coordinates and presentation/renderer disagreement.
>
> **8.1.0 flat-world + 3D Gale tornadoes:** Strict 3D/FPV Gale can now grow real procedural tornado funnels downward from the live cloud bank. Ordinary funnels roam the flat voxel world for about 3 minutes, steer around solid building/roof footprints where possible, become water-loaded twisters over water, and rope out upward. Rare same-storm secondary/multi-tornado outbreaks are bounded to three active funnels. Each **eligible** new funnel (enough safe visited destinations, with no existing carry funnel) uses one fixed **10%** carry roll to become a distant player-seeking carry tornado; it must travel to the player before pickup, visually orbits/lifts the player while gameplay coordinates remain safe, transfers only to an already visited map, sets the player down gently, then retracts into the cloud bank. NPC lightning now adds rapid cartoon white/black flashes with an internal skeleton before the existing **10% / 3-second** black/white-eyes/smoke reaction. A new flat-world footprint authority feeds shelter/water/solid information into wind/tornado behavior without mountain assumptions or another world grid.
>


> **8.0.10 NPC-lightning tuning:** Default world-space NPC lightning targeting is now **10% per eligible bolt**, and the temporary struck reaction lasts **3 seconds**. Shipped config, embedded fallback, runtime fallback, and settings CONFIG behavior agree.
>
> **8.0.9 player settings overhaul:** Weather FX now exposes 51 validated player controls through 11 real in-game submenus: Weather, Simulation, Atmosphere, Storms, Celestial, Time & Seasons, Audio, Gameplay, Battle, Performance, and Debug. Every row has a built-in description opened with **SELECT: HELP**. Twenty-three advanced controls use a **CONFIG** default, so existing `config.lua` tuning remains authoritative until the player explicitly overrides that setting in-game. New controls cover transition speed, fronts/strength, mesoscale localized weather/strength, puddles, sun god rays, NPC lightning/chance, tornado rate, celestial events/smoothing, time source/day length, season length, indoor/thunder/wind audio, weather/legendary encounters, follower weather damage, and a particle hard cap. The NPC-lightning player control remains available; in 8.0.10 its CONFIG default is **10% chance / 3-second effect**.


> **8.0.8 mesoscale spatial weather:** Weather is no longer spatially uniform around the player. A new constant-memory `MesoscaleField` reconstructs broad moving moisture/front bands in world space between the 1,024-unit WorldClimate grid and local cloud/precipitation renderers. Natural/broken weather can now contain cloud openings and localized rain/snow/hail bands that advect with the shared WindEngine; the player-local band drives physical near precipitation, wetness/microclimate, rain audio and lightning probability, while zero-upload GPU far fields reconstruct aligned wind/front bands for visible shafts without adding particles or per-instance uploads. Authored fog can pool/thin locally, short-range forecasts account for an approaching/departing band, and established manually selected storm/rain profiles intentionally retain their immediate sealed-deck behavior. The field is O(1) memory and runs on the existing multi-rate simulation stage.

> **8.0.7 synoptic weather simulation:** Natural AUTO/front changes are now staged as evolving weather instead of a symmetric ID crossfade. Clouds/pressure/wind build before the first drops, lightning charge arrives later as a storm develops, rain can taper before the remaining deck parts and sunlight returns, and cross-family precipitation briefly overlaps instead of swapping on one frame. Strict 3D, shared world wind, rain/storm audio and lightning/thunder now follow the same live transition authority, eliminating the old target-ID precipitation/wind/audio/electrical handoffs; map crossings can no longer prematurely skip the final transition stages. Manual weather selections intentionally stay responsive: choosing a storm immediately takes ownership of the sky/cloud profile while its particle channels receive the existing short gentle intro. The planner is bounded O(1), adds no particle population/grid/fluid solver, reuses scratch state, passes live channel/meteorology state by reference, and remains inside the LuaJIT chunk-local limit.


> **8.0.6 proper lunar phases:** The moon now follows a dedicated 29.530588-night lunar calendar instead of the compressed seasonal-year index. One in-game night advances one lunar day, with the phase held stable from evening through the following morning. The rendered disc now cleanly presents new moon, waxing/waning crescents, true half-moon first/last quarters, gibbous phases, and full moon; ordinary new moon is nearly invisible while solar-eclipse silhouettes remain intact.

> **8.0.5 solar/lunar continuity + sky events:** The strict-3D sun path is release-verified, moon cell seams are removed, direct-look blinding god rays remain intact, sunrise/sunset and horizon crossings stay continuous, and rain-only 3D weather no longer inherits mist/fog extinction. Shooting stars now participate in the depth-tested strict sky, meteor showers remain, rare fireballs are added, and the lunar clock can present supermoon, harvest moon, blue moon, blood moon/lunar-eclipse and solar-eclipse events without bypassing normal phase, cloud or world occlusion.


> **8.0.4 celestial visibility/occlusion repair:** Traced constellations are bright and vivid again at night. In strict 3D, stars, constellations, planets, sun and moon are submitted at far depth after terrain/buildings/NPCs have written scene depth and before clouds/weather, so world geometry can fully occlude celestial light instead of letting it shine through. World and fallback celestial shaders now use the same far-depth + `LEQUAL` rule, and direct-look sun glare is line-of-sight gated against terrain/buildings/NPCs; all 8.0.3 weather/performance fixes remain intact.


> **8.0.2 low-end/MAX procedural virtualization:** MAX keeps every authored particle ceiling and celestial catalogue. On instancing-capable LÖVE 11 hosts, distant snow/rain/hail/sand/ash move out of Lua simulation/upload into deterministic GPU-instanced fields while a fully physical near shell preserves collision and interaction; leaves remain physical. The 5,120 ordinary stars use a static instanced catalogue in both world and zenith-stable projected paths, cloud puffs use compact per-instance data with bounded deterministic puff caches, and 2D fog reuses staging geometry. Unsupported hosts automatically use the existing CPU fallbacks. 8.0.1 zenith/audio repairs and all manual MAX quality/count contracts remain preserved. Headless tests verify code and package contracts; live FPS/final pixels still require the target voxel host/GPU.


Weather FX 8.0.9 builds on the 8.0.4 celestial occlusion repair with verified sun/moon submission, seam-free celestial discs, continuous horizon crossings, preserved direct-look solar glare, and a depth-tested celestial-event layer. Shooting stars now render in strict 3D, meteor showers remain supported, rare fireballs are available, and deterministic supermoon, harvest moon, blue moon, blood moon/lunar-eclipse and solar-eclipse events use the same phase, cloud, horizon and world-occlusion rules. Rain-only 3D weather no longer inherits a mist/fog veil; authored fog/mist weather remains unchanged.

The current night sky ships 5,120 ordinary stars, nine persistent textured/cratered planets, the crossed-X ring planet, and the restored 25-subject high-detail constellation catalogue from 8.1.6. The halo-free cratered moon, direct-look-only sun god rays, continuous rise/set, 0.25× no-reset tilted-axis rotation, seasonal 2D/3D leaves, 3D weather and near-player NPC lightning/blackening are preserved.

> **Half-speed deep-sky rotation (4.35.35):** The world-space star vault now turns at exactly 50% of the 4.35.34 rate. Stars, planets, Milky Way and Pokémon constellation geometry stay locked together on the same celestial sphere; sun/moon rise-set timing is unchanged.

> **Restored strict-3D sky + golden-hour world lighting (4.35.34):** Fixed the 4.35.33 regression that could leave strict 3D with no stars/planets on hosts that rejected the custom celestial mesh. The old pitch-squashing `Sky.region` copy stays disabled; a robust background-stage vault now projects fixed celestial world directions through the host's exact `Voxel3D.vp`, restoring stars, planets, constellations, sun and moon without camera locking. Manual NITE/NIGHT snaps the deep sky visible immediately subject to cloud attenuation. Sunrise/sunset warmth now colours the actual outdoor voxel world, direct sun viewing produces cloud-attenuated camera glare/blinding bloom, and strict 3D PSYSTORM gets the same pink-violet wash as the 2D effect.

> **4.35.33 live-world fixes:** 3D lightning NPC targeting now uses authoritative overworld actor coordinates instead of requiring a second `pose()` call, preserving the 20% per-bolt NPC chance on live Voxel Realism hosts. Active 3D voxel scenes also suppress the duplicate `Sky.paint` celestial copy, so stars/planets/sun/moon are rendered only through the world-space `Voxel3D.vp` sphere and no longer squash/spread with camera pitch.

> **Celestial scale + cloud-reactive sunset (4.35.31):** Sun and moon are 20% larger, with a slightly rounder enlarged lunar phase disc; ordinary planets are 20% smaller and Saturn/rings are 35% smaller than 4.35.30. Live local cloud-bank transmission now strongly attenuates sun, moon, planets, stars, constellations and Milky Way, including when NITE is manually pinned. Sunset colour now evolves across a broad solar-altitude range and the solid sun, haze, cloud undersides and cloud rims share the same gradual low-sun colour authority, producing a longer, more natural cloud-reactive sunset.

> **4.35.32 season timing:** accelerated Weather FX seasons now last 15 in-game days each — exactly 6 real hours per season at the default 24-minute day, for a 24-hour four-season cycle. SEASONAL leaf colour now drives both legacy/2D and 3D world-space leaves from the same season state.


> **Sand camera-pitch stability (4.35.30):** Fixed the angle-dependent sand/dust rendering seen when looking toward the ground. Sand no longer gets a downward-view size boost, extra vertical lift, or `depth=always` override. The normal soft, subtle, wind-driven sand appearance is now used at every camera pitch with proper terrain/prop occlusion.

> **Release-candidate audit + SnowPack hold (4.35.29):** Persistent snow accumulation/banks and SnowPack footprints are temporarily **disabled** while that feature is redesigned; falling 3D snow remains active and continues to collide with the real voxel/model surface before recycling. Persistent deposit/state/render staging is hard-gated off, including on MAX, and the benchmark SnowPack/footprint telemetry fields therefore remain zero in this release. A new permanent deep-release audit inventories all 28 settings, 29 weather definitions, all 9 sound assets, all 23 battle backgrounds, procedural 2D/3D animation/effect paths, quality/intensity, battle, celestial/shadows, benchmark, LuaJIT/performance, sandbox and compatibility contracts.

> **Real QUALITY/INTENSITY tiers (4.35.28):** POTATO/LOW/MEDIUM/HIGH now impose hard live 3D weather ceilings and range/accumulation/atmosphere budgets instead of only soft multipliers; new manual-only MAX unlocks the full authored particle ceilings for extreme hardware. Explicit UI QUALITY wins over stale config-file values. INTENSITY now produces a real SOFT 0.45x / NORMAL 1.0x / HEAVY 1.50x particle-strength ladder, including snow/hail/sand/ash/leaves. Psychic Storm retains near/mid/far thunder character but only every second actual bolt schedules sound, cutting dense-storm voice concurrency roughly in half.

> **Natural radial snow accumulation (4.35.27):** The square 16x16 snow-bank presentation has been replaced by bounded world-space radial mounds deposited at the exact impact point of real 3D flakes. Early snowfall appears as small round patches that merge and bleed across compatible tile seams as coverage grows. Snow now uses the host `TileShape.at()` surface authority to clip accumulation to roofs, rounded tree/canopy crowns and thin signs/props instead of floating on a whole-cell collision box; water remains completely non-accumulating. Snow no longer has a deposit-age despawn timer: while a snow-family weather is active, accumulated depth stays indefinitely. The instant the authoritative weather ID changes away from snow, a finite top-down cleanup starts and guarantees the remaining pack is gone within 90 seconds, including manual weather changes. Footprint spacing is tightened to 2.25 world units and tracks are displacement-driven, so backward/diagonal walking stamps footprints as quickly as forward walking.

> **Physical 3D snow banks + leaf ground tumble (4.35.26):** SnowPack accumulation now raises a real world-space snow surface instead of only increasing a flat white coverage layer. Ground/grass can build to a capped ~3.6-unit bank (well below player height), while roofs, trees/canopies, bushes/vegetation and thin props/signs receive shallower conforming caps. New flakes collide with the current snow top so the pack stacks upward; exposed edges taper back to the supporting geometry instead of hanging over roofs or shorelines. Water is a hard non-accumulating surface: flakes can hit it, but no snow depth, bank or footprints can be created there. The 3-minute hold remains active. Leaves also gained continuous ground collision with size-aware clearance and WindEngine-preserving bounce/tumble, preventing fast or low leaves from visually sinking through terrain.

> **3-minute snow accumulation hold (4.35.25):** Deposited SnowPack cells now remain at full depth for **180 seconds after the most recent snowfall deposit** before normal weather-dependent melt begins. Fresh flakes refresh the timer, so sustained snow has time to visibly pile up instead of fighting immediate fade. The hold uses the existing lazy analytic SnowPack path, so it does not restore an expensive per-frame scan of accumulated cells.

> **Combined-mod benchmark (4.35.24):** Weather FX now includes a repeatable in-game benchmark for testing Weather FX + the active voxel renderer on the current player-selected settings. In the developer console run `weather benchmark quick` (~30 s) or `weather benchmark full` (~2 min). It cycles deterministic heavy weather/night phases, shows a live benchmark HUD, restores the original weather/time state afterward, and reports average FPS, 1%/0.1% lows, p95/p99 frame time, stutters, Weather FX update/3D timing, draw calls, memory, particle peaks, SnowPack cells and footprints. Use `weather benchmark status`, `weather benchmark stop`, and `weather benchmark last` as needed. For LOW-vs-MAX hardware comparisons, set both mods to the target settings first and run FULL from the same outdoor location/camera.

> **Whole-mod performance pass (4.35.23):** Weather FX has been optimized across precipitation, snow/leaf accumulation, audio, WindEngine access, the 2D/3D compositors, clouds, module ownership and GPU uniform traffic **without lowering visual/audio/animation quality or effect budgets**. SnowPack aging is analytic instead of scanning every accumulated cell per frame; hot collision caches use numeric stamped cells; per-flake protected calls are removed inside the already-protected WorldPrecip pass; audio queues compact in place; cloud/particle staging uses pooled tables; and VP uniforms send once per shader/frame. A full 2048-cell SnowPack benchmark confirms the O(1) aging path; the final exact-package five-run median measured ~45.469 us/update on 4.35.22 vs ~0.524 us/update on 4.35.23 (~86.8x lower isolated update overhead); an earlier source-run environment measured ~336x. Release invariants keep the existing 2560-star, 12000-rain, 100000-snow, 3600-grain and 45000-hail quality ceilings unchanged.

> **Exact leaf DDA + physical snow/footprints (4.35.22):** Leaf/building collision now traverses every crossed 16-unit voxel cell with supercover DDA before the retained 0.5-unit footprint sweep, eliminating fast/shallow/corner cell skipping while preserving WindEngine sliding, long-lived piles and the 2-second NPC escape. Actual 3D snowflakes now collide with the host voxel surface and build a persistent map-cell snow pack on ground, grass and raised tree/roof surfaces. Walking through accumulated snow stamps depth-tested world-space footprints that remain behind when you turn around and slowly refill/melt naturally.

> **Live leaf-collision repair (4.35.21):** Fixed the real-host integration bug that let 3D leaves pass through buildings and NPCs even though the isolated 4.35.20 physics tests passed. Weather FX now receives the actual voxel host `VoxelScene.groundAt()` authority through the voxel namespace, rebuilds NPC collision bodies from real overworld state when the host keeps its posed list private, and uses swept building/NPC collision so a leaf cannot tunnel through an obstacle between frames. Existing leaf piles, 2-second NPC escape, seasonal colours, GALE cleanup, WindEngine, and thunder behavior remain intact.

> **Gale cleanup + physical seasonal leaves (4.35.20):** GALE is now strictly non-electrical: no authored strike channel, no 3D atmospheric lightning flashes, and no generic storm ambience bed. 3D leaves now collide with real voxel terrain/building surfaces, slide down walls, form temporary piles at obstacle bases, bounce off posed NPCs with a hard 2-second escape cap, and default to season-driven colour (spring/summer green, autumn orange, winter brown). Manual leaf-colour choices remain overrides.

> **Psychic Storm spacing + universal NPC lightning (4.35.19):** Psychic Storm ordinary terrain bolts now stay out of the immediate player bubble and overwhelmingly land at mid/far world distances; multi-bolt bursts are deliberately spread across far/mid/far/far bands instead of clustering. Separately, every individual 3D bolt in every lightning-capable weather can independently redirect onto an eligible visible NPC. That revision introduced a 20% default; **8.0.10 changes the current default to 10%**. NPC redirects remain intentional close targets; missed/invalid rolls fall back to normal terrain placement.

> **Natural wind + distant thunder weight (4.35.18):** Weather FX now runs one shared world-space WindEngine across 2D precipitation, 3D rain/snow/grains, fog/mist, clouds and wind audio. Wind has weather-specific prevailing flow, slow direction changes, gusts and lulls instead of one fixed vector; existing particles bend gradually into new gusts and cloud/fog advection stays continuous. Psychic Storm distance now changes thunder *character* as well as loudness: genuinely distant bolts lose the sharp crack and arrive as quieter, low-passed heavy booms with their own delayed rolling tails, removing the rapid-gunfire read while preserving per-bolt speed-of-sound delay.

> **Psychic Storm thunder mix (4.35.17):** PSYSTORM no longer turns a multi-bolt burst into several identical full-pitch clap transients. The nearest bolt gets one softened electrical crack, other bolts become lower-pitched/darker booms, and the burst receives one delayed low rumble body. Every visible bolt still keeps its own distance-based arrival time and loudness from 4.35.16; this revision changes the acoustic character so dense psychic lightning reads as a violent supernatural storm instead of gunfire.

> **Per-bolt distance thunder (4.35.16):** Every generated lightning bolt now schedules its own independent thunder voice instead of being suppressed by an audio cooldown or by a sound file already playing. 3D bolts publish their actual world distance to Audio; thunder arrives at roughly the speed of sound (~343 world units/s) and gets progressively quieter with distance while remaining audible. Multi-bolt severe-storm bursts therefore produce multiple staggered thunder arrivals. The 4.35.15 full settings/release audit remains intact.

> **Continuous one-way shadows (4.35.14):** Weather FX now separates camera shadow-map stabilization from celestial motion. The voxel host’s sun-dependent whole-texel frustum snap is bypassed in memory, shadow direction invalidation is raised to 1/65536, and the vertical-orbit shadow rig is explicitly monotonic. Shadows may slow or hold under a real clock correction, but they cannot pull backward before advancing.

> **Natural sunset halo (4.35.12):** The solar halo is now driven by the rendered sun disc actually contacting the horizon. It stays off while the full sun is unobstructed, grows smoothly only while the disc is partially setting/rising, is geometrically clipped below the horizon, and eases to zero with the last visible limb instead of snapping off.
> **Ultra-fine celestial raster (4.35.11):** Sun and moon art now renders on a **16× supersampled local sky surface** and is composited at the exact floating-point body position. The world stays pixel-art, while the celestial discs get sixteen samples per output-pixel axis for much finer visible micro-movement.

> **Horizon/renderer handoff hardening (4.35.9):** The 3D and fallback sun/moon renderers now consume the same smoothed celestial clock, and both clip the portion of each disc that lies below the geometric horizon. This prevents the old post-sunset “half-sun outside the map” ghost and eliminates raw-clock vs smoothed-clock position disagreement that could make sunrise appear to jump when render ownership changes. The 4.35.7 motion smoothing and 30% smaller planets remain unchanged.

> **Continuous celestial rise/set repair (4.35.7):** Sun and moon now move through one uninterrupted world-space East → overhead → West great-circle with no phase-dependent teleport. In the default voxel presentation the moon is exactly opposite the sun, so sunset starts moonrise on the opposite horizon, midnight puts the moon overhead, and sunrise finishes moonset. Horizon visibility now follows the fraction of the actual rendered disc above the horizon instead of a center-point cutoff, so the sun/moon fade through the horizon gradually instead of disappearing while part of the disc is still visible. `Config.celestial.pairedMoonOrbit=false` restores phase-shifted lunar rise times if desired.

> **Deep-sky fade repair (4.35.5):** Stars, planets, constellations and the Milky Way now combine two continuous visibility envelopes: solar-altitude/time-of-day fade × building-distance light pollution. They remain invisible in daylight, fade in progressively after sunset, reach maximum brightness at deep astronomical night, and fade out progressively before sunrise. Building distance is tracked continuously even while the sky is hidden, so approaching/leaving towns no longer resets or pops the night brightness. The current voxel host can no longer force the star field instantly to 100% from a binary night flag.

> **Smooth natural voxel sky (4.35.4):** Weather FX now replaces the voxel hosts' visible checker-dithered horizontal sky bands with a continuous generated gradient while keeping the same live time/weather/celestial colours. Sun, moon and night-sky objects stay crisp over the smooth atmosphere. Set `celestial.smoothSky=false` in `config.lua` to restore the host's original banded sky.

> **Rare 3D NPC lightning reaction (4.35.3):** Each individual world-space lightning bolt has a 5% chance to strike an eligible NPC currently visible in the voxel camera. The player and obvious non-NPC objects are excluded. A struck NPC is temporarily redrawn as a black silhouette with white eyes for 5 seconds, then the untouched original presentation automatically returns. Severe multi-bolt storms roll independently per bolt. No external mod files, NPC textures or save data are edited.

> **Celestial orbit orientation repair (4.35.2):** Sun and moon now follow a fixed world **East → overhead → West** vertical orbit by default instead of the latitude/declination path that could look like a horizontal circle around the player in voxel view. Seasonal sunrise/sunset/day length, lunar phases/eclipses and the sidereal deep sky remain intact. The orbit plane never rotates with the camera or player. `Config.celestial.verticalOrbit=false` keeps the prior astronomy-style horizon path as an opt-in alternative.

> **Celestial clock + night-sky visibility repair (4.35.1):** Fixed the live voxel-clock adapter so Weather FX follows the host's effective in-game DayNight dial (`time()`) instead of accidentally preferring raw wall-clock `hours()`. AUTO is now the default time source: supported voxel hosts drive astronomy from their selected in-game clock; standalone Weather FX falls back to its accelerated cycle. Stars, planets, constellations and Milky Way are now hard NIGHT-only and never appear during day, dawn, dusk, golden hour or twilight. Building light pollution now fades across a much broader 4–48-cell field with slower symmetric temporal easing, so stars brighten gradually while leaving buildings and dim gradually while approaching them.

> **Ultimate celestial engine + thunder authority (4.35.0):** Weather FX now runs one physical celestial/environment authority across 2D and supported voxel worlds: seasonal sun paths and sunrise/sunset, continuous golden/civil/nautical/astronomical twilight, a synodic lunar phase cycle, moonlight, sidereal star/constellation rotation, Milky Way visibility, building light pollution, weather/cloud disc occlusion, terrain-conforming cloud shadows, weather-particle scattering, sun/moon wet-surface and voxel-water reflection data, and partial/near-total solar + lunar eclipse states. The live voxel DayNight rig is adapted in memory so terrain shadows and water follow the same sun/moon state without editing another mod. The actual 3D moon mesh now changes illuminated geometry by phase and can silhouette the sun during an eclipse. Lightning/thunder authority is also corrected: plain RAIN and HEAVY (`RAIN_LIGHT` / `RAIN_HEAVY`) are rain-only even during an eased transition, while every authored lightning weather—including PSYSTORM, PRIML, STORM, DRAGONSTORM, THUNDERSNOW and GALE—drives thunder from the durable strike event stream.

> **Current voxel-host compatibility (4.34.1):** Weather FX now preserves variadic/multi-view arguments when wrapping voxel `VoxelScene.render()`. This keeps the 3D atmosphere compatible with current Dramatic Shape 1.9.x / PotatoVoxel multi-view render contracts while retaining Dramaless Shape 2.0.3 and Voxel Realism compatibility. No Weather FX particle, cloud, lightning, lighting, or quality behavior changed.

> **Severe lightning clusters (4.34.0):** STORM, PRIML/HEAVY_RAIN, and PSYSTORM can now generate simultaneous 2-4 bolt cloud-to-ground bursts across separate rendered-world locations. Every bolt still originates in the live 3D cloud deck, hits voxel terrain, and carries its own world-space light. The 4.33.9 strike-event rates remain 18, 6, and 84 per minute.

> **Lightning-rate tuning (4.33.9):** STORM, PRIML/HEAVY_RAIN, and PSYSTORM now schedule lightning at exactly twice their 4.33.8 rates: 18, 6, and 84 strikes/min respectively. World-space strike targeting, cloud-to-terrain bolts, thunder voice limits, and all other weather rates are unchanged.

> **3D world-space lighting + terrain lightning (4.33.8):** Weather FX 3D lightning now starts inside the live rendered cloud deck, chooses random near/mid/far strike cells across the current rendered map and visible neighbour maps, resolves the endpoint against the voxel host's actual terrain height, and lights the cloud source/impact in world space. Healthy 3D lightning suppresses the old screen-wide 2D flash, so both the bolt and its illumination stay fixed in the world while the camera moves.

> **LuaJIT 3D particle spawn fix (4.33.7):** Fixed the real cause of the rain-only 3D failure. `WorldPrecip.update()` had exceeded LuaJIT 2.1's 60-upvalue compiler limit, so the full world-particle module could fail to load while CinematicAtmos silently fell back to legacy rain. The update closure is now reduced to 48 executable upvalues, the 3D bridge validates WorldPrecip at install, and permanent proof tests require actual live pools + submitted vertices for snow, hail, sand/dust, leaves/debris and ash.

> **3D world-space precipitation repair (4.33.4):** Snow, rain, hail and true ashfall now originate from the same physical 3D cloud-deck altitude used by the visible cloud bank. Cloud streaming and precipitation streaming share a camera-invariant world anchor: player position when available, first-person eye for rotation-safe FPV fallback, and the orbit focus near the avatar in third person. Turning the camera can no longer move the storm. Recognized Weather FX states now drive all six 3D particle channels (rain, snow, hail, sand/dust, leaves/debris and ash) instead of allowing the old embedded cinematic weather cycle to disagree. A new executable world-space suite verifies cloud-deck spawning, camera invariance, and healthy 3D draw paths for every family.

> **Strict 3D presentation ownership (4.33.3):** `WX PRESENT = 3D` is now authoritative whenever a supported voxel host is active. Weather FX bypasses its entire 2D overworld visual compositor instead of suppressing only individual precipitation families. No 2D weather tint, fog/veil, particles, psychic wash, glare, flat puddles, screen-space lightning, or 2D funnel is allowed to stack over the 3D atmosphere. AUTO still keeps the per-family 2D safety fallback, and an unavailable 3D host still falls back to visible 2D weather. First-person follows the same strict 3D rule.

> **3D ownership fix (4.33.2):** 3D weather no longer allows its 2D precipitation fallback to reappear merely because MAX-performance rear-camera culling produced zero visible billboard vertices for a family. Rain, snow, hail, sand, leaves/debris and ash now keep 3D ownership when their draw path is healthy, while real mesh/shader/draw failures still fail closed to the matching 2D safety fallback. This fixes flat 2D weather rendering over healthy 3D weather without removing particles, animation, density, world coverage, or the 4.33.1 FPS optimizations.

> **MAX-performance optimization (4.33.1):** MAX keeps the same weather populations, world coverage, stars, animation systems and visual quality while doing substantially less invisible/redundant work. NightSky caches frame-constant module/trigonometry/building values, world precipitation reuses persistent state and seed-derived coefficients, grain families draw from their own contiguous ranges, and billboard geometry that is guaranteed behind the camera is not built/uploaded even though those particles continue simulating in the full 360° world. A permanent performance-invariant gate prevents future “optimizations” from lowering the MAX particle/star budgets.

> **Feature-integrity audit (4.33.0):** Every shipped runtime module, player-facing setting, major host hook, bundled audio/backdrop asset, weather catalogue entry, battle system and world subsystem is now covered by an executable or structural integrity check. The audit fixed previously orphaned battle-art/time/viewport hooks, battle-weather visual authority, Solar Beam charge skipping, BuildingLight host-data access, DEBUG HUD wiring, and removed dead/inert runtime/config baggage.

> **2D fog loading-motion fix (4.32.2):** FOG, MIST, SMOG and HAUNTED MIST autonomous bank drift is halved again (25% of the original pre-4.32.1 rate). World-bank parallax now follows confirmed player world position rather than raw camera movement, so held directional input during loading cannot make the fog pretend the player is moving. Weather wind/meander continues normally during loads.

> **All 2D haze is world-wrapped (4.32.0):** FOG, MIST, SMOG and HAUNTED MIST now use the same local, repeating world-anchored bank field as Sandstorm/Duststorm. The banks wrap around the player, move opposite player travel, drift independently with weather/wind, and no longer rely on full-screen fog/veil overlays. The 3D renderer is unchanged.

> **2D sand/dust visibility fix (4.31.9):** The world-anchored Sandstorm/Duststorm haze now keeps its local banks populated across large map/camera offsets while retaining the corrected inverse movement. The 4.31.8 culling sign mismatch could make every bank disappear away from map origin. No screen overlay was restored, and the 3D renderer is unchanged.

> **2D sand/dust world-field fix (4.31.8):** Sandstorm and Duststorm no longer use a full-screen fog/veil overlay. Their haze is now built from local, repeating world-anchored banks that wrap around the camera, move opposite player travel, and drift independently with wind. LOW/POTATO use one depth layer; higher tiers use two. The 3D renderer is unchanged.

> **2D particle tuning (4.31.6):** 2D ash and black ash are now 2x larger, and 2D snow once again uses the full quality-tier particle population at high intensity while retaining the larger round flakes. The 3D renderer is unchanged.

# Weather FX

> **2D sand/dust parallax fix (4.31.5):** Sandstorm and Duststorm haze now moves opposite player movement in both X and Y instead of following the player like a screen overlay. Ground haze uses the same corrected world-space parallax. Ordinary fog and the complete 3D renderer are unchanged.

> **2D visual refresh (4.31.4):** 2D snow is now round, twice as large and half as dense; 2D rain is 50% thicker; hail and ash/black-ash use new procedural shapes based on their 3D counterparts; and 2D sandstorm haze is warm sandy/ochre instead of generic gray fog. The 3D renderer is unchanged.

> **Thunder mixer hardening (4.31.3):** Dense lightning no longer stacks/restarts minute-long thunder rolls. PSYSTORM keeps its frequent visual flashes but audible thunder is rate-limited, long rolls are single-instance, and voice saturation drops new distant strikes instead of cutting sounds already in flight.

> **Indoor acoustics (4.31.2):** Exterior rain, wind and thunder are attenuated and low-pass muffled through walls/windows, with smooth doorway transitions and a safe volume-only fallback when host audio filtering is unavailable.

> **Renderer hardening (4.31.1):** A full 2D/3D weather pipeline audit fixed the 3D leaf regression, mixed-family grain loss, false 3D ownership after failed draw submissions, tornado funnel composition, and several fallback/parity issues. 2D safety layers now remain active per weather family until the corresponding 3D pass proves a successful draw.

> **WX Pokémon split (4.31.0):** Weather FX core no longer contains or registers any WX Pokémon variants. Install the separate **Weather FX - WX Pokémon** add-on only when you want those forms. The core weather, battle buffs/nerfs, seasons, audio, celestial systems, encounter weather bias, and rendering all work without it.


> **Working on this with an AI assistant?** Point it at
> [`AGENTS.md`](AGENTS.md) first — it covers the tools in
> `tools/` and the failure modes in this engine that do not raise errors.


Weather for Pokémon. Skies change as you play, and the weather follows you
into battle — where it changes how the fight goes, not just how it looks.

Targets Red, Blue, Yellow and Gold through the engine's Gen 1/Gen 2 mod surfaces. This standalone package audit validates the shared adapters and contracts; an actual ROM/engine boot is still required to certify each game build.

---

## Install

Drop the `weather_fx` folder into your `mods/` folder, or import the
`.modpkg` through the launcher. That's it — it turns itself on.

Then open **OPTIONS** in game and set **WEATHER** to `AUTO`.

### Presentation (mod page)

On this mod’s page in the mod manager, **WX PRESENT** controls how overworld
weather is drawn:

| Setting | Behaviour |
|--------|-----------|
| **AUTO** (default) | 3D atmosphere when Dramatic Shape 1.9.x, Dramaless Shape, Potato Voxel, or Gen2-3D-Sprites is running; otherwise original 2D overlays |
| **2D** | Use the flat Weather FX overlays in normal camera modes; **FPV intentionally forces strict 3D** so weather remains spatial |
| **3D** | Prefer the voxel-pass atmosphere when a supported host is available |

Battles always use Weather FX’s own battle weather path.

### Voxel 3D (Dramatic Shape / Dramaless / Potato)

With **Dramatic Shape 1.9.x**, **Dramaless Shape**, or **Potato Voxel** in VOXEL mode, Weather FX can draw
clouds, light shafts, rain, fog, motes and puddles inside the host depth pass
(embedded Kanto-style atmosphere, Weather FX only — other mods are not edited).
If that path is unavailable or fails, the mod falls back to 2D automatically.

Turn on **DEBUG HUD** (mod page): **SIMPLE** (readable), **FULL** (dense),
or **3D** (voxel bridge only). SIMPLE/3D include a **why:** line when rain is
missing (indoors, clear sky, ladder off, 3d-precip, …). An `|err:` on the 3D
status is the last draw error.

### AI / headless tools

```bash
python3 tools/test_mod.py      # structural + contract tests
python3 tools/run_all.py       # debug + guard + map + tests
python3 tools/runtime_hints.py "wx:3d | v3:full-atmos:DRAMALESS_SHAPE"
```

---

## What you'll see

**Twenty-nine weather types** — the original rain, sun, snow, storm, sand, ash,
wind, mist and fog families plus typed fronts such as verdant rain, dragonstorm,
psystorm, haunted mist, smog, flock/swarm weather and more. Twenty-eight can be
pinned directly; MIST remains an AUTO-only fog variation.

**It changes on its own.** Leave WEATHER on `AUTO` and the sky rolls naturally. If WEATHER FRONTS is ON, moving physical fronts own automatic weather and persist across map changes; CYCLE is suspended while they are active. With fronts OFF, `CYCLE` walks through every type on its persistent timer and does not reroll just because you changed maps. Pick a named weather directly and it changes immediately while automatically turning WEATHER FRONTS OFF so the manual choice remains authoritative.

**Some places have their own weather.** Lavender Town runs foggy, the climb
to Indigo Plateau turns to snow, the sea routes run misty. Your own choice
from the menu always wins.

**Lightning and thunder** in storms, with a softer setting if flashing images
are a problem for you.

**A day/night cycle** that tints the world — morning, day, evening, night.
After dark the weather leans toward fog and storms.

---

## What it does in battle

Whatever sky you're standing under comes into the fight with you.

| | |
| --- | --- |
| **Rain** | Water moves hit harder, Fire moves weaker. Thunder never misses |
| **Sun** | Fire moves hit harder, Water moves weaker. Thunder gets unreliable |
| **Primal rain** | Fire moves fail completely |
| **Harsh sun** | Water moves fail completely |
| **Sandstorm** | Wears down anything that isn't Rock, Ground or Steel. Rock types resist special attacks better |
| **Hail / snow** | Hail chips non-Ice Pokémon; snow/blizzard do **not** deal residual chip. Blizzard gains its weather accuracy benefit |
| **Strong winds** | Flying types stop taking their usual extra damage |
| **Fog** | Everyone's accuracy drops |

**Where you fight matters too.** Bug and Grass moves hit harder in the
forest, Electric moves in the Power Plant, Ghost moves in the tower — on both
Kanto and Johto maps.

Also handled: Solar Beam's power, weather-based abilities like Swift Swim and
Sand Veil, the weather-extending rocks, and Utility Umbrella.

---

## Settings

Weather FX exposes **60 player controls** through **11 in-game submenus**, with a description for every row via **SELECT: HELP**. **WEATHER** is also mirrored into the normal OPTIONS ladder.

| Submenu | Covers |
| --- | --- |
| **WEATHER** | weather choice, intensity, rare-weather frequency, rotation speed, 2D/3D presentation, indoor presentation |
| **SIMULATION** | natural transition speed, regional fronts, front strength, localized mesoscale weather, directional wind walking |
| **ATMOSPHERE** | clouds, cloud height, **water style (Weather FX / Original)**, fog/sand/dust intensity, splashes, puddles, post-rain rainbows, snow shape, leaf colour |
| **STORMS** | lightning accessibility, NPC strikes/chance, tornado enable/frequency |
| **CELESTIAL** | sun god rays, celestial events, smooth sky, celestial motion |
| **TIME & SEASONS** | clock source/cadence, seasons, season length, hemisphere, notifications |
| **AUDIO** | weather master, indoor attenuation, thunder and wind audio |
| **GAMEPLAY** | weather encounters, legendary events and optional follower weather damage |
| **BATTLE** | battle visuals, mechanics, amplified rules and battle scenery |
| **PERFORMANCE** | quality tier and optional absolute particle cap |
| **DEBUG** | forced-rain verification and diagnostic HUD |

Advanced rows default to **CONFIG** where appropriate, so an existing `config.lua` remains authoritative until the player explicitly overrides that row. Low-level engine constants that can destabilize the simulation remain config/internal only.

---

## Something not working?

**Weather changes outside but battles stay visually clear.**
Set **BATTLE WEATHER FX** to `ON`. If the visuals are present but battle mechanics are not, set **BATTLE WEATHER DMG** to `ON`.

**No weather at all.**
Check **WEATHER** isn't set to `OFF`.

**A terrain bonus never seems to fire.**
Turn on **DEBUG HUD** and look at the `map:` field — it shows the map name
the game is actually using, which is what your config needs to match.

**Anything else.**
Turn on **DEBUG HUD**. The `btl` field reports whether the battle is indoors, seeding is disabled, or the visual/damage battle switches are off.

---

## Other mods

**Use one weather-authority mod at a time.** Do not enable Weather FX together with `kanto_dynamic_weather` / `Campo@kanto_dynamic_weather`; both own the overworld weather state and running both would create duplicate/conflicting weather authority. Voxel renderers, first-person mods and UI/battle presentation mods are different categories and are handled through guarded hooks/fallbacks.


Includes coexistence/stand-down guards for supported 3D/voxel, first-person, battle-UI and Kanto-Reforged-style integrations. Where Reforged already handles something — Weather Ball, Castform, Sand Veil — Weather FX is designed to step aside instead of doubling up. The shipped compatibility audit is structural; exact third-party mod combinations still require a live in-engine check.

---

## Two things worth knowing

**This isn't "Gen 1 accurate", and that's deliberate.** Gen 1 has no weather
at all, and Gen 2 has only rain, sun and sandstorm. Most of what's here is
borrowed from Gen 3 through Gen 8 and brought back. The
[full reference](docs/REFERENCE.md) lists which generation each effect comes
from, if you care.

**A few battle features need a mod that adds abilities and held items.**
Castform, weather rocks and abilities like Swift Swim have nothing to attach
to in the vanilla games.

---

## Full reference

Everything else — every config key, compatibility details, how to extend it,
how it's tested — is in **[docs/REFERENCE.md](docs/REFERENCE.md)**.


## Typed Weather Residuals (4.0.0)

Weather now covers **all 15 Generation I damage types**. A typed weather deals
**1/16 of maximum HP at the end of each battle turn** to battlers that do not
have the weather's matching type. Dual-typed Pokémon are immune when either
type matches. The residual uses the same configured `residualDamage.fraction`
and `canFaint` controls as the existing hail/sandstorm system.

| Gen 1 type | Weather |
|---|---|
| Normal | Plain Front |
| Fire | Heatwave / Sun |
| Water | Rain |
| Electric | Storm |
| Grass | Verdant Rain |
| Ice | Snow / Blizzard / Hail |
| Fighting | Brawl Wind |
| Poison | Smog |
| Ground | Duststorm |
| Flying | Flockstorm / Gale |
| Psychic | Psystorm |
| Bug | Swarm |
| Rock | Sandstorm |
| Ghost | Haunted Mist |
| Dragon | Dragonstorm |

Every typed weather has a non-empty visual recipe and is rendered by both the
overworld compositor and the battle weather compositor. The visual recipes
reuse the mod's renderer-independent rain, snow, grain, fog, veil, tint,
glare, wind and lightning layers, so they work on the flat renderer and
supported world/battle presentation paths without requiring platform-specific
code.

The weather's `chipType` lives in `lib/Types.lua`. The battle residual system
resolves the active field weather back through that catalogue, so adding
another typed weather does not require adding another residual-damage branch.

## Credits

The 3D atmosphere path reuses four modules and a compatibility bridge from
**[Kanto Dynamic Weather](https://github.com/1-Camp0-1/Kanto-Dynamic-Weather)**
by **Campo (`1-Camp0-1`)**, used verbatim under the MIT License. The licence
and a notice sit beside the code in `lib/voxel_atmos/`.


## Optional WX Pokémon add-on

Weather-form Pokémon are no longer bundled with Weather FX core. Install **Weather FX - WX Pokémon** (`weather_fx_wx_pokemon`) when you want those forms and their weather-matched wild substitutions. The add-on requires this core mod and reads live weather through the core export surface; it does not duplicate the renderer, seasons, celestial system, audio, or battle-weather engine.

The core deliberately remains usable with the add-on completely absent.
