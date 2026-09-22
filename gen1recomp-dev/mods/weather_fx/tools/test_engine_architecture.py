#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent.parent
checks=[]
def ck(v,n):
    checks.append((bool(v),n))
    if not v: print('FAIL',n)
def txt(p): return (ROOT/p).read_text(encoding='utf-8',errors='replace')
main=txt('main.lua'); rt=txt('lib/EngineRuntime.lua'); rg=txt('lib/RenderGraph.lua')
si=txt('lib/SpatialIndex.lua'); ch=txt('lib/ChunkSim.lua'); env=txt('lib/EnvironmentSurface.lua')
wp=txt('lib/voxel_atmos/WorldPrecip.lua'); npc=txt('lib/voxel_atmos/NpcLightning.lua')
cel=txt('lib/CelestialRenderer2.lua'); at=txt('lib/AtmosphereModel.lua'); ws=txt('lib/WeatherSimulation.lua'); da=txt('lib/DramalessAtmos.lua'); host=txt('lib/HostAdapter.lua')
ck('EngineRuntime.configure' in main and 'EngineRuntime.update' in main,'main is driven by staged engine runtime')
ck('ownership collision' in rg and 'executeStage' in rg,'render graph enforces single-owner stages')
ck('ObjectPool' in si and 'recordPool' in si,'spatial index pools records')
ck('activeRadius' in ch and 'sleepRadius' in ch,'chunk simulation has bounded active/sleep radii')
ck('depositWet' in env and 'depositSnow' in env and 'depositLeaves' in env and 'scorch' in env,'surface engine tracks sparse world state')
ck('EnvironmentSurface' in wp and 'ParticleBatcher' in wp,'3D precipitation feeds surfaces and central GPU batcher')
ck('SpatialIndex' in npc and 'nearRadius' in npc,'NPC lightning uses spatial near-player targeting')
ck('CelestialRenderer2' in main and 'function C.drawProjected' in cel and 'CR2.drawProjected' in da,'strict-3D celestial background has one renderer owner')
ck('AtmosphereModel' in main and 'function Atmosphere.applyBands' in at,'sky pipeline consumes atmosphere model')
ck('pressure' in ws and 'humidity' in ws and 'temperature' in ws and 'storm' in ws,'weather sim exposes continuous meteorological state')
ck('host_adapter' in rt and ('H.refresh()' in rt or 'HostAdapter.refresh()' in rt) and 'instancing' in host,'host capabilities refresh through staged runtime')
failed=sum(not ok for ok,_ in checks)
print(f'engine architecture static gate: {len(checks)-failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
