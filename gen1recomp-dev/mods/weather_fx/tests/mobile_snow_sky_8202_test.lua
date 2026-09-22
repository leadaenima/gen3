-- Weather FX 8.2.2: low-power 3D snow + true zenith sky render regression.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function text(p)local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end
local ps=text('lib/ProceduralSnowField.lua')
local wp=text('lib/voxel_atmos/WorldPrecip.lua')
local q=text('lib/Quality.lua')
ck(wp:find('if wantSnow>0 then',1,true)~=nil and wp:find('if wantSnow>1200 then',1,true)==nil,'all nonzero 3D snow populations may use proven GPU full-visual ownership')
ck(wp:find('if logicalActive>0 and not fullGPU then',1,true)~=nil,'low-density 3D snow probes procedural backend instead of remaining CPU-only')
ck(wp:find('drawnSnowVerts=nearVerts+farDrawn*4',1,true)~=nil,'procedural snow accounting matches four-vertex strip')
ck(q:find('worldSnowCap=100000',1,true)~=nil and q:find('worldBlizzardCap=200000',1,true)~=nil,'MAX authored 100k SNOW / 200k BLIZZARD ceilings are unchanged')
local pix=ps:match('local PIXEL_FLAKE=%[%[(.-)%]%]%s*local PIXEL_BALL') or ''
ck(#pix>0 and not pix:find('atan',1,true) and not pix:find('length(',1,true) and not pix:find('sin(',1,true),'flake fragment hot path has no atan/length/sin transcendental cost')
ck(pix:find('d0=ap.y',1,true)~=nil and pix:find('d1=abs(0.8660254*p.x+0.5*p.y)',1,true)~=nil and pix:find('ring2',1,true)~=nil,'fast fragment path retains six-arm crystalline detail and branch rings')
ck(ps:find('extern vec3 fieldAxisR;',1,true)~=nil and ps:find('vec3 right=fieldAxisR;',1,true)~=nil,'snow uses one frame billboard basis instead of per-vertex camera normalization')
ck(ps:find('vec3 right=vec3(-dir.z',1,true)==nil,'old per-vertex billboard basis is absent')
ck(ps:find('wfxLane0',1,true)~=nil and ps:find('uint q4=wfxMix32',1,true)~=nil,'native snow packs random channels into five integer mixes')
ck(ps:find('float wave=.5+.5*sin',1,true)==nil and ps:find('float cf=fract(crossp*fieldFrontCrossFreq)',1,true)~=nil,'storm patch modulation is transcendental-free')
local vert=ps:match('local VERTEX=%[%[(.-)%]%]%s*local function canGraphics') or ''
-- Strip line comments before checking executable shader tokens; comments document
-- the removed hardware trig and must not make the hot-path assertion fail.
local vertCode=vert:gsub('//[^\n]*','')
ck(#vertCode>0 and not vertCode:find('sin(',1,true) and not vertCode:find('cos(',1,true) and not vertCode:find('sqrt(',1,true) and not vertCode:find('length(',1,true) and vertCode:find('wfxSinTurn',1,true)~=nil,'3D snow vertex hot path is trig/sqrt free while retaining smooth periodic sway/tumble')
ck(ps:find('static%-page')~=nil and ps:find('STATIC_DETAIL_FLAKES=2048',1,true)~=nil and ps:find('STATIC_POINT_FLAKES=8192',1,true)~=nil,'non-instancing phones have immutable detail + point GPU page fallback')
ck(wp:find('8.2.2: prove the procedural backend BEFORE',1,true)~=nil and (wp:find('8.2.2: prove the procedural backend BEFORE',1,true) or 1) < (wp:find('if not nearHealthy then buf:reset()',1,true) or 1e9),'snow backend is proven before any first-frame CPU mesh build')

-- Real module draw proof: native path keeps counts, one draw and robust VP axes.
local shaders,draws,instances,sends={},0,0,{}
love={graphics={},timer={getTime=function()return 5 end}}
local g=love.graphics
function g.getSupported()return{instancing=true,glsl3=true}end
function g.newMesh(fmt,verts,mode,usage)return{release=function()end,attachAttribute=function()error('native must not attach seed')end}end
function g.newShader(src)shaders[#shaders+1]=src;return{send=function(self,n,v)sends[n]=v;return true end,release=function()end}end
function g.drawInstanced(_,n)draws=draws+1;instances=instances+n;return true end
function g.setBlendMode()end;function g.setDepthMode()end;function g.setShader()end;function g.setColor()end
local V={safeCall=pcall}
function V.require(n)
 if n=='MesoscaleField' then return{ready=function()return true end,renderParams=function()return{scale=520,frontScale=1180,windX=1,windZ=.2,patchiness=.7,floor=.5}end}end
 if n=='InstanceSeedBuffer' then error('not expected',0) end
 return nil
end
local P=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(V)
-- VP rows correspond to right=(1,0,0), up=(0,0,1), i.e. a camera looking straight +Y.
local zenVP={1,0,0,0, 0,0,1,0, 0,0,1,0, 0,1,0,0}
local vox={vp=zenVP,lookFlat={0,0,1},beginEffect=function()return true end,endEffect=function()end}
local o={count=1600,eye={0,0,0},focus={0,0,0},wind={.8,.2},farRadius=180,topY=110,bottomY=-18,span=64,time=5,intensity=1,tint={1,1,1}}
local ok,n=P.draw(vox,o)
ck(ok and n==1600 and draws==2 and instances>1600 and instances<1900,'POTATO-cap 3D snow uses bounded point+detail GPU draws, not CPU mesh churn')
local ar,au=sends.fieldAxisR,sends.fieldAxisU
ck(type(ar)=='table' and type(au)=='table' and math.abs((ar[1]or 0)-1)<1e-6 and math.abs((au[3]or 0)-1)<1e-6,'snow billboard axes come from zenith-safe VP rows')
o.count=200000;local d0=draws;local ok2,n2=P.draw(vox,o)
ck(ok2 and n2==200000 and draws==d0+2,'MAX BLIZZARD keeps full authored count in bounded point+detail native draws')

-- No-instancing mobile proof: ordinary Mesh page must keep snow on the GPU.
do
  local staticDraws,rangeCount=0,0;local ranges={}
  love={graphics={},timer={getTime=function()return 7 end}}
  local sg=love.graphics
  function sg.getSupported()return{instancing=false,glsl3=false}end
  function sg.newMesh(fmt,verts,mode,usage)
    return{release=function()end,setVertexMap=function()return true end,setDrawRange=function(self,start,count)rangeCount=count;ranges[#ranges+1]=count end}
  end
  function sg.newShader(src)
    ck(src:find('love_InstanceID',1,true)==nil,'static mobile shader contains no GLSL3 native-instance token')
    return{send=function()return true end,release=function()end}
  end
  function sg.draw()staticDraws=staticDraws+1;return true end
  function sg.setBlendMode()end;function sg.setDepthMode()end;function sg.setShader()end;function sg.setColor()end
  local SV={safeCall=pcall}
  function SV.require(n) if n=='MesoscaleField' then return{ready=function()return false end}end return nil end
  local SP=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(SV)
  ck(SP.supported()==true and SP.stats().backend=='static-page','phone without instancing selects immutable static GPU snow backend')
  local sok,sn=SP.draw(vox,{count=1600,eye={0,0,0},focus={0,0,0},wind={.5,.1},farRadius=180,topY=110,bottomY=-18,span=64,time=7,intensity=1,tint={1,1,1}})
  local sawPoint,sawDetail=false,false;for _,r in ipairs(ranges)do if r==1600 then sawPoint=true elseif r==64*6 then sawDetail=true end end
  ck(sok and sn==1600 and staticDraws==2 and sawPoint and sawDetail,'POTATO 1600-flake snow uses two immutable LOD GPU draws with no per-frame vertex upload')
  staticDraws=0;ranges={}
  local sok2,sn2=SP.draw(vox,{count=5000,eye={0,0,0},focus={0,0,0},wind={.5,.1},farRadius=280,topY=110,bottomY=-18,span=64,time=7.016,intensity=1,tint={1,1,1}})
  ck(sok2 and sn2==5000 and staticDraws==2,'LOW 5000-flake snow uses two immutable page draws instead of CPU mesh churn')
end

-- Cloud billboard basis: exact zenith must remain valid even when camera.up is parallel to focus ray.
local cache={}
local V2={mod={id='weather_fx',options={get=function()return nil end}},weatherFxId='RAIN_LIGHT',weatherFxChannels={rain=1},safeCall=pcall}
function V2.require(n)
 if cache[n] then return cache[n] end
 if n=='Settings' then return{cloudsOn=function()return true end,get=function()return'on'end} end
 if n=='WeatherSetting' then return{new=function()return{get=function()return'full'end}end}end
 if n=='ForestAtmos' then return{time=0,RAMP={day={fog={1,1,1},ray={1,1,1}}}}end
 if n=='MesoscaleField' then return{ready=function()return false end}end
 if n=='PerformanceGovernor' then return{scale=function()return 1 end}end
 if n=='Quality' then return{budget=function()return{worldPrecip=1}end}end
 if n=='Scene' then return{now={visible='world',outdoor=true}}end
 return{}
end
local C=assert(loadfile(ROOT..'lib/voxel_atmos/CinematicAtmos.lua'))(V2)
local cv={vp=zenVP,eye={0,8,0},focus={0,108,0},player={0,0,0},camera={up={0,1,0}},lookFlat={0,0,1},size=function()return 1280,720 end}
local cr,cu=nil,nil
if type(C.billboardBasisProbe)=='function' then cr,cu=C.billboardBasisProbe(cv) end
ck(cr and cu and math.abs(cr[1])>.9 and math.abs(cu[3])>.9,'3D cloud billboard basis survives exact upward camera pitch')

-- Sun/moon projection: horizontal-only lookFlat must not override real VP pitch.
local NV={}
function NV.require(n) return {} end
local N=assert(loadfile(ROOT..'lib/NightSky.lua'))(NV)
local host={eye={0,0,0},focus={0,0,0},lookFlat={0,0,1},vp=zenVP,fovY=math.rad(65)}
local x,y,front=N.projectDirection(host,0,1,0,640,480)
ck(x and math.abs(x-320)<1e-6 and y and math.abs(y-240)<1e-6 and front>0,'sun/moon use full VP pitch and remain centered at exact zenith')
local hx,hy=N.projectDirection(host,0,0,1,640,480)
ck(hx==nil and hy==nil,'horizontal-only lookFlat no longer falsely controls celestial vertical projection')

print(('8.2.2 mobile snow + zenith sky: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
