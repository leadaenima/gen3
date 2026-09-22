# 8.2.13 — MAX T-SNOW 3D Rebalance

- Rebalanced THUNDERSNOW/TSNOW only: steep deterministic far-population taper removes the MAX-distance white-fuzz wall while preserving nonzero full-distance continuation.
- Expanded and densified the detailed near/overhead snow shell with a hard +4096 detailed-submission cap.
- Preserved logical snow counts, CPU interaction/accumulation work, ordinary SNOW/BLIZZARD profiles, lightning, and Gen1/Gen2 3D host compatibility.
- Added focused 8.2.13 TSNOW visual-shape regression and fresh real Yellow + Crystal MAX-quality framebuffer qualification.

# 8.2.12 — Native Gen2Recomped 3D Weather Host

- Adds `Gen2Recomped-DramaticShapes` as a first-class voxel host. This is the voxel renderer bundled directly with Gen2Recomped 0.7.40, so Gold/Silver/Crystal no longer need an external Gen2 voxel mod for Weather FX 3D atmosphere.
- Orders Weather FX after that optional host and treats its live-world battles as wide/3D battles.
- Routes first-person detection through either a host-level `require` or the public `exports.lib.require` seam, matching the bundled Gen2 renderer.
- Preserves all existing Gen1 Battle Art/Dramatic Shape/Dramaless/Potato and external `STADIUM2_OVERWORLD_MODELS` integrations.

# 8.2.11 — Gen1Recomp + Gen2Recomped Six-Game Compatibility

- One Weather FX install now explicitly targets Pokémon Red, Blue, Yellow, Gold, Silver, and Crystal.
- Added call-time edition/generation detection shared by Gen1Recomp and Gen2Recomped.
- Fixed the Gen2 WEATHER options row so it no longer depends on the optional CRYSTAL_251 companion mod.
- Integrated Gen2Recomped native `RAIN` / `SUN` / `SANDSTORM` / `HAIL` battle weather without double-applying Weather FX mechanics.
- Added safe sidecar ownership for Weather FX-only battle weather on Gen2.
- Preserved all existing 8.2.10 Gen1 behavior and rendering/performance contracts.
- New compatibility qualification: six-edition 41/41, Gen2 battle ownership 20/20, static contract 18/18; maintained developer sweep 137/137.

# 8.2.10 — Dynamic 3D Leaf Size Continuity

- Removed spawn-distance scaling from the intrinsic size of 3D wind-blown leaves.
- Leaves born at the far edge now grow to the correct presentation size as they approach the player instead of remaining permanently tiny.
- Leaf opacity is likewise no longer permanently biased by spawn distance; current-distance fading remains in the draw path.
- Preserves authored leaf size variety, world-space motion, wind response, collision, settling/piles, seasonal color, and debris counts.
- Adds an on-demand live leaf-size diagnostic and a dedicated regression proving base size depends only on the leaf identity while current eye distance controls presentation.

# 8.2.9 — Pitch-Stable 3D Clouds + Real Weather-Strength Particle Counts

- Removed remaining bottom-up cloud clipping during upward camera motion by making cloud descriptor existence/opacity pitch-independent.
- WEATHER STRENGTH fixed choices now scale actual 3D logical particle populations: SOFT 45%, NORMAL baseline, HEAVY 150%; AUTO keeps natural oscillation.
- Fresh Battle Art qualification held 73 cloud descriptors from level through -50° and verified live rain/blizzard count scaling.

# 8.2.8 — 3D Cloud/Celestial Continuity + Localized Snow Fields

- Widened the bounded world-space overhead cloud shoulder so volumetric clouds remain present through repeated first-person up/down/up viewing instead of thinning/disappearing at zenith.
- Full 3D weather now always keeps the world-space celestial vault active, even when the separate CELESTIAL RENDERING selector is set to 2D.
- Removed global celestial alpha suppression from a single 3D cloud-transmission sample. Sun, moon, stars and constellations continue to exist/move behind the cloud field and are occluded by cloud geometry itself, so they show through real gaps but not through cloud bodies.
- Preserved the coarse cloud ray for direct optics such as glare/god-ray attenuation.
- Added a player-centred 3D population taper for SNOW_LIGHT / legacy SNOW and BLIZZARD only: full near-player/overhead density, progressively fewer actual particle identities outward, and an extremely sparse nonzero full-distance continuation with no hard cutoff ring.
- Retuned the taper after real framebuffer review showed that the first far-edge reduction still produced a fuzzy white-noise horizon.
- Replaced the taper's initial `length()` distance with a sqrt-free octagonal radius approximation so millions of procedural snow vertices retain the mobile/low-end hot-path performance contract.
- Fresh Gen1Recomp 0.2.53 + Battle Art Voxel Fork 1.10.4 fixture evidence verifies repeated zenith cloud persistence, FRONT OFF day/night cloud-gap astronomy, live sun/moon cycle motion, stars remaining live at night, and sustained SNOW_LIGHT/BLIZZARD near-to-far distribution.
- The official ROM-free fixture is not Pokémon Yellow; no fresh Yellow 8.2.8 run is claimed without legitimate user-provided game input.

# 8.2.7 — Battle Art 3D Compatibility + Procedural Snow Recovery

- Registered Weather FX private 3D `GustFront` and `WorldInteractionPrecip` helpers so Battle Art 1.10.4 does not resolve them through absent host/root paths.
- Pinned Weather FX-owned battle/snow-surface/world-interaction/RAVE APIs to the Weather FX root namespace and made optional host discovery non-telemetry protected probes.
- Feature-detected Battle Art's optional puddle-mask character-reflection seam, skipping only that cosmetic subpass on hosts that do not expose it.
- Removed dead procedural-snow `fieldIntensity` GLSL uniform/upload. Real GLSL optimized the unused uniform away, causing `Shader:send` to fail and dropping 3D snow to sparse CPU fallback; intensity remains authored through `fieldFallScale`.
- Uniform upload failure telemetry now identifies the exact failed uniform.
- Fresh real Gen1Recomp/LÖVE + Battle Art 1.10.4 fixture qualification: 30/30 3D weather entries, 30 seconds per weather, 60/60 long-dwell captures, 30/30 movement checks, and route->town->route persistence for heavy rain/blizzard/sandstorm/RAVE, with zero Weather FX failures.
- Fresh 2D fixture qualification covers all 30 weather entries, 80 settings / 357 choices, pause/map transitions, and in-battle FULL/OFF/FULL visual proof.
- The official ROM-free fixture is not Pokémon Yellow; no fresh Yellow 8.2.7 run is claimed without legitimate user-provided Yellow input.

# 8.2.6 — All-Weather Phone + MAX Performance Qualification

- Deep-audited the complete 3D weather stack for low-powered phones and 16 GB desktop/MAX use rather than limiting performance work to snow.
- Rain, hail, sand and ash now use proven procedural GPU visual ownership at every nonzero density, eliminating the old low-count CPU-only threshold.
- If the procedural rain/grain backend is unavailable or fails proof, visible CPU fallback is bounded by the established quality-tier budgets before simulation allocation; it can no longer inherit world-scale rain/hail/sand/ash populations.
- Leaves/debris retain their physical collision/settling path and established authored quality caps.
- Shared procedural rain/hail/sand/ash geometry is 4 unique strip vertices instead of 6 duplicated triangle vertices, reducing vertex work by one third at identical logical population.
- Shared precipitation hashing, hail/sand wander and storm-band modulation use continuous trig-free math; ash silhouette no longer performs per-pixel atan/length/sine work.
- Wet-weather puddle-reflection scans reuse bounded descriptor pools instead of allocating fresh candidate tables every reflected-character scan.
- Re-qualified existing efficient systems without needless rewrites: compact-instanced/cached volumetric clouds (including RAVE), fog ownership, water hot-path caching, tornado off-screen culling, world lightning, RAVE/battle persistence, celestial stress/zenith behavior, rain continuity, sand pitch, leaves, and all 8.2.5 snow behavior.
- New all-weather performance ownership regression passes 12/12; exact 8.2.5 fails 10/12. Sequential subsystem qualification passes 25/25 programs; maintained developer sweep passes 124/124 before final package replay.

# 8.2.5 — Requested 3D Snow Density Multipliers

- SNOW (`SNOW_LIGHT`, plus the legacy `SNOW` alias): exactly 2x the 8.2.4 logical 3D snow population.
- TSNOW (`THUNDERSNOW`): exactly 2x the 8.2.4 logical 3D snow population.
- DRAGON (`DRAGONSTORM`): exactly 2x the 8.2.4 logical 3D snow population.
- BLIZZARD: exactly 4x the 8.2.4 logical 3D snow population.
- No other snow-bearing weather is multiplied. WHITEOUT, SLEET, FROST/ICE variants and other weather remain unchanged.
- 8.2.4 CPU fallback caps, accumulation behavior, LOD, smooth motion, render distance, cloud/RAVE/celestial/battle behavior and every other runtime system are unchanged.

# 8.2.4 — Full 3D Snow Path Performance Repair

