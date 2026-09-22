#!/usr/bin/env python3
"""Weather FX 8.0.2 low-end/MAX zero-quality-loss optimization contracts."""
from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1]
def text(rel): return (R/rel).read_text(encoding='utf-8',errors='replace')
checks=[]
def ck(v,n): checks.append((bool(v),n)); print(('PASS ' if v else 'FAIL ')+n)
wp=text('lib/voxel_atmos/WorldPrecip.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua'); ns=text('lib/NightSky.lua'); cs=text('lib/CelestialStarField.lua'); fog=text('lib/Fog.lua'); q=text('lib/Quality.lua'); man=text('manifest.json')
# Exact visual ceilings remain authored.
for marker,name in [('RAIN_MAX = 12000','rain 12,000'),('SNOW_MAX = 100000','snow 100,000'),('HAIL_MAX = 45000','hail 45,000')]: ck(marker in wp,f'MAX preserves {name}')
ck('worldBlizzardCap=200000' in q and 'worldSandCap=43200' in q and 'worldAshCap=10800' in q,'MAX preserves blizzard/sand/ash ceilings')
ck('local N = 5120' in ns and 'POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in text('lib/Constellations.lua'),'MAX preserves 5,120 stars and exact constellations')
ck('lod.starStep,lod.maxPlanets,lod.twinkle,lod.meteors=1,#PLANETS,true,true' in ns,'quality never thins celestial catalogue')
# Far precipitation virtualization.
for rel in ['lib/InstanceSeedBuffer.lua','lib/ProceduralSnowField.lua','lib/ProceduralPrecipField.lua']:
    ck((R/rel).is_file() and (R/rel).stat().st_size>0,f'{rel} present')
ck('snow.simActive' in wp and 'snow.gpuActive' in wp and 'snow.simRadius' in wp,'snow physical-near/procedural-far split live')
ck('rain.simActive' in wp and 'rain.gpuActive' in wp,'rain physical-near/procedural-far split live')
ck('grain.simTarget' in wp and 'grain.gpuTarget' in wp,'hail/sand/ash physical-near/procedural-far split live')
ck('kind~=3' in wp,'leaves remain fully physical')
ck('drawInstanced' in text('lib/ProceduralSnowField.lua') and 'drawInstanced' in text('lib/ProceduralPrecipField.lua'),'far weather uses hardware instancing')
ck('InstanceSeed' in text('lib/InstanceSeedBuffer.lua') and '8192' in text('lib/InstanceSeedBuffer.lua'),'shared immutable 8,192 seed window is bounded')
# Ordinary stars: one immutable catalogue and projected-path acceleration.
ck('local F=V.require("CelestialStarField")' in text('tests/celestial_star_field_test.lua') or "V.require('CelestialStarField')" in text('tests/celestial_star_field_test.lua'),'star instancing executable regression exists')
ck('state.catalogue==stars' in cs and 'state.builds=state.builds+1' in cs,'star catalogue uploads once and is reused')
ck('function F.drawProjected' in cs and 'drawInstanced' in cs,'strict projected star path is instanced')
ck('_drawInstancedProjectedStars' in ns and "starBackend=gpuStars and 'instanced' or 'cpu'" in ns,'NightSky strict path selects instanced stars with CPU fallback')
# Cloud submission: same puffs, compact upload, bounded cache.
ck('CinematicAtmos._cloudInst' in ca and 'CloudCenter' in ca and 'CloudShape' in ca,'cloud puff instancing path present')
ck(('pcall(love.graphics.drawInstanced,ist.base,icount)' in ca) or ('V.safeCall(love.graphics.drawInstanced,ist.base,icount)' in ca),'all visible cloud puffs submit in one instanced draw')
ck('local pdata=CinematicAtmos._cloudPuffData(c)' in ca and 'c._puffIx==c.ix' in ca,'deterministic puff coefficients cache on bounded candidate pool')
ck('local verts, indices = buildCloudVertices' in ca,'legacy cloud mesh fallback remains')
# Fog/atmosphere allocations.
ck('Fog._quadVerts' in fog and 'local function setQuad' in fog,'2D fog reuses one quad staging buffer')
ck('m:setVertices({' not in fog[fog.find('function Fog.draw('):],'fog draw paths allocate no nested per-bank vertex tables')
for marker in ['_mistRows','_rollRows','_rayRows']:
    ck(marker in ca,f'3D atmosphere reuses {marker} staging')
# No manual-quality adaptive reductions.
ck('if not autoMode() then state.mode="manual";state.frameScale=1;state.scale=1;return 1 end' in text('lib/PerformanceGovernor.lua'),'manual quality bypasses particle adaptation immediately')
ck('graph:setProfilingEnabled(Governor.auto())' in text('lib/EngineRuntime.lua'),'manual tiers disable profiler timing')
m=re.search(r'\"version\"\s*:\s*\"(\d+)\.(\d+)\.(\d+)\"',man); ck(bool(m) and tuple(map(int,m.groups())) >= (8,0,2),'manifest preserves 8.0.2+ performance lineage')
failed=sum(not ok for ok,_ in checks)
print(f'8.0.2 performance/regression static gate: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
