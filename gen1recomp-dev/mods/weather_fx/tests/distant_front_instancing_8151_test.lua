-- Weather FX 8.1.51: remote StormCell precipitation uses immutable instanced seeds
-- while preserving the full 9,000-particle max-quality population and exact CPU fallback.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local draws={};local meshBuilds=0;local shaderBuilds=0;local attach=0;local vertexMaps=0;local sends={}
local baseMesh={}
function baseMesh:setVertexMap(map) vertexMaps=vertexMaps+1;self.vertexMap=map;return true end
function baseMesh:attachAttribute(name,mesh,mode) attach=attach+1;self.attached={name=name,mesh=mesh,mode=mode};return true end
local seedMesh={seed=true}
local shader={}
function shader:send(name,...)
  sends[name]=(sends[name] or 0)+1
  return true
end
love={graphics={
  newMesh=function(fmt,rows,mode,usage) meshBuilds=meshBuilds+1;return baseMesh end,
  newShader=function(src) shaderBuilds=shaderBuilds+1;return shader end,
  drawInstanced=function(mesh,n) draws[#draws+1]=n;return true end,
  getSupported=function() return {instancing=true} end,
  setColor=function() end,setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,
}}
local Seed={get=function() return seedMesh,8192 end}
local V={require=function(n) if n=='InstanceSeedBuffer' then return Seed end error('unexpected '..tostring(n)) end}
local P=assert(loadfile(ROOT..'lib/DistantFrontPrecip.lua'))(V)
local vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},curveX=0,curveZ=0,curveK=0,beginEffect=function(sh) return true end,endEffect=function() end}
local opts={count=9000,bx=420,bz=0,crossX=0,crossZ=1,viewX=0,viewZ=1,tx=1,tz=0,width=650,depth=338,top=54,bottom=2,time=113.25,alpha=.75,kind=0,frontId=51,windX=-1,windZ=0,gust=.8}
local ok,n=P.draw(vox,opts)
ck(ok and n==9000,'full max-quality remote particle population is rendered')
ck(#draws==2 and draws[1]==8192 and draws[2]==808,'9,000 particles use two bounded instanced draws with shared 8,192 seed window')
ck(meshBuilds==1 and shaderBuilds==1 and attach==1 and vertexMaps==1,'indexed base mesh/shader/instance attribute initialize once')
local beforeChecks=P.stats().checks
local ok2,n2=P.draw(vox,{count=2400,bx=1,bz=2,crossX=1,crossZ=0,viewX=1,viewZ=0,tx=0,tz=1,width=100,depth=80,top=42,bottom=2,time=2,alpha=.5,kind=1,frontId=52})
ck(ok2 and n2==2400 and meshBuilds==1 and shaderBuilds==1 and attach==1 and vertexMaps==1,'later fronts reuse immutable GPU objects without rebuilding resources')
ck(P.stats().checks==beforeChecks,'steady-state draws skip repeated capability/resource probes')
ck(sends.instanceBase==3,'only one scalar instanceBase upload is needed per draw chunk')
local src=assert(io.open(ROOT..'lib/DistantFrontPrecip.lua','rb')):read('*a')
ck(src:find('frontId*1009.0+id*17.173',1,true)~=nil and src:find('seed+.13',1,true)~=nil and src:find('seed+14.9',1,true)~=nil,'GPU path preserves the 8.1.50 deterministic particle identity/hash family')
ck(src:find('frontWidth*.48*(.72+.28*b)',1,true)~=nil and src:find('pow(b,.72)*frontDepth',1,true)~=nil,'GPU path preserves soft lateral/front-depth distribution')
ck(src:find('48.0+c*42.0',1,true)~=nil and src:find('.55+c*1.50',1,true)~=nil,'GPU rain fall and physical size family match 8.1.50')
ck(src:find('(5.0+c*6.5)*mul',1,true)~=nil and src:find('.17+c*.31',1,true)~=nil and src:find('.24+c*.34',1,true)~=nil,'GPU snow/blizzard fall and size families match 8.1.50')
print(string.format('distant front instancing 8.1.51: %d passed, %d failed',pass,fail));os.exit(fail==0 and 0 or 1)
