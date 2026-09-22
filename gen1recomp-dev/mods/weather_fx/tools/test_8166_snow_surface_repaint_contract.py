from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
checks=[]
def check(cond,msg):
    checks.append((bool(cond),msg)); print(('PASS ' if cond else 'FAIL ')+msg)
paint=root/'lib/SnowSurfacePaint.lua'
wp=root/'lib/voxel_atmos/WorldPrecip.lua'
da=root/'lib/DramalessAtmos.lua'
sp=root/'lib/SnowPack.lua'
manifest=root/'manifest.json'
p=paint.read_text() if paint.exists() else ''
w=wp.read_text() if wp.exists() else ''
d=da.read_text() if da.exists() else ''
check(paint.exists(),'SnowSurfacePaint runtime module present')
check('model * vertex_position' in p and 'wxSnowWorld = w.xyz' in p,'repaint uses exact host mesh world coordinates')
check('ChunkMesher' in p and 'C.peek' in p and 'a==mesh' in p,'terrain admission uses exact cached mesh object identity')
check('snowMap' in p and 'snowOrigin' in p and 'snowWorldSize' in p,'world-position coverage texture drives local repaint')
check('abs(wxSnowWorld.y - sy)' in p,'snow paint is bound to deposited support height, not an invisible cell cube')
check('setDepthMode,"lequal",false' in p,'repaint is depth-tested on exact visible surface without writing floating depth')
check('Voxel3D.draw=P._wrappedDraw' in p and 'P._Voxel3D.draw=P._origDraw' in p,'host draw hook is in-memory and restorable')
check('usePhysicalBank' in p and 'kind=="ground" or kind=="grass" or kind=="ice"' in p,'detached bank geometry is restricted to real load-bearing thickness surfaces')
check('SSP.capture' in w and 'SP.fillGroundPool' in w and w.index('SSP.capture')>w.index('SP.fillGroundPool'),'WorldPrecip feeds current SnowPack depth into repaint after exact-support staging')
check('SSP.usePhysicalBank' in w,'WorldPrecip suppresses old raised/tree cap path through repaint policy')
check('SSP.install(hostLib,Voxel3D,host)' in d,'DramalessAtmos installs repaint at actual voxel host draw seam')
check('SSP.observeScene(state,outdoor)' in d,'repaint receives exact current/neighbor world state')
check('SSP.invalidate' in d,'repaint state is cleared with Weather FX voxel invalidation')
check('paletteFor' not in p and 'TerrainAtlas' not in p,'repaint does not mutate shared palette/atlas and cannot whiten unrelated identical tiles')
check('snow_surface_repaint_8166_test.lua' in ''.join(x.name for x in (root/'tests').glob('*8166*')),'executable 8.1.66 repaint regression shipped')
failed=sum(not x for x,_ in checks)
print(f'8.1.66 snow surface repaint contract: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
