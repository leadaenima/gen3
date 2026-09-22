#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.39','manifest 8.1.39')
ck((R/'BASELINE').read_text().strip()=='8.1.39','BASELINE marker 8.1.39')
for f in ['RELEASE-NOTES-8.1.39.md','tests/void_water_all_voxels_8139_test.lua','tools/test_8139_runtime_delta.py','tools/test_8139_package_surface.py','tools/test_8139_external_voxel_water.py','tools/baselines/8.1.38-runtime-sha256.json','tools/baselines/8.1.39-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
cw=(R/'lib/ConnectedWater.lua').read_text();c3=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text();da=(R/'lib/DramalessAtmos.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.39.md').read_text()
for host in ['BATTLE_ART_VOXEL_FORK','DRAMATIC_SHAPE','DRAMALESS_SHAPE','potato_voxel','POTATO_VOXEL','PotatoVoxel','STADIUM2_OVERWORLD_MODELS']:
    ck(('"'+host+'"') in da,'bridge host '+host)
ck('pcall(require,"src.world.Map")' in cw and 'Map.isOutdoor' in cw,'generation-safe call-time outdoor authority')
ck('def.environment' in cw and 'def.tileset' in cw,'Gen1 + Gen2 fallback semantics')
ck('function W.setVoxelWaterHost(info)' in cw and 'outerVoidRange()' in cw and 'voidRingWorld()' in cw,'hydrosphere consumes host water capabilities')
ck('publishWaterHostCaps' in da and 'U.RANGE' in da and 'outerRange=32768' in da,'optional underlay range + universal horizon fallback')
ck('VoxelScene.drawWater=function(draws,cast,...)' in da and 'origWater(draws,cast,...)' in da,'host water wrapper preserves variadic contract and fail-open native path')
ck('_voidDraws' in c3 and 'function C.drawStandaloneVoid' in c3,'no-drawWater compatibility path is synthetic-VOID-only')
ck('if CW and CW.outerSea' in da and 'not Atmos._wxWaterDrawn' in da,'endScene fallback only runs when Weather FX void water was not already drawn')
ck('visualOnly=true' in cw and 'outerSea=true' in cw,'outer sea remains presentation-only')
ck('b.kind=="POND"' in c3 and 'MAX_POND_FISH=24' in c3,'8.1.38 living ponds retained')
ck('Surf' in rn and 'collision' in rn and 'SnowPack' in rn and 'WATER STYLE = ORIGINAL' in rn,'safety/fail-open contract documented')
failed=sum(not v for v,_ in checks);print(f'8.1.39 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
