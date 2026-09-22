-- DramalessAtmos
--
-- Full Kanto-style atmosphere (clouds, light shafts, rain, fog, motes,
-- puddles, distant horizon) running inside Weather FX only.
-- Multi-host 3D atmosphere bridge. First-class hosts (all must keep working):
--   DRAMATIC_SHAPE, DRAMALESS_SHAPE, Gen2Recomped-DramaticShapes, potato_voxel / POTATO_VOXEL, STADIUM2_OVERWORLD_MODELS
-- (Gen2-3D-Sprites). Other mods are never edited on disk;
-- we only read their exports.lib and wrap Voxel3D.endScene in memory.
--
-- Missing Dramatic Shape modules are supplied as stubs under
-- lib/voxel_atmos/stubs/. Features that need host data (e.g. sprite
-- reflections in puddles) degrade gracefully.

local V = ...
local safe = (V.safeBind and V.safeBind("DramalessAtmos")) or pcall
local mod = V.mod

local Atmos = {
  _ready = false,
  _active = false,
  _drawing = false,
  _reason = "not-initialised",
  _hostId = nil,
  _Voxel3D = nil,
  _origEndScene = nil,
  _cin = nil,
  _distant = nil,
  _horizon = nil,
  _forest = nil,
  _lastMap = nil,
  _lastOutdoor = true,
  _battleOutdoorCarry = nil,
  _wasBattleScene = false,
  _lastNeighbors = nil,
  _lastPosed = nil,
  _lastPlayer = nil,
  _lastState = nil,
  _hostRealisticWaterCaptured = false,
  _hostRealisticNativeWater = nil,
  _waterCaps = nil,
  _waterFrame = 0,
  _hostWaterCalled = false,
  _wxWaterDrawn = false,
  _wxVoidPreflightFrame = nil,
  _wxVoidPreflightOwned = false,
  _wxVoidPreflightRepl = nil,
  _hostUnderlaySuppressed = false,
}

local HOSTS = {
  "BATTLE_ART_VOXEL_FORK", "DRAMATIC_SHAPE", "DRAMALESS_SHAPE",
  "Gen2Recomped-DramaticShapes",
  "potato_voxel", "POTATO_VOXEL", "PotatoVoxel",
  -- Dramatic Shape, its Dramaless fork, and Gen2Recomped's bundled
  -- Gen2Recomped-DramaticShapes renderer expose the same exports.lib contract.
  -- Gold/Silver Stadium 2 overworld (Gen2-3D-Sprites) follows that contract too.
  -- convention as Dramaless; host-specific only via mod.find id.
  "STADIUM2_OVERWORLD_MODELS",
}

local WX_TO_KANTO = {
  -- Clear / sun family
  CLEAR = "clear", SUNNY = "clear", HEATWAVE = "clear", HARSH_SUN = "clear",
  -- Rain / storm → closed deck + 3D rain. Explicit 3D owns all Weather FX visuals.
  RAIN_LIGHT = "rain", RAIN_HEAVY = "rain", HEAVY_RAIN = "thunderstorm",
  VERDANT_RAIN = "rain", SLEET = "rain",
  STORM = "thunderstorm", DRAGONSTORM = "thunderstorm",
  -- Cold precip: dense overcast 3D clouds/fog + world-space snow/hail.
  SNOW_LIGHT = "snow", SNOW = "snow", SNOW_HEAVY = "blizzard",
  BLIZZARD = "blizzard", HAIL = "snow", THUNDERSNOW = "blizzard",
  -- Dust / ash / wind: broken cloud + fog volumes + world-space grains.
  SANDSTORM = "overcast", DUSTSTORM = "overcast", ASHFALL = "overcast",
  STRONG_WINDS = "mostly", GALE = "gale", BRAWL_WIND = "mostly",
  FLOCKSTORM = "mostly",
  -- Fog / mist: high world-space fog volumes in 3D.
  FOG = "overcast", MIST = "cloudy", HAUNTED_MIST = "cloudy", SMOG = "cloudy",
  -- Typed fronts / oddities
  PLAIN_FRONT = "partly", SWARM = "partly", PSYSTORM = "thunderstorm",
}

-- 8.1.87 battle sky continuity.
--
-- A 3D/world-backed battle is still physically located in the outdoor voxel
-- world. Some host battle stacks temporarily report Scene.now.outdoor=false
-- while the battle state owns the screen, even though VoxelScene continues to
-- render that outdoor world. Feeding that transient false into CinematicAtmos
-- makes frame() fail its sky gate and removes ALL 3D precipitation in battle.
-- Carry the last proven pre-battle sky authority across the battle instead.
-- Battles that actually started indoors/caves remain dry via Battle._startedIndoors.
local function resolveWeatherOutdoor(Scene)
  local now=Scene and Scene.now or nil
  local inBattle=now and now.visible=="battle" or false
  if inBattle then
    if not Atmos._wasBattleScene then
      Atmos._battleOutdoorCarry=Atmos._lastOutdoor and true or false
    end
    Atmos._wasBattleScene=true
    local startedIndoors=false
    safe(function()
      local B=V.require("Battle")
      startedIndoors=B and B._startedIndoors==true or false
    end)
    if startedIndoors then
      Atmos._battleOutdoorCarry=false
      return false
    end
    if Atmos._battleOutdoorCarry~=nil then return Atmos._battleOutdoorCarry end
  else
    Atmos._wasBattleScene=false
    Atmos._battleOutdoorCarry=nil
  end
  if now and now.outdoor~=nil then return now.outdoor and true or false end
  return Atmos._lastOutdoor and true or false
end
Atmos._resolveWeatherOutdoor=resolveWeatherOutdoor

local function findHost()
  if not (mod and mod.find) then return nil, nil end
  for i = 1, #HOSTS do
    local ok, host = safe(mod.find, mod, HOSTS[i])
    if ok and host then return host, HOSTS[i] end
  end
  return nil, nil
end

-- Some voxel packages carry a second optional "realistic" water renderer in
-- addition to VoxelScene.drawWater. Weather FX owns the complete water pass in
-- WEATHER FX mode, so letting that companion layer draw too wastes CPU/GPU and
-- can leave small pieces of the old material visible. Suppress only the
-- companion's public runtime flag, remember its exact original value, and
-- restore it immediately in ORIGINAL mode/invalidation. No host file is edited.
local function suppressSecondaryHostWater(on)
  local lib=Atmos._hostLib
  local rw=lib and lib.realisticWorld
  if type(rw)~="table" then return false end
  if not Atmos._hostRealisticWaterCaptured then
    Atmos._hostRealisticNativeWater=rw.nativeWater
    Atmos._hostRealisticWaterCaptured=true
  end
  if on then rw.nativeWater=true else rw.nativeWater=Atmos._hostRealisticNativeWater end
  return true
end
Atmos._suppressSecondaryHostWater=suppressSecondaryHostWater

-- Voxel Nexus' bundled realistic WaterEngine wraps Water.draw() and adds its
-- own model-space tide transform. Weather FX already applies connected-water
-- tide to every owned replacement model. Under world curvature the host first
-- depth-draws the mesh through Voxel3D.draw() at the Weather FX datum, then the
-- reflective Water.draw() wrapper can move that same mesh again by the Nexus
-- tide. The two passes no longer coincide and the lower pass reads as old water
-- bleeding through the replacement. Neutralize ONLY that additive host tide
-- while Weather FX owns the water call; ORIGINAL mode and failed ownership keep
-- the exact native function. The engine object is capability-discovered rather
-- than inferred from the shared BATTLE_ART_VOXEL_FORK id.
local ZERO_HOST_WATER_TIDE=function() return 0 end
local function suppressHostWaterModelTide(on)
  local lib=Atmos._hostLib
  local rw=lib and lib.realisticWorld
  local engine=type(rw)=="table" and rw.WaterEngine or nil
  if type(engine)~="table" or type(engine.tideOffset)~="function" then return false end
  if Atmos._hostWaterEngine~=engine then
    Atmos._hostWaterEngine=engine
    Atmos._hostWaterTideOriginal=engine.tideOffset
    Atmos._hostWaterTideSuppressed=false
  end
  if on then
    if not Atmos._hostWaterTideSuppressed then
      -- Capture again if another host layer legitimately replaced the function
      -- since our last release/hot reload boundary.
      if engine.tideOffset~=ZERO_HOST_WATER_TIDE then Atmos._hostWaterTideOriginal=engine.tideOffset end
      engine.tideOffset=ZERO_HOST_WATER_TIDE
      Atmos._hostWaterTideSuppressed=true
    end
  elseif Atmos._hostWaterTideSuppressed then
    engine.tideOffset=Atmos._hostWaterTideOriginal or engine.tideOffset
    Atmos._hostWaterTideSuppressed=false
  end
  return true
end
Atmos._suppressHostWaterModelTide=suppressHostWaterModelTide

-- One capability probe feeds the same Weather FX void-ocean authority on every
-- supported voxel host. The named Dramatic/Dramaless/Potato/Battle-Art family
-- normally exposes VoxelScene.drawWater; Gen2/Stadium-style or future hosts may
-- not. A host-specific WorldUnderlay is OPTIONAL metadata only: it can widen the
-- physical sea horizon, but correctness never depends on that module existing.
local function publishWaterHostCaps(hostId,hostLib,VoxelScene)
  local caps={id=tostring(hostId or "unknown"),drawWater=VoxelScene and type(VoxelScene.drawWater)=="function" or false,
    outerRange=32768,voidRingWorld=96,worldUnderlay=false,publicBattleArtWater=false,
    voxelNexusWater=false,hostWaterModelTide=false}
  if hostLib and type(hostLib.require)=="function" then
    local okU,U=pcall(hostLib.require,"WorldUnderlay")
    if okU and type(U)=="table" then
      caps.worldUnderlay=true
      local r=tonumber(U.RANGE);if r and r>=2048 then caps.outerRange=math.min(65536,r) end
    end
    -- Battle Art and Voxel Nexus intentionally share BATTLE_ART_VOXEL_FORK.
    -- Older Battle Art builds did not export _trainSource, but current public
    -- builds do, so that helper is no longer a lineage discriminator. 8.1.90
    -- could therefore call current Battle Art "Voxel Nexus" and select Nexus-
    -- only water paths. The reliable Nexus seam is its bundled realisticWorld
    -- WaterEngine/tideOffset layer. Everything else with the proven structured
    -- Water API is public Battle Art. Either way Weather FX owns the replacement
    -- geometry and suppresses the host relief only after physical preflight.
    local okW,HostWater=safe(hostLib.require,"Water")
    if okW and type(HostWater)=="table" and caps.id=="BATTLE_ART_VOXEL_FORK" then
      local structured=type(HostWater._waveTime)=="function"
        and type(HostWater.WAVE_TRAINS)=="table" and type(HostWater.WAVE_TRAINS[1])=="table"
        and type(HostWater.WAVE_SWELL)=="table" and type(HostWater.WAVE_BEND)=="table"
        and type(HostWater.begin)=="function" and type(HostWater.draw)=="function"
        and type(HostWater.finish)=="function"
      local rw=hostLib.realisticWorld
      local engine=type(rw)=="table" and rw.WaterEngine or nil
      local nexusTide=type(engine)=="table" and type(engine.tideOffset)=="function"
      caps.voxelNexusWater=structured and nexusTide
      caps.publicBattleArtWater=structured and not caps.voxelNexusWater
      caps.hostWaterModelTide=caps.voxelNexusWater and nexusTide
    end
  end
  Atmos._waterCaps=caps
  safe(function()
    local CW=V.require("ConnectedWater")
    if CW and CW.setVoxelWaterHost then CW.setVoxelWaterHost(caps) end
  end)
  return caps
end
Atmos._publishWaterHostCaps=publishWaterHostCaps

local function waterStyleEnabled()
  local enabled=true
  safe(function()
    local S=V.require("Settings")
    if S and S.weatherFxWaterEnabled then enabled=S.weatherFxWaterEnabled()~=false end
  end)
  return enabled
end

