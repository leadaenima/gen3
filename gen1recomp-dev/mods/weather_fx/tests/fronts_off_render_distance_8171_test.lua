-- Weather FX 8.1.71 rendered-distance regression, superseded for snow by 8.1.92.
-- Snow now follows the voxel far distance in both front modes; rain/hail keep
-- the original fronts-OFF whole-world vs fronts-ON regional split.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local fronts=false
local Settings={
  isFirstPerson=function() return false end,
  splashOn=function() return false end,
  cloudHeightScale=function() return 1.5 end,
  get=function(_,k) if k=='fronts' then return fronts and 'on' or 'off' end return 'config' end,
  snowAccumulationEnabled=function() return false end,
  weatherRenderDistanceScale=function() return 1.0 end,
}
local Config={get=function() return {fronts={enabled=fronts}} end}
local Quality={budget=function() return {
  worldPrecip=.001, worldRadiusCap=128,
  worldSnowCap=64, worldBlizzardCap=64, worldRainCap=64, worldHailCap=64,
  worldSandCap=64, worldAshCap=64, worldDebrisCap=64,
  snowPackDrawCap=0, footDrawCap=0, splash=0,
} end}
local V={safeCall=pcall}
function V.require(name)
  if name=='Settings' then return Settings end
  if name=='Config' then return Config end
  if name=='Quality' then return Quality end
  error('no module '..tostring(name),0)
end
local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
local focus={0,0,0}
local function meta(far)
  return {anchorKind='player',deckY=120,deckSpan=2,Voxel3D={far=far},volume={farPrecipScale=.72}}
end
local function near(a,b) return math.abs((tonumber(a) or -999)-(tonumber(b) or -777))<1e-9 end

fronts=false
W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(1024))
ck(near(W.snowVirtualization().fieldRadius,1024),'fronts OFF: snow field radius equals voxel render distance 1024 exactly')
W.update(1/60,focus,{wxId='RAIN',rainIntensity=1.0},meta(1536))
ck(near(W.precipVirtualization().rain.radius,1536),'fronts OFF: rain field radius equals voxel render distance 1536 exactly')
W.update(1/60,focus,{wxId='HAIL',hailIntensity=1.25},meta(2048))
ck(near(W.precipVirtualization().grain.radius[1],2048),'fronts OFF: hail field radius equals voxel render distance 2048 exactly')
W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(384))
ck(near(W.snowVirtualization().fieldRadius,384),'fronts OFF: lowering voxel render distance immediately lowers snow reach to 384')

fronts=true
W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(2048))
ck(near(W.snowVirtualization().fieldRadius,2048),'fronts ON: snow also equals live voxel render distance after 8.1.92')
W.update(1/60,focus,{wxId='RAIN',rainIntensity=1.0},meta(2048))
ck(W.precipVirtualization().rain.radius<=128,'fronts ON: rain keeps inherited quality/front radius budget')
W.update(1/60,focus,{wxId='HAIL',hailIntensity=1.25},meta(2048))
ck(W.precipVirtualization().grain.radius[1]<=750,'fronts ON: hail does not inherit the fronts-OFF exact render-distance rule')

local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(src:find('desiredSnowR = max(SNOW_MIN_R, lastFar * weatherDistanceScale)',1,true)~=nil and src:find('desiredRainR = max(4, lastFar * weatherDistanceScale)',1,true)~=nil,
  'fronts-OFF 100% rule still uses live far distance directly while allowing only a player-selected reduction')
ck(src:find('lastFar = WP._voxelRenderDistance(streamMeta) or lastFar',1,true)~=nil,
  'update consumes current Voxel3D render distance without waiting for the next draw frame')

print(('fronts-off voxel render distance 8.1.71: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
