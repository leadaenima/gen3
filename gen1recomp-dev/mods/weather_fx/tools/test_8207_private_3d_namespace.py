from pathlib import Path
import re, sys
R=Path(__file__).resolve().parents[1]
s=(R/'lib/DramalessAtmos.lua').read_text()
checks=[]
def ck(ok,msg):
    checks.append((bool(ok),msg))
for name,rel in {
    'GustFront':'lib/voxel_atmos/GustFront.lua',
    'WorldInteractionPrecip':'lib/voxel_atmos/WorldInteractionPrecip.lua',
}.items():
    ck(re.search(r'\b'+re.escape(name)+r'\s*=\s*[\"\']'+re.escape(rel)+r'[\"\']',s) is not None, name+' is registered in private 3D OWN map')
    ck((R/rel).is_file(), name+' mapped file exists')
# These helpers must not be root-authority lookups: their API is the private W namespace.
root_block=re.search(r'local ROOT_OWN\s*=\s*\{(.*?)\n\s*\}',s,re.S)
rb=root_block.group(1) if root_block else ''
ck('GustFront' not in rb,'GustFront is not misclassified as root authority')
ck('WorldInteractionPrecip' not in rb,'WorldInteractionPrecip is not misclassified as root authority')
for name in ('Battle','SnowSurfacePaint','WeatherWorldInteraction'):
    ck(re.search(r'\b'+name+r'\s*=\s*true',rb) is not None,name+' is pinned to Weather FX root authority')
    ck((R/'lib'/(name+'.lua')).is_file(),name+' root authority file exists')
fail=[m for ok,m in checks if not ok]
for ok,m in checks: print(('PASS ' if ok else 'FAIL ')+m)
print(f'8.2.7 private 3D namespace resolver: {len(checks)-len(fail)}/{len(checks)} PASS')
sys.exit(1 if fail else 0)
