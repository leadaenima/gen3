#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,n):
    checks.append((bool(v),n))
    if not v: print('FAIL',n)
def t(p): return (R/p).read_text(encoding='utf-8',errors='replace')
rt=t('lib/EngineRuntime.lua'); rg=t('lib/RenderGraph.lua'); q=t('lib/Quality.lua'); ca=t('lib/voxel_atmos/CinematicAtmos.lua'); main=t('main.lua')
env=t('lib/EnvironmentSurface.lua'); audio=t('lib/Audio.lua'); si=t('lib/SpatialIndex.lua')
for p in ['PerformanceGovernor','Microclimate','CloudField','MaterialSystem','AcousticModel','EnvironmentalEvents','EnvironmentBehavior','EngineHealth']:
    ck((R/'lib'/f'{p}.lua').is_file(),f'{p} runtime module present')
ck('"budget","world","climate"' in rt and 'performance_governor' in rt,'runtime begins with explicit performance budget stage')
ck(('interval(.10)' in rt or 'routedInterval(.10' in rt) and ('interval(.25)' in rt or 'routedInterval(.25' in rt) and 'pass.accumulator' in rg,'slow simulation uses multi-rate scheduling')
ck('PerformanceGovernor' in q and 'perfScale' in q,'quality particle/world ceilings consume AUTO performance scale')
ck('performanceScale()' in ca and 'weather.puffs' in ca,'3D atmosphere/cloud density consumes adaptive performance scale')
ck('puddle' in env and 'mud' in env and 'frost' in env and '__packed' in env,'surface engine tracks derived states and compacts sleeping chunks')
ck('acousticGain("rain")' in audio and 'acousticGain("wind")' in audio and 'acousticGain("thunder")' in audio,'rain/wind/thunder consume environmental acoustic model')
ck('function SpatialIndex:remove' in si and 'function SpatialIndex:update' in si and 'queryAABB' in si,'spatial index supports mutable world actors')
ck('mod.exports.environment' in main and 'mod.exports.onEnvironmentEvent' in main and 'mod.exports.performance' in main,'public read-only environment/performance/event API exported')
ck('mod.exports.environmentBehavior' in main and 'mod.exports.engineHealth' in main,'public behavior-hint and engine-health APIs exported')
failed=sum(not a for a,_ in checks)
print(f'environment engine 2 static gate: {len(checks)-failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
