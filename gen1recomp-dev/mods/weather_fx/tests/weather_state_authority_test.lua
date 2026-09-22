local passed,failed=0,0
local function check(ok,name)
  if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end
end
local mod={save={_d={},set=function(self,k,v) self._d[k]=v end,get=function(self,k,d) local v=self._d[k]; if v==nil then return d end; return v end},log={warn=function() end}}
local V={mod=mod}
local Types=assert(loadfile('lib/Types.lua'))(V)
local cfg={force=nil,bias={},transitionSeconds=3.2,maxParticles=10000}
local loc=nil
local Config={
  get=function() return cfg end,
  weatherEnabled=function() return true end,
  tuningFor=function() return {weight=1,intensity=1,speed=1} end,
  locationFor=function(mapId,indoors) if loc and loc.map==mapId then return {weather=loc.weather,chance=1} end end,
}
local always=nil
local exoticScale=1
local menuIntensity=1
local intensityChoice='100'
local Settings={
  syncWeatherFromLadder=function() end,debugRain=function() return false end,
  speedScale=function() return 1 end,alwaysWeather=function() return always end,
  exoticScale=function() return exoticScale end,is=function() return true end,intensity=function() return menuIntensity end,
  get=function(k) if k=='intensity' then return intensityChoice end return nil end,
  fogIntensity=function() return 1 end,fogOff=function() return false end,
  sandIntensity=function() return 1 end,dustIntensity=function() return 1 end,
  sandHaze=function() return 1 end,dustHaze=function() return 1 end,
  CHANNEL_FAMILY={},AUTO_FAMILIES={},autoScale=function() return 1 end,
}
local TOD={isNight=function() return false end,daylight=function() return 1 end}
local Seasons={multiplier=function() return 1 end}
local Fronts={update=function() end,weatherFor=function() return nil end,persist=function() end,restore=function() end,snapshot=function() return {} end}
local Psystorm={weatherFor=function() return nil end}
local Legendary={update=function() return nil end,tick=function() end}
local Harden={}
function V.require(name)
  local t={Types=Types,Settings=Settings,Config=Config,TimeOfDay=TOD,Seasons=Seasons,Fronts=Fronts,Psystorm=Psystorm,Legendary=Legendary,Harden=Harden}
  if t[name] then return t[name] end
  error('unexpected require '..tostring(name))
end
local S=assert(loadfile('lib/WeatherState.lua'))(V)

-- OFF really zeroes active channels and stops elapsed time.
S.ch.rain=1; S.ch.fog=1; S.dirty=true; S.elapsed=5
S.update(0.2,0,'ROUTE_1',false)
check(S.ch.rain==0 and S.ch.fog==0,'OFF clears visual weather channels')
check(S.elapsed==5,'OFF stops weather clock')

-- Config force is highest priority and takes effect through normal state authority.
cfg.force='STORM'; S._sessionStart=true; S._needOutdoorStart=true
S.update(0.1,1,'ROUTE_1',false)
check(S.id=='STORM','config force pins active weather')
check(S.pinnedBy=='config' or S.pinnedBy=='force','config force reports authority')
-- A force introduced while already running must be hard authority, not a soft AUTO handoff.
S._sessionStart=false; S._needOutdoorStart=false; S.id='CLEAR'; S.softTo=nil; cfg.force='STORM'
S.update(0.1,1,'ROUTE_1',false)
check(S.id=='STORM' and S.softTo==nil,'live config force hard-pins immediately')

-- A newly selected manual rain weather must become visibly active in the same
-- menu interaction window. AUTO/front evolution remains slow; this fast path is
-- only armed by hard manual/config authority changes.
cfg.force='RAIN_LIGHT'; S.id='CLEAR'; S.softTo=nil; S._sessionStart=false; S._needOutdoorStart=false
for k in pairs(S.ch) do S.ch[k]=0 end
S.update(0.1,1,'ROUTE_1',false)
check((S.ch.rain or 0)>0.40,'manual normal RAIN produces substantial live rain within 0.1 seconds')
cfg.force='HEAVY_RAIN'; S.id='RAIN_LIGHT'; S.softTo=nil
S.ch.strike=0; S.ch.rain=0
S.update(0.1,1,'ROUTE_1',false)
check((S.ch.rain or 0)>0.65,'manual Primal Heavy Rain produces strong live rain immediately')
check((S.ch.strike or 0)>2.5,'manual Primal Heavy Rain arms lightning/thunder authority immediately')

-- Mod-menu always weather overrides automatic selection when file force is absent.
cfg.force=nil; always='SNOW_LIGHT'; S._sessionStart=false
S.update(0.1,1,'ROUTE_1',false)
check(S.id=='SNOW_LIGHT','WEATHER menu pin is authoritative')
check(S.pinnedBy=='always','menu pin reports authority')

