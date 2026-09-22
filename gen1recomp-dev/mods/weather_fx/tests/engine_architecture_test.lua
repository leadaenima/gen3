local passed,failed=0,0
local function check(ok,name) if ok then passed=passed+1 else failed=failed+1; print('FAIL '..name) end end

local cache={}
local V={}
function V.require(name)
  if cache[name] then return cache[name] end
  local f=assert(loadfile('lib/'..name..'.lua')); local m=f(V); cache[name]=m; return m
end

local Graph=V.require('RenderGraph')
local g=Graph.new('test',{'a','b'}); local order={}
check(g:register('a','late',function() order[#order+1]='late' end,{priority=20,ownership='sky',owner='wx'}),'register pass')
check(g:register('a','early',function() order[#order+1]='early' end,{priority=10}),'register priority pass')
local okCollision=g:register('b','foreign',function() end,{ownership='sky',owner='other'})
check(okCollision==false,'single-owner render contract rejects collision')
check(g:executeStage('a',{})==true and table.concat(order,',')=='early,late','stable priority execution')

local Pool=V.require('ObjectPool'); local pool=Pool.new(function() return {v=1} end,function(o) o.v=0 end,{maxFree=2})
local p1=pool:acquire(); pool:release(p1); local p2=pool:acquire()
check(p1==p2 and p2.v==0,'object pool reuses and resets objects')
pool:release(p2); check(pool:stats().created==1,'object pool avoids repeat allocation')

local SI=V.require('SpatialIndex'); local idx=SI.new(64)
idx:insert('a',0,0,0,{name='a'}); idx:insert('b',200,0,0,{name='b'})
check(#idx:queryRadius(0,0,80,{})==1,'spatial index radius culls distant objects')
idx:clear(); check(idx:stats().count==0 and idx:stats().pool.free>=2,'spatial records return to pool')

local Chunk=V.require('ChunkSim'); local cs=Chunk.new({chunkSize=64,activeRadius=1,sleepRadius=2})
cs:updateCenter(0,0); local st=cs:stats(); check(st.active==9,'chunk simulation activates bounded 3x3 neighborhood')
local c=cs:at(0,0,true); c.data.keep=true; cs:updateCenter(1000,1000); check(cs:get(0,0,false)~=nil,'non-empty sleeping chunk state persists')

local Surface=V.require('EnvironmentSurface'); Surface.depositWet(10,20,.5); Surface.depositSnow(10,20,.25); Surface.depositLeaves(10,20,.2); Surface.scorch(10,20,.3)
local sm=Surface.sample(10,20)
check(sm.wet>0 and sm.snow>0 and sm.leaves>0 and sm.scorch>0,'sparse surface state combines environment channels')
Surface.update(1,10,20,{temperature=12,humidity=.3}); check(Surface.stats().cells>=1,'surface engine updates active chunks')

local WS=V.require('WeatherSimulation')
local fake={ch={rain=.8,fog=.2,dim=.5,gust=.6,strike=18,warm=.1}}
WS.update(10,fake); local w=WS.sample()
check(w.humidity>.45 and w.cloud>.15 and w.storm>0,'weather simulation derives continuous meteorology from channels')

local A=V.require('AtmosphereModel'); A.update(1,w,{sun={altitudeDeg=4}}); local grade=A.grade()
check(grade.warmth>0 and grade.haze>0,'atmosphere responds to solar altitude and aerosols')

local PB=V.require('ParticleBatcher'); local cap=PB.capabilities()
check(type(cap)=='table' and cap.mesh~=nil,'particle batcher capability probe is fail-open')

print(('engine architecture: %d passed, %d failed'):format(passed,failed))
os.exit(failed==0 and 0 or 1)
