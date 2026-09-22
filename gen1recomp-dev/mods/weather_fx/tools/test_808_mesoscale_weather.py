#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def has(rel,*parts):
    s=(ROOT/rel).read_text(encoding='utf-8',errors='replace')
    return all(p in s for p in parts)
def check(name,cond):
    checks.append((name,bool(cond))); print(('PASS ' if cond else 'FAIL ')+name)

check('MesoscaleField module ships', (ROOT/'lib/MesoscaleField.lua').exists())
check('mesoscale is O(1) procedural field', has('lib/MesoscaleField.lua', "memory='O(1)'", 'valueNoise', 'sampleInto', 'PATCH_SCALE=520'))
check('mesoscale has initialization gate', has('lib/MesoscaleField.lua','function M.ready() return serial>0 end'))
check('mesoscale advects with shared wind', has('lib/MesoscaleField.lua',"pcall(V.require,'WindEngine')",'advectX=advectX+windX*speed*dt','advectZ=advectZ+windZ*speed*dt'))
check('mesoscale forecast follows future advection', has('lib/MesoscaleField.lua','function M.forecastAt','windX*lastSpeed*seconds','windZ*lastSpeed*seconds'))
check('runtime orders mesoscale between world and micro climate', has('lib/EngineRuntime.lua','"world_climate",25','"mesoscale_field",27','"microclimate",30'))
check('microclimate consumes local mesoscale state', has('lib/EngineRuntime.lua','local base=MF and MF.peek and MF.peek()'))
check('cloud lattice consumes mesoscale samples', has('lib/CloudField.lua','MF.sampleInto','mesoScratch','localClimate.cloud'))
check('3D volume consumes mesoscale samples', has('lib/VolumetricWeather.lua','MF.sampleInto','localClimate.precip','localClimate.storm'))
check('strict cinematic cloud lattice consumes mesoscale cloud occupancy', has('lib/voxel_atmos/CinematicAtmos.lua','MesoscaleField','spatialCloudRatio','persistent world cell contains cloud'))
check('manual established storm deck remains sealed', has('lib/voxel_atmos/CinematicAtmos.lua','weather._transitionActive == true','weather.coverage) or 0) < .95'))
check('near physical precipitation follows local band', has('lib/voxel_atmos/WorldPrecip.lua','localScale','rainI,snowI,hailI=rainI*localScale'))
check('2D precipitation follows player-local band', has('lib/Draw.lua','spatialChannelsScratch','out.rain=','out.snow=','out.hail='))
check('lightning rate follows local storm band', has('lib/Draw.lua','strikeRate=(tonumber(strikeRate) or 0)*tonumber(ms.stormScale)'))
check('rain acoustics follow local precipitation and flat-world shelter', has('lib/AcousticModel.lua','local precip=clamp','local shelter=clamp','local canopy=clamp','local outdoorRain=clamp','precip*.84','target.rainGain=outdoorRain*(1-shelter*.52)*(1-canopy*.10)','target.rainGain=target.rainGain*.58'))
check('far rain/hail/ash reconstruct moving bands on GPU', has('lib/ProceduralPrecipField.lua','fieldPatchWind','fieldFrontScale','float wave=','fieldPatchiness'))
check('far snow reconstructs moving bands on GPU', has('lib/ProceduralSnowField.lua','fieldPatchWind','fieldFrontScale','float wave=','fieldPatchiness'))
check('GPU spatialization adds no per-instance climate upload', 'MesoscaleField' not in (ROOT/'lib/InstanceSeedBuffer.lua').read_text(encoding='utf-8',errors='replace'))
check('authored fog uses local mesoscale pooling', has('lib/voxel_atmos/CinematicAtmos.lua','CinematicAtmos._mistPolicy(authoredFog,fogScale)','fogScale'))
check('weather without authored fog still cannot manufacture mist', has('lib/voxel_atmos/CinematicAtmos.lua','function CinematicAtmos._mistPolicy','if f<=0.02 then return 0,false end'))
check('forecast engine overlays moving mesoscale band', has('lib/ForecastEngine.lua','M.forecastAt','o.precip=clamp','o.mesoscale=true'))
check('public SDK exposes mesoscale read-only state', has('lib/EnvironmentSDK.lua',"mesoscale='MesoscaleField'"))
check('public mod export exposes mesoscale query', has('main.lua','mod.exports.mesoscaleWeather'))
check('debug HUD exposes mesoscale state', has('lib/DebugHUD.lua','meso:p%.2f c%.2f b%.2f'))
check('executable mesoscale regression ships', (ROOT/'tests/mesoscale_weather_test.lua').exists())

failed=[n for n,v in checks if not v]
print(f'8.0.8 mesoscale gate: {len(checks)-len(failed)} passed, {len(failed)} failed')
if failed:
    for n in failed: print(' -',n)
    sys.exit(1)
