#!/usr/bin/env python3
"""Static contract gate for current voxel-host integration seams.

This protects Weather FX's side of the compatibility contract. Public host
snapshots are audited externally at release time; no third-party source is
vendored into Weather FX.
"""
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'lib/DramalessAtmos.lua').read_text()
light=(ROOT/'lib/voxel_atmos/WorldLightning.lua').read_text()
checks=[]
def ck(cond,msg):
    checks.append((bool(cond),msg))

for host in ('BATTLE_ART_VOXEL_FORK','DRAMATIC_SHAPE','DRAMALESS_SHAPE','Gen2Recomped-DramaticShapes','potato_voxel','POTATO_VOXEL','PotatoVoxel'):
    ck(host in text, f'host id retained: {host}')
ck('host.exports and host.exports.lib' in text, 'legacy/public lib export seam remains guarded')
ck('not Voxel3D.endScene' in text, 'endScene capability is validated before wrapping')
ck(re.search(r'VoxelScene\.render\s*=\s*function\(state,\s*w,\s*h,\s*vw,\s*vh,\s*paletteFor,\s*\.\.\.\)', text),
   'VoxelScene wrapper accepts trailing current/future host render args')
ck(re.search(r'return\s+orig\(state,\s*w,\s*h,\s*vw,\s*vh,\s*paletteFor,\s*\.\.\.\)', text),
   'VoxelScene wrapper forwards trailing args unchanged')
ck('type(Voxel3D.beginEffect) ~= "function"' in text and 'function Voxel3D.beginEffect(shader)' in text,
   'hosts without beginEffect retain safe in-memory polyfill')
ck('type(Voxel3D.endEffect) ~= "function"' in text and 'function Voxel3D.endEffect()' in text,
   'hosts without endEffect retain safe in-memory polyfill')
for name in ('Types','Config','Settings','Quality','Scene','TimeOfDay'):
    ck(re.search(r'ROOT_OWN\s*=\s*\{[\s\S]*?\b'+re.escape(name)+r'\s*=\s*true', text) is not None,
       f'Weather FX authority cannot be shadowed by host module: {name}')
ck('VoxelScene' in light and 'groundAt' in light, 'world lightning retains voxel terrain-height seam')
ck('Atmos._lastNeighbors = state.neighbors' in text, 'rendered neighbour context is captured')
ck('Atmos._lastPlayer = state.player' in text, 'live player context is captured')
ck('Atmos._lastState = state' in text and
   (('NL.observe(state)' in text) or ('_npcLightningForRuntime()' in text and ('pcall(NL.observe,state)' in text or 'safe(NL.observe,state)' in text))),
   'live voxel render state is published to NPC lightning targeting')
ck('NpcLightning = "lib/voxel_atmos/NpcLightning.lua"' in text,
   'NPC lightning module is isolated inside Weather FX private voxel namespace')
npc=(ROOT/'lib/voxel_atmos/NpcLightning.lua').read_text()
ck('type(Voxel3D.size) == "function"' in npc and 'type(c) == "function" then c = c() end' in npc,
   'NPC lightning accepts current Voxel3D size()/canvas() function seams')
ck('VS.drawEntity' in npc and 'Voxel3D.flatten' in npc,
   'NPC char overlay requires guarded host drawEntity + flatten seams')
ck('type(VS.drawEntity) == "function"' in npc and
   'type(Voxel3D.flatten) == "function"' in npc and 'then return false end' in npc,
   'NPC char overlay fails open when host presentation seams are unavailable')
ck('we only read their exports.lib and wrap Voxel3D.endScene in memory' in text,
   'integration remains in-memory; no host file patching contract')

passed=sum(1 for ok,_ in checks if ok)
for ok,msg in checks:
    print(('PASS' if ok else 'FAIL'), msg)
print(f'\ncurrent voxel-host contract gate: {passed}/{len(checks)} passed')
sys.exit(0 if passed==len(checks) else 1)
