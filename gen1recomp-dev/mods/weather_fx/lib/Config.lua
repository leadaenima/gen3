-- CONFIGURATION: loading config.lua, checking it, and deciding what wins.
--
-- WHY A FILE AND A MENU, NOT ONE OR THE OTHER.  They answer different
-- questions.  The menu answers "what do I want to see right now" and has
-- to be reachable on a handheld with no keyboard, so it is short.  The
-- file answers "how should this mod behave in my playthrough" -- per-map
-- overrides, per-weather density, which battle effects exist -- and none
-- of that belongs on a row the player cycles with a d-pad.  So both, with
-- one documented precedence order and no third place for a value to hide:
--
--   1. config.force        -- the file pins one weather everywhere
--   2. config.locations    -- the file pins one weather on this map
--   3. the OPTIONS row     -- OFF / AUTO / a pinned weather
--   4. the AUTO clock
--
-- WHY IT CANNOT BREAK THE MOD.  The file is loaded with `load`, called in
-- a pcall, and then walked against the default table: every key is
-- checked for type and range, and anything wrong is replaced by the
-- default and reported by name through mod.log (which the mod manager's
-- error feed shows).  A missing file, an empty file, a syntax error, a
-- table of nonsense -- all of them end with a usable config and a running
-- mod, because a player editing a config file is the single most likely
-- way this mod ever sees malformed input.
--
-- WHAT IS NOT VALIDATED is map ids in `locations`.  There is no list of
-- them to check against that would still be right after a map mod loads,
-- and a typo'd map id is self-diagnosing (the weather does not appear
-- there).  Weather ids inside those entries ARE checked, because those
-- fail silently otherwise.

local V = ...
local mod = V.mod
local Types = V.require("Types")

local Config = {}

Config.FILE = "config.lua"

-- ------- defaults
--
-- The shape below is authoritative: the validator walks THIS table and
-- copies matching keys out of the user's, so a key the defaults do not
-- have is reported as unknown rather than silently carried.  That makes a
-- typo ("lightingMode") a message instead of a mystery.

