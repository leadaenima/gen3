local V = ...

-- Weather FX 8.0.8 staged runtime.
--
-- Performance rules:
--   * WeatherState, presentation, lightning and audio stay frame-rate live.
--   * Slow physical/environmental fields remain multi-rate.
--   * One world-position query and one reusable surface snapshot per frame.
--   * Internal passes prefer zero-allocation peek/sampleInto APIs.
--   * Advisory SDK-only systems are computed on demand, never on gameplay frames.
--   * Profiling is sampled by RenderGraph instead of timing every pass.
--   * Explicit quality tiers are authoritative; targeted degradation is AUTO-only.
local Runtime={configured=false,frame=0}
local RenderGraph=V.require("RenderGraph")
local HostAdapter=V.require("HostAdapter")
local Governor=V.require("PerformanceGovernor")
local graph=RenderGraph.new("weather_fx_runtime",{"budget","world","climate","celestial","environment","presentation","effects","audio","telemetry"})
local modules={}
local EMPTY_OPTS={}
local frameCtx={scene={},surface={},worldX=0,worldZ=0}
-- Cache only successful Weather FX module resolves. These are mod-local tables,
-- not generation-specific engine modules; failed resolves intentionally retry.
local reqCache={}
local function req(name)
  local m=reqCache[name]; if m then return m end
  local ok,v=pcall(V.require,name); if ok and v then reqCache[name]=v; return v end
end
local function qualityInterval(base)
  local Q=req("Quality")
  local m=(Q and Q.simulationIntervalMultiplier and Q.simulationIntervalMultiplier()) or 1
  m=tonumber(m) or 1;if m<1 then m=1 elseif m>3 then m=3 end
  return base*m
end
local function interval(base) return function() return Governor.interval(qualityInterval(base)) end end
local function routedInterval(base,family)
  return function()
    local qb=qualityInterval(base)
    if not Governor.auto() then return qb end
    local R=req("WorkloadRouter"); local s=(R and R.scale and R.scale(family)) or 1
    if s<.45 then s=.45 elseif s>1 then s=1 end
    return Governor.interval(qb)/s
  end
end
local function register(stage,id,priority,fn,ownership,critical,period,profileEvery,enabled)
  return graph:register(stage,id,fn,{priority=priority,owner="weather_fx",ownership=ownership,critical=critical==true,interval=period,profileEvery=profileEvery or 8,enabled=enabled})
end

-- Presentation-aware work ownership. This is deliberately feature based rather
-- than a blunt 2D/3D master switch: 2D precipitation may coexist with Weather
-- FX 3D cloud banks/celestials/water, and those individually enabled consumers
-- must keep their exact runtime data. Conversely strict 3D should not pay for
-- flat-only particle/NPC overlay work. The flags live on the reused frame ctx so
-- evaluating them creates no per-frame garbage.
local function activeVoxelHost()
  local A=modules.VoxelAtmos
  if A and A.active then local ok,v=pcall(A.active); if ok then return v and true or false end end
  return false
end
local function refreshPresentationNeeds(c)
  local S=modules.Settings or req("Settings")
  local host=activeVoxelHost()
  local fp=false
  if S and S.isFirstPerson then local ok,v=pcall(S.isFirstPerson);fp=ok and v==true end
  local force2d=false
  if S and S.force2dPresent then local ok,v=pcall(S.force2dPresent);force2d=ok and v==true end
  local allow3d=true
  if S and S.allow3dPresent then local ok,v=pcall(S.allow3dPresent);if ok then allow3d=v~=false end end
  local weather3d=host and (fp or ((not force2d) and allow3d))
  local clouds3d=false
  if host and S and S.cloudsOn then local ok,v=pcall(S.cloudsOn);clouds3d=ok and v~=false end
  local celestial3d=false
  if host and S and S.use3dCelestial then local ok,v=pcall(S.use3dCelestial);celestial3d=ok and v==true end
  local water3d=false
  if host and S and S.weatherFxWaterEnabled then local ok,v=pcall(S.weatherFxWaterEnabled);water3d=ok and v==true end
  c.host3d,c.weather3d,c.clouds3d,c.celestial3d,c.water3d=host,weather3d,clouds3d,celestial3d,water3d
  c.atmos3d=weather3d or clouds3d
  c.any3d=weather3d or clouds3d or celestial3d or water3d
  return c
