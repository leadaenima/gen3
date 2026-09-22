local passed,failed=0,0
local function check(v,n) if v then passed=passed+1 else failed=failed+1; print('FAIL '..n) end end
local shaderSources={};local drawCalls=0;local drawInstances=0;local attachCount=0;local meshCreates=0
love={graphics={}}
-- Attribute instancing is deliberately supported even when GLSL3 is not: this
-- is the low-end compatibility path documented by LÖVE 11.
function love.graphics.getSupported() return {instancing=true,glsl3=false} end
function love.graphics.newMesh(fmt,verts,mode,usage)
  meshCreates=meshCreates+1
  return {release=function()end,attachAttribute=function(self,name,mesh,step) attachCount=attachCount+1;return true end}
end
function love.graphics.newShader(src) shaderSources[#shaderSources+1]=src; return {send=function()return true end,release=function()end} end
function love.graphics.drawInstanced(mesh,n) drawCalls=drawCalls+1;drawInstances=drawInstances+n end
function love.graphics.setBlendMode()end;function love.graphics.setDepthMode()end;function love.graphics.setShader()end;function love.graphics.setColor()end
local cache={};local V={}
function V.require(n) if cache[n]then return cache[n]end;local f=assert(loadfile('lib/'..n..'.lua'));local m=f(V);cache[n]=m;return m end
local P=V.require('ProceduralSnowField')
check(P.supported()==true,'attribute instancing accepted without GLSL3')
check(P.canVirtualize()==false,'capability alone does not virtualize before a real draw succeeds')
local Voxel3D={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local ok,n=P.draw(Voxel3D,{count=185000,eye={0,4,0},focus={0,0,0},wind={.3,.2},nearRadius=128,farRadius=600,topY=96,bottomY=-18,span=64,time=12,intensity=1.9,tint={1,1,1}})
check(ok==true and n==185000,'procedural field preserves requested far instance count')
check(P.canVirtualize()==true,'successful real draw proves virtualization backend')
check(drawInstances>=185000 and drawInstances<200000,'all authored far point carriers plus bounded near detail are submitted')
check(drawCalls==math.ceil(185000/8192)+1,'185k attribute-seed snow uses zero-upload point chunks plus one bounded detail chunk')
check(#shaderSources==3,'flake, ball and far-point shaders compile once')
local all=table.concat(shaderSources,'\n')
check(all:find('attribute float InstanceSeed',1,true)~=nil,'shared per-instance seed drives procedural particles')
check(all:find('love_InstanceID',1,true)==nil and all:find('#pragma language glsl3',1,true)==nil,'far snow no longer requires GLSL3/love_InstanceID')
check(all:find('fieldFarFadeInv',1,true)~=nil and all:find('fieldTileSpan',1,true)~=nil,'procedural field preserves far-distance fade and bounded periodic coverage')
check(attachCount>=2 and meshCreates>=3,'detail and point bases share the static per-instance seed buffer')
local st=P.stats();check(st.instances==185000 and st.drawCalls==drawCalls and st.proven and not st.failed,'stats report healthy proven exact submission')
check(st.anchorX==0 and st.anchorZ==0,'procedural snow publishes stable world-cell anchor')
P.invalidate();check(P.stats().failed==false,'invalidate resets GPU fallback state')
print(('procedural far snow: %d passed, %d failed'):format(passed,failed));os.exit(failed==0 and 0 or 1)
