#!/usr/bin/env python3
from pathlib import Path
import json, sys
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(ok,name):
    checks.append((bool(ok),name))
    if not ok: print('FAIL',name)
manifest=json.loads((R/'manifest.json').read_text())
ck(tuple(map(int,manifest.get('version','0.0.0').split('.'))) >= (8,2,11),'manifest version preserves 8.2.11+ contract')
ck(set(manifest.get('games',[]))=={'gen1','gen2'},'manifest advertises gen1 + gen2')
h=(R/'lib/HostRuntime.lua').read_text()
for game,gen in [('red',1),('blue',1),('yellow',1),('gold',2),('silver',2),('crystal',2)]:
    ck(game in h, f'HostRuntime declares {game}')
main=(R/'main.lua').read_text()
ck('HostRuntime.isGen2()' in main,'Gen2 OPTIONS row uses generation adapter')
# The old bug coupled generation detection to the optional CRYSTAL_251 mod.
options=main[main.find('Current Gen 2 does not splice'):main.find('Fallback descriptor',main.find('Current Gen 2 does not splice'))]
ck('Battle.hostCrystal()' not in options,'Gen2 OPTIONS row no longer depends on CRYSTAL_251')
b=(R/'lib/Battle.lua').read_text()
for token in ['NATIVE_TO_WX','WX_TO_NATIVE','nativeMechanicsOwn','wxWeather','weatherPermanent = true']:
    ck(token in b, f'Battle adapter contains {token}')
ck('RAIN = "RAIN_HEAVY"' in b and 'SUN = "SUNNY"' in b,'battle-end native weather maps back to overworld')
t=(R/'lib/Types.lua').read_text()
ck('SUN          = "SUNNY"' in t and 'RAIN         = "RAIN_HEAVY"' in t,'visual catalogue accepts Gen2 native weather ids')
bd=(R/'lib/BattleDraw.lua').read_text()
ck('field.wxWeather' in bd,'battle renderer reads custom Gen2 sidecar weather')
failed=[n for ok,n in checks if not ok]
print(f'8.2.11+ Gen2Recomp contract: {len(checks)-len(failed)}/{len(checks)} PASS')
sys.exit(1 if failed else 0)
