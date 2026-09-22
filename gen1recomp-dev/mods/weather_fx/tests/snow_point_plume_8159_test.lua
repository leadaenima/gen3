-- Weather FX 8.1.59: a local full-field snowfall must not be accompanied by
-- the perspective-compressed distant StormCell snow slab that reads as a
-- one-pixel vertical emitter. The remote slab remains visible before local
-- snow arrives; rain/fog/lightning remain under their existing owners.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end,cloudHeightScale=function() return 1.5 end}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=73.5,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local front={id=159,weather='SNOW_LIGHT',cloudWeather='SNOW_LIGHT',x=1000,z=0,bankX=430,bankZ=0,
  rx=650,rz=1400,radius=650,sizeClass='regional',vx=-1,vz=0,cloud=.95,stage='mature',shaft=.82,kind='snow',flash=0}
local DistantWeather={items=function() return {front},1 end,motionTime=function() return 73.5 end}
local WeatherWorldSpace={toLocal=function(x,z) return x,z end}
local generic={}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='CLEAR',weatherFxChannels={}}
function V.require(n)
  if n=='Settings' then return Settings elseif n=='WeatherSetting' then return WeatherSetting elseif n=='ForestAtmos' then return ForestAtmos end
  if n=='DistantWeather' then return DistantWeather elseif n=='WeatherWorldSpace' then return WeatherWorldSpace end
  if n=='MesoscaleField' then return {ready=function() return false end} elseif n=='PerformanceGovernor' then return {scale=function() return 1 end} end
  if n=='Quality' then return {budget=function() return {worldPrecip=1} end} elseif n=='Scene' then return {now={visible='world',outdoor=true}} end
  return generic
end
V.safeCall=pcall
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local vox={eye={0,12,0},focus={0,40,200},player={0,0,0},far=1400,size=function() return 1280,720 end}
local frame={level=1,canopy=false,weather={coverage=0,cloudShade=1.02,snowIntensity=0},rayColor={1,.96,.9}}
local function countKind(kind)
  local rows,indices,n=C._buildDistantWeather(vox,frame,{id='MAP'})
  local count,maxA=0,0
  for i=1,(n or 0) do
    if rows[i][7]==kind then count=count+1;maxA=math.max(maxA,tonumber(rows[i][6]) or 0) end
  end
  return count,maxA,n or 0,#(indices or {})
end

local c0,a0=countKind(6)
ck(c0>=800 and a0>.05,'remote snow slab remains visible before local snow begins')
ck(math.abs(C._distantSnowHandoff(frame,'rain')-1)<1e-12,'rain is never attenuated by snow handoff')
ck(math.abs(C._distantSnowHandoff(frame,'fog')-1)<1e-12,'fog is never attenuated by snow handoff')

frame.weather.snowIntensity=.22
local c1,a1=countKind(6)
ck(c1==c0 and a1<a0,'early local snowfall smoothly lowers remote snow opacity without particle teleport')

frame.weather.snowIntensity=.65
local c2,a2=countKind(6)
ck(c2==0 and a2==0,'established local snowfall fully retires duplicate remote snow slab')

front.kind='blizzard';front.weather='BLIZZARD';front.cloudWeather='BLIZZARD';front.gust=.95
local cb,ab=countKind(7)
ck(cb==0 and ab==0,'established local snowfall also retires duplicate blizzard slab')

front.kind='rain';front.weather='STORM';front.cloudWeather='STORM';front.gust=0
local cr,ar=countKind(5)
ck(cr>=800 and ar>.05,'rain-front precipitation remains unchanged while local snow is active')

local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
local _,uses=src:gsub('alpha=alpha%*CinematicAtmos%._distantSnowHandoff%(frame,a%.kind%)','')
ck(uses==2,'same snow handoff gates both CPU fallback and GPU-instanced front paths')
local dsrc=assert(io.open(ROOT..'lib/DramalessAtmos.lua','rb')):read('*a')
ck(dsrc:find('DistantFrontPrecip = true',1,true)~=nil,'private GPU distant-front backend resolves as Weather FX root authority')

print(string.format('8.1.59 snow point-plume regression: %d passed, %d failed',pass,fail))
os.exit(fail==0 and 0 or 1)
