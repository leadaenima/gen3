#!/usr/bin/env python3
from pathlib import Path
import json,re,sys,hashlib
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.52','manifest 8.1.52')
ck((R/'BASELINE').read_text().strip()=='8.1.52','BASELINE 8.1.52')
ck(not (R/'texluac.out').exists(),'no texluac.out compiler artifact')
for f in [
 'RELEASE-NOTES-8.1.52.md','WEATHER-FX-8.1.52-FINAL-AUDIT.md','tools/test_8152_front_realism.py','tools/test_8152_performance_contract.py',
 'tools/test_8152_runtime_delta.py','tools/test_8152_runtime_freeze.py','tools/test_8152_package_surface.py',
 'tests/front_entity_realism_8152_test.lua','tests/front_audio_motion_cloud_8152_test.lua','tests/weather_authority_8152_test.lua',
 'tools/baselines/8.1.51-runtime-sha256.json','tools/baselines/8.1.52-runtime-sha256.json',
 'tests/distant_front_instancing_8151_test.lua','tests/front_precip_continuity_8150_test.lua']:
    ck((R/f).exists(),f+' present')
# Current semantics.
h=(R/'lib/HostAdapter.lua').read_text();sc=(R/'lib/StormCells.lua').read_text();dw=(R/'lib/DistantWeather.lua').read_text();au=(R/'lib/Audio.lua').read_text();ca=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();ws=(R/'lib/WeatherState.lua').read_text();st=(R/'lib/Settings.lua').read_text();cf=(R/'lib/Config.lua').read_text()
ck('trajectoryLocked=true' in sc and 'maxShift=dt*' not in sc,'front entity no-homing model present')
ck(h.find('local Scene=safeRequire("Scene")') < h.find('if v and v.focus then'),'player position precedes camera-focus fallback')
ck('RAIN_HEARING_RANGE=2400' in dw and 'local spatial=(edge<=0) and 1' in dw,'physical front rain-audio falloff present')
ck('wantGain = (bed.gain or 0.6) * frontGain' in au,'front distance reaches audio mixer')
ck('weather.gate=lerp(1.01,authoredGate,spatialCloudU)' in ca,'finite storm cloud lattice uses continuous occupancy gate')
ck(ca.count('D.motionTime and tonumber(D.motionTime())')>=2,'both distant precipitation paths use monotonic front time')
ck('State.mode = \"FRONT\"' in ws and 'rung == \"CYCLE\" and not frontsOn' in ws,'front authority suspends CYCLE instead of advancing underneath')
ck('disableFrontsForManualWeather' in st and 'persistDependentOption(\"fronts\",\"off\")' in st,'named weather turns fronts off through the live settings path')
ck('manualWeatherSelected' in cf and 'data.fronts.enabled=false' in cf,'Config defensively enforces manual-weather front exclusion')
ck('minRetainedGain' in au and 'math.max(retained' in au,'indoor weather audio keeps the 40% retained floor')
# Preserve core 8.1.51 performance/runtime pieces not in the 8.1.52 repair.
b51=json.loads((R/'tools/baselines/8.1.51-runtime-sha256.json').read_text())['files']
for rel in ['lib/DistantFrontPrecip.lua','lib/Quality.lua','lib/voxel_atmos/WorldPrecip.lua','lib/voxel_atmos/ConnectedWater3D.lua']:
    p=R/rel;exp=b51[rel];ck(hashlib.sha256(p.read_bytes()).hexdigest()==exp['sha256'] and p.stat().st_size==exp['size'],rel+' byte-identical to 8.1.51')
print(f'8.1.52 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