-- Whole-mod quality owns the expensive part of water presentation. FULL keeps
-- screen-space world reflections for near/authored water; SKY keeps the same
-- Fresnel/sky/celestial material without the frame/depth copy; SIMPLE submits
-- only Weather FX's physical animated mesh. The far synthetic VOID horizon is
-- never allowed to be more expensive than SKY, even on MAX, because a 32K
-- presentation ocean has no useful nearby scene geometry to reflect.
local function waterReflectionMode()
  local mode="full"
  safe(function()
    local Q=V.require("Quality")
    if Q and Q.reflectionMode then mode=tostring(Q.reflectionMode() or mode) end
  end)
  if mode~="full" and mode~="sky" and mode~="simple" then mode="full" end
  return mode
end
Atmos._waterReflectionMode=waterReflectionMode


-- Voxel Nexus/Battle-Art draws a giant WorldUnderlay before terrain, outside
-- VoxelScene.drawWater. In VOID FILL = WATER this old cyan/default plane is a
-- second visual sea underneath Weather FX's physical ocean. Preflight the exact
-- Weather FX water renderer for this frame first; only after successful mesh
-- preparation do we suppress the host's outer underlay. This preserves the
-- existing fail-open contract: ORIGINAL mode, non-water voids, or any failed
-- Weather FX preparation immediately leave the native underlay untouched.
local function resetVoidPreflight()
  Atmos._wxVoidPreflightFrame=nil
  Atmos._wxVoidPreflightOwned=false
  Atmos._wxVoidPreflightRepl=nil
  Atmos._hostUnderlaySuppressed=false
end

local function preflightVoidOwnership()
  local frame=Atmos._waterFrame or 0
  if Atmos._wxVoidPreflightFrame==frame then return Atmos._wxVoidPreflightOwned==true end
  Atmos._wxVoidPreflightFrame=frame
  Atmos._wxVoidPreflightOwned=false
  Atmos._wxVoidPreflightRepl=nil
  if not waterStyleEnabled() then return false end
  local W=Atmos._ns
  if not W then return false end
  local CW=nil
  safe(function() CW=V.require("ConnectedWater") end)
  if not (CW and CW.observed and CW.outerSea) then return false end
  local repl,owned,outer=nil,false,nil
  safe(function()
    local CW3=W.require("ConnectedWater3D")
    if CW3 and CW3.setEnabled then CW3.setEnabled(true) end
    if CW3 and CW3.prepare then repl,owned=CW3.prepare(nil) end
    if CW3 and CW3.outerDraws then outer=CW3.outerDraws() end
  end)
  if owned and type(outer)=="table" and #outer>0 then
    Atmos._wxVoidPreflightOwned=true
    Atmos._wxVoidPreflightRepl=repl
    return true
  end
  return false
end
Atmos._preflightVoidOwnership=preflightVoidOwnership

local function wrapHostVoidUnderlay(hostLib)
  if not (hostLib and type(hostLib.require)=="function") then return false end
  local okU,U=pcall(hostLib.require,"WorldUnderlay")
  if not okU or type(U)~="table" or type(U.draw)~="function" then return false end
  if U._weatherFxVoidOwnerWrapped then Atmos._WorldUnderlay=U;return true end
  local origDraw=U.draw
  U._weatherFxVoidOwnerWrapped=true
  U._weatherFxVoidOwnerOriginalDraw=origDraw
  U.draw=function(...)
    if preflightVoidOwnership() then
      Atmos._hostUnderlaySuppressed=true
      -- Deliberately suppress ONLY the giant outer plane. The host's
      -- drawFootprints safety floors still run normally beneath loaded maps so
      -- a terrain hole cannot expose Weather FX ocean through authored land.
      return false
    end
    Atmos._hostUnderlaySuppressed=false
    return origDraw(...)
  end
  Atmos._WorldUnderlay=U
  return true
end
Atmos._wrapHostVoidUnderlay=wrapHostVoidUnderlay

local function attachNightSkyHost(NightSky)
  if not (NightSky and Atmos._hostLib) then return end
  local hostLib = Atmos._hostLib
  safe(function()
    -- Always refresh DayNight so Dramaless night is seen by NightSky every frame.
    local ok, DN = safe(hostLib.require, "DayNight")
    if ok and DN then NightSky._DayNight = DN end
    if not NightSky._FirstPerson then
      local ok2, FP = safe(hostLib.require, "FirstPerson")
      if ok2 then NightSky._FirstPerson = FP end
    end
    if not NightSky._Voxel then
      -- These are alternative host module names, so a missing first choice is
      -- not a Weather FX failure. Use plain pcall for discovery to avoid
      -- feeding expected compatibility misses into protected-call telemetry.
      local ok3, Voxel = pcall(hostLib.require, "Voxel")
      if not ok3 or not Voxel then
        ok3, Voxel = pcall(hostLib.require, "VoxelState")
      end
      if ok3 and Voxel then NightSky._Voxel = Voxel end
    end
    safe(function()
      local TOD = V.require("TimeOfDay")
      if TOD then NightSky._TOD = TOD end
    end)
  end)
end

local function want3d()
  local ok, Settings = safe(V.require, "Settings")
  if ok and Settings then
    -- First-person: always 3D weather (overrides WX PRESENT = 2D).
    if Settings.isFirstPerson and Settings.isFirstPerson() then return true end
    if Settings.force2dPresent and Settings.force2dPresent() then return false end
    if Settings.allow3dPresent and not Settings.allow3dPresent() then return false end
  end
  return true
end

-- 3D cloud banks are an independent player feature. WX PRESENT = 2D controls
-- precipitation/weather presentation; it must not silently override 3D CLOUDS.
-- This is the key mixed-mode seam for 2D rain/snow under world-space cloud banks.
local function clouds3dWanted()
  local ok,Settings=safe(V.require,"Settings")
  if ok and Settings and Settings.cloudsOn then
    local good,yes=safe(Settings.cloudsOn)
    if good then return yes~=false end
  end
  return true
end
Atmos._clouds3dWanted=clouds3dWanted

-- Celestial ownership is independently selectable from precipitation. A player
-- can keep classic 2D rain/snow/fog while sun/moon/stars remain true world-space
-- geometry in the voxel scene. MATCH WEATHER preserves the historical coupling.
local function celestialWorldWanted()
  -- 8.2.8: when the weather pipeline itself is 3D, the astronomical vault is
  -- part of that world and cannot be switched into a flat/absent layer. This
  -- keeps the sun/moon orbit and stars/constellations alive behind cloud geometry
  -- at all times; clouds drawn later reveal them only through real gaps.
  if want3d() then return true end
  local ok,Settings=safe(V.require,"Settings")
  if ok and Settings and Settings.use3dCelestial then
    local good,yes=safe(Settings.use3dCelestial)
    if good then return yes and true or false end
  end
  return false
end

-- Lightning may independently opt into the world-space renderer while WEATHER
-- RENDERING remains 2D OVERLAY. This wakes only the lightning subpass; it does
-- not turn on 3D precipitation, fog, rays, puddles, or other weather.
local function lightning3dWanted()
  if want3d() then return true end
  local ok,Settings=safe(V.require,"Settings")
  if ok and Settings and Settings.wants3dLightningWith2dWeather then
    local good,yes=safe(Settings.wants3dLightningWith2dWeather)
    if good then return yes and true or false end
  end
  return false
end
Atmos._lightning3dWanted=lightning3dWanted


local function chunkFor(rel)
  local source = mod:read(rel)
  if not source then error("missing " .. rel, 0) end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then error(rel .. " compile: " .. tostring(err), 0) end
  return chunk
end

-- Build a private 3D namespace. Weather FX authority modules are resolved from
-- Weather FX itself; true voxel/render APIs come from the host. Never writes into
-- the host mod.
local function buildNamespace(hostLib)
  local own = {}
  local resolving = {}
  local W = { path = mod.path, mod = mod, safeCall = safe }

  local STUBS = {
    ForestAtmos = "lib/voxel_atmos/stubs/ForestAtmos.lua",
    Mat4 = "lib/voxel_atmos/stubs/Mat4.lua",
    TileShape = "lib/voxel_atmos/stubs/TileShape.lua",
    SpriteBillboards = "lib/voxel_atmos/stubs/SpriteBillboards.lua",
    TerrainAtlas = "lib/voxel_atmos/stubs/TerrainAtlas.lua",
  }

  local OWN = {
    CinematicAtmos = "lib/voxel_atmos/CinematicAtmos.lua",
    WorldPrecip = "lib/voxel_atmos/WorldPrecip.lua",
    WorldLightning = "lib/voxel_atmos/WorldLightning.lua",
    WorldLighting = "lib/voxel_atmos/WorldLighting.lua",
    WorldCelestialLighting = "lib/voxel_atmos/WorldCelestialLighting.lua",
    NpcLightning = "lib/voxel_atmos/NpcLightning.lua",
    Tornado3D = "lib/voxel_atmos/Tornado3D.lua",
    Rainbow3D = "lib/voxel_atmos/Rainbow3D.lua",
    DistantWorld = "lib/voxel_atmos/DistantWorld.lua",
    HorizonApron = "lib/voxel_atmos/HorizonApron.lua",
    WeatherSetting = "lib/voxel_atmos/WeatherSetting.lua",
    ConnectedWater3D = "lib/voxel_atmos/ConnectedWater3D.lua",
    -- These are Weather FX private 3D helpers too.  Leaving them out of OWN
    -- made the Battle Art host resolver look for host/root modules with the
    -- same names; Battle Art 1.10.4 has neither, so gust-front geometry and
    -- roof/canopy interaction precipitation silently failed closed.
    GustFront = "lib/voxel_atmos/GustFront.lua",
    WorldInteractionPrecip = "lib/voxel_atmos/WorldInteractionPrecip.lua",
  }

  -- These names are Weather FX authorities, not voxel-host extension points.
  -- Host mods commonly have their own Settings/Scene/Types modules with
  -- unrelated schemas. Resolving those first can leave rain alive through the
  -- embedded cinematic rain profile while every Weather FX-only family gets a
  -- zero channel. Always bind these names to Weather FX's root namespace.
  local ROOT_OWN = {
    Types = true,
    Config = true,
    Settings = true,
    Quality = true,
    Scene = true,
    TimeOfDay = true,
    CelestialSim = true,
    CelestialEngine = true,
    -- Lightning is also Weather FX authority. The private 3D namespace must
    -- publish world-bolt distances onto the same root scheduler object that
    -- Audio consumes; a same-named host helper would split the event stream.
    Lightning = true,
    WindEngine = true,
    LeafPhysics = true,
    SnowPack = true,
    Tornado = true,
    Rainbow = true,
    WindPlayer = true,
    FlatWorldInteraction = true,
    ConnectedWater = true,
    -- These APIs are also Weather FX authorities.  Resolve them from the root
    -- namespace before asking a voxel host for same-named helpers; the private
    -- 3D modules rely on Weather FX battle/surface-interaction semantics.
    Battle = true,
    SnowSurfacePaint = true,
    WeatherWorldInteraction = true,
    -- Root-owned environment/realism helpers. These are Weather FX modules,
    -- never voxel-host extension points. Resolve them locally before touching
    -- hostLib.require so a host that logs failed requires does not emit false
    -- "reinstall the mod" warnings for perfectly valid Weather FX modules.
    WeatherState = true,
    DistantWeather = true,
    -- 8.1.59: this is Weather FX's private GPU front-particle backend. Letting
    -- Voxel Nexus/other hosts resolve it first produces a noisy failed host
    -- require and unnecessarily forces the CPU fallback.
    DistantFrontPrecip = true,
    ParticleBatcher = true,
    EnvironmentSurface = true,
    MesoscaleField = true,
    SurfaceVisualState = true,
    UnifiedLighting = true,
    WeatherWorldSpace = true,
    WorkloadRouter = true,
    WindFlow = true,
    VolumetricRenderer = true,
    CelestialBodies = true,
    CloudField = true,
    NightSky = true,
    Aurora = true,
    PerformanceGovernor = true,
    ProceduralPrecipField = true,
    ProceduralSnowField = true,
    SpatialIndex = true,
  }

  -- Optional host-only helpers must never fall through to Weather FX's root
  -- namespace. Gen2Recomped-DramaticShapes intentionally has no
  -- RenderDistance module; callers already pcall this extension point and
  -- safely fall back to camera/voxel bounds. Treating a miss as a root require
  -- used to create a false protected-call warning during otherwise valid Gen2
  -- 3D lightning frames.
  local OPTIONAL_HOST_ONLY = {
    RenderDistance = true,
  }

  local function finish(name, value)
    resolving[name] = nil
    own[name] = value
    return value
  end

  function W.require(name)
    if own[name] ~= nil then return own[name] end
    if resolving[name] then error("circular require " .. name, 0) end
    resolving[name] = true

    if OWN[name] then
      local ok, value = safe(function() return chunkFor(OWN[name])(W) end)
      if ok and value ~= nil then return finish(name, value) end
      resolving[name] = nil
      error(ok and (name .. " returned nil") or tostring(value), 0)
    end

    if ROOT_OWN[name] then
      local okRoot, valueRoot = safe(V.require, name)
      if okRoot and valueRoot ~= nil then return finish(name, valueRoot) end
      -- Do not fall through to a same-named host module: it is the wrong API.
      -- Clear the resolving marker so a module that appears later in startup can
      -- be retried on the next frame instead of being cached as a fake cycle.
      resolving[name] = nil
      error("DramalessAtmos: cannot resolve Weather FX root " .. tostring(name), 0)
    end

    -- Host-owned rendering/voxel APIs are preferred for true extension points
    -- such as Voxel3D, Sky, ShadowMap and DayNight.
    if hostLib and hostLib.require then
      -- This lookup is speculative: not every supported voxel host implements
      -- every optional rendering helper. A miss means "use our stub/root
      -- fallback", not "Weather FX failed", so do not report it through the
      -- exponential SafeCall error logger.
      local ok, value = pcall(hostLib.require, name)
      if ok and value ~= nil then return finish(name, value) end
    end

    if STUBS[name] then
      local ok, value = safe(function() return chunkFor(STUBS[name])(W) end)
      if ok and value ~= nil then return finish(name, value) end
      resolving[name] = nil
      error(ok and (name .. " stub returned nil") or tostring(value), 0)
    end

    if OPTIONAL_HOST_ONLY[name] then
      resolving[name] = nil
      error("optional voxel-host module unavailable: " .. tostring(name), 0)
    end

    -- Last resort for non-colliding Weather FX helpers. Failed lookups are
    -- deliberately NOT cached; startup/load-order races must be able to recover.
    local okOwn, valueOwn = safe(V.require, name)
    if okOwn and valueOwn ~= nil then return finish(name, valueOwn) end

    resolving[name] = nil
    error("DramalessAtmos: cannot resolve " .. tostring(name), 0)
  end

  W.data = hostLib and hostLib.data
  return W
