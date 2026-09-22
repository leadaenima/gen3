from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1]
d=(R/'lib/DramalessAtmos.lua').read_text()
c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
checks=[]
def ck(ok,msg): checks.append((bool(ok),msg)); print(('PASS ' if ok else 'FAIL ')+msg)
ck('local ok, value = pcall(hostLib.require, name)' in d,'speculative host lookup uses non-telemetry pcall')
ck('local ok3, Voxel = pcall(hostLib.require, "Voxel")' in d,'Voxel/VoxelState compatibility probe uses pcall')
ck('if type(Voxel3D.puddleMask) ~= "function" then return false end' in c,'puddle reflection feature-detects host mask seam')
# The guard must precede every direct puddleMask call inside the reflection function.
m=re.search(r'local function drawSpriteReflections(.*?)\nend\n\n-- ---------- ground mist',c,re.S)
body=m.group(1) if m else ''
guard=body.find('type(Voxel3D.puddleMask)')
first=body.find('Voxel3D.puddleMask(')
ck(guard>=0 and first>guard,'puddleMask guard executes before mask calls')
# Verify precipitation remains a later independent safe pass, so declining reflection cannot suppress it.
ck('_safePass("sprite-reflections"' in c and 'WorldPrecip.draw' in c,'sprite reflection and WorldPrecip remain independent passes')
fail=sum(not ok for ok,_ in checks)
print(f'8.2.7 Battle Art wet compatibility: {len(checks)-fail}/{len(checks)} PASS')
sys.exit(1 if fail else 0)
