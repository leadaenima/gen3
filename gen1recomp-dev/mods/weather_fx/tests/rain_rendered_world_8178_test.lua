-- Weather FX 8.1.78: with WEATHER FRONTS OFF, active rain is a complete
-- rendered-world field. 100% weather distance equals the live voxel far plane;
-- the visual field is an absolute world grid covering the full 2R x 2R render
-- window, not a radial/player-centred weather bubble.
local passed,failed=0,0
local function check(v,n) if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local Types=assert(loadfile('lib/Types.lua'))()

love={graphics={}}
function love.graphics.getSupported() return {instancing=true,glsl3=true} end
function love.graphics.newMesh()
  return {release=function()end,attachAttribute=function()return true end,setVertices=function()end,setDrawRange=function()end}
end
function love.graphics.newShader() return {send=function()return true end,release=function()end} end
function love.graphics.drawInstanced() return true end
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
  if name=='Config' then return {get=function()return{fronts={enabled=false}}end} end
  if name=='Quality' then return {budget=function()return{
    worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,
    worldBlizzardCap=200000,worldHailCap=7200,worldSandCap=43200,
    worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0,
  }end} end
  if name=='Settings' then return {
    get=function(k)if k=='fronts'then return'off'end return nil end,
    manualWeatherSelected=function()return'RAIN'end,
    weatherRenderDistanceScale=function()return 1 end,
    isFirstPerson=function()return false end,splashOn=function()return false end,
    snowAccumulationEnabled=function()return true end,snowShape=function()return'flake'end,
    leafColor=function()return'green'end,
  } end
  if name=='Scene' then return {now={visible='world'}} end
  if name=='WindEngine' then return {vector=function(s)return .5*(s or 1),.2*(s or 1)end} end
  if name=='MesoscaleField' then return {ready=function()return true end,peek=function()return{precipScale=1}end,renderParams=function()return{}end} end
  if name=='InstanceSeedBuffer' then
    local m={get=function()return {release=function()end},8192 end};cache[name]=m;return m
  end
  if name=='ProceduralPrecipField' then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralSnowField' then return {canVirtualize=function()return false end} end
  error('no module '..name,0)
end

local P=V.require('ProceduralPrecipField')
local Vox={far=512,vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={500,6,-300},player={0,0,0},beginEffect=function()return true end,endEffect=function()end}
check(P.probe(Vox,{kind='rain',eye=Vox.eye,focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=512,topY=120,bottomY=-40,span=24,time=1,intensity=1,uniformField=true,worldGrid=true})==true,
  'fronts-OFF rendered-world rain backend proves')
P.draw(Vox,{kind='rain',count=4096,eye=Vox.eye,focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=512,topY=120,bottomY=-40,span=24,time=2,intensity=1,uniformField=true,worldGrid=true})
local g=P.stats().lastGrid
check(type(g)=='table' and g.far==512,'procedural rain reports rendered-world grid at exact voxel far distance')
if type(g)=='table' then
  local minx=(g.baseX+.12)*g.stepX;local maxx=(g.baseX+g.cols-1+.88)*g.stepX
  local minz=(g.baseZ+.12)*g.stepZ;local maxz=(g.baseZ+g.rows-1+.88)*g.stepZ
  check(minx<=Vox.eye[1]-512 and maxx>=Vox.eye[1]+512,'absolute rain grid covers full rendered X span')
  check(minz<=Vox.eye[3]-512 and maxz>=Vox.eye[3]+512,'absolute rain grid covers full rendered Z span')

  -- Camera/player focus can turn/repoint without changing the absolute rain window.
  local before={g.baseX,g.baseZ,g.stepX,g.stepZ,g.cols,g.rows}
  P.draw(Vox,{kind='rain',count=4096,eye=Vox.eye,focus={900,0,900},wind={.5,.2},nearRadius=1.5,farRadius=512,topY=120,bottomY=-40,span=24,time=2.1,intensity=1,uniformField=true,worldGrid=true})
  local g2=P.stats().lastGrid
  check(type(g2)=='table' and g2.baseX==before[1] and g2.baseZ==before[2] and g2.stepX==before[3] and g2.stepZ==before[4],
    'turning/repointing focus cannot move rendered-world rain cells')
else
  check(false,'absolute rain grid covers full rendered X span')
  check(false,'absolute rain grid covers full rendered Z span')
  check(false,'turning/repointing focus cannot move rendered-world rain cells')
end

local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
local meta={anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D=Vox,player={px=7.5,py=7.5},map={id='render-world'}}
W.update(1/60,{8,0,8},{wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true},meta)
local r=W.rainCoverage()
check(math.abs(r-512)<.001,'fronts-OFF 100% rain distance equals live voxel render distance exactly')
local vr=W.precipVirtualization().rain
check(vr.logical>0 and vr.procedural==vr.logical and vr.fullVisual==true,'validated procedural backend owns complete visible fronts-OFF rain field')

local wp=read('lib/voxel_atmos/WorldPrecip.lua')
local pp=read('lib/ProceduralPrecipField.lua')
check(wp:find('((2*STREAM_RADIUS) * (2*STREAM_RADIUS))',1,true)~=nil,'fronts-OFF rain population budgets the full rendered square instead of a circle')
check(wp:find('worldGrid=WP._uniformPrecipField==true',1,true)~=nil,'WorldPrecip requests rendered-world grid ownership when fronts are OFF')
check(pp:find('if(fieldWorldGrid>0.5){',1,true)~=nil,'procedural shader has rendered-world branch shared by rain and non-debris grains')
check(pp:find('center.xz=(cell+jitter)*fieldGridStep',1,true)~=nil,'rain X/Z comes from absolute world cells rather than player focus')
check(pp:find('float key=cell.x*19.19+cell.y*73.71',1,true)~=nil,'world-cell identity owns rain jitter and phase across window handoffs')
check(pp:find('One guard cell on every side',1,true)~=nil,'rendered-world grid includes edge guard coverage')

-- Explicit OFF remains authoritative.
W.update(1/60,{8,0,8},{wxId='RAIN',rainIntensity=0,_wxChannelsResolved=true,_rainExplicitOff=true},meta)
check(W.precipVirtualization().rain.logical==0,'explicit rain OFF still stops rendered-world rain')

print(('rain rendered-world coverage 8.1.78: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
