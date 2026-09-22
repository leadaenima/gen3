-- Android-safe cinematic atmosphere for Dramatic Shape.
--
-- This pass deliberately avoids sampling the scene depth texture. Instead it
-- draws real translucent geometry while VoxelScene's hardware depth buffer is
-- still bound. Ground mist, clouds and light volumes are therefore occluded by
-- the same depth test as the voxel world on every platform, including Android.
--
-- The light volumes additionally sample Dramatic Shape's ordinary COLOR shadow
-- map (lib/ShadowMap.lua). That texture is portable on Android and tells each
-- fragment whether the sun can actually reach that point in space, so trees,
-- buildings and characters carve darkness through the shafts instead of the
-- shafts being painted screen overlays.

local V = ...
V.safeCall = V.safeCall or pcall

-- Stable optional/root modules are resolved once after they become available.
-- Failed startup lookups are not cached, preserving load-order recovery.
local moduleCache = {}
local function cachedRequire(name)
  local m = moduleCache[name]
  if m then return m end
  local ok, value = V.safeCall(V.require, name)
  if ok and value then moduleCache[name] = value; return value end
  return nil
end

local DayNight = V.require("DayNight")
-- FORWARD DECLARATIONS.
--
-- These four are defined further down but CALLED above their definitions. That
-- worked only because they used to be globals: a global is resolved at call
-- time, so declaration order did not matter. Making them local (to stop them
-- leaking into _G, where another mod could clobber them) reintroduces Lua's
-- scoping rule -- a local is invisible above its own declaration.
--
-- Declaring the names here and assigning below keeps both properties: the
-- names stay out of _G, and the earlier call sites still resolve.
local lerp, mixColor
local cloudTransmissionAt, cloudTransmissionAlongRay
local weatherSettings

local function wxCelestial()
  return cachedRequire("CelestialBodies")
end
local ForestAtmos = V.require("ForestAtmos")
local ShadowMap = V.require("ShadowMap")
local ModSetting = V.require("WeatherSetting")
local TileShape = V.require("TileShape")
local Sky = V.require("Sky")
local Mat4 = V.require("Mat4")
local SpriteBillboards = V.require("SpriteBillboards")
local TerrainAtlas = V.require("TerrainAtlas")
local WorldPrecip = nil
local WorldPrecipLoadError = nil
do
  local ok, value = V.safeCall(V.require, "WorldPrecip")
  if ok and value then
    WorldPrecip = value
  else
    WorldPrecipLoadError = tostring(value)
  end
end

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local sin, cos, abs = math.sin, math.cos, math.abs
local PI2 = math.pi * 2

local CinematicAtmos = {}

-- Pure policy seam used by the live frame and executable leakage regression.
-- Only an authored WeatherState fog channel may create explicit 3D ground mist.
function CinematicAtmos._mistPolicy(authoredFog, fogScale)
  local f=max(0,tonumber(authoredFog) or 0)
  if f<=0.02 then return 0,false end
  local ms=max(.28,min(1.32,tonumber(fogScale) or 1))
  return f*ms,true
end

-- 8.1.59: local/distant snow visual ownership. A finite StormCell keeps its
-- world-space snow slab visible while it is genuinely distant, but once the
-- player-local WorldPrecip field has become visible that same slab must retire.
-- Otherwise the perspective-compressed remote slab sits inside the broad local
-- snowfall as a dense vertical "one-pixel emitter" / fountain. The handoff is
-- intentionally snow-only: rain-front continuity and fog/lightning ownership
-- are unchanged. The local field already preserves the complete authored flake
-- population, so this removes duplicate presentation rather than reducing snow.
function CinematicAtmos._distantSnowHandoff(frame, kind)
  if kind~="snow" and kind~="blizzard" then return 1 end
  local w=frame and frame.weather or nil
  -- 8.1.91: the frame profile can lag the authoritative root channel by one
  -- presentation beat during map/front handoff. More importantly, an intensity
  -- fade is NOT a valid ownership handoff: at light/moderate snow it left most
  -- of the finite StormCell slab alive beside WorldPrecip. Perspective then
  -- compresses that remote slab into the reported one-pixel snow fountain.
  -- Once the player-local field is genuinely active it owns ALL nearby snow
  -- presentation, so the distant snow/blizzard slab retires atomically. A tiny
  -- threshold ignores interpolation noise while preserving a genuinely distant
  -- snow front whenever local snow is absent. Rain/fog/lightning are untouched.
  local frameSnow=max(0,tonumber(w and w.snowIntensity) or 0)
  local liveSnow=max(0,tonumber(V and V.weatherFxChannels and V.weatherFxChannels.snow) or 0)
  local localSnow=max(frameSnow,liveSnow)
  if localSnow>.02 then return 0 end
  -- 8.1.98: channel publication can briefly hit zero during a streaming/front
  -- presentation seam even though the authoritative current weather is still
  -- snow-family. Letting the finite distant slab back in for that beat recreates
  -- the dense perspective-compressed single-pixel fountain. Use the CURRENT
  -- root/source id as an ownership backstop (never the transition target): an
  -- approaching distant snow front from CLEAR therefore remains visible until
  -- local snow actually takes ownership, while an already-local BLIZZARD cannot
  -- resurrect its stale remote slab just because one channel sample dipped.
  local ownerWx=tostring((V and V.weatherFxId) or (w and w._sourceWxId) or ''):upper()
  local ownerSnow=(ownerWx:find('SNOW',1,true)~=nil)
    or ownerWx=='BLIZZARD' or ownerWx=='SLEET' or ownerWx=='DRAGONSTORM' or ownerWx=='WHITEOUT'
  return ownerSnow and 0 or 1
end

-- Reused synchronous frame scratch removes per-frame weather/fog/wind table
-- churn. No caller retains a CinematicAtmos frame past the current draw.
local weatherScratch = {}
CinematicAtmos._transitionProfileScratch = CinematicAtmos._transitionProfileScratch or {}
local frameScratch = { fog = {}, wind = {0.021, -0.014}, mistWind = {0,0}, mistAdvect = {0,0} }
local hourFogScratch, hourRayScratch = {0,0,0}, {0,0,0}
CinematicAtmos._uniformScratch = CinematicAtmos._uniformScratch or {
  curve={0,0,0}, wind2={0,0}, color3={0,0,0}, color3b={0,0,0},
  particleCool={0,0,0},particleWarm={0,0,0},cloudCool={0,0,0},cloudWarm={0,0,0},
  cloudBase={0,0,0},cloudColor={0,0,0},rainColor={0,0,0},
  shear2={0,0}, sun2={0,0}, body3={0,0,0}, identity4={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}
}
CinematicAtmos._worldUp=CinematicAtmos._worldUp or {0,1,0}
CinematicAtmos._defaultMistWind=CinematicAtmos._defaultMistWind or {8.8,-5.4}
CinematicAtmos._zero2=CinematicAtmos._zero2 or {0,0}
local NIGHT_FOG, NIGHT_RAY = {0.02,0.025,0.05}, {0,0,0}
CinematicAtmos._emptyClouds = CinematicAtmos._emptyClouds or {}
CinematicAtmos._cloudCandidates = CinematicAtmos._cloudCandidates or {}
CinematicAtmos._cloudCandidatePool = CinematicAtmos._cloudCandidatePool or {}
-- 8.1.37: distant fronts no longer own a separate dark primitive renderer.
-- They contribute descriptors to this same live cloud-bank list/pool, so their
-- cloud mass uses the exact same puffs, lighting, depth and deck altitude as
-- every other Weather FX cloud. The pool is bounded by DistantWeather.MAX (4).
CinematicAtmos._frontCloudCandidates = CinematicAtmos._frontCloudCandidates or {}
CinematicAtmos._frontCloudPool = CinematicAtmos._frontCloudPool or {}
CinematicAtmos._mesoCloudScratch = CinematicAtmos._mesoCloudScratch or {}
CinematicAtmos._particleVerts = CinematicAtmos._particleVerts or {}
CinematicAtmos._particleVertRows = CinematicAtmos._particleVertRows or {}
CinematicAtmos._particleIndices = CinematicAtmos._particleIndices or {}
CinematicAtmos._particleCorners = CinematicAtmos._particleCorners or { {-1,-1},{1,-1},{1,1},{-1,1} }
function CinematicAtmos._cloudSort(a,b) return (a.forwardDepth or 0) > (b.forwardDepth or 0) end

-- 8.1.27 live-host repair: several fallback atmospheric stream meshes have
-- weather-dependent populations. Creating a Mesh from the first frame's table
-- fixes its capacity to that exact row count; a later denser frame then raises
-- "Too many vertices" before the old recursive recreate path can recover.
-- Keep grow-only capacities per pass and upload the exact current rows.
CinematicAtmos._streamMeshCaps = CinematicAtmos._streamMeshCaps or {}
function CinematicAtmos._uploadStreamMesh(key, mesh, format, verts)
  local need = verts and #verts or 0
  if need < 1 then return mesh, false end
  local caps = CinematicAtmos._streamMeshCaps
  local have = tonumber(caps[key]) or 0
  if (not mesh) or have < need then
    local cap = 256
    while cap < need do cap = cap * 2 end
    local okNew, fresh = V.safeCall(love.graphics.newMesh, format, cap, "triangles", "stream")
    if not (okNew and fresh) then return mesh, false end
    local old = mesh
    mesh, caps[key] = fresh, cap
    if old and old.release then V.safeCall(old.release, old) end
  end
  local okUpload = V.safeCall(mesh.setVertices, mesh, verts, 1, need)
  return mesh, okUpload == true
end

-- 8.1.80: every stream pass below builds a conventional sequential quad map
-- (1,2,3,1,3,4 ...). The index contents therefore depend only on quad count.
-- Re-sending the same map every frame is pure driver traffic; retain the exact
-- map on the Mesh until either the Mesh object or index count changes.
CinematicAtmos._streamVertexMaps = CinematicAtmos._streamVertexMaps or {}
function CinematicAtmos._applySequentialQuadMap(key, mesh, indices)
  if not (mesh and mesh.setVertexMap and indices) then return false end
  local n=#indices
  local rec=CinematicAtmos._streamVertexMaps[key]
  if rec and rec.mesh==mesh and rec.count==n then return true end
  local ok=V.safeCall(mesh.setVertexMap,mesh,indices)
  if ok then
    if not rec then rec={}; CinematicAtmos._streamVertexMaps[key]=rec end
    rec.mesh,rec.count=mesh,n
  end
  return ok==true
end

-- Companion-mod atmosphere quality.  This intentionally belongs to Kanto
-- Dynamic Weather rather than reusing Dramatic Shape's FOREST FX setting:
-- the two mods can then be updated/configured independently.
CinematicAtmos.atmosphereSetting = ModSetting.new(
  "atmosphere", "ATMOSPHERE", { "full", "low", "off" },
  { "FULL", "LOW", "OFF" }, 1)

-- Volumetric sunlight strength. 5 is deliberately the A5 calibration the
-- user approved; the extra range is presentation, not a different lighting
-- model. Stored as strings because mod option values are serialized as simple
-- scalars across desktop and Android.
local LIGHT_VALUES, LIGHT_LABELS = {}, {}
for i = 1, 10 do
  LIGHT_VALUES[i], LIGHT_LABELS[i] = tostring(i), tostring(i)
end
CinematicAtmos.lightSetting = ModSetting.new(
  "light_intensity", "LIGHT INTENSITY", LIGHT_VALUES, LIGHT_LABELS, 5)

-- Particle tuning is intentionally exposed as two independent ladders so the
-- handset can be calibrated by eye.  A9 is the reference point the player
-- described as DENSITY 1 / SCALE 8. The preferred tuning is now
-- DENSITY 6 / SCALE 8, so new installs start there while both remain editable.
local PARTICLE_VALUES, PARTICLE_LABELS = {}, {}
for i = 1, 10 do
  PARTICLE_VALUES[i], PARTICLE_LABELS[i] = tostring(i), tostring(i)
end
CinematicAtmos.particleDensitySetting = ModSetting.new(
  "particle_density", "PARTICLE DENSITY", PARTICLE_VALUES, PARTICLE_LABELS, 6)
CinematicAtmos.particleScaleSetting = ModSetting.new(
  "particle_scale", "PARTICLE SCALE", PARTICLE_VALUES, PARTICLE_LABELS, 8)

-- Rain calibration is authored per weather preset rather than exposed as
-- separate menu rows. W5 keeps the handset-approved values: steady RAINING
-- uses SIZE 3 / DENSITY 4, while THUNDERSTORM uses SIZE 3 / DENSITY 6.

-- Weather is authored as a continuum internally, with these menu entries acting
-- as calibrated points on it.  PARTLY CLOUDY is the exact M6 cloud field the
-- user approved and is intentionally the default for existing installs.
local WEATHER_VALUES = { "dynamic", "clear", "partly", "mostly", "cloudy", "overcast", "rain", "thunderstorm", "snow", "blizzard", "gale" }
local WEATHER_LABELS = { "DYNAMIC", "CLEAR", "PARTLY CLOUDY", "MOSTLY CLOUDY", "CLOUDY", "OVERCAST", "RAINING", "THUNDERSTORM", "SNOW", "BLIZZARD", "GALE" }
CinematicAtmos.weatherSetting = ModSetting.new(
  "weather", "WEATHER", WEATHER_VALUES, WEATHER_LABELS, 1)

local WEATHER_SPEED_VALUES = { "slow", "normal", "fast", "very_fast" }
local WEATHER_SPEED_LABELS = { "SLOW", "NORMAL", "FAST", "VERY FAST" }
CinematicAtmos.weatherSpeedSetting = ModSetting.new(
  "weather_speed", "WEATHER SPEED", WEATHER_SPEED_VALUES, WEATHER_SPEED_LABELS, 2)

-- The cloud percentages are perceptual targets, not literal occupied lattice
-- cells.  M6 is our measured ~25% reference.  Denser presets tighten the world
-- lattice and use more broad-bank formations, so coverage grows by adding real
-- 3D cloud volume instead of scaling one cloud into a backdrop. RAIN and
-- THUNDERSTORM use the same sealed cloud ceiling plus the world-space rain
-- pass below; W5 adds atmospheric lightning illumination to the storm state.
local WEATHER = {
  clear =        { coverage=0.00, cell=185, gate=1.01, span=0.92, puffs=0.00, bank=0.00, rays=1.10, shadow=0.00, cloudShade=1.02, fog=0.00 },
  partly =       { coverage=0.25, cell=185, gate=0.18, span=1.00, puffs=1.00, bank=0.34, rays=1.00, shadow=1.00, cloudShade=1.00, fog=2.55 },
  mostly =       { coverage=0.75, cell=120, gate=0.08, span=1.08, puffs=0.74, bank=0.46, rays=0.88, shadow=1.18, cloudShade=0.94, fog=2.70 },

  -- W3: the bridge state between Mostly Cloudy and a sealed Overcast deck.
  -- CLOUDY is intentionally still broken cloud volume: broad banks dominate
  -- and blue openings are uncommon, but the deck has not yet fused shut.
  cloudy =       { coverage=0.92, cell=110, gate=0.015, span=1.16, puffs=0.84, bank=0.72, rays=0.55, shadow=1.34, cloudShade=0.86, fog=2.85,
                   skyBlend=0.24, skyColor={0.66,0.71,0.77} },

  -- W2: 100% states are a true CLOSED CEILING, not merely a denser version
  -- of Mostly Cloudy. Every lattice cell is occupied, broad bank bodies overlap
  -- their neighbours, and altitude is compressed into one coherent deck. The
  -- grey underlying sky is only a safety net for microscopic feather gaps; the
  -- visible ceiling is still made from the same world-space 3D cloud geometry.
  overcast =     { coverage=1.00, cell=108, gate=-0.01, span=1.24, puffs=0.94, bank=1.00, rays=0.08, shadow=1.46, cloudShade=0.76, fog=3.00,
                   closedDeck=true, deckWidth=1.82, deckDepth=1.12, deckY0=116, deckYSpan=26,
                   skyBlend=0.92, skyColor={0.52,0.54,0.55} },
  rain =         { coverage=1.00, cell=105, gate=-0.01, span=1.28, puffs=0.98, bank=1.00, rays=0.05, shadow=1.58, cloudShade=0.66, fog=3.22, motes=0.00, storm=0.00,
                   rainIntensity=1.00, rainSpeed=1.00, rainWind=1.00, rainDensityRung=4, rainSizeRung=3,
                   closedDeck=true, deckWidth=1.86, deckDepth=1.16, deckY0=110, deckYSpan=24,
                   skyBlend=0.96, skyColor={0.42,0.44,0.46} },
  thunderstorm = { coverage=1.00, cell=102, gate=-0.01, span=1.34, puffs=1.02, bank=1.00, rays=0.015, shadow=1.72, cloudShade=0.52, fog=3.45, motes=0.00, storm=1.00,
                   rainIntensity=1.38, rainSpeed=1.22, rainWind=1.48, rainDensityRung=6, rainSizeRung=3,
                   closedDeck=true, deckWidth=1.92, deckDepth=1.20, deckY0=104, deckYSpan=23,
                   skyBlend=0.98, skyColor={0.30,0.32,0.34} },
  -- Soft 3D snowfall (flakes, not streaks)
  snow =         { coverage=0.96, cell=108, gate=-0.01, span=1.20, puffs=0.90, bank=0.88, rays=0.12, shadow=1.30, cloudShade=0.82, fog=2.90, motes=0.00, storm=0.00,
                   snowIntensity=3.6, snowSpeed=0.55, snowWind=0.65, snowDensityRung=5, snowSizeRung=4,
                   closedDeck=true, deckWidth=1.78, deckDepth=1.10, deckY0=118, deckYSpan=28,
                   skyBlend=0.90, skyColor={0.58,0.62,0.68} },
  blizzard =     { coverage=1.00, cell=104, gate=-0.01, span=1.30, puffs=1.00, bank=1.00, rays=0.04, shadow=1.50, cloudShade=0.70, fog=3.40, motes=0.00, storm=0.00,
                   snowIntensity=5.5, snowSpeed=0.95, snowWind=1.45, snowDensityRung=7, snowSizeRung=5,
                   closedDeck=true, deckWidth=1.88, deckDepth=1.16, deckY0=108, deckYSpan=26,
                   skyBlend=0.96, skyColor={0.48,0.52,0.58} },
  -- Hard wind: scudding clouds, dense air motes, no rain (2D leaves/debris remain)
  -- GALE RAINS. Its weather definition carries `rain = 0.7` (plus rainSpeed
  -- 1.3, rainAngle 0.52, rainLen 1.4 -- driven, slanted rain), but this profile
  -- said rainIntensity = 0, so the 2D layer rained and the 3D layer produced
  -- nothing at all. A gale is a storm with wind, not a dry dust event.
  --
  -- 1.00 matches the `rain` profile, which is what was asked for: the same rain
  -- as rain weather. The high rainWind (1.80) is kept -- that is what makes it
  -- a gale rather than ordinary rain, and it is the one thing here that should
  -- differ. Density and size rungs are raised to the rain profile's 4/3 as
  -- well; at 1/1 the 3D rain would have been present but threadbare.
  gale =         { coverage=0.94, cell=98, gate=0.02, span=1.32, puffs=1.00, bank=0.92, rays=0.28, shadow=1.35, cloudShade=0.74, fog=2.35, motes=2.20, storm=0.00,
                   rainIntensity=1.00, rainSpeed=1.30, rainWind=1.80, rainDensityRung=4, rainSizeRung=3,
                   snowIntensity=0, snowSpeed=1, snowWind=1.5, snowDensityRung=1, snowSizeRung=1,
                   deckWidth=1.70, deckDepth=1.05, deckY0=118, deckYSpan=30, skyBlend=0.55, deckBlend=0.35, softGate=0.12 },
}

local lerp, mixColor

-- Dynamic weather uses one persistent master lattice so cloud cells do not
-- teleport when coverage changes. The manual presets above remain byte-for-byte
-- calibrated; only DYNAMIC normalises their lattice spacing and uses a soft
-- occupancy threshold so new cloud bodies fade into existence as the target
-- coverage rises.
local DYNAMIC_ORDER = { "clear", "partly", "mostly", "cloudy", "overcast", "rain", "thunderstorm" }
local DYNAMIC_INDEX = {}
for i, k in ipairs(DYNAMIC_ORDER) do DYNAMIC_INDEX[k] = i end

local function copyProfile(src)
  local out = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      local c = {}
      for i = 1, #v do c[i] = v[i] end
      out[k] = c
    else
      out[k] = v
    end
  end
  out.deckBlend = src.closedDeck and 1.0 or 0.0
  return out
end

local DYNAMIC_WEATHER = {}
for _, k in ipairs(DYNAMIC_ORDER) do
  DYNAMIC_WEATHER[k] = copyProfile(WEATHER[k])
  DYNAMIC_WEATHER[k].cell = 120
  DYNAMIC_WEATHER[k].softGate = 0.10
end
-- Preserve the handset-calibrated apparent coverage while keeping the same
-- 120-unit lattice under every dynamic state.
DYNAMIC_WEATHER.clear.gate = 1.01
DYNAMIC_WEATHER.partly.gate = 0.655
DYNAMIC_WEATHER.mostly.gate = 0.08
DYNAMIC_WEATHER.cloudy.gate = 0.01
DYNAMIC_WEATHER.overcast.gate = -0.01
DYNAMIC_WEATHER.rain.gate = -0.01
DYNAMIC_WEATHER.thunderstorm.gate = -0.01

local HOLD_RANGES = {
  clear={900,1800}, partly={720,1200}, mostly={600,1080},
  cloudy={480,900}, overcast={480,900}, rain={480,1080},
  thunderstorm={240,600}, gale={360,720},
}
local TRANSITION_RANGES = {
  -- Longer morphs so clouds/rain/snow never hard-cut between states.
  clear={180,360}, partly={180,360}, mostly={170,340},
  cloudy={160,320}, overcast={150,300}, rain={140,280},
  thunderstorm={120,240},
  snow={160,320}, blizzard={140,280}, gale={140,280},
}
local SPEED_MULT = { slow=1.70, normal=1.00, fast=0.50, very_fast=1.00 }
local VERY_FAST_HOLD = 120.0       -- two minutes per recognisable weather state
local VERY_FAST_TRANSITION = 24.0 -- short transition so the test cycle stays useful

local dynamic = {
  active=false, currentKey="clear", targetKey=nil, phase="hold",
  elapsed=0, duration=900, serial=0, speedKey="normal",
}

-- Persistent ground wetness. Rain fills puddles immediately; once the rain
-- stops the puddles remain, then shrink one authored rung after every later
-- dry weather transition. A new shower/storm resets them to full size. This
-- intentionally keys evaporation to weather evolution rather than wall-clock
-- seconds so the effect remains readable at every WEATHER SPEED, including
-- VERY FAST testing.
local PUDDLE_DRY_LEVELS = { 1.00, 0.78, 0.58, 0.42, 0.28, 0.16, 0.08, 0.0 }
local puddleState = { wetness=0.0, drySteps=99, lastManual=nil }

-- Ground snow cover (3D). Builds while snowy weather is active; melts when
-- weather changes. Rates are tuned to feel natural (not instant, not sticky).
local snowState = {
  cover = 0.0,
  target = 0.0,
  meltRate = 0.55,
  wxId = "",
}

local function wxIsSnowy(id)
  if not id then return false end
  id = tostring(id):upper()
  if id:find("SNOW", 1, true) then return true end
  -- HAIL is ice pellets only — not snowfall. Do not treat it as snowy for 3D flakes.
  return id == "BLIZZARD" or id == "THUNDERSNOW" or id == "SLEET" or id == "DRAGONSTORM"
end

-- Map Weather FX's authoritative weather id onto the matching 3D atmosphere
-- family. Historically the embedded cinematic atmosphere could be cycling
-- through CLEAR/PARTLY while Weather FX itself was SNOW/RAIN, so particles and
-- clouds were literally two different weather systems. Only recognized active
-- weather overrides the cinematic profile; an empty/unknown id preserves the
-- standalone dynamic atmosphere behaviour for compatibility hosts.
local function wxAtmosProfileKey(id)
  id = tostring(id or ""):upper()
  if id == "" then return nil end
  if id == "SNOW" or id == "SNOW_LIGHT" or id == "SNOWY"
      or id == "FROSTBOG" or id == "FROSTWAVE" or id == "SNOWSHREW" then
    return "snow"
  end
  if id == "BLIZZARD" or id == "WHITEOUT" then return "blizzard" end
  if id == "THUNDERSNOW" or id == "TSNOW" then return "thunderstorm" end
  if id == "SLEET" then return "snow" end
  if id == "HAIL" then return "snow" end
  if id == "SANDSTORM" or id == "DUSTSTORM" or id == "ASHFALL"
      or id == "SMOG" or id == "FOG" then return "overcast" end
  if id == "MIST" or id == "HAUNTED_MIST" then return "cloudy" end
  if id == "GALE" then return "gale" end
  if id == "STRONG_WINDS" or id == "BRAWL_WIND" or id == "FLOCKSTORM"
      or id == "SWARM" or id == "PLAIN_FRONT" then return "mostly" end
  if id == "STORM" or id == "HEAVY_RAIN" or id == "PRIMAL_RAIN"
      or id == "PSYSTORM" or id == "DRAGONSTORM" then
    return "thunderstorm"
  end
  if id == "RAIN" or id == "RAINING" or id == "RAIN_LIGHT"
      or id == "RAIN_HEAVY" or id == "DRIZZLE" or id == "VERDANT_RAIN" then
    return "rain"
  end
  if id == "ASHFALL" then return "overcast" end
  return nil
end

-- How thick packs get for each WX id (blizzard denser than light snow).
local function snowTargetFor(id)
  id = tostring(id or ""):upper()
  if id == "BLIZZARD" then return 1.00 end
  if id == "THUNDERSNOW" then return 7.38 end  -- dense snow under lightning
  if id == "DRAGONSTORM" then return 1.8 end
  if id == "SNOW_LIGHT" or id == "SNOW" then return 1.86 end
  if id == "HAIL" then return 0.0 end  -- hail = pellets only, no 3D snow
  if id == "SLEET" then return 0.28 end
  if wxIsSnowy(id) then return 0.55 end
  return 0.0
end

-- Melt speed after leaving snow: rain washes fast, sun medium, overcast slow.
local function meltRateFor(id)
  id = tostring(id or ""):upper()
  if id:find("RAIN", 1, true) or id == "STORM" or id == "GALE" then return 1.35 end
  if id == "SUNNY" or id == "HARSH_SUN" or id == "HEATWAVE" then return 0.72 end
  if id == "CLEAR" then return 0.55 end
  if id == "FOG" or id == "MIST" or id == "SMOG" or id == "HAUNTED_MIST" then return 0.22 end
  if id == "SANDSTORM" or id == "DUSTSTORM" or id == "ASHFALL" then return 0.40 end
  return 0.48
end

--- Called from Weather FX when the overworld weather id changes.
function CinematicAtmos.notifyWxWeather(id)
  id = tostring(id or ""):upper()
  -- Keep the namespace mirror authoritative as well as the local snow state.
  -- This gives WorldPrecip a second, direct source of truth.
  if V then V.weatherFxId = id end
  snowState.wxId = id
  if wxIsSnowy(id) then
    snowState.target = snowTargetFor(id)
    snowState.meltRate = 0.55
  else
    snowState.target = 0.0
    snowState.meltRate = meltRateFor(id)
  end
end

function CinematicAtmos.snowCover()
  return snowState.cover or 0
end

local function updateSnowCover(dt)
  dt = tonumber(dt) or 0
  if dt <= 0 then return end
  if dt > 0.25 then dt = 0.25 end
  local c = snowState.cover or 0
  local tgt = snowState.target or 0
  if c < tgt - 0.0005 then
    -- Ease-in accumulation: slower as it approaches the target.
    local gap = tgt - c
    local rate = 0.12 + gap * 0.22  -- ~15–40s to full under light snow
    if (snowState.wxId or "") == "BLIZZARD" then rate = rate * 1.55 end
    if (snowState.wxId or "") == "HAIL" then rate = rate * 0.75 end
    snowState.cover = min(1.0, c + dt * rate)
  elseif c > tgt + 0.0005 then
    -- Ease-out melt: starts noticeable, finishes clean (no long dirty remnants).
    local rate = snowState.meltRate or 0.55
    -- Slightly faster at high cover so thick packs start breaking up.
    rate = rate * (0.75 + 0.45 * c)
    snowState.cover = max(0.0, c - dt * rate)
  else
    snowState.cover = tgt
  end
end

-- Profile keys / wx ids that may show reflective rain puddles.
local function rainyKey(k)
  k = tostring(k or ""):lower()
  if k == "rain" or k == "thunderstorm" or k == "drizzle" then return true end
  if k:find("rain", 1, true) and not k:find("verdant", 1, true) then return true end
  if k:find("sleet", 1, true) then return true end
  if k:find("psy", 1, true) then return true end
  if k:find("dragon", 1, true) then return true end
  if k:find("storm", 1, true) and not k:find("sand", 1, true)
      and not k:find("dust", 1, true) and not k:find("flock", 1, true)
      and not k:find("ash", 1, true) then
    return true
  end
  return false
end

local function puddleWxId(id)
  id = tostring(id or ""):upper()
  return id == "RAIN_LIGHT" or id == "RAIN_HEAVY" or id == "HEAVY_RAIN"
      or id == "STORM" or id == "SLEET" or id == "PSYSTORM" or id == "DRAGONSTORM"
end

-- Weathers that definitely precipitate, so "is it snowing" has a definite
-- answer for them. Kept separate from puddleWxId, which is about wetness on the
-- ground and excludes dry storms.
local function precipWxId(id)
  id = tostring(id or ""):upper()
  if puddleWxId(id) then return true end
  return id == "RAIN" or id == "RAINING" or id == "PRIMAL_RAIN"
      or id == "THUNDERSTORM" or id == "GALE" or id == "DRIZZLE"
      or id:find("RAIN", 1, true) ~= nil
end

local function soakPuddles()
  puddleState.wetness = 1.0
  puddleState.drySteps = 0
  -- Rain washes snow packs away quickly.
  snowState.target = 0.0
  snowState.meltRate = 1.35
end

local function leaveRainPuddles()
  -- Rain-only puddles: clear as soon as rain weather ends.
  puddleState.drySteps = 99
  puddleState.wetness = 0.0
end

