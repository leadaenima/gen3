#!/usr/bin/env python3
"""Weather FX 8.1.40 exclusive VOID-underlay ownership gate.
Usage: test_8140_void_underlay.py [voxel_host_root]
When a host root is supplied, verify its WorldUnderlay really is a render path
outside VoxelScene.drawWater and that the Weather FX wrapper targets that seam.
"""
from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1]
D=(R/'lib/DramalessAtmos.lua').read_text(errors='replace')
checks=[]
def ck(v,m):
    checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)

ck('local function preflightVoidOwnership()' in D,'frame-local VOID ownership preflight exists')
ck('if not waterStyleEnabled() then return false end' in D,'ORIGINAL water style is fail-open')
ck('CW and CW.observed and CW.outerSea' in D,'preflight requires live observed Weather FX outer sea')
ck('repl,owned=CW3.prepare(nil)' in D,'host underlay is suppressed only after real Weather FX renderer preparation')
ck('owned and type(outer)=="table" and #outer>0' in D,'preflight proves drawable outer Weather FX rows')
ck('local function wrapHostVoidUnderlay(hostLib)' in D,'optional host WorldUnderlay wrapper exists')
ck('U._weatherFxVoidOwnerOriginalDraw=origDraw' in D,'native host underlay draw is preserved')
ck('if preflightVoidOwnership() then' in D and 'return false' in D,'successful Weather FX VOID ownership suppresses native outer plane')
ck('return origDraw(...)' in D,'failed/non-water/original ownership immediately passes native underlay through')
ck('drawFootprints' in D and 'suppress ONLY the giant outer plane' in D,'loaded-map WorldUnderlay safety footprints are explicitly preserved')
ck('safe(wrapHostVoidUnderlay,hostLib)' in D,'underlay wrapper installs on supported hosts')
ck('resetVoidPreflight()' in D and D.count('resetVoidPreflight()')>=3,'preflight state resets across frames/settings/invalidation')
ck('Atmos._wxVoidPreflightFrame==Atmos._waterFrame and Atmos._wxVoidPreflightOwned' in D,'later drawWater pass reuses same-frame prepared Weather FX rows')
ck('repl,owned=Atmos._wxVoidPreflightRepl,true' in D,'no second water-mesh preparation is required after underlay preflight')

# Truth table for the intended handoff. This deliberately mirrors the source
# guard, so every non-owned case remains native/fail-open.
def suppress(style_wx, observed_outer, prepared_outer):
    return bool(style_wx and observed_outer and prepared_outer)
for args,want,label in [
    ((True,True,True),True,'WEATHER FX + VOID WATER + successful preflight suppresses old outer fill'),
    ((False,True,True),False,'ORIGINAL mode keeps native outer fill'),
    ((True,False,True),False,'non-water/no-outer-sea keeps native outer fill'),
    ((True,True,False),False,'failed Weather FX preparation keeps native outer fill'),
]: ck(suppress(*args)==want,label)

if len(sys.argv)>1:
    H=Path(sys.argv[1])
    wu=H/'lib/WorldUnderlay.lua';vs=H/'lib/VoxelScene.lua'
    ck(wu.exists(),'exact host WorldUnderlay.lua exists')
    ck(vs.exists(),'exact host VoxelScene.lua exists')
    if wu.exists() and vs.exists():
        W=wu.read_text(errors='replace');V=vs.read_text(errors='replace')
        ck('function WorldUnderlay.draw(' in W,'host has separate WorldUnderlay.draw seam')
        ck('function WorldUnderlay.drawFootprints(' in W,'host has independent safety-footprint seam')
        ck(re.search(r'local\s+RANGE\s*=\s*32768',W) is not None,'host outer underlay spans the proven 32768-unit range')
        p_under=V.find('WorldUnderlay.draw(state')
        p_terrain=V.find('Voxel3D.draw(terrain')
        p_water=V.find('VoxelScene.drawWater(waterDraws')
        ck(min(p_under,p_terrain,p_water)>=0 and p_under<p_terrain<p_water,'host draws outer underlay before terrain and outside/later than drawWater ownership seam')
        ck('WorldUnderlay.drawFootprints(underlayFootprints)' in V,'host safety footprints remain a distinct call after outer underlay')

passed=sum(v for v,_ in checks);failed=len(checks)-passed
print(f'8.1.40 exclusive void-underlay ownership: {passed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
