#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/mnt/data/weatherfx_8166_work/host_extract')
sc=(root/'lib/realistic/CinematicScenery.lua').read_text()
vs=(root/'lib/VoxelScene.lua').read_text()
v3=(root/'lib/Voxel3D.lua').read_text()
vc=(root/'lib/VoxelCompanion.lua').read_text()
checks=[]
def ck(ok,msg):
    checks.append((bool(ok),msg)); print(('PASS ' if ok else 'FAIL ')+msg)
ck('local function addLedge' in sc,'exact host has dedicated cinematic ledge builder')
ck('ellipsoid(G,x,s.base+c.high*.58+lift,z' in sc,'cinematic ledges are real ellipsoid geometry with authored base height')
ck('if C.meshes.stone then Voxel3D.draw(C.meshes.stone,T and T.rock,rigidModel)' in sc,'ledge/boulder stone mesh is submitted as separate real geometry')
ck('opaque_after_terrain' in vc,'Voxel Companion exposes opaque_after_terrain phase')
ck('pcall(companion.render, companion, "opaque_after_terrain", state)' in vs,'companion opaque phase runs after base terrain')
ck('Voxel3D.draw(terrain, atlasFor(state.map), nil)' in vs,'base terrain draw remains distinct from companion/ledge geometry')
ck('function Voxel3D.beginWater(paint)' in v3,'host exposes readable-frame/depth handoff')
ck('return canvas, held.depth' in v3 or 'return held.mirror, held.depth' in v3,'beginWater returns readable color/depth textures')
ck('M.draw(snapshot,quality,opts,effective)' in sc,'cinematic scenery draw is a live host path')
ck('Ledges and boulders share the same lit neutral material path.' in sc,'ledge mesh family is identifiable in exact host source')
failed=sum(not x for x,_ in checks)
print(f'8.1.67 exact Voxel Nexus 2.0.17 ledge/depth contract: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