end

function Atmos.benchmarkStats(out)
  out=out or {}
  local WPmod=nil
  safe(function()
    if Atmos._ns then WPmod=Atmos._ns.require("WorldPrecip") end
  end)
  if WPmod and WPmod.liveCounts then
    local ok,res=safe(WPmod.liveCounts,out)
    if ok and type(res)=="table" then return res end
  end
  return out
end

local function benchmarkModule()
  if Atmos._Benchmark~=nil then return Atmos._Benchmark or nil end
  local ok,m=safe(V.require,"Benchmark")
  Atmos._Benchmark=(ok and m) or false
  return m
end

local function clamp01(x)
  x=tonumber(x) or 0
  if x<0 then return 0 end
  if x>1 then return 1 end
  return x
end

local function smooth01(x)
  x=clamp01(x)
  return x*x*(3-2*x)
end

-- Conservative direct-sun line-of-sight test used only inside the narrow
-- direct-look glare cone. The sun/moon/star meshes are hardware depth-tested;
-- this companion check prevents the screen-space god-ray/whiteout response
-- from surviving when the SUN ITSELF is hidden by a building, terrain column,
-- or posed NPC. It runs only while looking inside the direct-sun optics cone.
local function sunBlockedByWorld(Voxel3D,sun)
  local e=Voxel3D and Voxel3D.eye
  if not (e and sun) then return false end
  local dx,dy,dz=tonumber(sun.dx) or 0,tonumber(sun.dy) or 0,tonumber(sun.dz) or 0
  local dl=math.sqrt(dx*dx+dy*dy+dz*dz); if dl<1e-7 then return false end
  dx,dy,dz=dx/dl,dy/dl,dz/dl

  local VS=Atmos._VoxelScene
  local function dims(map)
    if not map then return 0,0 end
    local w,h=tonumber(map.widthCells),tonumber(map.heightCells)
    if (not w or w<=0) and map.def then local v=tonumber(map.def.width); if v and v>0 then w=v*2 end end
    if (not h or h<=0) and map.def then local v=tonumber(map.def.height); if v and v>0 then h=v*2 end end
    return math.max(0,math.floor(w or 0)),math.max(0,math.floor(h or 0))
  end
  local function groundWorld(x,z)
    if not (VS and type(VS.groundAt)=="function") then return nil end
    local function sample(map,ox,oz)
      local w,h=dims(map); if w<=0 or h<=0 then return nil end
      local lx,lz=x-(tonumber(ox) or 0),z-(tonumber(oz) or 0)
      if lx<0 or lz<0 or lx>=w*16 or lz>=h*16 then return nil end
      local ok,v=safe(VS.groundAt,map,math.floor(lx/16),math.floor(lz/16))
      if ok and type(v)=="number" and v==v then return v end
      return nil
    end
    local v=sample(Atmos._lastMap,0,0); if v~=nil then return v end
    for _,nb in ipairs(Atmos._lastNeighbors or {}) do
      if nb and nb.map then v=sample(nb.map,nb.ox or 0,nb.oy or nb.oz or 0); if v~=nil then return v end end
    end
    return nil
  end

  -- Terrain/buildings: groundAt is the host's solid-column top authority.
  -- Start beyond the player's own cell and march only through the rendered
  -- neighborhood. A 4-unit step is comfortably below one voxel tile.
  if VS and type(VS.groundAt)=="function" then
    for t=8,320,4 do
      local x,y,z=(e[1] or 0)+dx*t,(e[2] or 0)+dy*t,(e[3] or 0)+dz*t
      local gh=groundWorld(x,z)
      if gh~=nil and gh>y+0.20 then return true end
    end
  end

  -- Posed NPCs: finite vertical cylinders matching the collision dimensions
  -- used by Weather FX leaf/NPC physics. This matters mostly for a low sun.
  local hx,hz=dx,dz; local h2=hx*hx+hz*hz
  if h2>1e-6 then
    local function blocksNpc(px,pz,y0,r,height)
      px,pz=tonumber(px),tonumber(pz); if not (px and pz) then return false end
      local ex,ez=(e[1] or 0),(e[3] or 0)
      local t=((px-ex)*hx+(pz-ez)*hz)/h2
      if t<=0 or t>220 then return false end
      local rx,rz=ex+hx*t-px,ez+hz*t-pz
      if rx*rx+rz*rz>(r or 6.4)^2 then return false end
      local yy=(e[2] or 0)+dy*t; y0=tonumber(y0) or 0
      return yy>=y0-0.25 and yy<=y0+(height or 17.5)+0.25
    end
    local posed=Atmos._lastPosed or {}
    if #posed>0 then
      for _,q in ipairs(posed) do
        local ent=q and q.entity
        if q and ent and ent~=Atmos._lastPlayer then
          local y0=(tonumber(q.gh) or 0)+(tonumber(q.lift) or 0)
          if blocksNpc((tonumber(q.px) or 0)+8,(tonumber(q.py) or 0)+8,y0,6.4,17.5) then return true end
        end
      end
    else
      local st=Atmos._lastState
      for _,ent in ipairs((st and st.entities) or {}) do
        if ent and ent~=Atmos._lastPlayer then
          local px=tonumber(ent.px) or (tonumber(ent.cellX) and tonumber(ent.cellX)*16)
          local pz=tonumber(ent.py) or (tonumber(ent.cellY) and tonumber(ent.cellY)*16)
          if px and pz then
            local y0=0
            if VS and type(VS.groundAt)=="function" and st and st.map and tonumber(ent.cellX) and tonumber(ent.cellY) then
              local ok,v=safe(VS.groundAt,st.map,tonumber(ent.cellX),tonumber(ent.cellY)); if ok and type(v)=="number" then y0=v end
            end
            if blocksNpc(px+8,pz+8,y0,6.4,17.5) then return true end
          end
        end
      end
    end
  end
  return false
end

-- True camera forward for optics. Several supported voxel hosts publish
-- `focus` as the player/world anchor rather than a look target, so eye->focus
-- can point almost straight down even while the player looks at the horizon.
-- Prefer explicit host camera vectors, then the host FirstPerson yaw/pitch,
-- and use eye->focus only when it is a plausible view ray.
local function cameraViewDirection(Voxel3D)
  if not Voxel3D then return nil end
  local cam=Voxel3D.camera
  local cf=cam and (cam.forward or cam.look)
  if type(cf)=="table" then
    local x,y,z=tonumber(cf[1]),tonumber(cf[2]),tonumber(cf[3])
    if x and y and z then local l=math.sqrt(x*x+y*y+z*z);if l>1e-6 then return x/l,y/l,z/l end end
  end
  local NS=Atmos._NightSky
  local FP=NS and NS._FirstPerson
  if FP and type(FP.yaw)=="number" then
    local yaw=FP.yaw;local pitch=type(FP.pitch)=="number" and FP.pitch or 0
    local cp=math.cos(pitch)
    return math.sin(yaw)*cp,-math.sin(pitch),math.cos(yaw)*cp
  end
  local e,fo=Voxel3D.eye,Voxel3D.focus
  if e and fo then
    local x,y,z=(tonumber(fo[1]) or 0)-(tonumber(e[1]) or 0),(tonumber(fo[2]) or 0)-(tonumber(e[2]) or 0),(tonumber(fo[3]) or 0)-(tonumber(e[3]) or 0)
    local h2=x*x+z*z;local l2=h2+y*y
    if l2>1e-8 and h2>=l2*.0625 then local l=math.sqrt(l2);return x/l,y/l,z/l end
  end
  -- A horizontal heading is still preferable to a bogus downward focus on
  -- hosts that omit pitch. It enables horizon-level sun optics; elevated-sun
  -- alignment remains conservative until the host supplies a full 3D vector.
  local lf=Voxel3D.lookFlat
  if type(lf)=="table" then
    local x,z=tonumber(lf[1]),tonumber(lf[3] or lf[2])
    if x and z then local l=math.sqrt(x*x+z*z);if l>1e-6 then return x/l,0,z/l end end
  end
  return nil
end
Atmos._cameraViewDirection=cameraViewDirection

-- Project a direct-look sun even on voxel hosts whose matrix format cannot be
-- consumed by NightSky.projectDirection. The normal host projector remains the
-- first choice; this basis fallback is only an optics fail-safe inside 18 deg.
local function fallbackSunScreen(Voxel3D,sun,w,h)
  local fx,fy,fz=cameraViewDirection(Voxel3D)
  if not (fx and sun) then return nil end
  local rx,ry,rz=-fz,0,fx;local rl=math.sqrt(rx*rx+rz*rz)
  if rl<1e-6 then rx,ry,rz=1,0,0 else rx,rz=rx/rl,rz/rl end
  local ux,uy,uz=fy*rz-fz*ry,fz*rx-fx*rz,fx*ry-fy*rx
  local dl=math.sqrt((sun.dx or 0)^2+(sun.dy or 0)^2+(sun.dz or 0)^2);if dl<1e-6 then return nil end
  local dx,dy,dz=(sun.dx or 0)/dl,(sun.dy or 0)/dl,(sun.dz or 0)/dl
  local front=dx*fx+dy*fy+dz*fz;if front<=.05 then return nil end
  local sx=(dx*rx+dy*ry+dz*rz)/front;local sy=(dx*ux+dy*uy+dz*uz)/front
  -- Approximate the common voxel camera's ~70 degree horizontal field only as
  -- fallback. The direct-look cone is narrow, so this remains close to centre.
  local tanHalf=math.tan(math.rad(35))
  return w*.5+(sx/tanHalf)*w*.5,h*.5-(sy/tanHalf)*h*.5
