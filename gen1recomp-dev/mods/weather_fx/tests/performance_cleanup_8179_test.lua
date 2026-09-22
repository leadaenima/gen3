-- Weather FX 8.1.79 zero-quality-loss runtime cleanup regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(p) local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end
local manifest=read('manifest.json')
ck(manifest:find('"version": "8.1.79"',1,true)~=nil,'manifest declares 8.1.79')

local rg=read('lib/RenderGraph.lua')
ck(rg:find('intervalFn=type(rawInterval)=="function"',1,true)~=nil,'RenderGraph caches interval type at registration')
ck(rg:find('local st=pass.stats',1,true)~=nil,'RenderGraph uses pass-owned stats on hot execute path')
local R=assert(loadfile(ROOT..'lib/RenderGraph.lua'))({})
local g=R.new('8179',{'sim'});local calls=0
ck(g:register('sim','fixed',function(ctx) calls=calls+1 end,{interval=.1,profileEvery=999})==true,'RenderGraph fixed pass registers')
g:executeStage('sim',{dt=.05});ck(calls==0,'cached fixed interval still skips early frame')
g:executeStage('sim',{dt=.05});ck(calls==1,'cached fixed interval still executes at exact accumulated cadence')

local pp=read('lib/ProceduralPrecipField.lua')
local ps=read('lib/ProceduralSnowField.lua')
ck(pp:find('module-owned and reused',1,true)~=nil and not pp:find('local fields={',1,true),'procedural rain/grain reuses uniform scratch')
ck(ps:find('persistent uniform/vector scratch',1,true)~=nil and not ps:find('local fields={',1,true),'procedural snow reuses uniform scratch')

local wp=read('lib/voxel_atmos/WorldPrecip.lua')
ck(wp:find('WP._procScratch={',1,true)~=nil,'WorldPrecip owns persistent procedural option scratch')
ck(wp:find('worldGrid=WP._uniformPrecipField==true',1,true)~=nil,'8.1.78 rendered-world rain ownership is retained')
ck(assert(loadfile(ROOT..'lib/voxel_atmos/WorldPrecip.lua'))~=nil,'WorldPrecip remains under Lua local/compile limits')

local sp=read('lib/SnowSurfacePaint.lua')
ck(sp:find('P._radiiScratch={}',1,true)~=nil,'SnowSurfacePaint reuses radial lookup scratch')
ck(sp:find('local okRaster=pcall(rasterize)',1,true)~=nil and not sp:find('pcall(P._data.setPixel',1,true),'snow raster protects one batch instead of every texel')
ck(sp:find('P._invOutputScratch={}',1,true)~=nil,'cinematic snow depth repaint reuses matrix inverse scratch')

local sm=read('lib/WeatherShadowMap.lua')
ck(sm:find('local TO_UNIT_POS=',1,true)~=nil and sm:find('local FIT_DIR=',1,true)~=nil,'shadow fit immutable/small vectors are cached')
ck(sm:find('Fit once.',1,true)~=nil and not sm:find('local xs = {',1,true),'shadow recast performs one fit without corner arrays')
ck(sm:find('floor(l/texel)',1,true)~=nil,'continuous light-space no-snap contract remains documented')

local cs=read('lib/Constellations.lua')
ck(cs:find('local function ensureStars()',1,true)~=nil,'constellation star expansion is deferred')
local C=assert(loadfile(ROOT..'lib/Constellations.lua'))({})
ck(rawget(C,'STARS')==nil and rawget(C,'BY_NAME')==nil,'constellation module starts without 8,507 expanded star objects')
ck(C.count()==8507,'lazy constellation build preserves exact 8,507 traced stars')
ck(type(rawget(C,'STARS'))=='table' and #rawget(C,'STARS')==8507,'first constellation access publishes exact star table')

local cf=read('lib/CloudField.lua')
ck(cf:find('local baseCloud=',1,true)~=nil and cf:find('local ACTIVE_CELLS=',1,true)~=nil,'CloudField caches frame-invariant climate/cell values')

ck(wp:find('local RAIN_MAX = 12000',1,true)~=nil,'rain 12,000 cap preserved')
ck(wp:find('local HAIL_MAX = 45000',1,true)~=nil,'hail 45,000 cap preserved')
ck(wp:find('local SNOW_MAX = 100000',1,true)~=nil,'snow base cap preserved')

print(('performance cleanup 8.1.79: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
