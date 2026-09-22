-- Weather FX 8.1.81 zero-quality-loss CPU/GPU/RAM/VRAM resource regression.
local ROOT=(arg and arg[1]) or ((arg and arg[0] or ''):match('^(.*)tests[/\\][^/\\]*$') or './')
if ROOT~='' and ROOT:sub(-1)~='/' and ROOT:sub(-1)~='\\' then ROOT=ROOT..'/' end
local pass,fail=0,0
local function ck(v,n) if v then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n) end end
local function read(p) local f=assert(io.open(ROOT..p,'rb'));local s=f:read('*a');f:close();return s end

local manifest=read('manifest.json');local baseline=read('BASELINE')
local waterSrc=read('lib/voxel_atmos/ConnectedWater3D.lua')
local tornadoSrc=read('lib/voxel_atmos/Tornado3D.lua')
local shadowSrc=read('lib/WeatherShadowMap.lua')
local batchSrc=read('lib/ParticleBatcher.lua')
local nightSrc=read('lib/NightSky.lua')
local rainbowSrc=read('lib/voxel_atmos/Rainbow3D.lua')
local wp=read('lib/voxel_atmos/WorldPrecip.lua')

local _,_,vpatch=manifest:match('"version"%s*:%s*"(%d+)%.(%d+)%.(%d+)"')
ck((tonumber(vpatch) or 0)>=81,'manifest preserves 8.1.81+ resource baseline')
local bpatch=baseline:match('8%.1%.(%d+)')
ck((tonumber(bpatch) or 0)>=81,'BASELINE marker preserves 8.1.81+ resource baseline')

-- Particle budgets / visible ownership are immutable release requirements.
ck(wp:find('local RAIN_MAX = 12000',1,true)~=nil,'rain 12,000 cap preserved')
ck(wp:find('local HAIL_MAX = 45000',1,true)~=nil,'hail 45,000 cap preserved')
ck(wp:find('local SNOW_MAX = 100000',1,true)~=nil,'snow 100,000 base cap preserved')
ck(waterSrc:find('CW.windX,CW.windZ',1,true)~=nil,'water still consumes both live prevailing-wind axes')
ck(tornadoSrc:find('local top=cloudY(T)',1,true)~=nil and tornadoSrc:find('if r.stage=="forming" then bottom=top-5-(top-gy-5)*form',1,true)~=nil,'tornado still forms downward from live cloud deck')

-- Exact water-wave math: optimization changes loop mechanics, not output.
local Vnone={require=function() return nil end}
local CW3=assert(loadfile(ROOT..'lib/voxel_atmos/ConnectedWater3D.lua'))(Vnone)
local pi=math.pi
local function train(a,w,s,wt)local f=2*pi/w;return {math.cos(a)*f,math.sin(a)*f,s,wt} end
local a=.73
local Water={WAVE_TRAINS={train(a,78,1,.46),train(a,39,2,.17),train(a,26,3,.06),train(a+.46,51,.72,.20),train(a-.82,23,-.52,.11)},WAVE_SWELL=train(a+.08,290,.42,.32),WAVE_BEND=train(a+pi*.5,220,.28,.95)}
local r,sx,sz=CW3._waveSampleAtT(Water,100.25,-44.5,3.2,7.25)
ck(math.abs(r-0.70418507517034046)<1e-14 and math.abs(sx+0.52566123009100596)<1e-14 and math.abs(sz+0.43050904446505478)<1e-14,'optimized water hot loop is numerically identical at reference sample')
ck(waterSrc:find('if l2>lim*lim and l2>0 then local l=sqrt(l2)',1,true)~=nil,'water avoids sqrt when orbital clamp is not needed')
ck(waterSrc:find('local waterCtx={curve={0,0,0},screen={0,0}}',1,true)~=nil,'water draw context reuses persistent nested vectors')
ck(waterSrc:find('if d and type(d.release)=="function" then hostTry(d.release,d) end',1,true)~=nil,'generated water ImageData is released after GPU upload')