local function dryPuddlesOneTransition()
  if puddleState.wetness <= 0.001 then return end
  puddleState.drySteps = min(#PUDDLE_DRY_LEVELS - 1, (puddleState.drySteps or 0) + 1)
  puddleState.wetness = PUDDLE_DRY_LEVELS[puddleState.drySteps + 1] or 0.0
end

local function completedWeatherTransition(fromKey, toKey)
  if rainyKey(toKey) then
    soakPuddles()
  elseif rainyKey(fromKey) then
    -- The first dry state still inherits broad, fresh puddles. Only later
    -- weather transitions progressively evaporate them.
    leaveRainPuddles()
  else
    dryPuddlesOneTransition()
  end
end

local function dynRand(salt)
  local x = sin((dynamic.serial + 1) * 12.9898 + (salt or 0) * 78.233) * 43758.5453
  return x - floor(x)
end

local function speedMult()
  return SPEED_MULT[CinematicAtmos.weatherSpeedSetting:get() or "normal"] or 1.0
end

local function randomRange(pair, salt)
  local a, b = pair[1], pair[2]
  return (a + (b - a) * dynRand(salt)) * speedMult()
end

local function chooseNextWeather(key)
  -- W6: weather is a graph rather than a single severity ladder. Rain is a
  -- precipitation branch from an already-moist CLOUDY / OVERCAST sky, so a
  -- dynamic cycle no longer has to pass through perfect 100% overcast before
  -- every shower, nor must every overcast spell eventually rain.
  local r = dynRand(41)
  if key == "clear" then
    return "partly"
  elseif key == "partly" then
    return r < 0.43 and "clear" or "mostly"
  elseif key == "mostly" then
    return r < 0.36 and "partly" or "cloudy"
  elseif key == "cloudy" then
    if r < 0.31 then return "mostly" end
    if r < 0.73 then return "overcast" end
    return "rain"
  elseif key == "overcast" then
    return r < 0.48 and "cloudy" or "rain"
  elseif key == "rain" then
    -- Rain can clear back to broken cloud, settle under a sealed deck, or
    -- intensify. This is the branch that stops precipitation being a rung
    -- permanently above OVERCAST.
    if r < 0.22 then return "cloudy" end
    if r < 0.76 then return "overcast" end
    return "thunderstorm"
  end
  -- A storm normally decays through rain, but occasionally the convective
  -- rain collapses first and leaves a dark overcast deck behind.
  return r < 0.82 and "rain" or "overcast"
end

local function beginHold(key)
  dynamic.currentKey = key or dynamic.currentKey or "partly"
  dynamic.targetKey = nil
  dynamic.phase = "hold"
  dynamic.elapsed = 0
  dynamic.serial = dynamic.serial + 1
  if (CinematicAtmos.weatherSpeedSetting:get() or "normal") == "very_fast" then
    dynamic.duration = VERY_FAST_HOLD
  else
    dynamic.duration = randomRange(HOLD_RANGES[dynamic.currentKey] or HOLD_RANGES.partly, 17)
  end
end

local function beginTransition()
  dynamic.serial = dynamic.serial + 1
  dynamic.targetKey = chooseNextWeather(dynamic.currentKey)
  dynamic.phase = "transition"
  dynamic.elapsed = 0
  local a = TRANSITION_RANGES[dynamic.currentKey] or TRANSITION_RANGES.partly
  local b = TRANSITION_RANGES[dynamic.targetKey] or a
  local lo = (a[1] + b[1]) * 0.5
  local hi = (a[2] + b[2]) * 0.5
  if (CinematicAtmos.weatherSpeedSetting:get() or "normal") == "very_fast" then
    dynamic.duration = VERY_FAST_TRANSITION
  else
    dynamic.duration = randomRange({lo, hi}, 29)
  end
end

-- Runs on the same unconditional pipeline tick as DayNight/ForestAtmos, so the
-- weather clock keeps advancing in interiors, menus and battles. Returning to
-- the overworld therefore reveals the weather part-way through its natural
-- transition instead of restarting it. Manual presets pause the simulation and
-- seed DYNAMIC from the preset the player was just using.
function CinematicAtmos.update(dt)
  local visualDt=max(0,tonumber(dt) or 0)
  CinematicAtmos._weatherAnimationDt=visualDt
  updateSnowCover(visualDt)
  local selected = CinematicAtmos.weatherSetting:get() or "dynamic"
  if selected ~= "dynamic" then
    if WEATHER[selected] then
      local prev = puddleState.lastManual
      if rainyKey(selected) then
        soakPuddles()
      elseif prev and prev ~= selected then
        if rainyKey(prev) then leaveRainPuddles() else dryPuddlesOneTransition() end
      end
      puddleState.lastManual = selected
      dynamic.active = false
      dynamic.currentKey = selected
      dynamic.targetKey = nil
      dynamic.phase = "hold"
      dynamic.elapsed = 0
    end
    return
  end
  puddleState.lastManual = dynamic.currentKey or "partly"

  if not dynamic.active then
    dynamic.active = true
    dynamic.speedKey = CinematicAtmos.weatherSpeedSetting:get() or "normal"
    beginHold(dynamic.currentKey or "partly")
  end
  if rainyKey(dynamic.currentKey) and dynamic.phase == "hold" then soakPuddles() end

  -- Re-time the current phase immediately when WEATHER SPEED changes while
  -- preserving its progress. This makes VERY FAST useful as an on-device test
  -- switch without snapping the visible weather back to the start of a blend.
  local newSpeed = CinematicAtmos.weatherSpeedSetting:get() or "normal"
  if dynamic.speedKey ~= newSpeed then
    local progress = dynamic.duration > 0 and min(1, max(0, dynamic.elapsed / dynamic.duration)) or 0
    dynamic.speedKey = newSpeed
    if dynamic.phase == "hold" then
      if newSpeed == "very_fast" then
        dynamic.duration = VERY_FAST_HOLD
      else
        dynamic.duration = randomRange(HOLD_RANGES[dynamic.currentKey] or HOLD_RANGES.partly, 17)
      end
    else
      local a = TRANSITION_RANGES[dynamic.currentKey] or TRANSITION_RANGES.partly
      local b = TRANSITION_RANGES[dynamic.targetKey] or a
      local lo = (a[1] + b[1]) * 0.5
      local hi = (a[2] + b[2]) * 0.5
      if newSpeed == "very_fast" then
        dynamic.duration = VERY_FAST_TRANSITION
      else
        dynamic.duration = randomRange({lo, hi}, 29)
      end
    end
    dynamic.elapsed = progress * dynamic.duration
  end

  local left = visualDt
  local guard = 0
  while left > 0 and guard < 12 do
    guard = guard + 1
    local remain = max(0, dynamic.duration - dynamic.elapsed)
    if left < remain then
      dynamic.elapsed = dynamic.elapsed + left
      left = 0
    else
      left = left - remain
      dynamic.elapsed = dynamic.duration
      if dynamic.phase == "hold" then
        beginTransition()
      else
        local fromKey = dynamic.currentKey
        local toKey = dynamic.targetKey or dynamic.currentKey
        completedWeatherTransition(fromKey, toKey)
        beginHold(toKey)
      end
    end
  end
end

local BLEND_NUMERIC = {
  "coverage","cell","gate","span","puffs","bank","rays","shadow",
  "cloudShade","fog","motes","rainIntensity","rainSpeed","rainWind",
  "snowIntensity","snowSpeed","snowWind",
  "sandIntensity","ashIntensity","debrisIntensity","hailIntensity","snowCover",
  "rainDensityRung","rainSizeRung","deckWidth","deckDepth","deckY0",
  "deckYSpan","skyBlend","storm","deckBlend","softGate",
}
local BLEND_DEFAULT = {
  coverage=0, cell=120, gate=1.01, span=1, puffs=1, bank=0.34, rays=1,
  shadow=1, cloudShade=1, fog=1, motes=1, rainIntensity=0, rainSpeed=1,
  snowIntensity=0, snowSpeed=1, snowWind=1,
  sandIntensity=0, ashIntensity=0, debrisIntensity=0, hailIntensity=0, snowCover=0,
  rainWind=1, rainDensityRung=4, rainSizeRung=3, deckWidth=1.82,
  deckDepth=1.12, deckY0=116, deckYSpan=26, skyBlend=0, storm=0,
  deckBlend=0, softGate=0.10,
}

local function profileNumber(p, k)
  local v = p and p[k]
  if v == nil then return BLEND_DEFAULT[k] or 0 end
  return v
end

function CinematicAtmos._blendProfilesInto(out, a, b, t)
  for k in pairs(out) do out[k]=nil end
  -- Overlap ease so precip/clouds of the outgoing state linger while the
  -- next builds — no dead air between weathers.
  local u = max(0, min(1, t))
  local outW = 1.0 - (u * u)
  local inW = u * (2.0 - u)
  if inW > 1 then inW = 1 end
  for _, k in ipairs(BLEND_NUMERIC) do
    local av = profileNumber(a, k)
    local bv = profileNumber(b, k)
    local mixed = lerp(av, bv, u)
    if k == "rainIntensity" or k == "snowIntensity" or k == "fog"
        or k == "coverage" or k == "puffs" or k == "bank" then
      out[k] = max(mixed, av * outW, bv * inW)
    else
      out[k] = mixed
    end
  end
  local ac, bc = a.skyColor, b.skyColor
  if ac and bc then
    local c=out.skyColor or {}; out.skyColor=c
    c[1]=lerp(ac[1],bc[1],u); c[2]=lerp(ac[2],bc[2],u); c[3]=lerp(ac[3],bc[3],u)
  elseif bc then
    local c=out.skyColor or {}; out.skyColor=c; c[1],c[2],c[3]=bc[1],bc[2],bc[3]
  elseif ac then
    local c=out.skyColor or {}; out.skyColor=c; c[1],c[2],c[3]=ac[1],ac[2],ac[3]
  end
  out.closedDeck = (out.deckBlend or 0) >= 0.985
  return out
end

local function blendProfiles(a,b,t)
  -- Standalone DYNAMIC weather is not the hot Weather-FX bridge path. Keep its
  -- independent result table so callers outside frame() retain old semantics.
  return CinematicAtmos._blendProfilesInto({},a,b,t)
end

local function smoother01(t)
  t = max(0, min(1, t))
  return t * t * t * (t * (t * 6 - 15) + 10)
end

local function weatherProfile()
  local selected = CinematicAtmos.weatherSetting:get() or "dynamic"
  if selected ~= "dynamic" then
    return WEATHER[selected] or WEATHER.partly, selected
  end

  local a = DYNAMIC_WEATHER[dynamic.currentKey] or DYNAMIC_WEATHER.partly
  if dynamic.phase ~= "transition" or not dynamic.targetKey then
    return a, dynamic.currentKey
  end
  local b = DYNAMIC_WEATHER[dynamic.targetKey] or a
  local t = smoother01(dynamic.duration > 0 and dynamic.elapsed / dynamic.duration or 1)
  return blendProfiles(a, b, t), dynamic.currentKey .. ">" .. dynamic.targetKey
end

-- Effective puddle coverage for the current rendered frame. During a dry ->
-- rain blend, the growing precipitation can refill puddles before the target
-- preset is formally reached; once rain stops, persistent wetness owns them.
local function puddleWetnessFor(weather)
  local wx = tostring((weather and weather.wxId) or snowState.wxId or ""):upper()
  if wx == "GALE" then return 0.0 end  -- 2D cycling small puddles only
  local rain = max(0.0, min(1.0, tonumber(weather and weather.rainIntensity) or 0.0))
  -- Persistent ground state is the authority once drops stop. The old function
  -- returned zero as soon as rainIntensity crossed 0.02, which made a soaked
  -- route visually dry in a single frame even though EnvironmentSurface was
  -- still wet and drying naturally.
  local persistent=max(0,tonumber(puddleState.wetness) or 0)
  local SV=cachedRequire("SurfaceVisualState")
  if SV and SV.peek then
    local ok,q=V.safeCall(SV.peek)
    if ok and q then
      persistent=max(persistent,min(1,tonumber(q.wet) or 0),min(1,(tonumber(q.puddleDepth) or 0)*4))
    end
  end
  -- During a natural clearing the target id may already be CLEAR while live
  -- rain is still tapering. Keep wet-ground response tied to actual water, and
  -- retain the surface wetness afterward until the material dries.
  if not puddleWxId(wx) and not (weather and weather._transitionActive and rain>0.02) then return max(0,min(1.35,persistent*CinematicAtmos._puddleAmountScale())) end
  if wx == "PSYSTORM" or wx == "DRAGONSTORM" or wx == "SLEET" then
    return max(0,min(1.35,max(persistent, max(0.35, rain))*CinematicAtmos._puddleAmountScale()))
  end
  return max(0,min(1.35,max(persistent, rain)*CinematicAtmos._puddleAmountScale()))
end

function CinematicAtmos.puddleWetness()
  local w = weatherProfile()
  return puddleWetnessFor(w)
end

local function eventRand(i, salt)
  local x = sin((i + 17) * 19.197 + (salt or 0) * 71.731) * 9182.117
  return x - floor(x)
end

-- Atmospheric storm illumination rather than a drawn bolt: irregular short
-- bursts brighten the cloud deck, rain, fog and world lighting together. A
-- storm event can contain a second/third pulse, which reads much more like
-- distant lightning behind clouds than a regular screen flash.
local function lightningFlashFor(weather, t)
  local storm = weather and (weather.storm or 0) or 0
  if storm <= 0.001 then return 0 end
  t = t or ForestAtmos.time
  local cell = 8.5
  local base = floor(t / cell)
  local flash = 0
  for i = base - 1, base do
    local chance = eventRand(i, 3)
    if chance > 0.28 then
      local start = i * cell + 0.8 + eventRand(i, 4) * 5.7
      local d = t - start
      if d >= 0 and d < 0.78 then
        local function pulse(c, w, amp)
          local q = (d - c) / w
          return amp * math.exp(-q * q)
        end
        local f = max(pulse(0.035, 0.045, 1.00), pulse(0.19, 0.060, 0.68))
        if eventRand(i, 5) > 0.48 then f = max(f, pulse(0.43, 0.105, 0.38)) end
        flash = max(flash, f)
      end
    end
  end
  local scale=1
  local S=weatherSettings()
  if S and S.lightningFlashScale then scale=S.lightningFlashScale() or 1 end
  return min(1.0, flash * storm * max(0,scale))
end

function CinematicAtmos.lightningFlash()
  local w = weatherProfile()
  return lightningFlashFor(w, ForestAtmos.time)
end

function CinematicAtmos.worldTint(base, outdoor)
  if not outdoor then return base end
  local f = CinematicAtmos.lightningFlash()
  if f <= 0.001 then return base end
  return {
    min(1.42, base[1] + 0.46 * f),
    min(1.48, base[2] + 0.55 * f),
    min(1.60, base[3] + 0.72 * f),
  }
end

-- VoxelScene asks for this before painting the generated sky.  Closed-deck
-- weather shifts the sky beneath the 3D clouds toward the same cool grey family,
-- so a one-pixel feather gap can never read as a patch of saturated blue sky.
-- Clear/Partly/Mostly return nil and preserve Dramatic Shape's normal sky.
function CinematicAtmos.skyWeather()
  local w, key = weatherProfile()
  local flash = lightningFlashFor(w, ForestAtmos.time)
  if not (w and ((w.skyColor and w.skyBlend and w.skyBlend > 0) or flash > 0.001)) then return nil end
  local darkScale=1
  local S=weatherSettings()
  if S and S.stormDarknessScale then darkScale=S.stormDarknessScale() or 1 end
  return { color=w.skyColor, blend=min(1,max(0,(w.skyBlend or 0)*darkScale)), key=key, flash=flash }
end

local LIGHT_SCALE = { 0.38, 0.52, 0.67, 0.83, 1.00, 1.18, 1.38, 1.60, 1.83, 2.08 }

-- Density is a population multiplier, not opacity.  The upper rungs are
-- deliberately nonlinear: early steps are useful for fine tuning, while the
-- last few allow a genuinely busy pollen/dust field for testing.  1 = A9.
local PARTICLE_DENSITY_SCALE = {
  1.00, 1.35, 1.72, 2.12, 2.58, 3.08, 3.64, 4.26, 4.94, 5.70
}

-- Scale changes projected mote diameter only.  8 = A9 exactly; lower rungs
-- get substantially smaller so combinations such as SCALE 3 / DENSITY 7 can
-- create lots of fine atmospheric dust without turning into giant blobs.
local PARTICLE_SIZE_SCALE = {
  0.26, 0.34, 0.43, 0.53, 0.64, 0.76, 0.88, 1.00, 1.13, 1.27
}

-- Rain controls deliberately have a broad useful range. Density changes the
-- number of independent 3D streaks; size changes both streak width and length
-- without altering their fall speed. Level 5 is the authored neutral point.
local RAIN_DENSITY_SCALE = {
  0.30, 0.45, 0.62, 0.80, 1.00, 1.25, 1.55, 1.90, 2.30, 2.75
}
local RAIN_SIZE_SCALE = {
  0.45, 0.56, 0.68, 0.82, 1.00, 1.16, 1.34, 1.54, 1.76, 2.00
}

local function lightScale()
  local n = tonumber(CinematicAtmos.lightSetting:get()) or 5
  n = max(1, min(10, floor(n + 0.5)))
  return LIGHT_SCALE[n] or 1.0
end

local _PerformanceGovernor=nil
local function performanceScale()
  local scale=1
  if _PerformanceGovernor==nil then local ok,m=V.safeCall(V.require,"PerformanceGovernor"); _PerformanceGovernor=(ok and m) or false end
  if _PerformanceGovernor and _PerformanceGovernor.particleScale then local ok,v=V.safeCall(_PerformanceGovernor.particleScale); if ok and tonumber(v) then scale=max(.30,min(1,tonumber(v))) end end
  if _PerformanceGovernor and _PerformanceGovernor.auto and _PerformanceGovernor.auto() then
    local R=cachedRequire("WorkloadRouter"); if R and R.scale then local ok,v=V.safeCall(R.scale,"particles"); if ok and tonumber(v) then scale=min(scale,max(.30,min(1,tonumber(v)))) end end
  end
  return scale
end

function CinematicAtmos._qualityCloudDetail()
  local Q=cachedRequire("Quality")
  if Q and Q.cloudDetailScale then
    local ok,v=V.safeCall(Q.cloudDetailScale)
    if ok and tonumber(v) then return max(.40,min(1,tonumber(v))) end
  end
  return 1
end

local function particleDensityScale()
  local n = tonumber(CinematicAtmos.particleDensitySetting:get()) or 6
  n = max(1, min(10, floor(n + 0.5)))
  return (PARTICLE_DENSITY_SCALE[n] or 1.0) * performanceScale()
end

local function particleSizeScale()
  local n = tonumber(CinematicAtmos.particleScaleSetting:get()) or 8
  n = max(1, min(10, floor(n + 0.5)))
  return PARTICLE_SIZE_SCALE[n] or 1.0
end

local function rainDensityScale(weather)
  local n = tonumber(weather and weather.rainDensityRung) or 4
  n = max(1, min(10, floor(n + 0.5)))
  return RAIN_DENSITY_SCALE[n] or 0.80
end

local function rainSizeScale(weather)
  local n = tonumber(weather and weather.rainSizeRung) or 3
  n = max(1, min(10, floor(n + 0.5)))
  return RAIN_SIZE_SCALE[n] or 0.68
end

-- ---------- shared helpers

local function fract(x) return x - floor(x) end

-- Deterministic 2D hash. It is deliberately arithmetic-only: no bit library,
-- no platform-specific integer behaviour and no texture dependency.
local function hash2(x, z, salt)
  return fract(sin(x * 127.1 + z * 311.7 + (salt or 0) * 74.7) * 43758.5453123)
end

-- LOCAL, not global. These were plain assignments, which in Lua creates a
-- GLOBAL -- so loading this mod put `lerp` and `mixColor` into _G where any
-- other mod in the same VM could read or clobber them. Generic names like these
-- are exactly what a second mod is likely to define too, and the resulting
-- conflict would be intermittent and very hard to trace back here.
lerp = function(a, b, t) return a + (b - a) * t end

mixColor = function(a, b, t)
  return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

function CinematicAtmos._vpBillboardAxes(Voxel3D, outR, outU)
  local m=Voxel3D and Voxel3D.vp
  if type(m)~='table' then return nil,nil end
  local rx,ry,rz=tonumber(m[1]),tonumber(m[2]),tonumber(m[3])
  local ux,uy,uz=tonumber(m[5]),tonumber(m[6]),tonumber(m[7])
  if not (rx and ry and rz and ux and uy and uz) then return nil,nil end
  local rl=sqrt(rx*rx+ry*ry+rz*rz); if rl<1e-7 then return nil,nil end
  rx,ry,rz=rx/rl,ry/rl,rz/rl
  local d=ux*rx+uy*ry+uz*rz; ux,uy,uz=ux-d*rx,uy-d*ry,uz-d*rz
  local ul=sqrt(ux*ux+uy*uy+uz*uz); if ul<1e-7 then return nil,nil end
  local r=outR or {0,0,0}; local u=outU or {0,0,0}
  r[1],r[2],r[3]=rx,ry,rz;u[1],u[2],u[3]=ux/ul,uy/ul,uz/ul
  return r,u
end

local function billboardAxes(Voxel3D)
  local st=CinematicAtmos._spatialFrame
  if st and st.owner==Voxel3D and st.billboardValid then return st.axisR,st.axisU end
  -- 8.2.2 zenith repair: screen-facing cloud cards must not derive their right
  -- vector solely from forward x camera-up. That cross product reaches zero at
  -- exact upward/downward pitch and used to make the entire cloud bank vanish.
  local vr,vu=CinematicAtmos._vpBillboardAxes(Voxel3D)
  if vr then return vr,vu end
  local e, fo = Voxel3D.eye, Voxel3D.focus
  if not (e and fo) then return nil end
  local fx, fy, fz = fo[1] - e[1], fo[2] - e[2], fo[3] - e[3]
  local fl = sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then return nil end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local rx,ry,rz=-fz,0,fx
  local rl=sqrt(rx*rx+rz*rz)
  if rl<1e-6 then rx,ry,rz=1,0,0 else rx,rz=rx/rl,rz/rl end
  local ux,uy,uz=ry*fz-rz*fy,rz*fx-rx*fz,rx*fy-ry*fx
  local ul=sqrt(ux*ux+uy*uy+uz*uz)
  if ul<1e-6 then ux,uy,uz=0,1,0 else ux,uy,uz=ux/ul,uy/ul,uz/ul end
  return {rx,ry,rz},{ux,uy,uz}
end

local function horizontalRight(Voxel3D)
  local st=CinematicAtmos._spatialFrame
  if st and st.owner==Voxel3D and st.horizontalValid then return st.right end
  local e, f = Voxel3D.eye, Voxel3D.focus
  if not (e and f) then return nil end
  local fx, fz = f[1] - e[1], f[3] - e[3]
  local fl = sqrt(fx * fx + fz * fz)
  if fl < 1e-6 then return nil end
  fx, fz = fx / fl, fz / fl
  return { -fz, 0, fx }
end

-- The vertical FOV stays fixed while a landscape viewport exposes much more
-- world to the left and right. A6 kept a fixed square weather field around
-- the focus, so portrait was mostly inside it while landscape could see clear
-- world beyond its sides. Expand the FIELD, not its alpha: this preserves the
-- same fog density per metre and makes rotation change framing rather than
-- apparent weather strength.
local function viewportAspect(Voxel3D)
  local st=CinematicAtmos._spatialFrame
  if st and st.owner==Voxel3D and st.aspect then return st.aspect end
  local w, h = 0, 0
  if Voxel3D and Voxel3D.size then
    local ok, rw, rh = V.safeCall(Voxel3D.size)
    if ok then w, h = tonumber(rw) or 0, tonumber(rh) or 0 end
  end
  if h <= 0 and love and love.graphics and love.graphics.getDimensions then
    local ok, rw, rh = V.safeCall(love.graphics.getDimensions)
    if ok then w, h = tonumber(rw) or 0, tonumber(rh) or 0 end
  end
  if h <= 0 then return 1 end
  return max(0.35, min(2.6, w / h))
end

-- Projection-density correction.  Dramatic Shape's orbit keeps vertical FOV
-- fixed and moves the camera with the world-view HEIGHT.  A tall portrait
-- viewport therefore looks through more world-space air than a short
-- landscape viewport.  Coverage alone cannot compensate for that: the
-- landscape rays intersect fewer fog bodies along a typical sightline.
-- Keep portrait as the authored reference and modestly raise per-metre
-- extinction in wide views.  This is intentionally bounded so individual
-- cards never turn into opaque sheets.
local function orientationDensityScale(Voxel3D)
  local a = viewportAspect(Voxel3D)
  if a <= 1.0 then return 1.0 end
  return min(1.55, a ^ 0.42)
end

local function fieldBasis(Voxel3D)
  local st=CinematicAtmos._spatialFrame
  if st and st.owner==Voxel3D and st.fieldValid then return st.right,st.forward end
  local r = horizontalRight(Voxel3D)
  if not r then return nil, nil end
  local f = Voxel3D.lookFlat
  if not f then f = { -r[3], 0, r[1] } end
  local fl = sqrt(f[1] * f[1] + f[3] * f[3])
  if fl < 1e-6 then return nil, nil end
  return r, { f[1] / fl, 0, f[3] / fl }
end

-- Iterate only cells inside a camera-oriented rectangle. Landscape widens the
-- rectangle along the camera-right axis in direct proportion to the viewport
-- aspect. The depth span is unchanged, so the extra geometry pays only for
-- world the wider screen can actually reveal.
-- ---------------------------------------------------------------------------
-- CLOUD-SPACE ORIGIN -- seamless deck across map changes
-- ---------------------------------------------------------------------------
-- The cell grid below is world-anchored: a cell's identity comes from
-- floor(worldX / cell), so walking streams cells in and out at the edges and
-- the deck is already seamless while you move. That part was never broken.
--
-- A MAP CHANGE is different. The focus teleports to unrelated world
-- coordinates, every cell index changes at once, and an entirely new sky pops
-- into existence -- clouds "suddenly appearing" on a transition.
--
-- Clouds are sky. Unlike terrain they have no reason to be tied to absolute
-- world position, so the fix is to keep the grid continuous ACROSS the jump:
-- when the focus teleports, shift the cloud-space origin by the same delta.
-- The player then arrives under exactly the sky they left, and normal
-- streaming continues from there.
--
-- Detection matches the precipitation carry: far, fast and isolated. Ordinary
-- movement -- however quick -- must never shift the origin, or the deck would
-- be dragged along with the player instead of streaming past.
local cloudShiftX, cloudShiftZ = 0, 0
local cloudLastX, cloudLastZ = nil, nil
local cloudLastStep2 = 0
local cloudShifts = 0
local CLOUD_JUMP = 140          -- far:  minimum jump distance
local CLOUD_JUMP_SPEED = 2500   -- fast: implied units/s walking cannot reach

-- WORLD-PRECIP STREAMING ANCHOR.
--
-- Voxel3D exposes three different points on different hosts/camera modes:
--   player = real avatar/world position (best, invariant under camera motion)
--   eye    = camera position (stable under FIRST-PERSON rotation)
--   focus  = look target (stable near the avatar in orbit/third-person cameras)
--
-- A single unconditional eye fallback is wrong: in third person the eye orbits
-- the avatar, and a large turn can look exactly like a world teleport to the
-- precipitation streamer. That causes every live flake/drop/grain to be shifted
-- with the camera. Conversely, using focus in first person is wrong because the
-- focus target rotates around the head. Select the invariant point for the
-- active camera instead.
weatherSettings = function()
  return cachedRequire("Settings")
end

function CinematicAtmos._cloudHeightScale()
  local S=weatherSettings()
  if S and S.cloudHeightScale then
    local ok,v=V.safeCall(S.cloudHeightScale)
    if ok and tonumber(v) then return max(1.0,min(1.5,tonumber(v))) end
  end
  return 1.5
end

function CinematicAtmos._puddleAmountScale()
  local S=weatherSettings()
  if S and S.puddleAmountScale then
    local ok,v=V.safeCall(S.puddleAmountScale)
    if ok and tonumber(v) then return max(0,min(1.35,tonumber(v))) end
  end
  return 1
end

function CinematicAtmos._frontsEnabled()
  local S=weatherSettings()
  if S and S.get then
    local ok,v=V.safeCall(S.get,"fronts")
    if ok then
      if v=="off" then return false end
      if v=="on" then return true end
    end
  end
  local C=cachedRequire("Config")
  if C and C.get then
    local ok,cfg=V.safeCall(C.get)
    if ok and type(cfg)=="table" and type(cfg.fronts)=="table" and cfg.fronts.enabled~=nil then
      return cfg.fronts.enabled~=false
    end
  end
  return true
end

local function worldPrecipAnchor(Voxel3D,player)
  if not Voxel3D then return { 0, 0, 0 }, "origin" end
  -- 8.1.73: map-entry/player gameplay coordinates are the XZ authority. The
  -- voxel camera/player snapshot can lag one frame after a route/map transfer,
  -- which previously left precipitation anchored to the old map until walking
  -- forced the host snapshot to refresh. Preserve the host's real world Y, but
  -- take X/Z from the live overworld player immediately when available.
  if player and tonumber(player.px) and tonumber(player.py) then
    local y=0
    if Voxel3D.player then y=tonumber(Voxel3D.player[2]) or y
    elseif Voxel3D.focus then y=tonumber(Voxel3D.focus[2]) or y
    elseif Voxel3D.eye then y=tonumber(Voxel3D.eye[2]) or y end
    local a=CinematicAtmos._worldPrecipAnchorScratch or {0,0,0};CinematicAtmos._worldPrecipAnchorScratch=a
    a[1],a[2],a[3]=tonumber(player.px)+8,y,tonumber(player.py)+8
    return a,"live-player"
  end
  if Voxel3D.player then return Voxel3D.player, "player" end

  local fp = false
  local S = weatherSettings()
  if S and S.isFirstPerson then
    local ok, v = V.safeCall(S.isFirstPerson)
    fp = ok and v and true or false
  end

  if fp and Voxel3D.eye then return Voxel3D.eye, "eye-fpv" end
  if Voxel3D.focus then return Voxel3D.focus, "focus-orbit" end
  if Voxel3D.eye then return Voxel3D.eye, "eye-fallback" end
  return { 0, 0, 0 }, "origin"
end


-- 8.1.80 frame-spatial cache. Camera basis, viewport aspect and the default
-- world precipitation anchor are invariant during one CinematicAtmos.draw().
-- Several fog/cloud/ray passes used to normalize the same vectors and query the
-- host dimensions independently. Compute them once and hand the exact numbers
-- back through the existing helpers. Outside draw(), helpers keep their legacy
-- self-contained path.
function CinematicAtmos._refreshSpatialFrame(Voxel3D)
  local st=CinematicAtmos._spatialFrame or {
    right={0,0,0},forward={0,0,0},axisR={0,0,0},axisU={0,0,0},anchor={0,0,0}
  }
  CinematicAtmos._spatialFrame=st
  st.owner=nil; st.horizontalValid=false; st.fieldValid=false; st.billboardValid=false

  local w,h=0,0
  if Voxel3D and Voxel3D.size then
    local ok,rw,rh=V.safeCall(Voxel3D.size)
    if ok then w,h=tonumber(rw) or 0,tonumber(rh) or 0 end
  end
  if h<=0 and love and love.graphics and love.graphics.getDimensions then
    local ok,rw,rh=V.safeCall(love.graphics.getDimensions)
    if ok then w,h=tonumber(rw) or 0,tonumber(rh) or 0 end
  end
  st.aspect=h>0 and max(0.35,min(2.6,w/h)) or 1

  local e,fo=Voxel3D and Voxel3D.eye,Voxel3D and Voxel3D.focus
  do
    local vr,vu=CinematicAtmos._vpBillboardAxes(Voxel3D,st.axisR,st.axisU)
    if vr then st.billboardValid=true end
  end
  if e and fo then
    local fx,fz=fo[1]-e[1],fo[3]-e[3]
    local fl=sqrt(fx*fx+fz*fz)
    if fl>=1e-6 then
      fx,fz=fx/fl,fz/fl
      local r=st.right; r[1],r[2],r[3]=-fz,0,fx
      st.horizontalValid=true
      local f=Voxel3D.lookFlat
      local qx,qz
      if f then qx,qz=f[1],f[3] else qx,qz=-r[3],r[1] end
      local ql=sqrt(qx*qx+qz*qz)
      if ql>=1e-6 then
        local fw=st.forward; fw[1],fw[2],fw[3]=qx/ql,0,qz/ql
        st.fieldValid=true
      end
    end

    local bx,by,bz=fo[1]-e[1],fo[2]-e[2],fo[3]-e[3]
    local bl=sqrt(bx*bx+by*by+bz*bz)
    if (not st.billboardValid) and bl>=1e-6 then
      bx,by,bz=bx/bl,by/bl,bz/bl
      local up=(Voxel3D.camera and Voxel3D.camera.up) or CinematicAtmos._worldUp
      local rx=by*up[3]-bz*up[2]
      local ry=bz*up[1]-bx*up[3]
      local rz=bx*up[2]-by*up[1]
      local rl=sqrt(rx*rx+ry*ry+rz*rz)
      if rl>=1e-6 then
        rx,ry,rz=rx/rl,ry/rl,rz/rl
        local ar,au=st.axisR,st.axisU
        ar[1],ar[2],ar[3]=rx,ry,rz
        au[1],au[2],au[3]=ry*bz-rz*by,rz*bx-rx*bz,rx*by-ry*bx
        st.billboardValid=true
      end
    end
  end
  local a=worldPrecipAnchor(Voxel3D)
  if a then st.anchor[1],st.anchor[2],st.anchor[3]=a[1],a[2],a[3]; st.anchorValid=true else st.anchorValid=false end
  st.owner=Voxel3D
  return st
end

function CinematicAtmos.billboardBasisProbe(Voxel3D)
  local st=CinematicAtmos._refreshSpatialFrame(Voxel3D)
  if not (st and st.billboardValid) then return nil,nil end
  return {st.axisR[1],st.axisR[2],st.axisR[3]},{st.axisU[1],st.axisU[2],st.axisU[3]}
end

-- Falling precipitation must originate from the SAME physical deck as the 3D
-- cloud bank. The cloud profiles publish deckY0/deckYSpan; older precipitation
-- code looked for an unrelated cloudBase field, so it usually fell back to a
-- generic height. Keep this calculation in one place and mirror the exact
-- landscape cloud drop used by buildCloudDescriptors().
local function precipitationDeckBand(Voxel3D, weather)
  if not weather then return nil, nil end
  local base = tonumber(weather.deckY0); if base then base=base*CinematicAtmos._cloudHeightScale() end
  if not base then return nil, nil end
  local span = tonumber(weather.deckYSpan) or 26.0
  local aspect = viewportAspect(Voxel3D)
  local landscapeBlend = max(0.0, min(1.0, (aspect - 1.0) / 1.15))
  local landscapeCloudDrop = 34.0 * landscapeBlend

  -- Emit inside the lower body of the bank. The small vertical band prevents a
  -- mathematically flat spawn plane while still making flakes/drops visibly
  -- emerge from cloud volume when the player looks upward.
  local y0 = base - landscapeCloudDrop - 8.0
  local ySpan = max(12.0, min(30.0, span * 0.55 + 8.0))
  return y0, ySpan
end

--- Call once per frame with the streaming anchor. Returns nothing; it maintains
--- the cloud-space origin used by eachWeatherCell.
local function updateCloudOrigin(px, pz, dt, mapId, neighbors, outdoor)
  -- Connected outdoor maps are one continuous voxel world even though each
  -- engine map re-bases its local X/Z origin. Preserve the exact cloud lattice
  -- across that re-base instead of relying on a speed/jump heuristic one frame
  -- after the new map appears.
  local lastMap=CinematicAtmos._cloudLastMap
  local lastOutdoor=CinematicAtmos._cloudLastOutdoor
  local shifted=false
  mapId=mapId and tostring(mapId) or nil
  if mapId and lastMap and mapId~=lastMap and outdoor~=false and lastOutdoor~=false then
    local old=CinematicAtmos._cloudNeighborOffsets or {}
    local row=old[mapId]
    if row then
      -- In the OLD root frame the destination neighbor lived at (+ox,+oz).
      -- Once that destination becomes the root, all persistent world weather
      -- coordinates move by the inverse transform.
      cloudShiftX=cloudShiftX-(tonumber(row[1]) or 0)
      cloudShiftZ=cloudShiftZ-(tonumber(row[2]) or 0)
      cloudShifts=cloudShifts+1
      shifted=true
    end
  end

  if not shifted and cloudLastX and dt and dt > 0 then
    local jx, jz = px - cloudLastX, pz - cloudLastZ
    local j2 = jx * jx + jz * jz
    local far = j2 > (CLOUD_JUMP * CLOUD_JUMP)
    local fast = sqrt(j2) / dt > CLOUD_JUMP_SPEED
    local isolated = cloudLastStep2 < (CLOUD_JUMP * CLOUD_JUMP)
    if far and fast and isolated then
      -- Compatibility fallback for hosts that do not publish neighbour
      -- transforms. Carry the sky across a map-origin teleport, but never use
      -- this as the primary connected-map path.
      cloudShiftX = cloudShiftX + jx
      cloudShiftZ = cloudShiftZ + jz
      cloudShifts = cloudShifts + 1
    end
    cloudLastStep2 = j2
  elseif shifted then
    cloudLastStep2=0
  end
  cloudLastX, cloudLastZ = px, pz
  CinematicAtmos._cloudLastMap=mapId or lastMap
  CinematicAtmos._cloudLastOutdoor=outdoor~=false
  local snap=CinematicAtmos._cloudNeighborOffsets or {}; CinematicAtmos._cloudNeighborOffsets=snap
  for k in pairs(snap) do snap[k]=nil end
  for _,nb in ipairs(neighbors or {}) do
    local m=nb and nb.map
    local id=m and m.id
    if id~=nil then
      local row=snap[tostring(id)] or {}; snap[tostring(id)]=row
      row[1]=tonumber(nb.ox) or tonumber(nb.offsetX) or 0
      row[2]=tonumber(nb.oy) or tonumber(nb.offsetZ) or 0
    end
  end
end

--- Diagnostics for the debug line.
function CinematicAtmos.cloudOrigin()
  return cloudShiftX, cloudShiftZ, cloudShifts
end

-- Test-only deterministic map-frame seam. Production uses the same helper from
-- draw() before descriptors are built. Keeping this tiny lets regression tests
-- prove connected-map persistence without mocking the cloud maths itself.
function CinematicAtmos._testCloudOriginStep(px,pz,dt,mapId,neighbors,outdoor)
  updateCloudOrigin(px,pz,dt,mapId,neighbors,outdoor)
  return cloudShiftX,cloudShiftZ,cloudShifts
end

local function eachWeatherCell(Voxel3D, cell, baseRadius, fn)
  -- Cloud streaming uses the SAME camera-invariant world anchor as falling
  -- precipitation. Voxel3D.focus is a look target in first person, so using it
  -- here makes the cloud field select different world cells when the camera
  -- turns even though the player never moved. Turning the camera must only
  -- change the view into the storm, never the storm's world placement.
  local st=CinematicAtmos._spatialFrame
  local rawFocus=(st and st.owner==Voxel3D and st.anchorValid and st.anchor) or worldPrecipAnchor(Voxel3D)
  if not rawFocus then return end
  local wide = max(1.0, viewportAspect(Voxel3D))
  -- Cell identity is taken in CLOUD SPACE, which is world space minus the
  -- accumulated map-change shift. Within a map the two are identical, so
  -- streaming is unchanged; across a map change the shift cancels the teleport
  -- and the same sky is still overhead. Keep scalar focus coordinates here: a
  -- transient three-number table was formerly allocated for every weather pass.
  local focusX,focusZ=rawFocus[1]-cloudShiftX,rawFocus[3]-cloudShiftZ
  local ix0, iz0 = floor(focusX / cell), floor(focusZ / cell)

  -- Portrait/square preserves A6's exact authored neighbourhood. That makes
  -- the portrait look the calibration target instead of thickening it while
  -- trying to repair landscape.
  if wide <= 1.001 then
    for iz = iz0 - baseRadius, iz0 + baseRadius do
      for ix = ix0 - baseRadius, ix0 + baseRadius do fn(ix, iz) end
    end
    return
  end

  local right, forward = fieldBasis(Voxel3D)
  if not (right and forward) then return end
  local half = (baseRadius + 0.5) * cell
  local sideSpan = half * wide
  local depthSpan = half
  -- An oriented rectangle can project onto both world axes; their span sum is
  -- a conservative bounding square. We filter it immediately below, so the
  -- GPU still receives only the cells the widened frustum can reveal.
  local bound = math.ceil((sideSpan + depthSpan) / cell) + 1
  for iz = iz0 - bound, iz0 + bound do
    for ix = ix0 - bound, ix0 + bound do
      local wx, wz = (ix + 0.5) * cell, (iz + 0.5) * cell
      local dx, dz = wx - focusX, wz - focusZ
      local side = dx * right[1] + dz * right[3]
      local depth = dx * forward[1] + dz * forward[3]
      if abs(side) <= sideSpan and abs(depth) <= depthSpan then fn(ix, iz) end
    end
  end
end

function CinematicAtmos._curveUniform(Voxel3D)
  local q=CinematicAtmos._uniformScratch.curve
  q[1],q[2],q[3]=Voxel3D.curveX or 0,Voxel3D.curveZ or 0,Voxel3D.curveK or 0
  return q
end

local function pushQuad(indices, q)
  local b = q * 4
  indices[#indices + 1] = b + 1
  indices[#indices + 1] = b + 2
  indices[#indices + 1] = b + 3
  indices[#indices + 1] = b + 1
  indices[#indices + 1] = b + 3
  indices[#indices + 1] = b + 4
end

local function settingLevel()
  local s = CinematicAtmos.atmosphereSetting:get()
  if s == "off" then return 0 end
  -- The companion ATMOSPHERE row remains a user preference, but Weather FX
  -- QUALITY now scales the expensive volume/lattice work as well. This closes
  -- the old split-brain path where POTATO reduced 2D particles while full 3D
  -- cloud/fog volume kept running at the production budget.
  local base = (s == "full") and 1.0 or 0.78
  local Q = cachedRequire("Quality")
  local q = 1.0
  if Q and Q.profile then
    local p = Q.profile()
    q = tonumber(p and p.atmosphereScale) or 1.0
  end
  return base * q
end

local function hourColors()
  do
    local E=cachedRequire("CelestialEngine")
    if E and E.state then
      local ok2,st=V.safeCall(E.state)
      if ok2 and st and st.fogColor and st.rayColor then return st.fogColor,st.rayColor end
    end
  end
  local forcedNight = false
  V.safeCall(function()
    if package.loaded and package.loaded._WX_NIGHT then forcedNight = true end
    if rawget(_G, "V") and V._WX_NIGHT then forcedNight = true end
  end)
  if forcedNight then
    return NIGHT_FOG, NIGHT_RAY
  end
  local mix = DayNight.mix(DayNight.time())
  local fog, ray = hourFogScratch, hourRayScratch
  fog[1],fog[2],fog[3]=0,0,0
  ray[1],ray[2],ray[3]=0,0,0
  local weight = 0
  for name, w in pairs(mix) do
    local p = ForestAtmos.RAMP[name] or ForestAtmos.RAMP.day
    fog[1] = fog[1] + p.fog[1] * w
    fog[2] = fog[2] + p.fog[2] * w
    fog[3] = fog[3] + p.fog[3] * w
    ray[1] = ray[1] + p.ray[1] * w
    ray[2] = ray[2] + p.ray[2] * w
    ray[3] = ray[3] + p.ray[3] * w
    weight = weight + w
  end
  if weight <= 0 then
    fog[1],fog[2],fog[3]=0.78,0.86,0.76
    ray[1],ray[2],ray[3]=1.0,0.93,0.72
  end
  return fog, ray
end

-- The scene shader uses this as its far-distance atmospheric extinction.
-- The geometry below supplies the visible body of the mist; this very light
-- haze merely joins the puffs together in depth so they do not read as cards.
function CinematicAtmos.frame(map, outdoor)
  -- WEATHER=OFF must also stop the host-integrated 3D atmosphere. The 3D hook
  -- can run independently of the engine's 2D present pipeline, so relying only
  -- on pipeline eligibility left cloud banks / stale precipitation alive.
  do
    local S=weatherSettings()
    if S and S.weatherDisabled and S.weatherDisabled() then return nil end
    local WS=cachedRequire("WeatherState")
    if WS and tonumber(WS.level) and tonumber(WS.level)<=0 then
      -- A locally CLEAR map can still have a real finite storm/front visible on
      -- the flat-world horizon. Do not kill the entire 3D atmosphere frame just
      -- because local precipitation intensity is zero; retain a minimal frame
      -- while DistantWeather owns at least one remote cell. WEATHER=OFF above
      -- still remains an absolute opt-out.
      local DW=cachedRequire("DistantWeather")
      local farCount=0
      if DW and DW.items then
        local ok,_,n=V.safeCall(DW.items)
        if ok then farCount=tonumber(n) or 0 end
      end
      local keepInteraction=false
      local WI=cachedRequire("WeatherWorldInteraction")
      local wi=WI and WI.peek and WI.peek() or nil
      if wi then
        local gf=wi.gustFront
        keepInteraction=(tonumber(wi.roofDrip) or 0)>.004 or (tonumber(wi.canopyDrip) or 0)>.004
          or (tonumber(wi.postRainShaft) or 0)>.004 or (gf and gf.active==true)
      end
      if farCount<=0 and not keepInteraction then return nil end
    end
  end
  -- Refresh Weather FX night flag from TimeOfDay each atmos frame (not only Sky.paint).
  do
    local TOD = cachedRequire("TimeOfDay")
    if not TOD then
      local ok, m = V.safeCall(require, "TimeOfDay")
      if ok then TOD = m end
    end
    local night = false
    if TOD then
      if TOD.pin == "NITE" or TOD.pin == "NIGHT" or TOD.tod == "NITE" or TOD.tod == "NIGHT" then night = true end
      if TOD.isNight then
        local ok,v=V.safeCall(TOD.isNight)
        if ok and v then night=true end
      end
      if type(TOD.hour) == "number" then
        local h = TOD.hour % 24
        if h >= 20 or h < 5 then night = true end
      end
    end
    if DayNight and DayNight.isNight and DayNight.isNight() then night = true end
    package.loaded._WX_NIGHT = night
    if rawget(_G, "V") then V._WX_NIGHT = night end
  end

  local level = settingLevel()
  local canopy = DayNight.isCanopy(map)
  if level <= 0 or not (outdoor or canopy) then return nil end
  local fogColor, rayColor = hourColors()
  -- Read the authoritative Weather FX id from the shared namespace first.
  -- notifyWxWeather() remains useful for snow-cover transitions, but particle
  -- spawning no longer depends on that callback having fired successfully.
  local authoritativeId = tostring((V and V.weatherFxId) or snowState.wxId or ""):upper()
  if authoritativeId ~= "" and authoritativeId ~= tostring(snowState.wxId or ""):upper() then
    CinematicAtmos.notifyWxWeather(authoritativeId)
  end
  local weather, weatherKey = weatherProfile()
  -- Active Weather FX precipitation owns the matching 3D cloud family. During a
  -- natural AUTO/front handoff, however, the cloud deck must evolve *before* or
  -- *after* precipitation according to the synoptic planner rather than waiting
  -- for State.id to commit. Forced/menu selections do not publish an active
  -- synoptic handoff, so they retain the existing immediate cloud response.
  local tr = V and V.weatherFxTransition or nil
  local targetWxId = tostring((V and V.weatherFxTargetId) or ""):upper()
  local transitionActive = type(tr)=="table" and tr.active==true and targetWxId~=""
  local renderWxId = transitionActive and targetWxId or authoritativeId
  local linkedProfile = wxAtmosProfileKey(authoritativeId)
  if transitionActive then
    local fromKey = wxAtmosProfileKey(authoritativeId) or ((authoritativeId=="CLEAR" or authoritativeId=="SUNNY" or authoritativeId=="HARSH_SUN" or authoritativeId=="HEATWAVE") and "clear") or linkedProfile
    local toKey = wxAtmosProfileKey(targetWxId) or ((targetWxId=="CLEAR" or targetWxId=="SUNNY" or targetWxId=="HARSH_SUN" or targetWxId=="HEATWAVE") and "clear") or fromKey
    local a = fromKey and WEATHER[fromKey] or WEATHER.partly
    local b = toKey and WEATHER[toKey] or a
    weather = CinematicAtmos._blendProfilesInto(CinematicAtmos._transitionProfileScratch,a,b,tonumber(tr.cloudU) or tonumber(tr.u) or 0)
    -- Convective charge is deliberately later than cloud formation. Using the
    -- cloud curve for `storm` would make in-cloud flashes start while the first
    -- drops are still waiting to form.
    weather.storm = lerp(profileNumber(a,"storm"),profileNumber(b,"storm"),tonumber(tr.stormU) or tonumber(tr.u) or 0)
    weatherKey = "wx:"..tostring(authoritativeId)..">"..tostring(targetWxId)
  elseif linkedProfile and WEATHER[linkedProfile] then
    weather, weatherKey = WEATHER[linkedProfile], "wx:" .. linkedProfile
  end
  -- Shallow-copy the profile. WEATHER.* / DYNAMIC_WEATHER.* tables are shared
  -- constants; mutating rainIntensity/fog/etc. in place made INTENSITY soft
  -- (and CLEAR zeroing) permanently decay the base profile so 3D rain died
  -- after 1–2 seconds.
  do
    for k in pairs(weatherScratch) do weatherScratch[k]=nil end
    for k, v in pairs(weather) do weatherScratch[k] = v end
    weather = weatherScratch
  end
  local lightning = lightningFlashFor(weather, ForestAtmos.time)
  if lightning > 0.001 then
    fogColor = mixColor(fogColor, { 0.84, 0.91, 1.00 }, min(0.72, lightning * 0.62))
    rayColor = mixColor(rayColor, { 0.90, 0.95, 1.00 }, min(0.80, lightning * 0.72))
  end
  -- Weather-coloured mist is advected by the SAME world WindEngine as falling
  -- particles and cloud banks. Historically these were fixed vectors (sand
  -- always blew screen/world-right), which made every storm feel mechanically
  -- identical. Direction now veers continuously while each weather keeps its
  -- authored speed/character.
  local wxId = renderWxId
  local mistSpeed = 10.3
  if wxId == "SANDSTORM" then
    fogColor = { 0.90, 0.76, 0.48 }
    mistSpeed = 18.0
  elseif wxId == "DUSTSTORM" then
    fogColor = { 0.78, 0.66, 0.46 }
    mistSpeed = 14.0
  elseif wxId == "ASHFALL" then
    fogColor = { 0.42, 0.42, 0.40 }
    mistSpeed = 4.0
  end
  local windState = nil
  local WE = cachedRequire("WindEngine")
  if WE then
    if WE.peek then windState = WE.peek()
    elseif WE.state then windState = WE.state() end
  end
  local dirX, dirZ, windEnvelope = 0.85, -0.52, 1.0
  local mistAdvect = frameScratch.mistAdvect
  mistAdvect[1],mistAdvect[2]=0,0
  if windState then
    local wx, wz = tonumber(windState.x) or 0, tonumber(windState.z) or 0
    local wl = sqrt(wx*wx + wz*wz)
    if wl > 1e-5 then dirX, dirZ = wx/wl, wz/wl end
    windEnvelope = max(0.08, min(1.25, tonumber(windState.envelope) or 1))
    -- WindEngine advection is intentionally cloud-speed. Mist moves through the
    -- same direction field faster, so scale its integrated displacement rather
    -- than multiplying a changing vector by global time.
    mistAdvect[1]=(tonumber(windState.advectX) or 0) * 18.0
    mistAdvect[2]=(tonumber(windState.advectZ) or 0) * 18.0
  end
  local mistWind = frameScratch.mistWind
  mistWind[1],mistWind[2]=dirX * mistSpeed * windEnvelope,dirZ * mistSpeed * windEnvelope

  -- WEATHER FX IS THE PARTICLE AUTHORITY.
  --
  -- The old embedded cinematic cycle supplied rain/snow intensities of its own.
  -- That meant the cloud profile and Weather FX could disagree: a real RAIN
  -- state could receive zero 3D rain while the cinematic cycle was CLEAR, or a
  -- SNOW state could inherit rain from a cinematic rain profile. 8.0.7 takes the
  -- *live eased WeatherState channel bag* as the authority for all six families.
  -- The discrete Types definition is now only a compatibility fallback when a
  -- host cannot publish live channels. This is what lets clouds lead rain, rain
  -- taper before the deck breaks, and lightning arrive after convection without
  -- a last-frame particle pop at the weather-id commit.
  local channelSnapshot = V and V.weatherFxChannels or nil
  local liveChannels = type(channelSnapshot)=="table"
  local Types = cachedRequire("Types")
  local def = Types and Types.byId and Types.byId[wxId]
  local function resolvedChannel(key)
    if liveChannels then
      local v=tonumber(channelSnapshot[key])
      if v then return v end
    end
    if def and Types and Types.channel then return tonumber(Types.channel(def,key)) or 0 end
    return 0
  end
  if liveChannels or (def and Types.channel) then
    -- These are the exact eased WeatherState channels used by 2D and audio.
    -- Strict 3D no longer reconstructs full-strength precipitation from an id.
    weather.rainIntensity = resolvedChannel("rain")
    weather.snowIntensity = resolvedChannel("snow")
    weather.hailIntensity = min(2.0,resolvedChannel("hail")*1.35)
    weather.sandIntensity = min(2.4,resolvedChannel("sand")*0.80)
    weather.ashIntensity = min(2.0,resolvedChannel("ash")*1.50)
    weather.debrisIntensity = min(2.4,resolvedChannel("debris")*2.10)
    -- The broad ground-mist cards are a FOG renderer, not a generic rain
    -- overlay. RAIN_HEAVY / HEAVY_RAIN / STORM previously inherited the old
    -- cinematic profile's large `fog` scalar even though their Weather FX
    -- catalogue has no fog channel. That produced the translucent curtain /
    -- horizontal banding visible through the heavy-rain screenshot. Keep the
    -- physically useful long-range extinction below, but do not draw explicit
    -- mist/rolling-fog geometry for rain-only storms.
    local authoredFog = resolvedChannel("fog")
    -- Explicit ground mist belongs only to weather definitions that actually
    -- publish the fog channel. Old cinematic profile tables carried large
    -- decorative `fog` values for Snow/Blizzard and several other non-fog
    -- weathers; once live WeatherState became authoritative those stale profile
    -- values leaked out as the reported ground-cloud layer. Kill that leak at
    -- the owner: no authored fog channel means no 3D ground-mist cards or fog
    -- extinction. Snow whiteout remains snow/veil/cloud driven, not fake fog.
    local fogScale=1
    if authoredFog>0.02 then
      local MF=cachedRequire("MesoscaleField")
      local ms=MF and (not MF.ready or MF.ready()) and MF.peek and MF.peek() or nil
      fogScale=ms and tonumber(ms.fogScale) or 1
    end
    weather.fog,weather._mistVisual=CinematicAtmos._mistPolicy(authoredFog,fogScale)
  else
    weather._mistVisual = true
    -- The grain fields are not authored by the old profile tables, so stale
    -- values must still be cleared when no Weather FX catalogue id is present.
    weather.sandIntensity = tonumber(weather.sandIntensity) or 0
    weather.ashIntensity = tonumber(weather.ashIntensity) or 0
    weather.debrisIntensity = tonumber(weather.debrisIntensity) or 0
    weather.hailIntensity = tonumber(weather.hailIntensity) or 0
  end

  local function floorProgress(key)
    if not liveChannels then return 1 end
    local live=max(0,resolvedChannel(key))
    local base=(def and Types and Types.channel) and (tonumber(Types.channel(def,key)) or 0) or 0
    if base<=0.0001 then return live>0.0001 and 1 or 0 end
    return max(0,min(1,live/base))
  end

  -- Authored 3D tuning floors. These keep the established final visual strength
  -- but scale with the live eased channel, so a floor cannot turn a 5% onset
  -- into a full storm on the strict-3D path.
  if wxId == "HAIL" then
    weather.hailIntensity = max(tonumber(weather.hailIntensity) or 0, 1.25*floorProgress("hail"))
    if not transitionActive then weather.snowIntensity = 0; weather.rainIntensity = 0 end
  elseif wxId == "SLEET" then
    weather.hailIntensity = max(tonumber(weather.hailIntensity) or 0, 0.45*floorProgress("hail"))
  end
  if wxId == "SANDSTORM" then
    weather.sandIntensity = max(tonumber(weather.sandIntensity) or 0, 2.35*floorProgress("sand"))
  elseif wxId == "DUSTSTORM" then
    weather.sandIntensity = max(tonumber(weather.sandIntensity) or 0, 1.20*floorProgress("sand"))
  elseif wxId == "ASHFALL" then
    weather.ashIntensity = max(tonumber(weather.ashIntensity) or 0, 1.45*floorProgress("ash"))
  elseif wxId == "GALE" or wxId == "STRONG_WINDS" or wxId == "BRAWL_WIND" or wxId == "FLOCKSTORM" then
    weather.debrisIntensity = max(tonumber(weather.debrisIntensity) or 0, 1.15*floorProgress("debris"))
  elseif wxId == "DRAGONSTORM" then
    weather.sandIntensity = max(tonumber(weather.sandIntensity) or 0, 0.55*floorProgress("sand"))
    weather.debrisIntensity = max(tonumber(weather.debrisIntensity) or 0, 0.45*floorProgress("debris"))
    weather.snowIntensity = max(tonumber(weather.snowIntensity) or 0, 1.8*floorProgress("snow"))
  end

  -- FINITE FRONT CLOUD OWNERSHIP.
  --
  -- A front must never switch the local renderer from CLEAR straight to the
  -- storm profile's sealed deck. `weatherFxSpatialCloud` is the physical cloud
  -- influence at the player, while `weatherFxSpatialLocalized` distinguishes
  -- that finite entity from a manual/config weather selection. Drive BOTH the
  -- cloud amount and the deterministic lattice gate with that continuous value.
  -- As cloudU rises, persistent cells all around the sky cross their own soft
  -- thresholds at different moments; as it falls, they peel away the same way.
  -- No cloud object is spawned from the camera and no stage boundary can fill
  -- the sky in a single frame.
  local spatialLocalized = V and V.weatherFxSpatialLocalized == true
  local spatialCloudRaw = max(0,min(1,tonumber(V and V.weatherFxSpatialCloud) or 1))
  local spatialCloudU = spatialCloudRaw*spatialCloudRaw*(3-2*spatialCloudRaw)
  if spatialLocalized then
    weather.coverage=(tonumber(weather.coverage) or 0)*spatialCloudU
    weather.bank=(tonumber(weather.bank) or 0)*spatialCloudU
    weather.puffs=(tonumber(weather.puffs) or 0)*(.58+.42*spatialCloudU)
    weather.shadow=(tonumber(weather.shadow) or 0)*spatialCloudU
    local authoredGate=tonumber(weather.gate) or .18
    weather.gate=lerp(1.01,authoredGate,spatialCloudU)
    weather.softGate=max(tonumber(weather.softGate) or 0,.10)
    local authoredDeck=weather.deckBlend~=nil and tonumber(weather.deckBlend) or (weather.closedDeck and 1 or 0)
    weather.deckBlend=max(0,min(1,(authoredDeck or 0)*spatialCloudU))
    weather.closedDeck=(weather.closedDeck==true) and spatialCloudU>.985 or false
  end
  weather._spatialCloudU=spatialCloudU
  weather._spatialLocalized=spatialLocalized

  -- A falling-weather profile must own a visible cloud bank when CLOUDS is ON.
  -- This guards unknown/new weather ids and partial host handoffs where the
  -- precipitation channels are live but the profile mapper failed to supply a
  -- cloud-bearing preset. It does not affect CLEAR/SUNNY or CLOUDS=OFF.
  do
    local precip=max(tonumber(weather.rainIntensity) or 0,tonumber(weather.snowIntensity) or 0,
      tonumber(weather.hailIntensity) or 0,tonumber(weather.sandIntensity) or 0,
      tonumber(weather.ashIntensity) or 0)
    if precip>0.02 then
      local cloudAuthority=spatialLocalized and spatialCloudU or 1
      local floorCover=((precip>1.15) and 0.94 or 0.78)*cloudAuthority
      weather.coverage=max(tonumber(weather.coverage) or 0,floorCover)
      weather.puffs=max(tonumber(weather.puffs) or 0,0.82*cloudAuthority)
      weather.bank=max(tonumber(weather.bank) or 0,0.76*cloudAuthority)
    end
  end

  -- Always tag the weather bag so WorldPrecip can classify the weather.
  -- Also mark that CinematicAtmos completed its catalogue pass. WorldPrecip
  -- still has an independent recovery pass if this marker/id ever goes missing.
  weather.wxId = wxId
  weather._transitionActive = transitionActive == true
  weather._sourceWxId = authoritativeId
  weather._targetWxId = targetWxId
  weather._stormTransitionU = transitionActive and (tonumber(tr and tr.stormU) or 0) or 1
  weather._windTransitionU = transitionActive and (tonumber(tr and tr.windU) or 0) or 1
  weather._wxChannelsResolved = liveChannels == true

  -- CLEAR / OFF: hard-zero every precip channel. Sticky fields on the shared
  -- WEATHER profile tables otherwise keep raining/snowing after the player
  -- turns weather off while 3D presentation is enabled.
  if not transitionActive and (wxId == "" or wxId == "CLEAR" or wxId == "SUNNY" or wxId == "OFF"
      or wxId == "HEATWAVE" or wxId == "HARSH_SUN") then
    weather.rainIntensity = 0
    weather.snowIntensity = 0
    weather.hailIntensity = 0
    weather.sandIntensity = 0
    weather.ashIntensity = 0
    weather.debrisIntensity = 0
    weather.fog = 0
  end

  -- Rain / storm family: never carry sticky snowfall into the weather bag.
  -- Snow family: guarantee a real flake intensity so 3D snow always runs.
  do
    local snowy = false
    if wxId:find("SNOW", 1, true) then snowy = true end
    if wxId == "BLIZZARD" or wxId == "THUNDERSNOW" or wxId == "SLEET"
        or wxId == "DRAGONSTORM" or wxId == "WHITEOUT" then
      snowy = true
    end
    if snowy then
      local floorI = 1.4
      if wxId == "BLIZZARD" then floorI = 2.2
      elseif wxId == "WHITEOUT" then floorI = 2.4
      elseif wxId == "THUNDERSNOW" or wxId == "TSNOW" then floorI = 3.0
      elseif wxId == "DRAGONSTORM" then floorI = 1.8
      elseif wxId == "SLEET" then floorI = 0.5
      elseif wxId == "SNOW" or wxId == "SNOW_LIGHT" or wxId == "SNOWY" then floorI = 1.9
      end
      weather.snowIntensity = max(tonumber(weather.snowIntensity) or 0, floorI*floorProgress("snow"))
    elseif not transitionActive then
      weather.snowIntensity = 0
    end
  end

  -- Menu dials: INTENSITY / SAND / DUST / FOG scale particles + fog dens.
  local S = weatherSettings()
  if S and not liveChannels then
    -- Global INTENSITY (soft/normal/heavy) — same dial as 2D State channels.
    if S.intensity and wxId ~= "" and wxId ~= "CLEAR" and wxId ~= "SUNNY"
        and wxId ~= "OFF" and wxId ~= "HEATWAVE" and wxId ~= "HARSH_SUN" then
      local im = S.intensity() or 1
      if im and im ~= 1 then
        if weather.rainIntensity then weather.rainIntensity = weather.rainIntensity * im end
        if weather.snowIntensity then weather.snowIntensity = weather.snowIntensity * im end
        if weather.hailIntensity then weather.hailIntensity = weather.hailIntensity * im end
        if weather.sandIntensity then weather.sandIntensity = weather.sandIntensity * im end
        if weather.ashIntensity then weather.ashIntensity = weather.ashIntensity * im end
        if weather.debrisIntensity then weather.debrisIntensity = weather.debrisIntensity * im end
      end
    end
    if S.rainIntensity then
      local rm = S.rainIntensity() or 1
      if rm <= 0 then weather.rainIntensity = 0; weather._rainExplicitOff = true
      else weather.rainIntensity = (weather.rainIntensity or 0) * rm end
    end
    if S.snowIntensity then
      local sm = S.snowIntensity() or 1
      if sm <= 0 then weather.snowIntensity = 0; weather._snowExplicitOff = true
      else weather.snowIntensity = (weather.snowIntensity or 0) * sm end
    end
    if wxId == "SANDSTORM" and S.sandIntensity then
      local m = S.sandIntensity() or 1
      if m <= 0 then weather.sandIntensity = 0; weather._sandExplicitOff = true
      else weather.sandIntensity = (weather.sandIntensity or 0) * m end
    elseif wxId == "DUSTSTORM" and S.dustIntensity then
      local m = S.dustIntensity() or 1
      if m <= 0 then weather.sandIntensity = 0; weather._sandExplicitOff = true
      else weather.sandIntensity = (weather.sandIntensity or 0) * m end
    end
    if S.fogIntensity then
      local fm = S.fogIntensity() or 1
      if S.fogOff and S.fogOff() then fm = 0 end
      if fm <= 0 then weather.fog = 0 else weather.fog = (weather.fog or 1) * fm end
    end
  end
  if (tonumber(weather.snowIntensity) or 0) > 0.05 then
    weather.snowCover = max(weather.snowCover or 0, min(1.0, (weather.snowIntensity or 0) * 0.35))
  end


  local dens, start, heightK
  if canopy then
    -- Keep only a light extinction bed. The visible weather now comes from
    -- the animated world-space mist volumes below, not a static screen haze.
    dens, start, heightK = 0.00855 * level, 32, 0.042
  else
    -- Stronger long-range extinction; FOG INTENSITY / sand-dust haze scale dens.
    dens, start, heightK = 0.011 * level * (weather.fog or 1.0), 22, 0.045
  end
  -- Sand/dust intensity: 500% ≈ 25% remaining visibility (heavy haze, not darken).
  if wxId == "SANDSTORM" or wxId == "DUSTSTORM" then
    -- Desert whiteout: baseline haze is already heavy; dial pushes harder.
    local haze = (wxId == "SANDSTORM") and 0.55 or 0.15
    local S = weatherSettings()
    if S then
      if wxId == "SANDSTORM" and S.sandHaze then
        haze = max(haze, S.sandHaze() or 0)
      elseif wxId == "DUSTSTORM" and S.dustHaze then
        haze = S.dustHaze()
      end
      -- SAND GROUND FOG FOLLOWS THE SAND INTENSITY DIAL.
      --
      -- The haze above is a fixed baseline plus its own separate haze setting,
      -- so turning sand intensity down thinned the PARTICLES and left the
      -- ground fog exactly as thick -- the storm went quiet while the air
      -- stayed opaque. The fog is part of the sandstorm and should rise and
      -- fall with it.
      --
      -- Scaled, not replaced: the haze setting still sets the ceiling, the
      -- intensity dial scales it. At 0 the fog goes with the particles, which
      -- is what "sand off" should mean.
      local im = nil
      if wxId == "SANDSTORM" and S.sandIntensity then im = S.sandIntensity()
      elseif wxId == "DUSTSTORM" and S.dustIntensity then im = S.dustIntensity() end
      im = tonumber(im)
      if im then
        if im <= 0 then
          haze = 0
        else
          -- The dial runs past 1 for "more than default"; keep the fog from
          -- running away at the top of the range.
          haze = haze * min(1.6, im)
        end
      end
    end
    -- dens / start: pull fog in close and thicken so mid-range terrain vanishes.
    if wxId == "SANDSTORM" then
      dens = dens * (0.85 + haze * 10.5)
      start = max(3, start - haze * 22)
      heightK = heightK * (1.2 + haze * 2.4)
    else
      dens = dens * (0.35 + haze * 8.5)
      start = max(6, start - haze * 14)
      heightK = heightK * (1.0 + haze * 1.8)
    end
  end
  local lightIntensity=lightScale()*(weather.rays or 1.0)
  -- 8.1.15: god rays are SOLAR optics, not "whichever body currently owns
  -- the shadow map". At dawn the moon may still be the stronger direct light,
  -- which used to hold the shafts back and then flip their direction abruptly.
  -- CelestialEngine now gives us a limb-aware continuous solar ramp.
  CinematicAtmos._solarRayRamp=1; CinematicAtmos._solarRayStrength=1
  CinematicAtmos._sunDiscVisibility=1; CinematicAtmos._sunAltitudeDeg=45
  CinematicAtmos._sunDirX,CinematicAtmos._sunDirY,CinematicAtmos._sunDirZ=0,1,0
  CinematicAtmos._sunShearX=nil; CinematicAtmos._sunShearZ=nil; CinematicAtmos._sunShadowAuthority=true
  do
    local E=cachedRequire("CelestialEngine")
    if E and E.state then
      local ok2,st=V.safeCall(E.state)
      if ok2 and st then
        CinematicAtmos._solarRayRamp=max(0,min(1,tonumber(st.solarRayRamp) or 0))
        CinematicAtmos._solarRayStrength=max(0,min(1,tonumber(st.solarRayStrength) or 0))
        CinematicAtmos._sunDiscVisibility=max(0,min(1,tonumber(st.solarDiscVisibility) or 0))
        CinematicAtmos._sunAltitudeDeg=tonumber(st.sun and st.sun.altitudeDeg) or -90
        if st.sun then
          CinematicAtmos._sunDirX,CinematicAtmos._sunDirY,CinematicAtmos._sunDirZ=tonumber(st.sun.dx) or 0,tonumber(st.sun.dy) or 0,tonumber(st.sun.dz) or 0
          CinematicAtmos._sunShearX=max(-3,min(3,-CinematicAtmos._sunDirX/max(.055,CinematicAtmos._sunDirY)))
          CinematicAtmos._sunShearZ=max(-3,min(3,-CinematicAtmos._sunDirZ/max(.055,CinematicAtmos._sunDirY)))
        end
        CinematicAtmos._sunShadowAuthority=st.mainLight and st.mainLight.kind=="sun" or false
        lightIntensity=lightIntensity*CinematicAtmos._solarRayStrength
      end
    end
  end

  -- Weather FX 7 feeds the proven cloud/precip renderer with the new bounded
  -- 3D volume model and environmental light budget. These are descriptors, not
  -- a second renderer, so visual ownership remains single-path.
  local volumeWeather=nil; local environmentLight=nil
  do
    local VW=cachedRequire("VolumetricRenderer"); if VW and VW.peek then local okV,v=V.safeCall(VW.peek); if okV then volumeWeather=v end elseif VW and VW.sample then local okV,v=V.safeCall(VW.sample); if okV then volumeWeather=v end end
    local DL=cachedRequire("UnifiedLighting"); if DL and DL.peek then local okL,v=V.safeCall(DL.peek); if okL then environmentLight=v end elseif DL and DL.sample then local okL,v=V.safeCall(DL.sample); if okL then environmentLight=v end end
  end
  if volumeWeather then
    lightIntensity=lightIntensity*max(.58,min(1.08,tonumber(volumeWeather.lightTransmission) or 1))
  end
  if environmentLight then
    lightIntensity=lightIntensity*max(.62,min(1.18,(tonumber(environmentLight.finalDiffuse) or tonumber(environmentLight.diffuse) or .72)/.72))
  end

  local weatherInteraction=nil;local postRainShaft=0
  do
    local WI=cachedRequire("WeatherWorldInteraction")
    if WI and WI.peek then local okI,v=V.safeCall(WI.peek);if okI then weatherInteraction=v end end
    postRainShaft=max(0,min(1,tonumber(weatherInteraction and weatherInteraction.postRainShaft) or 0))
    -- Existing ray geometry/cloud transmission remain authoritative; recent rain
    -- only raises the optical gain while sunlight is actually breaking through.
    lightIntensity=lightIntensity*(1+.55*postRainShaft)
  end

  local out=frameScratch
  out.volumeWeather,out.environmentLight=volumeWeather,environmentLight
  out.level,out.canopy=level,canopy
  out.fogColor,out.rayColor=fogColor,rayColor
  out.mistWind,out.mistAdvect=mistWind,mistAdvect
  out.windState,out.wxId=windState,wxId
  out.weather,out.weatherKey=weather,weatherKey
  out.weatherInteraction,out.postRainShaft=weatherInteraction,postRainShaft
  out.gustFront=weatherInteraction and weatherInteraction.gustFront or nil
  out.lightning,out.lightIntensity=lightning,lightIntensity
  out.solarRayRamp,out.solarRayStrength=CinematicAtmos._solarRayRamp,CinematicAtmos._solarRayStrength
  out.sunDiscVisibility,out.sunAltitudeDeg=CinematicAtmos._sunDiscVisibility,CinematicAtmos._sunAltitudeDeg
  out.sunDirX,out.sunDirY,out.sunDirZ=CinematicAtmos._sunDirX,CinematicAtmos._sunDirY,CinematicAtmos._sunDirZ
  out.sunShearX,out.sunShearZ=CinematicAtmos._sunShearX,CinematicAtmos._sunShearZ
  out.sunShadowAuthority=CinematicAtmos._sunShadowAuthority
  local fog=out.fog
  fog.color,fog.density,fog.start,fog.heightK=fogColor,dens,start,heightK
  -- `startFromFocus` is consumed by Voxel3D.beginScene. Keep the exact
  -- established values without allocating a new fog table each frame.
  fog.startFromFocus=canopy and -12 or -4
  out.cloudShadow=(canopy and 0.055 or 0.13)*level*(weather.shadow or 1.0)
                  *(1.0-min(0.72,lightning*0.72))
                  *(volumeWeather and (tonumber(volumeWeather.shadowScale) or 1) or 1)
  out.wind[1],out.wind[2]=0.021,-0.014
  out.time=ForestAtmos.time
  return out
end

-- ---------- reflective rain puddles
--
-- W7.5: dedicated mirrored-camera planar reflections.  W7.1/W7.2 proved the
-- puddle geometry itself was fine but the phone did not contribute usable
-- readable-depth SSR, leaving only the grey/sky fallback visible.  The new
-- path copies the fully rendered scene COLOUR (no depth sampling) immediately
-- before the puddles draw, then maps a vertically inverted, perspective-aware
-- window of that real scene onto each horizontal puddle.  Buildings, trees,
-- characters and sky therefore produce recognisable moving reflection detail
-- on every renderer that can sample an ordinary Canvas -- the same capability
-- already used throughout Dramatic Shape.
--
-- Puddles remain map-wide and depth-tested by hardware.  Rain perturbs the
-- reflection window slightly; after rain it settles into a clearer mirror.
-- The old procedural sky is retained only as a fallback outside the captured
-- frame and as a very faint base so reflection failure can never erase the
-- puddle geometry entirely.
local PUDDLE_BASE_SHADER = [[
  varying vec2 vLocal;
  varying vec3 vWorld;
  varying float vAlpha;
  varying float vSeed;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  attribute vec4 PuddleData;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 w = vec4(vertex_position.xyz, 1.0);
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }
    vLocal = PuddleData.xy;
    vAlpha = PuddleData.z;
    vSeed = PuddleData.w;
    vWorld = w.xyz;
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform vec3 eye;
  uniform vec3 skyTop;
  uniform vec3 skyMid;
  uniform vec3 skyHaze;
  uniform vec3 bodyDir;
  uniform vec3 bodyColor;
  uniform float bodyStrength;
  uniform float rainAmount;
  uniform float flashAmount;
  uniform float wetness;
  uniform float time;

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float scale = mix(0.06, 1.0, pow(clamp(wetness, 0.0, 1.0), 0.63));
    vec2 local = vLocal / max(scale, 0.03);
    float d = length(local);
    float warp = 0.065 * sin(local.x * 7.2 + local.y * 5.7 + vSeed * 41.0)
               + 0.040 * sin(local.x * 12.0 - local.y * 8.0 + vSeed * 19.0);
    float edge = 1.0 - smoothstep(0.82 + warp, 1.03 + warp, d);
    if (edge <= 0.002) discard;

    vec3 V = normalize(eye - vWorld);
    vec3 R = reflect(-V, vec3(0.0, 1.0, 0.0));
    float elev = clamp(R.y, 0.0, 1.0);
    vec3 sky = mix(skyHaze, skyMid, smoothstep(0.03, 0.46, elev));
    sky = mix(sky, skyTop, smoothstep(0.46, 0.96, elev));
    float spec = pow(max(0.0, dot(normalize(R), normalize(bodyDir))), 54.0) * bodyStrength;
    float ring = sin(d * 30.0 - time * 9.0 + vSeed * 31.0);
    sky *= 0.88 + ring * rainAmount * 0.030 * edge;
    // Stylised shallow-water colour: enough sky/gloss to read as wet, but
    // intentionally restrained so the character reflection remains legible.
    vec3 water = mix(vec3(0.34, 0.57, 0.73), sky, 0.46);
    water += bodyColor * spec * 0.20;
    water = mix(water, vec3(0.82, 0.91, 1.00), flashAmount * 0.36);
    float fresnel = 0.42 + 0.30 * pow(1.0 - max(0.0, V.y), 2.0);
    float wetAlpha = smoothstep(0.015, 0.16, wetness);
    float a = clamp(vAlpha * edge * wetAlpha * fresnel * 0.62, 0.0, 0.48);
    return vec4(water, a) * color;
  }
#endif
]]

local PUDDLE_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "PuddleData", "float", 4 },
}
local puddleBaseShaderState, puddleMesh = nil, nil
local puddleMeshKey = nil

local function puddleBaseShader()
  if puddleBaseShaderState ~= nil then return puddleBaseShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, PUDDLE_BASE_SHADER)
  puddleBaseShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] puddle base shader refused: " .. tostring(sh)) end
  return puddleBaseShaderState or nil
end

local function flatGroundAt(map, cx, cy)
  if not (map and map.inBounds and map:inBounds(cx, cy)) then return nil end
  local shapes = TileShape.forMap(map)
  local sh = shapes and shapes[map:cellTile(cx, cy)]
  if not sh then return nil end
  if sh.art == "stair" or sh.art == "water" then return nil end
  local h = tonumber(sh.h) or 0
  -- Keep puddles on ordinary ground. Raised blocks are commonly trees,
  -- ledges/building bases; their top surfaces are not walkable wet ground.
  if abs(h) > 0.001 then return nil end
  return 0.12
end

local function mapCellDims(map)
  if not map then return 0, 0 end
  local w = tonumber(map.widthCells)
  local h = tonumber(map.heightCells)
  -- Live Gen1Recomp map objects do not consistently expose widthCells /
  -- heightCells even though the test fixtures do.  map.def is authoritative:
  -- one map block is 32 world pixels = two 16px puddle cells.
  if (not w or w <= 0) and map.def then
    local bw = tonumber(map.def.width)
    if bw and bw > 0 then w = bw * 2 end
  end
  if (not h or h <= 0) and map.def then
    local bh = tonumber(map.def.height)
    if bh and bh > 0 then h = bh * 2 end
  end
  return math.max(0, math.floor(w or 0)), math.max(0, math.floor(h or 0))
end

local function puddleWorldKey(map, neighbors)
  local out = {
    "sparse-v4-sizes",
    tostring(map and (map.id or map) or "nil"),
    tostring(select(1, mapCellDims(map))),
    tostring(select(2, mapCellDims(map))),
  }
  for _, nb in ipairs(neighbors or {}) do
    out[#out + 1] = table.concat({
      tostring(nb.map and (nb.map.id or nb.map) or "nil"),
      tostring(nb.ox or 0), tostring(nb.oy or 0),
      tostring(select(1, mapCellDims(nb.map))),
      tostring(select(2, mapCellDims(nb.map))),
    }, ":")
  end
  return table.concat(out, "|")