end
Runtime._refreshPresentationNeeds=refreshPresentationNeeds
local function refreshPosition(c)
  local x,z=0,0
  if HostAdapter and HostAdapter.worldPosition then x,z=HostAdapter.worldPosition() end
  x,z=tonumber(x) or 0,tonumber(z) or 0
  -- Convert the host's current-map local frame into one canonical connected-
  -- world frame. This is what allows a storm footprint to straddle two maps.
  local S=req("WeatherWorldSpace")
  if S and S.toWorld then x,z=S.toWorld(x,z,c.scene and c.scene.mapId) end
  c.worldX,c.worldZ=x,z
end
local function refreshSurface(c)
  local S=req("EnvironmentSurface")
  if S and S.sampleInto then S.sampleInto(c.worldX,c.worldZ,c.surface)
  elseif S and S.sample then
    local q=S.sample(c.worldX,c.worldZ); if q then for k in pairs(c.surface) do c.surface[k]=nil end; for k,v in pairs(q) do c.surface[k]=v end end
  end
  return c.surface
end

-- Several passes ask for the same WorldClimate cell. Cache the exact returned
-- cell reference for this frame; invalidate only when WorldClimate itself runs.
local function worldClimateAt(c)
  if c._worldClimateFrame==c.frame and c._worldClimateX==c.worldX and c._worldClimateZ==c.worldZ then return c.worldClimate end
  local WC=req("WorldClimate"); local q=nil
  if WC and (not WC.ready or WC.ready()) then
    if WC.peek then q=WC.peek() elseif WC.sampleAt then q=WC.sampleAt(c.worldX,c.worldZ) end
  end
  c.worldClimate=q;c._worldClimateFrame=c.frame;c._worldClimateX=c.worldX;c._worldClimateZ=c.worldZ
  return q
end

