#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def ck(cond,label):
    checks.append((bool(cond),label))
settings=(ROOT/'lib/Settings.lua').read_text()
draw=(ROOT/'lib/Draw.lua').read_text()
changelog=(ROOT/'CHANGELOG.md').read_text()
ck('function Settings.force3dPresent()' in settings, 'strict 3D setting helper exists')
ck('Settings.presentMode() == "3d"' in settings, 'explicit 3D drives strict helper')
ck('local function strict3dPresent()' in draw, 'Draw strict 3D ownership gate exists')
ck('VoxelAtmos.active and VoxelAtmos.active()' in draw, 'strict gate requires active 3D host')
ck('if strict3dPresent() then' in draw, 'Draw pass has strict 3D bypass')
ck('out.rain, out.snow, out.hail = 0, 0, 0' in draw, 'strict gate zeros primary 2D precipitation')
ck('out.sand, out.debris, out.ash = 0, 0, 0' in draw, 'strict gate zeros grain 2D precipitation')
ck('function Draw.passPrecipitationOnly' in draw and 'if strict3dPresent() then return end' in draw, 'clipped 2D path obeys strict 3D')
ck('AUTO keeps the existing fail-safe behavior' in changelog, 'AUTO fallback contract documented')
for ok,label in checks:
    print(('PASS ' if ok else 'FAIL ')+label)
print(f"strict 3d static guard: {sum(ok for ok,_ in checks)} passed, {sum(not ok for ok,_ in checks)} failed")
sys.exit(0 if all(ok for ok,_ in checks) else 1)
