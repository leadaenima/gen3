-- Weather FX 8.1.75: fronts-OFF rain must not fall back to a player-centred
-- visual stream at low populations, and a transient live-channel zero while
-- walking must not deallocate an otherwise unchanged rain weather.
local passed,failed=0,0
local function check(v,n)
  if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end
end
local Types=assert(loadfile('lib/Types.lua'))()

love={graphics={}}
function love.graphics.getSupported() return {instancing=true,glsl3=true} end
function love.graphics.newMesh()
  return {release=function()end,attachAttribute=function()return true end,setVertices=function()end}
end
function love.graphics.newShader() return {send=function()return true end,release=function()end} end
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
  if name=='Config' then return {get=function() return {fronts={enabled=false}} end} end
  if name=='Quality' then return {budget=function() return {
    worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,
    worldBlizzardCap=200000,worldHailCap=7200,worldSandCap=43200,
    worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0,
  } end} end
  if name=='Settings' then return {
    get=function(k) if k=='fronts' then return 'off' end return nil end,
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
local Vox={far=256,vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,6,0},player={0,0,0},beginEffect=function()return true end,endEffect=function()end}
local meta={anchorKind='live-player',deckY=120,deckSpan=24,Voxel3D=Vox,player={px=-.5,py=-.5}}
local P=V.require('ProceduralPrecipField')
check(P.probe(Vox,{kind='rain',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=64,topY=120,bottomY=-20,span=24,time=1,intensity=1,uniformField=true})==true,
  'procedural rain backend proves before low-population allocation')

local weather={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}
W.update(1/60,{0,0,0},weather,meta)
local a=W.precipVirtualization().rain
check(a.logical>0 and a.logical<1200,'short 25% weather radius creates a sub-1200 rain population')
check(a.fullVisual==true and a.procedural==a.logical,'proven procedural rain owns low-population visible rain instead of player-centred CPU visuals')
check(a.simulated<=96,'low-population procedural rain retains only bounded CPU interaction probes')
local r,d=W.rainCoverage();check(math.abs(r-64)<.001,'fronts-OFF rain radius remains exact 25% of voxel far distance')

-- Walk while the host publishes a one-frame zero for the same authored rain id.
meta.player={px=31.5,py=-.5}
local dropout={wxId='RAIN',rainIntensity=0,_wxChannelsResolved=true}
W.update(1/60,{32,0,0},dropout,meta)
local b=W.precipVirtualization().rain
check(b.logical==a.logical and b.fullVisual==true,'walking plus transient channel zero does not stop active fronts-OFF rain')
check((dropout.rainIntensity or 0)>.02,'continuity latch republishes stable rain intensity to the draw-frame weather bag')

-- A second movement frame with the live channel restored must remain seamless.
meta.player={px=63.5,py=-.5}
local restored={wxId='RAIN',rainIntensity=1,_wxChannelsResolved=true}
W.update(1/60,{64,0,0},restored,meta)
local c=W.precipVirtualization().rain
check(c.logical==a.logical and c.fullVisual==true,'restored live channel keeps the same rain allocation while walking')

-- Explicit user OFF remains authoritative.
local off={wxId='RAIN',rainIntensity=0,_wxChannelsResolved=true,_rainExplicitOff=true}
W.update(1/60,{64,0,0},off,meta)
check(W.precipVirtualization().rain.logical==0,'RAIN AMOUNT OFF still stops rain immediately')

-- Natural authored transitions retain their ability to taper to zero.
local W2=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
local trans={wxId='RAIN',rainIntensity=0,_wxChannelsResolved=true,_transitionActive=true}
W2.update(1/60,{0,0,0},trans,meta)
check(W2.precipVirtualization().rain.logical==0,'authored transition may still taper fronts-OFF rain to zero')

-- Anchor cells stay world-fixed but close to the player/weather circle.
P.invalidate();P.probe(Vox,{kind='rain',eye={0,6,0},focus={0,0,0},wind={0,0},nearRadius=1.5,farRadius=64,topY=120,bottomY=-20,span=24,time=2,intensity=1,uniformField=true})
local st=P.stats();check((tonumber(st.anchorCell)or 999)<=8.01,'short-distance procedural rain uses a tight world-fixed anchor cell')
P.draw(Vox,{kind='rain',count=64,eye={12,6,0},focus={12,0,0},wind={0,0},nearRadius=1.5,farRadius=64,topY=120,bottomY=-20,span=24,time=2.2,intensity=1,uniformField=true})
local st2=P.stats();check(st2.nextAnchorX~=nil or st2.anchorX~=0,'walking hands off between fixed world anchors instead of translating every drop')

print(('rain walk continuity 8.1.75: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
