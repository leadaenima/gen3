-- Weather FX 8.2.6: cross-weather phone/desktop performance ownership audit.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local budgets={
 potato={worldPrecip=.28,worldRadiusCap=180,worldRainCap=550,worldHailCap=800,worldSandCap=900,worldDebrisCap=260,worldAshCap=600,rain=90,snow=360,grain=60,splash=0},
 low={worldPrecip=.42,worldRadiusCap=280,worldRainCap=1400,worldHailCap=2500,worldSandCap=2500,worldDebrisCap=650,worldAshCap=1500,rain=160,snow=720,grain=110,splash=0},
 medium={worldPrecip=.62,worldRadiusCap=420,worldRainCap=3500,worldHailCap=8000,worldSandCap=7000,worldDebrisCap=1400,worldAshCap=3600,rain=380,snow=1640,grain=260,splash=55},
 high={worldPrecip=.88,worldRadiusCap=600,worldRainCap=7000,worldHailCap=22000,worldSandCap=18000,worldDebrisCap=2600,worldAshCap=7200,rain=720,snow=3200,grain=520,splash=120},
 max={worldPrecip=1,worldRadiusCap=750,worldRainCap=12000,worldHailCap=45000,worldSandCap=43200,worldDebrisCap=3600,worldAshCap=10800,rain=1100,snow=4800,grain=800,splash=180},
}

local function makeHarness(gpuGood)
  local tier='potato'
  local Settings={}
  function Settings.weatherRenderDistanceScale() return 1 end
  function Settings.snowAccumulationEnabled() return false end
  function Settings.isFirstPerson() return false end
  function Settings.snowShape() return 'flake' end
  function Settings.snowIntensity() return 1 end
  function Settings.get() return nil end
  local PP={}
  function PP.supported() return gpuGood==true end
  function PP.canVirtualize() return gpuGood==true end
  function PP.stats() return {proven=gpuGood==true,failed=gpuGood~=true} end
  local PS={canVirtualize=function() return false end,stats=function() return {failed=true} end}
  local SP={ACCUMULATION_ENABLED=false,setEnabled=function()end,update=function()end}
  local WIP={update=function()end,stats=function()return {active=0}end}
  local V={safeCall=pcall}
  function V.require(name)
    if name=='Quality' then return {budget=function()return budgets[tier] end} end
    if name=='Settings' then return Settings end
    if name=='ProceduralPrecipField' then return PP end
    if name=='ProceduralSnowField' then return PS end
    if name=='SnowPack' then return SP end
    if name=='WorldInteractionPrecip' then return WIP end
    if name=='WeatherWorldInteraction' then return {peek=function()return nil end} end
    if name=='MesoscaleField' then return {ready=function()return false end} end
    if name=='LeafPhysics' then return nil end
    return nil
  end
  local WP=assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))(V)
  local focus={100,0,100}
  local meta={Voxel3D={far=600},player={px=100,py=100},map={id='m',widthCells=80,heightCells=80},neighbors={}}
  local function run(q,w,frames)
    tier=q;if WP.reset then WP.reset() end
    for _=1,(frames or 1) do WP.update(1/60,focus,w,meta) end
    return WP.precipVirtualization()
  end
  return run
end

local gpu=makeHarness(true)
local allGpu=true
for _,q in ipairs({'potato','low','medium','high','max'}) do
  local r=gpu(q,{wxId='RAIN_LIGHT',rainIntensity=.45},2).rain
  allGpu=allGpu and r.logical>0 and r.fullVisual==true and r.procedural==r.logical and r.simulated<=96
  local h=gpu(q,{wxId='HAIL',hailIntensity=1.2},2).grain
  allGpu=allGpu and h.logical[1]~=nil and h.fullVisual[1]==true and h.procedural[1]==h.logical[1] and h.simulated[1]==0
  local s=gpu(q,{wxId='SANDSTORM',sandIntensity=2.0,debrisIntensity=0},2).grain
  allGpu=allGpu and s.fullVisual[2]==true and s.procedural[2]==s.logical[2] and s.simulated[2]==0
  local a=gpu(q,{wxId='ASHFALL',ashIntensity=1.4},2).grain
  allGpu=allGpu and a.fullVisual[4]==true and a.procedural[4]==a.logical[4] and a.simulated[4]==0
