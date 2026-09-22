#!/usr/bin/env python3
from pathlib import Path
import json, sys
R=Path(__file__).resolve().parents[1]
P=F=0
def ck(v,m):
 global P,F
 if v: P+=1
 else: F+=1; print('FAIL '+m)
def txt(x): return (R/x).read_text(errors='replace')
m=json.loads(txt('manifest.json'))
ver=tuple(int(x) for x in str(m.get('version','0.0.0')).split('.')[:3]); ck(ver >= (8,1,12),'manifest preserves 8.1.12+ lineage')
b=tuple(int(x) for x in (R/'BASELINE').read_text().strip().split('.')[:3]); ck(b >= (8,1,12),'baseline preserves 8.1.12+ lineage')
S=txt('lib/Settings.lua'); W=txt('lib/WeatherState.lua'); A=txt('lib/Audio.lua')
C=txt('lib/voxel_atmos/CinematicAtmos.lua'); D=txt('lib/DramalessAtmos.lua'); T=txt('lib/Tornado.lua')
CS=txt('lib/CelestialSim.lua'); SN=txt('lib/ProceduralSnowField.lua'); WP=txt('lib/voxel_atmos/WorldPrecip.lua')
PF=txt('lib/ProceduralPrecipField.lua'); NL=txt('lib/voxel_atmos/NpcLightning.lua')
ck('{ { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } }' in S,'weather menu separates OFF/AUTO/CYCLE')
ck('if lo == "off" then return 0 end' in S and 'if lo == "auto" then return 1 end' in S and 'if lo == "cycle" then return 2 end' in S,'weather menu maps OFF/AUTO/CYCLE to distinct ladder levels')
ck('Settings.weatherDisabled() then level = 0' in W,'WeatherState hard-disables channels for WEATHER OFF')
ck('hardWeatherOff' in A and 'Audio.stopAllBeds()' in A and 'Lightning.reset' in A,'WEATHER OFF stops weather beds, thunder queues and lightning audio state')
ck('S.weatherDisabled and S.weatherDisabled() then return nil' in C,'WEATHER OFF rejects 3D atmosphere frame')
ck('NL.clearEffects' in D,'WEATHER OFF clears lingering NPC lightning overlay effects')
ck('tonumber(WS.level) or 0)<=0' in T and 'return false end' in T,'WEATHER OFF cannot keep stale GALE tornado authority')
ck('moonriseStarVisibility' in CS and 'smooth(0.0,0.25,progress)' in CS,'stars begin at moonrise and reach authored maximum at quarter-night')
ck('afterPeak=1.0-0.28*smooth(0.25,0.82,progress)' in CS,'quarter-night is the unique star-visibility peak')

if ver >= (8,1,55):
 ck('ANCHOR_CELL=256' in SN and 'anchorNextX' in SN and 'submitFixed' in SN and 'anchorFromX' not in SN,'far snow streams between fixed world anchors instead of sliding toward player')
else:
 ck('anchorFromX' in SN and '/0.55' in SN and 'u=u*u*(3-2*u)' in SN,'far snow cell handoff is smoothed instead of hard teleported')
ck('(kind == 1) and 1.02' in WP and '(kind == 1) and 2.2' not in WP,'near hail uses pellet aspect ratio instead of streak aspect ratio')
ck('tiny deterministic cross-wind wander' in PF,'far hail breaks parallel background columns')
ck('weather.coverage=max' in C and 'weather.bank=max' in C,'precipitation guarantees a cloud-bearing weather profile')
ck('V.safeCall(drawParticles' in C and 'V.safeCall(drawClouds' in C,'cloud bank has independent fallback renderer')
ck(('FLASH_SECONDS, FLASH_STEP = 0.52, 0.020' in NL) or ('FLASH_SECONDS, FLASH_STEP = 0.72, 0.060' in NL),'NPC strike preserves rapid readable flash animation')
ck('for j=0,4 do' in NL and 'local half=.80+1.05*t' in NL and 'age>=0' in NL,'NPC smoke starts immediately and uses five larger puffs')
print(f'8.1.12 visual/runtime contract: {P} passed, {F} failed')
sys.exit(1 if F else 0)
