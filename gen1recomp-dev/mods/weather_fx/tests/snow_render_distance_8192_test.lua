-- Weather FX 8.1.92: 3D snow coverage must be impossible to out-walk at 100%.
-- Fronts may shape density/patchiness, but the actual falling-snow volume must
-- reach the live voxel far plane instead of stopping at the old 750-unit cap.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function near(a,b) return math.abs((tonumber(a) or -999)-(tonumber(b) or -777))<1e-9 end

local fronts=true
local scale=1.0
local Settings={
  isFirstPerson=function()return false end,
  splashOn=function()return false end,
  cloudHeightScale=function()return 1.5 end,
  get=function(_,k)if k=='fronts'then return fronts and 'on' or 'off' end return 'config' end,
  snowAccumulationEnabled=function()return false end,
  weatherRenderDistanceScale=function()return scale end,
}
local Config={get=function()return{fronts={enabled=fronts}}end}
-- Deliberately tiny quality radius: quality is allowed to thin snow, never to
-- cut the physical coverage radius below the rendered world.
local Quality={budget=function()return{
  worldPrecip=.001,worldRadiusCap=96,worldSnowCap=64,worldBlizzardCap=64,
  worldRainCap=64,worldHailCap=64,worldSandCap=64,worldAshCap=64,
  worldDebrisCap=64,snowPackDrawCap=0,footDrawCap=0,splash=0,
}end}
local V={safeCall=pcall}
function V.require(n)
  if n=='Settings'then return Settings end
  if n=='Config'then return Config end
  if n=='Quality'then return Quality end
  error('no module '..tostring(n),0)
end
local W=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
local focus={0,0,0}
local function meta(far)return{anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D={far=far},volume={farPrecipScale=.72}}end

fronts=true;scale=1
W.update(1/60,focus,{wxId='SNOW',snowIntensity=1.9},meta(1600))
ck(near(W.snowVirtualization().fieldRadius,1600),'fronts ON + 100% snow reaches exact 1600-unit voxel render distance')
W.update(1/60,{700,0,0},{wxId='SNOW',snowIntensity=1.9},meta(2304))
ck(near(W.snowVirtualization().fieldRadius,2304),'walking/far-distance change immediately expands snow to exact 2304-unit render distance')
scale=.75
W.update(1/60,{1200,0,0},{wxId='SNOW',snowIntensity=1.9},meta(2304))
ck(near(W.snowVirtualization().fieldRadius,1728),'fronts ON still honors explicit 75% 3D WEATHER DISTANCE reduction')
scale=1
W.update(1/60,{1800,0,0},{wxId='BLIZZARD',snowIntensity=3.8},meta(3072))
ck(near(W.snowVirtualization().fieldRadius,3072),'BLIZZARD uses the same full-render-distance snow coverage contract')

fronts=false;scale=1
W.update(1/60,{2400,0,0},{wxId='SNOW',snowIntensity=1.9},meta(1024))
ck(near(W.snowVirtualization().fieldRadius,1024),'fronts OFF keeps exact 100% render-distance snow behavior')

fronts=true;scale=1
W.update(1/60,focus,{wxId='RAIN',rainIntensity=1},meta(2048))
ck(W.precipVirtualization().rain.radius<=96.001,'fronts-ON regional rain radius is unchanged by the snow-only coverage correction')

local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(src:find('SNOW_STREAM_RADIUS = max(SNOW_MIN_R, desiredSnowR)',1,true)~=nil,'snow radius no longer re-enters the old fronts-ON 750-unit clamp')
ck(src:find('local snowFar=max(SNOW_MIN_R,voxelFar*scale)',1,true)~=nil,'procedural preflight uses the same live snow render-distance contract')

print(('8.1.92 snow render distance: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
