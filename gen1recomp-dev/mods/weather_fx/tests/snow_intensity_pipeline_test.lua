local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1;print('FAIL '..name) end end

local Types=assert(loadfile(ROOT..'lib/Types.lua'))()
local snow=Types.get('SNOW_LIGHT').ch
local bliz=Types.get('BLIZZARD').ch
check(math.abs((snow.snow or 0)-3.60)<1e-9,'SNOW authored density restored to 3.60')
check(math.abs((bliz.snow or 0)-5.50)<1e-9,'BLIZZARD authored density restored to 5.50')
check((bliz.snow or 0)>(snow.snow or 0),'Blizzard remains denser than Snow')

local st=assert(io.open(ROOT..'lib/WeatherState.lua','rb')):read('*a')
check(st:find('"snowIntensity"',1,true)~=nil,'WeatherState tracks SNOW INTENSITY revisions')
check(st:find('if key == "snow" then',1,true)~=nil and st:find('snowMul',1,true)~=nil,'WeatherState applies dedicated snow multiplier')
check(st:find('math.min(45.0, goal * scale * snowMul)',1,true)~=nil,'snow channel is no longer trapped by generic 2.0 amount cap')

local budget={worldPrecip=.04,worldRadiusCap=96,worldRainCap=20000,worldSnowCap=50000,worldBlizzardCap=100000,
  worldHailCap=20000,worldSandCap=20000,worldDebrisCap=20000,worldAshCap=20000,splash=0,snowPackDrawCap=0,footDrawCap=0}
local function build()
  local V={weatherFxId='SNOW_LIGHT'}
  V.safeCall=pcall
  function V.require(name)
    if name=='Quality' then return {budget=function() return budget end} end
    if name=='Settings' then return {isFirstPerson=function() return false end,is=function() return false end} end
    if name=='Scene' then return {now={visible='world'}} end
    if name=='WindEngine' then return {vector=function() return 1,0 end} end
    if name=='Types' then return Types end
    error('missing '..tostring(name),0)
  end
  return assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V),V
end
local function count(id,value,resolved,explicitOff)
  local W,V=build();V.weatherFxId=id
  local w={wxId=id,snowIntensity=value,snowWind=.7,_wxChannelsResolved=resolved==true,_snowExplicitOff=explicitOff==true}
  W.update(1/60,{0,24,0},w,{})
  return (W.liveCounts({}).snow or 0),w
end
local off=count('SNOW_LIGHT',0,true,false)
local normal=count('SNOW_LIGHT',3.60,true,false)
local high=count('SNOW_LIGHT',7.20,true,false)
local maxed=count('SNOW_LIGHT',18.0,true,false)
check(off==0,'authoritative SNOW INTENSITY OFF produces zero 3D snow')
check(normal>0 and high>normal and maxed>high,'3D snowfall counts rise with 100% < 200% < 500% snow intensity')
local bc=count('BLIZZARD',5.50,true,false)
check(bc>normal,'Blizzard live 3D snowfall is denser than Snow')
local compatOff=count('SNOW_LIGHT',0,false,true)
check(compatOff==0,'compatibility fallback cannot repair explicit SNOW INTENSITY OFF')
local compatOn=count('SNOW_LIGHT',0,false,false)
check(compatOn>0,'legacy host with missing live channel still recovers authored snow')

local wp=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
check(wp:find('min(5.0, (weather._populationStrengthFixed and (snowI/weather._populationStrength) or snowI) / 1.9)',1,true)~=nil and wp:find('snowCap=max(0,floor(snowCap*weather._populationStrength+0.5))',1,true)~=nil,'WorldPrecip preserves stronger snow density while fixed WEATHER STRENGTH scales the real population budget')
check(wp:find('weather._snowExplicitOff',1,true)~=nil,'WorldPrecip carries explicit snow-off authority')
print(('snow intensity pipeline: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
