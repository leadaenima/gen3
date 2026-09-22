#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
mods=[
 'main.lua','lib/CelestialStarField.lua','lib/voxel_atmos/NpcLightning.lua',
 'lib/NightSky.lua','lib/DramalessAtmos.lua','lib/voxel_atmos/CinematicAtmos.lua',
 'lib/voxel_atmos/WorldPrecip.lua']
failed=0

def ck(cond,msg):
 global failed
 print(('PASS' if cond else 'FAIL'),msg)
 if not cond: failed+=1

sc=(ROOT/'lib/SafeCall.lua').read_text()
ck('function S.call' in sc and 'function S.bind' in sc and 'function S.stats' in sc,'central SafeCall authority exists')
ck('stats.failures' in sc and 'lastScope' in sc and 'lastError' in sc,'SafeCall records diagnosable failures')
ck('mod.log:warn' in sc and 'power' in sc.lower(),'SafeCall rate-limits and logs failures')
main=(ROOT/'main.lua').read_text()
ck('V.safeCall = SafeCall.bind("root")' in main, 'root SafeCall keeps pcall-compatible argument semantics')
voxel_children={'lib/voxel_atmos/NpcLightning.lua','lib/voxel_atmos/CinematicAtmos.lua','lib/voxel_atmos/WorldPrecip.lua'}
for rel in mods:
 text=(ROOT/rel).read_text()
 if rel in voxel_children:
  ck('V.safeCall = V.safeCall or pcall' in text and 'V.safeCall(' in text, f'{rel} consumes shared voxel SafeCall authority with standalone fallback')
 else:
  ck(('SafeCall' in text and 'SafeCall.bind' in text) or ('V.safeBind' in text and 'or pcall' in text), f'{rel} uses shared SafeCall authority')
 ck(text.count('pcall')<=4, f'{rel} has no scattered protected-call island density ({text.count("pcall")})')
dram=(ROOT/'lib/DramalessAtmos.lua').read_text()
ck('safeCall = safe' in dram, 'voxel namespace publishes the root SafeCall authority to child modules')
r=subprocess.run(['texlua','tests/safe_call_test.lua'],cwd=ROOT)
ck(r.returncode==0,'SafeCall executable contract')
print(f'SafeCall hardening: {19-failed}/19 passed')
sys.exit(1 if failed else 0)
