-- ============================================================================
-- WEATHER FX + VOXEL REALISM IN-GAME BENCHMARK
-- ============================================================================
-- A deterministic, non-persistent benchmark harness for comparing real PCs and
-- mod revisions. It deliberately measures the WHOLE frame via the host-provided
-- dt while separately timing Weather FX update and 3D-atmosphere work when a
-- high-resolution timer is available.
--
-- Start from the developer console:
--   weather benchmark full     (~2 minutes, recommended)
--   weather benchmark quick    (~30 seconds)
--   weather benchmark status
--   weather benchmark stop
--   weather benchmark last
--
-- The benchmark does NOT lower quality or particle budgets. It uses the user's
-- currently selected Weather FX + voxel-host settings, changes only temporary
-- weather/time state, and restores the original WeatherState/TimeOfDay snapshot
-- at completion. No filesystem APIs are required; detailed results go to the
-- mod log and the concise summary remains available through `last`.
-- ============================================================================

local V = ...
local mod = V.mod
local B = {}

local State = V.require("WeatherState")
local TOD = V.require("TimeOfDay")
local Settings = V.require("Settings")
local Quality = V.require("Quality")
local Scene = V.require("Scene")

local floor, max, min = math.floor, math.max, math.min

local FULL = {
  { id="CLEAR",       label="CLEAR BASELINE", warm=2.0, measure=8.0,  tod="DAY" },
  { id="RAIN_HEAVY",  label="HEAVY RAIN",    warm=3.0, measure=12.0, tod="DAY" },
  { id="GALE",        label="GALE / LEAVES", warm=4.0, measure=15.0, tod="DAY" },
  { id="BLIZZARD",    label="BLIZZARD / SNOW",warm=5.0,measure=18.0, tod="DAY" },
  { id="SANDSTORM",   label="SANDSTORM",     warm=3.0, measure=12.0, tod="DAY" },
  { id="FOG",         label="FOG / FILL",    warm=3.0, measure=10.0, tod="DAY" },
  { id="PSYSTORM",    label="PSYCHIC STORM", warm=4.0, measure=15.0, tod="DAY" },
  { id="CLEAR",       label="NIGHT / CELESTIAL",warm=3.0,measure=10.0,tod="NITE" },
}

local QUICK = {
  { id="CLEAR",      label="CLEAR BASELINE", warm=1.5, measure=4.0, tod="DAY" },
  { id="GALE",       label="GALE / LEAVES", warm=2.0, measure=5.0, tod="DAY" },
  { id="BLIZZARD",   label="BLIZZARD / SNOW",warm=2.5,measure=6.0, tod="DAY" },
  { id="PSYSTORM",   label="PSYCHIC STORM", warm=2.0, measure=5.0, tod="DAY" },
}

local S = {
  active=false, mode="full", phases=FULL, phaseIndex=0, phaseElapsed=0,
  snapshot=nil, results={}, current=nil, last=nil, lastSummary=nil,
  updateStart=nil, atmosStart=nil, presentStart=nil,
  lastUpdateMs=0, lastAtmosMs=0, lastPresentMs=0,
  sampleClock=0, startedAt=0, warning=nil,
}

local function now()
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,t=pcall(love.timer.getTime)
    if ok and type(t)=="number" then return t end
  end
  return os.clock()
end

local function copyChannels(src)
  local out={}
  if type(src)=="table" then for k,v in pairs(src) do out[k]=v end end
  return out
end

local function restoreSnapshot()
  local x=S.snapshot
  if not x then return end
  State.id=x.id
  State.left=x.left
  State.level=x.level
  State.mode=x.mode
  State.pinnedBy=x.pinnedBy
  State.elapsed=x.elapsed
  State.dirty=x.dirty
  State.softFrom=x.softFrom;State.softTo=x.softTo;State.softT=x.softT;State.softDur=x.softDur
  State.mapsTowardCommit=x.mapsTowardCommit;State.fresh=x.fresh
  State._gentleIntro=x.gentleIntro;State._sessionStart=x.sessionStart;State._needOutdoorStart=x.needOutdoorStart
  State.lastMapId=x.lastMapId
  State._suppressPersist=x.suppressPersist
  if type(State.ch)=="table" then
    for k in pairs(State.ch) do State.ch[k]=nil end
    for k,v in pairs(x.ch or {}) do State.ch[k]=v end
  end
  TOD.pin=x.todPin
  S.snapshot=nil
end