function Runtime.configure(m)
  if Runtime.configured then return true end
  modules=m or {}

  register("budget","performance_governor",1,function(c)
    Governor.update(c.dt)
    local P=req("ParticleBatcher"); if P and P.beginFrame then P.beginFrame() end
  end,"frame_budget",false,nil,16)
  register("budget","predictive_budget",5,function(c)
    -- PredictiveBudget is consumed only by AUTO. Fixed player quality tiers are
    -- literal and intentionally ignore it, so do no forecast math in MANUAL.
    if not Governor.auto() then return end
    local P=req("PredictiveBudget"); local M=req("Microclimate"); local VW=req("VolumetricWeather")
    if P and P.update then P.update(c.dt,M and M.peek and M.peek() or nil,VW and VW.peek and VW.peek() or (VW and VW.sample and VW.sample() or nil)) end
  end,"predictive_budget",false,interval(.20),8,function(c) return c.atmos3d end)

  register("world","host_adapter",5,function(c)
    local H=HostAdapter; if H and H.refresh and (c.frame==1 or c.frame%60==0) then H.refresh() end
  end,"host_capabilities",false,nil,16)
  -- Seasons consume TOD.gameDaySerial(), so the clock must be current before
  -- season/weather weighting is evaluated on this frame (especially after load).
  register("world","time",10,function(c) if modules.TOD and modules.TOD.update then modules.TOD.update(c.dt) end end,"time_clock",false,nil,16)
  register("world","seasons",20,function(c) if modules.Seasons and modules.Seasons.update then modules.Seasons.update(c.dt,c.scene and c.scene.mapId) end end,"season_clock",false,nil,16)
  register("world","building_light",30,function(c) local BL=req("BuildingLight"); if BL and BL.update then BL.update(c.dt) end end,"building_light",false,interval(.05),8)

  register("climate","weather_state",10,function(c)
    if modules.State and modules.State.update then modules.State.update(c.dt,c.level,c.scene and c.scene.mapId,c.scene and c.scene.indoors,c.worldX,c.worldZ) end
  end,"weather_state",true,nil,16)
  register("climate","weather_sim",20,function(c)
    local W=req("WeatherSimulation"); if W and W.update then W.update(c.dt,modules.State) end
  end,"weather_sim",false,routedInterval(.10,"simulation"),8)
  register("climate","world_climate",25,function(c)
    local WC=req("WorldClimate"); local W=req("WeatherSimulation")
    if WC and WC.update then WC.update(c.dt,W and W.peek and W.peek() or (W and W.sample and W.sample() or nil),c.worldX,c.worldZ); c._worldClimateFrame=-1 end
  end,"world_climate",false,routedInterval(.75,"simulation"),8)
  register("climate","mesoscale_field",27,function(c)
    local MF=req("MesoscaleField"); local W=req("WeatherSimulation")
    if MF and MF.update then MF.update(c.dt,W and W.peek and W.peek() or nil,worldClimateAt(c),c.worldX,c.worldZ) end
  end,"mesoscale_weather",false,routedInterval(.28,"simulation"),8)
  register("climate","microclimate",30,function(c)
    local M=req("Microclimate"); local MF=req("MesoscaleField"); local W=req("WeatherSimulation")
    local base=MF and MF.peek and MF.peek() or (worldClimateAt(c) or (W and W.peek and W.peek() or nil))
    if M and M.update then M.update(c.dt,base,c.worldX,c.worldZ,c.scene) end
  end,"microclimate",false,routedInterval(.16,"simulation"),8)
  register("climate","cloud_field",40,function(c)
    local C=req("CloudField"); local M=req("Microclimate")
    if C and C.update then C.update(c.dt,M and M.peek and M.peek() or nil,c.worldX,c.worldZ) end
  end,"cloud_field",false,routedInterval(.20,"clouds"),8,function(c) return c.atmos3d end)
  register("climate","volumetric_weather",50,function(c)
    local VW=req("VolumetricWeather"); local M=req("Microclimate"); local CF=req("CloudField")
    if VW and VW.update then VW.update(c.dt,c.worldX,c.worldZ,M and M.peek and M.peek() or nil,CF and CF.peek and CF.peek() or nil,worldClimateAt(c)) end
  end,"volumetric_weather",false,routedInterval(.18,"clouds"),8,function(c) return c.atmos3d end)
  -- DistantWeather is a tiny bounded descriptor pass (<=6 cells / 4 visible
  -- fronts), not a heavy cloud simulation. It must refresh every frame so a
  -- moving front does not advance in ~180 ms stair-steps while the renderer is
  -- running at full frame rate. Expensive cloud/particle work remains routed.
  register("climate","distant_weather",55,function(c)
    local D=req("DistantWeather");if D and D.update then D.update(c.dt,c.worldX,c.worldZ) end
  end,"distant_weather",false,nil,8)

  register("celestial","celestial2",10,function(c) local C=req("CelestialRenderer2"); if C and C.update then C.update(c.dt,modules.State) end end,"celestial",false,nil,16)

  register("environment","wind",10,function(c) local W=req("WindEngine"); if W and W.update then W.update(c.dt,modules.State) end end,"wind",false,nil,16)
  register("environment","wind_flow",15,function(c)
    local F=req("WindFlow"); if F and F.update then F.update(c.dt,c.worldX,c.worldZ,c.scene) end
  end,"wind_flow",false,routedInterval(.12,"simulation"),8)
  register("environment","connected_water",17,function(c)
    local CW=req("ConnectedWater"); if CW and CW.update then CW.update(c.dt,modules.State,modules.Seasons) end
  end,"connected_water",false,nil,16,function(c) return c.water3d end)
  register("environment","atmosphere",20,function(c)
    local A=req("AtmosphereModel"); local M=req("Microclimate"); local C=req("CelestialRenderer2"); local CF=req("CloudField")
    if A and A.update then A.update(c.dt,M and M.peek and M.peek() or nil,C and C.state and C.state() or nil,CF and CF.peek and CF.peek() or nil) end
  end,"atmosphere",false,routedInterval(.08,"clouds"),8,function(c) return c.atmos3d end)
  register("environment","rainbow",22,function(c)
    local R=req("Rainbow"); if R and R.update then R.update(c.dt,modules.State,c.scene) end
  end,"rainbow",false,routedInterval(.10,"environment"),8,function(c) return c.weather3d end)
  register("environment","surface",30,function(c)
    local S=req("EnvironmentSurface"); local M=req("Microclimate")
    if S and S.update then S.update(c.dt,c.worldX,c.worldZ,M and M.peek and M.peek() or nil); refreshSurface(c) end
  end,"surface_state",false,routedInterval(.25,"surface"),8)
  register("environment","weather_world_interaction",32,function(c)
    local I=req("WeatherWorldInteraction")
    if I and I.update then I.update(c.dt,modules.State,c.surface,c.scene,c.worldX,c.worldZ) end
  end,"weather_world_interaction",false,nil,16,function(c) return c.weather3d end)
  register("environment","hydrology",34,function(c)
    local Hy=req("Hydrology"); local M=req("Microclimate")
    if Hy and Hy.update then Hy.update(c.dt,c.worldX,c.worldZ,M and M.peek and M.peek() or nil) end
  end,"hydrology",false,routedInterval(.28,"surface"),8,function(c) return c.weather3d end)
  register("environment","accumulation_geometry",36,function(c)
    local AG=req("AccumulationGeometry"); local Hy=req("Hydrology")
    local h=Hy and Hy.peekAt and Hy.peekAt(c.worldX,c.worldZ) or (Hy and Hy.sampleAt and Hy.sampleAt(c.worldX,c.worldZ) or nil)
    if AG and AG.update then AG.update(c.dt,c.surface,h) end
  end,"accumulation_geometry",false,routedInterval(.20,"surface"),8,function(c) return c.weather3d end)
  register("environment","dynamic_lighting",38,function(c)
    local DL=req("DynamicLighting"); local M=req("Microclimate"); local CR=req("CelestialRenderer2"); local CF=req("CloudField")
    if DL and DL.update then
      DL.update(c.dt,M and M.peek and M.peek() or nil,c.surface,CR and CR.state and CR.state() or nil,CF and CF.peek and CF.peek() or nil)
      -- Feed the real shared lightning envelope into world lighting/probes. The
      -- old DynamicLighting lightning channel existed but had no producer, so a
      -- bolt could flash the screen/clouds without illuminating nearby voxel
      -- faces. This is cheap: one scalar per frame, no extra lights or particles.
      if DL.observeLightning and modules.Lightning and modules.Lightning.flash then
        local mode=modules.Settings and modules.Settings.get and modules.Settings.get("lightning") or "full"
        local scale=modules.Settings and modules.Settings.lightningFlashScale and modules.Settings.lightningFlashScale() or 1
        DL.observeLightning((tonumber(modules.Lightning.flash(mode)) or 0)*scale)
      end
      if DL.decay then DL.decay(c.dt) end
    end
  end,"dynamic_lighting",false,routedInterval(.08,"lighting"),8,function(c) return c.any3d end)
  register("environment","unified_lighting",39,function(c)
    local U=req("UnifiedLighting"); local D=req("DynamicLighting"); local A=req("AtmosphereModel"); local VW=req("VolumetricWeather")
    if U and U.update then U.update(c.dt,D and D.peek and D.peek() or (D and D.sample and D.sample() or nil),A and A.peek and A.peek() or (A and A.grade and A.grade() or nil),VW and VW.peek and VW.peek() or nil,c.surface) end
  end,"unified_lighting",false,routedInterval(.08,"lighting"),8,function(c) return c.any3d end)
  register("environment","severe_weather",42,function(c)
    local SW=req("SevereWeather"); local M=req("Microclimate"); local CF=req("CloudField"); local WF=req("WindFlow")
    if SW and SW.update then SW.update(c.dt,M and M.peek and M.peek() or nil,worldClimateAt(c),CF and CF.peek and CF.peek() or nil,WF and WF.sampleAt and WF.sampleAt(c.worldX,c.worldZ) or nil) end
  end,"severe_weather",false,routedInterval(.20,"environment"),8,function(c) return c.weather3d end)
  register("environment","ecosystem",44,function(c)
    local Eco=req("EcosystemEngine"); local M=req("Microclimate")
    if Eco and Eco.update then Eco.update(c.dt,M and M.peek and M.peek() or nil,nil,c.surface) end
  end,"ecosystem",false,routedInterval(.25,"simulation"),8,function(c) return c.any3d end)
  register("environment","environment_events",46,function(c)
    local E=req("EnvironmentalEvents"); local M=req("Microclimate")
    if E and E.update then E.update(c.dt,M and M.peek and M.peek() or nil,c.surface,c.scene) end
  end,"environment_events",false,routedInterval(.20,"environment"),8,function(c) return c.any3d end)

  register("presentation","volumetric_renderer",3,function(c)
    local R=req("VolumetricRenderer"); local VW=req("VolumetricWeather"); local A=req("AtmosphereModel")
    if R and R.update then R.update(c.dt,VW and VW.peek and VW.peek() or nil,A and A.peek and A.peek() or nil) end
  end,"volumetric_renderer",false,routedInterval(.08,"clouds"),8,function(c) return c.atmos3d end)
  register("presentation","surface_visual_state",4,function(c)
    -- c.surface was sampled at frame start and refreshed immediately if the
    -- EnvironmentSurface pass ran; a third identical sample here was redundant.
    local SV=req("SurfaceVisualState"); local AG=req("AccumulationGeometry"); local Hy=req("Hydrology")
    if SV and SV.update then SV.update(c.surface,AG and AG.peek and AG.peek() or nil,Hy and Hy.peekAt and Hy.peekAt(c.worldX,c.worldZ) or nil) end
  end,"surface_visual_state",false,routedInterval(.12,"surface"),8,function(c) return c.weather3d end)
  register("presentation","draw_update",10,function(c) if modules.Draw and modules.Draw.update then modules.Draw.update(c.animDt,c.level) end end,"draw_update",false,nil,16)
  register("presentation","voxel_weather",20,function(c)
    if modules.VoxelAtmos then if modules.VoxelAtmos.syncFromWeatherFx then modules.VoxelAtmos.syncFromWeatherFx(modules.State,modules.Settings) end; if modules.VoxelAtmos.update then modules.VoxelAtmos.update(c.animDt) end end
  end,"voxel_weather",false,nil,16,function(c) return c.any3d end)

  register("effects","follower",10,function(c) if modules.Follower and modules.Follower.update then modules.Follower.update(c.dt) end end,"follower",false,nil,16)
  register("effects","tornado",20,function(c) if not c.benchmarkActive and modules.Tornado and modules.Tornado.update then modules.Tornado.update(c.animDt) end end,"tornado",false,nil,16)

  register("audio","acoustic_model",5,function(c)
    local A=req("AcousticModel"); local M=req("Microclimate")
    if A and A.update then A.update(c.dt,M and M.peek and M.peek() or nil,c.surface,c.scene) end
  end,"environment_audio",false,routedInterval(.10,"audio"),16)
  register("audio","audio",10,function(c) if modules.Audio and modules.Audio.update then modules.Audio.update(c.dt) end end,"weather_audio",false,nil,16)

  register("telemetry","system_profiler",10,function(c) if not Governor.auto() then return end; local P=req("SystemProfiler"); if P and P.update then P.update(c.dt,graph) end end,"system_profiler",false,interval(.50),1)
  register("telemetry","workload_router",20,function(c)
    -- Targeted routing is another AUTO-only controller. Manual QUALITY has no
    -- routed trims, so avoid profiler-family bookkeeping entirely in that mode.
    if not Governor.auto() then return end
    local R=req("WorkloadRouter"); if R and R.update then R.update(c.dt) end
  end,"targeted_auto_budget",false,interval(.50),1)

  Runtime.configured=true
  return true
