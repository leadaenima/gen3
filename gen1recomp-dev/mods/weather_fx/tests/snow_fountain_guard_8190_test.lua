-- Weather FX 8.1.90: no duplicate distant slab and no secondary visible instanced snow column.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n)if v then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n)end end
love={graphics={getDimensions=function()return 1280,720 end}}
local V={mod={id='weather_fx',options={get=function()return nil end}},safeCall=pcall,weatherFxChannels={snow=.65}}
local generic={}
function V.require(n)
 if n=='Settings'then return{cloudsOn=function()return true end,get=function()return'on'end,cloudHeightScale=function()return 1.5 end}
 elseif n=='WeatherSetting'then return{new=function()return{get=function()return'full'end}end}
 elseif n=='ForestAtmos'then return{time=0,RAMP={day={fog={1,1,1},ray={1,1,1}}}}
 elseif n=='PerformanceGovernor'then return{scale=function()return 1 end}
 elseif n=='Quality'then return{budget=function()return{worldPrecip=1}end}
 elseif n=='Scene'then return{now={visible='world',outdoor=true}} end
 return generic
end
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local frame={weather={snowIntensity=0}}
ck(C._distantSnowHandoff(frame,'snow')==0,'authoritative live snow channel retires stale distant snow slab even when frame profile lags')
ck(C._distantSnowHandoff(frame,'blizzard')==0,'authoritative live snow channel also retires stale distant blizzard slab')
ck(C._distantSnowHandoff(frame,'rain')==1,'rain distant-front ownership is unchanged')
local wsrc=assert(io.open(ROOT..'lib/voxel_atmos/WorldPrecip.lua','rb')):read('*a')
local drawStart=assert(wsrc:find('local function drawSnowFlakes',1,true));local drawEnd=assert(wsrc:find('-- ---------------------------------------------------------------------------\n-- DRAW: FACE SPECKS',drawStart,true))
local body=wsrc:sub(drawStart,drawEnd)
ck(body:find('snowInstance.draw(',1,true)==nil,'visible snow path no longer calls secondary instanced backend that can collapse into a fountain')
ck(body:find('local nearHealthy=fullGPU',1,true)~=nil,'driver-proven procedural full field remains the dense GPU snow owner')
ck(body:find('if not nearHealthy then',1,true)~=nil,'unsupported/small snow falls back to explicit world-XYZ CPU cards')
ck(wsrc:find('function WP.suspend()',1,true)~=nil,'inactive 3D precipitation can release transient snow working sets')
local suspendStart=assert(wsrc:find('function WP.suspend()',1,true)); local suspendEnd=assert(wsrc:find('function WP.invalidate()',suspendStart,true)); local suspendBody=wsrc:sub(suspendStart,suspendEnd)
ck(suspendBody:find('drawnGrainVerts=0',1,true)==nil,'suspend preserves grain counter table shape for safe feature resume')
ck(suspendBody:find('drawnGrainVerts[k]=0',1,true)~=nil,'suspend clears grain counters per slot instead of replacing their table')
print(('8.1.90 snow fountain guard: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
