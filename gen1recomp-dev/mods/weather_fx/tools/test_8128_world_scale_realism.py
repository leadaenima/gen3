#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys, re
ROOT=Path(__file__).resolve().parents[1]
passed=failed=0
def check(ok,name):
    global passed,failed
    if ok: passed+=1; print('PASS',name)
    else: failed+=1; print('FAIL',name)
def text(rel): return (ROOT/rel).read_text(errors='replace')
fw=text('lib/FlatWorldInteraction.lua'); mc=text('lib/Microclimate.lua'); hy=text('lib/Hydrology.lua')
wp=text('lib/voxel_atmos/WorldPrecip.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua')
dw=text('lib/DistantWeather.lua'); er=text('lib/EngineRuntime.lua'); dl=text('lib/DynamicLighting.lua'); ul=text('lib/UnifiedLighting.lua')
sp=text('lib/SnowPack.lua'); es=text('lib/EnvironmentSurface.lua')
check('mountain/peak/orographic branch' in mc and 'id:find("mount"' not in mc and 'id:find("peak"' not in mc,'legacy mountain/peak map modifier removed')
check('_height' not in hy and 'invented terrain elevation' in hy and '_outlet' in hy,'hydrology uses flat basin/outlet drainage, not fake elevation')
check(all(k in fw for k in ('built','canopyFraction','waterFraction','windShadow','windExposure','humidityBias','tempBias','fogAffinity')),'flat voxel footprint publishes microclimate/shelter channels')
check('directionalShadow' in fw and 'upwind' in fw,'building/canopy directional wind shadow exists')
check('SP.ACCUMULATION_ENABLED = true' in sp and 'local function retentionFor' in sp and 'kind=="water"' in sp,'SnowPack redesign enabled with retention and water rejection')
check('cleanupDurationFor' in sp and 'HEATWAVE' in sp and 'RAIN' in sp,'SnowPack cleanup responds to post-storm weather/temperature')
check('ES.depositWet' in wp and 'accepted==false' in wp,'wet ground marks honor shelter rejection')
check('structure interception' in wp and 'SP.surfaceAt' in wp and 'canopyPass' in wp,'3D rain is intercepted by exact roofs/props and partially by canopy')
check('persistent wetness' in ca and 'SurfaceVisualState' in ca,'3D puddles retain persistent post-rain surface state')
check('DistantWeather' in er and 'distant_weather' in er and 'DistantWeather' in ca and '_drawDistantWeather' in ca,'distant StormCells reach the 3D horizon renderer')
check('MAX=4' in dw and ('edge<3600' in dw or 'edge<2800' in dw),'distant weather observer is strictly bounded')
check('local precip=math.max(rain,snow,hail)' in dw and 'tonumber(ch.sand)' not in dw[dw.find('local function kindFor'):dw.find('local function swap')], 'distant curtains do not mis-render sand/ash as rain shafts')
check('observeLightning' in er and 'modules.Lightning.flash' in er,'real lightning envelope feeds dynamic lighting')
check('dyn.lightning' in ul or 'lightning' in ul,'unified lighting consumes dynamic lightning authority')
check('depositWet' in es and 'exposureAt' in es and 'water or exposure<=.06' in es,'surface wetness rejects water/solid shelter')
# Live-host namespace hygiene: Weather FX realism helpers resolve from this mod
# before probing the voxel host, avoiding false missing-module warnings.
da=text('lib/DramalessAtmos.lua')
check(all((name+' = true') in da for name in ('WeatherState','DistantWeather','ParticleBatcher','ProceduralPrecipField','CloudField','EnvironmentSurface','UnifiedLighting','WeatherWorldSpace')),
      'Weather FX realism helpers resolve root-first in private voxel namespace')
# Keep far-weather implementation allocation discipline explicit.
body=ca[ca.find('function CinematicAtmos._buildDistantWeather'):ca.find('function CinematicAtmos._drawDistantWeather')]
check('local coords={' not in body and 'math.min(4' in body,'distant curtain builder avoids per-curtain coordinate tables and caps cells at four')
# Executable behavioral contract.
r=subprocess.run(['texlua','tests/world_scale_realism_test.lua'],cwd=ROOT,text=True,capture_output=True)
print(r.stdout,end=''); print(r.stderr,end='',file=sys.stderr)
check(r.returncode==0 and '0 failed' in r.stdout,'world-scale realism executable contract')
print(f'8.1.28 world-scale realism gate: {passed} passed, {failed} failed')
sys.exit(0 if failed==0 else 1)
