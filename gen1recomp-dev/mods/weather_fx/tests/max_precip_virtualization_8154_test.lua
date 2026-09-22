-- Exact MAX-cap workload contract for Weather FX 8.1.54. The procedural
-- backends are proven BEFORE the first weather update so this test verifies
-- that MAX logical populations never need a MAX-size Lua visual allocation on
-- supported hardware.
local passed,failed=0,0
local function check(v,n) if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end end
local Types=assert(loadfile('lib/Types.lua'))()
love={graphics={}}
function love.graphics.getSupported() return {instancing=true,glsl3=true} end
function love.graphics.newMesh() return {release=function()end,attachAttribute=function()return true end,setVertices=function()end} end
function love.graphics.newShader() return {send=function()end,release=function()end} end
function love.graphics.drawInstanced() end
function love.graphics.setBlendMode()end; function love.graphics.setDepthMode()end; function love.graphics.setShader()end; function love.graphics.setColor()end
local cache={}; local V={weatherFxId='BLIZZARD'}; V.safeCall=pcall
function V.require(name)
  if cache[name] then return cache[name] end
  if name=='Types' then return Types end
  if name=='Quality' then
    local m={budget=function() return {worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldSnowCap=100000,worldBlizzardCap=200000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,splash=0,snowPackDrawCap=0,footDrawCap=0} end}; cache[name]=m; return m
  end
  if name=='Settings' then local m={isFirstPerson=function()return false end,splashOn=function()return false end,snowShape=function()return 'flake' end,leafColor=function()return 'green' end}; cache[name]=m; return m end
  if name=='Scene' then local m={now={visible='world'}}; cache[name]=m; return m end
  if name=='WindEngine' then local m={peek=function()return{x=.5,z=.2,strength=.7}end,vector=function(s)return .5*(s or 1),.2*(s or 1)end}; cache[name]=m; return m end
  if name=='InstanceSeedBuffer' then local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralSnowField' then local m=assert(loadfile('lib/ProceduralSnowField.lua'))(V);cache[name]=m;return m end
  if name=='ProceduralPrecipField' then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
  error('no module '..name,0)
end
local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
W.tune{radius=750,drawRadius=750,perTile=18,max=200000}
local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local meta={anchorKind='player',deckY=120,deckSpan=24}
local PS=V.require('ProceduralSnowField')
check(PS.probe(Vox,{eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=750,topY=120,bottomY=-20,span=24,time=1,intensity=5,ball=false})==true,'MAX test proves snow GPU before allocation')
W.update(1/60,{0,0,0},{wxId='BLIZZARD',snowIntensity=5},meta)
local s=W.snowVirtualization()
check(s.logical==200000,'MAX blizzard preserves exact 200,000 visual flakes')
check(s.procedural==200000 and s.fullVisual==true,'MAX blizzard complete visual population is GPU-owned')
check(s.simulated<=96 and s.pool<=96,'MAX blizzard allocates/integrates <=96 Lua snow probes')
local PP=V.require('ProceduralPrecipField')
check(PP.probe(Vox,{kind='rain',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=750,topY=120,bottomY=-20,span=24,time=1,intensity=2})==true,'MAX test proves rain GPU before allocation')
V.weatherFxId='RAIN_HEAVY'; W.update(1/60,{0,0,0},{wxId='RAIN_HEAVY',rainIntensity=2},meta)
local r=W.precipVirtualization().rain
check(r.logical==12000,'MAX rain preserves exact 12,000 visual drops')
check(r.procedural==12000 and r.fullVisual==true,'MAX rain complete visual population is GPU-owned')
check(r.simulated<=96 and r.pool<=96,'MAX rain allocates/integrates <=96 Lua interaction probes')
print(('MAX precipitation virtualization 8.1.54: %d passed, %d failed'):format(passed,failed)); os.exit(failed==0 and 0 or 1)
