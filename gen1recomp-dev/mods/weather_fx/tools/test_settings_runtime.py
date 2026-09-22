#!/usr/bin/env python3
"""Release gate for every user-facing Weather FX setting and two regressions.

This intentionally verifies wiring, not just that rows exist in Settings.lua.
It verifies every Weather FX core setting plus the indoor-audio regression.
WX Pokémon now lives in the separate weather_fx_wx_pokemon add-on.
"""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[1]

def read(rel): return (ROOT/rel).read_text(errors='replace')
fail=[]; passed=0
def check(ok,msg):
    global passed
    if ok:
        passed+=1; print('PASS',msg)
    else:
        fail.append(msg); print('FAIL',msg)

settings=read('lib/Settings.lua'); audio=read('lib/Audio.lua'); state=read('lib/WeatherState.lua')
enc=read('lib/Encounters.lua')
# Consumer search deliberately excludes Settings.lua itself. A helper's own
# definition is not proof that a player-facing row changes anything.
consumer_files=[p for p in (ROOT/'lib').rglob('*.lua') if p.name!='Settings.lua']
alllib='\n'.join(p.read_text(errors='replace') for p in consumer_files) + '\n' + read('main.lua')
schema=settings[settings.index('Settings.SCHEMA = {'):settings.index('-- Build the ALWAYS row')]
keys=re.findall(r'^\s{4}key\s*=\s*"([^"]+)"', schema, re.M)
expected=['quality', 'autoPerformance', 'performanceTarget', 'textureDetail', 'reflectionDetail', 'effectDistance', 'simulationDetail', 'always', 'intensity', 'rainIntensity', 'snowIntensity', 'snowAccumulation', 'weatherRenderDistance', 'fogIntensity', 'sandIntensity', 'dustIntensity', 'exotic', 'speed', 'daytime', 'seasons', 'clouds', 'cloudHeight', 'cloudDensity', 'cloudBankStyle', 'waterStyle', 'leafColor', 'snowShape', 'hemisphere', 'seasonNotify', 'battles', 'battleDamage', 'amplified', 'lightning', 'weather2dLightning', 'lightningFlash', 'lightningFrequency', 'stormDarkness', 'backdrops', 'sfx', 'splash', 'indoors', 'tornado', 'tornadoPickup', 'tornadoDuration', 'present', 'pauseMenuWeather', 'screenEffects', 'celestialRendering', 'nightSkyBrightness', 'transitionSpeed', 'fronts', 'frontStrength', 'mesoscale', 'mesoscaleStrength', 'windIntensity', 'windWalk', 'puddles', 'rainbows', 'godRays', 'npcLightning', 'npcStrikeChance', 'tornadoFrequency', 'celestialEvents', 'smoothSky', 'celestialMotion', 'timeSource', 'dayLength', 'seasonLength', 'indoorAudio', 'thunderAudio', 'thunderVolume', 'windAudio', 'weatherEncounters', 'legendaryEvents', 'followerChip', 'particleCap', 'debugRain', 'debug']
check(keys==expected, f'all 78 current settings present once and in expected order ({len(keys)})')
check(len(keys)==len(set(keys)), 'no duplicate setting keys')
labels=re.findall(r'^\s{4}key\s*=\s*"([^"]+)".*?label\s*=\s*"([^"]+)"', schema, re.M)
label_values=[v for _,v in labels]
check(len(label_values)==len(set(label_values)), 'no duplicate player-facing setting labels')
check('battleAnim' not in keys and 'Settings.get("battleAnim")' not in settings,
      'duplicate BATTLE WEATHER / WEATHER VISUALS control removed from player schema')
check('key = "weatherRenderDistance", label = "3D PRECIP DISTANCE"' in settings,
      'precipitation distance is clearly distinguished from global EFFECT DISTANCE')

# Every row must have a declared default. Every static choice row must include it.
starts=[m.start() for m in re.finditer(r'^  \{\n(?=(?:.|\n){0,900}?^\s{4}key\s*=)', schema, re.M)]
# Simpler key-position windows to next top-level row.
for i,k in enumerate(keys):
    pos=schema.find(f'key = "{k}"')
    nxt=schema.find('\n  {\n', pos+1)
    body=schema[pos:nxt if nxt!=-1 else len(schema)]
    md=re.search(r'default\s*=\s*"([^"]+)"', body)
    check(md is not None, f'{k}: default declared')
    if md and 'choices = nil' not in body:
        vals=re.findall(r'\{\s*"[^"]+"\s*,\s*"([^"]+)"\s*\}', body)
        check(md.group(1) in vals, f'{k}: default is one of its stored choice values')

