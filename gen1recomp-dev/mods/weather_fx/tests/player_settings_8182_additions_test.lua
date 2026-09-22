-- Weather FX 8.1.82: six requested player-control capabilities.
local envRoot=os.getenv and os.getenv('WFX_TEST_ROOT') or nil
if envRoot=='' then envRoot=nil end
local ROOT=envRoot or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end
if ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(rel)local f=assert(io.open(ROOT..rel,'rb'));local s=f:read('*a');f:close();return s end
local values={}
local cache={}
local V={mod={id='weather_fx',options={get=function(_,k)return values[k]end},events={on=function()end},log={warn=function()end,info=function()end}}}
function V.require(n)
  if cache[n] then return cache[n] end
  if n=='Types' then local t={PINNED={}};function t.get()return nil end;cache[n]=t;return t end
  if n=='WeatherState' then local w={LEVEL_IDS={false,'AUTO'}};cache[n]=w;return w end
  local f=assert(loadfile(ROOT..'lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m
end
V.safeCall=pcall
local S=V.require('Settings')
local function call(name)
  local f=S[name];if type(f)~='function' then return nil end
  local ok,a,b=pcall(f);if not ok then return nil end;return a,b
end
local manifest=read('manifest.json')
local ma,mi,mp=manifest:match('\"version\"%s*:%s*\"(%d+)%.(%d+)%.(%d+)\"');ma,mi,mp=tonumber(ma) or 0,tonumber(mi) or 0,tonumber(mp) or 0;ck(ma>8 or (ma==8 and (mi>1 or (mi==1 and mp>=82))),'manifest preserves 8.1.82+ player-control baseline')
ck(#S.SCHEMA==78,'schema has 78 settings after RAVE controls are removed')
local by={};for _,r in ipairs(S.SCHEMA)do by[r.key]=r end
local expected={'lightningFrequency','tornadoDuration','cloudDensity','nightSkyBrightness','screenEffects','puddles'}
for _,k in ipairs(expected)do ck(by[k]~=nil,k..' is player-facing') end
ck(by.lightningFrequency and by.lightningFrequency.default=='normal','LIGHTNING FREQUENCY default preserves authored cadence')
ck(by.tornadoDuration and by.tornadoDuration.default=='normal','TORNADO DURATION default preserves authored roam time')
ck(by.cloudDensity and by.cloudDensity.default=='normal','CLOUD DENSITY default preserves authored cloud field')
ck(by.nightSkyBrightness and by.nightSkyBrightness.default=='normal','NIGHT SKY BRIGHTNESS default preserves authored sky')
ck(by.screenEffects and by.screenEffects.default=='full','WEATHER SCREEN EFFECTS default preserves full 8.1.81 presentation')
ck(by.puddles and by.puddles.default=='config','WET GROUND still honors installed config by default')
local puddleVals={};for _,c in ipairs((by.puddles and by.puddles.choices) or {})do puddleVals[c[2]]=true end
ck(puddleVals.config and puddleVals.off and puddleVals.low and puddleVals.on and puddleVals.high,'WET GROUND exposes DEFAULT/OFF/LOW/NORMAL/HIGH and keeps legacy on token')
local function set(k,v) values[k]=v end
set('lightningFrequency','rare');ck(call('lightningFrequencyScale')==.45,'lightning rare scale')
set('lightningFrequency','normal');ck(call('lightningFrequencyScale')==1,'lightning normal exact no-op')
set('lightningFrequency','extreme');ck(call('lightningFrequencyScale')==2.25,'lightning extreme scale')
set('tornadoDuration','short');ck(call('tornadoDurationScale')==.5,'tornado short scale')
set('tornadoDuration','normal');ck(call('tornadoDurationScale')==1,'tornado normal exact no-op')
set('tornadoDuration','long');ck(call('tornadoDurationScale')==1.75,'tornado long scale')
set('cloudDensity','low');ck(call('cloudDensityScale')==.72 and call('cloudDensityGateBias')==.14,'cloud low changes puffs and occupancy')
set('cloudDensity','normal');ck(call('cloudDensityScale')==1 and call('cloudDensityGateBias')==0,'cloud normal exact no-op')
set('cloudDensity','veryhigh');ck(call('cloudDensityScale')==1.45 and call('cloudDensityGateBias')==-.14,'cloud very high changes puffs and occupancy')
set('nightSkyBrightness','low');ck(call('nightSkyBrightnessScale')==.65,'night sky low scale')
set('nightSkyBrightness','normal');ck(call('nightSkyBrightnessScale')==1,'night sky normal exact no-op')
set('nightSkyBrightness','high');ck(call('nightSkyBrightnessScale')==1.3,'night sky high scale')
set('screenEffects','off');ck(call('screenEffectsScale')==0,'screen effects off scale')
set('screenEffects','reduced');ck(call('screenEffectsScale')==.5,'screen effects reduced scale')
set('screenEffects','full');ck(call('screenEffectsScale')==1,'screen effects full exact no-op')
set('puddles','off');ck(call('puddleAmountScale')==0,'wet ground off scale')
set('puddles','low');ck(call('puddleAmountScale')==.5,'wet ground low scale')
set('puddles','on');ck(call('puddleAmountScale')==1,'wet ground normal legacy token exact no-op')
set('puddles','high');ck(call('puddleAmountScale')==1.35,'wet ground high scale')
-- Exactly one submenu per row.
local grouped={};local dup=false
for _,g in ipairs(S.GROUPS or {})do for _,k in ipairs(g.keys or {})do if grouped[k] then dup=true end;grouped[k]=true end end
local all=true;for _,r in ipairs(S.SCHEMA)do if not grouped[r.key] then all=false end end
ck(all and not dup,'all 78 settings appear in exactly one submenu')
-- Runtime ownership / non-leak contracts.
local draw=read('lib/Draw.lua'); local cells=read('lib/StormCells.lua'); local tor=read('lib/Tornado.lua')
local atmos=read('lib/voxel_atmos/CinematicAtmos.lua'); local dr=read('lib/DramalessAtmos.lua'); local sky=read('lib/NightSky.lua'); local battle=read('lib/BattleDraw.lua'); local cfg=read('lib/Config.lua')
ck(draw:find('Settings.lightningFrequencyScale',1,true)~=nil and draw:find('strikeRate = (tonumber(strikeRate) or 0) * lightningFrequency',1,true)~=nil,'main lightning scheduler consumes LIGHTNING FREQUENCY')
ck(cells:find('lightningFrequencyScale()',1,true)~=nil and cells:find('c.nextStrike=',1,true)~=nil,'regional storm cells consume LIGHTNING FREQUENCY')
ck(tor:find('roamFor=math.max(30,(tonumber(c.roamSeconds) or 180)*durationScale)',1,true)~=nil,'TORNADO DURATION scales mature roam timer')
ck(tor:find('formation=math.max(2,tonumber(c.formationSeconds) or 8)',1,true)~=nil and tor:find('ropeFor=math.max(3,tonumber(c.ropeSeconds) or 12)',1,true)~=nil,'tornado formation/descent and rope dissipation timers remain unscaled')
ck(atmos:find('cloudDensityScale',1,true)~=nil and atmos:find('gateAt+cloudGateBias',1,true)~=nil and atmos:find('puffs*cloudDensityScale',1,true)~=nil,'CLOUD DENSITY controls occupancy and puff population')
ck(atmos:find('rainIntensity) or 0.0',1,true)~=nil,'cloud density does not replace precipitation authority')
local starUses=select(2,sky:gsub('starScaleNow%(%)[^\n]-_nightSkyBrightnessScale%(%)[^\n]-',''))
ck(starUses>=3,'NIGHT SKY BRIGHTNESS reaches world, 2D and projected star/planet paths')
ck(sky:find('mwVis*hf*q[4]*NightSky._nightSkyBrightnessScale()',1,true)~=nil,'NIGHT SKY BRIGHTNESS reaches Milky Way')
ck(select(2,sky:gsub('constellationVisibility%(nightVis%)[^\n]-_nightSkyBrightnessScale',''))>=2,'NIGHT SKY BRIGHTNESS reaches world and projected constellations')
ck(not sky:find('bodyAlpha%s*=%s*bodyAlpha%s*%*%s*NightSky%._nightSkyBrightnessScale'),'night sky setting does not alter sun/moon body shader alpha')
ck(draw:find('Settings.puddleAmountScale',1,true)~=nil and atmos:find('CinematicAtmos._puddleAmountScale()',1,true)~=nil,'WET GROUND amount reaches 2D and 3D visible puddles')
ck(cfg:find('pv=="low" or pv=="on" or pv=="high"',1,true)~=nil,'WET GROUND LOW/NORMAL/HIGH enable visual system while preserving config/off semantics')
ck(draw:find('Settings.screenEffectsScale',1,true)~=nil and battle:find('Settings.screenEffectsScale',1,true)~=nil,'WEATHER SCREEN EFFECTS reaches overworld and battle screen presentation')
ck(dr:find('screenEffectsScale',1,true)~=nil and not atmos:find('screenEffectsScale',1,true),'WEATHER SCREEN EFFECTS scales 3D camera optics without attenuating physical CinematicAtmos weather')
ck(draw:find('filtered2dPrecipChannels',1,true)~=nil,'screen effects setting leaves precipitation ownership path intact')
print(string.format('8.1.82 player settings additions: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