local DEFAULTS = {
  force = nil,
  locations = {},
  bias = {},
  tuning = { ALL = { density = 1, intensity = 1, speed = 1, duration = 1, weight = 1 } },
  weathers = {},
  indoorMaps = {
    SSAnne1F=true, SSAnne2F=true, SSAnne3F=true, SSAnneB1F=true,
    SSAnneBow=true, SSAnneKitchen=true, SSAnneCaptainsRoom=true,
    SSAnne1FRooms=true, SSAnne2FRooms=true,
    SSANNE1F=true, SSANNE2F=true, SSANNE3F=true, SSANNEB1F=true,
    SSANNEBOW=true, SSANNEKITCHEN=true, SSANNECAPTAINSROOM=true,
    SSANNE1FROOMS=true, SSANNE2FROOMS=true,
  },
  visuals = {
    precipitation = true, splashes = true, fog = true, veil = true,
    tint = true, glare = true, lightning = true, battleWeather = true,
    textBoxClear = true,
    puddles = true,
  },
  coverage = "screen",
  battleView = "auto",
  battleBackdrops = true,
  battleFieldArt = "auto",
  encounters = { enabled = true, species = true, fishing = true,
                 strength = 1.0, rateBoost = 1.5, fishingBonus = 0.5,
                 -- When the map's table has no matching type, inject a dex
                 -- species of the favoured type at the rolled level.  Pool
                 -- is the merged pokemon registry (expanded dex included).
                 inject = true, injectChance = 0.35 },
  -- : how long a roused bird holds the sky. Without it a rousing
  -- only ended by leaving the map, so standing still froze the weather.
  legendary = { enabled = true, chance = 0.05, encounters = true,
                rateBoost = 1.05, encounterChance = 0.15, level = 50, minutes = 6 },
  psystorm = { enabled = true, carrierChance = 0.7, scale = 1.0 },
  -- House-rule visual gag: every world-space bolt has a 10% chance to target a visible NPC.
  -- Keep this fallback byte-for-byte aligned with shipped config.lua so a
  -- missing/unreadable config cannot silently change gameplay behavior.
  npcLightning = { enabled = true, chance = 0.10, duration = 3.0, nearRadius = 192.0 },
  fronts = { enabled = true, drift = 0.5 },
  mesoscale = { enabled = true, strength = 1.0 },
  rainbow = { enabled = true, memorySeconds = 120, fadeSeconds = 8 },
  wind = { playerMovement = true, headwindSlow = 0.10, tailwindBoost = 0.04, minimumStrength = 0.10 },
  pokegear = { enabled = true },
  audio = { enabled = true, volume = 1.0, indoors = 0.55, battle = 0.35,
            indoorRainHighGain = 0.55, indoorWindHighGain = 0.45,
            indoorThunderHighGain = 0.40, indoorTransition = 0.45,
            thunder = true, thunderGain = 0.8,
            wind = true },
  tornado = { enabled = true, everySeconds = 90, minVisited = 4,
              carryChance = 0.10, roamSeconds = 180, formationSeconds = 8, ropeSeconds = 12,
              spawnDistanceMin = 150, spawnDistanceMax = 250, maxActive = 3, touchRadius = 14,
              secondaryChance = 0.12, outbreakChance = 0.035, waterTwister = true,
              sandstorms = false, funnel = true, funnelSeconds = 2.5 },
  followerChip = { enabled = true, seconds = 6, fraction = 1/32, canFaint = false },
  battleBackdropDim = 0.25,
  autoIntensity = { min = 0.5, max = 1.4, seconds = 1.0 },
  splashSpread = 1.0,
  time = {
    source = "auto", cycleMinutes = 24, fixedPhase = "DAY",
    grade = true, gradeStrength = 1.0, publishTod = true, indoors = 0.35,
  },
  -- Seasons sit on top of the day/night clock.  enabled/notify can also be
  -- flipped from the mod options page; the file is the set-once default.
  seasons = {
    enabled = true,
    notify = true,
    notifySeconds = 3.5,
    daysPerSeason = 15,   -- 15 in-game days = 6 real hours at the default 24-minute day
    placeBanner = true,   -- location + season on map entry / game entry
  },
  -- Ultimate celestial engine. The feature set is intentionally one coherent
  -- house-rule system instead of a collection of inert toggles: when enabled,
  -- astronomy, phases, scattering, cloud occlusion/shadows, Milky Way, light
  -- pollution, reflections and eclipses all share this authority.
  celestial = {
    enabled = true,
    latitude = 35.0,       -- retained for seasons/star-vault rotation
    axialTilt = 23.43928,
    -- House rule / voxel presentation: keep sun + moon on a fixed world
    -- East-Up-West great-circle so they visibly rise, pass overhead, and set
    -- on the opposite side of the map. Set false for the latitude/declination
    -- horizon path, which is more astronomical but reads as a horizontal
    -- orbit in the voxel camera.
    verticalOrbit = true,
    pairedMoonOrbit = true,
    motionSmoothing = true, -- continuously interpolate sun/moon motion between coarse host clock ticks
    shadowMotionPrecision = 65536, -- finer in-memory voxel shadow-map invalidation
    discSupersample = 16, -- 16x local sun/moon raster; downsampled for extremely fine subpixel motion
    -- House rule: replace voxel hosts' checker-dithered palette bands with a
    -- continuous generated gradient while keeping the same live sky colours.
    smoothSky = true,
    events = true, -- special lunar events + shooting stars/meteor showers
    -- Lunar phase is a 29.530588-night cycle; one in-game night advances one lunar day.
    -- Phase is held stable from evening through the following morning.
  },
  battle = {
    enabled = true,
    seedFromOverworld = true,
    seededTurns = nil,
    effects = {
      typePower = true, accuracy = true, solarBeam = true,
      residual = true, defenseBoost = true, speed = true,
      evasion = true, healing = true,
      heldItems = true,
      -- Both are house rules rather than reference behaviour, so they
      -- carry their own switches instead of riding on typePower.
      --
      -- They default differently on purpose. `amplified` CONTRADICTS
      -- reference multipliers this mod already implements and tests
      -- ("...but physical damage is untouched" asserts a sandstorm does
      -- not power up ROCK), so switching it on by default would mean the
      -- mod quietly stopped doing what its own suite says it does --
      -- opt-in. `terrain` ADDS something the reference has no opinion on
      -- at all and only fires on named maps, so it contradicts nothing --
      -- on by default.
      amplified = false, terrain = true,
      -- the opening lines naming what the weather is doing to the fight
      announce = true,
    },
    -- Per-map type multipliers, applied whatever the weather.  Keys are
    -- map ids; a map with no entry gets nothing.  These ids are verified
    -- against tools/rom_manifest.json; ids the player adds are not checked
    -- at runtime and fail silently if wrong, which is what the DEBUG HUD's
    -- `map:`/`terr:` readout is for.
    terrain = {
      VIRIDIAN_FOREST = { BUG = 1.5, GRASS = 1.5 },
      POWER_PLANT     = { ELECTRIC = 1.5 },
      POKEMON_TOWER_1F = { GHOST = 1.5 },
      POKEMON_TOWER_2F = { GHOST = 1.5 },
      POKEMON_TOWER_3F = { GHOST = 1.5 },
      POKEMON_TOWER_4F = { GHOST = 1.5 },
      POKEMON_TOWER_5F = { GHOST = 1.5 },
      POKEMON_TOWER_6F = { GHOST = 1.5 },
      POKEMON_TOWER_7F = { GHOST = 1.5 },
      -- ------- Johto (Gold), verified against tools/rom_manifest_gold.json
      --
      -- The Kanto ids above mostly do NOT exist on Gold: only 76 of Gen 1's
      -- 222 maps survive into it, and Pokemon Tower (a Radio Tower by then)
      -- and Viridian Forest are not among them. Left alone, eight of the ten
      -- entries above would have been silently dead on a Gold boot -- the
      -- same failure that killed them once already under a misspelt id.
      --
      -- Both sets ship together because the table is keyed by MAP ID: an id
      -- that does not exist in the running game simply never matches, so the
      -- Johto rows cost a Kanto game nothing and vice versa.
      ILEX_FOREST      = { BUG = 1.5, GRASS = 1.5 },   -- Johto's Viridian Forest
      SPROUT_TOWER_1F  = { GHOST = 1.5 },
      SPROUT_TOWER_2F  = { GHOST = 1.5 },
      SPROUT_TOWER_3F  = { GHOST = 1.5 },
      BURNED_TOWER_1F  = { GHOST = 1.5 },              -- the Johto ghost site
      BURNED_TOWER_B1F = { GHOST = 1.5 },
      -- POWER_PLANT is in both games under the same id, so it needs no twin.
    },
    residualDamage = {
      fraction = 1 / 16, canFaint = true,
      sandImmune = { "ROCK", "GROUND", "STEEL" },
      psyImmune = { "PSYCHIC" },
      hailImmune = { "ICE" },
    },
    suppressAbilities = { "CLOUD_NINE" },
    items = {
      extenders = {
        DAMP_ROCK = "RAINY", HEAT_ROCK = "SUNNY",
        ICY_ROCK = "HAIL", SMOOTH_ROCK = "SANDSTORM",
      },
      extendBy = 3,
      umbrella = "UTILITY_UMBRELLA",
    },
  },
  quality = "auto",
  maxParticles = nil,
  transitionSeconds = 3.2,
  debug = false,
  debugRain = false,
}