# Runtime-consumer contract for every row (semantic helper path accepted).
markers={
'quality':['Settings.get("quality")'],'autoPerformance':['Settings.get("autoPerformance")'],'performanceTarget':['Settings.get("performanceTarget")'],
'textureDetail':['Settings.get("textureDetail")'],'reflectionDetail':['Settings.get("reflectionDetail")'],
'effectDistance':['Settings.get("effectDistance")'],'simulationDetail':['Settings.get("simulationDetail")'],'always':['Settings.alwaysWeather'],'intensity':['Settings.intensity'],
'rainIntensity':['Settings.rainIntensity'],
'snowIntensity':['Settings.snowIntensity'],
'snowAccumulation':['snowAccumulationEnabled'],
'fogIntensity':['Settings.fogIntensity'],'sandIntensity':['Settings.sandIntensity'],'dustIntensity':['Settings.dustIntensity'],
'exotic':['Settings.exoticScale'],'speed':['Settings.speedScale'],'daytime':['Settings.get("daytime")','Settings.is("daytime"','S.get("daytime"'],
'seasons':['Settings.get("seasons")','Settings.is("seasons"'],'clouds':['Settings.cloudsOn','S.cloudsOn','S.get("clouds")'],'leafColor':['Settings.leafColor','S.leafColor'],
'waterStyle':['Settings.weatherFxWaterEnabled','S.weatherFxWaterEnabled'],
'snowShape':['Settings.snowShape','S.snowShape'],'hemisphere':['Settings.get("hemisphere")'],'seasonNotify':['Settings.get("seasonNotify")','Settings.is("seasonNotify"'],
'battles':['Settings.battleScale'],
'battleDamage':['Settings.battleDamageOn'],'amplified':['Settings.get, "amplified"','Settings.get("amplified")'],
'lightning':['Settings.get("lightning")'],'lightningFrequency':['Settings.lightningFrequencyScale'],'backdrops':['Settings.get("backdrops")','Settings.is("backdrops"'],'sfx':['Settings.get("sfx")'],
'splash':['Settings.get("splash")','Settings.is("splash"'],'indoors':['S.get("indoors")'],'tornado':['Settings.get("tornado")','Settings.is("tornado"','S.is("tornado"'],'tornadoPickup':['Settings.tornadoPickupChance'],
'present':['Settings.force2dPresent','Settings.allow3dPresent'],'pauseMenuWeather':['Settings.get("pauseMenuWeather")'],'screenEffects':['Settings.screenEffectsScale'],
'celestialRendering':['Settings.use3dCelestial','Settings.celestialPresentMode'],'nightSkyBrightness':['NightSky._nightSkyBrightnessScale','nightSkyBrightnessScale'],
'transitionSpeed':['choice("transitionSpeed")'],'fronts':['onoff("fronts",'],'frontStrength':['choice("frontStrength")'],
'mesoscale':['onoff("mesoscale",'],'mesoscaleStrength':['choice("mesoscaleStrength")'],'windWalk':['onoff("windWalk",'],'puddles':['Settings.puddleAmountScale','choice("puddles")'],'rainbows':['onoff("rainbows",'],
'godRays':['onoff("godRays",'],'npcLightning':['onoff("npcLightning",'],'npcStrikeChance':['choice("npcStrikeChance")'],
'tornadoFrequency':['choice("tornadoFrequency")'],'celestialEvents':['onoff("celestialEvents",'],'smoothSky':['onoff("smoothSky",'],
'celestialMotion':['onoff("celestialMotion",'],'timeSource':['choice("timeSource")'],'dayLength':['choice("dayLength")'],
'seasonLength':['choice("seasonLength")'],'indoorAudio':['choice("indoorAudio")'],'thunderAudio':['onoff("thunderAudio",'],'thunderVolume':['Settings.thunderVolumeScale'],
'windAudio':['onoff("windAudio",'],'weatherEncounters':['onoff("weatherEncounters",'],'legendaryEvents':['onoff("legendaryEvents",'],
'followerChip':['onoff("followerChip",'],'particleCap':['choice("particleCap")'],
'debugRain':['Settings.debugRain'],'debug':['Settings.debugHudMode','call(Settings, "debugHudMode"']}
for k,alts in markers.items():
    check(any(a in alllib for a in alts), f'{k}: has a live runtime consumer')

