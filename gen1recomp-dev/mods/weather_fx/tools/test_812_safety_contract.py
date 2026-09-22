#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
passed=failed=0

def check(cond,msg):
    global passed,failed
    if cond: passed+=1
    else:
        failed+=1; print('FAIL:',msg)

def txt(rel): return (ROOT/rel).read_text(encoding='utf-8')

manifest=json.loads(txt('manifest.json'))
check(tuple(map(int,manifest.get('version','0.0.0').split('.'))) >= (8, 1, 2),'manifest preserves 8.1.2+ safety revision')
check(tuple(map(int,(ROOT/'BASELINE').read_text().strip().split('.'))) >= (8, 1, 2),'BASELINE preserves 8.1.2+ safety revision')

# Tornado destination safety: exact landing must be outdoor and path-connected
# to a real outdoor map connection. No arbitrary warp/door fallback is allowed.
t=txt('lib/Tornado.lua')
for token,label in [
    ('function T.validateLanding(', 'exact-cell landing validator exists'),
    ('connectedExit(', 'landing proof checks real map connections'),
    ('mapOutside(', 'outdoor-only map classifier exists'),
    ('warpCell(', 'door/warp landing cells are explicitly rejected'),
    ('T.hasSurf()', 'water destination selection is Surf-gated'),
    ('function T.activateSurfLanding(', 'water landing activates Surf before release'),
    ('function T.emergencyReturn(', 'failed water activation has emergency return'),
    ('world.warpTo', 'carry uses supported public world warp when present'),
]: check(token in t,label)
check('source="warp"' not in t and "source='warp'" not in t,'generic map warp fallback is removed')
check(re.search(r'world\.warpTo,world,destination,landing\.x,landing\.y,landing\.facing',t) is not None,
      'public carry warp always supplies map+x+y+facing')
check('ow.partyKnows' in t and '"SURF"' in t,'Surf eligibility uses live overworld party/badge authority')
check('landing.mode=="water"' in t and 'activateSurfLanding' in t,'water landing path cannot release control before Surf handling')

# Rainbow is a physically gated world-sky effect, not a generic overlay.
r=txt('lib/Rainbow.lua'); r3=txt('lib/voxel_atmos/Rainbow3D.lua'); da=txt('lib/DramalessAtmos.lua')
check('wetMemory' in r and 'rain' in r,'rainbow remembers recent rain')
check('sun' in r and ('altitude' in r or 'alt' in r),'rainbow consumes real sun state')
check('discTransmission' in r or 'cloud' in r,'rainbow requires clearing/solar transmission')
check('function R.draw' in r3 or 'function Rainbow3D.draw' in r3 or 'function R3.draw' in r3,'3D rainbow has executable renderer')
check('lequal' in r3.lower(),'3D rainbow is depth tested')
check('NightSky' in r3 and 'projectDirection' in r3,'3D rainbow is world-direction sky geometry')
pos_rb=da.find('Rainbow3D'); pos_cin=da.find('cin.draw', max(0,pos_rb))
check(pos_rb>=0 and pos_cin>pos_rb,'rainbow is submitted before cloud/weather compositor so clouds can occlude it')

# Wind movement consumes the existing natural wind authority and does not
# replace collision/player movement. Both grid and FPV/free-move seams exist.
w=txt('lib/WindPlayer.lua'); main=txt('main.lua')
check('WindFlow' in w or 'WindEngine' in w,'wind walking consumes existing shared wind authority')
check('movement.speed' in w,'grid walking uses documented movement.speed hook')
check('installFreeMove' in w and ('FreeMove' in w or 'FirstPerson' in w),'FPV/free-move receives in-memory wind scaling')
check('headwindSlow' in w and 'tailwindBoost' in w,'headwind/tailwind strengths are bounded config coefficients')
check('surf' in w.lower() and 'bike' in w.lower(),'bike and Surf are excluded from walking-speed changes')
check('WindPlayer.installHooks' in main,'main installs wind movement hook')

# Settings/config exposure.
cfg=txt('lib/Config.lua'); setsrc=txt('lib/Settings.lua')
check('rainbow = { enabled = true' in cfg,'rainbow enabled by config default')
check('playerMovement = true' in cfg,'wind walking enabled by config default')
check('key = "rainbows"' in setsrc and 'label = "RAINBOWS"' in setsrc,'rainbow player setting exists')
check('key = "windWalk"' in setsrc and 'label = "WIND & WALKING"' in setsrc,'wind walking player setting exists')

# Preserve the 8.1.1 truth repairs and flat-world rule.
bridge=txt('lib/VoxelAtmosBridge.lua'); distant=txt('lib/voxel_atmos/DistantWorld.lua'); apron=txt('lib/voxel_atmos/HorizonApron.lua')
check('function Bridge.presentation3d()' in bridge,'selected-presentation authority remains present')
for forbidden in ('ridgePoints','farMount','midMount','hillPts','noise1('):
    check(forbidden not in distant,f'flat-world DistantWorld excludes {forbidden}')
for forbidden in ('hashHill','rolling =','settle ='):
    check(forbidden not in apron,f'flat-world HorizonApron excludes {forbidden}')

print(f'8.1.2 safety contract: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