-- Ranges for the numeric keys, by dotted path.  Anything outside is
-- clamped and reported rather than rejected: a player who wrote
-- `density = 50` wants "a lot", and clamping to 3 gives them that.
local RANGES = {
  ["tuning.*.density"] = { 0, 3 },
  ["tuning.*.intensity"] = { 0, 3 },
  ["tuning.*.speed"] = { 0.25, 3 },
  ["tuning.*.duration"] = { 0.1, 10 },
  ["tuning.*.weight"] = { 0, 20 },
  ["time.cycleMinutes"] = { 0.5, 1440 },
  ["time.gradeStrength"] = { 0, 2 },
  ["time.indoors"] = { 0, 1 },
  ["battle.residualDamage.fraction"] = { 0, 0.5 },
  ["battle.items.extendBy"] = { 0, 20 },
  ["transitionSeconds"] = { 0.1, 60 },
  ["autoIntensity.min"] = { 0, 2 },
  ["autoIntensity.max"] = { 0, 3 },
  ["autoIntensity.seconds"] = { 0.05, 20 },
  ["splashSpread"] = { 0, 1 },
  ["legendary.chance"] = { 0, 1 },
  ["legendary.encounterChance"] = { 0, 1 },
  ["legendary.rateBoost"] = { 1, 3 },
  ["legendary.level"] = { 1, 100 },
  ["psystorm.carrierChance"] = { 0, 1 },
  ["psystorm.scale"] = { 0, 1 },
  ["npcLightning.chance"] = { 0, 1 },
  ["npcLightning.duration"] = { 0.1, 30 },
  ["npcLightning.nearRadius"] = { 16, 512 },
  ["fronts.drift"] = { 0, 1 },
  ["mesoscale.strength"] = { 0, 1.5 },
  ["rainbow.memorySeconds"] = { 20, 600 },
  ["rainbow.fadeSeconds"] = { 0.5, 30 },
  ["wind.headwindSlow"] = { 0, 0.25 },
  ["wind.tailwindBoost"] = { 0, 0.12 },
  ["wind.minimumStrength"] = { 0, 1.5 },
  ["audio.volume"] = { 0, 2 },
  ["audio.indoors"] = { 0, 1 },
  ["audio.indoorRainHighGain"] = { 0, 1 },
  ["audio.indoorWindHighGain"] = { 0, 1 },
  ["audio.indoorThunderHighGain"] = { 0, 1 },
  ["audio.indoorTransition"] = { 0.05, 5 },
  ["audio.battle"] = { 0, 1 },
  ["audio.thunderGain"] = { 0, 2 },
  ["tornado.everySeconds"] = { 30, 3600 },
  ["tornado.minVisited"] = { 2, 60 },
  ["tornado.funnelSeconds"] = { 0, 10 },
  ["tornado.carryChance"] = { 0, 1 },
  ["tornado.roamSeconds"] = { 30, 600 },
  ["tornado.formationSeconds"] = { 2, 30 },
  ["tornado.ropeSeconds"] = { 2, 30 },
  ["tornado.spawnDistanceMin"] = { 64, 512 },
  ["tornado.spawnDistanceMax"] = { 96, 768 },
  ["tornado.maxActive"] = { 1, 4 },
  ["tornado.touchRadius"] = { 6, 32 },
  ["tornado.secondaryChance"] = { 0, 0.75 },
  ["tornado.outbreakChance"] = { 0, 0.5 },
  ["encounters.strength"] = { 0, 3 },
  ["encounters.rateBoost"] = { 1, 3 },
  ["encounters.fishingBonus"] = { 0, 1 },
  ["encounters.injectChance"] = { 0, 1 },
  ["followerChip.seconds"] = { 1, 600 },
  ["followerChip.fraction"] = { 0, 0.25 },
  ["battleBackdropDim"] = { 0, 1 },
  ["maxParticles"] = { 0, 20000 },
}