# Official live option-change path, plus old-host fallback only when event absent.
check('mod.events:on("mod.options_changed"' in settings, 'settings bind documented mod.options_changed event')
check('function Settings.handleOptionChanged' in settings, 'live option-change dispatcher exists')
check('if Settings._optionsEventBound then return end' in settings, 'legacy set wrapper cannot double-fire current event path')
check('Settings._runtimeAlways = want' in settings, 'OPTIONS weather ladder has runtime authority when mod option setter is unavailable')
check('Settings._runtimeAlways = Settings.get("always")' in settings, 'mod-menu WEATHER pushes a live runtime mirror')
check('valid[row.key .. "__values"] = canonical' in settings, 'choice normalizer preserves exact declared values (including uppercase weather ids)')

# WX Pokémon split boundary: core must remain independently installable and contain no variant implementation.
check('weatherVariants' not in keys, 'core settings contain no WX POKEMON row')
check(not (ROOT/'lib/WeatherVariants.lua').exists(), 'core ships no WeatherVariants module')
check(not (ROOT/'lib/WeatherVariantsData.lua').exists(), 'core ships no WX species dataset')
check('WeatherVariants' not in read('main.lua'), 'core main has no WX variant wiring')
check('weatherVariants' not in read('config.lua'), 'core config has no WX Pokémon configuration')
check('weatherVariants' not in read('lib/Config.lua'), 'core config schema has no WX Pokémon keys')
check('WX_' in enc and 'def.weatherVariant == true' in enc, 'core encounter injector defensively excludes optional add-on species')

# Indoor sound: visuals still zeroed, but audio derives outside family from weather definition.
check('for _, key in ipairs(Types.channels) do State.ch[key] = 0 end' in state, 'indoor visual precipitation remains suppressed')
check('if indoors and not Settings.debugRain(Config) then' in state, 'DEBUG RAIN deliberately bypasses indoor channel suppression as its menu/help promises')
check('function Audio.channelForContext' in audio, 'audio has indoor/outdoor channel authority helper')
ch=re.search(r'function Audio\.channelForContext\(key\).*?\nend', audio, re.S)
if ch:
    b=ch.group(0)
    check('Scene.now.indoors' in b and 'Types.channel(cur, key)' in b, 'indoors audio reads active outside weather definition, not zeroed visual channels')
check('Audio.channelForContext("rain")' in audio and 'Audio.channelForContext("snow")' in audio and 'Audio.channelForContext("gust")' in audio,
      'rain/snow/wind beds use indoor-aware channel helper')
check('local inside = tonumber(cfg.indoors) or 0.55' in audio and 'minRetainedGain' in audio and 'inside = math.max(retained' in audio and '1 - (1 - inside) * mix' in audio,
      'indoor audio attenuation remains active with a hard 40% retained-volume floor')
check('floor = math.max(retained' in audio and 'rainHighGain = 0.55' in audio and 'windHighGain = 0.45' in audio and 'thunderHighGain = 0.40' in audio,
      'indoor low-pass preserves at least 40% high-frequency energy')
check('if sfx == "off" or sfx == false then return 0 end' in audio, 'SFX OFF remains a hard audio kill switch')
check('if Scene.now and Scene.now.indoors then return end' not in audio and 'Visual rendering is NOT audio authority' in audio and 'Audio.update follows WeatherState + Scene every frame' in audio, 'indoor/visual precipitation cannot stop authoritative real-time weather audio')


# INDOORS=TINT is a visual-only atmosphere pass: storm light/strike survive,
# falling channels do not, and the bolt itself never paints over a room.
scene=read('lib/Scene.lua')
draw=read('lib/Draw.lua')
check('if indoorMode == "tint" then return scale, false end' in scene,
      'INDOORS TINT keeps compositor alive while explicitly disabling precipitation')
check('local indoorLight = { dim = true, cool = true, warm = true, strike = true }' in state,
      'indoor state retains only storm lighting/strike channels')
check('local drawBolt = not use3dLightning() and not (Scene.now and Scene.now.indoors)' in draw,
      'indoor lightning is flash-only; no free-floating bolt is painted over rooms')

