-- Weather FX 8.2.1: low-power-phone 3D snow hot-path regression.
-- Preserve full counts + per-frame smooth motion while removing redundant vertex work.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
if ROOT=='' then ROOT='./' end;if ROOT:sub(-1)~='/' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local host=10
local meshVerts,meshMode=nil,nil
local shaders={};local draws=0;local instances=0;local sends={}
love={graphics={},timer={getTime=function()return host end}}
local g=love.graphics
function g.getSupported() return {instancing=true,glsl3=true} end
function g.newMesh(fmt,verts,mode,usage)
  meshVerts=#verts;meshMode=mode
  return {release=function()end,attachAttribute=function()error('native path should not attach InstanceSeed')end}
end
function g.newShader(src)
  shaders[#shaders+1]=src
  return {send=function(self,name,value)
    if type(value)=='table' then local t={};for i=1,#value do t[i]=value[i] end;sends[name]=t else sends[name]=value end
    return true
  end,release=function()end}
end
function g.drawInstanced(_,n)draws=draws+1;instances=instances+(tonumber(n)or 0);return true end
function g.setBlendMode()end;function g.setDepthMode()end;function g.setShader()end;function g.setColor()end
local V={safeCall=pcall}
function V.require(n)
  if n=='MesoscaleField' then return {ready=function()return true end,renderParams=function()return{scale=520,frontScale=1180,offsetX=20,offsetZ=-15,windX=3,windZ=4,patchiness=.65,floor=.55}end} end
  if n=='InstanceSeedBuffer' then error('native path must not need seed buffer',0) end
  return nil
end
local P=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(V)
local vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local o={count=100000,eye={37,6,-22},focus={37,0,-22},wind={.8,.25},nearRadius=1.5,farRadius=600,topY=110,bottomY=-18,span=64,time=5,intensity=2.3,tint={1,1,1}}
local ok,n=P.draw(vox,o)
ck(ok and n==100000 and draws==2 and instances>100000 and instances<110000,'ordinary 3D SNOW keeps full 100,000 logical flakes with bounded point+detail GPU work')
local pf=assert(io.open(ROOT..'lib/ProceduralSnowField.lua','rb'));local psrc=pf:read('*a');pf:close();ck(psrc:find("{{-1,1,0},{1,1,0},{-1,-1,0},{1,-1,0}}",1,true)~=nil and psrc:find("{{0,0,0}},'points','static'",1,true)~=nil,'snow keeps four-vertex near detail and adds one-vertex far points')
local sh=table.concat(shaders,'\n')
ck(sh:find('fract(vec2(hA,hB) + drift*fieldTileInv - fieldTilePhase + 0.5)',1,true)~=nil,'periodic continuity uses normalized tile-phase fract formulation')
ck(sh:find('floor((fieldFocus.xz-worldXZ)/tileSpan+0.5)',1,true)==nil and sh:find('/tileSpan',1,true)==nil,'snow hot path has no old per-vertex tile dynamic divide/floor selector')
ck(sh:find('length(wd)',1,true)==nil and sh:find('delta/ps',1,true)==nil and sh:find('along/fs',1,true)==nil,'frame-constant patch normalization/divisions are absent from snow vertex hot path')
ck(sh:find('if (fieldPatchiness>0.0001)',1,true)~=nil,'fronts-off/uniform 3D snow skips storm-band trigonometry')
ck(sh:find('wfxMix32',1,true)~=nil and (sh:find('floatBitsToUint',1,true)~=nil or (sh:find('uint(love_InstanceID)',1,true)~=nil and sh:find('wfxLane0',1,true)~=nil)),'native GLSL3 snow uses sine-free integer bit-mix hashing')
ck(sh:find('fract(sin(n*12.9898+78.233)*43758.5453123)',1,true)==nil,'native GLSL3 production shader removes trigonometric hash calls')
local pw=sends.fieldPatchWind or {0,0};local plen=math.sqrt((pw[1]or 0)^2+(pw[2]or 0)^2)
ck(math.abs(plen-1)<1e-6,'patch wind is normalized once on CPU before the GPU draw')
ck(type(sends.fieldTileInv)=='number' and sends.fieldTileInv>0 and type(sends.fieldFarFadeInv)=='number' and sends.fieldFarFadeInv>0,'tile/far reciprocals are precomputed once per draw')
ck(type(sends.fieldPatchFreq)=='number' and type(sends.fieldFrontFreq)=='number','patch/front frequencies are precomputed once per draw')

-- Algebra proof: optimized normalized-phase form equals the exact 8.2.0 nearest-periodic-copy form.
local function fract(x)return x-math.floor(x)end
local function oldwrap(h,drift,focus,span)
  local w=h*span+drift
  return w+math.floor((focus-w)/span+.5)*span
end
local function newwrap(h,drift,focus,span)
  local inv=1/span;local phase=fract(focus*inv)
  local rel=(fract(h+drift*inv-phase+.5)-.5)*span
  return focus+rel
end
local same=true
for _,span in ipairs({32,1063.472310546,4253.889242184}) do
  for _,focus in ipairs({-3000.25,-1064,-10.2,0,17.75,1064.1,9000.5}) do
    for _,h in ipairs({.0001,.123,.499,.731,.9991}) do
      for _,drift in ipairs({-700.2,-120.5,0,91.25,680.75}) do
        if math.abs(oldwrap(h,drift,focus,span)-newwrap(h,drift,focus,span))>1e-7 then same=false end
      end
    end
  end
end
ck(same,'optimized tile-phase wrap is numerically equivalent to 8.2.0 world continuity')

-- Smooth movement contract: host presentation time advances every frame even if simulation time is unchanged.
local st0=P.stats();host=10.016;o.focus={37.2,0,-21.9};o.eye={37.2,6,-21.9};P.draw(vox,o);local st1=P.stats()
host=10.032;o.focus={37.4,0,-21.8};o.eye={37.4,6,-21.8};P.draw(vox,o);local st2=P.stats()
ck(st1.renderClock>st0.renderClock and st2.renderClock>st1.renderClock,'3D snow animation phase advances every rendered frame for smooth motion')
ck(draws==6 and instances>300000 and instances<330000,'smooth walking frames retain bounded two-pass LOD with no whole-field handoff/double-submit')

-- MAX blizzard remains full logical density with bounded two-pass LOD.
o.count=200000;host=10.048;o.time=5;local before=draws;local okb,nb=P.draw(vox,o)
ck(okb and nb==200000 and draws-before==2,'MAX BLIZZARD retains full 200,000 logical flakes in point+detail draws')

print(('8.2.1 mobile 3D snow performance: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
