#!/usr/bin/env python3
from pathlib import Path
import json, re, sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,n):
    checks.append((bool(v),n))
    if not v: print('FAIL',n)
def text(rel): return (R/rel).read_text(encoding='utf-8',errors='replace')
manifest=json.loads(text('manifest.json'))
wp=text('lib/voxel_atmos/WorldPrecip.lua'); ns=text('lib/NightSky.lua'); au=text('lib/Audio.lua'); st=text('lib/Settings.lua'); pg=text('lib/PerformanceGovernor.lua'); rg=text('lib/RenderGraph.lua'); er=text('lib/EngineRuntime.lua'); q=text('lib/Quality.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua')
ver=tuple(int(x) for x in str(manifest.get('version','0.0.0')).split('.')[:3]); ck(ver >= (8,0,1),'manifest is 8.0.1+ performance line')
# MAX authored content is immutable in this optimization pass.
for marker in ['worldRainCap=12000','worldSnowCap=100000','worldBlizzardCap=200000','worldHailCap=45000','worldSandCap=43200','worldDebrisCap=3600','worldAshCap=10800','worldPrecip=1.00']:
    ck(marker in q,'MAX preserves '+marker)
ck('local RAIN_MAX = 12000' in wp and 'local SNOW_MAX = 100000' in wp and 'local HAIL_MAX = 45000' in wp,'hard precipitation pools unchanged')
ck('if not autoMode() then state.mode="manual";state.frameScale=1;state.scale=1;return 1 end' in pg,'manual quality bypasses governor particle trimming immediately')
ck('graph:setProfilingEnabled(Governor.auto())' in er,'fixed tiers disable pass timing')
ck('if not Governor.auto() then return end' in er and 'system_profiler' in er,'fixed tiers skip system profiler work')
# Cross-mod/cross-frame config overhead.
ck('function Settings.beginFrame()' in st and '_frameStamps' in st and 'stamps[key]==serial' in st,'settings reads are one-frame cached')
ck('Settings.beginFrame()' in text('main.lua'),'main begins settings cache each frame')
ck('profileEvery=' in rg and 'rawStats()' in rg and 'profilingEnabled' in rg,'RenderGraph samples timing and has zero-allocation raw stats')
ck('local reqCache={}' in er and 'reqCache[name]=v' in er,'environment runtime caches successful internal modules')
ck('local function refreshSurface(c)' in er and 'sampleInto(c.worldX,c.worldZ,c.surface)' in er,'environment runtime reuses one surface snapshot')
# MAX snow keeps every flake but submission and RAM are bounded.
ck('chunk=8192' in wp and 'for i=snowInstance.rowCap+1,chunk do' in wp,'snow instancing staging is fixed-size/chunked')
ck('love.graphics.drawInstanced' in wp and 'SnowInstanceA' in wp and 'SnowInstanceB' in wp,'snow has GPU instancing submission path')
ck('drawSnowFlakesCPU' in wp or 'drawSnowFlakes' in wp,'snow retains CPU fallback path')
for obsolete in ['phRate = {}','turb = {}','bobPhase = {}','swayPhase = {}','fallRate = {}','rollRate = {}','sizeSeed = {}']:
    ck(obsolete not in wp,'redundant snow array removed: '+obsolete.split('=')[0].strip())
ck('rainSteerAmt' in wp and 'snowSteerAmt' in wp and 'grainSteerAmt' in wp,'hot-loop steering invariants are hoisted')
ck(all(x not in wp for x in ('uFreq1={}','uPhase1={}','uFreq2={}','uPhase2={}','drawRotRate={}','drawFlutterFreq={}','drawFlutterPhase={}','drawBaseRot={}')),'grain families remove deterministic duplicate coefficient arrays')
ck('_seen=serial' in text('lib/CloudField.lua') and '_seen=serial' in text('lib/WindFlow.lua') and 'keepScratch' not in text('lib/CloudField.lua') and 'keepScratch' not in text('lib/WindFlow.lua'),'cloud/wind bounded grids use zero-churn generation stamps')
# Celestial identity is complete on every quality and projection is zenith stable.
ck('lod.starStep,lod.maxPlanets,lod.twinkle,lod.meteors=1,#PLANETS,true,true' in ns,'NightSky never quality-thins celestial catalogue')
ck('starStep=1' in q.replace(' ','') and 'maxPlanets=9' in q.replace(' ','') and 'twinkle=true' in q.replace(' ','') and 'meteors=true' in q.replace(' ',''),'Quality celestial API preserves sky identity')
ck('_projectionRightX' in ns and 'hl>1e-5' in ns and 'Camera pitch only' in ns and 'never rescales the vault' in ns,'sky projector has zenith-stable camera basis')
ck('local N = 5120' in ns and 'POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in text('lib/Constellations.lua'),'5,120 stars and exact constellation catalogue preserved')
# Audio is real-time state authority, never draw authority.
ck('Audio.update follows WeatherState + Scene every frame' in au and 'Visual rendering is NOT audio authority' in au,'weather audio is update/state authoritative')
body=au[au.find('function Audio.nudgeFromVisual'):au.find('function Audio.describe')]
ck(':play()' not in body and ':stop()' not in body and 'stopAllBeds' not in body,'visual nudge cannot start/stop audio')
ck('_frameAudioCfg' in au and 'local a = audioCfg()' in au,'audio config is cached per audio frame')
ck('setVolumeIfChanged' in au and 'setPitchIfChanged' in au,'audio avoids redundant native volume/pitch calls')
# Atmosphere avoids recurring giant Lua staging allocations.
for marker in ['_mist','_fog','_ray']:
    ck(marker.lower() in ca.lower(),'cinematic atmosphere retains reusable '+marker+' staging marker')
failed=sum(not ok for ok,_ in checks)
print(f'8.0.1 performance/regression static gate: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
