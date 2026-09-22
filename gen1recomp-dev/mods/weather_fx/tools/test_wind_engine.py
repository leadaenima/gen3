#!/usr/bin/env python3
from pathlib import Path
import shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
fail=[]
def ck(v,m):
    if not v: fail.append(m)
wind=(ROOT/'lib/WindEngine.lua').read_text()
main=(ROOT/'main.lua').read_text()
draw=(ROOT/'lib/Draw.lua').read_text()
wp=(ROOT/'lib/voxel_atmos/WorldPrecip.lua').read_text()
cin=(ROOT/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
au=(ROOT/'lib/Audio.lua').read_text()
ck('function Wind.update' in wind and 'function Wind.state' in wind,'shared WindEngine state/update missing')
for p in ('rain','storm','psychic','snow','blizzard','gale','sand','ash'):
    ck(p in wind,f'weather wind profile missing: {p}')
ck('advectX' in wind and 'advectZ' in wind,'integrated cloud/fog advection missing')
runtime=(ROOT/'lib/EngineRuntime.lua').read_text()
ck('req("WindEngine")' in runtime and 'W.update(c.dt,modules.State)' in runtime and runtime.find('register("environment","wind"') < runtime.find('register("presentation","draw_update"'),'staged runtime ticks WindEngine before presentation')
ck(('WindEngine.screenX(52)' in draw or 'WE.screenX(52)' in draw),'2D precipitation does not consume shared wind')
ck('WE.vector' in wp and 'steerHorizontal' in wp,'3D precipitation does not consume/live-steer from shared wind')
ck('local windX = 0.55 * windS\n  local windZ = 0.25 * windS' not in wp,'legacy fixed WorldPrecip wind vector still authoritative')
ck('frame.windState.advectX' in cin and 'frame.windState.advectZ' in cin,'cloud bank does not use integrated WindEngine displacement')
ck('mistAdvect' in cin and 'vec2 adv = vWorld + mistAdvect;' in cin,'mist still multiplies changing wind by global time')
ck((('WE.peek' in au or 'WE.state' in au) and 'windPitch' in au),'wind audio does not breathe with shared gust engine')
exe=next((shutil.which(x) for x in ('luajit','lua','texlua') if shutil.which(x)),None)
if exe:
    r=subprocess.run([exe,'tests/wind_engine_test.lua'],cwd=ROOT,text=True,capture_output=True)
    sys.stdout.write(r.stdout); sys.stderr.write(r.stderr)
    ck(r.returncode==0,'wind engine executable regression failed')
else:
    fail.append('no Lua runtime available for wind engine proof')
if fail:
    for x in fail: print('FAIL '+x)
    sys.exit(1)
print('PASS weather-driven world WindEngine')
