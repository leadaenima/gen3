-- Weather FX 8.1.54: full-visual precipitation virtualization + snow-ground
-- collision virtualization. The real procedural modules are exercised against a
-- mock LÖVE instancing driver, while WorldPrecip supplies the actual authored
-- target/simulation split and pool residency behavior.
local passed,failed=0,0
local function check(v,n)
  if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end
end
local Types=assert(loadfile('lib/Types.lua'))()

local function graphics()
  love={graphics={}}
  function love.graphics.getSupported() return {instancing=true,glsl3=true} end
  function love.graphics.newMesh()
    return {release=function()end,attachAttribute=function()return true end,setVertices=function()end}
  end
  function love.graphics.newShader() return {send=function()end,release=function()end} end
  function love.graphics.drawInstanced() end
  function love.graphics.setBlendMode()end
  function love.graphics.setDepthMode()end
  function love.graphics.setShader()end
  function love.graphics.setColor()end
end

local function fresh(id)
  graphics()
  local cache={}
  local V={weatherFxId=id}; V.safeCall=pcall
  function V.require(name)
    if cache[name] then return cache[name] end
    if name=='Types' then return Types end
    if name=='Quality' then
      return {budget=function() return {
        worldPrecip=1,worldRadiusCap=220,
        worldRainCap=3000,worldSnowCap=5000,worldBlizzardCap=5000,
        worldHailCap=3000,worldSandCap=3000,worldDebrisCap=1600,worldAshCap=3000,
        splash=0,snowPackDrawCap=0,footDrawCap=0,
      } end}
    end
    if name=='Settings' then
      return {isFirstPerson=function()return false end,splashOn=function()return false end,
        snowShape=function()return 'flake' end,leafColor=function()return 'green' end}
    end
    if name=='Scene' then return {now={visible='world'}} end
    if name=='WindEngine' then return {peek=function()return{x=.5,z=.2,strength=.7}end,vector=function(s)return .5*(s or 1),.2*(s or 1)end} end
    if name=='InstanceSeedBuffer' then local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m end
    if name=='ProceduralSnowField' then local m=assert(loadfile('lib/ProceduralSnowField.lua'))(V);cache[name]=m;return m end
    if name=='ProceduralPrecipField' then local m=assert(loadfile('lib/ProceduralPrecipField.lua'))(V);cache[name]=m;return m end
    error('no module '..name,0)
  end
  local W=assert(loadfile('lib/voxel_atmos/WorldPrecip.lua'))(V)
  W.tune{radius=180,drawRadius=180,perTile=18,max=5000}
  return W,V
end
local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local meta={anchorKind='player',deckY=120,deckSpan=24}

-- Rain: first frame remains fail-open/full CPU until a real procedural draw is
-- proven; subsequent frames keep only 96 interaction probes and compact the
-- old full CPU pool while GPU owns the full logical visual count.
do
  local W,V=fresh('RAIN_HEAVY')
  W.update(1/60,{0,0,0},{wxId='RAIN_HEAVY',rainIntensity=1.5},meta)
  local before=W.precipVirtualization().rain
  check(before.logical>1200 and before.simulated==before.logical,'rain begins fail-open with complete CPU population before driver proof')
  check(before.pool==before.logical,'rain first-frame CPU pool matches logical population')
  local P=V.require('ProceduralPrecipField')
  check(P.probe(Vox,{kind='rain',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=180,topY=120,bottomY=-20,span=24,time=1,intensity=1.5})==true,'rain procedural backend completes real invisible driver proof')
  W.update(1/60,{0,0,0},{wxId='RAIN_HEAVY',rainIntensity=1.5},meta)
  local after=W.precipVirtualization().rain
  check(after.fullVisual==true and after.procedural==after.logical,'rain GPU owns complete authored visual population after proof')
  check(after.simulated<=96,'rain CPU work is capped at 96 interaction probes')
  check(after.pool<=96,'rain large CPU pool is compacted after GPU visual ownership')
end

-- Snow: same full-visual handoff, with only face-contact probes retained and
-- bounded ground collision/settling authority restored in 8.1.64 without changing GPU visual ownership.
do
  local W,V=fresh('BLIZZARD')
  W.update(1/60,{0,0,0},{wxId='BLIZZARD',snowIntensity=5},meta)
  local before=W.snowVirtualization()
  check(before.logical>1200 and before.simulated==before.logical,'snow begins fail-open with complete CPU population before driver proof')
  local P=V.require('ProceduralSnowField')
  check(P.probe(Vox,{eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=1.5,farRadius=180,topY=120,bottomY=-20,span=24,time=1,intensity=5,ball=false})==true,'snow procedural backend completes real invisible driver proof')
  W.update(1/60,{0,0,0},{wxId='BLIZZARD',snowIntensity=5},meta)
  local after=W.snowVirtualization()
  check(after.fullVisual==true and after.procedural==after.logical,'snow GPU owns complete authored visual population after proof')
  check(after.simulated<=96 and after.pool<=96,'snow CPU state is reduced and compacted to <=96 face-contact probes')
  check(after.groundCollision==true and W.snowGroundCollisionEnabled()==true,'snow ground collision capability is restored without expanding CPU visual probes')
  local live=W.liveCounts({})
  check((live.groundSnow or 0)==0 and (live.footprints or 0)==0,'host without exact collision support cannot invent snow banks or footprints')
end

-- Noninteractive grain families become pure procedural visuals. Leaves remain
-- physical because their collision/settling behavior is authored gameplay.
do
  local W,V=fresh('SANDSTORM')
  W.update(1/60,{0,0,0},{wxId='SANDSTORM',sandIntensity=2.4},meta)
  local b=W.precipVirtualization().grain
  check((b.logical[2] or 0)>1200 and (b.simulated[2] or 0)==(b.logical[2] or 0),'sand begins with full CPU fallback before proof')
  local P=V.require('ProceduralPrecipField')
  check(P.probe(Vox,{kind='sand',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=4,farRadius=180,topY=120,bottomY=-20,span=24,time=1,intensity=2.4})==true,'shared grain procedural backend proves real draw')
  W.update(1/60,{0,0,0},{wxId='SANDSTORM',sandIntensity=2.4},meta)
  local a=W.precipVirtualization().grain
  check((a.simulated[2] or 0)==0 and (a.procedural[2] or 0)==(a.logical[2] or 0),'sand uses zero CPU visual cards after proof')
  check((a.pool or 0)==(a.simulated[3] or 0),'CPU grain pool retains only physical debris after sand procedural ownership')
end

do
  local W,V=fresh('GALE')
  -- Proving the shared backend must not virtualize leaves.
  local P=V.require('ProceduralPrecipField')
  P.probe(Vox,{kind='hail',eye={0,6,0},focus={0,0,0},wind={.5,.2},nearRadius=4,farRadius=180,topY=120,bottomY=-20,span=24,time=1,intensity=1})
  W.update(1/60,{0,0,0},{wxId='GALE',debrisIntensity=1.5},meta)
  local g=W.precipVirtualization().grain
  check((g.logical[3] or 0)>0 and (g.simulated[3] or 0)==(g.logical[3] or 0) and (g.procedural[3] or 0)==0,'leaves remain fully physical')
end

print(('near precipitation virtualization 8.1.54: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
