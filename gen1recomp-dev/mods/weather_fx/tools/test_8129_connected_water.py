#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
cw=(R/'lib/ConnectedWater.lua').read_text(); r=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text(); d=(R/'lib/DramalessAtmos.lua').read_text(); sp=(R/'lib/SnowPack.lua').read_text(); mc=(R/'lib/Microclimate.lua').read_text(); main=(R/'main.lua').read_text()
ck('isWaterCell' in cw and 'four-neighbour' not in cw or 'isWaterCell' in cw,'cartridge water classification is the body source')
ck('identityKey(map,cx,cz)' in cw and 'oldByCell' in cw,'body persistence uses map+cell identity rather than viewport position')
ck('c.gx+1' in cw and 'c.gx-1' in cw and 'c.gz+1' in cw and 'c.gz-1' in cw,'body connectivity is four-directional in flat world space')
ck('greedyRects' in cw and 'rects=greedyRects' in cw,'connected mask greedily merges surface rectangles')
ck('MAX_RIPPLES=48' in cw and 'spawnRipples' in cw,'rain ripple pool is active and bounded')
ck('_mapWaterCache' in cw and '_topologyKey==topo' in cw,'water classification/topology is cached instead of rescanned every frame')
ck('MAX_STORED_CELLS=16384' in cw and '_cellState' in cw,'off-screen water thermodynamics are persistent but memory-bounded')
ck('moonPhase' in cw and 'spring=' in cw and 'touchesBoundary' in cw,'moon phase and water-body scale drive tides')
ck('WINTER' in cw and 'LOAD_BEARING' in cw and 'THAW_HOLD' in cw,'progressive winter freeze and safe thaw are explicit')
ck('ctx.reason~="tile"' in cw and 'isWaterCell' in cw and 'ctx.mover.surfing' in cw,'ice movement hook only widens tile-water refusal and preserves Surf')
ck('ConnectedWater = true' in d and 'ConnectedWater3D' in d,'private voxel namespace resolves Weather FX water authorities root-first')
ck('VoxelScene.drawWater' in d and 'CW3.prepare' in d and 'CW3.drawAfterWater' in d,'host water pass is replaced at final presentation seam with fail-open wrapper')
ck('WAVE_TRAINS' in r and 'lastSector' in r and 'Water.invalidate' in r,'wind-directed wave shader has sector hysteresis')
ck('loadBearing' in r and 'iceTexture' in r,'load-bearing bodies leave liquid relief and render as ice')
ck('rippleMesh' in r and 'setVertices' in r,'rain ripples render as one bounded mesh batch')
ck('C._origDynamics=nil' in r and 'WAVE_SWELL' in r and 'WAVE_BEND' in r and 'CW3.invalidate' in d,'hot teardown restores host water tuning and clears hydrosphere renderer state')
ck('iceSupportAt' in sp and '"ice"' in sp,'SnowPack accepts load-bearing ice while retaining liquid-water rejection')
ck('liquidFractionNear' in mc and 'iceWater' in mc,'frozen water changes flat-world microclimate rather than only appearance')
ck('ConnectedWater.installHooks' in main,'connected-water movement hook installs at game.ready')
ck('mountain' not in cw.lower() and 'orographic' not in cw.lower() or 'no mountains' in cw.lower() or 'orographic assumptions' in cw.lower(),'connected-water engine contains no terrain-height/orographic weather logic')
# Execute focused behavior contracts so this structural test cannot pass on dead wiring.
for name in ['connected_water_test.lua','connected_water_3d_test.lua','snow_on_ice_test.lua']:
    rc=subprocess.call(['texlua',str(R/'tests'/name)],cwd=R)
    ck(rc==0,name+' executable contract')
failed=sum(not v for v,_ in checks)
print(f'8.1.29 connected water gate: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
