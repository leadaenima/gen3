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
check(tuple(map(int,manifest.get('version','0.0.0').split('.'))) >= (8, 1, 8),'manifest preserves 8.1.8+ settings/time/constellation revision')
check(tuple(map(int,(ROOT/'BASELINE').read_text().strip().split('.'))) >= (8, 1, 8),'BASELINE preserves 8.1.8+ settings/time/constellation revision')

settings=txt('lib/Settings.lua'); menu=txt('lib/SettingsMenu.lua'); state=txt('lib/WeatherState.lua')
wp=txt('lib/voxel_atmos/WorldPrecip.lua'); tod=txt('lib/TimeOfDay.lua'); ce=txt('lib/CelestialEngine.lua'); ns=txt('lib/NightSky.lua')
const=txt('lib/Constellations.lua')

# Menu -> live runtime authority
check('Settings._keyRevision' in settings and 'function Settings.keyRevision' in settings,'per-setting live revision authority exists')
check('Settings._lastChangedKey' in settings and 'function Settings.lastChangedKey' in settings,'last-changed setting diagnostic exists')
check('loader.loader.modOptions' in menu,'custom menu mirrors nested current loader cache')
check('bus:emit("mod.options_changed"' in menu,'custom menu emits official option-change event when available')
check('Settings.handleOptionChanged({mod=mod.id,key=key,value=value})' in menu,'custom menu updates Weather FX synchronously')
check('AUTO / ' in menu and 'Q.tier' in menu,'AUTO quality display exposes effective live tier')

# Quality/intensity response
check('keyRevision("quality")' in wp and 'keyRevision("particleCap")' in wp,'3D precipitation budget cache invalidates on quality/cap edits')
check('_qualityRev' in wp and '_capRev' in wp,'quality revision stamps live inside existing cache without new module locals')
m=re.search(r'local CONTROL_KEYS=\{([^}]*)\}',state)
check(m is not None and all(('\"'+k+'\"') in m.group(1) for k in ('intensity','snowIntensity','fogIntensity','sandIntensity','dustIntensity')),'manual strength controls have explicit response tracking')
check('State._controlResponse=.75' in state and 'tau=math.min(tau,0.12)' in state,'manual strength edits use fast live retarget window')
check(('Manual POTATO/LOW/MEDIUM/HIGH/MAX are exact' in settings) or ('manual tiers stay exact' in settings),'QUALITY description states manual-tier authority')
check('SOFT = 45%' in settings and 'HEAVY = 150%' in settings,'INTENSITY description states actual live scale')

# Host NIGHT -> celestial state -> projected stars/constellations
check('local function hostModeOf(dn)' in tod,'host DAY/NIGHT pin reader exists')
check('dn.setting' in tod and 'mode=dn.setting:get()' in tod,'host mode uses live DayNight setting')
check('dn.T[mode]' in tod and 'dialToHours' in tod,'explicit host pins map through authored host dial positions')
check('TOD.hostMode=hostMode' in tod,'host mode is published into TimeOfDay state')
check('if hostMode then key=key.."|host:"' in ce,'celestial source key changes immediately with host mode')
check('Engine._state.rawHour~=nil' in ce and 'abs(hourDelta(raw,old))>=2.0' in ce,'celestial state resync is limited to real source/multi-hour changes')
check('TOD.hostMode=="night"' in ns,'NightSky recognizes explicit host NIGHT')
check('NightSky._nightVis=target' in ns,'explicit NIGHT snaps the deep-sky envelope to visible target')
check('TOD.hostMode=="day"' in ns and 'NightSky._nightVis=0' in ns,'explicit DAY immediately suppresses deep sky')

# Roll back only the disliked 8.1.7 batch.
check('POKEMON_CONSTELLATION_ATLAS_EXACT_TRACE_2026_09_03' in const and const.count('atlasExact=true')==14,'8.1.13 approved atlas high-detail constellation source remains active')
check('USER_KANTO_JOHTO_SPRITE_TRACE_2026_09_02' not in const,'8.1.7 full-dex compact trace batch is removed')
check('POKEMON_ORDER' not in const and 'DEX12_PACKED' not in const,'8.1.7 generated full-dex metadata/packed traces are removed')
order_m=re.search(r'local ORDER=\{([^\n]+)\}',const)
order=re.findall(r'"([A-Za-z0-9]+)"',order_m.group(1) if order_m else '')
check(len(order)==25 and len(set(order))==25,'retained constellation catalogue is exactly 25 unique subjects')
for name in ('Charmander','Squirtle','Bulbasaur','Pikachu','Jigglypuff','PokeBall'):
    check(order.count(name)==1,f'{name} remains exactly once after rollback')

print(f'8.1.8+ settings/time/constellation contract: {passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