end

local function appendMapPuddles(verts, indices, q, map, ox, oz)
  if not map then return q end
  local mw, mh = mapCellDims(map)
  if mw <= 0 or mh <= 0 then return q end
  ox, oz = ox or 0, oz or 0
  local corners = { {-1,-1}, {1,-1}, {1,1}, {-1,1} }
  -- Sparse, non-adjacent puddles across the whole map (min 2 cells apart).
  local occupied = {}
  local function taken(cx, cz)
    return occupied[cx .. ":" .. cz]
  end
  local function mark(cx, cz)
    for dz = -2, 2 do
      for dx = -2, 2 do
        occupied[(cx + dx) .. ":" .. (cz + dz)] = true
      end
    end
  end
  for cz = 0, mh - 1 do
    for cx = 0, mw - 1 do
      local chance = hash2(cx, cz, 901)
      -- Lower density; skip if too close to an existing puddle.
      if chance < 0.055 and not taken(cx, cz) then
        local gy = flatGroundAt(map, cx, cz)
        if gy then
          mark(cx, cz)
          local seed = hash2(cx, cz, 902)
          local wx = ox + cx * 16 + 8 + (hash2(cx, cz, 903) * 2 - 1) * 3.0
          local wz = oz + cz * 16 + 8 + (hash2(cx, cz, 904) * 2 - 1) * 3.0
          local rx = (7.0 + hash2(cx, cz, 905) * 8.0) * 1.5
          local rz = rx * (0.55 + hash2(cx, cz, 906) * 0.28)
          local alpha = 0.64 + hash2(cx, cz, 907) * 0.20
          for i = 1, 4 do
            local c = corners[i]
            verts[#verts + 1] = {
              wx + c[1] * rx, gy, wz + c[2] * rz,
              c[1], c[2], alpha, seed,
            }
          end
          pushQuad(indices, q)
          q = q + 1
        end
      end
    end
  end
  return q
end

local function appendMapSmallPuddles(verts, indices, q, map, ox, oz)
  -- GALE: many tiny reflective flecks (10% of normal puddle radius).
  if not map then return q end
  local mw, mh = mapCellDims(map)
  if mw <= 0 or mh <= 0 then return q end
  ox, oz = ox or 0, oz or 0
  local corners = { {-1,-1}, {1,-1}, {1,1}, {-1,1} }
  local occupied = {}
  local function taken(cx, cz) return occupied[cx .. ":" .. cz] end
  local function mark(cx, cz)
    for dz = -1, 1 do
      for dx = -1, 1 do occupied[(cx + dx) .. ":" .. (cz + dz)] = true end
    end
  end
  for cz = 0, mh - 1 do
    for cx = 0, mw - 1 do
      local chance = hash2(cx, cz, 911)
      if chance < 0.22 and not taken(cx, cz) then
        local gy = flatGroundAt(map, cx, cz)
        if gy then
          mark(cx, cz)
          local seed = hash2(cx, cz, 912)
          local wx = ox + cx * 16 + 8 + (hash2(cx, cz, 913) * 2 - 1) * 5.0
          local wz = oz + cz * 16 + 8 + (hash2(cx, cz, 914) * 2 - 1) * 5.0
          local rx = (7.0 + hash2(cx, cz, 915) * 8.0) * 0.28
          local rz = rx * (0.55 + hash2(cx, cz, 916) * 0.28)
          local alpha = 0.55 + hash2(cx, cz, 917) * 0.30
          for i = 1, 4 do
            local c = corners[i]
            verts[#verts + 1] = {
              wx + c[1] * rx, gy, wz + c[2] * rz,
              c[1], c[2], alpha, seed,
            }
          end
          pushQuad(indices, q)
          q = q + 1
        end
      end
    end
  end
  return q
end

local function ensurePuddleMesh(map, neighbors)
  local key = puddleWorldKey(map, neighbors)
  -- GALE small puddles cycle in 2D Draw only (1s respawn). Skip static 3D mesh.
  local gale = (tostring(snowState.wxId or ""):upper() == "GALE")
  if gale then
    puddleMesh, puddleMeshKey = nil, key .. "|gale-skip"
    return nil
  end
  if puddleMesh and puddleMeshKey == key then return puddleMesh end

  local verts, indices, q = {}, {}, 0
  q = appendMapPuddles(verts, indices, q, map, 0, 0)
  for _, nb in ipairs(neighbors or {}) do
    q = appendMapPuddles(verts, indices, q, nb.map, nb.ox or 0, nb.oy or 0)
  end
  if #verts == 0 then
    puddleMesh, puddleMeshKey = nil, key
    return nil
  end

  local ok, mesh = V.safeCall(love.graphics.newMesh, PUDDLE_FORMAT, verts, "triangles", "static")
  if not (ok and mesh) then return nil end
  V.safeCall(mesh.setVertexMap, mesh, indices)
  puddleMesh, puddleMeshKey = mesh, key
  return puddleMesh
