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
ver=tuple(int(x) for x in str(m.get('version','0.0.0')).split('.')[:3]); ck(ver >= (8,1,13),'manifest preserves 8.1.13+ lineage')
b=tuple(int(x) for x in (R/'BASELINE').read_text().strip().split('.')[:3]); ck(b >= (8,1,13),'baseline preserves 8.1.13+ lineage')
S=txt('lib/Settings.lua'); W=txt('lib/WeatherState.lua'); A=txt('lib/Audio.lua')
C=txt('lib/voxel_atmos/CinematicAtmos.lua'); D=txt('lib/DramalessAtmos.lua'); T=txt('lib/Tornado.lua')
CS=txt('lib/CelestialSim.lua'); SN=txt('lib/ProceduralSnowField.lua'); WP=txt('lib/voxel_atmos/WorldPrecip.lua')
PF=txt('lib/ProceduralPrecipField.lua'); NL=txt('lib/voxel_atmos/NpcLightning.lua')
CONST=txt('lib/Constellations.lua'); NS=txt('lib/NightSky.lua')
ck('{ { "OFF", "off" }, { "AUTO", "auto" }, { "CYCLE", "cycle" } }' in S,'weather menu separates OFF/AUTO/CYCLE')
ck('if lo == "off" then return 0 end' in S and 'if lo == "auto" then return 1 end' in S and 'if lo == "cycle" then return 2 end' in S,'weather menu maps OFF/AUTO/CYCLE to distinct ladder levels')
ck('Settings.weatherDisabled() then level = 0' in W,'WeatherState hard-disables channels for WEATHER OFF')
ck('hardWeatherOff' in A and 'Audio.stopAllBeds()' in A and 'Lightning.reset' in A,'WEATHER OFF stops weather beds, thunder queues and lightning audio state')
ck('S.weatherDisabled and S.weatherDisabled() then return nil' in C,'WEATHER OFF rejects 3D atmosphere frame')
ck('NL.clearEffects' in D,'WEATHER OFF clears lingering NPC lightning overlay effects')
ck('WS.level~=nil' in T and '(tonumber(WS.level) or 0)<=0' in T and 'weatherDisabled' in T,'WEATHER OFF cannot keep stale GALE tornado authority without treating missing legacy level as OFF')
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
ck('FLASH_SECONDS, FLASH_STEP = 0.72, 0.060' in NL,'NPC skeleton flash phases remain visible for multiple normal render frames')
ck('w*.17' in NL and 'w*.050' in NL and 'w*.038' in NL and '{x,y,z,1.0,1.0,1.0,a}' in NL,'NPC x-ray skeleton uses thick high-contrast bone geometry')
ck('V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp);V.safeCall(sh.send,sh,"vp",Voxel3D.vp)' in NL,'NPC skeleton supports both voxel-host VP matrix upload forms')
ck((('for j=0,4 do' in NL and 'local half=.80+1.05*t' in NL and 'age>=0' in NL) or ('for j=0,5 do' in NL and 'local half=1.35+1.75*t' in NL and 'age>=SMOKE_DELAY' in NL and 'pushSmokeQuad' in NL)), 'NPC smoke retains visible multi-puff post-strike presentation')
ck('POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in CONST and CONST.count('atlasExact=true')==14,'all 14 added constellations come from the approved atlas trace')
ck('c4463a5a51b23cc400e1a99721006d567b48877bf17625cc28845e0826e14dc4' in CONST,'approved constellation atlas source hash is pinned')
ck('primary and 1.52 or .92' in CONST and ('primary and 1.00 or .82' in CONST or 'a=primary and 1.00 or .84' in CONST or 'a=primary and .96 or .73' in CONST),'atlas constellations retain approved strong line and landmark-star visibility')
ck(('globalVis^1.18' in NS or 'globalVis^1.08' in NS) and 'constellationVisibility' in NS,'constellation visibility is strengthened while preserving zero/cloud fade')
ck('s.atlasExact and math.max(.52' in CONST and 'cs.atlasExact and math.max(.90' in NS,'atlas trace samples use overlapping luminous sizing so silhouettes read continuously')
print(f'8.1.13 visual/runtime contract: {P} passed, {F} failed')
sys.exit(1 if F else 0)