- Full executable audit of all 12 snow-family weather IDs, every quality tier, accumulation OFF/ON, proven procedural GPU ownership, forced GPU failure, first-person interaction probes, and a rain control.
- With **SNOW ACCUMULATION OFF**, pure 3D snow now skips SnowPack support-context construction, exact terrain sweeps, SnowPack updates, ground/foot staging, and rain-only WorldInteractionPrecip work.
- With accumulation ON, exact support context plus ground/foot staging is reused and refreshed near 10 Hz unless map change or meaningful movement requires immediate refresh; procedural visual flakes do not individually exact-sweep terrain.
- Proven procedural GPU snow keeps one third-person telemetry identity or at most 16 first-person face-contact probes instead of the old 16–96 invisible probe loop.
- If the procedural GPU snow renderer is unavailable or fails proof, the legacy CPU-visible fallback is hard-capped by the existing quality budgets: POTATO 360, LOW 720, MEDIUM 1640, HIGH 3200, MAX 4800. It can no longer integrate the complete logical 100,000/200,000 storm on the CPU.
- Preserves 8.2.3 point/detail LOD, smooth per-render-frame snow motion, full render distance, continuous no-emitter/no-handoff behavior, and all established non-snow weather functionality.
- Added `snow_full_path_8204_test.lua`; exact 8.2.3 fails 6/7 new full-path checks.

# 8.2.3 — Mobile 3D Snow Raster/CPU Architecture Repair

- Keeps the full logical 3D snow field and smooth per-render-frame movement, but renders distant subpixel flakes as one-vertex GPU points and reserves detailed crystalline billboard cards for the area-matched near field.
- POTATO 1,600 snow: 1,600 far point carriers + 64 detailed crystals; MAX 100,000 SNOW: +1,778 detail; MAX 200,000 BLIZZARD: +3,556 detail. Effective falling-snow vertex work is under 30% of the previous all-card renderer.
- Preserves authored snow counts, render distance, weather intensity, wind/tumble motion, and continuous no-emitter world wrapping.
- Non-instancing phones use immutable 8,192-point pages plus bounded 2,048-crystal detail pages; no per-frame snow geometry rebuild/upload.
- SnowPack ground staging is capped at 10 Hz with immediate meaningful-movement/map refresh; cached ground-bank meshes are rebuilt only when staged data changes.
- Snow-surface coverage skips identical CPU raster + GPU texture uploads.
- Invisible exact-terrain interaction probes scale from 16 POTATO / 28 LOW / 48 MEDIUM / 72 HIGH / 96 MAX without reducing the visible GPU snow population.
- Added dedicated 8.2.3 LOD and secondary-system performance regressions; exact 8.2.2 negative control fails them.

# 8.2.2 — Mobile 3D Snow Universal GPU Path + Zenith Sky Repair

- All nonzero 3D snow densities probe the procedural GPU renderer before any CPU snow mesh build.
- Non-instancing/legacy phones use immutable 4,096-flake GPU pages instead of per-frame Lua geometry construction and uploads.
- 3D snow fragment and vertex hot paths remove costly angle/length/trigonometric operations while preserving continuous smooth animation and full authored populations.
- Shared cloud billboards use a zenith-safe VP-derived basis.
- Sun/moon projection uses a real perspective VP transform when available and a compatibility basis otherwise, preventing steep-pitch disappearance without breaking constellations/planets.

# 8.2.1 — Mobile 3D Snow Performance Repair
- Preserves 8.2.0 continuous no-emitter SNOW/BLIZZARD world tiling and smooth per-frame motion.
- Snow quad 6 -> 4 vertex executions via triangle strip (33.3% vertex workload reduction).
- Hoists tile/fade/patch/front constants and patch-wind normalization out of the per-vertex shader.
- Uses algebraically equivalent normalized tile-phase wrapping with no old dynamic tile divide/floor selector.
- Fronts-OFF/uniform snow skips storm-band trigonometry.
- Native GLSL3 snow uses sine-free 32-bit integer bit-mix hashing; legacy compatibility shader remains available.
- Authored ceilings unchanged: SNOW 100,000; MAX BLIZZARD 200,000.
- Runtime Lua delta vs 8.2.0: `lib/ProceduralSnowField.lua` only.

# 8.2.0 — Global Cloud Zenith + Continuous Snow Field + RAVE Mixed/Battle Presentation

- Fixed cloud-bank edge disappearance while looking up across **all 3D weather**, not only RAVE/sealed decks. Cloud candidate search is now centered on the gameplay/world anchor instead of the camera eye/focus corridor, and physically overhead clouds receive a bounded camera-independent world-space admission shoulder.
- Doubled RAVE's actual volumetric cloud-lobe population after normal quality/player-density scaling.
- RAVE now works while **WEATHER RENDERING = 2D**: dedicated RAVE fog, floor pools and lasers stay world-space while ordinary precipitation/fog/puddles/rays remain 2D-owned.
- RAVE lasers persist in world-backed battles without replacing battle weather mechanics. Opaque/classic battle canvases get a dedicated additive laser fallback.
- Replaced the SNOW/BLIZZARD finite player-centered disk + 24-unit whole-field anchor handoff with a continuous periodic world-tiled snow field. Individual flakes wrap only at the far tile boundary, eliminating the moving overhead emitter and whole-field snow off/on cycle while walking.
- Preserves the 8.1.99 native `love_InstanceID` backend and full 200,000-flake MAX BLIZZARD population.
- Added `weather_cloud_rave_snow_8200_test.lua`, covering global zenith cloud persistence, exact RAVE 2× lobe density, 2D-weather RAVE routing, battle carry/fallback, and continuous SNOW/BLIZZARD world tiling.

# 8.1.99 — BLIZZARD + 2D Weather Repair

