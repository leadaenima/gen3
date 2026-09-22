-- Weather FX 8.1.99: dense snow/blizzard must not replay an 8,192-row
-- per-instance seed window across dozens of draws on GLSL3 hosts. Native
-- love_InstanceID gives every flake a unique identity without replaying seed windows.
-- 8.2.3 spatial LOD uses one far-point pass plus one bounded near-detail pass.
local ROOT=(arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './'
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1; print('PASS '..n) else fail=fail+1; print('FAIL '..n) end end
local shaders,draws,instances,meshCreates,baseVerts,baseMode={},0,0,0,nil,nil
love={graphics={}}
local g=love.graphics
function g.getSupported() return {instancing=true,glsl3=true} end
function g.newMesh(fmt,verts,mode,usage)
  meshCreates=meshCreates+1;baseVerts=#verts;baseMode=mode
  return {release=function()end,attachAttribute=function() error('native-id snow must not attach shared seed mesh') end}
end
function g.newShader(src) shaders[#shaders+1]=src; return {send=function()return true end,release=function()end} end
function g.drawInstanced(_,n) draws=draws+1;instances=instances+(tonumber(n) or 0); return true end
function g.setBlendMode()end; function g.setDepthMode()end; function g.setShader()end; function g.setColor()end
local V={safeCall=pcall}
function V.require(name)
  if name=='MesoscaleField' then return {ready=function()return false end} end
  if name=='InstanceSeedBuffer' then error('8.1.99 native snow should not request InstanceSeedBuffer',0) end
  return assert(loadfile(ROOT..'lib/'..name..'.lua'))(V)
end
local P=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(V)
ck(P.supported()==true,'GLSL3 host accepts native instance-id snow backend')
ck(P.stats().backend=='native-id','native instance-id backend selected on GLSL3 host')
local Voxel3D={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local opts={count=200000,eye={0,4,0},focus={0,0,0},wind={.7,.2},nearRadius=1.5,farRadius=600,topY=96,bottomY=-18,span=64,time=0,intensity=5.5,tint={1,1,1}}
local ok,n=P.draw(Voxel3D,opts)
ck(ok and n==200000,'MAX blizzard preserves exact 200,000 authored flakes')
ck(draws==2 and instances>200000 and instances<220000,'MAX blizzard uses bounded native point+detail draws instead of replaying seed chunks')
ck(meshCreates==2,'native snow creates only detail + far-point bases and no per-instance seed mesh')
local src=table.concat(shaders,'\n')
ck(src:find('#pragma language glsl3',1,true)~=nil and src:find('love_InstanceID',1,true)~=nil,'native shader derives procedural identity from love_InstanceID')
ck(src:find('attribute float InstanceSeed',1,true)==nil,'native production shaders contain no replayable InstanceSeed attribute')
-- Move across former anchor boundaries. Total density remains exact and the
-- continuous periodic renderer still uses one native draw, never repeated seed windows.
opts.focus={30,0,0}; opts.time=.1; P.draw(Voxel3D,opts)
draws,instances=0,0
opts.time=.9; local ok2,n2=P.draw(Voxel3D,opts)
ck(ok2 and n2==200000 and instances>200000 and instances<220000,'continuous field preserves exact logical blizzard density while walking')
ck(draws==2,'walking BLIZZARD remains constant point+detail LOD with no whole-field handoff')

-- A quirky host may advertise GLSL3 but reject the native-id shader dialect.
-- The release must fail open to the established attribute-seed path instead of
-- dropping the blizzard. Exercise that fallback separately.
do
  local fallbackDraws,fallbackInstances=0,0
  love={graphics={}}
  local fg=love.graphics
  function fg.getSupported() return {instancing=true,glsl3=true} end
  function fg.newMesh() return {release=function()end,attachAttribute=function()return true end} end
  function fg.newShader(src)
    if src:find('love_InstanceID',1,true) then error('simulated native shader rejection') end
    return {send=function()return true end,release=function()end}
  end
  function fg.drawInstanced(_,n) fallbackDraws=fallbackDraws+1;fallbackInstances=fallbackInstances+(tonumber(n) or 0);return true end
  function fg.setBlendMode()end;function fg.setDepthMode()end;function fg.setShader()end;function fg.setColor()end
  local FV={safeCall=pcall}
  function FV.require(name)
    if name=='MesoscaleField' then return {ready=function()return false end} end
    if name=='InstanceSeedBuffer' then return {get=function()return {release=function()end},8192 end} end
    return assert(loadfile(ROOT..'lib/'..name..'.lua'))(FV)
  end
  local FP=assert(loadfile(ROOT..'lib/ProceduralSnowField.lua'))(FV)
  ck(FP.supported()==true and FP.stats().backend=='attribute-seed','native shader rejection falls back to established attribute-seed backend')
  local fok,fn=FP.draw(Voxel3D,{count=20000,eye={0,4,0},focus={0,0,0},wind={0,0},nearRadius=1.5,farRadius=600,topY=96,bottomY=-18,span=64,time=1,intensity=5.5,tint={1,1,1}})
  ck(fok and fn==20000 and fallbackInstances>20000 and fallbackInstances<22000,'fallback backend preserves authored logical snow population with bounded detail')
  ck(fallbackDraws==math.ceil(20000/8192)+1,'legacy non-native fallback retains bounded 8,192-point chunks plus one near-detail chunk')
end

print(('8.1.99 native snow instance-id regression: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
