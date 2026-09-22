#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
passed=failed=0
def ck(v,m):
 global passed,failed
 if v: passed+=1
 else: failed+=1; print('FAIL '+m)
def txt(p): return (ROOT/p).read_text(errors='replace')
m=json.loads(txt('manifest.json'))
ck(tuple(map(int,m.get('version','0.0.0').split('.'))) >= (8,1,11),'manifest version retains 8.1.11+ runtime fixes')
ck((ROOT/'BASELINE').read_text().strip()==m.get('version'),'BASELINE matches current manifest version')
RG=txt('lib/RenderGraph.lua'); I=txt('lib/Interop.lua'); H=txt('lib/HostAdapter.lua')
F=txt('lib/Fronts.lua'); G=txt('lib/Pokegear.lua'); W=txt('lib/WeatherState.lua'); T=txt('lib/TimeOfDay.lua')
S=txt('lib/Seasons.lua'); E=txt('lib/EngineRuntime.lua'); D=txt('lib/Draw.lua'); B=txt('lib/Battle.lua'); A=txt('lib/DramalessAtmos.lua'); N=txt('lib/NightSky.lua'); BM=txt('lib/Benchmark.lua')
ck('math.max(interval*2,pass.maxDt or .5)' in RG,'scheduler accumulator cap scales above pass interval')
ck('function Interop.hostLib()' in I,'host library accessor exists')
ck('n.playerWorldX' in H and 'n.playerWorldY' in H,'HostAdapter consumes live Scene world coordinates')
ck('local boundary = (#id == #prefix)' in F,'front route matching is boundary-safe')
ck('local boundary = (#mapId == #prefix)' in G,'Pokegear route marker matching is boundary-safe')
ck('Fronts.sunForbidden' in F and 'Types.get(st.id).sunny' in F,'front sunny-night retirement is live')
ck('softFrom' in W and 'softTo' in W and 'cycleIndex' in W and 'battleCarry' in W,'weather transition/cycle/battle carry are persisted')
ck('State._sessionStart = not hadSavedWeather' in W,'saved AUTO does not first-frame reroll')
ck('State._battleCarry and (State.left or 0) > 0' in W,'battle weather temporarily outranks AUTO/front')
ck('Settings.get("speed") == "test"' not in W and 'math.min(State.softDur, 3.0)' not in W,'legacy TEST transition cap is retired; duration control cannot accelerate visual handoff')
ck('function TOD.persist()' in T and 'function TOD.restore()' in T,'time-of-day persists')
ck('rawElapsed=mod.save:get("todElapsed",nil)' in T and 'resetPersistedClockDefaults()' in T,'clock restore does not leak same-process state into old/new saves')
ck(E.find('register("world","time",10') < E.find('register("world","seasons",20'),'time updates before dependent seasons in world stage')
ck('TOD._cycleOffset' in T and 'changedPeriod' in T,'cycle source/day-length edits rebase continuously')
ck('TOD.gameDaySerial' in S and 'return seasonFromDayOfYear(dayIndex, yearLen), "host"' in S,'seasons follow host game-day authority')
ck('drawOutsideTextBox' in D and 'function Draw.gradeFrame' in D,'flat weather/grade are clipped around dialogue rather than suppressed')
ck('Battle.hostCrystal()' in txt('main.lua') and 'Battle.isGen2()' not in txt('main.lua'),'Gen2 OPTIONS detection calls valid Battle capability')
ck('origPaint(w, h, skyArg, horizonY, cell, nil, ...)' in A,'fallback does not forward legacy host celestial body')
ck('elseif dt > 0.25 then dt = 0.25 end' in N,'night-sky smoothing does not collapse extreme low FPS to 1/60')
ck('if dt<=0 or dt>2.0 then return end' in BM,'benchmark counts sub-2-second catastrophic slow frames')
ck('player_runtime_regression_test.lua' in txt('tools/run_all.py'),'player runtime regression is wired into release runner')
print(f'8.1.11 player-runtime contract: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