tod=read('lib/TimeOfDay.lua')
check('menuDaytimeOn' in tod and 'S.get("daytime") ~= "off"' in tod, 'TIME OF DAY OFF gates Weather FX clock/grade, not only weather bias')


main=read('main.lua')
check('local TIME_PIPELINE_ID = "weather_time_grade"' in main,
      'TIME OF DAY has a dedicated internal compositor pipeline')
check('P.setLevel(TIME_PIPELINE_ID, 1)' in main,
      'hidden TIME compositor self-enables independently of WEATHER ladder')
check('Settings.get("daytime") == "off"' in main and 'TOD.grade(Scene.now.indoors)' in main,
      'TIME compositor availability follows live TIME OF DAY setting and grade')
check('row.id == HIDDEN_TIME_ID' in main,
      'internal TIME compositor row is filtered from player OPTIONS')
check('Draw.grade' in main and main.count('Draw.grade') >= 3,
      'TIME grade has live worldPresent/present runtime call sites')

# Semantics beyond "has a consumer": these protect previously discovered
# cases where a setting was wired but did not quite do what its help promised.
check('if exotic <= 0 and (def.frozen or def.sandy) then return 0 end' in state,
      'RARE WEATHER OFF hard-excludes exotic AUTO families even on favored maps')
check('if key == "fog" or key == "veil" then' in state and 'scale = tuningIntensity * autoFamily' in state,
      'fixed INTENSITY is separated from fog/veil; FOG INTENSITY owns haze strength')
check('local gStrength = fogMul * qBoost * 0.5' in draw and 'gStrength = fogMul * math.max' not in draw,
      'legacy 2D ground-fog fallback cannot reapply global INTENSITY')
check('TOD.source = "host-passive"' in tod and 'if dn then h,hostMode=voxelHours(dn) end' in tod,
      'TIME OF DAY OFF passively follows a supported host clock for celestial alignment')
seasons=read('lib/Seasons.lua')
check('if Settings.is("seasonNotify", "off") then' in seasons and 'Seasons.notifyT = 0' in seasons,
      'SEASON NOTE OFF immediately clears a live Weather FX season banner')
sfx_pos=settings.find('key = "sfx"')
sfx_end=settings.find('\n  },', sfx_pos)
sfx_text=settings[sfx_pos:sfx_end if sfx_end != -1 else len(settings)].lower()
check('wind' in sfx_text and 'thunder' in sfx_text,
      'WEATHER VOLUME help matches the live precipitation/wind/thunder audio pipeline')


# 8.0.9 grouped in-game settings and config overlay contracts.
menu=read('lib/SettingsMenu.lua'); config=read('lib/Config.lua'); meso=read('lib/MesoscaleField.lua'); atmos=read('lib/DramalessAtmos.lua')
check('Settings.GROUPS = {' in settings and 'id="weather"' in settings and 'id="behavior"' in settings and 'id="skytime"' in settings, 'settings are grouped into clear shallow submenu categories')
group_block=settings[settings.index('Settings.GROUPS = {'):settings.index('function Settings.row')]
group_keys=re.findall(r'keys\s*=\s*\{([^}]*)\}', group_block, re.S)
grouped=[]
for body in group_keys:
    grouped.extend(re.findall(r'"([^"]+)"', body))
check(len(grouped)==len(keys) and len(set(grouped))==len(keys) and set(grouped)==set(keys), 'every player setting appears in exactly one submenu')
check('SELECT' in menu.upper() and 'help=row.help' in menu and 'drawHelp' in menu, 'in-game submenu exposes per-setting descriptions')
check('ui.options.rows' in menu and 'src.mods.ManagerState' in menu, 'Weather FX settings opener is reachable from OPTIONS and mod manager')
check('function Config.applyPlayerSettings' in config and 'default to CONFIG' in config, 'advanced menu uses config-preserving live override layer')
check('chance = 0.10, duration = 3.0' in config, 'embedded NPC lightning fallback matches shipped 10 percent / 3 second config')
check('mesoscale = { enabled = true, strength = 1.0 }' in config and 'fieldEnabled=m.enabled~=false' in meso, 'LOCAL WEATHER FIELDS setting reaches mesoscale runtime')
check('not C.visual("glare")' in atmos, 'SUN GOD RAYS setting gates strict-3D direct-sun optics')
print(f'\nsettings/runtime audit: {passed} passed, {len(fail)} failed')
if fail:
    for x in fail: print('  -',x)
    sys.exit(1)
