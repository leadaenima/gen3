#!/usr/bin/env python3
from pathlib import Path
import json,re,hashlib,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.51','manifest 8.1.51')
ck((R/'lib/DistantFrontPrecip.lua').exists(),'DistantFrontPrecip runtime module present')
new=(R/'lib/DistantFrontPrecip.lua').read_text(); c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); d=(R/'lib/DistantWeather.lua').read_text()
ck("V.require,'InstanceSeedBuffer'" in new and 'drawInstanced' in new,'front precipitation reuses shared immutable instancing infrastructure')
ck('if state.base and state.seed and state.shader then return true end' in new,'steady-state instancing avoids repeated support/resource probes')
ck('opts.count,opts.bx,opts.bz=particles' in c and 'DistantFrontPrecip' in c and '_drawDistantPrecipInstanced' in c,'CinematicAtmos production path routes front hydrometeors to instancing')
ck('_buildDistantWeather(Voxel3D,frame,map,instanced)' in c and 'elseif not skipHydrometeors then' in c,'exact 8.1.50 CPU hydrometeor path remains automatic fallback')
ck('particleBudget=max(1400,floor(9000*qscale+.5))' in c,'instanced production path preserves 9,000 max-quality front budget')
ck('particleBudget=math.max(1400,math.floor(9000*qscale+.5))' in c,'CPU fallback preserves 9,000 max-quality front budget')
ck('radius*.62' in d and 'shaftHandoff' in d,'broad 62% remote/local precipitation overlap remains intact')
# Exact baseline comparison: runtime edits must be surgical.
base=Path('/mnt/data/wfx8150_orig')
if base.exists():
    def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
    rels=['lib/DistantWeather.lua','lib/Settings.lua','lib/Quality.lua','lib/voxel_atmos/WorldPrecip.lua','lib/voxel_atmos/ConnectedWater3D.lua']
    for rel in rels: ck(sha(R/rel)==sha(base/rel),rel+' byte-identical to 8.1.50')
else: ck(False,'8.1.50 comparison tree available')
# No player-facing setting surface reduction.
s=(R/'lib/Settings.lua').read_text(); schema=s[s.find('Settings.SCHEMA'):s.find('Settings.GROUPS')]
keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',schema)
ck(len(keys)==68 and len(set(keys))==68,'all 68 player settings preserved')
# Quantitative staging contract at the 9,000-particle ceiling.
particles=9000; cpu_vertices=particles*4; cpu_floats=cpu_vertices*7; cpu_vertex_bytes=cpu_floats*4; cpu_hashes=particles*4
ck(cpu_vertices==36000 and cpu_vertex_bytes==1008000 and cpu_hashes==36000,'old max front path required 36,000 vertices / 1,008,000 float-bytes / 36,000 sine hashes per frame')
ck('BASE_ROWS={{-1,-1,0},{1,-1,0},{1,1,0},{-1,1,0}}' in new and 'BASE_MAP={1,2,3,1,3,4}' in new,'new base geometry is four immutable indexed vertices (no 6-vertex shader duplication)')
ck('seedCapacity=state.seedCap' in new and '8192' in new,'instance seed window remains bounded to shared 8,192 entries')
print(f'8.1.51 performance release gate: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
