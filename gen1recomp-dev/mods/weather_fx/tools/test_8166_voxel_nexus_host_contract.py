#!/usr/bin/env python3
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
host=Path(sys.argv[1]) if len(sys.argv)>1 else None
checks=[]
def ck(v,msg): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+msg)
if not host or not host.exists():
    print('FAIL exact Voxel Nexus host root argument missing');sys.exit(1)
v3=(host/'lib/Voxel3D.lua').read_text()
vs=(host/'lib/VoxelScene.lua').read_text()
cm=(host/'lib/ChunkMesher.lua').read_text()
st=(host/'lib/Structures.lua').read_text()
api=(host/'lib/VoxelCompanionAPI.lua').read_text()
real=(host/'lib/realistic/main.lua').read_text()
ck('function Voxel3D.draw(mesh, texture, model, pull, sunModel)' in v3,'exact host Voxel3D.draw seam signature')
ck('function Voxel3D.beginWater(paint)' in v3 and 'return held.mirror, held.depth' in v3 and 'function Voxel3D.endWater()' in v3,'exact host exposes readable depth with paired beginWater/endWater')
ck('function Voxel3D.size()' in v3 and 'return canvasW, canvasH' in v3,'exact host exposes bound canvas physical pixel size')
terrain='Voxel3D.draw(terrain, atlasFor(state.map), nil)'
phase='pcall(companion.render, companion, "opaque_after_terrain", state)'
water='VoxelScene.drawWater(waterDraws, function()'
ck(terrain in vs and phase in vs and water in vs and vs.index(terrain)<vs.index(phase)<vs.index(water),'opaque companion phase is after terrain/trees and before water')
ck('for _, st in ipairs(S.roundStamps or {}) do' in cm and 'for _, q in ipairs(st.quads) do' in cm,'ChunkMesher submits Structures.roundStamps quads to real terrain mesh')
ck('function Structures.forMap(map)' in st and 'roundStamps = {}' in st and 'S.roundStamps[#S.roundStamps + 1]' in st,'Structures.forMap publishes exact reusable round/tree hull stamps')
ck('if a.priority ~= b.priority then return a.priority < b.priority end' in api,'companion render order is ascending priority')
ck('id="realistic_flora.world"' in real and 'priority=50' in real,'Voxel Nexus cinematic vegetation owns priority 50')
paint=(root/'lib/SnowSurfacePaint.lua').read_text()
ck('priority=99990' in paint,'Weather FX snow depth repaint runs after cinematic vegetation')
ck('Voxel3D.beginWater' in paint and 'Voxel3D.endWater' in paint and 'depthTex' in paint and 'invVP' in paint,'Weather FX cinematic-tree repaint uses exact host readable-depth reconstruction')
ck('C.peek' in paint and 'a==mesh' in paint,'Weather FX stock terrain repaint admits only exact cached host terrain mesh identity')
failed=len(checks)-sum(checks)
print(f'8.1.66 exact Voxel Nexus 2.0.17 host contract: {sum(checks)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
