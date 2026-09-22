-- Weather FX 8.1.90: BLOCKY clouds are connected stepped cloud masses, not cube grids.
local ROOT=os.getenv('WX_ROOT') or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n)if v then pass=pass+1;print('PASS '..n)else fail=fail+1;print('FAIL '..n)end end
love={graphics={getDimensions=function()return 1280,720 end}}
local V={mod={id='weather_fx',options={get=function()return nil end}},safeCall=pcall,weatherFxChannels={}}
local generic={}
function V.require(n)
 if n=='Settings'then return{cloudsOn=function()return true end,cloudHeightScale=function()return 1.5 end,get=function()return'blocky'end}
 elseif n=='WeatherSetting'then return{new=function()return{get=function()return'full'end}end}
 elseif n=='ForestAtmos'then return{time=0,RAMP={day={fog={1,1,1},ray={1,1,1}}}}
 elseif n=='PerformanceGovernor'then return{scale=function()return 1 end}
 elseif n=='Quality'then return{budget=function()return{worldPrecip=1}end}
 elseif n=='Scene'then return{now={visible='world',outdoor=true}} end
 return generic
end
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V)
local frame={level=1,weather={cloudShade=1}}
local cloud={ix=11,iz=19,cx=100,cy=150,cz=220,spanX=100,spanZ=60,deckBlend=.35,fadeAlpha=1}
local rows,n=C._buildBlockCloudRows(frame,{cloud})
ck(n==18,'broken block cloud uses three merged strips instead of many individual cube tiles')
local rects={}
for q=0,2 do
 local minx,maxx,minz,maxz=1e9,-1e9,1e9,-1e9
 for i=q*6+1,q*6+6 do local r=rows[i];minx=math.min(minx,r[1]);maxx=math.max(maxx,r[1]);minz=math.min(minz,r[3]);maxz=math.max(maxz,r[3]) end
 rects[q+1]={minx,maxx,minz,maxz}
end
ck(math.abs(rects[1][4]-rects[2][3])<1e-9 and math.abs(rects[2][4]-rects[3][3])<1e-9,'stepped rows touch with no internal Z gaps')
local function overlap(a,b)return math.min(a[2],b[2])-math.max(a[1],b[1])end
ck(overlap(rects[1],rects[2])>0 and overlap(rects[2],rects[3])>0,'all stepped rows overlap in X as one connected cloud body')
local ys={};for i=1,n do ys[rows[i][2]]=true end;local yc=0;for _ in pairs(ys)do yc=yc+1 end
ck(yc==1,'connected block cloud remains one shallow horizontal plane')
cloud.deckBlend=.99;local sealed,sn=C._buildBlockCloudRows(frame,{cloud})
local minx,maxx,minz,maxz=1e9,-1e9,1e9,-1e9
for i=1,sn do local r=sealed[i];minx=math.min(minx,r[1]);maxx=math.max(maxx,r[1]);minz=math.min(minz,r[3]);maxz=math.max(maxz,r[3])end
ck(sn==6 and math.abs((maxx-minx)-100)<1e-9 and math.abs((maxz-minz)-60)<1e-9,'closed storm deck is one sealed full-span rectangle')
local src=assert(io.open(ROOT..'lib/voxel_atmos/CinematicAtmos.lua','rb')):read('*a')
ck(src:find('connected stepped cloud silhouette',1,true)~=nil and src:find('local inset=min(.42',1,true)==nil,'old per-cell gap/cube-grid construction is removed')
print(('8.1.90 block cloud coherence: %d passed, %d failed'):format(pass,fail));os.exit(fail==0 and 0 or 1)
