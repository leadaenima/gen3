#!/usr/bin/env python3
from pathlib import Path
import re, sys, shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
main=(ROOT/'main.lua').read_text()
bench=(ROOT/'lib/Benchmark.lua').read_text()
atmos=(ROOT/'lib/DramalessAtmos.lua').read_text()
wp=(ROOT/'lib/voxel_atmos/WorldPrecip.lua').read_text()
fail=[]
def ck(v,m):
    if not v: fail.append(m)
ck('local Benchmark = V.require("Benchmark")' in main,'main does not load benchmark module')
ck('Benchmark.beginUpdate()' in main and 'Benchmark.endUpdate(dt)' in main,'benchmark does not bracket live Weather FX update')
ck('Benchmark.preUpdate(dt)' in main and 'Benchmark.enforce()' in main,'benchmark phases do not drive live weather state')
ck('Benchmark.beginPresent()' in main and 'Benchmark.endPresent()' in main,'benchmark does not time Weather FX present work')
ck('weather benchmark [quick|full|status|stop|last]' in main,'benchmark console help/command missing')
runtime=(ROOT/'lib/EngineRuntime.lua').read_text()
ck(('if not(c.benchmarkActive)' in runtime or 'if not c.benchmarkActive' in runtime) and 'modules.Tornado.update(c.dt)' in runtime,'benchmark suppresses tornado gameplay inside staged runtime')
ck('BM.beginAtmos' in atmos and 'BM.endAtmos' in atmos,'voxel 3D atmosphere timing is not wired')
ck('function Atmos.benchmarkStats(out)' in atmos and 'WPmod.liveCounts' in atmos,'live voxel particle telemetry is not exposed')
ck('function WP.liveCounts(out)' in wp,'WorldPrecip lacks zero-allocation benchmark counters')
for phase in ('RAIN_HEAVY','GALE','BLIZZARD','SANDSTORM','FOG','PSYSTORM'):
    ck(('id="%s"'%phase) in bench,f'full benchmark is missing {phase} stress phase')
ck('label="NIGHT / CELESTIAL"' in bench and 'tod="NITE"' in bench,'full benchmark lacks deterministic night/celestial phase')
ck('restoreSnapshot()' in bench and 'TOD.pin=x.todPin' in bench,'benchmark does not restore temporary weather/time state')
ck('State._suppressPersist=true' in bench and 'State._suppressPersist=x.suppressPersist' in bench,
   'benchmark does not suppress/restore WeatherState persistence around synthetic phases')
ws=(ROOT/'lib/WeatherState.lua').read_text()
ck('if State._suppressPersist then return end' in ws,
   'WeatherState persistence does not honor benchmark non-persistent mode')
ck('onePct=lowFps' in bench and 'pointOnePct=lowFps' in bench,'benchmark lacks 1% / 0.1% low metrics')
ck('stutter33' in bench and 'stutter50' in bench and 'stutter100' in bench,'benchmark lacks explicit stutter counters')
ck('getStats' in bench and 'texturememory' in bench and 'drawcalls' in bench,'benchmark lacks GPU/driver telemetry proxies')
ck('collectgarbage("count")' in bench,'benchmark lacks Lua memory telemetry')
ck('peakSnowCells' in bench and 'peakPackFootprints' in bench,'benchmark lacks snow accumulation/footprint telemetry')
ck('Quality.describe()' in bench and 'Settings.presentMode()' in bench,'benchmark does not record active user quality/presentation settings')
ck('Weather FX + Voxel Realism together' in bench,'benchmark warning does not identify combined-mod validity requirement')
# Benchmark must not modify quality budgets or settings as a shortcut.
ck('Quality.TIERS' not in bench and 'maxParticles' not in bench,'benchmark tampers with visual quality/particle budgets')
ck('mod.options:set' not in bench and 'Settings.set(' not in bench,'benchmark persists/modifies player settings')
exe=shutil.which('texlua') or shutil.which('luatex') or shutil.which('lua')
if exe:
    cmd=[exe]
    if Path(exe).name in ('texlua','luatex'): cmd+=['--luaonly']
    cmd+=['tests/benchmark_test.lua']
    r=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True)
    sys.stdout.write(r.stdout);sys.stderr.write(r.stderr)
    ck(r.returncode==0,'benchmark executable regression failed')
else:
    fail.append('no Lua runtime available for benchmark executable proof')
if fail:
    for x in fail: print('FAIL '+x)
    sys.exit(1)
print(f'benchmark integration: {24-len(fail)}/24 passed')