local function graphicsStats(out)
  out=out or {}
  local g=love and love.graphics
  if g and type(g.getStats)=="function" then
    local ok,st=pcall(g.getStats)
    if ok and type(st)=="table" then
      out.drawcalls=tonumber(st.drawcalls) or 0
      out.drawcallsbatched=tonumber(st.drawcallsbatched) or 0
      out.texturememory=tonumber(st.texturememory) or 0
      out.images=tonumber(st.images) or 0
      out.canvases=tonumber(st.canvases) or 0
      return out
    end
  end
  out.drawcalls=0;out.drawcallsbatched=0;out.texturememory=0;out.images=0;out.canvases=0
  return out
end

local function newMetric(phase)
  return {
    id=phase.id,label=phase.label,warm=phase.warm,measure=phase.measure,tod=phase.tod,
    frames=0,sumDt=0,minDt=1e9,maxDt=0,frameTimes={},stutter33=0,stutter50=0,stutter100=0,
    sumUpdateMs=0,maxUpdateMs=0,sumAtmosMs=0,maxAtmosMs=0,sumPresentMs=0,maxPresentMs=0,
    telemetrySamples=0,sumLuaMB=0,peakLuaMB=0,sumDrawCalls=0,peakDrawCalls=0,
    peakTextureMB=0,peakRain=0,peakSnow=0,peakGrain=0,peakGroundSnow=0,peakFootprints=0,
    peakSnowCells=0,peakPackFootprints=0,
  }
end

local function applyPhase()
  local p=S.phases[S.phaseIndex]
  if not p then return false end
  State.setWeather(p.id,"benchmark")
  State.settle()
  TOD.pin=p.tod
  S.current=newMetric(p)
  S.phaseElapsed=0
  S.sampleClock=0
  return true
end

function B.enforce()
  if not S.active then return end
  local p=S.phases[S.phaseIndex]
  if not p then return end
  if State.id~=p.id then
    State.setWeather(p.id,"benchmark")
    State.settle()
  end
  TOD.pin=p.tod
end

local function phasePercent()
  local p=S.phases[S.phaseIndex]
  if not p then return 1 end
  return min(1,max(0,S.phaseElapsed/max(0.001,p.warm+p.measure)))
end

local function percentile(sorted,p)
  local n=#sorted
  if n==0 then return 0 end
  local i=floor((n-1)*p+1.5)
  if i<1 then i=1 elseif i>n then i=n end
  return sorted[i]
end

local function lowFps(frameTimes,fraction)
  local n=#frameTimes
  if n==0 then return 0 end
  local copy={}
  for i=1,n do copy[i]=frameTimes[i] end
  table.sort(copy,function(a,b) return a>b end)
  local count=max(1,floor(n*fraction+0.5))
  local sum=0
  for i=1,count do sum=sum+copy[i] end
  return count/max(sum,1e-9)
end

local function finishMetric(m)
  if not m then return nil end
  local copy={}
  for i=1,#m.frameTimes do copy[i]=m.frameTimes[i] end
  table.sort(copy)
  local n=max(1,m.frames)
  local t=max(1,m.telemetrySamples)
  m.avgMs=(m.sumDt/n)*1000
  m.avgFps=(m.sumDt>0) and (m.frames/m.sumDt) or 0
  m.onePct=lowFps(m.frameTimes,0.01)
  m.pointOnePct=lowFps(m.frameTimes,0.001)
  m.p95Ms=percentile(copy,0.95)*1000
  m.p99Ms=percentile(copy,0.99)*1000
  m.avgUpdateMs=m.sumUpdateMs/n
  m.avgAtmosMs=m.sumAtmosMs/n
  m.avgPresentMs=m.sumPresentMs/n
  m.avgLuaMB=m.sumLuaMB/t
  m.avgDrawCalls=m.sumDrawCalls/t
  m.frameTimes=nil
  return m
end

local function aggregate(results)
  local a={frames=0,sumDt=0,stutter33=0,stutter50=0,stutter100=0,peakLuaMB=0,peakTextureMB=0,
           peakDrawCalls=0,worstOnePct=1e9,worstPhase="-",maxUpdateMs=0,maxAtmosMs=0,maxPresentMs=0}
  local weightedOne=0
  for _,m in ipairs(results) do
    a.frames=a.frames+(m.frames or 0);a.sumDt=a.sumDt+(m.sumDt or 0)
    a.stutter33=a.stutter33+(m.stutter33 or 0);a.stutter50=a.stutter50+(m.stutter50 or 0);a.stutter100=a.stutter100+(m.stutter100 or 0)
    a.peakLuaMB=max(a.peakLuaMB,m.peakLuaMB or 0);a.peakTextureMB=max(a.peakTextureMB,m.peakTextureMB or 0);a.peakDrawCalls=max(a.peakDrawCalls,m.peakDrawCalls or 0)
    a.maxUpdateMs=max(a.maxUpdateMs,m.maxUpdateMs or 0);a.maxAtmosMs=max(a.maxAtmosMs,m.maxAtmosMs or 0);a.maxPresentMs=max(a.maxPresentMs,m.maxPresentMs or 0)
    if (m.onePct or 0)<a.worstOnePct then a.worstOnePct=m.onePct or 0;a.worstPhase=m.label or m.id end
    weightedOne=weightedOne+(m.onePct or 0)*(m.frames or 0)
  end
  a.avgFps=(a.sumDt>0) and a.frames/a.sumDt or 0
  a.avgMs=(a.frames>0) and a.sumDt/a.frames*1000 or 0
  a.weightedOne=(a.frames>0) and weightedOne/a.frames or 0
  if a.worstOnePct==1e9 then a.worstOnePct=0 end
  return a