end
Atmos._fallbackSunScreen=fallbackSunScreen

-- Scene-level colour/glare pass for strict 3D. This is drawn into the voxel
-- scene itself after volumetric weather but before the host resolves its canvas.
-- It therefore grades only the rendered world, never menus/HUD/text boxes.
local function draw3dScenePost(Voxel3D,outdoor)
  if not outdoor or not (love and love.graphics and Voxel3D) then return end
  local w,h
  if Voxel3D.size then local ok,cw,ch=safe(Voxel3D.size); if ok then w,h=cw,ch end end
  w=tonumber(w) or 160; h=tonumber(h) or 144
  if w<=1 or h<=1 then return end

  local prevShader,prevDepth,prevWrite,prevBlend,prevAlpha,pr,pg,pb,pa
  safe(function() prevShader=love.graphics.getShader() end)
  safe(function() prevDepth,prevWrite=love.graphics.getDepthMode() end)
  safe(function() prevBlend,prevAlpha=love.graphics.getBlendMode() end)
  safe(function() pr,pg,pb,pa=love.graphics.getColor() end)
  safe(love.graphics.setShader)
  safe(love.graphics.setDepthMode)

  -- Match the legacy 2D PSYSTORM wash exactly, but apply it only to the voxel
  -- scene. The eased WeatherState.psy channel remains the intensity authority.
  local psy=0
  safe(function()
    local WS=V.require("WeatherState")
    if WS and type(WS.ch)=="table" then psy=tonumber(WS.ch.psy) or 0 end
  end)
  if tostring(Atmos._wxId or ""):upper()=="PSYSTORM" then psy=math.max(psy,.01) end
  if psy>.004 then
    -- Match the 2D Psychic Storm's additive violet emission, but keep it
    -- inside the voxel scene so HUD/menu layers are never tinted.
    safe(love.graphics.setBlendMode,"add","alphamultiply")
    safe(love.graphics.setColor,.42,.10,.55,math.min(.60,psy*.42))
    safe(love.graphics.rectangle,"fill",0,0,w,h)
    Atmos._lastPsyWash=math.min(.60,psy*.42)
  else
    Atmos._lastPsyWash=0
  end

  -- Direct-sun optics: no passive halo merely because the disc is on-screen.
  -- Rays begin only in a narrow centre-aim cone and ramp smoothly to a
  -- near-white sensor wash. Cloud transmission is the occlusion authority.
  local glare=0
  Atmos._lastLensFlareCount=0
  Atmos._lastSunGlareReason="inactive"
  safe(function()
    local C=V.require("Config")
    if C and type(C.visual)=="function" and not C.visual("glare") then Atmos._lastSunGlareReason="disabled";return end
    local screenScale=1
    local okS,S=pcall(V.require,"Settings")
    if okS and S and S.screenEffectsScale then screenScale=tonumber(S.screenEffectsScale()) or 1 end
    if screenScale<=0 then Atmos._lastSunGlareReason="screen-effects-off";return end
    local CE=V.require("CelestialEngine"); local st=CE and CE.state and CE.state(); local sun=st and st.sun
    if not (sun and Voxel3D.eye) then Atmos._lastSunGlareReason="camera-unavailable";return end
    -- 8.1.15: first-limb sunrise is the visibility authority. The solar centre
    -- can still be below the horizon while the upper limb is already visible,
    -- so do not gate glare/rays on sun.dy. This prevents a late optical pop.
    local discVis=clamp01(tonumber(st and st.solarDiscVisibility) or tonumber(sun.horizonFraction) or 0)
    local rise=clamp01(tonumber(st and st.solarRayRamp) or discVis)
    if (tonumber(sun.alpha) or 0)<=.01 or discVis<=0 or rise<=0 then Atmos._lastSunGlareReason="sun-not-visible";return end
    local fx,fy,fz=cameraViewDirection(Voxel3D)
    if not fx then Atmos._lastSunGlareReason="camera-forward-unavailable";return end
    local dot=math.max(-1,math.min(1,fx*(sun.dx or 0)+fy*(sun.dy or 0)+fz*(sun.dz or 0)))
    -- 8.1.26: optical response begins much earlier than the old 7.5-degree hard
    -- cone. Separate flare/ray/wash/whiteout bands make the approach gradual:
    -- faint lens response first, then rays, then a warm sensor wash, with true
    -- blinding whiteout reserved for increasingly direct staring.
    local angleDeg=math.deg(math.acos(dot))
    local glareStart=18.0; if angleDeg>=glareStart then Atmos._lastSunGlareReason="outside-look-cone";return end
    -- The visible disc is depth-tested. Gate the separate screen-space glare
    -- against the same world line of sight so a roof/wall/NPC cannot hide the
    -- sun while its god rays or whiteout keep shining through that occluder.
    if sunBlockedByWorld(Voxel3D,sun) then Atmos._lastSunGlareReason="world-occluded";return end
    local align=smooth01((glareStart-angleDeg)/glareStart)
    local rayAlign=smooth01((15.0-angleDeg)/13.0)
    local warmAlign=smooth01((13.0-angleDeg)/11.0)
    local whiteAlign=smooth01((11.5-angleDeg)/10.5)
    -- 8.2.8: celestial body alpha no longer globally disappears under a 3D
    -- deck. Direct camera optics still obey the exact cloud ray so glare/rays
    -- cannot shine through cloud bodies; the disc itself is occluded by the
    -- later cloud geometry and remains visible only through real gaps.
    local trans=clamp01(tonumber(sun.cloudLineTransmission) or tonumber(sun.discTransmission) or 1)^1.25; local bodyA=clamp01(tonumber(sun.alpha) or 0)
    glare=clamp01(align*trans*bodyA*rise)*screenScale; if glare<=.001 then Atmos._lastSunGlareReason="too-dim";return end
    local x,y; local NS=V.require("NightSky"); if NS and NS.projectDirection then x,y=NS.projectDirection(Voxel3D,sun.dx,sun.dy,sun.dz,w,h) end
    if not (x and y) then x,y=fallbackSunScreen(Voxel3D,sun,w,h) end
    if not (x and y) then Atmos._lastSunGlareReason="projection-failed";return end
    Atmos._lastSunGlareReason="drawing"

    -- 8.1.16 camera optics. Real lenses produce a compact bloom around the
    -- solar image plus faint ghost circles mirrored through the optical axis.
    -- They are gaze-, cloud-, body-alpha- and sunrise-ramp-gated by `glare`, so
    -- the effect cannot shine through clouds/geometry or pop on at sunrise.
    Atmos._lastLensFlareCount=0
    local flareStrength=(glare^1.30)*(.52+.48*rise)
    if flareStrength>.004 and love.graphics.circle then
      safe(love.graphics.setBlendMode,"add","alphamultiply")
      local function softDisc(px,py,rad,rr,gg,bb,aa)
        for ring=7,1,-1 do
          local t=ring/7; local fall=(1-t); local a0=aa*(.035+.19*fall*fall)
          safe(love.graphics.setColor,rr,gg,bb,a0)
          safe(love.graphics.circle,"fill",px,py,math.max(.6,rad*t))
        end
      end
      local minDim=math.max(1,math.min(w,h))
      -- Sensor bloom is compact enough to preserve photosphere detail.
      softDisc(x,y,minDim*.071,1.0,.84,.42,flareStrength*.46)
      softDisc(x,y,minDim*.042,1.0,.97,.78,flareStrength*.36)
      local cx,cy=w*.5,h*.5; local vx,vy=cx-x,cy-y
      local ghosts={
        {.34,.026,1.00,.62,.58,.22},
        {.63,.044,.62,.88,1.00,.16},
        {.91,.021,.78,1.00,.86,.14},
        {1.18,.058,.70,.82,1.00,.13},
        {1.47,.032,1.00,.72,.82,.12},
        {1.76,.074,.70,.92,.96,.085},
      }
      for i=1,#ghosts do
        local g=ghosts[i]; softDisc(x+vx*g[1],y+vy*g[1],minDim*g[2],g[3],g[4],g[5],flareStrength*g[6])
      end
      Atmos._lastLensFlareCount=#ghosts
    end
    local rays=(rayAlign^1.25)*trans*bodyA*rise
    if rays>.004 then
      safe(love.graphics.setBlendMode,"add","alphamultiply"); local extent=math.sqrt(w*w+h*h)*1.18; local TAU=math.pi*2
      for i=1,28 do
        local ang=(i-1)*(TAU/28)+math.sin(i*3.71)*.045; local spread=.012+.018*((i*37)%11)/10; local len=extent*(.72+.40*((i*53)%17)/16)
        local aa,bb=ang-spread,ang+spread; local x1,y1=x+math.cos(aa)*len,y+math.sin(aa)*len; local x2,y2=x+math.cos(bb)*len,y+math.sin(bb)*len
        safe(love.graphics.setColor,1,.94,.72,rays*(.020+.024*((i*29)%13)/12)); safe(love.graphics.polygon,"fill",x,y,x1,y1,x2,y2)
      end
    end
    local white=(whiteAlign^1.55)*trans*bodyA*rise; local warm=(warmAlign^1.30)*trans*bodyA*rise
    safe(love.graphics.setBlendMode,"alpha","alphamultiply"); safe(love.graphics.setColor,1,.91,.66,math.min(.38,warm*.32)); safe(love.graphics.rectangle,"fill",0,0,w,h)
    safe(love.graphics.setColor,1,.995,.965,math.min(.94,white*.94)); safe(love.graphics.rectangle,"fill",0,0,w,h)
  end)
  Atmos._lastSunGlare=glare

  if prevShader then safe(love.graphics.setShader,prevShader) else safe(love.graphics.setShader) end
  if prevDepth then safe(love.graphics.setDepthMode,prevDepth,prevWrite) else safe(love.graphics.setDepthMode,"lequal",true) end
  if prevBlend then safe(love.graphics.setBlendMode,prevBlend,prevAlpha) end
  if pr then safe(love.graphics.setColor,pr,pg,pb,pa) end
end
Atmos._draw3dScenePost=draw3dScenePost

local function drawWorldCelestial()
  local Voxel3D=Atmos._Voxel3D
  if not (Atmos._drawing and celestialWorldWanted() and Voxel3D and Voxel3D.vp) then
    Atmos._worldCelestialDrew=false
    return false
  end
  Atmos._worldCelestialDrew=false
  safe(function()
    if not Atmos._NightSky then Atmos._NightSky=V.require("NightSky") end
    local NS=Atmos._NightSky; if not NS then return end
    attachNightSkyHost(NS)
    local cw,ch; if Voxel3D.size then local good,w0,h0=safe(Voxel3D.size); if good then cw,ch=w0,h0 end end
    local tt=(Atmos._forest and Atmos._forest.time) or 0
    local CR2=V.require("CelestialRenderer2")
    local drew=CR2 and CR2.drawProjected and CR2.drawProjected(Voxel3D,tt,cw,ch) or false
    Atmos._worldCelestialDrew=drew and true or false
    Atmos._celestialBackgroundDrew=Atmos._worldCelestialDrew
  end)
  return Atmos._worldCelestialDrew
end