end

local function puddleSkyColors(frame)
  local bands = Sky.bands() or {}
  V.safeCall(function()
    local E=V.require("CelestialEngine")
    if E and E.applySkyBands then bands=E.applySkyBands(bands) or bands end
  end)
  local top = bands[1] or {0.20,0.42,0.76}
  local mid = bands[max(1, floor((#bands + 1) * 0.55))] or top
  local haze = bands[#bands] or mid
  local w = frame.weather or {}
  if w.skyColor and (w.skyBlend or 0) > 0 then
    local b = min(1, max(0, w.skyBlend or 0))
    top = mixColor(top, w.skyColor, b * 0.90)
    mid = mixColor(mid, w.skyColor, b * 0.82)
    haze = mixColor(haze, w.skyColor, b * 0.72)
  end
  return top, mid, haze
end

local function sendPuddleCommon(sh, Voxel3D, frame, wetness)
  V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
  V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
  V.safeCall(sh.send, sh, "eye", Voxel3D.eye or CinematicAtmos._worldUp)
  V.safeCall(sh.send, sh, "wetness", wetness)
  V.safeCall(sh.send, sh, "time", ForestAtmos.time)
  local top, mid, haze = puddleSkyColors(frame)
  V.safeCall(sh.send, sh, "skyTop", top)
  V.safeCall(sh.send, sh, "skyMid", mid)
  V.safeCall(sh.send, sh, "skyHaze", haze)
  -- Unified celestial authority: water/wet surfaces receive the same body
  -- direction, colour and strength as world shadows and atmosphere.
  local bdx,bdy,bdz=0,1,0; local bodyColor=frame.rayColor; local strength=.25
  do
    local ok,E=V.safeCall(V.require,"CelestialEngine")
    if ok and E and E.state then
      local ok2,st=V.safeCall(E.state)
      if ok2 and st and st.mainLight then
        local b=st.mainLight; bdx,bdy,bdz=b.dx or 0,b.dy or 1,b.dz or 0
        bodyColor=b.color or bodyColor; strength=st.directLight or strength
      end
    end
  end
  local b3=CinematicAtmos._uniformScratch.body3; b3[1],b3[2],b3[3]=bdx,bdy,bdz
  V.safeCall(sh.send,sh,"bodyDir",b3)
  V.safeCall(sh.send,sh,"bodyColor",bodyColor)
  V.safeCall(sh.send,sh,"bodyStrength",max(.03,min(1,strength)))
  V.safeCall(sh.send, sh, "rainAmount", min(1, max(0, frame.weather.rainIntensity or 0)))
  V.safeCall(sh.send, sh, "flashAmount", min(1, max(0, frame.lightning or 0)))
end

local function drawPuddles(Voxel3D, frame, map, neighbors)
  local wetness = puddleWetnessFor(frame.weather)
  -- Snow packs hide reflective water; avoid double-drawing wet + white.
  local snow = snowState.cover or 0
  if snow > 0.35 then
    wetness = wetness * max(0.0, 1.0 - (snow - 0.35) / 0.65)
  end
  if wetness <= 0.015 then return end
  local mesh = ensurePuddleMesh(map, neighbors)
  if not mesh then return end

  local base = puddleBaseShader()
  if not base then return end
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(base) then
    sendPuddleCommon(base, Voxel3D, frame, wetness)
    V.safeCall(love.graphics.draw, mesh)
    Voxel3D.endEffect()
  end
end

-- Ground snow pack mesh draw disabled: the shared puddle shader path produced
-- a visible pink line artifact on some hosts. Cover state still updates so a
-- dedicated snow pack pass can be restored later without redoing weather logic.
local function drawSnowPacks(Voxel3D, frame, map, neighbors, outdoor)
  return
end

-- W7.6: intentionally stylised reflections.  Android repeatedly proved that
-- scene-wide mirror techniques were either unavailable or visually unstable.
-- Instead, use the Gen-2 visual language: when Red/NPCs stand beside a puddle,
-- draw their CURRENT sprite frame as a flattened, inverted-looking ground
-- reflection extending inward from the puddle edge.  It is still 3D world
-- geometry and depth tested, but the image is simple and instantly readable.
local function puddleDescAt(map, cx, cz, ox, oz, reuse)
  if not map then return nil end
  local mw, mh = mapCellDims(map)
  if cx < 0 or cz < 0 or cx >= mw or cz >= mh then return nil end
  local chance = hash2(cx, cz, 901)
  if chance >= 0.175 then return nil end
  local gy = flatGroundAt(map, cx, cz)
  if not gy then return nil end
  ox, oz = ox or 0, oz or 0
  local seed = hash2(cx, cz, 902)
  local wx = ox + cx * 16 + 8 + (hash2(cx, cz, 903) * 2 - 1) * 4.2
  local wz = oz + cz * 16 + 8 + (hash2(cx, cz, 904) * 2 - 1) * 4.2
  local rx = 9.0 + hash2(cx, cz, 905) * 11.0
  local rz = rx * (0.58 + hash2(cx, cz, 906) * 0.30)
  local out=reuse or {}
  out.wx,out.wz,out.rx,out.rz,out.y,out.seed=wx,wz,rx,rz,gy,seed
  return out
end

local function nearestPuddle(map, neighbors, wx, wz)
  local best, bestScore = nil, 1e9
  local function scan(one, ox, oz)
    if not one then return end
    ox, oz = ox or 0, oz or 0
    local lx, lz = wx - ox, wz - oz
    local cx0, cz0 = floor(lx / 16), floor(lz / 16)
    for dz = -2, 2 do
      for dx = -2, 2 do
        local p = puddleDescAt(one, cx0 + dx, cz0 + dz, ox, oz)
        if p then
          local ex, ez = wx - p.wx, wz - p.wz
          local ell = sqrt((ex / p.rx)^2 + (ez / p.rz)^2)
          -- Search generously around the feet so we can find the nearest
          -- candidate cheaply. W7.7 applies the strict inside-water test at
          -- draw time; merely being beside this candidate is not sufficient.
          if ell <= 1.42 and ell < bestScore then
            best, bestScore = p, ell
          end
        end
      end
    end
  end
  scan(map, 0, 0)
  for _, nb in ipairs(neighbors or {}) do scan(nb.map, nb.ox or 0, nb.oy or 0) end
  return best, bestScore
end

local function reflectionFrameFor(def, facing, phase, flip)
  local SR = require("src.render.SpriteRenderer")
  local frame, mirror = 0, false
  if (def.frames or 1) > 1 then
    frame = (def.walker and phase == 1) and SR.WALK[facing] or SR.STAND[facing]
    mirror = facing == "right"
      or ((facing == "down" or facing == "up") and phase == 1 and flip)
  end
  return frame, mirror
end

CinematicAtmos._puddleReflectionOut=CinematicAtmos._puddleReflectionOut or {}
CinematicAtmos._puddleReflectionPool=CinematicAtmos._puddleReflectionPool or {}
local function puddlesNearReflection(map, neighbors, wx, wz, radius)
  -- 8.2.6 wet-weather phone path: this scan runs once per reflected character
  -- every frame. Reuse the result/candidate tables instead of allocating one
  -- descriptor per nearby puddle and feeding the mobile GC during rain.
  local out=CinematicAtmos._puddleReflectionOut
  for i=#out,1,-1 do out[i]=nil end
  local pool=CinematicAtmos._puddleReflectionPool
  local poolN=0
  radius = radius or 42.0
  local function scan(one, ox, oz)
    if not one then return end
    ox, oz = ox or 0, oz or 0
    local lx, lz = wx - ox, wz - oz
    local cx0, cz0 = floor(lx / 16), floor(lz / 16)
    local cells = max(2, math.ceil((radius + 22) / 16))
    for dz = -cells, cells do
      for dx = -cells, cells do
        local slot=pool[poolN+1]
        if not slot then slot={};pool[poolN+1]=slot end
        local p = puddleDescAt(one, cx0 + dx, cz0 + dz, ox, oz, slot)
        if p then
          local ddx, ddz = p.wx - wx, p.wz - wz
          local reach = radius + max(p.rx, p.rz)
          if ddx*ddx + ddz*ddz <= reach*reach then
            poolN=poolN+1
            out[#out + 1] = p
          end
        end
      end
    end
  end
  scan(map, 0, 0)
  for _, nb in ipairs(neighbors or {}) do scan(nb.map, nb.ox or 0, nb.oy or 0) end
  return out
end

-- W7.8: continuous under-map reflection + puddle-as-mask.
--
-- The reflected card exists conceptually for EVERY posed character on EVERY
-- frame.  No "touch puddle" test turns it on.  We project the current sprite
-- frame from the character's feet along the camera-ground mirror direction,
-- then draw that same card once through each nearby puddle mask.  The scene
-- shader discards every fragment outside the puddle's authored water shape.
--
-- This is the important visual difference from W7.6/W7.7: approaching a
-- puddle does not cross an activation threshold.  The water progressively
-- reveals whichever part of the already-existing reflection lies beneath it,
-- exactly like cutting holes in the map to a reflection layer underneath.
local function drawSpriteReflections(Voxel3D, frame, map, neighbors, posed)
  if not (posed and Voxel3D.eye) then return end
  -- Current Battle Art Voxel Fork 1.10.4 intentionally does not expose the
  -- puddleMask shader seam used by the older 1.7 compatibility bridge. The
  -- reflection is cosmetic and already lives in its own safe pass: feature-
  -- detect that host capability and decline only this subpass instead of
  -- throwing on every wet frame. WorldPrecip/puddles/fog/rays continue.
  if type(Voxel3D.puddleMask) ~= "function" then return false end
  local wetness = puddleWetnessFor(frame.weather)
  if wetness <= 0.04 then return end

  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  V.safeCall(love.graphics.setColor, 0.70, 0.86, 0.94, 0.54 * min(1, wetness * 1.18))
  Voxel3D.glass(false)
  Voxel3D.seams(false)

  for _, p in ipairs(posed) do
    if p.sprite and p.sprite.def and (p.lift or 0) < 1.0 then
      local footX, footZ = p.px + 8, p.py + 8
      local dirX, dirZ = (Voxel3D.eye[1] or footX) - footX,
                         (Voxel3D.eye[3] or footZ) - footZ
      local dl = sqrt(dirX*dirX + dirZ*dirZ)
      if dl > 0.001 then
        dirX, dirZ = dirX / dl, dirZ / dl

        local def = p.sprite.def
        local frameIndex, mirror = reflectionFrameFor(def, p.facing or "down", p.phase or 0, p.flip)
        local mesh = SpriteBillboards.mesh(def, frameIndex)
        if mesh then
          local tex = p.sprite:resolveImage()
          if p.colors and not def.trueColor then
            tex = TerrainAtlas.forSprite(def.image, p.colors) or tex
          end

          -- One persistent 16x16 ground reflection, hinged at the feet and
          -- extending toward the camera.  It is deliberately NOT resized to
          -- whichever puddle happens to reveal it; that was the old telltale
          -- attachment behaviour.  Water only masks this fixed projection.
          local yaw = math.atan2(dirX, dirZ)
          local puddles = puddlesNearReflection(map, neighbors, footX, footZ, 23.0)
          for _, puddle in ipairs(puddles) do
            -- Cheap overlap rejection before asking the GPU to apply the
            -- precise irregular ellipse.  The reflected card occupies a
            -- short capsule from the feet toward the camera.
            local midX, midZ = footX + dirX * 8, footZ + dirZ * 8
            local dx, dz = puddle.wx - midX, puddle.wz - midZ
            local reach = max(puddle.rx, puddle.rz) + 12.0
            if dx*dx + dz*dz <= reach*reach then
              local m = Mat4.translate(footX, puddle.y + 0.055, footZ)
              m = Mat4.mul(m, Mat4.rotateY(yaw))
              m = Mat4.mul(m, Mat4.rotateX(math.pi / 2))
              if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
              m = Mat4.mul(m, Mat4.translate(-8, 0, 0))

              Voxel3D.puddleMask(puddle, wetness)
              Voxel3D.flatten({0.47, 0.68, 0.78}, 0.30)
              Voxel3D.draw(mesh, tex, m, 0)
              Voxel3D.flatten(nil)
              Voxel3D.puddleMask(nil)
            end
          end
        end
      end
    end
  end

  Voxel3D.puddleMask(nil)
  Voxel3D.seams(true)
  Voxel3D.glass(true)
  V.safeCall(love.graphics.setColor, 1, 1, 1, 1)
end

-- ---------- ground mist

local MIST_SHADER = [[
  varying vec2 vLocal;
  varying float vPhase;
  varying float vAlpha;
  varying vec2 vWorld;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  uniform vec3 axisR;
  uniform vec2 mistWind;
  uniform vec2 mistAdvect;
  uniform float time;
  attribute vec4 MistData;   // local x, local y, phase, alpha
  attribute vec4 MistShape;  // half width, height, drift, rate
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float ph = MistData.z;
    float rt = MistShape.w;
    vec3 base = vertex_position.xyz;
    float t = time * rt + ph;
    // Large, slow horizontal excursions make the bodies visibly roll across
    // the world. Two incommensurate motions avoid a repetitive pendulum read.
    float roll1 = sin(t * 0.71) * MistShape.z;
    float roll2 = sin(t * 0.29 + ph * 1.63) * MistShape.z * 0.46;
    base.x += roll1 + roll2 * 0.62;
    base.z += cos(t * 0.53 + ph * 1.91) * MistShape.z * 0.78
            + roll2 * 0.44;
    base.x += mistWind.x * sin(time * 0.055 + ph) * 2.2;
    base.z += mistWind.y * sin(time * 0.047 + ph * 0.77) * 2.2;
    base.y += sin(t * 0.37 + ph) * 2.2;
    vLocal = MistData.xy;
    vPhase = ph;
    vAlpha = MistData.w;
    vec4 w = vec4(base + axisR * (MistData.x * MistShape.x)
                       + vec3(0.0, MistData.y * MistShape.y, 0.0), 1.0);
    vWorld = w.xz;
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform vec3 mistColor;
  uniform vec2 mistWind;
  uniform vec2 mistAdvect;
  uniform float alphaScale;
  uniform float time;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float sx = vLocal.x;
    float x = abs(sx);
    float y = clamp(vLocal.y, 0.0, 1.0);
    float floorFade = smoothstep(0.0, 0.06, y);

    // The A5 field moved internally but kept a largely fixed outer silhouette,
    // which the eye reads as haze. A6 makes the silhouette itself travel and
    // billow. The top of every bank is a set of waves moving at different
    // speeds, so shoulders rise, fold and disappear while the player stands
    // still instead of the whole translucent body merely sliding sideways.
    vec2 adv = vWorld + mistAdvect;
    float travel = adv.x * 0.022 + adv.y * 0.014
                   - time * 0.34 + vPhase;
    float crest = 0.53
      + 0.13 * sin(travel)
      + 0.075 * sin(travel * 1.83 + time * 0.16 + vPhase * 0.7)
      + 0.055 * sin(sx * 8.0 - time * 0.29 + vPhase * 1.9);
    float crown = 1.0 - smoothstep(crest - 0.10, crest + 0.11, y);
    float sideEdge = 0.86 + 0.08 * sin(y * 5.0 + time * 0.23 + vPhase);
    float side = 1.0 - smoothstep(sideEdge - 0.30, sideEdge, x);

    // Three advected scales keep the interior turbulent rather than pulsing as
    // one sheet. Their time terms are deliberately much faster than A5: on a
    // stationary tree edge the density should be visibly different within a
    // few seconds, not merely detectable over half a minute.
    float n1 = 0.5 + 0.5 * sin(adv.x * 0.030 + adv.y * 0.019
                               - time * 0.29 + vPhase);
    float n2 = 0.5 + 0.5 * sin(adv.x * 0.061 - adv.y * 0.044
                               + time * 0.21 + vPhase * 2.37);
    float n3 = 0.5 + 0.5 * sin((adv.x + adv.y) * 0.016
                               - time * 0.17 + vPhase * 0.53);
    float n = n1 * 0.42 + n2 * 0.34 + n3 * 0.24;
    float body = 0.24 + 0.76 * smoothstep(0.34, 0.67, n);

    // A travelling corkscrew pattern hollows and refills parts of the bank.
    // Because its phase couples horizontal position to height, bright lobes
    // appear to curl upward and over darker pockets: the visual cue missing
    // from A5's otherwise-volumetric fog.
    float curlPhase = sx * 7.2 + y * 9.0 - time * 0.52 + vPhase * 1.41;
    float curlA = 0.5 + 0.5 * sin(curlPhase + sin(travel * 0.73) * 1.35);
    float curlB = 0.5 + 0.5 * sin(sx * 11.0 - y * 6.5
                                  + time * 0.37 + vPhase * 2.1);
    float curl = 0.50 + 0.50 * smoothstep(0.28, 0.78,
                                          curlA * 0.64 + curlB * 0.36);

    float a = vAlpha * alphaScale * side * floorFade * crown * body * curl;
    return vec4(mistColor, a) * color;
  }
#endif
]]

local MIST_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "MistData", "float", 4 },
  { "MistShape", "float", 4 },
}

local mistShaderState, mistMesh = nil, nil

local function mistShader()
  if mistShaderState ~= nil then return mistShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, MIST_SHADER)
  mistShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] cinematic mist shader refused: " .. tostring(sh)) end
  return mistShaderState or nil
end

local function buildMistVertices(Voxel3D, frame)
  local f = Voxel3D.focus
  if not f then return nil, nil end
  local level = frame.level
  local cell = 66
  local radius = level > 0.9 and 4 or 3
  local verts=CinematicAtmos._mistVerts or {}; CinematicAtmos._mistVerts=verts
  local rows=CinematicAtmos._mistRows or {}; CinematicAtmos._mistRows=rows
  local indices=CinematicAtmos._mistIndices or {}; CinematicAtmos._mistIndices=indices
  local oldV=#verts; for i=#indices,1,-1 do indices[i]=nil end
  local q,n = 0,0
  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
    local h = hash2(ix, iz, 1)
    -- Density per WORLD CELL is unchanged from A6. Landscape gets more cells
    -- because it sees more world, rather than making every card more opaque.
    local count = (level > 0.9 and h > 0.35) and 2 or 1
    for k = 1, count do
      local a = hash2(ix, iz, 10 + k)
      local b = hash2(ix, iz, 20 + k)
      local c = hash2(ix, iz, 30 + k)
      local d = hash2(ix, iz, 40 + k)
      -- ix/iz are CLOUD-SPACE indices (eachWeatherCell subtracts the
      -- map-change shift before deriving them), so converting back to a drawn
      -- position has to add it again. Without this the whole layer renders
      -- offset from the player by the accumulated jump after the first map
      -- change -- a bug introduced by moving the grid into cloud space, and
      -- caught by a guard checking the DRAWN position rather than only the
      -- cell identity.
      local cx = (ix + 0.12 + a * 0.76) * cell + cloudShiftX
      local cz = (iz + 0.12 + b * 0.76) * cell + cloudShiftZ
      local cy = 0.5 + c * 5.0
      local halfW = 46 + d * 62
      local height = 18 + hash2(ix, iz, 50 + k) * 22
      local alpha = (0.081 + hash2(ix, iz, 60 + k) * 0.071) * level
      local phase = hash2(ix, iz, 70 + k) * PI2
      local drift = 13 + hash2(ix, iz, 80 + k) * 18
      local rate = 0.26 + hash2(ix, iz, 90 + k) * 0.22
      for ci = 1, 4 do
        n=n+1; local row=rows[n]; if not row then row={0,0,0,0,0,0,0,0,0,0,0}; rows[n]=row end
        local coX=(ci==1 or ci==4) and -1 or 1
        local coY=(ci>=3) and 1 or 0
        row[1],row[2],row[3]=cx,cy,cz
        row[4],row[5],row[6],row[7]=coX,coY,phase,alpha
        row[8],row[9],row[10],row[11]=halfW,height,drift,rate
        verts[n]=row
      end
      pushQuad(indices, q)
      q = q + 1
    end
  end)
  for i=n+1,oldV do verts[i]=nil end
  return verts, indices
end

local function drawMist(Voxel3D, frame)
  if frame and frame.weather and frame.weather._mistVisual == false then return false end
  local sh = mistShader()
  local axisR = horizontalRight(Voxel3D)
  if not (sh and axisR) then return false end
  local verts, indices = buildMistVertices(Voxel3D, frame)
  if not (verts and indices and #verts > 0) then return false end
  local meshOk
  mistMesh, meshOk = CinematicAtmos._uploadStreamMesh("mist", mistMesh, MIST_FORMAT, verts)
  if not meshOk then return false end
  CinematicAtmos._applySequentialQuadMap("mist", mistMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(sh) then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
    V.safeCall(sh.send, sh, "axisR", axisR)
    V.safeCall(sh.send, sh, "mistWind", frame.mistWind or CinematicAtmos._defaultMistWind)
    V.safeCall(sh.send, sh, "mistAdvect", frame.mistAdvect or CinematicAtmos._zero2)
    -- Geometry coverage now follows the frustum. Keep only a very small
    -- projection correction; cumulative density comes from extra world-space
    -- fog bodies, not stronger alpha in landscape.
    local projectionScale = orientationDensityScale(Voxel3D)
    V.safeCall(sh.send, sh, "alphaScale", projectionScale)
    V.safeCall(sh.send, sh, "time", ForestAtmos.time)
    local c = frame.fogColor or { 0.86, 0.89, 0.93 }
    local wid = tostring(frame.wxId or ""):upper()
    local mr, mg, mb
    if wid == "SANDSTORM" or wid == "DUSTSTORM" then
      mr, mg, mb = c[1], c[2], c[3]  -- exact particle match; opacity from alpha
    else
      mr = min(1, c[1] * 0.76 + 0.24)
      mg = min(1, c[2] * 0.76 + 0.24)
      mb = min(1, c[3] * 0.76 + 0.24)
    end
    local c3=CinematicAtmos._uniformScratch.color3; c3[1],c3[2],c3[3]=mr,mg,mb
    V.safeCall(sh.send, sh, "mistColor", c3)
    local okDraw = V.safeCall(love.graphics.draw, mistMesh)
    Voxel3D.endEffect()
    return okDraw
  end
  return false
end

-- ---------- rolling crest billows
--
-- The broad mist cards above provide the body of the weather. These smaller
-- puffs are the motion cue: they continually travel through that body, rise,
-- curl over and dissolve downstream. Hardware depth testing keeps every puff
-- in the world, so the rolling edge can disappear behind a tree and reappear
-- on the other side instead of behaving like a screen-space particle layer.

local ROLL_SHADER = [[
  varying vec2 vLocal;
  varying float vAlpha;
  varying float vLife;
  varying float vPhase;
  varying float vCycle;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  uniform vec3 axisR;
  uniform vec3 axisU;
  uniform vec2 windDir;
  uniform float time;
  attribute vec4 RollData;   // local x, local y, phase 0..1, alpha
  attribute vec4 RollShape;  // half width, half height, travel, rate
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float ph = RollData.z;
    float cyc = fract(time * RollShape.w + ph);
    float theta = cyc * 6.2831853;
    float along = (cyc * 2.0 - 1.0) * RollShape.z;
    float sideways = sin(theta + ph * 9.7) * RollShape.z * 0.17;
    vec2 perp = vec2(-windDir.y, windDir.x);
    vec3 base = vertex_position.xyz;
    base.x += windDir.x * along + perp.x * sideways;
    base.z += windDir.y * along + perp.y * sideways;
    // A cycloidal rise/fall gives the crest an actual turnover trajectory:
    // it grows out of the bank, climbs, folds forward and sinks back into it.
    float lift = 0.5 - 0.5 * cos(theta);
    base.y += 0.8 + lift * RollShape.y * 0.66
              + sin(theta * 2.0 + ph * 13.0) * 1.25;
    float breathe = 0.88 + 0.18 * sin(theta - 0.8 + ph * 5.0);
    vLocal = RollData.xy;
    vPhase = ph * 6.2831853;
    vCycle = cyc;
    vAlpha = RollData.w;
    vLife = smoothstep(0.00, 0.13, cyc) * (1.0 - smoothstep(0.78, 1.0, cyc));

    // Tip the asymmetric billow as it climbs and folds. Because the puff is
    // made of offset lobes rather than a circle, this rotation reads as the
    // fog rolling over itself instead of merely translating through space.
    float turn = sin(theta - 1.05) * 0.48
                 + sin(theta * 0.5 + ph * 11.0) * 0.11;
    float ct = cos(turn), st = sin(turn);
    vec2 lp = vec2(RollData.x * RollShape.x * breathe,
                   RollData.y * RollShape.y * breathe);
    vec2 rp = vec2(lp.x * ct - lp.y * st, lp.x * st + lp.y * ct);
    vec3 p = base + axisR * rp.x + axisU * rp.y;
    vec4 w = vec4(p, 1.0);
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform vec3 mistColor;
  uniform float alphaScale;
  uniform float time;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vLocal;
    // The internal lobe field turns with the crest too. It is intentionally
    // less than a full spin: natural fog folds/curls rather than pinwheeling.
    float localTurn = sin(vCycle * 6.2831853 - 1.0) * 0.38
                      + sin(vPhase) * 0.08;
    float lc = cos(localTurn), ls = sin(localTurn);
    p = vec2(p.x * lc - p.y * ls, p.x * ls + p.y * lc);
    // Several soft lobes inside one quad make a billow rather than a circle.
    float d0 = length(vec2(p.x * 0.90, p.y * 1.05));
    float d1 = length(vec2((p.x + 0.34) * 1.32, (p.y - 0.05) * 1.42));
    float d2 = length(vec2((p.x - 0.31) * 1.28, (p.y + 0.08) * 1.36));
    float l0 = 1.0 - smoothstep(0.47, 1.00, d0);
    float l1 = 1.0 - smoothstep(0.42, 0.98, d1);
    float l2 = 1.0 - smoothstep(0.44, 1.00, d2);
    float body = max(l0, max(l1 * 0.88, l2 * 0.84));
    // Internal curling makes the puff deform while its centre follows the
    // rolling trajectory, so it does not look like a sprite simply drifting.
    float curl = 0.70 + 0.30 * sin(p.x * 5.8 - p.y * 7.6
                                  - time * 0.61 + vPhase);
    float a = vAlpha * alphaScale * vLife * body * (0.74 + 0.26 * curl);
    return vec4(mistColor, a) * color;
  }
#endif
]]

local ROLL_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "RollData", "float", 4 },
  { "RollShape", "float", 4 },
}

local rollShaderState, rollMesh = nil, nil

local function rollShader()
  if rollShaderState ~= nil then return rollShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, ROLL_SHADER)
  rollShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] rolling fog shader refused: " .. tostring(sh)) end
  return rollShaderState or nil
end

local function buildRollVertices(Voxel3D, frame)
  local f = Voxel3D.focus
  if not f then return nil, nil end
  local cell = 72
  local radius = frame.level > 0.9 and 4 or 3
  local verts=CinematicAtmos._rollVerts or {}; CinematicAtmos._rollVerts=verts
  local rows=CinematicAtmos._rollRows or {}; CinematicAtmos._rollRows=rows
  local indices=CinematicAtmos._rollIndices or {}; CinematicAtmos._rollIndices=indices
  local oldV=#verts; for i=#indices,1,-1 do indices[i]=nil end
  local q,n=0,0
  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
    local gate = hash2(ix, iz, 401)
    if gate > 0.16 then
      local count = frame.level > 0.9 and 3 or 2
      for k = 1, count do
        local cx = (ix + 0.16 + hash2(ix, iz, 410 + k) * 0.68) * cell + cloudShiftX
        local cz = (iz + 0.16 + hash2(ix, iz, 420 + k) * 0.68) * cell + cloudShiftZ
        local cy = 2.3 + hash2(ix, iz, 430 + k) * 4.4
        local hw = 23 + hash2(ix, iz, 440 + k) * 32
        local hh = 10 + hash2(ix, iz, 450 + k) * 14
        local travel = 30 + hash2(ix, iz, 460 + k) * 34
        local rate = 0.030 + hash2(ix, iz, 470 + k) * 0.024
        local phase = hash2(ix, iz, 480 + k)
        local alpha = (0.046 + hash2(ix, iz, 490 + k) * 0.040) * frame.level
        for ci = 1, 4 do
          n=n+1; local row=rows[n]; if not row then row={0,0,0,0,0,0,0,0,0,0,0}; rows[n]=row end
          local coX=(ci==1 or ci==4) and -1 or 1
          local coY=(ci<=2) and -1 or 1
          row[1],row[2],row[3]=cx,cy,cz
          row[4],row[5],row[6],row[7]=coX,coY,phase,alpha
          row[8],row[9],row[10],row[11]=hw,hh,travel,rate
          verts[n]=row
        end
        pushQuad(indices, q)
        q = q + 1
      end
    end
  end)
  for i=n+1,oldV do verts[i]=nil end
  return verts, indices
end

local function drawRollFog(Voxel3D, frame)
  if frame and frame.weather and frame.weather._mistVisual == false then return false end
  local sh = rollShader()
  local axisR, axisU = billboardAxes(Voxel3D)
  if not (sh and axisR and axisU) then return false end
  local verts, indices = buildRollVertices(Voxel3D, frame)
  if not (verts and indices and #verts > 0) then return false end
  local meshOk
  rollMesh, meshOk = CinematicAtmos._uploadStreamMesh("roll", rollMesh, ROLL_FORMAT, verts)
  if not meshOk then return false end
  CinematicAtmos._applySequentialQuadMap("roll", rollMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(sh) then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
    V.safeCall(sh.send, sh, "axisR", axisR)
    V.safeCall(sh.send, sh, "axisU", axisU)
    local wx, wz = (frame.mistWind and frame.mistWind[1]) or 8.8,
                   (frame.mistWind and frame.mistWind[2]) or -5.4
    local wl = sqrt(wx * wx + wz * wz)
    if wl < 1e-5 then wx, wz, wl = 1, 0, 1 end
    local w2=CinematicAtmos._uniformScratch.wind2; w2[1],w2[2]=wx/wl,wz/wl
    V.safeCall(sh.send, sh, "windDir", w2)
    V.safeCall(sh.send, sh, "time", ForestAtmos.time)
    local projectionScale = orientationDensityScale(Voxel3D)
    V.safeCall(sh.send, sh, "alphaScale", projectionScale)
    local c = frame.fogColor or { 0.86, 0.89, 0.93 }
    local wid = tostring(frame.wxId or ""):upper()
    local mr, mg, mb
    if wid == "SANDSTORM" or wid == "DUSTSTORM" then
      mr, mg, mb = c[1], c[2], c[3]
    else
      mr = min(1, c[1] * 0.74 + 0.26)
      mg = min(1, c[2] * 0.74 + 0.26)
      mb = min(1, c[3] * 0.74 + 0.26)
    end
    local c3=CinematicAtmos._uniformScratch.color3; c3[1],c3[2],c3[3]=mr,mg,mb
    V.safeCall(sh.send, sh, "mistColor", c3)
    local okDraw = V.safeCall(love.graphics.draw, rollMesh)
    Voxel3D.endEffect()
    return okDraw
  end
  return false
end


-- ---------- ambient floating particles
--
-- Small, soft motes provide parallax and make otherwise-clear air feel alive.
-- They are ordinary depth-tested 3D billboards, not a screen overlay. Every
-- mote has its own direction, speed and lifecycle; the fade hides the wrap so
-- it appears, drifts, disappears, and later reforms elsewhere without pops.

local PARTICLE_SHADER = [[
  varying vec2 vLocal;
  varying float vAlpha;
  varying float vLife;
  varying float vWarm;
  varying float vCloud;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  uniform vec3 axisR;
  uniform vec3 axisU;
  uniform float time;
  attribute vec4 ParticleData;   // local x, local y, phase 0..1, alpha
  attribute vec4 ParticleMove;   // mote: size, range, angle, +rate
                                 // cloud: half-width, half-height, drift, -rate
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float cloud = step(0.000001, -ParticleMove.w);
    float rate = mix(ParticleMove.w, -ParticleMove.w, cloud);
    float cyc = fract(time * rate + ParticleData.z);
    float age = cyc * 2.0 - 1.0;

    vec3 base = vertex_position.xyz;

    // Proven A9/A10 mote motion, unchanged when cloud == 0.
    float ang = ParticleMove.z;
    vec2 dir = vec2(cos(ang), sin(ang));
    vec2 perp = vec2(-dir.y, dir.x);
    float travel = age * ParticleMove.y;
    float wander = sin(time * 0.43 + ParticleData.z * 19.7 + cyc * 8.0)
                   * ParticleMove.y * 0.17;
    base.x += (dir.x * travel + perp.x * wander) * (1.0 - cloud);
    base.z += (dir.y * travel + perp.y * wander) * (1.0 - cloud);
    base.y += (sin(time * 0.31 + ParticleData.z * 23.0 + cyc * 9.0) * 2.0
              + sin(cyc * 3.14159265) * ParticleMove.y * 0.10) * (1.0 - cloud);

    // Cloud lobes ride one coherent wind lane; their own motion is deliberately
    // small and slow. A14 proved the shared particle path, but letting every
    // puff wander too far makes a cloud look like independent bubbles. Here
    // the lobe only swells, settles and shears a little while the descriptor
    // moves the whole cloud across the sky.
    float ct = time * rate + ParticleData.z * 6.2831853;
    base.x += sin(ct * 0.37 + ParticleData.z * 7.1) * ParticleMove.z * 0.42 * cloud;
    base.z += cos(ct * 0.31 + ParticleData.z * 5.3) * ParticleMove.z * 0.24 * cloud;
    base.y += sin(ct * 0.23 + ParticleData.z * 9.7) * 1.15 * cloud;

    vLocal = ParticleData.xy;
    vAlpha = ParticleData.w;
    float moteLife = smoothstep(0.02, 0.18, cyc) * (1.0 - smoothstep(0.76, 0.98, cyc));
    vLife = mix(moteLife, 1.0, cloud);
    vWarm = 0.5 + 0.5 * sin(ParticleData.z * 31.0);
    vCloud = cloud;

    float breathe = 0.86 + 0.14 * sin(time * 0.37 + ParticleData.z * 17.0);
    // Slow growth/decay gives the cloud edge a living cauliflower motion
    // without making the whole mass pulse in unison.
    float cloudBreathe = 0.945 + 0.055 * sin(time * 0.052 + ParticleData.z * 13.0);
    float sx = mix(ParticleMove.x * breathe, ParticleMove.x * cloudBreathe, cloud);
    float sy = mix(ParticleMove.x * breathe, ParticleMove.y * cloudBreathe, cloud);
    vec3 p = base + axisR * (ParticleData.x * sx)
                  + axisU * (ParticleData.y * sy);
    vec4 w = vec4(p, 1.0);

    // Ground motes bend with Dramatic Shape's globe. Sky clouds do not: they
    // are camera-frustum sky geometry, not objects attached to the terrain.
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z * (1.0 - cloud);
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform vec3 particleCool;
  uniform vec3 particleWarm;
  uniform vec3 cloudCool;
  uniform vec3 cloudWarm;
  uniform vec2 cloudSun;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float d = length(vLocal);

    float moteCore = 1.0 - smoothstep(0.10, 0.92, d);
    float moteFeather = 1.0 - smoothstep(0.42, 1.0, d);
    float moteA = vAlpha * vLife * moteCore * moteFeather;
    vec3 moteC = mix(particleCool, particleWarm, vWarm * 0.42);

    // Mostly Cloudy M2: deliberately soft/ambiguous cloud lobes. The previous
    // pass made every puff readable, which produced a scalloped ceiling. Here
    // individual lobes have broad feathering and restrained vertical shading;
    // density comes from overlap, so the eye sees one cloud mass rather than
    // the primitives that construct it.
    vec2 cq = vec2(vLocal.x * 0.96, vLocal.y * 1.03);
    float qd = length(cq);
    float cloudBody = 1.0 - smoothstep(0.36, 1.0, qd);
    float cloudCore = 1.0 - smoothstep(0.10, 0.68, qd);
    float cloudA = clamp(vAlpha * cloudBody * (0.76 + cloudCore * 0.28), 0.0, 0.90);

    float top = smoothstep(-0.86, 0.90, vLocal.y);
    float underside = 0.88 + top * 0.13;
    float selfShade = 0.97 - cloudCore * (1.0 - top) * 0.035;
    vec3 cloudC = mix(cloudCool, cloudWarm, 0.34 + top * 0.31 + cloudCore * 0.035);
    cloudC *= underside * selfShade;

    vec2 sdir = cloudSun / max(length(cloudSun), 0.001);
    vec2 edir = cq / max(qd, 0.001);
    float sunSide = clamp(dot(edir, sdir), 0.0, 1.0);
    float feather = smoothstep(0.68, 0.95, qd) * cloudBody;
    float silver = feather * sunSide * smoothstep(-0.05, 0.92, vLocal.y);
    cloudC += cloudWarm * silver * 0.13;


    float a = mix(moteA, cloudA, vCloud);
    vec3 c = mix(moteC, cloudC, vCloud);
    return vec4(c, a) * color;
  }
#endif
]]

local PARTICLE_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "ParticleData", "float", 4 },
  { "ParticleMove", "float", 4 },
}

local particleShaderState, particleMesh = nil, nil

local function particleShader()
  if particleShaderState ~= nil then return particleShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, PARTICLE_SHADER)
  particleShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] ambient particle shader refused: " .. tostring(sh)) end
  return particleShaderState or nil
end