- Replaced the modern high-count procedural snow seed-window path with native `love_InstanceID`, preserving the full 200,000-flake BLIZZARD population while removing repeated 8,192-instance identity windows.
- Fixed 2D sun/moon camera locking by preferring real live camera orientation over host player/world focus anchors.
- Fixed the initial 2D snow dump by phase-distributing freshly allocated flakes through their normal visible lifetimes; recycled flakes still enter from above.
- Added **2D WEATHER LIGHTNING — 2D BOLTS / 3D BOLTS**. It affects only forced 2D overworld weather; 3D BOLTS wakes only world lightning and falls back to 2D when unavailable.
- Player-facing settings total is now **80** distinct controls.
- Maintained developer sweep: **115/115 programs PASS**; `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.

# 8.1.98 — RAVE Cloud + Snow Continuity Repair

- Thickened RAVE's volumetric cloud bank with additional lobe density and overlap while leaving ordinary weather cloud populations unchanged.
- Added a RAVE-only wider bounded world-space overhead cloud admission/fade, preventing the sealed bank from disappearing as the camera pitches toward zenith.
- Tightened ProceduralSnowField's fixed streaming anchor from the old 256-unit/50%-radius rule to 4% of snow radius capped at 24 world units. Maximum centre lag is now 12 world units, eliminating the directional far-edge snow dropout without increasing the authored particle count or handoff draw budget.
- Added current/root snow-family ownership as a backstop for distant snow/blizzard slab retirement during transient channel publication gaps, preventing the stale remote slab from reappearing as a single-pixel/fountain emitter.
- Preserved incoming distant snow fronts while local weather is genuinely clear, and left rain/fog/lightning distant-front ownership unchanged.
- Added `rave_snow_continuity_8198_test.lua`, with exact 8.1.97 negative control failing 8/12 checks as required.

# 8.1.97 — Full Player Settings Audit + RAVE Accessibility

- Audited every player-facing setting for registration, persistence, allowed values, runtime consumption, submenu placement, help text, and maximum-load compatibility.
- Removed the duplicate **WEATHER VISUALS** battle row. **BATTLE WEATHER** is now the single battle-presentation OFF/SUBTLE/FULL authority; **WEATHER RULES** remains the separate battle-mechanics control.
- Renamed **3D WEATHER DISTANCE** to **3D PRECIP DISTANCE** and clarified that it controls precipitation reach as a percentage of the live voxel render distance, while **EFFECT DISTANCE** is the broader expensive-detail/performance radius.
- Added **RAVE STROBE — OFF / REDUCED / FULL**. OFF removes full-rig blackout flashes while retaining moving lasers, illuminated fog, color and beat-reactive motion; REDUCED prevents a full blackout while keeping softer outer choreography; FULL preserves each song's authored strobe.
- Added **RAVE MUSIC — OFF / 50% / 75% / 100% / 125%** underneath **WEATHER VOLUME**. OFF truly stops the RAVE stream/decoder and returns native game-music ownership instead of leaving an inaudible stream running.
- Updated the RAVE soundtrack regression for the new dedicated music sub-control while preserving authoritative weather-id ownership.
- Final audited player-facing count: **79 distinct controls** with no duplicate keys or labels and exactly one submenu placement per control.

# 8.1.96 — Pause-Menu Weather Visibility + Animation Freeze

- Added **PAUSE MENU WEATHER** to the in-game WEATHER settings page: **ANIMATED** (default) or **FROZEN**.
- START/pause menus and their pause submenus now keep the live overworld eligible for Weather FX rendering, fixing classic 2D weather disappearing while the pause menu is open.
- FROZEN keeps the current weather visible but stops Weather FX presentation animation until the pause stack closes. 2D precipitation/fog/wind phases, 3D precipitation, voxel atmosphere/tornado presentation, and RAVE light-show motion all honor the frozen animation clock.
- Weather simulation, scheduling, transitions outside the presentation layer, and audio continue in real time while paused.
- Unknown non-pause UI remains fail-closed so Weather FX still cannot cover arbitrary full-screen menus.
- Added `pause_menu_weather_8196_test.lua` and updated settings/3D pipeline release gates for the new setting and animation-dt ownership.

# 8.1.95 — RAVE Illuminated Fog + Strobe Qualification

- Strengthened only the laser-hit optical response of bounded RAVE fog so real beam intersections visibly illuminate fog bodies in the 3D framebuffer.
- Retained the same bounded fog lattice and world-space intersection logic; non-hit fog is not falsely lit.
- Re-qualified the production per-song strobe as a hard fixture gate. Laser Floor at 160 BPM visibly runs 56 fixtures ON -> 0 OFF -> 56 ON return.
- Added `rave_fog_strobe_8195_test.lua`; focused regression passes 13/13.
- Fresh Battle Art 1.10.4 / Pokémon Yellow / LÖVE 11.5 framebuffer QA confirms illuminated fog draw submission and the strobe ON/OFF/return sequence.
- Maintained developer sweep: 107/107 programs PASS.

# 8.1.94 — RAVE Soundtrack + Per-Song BPM Light Shows

- Added eight original procedural electronic songs: two techno, two rave, two dubstep and two house.
- Added streamed Fisher-Yates shuffle playback with no immediate repeat, EOF advance, fades and native-music ownership cleanup.
- Synchronized the RAVE presentation clock to the active song's exact BPM and streamed audio playhead instead of a fixed global 128 BPM.
- Added eight distinct song-specific light-show profiles with separate laser movement, strobe density, palette, fog response and floor-pool behavior.
- Added arrangement cues for authored breakdown/accent bars so the rig follows musical structure as well as tempo.
- Preserved legacy 128-BPM RAVE timing as the audio-unavailable fallback only; weather/gameplay simulation remains independent.

# 8.1.93 — Battle Art 3D NPC Lightning Repair

- Fixed current Battle Art 3D NPC lightning integration by consuming its public `CharacterRenderers.afterActors` actor stream instead of depending only on raw entity state while Battle Art keeps `posed` local to `VoxelScene.render()`.
- The exact host-resolved actor position, support height, animation lift, facing and sprite now drive eligible NPC strike endpoints and the temporary strike reaction.
- Weather FX does not call `pose()` a second time, does not claim/replace Battle Art character rendering, and never mutates NPC gameplay state.
- When Battle Art's live actor bridge is active, raw actors not presented by the host are not appended as strike candidates. Older hosts retain the existing raw-coordinate fallback.
- CHARACTER STRIKES and STRIKE CHANCE semantics are unchanged (default ON / 10% per eligible 3D bolt); misses and no-candidate rolls still strike ordinary terrain.
- Added `npc_lightning_battle_art_8193_test.lua`: 8/8 PASS on 8.1.93; exact 8.1.92 negative control fails 6/8 checks. Existing NPC-lightning regression remains 43/43 PASS.

# 8.1.92 — Full-Render-Distance 3D Snow Coverage

- Fixed the 3D snow field being smaller than the voxel render distance when WEATHER FRONTS was ON. The old fronts-ON path still clamped snow reach to 750 world units, which exposed a dry field edge on longer render distances and made snow disappear/reappear as the player travelled.
- At **3D WEATHER DISTANCE = 100%** (default), falling 3D snow now reaches the exact live voxel render distance in both WEATHER FRONTS modes.
- 25% / 50% / 75% remain intentional weather-only reductions and now apply consistently to snow in either fronts mode.
- Fronts still control snow patchiness/density and quality still controls particle budgets; neither can silently reduce the 100% snow coverage radius.
- Procedural snow preflight now uses the same snow-specific live-distance radius as the main update path, preventing first-frame/proven-backend radius disagreement.
- Rain, hail, Battle Art water ownership, the 8.1.91 one-pixel snow fix, RAVE, clouds, gameplay and unrelated systems are unchanged.
- Added a dedicated 8.1.92 render-distance regression. Exact 8.1.91 fails 6 of its 8 checks; 8.1.92 passes 8/8. Maintained developer sweep: 102/102 programs PASS.

# 8.1.91 — 3D Snow + Battle Art Water Ownership Hotfix

- Fixed the remaining 3D snow one-pixel/fountain failure: once player-local snow is active, the finite distant snow/blizzard slab now retires completely instead of remaining partially visible at light/moderate intensities.
- Preserved genuinely distant snow fronts when local snow is absent; rain-front, fog and lightning ownership are unchanged.
- Updated `BATTLE_ART_VOXEL_FORK` water capability detection for current public Battle Art, which now exports `_trainSource`; that helper is no longer used to misclassify Battle Art as Voxel Nexus.
- Voxel Nexus is now identified by its Nexus-only `realisticWorld.WaterEngine.tideOffset` seam.
- Added explicit host-relief ownership transitions for Weather FX physical water. When Weather FX owns physical wave geometry, the host Water shader is invalidated on the transition after `WAVE_HEIGHT=0`, preventing already-compiled Battle Art wave relief from rendering as a second water surface.
- Added 8.1.91 regressions for light-snow exclusive ownership, current Battle Art capability shape, Nexus disambiguation, and compiled host-relief suppression.

# 8.1.90 — Feature-Aware Runtime + Full RAVE Atmosphere

- Added feature-aware presentation ownership: pure 2D no longer pays for unused 3D cloud/volumetric/surface work, and strict 3D releases unused flat-particle/NPC-lightning work. Individually enabled 3D cloud banks, celestial rendering, and enhanced water remain live over 2D precipitation.
- Rebuilt BLOCKY cloud presentation into connected stepped cloud masses instead of visible cube/tile grids.
- Removed the secondary instanced visible-snow path that could collapse into a narrow 3D snow fountain on some drivers; dense snow remains on the proven procedural GPU field and fallback snow uses explicit world-XYZ cards.
- Retires stale distant snow/blizzard slabs as soon as authoritative local snow is active, preventing duplicate perspective-compressed snow columns.
- Upgraded manual RAVE into a coordinated 128-BPM/16-beat light show: fan sweeps, opposing cross sweeps, rotating room sweeps, and drop/strobe sections.
- Added broad additive laser halos behind crisp world-space beam cores.
- Added bounded rolling 3D RAVE fog. Each fog body tests the live world-space laser centerlines and changes to the strongest intersecting laser color only for the duration of the hit.
- Added synchronized slow RAVE color motion to both volumetric and BLOCKY cloud banks.
- Added moving-head floor light pools at live laser target points and a phrase-linked master sky/atmospheric color wash so the entire RAVE state changes together.
- Added regressions for feature-aware gating, block-cloud coherence, snow-fountain ownership, and full RAVE show behavior.
- Maintained Lua wall: 88/88 programs PASS. Aggregate validator: 192/192 PASS.

# 8.1.88 — Weather-World Interaction + 2D/Options Repair

- Added bounded roof/eave runoff, retained canopy drips, material-aware precipitation impacts, travelling world-space gust fronts, post-rain shaft enhancement, and Environment SDK v5 vegetation/weather-load interoperability.
- Fixed all classic `2D OVERLAY` weather disappearing on voxel hosts by deferring forced 2D weather from intermediate `worldPresent` to the final-frame `present()` compositor.
- Fixed base OPTIONS WEATHER appearing inert until Mod Manager was opened by adding always-running ladder reconciliation independent of OPTIONS-row wrapper ordering.
- Fixed option-schema re-registration erasing live runtime mirrors while loader caches were stale.
- Fixed the custom Weather FX OPTIONS submenu not always updating the real core mod-loader caches when opened through a lightweight UI game facade.
- Added a dedicated negative-control regression for the 2D/options repair; the pre-fix candidate fails it.
- Maintained sweep: 92/92 programs PASS; aggregate validator 191/191 PASS.

# 8.1.87 — World-Space RAVE Lasers + 3D Battle Weather Continuity

- Fixed RAVE laser emitters being derived from the camera-filtered visible cloud list. Laser centerlines now come from a deterministic world/cloud lattice around the player/world anchor; camera heading/pitch only affects final ribbon facing/visibility.
- RAVE lasers now populate overhead, near, mid-distance, far-distance, and all horizontal quadrants instead of appearing only in a small camera-dependent patch.
- Fixed outdoor 3D weather disappearing on some world-backed battle transitions when the host temporarily reported `Scene.now.outdoor=false`. The 3D atmosphere now carries the last proven pre-battle outdoor/sky authority through the battle.
- True indoor/cave battles remain dry through the existing `Battle._startedIndoors` authority.
- Added executable regressions for camera-independent RAVE laser centerlines/coverage and for 3D RAIN_HEAVY persistence through the exact battle outdoor-gate failure mode.
- Preserves every 8.1.86 RAVE/manual-weather, cloud-style, settings, precipitation, battle, celestial, water, wind, tornado, lightning, audio, and performance contract.

# 8.1.86 — Manual RAVE Weather

- Added **RAVE**, a manual-only 3D weather selectable from both synchronized weather selectors.
- RAVE is `natural=false`, so AUTO, CYCLE, seasons, and regional fronts cannot schedule it.
- RAVE uses heavy-rain-class sealed cloud-bank occupancy without borrowing rain/snow/hail/sand/ash or lightning mechanics.
- Every cloud descriptor receives a deterministic rainbow hue; both volumetric and blocky cloud-bank styles pulse their colour/opacity on a shared 128-BPM visual beat.
- Added bounded world-space laser ribbons emitted from the live cloud descriptors. Lasers use multiple rainbow colours, sweep toward the world, depth-test against geometry, and strobe independently on/off around the shared beat.
- RAVE adds no music asset and no battle-weather mechanic; the party rhythm is visual presentation timing only.
- Preserves every 8.1.85 weather-distance, precipitation, cloud-style, settings, battle, celestial, water, wind, tornado, lightning, audio, and performance contract.

# 8.1.83 — Full Developer Sweep / Weather Ownership Repair

- Fixed 3D procedural snow fall stepping by moving visible snow animation to a monotonic presentation clock while preserving fall-speed and wind equations.
- Fixed fronts-OFF 3D hail, sand/dust and ash/black-ash being trapped in player-local columns: visual radius is now independent from the tiny GPU interaction/probe radius and uses rendered-world absolute-grid ownership.
- Fixed WEATHER OFF becoming sticky by reconciling new player menu authority into the engine weather ladder before WeatherState/runtime consumption.
- Fixed flat 2D battle weather leaking over world-backed 3D voxel battles; precipitation, grains, fog and lightning now share the same nonopaque-battle ownership rule while opaque/classic battles remain 2D-owned.
- Preserved battle-owned weather changes under 3D ownership by continuing BattleDraw easing and publishing battle channels/id into the 3D atmosphere.
- Fixed missing direct-look sun glare/god rays on hosts where `focus` is a player/world anchor rather than the camera look target. Optics now prefer true camera vectors or FirstPerson yaw/pitch and have a projection fallback.
- Added 8.1.83 release regression covering reversible OFF, grain visual coverage, snow presentation timing, world-backed battle ownership and executable sun-glare rendering.
- Modernized inherited static tests for the generalized rendered-world precipitation branch and glare diagnostics.

# 8.1.82 — Player Control Expansion

- Added LIGHTNING FREQUENCY, TORNADO DURATION, CLOUD DENSITY, NIGHT SKY BRIGHTNESS and WEATHER SCREEN EFFECTS.
- Expanded WET GROUND to DEFAULT/OFF/LOW/NORMAL/HIGH while preserving legacy `on` as NORMAL.
- Defaults preserve exact 8.1.81 behavior. No particle caps, weather distance, wind-driven water, tornado descent, assets or quality ceilings were reduced.

# 8.1.78 — Rendered-World Rain Coverage

- WEATHER FRONTS OFF rain is no longer represented by a player/focus-centred circular field. Validated procedural rain now fills the complete voxel render window from absolute world-grid cells.
- At 100% **3D WEATHER DISTANCE**, rain coverage is exactly the current live voxel render distance; 75/50/25% remain weather-only reductions and never alter voxel rendering.
- Absolute world-cell identity owns rain jitter, fall phase and personal drift, so moving the render window preserves rain already occupying overlapping world cells instead of translating/reseeding the storm.
- The rendered-world grid includes guard cells beyond every side of the active 2R × 2R window, preventing dry strips at map edges or after camera turns.
- Fronts-OFF rain population budgeting now uses the complete render-window area rather than πR², preserving density across the edges/corners of the voxel view.
- CPU fallback uses the same full square render-window coverage instead of radial spawning and recycles with a square-safe bound.
- WEATHER FRONTS ON keeps inherited regional/front-owned precipitation behavior.
- Preserves all 8.1.77 rain cadence/map-edge fixes and the 8.1.76 tapered translucent water-streak model.

# 8.1.77 — Map-Edge / Turn Rain Continuity

- CPU fallback rain now uses a fixed snapped world anchor and recycles against that anchor instead of the live player position.
- CPU rain no longer uses camera-forward/rear-hemisphere culling; GPU frustum/depth clipping is the only view-dependent visibility rule.
- Procedural rain phase uses a monotonic render clock so short map-streaming or turn-state update stalls cannot slow/freeze the field.
- CPU rain integration uses a bounded wall-delta catch-up through short host stalls.
- Procedural rain anchor cells are tightened (4% of weather radius, 24-unit cap, 4-unit minimum) so turning cannot expose a dry edge caused by anchor offset.
- Preserves 8.1.76 tapered water-streak appearance and ledge continuity fixes.

# 8.1.76 — Rain Ledge Continuity / Water-Streak Model

- Fixed 3D rain still pausing intermittently while walking with WEATHER FRONTS OFF. The draw pass no longer re-gates visible rain from a transient frame-local zero/clear bag after update() has already allocated the active stream.
- Fixed the reproducible ledge-hop pause: procedural rain no longer uses the player's current elevation as the lower phase boundary. A padded world bottom is frozen for the rain episode/map so hopping raised terrain cannot rephase the whole rain column at once.
- With WEATHER FRONTS OFF and no authored transition, explicit WEATHER selection/root Weather FX rain identity wins over transient frame-local CLEAR/zero pose bags. Explicit RAIN AMOUNT OFF and real authored transitions remain authoritative.
- Rebuilt the 3D rain streak model on both procedural and CPU fallback paths: substantially thinner geometry, longer motion streak, tapered silhouette, feathered ends, narrow specular core, lower opacity, and restrained blue-grey water tint. The old broad rectangular procedural rain mask is removed.
- Preserved 8.1.75 low-population procedural ownership, 8.1.74 fronts-OFF uniform coverage, 8.1.73 map-entry reprime/snow fountain fixes, 8.1.72 3D WEATHER DISTANCE, and 8.1.69 SNOW ACCUMULATION.

# 8.1.75 — Rain Walk Continuity / Low-Population World Ownership

- Fixed the remaining WEATHER FRONTS OFF rain start/stop while walking.
- Proven procedural world-space rain now owns the visible field at every nonzero fronts-OFF rain population, including sub-1,200-drop short-distance / low-budget cases that previously fell back to the legacy player-centred CPU visual stream.
- CPU rain is capped to <=96 interaction probes once the procedural backend is proven; it no longer becomes the low-population visual authority in fronts-OFF mode.
- Added a fronts-OFF stable-rain continuity latch for transient live-channel zeroes while the same authored rain weather remains active. Explicit RAIN AMOUNT OFF and authored transitions still stop/taper normally.
- Tightened procedural rain world-anchor cells for short/medium weather distances so the fixed field stays close to the configured weather-radius circle during walking and hands off between fixed anchors instead of exposing large dry sectors.
- Preserved fronts-ON low-population behavior and all 8.1.74/8.1.73/8.1.72 snow, hail, map-entry, distance and fountain fixes.

# 8.1.74 — Continuous Precipitation / Fronts-Off Uniform Field

- Fixed 3D rain starting and stopping as the player walks. WEATHER FRONTS OFF no longer lets player-position mesoscale shower-band samples scale rain/snow/hail intensity.
- Procedural rain, hail, and snow now force mesoscale patchiness to a full uniform field while WEATHER FRONTS is OFF, so the configured 3D weather radius remains continuously filled instead of containing invisible dry bands.
- WEATHER FRONTS ON keeps regional mesoscale banding, but active authored rain/snow/hail channels can no longer be pushed below the precipitation allocation threshold solely by mesoscale thinning.
- Preserves 8.1.73 fixed world anchors, map-entry reprime, full-distance SnowPack accumulation, first-frame snow/blizzard fountain protection, and the 8.1.72 3D WEATHER DISTANCE control.

# 8.1.73 — World-Anchored Precipitation / Map-Entry Reprime

- Fixed 3D rain translating with the player. Procedural rain/hail now use fixed world-cell anchors with a smooth identity handoff instead of rebuilding around the live player every step.
- Restored procedural rain proportions and ballistic motion closer to the proven CPU rain path so 3D rain reads as longer, depth-scaled world-space streaks instead of tiny camera-following particles.
- SnowPack aggregate deposition now samples across the full effective **3D WEATHER DISTANCE** radius, so snow accumulation no longer stays in the old ~108-unit circle while visible snowfall extends farther.
- Added pre-update procedural precipitation preflight. Snow/blizzard can prove and enter the distributed procedural path on the first visible frame instead of briefly exposing a large legacy overhead instance pool that could collapse into a fountain/tight circle on affected hosts.
- WEATHER FRONTS OFF now hard-gates stale distant-front precipitation renderers, removing another possible duplicate snow/blizzard plume owner.
- Map changes immediately re-prime and reanchor rain, snow/blizzard, and hail from the live gameplay player position; weather no longer waits for the player to walk before reappearing.
- Preserves the 8.1.72 3D WEATHER DISTANCE choices and fronts-OFF-only distance rule, 8.1.69 SNOW ACCUMULATION toggle, and approved snow-bank height profile.

# 8.1.72 — 3D Weather Render Distance

- Added player-facing **3D WEATHER DISTANCE** under **PRECIPITATION** with 25%, 50%, 75%, and 100% choices.
- 100% is the current voxel render distance when WEATHER FRONTS is OFF. Lower values only shorten Weather FX precipitation; they never change the voxel/world render distance and never extend weather past it.
- Rain, snow, and hail consume the reduced distance immediately in the live WorldPrecip frame.
- Fixed-budget grain families scale their visual population with covered area when the distance is reduced, preventing hail/sand/ash/debris from becoming artificially denser just because the field is smaller.
- WEATHER FRONTS ON keeps the inherited regional/front-owned precipitation reach.
- Preserves 8.1.71 exact-distance behavior at the default 100%, 8.1.70 snow-fountain/hail-tube fail-open protection, and 8.1.69 SNOW ACCUMULATION ON/OFF.

# 8.1.71 — Fronts-Off Exact Voxel Render Distance

- WEATHER FRONTS OFF now makes **rain, snow, and hail use the live voxel renderer far distance exactly** as their 3D field radius.
- Removed Weather FX's old 750-world-unit ceiling and 1.15× overlap multiplier from the fronts-OFF fallback path only.
- The current `Voxel3D.far` / camera far value is consumed in the same update frame, so changing voxel render distance immediately changes precipitation reach.
- WEATHER FRONTS ON is unchanged: regional/front precipitation retains its inherited quality/front radius budgets and handoff behavior.
- Preserves 8.1.70 procedural seed-collapse protection and 8.1.69 snow accumulation toggle behavior.

# 8.1.70 — Fronts-Off World Snow/Hail / Procedural Seed Validation

- Fixed WEATHER FRONTS OFF precipitation coverage so the fallback snow/rain/hail field spans the full rendered world instead of shrinking to a small player-local disk.
- Fixed hail CPU fallback coverage to use the same far-radius contract as the rest of the fronts-off precipitation field.
- Added one-time procedural instancing self-validation for snow and precipitation shaders; if a host collapses all instanced particles into one seed/tube/sky-plume, Weather FX now fails open to the proven full CPU renderer instead of showing a vertical shower column.
- Corrected procedural wind wiring so snow uses snow wind and hail/sand/ash use grain wind.
- Preserved the 8.1.69 SNOW ACCUMULATION menu toggle and all approved 8.1.68 snow-bank height/shape behavior.

# 8.1.69 — Snow Accumulation Toggle

- Added player-facing **SNOW ACCUMULATION** ON/OFF under PRECIPITATION.
- OFF clears existing Weather FX snow banks/footprints immediately and blocks new ground accumulation without disabling falling snow or snow weather.
- ON resumes accumulation from a clean field with the inherited gradual startup ramp.
- Snow-bank heights remain exactly unchanged from 8.1.68 / approved 8.1.67 values.

## 8.1.68

- Removed the old 4-pixel 9×9 player-local aggregate snow lattice that produced visible accumulation lines.
- Added a 45-second accumulation startup ramp and broad golden-angle support sampling out to 112 world units.
- Added true same-surface SnowPack coalescing so overlapping deposits merge into wider mass-preserving banks instead of stacked blobs.
- Flattened mature bank geometry with a broad interior and soft perimeter slope.
- Preserved persistent physical bank mass for the entire active snow-family weather, including while the player walks through it.
- Preserved the exact 8.1.67 accumulation-height profile; 8.1.68 changes only distribution, persistence and bank merging.
- Reduced mature aggregate exact-support work to an 18 samples/second maximum and bounded bank clipping/coalescing neighborhoods.

## 8.1.67

- Fixed live 3D snow using camera/focus Y as a fallback floor; SnowPack now follows the player's actual voxel support.
- Fixed authored raised ledges being flattened or starved by stale/mixed-cell SnowPack support state; real ledges retain independent repaint coverage without detached caps.
- Fixed 2D Gale tornado opportunity timing: NORMAL is 90 seconds / 1.5 minutes and keeps the independent 10% NORMAL carry roll.
- Added player-facing TORNADO FREQUENCY with RARE 180s / NORMAL 90s / OFTEN 60s / EXTREME 30s opportunity spacing.
- Fixed screen-space 2D sun/moon projection following the camera by projecting through the active voxel camera basis.
- Added independent CELESTIAL RENDERING: MATCH WEATHER / 2D SKY / 3D WORLD, including 2D weather + 3D world-space celestial support.
- Added exact 8.1.66 negative controls and real Gen1Recomp/Voxel Nexus framebuffer qualification for the snow/ledge repair.

## 8.1.65

- Fixed 3D Gale tornadoes freezing when the player moved more than one connected outdoor map away.
- Added persistent map-local funnel coordinates and authored outdoor connection traversal while off-screen.
- Remote tornadoes keep aging/moving but submit no invisible Tornado3D geometry.
- The same entity re-enters the current/neighbor render set without respawn or lifecycle reset.
- Added positive regressions plus exact-8.1.64 negative controls for remote roaming and render culling.

## 8.1.64

- Complete player/settings/visual/performance/system audit.
- Restored bounded exact-support live SnowPack banks and real player footprints.
- Preserved GPU/procedural snow ownership and strict interaction budgets.
- Requalified 29 weather types in 2D/3D and major special events.

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

- fixes the original shared carry defect that let 2D and 3D tornado sequences run without making the destination map become the live overworld;
- uses the real live Gen1 `setMap` / Gen2 `warpToMapId` transfer primitive first and requires a destination-map postcondition before synchronous success;
- retains public/private warp APIs only as compatibility fallbacks for hosts without a direct live transfer primitive;
- replaces the incorrect assumption that Gen1Recomp `save.visited` is complete map history with Weather FX's own persisted validated outdoor landing history, merged with engine visit flags for compatibility;
- preserves escape-safe landing validation, Surf restrictions, current-map exclusion, movement lock, blackout/arrival choreography and all 8.1.60 NPC-lightning behavior;
- adds a hostile no-op-warp regression proving both 2D and 3D still change maps and that non-fly outdoor visits remain eligible.

See `RELEASE-NOTES-8.1.61.md`.

# Weather FX 8.1.60 — 2D NPC Lightning / Visible Strike Smoke

- lets normal scheduled 2D lightning independently redirect onto a real visible outdoor NPC using the existing CHARACTER STRIKES / STRIKE CHANCE authority;
- aims at the live current NPC sprite's head/upper body and respects the real letterboxed 160×144 playfield;
- excludes the player, item balls, boulders, fossils and off-screen entities; a missed roll leaves ordinary terrain lightning unchanged;
- gives struck 2D NPCs the existing presentation-only cartoon electrocution treatment: white/black flash, skeleton silhouette, charred state, bright eyes, then automatic restoration;
- adds large high-contrast 2D head smoke after the initial electrical flash and keeps it emitting through the charred state;
- increases 3D post-strike smoke from a barely visible sub-pixel smudge to six bounded dual-layer world-space puffs, still depth-tested and anchored above the NPC;
- keeps the existing default character-strike rule at 10% and reaction duration at 3 seconds;
- does not mutate NPC movement, collision, dialogue, scripts, save state or authored sprite assets.

See `RELEASE-NOTES-8.1.60.md`.

# Weather FX 8.1.59 — Snow Point-Plume Repair

- Fixed the 3D snow "one-pixel fountain" / narrow vertical plume reported in live Voxel Nexus gameplay.
- The plume was duplicate presentation: a perspective-compressed distant StormCell snow/blizzard slab remained visible while the broad player-local WorldPrecip field was already active.
- Added a smooth snow-only visual-ownership handoff: distant snow remains intact while genuinely remote, fades as local snowfall becomes visible, and reaches zero once local snow owns the view.
- Preserved exact local snow/blizzard particle populations, fixed-world anchors, motion, collision-probe virtualization and quality ceilings.
- Rain-front precipitation, fog, cloud banks, lightning and audio are unchanged.
- Added `DistantFrontPrecip` to Weather FX root-owned modules in the shared multi-host bridge, preventing failed host lookups and avoidable CPU front-particle fallback.
- Added executable 8.1.59 regression and negative-control coverage for the point-plume failure.

See `RELEASE-NOTES-8.1.59.md`.

# Weather FX 8.1.58 — Tornado Relocation Completion / Waterspout Contact

- completes the 2D GALE tornado sequence with source-camera lock, real-player sweep-off, destination-confirmed blackout, left-side sweep-in, drop, then tornado exit;
- removes the old four-visited-map availability gate; one other visited destination is sufficient when it independently passes the existing escape-safe proof;
- derives safe inward landing candidates from real outdoor map connections when Weather FX has not already remembered a cell and no authored Fly cell is available;
- adds visible 3D departure and destination-arrival stages around the real cross-map warp;
- makes every sufficiently formed 3D funnel a direct-contact relocation hazard while preserving the separate random seeker/hunting chance;
- uses the public warp completion callback plus destination-map proof before arrival is shown;
- makes live map water tiles authoritative for waterspout conversion;
- adds explicit 3D rotating water-contact annuli, spray collar and blue-white ingested droplets, suppressing the land dirt skirt over water;
- adds matching 2D water-twister spray rings/droplets during relocation;
- adds deterministic relocation/choreography/waterspout regressions and updates the maintained 3D tornado regression for the new depart/arrival stages.

See `RELEASE-NOTES-8.1.58.md`.

# Weather FX 8.1.57 — 2D Gale Relocation Tornado

- adds a true 2D tornado carry event during authored GALE;
- 2D tornadoes are relocation-only and never spawn as ambient/roaming scenery;
- carry chance and a valid previously visited destination are resolved before any 2D funnel becomes visible;
- tornado enters from the left, crosses the screen, engulfs the player near centre, relocates through the existing guarded visited-map path, and exits off the right on the destination map;
- player movement is locked for the short 2D carry sequence;
- STRONG WINDS/sand/dust cannot spawn the 2D tornado;
- CARRY CHANCE OFF or no safe visited destination means no 2D tornado is shown;
- centralizes Funnel.update under Tornado.update so the 2D animation advances exactly once per frame;
- preserves the full 3D Gale tornado system unchanged.

See `RELEASE-NOTES-8.1.57.md`.

# Weather FX 8.1.56 — Seamless Battle Precipitation Handoff

- fixes the snow/rain burst-stop-restart sequence when entering battle;
- removes the old 1-second cached battle check from WorldPrecip;
- suspends overworld precipitation before battle camera/focus re-anchoring can shift particle pools;
- suppresses the flat overworld precipitation layer during battle-opening transition frames;
- primes BattleDraw from finalized `battle.field.weather`, so inherited weather is already at the correct level on the first battle frame;
- preserves normal eased activation for weather created later by moves/abilities;
- preserves 8.1.55 snow density/motion and 8.1.54 GPU precipitation virtualization unchanged.

See `RELEASE-NOTES-8.1.56.md`.

# Weather FX 8.1.55 — Smooth World-Anchored Snow Motion

- fixes visible snow/blizzard fall stutter after 8.1.54 full-visual GPU virtualization;
- gives procedural snow a dedicated monotonic presentation clock so visible fall/tumble is not exposed to stepped/repeated simulation time;
- removes the old 64-unit player-following sliding anchor that made snow move with the player and snap back overhead;
- streams snow between immutable 256-unit world anchors, transferring the same authored instance population instead of translating the whole field;
- preserves the exact 8.1.54 snow/blizzard particle targets and full-GPU virtualization architecture;
- keeps snow ground collision/settling/banks/footprints disabled as requested.

See `RELEASE-NOTES-8.1.55.md` and `PERFORMANCE-AUDIT-8.1.55.md`.

# Weather FX 8.1.54 — Full-Visual Precipitation Virtualization / Snow Collision Suspension

- extends the proven procedural GPU precipitation fields from far-only ownership to the complete visual population on capable drivers;
- preserves all authored MAX counts: rain 12,000 / snow 100,000 / blizzard 200,000 / hail 45,000 / sand 43,200 / debris 3,600 / ash 10,800;
- caps CPU rain and snow interaction state at 96 probes each after GPU proof, while hail/sand/ash can run with zero CPU visual cards;
- keeps debris/leaves fully physical and preserves the complete CPU fallback until a real GPU instanced draw is proven;
- compacts retired high-water CPU particle pools after handoff so dense prior weather does not remain resident in RAM;
- temporarily disables broken snow ground collision/settling/banks/footprints while keeping falling snow fully visible;
- preserves 8.1.53 cloud/sun localization and all earlier storm-front, audio, water, celestial and settings behavior.

See `RELEASE-NOTES-8.1.54.md` and `PERFORMANCE-AUDIT-8.1.54.md`.

# Weather FX 8.1.53 — Spatial Cloud-Sun Terrain Lighting

- separates player-local cloud transmission from map-wide direct sunlight so one hole over the player cannot brighten the entire rendered world;
- samples regional cloud coverage from a bounded 3x3 world-space footprint across the rendered weather corridor;
- keeps local cloud transmission authoritative for sun/moon disc visibility, stars/deep sky and god-ray occlusion;
- projects rotated four-lobe terrain shadows from the same macro cloud bodies used by CinematicAtmos cloud occlusion, so covered terrain remains shaded while real openings stay bright;
- keeps the cloud-light pass bounded to at most 18 visible clouds / 72 terrain lobes with no per-pixel shadow map or cloud ray march;
- preserves all 8.1.52 storm-front, audio, map-persistence and weather-authority fixes plus 8.1.51's zero-upload precipitation performance contract.

See `RELEASE-NOTES-8.1.53.md`.

# Weather FX 8.1.52 — Independent World-Space Storm Fronts / Physical Audio & Cloud Continuity

- makes each StormCell an independent world-space entity: one spawn-time player snapshot, then constant heading/speed with no player-following steering;
- fixes camera-driven weather motion by preferring authoritative Scene/player coordinates over Voxel3D camera focus;
- updates the tiny distant-front descriptor observer every frame, eliminating the old ~0.18 s visible movement stepping;
- makes front rain audio full throughout the physical storm footprint and smoothly distance-attenuated only after the player exits;
- anchors front cloud banks to the physical leading edge and replaces lifecycle row/column swaps with stable continuous formation/parting;
- drives finite-front local sky occupancy through a continuous persistent-cloud gate so storm clouds form/part progressively instead of teleport-filling the sky;
- moves both distant precipitation render paths to a monotonic Weather FX clock, preventing apparent upward/reversed rain;
- caps automatic indoor weather attenuation at 60% so at least 40% of the distance-adjusted outdoor weather bed remains audible, with matching minimum retained high-frequency energy;
- keeps CYCLE weather and storm entities persistent across map transitions instead of rerolling or deleting them at map seams;
- gives WEATHER FRONTS exclusive authority over CYCLE while fronts are enabled, freezing the CYCLE timer until fronts are disabled;
- makes named WEATHER choices automatically disable fronts and remain authoritative until the player changes weather mode;
- preserves 8.1.51's 9,000-particle MAX front budget, zero-upload instancing path, 62% handoff, CPU fallback and all 68 settings.

See `RELEASE-NOTES-8.1.52.md`.

# Weather FX 8.1.51 — Zero-Upload Front Precipitation / Max-Settings Performance

- moves 8.1.50 remote rain/snow/blizzard particle synthesis from per-frame CPU mesh staging to shared-seed hardware instancing on supported hosts;
- preserves the exact 9,000 MAX front budget, 62% handoff, particle morphology/distribution and exact CPU fallback;
- uses an indexed four-vertex instance quad and reuses all steady-frame option/uniform scratch records;
- validates all 68 player settings simultaneously at their highest-load values without AUTO trimming or authored quality reduction.

See `RELEASE-NOTES-8.1.51.md` and `PERFORMANCE-AUDIT-8.1.51.md`.

# Weather FX 8.1.50 — Seamless 3D Front Precipitation

- Replaced distant rain/snow/blizzard hydrometeor cards with bounded discrete world-space 3D precipitation inside the real moving StormCell slab.
- Matched remote rain/snow particle scale families to local WorldPrecip morphology.
- Extended remote/local precipitation overlap to 62% of physical front penetration so local easing can establish before remote precipitation disappears.
- Preserved stable deterministic remote particle identities through the handoff; opacity/density changes without a particle-field teleport or morphology swap.
- Real Gen1Recomp + Pokémon Yellow + Voxel Nexus controlled approach runs passed for both rain and snow at natural physical front speed.
- Added `front_precip_continuity_8150_test.lua`; negative control against exact 8.1.49 fails 6/9 as expected, current 8.1.50 passes 9/9.

See `RELEASE-NOTES-8.1.50.md` and `FRONT-PRECIP-CONTINUITY-AUDIT-8.1.50.md`.

# Weather FX 8.1.49 — Professional Player Settings Audit

- reorganizes all 68 player settings into 11 shallow, task-based categories with no submenu-inside-submenu chain;
- replaces player-facing developer shorthand and ambiguous labels with plain language;
- hides the internal `config` sentinel behind the player-facing word **DEFAULT** without breaking existing saved values or config-file defaults;
- fixes the stale Legendary Events description so Gen 2-capable games are described correctly;
- publishes every setting/group description through `help`, `description`, and `desc` so compatible UI skins show the real explanation instead of generic fallback copy;
- validates every selectable value through the real menu persistence path and visually audits every player row in Gen1Recomp;
- preserves all non-settings runtime systems and assets from 8.1.48.

See `RELEASE-NOTES-8.1.49.md` and `PLAYER-SETTINGS-AUDIT-8.1.49.md`.

# Weather FX 8.1.48 — EngineRuntime Compile Repair

- fixes the 8.1.47 Mod Manager load failure caused by one missing Lua comment prefix in `lib/EngineRuntime.lua`;
- changes no behavioral code beyond that syntax repair;
- preserves every 8.1.47 zero-quality-loss pruning and all 8.1.46 graphics/settings/water/constellation behavior.

See `RELEASE-NOTES-8.1.48.md`.

# Weather FX 8.1.47 — Flat-Voxel Zero-Quality-Loss Runtime Pruning

- removes four SDK/debug-only advisory passes from continuous gameplay scheduling while preserving their public APIs on demand;
- replaces the unused resident 49-cell LightProbeGrid with the exact same analytic probe formula;
- preserves exact renderer-facing volumetric weather aggregates while keeping the 75 detailed cells virtual until explicitly requested;
- caches static flat-world building/tree/water footprint profiles so WindFlow/Hydrology stop rescanning the same 3x3/5x5 neighbourhoods;
- skips AUTO-only predictive/router bookkeeping under fixed manual quality;
- changes no authored visual quality, particles, textures, water, cloud/front, celestial, constellation, aurora, snow/leaf, audio or gameplay settings.

See `RELEASE-NOTES-8.1.47.md`.

# Weather FX 8.1.46 — Seamless Water + Adaptive Low-End Performance + Correct Constellation Dimming

- replaces 8.1.45's visually mismatched ordinary-scene far VOID water with Voxel Nexus' matching SKY-only Water shader while retaining zero far-ocean `beginWater`/depth-frame capture/FULL SSR transaction;
- keeps the 96px near VOID handoff and authored water FULL reflective and preserves exclusive Nexus tide ownership plus public Battle Art ownership;
- upgrades QUALITY PRESET to AUTO/MAX/HIGH/MEDIUM/LOW/POTATO whole-mod profiles covering particles, world precipitation/radius, clouds, generated texture resolution, water reflections, aurora tessellation, celestial disc layers, Weather FX shadow precision, snowpack budgets and background simulation cadence;
- adds AUTO PERFORMANCE policy, 60/50/40/30 FPS target, TEXTURE DETAIL, WATER REFLECTIONS, EFFECT DISTANCE and SIMULATION DETAIL controls in a dedicated PERFORMANCE submenu, all defaulting to FOLLOW QUALITY where applicable;
- keeps manual quality tiers exact and makes AUTO adapt only Weather FX workload with sustained-pressure hysteresis and slow recovery;
- removes fake town-centre/corner constellation light-pollution emitters and uses real voxel building/roof footprints where available, so constellations brighten monotonically as the player moves away from buildings;
- preserves all 25 constellation subjects / 8,507 traced stars and the exact equal 8.1.43 unobstructed maximum brightness contract.

See `RELEASE-NOTES-8.1.46.md`.

# Weather FX 8.1.45 — Voxel Nexus Exclusive Water + VOID Performance

- fixes Voxel Nexus curved-water double-height bleed by neutralizing its additive `WaterEngine.tideOffset` only while Weather FX owns the replacement, then restoring the exact native function;
- keeps the curved depth prepass and reflective pass on the same Weather FX tide datum, removing the lower old-water surface that could show through;
- removes the far synthetic 32K VOID ocean from a second Voxel Nexus FULL reflection/depth transaction and draws its already-deformed physical mesh once through the scene shader;
- keeps the exact 96px VOID handoff and all authored water on the full reflective Nexus path;
- preserves public Battle Art behavior and reflective fallback for other hosts/failures.

See `RELEASE-NOTES-8.1.45.md`.

---

# Weather FX 8.1.44 — Public Battle Art Exclusive Water Ownership

- distinguishes upstream/public Battle Art 1.10.x from Voxel Nexus by actual Water capabilities despite their shared `BATTLE_ART_VOXEL_FORK` id;
- recognizes public Battle Art's structured `WAVE_TRAINS`/`WAVE_SWELL`/`WAVE_BEND` + `_waveTime` contract even though it lacks Voxel Nexus' `_trainSource` export;
- enables Weather FX tessellated physical water on public Battle Art and sets native `Water.WAVE_HEIGHT` to zero after successful ownership, removing the second geometric relief surface;
- preserves the host reflection/depth pass, 8.1.40 WorldUnderlay suppression, ORIGINAL/fail-open behavior, authored water safety and every later weather/celestial feature.

See `RELEASE-NOTES-8.1.44.md`.

---

# Weather FX 8.1.43 — Exact Constellation Peak Brightness

- audits all 25 traced constellations / 8,507 traced stars rather than applying another global brightness bump;
- removes the 8.1.25 density-energy gain spread that left dense constellations visibly dimmer at maximum brightness;
- locks every constellation to exact 1.0 subject gain while preserving the approved .96/.73 landmark/trace alpha hierarchy;
- minimally luminance-normalizes each constellation tint to the same Rec.709 display-luma target, preserving distinct hues while equalizing perceived peak brightness;
- preserves building/cloud dimming, depth occlusion, twinkle, geometry, anchors and all 8.1.42 aurora/snowstorm behavior.

See `RELEASE-NOTES-8.1.43.md` and `CONSTELLATION-BRIGHTNESS-AUDIT-8.1.43.csv`.

---

# Weather FX 8.1.42 — Winter Snowstorms + Research-Grounded Aurora

- adds a research-grounded winter aurora system built from thin layered world-vault curtains rather than a flat green overlay;
- uses altitude-structured green / purple-blue / red emission, folded/rayed morphology, slow coherent motion and strong-event overhead corona geometry;
- strongly weights natural aurora toward winter while giving every spring/summer/autumn night an independent deterministic 5% aurora chance;
- makes clouds physically occlude aurora and lets moon/building light reduce apparent contrast;
- upgrades distant BLIZZARD / THUNDERSNOW fronts to dedicated wind-driven multi-band snow walls with ground blowing-snow veil instead of recoloured rain curtains;
- preserves the 8.1.41 world-scale reachability/interception engine and all 8.1.40 water ownership behavior.

See `RELEASE-NOTES-8.1.42.md`.

---

# Weather FX 8.1.41 — Reachable World-Scale Storm Fronts

- removes the old final-320-unit approach fade that caused storm fronts to dissolve as the player got close;
- adds cell, regional, broad and synoptic front-size classes with multi-map cross-front footprints;
- slows world translation substantially and makes larger weather systems move more slowly than compact cells;
- guarantees useful leading-edge lifetime and adds bounded connected-world interception steering so fronts can actually reach travelling players without teleporting;
- lets players physically intercept an incoming front sooner by walking toward it;
- anchors distant 3D banks on the physical leading edge and scales shared cloud-bank coverage from true front width instead of the old small visual cap;
- preserves the integrated cloud-bank handoff, cross-map continuity, 8.1.40 exclusive VOID-water ownership and all prior gameplay safety.

See `RELEASE-NOTES-8.1.41.md`.

---

# Weather FX 8.1.40 — Exclusive Void-Water Handoff

- closes the last Voxel Nexus/Battle-Art double-water path by owning the separate `WorldUnderlay.draw()` outer fill when Weather FX successfully owns `VOID FILL = WATER`;
- preflights the physical VOID ocean before suppressing the host underlay, preserving fail-open behavior if Weather FX cannot prepare;
- preserves `WorldUnderlay.drawFootprints()` safety floors beneath loaded maps so terrain holes do not reveal ocean through authored land;
- reuses the same prepared Weather FX water rows in the later reflective `VoxelScene.drawWater` seam rather than preparing a second copy;
- keeps `WATER STYLE = ORIGINAL`, non-water VOID modes, authored ponds, waves, reflections, ice, Surf/collision safety and all 8.1.39 multi-host compatibility unchanged.

See `RELEASE-NOTES-8.1.40.md`.

---

# Weather FX 8.1.39 — Universal Voxel Void-Water Ownership

- Generalizes `VOID FILL = WATER` from the Voxel Nexus-specific outer seam to the shared voxel-host bridge.
- Supports Battle Art / Voxel Nexus, Dramatic Shape, Dramaless Shape, Potato Voxel aliases and Stadium2/Gen2 overworld through one capability record.
- Uses call-time `Map.isOutdoor()` so Gen2 ROUTE/TOWN maps are eligible without a Gen1 `OVERWORLD` tileset.
- Probes optional `WorldUnderlay.RANGE` when available; otherwise uses the bounded universal 32768-unit physical horizon.
- Preserves each host's own `drawWater` reflection/depth function and variadic arguments when present.
- Adds a depth-tested synthetic-VOID-only fallback for compatible hosts/frames without `drawWater`.
- Preserves WATER STYLE ORIGINAL fail-open behavior and all 8.1.38 living-pond/fish/gameplay-safety behavior.

See `RELEASE-NOTES-8.1.39.md`.

# Weather FX 8.1.38 — Living Ponds / Complete Void Ocean

- authored POND-class connected water now uses a translucent reflective 46–54% surface pass with a shallow procedural pond bed;
- adds 2–6 deterministic tiny 3D fish per authored pond, capped at 24 whole fish, cell-confined and suppressed as pond ice closes;
- bypasses only the host's opaque curved-water prepass for the specialized pond path, with immediate fail-open to ordinary host water;
- extends `VOID FILL = WATER` ownership beyond the existing exact 96px apron across the current 32768-unit Voxel Nexus WorldUnderlay radius;
- outer void water shares the same physical tide/wave state, leaves holes for loaded maps, and remains strictly presentation-only;
- preserves `WATER STYLE = ORIGINAL`, Surf/collision/progression safety, all broad-water rendering and all 8.1.37 storm-cloud/weather/celestial behavior.

See `RELEASE-NOTES-8.1.38.md`.

---

# Weather FX 8.1.37 — Integrated Storm Cloud Bank

- Distant StormCell cloud fronts now join the ordinary live cloud-bank descriptor field instead of using a separate dark tessellated-ellipsoid renderer.
- Front cloud centers use the exact bank deck-height equation and CLOUD HEIGHT scaling; the live local deck becomes authoritative during handoff.
- Mature fronts gain staggered horizontal X/Z thickness and dense overlapping ordinary cloud formations instead of vertically stacked black rounded bodies.
- Distant precipitation/fog/lightning remains separate, but its curtain/bolt origin now uses the same front deck altitude as the integrated clouds.
- 8.1.36 world-front continuity, remote lightning/true-distance thunder, seasonal climatology, celestial continuity, water/ice ownership and zero-quality-loss performance work are preserved.

See `RELEASE-NOTES-8.1.37.md`.

---

# Weather FX 8.1.36 — World Front Continuity / Zero-Quality-Loss Performance

- persistent cloud-first distant weather fronts with continuous local handoff and remote lightning/thunder;
- true tessellated 3D storm/anvil volumes instead of flat-looking front cards;
- seasonal weather hard gates/biases plus naturally reachable celestial-event qualification;
- connected-world building-light continuity for stars and constellations;
- complete Weather FX ownership of host 8x8 water fragments and suppression of duplicate host water rendering;
- preserved seasonal freeze/thaw and load-bearing authored ice;
- fused one-pass physical wave sampling and low-allocation persistent foam construction with no quality/population reduction;
- defensive water safety only; no claim to fix Gen1Recomp's separate out-of-bounds issue.

# Weather FX 8.1.35 — Persistent Whitewater

- replaces fixed-point on/off whitecap quads with deterministic persistent crest-following foam tracks;
- makes foam grow and collapse smoothly and permits analytic lifetime resets only at effectively zero visible size, eliminating the apparent teleport jump;
- replaces square open-water patches with tapered, slightly crooked five-section foam ribbons;
- keeps raised curling lips attached to the same moving whitecap identity;
- changes river whitewater into downstream-moving tapered streaks with invisible lifecycle resets;
- removes the time-bucket random shoreline-break reroll and uses stable coastline identities with smooth pulse cycles;
- preserves 8.1.34 void-water ownership, WATER STYLE handoff, 3D wave relief, reflections, Surf bob, tides, rain ripples, progressive ice and gameplay safety.

# Weather FX 8.1.34 — Void Water Unification

- hooks Gen1Recomp's live `VOID FILL = WATER` authority and replaces the voxel host's flat synthetic border-water apron with Weather FX physical water;
- reproduces Voxel Realism's exact three-block / 96px current-map apron and strict connected-neighbour body masking;
- routes void water through the same tessellated 3D sea waves, crest/trough motion, reflections, whitecaps, curling lips and weather-driven sea state as authored water;
- keeps synthetic void water presentation-only: no cartridge `bodyByCell`, collision, Surf authority, freezing, load-bearing ice, SnowPack or progression effects;
- makes live VOID FILL WATER/TREES/BLACK changes rebuild water topology immediately without requiring a map change;
- extends the existing `WATER STYLE = WEATHER FX / ORIGINAL` handoff to void water, so ORIGINAL restores the host's untouched flat void-water draw and WEATHER FX reclaims it instantly;
- preserves the full 8.1.33 Professional Physical Water implementation and all prior weather/celestial/gameplay behavior.

# Weather FX 8.1.33 — Professional Physical Water

- replaces the flat connected-water silhouette on structured Voxel Realism with a true indexed dynamic 3D surface rather than another texture/ripple-only treatment;
- uses a Gerstner-inspired multi-train spectrum with real crest/trough displacement and bounded horizontal orbital motion for forward-leaning waves;
- pins horizontal displacement at the exact cartridge shoreline and blends it inward so waves cannot crawl under authored land;
- classifies connected water topology as pond, lake, river, or sea and scales calm heave/exposure/rapid behavior accordingly;
- adds depth-tested crest whitecaps, raised/folded curling foam lips, directional river rapid streaks, and impact-facing shoreline break foam;
- drives Surf/player presentation bob from the exact same moving surface sampler without changing gameplay coordinates, collision, Surf state, warps, or progression;
- keeps Voxel Realism's mature reflective shader as the reflection/material layer while the real mesh owns the visible silhouette;
- retains the 8.1.32 fail-open reflective-relief compatibility path if true structured dynamic meshes are unavailable;
- reuses dynamic surface meshes and uses 8-pixel tessellation for broad bodies / 4-pixel tessellation for small water to keep the new physical geometry practical without deleting authored visual features;
- preserves all 8.1.32 performance work and every unrelated Weather FX weather, celestial, ice, SnowPack, audio, battle, season, settings, and gameplay contract.

# Weather FX 8.1.32 — Mega Performance Audit / Zero-Quality-Loss Hot Path

- preserves every 8.1.31 real-wave, ice, Surf, WATER STYLE, weather, celestial, audio, battle, season, and gameplay behavior;
- caches successful ConnectedWater dependencies instead of protected-resolving WindEngine, CelestialSim, TimeOfDay, Microclimate, and Settings every tick/query;
- caches ConnectedWater3D host/private module handles between steady water frames, with invalidate/handoff clearing them so hot reload still re-resolves safely;
- reads connected-water wind direction directly from the published hydrosphere state rather than creating a public diagnostics snapshot every water render;
- reuses reflective-water draw rows and translation matrices on the verified structured Voxel Realism water API; unknown/older hosts retain their allocation-safe compatibility behavior;
- adds a permanent hot-path regression that proves module lookup, diagnostics, transform reuse, mesh stability, tide tracking, and hot invalidation behavior;
- does not reduce particle populations, water wave amplitude/resolution, rain-ripple cap, snow density, cloud/celestial/shadow quality, or any player-visible setting.

# Weather FX 8.1.31 — Real Rolling Water / Native Water Handoff

- centers compatible Voxel Realism relief water around the physical tide datum so troughs fall below mean water while crests rise above it;
- replaces equal-frequency bumping with a long dominant swell, oblique cross-sea, light opposing chop, moving wave groups, and curved crest bands;
- reaches up to one cartridge tile peak-to-trough at the strongest connected-water sea state while keeping calm water subtle;
- adds a below-datum, boundary-only shoreline seal so deep troughs cannot reveal void seams beside banks;
- makes a Surfing player and first-person eye ride the exact same wave field as presentation-only motion without changing gameplay coordinates, collision, Surf state, or warps;
- adds **WATER STYLE = WEATHER FX / ORIGINAL** to the in-game **ATMOSPHERE** menu; ORIGINAL immediately restores the voxel host's untouched water renderer/tuning and masks Weather FX ice-walking/frozen-water presentation, with no restart required;
- preserves 8.1.30 progressive realistic ice, cartridge shoreline authority, freeze/thaw physics, tides, rain ripples, SnowPack integration, and all unrelated Weather FX systems.

# Weather FX 8.1.28 — World-Scale Realism Phase 1

- Final live-host qualification: root-first Weather FX private voxel helpers and NpcLightning Voxel3D.size()/canvas() live-host compatibility.

- explicitly removes mountain/orographic microclimate assumptions for the flat voxel world;
- adds town/forest/water/open-route voxel-footprint microclimates and directional shelter/wind shadows;
- makes real 3D rain collide with roofs/raised props while tree canopy remains partially permeable;
- keeps post-rain wetness visible and rejects sheltered/water land-puddle deposition;
- redesigns and re-enables bounded SnowPack accumulation/melt on exact voxel supports;
- renders bounded depth-tested distant rain/snow/fog curtains from existing StormCells;
- adds local structure/canopy acoustic propagation and water-storm ambience authority;
- routes the real lightning flash envelope through DynamicLighting/UnifiedLighting/LightProbeGrid;
- replaces fake hydrology elevation with flat basin/outlet drainage;
- preserves 8.1.27 live-host fixes and all population/quality targets.

# Weather FX 8.1.27 — Live Host Repair

- fixed overhead sealed-cloud nil projection arithmetic found in a real Yellow/Voxel run;
- removed dead puddle shader uniform send rejected by live LÖVE 11.5;
- added grow-only fallback atmosphere mesh capacities to prevent `Too many vertices`;
- fixed NightSky celestial shader texcoord type mismatch with `VertexTexCoord.xy`;
- preserves all particle/cloud/celestial counts and quality settings.

# Weather FX 8.1.26 — Celestial Realism / Player Experience Repair

- replaced the flat emergency sun/moon body fallback with a dense detailed procedural CPU renderer;
- routed the 2D sun/moon path through the shared detailed celestial-body authority;
- reduced excessive radial limb shading while strengthening solar granulation/sunspots and lunar maria/crater/highland structure;
- widened direct-look solar optics to a gradual 18-degree onset with separate rays, warm sensor response and near-center whiteout ramps;
- fixed reversed physical sky-band interpolation in AtmosphereModel;
- strengthened directional dawn/dusk horizon scattering while keeping the zenith cooler;
- restored the full README/truth documentation accidentally truncated in 8.1.25;
- completed player-flow, 2D/3D weather, settings, compatibility, performance and code-bug audits.

# Weather FX 8.1.25 — Constellation Uniformity

- normalized whole-constellation perceived brightness across all 25 approved traced subjects while preserving the existing per-star hierarchy;
- added deterministic anchor spreading so closely packed constellations are separated more clearly in the sky;
- constellations now dim near buildings with the same BuildingLight star-scale rule as ordinary stars;
- preserved the 8.1.24 zero-quality-loss performance contract.

Compatibility truth retained: AUTO keeps the existing fail-safe behavior when strict 3D ownership is unavailable; explicit 3D remains strict only while an active voxel host can own the 3D weather compositor.

- 8.1.58: repaired 2D tornado relocation blackout at the final `render.hud` framebuffer seam; destination-map rendering can no longer overwrite the blackout during transfer.


## 8.1.85

- Added player-facing **CLOUD BANK STYLE** with `VOLUMETRIC` (default, exact 8.1.84 presentation) and `BLOCKY`.
- BLOCKY renders the existing authoritative cloud descriptors as flat world-space rectangular tile fields with a voxel/pixel silhouette and bounded translucency.
- BLOCKY reuses the same cloud height, density, wind advection, map persistence, WEATHER FRONTS descriptors, precipitation origins, lightning/tornado attachment and cloud transmission/occlusion authority as the volumetric bank.
- Block clouds remain in the 3D depth pipeline and fail open to the proven volumetric renderer if a host refuses the block shader/mesh.
- Player settings schema is now 77 controls.

## 8.1.84
- Unified base OPTIONS WEATHER and Weather FX Mod Manager WEATHER MODE into one live/persisted weather authority.
- Fixed OPTIONS weather changes being ignored by stale Mod Manager OFF/named state.
- Both selectors now mirror each other immediately and remain reversible from OFF.

## 8.1.89
- Fixed classic 2D weather periodically restarting from the beginning on hosts that rebroadcast unchanged WEATHER options.
- Same-value WEATHER events are now strict no-ops: they do not bump weather authority or call the pipeline setter.
- `pushWeatherToLadder()` and pending ladder reconciliation now avoid calling `setLevel()` when the engine already reports the requested rung.
- Real WEATHER changes still apply immediately exactly once.
- Added `weather_2d_restart_8189_test.lua`; fixed 8.1.89 passes 5/5 while exact 8.1.88 fails 4/5 checks.

## 8.1.96
- Added **PAUSE MENU WEATHER = ANIMATED / FROZEN** to the in-game WEATHER settings.
- Native START/pause stacks are recognized as world overlays, fixing classic 2D weather disappearing while START is open.
- FROZEN now holds all Weather FX update evolution at zero delta, not only motion clocks, so precipitation populations cannot change while the player expects a frozen frame.
- Real Yellow + Battle Art 1.10.4 flat/2D framebuffer qualification proves: weather visible under START context, ANIMATED changes, FROZEN is pixel-identical across 30 frames, and motion resumes after exit.
## 8.2.14
- Removed the former **RAVE** weather mode from Weather FX.
- Removed its manual weather selector entry, RAVE MUSIC / RAVE STROBE settings, RaveMusic module, bundled rave soundtrack, music-ownership hooks, 3D laser/fog/floor show, cloud rave tint, and battle carryover.
- Legacy saves containing `WEATHER = RAVE` now migrate safely to `AUTO`.
- Standalone **Poke Rave** is not part of this package and is unaffected.
- Preserved and requalified all ordinary Weather FX systems.