local function drawInScene()
  if not Atmos._drawing then return end
  local fullWeather=want3d()
  local cloudWeather=clouds3dWanted()
  local lightningWeather=lightning3dWanted()
  if not fullWeather and not cloudWeather and not lightningWeather then return end
  safe(function()
    local TOD = V.require("TimeOfDay")
    local night = TOD and (TOD.pin == "NITE" or TOD.tod == "NITE" or (TOD.isNight and TOD.isNight()))
    package.loaded._WX_NIGHT = night and true or false
  end)
  local cin = Atmos._cin
  local Voxel3D = Atmos._Voxel3D
  if not (cin and Voxel3D and Voxel3D.vp) then return end

  -- Animation clock is advanced in Atmos.update(dt). Do not call
  -- ForestAtmos.update(0) here — that was a no-op that invited TOD snaps.

  -- Align light-shaft shear with the host sun/moon *this frame*.
  -- Cache DayNight/ShadowMap on Atmos so we never hostLib.require per frame.
  safe(function()
    if not Atmos._DayNight or not Atmos._ShadowMap then
      local hostLib = Atmos._hostLib
      if not hostLib then return end
      if not Atmos._DayNight then
        local ok, DN = safe(hostLib.require, "DayNight")
        if ok then Atmos._DayNight = DN end
      end
      if not Atmos._ShadowMap then
        local ok, SM = safe(hostLib.require, "ShadowMap")
        if ok then Atmos._ShadowMap = SM end
      end
    end
    local DayNight, ShadowMap = Atmos._DayNight, Atmos._ShadowMap
    if not ShadowMap then return end
    -- ONE celestial-shadow authority only. Older revisions wrote the raw
    -- TimeOfDay/CelestialBodies shear here, then DayNight.applyRig wrote the
    -- smoothed CelestialEngine shear later in the same frame. Because the raw
    -- clock is slightly ahead of the presentation clock, the visible shadow
    -- could twitch forward, be corrected backward, then step forward again.
    -- Read the same frame-smoothed rig used everywhere else instead.
    local kx, kz
    safe(function()
      local CE = V.require("CelestialEngine")
      if CE and CE.shadowRig then kx, kz = CE.shadowRig() end
    end)
    if type(kx) ~= "number" and DayNight and DayNight.shearAt then
      kx, kz = DayNight.shearAt(nil)
    end
    if type(kx) == "number" and type(kz) == "number" then
      ShadowMap.KX, ShadowMap.KZ = kx, kz
    end
  end)

  local map = Atmos._lastMap
  local outdoor = Atmos._lastOutdoor
  if outdoor == nil then outdoor = true end

  local prevBlend, prevAlpha
  safe(function()
    prevBlend, prevAlpha = love.graphics.getBlendMode()
  end)
  local pr, pg, pb, pa
  safe(function() pr, pg, pb, pa = love.graphics.getColor() end)

  -- 8.0.4/8.1.67 celestial occlusion authority. Celestial presentation is
  -- independently selectable from weather presentation; when enabled, project
  -- the infinite vault after world depth exists even if precipitation remains 2D.
  -- Preserve historical full-3D behavior; in mixed 2D-weather mode only draw
  -- the celestial vault when its own CELESTIAL RENDERING setting requests 3D.
  if fullWeather or celestialWorldWanted() then drawWorldCelestial() end

  -- A primary rainbow is sky geometry, not a screen overlay. Draw it after the
  -- far celestial vault (so terrain/buildings can depth-occlude it) and before
  -- clouds/weather (so a surviving cloud bank can naturally hide parts of it).
  if fullWeather then
    safe(function()
      local RB=Atmos._ns and Atmos._ns.require("Rainbow3D")
      if RB and RB.draw then RB.draw(Voxel3D) end
    end)
  end

  local BM=benchmarkModule()
  if BM and BM.beginAtmos then BM.beginAtmos() end
  local ok, err = safe(function()
    if cin.draw then
      local policy=Atmos._drawPolicy or {};Atmos._drawPolicy=policy
      policy.weather3d=fullWeather;policy.clouds3d=cloudWeather;policy.lightning3d=lightningWeather
      cin.draw(map, outdoor, Atmos._lastNeighbors, Atmos._lastPosed, Atmos._lastPlayer, Atmos._lastState, policy)
    end
  end)
  if BM and BM.endAtmos then BM.endAtmos() end
  if not ok then
    Atmos._lastDrawError = tostring(err)
    safe(function() if cin.markFrameFailed then cin.markFrameFailed() end end)
    -- An exception before CinematicAtmos reaches its own precipitation guard
    -- must revoke LAST FRAME'S draw proof. Otherwise Draw.lua can suppress the
    -- 2D safety layer using stale counters while the whole 3D pass is broken.
    safe(function()
      if Atmos._ns then
        local WPmod = Atmos._ns.require("WorldPrecip")
        if WPmod and WPmod.markDrawFailed then WPmod.markDrawFailed() end
      end
    end)
  else
    local sub = nil
    if cin.drawErrors then safe(function() sub = cin.drawErrors() end) end
    Atmos._lastDrawError = sub
  end

  -- Gale funnels are true world geometry, so buildings/actors can occlude them
  -- through the same scene depth buffer. They are drawn after the cloud/weather
  -- body and before transient NPC lightning reaction overlays.
  if fullWeather then
    local T3=Atmos._tornado3dForRuntime()
    if T3 and T3.draw then safe(T3.draw,Voxel3D) end
  end

  -- A lightning-char overlay is deliberately independent of the atmosphere
  -- subpasses. It redraws only an already-rendered NPC and expires in memory;
  -- no host sprite, texture or entity state is ever mutated.
  if fullWeather then
    local NL = Atmos._npcLightningForRuntime()
    if NL and NL.draw then safe(NL.draw,Voxel3D) end
  end

  -- Final 3D-only scene colour/lens response: PSYSTORM violet wash and
  -- camera-facing solar glare. This remains under the game's HUD/UI because it
  -- is composited into the voxel scene before endScene resolves the canvas.
  if fullWeather then safe(draw3dScenePost,Voxel3D,outdoor) end

  safe(love.graphics.setShader)
  if prevBlend then safe(love.graphics.setBlendMode, prevBlend, prevAlpha) end
  if pr then safe(love.graphics.setColor, pr, pg, pb, pa) end
  safe(love.graphics.setDepthMode, "lequal", true)
end