local function buildParticleVertices(Voxel3D, frame, clouds)
  local f = Voxel3D.focus
  if not f then return nil, nil end
  local cell = 48
  local radius = frame.level > 0.9 and 4 or 3
  local density = particleDensityScale() * ((frame.weather and frame.weather.motes) or 1.0)
  local sizeScale = particleSizeScale()
  local verts=CinematicAtmos._particleVerts
  local rows=CinematicAtmos._particleVertRows
  local indices=CinematicAtmos._particleIndices
  for i=#verts,1,-1 do verts[i]=nil end
  for i=#indices,1,-1 do indices[i]=nil end
  local q,vcount=0,0
  local corners=CinematicAtmos._particleCorners
  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
    -- DENSITY 1 / SCALE 8 is byte-for-byte the A9 population/size recipe.
    -- Higher density adds genuinely independent motes rather than increasing
    -- alpha, so the result remains airy instead of becoming a white veil.
    local gate = hash2(ix, iz, 601)
    if gate > 0.18 then
      local baseCount = 1
      if gate > 0.54 then baseCount = baseCount + 1 end
      if frame.level > 0.9 and gate > 0.91 then baseCount = baseCount + 1 end

      -- Stochastic rounding avoids visible whole-number jumps between cells.
      -- At density 1 this resolves to baseCount exactly, preserving A9.
      local wanted = baseCount * density
      local count = floor(wanted)
      if hash2(ix, iz, 606) < (wanted - count) then count = count + 1 end

      for k = 1, count do
        -- k=1..baseCount retains A9's original deterministic particles. Extra
        -- motes get their own salted hashes and therefore independent motion.
        local cx = (ix + 0.12 + hash2(ix, iz, 610 + k) * 0.76) * cell + cloudShiftX
        local cz = (iz + 0.12 + hash2(ix, iz, 620 + k) * 0.76) * cell + cloudShiftZ
        -- Bias toward the height band occupied by Red, grass, shrubs and
        -- lower tree crowns. An occasional high mote preserves vertical depth.
        local cy = 3.0 + hash2(ix, iz, 630 + k) * 21.0
        if hash2(ix, iz, 635 + k) > 0.88 then
          cy = cy + 7.0 + hash2(ix, iz, 636 + k) * 9.0
        end
        local size = (1.65 + hash2(ix, iz, 640 + k) * 2.55) * sizeScale
        local range = 10.0 + hash2(ix, iz, 650 + k) * 22.0
        local angle = hash2(ix, iz, 660 + k) * PI2
        local life = 6.5 + hash2(ix, iz, 670 + k) * 10.5
        local rate = 1.0 / life
        local phase = hash2(ix, iz, 680 + k)
        local alpha = (0.115 + hash2(ix, iz, 690 + k) * 0.105) * frame.level
        for ci = 1, 4 do
          local co = corners[ci]
          vcount=vcount+1
          local row=rows[vcount]
          if not row then row={};rows[vcount]=row end
          row[1],row[2],row[3]=cx,cy,cz
          row[4],row[5],row[6],row[7]=co[1],co[2],phase,alpha
          row[8],row[9],row[10],row[11]=size,range,angle,rate
          verts[vcount]=row
        end
        pushQuad(indices, q)
        q = q + 1
      end
    end
  end)

  -- MOSTLY CLOUDY M2: retain the proven shared particle/cloud render path,
  -- but go back to the visual ambiguity that worked in A14/A15. Each formation
  -- has a few broad low-alpha backbone bodies plus many smaller overlapping
  -- lobes. There is NO explicit row of base puffs, so the player cannot read a
  -- repeated scalloped underside. Macro type still changes width/height, but
  -- the construction itself stays deliberately hard to parse.
  if clouds and #clouds > 0 then
    for ciCloud = 1, #clouds do
      local c = clouds[ciCloud]
      local ix, iz = c.ix, c.iz
      local spanX, spanY, spanZ = c.spanX, c.spanY, c.spanZ
      local kind = c.kind or 1
      local puffs = c.puffs or (frame.level > 0.9 and 34 or 26)

      local deckBlend = c.deckBlend or (c.closedDeck and 1.0 or 0.0)
      local closedDeck = deckBlend >= 0.985
      local backboneCount = max(3, min(6, floor(3 + deckBlend * 3 + 0.5)))
      for k = 1, puffs do
        local hk = 900 + k * 13
        local ox, oy, oz, hw, hh, alpha
        local core = k <= (closedDeck and 14 or 9)

        if k <= backboneCount then
          -- Broad translucent backbones hide the billboard primitives.  Closed
          -- weather gets six overlapping bodies spanning almost the full cell,
          -- which bridges neighbouring formations into a continuous ceiling.
          local anchor
          if backboneCount <= 3 then
            local anchors = { -0.30, 0.0, 0.31 }
            anchor = anchors[k]
          else
            anchor = -0.58 + (k - 1) * (1.17 / max(1, backboneCount - 1))
          end
          ox = spanX * anchor
          oz = (hash2(ix, iz, hk + 1) * 2 - 1) * spanZ * lerp(0.15, 0.20, deckBlend)
          oy = -spanY * lerp(0.03, 0.06, deckBlend)
             + hash2(ix, iz, hk + 2) * spanY * lerp(0.16, 0.12, deckBlend)
          hw = spanX * (lerp(0.39, 0.34, deckBlend)
             + hash2(ix, iz, hk + 3) * lerp(0.09, 0.07, deckBlend))
          hh = spanY * (lerp(0.50, 0.68, deckBlend)
             + hash2(ix, iz, hk + 4) * 0.12)
          alpha = (lerp(0.24, 0.40, deckBlend)
             + hash2(ix, iz, hk + 5) * lerp(0.08, 0.10, deckBlend)) * frame.level
        else
          -- Irregular shell around a soft core. Vertical placement is biased
          -- upward toward the centre but never snaps to a flat floor. Broad
          -- banks stay low; tower types gain a little more central lift.
          local rx = hash2(ix, iz, hk + 1) * 2 - 1
          local rz = hash2(ix, iz, hk + 2) * 2 - 1
          local centre = max(0, 1.0 - abs(rx))
          local radial = sqrt(min(1.0, rx * rx * 0.76 + rz * rz))
          local lift
          if kind == 0 then
            lift = -0.16 + centre * 0.25 + hash2(ix, iz, hk + 3) * 0.26
          elseif kind == 2 then
            lift = -0.12 + (centre ^ 1.55) * 0.72 + hash2(ix, iz, hk + 3) * 0.30
          else
            lift = -0.14 + (centre ^ 1.25) * 0.48 + hash2(ix, iz, hk + 3) * 0.29
          end
          ox = rx * spanX * (kind == 0 and 0.94 or 0.86)
          oz = rz * spanZ * (0.58 + hash2(ix, iz, hk + 4) * 0.34)
          oy = spanY * lift

          -- More, smaller lobes than M1. Near the perimeter they become
          -- broader/softer instead of turning into a crisp string of bubbles.
          local edge = max(0, min(1, (radial - 0.48) / 0.52))
          edge = edge * edge * (3 - 2 * edge)
          hw = spanX * (0.13 + hash2(ix, iz, hk + 5) * 0.16) * (1.0 + edge * 0.12)
          hh = spanY * (0.20 + hash2(ix, iz, hk + 6) * 0.24) * (1.0 + edge * 0.08)
          alpha = (lerp(0.31, 0.39, deckBlend)
                 + hash2(ix, iz, hk + 7) * lerp(0.13, 0.14, deckBlend)) * frame.level
          if core then alpha = min(lerp(0.62, 0.70, deckBlend),
                                   alpha * lerp(1.10, 1.12, deckBlend)) end
        end

        -- Minute-scale edge evolution. Keep displacement tiny; mostly alter
        -- size and height so the cloud appears to develop, not swim apart.
        local evolve = sin(ForestAtmos.time * (0.0085 + c.evolveRate * 0.0035)
                           + c.phase + k * 1.417)
        hw = hw * (0.975 + evolve * 0.035)
        hh = hh * (0.974 + evolve * 0.042)
        oy = oy + evolve * spanY * 0.022

        -- Close formations gain density primarily from extra overlapping lobes,
        -- not from stronger individual cards. That prevents an overhead cloud
        -- from becoming a translucent screen wash as it approaches the camera.
        if c.depthClass == 0 then
          alpha = alpha * lerp(0.82, 1.0, deckBlend)
        elseif c.depthClass == 2 then
          alpha = alpha * lerp(0.93, 0.97, deckBlend)
        end
        alpha = alpha * (c.fadeAlpha or 1.0)

        local phase = hash2(ix, iz, hk + 8)
        local drift = 0.45 + hash2(ix, iz, hk + 9) * 0.95
        local rate = 0.0050 + hash2(ix, iz, hk + 10) * 0.0048

        for corner = 1, 4 do
          local co = corners[corner]
          vcount=vcount+1
          local row=rows[vcount]
          if not row then row={};rows[vcount]=row end
          row[1],row[2],row[3]=c.cx+ox,c.cy+oy,c.cz+oz
          row[4],row[5],row[6],row[7]=co[1],co[2],phase,alpha
          row[8],row[9],row[10],row[11]=hw,hh,drift,-rate
          verts[vcount]=row
        end
        pushQuad(indices, q)
        q = q + 1
      end
    end
  end
  return verts, indices
end

local function drawParticles(Voxel3D, frame, clouds)
  local sh = particleShader()
  local axisR, axisU = billboardAxes(Voxel3D)
  if not (sh and axisR and axisU) then return false end
  local verts, indices = buildParticleVertices(Voxel3D, frame, clouds)
  if not (verts and indices and #verts > 0) then return false end
  local meshOk
  particleMesh, meshOk = CinematicAtmos._uploadStreamMesh("particles", particleMesh, PARTICLE_FORMAT, verts)
  if not meshOk then return false end
  CinematicAtmos._applySequentialQuadMap("particles", particleMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(sh) then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
    V.safeCall(sh.send, sh, "axisR", axisR)
    V.safeCall(sh.send, sh, "axisU", axisU)
    V.safeCall(sh.send, sh, "time", ForestAtmos.time)
    local fog, ray = frame.fogColor, frame.rayColor
    local pc=CinematicAtmos._uniformScratch.particleCool
    pc[1],pc[2],pc[3]=min(1,fog[1]*0.74+0.22),min(1,fog[2]*0.74+0.22),min(1,fog[3]*0.74+0.22)
    V.safeCall(sh.send, sh, "particleCool", pc)
    local pw=CinematicAtmos._uniformScratch.particleWarm
    pw[1],pw[2],pw[3]=min(1,ray[1]*0.84+0.13),min(1,ray[2]*0.84+0.13),min(1,ray[3]*0.84+0.13)
    V.safeCall(sh.send, sh, "particleWarm", pw)
    local tint = DayNight.tint(true)
    local cloudShade = (frame.weather and frame.weather.cloudShade) or 1.0
    local cc=CinematicAtmos._uniformScratch.cloudCool
    cc[1],cc[2],cc[3]=min(1,(0.58*tint[1]+0.17)*cloudShade),min(1,(0.59*tint[2]+0.18)*cloudShade),min(1,(0.61*tint[3]+0.19)*cloudShade)
    V.safeCall(sh.send, sh, "cloudCool", cc)
    local cw=CinematicAtmos._uniformScratch.cloudWarm
    cw[1],cw[2],cw[3]=min(1,(0.68+ray[1]*0.30)*cloudShade),min(1,(0.70+ray[2]*0.29)*cloudShade),min(1,(0.73+ray[3]*0.27)*cloudShade)
    V.safeCall(sh.send, sh, "cloudWarm", cw)
    -- Project the sun direction into the billboard plane. The cloud pixel
    -- shader uses this only for restrained silver-lining at the lit feather.
    local kx, kz = ShadowMap.KX or -0.85, ShadowMap.KZ or -0.55
    local sx, sy, sz = -kx, 1.0, -kz
    local sl = sqrt(sx * sx + sy * sy + sz * sz)
    sx, sy, sz = sx / sl, sy / sl, sz / sl
    local sr = sx * axisR[1] + sy * axisR[2] + sz * axisR[3]
    local su = sx * axisU[1] + sy * axisU[2] + sz * axisU[3]
    local su2=CinematicAtmos._uniformScratch.sun2; su2[1],su2[2]=sr,su
    V.safeCall(sh.send, sh, "cloudSun", su2)
    local okDraw = V.safeCall(love.graphics.draw, particleMesh)
    Voxel3D.endEffect()
    return okDraw
  end
  return false
end

-- ---------- world-space rain
--
-- Rain is a genuine 3D weather field, not a screen overlay. Each streak has a
-- deterministic world X/Z anchor, falls through a real Y range, leans with the
-- weather wind and is drawn while Dramatic Shape's live scene depth buffer is
-- still bound. Trees, roofs and terrain therefore occlude drops in hardware.

local RAIN_SHADER = [[
  varying vec2 vLocal;
  varying float vAlpha;
  varying float vLife;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  uniform vec3 axisR;
  uniform float time;
  attribute vec4 RainData;    // local x, local y (0..1), phase, alpha
  attribute vec4 RainShape;   // half width, streak length, fall range, cycle rate
  attribute vec4 RainMotion;  // top height, wind x, wind z, sway

  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float cyc = fract(time * RainShape.w + RainData.z);
    vec3 base = vertex_position.xyz;

    // Fall down through the local atmosphere. Horizontal displacement uses the
    // same cycle, so each streak follows one coherent wind-slanted trajectory.
    base.y += RainMotion.x - cyc * RainShape.z;
    base.x += RainMotion.y * cyc;
    base.z += RainMotion.z * cyc;
    float wobble = sin(time * 2.1 + RainData.z * 37.0 + cyc * 11.0) * RainMotion.w;
    base.x += wobble;

    // Tail points back up the actual world-space fall vector. Perspective is
    // supplied by the ordinary 3D projection, so nearby rain naturally reads
    // larger/faster while distant streaks recede.
    vec3 trail = normalize(vec3(-RainMotion.y, RainShape.z, -RainMotion.z));
    vec3 p = base + axisR * (RainData.x * RainShape.x)
                  + trail * (RainData.y * RainShape.y);
    vec4 w = vec4(p, 1.0);

    // Rain maintains altitude relative to the curved diorama terrain instead
    // of becoming a flat screen sheet at the horizon.
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }

    vLocal = RainData.xy;
    vAlpha = RainData.w;
    vLife = smoothstep(0.015, 0.065, cyc) * (1.0 - smoothstep(0.91, 0.995, cyc));
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform vec3 rainColor;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float side = 1.0 - smoothstep(0.18, 1.0, abs(vLocal.x));
    float tail = smoothstep(0.00, 0.08, vLocal.y)
               * (1.0 - smoothstep(0.82, 1.0, vLocal.y));
    // A faint body plus a brighter lower portion reads as falling water rather
    // than glowing white scratches, especially against the closed cloud deck.
    float body = 0.44 + 0.56 * (1.0 - vLocal.y);
    float a = vAlpha * vLife * side * tail * body;
    return vec4(rainColor, a) * color;
  }
#endif
]]

local RAIN_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "RainData", "float", 4 },
  { "RainShape", "float", 4 },
  { "RainMotion", "float", 4 },
}

local rainShaderState, rainMesh = nil, nil

-- Rain animation must use an INTEGRATED clock, never absoluteTime * speed.
-- W5 multiplied ForestAtmos.time by the live interpolated rainSpeed. During a
-- Thunderstorm -> Rain transition the speed decreases, and at sufficiently
-- large absolute times the changing multiplier can make that product move
-- backwards for a few frames. The authored fall vector was still downward,
-- but the cycle phase reversed and the drops appeared to fly into the sky.
--
-- Integrating positive speed over frame time makes reversal mathematically
-- impossible while preserving smooth acceleration/deceleration between weather
-- states. Source time is sampled here rather than in update(), so headless/menu
-- paths that never draw rain cannot accidentally advance the GPU phase twice.
local rainClock = 0
local rainClockSourceTime = nil
local function integratedRainTime(weather)
  local now = ForestAtmos.time or 0
  if rainClockSourceTime == nil then
    rainClockSourceTime = now
    return rainClock
  end
  local dt = now - rainClockSourceTime
  rainClockSourceTime = now
  if dt > 0 then
    local speed = max(0.05, tonumber(weather and weather.rainSpeed) or 1.0)
    rainClock = rainClock + dt * speed
  end
  -- A reset/frozen screenshot clock may move backwards. Never subtract from the
  -- integrated phase; simply re-anchor the source time on that frame.
  return rainClock
end

local function rainShader()
  if rainShaderState ~= nil then return rainShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, RAIN_SHADER)
  rainShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] 3D rain shader refused: " .. tostring(sh)) end
  return rainShaderState or nil
end

local function buildRainVertices(Voxel3D, frame)
  local f = Voxel3D.focus
  local weather = frame.weather
  local baseIntensity = weather and weather.rainIntensity or 0
  if not f or baseIntensity <= 0 then return nil, nil end

  local density = rainDensityScale(weather) * baseIntensity
  local size = rainSizeScale(weather)
  local windStrength = weather.rainWind or 1.0
  local cell = 34
  local radius = frame.level > 0.9 and 4 or 3
  local verts, indices, q = {}, {}, 0
  local corners = { { -1, 0 }, { 1, 0 }, { 1, 1 }, { -1, 1 } }

  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
    local gate = hash2(ix, iz, 1701)
    if gate > 0.05 then
      local baseCount = frame.level > 0.9 and 3 or 2
      if gate > 0.42 then baseCount = baseCount + 1 end
      if gate > 0.76 then baseCount = baseCount + 1 end
      local wanted = baseCount * density
      local count = floor(wanted)
      if hash2(ix, iz, 1702) < (wanted - count) then count = count + 1 end

      for k = 1, count do
        local cx = (ix + 0.08 + hash2(ix, iz, 1710 + k) * 0.84) * cell + cloudShiftX
        local cz = (iz + 0.08 + hash2(ix, iz, 1720 + k) * 0.84) * cell + cloudShiftZ
        -- Each drop falls through a tall local atmospheric column. The base is
        -- tied to focus elevation so maps with raised terrain still get rain.
        local top = 82 + hash2(ix, iz, 1730 + k) * 42
        local fallRange = 102 + hash2(ix, iz, 1740 + k) * 54
        -- Per-drop cycle rate is fixed. Weather speed is applied by the
        -- monotonic integratedRainTime() clock at draw time, so interpolating
        -- storm speed can never reverse the animation phase.
        local life = 0.72 + hash2(ix, iz, 1750 + k) * 0.48
        local rate = 1.0 / life
        local phase = hash2(ix, iz, 1760 + k)

        local width = (0.72 + hash2(ix, iz, 1770 + k) * 0.58) * size
        local length = (9.0 + hash2(ix, iz, 1780 + k) * 8.5) * size
        -- Wind is coherent at weather scale with small per-drop variance. The
        -- storm preset increases the same vector rather than inventing a new
        -- screen-space angle.
        local jitter = (hash2(ix, iz, 1790 + k) * 2 - 1) * 0.18
        local dx, dz = 0.85, -0.53
        if frame.windState then
          local vx, vz = tonumber(frame.windState.x) or 0, tonumber(frame.windState.z) or 0
          local vl = sqrt(vx*vx + vz*vz)
          if vl > 1e-5 then dx, dz = vx/vl, vz/vl end
          windStrength = windStrength * max(0.08, tonumber(frame.windState.strength) or 0.5)
        end
        local drive = (11.8 + jitter * 4.0) * windStrength
        local windX = dx * drive
        local windZ = dz * drive
        local sway = 0.12 + hash2(ix, iz, 1800 + k) * 0.28
        local alpha = (0.18 + hash2(ix, iz, 1810 + k) * 0.16) * frame.level

        for ci = 1, 4 do
          local co = corners[ci]
          verts[#verts + 1] = {
            cx, f[2] or 0, cz,
            co[1], co[2], phase, alpha,
            width, length, fallRange, rate,
            top, windX, windZ, sway,
          }
        end
        pushQuad(indices, q)
        q = q + 1
      end
    end
  end)

  return verts, indices
end


-- ---------------------------------------------------------------------------
-- 3D snow: soft world-space flakes (billboards), slow fall, horizontal sway.
-- ---------------------------------------------------------------------------
local function snowDensityScale(weather)
  local n = tonumber(weather and weather.snowDensityRung) or 5
  return 0.55 + n * 0.18
end

local function snowSizeScale(weather)
  local n = tonumber(weather and weather.snowSizeRung) or 4
  return 0.70 + n * 0.16
end

local SNOW_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "SnowData", "float", 4 },
}

local snowShaderState, snowMesh = nil, nil

local function snowShader()
  if snowShaderState then return snowShaderState end
  if not (love and love.graphics and love.graphics.newShader) then return nil end
  local ok, sh = V.safeCall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  extern float time;
  extern vec3 eye;
  attribute vec4 SnowData; // phase, rate, size, alpha
  varying float vAlpha;
  varying vec2 vLocal;
  vec4 position(mat4 t, vec4 v) {
    // v.xyz = column anchor; SnowData drives fall/sway
    float phase = SnowData.x;
    float rate = max(0.05, SnowData.y);
    float size = SnowData.z;
    float baseA = SnowData.w;
    float cyc = fract(phase + time * rate);
    // Slow drop with soft horizontal flutter (realistic flake motion)
    float fall = cyc * 95.0;
    float sway = sin((phase + time * 0.7) * 6.28318) * 7.5
               + sin((phase * 1.7 + time * 0.45) * 6.28318) * 4.0;
    float drift = cos((phase * 0.9 + time * 0.33) * 6.28318) * 5.5;
    vec3 w = v.xyz;
    w.y -= fall;
    w.x += sway + drift * 0.35;
    w.z += drift * 0.65;
    // Billboard in view plane approx via eye vector
    vec3 toEye = normalize(eye - w);
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, toEye));
    up = normalize(cross(toEye, right));
    // v.w encodes corner: 0..3 via RainShape-style packing in position.w unused —
    // corners packed into SnowData via mesh generator using position offset
    vLocal = vec2(0.0);
    vAlpha = baseA * smoothstep(0.0, 0.12, cyc) * (1.0 - smoothstep(0.82, 1.0, cyc));
    return vp * vec4(w, 1.0);
  }
#endif
#ifdef PIXEL
  varying float vAlpha;
  varying vec2 vLocal;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // Soft round flake
    vec2 p = tc * 2.0 - 1.0;
    float d = length(p);
    float soft = 1.0 - smoothstep(0.25, 1.0, d);
    float a = vAlpha * soft * soft;
    return vec4(0.95, 0.97, 1.0, a) * color;
  }
#endif
]])
  if ok and sh then snowShaderState = sh end
  return snowShaderState
end

-- Mesh built with expanded positions for 4 corners of each flake billboard
local function buildSnowVertices(Voxel3D, frame)
  local f = Voxel3D.focus
  local weather = frame.weather
  local wxId = snowState.wxId or ""
  local baseIntensity = tonumber(weather and weather.snowIntensity) or 0
  if baseIntensity <= 0 and wxIsSnowy(wxId) then
    baseIntensity = snowTargetFor(wxId)
  end
  if not f or baseIntensity <= 0.02 then return nil end

  local density = snowDensityScale(weather) * baseIntensity
  local sizeMul = snowSizeScale(weather)
  local cell = 40
  local radius = frame.level > 0.9 and 4 or 3
  local verts = {}
  local eye = Voxel3D.eye or f

  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
    local gate = hash2(ix, iz, 2701)
    if gate > 0.12 then return end
    local baseCount = frame.level > 0.9 and 4 or 3
    if gate < 0.04 then baseCount = baseCount + 2 end
    local wanted = baseCount * density
    local count = floor(wanted)
    if hash2(ix, iz, 2702) < (wanted - count) then count = count + 1 end
    for k = 1, count do
      local cx = (ix + 0.05 + hash2(ix, iz, 2710 + k) * 0.90) * cell + cloudShiftX
      local cz = (iz + 0.05 + hash2(ix, iz, 2720 + k) * 0.90) * cell + cloudShiftZ
      local top = (f[2] or 0) + 55 + hash2(ix, iz, 2730 + k) * 50
      local phase = hash2(ix, iz, 2740 + k)
      local life = 1.4 + hash2(ix, iz, 2750 + k) * 1.6
      local rate = 1.0 / life
      local size = (1.6 + hash2(ix, iz, 2760 + k) * 2.8) * sizeMul
      local alpha = (0.35 + hash2(ix, iz, 2770 + k) * 0.45) * (0.55 + 0.45 * frame.level)
      -- 4 billboard corners in world, camera-facing approx via fixed axes
      local hs = size * 0.5
      -- Two triangles (6 verts) so we do not need setVertexMap
      local c1 = { cx - hs, top, cz - hs * 0.2 }
      local c2 = { cx + hs, top, cz - hs * 0.2 }
      local c3 = { cx + hs, top, cz + hs * 0.2 }
      local c4 = { cx - hs, top, cz + hs * 0.2 }
      local function push(c)
        verts[#verts + 1] = { c[1], c[2], c[3], phase, rate, size, alpha }
      end
      push(c1); push(c2); push(c3)
      push(c1); push(c3); push(c4)
    end
  end)

  if #verts < 4 then return nil end
  return verts
end

local function drawSnow3D(Voxel3D, frame)
  -- DISABLED. Old path: eachWeatherCell around camera/focus + shader fall.
  -- That made every flake follow the camera. Falling snow is WorldPrecip only.
  return
end
local function drawRain(Voxel3D, frame)
  local weather = frame.weather
  if not (weather and (weather.rainIntensity or 0) > 0) then return end
  local sh = rainShader()
  local axisR = billboardAxes(Voxel3D)
  if not (sh and axisR) then return end
  local verts, indices = buildRainVertices(Voxel3D, frame)
  if not (verts and indices and #verts > 0) then return end

  local meshOk
  rainMesh, meshOk = CinematicAtmos._uploadStreamMesh("rain", rainMesh, RAIN_FORMAT, verts)
  if not meshOk then return end
  CinematicAtmos._applySequentialQuadMap("rain", rainMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(sh) then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
    V.safeCall(sh.send, sh, "axisR", axisR)
    V.safeCall(sh.send, sh, "time", integratedRainTime(weather))
    local fog = frame.fogColor
    local tint = DayNight.tint(true)
    local rc=CinematicAtmos._uniformScratch.rainColor
    rc[1],rc[2],rc[3]=min(1,fog[1]*0.54+tint[1]*0.34+0.16),min(1,fog[2]*0.58+tint[2]*0.35+0.17),min(1,fog[3]*0.64+tint[3]*0.38+0.19)
    V.safeCall(sh.send, sh, "rainColor", rc)
    V.safeCall(love.graphics.draw, rainMesh)
    Voxel3D.endEffect()
  end
end

-- ---------- shadow-map-aware volumetric light shafts

local RAY_SHADER = [[
  varying vec2 vLocal;
  varying float vPhase;
  varying float vAlpha;
  varying LOVE_HIGHP_OR_MEDIUMP vec3 vWorld;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 curve;
  attribute vec4 RayData;    // local x (-1..1), local y (0..1), phase, alpha
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vLocal = RayData.xy;
    vPhase = RayData.z;
    vAlpha = RayData.w;
    vec4 w = vertex_position;
    vWorld = w.xyz;
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform Image sunMap;
  uniform mat4 sunVP;
  uniform float sunBias;
  uniform float sunActive;
  uniform vec3 rayColor;
  uniform vec2 shear;
  uniform vec2 wind;
  uniform float canopyY;
  uniform float time;

  float packedDepth(vec2 uv) {
    vec4 c = Texel(sunMap, uv);
    return c.r + c.g * (1.0 / 255.0);
  }

  float sunlightAt(vec3 p) {
    if (sunActive < 0.5) return 1.0;
    vec3 su = (sunVP * vec4(p, 1.0)).xyz;
    if (su.x <= 0.0 || su.x >= 1.0 || su.y <= 0.0 || su.y >= 1.0 || su.z >= 1.0)
      return 1.0;
    vec2 e = min(su.xy, 1.0 - su.xy);
    float edge = smoothstep(0.0, 0.055, min(e.x, e.y));
    float z = su.z - sunBias;
    float lit = step(z, packedDepth(su.xy));
    return mix(1.0, lit, edge);
  }

  float canopyPattern(vec3 p) {
    float up = max(0.0, canopyY - p.y);
    vec2 g = p.xz - shear * up;
    vec2 q = g * 0.020 + wind * time;
    float n1 = 0.5 + 0.5 * sin(q.x * 3.1 + q.y * 1.7 + 0.3);
    float n2 = 0.5 + 0.5 * sin(q.x * 1.3 - q.y * 4.2 + 2.1);
    float n3 = 0.5 + 0.5 * sin((q.x + q.y) * 2.2 - 1.4);
    float n = n1 * 0.45 + n2 * 0.35 + n3 * 0.20;
    return 0.46 + 0.54 * smoothstep(0.41, 0.78, n);
  }

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float x = abs(vLocal.x);
    float y = clamp(vLocal.y, 0.0, 1.0);
    float side = 1.0 - smoothstep(0.08, 1.0, x);
    float foot = smoothstep(0.00, 0.09, y);
    float head = 1.0 - smoothstep(0.72, 1.0, y);
    float breathe = 0.82 + 0.18 * sin(time * 0.17 + vPhase + vWorld.y * 0.025);
    float lit = sunlightAt(vWorld);
    float dapple = canopyPattern(vWorld);
    // Cloud transmission is baked into vAlpha on the CPU using the exact
    // cloud descriptors that build the visible clusters. This is much cheaper
    // on Android than re-evaluating a procedural cloud field for every ray
    // fragment, while still making cloud cores physically break the shafts.
    float a = vAlpha * side * foot * head * breathe * lit * dapple;
    return vec4(rayColor * a, a) * color;
  }
#endif
]]

local RAY_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "RayData", "float", 4 },
}

local rayShaderState, rayMesh = nil, nil
local cloudTransmissionAt, cloudTransmissionAlongRay

local function rayShader()
  if rayShaderState ~= nil then return rayShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, RAY_SHADER)
  rayShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] cinematic ray shader refused: " .. tostring(sh)) end
  return rayShaderState or nil
end

local function buildRayVertices(Voxel3D, frame, clouds)
  local f = Voxel3D.focus
  if not f then return nil, nil end
  local kx, kz = tonumber(frame.sunShearX) or ShadowMap.KX or -0.85, tonumber(frame.sunShearZ) or ShadowMap.KZ or -0.55
  local kl = sqrt(kx * kx + kz * kz)
  if kl < 1e-5 then return nil, nil end
  local px, pz = -kz / kl, kx / kl -- horizontal width axis, perpendicular to sun travel
  local cell = 58
  local radius = frame.level > 0.9 and 4 or 3
  local verts=CinematicAtmos._rayVerts or {}; CinematicAtmos._rayVerts=verts
  local rows=CinematicAtmos._rayRows or {}; CinematicAtmos._rayRows=rows
  local indices=CinematicAtmos._rayIndices or {}; CinematicAtmos._rayIndices=indices
  local oldV=#verts; for i=#indices,1,-1 do indices[i]=nil end
  local q,n=0,0
  local function emit(x,y,z,u,v,phase,alpha)
    n=n+1; local row=rows[n]; if not row then row={0,0,0,0,0,0,0}; rows[n]=row end
    row[1],row[2],row[3],row[4],row[5],row[6],row[7]=x,y,z,u,v,phase,alpha; verts[n]=row
  end
  local projectionScale = orientationDensityScale(Voxel3D)
  eachWeatherCell(Voxel3D, cell, radius, function(ix, iz)
      local gate = hash2(ix, iz, 151)
      local gateBase=(frame.level > 0.9 and 0.20 or 0.30)-0.09*max(0,min(1,tonumber(frame.postRainShaft) or 0))
      if gate > gateBase then
        local hx = hash2(ix, iz, 152)
        local hz = hash2(ix, iz, 153)
        local cx = (ix + 0.18 + hx * 0.64) * cell + cloudShiftX
        local cz = (iz + 0.18 + hz * 0.64) * cell + cloudShiftZ
        local groundY = 1.5 + hash2(ix, iz, 154) * 6.0
        local height = (frame.canopy and 72 or 116) + hash2(ix, iz, 155) * (frame.canopy and 34 or 70)
        -- Keep the A4 broad footprint, but restore enough radiance that the
        -- field survives mobile display scaling and bright daytime palettes.
        local width = 46 + hash2(ix, iz, 156) * 54
        local alpha = (0.082 + hash2(ix, iz, 157) * 0.068) * frame.level
                      * (frame.lightIntensity or 1.0) * projectionScale
        local phase = hash2(ix, iz, 158) * PI2
        -- Project this shaft toward the mean cloud deck.  The helper below
        -- evaluates the same descriptors used to draw the visible cloud
        -- clusters: dense cores nearly extinguish the shaft, thin lobes only
        -- soften it.  This is true cloud/light interaction without a costly
        -- per-pixel cloud march on Android.
        if clouds and #clouds > 0 then
          -- Sample the physical sun path at each visible cloud's own height.
          -- Three samples across the broad shaft keep cloud edges soft rather
          -- than switching an entire beam on/off at once.
          local off = width * 0.34
          local t0 = cloudTransmissionAlongRay(clouds, cx, groundY, cz, 0, 0, kx, kz)
          local t1 = cloudTransmissionAlongRay(clouds, cx, groundY, cz, px * off, pz * off, kx, kz)
          local t2 = cloudTransmissionAlongRay(clouds, cx, groundY, cz, -px * off, -pz * off, kx, kz)
          alpha = alpha * (t0 * 0.50 + t1 * 0.25 + t2 * 0.25)
        end
        -- Top of the same sun ray: the light travels DOWN by (kx,-1,kz),
        -- therefore rising to the top walks opposite that horizontal shear.
        local tx = cx - kx * height
        local tz = cz - kz * height
        local hw = width * 0.5
        emit(cx - px * hw,groundY,cz - pz * hw,-1,0,phase,alpha)
        emit(cx + px * hw,groundY,cz + pz * hw, 1,0,phase,alpha)
        emit(tx + px * hw,groundY + height,tz + pz * hw, 1,1,phase,alpha)
        emit(tx - px * hw,groundY + height,tz - pz * hw,-1,1,phase,alpha)
        pushQuad(indices, q)
        q = q + 1

        -- A second, narrower slice through the same shaft prevents a ribbon
        -- vanishing when the camera lines up with the first plane.
        if frame.level > 0.9 or gate > 0.72 then
          local rx = px * 0.52 + (kx / kl) * 0.85
          local rz = pz * 0.52 + (kz / kl) * 0.85
          local rl = sqrt(rx * rx + rz * rz)
          rx, rz = rx / rl, rz / rl
          local hw2 = hw * 0.88
          local a2 = alpha * 0.46
          emit(cx - rx * hw2,groundY,cz - rz * hw2,-1,0,phase + 1.7,a2)
          emit(cx + rx * hw2,groundY,cz + rz * hw2, 1,0,phase + 1.7,a2)
          emit(tx + rx * hw2,groundY + height,tz + rz * hw2, 1,1,phase + 1.7,a2)
          emit(tx - rx * hw2,groundY + height,tz - rz * hw2,-1,1,phase + 1.7,a2)
          pushQuad(indices, q)
          q = q + 1
        end
      end
  end)
  for i=n+1,oldV do verts[i]=nil end
  return verts, indices
end

