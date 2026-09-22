# Weather FX 8.1.64 — Complete Player / Visual / Settings / Performance / Systems Audit

## Scope and truth standard

This audit covers the exact 8.1.64 runtime derived from exact 8.1.63. A unit/static PASS is not reported as a visual PASS. Real framebuffer qualification is specifically Gen1Recomp 0.2.53 / LÖVE 11.5 + the preserved user-provided Pokémon Yellow input + Voxel Nexus 2.0.16. Other supported voxel hosts are covered by compatibility/source/runtime contracts unless separately stated.

## Player settings

All 68 player-facing settings are present once, have defaults/choices, have live consumers, are grouped into player submenus and have descriptions. Complete executable settings suite: 49/49 programs. Interaction audit: 2020/2020. Runtime setting audit: 648/648. Description audit: 1693/1693. General settings/runtime audit: 246/246.

Settings: quality, autoPerformance, performanceTarget, textureDetail, reflectionDetail, effectDistance, simulationDetail, always, intensity, rainIntensity, snowIntensity, fogIntensity, sandIntensity, dustIntensity, exotic, speed, daytime, seasons, clouds, cloudHeight, waterStyle, leafColor, snowShape, hemisphere, seasonNotify, battles, battleAnim, battleDamage, amplified, lightning, lightningFlash, stormDarkness, backdrops, sfx, splash, indoors, tornado, tornadoPickup, present, transitionSpeed, fronts, frontStrength, mesoscale, mesoscaleStrength, windIntensity, windWalk, puddles, rainbows, godRays, npcLightning, npcStrikeChance, tornadoFrequency, celestialEvents, smoothSky, celestialMotion, timeSource, dayLength, seasonLength, indoorAudio, thunderAudio, thunderVolume, windAudio, weatherEncounters, legendaryEvents, followerChip, particleCap, debugRain, debug.

## Weather visual audit

All 29 weather definitions activate through the player option pipeline and were captured in real 2D and 3D outdoor presentation: CLEAR, SUNNY, HARSH_SUN, RAIN_LIGHT, RAIN_HEAVY, HEAVY_RAIN, STORM, SNOW_LIGHT, BLIZZARD, HAIL, SANDSTORM, STRONG_WINDS, PLAIN_FRONT, VERDANT_RAIN, BRAWL_WIND, SMOG, DUSTSTORM, FLOCKSTORM, SWARM, HAUNTED_MIST, DRAGONSTORM, SLEET, THUNDERSNOW, ASHFALL, HEATWAVE, GALE, PSYSTORM, MIST, FOG.

MIST is intentionally natural/AUTO-only and is not a manual WEATHER ladder choice. Corrected 2D and 3D contact sheets are release artifacts. 2D style audit: 94/94. Cross-presentation render pipeline: 352/352. 3D pipeline integrity: 117/117.

## Events

Rainbow behavior 11/11; winter aurora 19/19; celestial engine 49/49; celestial clock visibility 15/15; celestial occlusion/brightness 10/10; rise/set continuity 19/19; star field 7/7; lightning burst 24/24; world-space lightning 493/493; NPC lightning 43/43 plus 15/15 2D; storm-front integration 13/13; front realism 9/9 and motion/audio 15/15; tornado pickup semantics 20/20 and walk contact 8/8.

Real special-event driver exits cleanly with rainbow alpha 0.465, winter aurora active visibility 0.727, and lightning flash 1.0 with a live bolt. Tornado 2D sweep / 3D walk-in / 3D seeker were previously real-host proven in 8.1.63 and the unchanged Tornado.lua remains byte-identical in 8.1.64.

## SnowPack

The audit found one genuine live gap inherited from 8.1.54: falling 3D snow no longer fed persistent banks/footprints. 8.1.64 repairs it. Real held-input proof: 9.008 world-pixel player movement through accumulated snow -> 2 persistent footprints, 1 live footprint draw; 113 ground-snow draws / 66 cells / 118 patches. Water rejection and exact support remain intact.

## Performance

Performance invariants 66/66; benchmark 26/26; benchmark integration 24/24; near precipitation virtualization 17/17; MAX precipitation virtualization 8/8; 8.1.54 performance contract 11/11; 8.1.55 snow-motion preservation 10/10; MAX no-quality-loss 5/5; LuaJIT WorldPrecip update estimated direct upvalues 49 (ship threshold 55, hard 60). SnowPack restore adds no unbounded per-flake CPU work: <=96 interaction probes and <=24 aggregate support samples/second.

## Systems and engines

Feature integrity 501/501. Engine architecture 11/11. Environment-engine static layers 17/17 and 30/30; executable environment engine 3 28/28; mesoscale 12/12; weather/thunder authority 110/110; wind engine 20/20; voxel-host contract 27/27; strict 3D guard 9/9. Aggressive compatibility: 30 PASS, 0 MED, 0 HIGH. AI debug: FAIL=0, WARN=0.

Major audited systems include WeatherState/AUTO authority, fronts and synoptic transitions, mesoscale fields, wind/leaf physics, precipitation and GPU virtualization, SnowPack, fog/cloud/atmosphere, water/ice handoff, celestial/sky/aurora, lightning/NPC reactions, tornadoes, audio/thunder, encounters/legendary events, battle weather/art, persistence, performance governor, environment SDK and voxel-host composition.

## Audit boundaries

No HIGH defects remain. Five MED/manual/robustness notes remain: real framebuffer composition has been proved on Voxel Nexus 2.0.16 rather than every optional voxel host; hot-unload/uninstall requires live destructive testing; sun/moon overhead/orbit orientation still merits manual engine viewing; Settings.lua and Tornado.lua retain high pcall density. These are explicitly retained rather than silently promoted to PASS.
