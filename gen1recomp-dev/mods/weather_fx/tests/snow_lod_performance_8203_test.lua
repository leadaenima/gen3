-- Weather FX 8.2.3: screen-space-aware 3D snow LOD performance regression.
-- Dense snowfall keeps its logical population and smooth world motion, but only
-- near flakes pay for detailed translucent crystal quads. Distant flakes use
-- one point vertex / tiny raster footprint on the LÖVE 11.5 path.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function text(p)local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end
local ps=text('lib/ProceduralSnowField.lua')
local q=text('lib/Quality.lua')
ck(ps:find("{{0,0,0}},'points','static'",1,true)~=nil,'native/instanced far snow uses a one-vertex point mesh')
ck(ps:find("g.newMesh,fmt,rows,'points','static'",1,true)~=nil,'non-instancing far snow uses immutable point pages')
ck(ps:find('fieldDetailInner2',1,true)~=nil and ps:find('fieldDetailOuter2',1,true)~=nil,'far points cross-fade into near detailed snow instead of popping')
ck(ps:find('detailRatio=math.min(1,(detailRadius*detailRadius)/(farRadius*farRadius))',1,true)~=nil,'near detailed population is area-density matched to the logical field')
ck(ps:find('count>=192',1,true)~=nil,'only tiny snow populations skip hybrid LOD')
ck(q:find('worldSnowCap=100000',1,true)~=nil and q:find('worldBlizzardCap=200000',1,true)~=nil,'authored MAX SNOW/BLIZZARD logical ceilings remain 100k/200k')

local host=10
local meshes,shaders,draws={}, {}, {}
local pointSize=1
love={graphics={},timer={getTime=function()return host end}}
local g=love.graphics
function g.getSupported()return{instancing=true,glsl3=true}end
function g.newMesh(fmt,verts,mode,usage)
  local m={mode=mode,verts=#verts,release=function()end,attachAttribute=function()error('native path must not attach seed')end}
  meshes[#meshes+1]=m;return m
end
function g.newShader(src)
  shaders[#shaders+1]=src
  return{send=function()return true end,release=function()end}
end
function g.drawInstanced(m,n)draws[#draws+1]={mode=m.mode,n=n};return true end
function g.setBlendMode()end;function g.setDepthMode()end;function g.setShader()end;function g.setColor()end
function g.getPointSize()return pointSize end
function g.setPointSize(v)pointSize=v end
local V={safeCall=pcall}
function V.require(n)
 if n=='MesoscaleField' then return{ready=function()return true end,renderParams=function()return{scale=520,frontScale=1180,windX=1,windZ=.2,patchiness=.5,floor=.6}end}end
 if n=='InstanceSeedBuffer' then error('native path should not request seed buffer',0) end
 return nil
end
local P=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(V)
local vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local function opts(count,radius,time)
 return{count=count,eye={0,6,0},focus={0,0,0},wind={.8,.2},farRadius=radius,topY=110,bottomY=-18,span=64,time=time,intensity=1.9,tint={1,1,1}}
end
local ok,n=P.draw(vox,opts(1600,180,5))
local st=P.stats()
local pointN,detailN=0,0
for _,d in ipairs(draws)do if d.mode=='points'then pointN=pointN+d.n elseif d.mode=='strip'then detailN=detailN+d.n end end
ck(ok and n==1600 and st.instances==1600,'POTATO snow preserves the full 1600 logical flakes')
ck(pointN==1600 and detailN==64,'POTATO snow submits 1600 far-point carriers but only 64 detailed near crystals')
ck((pointN+detailN*4) <= 1900,'POTATO vertex workload is under 30 percent of the old all-quad path')
ck(pointSize==1,'point size state is restored after snow draw')
local hasPoint=false;for _,m in ipairs(meshes)do if m.mode=='points' and m.verts==1 then hasPoint=true end end
ck(hasPoint,'native path actually constructs the one-vertex point base')
local joined=table.concat(shaders,'\n')
local pointSrc='';for _,src in ipairs(shaders)do if src:find('#define WFX_POINT_SNOW 1',1,true) then pointSrc=pointSrc..src end end
ck(#pointSrc>0 and pointSrc:find('return vp*vec4(center,1.0);',1,true)~=nil,'far snow shader transforms only the flake center, not four billboard corners')
ck(pointSrc:find('vec3 axisX=',1,true)~=nil,'shared source retains near-detail billboard code behind the point preprocessor branch')

-- MAX desktop path: logical density is unchanged, but nearly all geometry uses
-- one-vertex points and only the near-area share uses detailed cards.
draws={};host=10.016
local okm,nm=P.draw(vox,opts(100000,600,5))
local mp,md=0,0;for _,d in ipairs(draws)do if d.mode=='points'then mp=mp+d.n elseif d.mode=='strip'then md=md+d.n end end
ck(okm and nm==100000 and mp==100000 and md==1778,'MAX SNOW keeps 100k logical density with only area-matched near detail')
ck(mp+md*4 < 110000,'MAX SNOW executes under 28 percent of the old 400k quad vertices')
draws={};host=10.032
local okb,nb=P.draw(vox,opts(200000,600,5))
local bp,bd=0,0;for _,d in ipairs(draws)do if d.mode=='points'then bp=bp+d.n elseif d.mode=='strip'then bd=bd+d.n end end
ck(okb and nb==200000 and bp==200000 and bd==3556,'MAX BLIZZARD keeps 200k logical density with bounded near detail')
ck(bp+bd*4 < 220000,'MAX BLIZZARD executes under 28 percent of the old 800k quad vertices')

-- Smoothness: presentation clock still advances every rendered frame; LOD is
-- spatial only and never lowers animation cadence.
local t0=P.stats().renderClock;host=10.048;P.draw(vox,opts(1600,180,5));local t1=P.stats().renderClock
host=10.064;P.draw(vox,opts(1600,180,5));local t2=P.stats().renderClock
ck(t1>t0 and t2>t1,'3D snow movement still advances every rendered frame')

-- No-instancing phone: both point and detail geometry are immutable pages.
do
 local sdraws={};local ranges={};local smodes={}
 love={graphics={},timer={getTime=function()return 20 end}};local sg=love.graphics
 function sg.getSupported()return{instancing=false,glsl3=false}end
 function sg.newMesh(fmt,verts,mode,usage)
   local m={mode=mode,release=function()end,setDrawRange=function(self,a,b)ranges[#ranges+1]={mode=mode,n=b}end}
   if mode=='triangles' then function m:setVertexMap()return true end end
   smodes[#smodes+1]=mode;return m
 end
 function sg.newShader(src)return{send=function()return true end,release=function()end}end
 function sg.draw(m)sdraws[#sdraws+1]=m.mode;return true end
 function sg.setBlendMode()end;function sg.setDepthMode()end;function sg.setShader()end;function sg.setColor()end
 function sg.getPointSize()return 1 end;function sg.setPointSize()end
 local SV={safeCall=pcall};function SV.require(n) if n=='MesoscaleField'then return{ready=function()return false end}end return nil end
 local SP=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(SV)
 local sok,sn=SP.draw(vox,opts(1600,180,20))
 local sawP,sawD=false,false
 for _,r in ipairs(ranges)do if r.mode=='points' and r.n==1600 then sawP=true end;if r.mode=='triangles' and r.n==64*6 then sawD=true end end
 ck(sok and sn==1600 and sawP and sawD,'no-instancing phone uses immutable 1600-point far page plus 64-crystal detail page')
 ck(#sdraws==2,'POTATO no-instancing snow needs only two immutable draws')
end

print(('8.2.3 3D snow LOD performance: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