local function drawRays(Voxel3D, frame, clouds)
  if not frame or (tonumber(frame.lightIntensity) or 0) <= 0.001 then return end
  local sh = rayShader()
  if not sh then return end
  local verts, indices = buildRayVertices(Voxel3D, frame, clouds)
  if not (verts and indices and #verts > 0) then return end
  local meshOk
  rayMesh, meshOk = CinematicAtmos._uploadStreamMesh("rays", rayMesh, RAY_FORMAT, verts)
  if not meshOk then return end
  CinematicAtmos._applySequentialQuadMap("rays", rayMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "add", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  if Voxel3D.beginEffect(sh) then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "curve", CinematicAtmos._curveUniform(Voxel3D))
    local active = ShadowMap.active() and frame.sunShadowAuthority == true
    V.safeCall(sh.send, sh, "sunVP", "row", active and ShadowMap.uvVP or CinematicAtmos._uniformScratch.identity4)
    local tex = ShadowMap.texture()
    if tex then V.safeCall(sh.send, sh, "sunMap", tex) end
    V.safeCall(sh.send, sh, "sunBias", ShadowMap.bias or 0)
    V.safeCall(sh.send, sh, "sunActive", active and 1 or 0)
    V.safeCall(sh.send, sh, "rayColor", frame.rayColor)
    local sh2=CinematicAtmos._uniformScratch.shear2
    sh2[1],sh2[2]=tonumber(frame.sunShearX) or ShadowMap.KX or -0.85,tonumber(frame.sunShearZ) or ShadowMap.KZ or -0.55
    V.safeCall(sh.send, sh, "shear", sh2)
    V.safeCall(sh.send, sh, "wind", frame.wind)
    V.safeCall(sh.send, sh, "canopyY", frame.canopy and 66 or 188)
    V.safeCall(sh.send, sh, "time", ForestAtmos.time)
    V.safeCall(love.graphics.draw, rayMesh)
    Voxel3D.endEffect()
  end
end

-- ---------- clustered volumetric sky clouds

-- The visible deck and the ray occlusion share one small set of deterministic
-- descriptors every frame.  That gives us exact macro alignment at a fraction
-- of the cost of sampling procedural cloud noise in every ray fragment.
local function smoothstepLua(a, b, x)
  if a == b then return x < a and 0 or 1 end
  local t = max(0, min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

-- A13 no longer infers a fixed cloud altitude. See buildCloudDescriptors:
-- the deck is constructed from the live camera basis so cloud geometry and
-- the visible sky can no longer disagree on strongly curved/globe views.

local function projectNoCurveNdc(Voxel3D, wx, wy, wz)
  -- Clouds deliberately do not inherit the globe bend. This projection helper
  -- therefore mirrors the VP transform directly instead of Voxel3D.project(),
  -- which applies WorldCurve.drop() for terrain-bound effects.
  local m = Voxel3D.vp
  if not m then return nil end
  local cx = m[1] * wx + m[2] * wy + m[3] * wz + m[4]
  local cy = m[5] * wx + m[6] * wy + m[7] * wz + m[8]
  local cw = m[13] * wx + m[14] * wy + m[15] * wz + m[16]
  if cw <= 1e-5 then return nil end
  return cx / cw, cy / cw, cw
end

local function buildCloudDescriptors(Voxel3D, frame)
  -- CLOUDS option: OFF makes cloud banks invisible without touching precip.
  do
    local cloudsOn = true
    local S=weatherSettings()
    if S and S.cloudsOn then cloudsOn=S.cloudsOn()
    elseif S and S.get then cloudsOn=(S.get("clouds")~="off") end
    if not cloudsOn then return CinematicAtmos._emptyClouds end
  end
  if frame.canopy or not (Voxel3D.eye and Voxel3D.focus) then return CinematicAtmos._emptyClouds end
  local weather = frame.weather or WEATHER.partly
  if (weather.coverage or 0) <= 0.001 then return CinematicAtmos._emptyClouds end
  local cloudDensityScale, cloudGateBias = 1, 0
  do
    local S=weatherSettings()
    if S and S.cloudDensityScale then
      local ok,v=V.safeCall(S.cloudDensityScale); if ok and tonumber(v) then cloudDensityScale=tonumber(v) end
    end
    if S and S.cloudDensityGateBias then
      local ok,v=V.safeCall(S.cloudDensityGateBias); if ok and tonumber(v) then cloudGateBias=tonumber(v) end
    end
  end

  -- WEATHER W1: world-anchored atmosphere with persistent frustum coverage.
  --
  -- M1/M2 finally looked like clouds, but the descriptors themselves were
  -- reconstructed from the live camera basis every frame. That made the whole
  -- deck follow the camera like scenery painted on a distant shell. M3 uses an
  -- infinite deterministic X/Z lattice instead. The lattice advects through
  -- world space with one coherent wind vector, so walking/rotating the camera
  -- produces genuine near/mid/far parallax and a cloud can actually pass
  -- overhead rather than remaining pinned to the upper screen.
  local e, f = Voxel3D.eye, Voxel3D.focus
  local fx, fy, fz = f[1] - e[1], f[2] - e[2], f[3] - e[3]
  local camDist = sqrt(fx * fx + fy * fy + fz * fz)
  if camDist < 1e-6 then return CinematicAtmos._emptyClouds end
  fx, fy, fz = fx / camDist, fy / camDist, fz / camDist

  -- 8.2.9 cloud-pitch continuity. Cloud existence/opacity must never depend on
  -- camera pitch. Normalize only the horizontal heading for the bounded far-bank
  -- corridor; pitching up/down then changes framing while the world cloud field
  -- itself stays unchanged. The nearby ring is radial, so it also survives an
  -- almost-vertical look direction.
  local flatLen=sqrt(fx*fx+fz*fz)
  local flatFx,flatFz=0,-1
  if flatLen>1e-6 then flatFx,flatFz=fx/flatLen,fz/flatLen end
  local flatSideX,flatSideZ=-flatFz,flatFx

  local aspect = viewportAspect(Voxel3D)

  -- MOSTLY CLOUDY M6: size parity is a separate problem from deck height.
  -- A15-M5 used 1/aspect, which perfectly cancels the orbit camera distance
  -- only for geometry attached to the focus plane.  These clouds are world-
  -- anchored at independent near/mid/far depths, so that correction shrank
  -- them far too much in a wide landscape view.  Use a gentler projection
  -- compensation instead: portrait remains the authored 1.0 reference, while
  -- a ~2.16:1 handset landscape uses ~0.76 world scale.  The closer landscape
  -- eye then restores the missing projected size without returning to A14's
  -- giant screen-filling cloud sheets.
  local orientationScale = aspect > 1.0 and (aspect ^ -0.35) or 1.0

  -- MOSTLY CLOUDY M5: portrait is the approved vertical-composition reference.
  -- Dramatic Shape's short landscape viewport changes the orbit-camera geometry
  -- enough that the same absolute cloud altitude projects too close to the top
  -- of the screen.  Lower the entire weather deck smoothly as the viewport gets
  -- wider.  This is a descriptor-space correction, so visible cloud geometry
  -- and god-ray occlusion continue to use the exact same physical cloud height.
  -- At the test handset's ~2.16:1 landscape aspect this is ~34 world units;
  -- portrait (aspect <= 1) is untouched.
  local landscapeBlend = max(0.0, min(1.0, (aspect - 1.0) / 1.15))
  local landscapeCloudDrop = 34.0 * landscapeBlend

  local now = ForestAtmos.time
  -- One menu read per cloud build, never per cloud cell. ORIGINAL is exactly
  -- the pre-8.1.22 geometry; RAISED preserves 8.1.22's 150% altitude.
  local heightScale = CinematicAtmos._cloudHeightScale()

  -- One slow coherent weather flow. Because candidate indices are evaluated
  -- in the inverse-advected lattice, positions are continuous for arbitrarily
  -- long sessions instead of being recycled around the camera.
  local cell = weather.cell or 185.0
  -- Integrated WindEngine displacement is continuous across direction changes.
  -- Never compute globalTime * currentDirection here: that teleports the cloud
  -- lattice whenever the wind veers.
  local advX, advZ = 0, 0
  if frame.windState then
    advX = tonumber(frame.windState.advectX) or 0
    advZ = tonumber(frame.windState.advectZ) or 0
  else
    advX, advZ = now * 0.43, now * -0.14
  end

  -- Search the world corridor between the player's focus and the camera eye,
  -- not merely around the map centre. This is what allows real foreground
  -- atmospheric masses to exist physically between the viewer and Kanto.
  -- CLOUD SPACE, not raw world space.
  --
  -- This is the cloud BANK lattice -- a second, separate cloud path from the
  -- eachWeatherCell grid. 4.30.84 moved that grid into cloud space so the deck
  -- survived a map change; this lattice was missed, and it is the one that
  -- carries the bank on most weathers. So the bank still jumped at every load
  -- point even though the other layer no longer did.
  --
  -- Same correction: subtract the accumulated map-change shift before deriving
  -- lattice cell identity. Within a map the shift is constant, so advection and
  -- streaming are completely unchanged; across a map change it cancels the
  -- teleport and the same bank stays overhead.
  -- 8.2.0 GLOBAL CLOUD LOOK-UP CONTINUITY.  Candidate identity must not be
  -- derived from the eye/focus corridor because that corridor changes when the
  -- camera pitches even if the player has not moved.  Center the bounded lattice
  -- search on the gameplay/world precipitation anchor instead.  Camera pitch now
  -- affects only projection, never which physical cloud cells exist.
  local cloudAnchor=worldPrecipAnchor(Voxel3D)
  local midX = (tonumber(cloudAnchor and cloudAnchor[1]) or e[1] or 0) - cloudShiftX
  local midZ = (tonumber(cloudAnchor and cloudAnchor[3]) or e[3] or 0) - cloudShiftZ
  local bix = floor((midX - advX) / cell)
  local biz = floor((midZ - advZ) / cell)

  local candidates=CinematicAtmos._cloudCandidates
  for i=#candidates,1,-1 do candidates[i]=nil end
  local candidatePool=CinematicAtmos._cloudCandidatePool
  local candidateCount=0
  local MF=cachedRequire("MesoscaleField")
  local mesoScratch=CinematicAtmos._mesoCloudScratch
  -- Only widen the expensive horizon search while a finite localized cell is
  -- actually creating a partial-map front around the player. Ordinary sealed
  -- weather keeps the proven 8.1.21 search budget for potato-class devices.
  local localizedSpatial = (V and V.weatherFxSpatialLocalized == true)
    or (tonumber(V and V.weatherFxSpatialStrength) or 1) < .995
    or (tonumber(V and V.weatherFxSpatialCloud) or 1) < .995
  local frontCloudAuthority=max(0,min(1,tonumber(V and V.weatherFxSpatialCloud) or 1))
  local searchSide = localizedSpatial
    and max(5, min(10, math.ceil(5.4 * max(1.0, aspect))))
    or max(4, min(7, math.ceil(4.2 * max(1.0, aspect))))
  local searchDepth = localizedSpatial and 9 or 6

  for iz = biz - searchDepth, biz + searchDepth do
    for ix = bix - searchSide, bix + searchSide do
      -- M3 proved that roughly 70% occupied lattice cells only *looked* Partly
      -- Cloudy once perspective/frustum filtering was applied.  Mostly Cloudy
      -- needs a tighter lattice and a higher occupancy target, while still
      -- leaving irregular blue-sky breaks for dramatic shafts.
      local gate = hash2(ix, iz, 230)
      local gateAt = weather.gate or 0.18
      local softGate = weather.softGate or 0.0
      -- Sample the same mesoscale field that owns local precipitation. During
      -- natural transitions and broken-cloud weather it changes the probability
      -- that this persistent world cell contains cloud, so formations grow,
      -- merge and open into blue-sky gaps as moisture bands advect through.
      -- Fully established manual storm/rain profiles deliberately keep their
      -- authored sealed deck: selecting THUNDERSTORM still covers the sky now.
      local probeX=(ix + 0.50) * cell + advX + cloudShiftX
      local probeZ=(iz + 0.50) * cell + advZ + cloudShiftZ
      local meso=nil
      if MF and MF.sampleInto and (not MF.ready or MF.ready()) then
        local sx,sz=probeX,probeZ
        local WS=cachedRequire("WeatherWorldSpace")
        if WS and WS.toWorld then sx,sz=WS.toWorld(probeX,probeZ,map and map.id) end
        meso=MF.sampleInto(sx,sz,mesoScratch)
      end
      local localCloud=meso and tonumber(meso.cloud) or tonumber(weather.coverage) or 0
      if localizedSpatial then localCloud=min(max(0,localCloud),frontCloudAuthority) end
      local spatialCloudRatio=1.0
      if meso and (frame.weather and frame.weather._transitionActive == true or (tonumber(weather.coverage) or 0) < .95 or localizedSpatial) then
        local simGate=1.01-max(0,min(1,localCloud))*1.02
        gateAt=lerp(gateAt,simGate,.68)
        softGate=max(softGate,.055)
        spatialCloudRatio=max(localizedSpatial and .04 or .18,min(1.18,localCloud/max(.12,tonumber(weather.coverage) or .12)))
      end
      gateAt=max(-0.25,min(1.25,gateAt+cloudGateBias))
      local occupancyAlpha
      if softGate > 0.0001 then
        occupancyAlpha = smoothstepLua(gateAt - softGate, gateAt + softGate, gate)
      else
        occupancyAlpha = gate > gateAt and 1.0 or 0.0
      end
      if occupancyAlpha > 0.01 then
        local seedX, seedZ = ix, iz
        local styleA = hash2(seedX, seedZ, 246)
        local styleB = hash2(seedX, seedZ, 247)
        local styleC = hash2(seedX, seedZ, 248)
        local bankBias = weather.bank or 0.34
        local towerCut = min(0.94, bankBias + 0.48)
        local kind = styleA < bankBias and 0 or (styleA < towerCut and 1 or 2)
        local deckBlend = max(0.0, min(1.0, weather.deckBlend ~= nil
                          and weather.deckBlend or (weather.closedDeck and 1.0 or 0.0)))
        deckBlend=max(0,min(1,deckBlend*spatialCloudRatio))
        -- As the dynamic continuum approaches overcast, more formations become
        -- broad stratiform banks progressively rather than all changing type on
        -- one frame. Manual overcast still resolves to a fully sealed deck.
        if hash2(seedX, seedZ, 251) < deckBlend then kind = 0 end

        -- Stable world-space centre plus coherent global wind advection.
        -- Identity comes from the cloud-space lattice above; the DRAWN
        -- position has to come back to world space, or after a map-change
        -- shift the bank would be rendered offset from the player by the
        -- whole accumulated jump. Shift out here, exactly as it was shifted
        -- in when bix/biz were derived.
        local cx = (ix + 0.12 + hash2(ix, iz, 232) * 0.76) * cell + advX + cloudShiftX
        local cz = (iz + 0.12 + hash2(ix, iz, 233) * 0.76) * cell + advZ + cloudShiftZ

        -- Absolute cloud altitude, deliberately independent of camera pitch.
        -- The range is several building heights above the world: low enough
        -- for near formations to feel overhead, high enough to stay sky-like.
        local brokenCy = (92.0 + hash2(ix, iz, 234) * 84.0) * heightScale
        if kind == 2 then brokenCy = brokenCy + 12.0 + styleC * 20.0 end
        local deckCy = (weather.deckY0 or 116.0) * heightScale
                     + hash2(ix, iz, 234) * (weather.deckYSpan or 26.0)
        local cy = lerp(brokenCy, deckCy, deckBlend) - landscapeCloudDrop

        -- 8.2.9: no camera projection is used to decide whether this cloud cell
        -- exists or how opaque it is. That removes the last pitch-dependent
        -- descriptor/fade seam and also saves one projection per candidate.
        local hdx,hdz=cx-e[1],cz-e[3]
        local horizontalDepth=sqrt(hdx*hdx+hdz*hdz)
        local horizontalForward=hdx*flatFx+hdz*flatFz
        local horizontalSide=abs(hdx*flatSideX+hdz*flatSideZ)
        -- A sealed rain/storm deck is an overhead world volume, not a list of
        -- billboard centres. When the camera pitches toward zenith the centre
        -- of a huge nearby bank can project outside the old narrow NDC band even
        -- while the volume fills the entire view. Admit a small bounded ring of
        -- physically overhead sealed-deck cells by world distance; broken
        -- clouds keep the ordinary projection/frustum rule.
        -- 8.2.0: overhead admission belongs to EVERY 3D cloud family, not only
        -- sealed decks.  A physically nearby cloud volume must not disappear just
        -- because its centre projects past the top edge while the player looks up.
        -- This bounded world-space shoulder is camera-pitch independent and keeps
        -- broken, snow, storm and sealed cloud banks continuous at zenith.
        -- 8.2.8 zenith persistence. The prior 2.90-cell shoulder could leave
        -- only the 0.12 alpha floor when a real first-person camera pitched up,
        -- which looked like the bank switched off even though descriptors still
        -- technically existed. Keep a bounded but wider physical overhead
        -- neighbourhood and a visible shoulder floor for every cloud family.
        -- This is camera-independent world distance, so looking up/down cannot
        -- create or delete cloud cells; it only changes which part is framed.
        local overheadOuter=cell*3.35
        local overheadInner=cell*2.55
        local overheadFloor=.24
        local overheadCloud=horizontalDepth <= overheadOuter
        -- The old projected-NDC Y admission caused the visible bank to vanish
        -- from the bottom upward as pitch increased. Keep a yaw-only horizontal
        -- corridor for distant work and a radial overhead neighbourhood nearby.
        -- Neither admission nor opacity below contains camera pitch.
        local corridorSide=cell*(searchSide*.62+.58)
        local corridorForward=cell*(searchDepth+.50)
        local corridorBack=cell*1.20
        local sideFade=1.0-smoothstepLua(corridorSide*.82,corridorSide,horizontalSide)
        local rearFade=smoothstepLua(-corridorBack,-corridorBack*.20,horizontalForward)
        local farFade=1.0-smoothstepLua(corridorForward*.84,corridorForward,horizontalForward)
        local corridorAlpha=max(0.0,min(1.0,sideFade*rearFade*farFade))
        local radial=1.0-smoothstepLua(overheadInner,overheadOuter,horizontalDepth)
        local worldAdmission=max(corridorAlpha,overheadCloud and max(overheadFloor,radial) or 0.0)
        if worldAdmission>0.01 then
            local dx, dy, dz = cx - e[1], cy - e[2], cz - e[3]
            local forwardDepth = horizontalDepth
            local relativeDepth = horizontalDepth/max(cell,1)
            local depthClass
            if horizontalDepth < cell*2.35 then depthClass = 0      -- near / overhead
            elseif horizontalDepth < cell*4.55 then depthClass = 1 -- mid atmosphere
            else depthClass = 2 end                                -- distant deck

              -- Fixed world dimensions are important here: perspective should
              -- make a near cloud genuinely larger than a far cloud. M6 applies
              -- only a gentle landscape projection correction above; unlike the
              -- old 1/aspect rule it preserves most of the physical cloud size,
              -- so portrait and landscape now keep comparable apparent scale.
              local spanX, spanY, spanZ
              if kind == 0 then
                spanX = (76 + styleB * 52) * orientationScale
                spanY = (16 + styleC * 12) * orientationScale
                spanZ = (38 + styleB * 30) * orientationScale
              elseif kind == 2 then
                spanX = (52 + styleB * 42) * orientationScale
                spanY = (30 + styleC * 20) * orientationScale
                spanZ = (31 + styleB * 29) * orientationScale
              else
                spanX = (58 + styleB * 48) * orientationScale
                spanY = (21 + styleC * 16) * orientationScale
                spanZ = (33 + styleB * 31) * orientationScale
              end
              local weatherSpan = weather.span or 1.0
              spanX, spanY, spanZ = spanX * weatherSpan, spanY * weatherSpan, spanZ * weatherSpan
              if deckBlend > 0.001 then
                -- Geometric closure grows continuously as the continuum moves
                -- through Cloudy toward Overcast. The minimum overlap expands
                -- with deckBlend; at 1.0 it is the exact sealed-ceiling rule.
                local minX = cell * lerp(0.72, weather.deckWidth or 1.82, deckBlend) * orientationScale
                local minZ = cell * lerp(0.52, weather.deckDepth or 1.12, deckBlend) * orientationScale
                spanX = max(spanX, minX)
                spanZ = max(spanZ, minZ)
                spanY = max(spanY, 28.0 * orientationScale * deckBlend)
              end

              -- Nearby formations get a little more internal structure and a
              -- softer per-lobe alpha. The extra overlap creates density while
              -- preserving the undefined volume language the user preferred.
              local puffs
              if kind == 0 then puffs = frame.level > 0.9 and 36 or 28
              elseif kind == 2 then puffs = frame.level > 0.9 and 39 or 30
              else puffs = frame.level > 0.9 and 37 or 29 end
              if depthClass == 0 then puffs = puffs + 7
              elseif depthClass == 2 then puffs = max(22, puffs - 5) end
              puffs = max(10, floor(puffs * (weather.puffs or 1.0) * (.68 + .32*performanceScale()) * CinematicAtmos._qualityCloudDetail() + 0.5))
              if deckBlend > 0.001 then
                local deckMin = floor(lerp(12, frame.level > 0.9 and 34 or 28, deckBlend) * CinematicAtmos._qualityCloudDetail() + 0.5)
                puffs = max(puffs, deckMin)
              end
              puffs=max(6,floor(puffs*cloudDensityScale+0.5))

              -- Prefer atmospheric centres in the upper half, but don't force
              -- every cloud into one horizon band. Near clouds may sit partly
              -- above frame; distant clouds are allowed closer to the horizon.
              -- Yaw-only desirability is diagnostic/sort-neutral; pitch never
              -- changes descriptor identity, puff count, or opacity.
              local desirability=(horizontalSide/max(1,corridorSide))*.10
                +(horizontalDepth/max(1,corridorForward))*.03+depthClass*.015

              -- World-space shoulder fade. Cloud opacity is driven only by
              -- persistent lattice occupancy plus the bounded horizontal world
              -- corridor/radial ring. The GPU clips geometry to the pitched view.
              local fadeAlpha=max(0.0,min(1.0,occupancyAlpha*worldAdmission))

              if fadeAlpha > 0.01 then
                candidateCount=candidateCount+1
                local c=candidatePool[candidateCount]
                if not c then c={};candidatePool[candidateCount]=c end
                c.ix,c.iz=seedX,seedZ
                c.cx,c.cz,c.cy=cx,cz,cy
                c.orientationScale=orientationScale
                c.kind,c.spanX,c.spanY,c.spanZ=kind,spanX,spanY,spanZ
                c.puffs,c.depthClass,c.deckBlend=puffs,depthClass,deckBlend
                c.closedDeck=deckBlend>=0.985
                c.relativeDepth,c.desirability=relativeDepth,desirability
                c.forwardDepth,c.fadeAlpha=forwardDepth,fadeAlpha
                c.evolveRate=hash2(seedX,seedZ,250)
                c.angle=(hash2(seedX,seedZ,245)*2-1)*0.22
                -- 8.1.24: these descriptor-space values are invariant for every
                -- occlusion query this frame. God rays may ask cloudBodyAt many
                -- times, so do the trig/span setup once when the descriptor is
                -- authored instead of once per ray/cloud intersection.
                c._bodyCa,c._bodySa=cos(c.angle),sin(c.angle)
                c._bodySx,c._bodySz=spanX*1.22,spanZ*1.18
                c.styleA,c.styleB,c.styleC=styleA,styleB,styleC
                c.phase=hash2(seedX,seedZ,249)*PI2
                candidates[candidateCount]=c
              end
        end
      end
    end
  end

  -- M3 ranked candidates by camera-relative desirability and then kept only
  -- 8/10.  On a wide landscape frustum tiny camera changes could reorder that
  -- list and instantly replace one fully visible cloud with another.  M4 does
  -- not camera-rank/cull visible formations.  The broad shoulder fade above
  -- is the budget boundary; all surviving candidates are drawn, sorted only
  -- back-to-front for stable alpha blending.
  table.sort(candidates, CinematicAtmos._cloudSort)

  return candidates
end

-- 8.1.37 REAL FRONT/BANK INTEGRATION
--
-- A distant front used to be rendered by a second cloud system: dark tessellated
-- ellipsoids with an independent cloudBase/tower altitude. That was visually
-- disconnected from the approved cloud bank and could read as stacked charcoal
-- balls. A front is now authored as several ordinary cloud DESCRIPTORS and then
-- appended to the same descriptor field returned above. From this point onward
-- front and bank clouds are indistinguishable to the renderer, god-ray/cloud
-- transmission code and depth buffer.
--
-- The visible bank is authoritative for altitude whenever it publishes a deck.
-- If the local sky has no deck yet (for example, a storm still on the horizon),
-- the incoming weather family's deck supplies the same equation. Cloud centers
-- remain inside that single deck band; maturity increases horizontal thickness
-- and puff density, never a separate vertical stack.
function CinematicAtmos._frontCloudDeck(Voxel3D, frame, remoteWeatherId)
  local profile=frame and frame.weather or nil
  if not (profile and tonumber(profile.deckY0)) then
    local key=wxAtmosProfileKey(remoteWeatherId)
    profile=(key and WEATHER[key]) or WEATHER.overcast
  end
  local heightScale=CinematicAtmos._cloudHeightScale()
  local aspect=viewportAspect(Voxel3D)
  local landscapeBlend=max(0.0,min(1.0,(aspect-1.0)/1.15))
  local landscapeCloudDrop=34.0*landscapeBlend
  local base=(tonumber(profile and profile.deckY0) or 116.0)*heightScale-landscapeCloudDrop
  local span=tonumber(profile and profile.deckYSpan) or 26.0
  return profile,base,span
end

function CinematicAtmos._appendFrontCloudDescriptors(Voxel3D, frame, clouds, map)
  -- Honor the exact same CLOUDS switch as the ordinary bank.
  local cloudsOn=true
  local S=weatherSettings()
  if S and S.cloudsOn then
    local ok,v=V.safeCall(S.cloudsOn);if ok then cloudsOn=v and true or false end
  elseif S and S.get then
    local ok,v=V.safeCall(S.get,"clouds");if ok then cloudsOn=(v~="off") end
  end
  if not cloudsOn or (frame and frame.canopy) then return clouds or CinematicAtmos._emptyClouds,0 end

  local D=cachedRequire("DistantWeather")
  local W=cachedRequire("WeatherWorldSpace")
  if not (D and D.items and W and W.toLocal) then return clouds or CinematicAtmos._emptyClouds,0 end
  local items,count=D.items()
  count=math.min(4,tonumber(count) or 0)
  if type(items)~="table" or count<=0 then return clouds or CinematicAtmos._emptyClouds,0 end

  local out=clouds
  if type(out)~="table" or out==CinematicAtmos._emptyClouds then
    out=CinematicAtmos._frontCloudCandidates
    for i=#out,1,-1 do out[i]=nil end
  end
  local baseCount=#out
  local pool=CinematicAtmos._frontCloudPool
  local poolN=0
  local eye=Voxel3D.eye or Voxel3D.player or Voxel3D.focus or {0,0,0}
  local ex,ey,ez=tonumber(eye[1]) or 0,tonumber(eye[2]) or 0,tonumber(eye[3]) or 0
  local camFx,camFy,camFz=0,0,1
  if Voxel3D.eye and Voxel3D.focus then
    camFx=(tonumber(Voxel3D.focus[1]) or 0)-(tonumber(Voxel3D.eye[1]) or 0)
    camFy=(tonumber(Voxel3D.focus[2]) or 0)-(tonumber(Voxel3D.eye[2]) or 0)
    camFz=(tonumber(Voxel3D.focus[3]) or 0)-(tonumber(Voxel3D.eye[3]) or 0)
    local cl=sqrt(camFx*camFx+camFy*camFy+camFz*camFz)
    if cl>.001 then camFx,camFy,camFz=camFx/cl,camFy/cl,camFz/cl else camFx,camFy,camFz=0,0,1 end
  end
  local mapId=map and map.id or nil
  local far=max(320,tonumber(Voxel3D.far) or 900)
  local aspect=viewportAspect(Voxel3D)
  local orientationScale=aspect>1.0 and (aspect^-0.35) or 1.0
  local frontDensityScale=1
  if S and S.cloudDensityScale then
    local ok,v=V.safeCall(S.cloudDensityScale);if ok and tonumber(v) then frontDensityScale=tonumber(v) end
  end

  for i=1,count do
    local a=items[i]
    local cloud=max(0,min(1,tonumber(a and a.cloud) or 0))
    if a and cloud>.015 and a.x and a.z then
      local anchorX=tonumber(a.bankX) or tonumber(a.x)
      local anchorZ=tonumber(a.bankZ) or tonumber(a.z)
      local lx,lz=W.toLocal(anchorX,anchorZ,mapId)
      lx,lz=tonumber(lx),tonumber(lz)
      if lx and lz then
        local dx,dz=lx-ex,lz-ez
        local len=sqrt(dx*dx+dz*dz)
        local fx,fz=tonumber(a.vx) or 0,tonumber(a.vz) or 0
        local fl=sqrt(fx*fx+fz*fz)
        if fl<.001 then
          if len>.001 then fx,fz=-dx/len,-dz/len else fx,fz=0,1 end
        else fx,fz=fx/fl,fz/fl end
        local crx,crz=-fz,fx
        local _,deckBase,deckSpan=CinematicAtmos._frontCloudDeck(Voxel3D,frame,a.cloudWeather or a.weather)
        local stage=tostring(a.stage or "mature")
        local sizeClass=tostring(a.sizeClass or "legacy")
        local lifeU=max(0,min(1,tonumber(a.lifeU) or .5))
        -- Fixed cloud topology for the entire life of a front. Earlier builds
        -- changed row/column counts at named lifecycle stages; even with smooth
        -- front motion that destroys/recreates descriptor positions on one
        -- frame and reads as a jump. Geometry identity is now stable from first
        -- formation through final parting; only continuous alpha/scale terms
        -- evolve.
        local columns=(sizeClass=="synoptic" and 8) or (sizeClass=="broad" and 7)
          or (sizeClass=="regional" and 5) or 4
        local rowsN=2
        local nDesc=columns*rowsN
        local growU=smoothstepLua(0,.30,lifeU)
        local partU=smoothstepLua(.72,1.0,lifeU)
        -- Use the physical CROSS-FRONT radius for the visible wall. The old
        -- renderer hard-capped every bank at 760 units, so even a genuinely
        -- broad simulated system looked like the same small cloud patch.
        local physicalCross=max(tonumber(a.rz) or 220,180)
        local visualCap=max(900,far*2.25)
        local width=max(180,min(visualCap,physicalCross*((sizeClass=="synoptic" and 1.16) or (sizeClass=="broad" and 1.10) or 1.04)))
        local id=tonumber(a.id) or i
        local step=width/max(1,columns-.45)
        local maturity=(.58+.42*smoothstepLua(.04,.30,lifeU))*(1-.16*partU)
        local deckBlend=max(0,min(1,.62+.38*maturity))

        for l=1,nDesc do
          poolN=poolN+1
          local c=pool[poolN];if not c then c={};pool[poolN]=c end
          local col=(l-1)%columns
          local row=floor((l-1)/columns)
          local seedX=floor(id*131+l*17+37)
          local seedZ=floor(id*197+l*29+53)
          local styleA=hash2(seedX,seedZ,246)
          local styleB=hash2(seedX,seedZ,247)
          local styleC=hash2(seedX,seedZ,248)
          -- Each stable descriptor has a different deterministic birth/parting
          -- threshold. As the front develops, cloud masses therefore appear
          -- progressively across both rows instead of the whole wall popping in
          -- at a stage boundary. Dissipation uses a separate ordering so holes
          -- open organically rather than reversing the formation sequence.
          local birth=.18+.64*hash2(seedX,seedZ,252)
          local death=.18+.64*hash2(seedX,seedZ,253)
          local growthAlpha=smoothstepLua(birth-.12,birth+.12,growU)
          local partAlpha=1-smoothstepLua(death-.12,death+.12,partU)
          local lifeAlpha=growthAlpha*partAlpha
          local centered=col-(columns-1)*.5
          -- Two staggered X/Z rows make a thick physical frontal bank. There is
          -- intentionally NO vertical row/stack: Y always comes from deckBase +
          -- the same deterministic deckYSpan equation as ordinary cloud cells.
          local cross=centered*step+(row==1 and step*.34 or 0)
          local along=(row-(rowsN-1)*.5)*step*.62+(styleA-.5)*step*.22
          local cx=lx+crx*cross+fx*along
          local cz=lz+crz*cross+fz*along
          local cy=deckBase+hash2(seedX,seedZ,234)*deckSpan
          local spacing=max(62,step)
          local broad=spacing*(.92+styleB*.30)*orientationScale
          local deep=spacing*(.62+styleC*.24)*orientationScale
          -- Axis-aligned descriptor extents overlap aggressively enough that the
          -- shared puff renderer reads one cloud mass from every heading. The
          -- FRONT orientation still comes from physical descriptor placement.
          local spanX=max(64,broad*(.82+abs(crx)*.32)+deep*abs(fx)*.24)
          local spanZ=max(46,broad*(.82+abs(crz)*.32)+deep*abs(fz)*.24)
          local spanY=(22+styleC*10+8*maturity)*orientationScale
          local kind=(l%5==0) and 2 or (((l+row)%3==0) and 1 or 0)
          local px,py,pz=cx-ex,cy-ey,cz-ez
          local forwardDepth=px*camFx+py*camFy+pz*camFz
          local depthClass=len<far*.62 and 1 or 2

          c.ix,c.iz=seedX,seedZ
          c.cx,c.cy,c.cz=cx,cy,cz
          c.orientationScale=orientationScale
          c.kind,c.spanX,c.spanY,c.spanZ=kind,spanX,spanY,spanZ
          c.puffs=max(12,floor((34+styleC*5)*(.94+styleC*.12)*frontDensityScale+.5))
          c.depthClass,c.deckBlend=depthClass,deckBlend
          c.closedDeck=deckBlend>=.985
          c.relativeDepth=len/far;c.desirability=len/far
          c.forwardDepth,c.fadeAlpha=forwardDepth,cloud*lifeAlpha*(.90+.10*styleB)
          c.evolveRate=hash2(seedX,seedZ,250)
          c.angle=0
          -- Coarse celestial/god-ray occlusion follows the front's cross/travel
          -- axes even though the visible puffs use the bank's ordinary renderer.
          c._bodyCa,c._bodySa=crx,-crz
          c._bodySx,c._bodySz=max(spanX,spanZ)*1.26,max(42,min(spanX,spanZ)*.90)
          c.styleA,c.styleB,c.styleC=styleA,styleB,styleC
          c.phase=hash2(seedX,seedZ,249)*PI2
          c._frontCloud=true;c._frontFx,c._frontFz=fx,fz
          c._frontCrossX,c._frontCrossZ=crx,crz
          c._frontPuffKey=tostring(sizeClass)..":"..tostring(columns)..":"..tostring(row)..":"..tostring(l)
          out[#out+1]=c
        end
      end
    end
  end
  for i=poolN+1,#pool do
    -- Retain pool objects for reuse but make stale diagnostic identity explicit.
    pool[i]._frontCloud=false
  end
  if #out>1 then table.sort(out,CinematicAtmos._cloudSort) end
  return out,#out-baseCount
end

-- Read-only executable seam used by the 8.1.37 integration regression.
function CinematicAtmos.frontCloudDescriptorProbe(Voxel3D,frame,map)
  local list,n=CinematicAtmos._appendFrontCloudDescriptors(Voxel3D,frame,CinematicAtmos._emptyClouds,map)
  return list,n
end

local function cloudBodyAt(c, x, z)
  local ca,sa=c._bodyCa,c._bodySa
  if ca==nil or sa==nil then ca,sa=cos(c.angle),sin(c.angle) end
  local dx, dz = x - c.cx, z - c.cz
  local rx = dx * ca - dz * sa
  local rz = dx * sa + dz * ca
  local sx=c._bodySx or ((c.spanX or 80)*1.22)
  local sz=c._bodySz or ((c.spanZ or 46)*1.18)
  local kind = c.kind or 1

  local function lobe(ox, oz, wx, wz, lo, hi)
    local px = (rx - ox) / max(wx, 1)
    local pz = (rz - oz) / max(wz, 1)
    local d = sqrt(px * px + pz * pz)
    return 1 - smoothstepLua(lo, hi, d)
  end

  -- Macro occlusion mirrors the visible archetype: a bank is wider/flatter,
  -- classic cumulus has three strong bodies, and a tower has a compact dense
  -- centre. This is deliberately coarse; the ray should soften under cloud
  -- mass, not flicker at every individual billboard feather.
  local b0 = lobe(0, 0, sx, sz, 0.52, 1.02)
  local b1 = lobe(-sx * 0.46, sz * 0.05, sx * 0.66, sz * 0.76, 0.47, 1.00)
  local b2 = lobe( sx * 0.44,-sz * 0.06, sx * 0.64, sz * 0.80, 0.47, 1.00)
  local b3
  if kind == 0 then
    b3 = lobe(0, sz * 0.25, sx * 0.80, sz * 0.54, 0.44, 0.98)
  elseif kind == 2 then
    b3 = lobe(0, sz * 0.18, sx * 0.48, sz * 0.56, 0.38, 0.94)
  else
    b3 = lobe(0, sz * 0.31, sx * 0.60, sz * 0.60, 0.43, 0.97)
  end
  return max(max(b0, b1), max(b2, b3)) * (c.fadeAlpha or 1.0)
end

-- Localised: was a global (see lerp above).
cloudTransmissionAt = function(clouds, x, z)
  local density = 0
  for i = 1, #clouds do
    local c = clouds[i]
    local dx, dz = x - c.cx, z - c.cz
    if dx * dx + dz * dz < 42000 then
      density = max(density, cloudBodyAt(c, x, z))
      if density > 0.90 then break end
    end
  end
  local core = smoothstepLua(0.20, 0.88, density)
  return lerp(1.0, 0.07, core)
end

-- Evaluate a shaft where it actually crosses EACH cloud's visible altitude.
-- A11 projected every shaft to a hard-coded Y=174 even though the visible
-- cloud geometry was elsewhere. With frustum-aware clouds that would make the
-- light/cloud relationship drift apart. This follows the sun shear from the
-- shaft foot to each cloud centre, so the same cloud that is visible is the
-- cloud that blocks the beam.
-- Localised: was a global (see lerp above).
cloudTransmissionAlongRay = function(clouds, bx, by, bz, ox, oz, kxOverride, kzOverride)
  local kx, kz = tonumber(kxOverride) or ShadowMap.KX or -0.85, tonumber(kzOverride) or ShadowMap.KZ or -0.55
  local density = 0
  for i = 1, #clouds do
    local c = clouds[i]
    local up = max(0, c.cy - by)
    local x = bx - kx * up + (ox or 0)
    local z = bz - kz * up + (oz or 0)
    local dx, dz = x - c.cx, z - c.cz
    if dx * dx + dz * dz < 42000 then
      density = max(density, cloudBodyAt(c, x, z))
      if density > 0.92 then break end
    end
  end
  local core = smoothstepLua(0.18, 0.86, density)
  return lerp(1.0, 0.055, core)
end

-- 8.1.53: regional cloud cover for WORLD lighting. The old observer used
-- `1 - playerRayTransmission` as cloud coverage, which turned one sun hole over
-- the player into a map-wide daylight boost. Sample a bounded 3x3 footprint
-- across the rendered weather corridor instead; the centre ray is still kept
-- separately for solar-disc/deep-sky occlusion.
function CinematicAtmos._regionalCloudCoverage(clouds, Voxel3D, frame)
  if not clouds or #clouds==0 then return 0 end
  local foc=Voxel3D and (Voxel3D.player or Voxel3D.focus or Voxel3D.eye)
  if not foc then return nil end
  local kx,kz=tonumber(frame and frame.sunShearX) or ShadowMap.KX or -0.85,tonumber(frame and frame.sunShearZ) or ShadowMap.KZ or -0.55
  local by=tonumber(foc[2]) or 0
  -- Two map-scale cloud cells across either side is enough to reject a tiny
  -- local opening without turning this into a per-pixel cloud march.
  local step=176
  local blocked,n=0,0
  for iz=-1,1 do for ix=-1,1 do
    local tr=cloudTransmissionAlongRay(clouds,(tonumber(foc[1]) or 0)+ix*step,by,(tonumber(foc[3]) or 0)+iz*step,0,0,kx,kz)
    blocked=blocked+(1-max(0,min(1,tonumber(tr) or 1))); n=n+1
  end end
  return n>0 and max(0,min(1,blocked/n)) or 0
end

local CLOUD_SHADER = [[
  varying vec2 vLocal;
  varying float vPhase;
  varying float vAlpha;
#ifdef VERTEX
  uniform mat4 vp;
  uniform vec3 axisR;
  uniform vec3 axisU;
  uniform float time;
  attribute vec4 CloudData;    // local x, local y, phase, alpha
  attribute vec4 CloudShape;   // half width, half height, drift, rate

  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 base = vertex_position.xyz;
    // Same deliberately conservative structure as the proven Android particle
    // shader: a world-space centre plus two camera-facing axes. The puff only
    // breathes/drifts slightly; the macro lane drift is handled by Lua.
    float t = time * CloudShape.w + CloudData.z;
    base.x += sin(t * 0.53 + CloudData.z * 3.7) * CloudShape.z;
    base.z += cos(t * 0.41 + CloudData.z * 2.9) * CloudShape.z * 0.58;
    base.y += sin(t * 0.29 + CloudData.z * 5.1) * 1.8;

    vLocal = CloudData.xy;
    vPhase = CloudData.z;
    vAlpha = CloudData.w;
    vec3 p = base + axisR * (CloudData.x * CloudShape.x)
                  + axisU * (CloudData.y * CloudShape.y);
    return vp * vec4(p, 1.0);
  }
#endif
#ifdef PIXEL
  uniform vec3 cloudColor;
  uniform vec3 rayColor;
  uniform vec2 sunScreen;
  uniform float sunsetWarmth;
  uniform float sunDiscVisibility;
  uniform float solarRayRamp;
  uniform float time;

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p = vLocal;
    // One puff is soft and rounded. Cloud complexity comes from many puffs at
    // independent sizes/depths, which is both more natural and much cheaper on
    // Android than one procedural mega-shader.
    float d = length(vec2(p.x * 0.94, p.y * 1.04));
    float body = 1.0 - smoothstep(0.56, 1.0, d);
    float inner = 1.0 - smoothstep(0.20, 0.82, d);
    float detail = 0.94
      + 0.035 * sin(p.x * 10.0 + p.y * 6.0 + vPhase * 7.0 + time * 0.020)
      + 0.025 * sin(p.x * 17.0 - p.y * 11.0 + vPhase * 11.0);
    float a = clamp(vAlpha * body * detail, 0.0, 0.96);

    float underside = mix(0.62, 1.02, smoothstep(-0.82, 0.72, p.y));
    vec2 n = normalize(p + vec2(0.0001));
    vec2 sdir = normalize(sunScreen + vec2(0.0001));
    float facing = max(0.0, dot(n, sdir));
    float away = max(0.0, dot(n, -sdir));
    float rimBand = smoothstep(0.18, 0.70, body) * (1.0 - smoothstep(0.70, 0.97, inner));
    // The solar rim is born with the first visible limb instead of appearing
    // when the shadow system finally hands authority from moon to sun.
    float solarVis = clamp(sunDiscVisibility * 0.72 + solarRayRamp * 0.48, 0.0, 1.0);
    float rim = rimBand * facing * solarVis;
    float lower = 1.0 - smoothstep(-0.30, 0.82, p.y);
    // Directional warm scattering: lower/facing portions catch sunrise/sunset
    // colour while the opposite side remains cooler/darker, avoiding a flat
    // orange tint painted over the whole cloud bank.
    float warmMix = sunsetWarmth * (0.07 + lower * 0.25 + facing * 0.36);
    vec3 warmBody = mix(cloudColor, rayColor, clamp(warmMix,0.0,0.64));
    float backShade = 1.0 - sunsetWarmth * away * 0.20;
    // Forward/grazing Mie scatter gives low-sun clouds a real silver-gold edge
    // instead of a flat orange wash. It is strongest in broken thin edges and
    // inherits first-limb/solar-ray continuity through solarVis.
    float forwardGlow=pow(facing,3.2)*rimBand*solarVis;
    vec3 scatterColor=mix(vec3(1.0,0.96,0.88),rayColor,0.58+0.24*sunsetWarmth);
    vec3 rgb = warmBody * underside * backShade
             + rayColor * rim * (0.28 + solarRayRamp * 0.48 + sunsetWarmth * 0.24)
             + scatterColor * forwardGlow * (0.10 + 0.30*solarRayRamp + 0.18*sunsetWarmth);
    return vec4(rgb, a) * color;
  }
#endif
]]

local CLOUD_FORMAT = {
  { "VertexPosition", "float", 3 },
  { "CloudData", "float", 4 },
  { "CloudShape", "float", 4 },
}

local cloudShaderState, cloudMesh = nil, nil
CinematicAtmos._cloudMeshCapacity = 0

-- 8.0.2 MAX submission path: one dynamic instance record per cloud puff
-- instead of four duplicated vertices plus a rebuilt vertex map.  The puff
-- catalogue itself is unchanged; only GPU submission is compacted.  State is
-- kept on the module table to avoid consuming additional chunk-scope locals in
-- this already-large Lua file (LuaJIT/Lua both cap function locals).
CinematicAtmos._cloudInst = CinematicAtmos._cloudInst or {
  base=nil, data=nil, capacity=0, shader=nil, failed=false, reason=nil,
  rows={}, drawCalls=0, instances=0, uploads=0,
}
CinematicAtmos._cloudInstBaseRows = CinematicAtmos._cloudInstBaseRows or {
  {-1,-1,0},{1,-1,0},{1,1,0},{-1,-1,0},{1,1,0},{-1,1,0},
}
CinematicAtmos._cloudInstShaderSource = CinematicAtmos._cloudInstShaderSource or [[
varying vec2 vLocal;
varying float vPhase;
varying float vAlpha;
#ifdef VERTEX
uniform mat4 vp;
uniform vec3 axisR;
uniform vec3 axisU;
uniform float time;
attribute vec3 CloudCenter;
attribute vec2 CloudInfo;     // phase, alpha
attribute vec4 CloudShape;    // half width, half height, drift, rate
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 base=CloudCenter;
  float phase=CloudInfo.x;
  float t=time*CloudShape.w+phase;
  base.x += sin(t*0.53+phase*3.7)*CloudShape.z;
  base.z += cos(t*0.41+phase*2.9)*CloudShape.z*0.58;
  base.y += sin(t*0.29+phase*5.1)*1.8;
  vLocal=vertex_position.xy;vPhase=phase;vAlpha=CloudInfo.y;
  vec3 p=base+axisR*(vertex_position.x*CloudShape.x)+axisU*(vertex_position.y*CloudShape.y);
  return vp*vec4(p,1.0);
}
#endif
#ifdef PIXEL
uniform vec3 cloudColor;
uniform vec3 rayColor;
uniform vec2 sunScreen;
uniform float sunsetWarmth;
uniform float sunDiscVisibility;
uniform float solarRayRamp;
uniform float time;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p=vLocal;
  float d=length(vec2(p.x*0.94,p.y*1.04));
  float body=1.0-smoothstep(0.56,1.0,d);
  float inner=1.0-smoothstep(0.20,0.82,d);
  float detail=0.94+0.035*sin(p.x*10.0+p.y*6.0+vPhase*7.0+time*0.020)+0.025*sin(p.x*17.0-p.y*11.0+vPhase*11.0);
  float a=clamp(vAlpha*body*detail,0.0,0.96);
  float underside=mix(0.62,1.02,smoothstep(-0.82,0.72,p.y));
  vec2 n=normalize(p+vec2(0.0001));vec2 sdir=normalize(sunScreen+vec2(0.0001));
  float facing=max(0.0,dot(n,sdir));float away=max(0.0,dot(n,-sdir));
  float rimBand=smoothstep(0.18,0.70,body)*(1.0-smoothstep(0.70,0.97,inner));
  float solarVis=clamp(sunDiscVisibility*0.72+solarRayRamp*0.48,0.0,1.0);
  float rim=rimBand*facing*solarVis;float lower=1.0-smoothstep(-0.30,0.82,p.y);
  float warmMix=sunsetWarmth*(0.07+lower*0.25+facing*0.36);
  vec3 warmBody=mix(cloudColor,rayColor,clamp(warmMix,0.0,0.64));
  float backShade=1.0-sunsetWarmth*away*0.20;
  float forwardGlow=pow(facing,3.2)*rimBand*solarVis;
  vec3 scatterColor=mix(vec3(1.0,0.96,0.88),rayColor,0.58+0.24*sunsetWarmth);
  vec3 rgb=warmBody*underside*backShade+rayColor*rim*(0.28+solarRayRamp*0.48+sunsetWarmth*0.24)+scatterColor*forwardGlow*(0.10+0.30*solarRayRamp+0.18*sunsetWarmth);
  return vec4(rgb,a)*color;
}
#endif
]]

