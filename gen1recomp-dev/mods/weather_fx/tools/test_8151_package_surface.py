#!/usr/bin/env python3
from pathlib import Path
import json,re,sys,hashlib
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.51','manifest 8.1.51')
ck((R/'BASELINE').read_text().strip()=='8.1.51','BASELINE 8.1.51')
ck(not (R/'texluac.out').exists(),'no texluac.out compiler artifact')
for f in ['RELEASE-NOTES-8.1.51.md','PERFORMANCE-AUDIT-8.1.51.md','WEATHER-FX-8.1.51-FINAL-AUDIT.md','tools/test_8151_performance_release.py','tools/test_8151_runtime_delta.py','tools/test_8151_runtime_freeze.py','tools/test_8151_package_surface.py','tests/distant_front_instancing_8151_test.lua','tests/max_settings_simultaneous_8151_test.lua','tests/front_precip_continuity_8150_test.lua','tools/benchmark_8151_front_precip.lua','tools/baselines/8.1.50-runtime-sha256.json','tools/baselines/8.1.51-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();n=(R/'lib/DistantFrontPrecip.lua').read_text();d=(R/'lib/DistantWeather.lua').read_text()
ck('particleBudget=max(1400,floor(9000*qscale+.5))' in c and 'particleBudget=math.max(1400,math.floor(9000*qscale+.5))' in c,'both instanced and CPU fallback retain 9,000 MAX remote budget')
ck('radius*.62' in d and 'shaftHandoff' in d,'8.1.50 62% handoff retained')
ck('BASE_MAP={1,2,3,1,3,4}' in n and 'drawInstanced' in n,'indexed four-vertex instancing path present')
ck('if state.base and state.seed and state.shader then return true end' in n,'steady-state support probe bypass present')
ck('_distantInstOpts' in c and 'opts.count,opts.bx,opts.bz=particles' in c,'per-front option records are reused')
ck('elseif not skipHydrometeors then' in c,'8.1.50 CPU hydrometeor fallback preserved')
s=(R/'lib/Settings.lua').read_text();schema=s[s.find('Settings.SCHEMA'):s.find('Settings.GROUPS')];keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',schema)
ck(len(keys)==68 and len(set(keys))==68,'68 player settings preserved')
groups=s[s.find('Settings.GROUPS'):s.find('function Settings.row',s.find('Settings.GROUPS'))];ids=re.findall(r'\{\s*id="([^"]+)"',groups)
ck(len(ids)==11 and len(set(ids))==11,'11 shallow categories preserved')
# Surgical baseline identity checks.
b50=json.loads((R/'tools/baselines/8.1.50-runtime-sha256.json').read_text())['files']
for rel in ['lib/DistantWeather.lua','lib/Settings.lua','lib/Quality.lua','lib/voxel_atmos/WorldPrecip.lua','lib/voxel_atmos/ConnectedWater3D.lua']:
    exp=b50[rel];p=R/rel;ck(hashlib.sha256(p.read_bytes()).hexdigest()==exp['sha256'] and p.stat().st_size==exp['size'],rel+' byte-identical to 8.1.50')
print(f'8.1.51 package surface: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
