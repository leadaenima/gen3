#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
er=(R/'lib/EngineRuntime.lua').read_text(); fw=(R/'lib/FlatWorldInteraction.lua').read_text(); vw=(R/'lib/VolumetricWeather.lua').read_text(); lp=(R/'lib/LightProbeGrid.lua').read_text(); ws=(R/'lib/WorldStreamer.lua').read_text(); gw=(R/'lib/GPUWeatherEngine.lua').read_text(); sv=(R/'lib/SurfaceVisuals.lua').read_text()
for name in ('world_streamer','light_probe_grid','gpu_weather','surface_visuals'):
    ck(f'"{name}"' not in er, f'{name} no longer registered as continuous pass')
ck('if not Governor.auto() then return end' in er and 'PredictiveBudget is consumed only by AUTO' in er,'predictive budget sleeps under manual QUALITY')
ck('Targeted routing is another AUTO-only controller' in er and er.count('if not Governor.auto() then return end')>=2,'workload router sleeps under manual QUALITY')
ck('sampleCache' in fw and 'staticProfile' in fw and 'directionalShadow' in fw,'flat-world static footprint cache retains live directional shelter')
ck('sampleCache[r] = nil' in fw,'flat-world cache invalidates with voxel region cache')
ck('materializedCells=0' in vw and 'wantCells=false' in vw and 'function W.cells()' in vw,'volumetric 75-cell table is lazy')
ck('state.cloudVolume=sumC' in vw and 'state.lightTransmission=clamp(math.exp(-state.cloudVolume*1.35)' in vw,'renderer-facing volumetric aggregate equations retained')
ck('cells=0,virtualCells=49' in lp and 'analytic-on-demand' in lp,'light probes have zero resident grid and on-demand compatibility')
ck('function S.peek() return refresh() end' in ws and 'function S.sample()' in ws,'WorldStreamer compatibility API remains on-demand')
ck('function G.peek() return refresh() end' in gw and "backend='fallback'" in gw,'GPUWeatherEngine compatibility budget remains on-demand')
ck('function S.peek() return refresh() end' in sv and 'SurfaceVisualState' in sv,'SurfaceVisuals compatibility summary remains on-demand')
failed=sum(not x for x,_ in checks); print(f'8.1.47 flat-voxel prune source contract: {len(checks)-failed}/{len(checks)} passed'); sys.exit(1 if failed else 0)
