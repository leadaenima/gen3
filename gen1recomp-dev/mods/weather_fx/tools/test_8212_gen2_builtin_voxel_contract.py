#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=(Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1])
checks=[]
def ck(ok,n): checks.append((bool(ok),n)); print(('PASS ' if ok else 'FAIL ')+n)
m=json.loads((R/'manifest.json').read_text())

ver=tuple(int(x) for x in str(m.get('version','0.0.0')).split('.')[:3])
ck(ver>=(8,2,12),'manifest version retains 8.2.12+ bundled Gen2-host contract')
ck('Gen2Recomped-DramaticShapes' in m.get('optional_dependencies',[]),'bundled Gen2 host orders before Weather FX')
for f in ['lib/Interop.lua','lib/DramalessAtmos.lua','lib/Settings.lua']:
    ck('Gen2Recomped-DramaticShapes' in (R/f).read_text(),f'{f} recognizes bundled host')
d=(R/'lib/DramalessAtmos.lua').read_text()
ck('OPTIONAL_HOST_ONLY' in d and 'RenderDistance = true' in d,'optional RenderDistance helper is silent on hosts that omit it')
i=(R/'lib/Interop.lua').read_text()
ck('Gen2Recomped-DramaticShapes' in i[i.find('WIDE_BATTLE_IDS'):i.find('local cache')],'bundled Gen2 host is wide/live-world battle owner')
s=(R/'lib/Settings.lua').read_text()
ck('host.exports and host.exports.lib' in s and 'lib.require' in s,'first-person resolver supports exports.lib.require')
failed=[n for ok,n in checks if not ok]
print(f'8.2.12 bundled Gen2 voxel contract: {len(checks)-len(failed)}/{len(checks)} PASS')
sys.exit(1 if failed else 0)
