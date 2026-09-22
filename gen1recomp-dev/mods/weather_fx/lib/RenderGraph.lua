local V = ...

local RenderGraph = {}
RenderGraph.__index = RenderGraph

local function now()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

function RenderGraph.new(name, stages)
  local self=setmetatable({ name=name or "weather_fx", stages={}, order={}, owners={}, statsData={}, profilingEnabled=true },RenderGraph)
  for i,stage in ipairs(stages or {}) do self.stages[stage]={}; self.order[#self.order+1]=stage end
  return self
end

function RenderGraph:addStage(stage)
  if self.stages[stage] then return end
  self.stages[stage]={}; self.order[#self.order+1]=stage
end

function RenderGraph:register(stage,id,fn,opts)
  opts=opts or {}
  if type(fn)~="function" then return false,"pass is not a function" end
  if not self.stages[stage] then self:addStage(stage) end
  local owner=opts.owner or id
  local ownership=opts.ownership
  if ownership then
    local prior=self.owners[ownership]
    if prior and prior~=owner then return false,"ownership collision: "..tostring(ownership) end
    self.owners[ownership]=owner
  end
  local bucket=self.stages[stage]
  for i=1,#bucket do
    if bucket[i].id==id then return false,"duplicate pass: "..tostring(id) end
  end
  local rawInterval=opts.interval
  local intervalFn=type(rawInterval)=="function" and rawInterval or nil
  local intervalValue=intervalFn and 0 or (tonumber(rawInterval) or 0)
  local st={calls=0,total=0,max=0,errors=0,skipped=0,samples=0}
  local pass={id=id,fn=fn,priority=tonumber(opts.priority) or 0,enabled=opts.enabled,owner=owner,ownership=ownership,critical=opts.critical==true,
    interval=rawInterval,intervalFn=intervalFn,intervalValue=intervalValue,accumulator=0,maxDt=tonumber(opts.maxDt) or .5,
    profileEvery=math.max(1,math.floor(tonumber(opts.profileEvery) or 8)),profileCounter=0,stats=st}
  bucket[#bucket+1]=pass
  self.statsData[id]=st
  table.sort(bucket,function(a,b) if a.priority==b.priority then return tostring(a.id)<tostring(b.id) end return a.priority<b.priority end)
  return true
end

function RenderGraph:executeStage(stage,ctx)
  local bucket=self.stages[stage]
  if not bucket then return true end
  for i=1,#bucket do
    local pass=bucket[i]
    local enabled=true
    if pass.enabled then local ok,v=pcall(pass.enabled,ctx); enabled=ok and v~=false end
    if enabled then
      -- Slow simulation passes can run at a lower fixed rate while presentation
      -- remains frame-rate smooth. interval may be a function so the adaptive
      -- governor can stretch non-visual work under pressure without changing
      -- authored weather intensity or renderer ownership.
      local interval=pass.intervalValue or 0
      if pass.intervalFn then local ok,v=pcall(pass.intervalFn,ctx); interval=ok and tonumber(v) or 0 end
      local run=true; local passDt=tonumber(ctx and ctx.dt) or 0
      if interval>0 then
        -- Accumulation must be able to REACH the requested interval. The old
        -- code capped it at maxDt (0.5s by default), which made every pass
        -- scheduled slower than that mathematically impossible to execute.
        -- Keep elapsed scheduling time separately, run at most once per frame,
        -- and retain a bounded remainder so AUTO interval stretching cannot
        -- freeze a subsystem under load.
        local incoming=math.max(0,passDt)
        local cap=math.max(interval*2,pass.maxDt or .5)
        pass.accumulator=math.min(cap,(pass.accumulator or 0)+incoming)
        if pass.accumulator+1e-9<interval then
          run=false
        else
          local elapsed=pass.accumulator
          pass.accumulator=math.max(0,elapsed-interval)
          -- A scheduled pass should receive the interval it represents, while
          -- still respecting an explicitly larger maxDt chosen by a caller.
          passDt=math.min(elapsed,math.max(interval,pass.maxDt or .5))
        end
      end
      local st=pass.stats
      if not run then st.skipped=(st.skipped or 0)+1 else
        local oldDt=ctx and ctx.dt; if ctx then ctx.dt=passDt end
        pass.profileCounter=(pass.profileCounter or 0)+1
        local measure=self.profilingEnabled~=false and (pass.profileCounter % (pass.profileEvery or 8))==1
        local t0=measure and now() or 0
        local ok,err=pcall(pass.fn,ctx)
        if measure then local measured=now()-t0; st.total=st.total+measured; st.samples=(st.samples or 0)+1; if measured>st.max then st.max=measured end end
        if ctx then ctx.dt=oldDt end
        st.calls=st.calls+1
        if not ok then
          st.errors=st.errors+1; st.lastError=tostring(err)
          if pass.critical then return false,err end
        end
      end
    end
  end
  return true
end

function RenderGraph:execute(ctx)
  for i=1,#self.order do
    local ok,err=self:executeStage(self.order[i],ctx)
    if not ok then return false,err,self.order[i] end
  end
  return true
end

function RenderGraph:stats()
  local out={name=self.name,passes={}}
  for id,s in pairs(self.statsData) do local samples=tonumber(s.samples) or tonumber(s.calls) or 0; out.passes[id]={calls=s.calls,total=s.total,max=s.max,errors=s.errors,skipped=s.skipped or 0,samples=samples,lastError=s.lastError,avg=samples>0 and s.total/samples or 0} end
  return out
end

-- Internal zero-allocation profiler view. Public stats() still returns copies.
function RenderGraph:rawStats() return self.statsData end
function RenderGraph:setProfilingEnabled(v) self.profilingEnabled=v~=false end

function RenderGraph:ownership() local o={}; for k,v in pairs(self.owners) do o[k]=v end; return o end

return RenderGraph
