local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function ck(v,msg) if v then passed=passed+1;print('PASS '..msg) else failed=failed+1;print('FAIL '..msg) end end
local Types=assert(loadfile(ROOT..'lib/Types.lua'))()
local values={always='RAIN_HEAVY',weatherPresentation='3d'}
local mod={id='weather_fx',options={define=function() return true end,get=function(self,k) return values[k] end},events={on=function() end},log={info=function() end,warn=function() end}}
local battle={_startedIndoors=false}
local Scene={now={visible='world',outdoor=true,indoors=false,mapId='ROUTE_1'}}
local V={mod=mod,weatherFxId='RAIN_HEAVY',weatherFxChannels={rain=1,dim=.55,veil=.12,gust=.2},weatherFxSpatialCloud=1,weatherFxSpatialStrength=1,weatherFxSpatialLocalized=false}
local S
local ForestAtmos={time=4,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local generic={}
function V.require(n)
  if n=='Types' then return Types end
  if n=='Settings' then return S end
  if n=='WeatherState' then return {LEVEL_IDS={false,'AUTO','CYCLE'},id='RAIN_HEAVY',level=1,ch=V.weatherFxChannels} end
  if n=='Battle' then return battle end
  if n=='Scene' then return Scene end
  if n=='DayNight' then return {tint=function() return {1,1,1} end,isCanopy=function() return false end,isNight=function() return false end,time=function() return 12 end,mix=function() return {day=1} end} end
  if n=='WeatherSetting' then return {new=function() return {get=function() return 'full' end,setValue=function() end} end} end
  if n=='ForestAtmos' then return ForestAtmos end
  if n=='TimeOfDay' then return {isNight=function() return false end,daylight=function() return 1 end} end
  if n=='MesoscaleField' then return {ready=function() return false end} end
  if n=='PerformanceGovernor' then return {scale=function() return 1 end} end
  if n=='Quality' then return {budget=function() return {worldPrecip=1} end} end
  if n=='WindEngine' then return {peek=function() return {x=.7,z=-.3,envelope=1,advectX=12,advectZ=-5} end} end
  if n=='DistantWeather' then return {items=function() return {},0 end} end
  return generic
end
V.safeCall=pcall
S=assert(loadfile(ROOT..'lib/Settings.lua'))(V);S.define()
local Atmos=assert(loadfile(ROOT..'lib/DramalessAtmos.lua'))(V)
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local hasResolve=type(Atmos._resolveWeatherOutdoor)=='function'
ck(hasResolve,'3D atmosphere exposes battle sky continuity resolver')
if not hasResolve then Atmos._resolveWeatherOutdoor=function(Scene) return Scene and Scene.now and Scene.now.outdoor and true or false end end

Atmos._lastOutdoor=true
Scene.now.visible='world';Scene.now.outdoor=true;battle._startedIndoors=false
ck(Atmos._resolveWeatherOutdoor(Scene)==true,'outdoor overworld establishes sky authority')

-- Reproduce the reported host transition: battle state claims outdoor=false even
-- though the voxel world remains the rendered outdoor battle background.
Scene.now.visible='battle';Scene.now.outdoor=false
local carry=Atmos._resolveWeatherOutdoor(Scene)
ck(carry==true,'3D battle carries pre-battle outdoor authority despite transient battle outdoor=false')
local f=C.frame(nil,carry)
ck(type(f)=='table','carried outdoor authority keeps CinematicAtmos frame alive in battle')
ck(f and f.weather and (tonumber(f.weather.rainIntensity) or 0)>.5,'3D battle frame retains active rain intensity from overworld weather')
ck(f and f.weather and tostring(f.weather.wxId)=='RAIN_HEAVY','3D battle frame retains the selected overworld weather identity')

-- A direct false proves this is the exact gate that used to erase 3D battle rain.
ck(C.frame(nil,false)==nil,'without carried sky authority the same 3D rain frame is rejected')

-- Indoor/cave starts must stay dry even if the last outdoor frame was true.
Atmos._wasBattleScene=false;Atmos._battleOutdoorCarry=nil;Atmos._lastOutdoor=true
Scene.now.visible='battle';Scene.now.outdoor=false;battle._startedIndoors=true
local indoor=Atmos._resolveWeatherOutdoor(Scene)
ck(indoor==false,'battle that actually started indoors does not inherit outdoor weather')
ck(C.frame(nil,indoor)==nil,'indoor battle still rejects outdoor 3D precipitation')

-- Leaving battle clears the carry and resumes live Scene.outdoor authority.
Scene.now.visible='world';Scene.now.outdoor=false;battle._startedIndoors=false
ck(Atmos._resolveWeatherOutdoor(Scene)==false,'leaving battle returns to live overworld outdoor authority')
ck(Atmos._battleOutdoorCarry==nil,'battle outdoor carry is cleared after battle')

local fh=assert(io.open(ROOT..'lib/DramalessAtmos.lua','r'));local src=fh:read('*a');fh:close()
ck(src:find('Carry the last proven pre%-battle sky authority')~=nil,'source documents the battle sky continuity contract')
ck(src:find('Atmos%._lastOutdoor=resolveWeatherOutdoor%(Scene%)')~=nil,'runtime update uses carried battle sky authority')
print(('3D battle weather persistence 8.1.87: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