function CinematicAtmos._ensureCloudInstancer(need)
  local st=CinematicAtmos._cloudInst
  if st.failed then return false end
  local g=love and love.graphics
  if not(g and type(g.newMesh)=='function' and type(g.newShader)=='function' and type(g.drawInstanced)=='function') then st.reason='instancing api unavailable';return false end
  if type(g.getSupported)=='function' then local ok,c=V.safeCall(g.getSupported);if ok and type(c)=='table' and c.instancing==false then st.reason='instancing unsupported';return false end end
  if not st.base then
    local ok,m=V.safeCall(g.newMesh,{{'VertexPosition','float',3}},CinematicAtmos._cloudInstBaseRows,'triangles','static')
    if not(ok and m) then st.failed=true;st.reason='cloud base mesh creation failed';return false end
    st.base=m
  end
  need=max(1,tonumber(need) or 1)
  if not st.data or st.capacity<need then
    local cap=1;while cap<need do cap=cap*2 end;cap=min(cap,8192)
    if cap<need then st.reason='cloud instance capacity exceeded';return false end
    local fmt={{'CloudCenter','float',3},{'CloudInfo','float',2},{'CloudShape','float',4}}
    local ok,m=V.safeCall(g.newMesh,fmt,cap,'points','stream')
    if not(ok and m) then st.failed=true;st.reason='cloud instance mesh creation failed';return false end
    local okA=V.safeCall(st.base.attachAttribute,st.base,'CloudCenter',m,'perinstance')
      and V.safeCall(st.base.attachAttribute,st.base,'CloudInfo',m,'perinstance')
      and V.safeCall(st.base.attachAttribute,st.base,'CloudShape',m,'perinstance')
    if not okA then st.failed=true;st.reason='cloud instance attribute attach failed';return false end
    local oldData=st.data;st.data,st.capacity=m,cap
    if oldData and oldData.release then V.safeCall(oldData.release,oldData) end
  end
  if not st.shader then local ok,sh=V.safeCall(g.newShader,CinematicAtmos._cloudInstShaderSource);if not(ok and sh) then st.failed=true;st.reason='cloud instanced shader failed';return false end;st.shader=sh end
  return true
end

function CinematicAtmos._cloudPuffData(c)
  -- Puff offsets/shapes are pure functions of the world-cell identity and never
  -- animate on the CPU.  Candidate objects come from a stable scan-order pool,
  -- so retain their deterministic puff catalogue until that pool slot is reused
  -- for a different cell. This removes thousands of hash2/sin evaluations from
  -- steady cloud frames without creating an unbounded world cache.
  if c._puffIx==c.ix and c._puffIz==c.iz and c._puffData then return c._puffData end
  local data=c._puffData or {};c._puffData=data;c._puffIx,c._puffIz=c.ix,c.iz
  local ix,iz=c.ix,c.iz;local spanX=54+c.styleB*58;local spanZ=34+c.styleC*48;local spanY=12+c.styleA*24
  for k=1,19 do
    local hk=300+k*11;local rx=hash2(ix,iz,hk+1)*2-1;local ry=hash2(ix,iz,hk+2)*2-1;local rz=hash2(ix,iz,hk+3)*2-1;local core=k<=5
    local ox=rx*spanX*(core and .36 or .86);local oy=ry*spanY*(core and .30 or .82);local oz=rz*spanZ*(core and .34 or .90)
    if k==1 then ox,oy,oz=0,0,0 elseif k==2 then ox,oy=-spanX*.31,spanY*.08 elseif k==3 then ox,oy=spanX*.30,spanY*.02 elseif k==4 then ox,oy=spanX*.02,spanY*.44 end
    local r=data[k];if not r then r={};data[k]=r end
    r[1],r[2],r[3]=ox,oy,oz
    r[4]=(42+hash2(ix,iz,hk+4)*40)*(.88+c.styleB*.28)
    r[5]=(20+hash2(ix,iz,hk+5)*24)*(.84+c.styleA*.42)
    r[6]=.34+hash2(ix,iz,hk+6)*.20;r[7]=hash2(ix,iz,hk+7)*1.25
    r[8]=3.5+hash2(ix,iz,hk+8)*6.5;r[9]=.035+hash2(ix,iz,hk+9)*.040;r[10]=core and 1 or 0
  end
  return data
end

function CinematicAtmos._buildCloudInstances(frame,clouds)
  if not clouds or #clouds==0 then return nil,0 end
  local rows=CinematicAtmos._cloudInst.rows;local n=0
  for ciCloud=1,#clouds do
    local c=clouds[ciCloud]
    local puffs=frame.level>0.9 and (14+floor(c.styleC*5)) or (11+floor(c.styleC*4))
    puffs=max(6,floor(puffs*(.70+.30*performanceScale())*CinematicAtmos._qualityCloudDetail()+.5))
    local pdata=CinematicAtmos._cloudPuffData(c)
    for k=1,puffs do
      local d=pdata[k];local alpha=d[6]*frame.level;if d[10]==1 then alpha=alpha*1.18 end
      if c._frontCloud then alpha=alpha*(c.fadeAlpha or 1.0) end
      n=n+1;local r=rows[n];if not r then r={0,0,0,0,0,0,0,0,0};rows[n]=r end
      r[1],r[2],r[3]=c.cx+d[1],c.cy+d[2],c.cz+d[3];r[4],r[5]=c.phase+d[7],alpha;r[6],r[7],r[8],r[9]=d[4],d[5],d[8],d[9]
    end
  end
  return rows,n
end

local function cloudShader()
  if cloudShaderState ~= nil then return cloudShaderState or nil end
  local ok, sh = V.safeCall(love.graphics.newShader, CLOUD_SHADER)
  cloudShaderState = (ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] volumetric cloud shader refused: " .. tostring(sh)) end
  return cloudShaderState or nil
end

local function buildCloudVertices(Voxel3D, frame, clouds)
  if not clouds or #clouds == 0 then return nil, nil end
  local verts, indices, q = {}, {}, 0
  local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }

  for ciCloud = 1, #clouds do
    local c = clouds[ciCloud]
    local puffs = frame.level > 0.9 and (14 + floor(c.styleC * 5)) or (11 + floor(c.styleC * 4))
    puffs=max(6,floor(puffs*(.70+.30*performanceScale())*CinematicAtmos._qualityCloudDetail()+.5))
    local pdata=CinematicAtmos._cloudPuffData(c)

    for k = 1, puffs do
      local d=pdata[k];local alpha=d[6]*frame.level;if d[10]==1 then alpha=alpha*1.18 end
      if c._frontCloud then alpha=alpha*(c.fadeAlpha or 1.0) end
      local puffPhase=c.phase+d[7]
      for corner = 1, 4 do
        local co = corners[corner]
        verts[#verts + 1] = {
          c.cx + d[1], c.cy + d[2], c.cz + d[3],
          co[1], co[2], puffPhase, alpha,
          d[4], d[5], d[8], d[9],
        }
      end
      pushQuad(indices, q)
      q = q + 1
    end
  end
  return verts, indices
end

local function drawClouds(Voxel3D, frame, clouds)
  do
    local cloudsOn = true
    V.safeCall(function()
      local S = V.require("Settings")
      if S and S.cloudsOn then cloudsOn = S.cloudsOn()
      elseif S and S.get then cloudsOn = (S.get("clouds") ~= "off") end
    end)
    if not cloudsOn then return end
  end
  if not clouds or #clouds == 0 then return end
  local sh = cloudShader()
  local axisR, axisU = billboardAxes(Voxel3D)
  if not (sh and axisR and axisU) then return end

  -- Prefer compact hardware instancing: one 9-float record per puff instead of
  -- four 11-float vertices plus a rebuilt index map.  This preserves every puff
  -- and the exact shader equations while cutting cloud upload volume by >4x.
  local irows,icount=CinematicAtmos._buildCloudInstances(frame,clouds)
  if icount>0 and CinematicAtmos._ensureCloudInstancer(icount) then
    local ist=CinematicAtmos._cloudInst
    local okUpload=V.safeCall(ist.data.setVertices,ist.data,irows,1,icount)
    if okUpload then
      V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply");V.safeCall(love.graphics.setDepthMode,"lequal",false)
      if Voxel3D.beginEffect(ist.shader) then
        V.safeCall(ist.shader.send,ist.shader,"vp","row",Voxel3D.vp);V.safeCall(ist.shader.send,ist.shader,"axisR",axisR);V.safeCall(ist.shader.send,ist.shader,"axisU",axisU);V.safeCall(ist.shader.send,ist.shader,"time",ForestAtmos.time)
        local tint=DayNight.tint(true);local base=mixColor({.67,.73,.82},{.97,.96,.91},min(1,(frame.rayColor[1]+frame.rayColor[2])*.28))
        V.safeCall(ist.shader.send,ist.shader,"cloudColor",{min(1,base[1]*(.74+tint[1]*.27)),min(1,base[2]*(.74+tint[2]*.27)),min(1,base[3]*(.74+tint[3]*.27))});V.safeCall(ist.shader.send,ist.shader,"rayColor",frame.rayColor)
        local sunsetStrength=0;do local E=cachedRequire("CelestialEngine");if E and E.state then local okS,st=V.safeCall(E.state);if okS and st then sunsetStrength=tonumber(st.cloudSunsetStrength) or tonumber(st.sunsetWarmth) or 0 end end end
        V.safeCall(ist.shader.send,ist.shader,"sunsetWarmth",max(0,min(1,sunsetStrength)))
        V.safeCall(ist.shader.send,ist.shader,"sunDiscVisibility",max(0,min(1,tonumber(frame.sunDiscVisibility) or 0)))
        V.safeCall(ist.shader.send,ist.shader,"solarRayRamp",max(0,min(1,tonumber(frame.solarRayRamp) or 0)))
        local sx,sy,sz=tonumber(frame.sunDirX) or 0,tonumber(frame.sunDirY) or 0,tonumber(frame.sunDirZ) or 0;local sl=sqrt(sx*sx+sy*sy+sz*sz);if sl<.0001 then sx,sy,sz,sl=0,1,0,1 end;sx,sy,sz=sx/sl,sy/sl,sz/sl
        V.safeCall(ist.shader.send,ist.shader,"sunScreen",{sx*axisR[1]+sy*axisR[2]+sz*axisR[3],sx*axisU[1]+sy*axisU[2]+sz*axisU[3]})
        local okDraw=V.safeCall(love.graphics.drawInstanced,ist.base,icount);Voxel3D.endEffect()
        if okDraw then ist.drawCalls=ist.drawCalls+1;ist.instances=ist.instances+icount;ist.uploads=ist.uploads+1;return true end
      end
    end
  end

  local verts, indices = buildCloudVertices(Voxel3D, frame, clouds)
  if not (verts and indices and #verts > 0) then return end
  -- 8.1.27 live-host repair: the software/fallback cloud path must be able to
  -- grow when a denser weather profile follows a clearer one. LÖVE meshes made
  -- from a vertex table have exactly that table's capacity; calling setVertices
  -- with a later, larger cloud population raises "Too many vertices". Allocate
  -- a grow-only power-of-two buffer and upload the exact current rows instead.
  local need = #verts
  if (not cloudMesh) or (CinematicAtmos._cloudMeshCapacity or 0) < need then
    local cap = 256
    while cap < need do cap = cap * 2 end
    local ok, mesh = V.safeCall(love.graphics.newMesh, CLOUD_FORMAT, cap, "triangles", "stream")
    if not ok then return end
    local old = cloudMesh
    cloudMesh, CinematicAtmos._cloudMeshCapacity = mesh, cap
    if old and old.release then V.safeCall(old.release, old) end
  end
  local okUpload = V.safeCall(cloudMesh.setVertices, cloudMesh, verts, 1, need)
  if not okUpload then return false end
  V.safeCall(cloudMesh.setVertexMap, cloudMesh, indices)
  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", false)
  local began = Voxel3D.beginEffect and Voxel3D.beginEffect(sh)
  if not began then V.safeCall(love.graphics.setShader, sh) end
  if began or sh then
    V.safeCall(sh.send, sh, "vp", "row", Voxel3D.vp)
    V.safeCall(sh.send, sh, "axisR", axisR)
    V.safeCall(sh.send, sh, "axisU", axisU)
    V.safeCall(sh.send, sh, "time", ForestAtmos.time)
    local tint = DayNight.tint(true)
    local mt=min(1,(frame.rayColor[1]+frame.rayColor[2])*0.28)
    local base=CinematicAtmos._uniformScratch.cloudBase
    base[1],base[2],base[3]=lerp(0.67,0.97,mt),lerp(0.73,0.96,mt),lerp(0.82,0.91,mt)
    local co=CinematicAtmos._uniformScratch.cloudColor
    co[1],co[2],co[3]=min(1,base[1]*(0.74+tint[1]*0.27)),min(1,base[2]*(0.74+tint[2]*0.27)),min(1,base[3]*(0.74+tint[3]*0.27))
    V.safeCall(sh.send, sh, "cloudColor", co)
    V.safeCall(sh.send, sh, "rayColor", frame.rayColor)
    local sunsetStrength=0
    do
      local E=cachedRequire("CelestialEngine")
      if E and E.state then
        local okS,st=V.safeCall(E.state)
        if okS and st then sunsetStrength=tonumber(st.cloudSunsetStrength) or tonumber(st.sunsetWarmth) or 0 end
      end
    end
    V.safeCall(sh.send, sh, "sunsetWarmth", max(0,min(1,sunsetStrength)))
    V.safeCall(sh.send, sh, "sunDiscVisibility", max(0,min(1,tonumber(frame.sunDiscVisibility) or 0)))
    V.safeCall(sh.send, sh, "solarRayRamp", max(0,min(1,tonumber(frame.solarRayRamp) or 0)))

    local sx, sy, sz = tonumber(frame.sunDirX) or 0, tonumber(frame.sunDirY) or 0, tonumber(frame.sunDirZ) or 0
    local sl = sqrt(sx * sx + sy * sy + sz * sz); if sl < .0001 then sx,sy,sz,sl=0,1,0,1 end
    sx, sy, sz = sx / sl, sy / sl, sz / sl
    local sr = sx * axisR[1] + sy * axisR[2] + sz * axisR[3]
    local su = sx * axisU[1] + sy * axisU[2] + sz * axisU[3]
    local ss=CinematicAtmos._uniformScratch.sun2; ss[1],ss[2]=sr,su
    V.safeCall(sh.send, sh, "sunScreen", ss)

    local okDraw=V.safeCall(love.graphics.draw, cloudMesh)
    if began and Voxel3D.endEffect then
      V.safeCall(Voxel3D.endEffect)
    else
      V.safeCall(love.graphics.setShader)
    end
    return okDraw == true
  end
  return false
end

-- Debug/test surfaces for the world-space precipitation contract. They return
-- read-only values and are intentionally tiny so release tests can exercise
-- camera invariance without duplicating host heuristics.
function CinematicAtmos.worldPrecipLoadStatus()
  return WorldPrecip ~= nil, WorldPrecipLoadError
end

function CinematicAtmos.precipAnchor(Voxel3D)
  return worldPrecipAnchor(Voxel3D)
end

function CinematicAtmos.precipDeckBand(Voxel3D, weather)
  return precipitationDeckBand(Voxel3D, weather)
end

-- Read-only diagnostic/test seam: count the exact descriptors the live cloud
-- builder would submit for a camera pose. This exercises real pitch admission
-- instead of duplicating the culling math in a fixture.
function CinematicAtmos.cloudDescriptorProbe(Voxel3D, frame)
  local list=buildCloudDescriptors(Voxel3D,frame)
  local n=type(list)=="table" and #list or 0
  local fadeSum,puffSum=0,0
  if type(list)=="table" then
    for i=1,#list do
      local c=list[i] or {}
      fadeSum=fadeSum+(tonumber(c.fadeAlpha) or 0)
      puffSum=puffSum+(tonumber(c.puffs) or 0)
    end
  end
  return n,fadeSum,puffSum
end

-- Read-only diagnostic: exact volumetric lobe population authored by the live
-- descriptor builder. Used by renderer regression tests without duplicating
-- the live cloud-population math.
function CinematicAtmos.cloudPrimitiveProbe(Voxel3D, frame)
  local list=buildCloudDescriptors(Voxel3D,frame)
  local n,puffs=type(list)=="table" and #list or 0,0
  if type(list)=="table" then
    for i=1,#list do puffs=puffs+max(0,tonumber(list[i] and list[i].puffs) or 0) end
  end
  return n,puffs
end

-- ---------- flat-world distant precipitation/lightning
--
-- A flat voxel world exposes an unusually long horizon. Front CLOUDS now belong
-- to the ordinary bank above; this bounded pass keeps only depth-tested distant
-- precipitation/fog curtains and true world-space lightning. Nearby weather is
-- still owned by WorldPrecip.
CinematicAtmos._distantFormat = CinematicAtmos._distantFormat or {
  { "VertexPosition", "float", 3 },
  { "DistantData", "float", 4 }, -- u, v, alpha, kind
}
CinematicAtmos._distantRows = CinematicAtmos._distantRows or {}
CinematicAtmos._distantIndices = CinematicAtmos._distantIndices or {}

function CinematicAtmos._distantShader()
  if CinematicAtmos._distantShaderState ~= nil then
    return CinematicAtmos._distantShaderState or nil
  end
  if not (love and love.graphics and love.graphics.newShader) then
    CinematicAtmos._distantShaderState=false
    return nil
  end
  local src=[[
    varying vec2 vUv;
    varying float vAlpha;
    varying float vKind;
  #ifdef VERTEX
    uniform mat4 vp;
    uniform vec3 curve;
    attribute vec4 DistantData;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
      vUv=DistantData.xy;
      vAlpha=DistantData.z;
      vKind=DistantData.w;
      vec4 w=vertex_position;
      if (curve.z > 0.0) {
        vec2 cd=w.xz-curve.xy;
        w.y-=dot(cd,cd)*curve.z;
      }
      return vp*w;
    }
  #endif
  #ifdef PIXEL
    uniform float time;
    uniform float flashAmount;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      float u=clamp(vUv.x,0.0,1.0);
      float v=clamp(vUv.y,0.0,1.0);
      float side=smoothstep(0.0,0.10,u)*(1.0-smoothstep(0.90,1.0,u));
      float top=smoothstep(0.0,0.10,v);
      float bottom=1.0-smoothstep(0.76,1.0,v);
      float streak=0.55+0.45*sin(u*91.0 + v*17.0 - time*7.4);
      float fine=0.68+0.32*sin(u*211.0 - time*11.1 + v*29.0);
      float body=clamp(0.40+0.36*streak+0.24*fine,0.0,1.0);
      vec3 rain=vec3(0.42,0.49,0.58);
      vec3 snow=vec3(0.76,0.80,0.86);
      vec3 fog=vec3(0.67,0.71,0.76);
      vec3 blizzard=vec3(0.84,0.88,0.94);
      if (vKind > 3.5 && vKind < 4.5) {
        float bolt=0.76+0.24*sin(v*33.0+u*11.0);
        return vec4(vec3(0.88,0.94,1.0),vAlpha*bolt)*color;
      }
      // 8.1.50 front precipitation uses discrete world-space particles, not
      // the old painted curtain. Kinds 5/6/7 are rain/snow/blizzard particles
      // generated in the same physical front slab that later reaches the local
      // WorldPrecip volume. The shader only shapes each individual quad.
      if (vKind > 4.5 && vKind < 5.5) {
        float sideP=smoothstep(0.0,0.24,u)*(1.0-smoothstep(0.76,1.0,u));
        float endP=smoothstep(0.0,0.10,v)*(1.0-smoothstep(0.90,1.0,v));
        return vec4(rain,vAlpha*sideP*endP)*color;
      }
      if (abs(vKind-6.0) < 0.5) {
        vec2 fp=vec2(u,v)*2.0-1.0;
        float d=dot(fp,fp);
        float flake=(1.0-smoothstep(0.20,1.0,d));
        flake*=flake;
        return vec4(snow,vAlpha*flake)*color;
      }
      if (abs(vKind-7.0) < 0.5) {
        vec2 fp=vec2(u,v)*2.0-1.0;
        float d=dot(fp,fp);
        float flake=(1.0-smoothstep(0.16,1.0,d));
        float gust=0.70+0.30*sin((u-v)*15.0-time*8.0);
        return vec4(blizzard,vAlpha*flake*gust)*color;
      }
      bool isBlizzard=(vKind>2.5 && vKind<3.5);
      vec3 c = vKind < 0.5 ? rain : (vKind < 1.5 ? snow : (vKind < 2.5 ? fog : blizzard));
      c=mix(c,vec3(0.96,0.98,1.0),clamp(flashAmount,0.0,1.0)*0.62);
      float kindBody = vKind > 1.5 && !isBlizzard ? (0.52+0.48*(1.0-v)) : body;
      if (isBlizzard) {
        // Dense wind-driven snow wall: diagonal filament families plus a
        // broader low-level veil. This must not read as white rain streaks.
        float d1=0.5+0.5*sin(u*121.0-v*39.0-time*13.0);
        float d2=0.5+0.5*sin(u*57.0-v*71.0-time*8.2);
        float drift=0.34+0.42*d1+0.24*d2;
        float ground=0.62+0.38*(1.0-v);
        kindBody=clamp(drift*ground,0.0,1.0);
      }
      float a=vAlpha*side*top*bottom*kindBody;
      return vec4(c,a)*color;
    }
  #endif
  ]]
  local ok,sh=V.safeCall(love.graphics.newShader,src)
  CinematicAtmos._distantShaderState=(ok and sh) or false
  if not ok then print("[DRAMATIC_SHAPE] distant-weather shader refused: "..tostring(sh)) end
  return CinematicAtmos._distantShaderState or nil
end

function CinematicAtmos._buildDistantWeather(Voxel3D,frame,map,skipHydrometeors)
  local D=cachedRequire("DistantWeather")
  local W=cachedRequire("WeatherWorldSpace")
  if not (D and D.items and W and W.toLocal) then return nil,nil,0 end
  local items,count=D.items()
  if type(items)~="table" or (tonumber(count) or 0)<=0 then return nil,nil,0 end
  local eye=Voxel3D.eye or Voxel3D.player or Voxel3D.focus
  if not eye then return nil,nil,0 end
  local ex,ez=tonumber(eye[1]) or 0,tonumber(eye[3]) or 0
  local rows=CinematicAtmos._distantRows
  local indices=CinematicAtmos._distantIndices
  local old=#rows
  for i=#indices,1,-1 do indices[i]=nil end
  local n,q=0,0
  local mapId=map and map.id or nil
  local function emit(x,y,z,u,v,a,kind)
    n=n+1;local row=rows[n];if not row then row={0,0,0,0,0,0,0};rows[n]=row end
    row[1],row[2],row[3],row[4],row[5],row[6],row[7]=x,y,z,u,v,a,kind
  end
  local function card(cx,cz,rx,rz,half,y0,y1,a,kind,topShiftX,topShiftZ)
    local sx,sz=tonumber(topShiftX) or 0,tonumber(topShiftZ) or 0
    emit(cx-rx*half,y0,cz-rz*half,0,0,a,kind);emit(cx+rx*half,y0,cz+rz*half,1,0,a,kind)
    emit(cx+sx+rx*half,y1,cz+sz+rz*half,1,1,a,kind);emit(cx+sx-rx*half,y1,cz+sz-rz*half,0,1,a,kind)
    pushQuad(indices,q);q=q+1
  end
  local hash01,particleQuad
  if not skipHydrometeors then
    hash01=function(v)
      local x=math.sin(v*12.9898+78.233)*43758.5453123
      return x-math.floor(x)
    end
    particleQuad=function(cx,cy,cz,sideX,sideZ,halfW,halfH,slantX,slantZ,a,kind)
      local sx,sz=tonumber(slantX) or 0,tonumber(slantZ) or 0
      emit(cx-sideX*halfW-sx,cy-halfH,cz-sideZ*halfW-sz,0,0,a,kind)
      emit(cx+sideX*halfW-sx,cy-halfH,cz+sideZ*halfW-sz,1,0,a,kind)
      emit(cx+sideX*halfW+sx,cy+halfH,cz+sideZ*halfW+sz,1,1,a,kind)
      emit(cx-sideX*halfW+sx,cy+halfH,cz-sideZ*halfW+sz,0,1,a,kind)
      pushQuad(indices,q);q=q+1
    end
  end
  -- Front cloud mass is injected into the ordinary cloud-bank descriptor field.
  -- 8.1.50: precipitation fronts no longer use a painted rain/snow curtain.
  -- The distant stream now builds discrete world-space 3D drops/flakes inside
  -- the real StormCell slab. These particles remain the same visual object as
  -- the front approaches; after contact their alpha hands off gradually to the
  -- local WorldPrecip field. Fog and true world-space lightning stay here.
  --
  -- Density matters just as much as morphology. A few hundred real drops over
  -- a regional front are technically 3D but visually disappear at range and
  -- then make the local field look like it popped on. Share one bounded budget
  -- across all visible fronts and give the nearest hydrometeor slab a density
  -- comparable to WorldPrecip. This preserves the same falling-particle read
  -- from far field through contact without restoring a painted sheet.
  local particleBudget=0
  if not skipHydrometeors then
    local qscale=1
    local Q=cachedRequire("Quality")
    if Q and Q.budget then
      local okQ,b=V.safeCall(Q.budget)
      if okQ and b then qscale=math.max(.28,math.min(1,tonumber(b.worldPrecip) or 1)) end
    end
    particleBudget=math.max(1400,math.floor(9000*qscale+.5))
  end
  local function boltSegment(x0,y0,z0,x1,y1,z1,viewRx,viewRz,width,a)
    card((x0+x1)*.5,(z0+z1)*.5,viewRx,viewRz,width*.5,0,0,0,4) -- reserve indices/rows overwritten below
    local base=n-3
    rows[base][1],rows[base][2],rows[base][3]=x0-viewRx*width,y0,z0-viewRz*width
    rows[base+1][1],rows[base+1][2],rows[base+1][3]=x0+viewRx*width,y0,z0+viewRz*width
    rows[base+2][1],rows[base+2][2],rows[base+2][3]=x1+viewRx*width,y1,z1+viewRz*width
    rows[base+3][1],rows[base+3][2],rows[base+3][3]=x1-viewRx*width,y1,z1-viewRz*width
    for r=base,base+3 do rows[r][6],rows[r][7]=a,4 end
  end
  for i=1,math.min(4,tonumber(count) or 0) do
    local a=items[i]
    local anchorX=tonumber(a.bankX) or tonumber(a.x)
    local anchorZ=tonumber(a.bankZ) or tonumber(a.z)
    local lx,lz=W.toLocal(anchorX,anchorZ,mapId)
    local dx,dz=lx-ex,lz-ez
    local len=math.sqrt(dx*dx+dz*dz)
    if len>1 then
      local rx,rz=-dz/len,dx/len
      local curtainCap=math.max(900,(tonumber(Voxel3D.far) or 900)*1.80)
      local worldWidth=math.max(96,math.min(curtainCap,(tonumber(a.rz) or 420)*1.02))
      -- Curtain/lightning origins use the SAME deck selected for this front's
      -- integrated cloud descriptors. This keeps rain visibly attached to the
      -- bank even while the local player is still under a clear/broken sky.
      local _,frontDeckBase,frontDeckSpan=CinematicAtmos._frontCloudDeck(Voxel3D,frame,a.cloudWeather or a.weather)
      local frontPrecipY=frontDeckBase-8.0
      local frontPrecipSpan=max(12.0,min(30.0,frontDeckSpan*.55+8.0))
      -- Precipitation/fog may be zero during the developing-cloud stage. Rain
      -- and snow are individual 3D particles; only fog retains a low curtain.
      local alpha=math.max(0,math.min(.92,(tonumber(a.shaft) or 0)*.92))
      alpha=alpha*CinematicAtmos._distantSnowHandoff(frame,a.kind)
      if alpha>.004 then
        local kind=(a.kind=="snow") and 1 or ((a.kind=="fog") and 2 or ((a.kind=="blizzard") and 3 or 0))
        if kind==2 then
          -- Fog is genuinely a volume/veil rather than falling hydrometeors.
          -- Keep a few depth-tested cards, which is visually correct for fog.
          local bands=3
          for band=1,bands do
            local center=(bands+1)*.5
            local off=(band-center)*worldWidth*.25
            local half=worldWidth*((math.abs(band-center)<.6) and .23 or .18)
            local cx,cz=lx+rx*off,lz+rz*off
            local top=math.min(frontPrecipY,36)
            local ba=alpha*((math.abs(band-center)<.6) and 1.0 or .76)
            card(cx,cz,rx,rz,half,1.2,top,ba,2)
          end
        elseif not skipHydrometeors then
          -- Physical front slab. `bankX/bankZ` is its leading edge; particles
          -- extend back toward the cell centre, so the same rain/snow volume
          -- visibly advances through the world instead of being screen-painted.
          local cellX,cellZ=W.toLocal(tonumber(a.x) or anchorX,tonumber(a.z) or anchorZ,mapId)
          local bx,bz=lx,lz
          local tx,tz=cellX-bx,cellZ-bz
          local tl=math.sqrt(tx*tx+tz*tz)
          if tl>.001 then tx,tz=tx/tl,tz/tl else tx,tz=-dx/len,-dz/len end
          local crossX,crossZ=-tz,tx
          local depth=math.max(80,math.min(worldWidth*.52,(tonumber(a.radius) or worldWidth)*.66))
          local sizeClass=tostring(a.sizeClass or "regional")
          -- Match the local field by area rather than by an arbitrary tiny
          -- per-front count. The nearest front may use most of the shared
          -- budget; later fronts consume only what remains, keeping total work
          -- bounded even when several systems are visible on the flat horizon.
          local density=(kind==0) and .030 or .034
          local desired=math.floor(worldWidth*depth*density+.5)
          local classFloor=(sizeClass=="synoptic" and 3600) or (sizeClass=="broad" and 3000) or (sizeClass=="regional" and 2400) or 1400
          desired=math.max(classFloor,math.min(6500,desired))
          local particles=math.max(0,math.min(desired,particleBudget))
          particleBudget=math.max(0,particleBudget-particles)
          local top=frontPrecipY+frontPrecipSpan
          local bottom=2.0
          local height=math.max(8,top-bottom)
          local frontId=tonumber(a.id) or i
          -- Distant fronts own a monotonic weather-motion clock. Using a host
          -- animation/camera clock here allowed resets or reversals to make the
          -- modulo fall phase move backward, which reads as rain falling up.
          local time=(D.motionTime and tonumber(D.motionTime())) or tonumber(ForestAtmos.time) or 0
          local windX,windZ=tonumber(a.vx) or 0,tonumber(a.vz) or 0
          for pi=1,particles do
            local seed=frontId*1009+pi*17.173
            local h1=hash01(seed+.13);local h2=hash01(seed+3.71);local h3=hash01(seed+8.27);local h4=hash01(seed+14.9)
            -- Soft lateral distribution prevents an artificial hard rectangle.
            local lateral=(h1*2-1)*worldWidth*.48*(.72+.28*h2)
            local behind=(h2^.72)*depth
            local px=bx+crossX*lateral+tx*behind
            local pz=bz+crossZ*lateral+tz*behind
            if kind==0 then
              local fall=48+h3*42
              local travel=(time*fall+h4*height)%height
              local py=top-travel
              local age=travel/math.max(1,fall)
              px=px+windX*(5+h2*12)*age*.34
              pz=pz+windZ*(5+h1*12)*age*.34
              -- Same physical scale family as WorldPrecip rain: local drops
              -- use size 0.55..2.05, half-width ~= size*.12 and half-length
              -- ~= size*1.4. Matching that scale removes the last visible
              -- "distant tiny streak -> local fat streak" morphology change.
              local size=.55+h3*1.50
              local halfW=size*.12
              local halfH=size*1.40
              particleQuad(px,py,pz,rx,rz,halfW,halfH,windX*size*.10,windZ*size*.10,alpha*(.34+.34*h2),5)
            else
              local fall=(5.0+h3*6.5)*((kind==3) and 1.22 or 1.0)
              local travel=(time*fall+h4*height)%height
              local py=top-travel
              local age=travel/math.max(1.5,fall)
              local gust=(kind==3) and (8+18*(tonumber(a.gust) or 0)) or (3+h2*7)
              px=px+windX*gust*age*.36+math.sin(time*(.7+h1)+seed)*(.5+h3*1.4)
              pz=pz+windZ*gust*age*.36+math.cos(time*(.6+h2)+seed)*(.5+h1*1.4)
              -- Ordinary snow uses the same 0.17..0.48 world-size family as
              -- WorldPrecip. Blizzard flakes are slightly stretched/sheared by
              -- the actual front gust but remain individual flakes.
              local size=(kind==3) and (.24+h3*.34) or (.17+h3*.31)
              local shear=(kind==3) and (.18+.28*(tonumber(a.gust) or 0)) or 0
              particleQuad(px,py,pz,rx,rz,size,size,windX*shear,windZ*shear,alpha*(.42+.40*h1),(kind==3) and 7 or 6)
            end
          end
        end
      end

      -- A remote charged cloud owns a real distant bolt, not a global screen
      -- flash. The strike coordinate comes from the same StormCell that queued
      -- the delayed thunder event.
      if (tonumber(a.flash) or 0)>.02 and a.strikeX and a.strikeZ then
        local sx,sz=W.toLocal(a.strikeX,a.strikeZ,mapId)
        local x0,z0=lx,lz;local y0=frontPrecipY+frontPrecipSpan*.62
        local x1,z1=sx,sz;local y1=2.0
        local seg=6;local px,pz=x0,z0;local py=y0
        for j=1,seg do
          local t=j/seg
          local nx=x0+(x1-x0)*t;local nz=z0+(z1-z0)*t;local ny=y0+(y1-y0)*t
          if j<seg then
            local wob=math.sin((j*17+(tonumber(a.id) or 1)*11))*worldWidth*.018
            nx,nz=nx+rx*wob,nz+rz*wob
          end
          boltSegment(px,py,pz,nx,ny,nz,rx,rz,math.max(.55,math.min(2.4,len/850)),math.min(1,(tonumber(a.flash) or 0)*1.25))
          px,py,pz=nx,ny,nz
        end
      end
    end
  end
  for i=n+1,old do rows[i]=nil end
  return rows,indices,n
