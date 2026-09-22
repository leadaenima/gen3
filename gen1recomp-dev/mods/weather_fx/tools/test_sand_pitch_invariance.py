#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
src = (ROOT/'lib/voxel_atmos/WorldPrecip.lua').read_text(encoding='utf-8')
checks=[]
def ck(ok,msg): checks.append((bool(ok),msg))
ck('local function drawGrainPass(Voxel3D, wantedKind, only, firstIdx, lastIdx, ex, ey, ez)' in src,
   'grain draw pass no longer accepts camera-pitch/lookDown state')
ck('lookDown' not in src, 'WorldPrecip contains no camera-pitch sand presentation branch')
ck('setDepthMode, "always"' not in src, 'sand never disables normal depth occlusion when looking down')
ck('if kind == 2 then\n      y = y + 0.25\n    end' in src,
   'sand uses one fixed small world-space floor clearance at every pitch')
ck('if hs > 0.85 then hs = 0.85 end' in src and 'if hw > 1.6 then hw = 1.6 end' in src,
   'sand uses fixed pitch-invariant card caps')
ck('local sandShader = nil' in src and 'float soft = 1.0 - smoothstep(0.08, 1.0, d);' in src,
   'sand keeps soft radial shader instead of hard opaque rectangles')
ck('local horiz = sqrt(tx * tx + tz * tz)' in src,
   'sand distance fade remains based on world horizontal distance, not camera pitch')
ck('local streak = 1.15 + min(2.4, speed * 0.028)' in src,
   'sand elongation remains driven by particle travel speed')
for ok,msg in checks:
    print(('PASS: ' if ok else 'FAIL: ')+msg)
failed=sum(not x for x,_ in checks)
print(f'\n{len(checks)-failed}/{len(checks)} sand pitch-invariance checks passed')
sys.exit(1 if failed else 0)
