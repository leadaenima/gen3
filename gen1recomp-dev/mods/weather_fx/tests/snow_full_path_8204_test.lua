-- Weather FX 8.2.4: exhaustive 3D snow CPU-path / accumulation performance regression.
--
-- This test exists because renderer-only LOD tests missed two real phone hot
-- paths: (1) a failed procedural backend could route the complete logical storm
-- through CPU integration/dynamic-mesh fallback, and (2) accumulation OFF still
-- built SnowPack support and exact-resolved invisible flakes every frame.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end

local budgets={
 potato={worldPrecip=.28,worldRadiusCap=180,worldSnowCap=1600,worldBlizzardCap=2400,snowProbeCap=16,snow=360,snowPackDrawCap=600,footDrawCap=40,splash=0},
 low={worldPrecip=.42,worldRadiusCap=280,worldSnowCap=5000,worldBlizzardCap=8000,snowProbeCap=28,snow=720,snowPackDrawCap=1200,footDrawCap=72,splash=0},
 medium={worldPrecip=.62,worldRadiusCap=420,worldSnowCap=15000,worldBlizzardCap=24000,snowProbeCap=48,snow=1640,snowPackDrawCap=2200,footDrawCap=112,splash=55},
 high={worldPrecip=.88,worldRadiusCap=600,worldSnowCap=45000,worldBlizzardCap=70000,snowProbeCap=72,snow=3200,snowPackDrawCap=3400,footDrawCap=160,splash=120},
 max={worldPrecip=1.0,worldRadiusCap=750,worldSnowCap=100000,worldBlizzardCap=200000,snowProbeCap=96,snow=4800,snowPackDrawCap=4800,footDrawCap=192,splash=180},
}
local snowIds={'SNOW','SNOW_LIGHT','BLIZZARD','THUNDERSNOW','SLEET','WHITEOUT','ICEBOUND','FROSTBOG','FROSTWAVE','SNOWSHREW','TSNOW','DRAGONSTORM'}

local function makeHarness(gpuGood,accum,firstPerson)
  local tier='potato'
  local calls={beginFrame=0,resolveFlake=0,spUpdate=0,fillGround=0,fillFoot=0,deposit=0,interaction=0}
  local SP={ACCUMULATION_ENABLED=true}
  local accumulation=accum==true
  function SP.setEnabled(on) accumulation=on~=false;return accumulation end
  function SP.beginFrame(meta,ground)
    calls.beginFrame=calls.beginFrame+1
    return {collisionEnabled=true,fallbackGroundY=ground or 0,regions={{key='x'}},regionByKey={}}
  end
  function SP.resolveFlake(...) calls.resolveFlake=calls.resolveFlake+1;return nil end
  function SP.update(...) calls.spUpdate=calls.spUpdate+1 end
  function SP.fillGroundPool(pool) calls.fillGround=calls.fillGround+1;pool.active=0;return 0 end
  function SP.fillFootPool(pool) calls.fillFoot=calls.fillFoot+1;pool.active=0;return 0 end
  function SP.deposit(...) calls.deposit=calls.deposit+1;return nil,nil end
  function SP.depositAggregate(...) calls.deposit=calls.deposit+1;return nil,nil end
  function SP.surfaceAt(ctx,x,z) return 0,'ground' end

  local Settings={}
  function Settings.snowAccumulationEnabled() return accumulation end
  function Settings.isFirstPerson() return firstPerson==true end
  function Settings.weatherRenderDistanceScale() return 1 end
  function Settings.snowShape() return 'flake' end
  function Settings.snowIntensity() return 1 end
  function Settings.splashesEnabled() return false end
  function Settings.get(k) if k=='snowAccumulation' then return accumulation and 'on' or 'off' end return nil end

  local PS={}
  function PS.canVirtualize() return gpuGood==true end
  function PS.stats() return {proven=gpuGood==true,failed=gpuGood~=true,backend=gpuGood and 'native-id' or 'failed'} end

  local WIP={}
  function WIP.update(...) calls.interaction=calls.interaction+1 end
  function WIP.draw() end
  function WIP.stats() return {active=0} end

  local V={safeCall=pcall}
  function V.require(name)
    if name=='Quality' then return {budget=function()return budgets[tier] end} end
    if name=='Settings' then return Settings end
    if name=='SnowPack' then return SP end
    if name=='ProceduralSnowField' then return PS end
    if name=='WorldInteractionPrecip' then return WIP end
    if name=='WeatherWorldInteraction' then return {peek=function()return nil end} end
    if name=='MesoscaleField' then return {ready=function()return false end} end
    return nil
  end
  local WP=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
  local focus={100,0,100}
  local meta={Voxel3D={far=600},player={px=100,py=100},map={id='m',widthCells=50,heightCells=50},neighbors={}}
  local function resetCalls() for k in pairs(calls) do calls[k]=0 end end
  local function run(id,q,frames)
    tier=q;resetCalls();if WP.reset then WP.reset() end
    local w={wxId=id,snowIntensity=(id=='BLIZZARD' and 2.2 or 1.9)}
    for _=1,frames do WP.update(1/60,focus,w,meta) end
    return WP.snowVirtualization(),calls
  end
  return WP,run,calls,focus,meta,function(q) tier=q end
