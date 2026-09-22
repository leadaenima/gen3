local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1; print('FAIL '..n) end end
local ROOT='./'
local Types=assert(loadfile('lib/Types.lua'))()
local function graphics(supported)
  love={graphics={}}
  function love.graphics.getSupported() return {instancing=supported,glsl3=supported} end
  function love.graphics.newMesh() return {release=function()end,attachAttribute=function()return true end} end
  function love.graphics.newShader() return {send=function()end,release=function()end} end
  function love.graphics.drawInstanced()end
  function love.graphics.setBlendMode()end;function love.graphics.setDepthMode()end;function love.graphics.setShader()end;function love.graphics.setColor()end
end
local function fresh(supported)
  graphics(supported)
  local V={weatherFxId='BLIZZARD'}; local cache={}
  function V.require(name)
    if cache[name] then return cache[name] end
    if name=='Types' then return Types end
    if name=='Quality' then return {budget=function() return {worldPrecip=1,worldRadiusCap=750,worldSnowCap=100000,worldBlizzardCap=200000,snow=4800,snowProbeCap=96,splash=1} end} end
    if name=='Settings' then return {isFirstPerson=function()return false end,splashOn=function()return false end,snowShape=function()return 'flake' end,leafColor=function()return 'green'end} end
    if name=='Scene' then return {now={visible='world'}} end
    if name=='WindEngine' then return {peek=function()return{x=.3,z=.15,strength=.5}end,vector=function(scale)return .3*(scale or 1),.15*(scale or 1)end} end
    if name=='InstanceSeedBuffer' then local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m end
    if name=='ProceduralSnowField' then local m=assert(loadfile('lib/ProceduralSnowField.lua'))(V);cache[name]=m;return m end
    error('no module '..name,0)
  end
  local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
  W.tune{radius=600,perTile=22,max=100000}
  if supported then
    local P=V.require('ProceduralSnowField')
    local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
    local ok=P.draw(Vox,{count=1,alpha=0,eye={0,4,0},focus={0,0,0},wind={0,0},nearRadius=128,farRadius=600,topY=120,bottomY=-20,span=24,time=0,intensity=2})
    check(ok==true and P.canVirtualize()==true,'successful GPU probe enables snow virtualization')
  end
  W.update(1/60,{0,0,0},{}, {anchorKind='player',deckY=120,deckSpan=24})
  return W
end

do
  local W=fresh(true);local v=W.snowVirtualization();local s=W.spawnStatus()
  check(s.snow>100000,'MAX blizzard keeps six-figure authored logical snow target')
  check(v.logical==s.snow,'virtualization logical count equals authoritative spawn count')
  check(v.procedural==v.logical and v.simulated>0,'capable GPU owns complete visual snow while retaining tiny interaction probes')
  check(v.simulated<=96,'snow CPU interaction sample is capped at 96 probes')
  check(v.simRadius<=48.001,'snow interaction probe shell bounded to 48 world units')
  check(v.simulated<v.logical*.001,'600-unit MAX blizzard removes over 99.9% of visual snow from Lua integration')
  check(v.fieldRadius>=600,'snow field coverage is not reduced by quality radius budgeting')
end

do
  local W=fresh(false);local v=W.snowVirtualization();local s=W.spawnStatus()
  check(v.logical==s.snow and v.procedural==0,'unsupported GPU keeps no virtual far field')
  check(v.simulated<=4800 and v.simulated<v.logical,'unsupported GPU uses bounded CPU-visible fallback instead of integrating the complete logical storm')
end
print(('snow virtualization: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
