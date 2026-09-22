#!/usr/bin/env python3
"""Weather FX 8.0.7 natural-transition release gate.

This is intentionally a source/contract test because the release environment
may not provide LuaJIT. Runtime behaviour remains covered by the existing Lua
suites on hosts that do. The checks here make the architecture hard to regress:
manual pins stay immediate, AUTO/front handoffs use staged meteorology, strict
3D consumes the same eased channels as 2D/audio, and WorldPrecip may not refill
an intentional transitional zero from a discrete weather id.
"""
from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[1]
S=(ROOT/'lib/SynopticTransition.lua').read_text(errors='replace')
W=(ROOT/'lib/WeatherState.lua').read_text(errors='replace')
SIM=(ROOT/'lib/WeatherSimulation.lua').read_text(errors='replace')
D=(ROOT/'lib/DramalessAtmos.lua').read_text(errors='replace')
C=(ROOT/'lib/voxel_atmos/CinematicAtmos.lua').read_text(errors='replace')
P=(ROOT/'lib/voxel_atmos/WorldPrecip.lua').read_text(errors='replace')
R=(ROOT/'lib/EngineRuntime.lua').read_text(errors='replace')
WIND=(ROOT/'lib/WindEngine.lua').read_text(errors='replace')
AUDIO=(ROOT/'lib/Audio.lua').read_text(errors='replace')
DRAW=(ROOT/'lib/Draw.lua').read_text(errors='replace')

checks=fails=0
def ck(ok,msg):
    global checks,fails
    checks+=1
    if ok: print('PASS',msg)
    else: fails+=1; print('FAIL',msg)

def curve(kind,field):
    m=re.search(rf'if k=="{re.escape(kind)}" then(.*?)(?:elseif k==|else\n)',S,re.S)
    if not m: return None
    n=re.search(rf'state\.{re.escape(field)}=range\(u,([0-9.]+),([0-9.]+)\)',m.group(1))
    if not n: return None
    return float(n.group(1)),float(n.group(2))

ck((ROOT/'lib/SynopticTransition.lua').is_file(),'synoptic transition planner ships')
ck('local BASE_DURATION' in S and all(k+'=' in S for k in ('onset','clearing','intensify','weaken','phase_change','dry_shift')),
   'planner defines distinct meteorological transition classes')
ck('return math.max(28,d),kind' in S,'natural handoffs have a non-trivial minimum duration')

on_cloud,on_precip,on_storm=curve('onset','cloudU'),curve('onset','precipU'),curve('onset','stormU')
ck(bool(on_cloud and on_precip and on_storm and on_cloud[0] < on_precip[0] < on_storm[0]),
   'onset stages cloud formation before precipitation before lightning/convection')
cl_storm,cl_precip,cl_cloud=curve('clearing','stormU'),curve('clearing','precipU'),curve('clearing','cloudU')
ck(bool(cl_storm and cl_precip and cl_cloud and cl_storm[1] < cl_precip[1] < cl_cloud[1]),
   'clearing kills convection first, then rain, then parts the remaining cloud deck')
int_cloud,int_precip,int_storm=curve('intensify','cloudU'),curve('intensify','precipU'),curve('intensify','stormU')
ck(bool(int_cloud and int_precip and int_storm and int_cloud[0] <= int_precip[0] < int_storm[0]),
   'rain-to-storm intensification builds cloud/wind before late electrical charge')
ck('phaseBlend' in S and 'local cap=math.max(a,b)*1.06' in S,
   'cross-family precipitation transitions overlap without unbounded double-density spikes')

ck('Synoptic.begin' in W and 'State.softDur=tonumber(dur)' in W,
   'AUTO/front handoffs use planner-selected duration')
ck('Synoptic.goal(key,goal,goalB)' in W,
   'WeatherState channels use per-family staged goals')
ck('pcall(Synoptic.goal' not in W,
   'per-channel transition hot path has no new pcall overhead')
ck('local sourceFog=State.isFogWeather(activeId)' in W and 'local targetFog=targetId and State.isFogWeather(targetId)' in W,
   'fog intensity/settings follow both source and target during a natural handoff')
ck('local sandId=(targetId=="SANDSTORM"' in W and 'local dustId=(targetId=="DUSTSTORM"' in W,
   'sand/dust family settings cannot wait for the final id commit and pop in')

hard=re.search(r'local HARD_PIN = \{(.*?)\n  \}',W,re.S)
ck(bool(hard and all(x in hard.group(1) for x in ('config = true','always = true','menu = true','debug = true'))),
   'explicit player/config weather selection remains an immediate pin, not a long natural handoff')
ck('State._manualWeatherResponse = 1.0' in W and 'tau=math.min(tau,0.14)' in W,
   'manual weather gets immediate sky ownership with a short live particle/channel response')