end

function Runtime.update(dt,level,scene,opts)
  Runtime.frame=Runtime.frame+1; opts=opts or EMPTY_OPTS
  local c=frameCtx
  local realDt=math.max(0,tonumber(dt) or 0)
  c.animationPaused=opts.animationPaused and true or false
  -- PAUSE MENU WEATHER = FROZEN is a true Weather FX presentation hold.
  -- Keep the real delta for diagnostics, but feed zero through every Weather FX
  -- update stage so live climate/channel changes cannot silently add/remove
  -- particles while their positions are supposedly frozen.  The host game and
  -- its clock/input continue normally; only this mod's weather evolution is
  -- held until the pause stack closes.
  c.realDt=realDt
  c.dt=c.animationPaused and 0 or realDt
  c.animDt=c.dt
  c.level=level; c.scene=scene or c.scene; c.benchmarkActive=opts.benchmarkActive; c.frame=Runtime.frame; c.afterClimate=opts.afterClimate; c._worldClimateFrame=-1
  refreshPresentationNeeds(c)
  refreshPosition(c)
  refreshSurface(c)
  for i=1,#graph.order do
    local stage=graph.order[i]; local ok,err=graph:executeStage(stage,c)
    if not ok then return false,err,stage end
    -- Fixed tiers never consume profiler output, so after the governor pass
    -- disable timer sampling for every remaining pass (and the next frame).
    if stage=="budget" and graph.setProfilingEnabled then graph:setProfilingEnabled(Governor.auto()) end
    if stage=="climate" and type(c.afterClimate)=="function" then local cbOk,cbErr=pcall(c.afterClimate,c); if not cbOk then return false,cbErr,"afterClimate" end end
  end
  return true
