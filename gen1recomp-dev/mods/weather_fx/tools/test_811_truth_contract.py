#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
passed=failed=0

def check(cond,msg):
    global passed,failed
    if cond:
        passed+=1
    else:
        failed+=1; print('FAIL:',msg)

def txt(rel): return (ROOT/rel).read_text(encoding='utf-8')

manifest=json.loads(txt('manifest.json'))
check(tuple(map(int,manifest.get('version','0.0.0').split('.'))) >= (8, 1, 1),'manifest preserves 8.1.1+ truth repair')
check((ROOT/'BASELINE').read_text().strip()==manifest.get('version'),'BASELINE marker matches manifest')

# Presentation truth: active voxel host is not synonymous with chosen strict 3D.
bridge=txt('lib/VoxelAtmosBridge.lua'); atmos=txt('lib/DramalessAtmos.lua'); tornado=txt('lib/Tornado.lua')
check('function Bridge.presentation3d()' in bridge,'bridge exposes selected-presentation authority')
check('function Atmos.wants3d()' in atmos,'voxel atmosphere exposes wants3d')
check('B.presentation3d' in tornado,'tornado asks selected presentation, not host activity alone')

# Current supported public warp seam requires destination coordinates.
check('world.warpTo' in tornado,'tornado carry prefers public mod.world warp API')
check(re.search(r'world\.warpTo,world,destination,landing\.x,landing\.y,landing\.facing',tornado) is not None,
      'public tornado warp supplies map + x + y + facing')
check('T.landingFor(destination)' in tornado,'carry refuses destinations without a safe landing record')
check(('type(mapId)=="string" and T.landingFor(mapId)' in tornado) or ('if T.landingFor(mapId) then' in tornado),'destination list filters visited maps by safe landing')

# Flat voxel world: legacy compatibility paths must not generate relief.
distant=txt('lib/voxel_atmos/DistantWorld.lua'); apron=txt('lib/voxel_atmos/HorizonApron.lua')
for forbidden in ('ridgePoints','farMount','midMount','hillPts','noise1('):
    check(forbidden not in distant,f'DistantWorld does not generate legacy relief token {forbidden}')
for forbidden in ('hashHill','rolling =','settle ='):
    check(forbidden not in apron,f'HorizonApron does not generate local relief token {forbidden}')
check('w.y = -0.72;' in apron,'HorizonApron continuation is level before optional host-wide curvature')

# User-facing docs must disclose FPV override and the current settings surface.
readme=txt('README.md')
check('FPV intentionally forces strict 3D' in readme,'README discloses FPV presentation override')
check((('51 player controls' in readme) or ('53 player controls' in readme) or ('60 player controls' in readme)) and '11 in-game submenus' in readme,'README states grouped settings surface')
check(('outdoor overworld' in readme and 'exact' in readme and 'landing' in readme),'README does not promise arbitrary visited-map coordinates')

print(f'8.1.1 truth contract: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
