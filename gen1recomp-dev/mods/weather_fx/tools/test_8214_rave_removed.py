#!/usr/bin/env python3
from pathlib import Path
import json, sys
ROOT=Path(__file__).resolve().parent.parent
checks=[]
def check(cond,msg):
    checks.append((bool(cond),msg))
    if not cond: print('FAIL',msg)
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
manifest=json.loads(text('manifest.json'))
check(manifest.get('version')=='8.2.14','manifest version is 8.2.14')
check(not (ROOT/'lib/RaveMusic.lua').exists(),'RaveMusic module removed')
check(not (ROOT/'assets/sounds/rave').exists(),'bundled RAVE audio directory removed')
types=text('lib/Types.lua')
check('id="RAVE"' not in types and "id='RAVE'" not in types,'RAVE weather definition removed')
check('"RAVE"' not in types and "'RAVE'" not in types,'RAVE removed from weather catalogue/pins')
settings=text('lib/Settings.lua')
check('key = "raveMusic"' not in settings and 'key = "raveStrobe"' not in settings,'RAVE settings rows removed')
check('function Settings.raveMusic' not in settings and 'function Settings.raveStrobe' not in settings,'RAVE settings helpers removed')
check('tostring(norm):upper()=="RAVE"' in settings and 'defaults.always or "auto"' in settings,'legacy persisted RAVE selection migrates to AUTO')
audio=text('lib/Audio.lua')
check('RaveMusic' not in audio and 'raveOwnsMusic' not in audio and 'raveStatus' not in audio,'RAVE audio ownership removed')
main=text('main.lua')
check('raveOwnsMusic' not in main,'native music-volume RAVE duck removed')
drama=text('lib/DramalessAtmos.lua')
check('raveShowWanted' not in drama and 'weatherFxRaveCarry' not in drama,'RAVE host bridge/show carry removed')
battle=text('lib/BattleDraw.lua')
check('raveCarry' not in battle,'RAVE battle carry removed')
cin=text('lib/voxel_atmos/CinematicAtmos.lua')
for token,label in [('raveAmount','rave atmosphere channel'),('_drawRave','rave draw rig'),('weatherFxRave','rave carry namespace'),('raveSong','rave song synchronization')]:
    check(token not in cin,f'{label} removed')
failed=[x for x in checks if not x[0]]
print(f'8.2.14 RAVE removal contract: {len(checks)-len(failed)}/{len(checks)} PASS')
sys.exit(1 if failed else 0)
