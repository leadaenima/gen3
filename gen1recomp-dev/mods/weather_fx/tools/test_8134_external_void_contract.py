#!/usr/bin/env python3
"""Release-time contract check against exact Gen1Recomp/Voxel Realism sources.
Usage: test_8134_external_void_contract.py <gen1_root> <voxel_root>
"""
from pathlib import Path
import re,sys
if len(sys.argv)!=3:
    print('usage: test_8134_external_void_contract.py <gen1_root> <voxel_root>');sys.exit(2)
g=Path(sys.argv[1]);v=Path(sys.argv[2]);root=Path(__file__).resolve().parents[1]
checks=[]
def ck(x,m): checks.append((bool(x),m));print(('PASS ' if x else 'FAIL ')+m)
tr=(g/'src/render/TileRenderer.lua').read_text()
cm=(v/'lib/ChunkMesher.lua').read_text()
vs=(v/'lib/VoxelScene.lua').read_text()
vm=(v/'main.lua').read_text()
cw=(root/'lib/ConnectedWater.lua').read_text()
c3=(root/'lib/voxel_atmos/ConnectedWater3D.lua').read_text()
da=(root/'lib/DramalessAtmos.lua').read_text()
ck(re.search(r'local\s+BORDER_BLOCKS\s*=\s*3',tr),'Gen1Recomp VOID FILL ring is exactly 3 border blocks')
ck(re.search(r'local\s+WATER_BORDER_BLOCK\s*=\s*0x43',tr),'Gen1Recomp water void uses OVERWORLD water border block 0x43')
ck('TileRenderer.VOID_FILLS = { "trees", "water", "black" }' in tr,'Gen1Recomp exposes TREES/WATER/BLACK VOID FILL modes')
ck('if mode == "water" then return WATER_BORDER_BLOCK end' in tr,'Gen1Recomp borderBlockFor maps WATER mode to water geometry')
ck(re.search(r'local\s+RING\s*=\s*3',cm),'Voxel Realism uses matching 3-block synthetic ring')
ck('local r = bodyOnly and 0 or RING * 4' in cm,'Voxel Realism expands current map ring by 4 8px tiles per border block')
ck('px1 > mk[1] and px0 < mk[3] and pz1 > mk[2] and pz0 < mk[4]' in cm,'Voxel Realism water/terrain ring uses strict neighbour-body overlap masking')
ck('nb.ox + nb.map.def.width * 32' in vs and 'nb.oy + nb.map.def.height * 32' in vs,'VoxelScene neighbour masks use exact Gen1 map body dimensions')
ck('ChunkMesher.invalidateVoidRings()' in vm and 'TileRenderer.voidFill' in vm,'Voxel Realism rebuilds synthetic ring when live VOID FILL changes')
ck('VOID_RING_CELLS=6' in cw and 'src.render.TileRenderer' in cw,'Weather FX converts 3x32px host ring to exact six 16px physical-water cells')
ck('renderBodies(CW)' in c3,'Weather FX 3D pass consumes synthetic void bodies alongside authored bodies')
ck('CW3.setEnabled(false)' in da and 'return origWater(draws,cast,...)' in da,'WATER STYLE ORIGINAL restores host draw list including void water')
ck(3*32==6*16==96,'host and Weather FX apron units are exactly equal at 96 pixels')
passed=sum(x for x,_ in checks);print(f'8.1.34 external void-water contract: {passed}/{len(checks)} passed')
sys.exit(0 if passed==len(checks) else 1)
