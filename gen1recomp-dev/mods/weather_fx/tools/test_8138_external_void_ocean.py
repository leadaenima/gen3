#!/usr/bin/env python3
"""8.1.38 exact Gen1Recomp + Voxel Nexus outer-water contract.
Usage: test_8138_external_void_ocean.py <gen1_root> <voxel_root>
"""
from pathlib import Path
import re,sys
if len(sys.argv)!=3:
    print('usage: test_8138_external_void_ocean.py <gen1_root> <voxel_root>');sys.exit(2)
g=Path(sys.argv[1]);v=Path(sys.argv[2]);r=Path(__file__).resolve().parents[1]
checks=[]
def ck(x,m): checks.append((bool(x),m));print(('PASS ' if x else 'FAIL ')+m)
tr=(g/'src/render/TileRenderer.lua').read_text(); wu=(v/'lib/WorldUnderlay.lua').read_text(); vs=(v/'lib/VoxelScene.lua').read_text(); water=(v/'lib/Water.lua').read_text()
cw=(r/'lib/ConnectedWater.lua').read_text(); c3=(r/'lib/voxel_atmos/ConnectedWater3D.lua').read_text(); da=(r/'lib/DramalessAtmos.lua').read_text()
ck(re.search(r'local\s+BORDER_BLOCKS\s*=\s*3',tr),'Gen1Recomp finite void apron remains exactly three 32px blocks')
ck('TileRenderer.VOID_FILLS = { "trees", "water", "black" }' in tr,'Gen1Recomp exposes live VOID FILL WATER authority')
ck(re.search(r'local\s+RANGE\s*=\s*32768',wu),'Voxel Nexus 2.0.8 WorldUnderlay radius is exactly 32768')
ck(re.search(r'local\s+HEIGHT\s*=\s*-20',wu),'Voxel Nexus outer cosmetic underlay sits below gameplay water')
ck('WorldUnderlay.draw(state, cx, cy, underlayColor)' in vs and 'VoxelScene.drawWater(waterDraws' in vs,'Voxel Nexus draws underlay before normal reflective water pass')
ck('return vec4(rgb, 1.0) * color' in water,'Voxel Nexus Water shader honors draw alpha for translucent pond surface')
ck('VOID_RING_CELLS=6' in cw and 'OUTER_VOID_RANGE=32768' in cw,'Weather FX bridges exact 96px apron to full 32768 outer sea')
ck('visualOnly=true' in cw and 'outerSea=true' in cw,'outer sea is explicitly visual-only')
ck('holes=holes' in cw and 'innerRing=VOID_RING_WORLD' in cw,'outer sea cuts loaded-map/apron holes instead of covering authored terrain')
ck('dynamicCount=dc' in c3 and 'for i=1,dc do' in c3,'far sea only CPU-displaces bounded near-corridor vertices')
ck('isLivingPond' in c3 and 'pondAlpha' in c3 and 'MAX_POND_FISH=24' in c3,'authored pond translucent/fish renderer is present')
ck('drawPonds' in da and 'outerDraws' in da and 'origWater(ponds' in da,'shared host bridge routes full sea and fail-open pond draw')
passed=sum(x for x,_ in checks);print(f'8.1.38 exact external void-ocean contract: {passed}/{len(checks)} passed');sys.exit(0 if passed==len(checks) else 1)
