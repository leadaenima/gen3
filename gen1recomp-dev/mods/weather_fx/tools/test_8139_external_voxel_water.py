#!/usr/bin/env python3
"""8.1.39 exact-host VOID-water bridge check.
Usage: test_8139_external_voxel_water.py <voxel_host_root>
The host root may be Battle Art / Voxel Nexus or another Dramatic-lineage tree.
"""
from pathlib import Path
import re,sys
if len(sys.argv)!=2:
    print('usage: test_8139_external_voxel_water.py <voxel_host_root>');sys.exit(2)
v=Path(sys.argv[1]);r=Path(__file__).resolve().parents[1]
checks=[]
def ck(x,m): checks.append((bool(x),m));print(('PASS ' if x else 'FAIL ')+m)
vs=(v/'lib/VoxelScene.lua').read_text(errors='replace')
da=(r/'lib/DramalessAtmos.lua').read_text();cw=(r/'lib/ConnectedWater.lua').read_text();c3=(r/'lib/voxel_atmos/ConnectedWater3D.lua').read_text()
ck(re.search(r'function\s+VoxelScene\.drawWater\s*\(',vs) is not None,'host exposes shared VoxelScene.drawWater seam')
ck('VoxelScene.drawWater=function(draws,cast,...)' in da,'Weather FX wrapper preserves variadic host water arguments')
ck('publishWaterHostCaps(hostId,hostLib' in da,'host capability publication is installed')
ck('CW.setVoxelWaterHost(caps)' in da,'capabilities reach ConnectedWater authority')
ck('setVoxelWaterHost' in cw and 'outerVoidRange()' in cw and 'voidRingWorld()' in cw,'ConnectedWater consumes host-published void range/ring')
ck('pcall(require,"src.world.Map")' in cw and 'local _Map' not in cw,'outdoor engine module is resolved at call time')
ck('def.environment' in cw and 'def.tileset' in cw,'VOID WATER accepts both Gen2 environment and Gen1 tileset semantics')
ck('drawStandaloneVoid' in c3 and '_voidDraws' in c3,'renderer has no-drawWater fallback isolated to synthetic VOID rows')
wu=v/'lib/WorldUnderlay.lua'
if wu.exists():
    text=wu.read_text(errors='replace');m=re.search(r'local\s+RANGE\s*=\s*(\d+)',text)
    ck(m is not None,'host WorldUnderlay publishes a discoverable range')
    ck('WorldUnderlay' in da and 'U.RANGE' in da,'Weather FX probes optional WorldUnderlay range instead of naming one host')
else:
    ck(True,'host has no WorldUnderlay: universal default-horizon path is applicable')
    ck('outerRange=32768' in da,'universal default-horizon path is present')
passed=sum(x for x,_ in checks);print(f'8.1.39 exact external voxel-water contract: {passed}/{len(checks)} passed');sys.exit(0 if passed==len(checks) else 1)
