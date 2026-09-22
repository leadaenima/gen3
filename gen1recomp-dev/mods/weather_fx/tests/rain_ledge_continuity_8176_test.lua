-- Weather FX 8.1.76: fronts-OFF rain must survive player movement/ledge pose
-- frames, draw from update-owned stream state, keep a stable fall-column bottom,
-- and use the tapered translucent water-streak model instead of a white rectangle.
local passed,failed=0,0
local function check(v,n)
  if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end
end
local Types=assert(loadfile('lib/Types.lua'))()

local drawInstancedCalls=0
love={graphics={}}
function love.graphics.getSupported() return {instancing=true,glsl3=true} end
function love.graphics.newMesh()
  return {
    release=function()end,attachAttribute=function()return true end,
    setVertices=function()return true end,setDrawRange=function()return true end,
    setVertexMap=function()return true end,
  }
end
function love.graphics.newShader() return {send=function()return true end,release=function()end} end
function love.graphics.drawInstanced() drawInstancedCalls=drawInstancedCalls+1;return true end
function love.graphics.draw() return true end
function love.graphics.setBlendMode()end
function love.graphics.setDepthMode()end
function love.graphics.setShader()end
function love.graphics.setColor()end

local cache={}
local V={weatherFxId='RAIN'};V.safeCall=pcall
function V.require(name)
  if cache[name] then return cache[name] end
  if name=='Types' then return Types end
  if name=='Config' then return {get=function() return {fronts={enabled=false}} end} end
  if name=='Quality' then return {budget=function() return {
    worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,
    worldBlizzardCap=200000,worldHailCap=7200,worldSandCap=43200,
    worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0,
  } end} end
  if name=='Settings' then return {
    get=function(k) if k=='fronts' then return 'off' end return nil end,
    manualWeatherSelected=function() return nil end,
    weatherRenderDistanceScale=function()return .25 end,
    isFirstPerson=function()return false end,splashOn=function()return false end,
    snowAccumulationEnabled=function()return true end,snowShape=function()return 'flake' end,
    leafColor=function()return 'green' end,
  } end
  if name=='Scene' then return {now={visible='world'}} end
  if name=='WindEngine' then return {peek=function()return{x=.5,z=.2,strength=.7}end,vector=function(s)return .5*(s or 1),.2*(s or 1)end} end
  if name=='MesoscaleField' then return {ready=function()return true end,peek=function()return{precipScale=.01}end,renderParams=function()return{patchiness=.9,floor=.01}end} end
  if name=='InstanceSeedBuffer' then local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralPrecipField' then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralSnowField' then local m=assert(loadfile('lib/ProceduralSnowField.lua'))(V);cache[name]=m;return m end
  error('no module '..name,0)
end

local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
local Vox={far=256,vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,6,0},focus={0,0,-1},player={0,0,0},beginEffect=function()return true end,endEffect=function()end}
local meta={anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D=Vox,player={px=-.5,py=-.5},map={id='route-test'}}
local P=V.require('ProceduralPrecipField')
check(P.probe(Vox,{kind='rain',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=64,topY=120,bottomY=-32,span=24,time=1,intensity=1,uniformField=true})==true,
  'procedural rain backend proves before ledge continuity test')

local weather={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}
W.update(1/60,{0,0,0},weather,meta)
local a=W.precipVirtualization().rain
check(a.logical>0 and a.fullVisual==true,'initial fronts-OFF rain is active and procedural')
check(type(a.fieldBottomY)=='number','rain records a stable world fall-column bottom')
local bottom0=tonumber(a.fieldBottomY) or -9999

-- Simulate the exact bad frame: player moves onto a ledge, focus Y rises, and the
-- cinematic frame bag briefly says CLEAR/zero even though the root weather is RAIN.
meta.player={px=15.5,py=-.5}
local ledgeBag={wxId='CLEAR',rainIntensity=0,_wxChannelsResolved=true}
W.update(1/60,{16,6,0},ledgeBag,meta)
local b=W.precipVirtualization().rain
check(b.logical==a.logical and b.fullVisual==true,'ledge movement plus transient CLEAR bag does not deallocate fronts-OFF rain')
check(ledgeBag.wxId=='RAIN' and (ledgeBag.rainIntensity or 0)>.02,'root fronts-OFF rain identity repairs the transient ledge pose bag')
check(math.abs((b.fieldBottomY or 999)-bottom0)<.001,'ledge elevation does not rephase the procedural rain fall column')

-- Draw receives a fresh frame-local zero bag. update() already owns the rain
-- stream, so this must not suppress visible rain for one frame.
local before=drawInstancedCalls
W.draw(Vox,{weather={wxId='CLEAR',rainIntensity=0,_wxChannelsResolved=true},fogColor={.5,.5,.6}})
check(drawInstancedCalls>before,'draw pass still submits rain when frame-local bag glitches to zero after update')
check(W.drawingRain()==true,'draw health reports rain visible across transient draw-frame zero')

-- Ordinary walking at the same weather keeps the exact same field bottom.
meta.player={px=47.5,py=-.5}
local restored={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}
W.update(1/60,{48,0,0},restored,meta)
local c=W.precipVirtualization().rain
check(c.logical==a.logical and math.abs((c.fieldBottomY or 999)-bottom0)<.001,'walking keeps stable rain allocation and fall-column bottom')

-- Real authored transition is still allowed to shut rain down.
local trans={wxId='CLEAR',rainIntensity=0,_wxChannelsResolved=true,_transitionActive=true}
W.update(1/60,{48,0,0},trans,meta)
check(W.precipVirtualization().rain.logical==0,'authored transition can still stop rain')

-- Static visual-model contract: both procedural and CPU fallback are thin,
-- tapered, translucent water streaks rather than broad white rectangles.
local function read(path) local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local pp=read('lib/ProceduralPrecipField.lua')
local wp=read('lib/voxel_atmos/WorldPrecip.lua')
check(pp:find('authoredSize%*0%.070')~=nil and pp:find('authoredSize%*3%.35')~=nil,'procedural rain geometry is thin and elongated')
check(pp:find('tapered translucent water streak',1,true)~=nil and pp:find('vec3(.62,.72,.82)',1,true)~=nil,'procedural rain uses tapered translucent blue-grey water shading')
check(pp:find('shape=1.0-smoothstep(.62,1.0,abs(p.x))',1,true)==nil,'old procedural rectangular rain mask is removed')
check(wp:find('local half = size * 0.070',1,true)~=nil and wp:find('local len = size * 3.35',1,true)~=nil,'CPU fallback uses matching thin elongated rain geometry')

print(('rain ledge continuity 8.1.76: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
