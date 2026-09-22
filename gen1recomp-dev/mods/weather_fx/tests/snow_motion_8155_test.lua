-- Weather FX 8.1.55+ / 8.2.0: full-GPU snow motion must remain smooth,
-- world-stable and free of whole-field player-following emitter relocation.
local passed,failed=0,0
local function check(v,n)
  if v then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n) end
end
local hostTime=100
local sentFocus={};local sentTime={};local drawInstances=0;local drawCalls=0
love={graphics={},timer={}}
function love.timer.getTime() return hostTime end
function love.graphics.getSupported() return {instancing=true,glsl3=true} end
function love.graphics.newMesh()
  return {release=function()end,attachAttribute=function()return true end}
end
function love.graphics.newShader()
  return {send=function(self,name,value)
    if name=='fieldFocus' then sentFocus[#sentFocus+1]={value[1],value[2],value[3]} end
    if name=='fieldTime' then sentTime[#sentTime+1]=value end
    return true
  end,release=function()end}
end
function love.graphics.drawInstanced(mesh,n) drawCalls=drawCalls+1;drawInstances=drawInstances+n end
function love.graphics.setBlendMode()end
function love.graphics.setDepthMode()end
function love.graphics.setShader()end
function love.graphics.setColor()end

local cache={};local V={}
function V.require(name)
  if cache[name] then return cache[name] end
  if name=='InstanceSeedBuffer' then
    local m=assert(loadfile('lib/InstanceSeedBuffer.lua'))(V);cache[name]=m;return m
  end
  if name=='MesoscaleField' then
    local m={ready=function()return true end,renderParams=function()return {scale=520,frontScale=1180,offsetX=0,offsetZ=0,windX=1,windZ=0,patchiness=0,floor=1} end}
    cache[name]=m;return m
  end
  error('no module '..name,0)
end
local P=assert(loadfile('lib/ProceduralSnowField.lua'))(V)
local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},beginEffect=function()return true end,endEffect=function()end}
local function draw(focus,time,count)
  return P.draw(Vox,{count=count or 20000,eye={focus[1],6,focus[3]},focus=focus,wind={.2,.1},nearRadius=1.5,farRadius=600,topY=120,bottomY=-20,span=32,time=time or 5,intensity=2,alpha=1,ball=false})
end

local ok,n=draw({0,0,0},5)
check(ok and n==20000,'initial procedural snow draw succeeds at full requested count')
local s=P.stats()
check(s.anchorX==0 and s.anchorZ==0 and s.anchorCell==0 and s.nextAnchorX==nil,'initial snow field has no snapped emitter cell or handoff target')
local t0=s.renderClock

local beforeCalls=drawCalls;local beforeInstances=drawInstances
hostTime=100.016
draw({8,0,0},5)
s=P.stats()
check(s.anchorX==8 and s.anchorZ==0 and s.anchorCell==0 and s.nextAnchorX==nil,'ordinary player movement has no whole-field anchor handoff')
check(drawCalls-beforeCalls==2 and drawInstances-beforeInstances>20000 and drawInstances-beforeInstances<22000,'ordinary movement keeps constant bounded point+detail snow submission')
check(s.renderClock>t0,'presentation clock advances even when caller simulation time is unchanged')
local t1=s.renderClock

sentFocus={};beforeCalls=drawCalls;beforeInstances=drawInstances
hostTime=100.032
draw({37,0,0},5)
s=P.stats()
check(s.anchorX==37 and s.anchorCell==0 and s.nextAnchorX==nil,'former snap-boundary crossing cannot schedule a moving emitter')
check(drawCalls-beforeCalls==2 and drawInstances-beforeInstances>20000 and drawInstances-beforeInstances<22000,'former boundary crossing cannot old/new whole-field double-submit beyond constant LOD passes')
local focusOK=#sentFocus==2;for _,f in ipairs(sentFocus)do focusOK=focusOK and math.abs(f[1]-37)<.001 end;check(focusOK,'both spatial LOD shaders receive the same exact live-focus periodic-copy selector')
check(s.renderClock>t1,'snow fall clock advances monotonically while walking')

local beforeClock=s.renderClock
hostTime=100.048
draw({71,0,0},1,20000)
s=P.stats()
check(s.renderClock>=beforeClock,'backward source time cannot reverse visible snow motion')
check(s.anchorX==71 and s.anchorCell==0 and s.nextAnchorX==nil,'continued traversal remains handoff-free')

local rx,rz=P.reanchor({123,0,-45},2400);s=P.stats()
check(rx==123 and rz==-45 and s.anchorX==123 and s.anchorZ==-45 and s.anchorCell==0 and s.nextAnchorX==nil,'map reanchor records exact focus without a snapped snow-emitter cell')

local f=assert(io.open('lib/ProceduralSnowField.lua','rb'));local src=f:read('*a');f:close()
check(src:find('fieldTilePhase',1,true)~=nil and src:find('fract(vec2(hA,hB) + drift*fieldTileInv - fieldTilePhase + 0.5)',1,true)~=nil and src:find('fieldFocus.x+cos(ang)*rad',1,true)==nil,'snow shader uses optimized per-flake periodic wrapping instead of a finite player-centered disk')

print(('snow motion 8.2.0 continuity: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