end

-- Every supported snow-family weather must take the zero-SnowPack procedural
-- path when accumulation is OFF. This is the user's reported bad state.
do
  local WP,run=makeHarness(true,false,false)
  local all=true
  for _,id in ipairs(snowIds) do
    local st,c=run(id,'potato',60)
    all=all and st.logical>0 and st.fullVisual==true and st.procedural==st.logical
      and st.simulated<=1 and c.beginFrame==0 and c.resolveFlake==0 and c.spUpdate==0 and c.interaction==0
  end
  ck(all,'all 12 3D snow weather families use procedural visual ownership with zero SnowPack/support work when accumulation is OFF')
end

-- Across every quality tier, accumulation OFF must stay independent of the
-- old exact-terrain support path while logical visual density remains intact.
do
  local WP,run=makeHarness(true,false,false)
  local ok=true
  for _,q in ipairs({'potato','low','medium','high','max'}) do
    for _,id in ipairs({'SNOW','BLIZZARD'}) do
      local st,c=run(id,q,600)
      ok=ok and st.logical>0 and st.procedural==st.logical and st.fullVisual==true
        and st.simulated<=1 and c.beginFrame==0 and c.resolveFlake==0 and c.spUpdate==0
    end
  end
  ck(ok,'SNOW/BLIZZARD accumulation-OFF hot path stays zero-support from POTATO through MAX')
end

-- Accumulation ON still works, but support staging is a slow process: context,
-- ground pool and footprint staging are bounded near 10 Hz, and procedural
-- visual flakes never exact-sweep terrain one-by-one.
do
  local WP,run=makeHarness(true,true,false)
  local ok=true
  for _,q in ipairs({'potato','low','medium','high','max'}) do
    for _,id in ipairs({'SNOW','BLIZZARD'}) do
      local st,c=run(id,q,600)
      ok=ok and st.fullVisual==true and st.simulated<=1 and c.resolveFlake==0
        and c.beginFrame>=80 and c.beginFrame<=120
        and c.fillGround==c.beginFrame and c.fillFoot==c.beginFrame
        and c.spUpdate==600 and c.deposit>0
    end
  end
  ck(ok,'accumulation ON stages support/ground/foot pools near 10 Hz with zero per-flake terrain sweeps')
end

-- Force the procedural backend unavailable. This is the compatibility path the
-- earlier tests did not execute. It must NEVER integrate the 100k/200k logical
-- storm on the CPU; the existing per-tier `snow` budget is the hard CPU-visible
-- cap, and exact terrain sweeps are separately bounded by snowProbeCap.
do
  local WP,run=makeHarness(false,false,false)
  local ok=true
  for _,q in ipairs({'potato','low','medium','high','max'}) do
    for _,id in ipairs({'SNOW','BLIZZARD'}) do
      local st,c=run(id,q,1)
      ok=ok and st.cpuFallback==true and st.procedural==0 and st.simulated<=budgets[q].snow
        and c.beginFrame==0 and c.resolveFlake==0
      if id=='BLIZZARD' then ok=ok and st.logical>=st.simulated end
    end
  end
  ck(ok,'GPU-failure compatibility path is hard-capped by per-tier CPU snow budget and does zero SnowPack work when accumulation is OFF')
end

do
  local ok=true
  for _,q in ipairs({'potato','low','medium','high','max'}) do
    -- Use a fresh module instance per tier so the Quality budget cache cannot
    -- carry the previous tier into this deliberately short negative-control case.
    local WP,run=makeHarness(false,true,false)
    local st,c=run('BLIZZARD',q,2)
    ok=ok and st.simulated<=budgets[q].snow and c.beginFrame==1
      and c.resolveFlake<=budgets[q].snowProbeCap*2
  end
  ck(ok,'GPU-failure + accumulation path keeps CPU population and exact collision sweeps independently bounded on every tier')
end

-- First-person keeps only the small face-contact sample after GPU ownership is
-- proven; third-person does not pay for 16-96 invisible snow probes.
do
  local WP,run,calls,focus,meta,setTier=makeHarness(true,false,true)
  setTier('max')
  -- lastEye is learned in draw(), so use a minimal graphics-free frame to seed it.
  local st=run('SNOW','max',1)
  -- With no prior eye the first update is telemetry-only. The source contract
  -- below pins the first-person cap itself because a real draw is host-specific.
  local f=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb'));local src=f:read('*a');f:close()
  ck(src:find('return min(wantSnow,min(16,qcap))',1,true)~=nil,'first-person procedural snow face-contact probes are capped at 16')
end

-- Rain continues to own the support/interaction path; the snow optimization
-- must not silently disable roof/canopy/material rain impacts.
do
  local WP,run,calls,focus,meta,setTier=makeHarness(true,false,false)
  setTier('potato');for k in pairs(calls)do calls[k]=0 end
  if WP.reset then WP.reset() end
  local w={wxId='RAIN',rainIntensity=1.0}
  for _=1,60 do WP.update(1/60,focus,w,meta) end
  ck(calls.beginFrame==60 and calls.interaction==60,'rain still refreshes support and world-interaction precipitation every frame')
end

print(('8.2.4 full 3D snow path audit: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
