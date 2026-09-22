-- Manual intensity dials should feel like controls, not like waiting for a new
-- weather front. Natural weather onset keeps its long TAUs; an explicit menu
-- edit must materially retarget the live amount channels in < 1 second.
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end
local mod={save={set=function() end,get=function(self,k,d) return d end},log={warn=function() end}}
local V={mod=mod}
local Types=assert(loadfile('lib/Types.lua'))(V)
local cfg={force='RAIN_HEAVY',bias={},transitionSeconds=3.2}
local Config={get=function() return cfg end,weatherEnabled=function() return true end,tuningFor=function() return {weight=1,intensity=1,speed=1} end,locationFor=function() end}
local choice='normal';local mul=1;local rev={intensity=0,fogIntensity=0,sandIntensity=0,dustIntensity=0}
local Settings={
 syncWeatherFromLadder=function() end,debugRain=function() return false end,speedScale=function() return 1 end,alwaysWeather=function() end,
 exoticScale=function() return 1 end,is=function() return true end,intensity=function() return mul end,
 get=function(k) if k=='intensity' then return choice end return nil end,keyRevision=function(k) return rev[k] or 0 end,
 fogIntensity=function() return 1 end,fogOff=function() return false end,sandIntensity=function() return 1 end,dustIntensity=function() return 1 end,
 sandHaze=function() return 1 end,dustHaze=function() return 1 end,CHANNEL_FAMILY={},AUTO_FAMILIES={},autoScale=function() return 1 end,
}
local TOD={isNight=function() return false end,daylight=function() return 1 end}
local Seasons={multiplier=function() return 1 end}
local Fronts={update=function() end,weatherFor=function() end,persist=function() end,restore=function() end,snapshot=function() return {} end}
local Psystorm={weatherFor=function() end}
local Legendary={update=function() end,tick=function() end}
function V.require(n)
 local t={Types=Types,Settings=Settings,Config=Config,TimeOfDay=TOD,Seasons=Seasons,Fronts=Fronts,Psystorm=Psystorm,Legendary=Legendary,Harden={}}
 if t[n] then return t[n] end;error('missing '..tostring(n),0)
end
local S=assert(loadfile('lib/WeatherState.lua'))(V)
S._sessionStart=false;S._needOutdoorStart=false
for _=1,240 do S.update(.05,1,'ROUTE_1',false) end
local normal=S.ch.rain or 0
check(normal>.5,'normal rain reaches steady visible strength')
choice='soft';mul=.45;rev.intensity=rev.intensity+1
for _=1,7 do S.update(.05,1,'ROUTE_1',false) end
local soft=S.ch.rain or 0
check(soft<normal*.65,'SOFT manual edit visibly reduces live rain within 0.35s')
choice='heavy';mul=1.5;rev.intensity=rev.intensity+1
for _=1,7 do S.update(.05,1,'ROUTE_1',false) end
local heavy=S.ch.rain or 0
check(heavy>soft*1.8,'HEAVY manual edit visibly raises live rain within 0.35s')
check(heavy>normal,'HEAVY exceeds NORMAL live rain strength')
print(('intensity control response: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