-- Keys whose DEFAULT is nil, so the merge cannot infer their type from the
-- default table.  Without this list every one of them would be reported as
-- an unknown key -- which is exactly what "no default" looks like to a
-- table walk.  Listing them keeps the typo detection strict everywhere
-- else: a key that is neither in the defaults nor here really is a typo.
local OPTIONAL = {
  force = "string",
  maxParticles = "number",
  ["battle.seededTurns"] = "number",
}

local ENUMS = {
  ["coverage"] = { screen = true, playfield = true },
  ["battleView"] = { auto = true, canvas = true, screen = true },
  ["battleFieldArt"] = { auto = true, on = true, off = true, mono = true },
  ["quality"] = { auto = true, max = true, high = true, medium = true, low = true, potato = true },
  ["time.source"] = { auto = true, system = true, cycle = true,
                      fixed = true, off = true },
  ["time.fixedPhase"] = { MORN = true, DAY = true, EVE = true, NITE = true },
}

-- ------- the live config, and the problems found loading it

Config.data = nil
Config.problems = {}
-- Whether config.lua was found and read at all.  Reported on the debug
-- readout, because "my edits do nothing" and "there is no file to edit"
-- look identical from the player's side -- and a .modpkg install has no
-- editable file at all.
Config.found = false

local function problem(fmt, ...)
  local line = select("#", ...) > 0 and fmt:format(...) or fmt
  Config.problems[#Config.problems + 1] = line
  mod.log:warn("config.lua: %s", line)
end

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepCopy(v) end
  return out
end

local function isWeatherId(id)
  return type(id) == "string" and Types.byId[id] ~= nil
end

-- Enum keys fall back to the default rather than being stored, so a
-- typo'd `coverage = "playfeild"` behaves like the default instead of
-- silently disabling a feature.  This table existed since 2.0.0 and was
-- never actually consulted -- a test asserting the hole is what found it.
local function checkEnum(path, value, default)
  local allowed = ENUMS[path]
  if not allowed then return value end
  if allowed[value] then return value end
  problem("%s = %s is not one of its allowed values; using %s",
    path, tostring(value), tostring(default))
  return default
end

local function clampPath(path, value)
  local range = RANGES[path]
  if not range or type(value) ~= "number" or value ~= value then return value end
  if value < range[1] then
    problem("%s = %s is below %s; clamped", path, tostring(value), tostring(range[1]))
    return range[1]
  end
  if value > range[2] then
    problem("%s = %s is above %s; clamped", path, tostring(value), tostring(range[2]))
    return range[2]
  end
  return value
end

-- Merge `user` over `base` in place, type-checking against `base`.
-- `wildcard` marks a level whose keys are user-chosen (tuning ids, map
-- ids), where an unknown key is data rather than a typo.
local function merge(base, user, path, wildcard)
  if type(user) ~= "table" then
    problem("%s should be a table; ignored", path ~= "" and path or "config")
    return base
  end
  for key, value in pairs(user) do
    local sub = (path == "" and tostring(key)) or (path .. "." .. tostring(key))
    local default = base[key]
    local optional = OPTIONAL[sub]
    if default == nil and optional then
      if type(value) ~= optional then
        problem("%s should be a %s, got %s; ignored", sub, optional, type(value))
      else
        base[key] = clampPath(sub, value)
      end
    elseif default == nil and not wildcard then
      problem("unknown key %s; ignored", sub)
    elseif type(default) == "table" and type(value) == "table" then
      -- one level of wildcard: the CHILDREN of tuning/locations/bias are
      -- user-named, their contents are not
      merge(default, value, sub, false)
    elseif type(default) == "table" and type(value) ~= "table" then
      problem("%s should be a table; ignored", sub)
    elseif default ~= nil and type(value) ~= type(default) then
      problem("%s should be a %s, got %s; ignored", sub, type(default), type(value))
    else
      base[key] = checkEnum(sub, clampPath(sub, value), default)
    end
  end
  return base
end

-- ------- entry-shape checks for the two user-keyed tables

local function normaliseLocation(mapId, entry)
  if type(entry) == "string" then
    entry = { weather = entry }
  elseif type(entry) ~= "table" then
    problem("locations.%s should be a weather id or a table; ignored", tostring(mapId))
    return nil
  end
  if not isWeatherId(entry.weather) then
    problem("locations.%s has unknown weather %q; ignored",
      tostring(mapId), tostring(entry.weather))
    return nil
  end
  local chance = tonumber(entry.chance)
  if chance == nil then chance = 1 end
  if chance < 0 then chance = 0 elseif chance > 1 then chance = 1 end
  return { weather = entry.weather, chance = chance,
           indoors = entry.indoors and true or false }
end

local function normaliseTuning(id, entry)
  if id ~= "ALL" and not isWeatherId(id) then
    problem("tuning.%s is not a weather id; ignored", tostring(id))
    return nil
  end
  if type(entry) ~= "table" then
    problem("tuning.%s should be a table; ignored", tostring(id))
    return nil
  end
  -- Clamped HERE rather than in the generic merge: these keys live under a
  -- user-chosen weather id, so their dotted path is not knowable in advance
  -- and the RANGES table addresses them through a `*` wildcard.
  local function one(key)
    local v = tonumber(entry[key])
    if v == nil then return 1 end
    return clampPath("tuning.*." .. key, v)
  end
  return { density = one("density"), intensity = one("intensity"),
           speed = one("speed"), duration = one("duration"),
           weight = one("weight") }
end

-- ------- load

function Config.load()
  Config._tuningCache = {}
  Config.problems = {}
  Config._playerBase = nil
  Config._playerRevision = nil
  local data = deepCopy(DEFAULTS)

  local source = nil
  local okRead = pcall(function() source = mod:read(Config.FILE) end)
  Config.found = (okRead and source ~= nil) and true or false
  if not okRead or not source then
    -- No config file is the normal case for a fresh install, not an error.
    Config.data = data
    Config.finalise(data)
    return data
  end

  local loadChunk = loadstring or load
  local chunk, err = loadChunk(source, "@" .. Config.FILE)
  if not chunk then
    problem("did not compile (%s); using defaults", tostring(err))
    Config.data = data
    Config.finalise(data)
    return data
  end

  -- The file is data, so it is run with no arguments and its return value
  -- is all that is kept.  A file that throws costs its own contents and
  -- nothing else.
  local okRun, user = pcall(chunk)
  if not okRun or type(user) ~= "table" then
    problem("did not return a table (%s); using defaults",
      tostring(okRun and type(user) or user))
    Config.data = data
    Config.finalise(data)
    return data
  end

  -- the user-keyed tables come out before the type-checked merge, because
  -- their keys are data and would every one be reported as unknown
  local locations, bias, tuning = user.locations, user.bias, user.tuning
  local weathers, indoorMaps = user.weathers, user.indoorMaps
  user.locations, user.bias, user.tuning = nil, nil, nil
  user.weathers, user.indoorMaps = nil, nil

  -- Encounter hard-ban tables are user data too. `bansById` is keyed by
  -- weather id and each value is a variable-length type list; `bans` permits
  -- those lists or literal false. The strict shape merge cannot represent
  -- either without rejecting valid entries, so validate them explicitly.
  local encounterBans, encounterBansById = nil, nil
  if type(user.encounters) == "table" then
    encounterBans = user.encounters.bans
    encounterBansById = user.encounters.bansById
    user.encounters.bans = nil
    user.encounters.bansById = nil
  end

  -- Pre-split legacy keys that Weather FX never implemented itself. Older
  -- configs may still contain them; accept-and-drop silently rather than
  -- advertising inert switches or rejecting a previously valid file.
  -- Old standalone config controls that were never consumed by the live
  -- renderer/mixer. Keep upgrades quiet, but do not ship knobs that lie.
  user.lightningMode = nil
  if type(user.audio) == "table" then user.audio.fadeSeconds = nil end

  if type(user.battle) == "table" then
    -- Removed WX RULES gate: old files may still carry this inert key.
    user.battle.requireRuleset = nil
    if type(user.battle.effects) == "table" then
      user.battle.effects.weatherBall = nil
      user.battle.effects.forms = nil
    end
  end

  -- battle.terrain is keyed by MAP ID, so it comes out too: left in, the
  -- strict merge would report every map the player added as an unknown
  -- key and drop it.  Its own table, not `locations`, because a map can
  -- reasonably have both a weather override and a terrain bonus.
  local terrain = nil
  if type(user.battle) == "table" then
    terrain = user.battle.terrain
    user.battle.terrain = nil
  end

  merge(data, user, "", false)

  local function typeList(path, list)
    if type(list) ~= "table" then
      problem("%s should be a list of type names; ignored", path)
      return nil
    end
    local out = {}
    for i = 1, #list do
      if type(list[i]) == "string" and list[i] ~= "" then
        out[#out + 1] = list[i]:upper()
      else
        problem("%s[%d] should be a type name; ignored", path, i)
      end
    end
    return out
  end

  if encounterBans ~= nil then
    if encounterBans == false then
      data.encounters.bans = false
    elseif type(encounterBans) == "table" then
      local allowed = { wet=true, sunny=true, frozen=true, sandy=true,
                        foggy=true, ash=true, psychic=true }
      local out = {}
      for tag, list in pairs(encounterBans) do
        if allowed[tag] then
          local norm = typeList("encounters.bans." .. tostring(tag), list)
          if norm then out[tag] = norm end
        else
          problem("unknown key encounters.bans.%s; ignored", tostring(tag))
        end
      end
      data.encounters.bans = out
    else
      problem("encounters.bans should be a table or false; ignored")
    end
  end

  if encounterBansById ~= nil then
    if type(encounterBansById) == "table" then
      local out = {}
      for weatherId, list in pairs(encounterBansById) do
        local id = tostring(weatherId or ""):upper()
        if not isWeatherId(id) then
          problem("encounters.bansById.%s has unknown weather id; ignored", tostring(weatherId))
        else
          local norm = typeList("encounters.bansById." .. id, list)
          if norm then out[id] = norm end
        end
      end
      data.encounters.bansById = out
    else
      problem("encounters.bansById should be a table; ignored")
    end
  end

  if locations ~= nil then
    data.locations = {}
    if type(locations) == "table" then
      for mapId, entry in pairs(locations) do
        local norm = normaliseLocation(mapId, entry)
        if norm then data.locations[mapId] = norm end
      end
    else
      problem("locations should be a table; ignored")
    end
  end

  if bias ~= nil then
    if type(bias) == "table" then data.bias = bias
    else problem("bias should be a table; ignored") end
  end

  if tuning ~= nil then
    data.tuning = { ALL = { density = 1, intensity = 1, speed = 1, duration = 1 } }
    if type(tuning) == "table" then
      for id, entry in pairs(tuning) do
        local norm = normaliseTuning(id, entry)
        if norm then data.tuning[id] = norm end
      end
    else
      problem("tuning should be a table; ignored")
    end
  end

  if weathers ~= nil then
    data.weathers = {}
    if type(weathers) == "table" then
      for id, on in pairs(weathers) do
        if not isWeatherId(id) then
          problem("weathers.%s is not a weather id; ignored", tostring(id))
        else
          data.weathers[id] = on and true or false
        end
      end
    else
      problem("weathers should be a table; ignored")
    end
  end

  if indoorMaps ~= nil then
    data.indoorMaps = {}
    if type(indoorMaps) == "table" then
      -- accepts either { "MAP_ID", ... } or { MAP_ID = true }
      for k, v in pairs(indoorMaps) do
        if type(k) == "number" and type(v) == "string" then
          data.indoorMaps[v] = true
        elseif type(k) == "string" then
          data.indoorMaps[k] = v and true or false
        end
      end
    else
      problem("indoorMaps should be a table; ignored")
    end
  end

  if terrain ~= nil then
    data.battle.terrain = {}
    if type(terrain) == "table" then
      for mapId, row in pairs(terrain) do
        if type(mapId) ~= "string" then
          problem("battle.terrain keys should be map ids; ignored")
        elseif type(row) ~= "table" then
          problem("battle.terrain.%s should be a table of TYPE = multiplier; ignored",
            tostring(mapId))
        else
          local clean = nil
          for typeName, mult in pairs(row) do
            local n = tonumber(mult)
            if type(typeName) ~= "string" or n == nil then
              problem("battle.terrain.%s.%s should be TYPE = number; ignored",
                tostring(mapId), tostring(typeName))
            else
              -- Same spirit as clampPath elsewhere: a player who wrote 50
              -- wants "a lot", and a hard clamp gives them that without
              -- letting a typo one-shot the whole game.
              if n < 0 then n = 0 elseif n > 4 then n = 4 end
              clean = clean or {}
              clean[typeName:upper()] = n
            end
          end
          if clean then data.battle.terrain[mapId] = clean end
        end
      end
    else
      problem("battle.terrain should be a table; ignored")
    end
  end

  if data.force ~= nil and not isWeatherId(data.force) then
    problem("force = %q is not a weather id; ignored", tostring(data.force))
    data.force = nil
  end

  Config.data = data
  Config.finalise(data)
  return data
end

-- Normalise the shapes the hot paths read every frame, so those paths do
-- no defaulting of their own.
function Config.finalise(data)
  data.tuning = data.tuning or {}
  data.tuning.ALL = data.tuning.ALL
    or { density = 1, intensity = 1, speed = 1, duration = 1, weight = 1 }
  data.weathers = data.weathers or {}
  data.indoorMaps = data.indoorMaps or {}
  data.locations = data.locations or {}
  data.bias = data.bias or {}
  -- immunity lists become sets, once, rather than a linear scan per turn
  local rd = data.battle.residualDamage
  rd.sandImmuneSet, rd.hailImmuneSet, rd.psyImmuneSet = {}, {}, {}
  for _, t in ipairs(rd.psyImmune or { "PSYCHIC" }) do rd.psyImmuneSet[t] = true end
  for _, t in ipairs(rd.sandImmune or {}) do rd.sandImmuneSet[t] = true end
  for _, t in ipairs(rd.hailImmune or {}) do rd.hailImmuneSet[t] = true end
  local suppress = {}
  for _, a in ipairs(data.battle.suppressAbilities or {}) do suppress[a] = true end
  data.battle.suppressSet = suppress
  if #Config.problems > 0 then
    mod.log:warn("config.lua loaded with %d problem(s); defaults used for those",
      #Config.problems)
  end
end

local function capturePlayerBase(data)
  local c=data or {}
  local v=c.visuals or {}; local n=c.npcLightning or {}; local f=c.fronts or {}
  local m=c.mesoscale or {}; local ce=c.celestial or {}; local t=c.time or {}
  local se=c.seasons or {}; local a=c.audio or {}; local en=c.encounters or {}
  local le=c.legendary or {}; local fc=c.followerChip or {}; local to=c.tornado or {}
  local rb=c.rainbow or {}; local wd=c.wind or {}
  Config._playerBase={
    transitionSeconds=c.transitionSeconds,
    frontsEnabled=f.enabled,frontsDrift=f.drift,
    mesoscaleEnabled=m.enabled,mesoscaleStrength=m.strength,
    puddles=v.puddles,glare=v.glare,
    npcEnabled=n.enabled,npcChance=n.chance,
    tornadoEvery=to.everySeconds,
    rainbowEnabled=rb.enabled,windPlayerMovement=wd.playerMovement,
    celestialEvents=ce.events,smoothSky=ce.smoothSky,motionSmoothing=ce.motionSmoothing,
    timeSource=t.source,cycleMinutes=t.cycleMinutes,
    daysPerSeason=se.daysPerSeason,
    indoorAudio=a.indoors,thunderAudio=a.thunder,windAudio=a.wind,
    encountersEnabled=en.enabled,legendaryEnabled=le.enabled,followerChipEnabled=fc.enabled,
    maxParticles=c.maxParticles,
  }
  Config._playerRevision=nil
end

-- Apply only the controls deliberately exposed in the in-game advanced pages.
-- New rows default to CONFIG, so existing folder-install config.lua choices keep
-- precedence until the player explicitly overrides that individual control.
function Config.applyPlayerSettings()
  local data=Config.data; if type(data)~="table" then return end
  if not Config._playerBase then capturePlayerBase(data) end
  local S=Config._Settings
  if not S then
    local ok,loaded=pcall(V.require,"Settings")
    if ok and type(loaded)=="table" then Config._Settings=loaded; S=loaded end
  end
  if type(S)~="table" or type(S.get)~="function" then return end
  local rev=type(S.optionRevision)=="function" and S.optionRevision() or 0
  if Config._playerRevision==rev then return end
  Config._playerRevision=rev
  local b=Config._playerBase
  data.fronts=data.fronts or {}; data.mesoscale=data.mesoscale or {}; data.visuals=data.visuals or {}
  data.npcLightning=data.npcLightning or {}; data.tornado=data.tornado or {}; data.celestial=data.celestial or {}
  data.time=data.time or {}; data.seasons=data.seasons or {}; data.audio=data.audio or {}
  data.rainbow=data.rainbow or {}; data.wind=data.wind or {}
  data.encounters=data.encounters or {}; data.legendary=data.legendary or {}; data.followerChip=data.followerChip or {}

  -- Restore authored config values first; then layer explicit menu overrides.
  data.transitionSeconds=b.transitionSeconds
  data.fronts.enabled=b.frontsEnabled; data.fronts.drift=b.frontsDrift
  data.mesoscale.enabled=b.mesoscaleEnabled; data.mesoscale.strength=b.mesoscaleStrength
  data.visuals.puddles=b.puddles; data.visuals.glare=b.glare
  data.npcLightning.enabled=b.npcEnabled; data.npcLightning.chance=b.npcChance
  data.tornado.everySeconds=b.tornadoEvery
  data.rainbow.enabled=b.rainbowEnabled; data.wind.playerMovement=b.windPlayerMovement
  data.celestial.events=b.celestialEvents; data.celestial.smoothSky=b.smoothSky; data.celestial.motionSmoothing=b.motionSmoothing
  data.time.source=b.timeSource; data.time.cycleMinutes=b.cycleMinutes
  data.seasons.daysPerSeason=b.daysPerSeason
  data.audio.indoors=b.indoorAudio; data.audio.thunder=b.thunderAudio; data.audio.wind=b.windAudio
  data.encounters.enabled=b.encountersEnabled; data.legendary.enabled=b.legendaryEnabled; data.followerChip.enabled=b.followerChipEnabled
  data.maxParticles=b.maxParticles

  local function choice(k) local okv,v=pcall(S.get,k); return okv and v or "config" end
  local function onoff(k,base) local v=choice(k); if v=="on" then return true elseif v=="off" then return false end return base end
  local ts=choice("transitionSpeed"); if ts=="quick" then data.transitionSeconds=1.2 elseif ts=="natural" then data.transitionSeconds=3.2 elseif ts=="slow" then data.transitionSeconds=6.0 end
  data.fronts.enabled=onoff("fronts",data.fronts.enabled)
  -- Named WEATHER choices are direct player authority. Keep this defensive
  -- clamp even if a host cannot persist the dependent FRONT=OFF menu write: a
  -- moving front must never replace a weather the player explicitly selected.
  if S.manualWeatherSelected and S.manualWeatherSelected() then data.fronts.enabled=false end
  local fs=choice("frontStrength"); local fv={gentle=.25,natural=.50,strong=.75,max=1.0}; if fv[fs] then data.fronts.drift=fv[fs] end
  data.mesoscale.enabled=onoff("mesoscale",data.mesoscale.enabled)
  local ms=choice("mesoscaleStrength"); local mv={subtle=.60,natural=1.0,strong=1.35}; if mv[ms] then data.mesoscale.strength=mv[ms] end
  -- WEATHER FRONTS=OFF is a true master spatial-weather fallback. Do not let
  -- LOCAL WEATHER FIELDS silently reintroduce partial-map rain/cloud bands.
  -- A later menu edit re-runs this overlay from the captured authored base, so
  -- turning fronts back ON restores the player's independent mesoscale choice.
  if data.fronts.enabled == false then data.mesoscale.enabled = false end
  do
    local pv=choice("puddles")
    if pv=="off" then data.visuals.puddles=false
    elseif pv=="low" or pv=="on" or pv=="high" then data.visuals.puddles=true end
  end
  data.visuals.glare=onoff("godRays",data.visuals.glare)
  data.npcLightning.enabled=onoff("npcLightning",data.npcLightning.enabled)
  local nc=tonumber(choice("npcStrikeChance")); if nc then data.npcLightning.chance=math.max(0,math.min(1,nc/100)) end
  local tf=choice("tornadoFrequency"); local tv={rare=180,normal=90,often=60,extreme=30}; if tv[tf] then data.tornado.everySeconds=tv[tf] end
  data.rainbow.enabled=onoff("rainbows",data.rainbow.enabled)
  data.wind.playerMovement=onoff("windWalk",data.wind.playerMovement)
  data.celestial.events=onoff("celestialEvents",data.celestial.events)
  data.celestial.smoothSky=onoff("smoothSky",data.celestial.smoothSky)
  data.celestial.motionSmoothing=onoff("celestialMotion",data.celestial.motionSmoothing)
  local src=choice("timeSource"); if src=="auto" or src=="system" or src=="cycle" or src=="off" then data.time.source=src end
  local dl=tonumber(choice("dayLength")); if dl then data.time.cycleMinutes=dl end
  local sl=tonumber(choice("seasonLength")); if sl then data.seasons.daysPerSeason=sl end
  local ia=choice("indoorAudio")
  -- 8.1.52: entering a building may attenuate outside weather by at most 60%.
  -- Keep the legacy `muted` save token for compatibility, but reinterpret it
  -- as the quietest legal indoor mix (40% of the outdoor distance-adjusted bed).
  -- WEATHER SFX=OFF remains the intentional way to silence Weather FX audio.
  local iv={muted=.40,quiet=.50,natural=.60,loud=.75}
  if iv[ia]~=nil then data.audio.indoors=iv[ia] end
  data.audio.thunder=onoff("thunderAudio",data.audio.thunder)
  data.audio.wind=onoff("windAudio",data.audio.wind)
  data.encounters.enabled=onoff("weatherEncounters",data.encounters.enabled)
  data.legendary.enabled=onoff("legendaryEvents",data.legendary.enabled)
  data.followerChip.enabled=onoff("followerChip",data.followerChip.enabled)
  local pc=choice("particleCap"); if pc=="tier" then data.maxParticles=nil else local pn=tonumber(pc); if pn then data.maxParticles=pn end end
end

function Config.get()
  if not Config.data then Config.load() end
  Config.applyPlayerSettings()
  return Config.data
end

-- ------- accessors the rest of the mod uses
--
-- Every one of these is total: it answers even with no config file, and
-- never returns nil for something a caller would then have to default.

Config._tuningCache = Config._tuningCache or {}
function Config.tuningFor(weatherId)
  local id = weatherId or ""
  local cached = Config._tuningCache[id]
  if cached then return cached end
  local t = Config.get().tuning
  local all = t.ALL
  local one = t[id]
  if not one then
    Config._tuningCache[id] = all
    return all
  end
  local out = {
    density = all.density * one.density,
    intensity = all.intensity * one.intensity,
    speed = all.speed * one.speed,
    duration = all.duration * one.duration,
    weight = (all.weight or 1) * (one.weight or 1),
  }
  Config._tuningCache[id] = out
  return out
end

-- Is this weather allowed to be rolled by AUTO at all?  `weathers` in
-- config.lua is a plain on/off list, checked before any weighting, so
-- switching one off is absolute rather than merely unlikely.
function Config.weatherEnabled(id)
  local v = Config.get().weathers[id or ""]
  if v == nil then return true end
  return v and true or false
end

-- The location override for a map, or nil.  `indoors` gates whether it
-- applies to an interior: a fog override on a town should not fog the
-- houses in it, but a mist override on the Pokémon Tower should.
function Config.locationFor(mapId, isIndoors)
  local entry = Config.get().locations[mapId or ""]
  if not entry then return nil end
  if isIndoors and not entry.indoors then return nil end
  return entry
end

function Config.visual(name)
  local v = Config.get().visuals[name]
  if v == nil then return true end
  return v and true or false
end

-- NOTE: the master on/off is Battle.effectsEnabled(), which folds in the
-- mod-manager row as well; this only answers "is this individual effect
-- switched on", and every caller is already behind that master gate.
-- The map ids this mod ships, gathered from the DEFAULTS rather than a
-- hand-kept list, so adding a row above cannot leave this behind. Used by
-- the map-id check to tell "the author shipped a Johto id and this is a
-- Kanto game" apart from "the player mistyped something".
function Config.bundledMapIds()
  local out = {}
  local d = DEFAULTS or {}
  local t = d.battle and d.battle.terrain
  if type(t) == "table" then
    for mapId in pairs(t) do out[mapId] = true end
  end
  if type(d.locations) == "table" then
    for mapId in pairs(d.locations) do out[mapId] = true end
  end
  return out
end

function Config.battleEffect(name)
  local b = Config.get().battle
  if not b.enabled then return false end
  local v = b.effects[name]
  if v == nil then return true end
  return v and true or false
end

return Config