function Atmos.install()
  if Atmos._ready and Atmos._active then return true end
  Atmos._ready = true
  Atmos._active = false
  Atmos._drawing = false

  local host, hostId = findHost()
  if not host then
    Atmos._reason = "no-3d-voxel-host"
    return false
  end
  Atmos._hostId = hostId

  -- The voxel host supplies the clock when available, but Weather FX keeps
  -- astronomy active and derives the physical light rig from that shared clock.
  safe(function()
    local TOD = V.require("TimeOfDay")
    if TOD and TOD.setHostOwnsClock then
      TOD.setHostOwnsClock(true)
    end
  end)
  if not (host.exports and host.exports.lib) then
    Atmos._reason = "host-missing-exports-lib"
    return false
  end

  local hostLib = host.exports.lib
  Atmos._hostLib = hostLib
  -- Grid movement uses movement.speed. Dramatic/first-person free-move hosts
  -- bypass that step hook, so install an in-memory wrapper over their own
  -- movement vector when the optional FreeMove seam exists. No host file is
  -- edited and unsupported hosts simply keep the normal grid hook.
  safe(function()
    local WP=V.require("WindPlayer")
    if WP and WP.installFreeMove then WP.installFreeMove(hostLib) end
  end)
  local W = buildNamespace(hostLib)
  -- Keep the namespace reachable: handlesSnow() has to be able to ask
  -- WorldPrecip whether it is actually drawing before it suppresses the 2D
  -- layer. Without this it could only guess, which is why it gave up and
  -- returned a hardcoded false.
  Atmos._ns = W
  W.weatherFxId = Atmos._wxId or "CLEAR"

  local okV, Voxel3D = safe(function() return W.require("Voxel3D") end)
  if not okV or not Voxel3D or not Voxel3D.endScene then
    Atmos._reason = "Voxel3D-unavailable"
    return false
  end
  Atmos._Voxel3D = Voxel3D

  -- 8.1.66: install the conformal snow-surface repaint at the host's own
  -- Voxel3D draw seam. The wrapper identifies cached TERRAIN meshes by object
  -- identity and redraws those exact vertices only; no host atlas/mesh/map file
  -- is mutated and unsupported hosts fail open to their untouched render path.
  safe(function()
    local SSP=V.require("SnowSurfacePaint")
    if SSP and SSP.install then SSP.install(hostLib,Voxel3D,host) end
  end)

  -- In-memory celestial rig adapter. Weather FX owns the compatible shadow map
  -- when the host exposes the standard caster API, while DayNight consumes the
  -- same physical sun/moon direction and tint. No host file/save is edited.
  safe(function()
    local DayNight=hostLib.require("DayNight")
    local ShadowMap=hostLib.require("ShadowMap")
    if not (DayNight and ShadowMap) or DayNight._wxCelestialWrapped then return end
    DayNight._wxCelestialWrapped=true

    -- Weather FX now owns the shadow-map implementation itself. Voxel hosts
    -- keep submitting their normal terrain/building/tree/NPC/player casters
    -- through the same public ShadowMap table, so compatibility stays intact,
    -- but the host no longer owns the texture, projection, cache or GPU pass.
    -- This is an in-memory replacement only; no companion-mod file is edited.
    safe(function()
      local WXShadow=V.require("WeatherShadowMap")
      if WXShadow and WXShadow.install then
        local installed,why=WXShadow.install(hostLib,ShadowMap)
        if not installed then ShadowMap._wxInstallReason=tostring(why or "declined") end
      end
    end)
    local origApply=DayNight.applyRig
    local origTint=DayNight.tint
    local origBody=DayNight.body
    local origBodyAt=DayNight.bodyAt
    local origGlow=DayNight.glow
    local origShear=DayNight.shearAt
    function DayNight.applyRig(outdoor,...)
      local ret
      if origApply then ret=origApply(outdoor,...) end
      if outdoor then
        safe(function()
          local CE=V.require("CelestialEngine")
          local kx,kz,a=CE and CE.shadowRig and CE.shadowRig()
          if type(kx)=="number" and type(kz)=="number" then
            ShadowMap.KX,ShadowMap.KZ=kx,kz
            Voxel3D.SHADOW_KX,Voxel3D.SHADOW_KZ=kx,kz
          end
          if type(a)=="number" then Voxel3D.SHADOW_ALPHA=a end
        end)
      end
      return ret
    end
    function DayNight.tint(outdoor,...)
      if outdoor then
        local ok,CE=safe(V.require,"CelestialEngine")
        if ok and CE and CE.hostTint then
          local ok2,t=safe(CE.hostTint); if ok2 and type(t)=="table" then return t end
        end
      end
      if origTint then return origTint(outdoor,...) end
      return {1,1,1}
    end
    function DayNight.shearAt(t,...)
      local ok,CE=safe(V.require,"CelestialEngine")
      if ok and CE and CE.shadowRig then
        local ok2,kx,kz=safe(CE.shadowRig); if ok2 and type(kx)=="number" then return kx,kz,false end
      end
      return origShear and origShear(t,...) or 0,0,false
    end
    local function wxBody()
      local ok,CB=safe(V.require,"CelestialBodies")
      if ok and CB and CB.bodies then
        local ok2,b=safe(CB.bodies)
        if ok2 and b then
          local sun=b.sun
          -- Keep the host-facing body on the sun for the complete limb-contact
          -- interval. Otherwise the brighter moon can win slightly before the
          -- solar halo reaches zero, and host water/reflection code immediately
          -- suppresses solar glow when `body.moon` flips true.
          if sun and ((tonumber(sun.horizonFraction) or 0)>0 or (tonumber(sun.haloStrength) or 0)>0.0001)
             and (tonumber(sun.discTransmission) or 1)>0.02 then
            return sun
          end
          local body=((b.moon and (b.moon.intensity or 0)>(b.sun.intensity or 0)) and b.moon or b.sun)
          if body and (body.horizonFraction~=nil and (tonumber(body.horizonFraction) or 0)>0 or (body.alpha or 0)>0.02) then return body end
        end
      end
    end
    function DayNight.body(t,...)
      local body=wxBody()
      if body then
        return {dx=body.dx,dy=body.dy,dz=body.dz,moon=body.kind=="moon",_wx=true,
          phase=body.phase,illumination=body.illumination,color=body.color}
      end
      return origBody and origBody(t,...) or nil
    end
    function DayNight.bodyAt(t,...)
      local body=wxBody()
      if body then
        -- Preserve the host's bodyAt shape (azimuth°, elevation°, isMoon) and
        -- append phase as a harmless fourth value for water/companion users.
        return math.deg(body.azimuth or body.theta or 0),
          math.deg(body.altitude or body.el or 0), body.kind=="moon", body.phase
      end
      return origBodyAt and origBodyAt(t,...) or 0,0,false,nil
    end
    function DayNight.glow(t,...)
      -- Weather FX owns the visible celestial bodies. Keep host halo/glow off;
      -- atmospheric sunrise/set colour is handled by SmoothSky/AtmosphereModel,
      -- and direct staring is handled by the narrow-angle god-ray pass above.
      local ok,CE=safe(V.require,"CelestialEngine")
      if ok and CE and CE.state then local ok2,st=safe(CE.state); if ok2 and st and (st.sun or st.moon) then return 0,nil end end
      return origGlow and origGlow(t,...) or 0,nil
    end
  end)

  -- CinematicAtmos draws through beginEffect/endEffect (Dramatic Shape API).
  -- Dramaless does not define them; install safe in-memory polyfills so
  -- clouds/rays/rain can bind shaders without editing the host mod on disk.
  if type(Voxel3D.beginEffect) ~= "function" then
    function Voxel3D.beginEffect(shader)
      if not Voxel3D.vp then return false end
      if shader then
        local ok = safe(love.graphics.setShader, shader)
        if not ok then return false end
      end
      -- Keep depth test; do not write depth for translucent volumes.
      safe(love.graphics.setDepthMode, "lequal", false)
      return true
    end
  end
  if type(Voxel3D.endEffect) ~= "function" then
    function Voxel3D.endEffect()
      safe(love.graphics.setShader)
      safe(love.graphics.setDepthMode, "lequal", true)
    end
  end

  -- Scene-start wrapper now only clears celestial proof. The actual celestial
  -- draw happens from drawInScene() immediately before endScene, after world
  -- depth exists. Keeping this hook preserves frame ownership/debug semantics
  -- without reintroducing an unoccluded background copy.
  if type(Voxel3D.beginScene)=="function" and not Atmos._origBeginScene then
    Atmos._origBeginScene=Voxel3D.beginScene
    function Voxel3D.beginScene(...)
      Atmos._celestialBackgroundDrew=false
      Atmos._worldCelestialDrew=false
      return Atmos._origBeginScene(...)
    end
  end
  -- Optional fields some Kanto draws read; never crash if absent.
  if Voxel3D.focus == nil then Voxel3D.focus = { 0, 0, 0 } end
  if Voxel3D.eye == nil then Voxel3D.eye = { 0, 40, 0 } end

  local okF, forest = safe(function() return W.require("ForestAtmos") end)
  if okF then Atmos._forest = forest end

  local okC, cin = safe(function() return W.require("CinematicAtmos") end)
  if not okC or not cin then
    Atmos._reason = "CinematicAtmos-load-failed: " .. tostring(cin)
    return false
  end
  Atmos._cin = cin

  -- WorldPrecip is not optional in a full 3D atmosphere. Older builds allowed
  -- CinematicAtmos to swallow a WorldPrecip compile/load error and silently
  -- fall back to the legacy rain-only renderer. The result looked deceptively
  -- half-working: rain rendered while snow/hail/sand/leaves/ash could never
  -- spawn because their simulator did not exist. Validate it during install so
  -- a broken precipitation module makes the 3D bridge fail closed instead of
  -- masquerading as a healthy rain-only 3D implementation.
  local okWP, wpOrErr = safe(function() return W.require("WorldPrecip") end)
  if not okWP or not wpOrErr then
    Atmos._reason = "WorldPrecip-load-failed: " .. tostring(wpOrErr)
    Atmos._active = false
    Atmos._drawing = false
    return false
  end
  Atmos._worldPrecip = wpOrErr
  Atmos._worldPrecipNs = Atmos._ns

  safe(function() Atmos._distant = W.require("DistantWorld") end)
  safe(function() Atmos._horizon = W.require("HorizonApron") end)

  -- Night stars/planets + greyer rain sky via one Sky.paint wrap (host only).
  if not Atmos._skyWrapped then
    local okSky, Sky = safe(function() return hostLib.require("Sky") end)
    if okSky and Sky and type(Sky.paint) == "function" then
      local NightSky
      safe(function()
        local src = mod:read("lib/NightSky.lua")
        if not src then return end
        NightSky = assert((loadstring or load)(src, "@NightSky"))(V)
      end)
      local origPaint = Sky.paint
      -- Gen2 Sky.paint may pass extra args (top, axis, ray); always forward them.
      function Sky.paint(w, h, sky, horizonY, cell, body, ...)
        local skyArg = sky
        if NightSky and sky and sky.bands and Atmos._cin and Atmos._cin.skyWeather then
          local ok, info = safe(Atmos._cin.skyWeather)
          if ok and info then
            local copy = {}
            for k, v in pairs(sky) do copy[k] = v end
            copy.bands = NightSky.applyWeatherBands(sky.bands, info)
            skyArg = copy
          end
        end
        -- Never forward host DayNight body (wrong axis). Leave body to outer
        -- Weather FX wrap (main) which injects CelestialBodies positions.
        local result = origPaint(w, h, skyArg, horizonY, cell, nil, ...)
        attachNightSkyHost(NightSky)
        -- main.lua owns the final Weather FX night-sky draw when its shared
        -- Sky wrapper is installed.  This wrapper still applies Dramaless
        -- weather bands, but must not paint the same stars/planets a second
        -- time.  Check dynamically so install order cannot change ownership.
        if not Sky._wxNightWrapped and not celestialWorldWanted() then
          -- 2D presentation only. Active voxel presentation owns celestial
          -- bodies exclusively in the beginScene projected-world background stage.
          local showStars = NightSky and NightSky.isNight and NightSky.isNight(nil)
          if NightSky and showStars then
            local edge
            safe(function() edge = Sky.region(h, horizonY) end)
            local t = (Atmos._forest and Atmos._forest.time) or 0
            safe(NightSky.draw, w, h, edge or (h * 0.42), nil, t)
          end
        end
        return result
      end
      Atmos._skyWrapped = true
    end
  end

  -- Capture scene context from VoxelScene.render by wrapping it when available
  local okS, VoxelScene = safe(function() return hostLib.require("VoxelScene") end)
  if okS and VoxelScene then Atmos._VoxelScene=VoxelScene end
  publishWaterHostCaps(hostId,hostLib,okS and VoxelScene or nil)
  safe(wrapHostVoidUnderlay,hostLib)

  -- Current Battle Art resolves its live actor poses into a private `posed`
  -- buffer inside VoxelScene.render(); it intentionally does not publish that
  -- list on state.posed. Use Battle Art's public CharacterRenderers.afterActors
  -- extension seam to observe exactly the NPC records the host just rendered.
  -- The host module owns the registration. A small module slot lets hot reloads
  -- replace the delegate without stacking duplicate renderer entries.
  safe(function()
    local okCR, CharacterRenderers = pcall(hostLib.require,"CharacterRenderers")
    if not okCR or not (CharacterRenderers and type(CharacterRenderers.register)=="function") then return end
    CharacterRenderers._weatherFxNpcLightningObserver = function(context)
      if type(context)=="table" then
        -- Also publish the host-resolved pose list into the atmosphere frame
        -- context before wrapped Voxel3D.endScene() runs drawInScene().
        Atmos._lastPosed = context.posed or Atmos._lastPosed
        Atmos._lastState = context.state or Atmos._lastState
        Atmos._lastPlayer = context.player or Atmos._lastPlayer
      end
      local NL = Atmos._npcLightningForRuntime()
      if NL and NL.observeActors then safe(NL.observeActors,context) end
    end
    if not CharacterRenderers._weatherFxNpcLightningObserverRegistered then
      local handle = CharacterRenderers.register({
        id = "weather_fx_npc_lightning_observer",
        name = "Weather FX NPC Lightning Observer",
        apiVersion = CharacterRenderers.API_VERSION or 1,
        priority = -100000,
        afterActors = function(context)
          local fn = CharacterRenderers._weatherFxNpcLightningObserver
          if type(fn)=="function" then fn(context) end
          -- Observer only: never claim or replace host character rendering.
          return false
        end,
      })
      if handle then CharacterRenderers._weatherFxNpcLightningObserverRegistered = handle end
    end
  end)
  if okS and VoxelScene and VoxelScene.render and not Atmos._wrappedScene then
    local orig = VoxelScene.render
    -- Forward every host render argument. Dramatic Shape 1.9.x and current
    -- PotatoVoxel add an optional `eyes`/multi-view argument after paletteFor;
    -- future hosts may append more. Weather FX only observes scene state and
    -- must never truncate the host's render contract.
    VoxelScene.render = function(state, w, h, vw, vh, paletteFor, ...)
      Atmos._waterFrame=(Atmos._waterFrame or 0)+1
      Atmos._hostWaterCalled=false
      Atmos._wxWaterDrawn=false
      resetVoidPreflight()
      if state then
        Atmos._lastMap = state.map
        Atmos._lastNeighbors = state.neighbors
        Atmos._lastPosed = state.posed
        Atmos._lastPlayer = state.player
        Atmos._lastState = state
        local NL = Atmos._npcLightningForRuntime()
        if NL and NL.observe then safe(NL.observe,state) end
        -- Feed one shared flat-world footprint classifier from the exact voxel
        -- state the host is about to draw. Tornado/wind/shelter systems only
        -- observe this data; no host map or geometry is modified.
        safe(function()
          local FW=V.require("FlatWorldInteraction")
          if not Atmos._FlatTileShape then local okTS,TS=safe(W.require,"TileShape");if okTS then Atmos._FlatTileShape=TS end end
          if FW and FW.observeVoxel then FW.observeVoxel(state,VoxelScene,Atmos._FlatTileShape) end
        end)
        safe(function()
          local CW=V.require("ConnectedWater"); if CW and CW.observeVoxel then CW.observeVoxel(state,Atmos._FlatTileShape) end
        end)
        safe(function()
          local T=V.require("Tornado"); if T and T.observeVoxelState then T.observeVoxelState(state) end
        end)
        safe(function()
          local W=V.require("WeatherWorldSpace"); if W and W.observeVoxelState then W.observeVoxelState(state) end
        end)
        -- Prefer Weather FX Scene outdoor flag; fall back to outdoor=true for
        -- voxel overworld (host only renders outdoor maps in practice).
        local outdoor = true
        safe(function()
          local Scene = V.require("Scene")
          outdoor = resolveWeatherOutdoor(Scene)
          -- Canopy maps still get atmosphere (Kanto behaviour). During battle
          -- resolveWeatherOutdoor already carries the pre-battle canopy result.
          if outdoor == false and Scene and Scene.now and Scene.now.visible~="battle" and Scene.now.mapId then
            local DN = hostLib.require("DayNight")
            if DN and DN.isCanopy and state.map and DN.isCanopy(state.map) then
              outdoor = true
            end
          end
        end)
        Atmos._lastOutdoor = outdoor
        safe(function()
          local SSP=V.require("SnowSurfacePaint")
          if SSP and SSP.observeScene then SSP.observeScene(state,outdoor) end
        end)
      end
      -- Tornado carry changes only the presentation pose during this host render.
      -- Gameplay coordinates remain on a valid cell until the normal visited-map
      -- warp occurs. protected-call is used only during the rare carry window so a host
      -- draw error cannot leave the entity pose patched.
      local T=nil;local pose=nil
      safe(function() T=V.require("Tornado");if T and T.presentationPose then pose=T.presentationPose() end end)
      local player=state and state.player
      local waveLift=0
      if not pose and player and player.surfing then
        safe(function()
          local S=V.require("Settings")
          if S and S.weatherFxWaterEnabled and not S.weatherFxWaterEnabled() then return end
          local CW3=W.require("ConnectedWater3D")
          if CW3 and CW3.playerBob then waveLift=tonumber(CW3.playerBob(state)) or 0 end
        end)
      end
      if (pose or math.abs(waveLift)>0.0001) and player and type(player.pose)=="function" then
        local originalPose,oldPy=player.pose,player.py
        player.pose=function(self,...)
          local sprite,vx,vy,facing,phase,flip=originalPose(self,...)
          if pose then
            -- Tornado carry remains higher-priority and may temporarily move
            -- presentation x/z; gameplay coordinates are restored after draw.
            local rz=tonumber(pose.z) or tonumber(self.py) or tonumber(vy) or 0
            self.py=rz
            return sprite,tonumber(pose.x) or vx,rz-(tonumber(pose.lift) or 0),pose.facing or facing,phase,flip
          end
          -- Surf wave bob is VISUAL Y ONLY. VoxelScene converts e.py-vy into
          -- lift for both the visible body and first-person eye, so subtracting
          -- the sampled wave here rides the actual hydrosphere field without
          -- changing px/py, cellX/cellY, collision, warps or Surf authority.
          local baseVy=tonumber(vy) or tonumber(self.py) or 0
          return sprite,vx,baseVy-waveLift,facing,phase,flip
        end
        local okR,r1,r2,r3,r4,r5=safe(orig,state,w,h,vw,vh,paletteFor,...)
        player.pose,player.py=originalPose,oldPy
        if not okR then error(r1,0) end
        return r1,r2,r3,r4,r5
      end
      return orig(state, w, h, vw, vh, paletteFor, ...)
    end
    Atmos._wrappedScene = true
  end

  -- Replace the host's per-tile water surface geometry only at the final water
  -- pass. The host still owns reflections, depth, shoreline terrain, actors and
  -- Surf gameplay. If the replacement cannot build, the original draw list is
  -- forwarded unchanged.
  if okS and VoxelScene and VoxelScene.drawWater and not Atmos._wrappedWater then
    local origWater=VoxelScene.drawWater
    VoxelScene.drawWater=function(draws,cast,...)
      Atmos._hostWaterCalled=true
      -- Water is world geometry, not a Weather FX 2D/3D presentation choice.
      -- If the voxel host is drawing water, keep connected hydrosphere ownership
      -- even when precipitation itself is presented with the 2D compositor.
      local repl,owned=nil,false
      local useWxWater=waterStyleEnabled()
      if not useWxWater then
        safe(suppressSecondaryHostWater,false)
        safe(suppressHostWaterModelTide,false)
        safe(function()
          local CW3=W.require("ConnectedWater3D")
          if CW3 and CW3.setEnabled then CW3.setEnabled(false) elseif CW3 and CW3.invalidate then CW3.invalidate() end
        end)
        return origWater(draws,cast,...)
      end
      safe(suppressSecondaryHostWater,true)
      if Atmos._wxVoidPreflightFrame==Atmos._waterFrame and Atmos._wxVoidPreflightOwned then
        repl,owned=Atmos._wxVoidPreflightRepl,true
      else
        safe(function()
          local CW3=W.require("ConnectedWater3D")
          if CW3 and CW3.setEnabled then CW3.setEnabled(true) end
          if CW3 and CW3.prepare then repl,owned=CW3.prepare(draws) end
        end)
      end
      if owned then
        -- Voxel Nexus' WaterEngine adds an extra model-space tide inside
        -- Water.draw(). Weather FX already owns tide on `repl`, so suppress the
        -- host addition for the complete owned draw transaction. Restoration is
        -- unconditional even if a host draw raises.
        local hostCaps=Atmos._waterCaps or {}
        if hostCaps.hostWaterModelTide then safe(suppressHostWaterModelTide,true) end
        local waterExtraN=select("#",...);local waterExtra={...};local waterUnpack=table.unpack or unpack
        local okOwned,result=safe(function()
          local CW3=W.require("ConnectedWater3D")
          local outer=(CW3 and CW3.outerDraws and CW3.outerDraws()) or {}
          local reflectMode=waterReflectionMode()
          if #outer>0 then
            -- The synthetic 32K VOID horizon is presentation-only. 8.1.45's
            -- ordinary scene shader was cheap but visibly changed the material.
            -- Use the SAME host water shader family in SKY mode for FULL/SKY
            -- presets, or the same SIMPLE physical path as the near water on the
            -- lowest preset. This keeps one continuous-looking ocean while still
            -- forbidding a second framebuffer/depth copy and far SSR march.
            local fast=false
            if hostCaps.voxelNexusWater and CW3 and CW3.drawOuterFast then
              local farMode=(reflectMode=="simple") and "simple" or "sky"
              local okFast,v=safe(CW3.drawOuterFast,farMode);fast=okFast and v==true
            end
            if not fast then origWater(outer,cast,waterUnpack(waterExtra,1,waterExtraN)) end
          end
          if repl and #repl>0 then
            if reflectMode=="sky" and CW3 and CW3.drawRowsSky then
              local okSky,v=safe(CW3.drawRowsSky,repl,true)
              if okSky and v==true then result=true else result=origWater(repl,cast,waterUnpack(waterExtra,1,waterExtraN)) end
            elseif reflectMode=="simple" and CW3 and CW3.drawRowsSimple then
              local okSimple,v=safe(CW3.drawRowsSimple,repl)
              if okSimple and v==true then result=true else result=origWater(repl,cast,waterUnpack(waterExtra,1,waterExtraN)) end
            else
              result=origWater(repl,cast,waterUnpack(waterExtra,1,waterExtraN))
            end
          end
          -- 8.1.38 authored ponds are intentionally separated from the ordinary
          -- water list so VoxelScene's curved-world OPAQUE prepass cannot hide
          -- their submerged bed/fish before the translucent reflective surface.
          -- Any specialized-pass failure immediately falls back to the host water
          -- function for those same Weather FX pond meshes, preserving visibility.
          if CW3 and CW3.pondDraws then
            local ponds=CW3.pondDraws() or {}
            if #ponds>0 then
              local okP,drawn=safe(CW3.drawPonds,cast,reflectMode)
              if not okP or drawn==false then origWater(ponds,cast,waterUnpack(waterExtra,1,waterExtraN)) end
            end
          end
          if CW3 and CW3.drawAfterWater then safe(CW3.drawAfterWater) end
          return result
        end)
        if hostCaps.hostWaterModelTide then safe(suppressHostWaterModelTide,false) end
        if not okOwned then error(result,0) end
        Atmos._wxWaterDrawn=true
        return result
      end
      return origWater(draws,cast,...)
    end
    Atmos._wrappedWater=true
  end

  if not Atmos._origEndScene then
    Atmos._origEndScene = Voxel3D.endScene
    function Voxel3D.endScene()
      -- Every named Dramatic/Dramaless/Potato/Battle-Art host normally reaches
      -- the wrapped drawWater seam above. If a supported voxel host lacks that
      -- seam, or legitimately skips it because its current map has no host water
      -- draw list, still render Weather FX's presentation-only VOID sea once at
      -- the end of the 3D scene. This is an overlay fallback only: it cannot
      -- create Surf/collision/ice and never redraws authored water.
      if Atmos._drawing and waterStyleEnabled() and not Atmos._wxWaterDrawn then
        safe(function()
          local CW=V.require("ConnectedWater")
          if CW and CW.outerSea then
            local CW3=W.require("ConnectedWater3D")
            if CW3 and CW3.setEnabled then CW3.setEnabled(true) end
            if CW3 and CW3.prepare then CW3.prepare(nil) end
            if CW3 and CW3.drawStandaloneVoid and CW3.drawStandaloneVoid(nil) then Atmos._wxWaterDrawn=true end
          end
        end)
      end
      if Atmos._drawing and (want3d() or clouds3dWanted() or lightning3dWanted()) then
        -- Full 3D weather or mixed 2D precipitation + 3D cloud banks. drawInScene
        -- applies feature-level policy so enabling clouds cannot wake precipitation.
        safe(drawInScene)
      elseif Atmos._drawing and celestialWorldWanted() then
        -- 2D weather + 3D celestial: draw only the world-space celestial vault.
        safe(drawWorldCelestial)
      end
      return Atmos._origEndScene()
    end
  end

  Atmos._active = true
  Atmos._drawing = true
  Atmos._reason = "full-atmos:" .. tostring(hostId)
  return true
