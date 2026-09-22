-- Weather FX 8.1.77: active fronts-OFF rain must remain continuous at map
-- edges and through camera turns even when the host cannot use procedural
-- instancing. Rain animation phase also uses a monotonic render clock so a
-- gameplay/update hitch cannot make the entire field visibly slow/freeze.
local passed,failed=0,0
local function check(v,n)
  if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end
end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local Types=assert(loadfile('lib/Types.lua'))()

local wall=100
local draws=0
love={timer={},graphics={}}
function love.timer.getTime() return wall end
function love.graphics.getSupported() return {instancing=false,glsl3=true} end
function love.graphics.newMesh(fmt,verts)
  return {setVertices=function()return true end,setDrawRange=function()return true end,release=function()end}
end
function love.graphics.newShader() return {send=function()return true end,release=function()end} end
function love.graphics.draw() draws=draws+1;return true end
function love.graphics.drawInstanced() return true end
function love.graphics.setBlendMode()end
function love.graphics.setDepthMode()end
function love.graphics.setShader()end
function love.graphics.setColor()end

local cache={}
local V={weatherFxId='RAIN'};V.safeCall=pcall
function V.require(name)
  if cache[name] then return cache[name] end
  if name=='Types' then return Types end
  if name=='Config' then return {get=function()return{fronts={enabled=false}}end} end
  if name=='Quality' then return {budget=function()return{
    worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,
    worldBlizzardCap=200000,worldHailCap=7200,worldSandCap=43200,
    worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0,
  }end} end
  if name=='Settings' then return {
    get=function(k)if k=='fronts'then return'off'end return nil end,
    manualWeatherSelected=function()return'RAIN'end,
    weatherRenderDistanceScale=function()return .25 end,
    isFirstPerson=function()return false end,splashOn=function()return false end,
    snowAccumulationEnabled=function()return true end,snowShape=function()return'flake'end,
    leafColor=function()return'green'end,
  } end
  if name=='Scene' then return {now={visible='world'}} end
  if name=='WindEngine' then return {vector=function(s)return .5*(s or 1),.2*(s or 1)end} end
  if name=='MesoscaleField' then return {ready=function()return true end,peek=function()return{precipScale=1}end,renderParams=function()return{}end} end
  if name=='ProceduralPrecipField' then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralSnowField' then return {canVirtualize=function()return false end} end
  error('no module '..name,0)
end

local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
-- Monotonic render clock progresses even with no WP.update call.
local haveClock=type(W._rainVisualTime)=='function' and type(W._rainFrameDt)=='function'
if haveClock then
  local t0=W._rainVisualTime();wall=100.40;local t1=W._rainVisualTime()
  check(math.abs((t1-t0)-.40)<.0001,'rain render clock advances independently of gameplay update')
  wall=100.40;W._rainFrameDt(1/60) -- seed wall-update clock
  wall=100.75;local d=W._rainFrameDt(1/60)
  check(math.abs(d-.25)<.0001,'rain frame delta catches wall hitch but respects safety cap')
  -- Verify a normal short wall step dominates an artificially tiny gameplay delta.
  wall=100.85;local d2=W._rainFrameDt(.001)
  check(d2>.09 and d2<.11,'CPU rain integration follows real elapsed wall time through host cadence stalls')
else
  check(false,'rain render clock advances independently of gameplay update')
  check(false,'rain frame delta catches wall hitch but respects safety cap')
  check(false,'CPU rain integration follows real elapsed wall time through host cadence stalls')
end

local Vox={far=128,vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,6,0},focus={0,0,-1},lookFlat={0,0,-1},player={0,0,0},beginEffect=function()return true end,endEffect=function()end}
local meta={anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D=Vox,player={px=-.5,py=-.5},map={id='edge-route'}}
local weather={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}
wall=101;W.update(1/60,{0,0,0},weather,meta)
local a=W.precipVirtualization().rain
check(a.logical>0 and a.fullVisual==false,'instancing-disabled host uses CPU visible rain fallback')
check(type(a.cpuAnchorX)=='number' and type(a.cpuAnchorZ)=='number','CPU fallback records fixed world rain anchor')
local ax,az=a.cpuAnchorX,a.cpuAnchorZ

-- Small local movement keeps the CPU field anchor fixed rather than dragging it
-- with the player every step.
meta.player={px=1.5,py=-.5};wall=101.016;W.update(1/60,{2,0,0},{wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true},meta)
local b=W.precipVirtualization().rain
check(b.cpuAnchorX==ax and b.cpuAnchorZ==az,'ordinary walking does not translate CPU rain field')

-- Draw once facing one way and once after a 180-degree turn, with no weather
-- update between them. The CPU path must stay healthy/submitted both times.
local before=draws
W.draw(Vox,{weather={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}})
local s1=W.drawStatus().rain
check(draws>before and s1.healthy and s1.verts>0,'CPU rain draws healthy before camera turn')
Vox.lookFlat={0,0,1};Vox.focus={0,0,1};before=draws;wall=101.050
W.draw(Vox,{weather={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}})
local s2=W.drawStatus().rain
check(draws>before and s2.healthy and s2.verts>0,'180-degree camera turn cannot cull/stop CPU rain')
check(s2.active==s1.active,'camera turn does not change rain allocation')

-- Move near an authored map edge coordinate and keep rain allocated. The CPU
-- anchor may advance by a small world cell, but the stream never deallocates.
meta.player={px=31.5,py=-.5};wall=101.066;W.update(1/60,{32,0,0},{wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true},meta)
local c=W.precipVirtualization().rain
check(c.logical==a.logical and c.logical>0,'map-edge walking keeps authored fronts-OFF rain allocated')
check((tonumber(c.cpuAnchorCell)or 999)<=8.01,'short-distance CPU anchor cells stay tight enough to avoid directional field edges')

local wp=read('lib/voxel_atmos/WorldPrecip.lua')
local p0=assert(wp:find('local function drawRainStreaks',1,true))
local p1=assert(wp:find('-- DRAW: SNOW',p0,true))
local rainDraw=wp:sub(p0,p1-1)
check(rainDraw:find('cameraForward',1,true)==nil,'CPU rain draw has no camera-facing visibility gate')
check(wp:find('rainSpawnX',1,true)~=nil and wp:find('rx[i]-rainSpawnX',1,true)~=nil,'CPU rain spawn and recycle use stable world anchor')
check(wp:find('rainVisualTime',1,true)~=nil and rainDraw:find('time=rainTime',1,true)~=nil,'procedural rain phase uses monotonic render clock')
local pp=read('lib/ProceduralPrecipField.lua')
check(pp:find('r%*0%.04')~=nil and pp:find('ANCHOR_CELL=24',1,true)~=nil,'procedural anchor stays close enough to player to avoid turn-exposed field edge')

-- Explicit OFF still wins; continuity must not make rain immortal.
wall=101.10;W.update(1/60,{32,0,0},{wxId='RAIN',rainIntensity=0,_wxChannelsResolved=true,_rainExplicitOff=true},meta)
check(W.precipVirtualization().rain.logical==0,'explicit rain OFF still stops stream')

print(('rain map-edge/turn continuity 8.1.77: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
