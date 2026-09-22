-- Weather FX 8.1.50: approaching precipitation fronts are the same 3D
-- hydrometeor field all the way to the local WorldPrecip handoff.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
love={graphics={getDimensions=function() return 1280,720 end}}
local Settings={cloudsOn=function() return true end,get=function() return 'on' end,cloudHeightScale=function() return 1.5 end}
local WeatherSetting={new=function() return {get=function() return 'full' end} end}
local ForestAtmos={time=113.25,RAMP={day={fog={.8,.8,.8},ray={1,1,1}}}}
local front={id=50,weather='STORM',cloudWeather='STORM',x=1000,z=0,bankX=420,bankZ=0,rx=650,rz=1400,radius=650,sizeClass='regional',vx=-1,vz=0,cloud=.95,stage='mature',shaft=.82,kind='rain',flash=0}
local DistantWeather={items=function() return {front},1 end}
local WeatherWorldSpace={toLocal=function(x,z) return x,z end}
local generic={}
local V={mod={id='weather_fx',options={get=function() return nil end}},weatherFxId='CLEAR',weatherFxChannels={}}
function V.require(n)
  if n=='Settings' then return Settings elseif n=='WeatherSetting' then return WeatherSetting elseif n=='ForestAtmos' then return ForestAtmos end
  if n=='DistantWeather' then return DistantWeather elseif n=='WeatherWorldSpace' then return WeatherWorldSpace end
  if n=='MesoscaleField' then return {ready=function() return false end} elseif n=='PerformanceGovernor' then return {scale=function() return 1 end} end
  if n=='Quality' then return {budget=function() return {worldPrecip=1} end} elseif n=='Scene' then return {now={visible='world',outdoor=true}} end
  return generic
end
V.safeCall=pcall
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local vox={eye={0,12,0},focus={0,40,200},player={0,0,0},far=1400,size=function() return 1280,720 end}
local frame={level=1,canopy=false,weather={coverage=0,cloudShade=1.02},rayColor={1,.96,.9}}
local function kinds()
  local rows,indices,n=C._buildDistantWeather(vox,frame,{id='MAP'})
  local count={};local maxA=0
  for i=1,n do local k=rows[i][7];count[k]=(count[k] or 0)+1;maxA=math.max(maxA,tonumber(rows[i][6]) or 0) end
  return count,n,#indices,maxA,rows
end
local k,n,idx,a,rows=kinds()
ck((k[5] or 0)>=800 and (k[0] or 0)==0,'rain front is hundreds of discrete 3D rain vertices, never a rain sheet/card')
ck(n>=800 and idx>=1200,'rain front submits a dense bounded 3D particle field')
-- Particle quads must occupy true depth behind the leading edge, not one plane.
local minx,maxx=1e9,-1e9
for i=1,n do if rows[i][7]==5 then minx=math.min(minx,rows[i][1]);maxx=math.max(maxx,rows[i][1]) end end
ck((maxx-minx)>80,'rain particles occupy physical front depth behind the moving leading edge')
front.weather='SNOW_LIGHT';front.cloudWeather='SNOW_LIGHT';front.kind='snow';front.shaft=.78
k,n,idx,a,rows=kinds()
ck((k[6] or 0)>=800 and (k[1] or 0)==0,'snow front is discrete 3D flakes, never a snow sheet/card')
front.weather='BLIZZARD';front.cloudWeather='BLIZZARD';front.kind='blizzard';front.gust=.95;front.shaft=.85
k,n,idx,a,rows=kinds()
ck((k[7] or 0)>=800 and (k[3] or 0)==0,'blizzard front is wind-sheared 3D flakes, never the old blizzard wall')
-- Handoff is alpha-only on stable particle identities. Lower shaft must reduce
-- opacity without replacing the particle morphology or changing coordinates.
front.weather='STORM';front.cloudWeather='STORM';front.kind='rain';front.gust=0;front.shaft=.82
local _,_,_,a1,r1=kinds();local x1,y1,z1=r1[1][1],r1[1][2],r1[1][3]
front.shaft=.28
local _,_,_,a2,r2=kinds();local x2,y2,z2=r2[1][1],r2[1][2],r2[1][3]
ck(a2<a1*.5,'near-field handoff reduces remote 3D precipitation opacity continuously')
ck(math.abs(x1-x2)<1e-9 and math.abs(y1-y2)<1e-9 and math.abs(z1-z2)<1e-9,'handoff never swaps or teleports the front particle field')

-- The production DistantWeather overlap must not exhaust remote hydrometeors
-- during the early local-ramp zone. At roughly 30% penetration the remote field
-- should still retain substantial authority; it reaches zero only deep inside.
local dsrc=assert(io.open(ROOT..'lib/DistantWeather.lua','rb')):read('*a')
ck(dsrc:find('radius*.62',1,true)~=nil and dsrc:find('shaftHandoff',1,true)~=nil,'front handoff keeps broad 62% remote/local 3D precipitation overlap')
local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
ck(src:find('painted rain/snow curtain',1,true)~=nil and src:find('particleQuad',1,true)~=nil,'source explicitly forbids painted rain/snow front curtains')
print(string.format('front precip continuity 8.1.50: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