end

function Atmos.active()
  return Atmos._active and Atmos._drawing
end

-- Called synchronously by Settings.handleOptionChanged so WATER STYLE can
-- restore native host water immediately from the in-game menu. The draw wrapper
-- independently rechecks the setting every frame, making this a responsiveness
-- path rather than a single point of correctness.
function Atmos.onWaterStyleChanged(style)
  local W=Atmos._ns
  if not W then return false end
  local enabled=tostring(style or "weatherfx")~="original"
  resetVoidPreflight()
  safe(suppressSecondaryHostWater,enabled)
  local ok=false
  safe(function()
    local CW3=W.require("ConnectedWater3D")
    if CW3 and CW3.setEnabled then CW3.setEnabled(enabled);ok=true
    elseif not enabled and CW3 and CW3.invalidate then CW3.invalidate();ok=true end
  end)
  return ok
end

-- Presentation-aware ownership. A voxel host can be installed/active while
-- Weather FX is explicitly presenting its 2D compositor. FPV intentionally
-- remains strict 3D via want3d(), matching the renderer itself.
function Atmos.wants3d()
  return Atmos.active() and want3d()
end

function Atmos.handlesCelestialWorld()
  -- Ownership is selected independently from precipitation presentation. This
  -- prevents Sky.paint from painting a second screen-space copy when players
  -- select 2D weather + 3D celestial.
  return Atmos.active() and celestialWorldWanted() and Atmos._Voxel3D ~= nil
end

function Atmos.voxel3d() return Atmos._Voxel3D end

function Atmos.reason()
  if Atmos._lastDrawError then
    return tostring(Atmos._reason) .. "|err:" .. tostring(Atmos._lastDrawError):sub(1, 40)
  end
  return Atmos._reason
end

function Atmos._worldPrecipForOwnership()
  local ns=Atmos._ns
  if not ns then return nil end
  if Atmos._worldPrecip and Atmos._worldPrecipNs==ns then return Atmos._worldPrecip end
  local ok,WPmod=safe(ns.require,"WorldPrecip")
  if ok and WPmod then
    Atmos._worldPrecip,Atmos._worldPrecipNs=WPmod,ns
    return WPmod
  end
  return nil
end

function Atmos._npcLightningForRuntime()
  local ns=Atmos._ns
  if not ns then return nil end
  if Atmos._npcLightning and Atmos._npcLightningNs==ns then return Atmos._npcLightning end
  local ok,NL=safe(ns.require,"NpcLightning")
  if ok and NL then
    Atmos._npcLightning,Atmos._npcLightningNs=NL,ns
    return NL
  end
  return nil
end

function Atmos._tornado3dForRuntime()
  local ns=Atmos._ns
  if not ns then return nil end
  if Atmos._tornado3d and Atmos._tornado3dNs==ns then return Atmos._tornado3d end
  local ok,T3=safe(ns.require,"Tornado3D")
  if ok and T3 then Atmos._tornado3d,Atmos._tornado3dNs=T3,ns;return T3 end
  return nil
end

function Atmos.handlesPrecipitation()
  if not want3d() or not Atmos.active() then return false end
  local WPmod=Atmos._worldPrecipForOwnership()
  if not (WPmod and WPmod.drawingRain) then return false end
  local ok,drawing=safe(WPmod.drawingRain)
  return (ok and drawing) and true or false
end

-- 2D snow is suppressed ONLY when the 3D world-space snow is provably on
-- screen this frame.
--
-- History: this returned a hardcoded false because an earlier version returned
-- true whenever 3D *should* be running, which zeroed the 2D channel and then
-- left nothing at all on screen when 3D silently failed. The 3D path had in
-- fact been failing continuously -- WorldPrecip was a LuaJIT compile error and
-- never loaded at all -- so the hardcoded false was the only thing keeping any
-- snow visible, and what it kept was the flat 2D overlay.
--
-- The fix is not to flip the constant back. It is to ask the thing that knows:
-- WorldPrecip reports whether it emitted flake geometry on the last frame. If
-- it did, the 2D sheet is redundant and drawing both is what makes world snow
-- look like an overlay. If it did not -- module missing, host absent, zero
-- intensity, everything culled -- we fall back to 2D exactly as before. Fail
-- closed: any doubt returns false and the player still sees snow.
function Atmos.handlesSnow()
  if not want3d() or not Atmos.active() then return false end
  local WPmod=Atmos._worldPrecipForOwnership()
  if not (WPmod and WPmod.drawingSnow) then return false end
  local ok,drawing=safe(WPmod.drawingSnow)
  return (ok and drawing) and true or false
end

function Atmos.handlesGrains(kind)
  if not want3d() or not Atmos.active() then return false end
  local WPmod=Atmos._worldPrecipForOwnership()
  if not (WPmod and WPmod.drawingGrain) then return false end
  local ok,drawing=safe(WPmod.drawingGrain,kind)
  return (ok and drawing) and true or false
