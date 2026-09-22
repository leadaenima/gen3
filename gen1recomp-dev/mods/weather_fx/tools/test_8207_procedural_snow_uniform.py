#!/usr/bin/env python3
from pathlib import Path
import re, sys
R=Path(__file__).resolve().parents[1]
s=(R/'lib/ProceduralSnowField.lua').read_text()
checks=[]
def ck(ok,msg):
    checks.append((bool(ok),msg)); print(('PASS ' if ok else 'FAIL ')+msg)
# 8.2.7 regression: fieldIntensity was declared+uploaded but never consumed by
# GLSL, so real Battle Art/LOVE optimized it away and Shader:send failed,
# forcing BLIZZARD/SNOW onto the sparse CPU compatibility fallback.
ck('extern float fieldIntensity' not in s,'dead optimized-out fieldIntensity uniform is not declared')
ck("uniform(sh,'fieldIntensity'" not in s,'dead fieldIntensity uniform is not uploaded')
# Authored intensity still has to affect the actual shader through fallScale;
# removing the dead uniform must not remove intensity from motion/density math.
ck(re.search(r'local\s+fallScale\s*=.*intensity',s) is not None,'authored intensity remains baked into fallScale')
ck("uniform(sh,'fieldFallScale',fallScale)" in s,'live fieldFallScale uniform is still uploaded')
# Preserve actionable telemetry if another real uniform ever fails.
ck("state.reason='uniform upload failed: '..tostring(name)" in s,'uniform failure telemetry names the failed uniform')
# Keep the modern native-instance snow path and full-visual proof seam intact.
ck('love_InstanceID' in s,'native instance-ID snow backend remains present')
ck('function P.canVirtualize() return ensure() and state.proven==true end' in s and 'state.proven=true' in s,'procedural full-visual proof seam remains present')
fail=sum(not ok for ok,_ in checks)
print(f'8.2.7 procedural snow optimized-uniform regression: {len(checks)-fail}/{len(checks)} PASS')
sys.exit(1 if fail else 0)
