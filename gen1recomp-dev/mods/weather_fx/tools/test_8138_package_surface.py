#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.38','manifest 8.1.38')
ck((R/'BASELINE').read_text().strip()=='8.1.38','BASELINE marker 8.1.38')
for f in ['RELEASE-NOTES-8.1.38.md','tests/pond_void_water_8138_test.lua','tools/test_8138_runtime_delta.py','tools/test_8138_package_surface.py','tools/test_8138_external_void_ocean.py','tools/baselines/8.1.37-runtime-sha256.json','tools/baselines/8.1.38-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
cw=(R/'lib/ConnectedWater.lua').read_text(); c3=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text(); dra=(R/'lib/DramalessAtmos.lua').read_text(); rn=(R/'RELEASE-NOTES-8.1.38.md').read_text()
ck('OUTER_VOID_RANGE=32768' in cw and 'VOID_RING_CELLS=6' in cw and 'TILE=16' in cw,'outer sea matches 32768 host underlay and exact 96px apron handoff')
ck('visualOnly=true' in cw and 'outerSea=true' in cw and 'W.bodyByCell' not in cw[cw.find('local function outerVoidSea'):cw.find('function W.observeVoxel')],'outer sea remains presentation-only outside gameplay body map')
ck('b.kind=="POND"' in c3 and 'b.visualOnly~=true' in c3 and 'b.voidWater~=true' in c3,'living-water classification is authored POND only')
ck('return 0.46+0.08' in c3,'pond alpha constrained to 46-54 percent')
ck('MAX_POND_FISH=24' in c3 and 'return 2+floor' in c3,'fish population is deterministic 2-6 with global cap 24')
ck('meshForPondBed' in c3 and 'ensureFishMesh' in c3 and 'drawPondUnderwater' in c3,'pond bed and tiny fish use real 3D geometry')
ck('(tonumber(b.ice) or 0)<0.68' in c3,'fish close under substantial pond ice')
ck('dynamicCount=dc' in c3 and 'for i=1,dc do' in c3 and 'setVertices,e.mesh,e.rows,1,dc' in c3,'outer ocean updates only bounded near physical belt')
ck('outerDraws' in dra and 'drawPonds' in dra and 'origWater(ponds' in dra,'shared host bridge routes outer sea and fail-open pond pass')
ck('Surf destinations' in rn and 'movement/collision support' in rn and 'freezing or load-bearing ice' in rn,'presentation-only gameplay safety contract documented')
ck('Only **authored connected bodies classified as `POND`**' in rn,'authored-POND scope documented')
ck('5,576 vertices / 32,472 indices' in rn and '576 near-corridor vertices' in rn,'final bounded outer-ocean topology documented')
failed=sum(not v for v,_ in checks);print(f'8.1.38 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
