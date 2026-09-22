#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
h=(R/'lib/HostAdapter.lua').read_text();e=(R/'lib/EngineRuntime.lua').read_text();s=(R/'lib/StormCells.lua').read_text();d=(R/'lib/DistantWeather.lua').read_text();a=(R/'lib/Audio.lua').read_text();c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();p=(R/'lib/DistantFrontPrecip.lua').read_text();dr=(R/'lib/DramalessAtmos.lua').read_text()
ck(h.find('local Scene=safeRequire("Scene")') < h.find('if v and v.focus then'), 'player Scene position precedes camera-focus fallback')
ck('targetX=x,targetZ=z,reachedTarget=false,trajectoryLocked=true' in s and 'maxShift=dt*' not in s, 'front target is one-time spawn snapshot with no pursuit shifter')
ck('c.x=c.x+c.vx*c.speed*dt;c.z=c.z+c.vz*c.speed*dt' in s and 'target=clamp((.90+ws*2.20)' not in s, 'front uses constant spawn-owned world translation')
ck('end,"distant_weather",false,nil,8)' in e, 'distant front descriptors refresh every frame rather than 0.18s steps')
ck('q.bankX=q.x+vx*rx' in d and 'q.bankZ=q.z+vz*rx' in d, 'remote bank anchor is physical leading edge')
ck('local spatial=(edge<=0) and 1' in d and 'edge/RAIN_HEARING_RANGE' in d, 'front audio is full inside and distance-fades only outside')
ck('frontOwnsRain' in a and 'wantGain = (bed.gain or 0.6) * frontGain' in a, 'audio mixer consumes physical front distance instead of local eased rain only')
ck('weatherFxSpatialLocalized = state and state.pinnedBy == "front"' in dr, 'manual weather is distinguished from finite front cloud ownership')
ck('weather.gate=lerp(1.01,authoredGate,spatialCloudU)' in c and 'weather.softGate=max(tonumber(weather.softGate) or 0,.10)' in c, 'local storm deck fills/parts through continuous persistent-cell gate')
ck('local rowsN=2' in c and 'local growU=smoothstepLua(0,.30,lifeU)' in c and 'local partU=smoothstepLua(.72,1.0,lifeU)' in c, 'front cloud topology stays fixed while formation/parting are continuous')
ck('tostring(stage)..":"..tostring(columns)' not in c, 'cloud descriptor identity no longer changes at lifecycle stage boundary')
ck(c.count('D.motionTime and tonumber(D.motionTime())')>=2, 'both instanced and CPU remote precipitation use monotonic front time')
ck('center.y=frontTop-travel' in p and 'float travel=mod(frontTime*fall+d*height,height);' in p, 'GPU rain gravity is explicitly downward in world Y')
failed=sum(not x for x in checks);print(f'8.1.52 front realism source gate: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
