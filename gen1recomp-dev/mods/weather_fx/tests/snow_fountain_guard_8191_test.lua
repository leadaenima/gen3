-- Weather FX 8.1.91: local snow has exclusive near-field presentation ownership.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n)if v then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n)end end
love={graphics={getDimensions=function()return 1280,720 end}}
local V={mod={id='weather_fx',options={get=function()return nil end}},safeCall=pcall,weatherFxChannels={snow=0}}
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
ck(C._distantSnowHandoff({weather={snowIntensity=0}},'snow')==1,'genuinely distant snow remains visible when local snow is absent')
ck(C._distantSnowHandoff({weather={snowIntensity=.019}},'snow')==1,'sub-threshold interpolation noise does not steal distant-front presentation')
ck(C._distantSnowHandoff({weather={snowIntensity=.021}},'snow')==0,'light local snow fully retires the distant slab instead of partially fading it')
ck(C._distantSnowHandoff({weather={snowIntensity=.12}},'snow')==0,'moderate local snow has exclusive near-field ownership')
V.weatherFxChannels.snow=.03
ck(C._distantSnowHandoff({weather={snowIntensity=0}},'blizzard')==0,'authoritative live channel also atomically retires stale blizzard slab during frame lag')
ck(C._distantSnowHandoff({weather={snowIntensity=.5}},'rain')==1,'rain-front continuity is untouched by snow ownership')
print(('8.1.91 snow fountain guard: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