-- OPTIONS ladder pin outranks location defaults.
always=nil; loc={map='LAVENDER_TOWN',weather='FOG'}
S.update(0.1,4,'LAVENDER_TOWN',false) -- level 4 => SUNNY (OFF/AUTO/CYCLE/CLEAR/SUNNY labels translated as level offset)
check(S.id=='SUNNY','explicit OPTIONS ladder weather outranks location override')
check(S.mode=='PIN' and S.pinnedBy=='menu','ladder pin enters PIN mode')

-- AUTO location override parks the global spell clock and begins a soft handoff.
S.id='CLEAR'; S.softTo=nil; S.left=99
S.update(0.1,1,'LAVENDER_TOWN',false)
check(S.softTo=='FOG','AUTO location override drives local weather')
check(S.left==99,'location override parks AUTO clock')

-- CYCLE is one world-persistent spell clock. Map-specific location overrides
-- must not replace it when the player crosses a route/town/building boundary.
S.id='RAIN_LIGHT'; S.softTo=nil; S.softFrom=nil; S.left=20; S.cycleIndex=0
S._sessionStart=false; S._needOutdoorStart=false; S._wasIndoors=false
loc={map='LAVENDER_TOWN',weather='FOG'}
S.update(0.1,2,'ROUTE_1',false)
local cycleLeft=S.left
S.update(0.1,2,'LAVENDER_TOWN',false)
check(S.id=='RAIN_LIGHT' and S.softTo==nil,'CYCLE map crossing keeps active world weather')
check(S.pinnedBy=='cycle' and S.mode=='CYCLE','CYCLE retains authority across map change')
check(S.left<cycleLeft and S.left>19.7,'CYCLE timer advances by time rather than resetting on map entry')

-- Buildings are maps too: the cycle timer keeps running while precipitation is
-- visually gated. If it expires indoors, the world advances there and exiting
-- resumes that already-running spell instead of restoring/rerolling on the door.
loc=nil; S.left=0.15; S.softTo=nil; S.softFrom=nil
S.update(0.1,2,'HOUSE',true)
S.update(0.1,2,'HOUSE',true)
local indoorCycleId,indoorCycleLeft=S.id,S.left
check(indoorCycleLeft>1,'CYCLE timer can expire and rearm while indoors')
S.update(0.1,2,'ROUTE_1',false)
check(S.id==indoorCycleId and S.left<=indoorCycleLeft,'leaving building preserves current CYCLE spell/timer')

-- Indoor gate removes spatial precipitation but remembers current weather.
loc=nil; S.softTo=nil; S.id='RAIN_HEAVY'; S.ch.rain=1; S.ch.fog=1
S.update(0.1,1,'HOUSE',true)
check(S._wasIndoors==true and S._pausedWeatherId=='RAIN_HEAVY','indoor gate remembers outside weather')
check((S.ch.rain or 0)==0 and (S.ch.fog or 0)==0,'indoor gate removes precipitation/fog channels')
S.update(0.1,1,'ROUTE_1',false)
check(S._wasIndoors==false and S.id=='RAIN_HEAVY','short indoor stay resumes same weather on exit')


-- RARE WEATHER OFF is a catalogue-wide AUTO gate, even on geography that
-- normally boosts frozen/sandy families (e.g. Indigo Plateau).
cfg.force=nil; always=nil; loc=nil; exoticScale=0
love = { math = { random = function() return 0.5 end } }
for i=0,199 do
  love.math.random = function() return (i + 0.5) / 200 end
  local picked=S.pick('INDIGO_PLATEAU')
  local pd=Types.get(picked)
  check(not (pd and (pd.frozen or pd.sandy)), 'RARE WEATHER OFF excludes exotic AUTO pick '..tostring(i))
end
exoticScale=1

-- Fixed global INTENSITY must not leak into fog/veil. FOG INTENSITY owns
-- those channels; weather-specific tuning is identical between these runs.
local function fogStep(intensity, choice)
  cfg.force='FOG'; always=nil; loc=nil
  menuIntensity=intensity; intensityChoice=choice
  S.id='FOG'; S.softTo=nil; S.softT=0; S.softDur=0; S._sessionStart=false; S._needOutdoorStart=false
  S._wasIndoors=false; S._pausedWeatherId=nil; S.dirty=true; S.elapsed=0
  for k in pairs(S.ch) do S.ch[k]=0 end
  S.update(0.1,1,'ROUTE_1',false)
  return S.ch.fog or 0, S.ch.veil or 0, S.ch.rain or 0
end
local fogSoft,veilSoft=fogStep(0.6,'soft')
local fogHeavy,veilHeavy=fogStep(1.35,'heavy')
check(math.abs(fogSoft-fogHeavy)<1e-9 and math.abs(veilSoft-veilHeavy)<1e-9,
  'fixed INTENSITY does not alter fog/veil channels')
menuIntensity=1; intensityChoice='100'; cfg.force=nil

-- Persistence degrades unknown historical IDs safely to CLEAR.
mod.save._d.id='NO_SUCH_WEATHER'; mod.save._d.left=42
S.restore()
check(S.id=='CLEAR','unknown saved weather degrades safely to CLEAR')
check(S.left==42 or S._sessionStart==true,'saved dwell state restores without corrupting state machine')

print(('weather state authority: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
