-- Weather FX 8.1.37 storm-front / cloud-bank integration regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function check(v,n)
  if v then pass=pass+1;io.write('PASS ',n,'\n')
  else fail=fail+1;io.write('FAIL ',n,'\n') end
end

love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end,cloudHeightScale=function() return 1.5 end}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=120,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local front={id=9,weather='STORM',x=720,z=120,rx=430,rz=340,vx=-1,vz=.18,cloud=.92,stage='mature',lifeU=.5,sizeClass='regional',shaft=.7,kind='rain',flash=0}
local DistantWeather={items=function() return {front},1 end}
local WeatherWorldSpace={toLocal=function(x,z) return x,z end}
local generic={}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='CLEAR',weatherFxChannels={}}
function V.require(n)
  if n=='Settings' then return Settings end
  if n=='WeatherSetting' then return WeatherSetting end
  if n=='ForestAtmos' then return ForestAtmos end
  if n=='DistantWeather' then return DistantWeather end
  if n=='WeatherWorldSpace' then return WeatherWorldSpace end
  if n=='MesoscaleField' then return {ready=function() return false end} end
  if n=='PerformanceGovernor' then return {scale=function() return 1 end} end
  if n=='Quality' then return {budget=function() return {worldPrecip=1} end} end
  if n=='Scene' then return {now={visible='world',outdoor=true}} end
  return generic
end
V.safeCall=pcall
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local vox={eye={0,12,0},focus={0,40,200},player={0,0,0},far=1200,size=function() return 1280,720 end}
local clear={coverage=0,cloudShade=1.02}
local frame={level=1,canopy=false,weather=clear,rayColor={1,.96,.9}}
local list,n=C.frontCloudDescriptorProbe(vox,frame,{id='MAP'})
check(type(list)=='table' and n==10 and #list==10,'mature remote storm becomes ten bounded ordinary cloud-bank descriptors')

local _,deckBase,deckSpan=C._frontCloudDeck(vox,frame,'STORM')
local minY,maxY=1e9,-1e9
local minCross,maxCross=1e9,-1e9
local minAlong,maxAlong=1e9,-1e9
local avgAlpha=0
local allFront,allBankShape=true,true
-- front velocity normalized: (-1,.18); cross is (-.18,-1), sign does not matter for spread.
local fl=math.sqrt(1+.18*.18);local fx,fz=-1/fl,.18/fl;local crx,crz=-fz,fx
for i=1,#list do
  local c=list[i]
  allFront=allFront and c._frontCloud==true
  allBankShape=allBankShape and c.puffs>=24 and c.spanY<45 and c.deckBlend>=.88
  minY=math.min(minY,c.cy);maxY=math.max(maxY,c.cy)
  local dx,dz=c.cx-front.x,c.cz-front.z
  local cross=dx*crx+dz*crz
  local along=dx*fx+dz*fz
  minCross=math.min(minCross,cross);maxCross=math.max(maxCross,cross)
  minAlong=math.min(minAlong,along);maxAlong=math.max(maxAlong,along)
  avgAlpha=avgAlpha+(c.fadeAlpha or 0)
end
avgAlpha=avgAlpha/math.max(1,#list)
check(allFront,'every remote front descriptor is explicitly marked as shared cloud-bank geometry')
check(minY>=deckBase-1e-6 and maxY<=deckBase+deckSpan+1e-6,'all storm-front cloud centers remain inside the exact incoming cloud-bank deck band')
check((maxY-minY)<deckSpan+1e-6 and maxY<deckBase+45,'front has no legacy 48-118-unit vertical tower/stack offset')
check((maxCross-minCross)>260,'front cloud mass spreads laterally across the meteorological front')
check((maxAlong-minAlong)>35,'mature front has real horizontal depth from staggered X/Z bank rows')
check(allBankShape,'front uses dense broad bank descriptors rather than large standalone primitives')
check(avgAlpha>.78 and avgAlpha<.93,'remote lifecycle opacity is preserved on integrated bank clouds')

-- A local closed deck is authoritative during handoff. The incoming front must
-- sit in exactly the same live band rather than retaining its own storm height.
local liveRain={coverage=1,closedDeck=true,deckBlend=1,deckY0=110,deckYSpan=24,cloudShade=.66}
frame.weather=liveRain
local list2,n2=C.frontCloudDescriptorProbe(vox,frame,{id='MAP'})
local _,liveBase,liveSpan=C._frontCloudDeck(vox,frame,'STORM')
local sameBand=true
for i=1,#list2 do sameBand=sameBand and list2[i].cy>=liveBase and list2[i].cy<=liveBase+liveSpan end
check(n2==10 and sameBand,'during handoff the visible local cloud bank becomes the front altitude authority')

-- 8.1.52 supersession: formation keeps the SAME two-row descriptor topology as
-- maturity so a lifecycle label change cannot destroy/recreate cloud positions.
-- Individual descriptors instead fade in at deterministic continuous thresholds.
front.stage='formation';front.lifeU=.15;front.cloud=.55;frame.weather=clear
local forming,n3=C.frontCloudDescriptorProbe(vox,frame,{id='MAP'})
local fmin,fmax=1e9,-1e9;local visible=0
for i=1,#forming do fmin=math.min(fmin,forming[i].cy);fmax=math.max(fmax,forming[i].cy);if (forming[i].fadeAlpha or 0)>.015 then visible=visible+1 end end
check(n3==10 and visible>0 and visible<10 and (fmax-fmin)<=deckSpan,'forming front preserves stable two-row topology while cloud masses fade in progressively')

local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
check(src:find('clouds = CinematicAtmos._appendFrontCloudDescriptors',1,true)~=nil,'live draw appends front descriptors before rendering/cloud-shadow observation')
check(src:find('local function ellipsoid',1,true)==nil and src:find('vKind > 5.5',1,true)==nil,'legacy dark ellipsoid storm-cloud renderer is gone')
check(src:find('Front cloud mass is injected into the ordinary cloud-bank descriptor field',1,true)~=nil,'distant stream is precipitation/lightning-only after integration')

io.write(string.format('storm cloudbank integration 8.1.37: %d passed, %d failed\n',pass,fail))
os.exit(fail==0 and 0 or 1)