end

function Runtime.stats()
  local s=graph:stats(); s.frame=Runtime.frame
  if HostAdapter and HostAdapter.capabilities then s.host=HostAdapter.capabilities() end
  local S=req("EnvironmentSurface"); if S and S.stats then s.surface=S.stats() end
  local W=req("WeatherSimulation"); if W and W.sample then s.weather=W.sample() end
  local M=req("Microclimate"); if M and M.sample then s.microclimate=M.sample() end
  local C=req("CloudField"); if C and C.stats then s.cloudField=C.stats() end
  local P=req("ParticleBatcher"); if P and P.stats then s.particles=P.stats() end
  local E=req("EnvironmentalEvents"); if E and E.stats then s.events=E.stats() end
  local WC=req("WorldClimate"); if WC and WC.stats then s.worldClimate=WC.stats() end
  local VW=req("VolumetricWeather"); if VW and VW.stats then s.volumetric=VW.stats() end
  local DW=req("DistantWeather"); if DW and DW.stats then s.distantWeather=DW.stats() end
  local WF=req("WindFlow"); if WF and WF.stats then s.windFlow=WF.stats() end
  local Hy=req("Hydrology"); if Hy and Hy.stats then s.hydrology=Hy.stats() end
  local DL=req("DynamicLighting"); if DL and DL.sample then s.lighting=DL.sample() end
  local SW=req("SevereWeather"); if SW and SW.sample then s.severe=SW.sample() end
  local Eco=req("EcosystemEngine"); if Eco and Eco.sample then s.ecosystem=Eco.sample() end
  local PB=req("PredictiveBudget"); if PB and PB.sample then s.predictive=PB.sample() end
  local WR=req("WorkloadRouter"); if WR and WR.sample then s.workloadRouter=WR.sample() end
  local Prof=req("SystemProfiler"); if Prof and Prof.sample then s.profiler=Prof.sample() end
  local WS=req("WorldStreamer"); if WS and WS.sample then s.streamer=WS.sample() end
  local GW=req("GPUWeatherEngine"); if GW and GW.sample then s.gpuWeather=GW.sample() end
  local VR=req("VolumetricRenderer"); if VR and VR.sample then s.volumeRenderer=VR.sample() end
  local UL=req("UnifiedLighting"); if UL and UL.sample then s.unifiedLighting=UL.sample() end
  local LP=req("LightProbeGrid"); if LP and LP.stats then s.lightProbeGrid=LP.stats() end
  local SV=req("SurfaceVisuals"); if SV and SV.sample then s.surfaceVisuals=SV.sample() end
  s.performance=Governor.sample()
  return s
end

function Runtime.graph() return graph end
return Runtime