end

function CinematicAtmos._drawDistantPrecipInstanced(Voxel3D,frame,map)
  -- Named/manual weather disables fronts. Never render a stale StormCell
  -- precipitation slab for even one frame after that authority changes; this
  -- was the remaining snow/blizzard "fountain" that could sit in the sky.
  if CinematicAtmos._frontsEnabled and not CinematicAtmos._frontsEnabled() then return true,false end
  local F=cachedRequire("DistantFrontPrecip")
  local D=cachedRequire("DistantWeather")
  local W=cachedRequire("WeatherWorldSpace")
  if not (F and F.supported and F.draw and D and D.items and W and W.toLocal) then return false end
  local okSupport,supported=V.safeCall(F.supported)
  if not(okSupport and supported) then return false end
  local items,count=D.items();count=min(4,tonumber(count) or 0)
  if type(items)~="table" or count<=0 then return true end
  local eye=Voxel3D.eye or Voxel3D.player or Voxel3D.focus;if not eye then return false end
  local ex,ez=tonumber(eye[1]) or 0,tonumber(eye[3]) or 0
  local mapId=map and map.id or nil
  local qscale=1;do local Q=cachedRequire("Quality");if Q and Q.budget then local okQ,b=V.safeCall(Q.budget);if okQ and b then qscale=max(.28,min(1,tonumber(b.worldPrecip) or 1)) end end end
  local particleBudget=max(1400,floor(9000*qscale+.5))
  local any=false
  for i=1,count do
    local a=items[i]
    local kind=(a.kind=="snow") and 1 or ((a.kind=="blizzard") and 2 or ((a.kind=="fog") and -1 or 0))
    local alpha=max(0,min(.92,(tonumber(a.shaft) or 0)*.92))
    alpha=alpha*CinematicAtmos._distantSnowHandoff(frame,a.kind)
    if kind>=0 and alpha>.004 and particleBudget>0 then
      local anchorX=tonumber(a.bankX) or tonumber(a.x);local anchorZ=tonumber(a.bankZ) or tonumber(a.z)
      local lx,lz=W.toLocal(anchorX,anchorZ,mapId);local dx,dz=lx-ex,lz-ez;local len=sqrt(dx*dx+dz*dz)
      if len>1 then
        local rx,rz=-dz/len,dx/len
        local curtainCap=max(900,(tonumber(Voxel3D.far) or 900)*1.80)
        local worldWidth=max(96,min(curtainCap,(tonumber(a.rz) or 420)*1.02))
        local _,frontDeckBase,frontDeckSpan=CinematicAtmos._frontCloudDeck(Voxel3D,frame,a.cloudWeather or a.weather)
        local frontPrecipY=frontDeckBase-8.0;local frontPrecipSpan=max(12.0,min(30.0,frontDeckSpan*.55+8.0))
        local cellX,cellZ=W.toLocal(tonumber(a.x) or anchorX,tonumber(a.z) or anchorZ,mapId)
        local tx,tz=cellX-lx,cellZ-lz;local tl=sqrt(tx*tx+tz*tz);if tl>.001 then tx,tz=tx/tl,tz/tl else tx,tz=-dx/len,-dz/len end
        local crossX,crossZ=-tz,tx
        local depth=max(80,min(worldWidth*.52,(tonumber(a.radius) or worldWidth)*.66))
        local density=(kind==0) and .030 or .034
        local desired=floor(worldWidth*depth*density+.5);local sizeClass=tostring(a.sizeClass or "regional")
        local classFloor=(sizeClass=="synoptic" and 3600) or (sizeClass=="broad" and 3000) or (sizeClass=="regional" and 2400) or 1400
        desired=max(classFloor,min(6500,desired));local particles=max(0,min(desired,particleBudget));particleBudget=max(0,particleBudget-particles)
        if particles>0 then
          -- Four fronts maximum: keep one reusable options record per slot so
          -- the 8.1.51 hot path creates no short-lived per-front Lua tables.
          CinematicAtmos._distantInstOpts=CinematicAtmos._distantInstOpts or {}
          local opts=CinematicAtmos._distantInstOpts[i]
          if not opts then opts={};CinematicAtmos._distantInstOpts[i]=opts end
          opts.count,opts.bx,opts.bz=particles,lx,lz
          opts.crossX,opts.crossZ,opts.viewX,opts.viewZ=crossX,crossZ,rx,rz
          opts.tx,opts.tz,opts.width,opts.depth=tx,tz,worldWidth,depth
          opts.top,opts.bottom=frontPrecipY+frontPrecipSpan,2.0
          opts.time=(D.motionTime and tonumber(D.motionTime())) or tonumber(ForestAtmos.time) or 0
          opts.alpha,opts.kind=alpha,kind
          opts.frontId=tonumber(a.id) or i
          opts.windX,opts.windZ,opts.gust=tonumber(a.vx) or 0,tonumber(a.vz) or 0,tonumber(a.gust) or 0
          local okDraw,drawn=V.safeCall(F.draw,Voxel3D,opts)
          if not(okDraw and drawn==true) then return false end
          any=true
        end
      end
    end
  end
  return true,any
end

function CinematicAtmos._drawDistantWeather(Voxel3D,frame,map)
  if CinematicAtmos._frontsEnabled and not CinematicAtmos._frontsEnabled() then return false end
  -- 8.1.51 production path: synthesize the same 8.1.50 discrete front drops
  -- and flakes from the shared immutable instance seed on the GPU.  No particle
  -- ceiling or morphology changes.  If instancing is unavailable/refused, the
  -- exact 8.1.50 CPU quad builder remains the fallback below.
  local okInst,instanced,anyInst=V.safeCall(CinematicAtmos._drawDistantPrecipInstanced,Voxel3D,frame,map)
  instanced=okInst and instanced==true
  local rows,indices,n=CinematicAtmos._buildDistantWeather(Voxel3D,frame,map,instanced)
  if not (rows and indices and n and n>0) then return instanced and (anyInst==true) or false end
  local sh=CinematicAtmos._distantShader();if not sh then return instanced and (anyInst==true) or false end
  local mesh=CinematicAtmos._distantMesh
  local ok
  mesh,ok=CinematicAtmos._uploadStreamMesh("distant-weather",mesh,CinematicAtmos._distantFormat,rows)
  CinematicAtmos._distantMesh=mesh
  if not ok then return instanced and (anyInst==true) or false end
  CinematicAtmos._applySequentialQuadMap("distant-weather",mesh,indices)
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply")
  V.safeCall(love.graphics.setDepthMode,"lequal",false)
  if not Voxel3D.beginEffect(sh) then return instanced and (anyInst==true) or false end
  V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp)
  V.safeCall(sh.send,sh,"curve",CinematicAtmos._curveUniform(Voxel3D))
  V.safeCall(sh.send,sh,"time",ForestAtmos.time)
  local flash=0
  local L=cachedRequire("Lightning")
  if L and L.flash then local good,v=V.safeCall(L.flash,"full");if good then flash=tonumber(v) or 0 end end
  V.safeCall(sh.send,sh,"flashAmount",max(0,min(1,flash)))
  local drawn=V.safeCall(love.graphics.draw,mesh)
  Voxel3D.endEffect()
  return drawn==true or (instanced and anyInst==true)
end


-- 8.1.85 BLOCK CLOUD BANK
-- Optional second presentation style for the SAME authoritative cloud
-- descriptors. It deliberately does not create a camera shell or a second
-- weather simulation: wind advection, fronts, map persistence, cloud height,
-- precipitation origins, lightning, tornado attachment and cloud transmission
-- continue to come from buildCloudDescriptors/_appendFrontCloudDescriptors.
function CinematicAtmos._cloudBankStyle()
  local S=weatherSettings()
  if S and S.cloudBankStyle then
    local ok,v=V.safeCall(S.cloudBankStyle)
    if ok and v=="blocky" then return "blocky" end
  elseif S and S.get then
    local ok,v=V.safeCall(S.get,"cloudBankStyle")
    if ok and v=="blocky" then return "blocky" end
  end
  return "volumetric"
end

CinematicAtmos._blockCloudFormat=CinematicAtmos._blockCloudFormat or {
  {"VertexPosition","float",3},
  {"BlockCloudData","float",4}, -- shade, alpha, phase, spare
}
CinematicAtmos._blockCloudRows=CinematicAtmos._blockCloudRows or {}
CinematicAtmos._blockCloudShaderSource=CinematicAtmos._blockCloudShaderSource or [[
varying float vShade;
varying float vAlpha;
varying float vPhase;
#ifdef VERTEX
uniform mat4 vp;
attribute vec4 BlockCloudData;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vShade=BlockCloudData.x;
  vAlpha=BlockCloudData.y;
  vPhase=BlockCloudData.z;
  return vp*vertex_position;
}
#endif
#ifdef PIXEL
uniform vec3 cloudColor;
uniform vec3 rayColor;
uniform float sunsetWarmth;
uniform float flashAmount;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float warm=clamp(sunsetWarmth,0.0,1.0);
  vec3 base=mix(cloudColor,rayColor,0.045+0.10*warm);
  base*=vShade;
  base=mix(base,vec3(1.0,0.99,0.96),clamp(flashAmount,0.0,1.0)*0.58);
  float alpha=clamp(vAlpha,0.0,0.78);
  return vec4(base,alpha)*color;
}
#endif
]]

function CinematicAtmos._blockCloudShader()
  if CinematicAtmos._blockCloudShaderState~=nil then return CinematicAtmos._blockCloudShaderState or nil end
  local g=love and love.graphics
  if not(g and type(g.newShader)=="function") then CinematicAtmos._blockCloudShaderState=false;return nil end
  local ok,sh=V.safeCall(g.newShader,CinematicAtmos._blockCloudShaderSource)
  CinematicAtmos._blockCloudShaderState=(ok and sh) or false
  if not ok then print("[WEATHER_FX] block cloud shader refused: "..tostring(sh)) end
  return CinematicAtmos._blockCloudShaderState or nil
end

-- Emit one horizontal tile as two explicit triangles. Tiles never overlap in
-- the local grid, so translucency stays uniform instead of producing dark
-- double-alpha seams. The tiny per-tile inset only exposes the pixel silhouette;
-- it is not a gap large enough to break a sealed storm deck.
function CinematicAtmos._emitBlockCloudTile(rows,n,x0,x1,y,z0,z1,shade,alpha,phase)
  local function put(px,pz)
    n=n+1
    local r=rows[n];if not r then r={};rows[n]=r end
    r[1],r[2],r[3]=px,y,pz
    r[4],r[5],r[6],r[7]=shade,alpha,phase,0
  end
  put(x0,z0);put(x1,z0);put(x1,z1)
  put(x0,z0);put(x1,z1);put(x0,z1)
  return n
end

function CinematicAtmos._buildBlockCloudRows(frame,clouds)
  local rows=CinematicAtmos._blockCloudRows
  local n=0
  if not clouds then return rows,0 end
  local level=max(0,min(1,tonumber(frame and frame.level) or 1))
  for i=1,#clouds do
    local c=clouds[i]
    local sx=max(34,tonumber(c.spanX) or 86)
    local sz=max(24,tonumber(c.spanZ) or 52)
    local deck=max(0,min(1,tonumber(c.deckBlend) or 0))
    local fade=max(0,min(1,tonumber(c.fadeAlpha) or 1))
    local alpha=max(0,min(.74,(.49+.15*deck)*level*fade))
    if alpha>.008 then
      -- BLOCKY is a connected stepped cloud silhouette, not a matrix of little
      -- cubes. Three touching horizontal strips share boundaries and overlap in
      -- X, so the eye reads one broad pixel-art cloud mass with stepped shoulders.
      -- The authoritative descriptor still owns the same total span, altitude,
      -- density, wind drift and front position; only its tessellation changed.
      local cols,rowsN=5,3
      local tileX=sx/cols
      local tileZ=sz/rowsN
      local baseX=(tonumber(c.cx) or 0)-sx*.5
      local baseZ=(tonumber(c.cz) or 0)-sz*.5
      local y=(tonumber(c.cy) or 0)+((hash2(tonumber(c.ix) or i,tonumber(c.iz) or i,611)-.5)*1.4)
      local phase=hash2(tonumber(c.ix) or i,tonumber(c.iz) or i,612)
      local ix,iz=tonumber(c.ix) or i,tonumber(c.iz) or i
      -- Closed storm decks remain one sealed rectangle. Broken decks use a
      -- deterministic 3-row stair-step profile. Every adjacent row touches at
      -- exactly one Z boundary and overlaps the middle row in X: no internal gaps.
      if deck>=.985 then
        local shade=.95+.05*hash2(ix,iz,670)
        n=CinematicAtmos._emitBlockCloudTile(rows,n,baseX,baseX+sx,y,baseZ,baseZ+sz,shade,alpha,phase)
      else
        local shoulderL=hash2(ix,iz,620)>.48 and 0 or 1
        local shoulderR=hash2(ix,iz,621)>.48 and 5 or 4
        local topL=1
        local topR=(hash2(ix,iz,622)>.52) and 4 or 5
        local botL=(hash2(ix,iz,623)>.52) and 0 or 1
        local botR=4
        local extents={{topL,topR},{shoulderL,shoulderR},{botL,botR}}
        for gz=0,rowsN-1 do
          local e=extents[gz+1]
          local x0=baseX+e[1]*tileX
          local x1=baseX+e[2]*tileX
          local z0=baseZ+gz*tileZ
          local z1=baseZ+(gz+1)*tileZ
          local shade=.93+.07*hash2(ix,iz,670+gz*5)
          n=CinematicAtmos._emitBlockCloudTile(rows,n,x0,x1,y,z0,z1,shade,alpha,phase)
        end
      end
    end
  end
  for i=n+1,#rows do rows[i]=nil end
  return rows,n
end

function CinematicAtmos._drawBlockClouds(Voxel3D,frame,clouds)
  if not clouds or #clouds==0 then return false end
  local sh=CinematicAtmos._blockCloudShader()
  if not sh then return false end
  local rows,n=CinematicAtmos._buildBlockCloudRows(frame,clouds)
  if n<1 then return false end
  local mesh,ok=CinematicAtmos._uploadStreamMesh("block-clouds",CinematicAtmos._blockCloudMesh,CinematicAtmos._blockCloudFormat,rows)
  CinematicAtmos._blockCloudMesh=mesh
  if not ok then return false end
  V.safeCall(love.graphics.setBlendMode,"alpha","alphamultiply")
  V.safeCall(love.graphics.setDepthMode,"lequal",false)
  if not Voxel3D.beginEffect(sh) then return false end
  V.safeCall(sh.send,sh,"vp","row",Voxel3D.vp)
  local tint=DayNight.tint(true)
  local ray=frame.rayColor or {1,1,1}
  local shade=(frame.weather and tonumber(frame.weather.cloudShade)) or 1
  CinematicAtmos._blockCloudColor=CinematicAtmos._blockCloudColor or {1,1,1}
  local co=CinematicAtmos._blockCloudColor
  co[1]=min(1,(.78*tint[1]+.18)*shade);co[2]=min(1,(.80*tint[2]+.18)*shade);co[3]=min(1,(.84*tint[3]+.16)*shade)
  V.safeCall(sh.send,sh,"cloudColor",co)
  V.safeCall(sh.send,sh,"rayColor",ray)
  local sunset=0
  do
    local E=cachedRequire("CelestialEngine")
    if E and E.state then local okS,st=V.safeCall(E.state);if okS and st then sunset=tonumber(st.cloudSunsetStrength) or tonumber(st.sunsetWarmth) or 0 end end
  end
  V.safeCall(sh.send,sh,"sunsetWarmth",max(0,min(1,sunset)))
  local flash=0
  do local L=cachedRequire("Lightning");if L and L.flash then local okF,v=V.safeCall(L.flash,"full");if okF then flash=tonumber(v) or 0 end end end
  V.safeCall(sh.send,sh,"flashAmount",max(0,min(1,flash)))
  local drawn=V.safeCall(love.graphics.draw,mesh)
  Voxel3D.endEffect()
  return drawn==true
end

function CinematicAtmos._drawCloudBank(Voxel3D,frame,clouds)
  if not clouds or #clouds==0 then return false end
  if CinematicAtmos._cloudBankStyle()=="blocky" then
    local okBlock,blockDrawn=V.safeCall(CinematicAtmos._drawBlockClouds,Voxel3D,frame,clouds)
    if okBlock and blockDrawn==true then return true end
    -- Fail open to the proven volumetric path if a host refuses the tiny block
    -- shader/mesh rather than erasing clouds entirely.
  end
  local okPrimary,primary=V.safeCall(drawParticles,Voxel3D,frame,clouds)
  if okPrimary and primary==true then return true end
  -- The compact puff path is preferred, but a shader/mesh/host seam failure
  -- must not erase the entire cloud bank. Fall back to the older clustered
  -- cloud renderer, which uses the same descriptor field and depth buffer.
  local okFallback,fallback=V.safeCall(drawClouds,Voxel3D,frame,clouds)
  return okFallback and fallback==true
end

-- ---------- public draw

-- Reusable draw-pass protection. Store caches on the existing module table so
-- this very large Lua chunk does not consume extra top-level locals (Lua caps
-- those at 200). Healthy passes reuse their result records instead of allocating.
CinematicAtmos._drawPassRecords = CinematicAtmos._drawPassRecords or {}
CinematicAtmos._precipMetaScratch = CinematicAtmos._precipMetaScratch or {}
function CinematicAtmos._safePass(tag, fn, ...)
  local ok, result = V.safeCall(fn, ...)
  local records=CinematicAtmos._drawPassRecords
  local rec = records[tag]
  if not rec then rec={}; records[tag]=rec end
  rec.ok,rec.result=ok,ok and result or nil
  CinematicAtmos._drawPass[tag]=rec
  if not ok then
    local e=CinematicAtmos._drawErrors
    e[#e+1]=tostring(tag)..":"..tostring(result)
  end
  return ok,result
end

function CinematicAtmos.draw(map, outdoor, neighbors, posed, player, state, policy)
  -- Clear health/proof at the very start. Even a Voxel3D/frame exception must
  -- not leave last frame's fog/lightning ownership looking healthy.
  local errs=CinematicAtmos._drawErrors or {}
  for i=#errs,1,-1 do errs[i]=nil end
  CinematicAtmos._drawErrors=errs
  local passes=CinematicAtmos._drawPass or {}
  for k in pairs(passes) do passes[k]=nil end
  CinematicAtmos._drawPass=passes
  CinematicAtmos._fogDrawn = false
  CinematicAtmos._cloudDescriptorCount = 0
  CinematicAtmos._cloudDrawn = false
  -- Nil policy preserves the historical full-3D call contract. Mixed mode may
  -- request only cloud banks while classic 2D precipitation remains authoritative.
  local weather3d=(policy==nil) or policy.weather3d~=false
  local clouds3d=weather3d or (policy and policy.clouds3d==true)
  local lightning3d=weather3d or (policy and policy.lightning3d==true)

  local Voxel3D = V.require("Voxel3D")
  local frame = CinematicAtmos.frame(map, outdoor)
  if not frame then return end
  CinematicAtmos._refreshSpatialFrame(Voxel3D)

  -- A cosmetic subpass must NEVER be able to prevent precipitation from
  -- reaching WorldPrecip. Before this guard, puddles/fog/clouds/rays and the
  -- precipitation block all lived under the host's one outer protected-call; one error
  -- anywhere before WorldPrecip silently removed rain/snow/leaves for the frame.
  -- Record failures for DEBUG, continue independent passes, and let the 2D
  -- ownership gate fall back if WorldPrecip itself fails.


  -- Reconcile/build cloud state only when a 3D weather or cloud consumer exists.
  -- This is the mixed-mode boundary: 2D precipitation + 3D CLOUDS wakes only
  -- descriptor/cloud geometry work, not fog, precipitation, lightning or surface FX.
  local clouds = {}
  if clouds3d then
    local earlyAnchor=worldPrecipAnchor(Voxel3D)
    CinematicAtmos._safePass("cloud-origin", updateCloudOrigin,
      earlyAnchor[1] or 0,earlyAnchor[3] or 0,1/60,map and map.id or nil,neighbors,outdoor)

    CinematicAtmos._safePass("cloud-descriptors", function()
      clouds = buildCloudDescriptors(Voxel3D, frame) or {}
      clouds = CinematicAtmos._appendFrontCloudDescriptors(Voxel3D, frame, clouds, map) or clouds
      CinematicAtmos._cloudDescriptorCount = #clouds
      V.safeCall(function()
        local E=V.require("CelestialEngine")
        local foc=Voxel3D.player or Voxel3D.focus or Voxel3D.eye
        local tr=1
        if foc and cloudTransmissionAlongRay then
          local skx,skz
          if (tonumber(frame.sunDiscVisibility) or 0)>0 then skx,skz=frame.sunShearX,frame.sunShearZ end
          tr=cloudTransmissionAlongRay(clouds,foc[1] or 0,foc[2] or 0,foc[3] or 0,0,0,skx,skz)
        elseif foc and cloudTransmissionAt then
          tr=cloudTransmissionAt(clouds,foc[1] or 0,foc[3] or 0)
        end
        if E and E.observeCloudField then
          local regional=CinematicAtmos._regionalCloudCoverage(clouds,Voxel3D,frame)
          E.observeCloudField(tr,regional)
        end
      end)
      return true
    end)
  end

  if weather3d then
    CinematicAtmos._safePass("celestial-cloud-shadows", function()
      local L=V.require("WorldCelestialLighting")
      if L and L.draw then return L.draw(Voxel3D,frame,clouds,map,neighbors) end
    end)
    CinematicAtmos._safePass("puddles", drawPuddles, Voxel3D, frame, map, neighbors)
    CinematicAtmos._safePass("snow-packs", drawSnowPacks, Voxel3D, frame, map, neighbors, outdoor)
    CinematicAtmos._safePass("sprite-reflections", drawSpriteReflections, Voxel3D, frame, map, neighbors, posed)
    local mistOk, mistDrawn = CinematicAtmos._safePass("mist", drawMist, Voxel3D, frame)
    local rollOk, rollDrawn = CinematicAtmos._safePass("roll-fog", drawRollFog, Voxel3D, frame)
    CinematicAtmos._fogDrawn = (mistOk and mistDrawn == true) or (rollOk and rollDrawn == true)
  end

  if clouds3d then
    local particleOk, particleDrawn = CinematicAtmos._safePass("cloud-particles", CinematicAtmos._drawCloudBank, Voxel3D, frame, clouds)
    CinematicAtmos._cloudDrawn = CinematicAtmos._cloudDescriptorCount > 0 and particleOk and particleDrawn == true
  end


  if weather3d then
    CinematicAtmos._safePass("distant-weather", CinematicAtmos._drawDistantWeather, Voxel3D, frame, map)
    CinematicAtmos._safePass("gust-front", function()
      local G=cachedRequire("GustFront");if G and G.draw then return G.draw(Voxel3D,frame) end
    end)
    CinematicAtmos._safePass("rays", drawRays, Voxel3D, frame, clouds)
  end

  if weather3d and not WorldPrecip then
    local okLoad, loaded = CinematicAtmos._safePass("world-precip-load", V.require, "WorldPrecip")
    if okLoad and loaded then
      WorldPrecip = loaded
      WorldPrecipLoadError = nil
    else
      WorldPrecipLoadError = tostring(loaded or WorldPrecipLoadError or "unknown WorldPrecip load error")
    end
  end
  if weather3d and WorldPrecip and WorldPrecip.draw then
    local foc, focKind = worldPrecipAnchor(Voxel3D,player)
    local dt = CinematicAtmos._weatherAnimationDt
    if dt==nil then
      dt=1/60
      -- Access to timer may be unavailable on sandboxed hosts; never index a
      -- missing branch outside protected-call. The update-owned animation dt
      -- wins whenever available, including an intentional zero while paused.
      if love and love.timer and love.timer.getDelta then
        local okTimer,v=V.safeCall(love.timer.getDelta)
        if okTimer and tonumber(v) then dt=v end
        local rec=CinematicAtmos._drawPassRecords["timer"] or {}; CinematicAtmos._drawPassRecords["timer"]=rec
        rec.ok,rec.result=okTimer,okTimer and v or nil; CinematicAtmos._drawPass["timer"]=rec
      end
    end
    -- Cloud origin was reconciled before descriptor generation above; do not
    -- apply the same map transform twice here.

    -- Bind rain/snow/hail/ash to the same rendered 3D cloud altitude. This is
    -- presentation metadata only; weather state/catalogue data stays untouched.
    local deckY, deckSpan = precipitationDeckBand(Voxel3D, frame.weather)
    local meta=CinematicAtmos._precipMetaScratch
    meta.anchorKind,meta.deckY,meta.deckSpan=focKind,deckY,deckSpan
    meta.map,meta.neighbors,meta.posed=map,neighbors,posed
    meta.player,meta.state,meta.Voxel3D=player,state,Voxel3D
    meta.volume=frame.volumeWeather
    -- Probe the real procedural precipitation backends before allocation. This
    -- removes the one-frame map/weather-start gap where the legacy instanced
    -- snow path could collapse into an overhead fountain before the procedural
    -- field proved itself on the following frame.
    if WorldPrecip.preflight then CinematicAtmos._safePass("world-precip-preflight",WorldPrecip.preflight,Voxel3D,foc,frame.weather,meta) end
    local updateOk = CinematicAtmos._safePass("world-precip-update", WorldPrecip.update, dt, foc, frame.weather, meta)
    local drawOk = false
    if updateOk then
      drawOk = CinematicAtmos._safePass("world-precip-draw", WorldPrecip.draw, Voxel3D, frame)
    end
    if not (updateOk and drawOk) and WorldPrecip.markDrawFailed then
      V.safeCall(WorldPrecip.markDrawFailed)
    end


  elseif weather3d then
    -- Old-host fallback. It is intentionally guarded separately so one legacy
    -- rain error does not corrupt the rest of the scene state.
    CinematicAtmos._safePass("legacy-rain", drawRain, Voxel3D, frame)
  end

  if lightning3d then
    -- The 2D-weather / 3D-bolt mixed mode reaches this pass without waking the
    -- precipitation renderer. Compute only the small spatial context lightning
    -- needs, then reuse the exact same scheduler/WorldLightning authority as
    -- full 3D weather.
    local foc = worldPrecipAnchor(Voxel3D,player)
    local dt = CinematicAtmos._weatherAnimationDt
    if dt==nil then
      dt=1/60
      if love and love.timer and love.timer.getDelta then
        local okTimer,v=V.safeCall(love.timer.getDelta)
        if okTimer and tonumber(v) then dt=v end
      end
    end
    local deckY, deckSpan = precipitationDeckBand(Voxel3D, frame.weather)
    -- Lightning is independent of precipitation submission; it gets its own
    -- guard so a bolt error cannot revoke rain/snow/grain rendering.
    CinematicAtmos._safePass("world-lightning", function()
      local lightMode = "full"
      local S = cachedRequire("Settings")
      if S and S.get then lightMode = tostring(S.get("lightning") or "full"):lower() end
      local WL = cachedRequire("WorldLightning")
      if not (WL and WL.draw and WL.update) then return false end
      local L = cachedRequire("Lightning")
      local T = cachedRequire("Types")
      local id = frame.weather and frame.weather.wxId or (V and V.weatherFxId)
      local sourceId = frame.weather and frame.weather._sourceWxId or (V and V.weatherFxId)
      local targetId = frame.weather and frame.weather._targetWxId or nil
      local transitionLightning = frame.weather and frame.weather._transitionActive == true
      local liveStrike = tonumber(V and V.weatherFxChannels and V.weatherFxChannels.strike) or 0
      local sourceHas = T and T.hasLightning and T.hasLightning(sourceId) or false
      local targetHas = T and T.hasLightning and T.hasLightning(targetId) or false
      local allowsLightning, lightningWeatherId
      if transitionLightning then
        -- Natural transitions use the same eased strike authority as the root
        -- scheduler. A storm clearing into rain may keep a few late bolts while
        -- stormU decays; rain developing into a storm cannot bolt until the
        -- delayed convective strike channel is actually non-zero.
        allowsLightning = liveStrike > 0.01 and (sourceHas or targetHas)
        if targetHas and (tonumber(frame.weather._stormTransitionU) or 0) > 0.02 then
          lightningWeatherId = targetId
        elseif sourceHas then
          lightningWeatherId = sourceId
        else
          lightningWeatherId = targetId or id
        end
      else
        allowsLightning = T and T.hasLightning and T.hasLightning(id) or false
        lightningWeatherId = id
      end
      if lightMode == "off" or not allowsLightning then
        if WL.clear then WL.clear() end
        if L then
          CinematicAtmos._lastStrikeSerial = tonumber(L.strikeSerial) or 0
        end
        return true
      end
      WL.update(dt, foc, frame.weather)
      if L then
        local serial = L.strikeSerial or 0
        if serial ~= (CinematicAtmos._lastStrikeSerial or 0) then
          CinematicAtmos._lastStrikeSerial = serial
          -- Start the bolt in the same physical cloud deck as precipitation.
          -- `cloudBase` is not a live profile field; using it here detached
          -- lightning from the rendered storm bank just like the old snow bug.
          local boltDeck = deckY
              or ((tonumber(frame.weather and frame.weather.deckY0) or 120) * CinematicAtmos._cloudHeightScale())
          local strikeContext = {
            deckSpan = deckSpan or tonumber(frame.weather and frame.weather.deckYSpan) or 0,
            map = map, neighbors = neighbors, player = player, Voxel3D = Voxel3D,
            -- Placement profile is weather-specific. Psychic Storm uses a much
            -- more distant ordinary-terrain distribution while NPC redirects
            -- remain governed by the shared per-bolt NPC targeting authority.
            weatherId = lightningWeatherId,
          }

          -- Shared cartoon strike rule: every individual 3D lightning bolt in
          -- every lightning-capable weather gets an independent 10% roll to
          -- redirect onto a visible non-player character. If the
          -- roll misses, or no valid NPC is actually inside the voxel view,
          -- WorldLightning follows its normal terrain target path unchanged.
          local NL = cachedRequire("NpcLightning")
          local usedNpc = {}
          local function npcImpact()
            if not (NL and NL.rollImpact) then return nil end
            local impact = NL.rollImpact(Voxel3D, nil, usedNpc)
            if impact and impact.npcTarget and impact.npcTarget.entity then
              usedNpc[impact.npcTarget.entity] = true
            end
            return impact
          end
          strikeContext.forcedImpactForBolt = function() return npcImpact() end

          local burstCount = math.max(1, math.min(4, math.floor(tonumber(L.burstCount) or 1)))
          local made
          if burstCount > 1 and WL.strikeBurst then
            made = WL.strikeBurst(foc, max(60, boltDeck), strikeContext, burstCount)
          else
            strikeContext.forcedImpact = npcImpact()
            made = WL.strike(foc, max(60, boltDeck), strikeContext)
          end
          -- Publish one distance per actual world-space bolt onto the shared
          -- Lightning scheduler. Audio consumes this on the next update and
          -- gives every bolt its own delayed/attenuated thunder voice. This is
          -- deliberately after allocation so burst storms use the real sampled
          -- world distances rather than one guessed event distance.
          if L and L.publishWorldStrikeBatch then
            local distances = {}
            if type(made) == "table" and made.pts then
              if tonumber(made.dist) then distances[1] = tonumber(made.dist) end
            elseif type(made) == "table" then
              for _, b in ipairs(made) do
                if b and tonumber(b.dist) then distances[#distances + 1] = tonumber(b.dist) end
              end
            end
            if #distances > 0 then
              V.safeCall(L.publishWorldStrikeBatch, serial, distances)
            end
          end

          if NL and NL.hit then
            if type(made) == "table" and made.pts then
              if made.npcTarget then NL.hit(made.npcTarget) end
            elseif type(made) == "table" then
              for _, b in ipairs(made) do
                if b and b.npcTarget then NL.hit(b.npcTarget) end
              end
            end
          end
        end
      end
      if lightMode == "full" then WL.draw(Voxel3D) end

      -- Weather lighting uses the same strike objects as the bolt renderer. The
      -- result is a depth-tested glow at the cloud source and actual terrain
      -- impact instead of a screen-wide flash glued to the camera. FLASH mode
      -- keeps this world illumination while omitting the visible channel.
      local WorldLighting = V.require("WorldLighting")
      if WorldLighting and WorldLighting.draw then
        if not WorldLighting.draw(Voxel3D, WL) then
          error("world lighting draw failed", 0)
        end
      end
      return true
    end)
  end

  V.safeCall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  V.safeCall(love.graphics.setDepthMode, "lequal", true)
end

-- Behavioural ownership signals consumed by DramalessAtmos. These are reset
-- every draw, so a failed/aborted frame cannot inherit stale success.
function CinematicAtmos.fogDrawing()
  return CinematicAtmos._fogDrawn == true
end

function CinematicAtmos.cloudStatus()
  return CinematicAtmos._cloudDescriptorCount or 0, CinematicAtmos._cloudDrawn == true
end

-- Live lower cloud-deck band shared with precipitation and 3D tornado formation.
-- Returning the same metadata avoids a second guessed sky height.
function CinematicAtmos.precipitationDeck()
  local m=CinematicAtmos._precipMetaScratch
  if type(m)=="table" then return tonumber(m.deckY),tonumber(m.deckSpan) end
end

function CinematicAtmos.passHealthy(tag)
  local p = CinematicAtmos._drawPass and CinematicAtmos._drawPass[tag]
  return p ~= nil and p.ok == true and p.result ~= false
end

function CinematicAtmos.markFrameFailed()
  CinematicAtmos._fogDrawn = false
  CinematicAtmos._cloudDescriptorCount = 0
  CinematicAtmos._cloudDrawn = false
  CinematicAtmos._drawPass = {}
  V.safeCall(function()
    if WorldPrecip and WorldPrecip.markDrawFailed then WorldPrecip.markDrawFailed() end
  end)
end

function CinematicAtmos.drawErrors()
  local e = CinematicAtmos._drawErrors
  if not e or #e == 0 then return nil end
  return table.concat(e, "|")
end

function CinematicAtmos.suspendWeather3d()
  CinematicAtmos._fogDrawn=false
  V.safeCall(function() if WorldPrecip and WorldPrecip.suspend then WorldPrecip.suspend() end end)
  V.safeCall(function() local WL=cachedRequire("WorldLightning");if WL and WL.clear then WL.clear() end end)
  V.safeCall(function() local G=cachedRequire("GustFront");if G and G.invalidate then G.invalidate() end end)
  return true
end

function CinematicAtmos.invalidate()
  V.safeCall(function() if WorldPrecip and WorldPrecip.invalidate then WorldPrecip.invalidate() end end)
  V.safeCall(function() local G=cachedRequire("GustFront");if G and G.invalidate then G.invalidate() end end)
  mistMesh, rollMesh, particleMesh, rainMesh, rayMesh, cloudMesh, puddleMesh = nil, nil, nil, nil, nil, nil, nil
  CinematicAtmos._cloudMeshCapacity = 0
  CinematicAtmos._streamMeshCaps = {}
  puddleMeshKey = nil
  mistShaderState, rollShaderState, particleShaderState, rainShaderState, rayShaderState, cloudShaderState, puddleBaseShaderState = nil, nil, nil, nil, nil, nil, nil
end

return CinematicAtmos
