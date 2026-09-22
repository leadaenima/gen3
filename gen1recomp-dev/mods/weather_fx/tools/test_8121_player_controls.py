from pathlib import Path
import re,sys
R=Path(__file__).resolve().parents[1]
S=(R/'lib/Settings.lua').read_text(); W=(R/'lib/WeatherState.lua').read_text(); C=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); WP=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text(); T=(R/'lib/Tornado.lua').read_text(); A=(R/'lib/Audio.lua').read_text(); D=(R/'lib/Draw.lua').read_text(); B=(R/'lib/BattleDraw.lua').read_text(); L=(R/'lib/Lightning.lua').read_text(); WL=(R/'lib/voxel_atmos/WorldLighting.lua').read_text(); M=(R/'lib/SettingsMenu.lua').read_text()
ok=0;bad=0
def ck(x,msg):
 global ok,bad
 if x: ok+=1; print('PASS',msg)
 else: bad+=1; print('FAIL',msg)
rows={k: re.search(r'key = "'+re.escape(k)+r'", label = "([^"]+)".*?  },',S,re.S) for k in ['rainIntensity','windIntensity','lightningFlash','stormDarkness','tornadoPickup','thunderVolume']}
for k,m in rows.items(): ck(m is not None,k+' setting row exists')
ck(all(x in S for x in ['function Settings.rainIntensity','function Settings.windIntensity','function Settings.lightningFlashScale','function Settings.stormDarknessScale','function Settings.tornadoPickupChance','function Settings.thunderVolumeScale']),'all six typed runtime helpers exist')
ck('key == "rain"' in W and 'goal * scale * rainMul' in W,'rain intensity reaches live rain amount')
ck('rainSpeed' in W and 'rainMul' not in re.search(r'elseif key == "rainSpeed".*?elseif family',W,re.S).group(0),'rain intensity does not alter rain fall-speed channel')
ck('_rainExplicitOff = true' in C and 'if not weather._rainExplicitOff then rainI = fill' in WP and 'if weather._rainExplicitOff then rainI = 0 end' in WP,'rain OFF survives 3D compatibility recovery')
ck('key == "gust"' in W and 'Settings.windIntensity' in W,'wind intensity reaches shared gust authority')
ck('weatherLifetimeScale = Settings.speedScale' in S and 'windIntensity' not in re.search(r'local SPEED = .*?Settings.weatherLifetimeScale = Settings.speedScale',S,re.S).group(0),'wind intensity is isolated from weather lifetime')
ck('flashScale' in D and 'Lightning.flash(lightMode) * flashScale' in B,'lightning flash scale reaches 2D and battle illumination')
ck('lightningFlashScale' in C and 'lightningFlashScale' in WL,'lightning flash scale reaches 3D sky/world illumination')
ck('local weatherSettings' in C and 'weatherSettings = function()' in C and C.index('local weatherSettings') < C.index('local function lightningFlashFor'),'3D settings helper is forward-declared before lightning fallback')
ck('mode ~= "full" or not drawBolt' in L,'flash OFF can leave FULL bolt geometry independently enabled')
ck('darknessMul' in W and 'stormDarknessScale' in C and 'skyBlend' in C,'storm darkness reaches 2D channel and 3D weather sky')
ck('Settings.tornadoPickupChance' in T and 'rnd()<carryChance' in T,'tornado pickup chance reaches seeker decision')
ck('0.03' in S and '0.10' in S and '0.25' in S,'tornado pickup choices map to 3/10/25 percent')
ck(A.count('Settings.thunderVolumeScale')>=2,'thunder volume scales new and already-ringing voices')
ck('thunderDistanceGain' in A and 'indoor' in A.lower(),'thunder distance and indoor acoustic systems remain present')
ck('for _,key in ipairs(group.keys or {})' in M and 'local row=Settings.row(key)' in M,'custom in-game menu resolves every grouped setting generically')
atmo=re.search(r'\{ id="precipitation".*?keys=\{([^}]*)\}',S,re.S)
ck(atmo is not None and '"rainIntensity"' in atmo.group(1),'rain amount is in PRECIPITATION submenu')
ck('"windIntensity","windWalk"' in S,'wind strength is in WORLD & CLOUDS submenu')
storms=re.search(r'\{ id="storms".*?keys=\{([^}]*)\}',S,re.S)
ck(storms is not None and all(('"'+k+'"') in storms.group(1) for k in ('lightningFlash','stormDarkness','tornadoPickup')),
   'flash/darkness/pickup are in STORMS submenu')
ck('"thunderAudio","thunderVolume","windAudio"' in S,'thunder volume is in SOUND submenu')
print(f'8.1.21 player controls: {ok} passed, {bad} failed')
sys.exit(1 if bad else 0)