-- Generic dynamic mesh growth must retire superseded VRAM immediately.
do
  local created,released=0,0
  love={graphics={newMesh=function(fmt,cap) created=created+1;return {setVertices=function() end,setDrawRange=function() end,release=function() released=released+1 end} end,draw=function() end,drawInstanced=function() end}}
  local B=assert(loadfile(ROOT..'lib/ParticleBatcher.lua'))(Vnone)
  local verts={};for i=1,400 do verts[i]={0,0,0} end
  local m=B.upload(nil,nil,verts,100,'stream',0)
  local m2=B.upload(m,nil,verts,300,'stream',0)
  ck(created==2 and m2~=m,'particle batcher grows buffer only when capacity is exceeded')
  ck(released==1,'particle batcher immediately releases superseded GPU mesh')
end

-- Tornado owns its renderer completely, so prove identical dense geometry with
-- persistent Lua rows and right-sized GPU capacity. This keeps cloud descent and
-- waterspout appearance while removing steady-frame table churn.
do
  local list={{id=1,x=40,z=40,age=30,formation=8,stage='roam',ropeAge=0,ropeFor=12,spin=4.6,waterBlend=1,groundY=0}}
  local mods={Tornado={renderState=function() return list end,cloudBase=function() return 180 end},CinematicAtmos={precipitationDeck=function() return 177 end},WeatherState={elapsed=5}}
  local V={require=function(n) return mods[n] end};local meshCreates,meshReleases,shaderReleases,cap,maxY=0,0,0,0,-1e9
  love={graphics={newShader=function() return {send=function() end,release=function() shaderReleases=shaderReleases+1 end} end,newMesh=function(fmt,c) meshCreates=meshCreates+1;cap=c;return {setVertices=function(self,v,s,n) for i=1,n do if v[i][2]>maxY then maxY=v[i][2] end end end,setDrawRange=function() end,release=function() meshReleases=meshReleases+1 end} end,setBlendMode=function() end,setDepthMode=function() end,setShader=function() end,setColor=function() end,draw=function() end}}
  local T3=assert(loadfile(ROOT..'lib/voxel_atmos/Tornado3D.lua'))(V);local Vox={vp={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},eye={0,20,-40},beginEffect=function() return false end,endEffect=function() end}
  ck(T3.draw(Vox)==true,'optimized waterspout still submits real 3D geometry')
  local n,layers=T3.geometryStatus()
  ck(n>3000 and layers.shell and layers.sheath and layers.wallCloud and layers.waterSpray and layers.debris,'optimized waterspout preserves all dense realism layers')
  ck(maxY>180,'optimized tornado remains physically attached into live cloud deck')
  ck(cap>=n and cap<4096 and cap%256==0,'tornado GPU mesh is right-sized without dropping vertices')
  local c0=meshCreates;ck(T3.draw(Vox)==true and meshCreates==c0,'steady tornado frames reuse the same GPU mesh')
  T3.invalidate();ck(meshReleases==1 and shaderReleases==1,'tornado hard invalidation explicitly releases mesh and shader VRAM')
end

ck(tornadoSrc:find('local row=verts[vertCount]',1,true)~=nil,'tornado reuses persistent vertex rows instead of allocating per vertex/frame')
ck(tornadoSrc:find('quadS(',1,true)~=nil and not tornadoSrc:find('local col={',1,true),'tornado hot geometry uses scalar quads without transient color/point tables')
ck(shadowSrc:find('if state.spriteMode==on then return end',1,true)~=nil,'shadow pass skips redundant sprite uniform sends')
ck(shadowSrc:find('if model~=nil or not state.modelIdentity then',1,true)~=nil,'shadow pass skips redundant identity model uniform sends')
ck(batchSrc:find('oldMesh.release',1,true)~=nil,'shared particle mesh growth has explicit VRAM retirement')
ck(nightSrc:find('safe(mesh.release,mesh)',1,true)~=nil,'night-sky stream mesh failure retires old GPU buffer before recreation')
ck(rainbowSrc:find('oldMesh.release',1,true)~=nil,'rainbow capacity growth retires old GPU buffer')

print(('resource efficiency 8.1.81: %d passed, %d failed'):format(pass,fail))
os.exit(fail==0 and 0 or 1)