ck('weatherFxChannels = state and state.ch or nil' in D,
   '3D bridge publishes WeatherState channel table by reference (no per-frame copy)')
ck('weatherFxTargetId = state and state.softTo or nil' in D and 'weatherFxTransition = state.synoptic()' in D,
   '3D bridge publishes target id and staged transition state')
ck('WS and WS.peek' in D and 'Atmos._ns.weatherFxMeteo=WS.peek()' in D,
   '3D bridge reuses meteorological state instead of allocating a sample table every frame')

ck('local transitionActive = type(tr)=="table" and tr.active==true' in C,
   'strict 3D recognizes a live synoptic handoff')
ck('CinematicAtmos._blendProfilesInto(CinematicAtmos._transitionProfileScratch,a,b,tonumber(tr.cloudU)' in C,
   'strict 3D cloud deck follows cloud-stage progress through a reused scratch profile')
ck('weather.storm = lerp' in C and 'tr.stormU' in C,
   'strict 3D convective cloud/lightning character follows the later storm stage')
ck('local channelSnapshot = V and V.weatherFxChannels or nil' in C and 'local function resolvedChannel(key)' in C,
   'strict 3D precipitation consumes live eased WeatherState channels')
for fam in ('rain','snow','hail','sand','ash','debris'):
    ck(f'resolvedChannel("{fam}")' in C,f'{fam} has a live strict-3D transition driver')
ck('local function floorProgress(key)' in C and '*floorProgress(' in C,
   'authored 3D visual floors scale with transition progress instead of forcing full-strength onset')
ck('if not transitionActive and (wxId == "" or wxId == "CLEAR"' in C,
   'clearing transitions may keep outgoing precipitation while target sky is already CLEAR')

ck('local resolvedByAtmos = weather._wxChannelsResolved == true' in P,
   'WorldPrecip knows when zero is an intentional live transition value')
ck(re.search(r'if not resolvedByAtmos(?: and def and T\.channel)? then.*?fill\(',P,re.S) is not None,
   'WorldPrecip static Types refill is compatibility-only, not allowed over live channels')

ck('weather.synoptic()' in SIM and 'target.cloud=clamp01(mix(target.cloud,syn.cloudTarget,.82))' in SIM,
   'macro meteorology follows the same staged synoptic state as presentation')
ck("Sim.peek()" in SIM,'meteorological state exposes zero-copy read path')
ck('syncFromWeatherFx(modules.State,modules.Settings)' in R and R.find('syncFromWeatherFx(modules.State,modules.Settings)') < R.find('modules.VoxelAtmos.update(c.dt)'),
   'live transition authority reaches 3D before the 3D update each frame')

ck('local profileId = nil' in WIND and 'state.softTo and state.synoptic' in WIND and 'tr.windU' in WIND,
   'shared world WindEngine adopts target weather character during the staged wind front')
ck('S.advectX = S.advectX +' in WIND and 'S.advectZ = S.advectZ +' in WIND,
   'transition-aware wind keeps integrated advection, so profile changes cannot teleport clouds')
ck('local tr = State.synoptic and State.synoptic() or nil' in DRAW and 'if State.softTo and type(tr)=="table" and tr.active then' in DRAW and 'strikeRate = tonumber(State.ch and State.ch.strike) or 0' in DRAW,
   'root lightning scheduler uses staged live strike rate only for natural handoffs')
ck('strikeRate = (State.channel and State.channel("strike")) or 0' in DRAW,
   'manual/non-transition lightning retains live localized channel authority')
ck('local targetWxId = State.softTo' in AUDIO and 'local bedWxId, bedDef = wxId, current' in AUDIO,
   'rain/storm audio can adopt the incoming family before final id commit')
ck('local liveStrike=tonumber(State.ch and State.ch.strike) or 0' in AUDIO and 'weatherCanThunder = liveStrike > 0.01' in AUDIO,
   'thunder audio follows actual staged electrical activity during natural handoffs')
ck('local ready = (State.softT >= dur)' in W and 'dur * 0.72' not in W,
   'map traversal cannot prematurely skip the final synoptic stages')

# Performance contract for this upgrade: no fluid solver, no new particle pool,
# no per-frame profile allocation. It orchestrates existing bounded engines.
ck('CinematicAtmos._transitionProfileScratch = CinematicAtmos._transitionProfileScratch or {}' in C and 'blendProfilesInto(CinematicAtmos._transitionProfileScratch',
   'cloud profile blending reuses bounded scratch memory')
ck('local state = {' in S and 'local fromM = {}' in S and 'local toM = {}' in S,
   'synoptic planner uses persistent bounded state rather than per-frame simulation grids')

print(f'8.0.7 synoptic transition gate: {checks-fails}/{checks} passed')
sys.exit(1 if fails else 0)