end

local function rating(a)
  if a.worstOnePct>=115 and a.avgFps>=120 then return "EXCELLENT-120" end
  if a.worstOnePct>=58 and a.avgFps>=60 then return "EXCELLENT-60" end
  if a.worstOnePct>=50 and a.avgFps>=58 then return "GOOD-60" end
  if a.worstOnePct>=40 and a.avgFps>=50 then return "PLAYABLE" end
  if a.worstOnePct>=28 then return "MARGINAL" end
  return "TOO-SLOW"
end

local function logReport(report)
  if not (mod and mod.log and mod.log.info) then return end
  pcall(function()
    mod.log:info("WXBENCH %s | avg %.1f fps | weighted 1%% %.1f | worst 1%% %.1f (%s) | %s",
      report.mode:upper(),report.aggregate.avgFps,report.aggregate.weightedOne,
      report.aggregate.worstOnePct,report.aggregate.worstPhase,report.rating)
    for i,m in ipairs(report.phases) do
      mod.log:info("WXBENCH %d/%d %s | avg %.1f | 1%% %.1f | 0.1%% %.1f | p95 %.2fms p99 %.2fms | wxU %.2fms wx3D %.2fms | dc %.0f/%d | lua %.1f/%.1fMB tex %.1fMB | particles r%d s%d g%d pack%d foot%d",
        i,#report.phases,m.label,m.avgFps,m.onePct,m.pointOnePct,m.p95Ms,m.p99Ms,
        m.avgUpdateMs,m.avgAtmosMs,m.avgDrawCalls,m.peakDrawCalls,m.avgLuaMB,m.peakLuaMB,m.peakTextureMB,
        m.peakRain,m.peakSnow,m.peakGrain,m.peakSnowCells,m.peakPackFootprints)
    end
  end)
end