end
ck(allGpu,'proven GPU owns every nonzero rain/hail/sand/ash visual population from POTATO through MAX')

local cpu=makeHarness(false)
local caps=true
for _,q in ipairs({'potato','low','medium','high','max'}) do
  local r=cpu(q,{wxId='HEAVY_RAIN',rainIntensity=2.0},1).rain
  caps=caps and r.simulated<=budgets[q].rain and r.procedural==0 and r.fullVisual==false
  local h=cpu(q,{wxId='HAIL',hailIntensity=1.5},1).grain
  caps=caps and h.simulated[1]<=budgets[q].grain and h.procedural[1]==0
  local s=cpu(q,{wxId='SANDSTORM',sandIntensity=2.3,debrisIntensity=0},1).grain
  caps=caps and s.simulated[2]<=budgets[q].grain and s.procedural[2]==0
  local a=cpu(q,{wxId='ASHFALL',ashIntensity=1.8},1).grain
  caps=caps and a.simulated[4]<=budgets[q].grain and a.procedural[4]==0
end
ck(caps,'GPU-failure rain/hail/sand/ash CPU fallbacks are hard-capped by quality budgets')

local clear=cpu('max',{wxId='CLEAR',rainIntensity=0,hailIntensity=0,sandIntensity=0,ashIntensity=0,debrisIntensity=0},2)
local clearOk=clear.rain.logical==0 and clear.rain.simulated==0
for i=1,4 do clearOk=clearOk and (clear.grain.logical[i] or 0)==0 and (clear.grain.simulated[i] or 0)==0 end
ck(clearOk,'CLEAR retires rain/grain simulation immediately')

-- Leaves intentionally remain physical; performance work must not silently virtualize gameplay-visible settling/collision.
local src=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
ck(src:find("grain.simTarget%[kind%]=%(kind==3%) and logical or min%(logical,cpuGrainCap%)")~=nil,'debris/leaves remain physical while noninteractive grain fallback is capped')
ck(src:find('if kind~=3 and logical>0 and grain.proceduralOK',1,true)~=nil,'low-count noninteractive grains no longer have a >1200 CPU-only threshold')
ck(src:find('local cpuRainCap=max(24,floor(tonumber(qb.rain) or 720))',1,true)~=nil,'rain compatibility path is capped before simulation allocation')

local psrc=assert(io.open(ROOT..'lib/ProceduralPrecipField.lua','rb')):read('*a')
ck(psrc:find("{{-1,1,0},{1,1,0},{-1,-1,0},{1,-1,0}},'strip','static'",1,true)~=nil,'shared procedural precipitation uses four unique strip vertices instead of six duplicated vertices')
ck(psrc:find('float h1(float n){n=fract(n*0.1031);',1,true)~=nil and psrc:find('fract(sin(n*12.9898',1,true)==nil,'shared precipitation identity hash is trig-free')
ck(psrc:find('float wfxSinTurn',1,true)~=nil and psrc:find('float crossWave=wfxSinTurn',1,true)~=nil,'shared precipitation storm-band/wander animation uses smooth trig-free periodic math')
ck(psrc:find('atan(p.y,p.x)',1,true)==nil,'ash fragment silhouette no longer uses per-pixel atan')

local csrc=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
local iInst=csrc:find('local irows,icount=CinematicAtmos._buildCloudInstances',1,true) or 1e9
local iFallback=csrc:find('local verts, indices = buildCloudVertices',1,true) or 0
ck(iInst<iFallback,'primary cloud-bank path prefers compact instancing before dynamic quad fallback')
ck(csrc:find('CinematicAtmos._puddleReflectionPool=CinematicAtmos._puddleReflectionPool or {}',1,true)~=nil,'wet-weather reflection scan reuses pooled puddle descriptors')

print(('8.2.6 all-weather performance ownership audit: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
