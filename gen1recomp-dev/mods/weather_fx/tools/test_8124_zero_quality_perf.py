#!/usr/bin/env python3
from pathlib import Path
import re,sys,json
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(cond,msg): checks.append((bool(cond),msg)); print(('PASS ' if cond else 'FAIL ')+msg)
def text(p): return (R/p).read_text()
wc=text('lib/WorldClimate.lua'); wf=text('lib/WindFlow.lua'); hy=text('lib/Hydrology.lua'); lp=text('lib/LightProbeGrid.lua'); cf=text('lib/CloudField.lua'); sc=text('lib/StormCells.lua'); er=text('lib/EngineRuntime.lua'); ws=text('lib/WeatherState.lua'); mf=text('lib/MesoscaleField.lua'); ns=text('lib/NightSky.lua'); co=text('lib/Constellations.lua'); ca=text('lib/voxel_atmos/CinematicAtmos.lua')
# Frozen quality/population contracts remain separately tested, but assert the core world-field footprints here too.
ck('local RADIUS=5' in wc and 'local MAX_CELLS=256' in wc,'WorldClimate 11x11 footprint and 256-cell ceiling unchanged')
ck('local CELL=64; local R=4' in wf,'WindFlow 9x9 footprint unchanged')
ck('local CELL=64; local R=4' in hy,'Hydrology 9x9 footprint unchanged')
ck(('local L={}; local CELL,R=96,3' in lp) or ('virtualCells=49' in lp and 'cells=0' in lp),'LightProbeGrid preserves 7x7 logical footprint while allowing 8.1.47 zero-resident virtualization')
ck('local RADIUS=3' in cf,'CloudField 7x7 footprint unchanged')
ck('local MAX_CELLS=6' in sc,'finite StormCell count unchanged')
ck('lod.starStep,lod.maxPlanets,lod.twinkle,lod.meteors=1,#PLANETS,true,true' in ns,'full star/planet catalogue retained on every quality tier')
ck('RAIN_MAX' in text('lib/voxel_atmos/WorldPrecip.lua'),'WorldPrecip population authority retained')
# Exact-math/zero-allocation improvements.
ck('local targetScratch={}' in wc and 'targetForInto' in wc,'WorldClimate reuses target scratch')
ck(wc.count('math.exp(') <= 12,'WorldClimate smoothing exponentials hoisted out of cell loop')
ck('_n=n,_n2=n2' in wf and '_drag=false,_cs=1,_sn=0,_amp=1' in wf,'WindFlow caches deterministic cell coefficients')
ck('_basin=1-hash(cx,cz,4)' in hy and '_outlet=.30+.70*hash(cx,cz,7)' in hy and '_height' not in hy,'Hydrology caches static flat basin/outlet drainage')
ck((('_ambientOccl=.86+.14*hash(cx,cz)' in lp and '_diffuseOccl=.90+.1*hash(cx+9,cz-3)' in lp) or ('.86+.14*hash(cx,cz)' in lp and '.90+.10*hash(cx+9,cz-3)' in lp)),'LightProbeGrid preserves deterministic occlusion formula')
ck('_chargeNoise=.60+.40*hash(cx,cz,7)' in cf,'CloudField caches static charge noise')
ck('refreshLife(c)' in sc and '_lifeAmp' in sc and '_lifeRadius' in sc,'StormCells caches lifecycle coefficients')
ck('_worldClimateFrame' in er and 'worldClimateAt(c)' in er,'EngineRuntime shares one center-climate reference per frame')
ck(er.count('refreshSurface(c)') <= 3,'redundant presentation surface resample removed')
ck('local CONTROL_KEYS=' in ws and 'local FAMILY_SCALE=' in ws,'WeatherState reuses frame-constant lookup/scratch structures')
ck('local windMul=Settings.windIntensity' in ws,'WeatherState reads wind setting once per update')
ck('local rainMul=Settings.rainIntensity' in ws and 'local snowMul=Settings.snowIntensity' in ws,'WeatherState reads precipitation multipliers once per update')
ck('local Types=V.require("Types")' in mf and 'pcall(V.require,"Types")' not in mf,'Mesoscale sample hot path has no protected Types lookup')
ck('PLANET_DISC_CACHE' in ns and 'planetDiscTemplate' in ns,'planet surface topology/color cached')
ck('SATURN_RING_TEMPLATE' in ns and 'X_RING_TEMPLATES' in ns,'world ring topology cached')
ck('MILKY_WAY_POINTS' in ns,'Milky Way base coordinates cached')
ck('SCREEN_RING_ARCS' in ns,'projected ring arc square roots cached')
ck('_wxStaticHalf' in co,'constellation static billboard size cached')
ck('constVis, nil, NightSky.twinkleAlpha' in ns,'constellation world pass removes redundant per-star fade dispatch')
ck('_bodyCa' in ca and '_bodySa' in ca and '_bodySx' in ca and '_bodySz' in ca,'cloud occlusion descriptor trig/spans cached')
# Explicitly reject common quality-cut shortcuts in this optimization revision.
for needle,msg in [
 ('starStep=2','no new star catalogue skipping'),('maxPlanets=5','no planet-count reduction'),('RADIUS=2','no CloudField radius reduction'),
 ('MAX_CELLS=4','no StormCell-count reduction')]:
    ck(needle not in (ns+cf+sc),msg)
fail=[m for ok,m in checks if not ok]
print(f'8.1.24 zero-quality performance contract: {len(checks)-len(fail)}/{len(checks)} passed')
sys.exit(1 if fail else 0)
