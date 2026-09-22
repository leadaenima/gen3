-- Global INTENSITY must materially change live 3D particle populations.
local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end
local budget={worldPrecip=.06,worldRadiusCap=96,worldRainCap=10000,worldSnowCap=10000,worldBlizzardCap=10000,
  worldHailCap=10000,worldSandCap=10000,worldDebrisCap=10000,worldAshCap=10000,splash=0,snowPackDrawCap=0,footDrawCap=0}
local function build()
  local V={weatherFxId='CUSTOM'}
  function V.require(name)
    if name=='Quality' then return {budget=function() return budget end} end
    if name=='Settings' then return {isFirstPerson=function() return false end,is=function() return false end} end
    if name=='Scene' then return {now={visible='world'}} end
    if name=='WindEngine' then return {vector=function() return 1,0 end} end
    error('no module '..tostring(name),0)
  end
  return assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
end
local function measure(scale)
  local W=build()
  W.update(1/60,{0,24,0},{wxId='CUSTOM',rainIntensity=scale,snowIntensity=scale,hailIntensity=scale,
    sandIntensity=scale,ashIntensity=scale,debrisIntensity=scale,rainWind=1,snowWind=1},{})
  return W.liveCounts({})
end
local soft,normal,heavy=measure(.45),measure(1.0),measure(1.50)
for _,k in ipairs({'rain','snow','hail','sand','debris','ash'}) do
  check((soft[k] or 0)<(normal[k] or 0) and (normal[k] or 0)<(heavy[k] or 0),
    'INTENSITY produces SOFT < NORMAL < HEAVY live '..k..' counts')
end
-- Static bridge proof: CinematicAtmos applies the menu multiplier to every 3D
-- family before WorldPrecip receives the weather bag.
local f=assert(io.open('lib/voxel_atmos/CinematicAtmos.lua','rb')); local src=f:read('*a'); f:close()
for _,field in ipairs({'rainIntensity','snowIntensity','hailIntensity','sandIntensity','ashIntensity','debrisIntensity'}) do
  check(src:find('weather.'..field..' = weather.'..field..' * im',1,true)~=nil,
    'CinematicAtmos forwards INTENSITY into '..field)
end

-- Named-weather compatibility floors must NOT erase the multiplier once the
-- authoritative 3D atmosphere has resolved the bag. This was the real bug that
-- made SOFT snow/sand/hail/ash/leaves jump back toward normal strength.
local function named(id,field,value,key)
  local W=build(); local w={wxId=id,_wxChannelsResolved=true,rainWind=1,snowWind=1}
  w[field]=value; W.update(1/60,{0,24,0},w,{}); return W.liveCounts({})[key] or 0
end
check(named('SNOW','snowIntensity',1.9*.45,'snow') < named('SNOW','snowIntensity',1.9,'snow'),
  'SOFT resolved SNOW is not restored to authored normal floor')
check(named('HAIL','hailIntensity',1.25*.45,'hail') < named('HAIL','hailIntensity',1.25,'hail'),
  'SOFT resolved HAIL is not restored to authored normal floor')
check(named('SANDSTORM','sandIntensity',2.35*.45,'sand') < named('SANDSTORM','sandIntensity',2.35,'sand'),
  'SOFT resolved SANDSTORM is not restored to authored normal floor')
check(named('ASHFALL','ashIntensity',1.45*.45,'ash') < named('ASHFALL','ashIntensity',1.45,'ash'),
  'SOFT resolved ASHFALL is not restored to authored normal floor')
check(named('GALE','debrisIntensity',1.15*.45,'debris') < named('GALE','debrisIntensity',1.15,'debris'),
  'SOFT resolved debris/leaves are not restored to authored normal floor')
print(('intensity live 3D: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