end


-- Does the 3D layer own lightning?
--
-- NOTE THE DIFFERENCE FROM handlesSnow/handlesPrecipitation. Those ask whether
-- geometry was actually emitted last frame, because rain and snow draw
-- CONTINUOUSLY -- if they drew, they are on screen.
--
-- Lightning does not. A bolt lasts a fraction of a second and then there is
-- nothing for many seconds. A "did it draw this frame" gate would therefore
-- report false almost all the time, and the 2D bolt overlay would come back
-- between strikes -- which is exactly the overlay this is meant to replace.
--
-- So the question is whether 3D lightning is INSTALLED AND RUNNING, not whether
-- it happened to be mid-strike on this particular frame.
-- Does the 3D atmosphere own ALL precipitation?
--
-- Every previous attempt gated the 2D layer channel by channel: rain, then
-- snow, then hail/sand/debris/ash, then splash. Each round fixed the channels
-- named in the report and missed the next one, because a weather carries
-- whatever channels it likes -- SLEET has hail, PSYSTORM debris, DRAGONSTORM
-- sand AND debris, VERDANT_RAIN splash. Enumerating them cannot converge.
--
-- The rule is now the one that was actually asked for: on the 3D setting there
-- is no 2D weather at all. If the 3D atmosphere is running, it owns
-- precipitation outright and the flat particle layer does not draw.
--
-- This is safe only because every family now has a 3D path -- rain, snow, and
-- all four grain kinds including hail, which was wired for this. If a family
-- is ever added without one, it must be given a 3D path, NOT an exception here.
--
-- Deliberately not a per-frame "did it draw" test: precipitation ramps in and
-- out, and a frame where the 3D layer emitted nothing would flash the 2D sheet.
function Atmos.handlesAllPrecipitation()
  if not (want3d() and Atmos.active()) then return false end
  local WPmod=Atmos._worldPrecipForOwnership()
  if not WPmod then return false end
  if WPmod.immersiveCamera then
    local okImm,imm=safe(WPmod.immersiveCamera)
    if not (okImm and imm) then return false end
  end
  if not WPmod.drawingAllRequested then return false end
  local ok,owns=safe(WPmod.drawingAllRequested)
  return (ok and owns) and true or false
end

function Atmos.handlesLightning()
  if not lightning3dWanted() or not Atmos.active() then return false end
  local cin = Atmos._cin
  if not (cin and cin.passHealthy) then return false end
  local ok, healthy = safe(cin.passHealthy, "world-lightning")
  return (ok and healthy) and true or false
end

function Atmos.handlesFog()
  if not want3d() or not Atmos.active() then return false end
  local cin = Atmos._cin
  if not (cin and cin.fogDrawing) then return false end
  local ok, drawing = safe(cin.fogDrawing)
  return (ok and drawing) and true or false
end

function Atmos.syncFromWeatherFx(state)
  -- Capture the authoritative id even before the 3D host finishes installing.
  -- main.lua calls sync before update/install, so returning early here used to
  -- drop the first selected non-rain state during late host startup.
  local weatherId = state and state.id
  if type(weatherId) == "table" then
    weatherId = weatherId.id or weatherId.name
  end
  weatherId = tostring(weatherId or ""):upper()
  -- Weather FX pipeline OFF (level 0): force 3D path to CLEAR immediately.
  -- Without this, 3D kept the last profile (snow/rain/etc.) because intensity
  -- comes from CinematicAtmos weather bags, not State.ch — so turning weather
  -- off left 3D precip running while 2D correctly stopped.
  local level = tonumber(state and state.level) or 0
  if level <= 0 then
    weatherId = "CLEAR"
  end
  if weatherId == "" or weatherId == "NIL" or weatherId == "NONE"
      or weatherId == "OFF" or weatherId == "NONE_WEATHER" then
    weatherId = "CLEAR"
  end
  Atmos._wxId = weatherId
  -- Publish the authoritative Weather FX id into the shared voxel namespace.
  -- CinematicAtmos and WorldPrecip can read this directly every frame, so a
  -- failed/stale ModSetting or notify callback cannot leave rain working while
  -- snow/hail/sand/ash/debris silently receive no spawn demand.
  if Atmos._ns then
    Atmos._ns.weatherFxId = weatherId
    -- Strict 3D must consume the SAME live eased channels as 2D/audio.  Publish
    -- the stable WeatherState channel table by reference (read-only) rather than
    -- rebuilding values from the discrete catalogue id. This removes the old
    -- "blend internally, then suddenly rain at commit" split and allocates
    -- nothing per frame.
    Atmos._ns.weatherFxChannels = state and state.ch or nil
    Atmos._ns.weatherFxSpatialStrength = state and state._spatialStrength or 1
    Atmos._ns.weatherFxSpatialCloud = state and state._spatialCloud or 1
    -- Distinguish a finite front from manual/config weather. Manual weather is
    -- still allowed to establish its authored deck immediately; only a real
    -- front uses the physical cloud footprint to grow/part the local sky.
    Atmos._ns.weatherFxSpatialLocalized = state and state.pinnedBy == "front" or false
    Atmos._ns.weatherFxSourceId = weatherId
    Atmos._ns.weatherFxTargetId = state and state.softTo or nil
    if state and state.synoptic then
      -- Internal read-only hot path. Avoid a protected call every frame; the
      -- bridge already guards the optional method and the planner itself owns
      -- persistent state.
      Atmos._ns.weatherFxTransition = state.synoptic()
    else
      Atmos._ns.weatherFxTransition = nil
    end
    -- Publish the continuous meteorological state by reference as well. The old
    -- sample() call copied a table every frame; peek() is safe because this is an
    -- internal read-only bridge and materially reduces GC traffic on weak hosts.
    safe(function()
      local WS=V.require("WeatherSimulation")
      if WS and WS.peek then Atmos._ns.weatherFxMeteo=WS.peek()
      elseif WS and WS.sample then Atmos._ns.weatherFxMeteo=WS.sample() end
    end)
  end
  if not Atmos.active() or not Atmos._cin then return end
  local cin = Atmos._cin
  local kanto = WX_TO_KANTO[weatherId] or "clear"
  if weatherId == "CLEAR" or weatherId == "SUNNY" then kanto = "clear" end
  if cin.weatherSetting and cin.weatherSetting.setValue then
    safe(function() cin.weatherSetting:setValue(kanto) end)
  end
  -- Ground snow packs clear when WX leaves snowy weather (all hosts).
  if cin.notifyWxWeather then
    safe(cin.notifyWxWeather, weatherId)
  end
end

-- Runtime proof surface for DEBUG/tests. This reports the actual simulator
-- object used by the installed 3D host, not a synthetic copy.
function Atmos.precipProof()
  if not Atmos._worldPrecip then
    return { loaded=false, reason=tostring(Atmos._reason or "WorldPrecip-unavailable") }
  end
  local out = { loaded=true, host=Atmos._hostId, wxId=Atmos._wxId }
  if Atmos._worldPrecip.spawnStatus then
    local ok, st = safe(Atmos._worldPrecip.spawnStatus)
    if ok then out.spawn = st end
  end
  if Atmos._worldPrecip.drawStatus then
    local ok, st = safe(Atmos._worldPrecip.drawStatus)
    if ok then out.draw = st end
  end
  return out
end

local function syncWorldBackedBattleWeather(step)
  local Scene=Atmos._scene
  if not (Scene and Scene.now and Scene.now.visible=="battle" and Scene.now.battleOpaque==false) then return false end
  local okS,S=safe(V.require,"Settings")
  if okS and S then
    if S.force2dPresent and S.force2dPresent() then return false end
    if S.allow3dPresent and not S.allow3dPresent() then return false end
  end
  local okB,B=safe(V.require,"Battle"); local battle=okB and B and B.current and B.current() or nil
  local okD,BD=safe(V.require,"BattleDraw")
  if not (battle and okD and BD) then return false end
  if BD.tick then safe(BD.tick,step,battle) end
  local id=BD.weatherId and BD.weatherId(battle) or "CLEAR"
  id=tostring(id or "CLEAR"):upper()
  local hardOff=S and S.weatherDisabled and S.weatherDisabled()
  if hardOff then id="CLEAR" end
  Atmos._wxId=id
  if Atmos._ns then
    Atmos._ns.weatherFxId=id
    Atmos._ns.weatherFxSourceId=id
    Atmos._ns.weatherFxTargetId=nil
    Atmos._ns.weatherFxChannels=(not hardOff and BD.channels and BD.channels()) or nil
    Atmos._ns.weatherFxSpatialStrength=1
    Atmos._ns.weatherFxSpatialCloud=1
    Atmos._ns.weatherFxSpatialLocalized=false
    Atmos._ns.weatherFxTransition=nil
  end
  Atmos._battle3dWeatherOwned=true
  return true
end
Atmos._syncWorldBackedBattleWeather=syncWorldBackedBattleWeather

function Atmos.update(dt)
  if not Atmos._ready then Atmos.install() end
  if not Atmos.active() then
    if not Atmos._ready then return end
    -- retry install occasionally if host appeared late
    if not Atmos._active then safe(Atmos.install) end
    return
  end
  -- Keep outdoor flag in sync without resolving Scene through the loader each frame.
  if not Atmos._scene then
    local ok,Scene=safe(V.require,"Scene"); if ok then Atmos._scene=Scene end
  end
  local Scene=Atmos._scene
  if Scene and Scene.now then
    Atmos._lastOutdoor=resolveWeatherOutdoor(Scene)
  end
  local step = tonumber(dt) or 0
  if step < 0 then step = 0 end
  if step > 0.25 then step = 0.25 end  -- avoid hitch-induced lattice jumps
  Atmos._battle3dWeatherOwned=false
  syncWorldBackedBattleWeather(step)
  local weather3d=want3d()
  local clouds3d=clouds3dWanted()
  if not weather3d and Atmos._weather3dWasActive and Atmos._cin and Atmos._cin.suspendWeather3d then
    safe(Atmos._cin.suspendWeather3d)
  end
  Atmos._weather3dWasActive=weather3d
  if weather3d or clouds3d then
    if Atmos._forest and Atmos._forest.update then safe(Atmos._forest.update, step) end
    if Atmos._cin and Atmos._cin.update then safe(Atmos._cin.update, step) end
  end
  local NL=weather3d and Atmos._npcLightningForRuntime() or nil
  local hardWeatherOff=false
  safe(function()
    local S=V.require("Settings"); local WS=V.require("WeatherState")
    hardWeatherOff=(S and S.weatherDisabled and S.weatherDisabled())
      or (WS and (tonumber(WS.level) or 0)<=0)
  end)
  if hardWeatherOff then
    if NL and NL.clearEffects then safe(NL.clearEffects) end
  elseif NL and NL.update then safe(NL.update,step) end
end

function Atmos.invalidate()
  Atmos._hostWaterCalled=false;Atmos._wxWaterDrawn=false
  resetVoidPreflight()
  safe(suppressSecondaryHostWater,false)
  safe(suppressHostWaterModelTide,false)
  if Atmos._cin and Atmos._cin.invalidate then
    safe(Atmos._cin.invalidate)
  end
  local NL=Atmos._npcLightningForRuntime()
  if NL and NL.invalidate then safe(NL.invalidate) end
  local T3=Atmos._tornado3dForRuntime()
  if T3 and T3.invalidate then safe(T3.invalidate) end
  -- Undo hydrosphere renderer mutations before the host water renderer can be
  -- used again, then invalidate the root observation/topology state.
  local W=Atmos._ns
  if W then
    safe(function() local CW3=W.require("ConnectedWater3D");if CW3 and CW3.invalidate then CW3.invalidate() end end)
  end
  safe(function() local CW=V.require("ConnectedWater");if CW and CW.invalidate then CW.invalidate() end end)
  safe(function() local FW=V.require("FlatWorldInteraction");if FW and FW.invalidate then FW.invalidate() end end)
  safe(function() local SSP=V.require("SnowSurfacePaint");if SSP and SSP.invalidate then SSP.invalidate() end end)
end

return Atmos
