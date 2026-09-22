-- Weather FX 8.1.41 visual scale/near-contact storm-bank regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end,cloudHeightScale=function() return 1.5 end}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=120,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local front={id=41,weather='STORM',x=1500,z=0,bankX=700,bankZ=0,rx=1200,rz=3200,sizeClass='synoptic',vx=-1,vz=0,cloud=.98,stage='mature',shaft=.8,kind='rain',flash=0}
local DistantWeather={items=function() return {front},1 end}
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
local vox={eye={0,12,0},focus={0,40,200},player={0,0,0},far=1200,size=function() return 1280,720 end}
local frame={level=1,canopy=false,weather={coverage=0,cloudShade=1.02},rayColor={1,.96,.9}}
local list,n=C.frontCloudDescriptorProbe(vox,frame,{id='MAP'})
ck(n==16,'synoptic mature front expands to sixteen bounded shared-bank descriptors')
local minZ,maxZ=1e9,-1e9
for i=1,#list do minZ=math.min(minZ,list[i].cz);maxZ=math.max(maxZ,list[i].cz) end
ck((maxZ-minZ)>1500,'synoptic front renders as a multi-map-wide wall instead of the old <=760-unit patch')
local sum=0
for i=1,#list do sum=sum+(list[i].fadeAlpha or 0) end
ck(sum/math.max(1,#list)>.85,'near-contact front bank retains strong visible opacity')
local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
ck(src:find('physicalCross',1,true)~=nil and src:find('far*2.25',1,true)~=nil,'renderer scales visible bank width from physical cross-front radius')
ck(src:find('a.bankX',1,true)~=nil and src:find('a.bankZ',1,true)~=nil,'renderer anchors distant bank on its leading edge rather than hidden cell centre')
print(string.format('storm front scale render 8.1.41: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