local function finish(reason)
  if S.current and S.current.frames>0 then
    S.results[#S.results+1]=finishMetric(S.current)
  end
  local a=aggregate(S.results)
  local g=love and love.graphics
  local w,h=0,0
  if g and type(g.getDimensions)=="function" then pcall(function() w,h=g.getDimensions() end) end
  local bridge=nil
  pcall(function() bridge=V.require("VoxelAtmosBridge") end)
  local voxel=false; if bridge and bridge.active then pcall(function() voxel=bridge.active() and true or false end) end
  local report={
    mode=S.mode,reason=reason or "complete",phases=S.results,aggregate=a,rating=rating(a),
    quality=Quality.describe(),present=Settings.presentMode(),mapId=tostring(Scene.now and Scene.now.mapId or "-"),
    outdoor=Scene.now and Scene.now.outdoor==true,voxelActive=voxel,resolution={w,h},
    seconds=max(0,now()-(S.startedAt or now())),
  }
  report.summary=("%s %s | %.1f avg FPS | %.1f weighted 1%% | %.1f worst 1%% (%s) | %s | %dx%d | quality %s | voxel %s"):format(
    "WXBENCH",S.mode:upper(),a.avgFps,a.weightedOne,a.worstOnePct,a.worstPhase,report.rating,w,h,tostring(report.quality),voxel and "ON" or "OFF")
  S.last=report;S.lastSummary=report.summary
  S.active=false;S.current=nil;S.phaseIndex=0;S.phaseElapsed=0
  restoreSnapshot()
  logReport(report)
  return report
end

function B.start(mode)
  if S.active then return false,"benchmark already running" end
  mode=tostring(mode or "full"):lower()
  if mode~="quick" and mode~="full" then return false,"benchmark mode must be quick or full" end
  S.mode=mode;S.phases=(mode=="quick") and QUICK or FULL
  S.results={};S.current=nil;S.phaseIndex=1;S.phaseElapsed=0;S.warning=nil
  S.snapshot={id=State.id,left=State.left,level=State.level,mode=State.mode,pinnedBy=State.pinnedBy,
    elapsed=State.elapsed,dirty=State.dirty,ch=copyChannels(State.ch),todPin=TOD.pin,
    softFrom=State.softFrom,softTo=State.softTo,softT=State.softT,softDur=State.softDur,
    mapsTowardCommit=State.mapsTowardCommit,fresh=State.fresh,gentleIntro=State._gentleIntro,
    sessionStart=State._sessionStart,needOutdoorStart=State._needOutdoorStart,lastMapId=State.lastMapId,
    suppressPersist=State._suppressPersist}
  State._suppressPersist=true
  S.startedAt=now();S.active=true
  local bridge=nil;pcall(function() bridge=V.require("VoxelAtmosBridge") end)
  local voxel=false;if bridge and bridge.active then pcall(function() voxel=bridge.active() and true or false end) end
  if not voxel then S.warning="Voxel 3D bridge is not active; result will not represent Weather FX + Voxel Realism together." end
  if Scene.now and Scene.now.indoors then S.warning="Benchmark started indoors; use an outdoor map for comparable results." end
  applyPhase()
  return true,("started %s benchmark (%d phases)%s"):format(mode,#S.phases,S.warning and (" | WARNING: "..S.warning) or "")
end

function B.stop()
  if not S.active then return false,"no benchmark is running" end
  local r=finish("stopped")
  return true,r.summary
end

function B.preUpdate(dt)
  if not S.active then return end
  dt=tonumber(dt) or 0
  if dt<0 then dt=0 elseif dt>2.0 then dt=0.25 end
  -- Benchmark time should follow real rendered time even on a very slow
  -- device. Only multi-second focus/window stalls are collapsed as hitches.
  S.phaseElapsed=S.phaseElapsed+dt
  local p=S.phases[S.phaseIndex]
  if p and S.phaseElapsed >= p.warm+p.measure then
    if S.current and S.current.frames>0 then S.results[#S.results+1]=finishMetric(S.current) end
    S.current=nil
    S.phaseIndex=S.phaseIndex+1
    if S.phaseIndex>#S.phases then finish("complete");return end
    applyPhase()
  end
  B.enforce()
end

function B.beginUpdate()
  if S.active then S.updateStart=now() end
end
function B.endUpdate(dt)
  if not S.active then return end
  local t=now(); if S.updateStart then S.lastUpdateMs=max(0,(t-S.updateStart)*1000) end
  local p=S.phases[S.phaseIndex];local m=S.current
  if not (p and m) then return end
  if S.phaseElapsed < p.warm then return end
  dt=tonumber(dt) or 0
  -- Count genuinely slow rendered frames: discarding every >0.5 s sample made
  -- the benchmark blind exactly when a low-end device was performing worst.
  -- Multi-second focus/window stalls remain excluded as non-gameplay samples.
  if dt<=0 or dt>2.0 then return end
  m.frames=m.frames+1;m.sumDt=m.sumDt+dt;m.minDt=min(m.minDt,dt);m.maxDt=max(m.maxDt,dt)
  m.frameTimes[#m.frameTimes+1]=dt
  if dt>1/30 then m.stutter33=m.stutter33+1 end
  if dt>0.050 then m.stutter50=m.stutter50+1 end
  if dt>0.100 then m.stutter100=m.stutter100+1 end
  m.sumUpdateMs=m.sumUpdateMs+S.lastUpdateMs;m.maxUpdateMs=max(m.maxUpdateMs,S.lastUpdateMs)
  m.sumAtmosMs=m.sumAtmosMs+S.lastAtmosMs;m.maxAtmosMs=max(m.maxAtmosMs,S.lastAtmosMs)
  m.sumPresentMs=m.sumPresentMs+S.lastPresentMs;m.maxPresentMs=max(m.maxPresentMs,S.lastPresentMs)
  S.lastAtmosMs=0;S.lastPresentMs=0
  S.sampleClock=S.sampleClock+dt
  if S.sampleClock>=1.0 then
    S.sampleClock=S.sampleClock-1.0;m.telemetrySamples=m.telemetrySamples+1
    local luaMB=(collectgarbage("count") or 0)/1024;m.sumLuaMB=m.sumLuaMB+luaMB;m.peakLuaMB=max(m.peakLuaMB,luaMB)
    local gs=graphicsStats(B._gstats or {});B._gstats=gs
    m.sumDrawCalls=m.sumDrawCalls+(gs.drawcalls or 0);m.peakDrawCalls=max(m.peakDrawCalls,gs.drawcalls or 0)
    m.peakTextureMB=max(m.peakTextureMB,(gs.texturememory or 0)/(1024*1024))
    local Atmos=nil;pcall(function() Atmos=V.require("DramalessAtmos") end)
    if Atmos and Atmos.benchmarkStats then
      local out=B._pstats or {};B._pstats=out
      local ok=pcall(Atmos.benchmarkStats,out)
      if ok then
        m.peakRain=max(m.peakRain,tonumber(out.rain) or 0);m.peakSnow=max(m.peakSnow,tonumber(out.snow) or 0)
        local gr=(tonumber(out.hail) or 0)+(tonumber(out.sand) or 0)+(tonumber(out.debris) or 0)+(tonumber(out.ash) or 0)
        m.peakGrain=max(m.peakGrain,gr);m.peakGroundSnow=max(m.peakGroundSnow,tonumber(out.groundSnow) or 0)
      end
    end
    local SP=nil;pcall(function() SP=V.require("SnowPack") end)
    if SP and SP.stats then
      local ok,c,f=pcall(SP.stats);if ok then m.peakSnowCells=max(m.peakSnowCells,tonumber(c) or 0);m.peakPackFootprints=max(m.peakPackFootprints,tonumber(f) or 0) end
    end
  end
end

function B.beginAtmos() if S.active then S.atmosStart=now() end end
function B.endAtmos()
  if S.active and S.atmosStart then S.lastAtmosMs=max(0,(now()-S.atmosStart)*1000);S.atmosStart=nil end
end
function B.beginPresent() if S.active then S.presentStart=now() end end
function B.endPresent()
  if S.active and S.presentStart then S.lastPresentMs=S.lastPresentMs+max(0,(now()-S.presentStart)*1000);S.presentStart=nil end
end

function B.active() return S.active end
function B.last() return S.last end
function B.summary() return S.lastSummary or "no benchmark result yet" end
function B.status()
  if not S.active then return B.summary() end
  local p=S.phases[S.phaseIndex]
  local stage=(p and S.phaseElapsed<p.warm) and "WARMUP" or "MEASURE"
  local left=p and max(0,p.warm+p.measure-S.phaseElapsed) or 0
  return ("WXBENCH %s %d/%d %s %s %.1fs left"):format(S.mode:upper(),S.phaseIndex,#S.phases,p and p.label or "-",stage,left)
end

function B.reportLines()
  local r=S.last;if not r then return {"No benchmark result yet."} end
  local out={r.summary}
  for i,m in ipairs(r.phases) do
    out[#out+1]=("%d %s avg %.1f 1%% %.1f p99 %.2fms wxU %.2fms wx3D %.2fms"):format(i,m.label,m.avgFps,m.onePct,m.p99Ms,m.avgUpdateMs,m.avgAtmosMs)
  end
  return out
end

function B.draw(viewport)
  if not S.active then return false end
  local g=love and love.graphics;if not (g and g.print) then return false end
  local p=S.phases[S.phaseIndex];if not p then return false end
  local x=tonumber(viewport and (viewport.gameX or viewport.x)) or 4
  local y=tonumber(viewport and (viewport.gameY or viewport.y)) or 4
  x=x+4;y=y+4
  local stage=S.phaseElapsed<p.warm and "WARMUP" or "MEASURE"
  local m=S.current;local fps=(m and m.sumDt>0) and (m.frames/m.sumDt) or 0
  local lines={
    ("WX BENCH %s  %d/%d"):format(S.mode:upper(),S.phaseIndex,#S.phases),
    ("%s  %s"):format(p.label,stage),
    ("phase %3.0f%%  avg %5.1f fps"):format(phasePercent()*100,fps),
    ("wx update %.2fms  3D %.2fms"):format(S.lastUpdateMs,S.lastAtmosMs),
  }
  if S.warning then lines[#lines+1]="WARN: "..S.warning end
  local pushed=false;if g.push then pushed=pcall(g.push,"all") end
  pcall(g.setBlendMode,"alpha");pcall(g.setColor,0,0,0,0.78);pcall(g.rectangle,"fill",x,y,220,#lines*13+8)
  pcall(g.setColor,1,1,1,1);for i=1,#lines do pcall(g.print,lines[i],x+4,y+3+(i-1)*13) end
  if pushed and g.pop then pcall(g.pop) end
  return true
end

function B._reset()
  if S.active then restoreSnapshot() end
  S.active=false;S.results={};S.current=nil;S.last=nil;S.lastSummary=nil;S.phaseIndex=0;S.phaseElapsed=0;S.warning=nil
end

return B
