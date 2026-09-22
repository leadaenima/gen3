-- Weather FX 8.1.90: presentation work is feature-aware, never a blunt 2D/3D kill switch.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local mode='2d';local clouds=true;local celestial=false;local water=false;local host=true
local Settings={}
function Settings.isFirstPerson()return false end
function Settings.force2dPresent()return mode=='2d' end
function Settings.allow3dPresent()return mode~='2d' end
function Settings.cloudsOn()return clouds end
function Settings.use3dCelestial()return celestial end
function Settings.weatherFxWaterEnabled()return water end
local VoxelAtmos={active=function()return host end}
local HostAdapter={worldPosition=function()return 0,0 end,capabilities=function()return{}end}
local Governor={interval=function(x)return x end,auto=function()return false end,update=function()end,sample=function()return{}end}
local cache={Settings=Settings,VoxelAtmosBridge=VoxelAtmos,HostAdapter=HostAdapter,PerformanceGovernor=Governor}
local V={}
function V.require(n)
  if cache[n] then return cache[n] end
  if n=='RenderGraph' then local m=assert(loadfile(ROOT..'lib/RenderGraph.lua'))(V);cache[n]=m;return m end
  local m={update=function()end,peek=function()return{}end,sample=function()return{}end,ready=function()return true end}
  cache[n]=m;return m
end
local R=assert(loadfile(ROOT..'lib/EngineRuntime.lua'))(V)
R.configure({Settings=Settings,VoxelAtmos=VoxelAtmos})
local function policy()
  local c={};R._refreshPresentationNeeds(c);return c
end
local function enabled(id,c)
  local g=R.graph()
  for _,stage in ipairs(g.order) do for _,p in ipairs(g.stages[stage]) do if p.id==id then return (not p.enabled) or p.enabled(c) end end end
end
local c=policy()
ck(c.weather3d==false and c.clouds3d==true and c.atmos3d==true,'2D precipitation can independently retain enabled 3D cloud banks')
ck(enabled('cloud_field',c) and enabled('volumetric_weather',c) and enabled('volumetric_renderer',c),'cloud-only mixed mode keeps only cloud data/render preparation alive')
ck(not enabled('weather_world_interaction',c) and not enabled('hydrology',c) and not enabled('accumulation_geometry',c),'cloud-only mixed mode does not wake 3D precipitation/surface interaction work')

clouds=false;c=policy()
ck(c.weather3d==false and c.any3d==false,'pure 2D mode with all independent 3D features off has no 3D consumer')
ck(not enabled('cloud_field',c) and not enabled('volumetric_weather',c) and not enabled('voxel_weather',c),'pure 2D mode skips cloud/voxel weather background work')

celestial=true;c=policy()
ck(c.celestial3d and c.any3d and not c.atmos3d,'3D celestial remains independently available over 2D weather')
ck(enabled('dynamic_lighting',c) and enabled('unified_lighting',c) and enabled('voxel_weather',c),'3D celestial keeps required world-light/voxel bridge work alive')
ck(not enabled('cloud_field',c),'3D celestial alone does not wake cloud simulation when 3D CLOUDS is off')

celestial=false;water=true;c=policy()
ck(c.water3d and enabled('connected_water',c) and enabled('voxel_weather',c),'enhanced 3D water remains independently available over 2D weather')
ck(not enabled('weather_world_interaction',c),'enhanced water alone does not wake 3D precipitation interaction work')

mode='3d';clouds=true;water=true;c=policy()
ck(c.weather3d and c.atmos3d and c.any3d,'3D WEATHER mode retains full 3D weather ownership')
ck(enabled('weather_world_interaction',c) and enabled('hydrology',c) and enabled('volumetric_renderer',c),'full 3D weather keeps its required runtime passes')

local dsrc=assert(io.open(ROOT..'lib/Draw.lua','rb')):read('*a')
ck(dsrc:find('if not strict3d and NpcLightning2D and NpcLightning2D.update then',1,true)~=nil,'strict 3D skips 2D NPC-lightning simulation')
ck(dsrc:find('if Particles.suspend then',1,true)~=nil,'strict 3D releases inactive 2D particle working sets')
local psrc=assert(io.open(ROOT..'lib/Particles.lua','rb')):read('*a')
ck(psrc:find('function P.suspend()',1,true)~=nil,'2D particle system exposes transition-only RAM/VRAM suspension')
local asrc=assert(io.open(ROOT..'lib/DramalessAtmos.lua','rb')):read('*a')
ck(asrc:find('policy.weather3d=fullWeather;policy.clouds3d=cloudWeather',1,true)~=nil,'voxel atmosphere forwards mixed-mode feature policy to renderer')
local csrc=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
ck(csrc:find('if weather3d and WorldPrecip and WorldPrecip.draw then',1,true)~=nil,'cloud-only mixed mode cannot run 3D falling precipitation')

print(('8.1.90 feature-aware gating: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
