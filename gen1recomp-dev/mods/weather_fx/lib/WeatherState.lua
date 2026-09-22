-- THE WEATHER ITSELF: what it is, what it is becoming, and when it changes.
--
-- Everything the draw path and the battle layer read comes out of here --
-- as a number (State.channel) or as an id (State.id) -- and neither of
-- them ever asks what the weather is called in order to decide how to
-- behave.  That separation is what lets a transition be arithmetic and
-- lets a new weather type arrive without a line of renderer changing.
--
-- ---------------------------------------------------------------------
-- WHAT DECIDES THE WEATHER, highest priority first
-- ---------------------------------------------------------------------
--
--   1. config.force        the file pins one weather everywhere
--   2. config.locations    the file pins one on THIS map
--   3. a named OPTIONS weather pin (also disables fronts)
--   4. physical weather fronts when WEATHER FRONTS is ON
--   5. CYCLE/AUTO clock only when front authority does not own the sky
--
-- All four land on the same one-line answer -- an id -- which is then
-- eased into.  There is no second code path for a forced weather: forcing
-- is just a different way of choosing the id, so a forced storm fades in
-- like any other storm and every effect downstream is identical.
--
-- A LOCATION OVERRIDE PARKS THE CLOCK rather than consuming it.  Walk into
-- Lavender Town under a pinned fog and the AUTO timer stops where it is;
-- walk out and it resumes with the same time left on the same spell.
-- Otherwise a player who spent ten minutes in an overridden town would
-- come out into a sky that had silently rolled six times.
--
-- ---------------------------------------------------------------------
-- THE LADDER IS THE MODE
-- ---------------------------------------------------------------------
--
-- The engine's render_pipelines registry gives a pipeline an OFF/1/2/3
-- ladder, an OPTIONS row, persistence in save.options.pipelines and a
-- gate, all from the record's `levels` list.  So the ladder is not "how
-- strong is the weather", it is WHICH WEATHER -- level 1 is AUTO and
-- levels 2+ pin a type.  The player gets a weather picker on the main
-- OPTIONS menu without this mod drawing a single menu widget, and OFF is
-- genuinely off: at level 0 nothing here ticks, the present pass is not
-- eligible, and the engine skips allocating the present canvas entirely,
-- so the frame is byte-for-byte vanilla.
--
-- ---------------------------------------------------------------------
-- WHAT IS PERSISTED, AND WHERE
-- ---------------------------------------------------------------------
--
--   * the MODE (the ladder level) is a display setting and rides in
--     save.options.pipelines with TILT and ZOOM.  The engine writes it.
--   * the WEATHER (which spell is running, and how much is left) is world
--     state and rides in this mod's own save namespace (mod.save ->
--     save.modData.weather_fx).  Load a save from the middle of a storm
--     and it is still storming.
--
-- The eased channel values are deliberately NOT persisted: they are
-- recomputed from the weather in a couple of seconds, and a save carrying
-- them could restore a half-faded frame.  Loading snaps them instead.

local V = ...
local Harden = nil
pcall(function() Harden = V.require("Harden") end)
local mod = V.mod
local Types = V.require("Types")
local Settings = V.require("Settings")
local Config = V.require("Config")
local TOD = V.require("TimeOfDay")
local Seasons = V.require("Seasons")
local Fronts = V.require("Fronts")
local StormCells=nil
pcall(function() StormCells=V.require("StormCells") end)
local Psystorm = V.require("Psystorm")
local Synoptic = nil
pcall(function() Synoptic = V.require("SynopticTransition") end)
local Legendary = nil
local function getLegendary()
  if not Legendary then Legendary = V.require("Legendary") end
  return Legendary
end

local State = {}

-- ------- the ladder
--
-- Built from Types.PINNED so the two can never disagree: add an id there
-- and the row grows a rung.

-- OFF, then two automatic modes, then one rung per pinned weather.
--
-- CYCLE exists because AUTO is honest weather and honest weather is mostly
-- nothing happening: CLEAR carries the largest weight and spells run for
-- minutes, so a player can walk a long way between visible skies and
-- reasonably conclude the mod is broken.  CYCLE gives up realism for
-- variety -- it walks the catalogue in order, skipping clear skies, so
-- something is always falling and every weather gets its turn.
State.LEVEL_LABELS = { "OFF", "AUTO", "CYCLE" }
State.LEVEL_IDS = { false, "AUTO", "CYCLE" }   -- parallel: what each rung means
for _, id in ipairs(Types.PINNED) do
  State.LEVEL_LABELS[#State.LEVEL_LABELS + 1] = Types.get(id).label
  State.LEVEL_IDS[#State.LEVEL_IDS + 1] = id
end

-- ------- live state


-- Single entry for changing active weather id (avoids ad-hoc State.id writes).
function State.setWeather(id, reason)
  if type(id) ~= "string" or id == "" then return false end
  local Types = select(2, pcall(V.require, "Types"))
  if Types and Types.get then
    local def = Types.get(id)
    if def and def.id then id = def.id end
  end
  State.id = id
  if reason then State.pinnedBy = reason end
  return true
end

State.id = Types.DEFAULT      -- the weather actually running
State.left = 0                -- seconds until AUTO picks again
State.level = 0               -- last ladder level seen
State.ch = {}                 -- eased channel values: the draw path's input
State._spatialStrength = 1
State._spatialCloud = 1
State._cellWeather = nil
State._cellCloudWeather = nil
State._worldX, State._worldZ = 0, 0
local SPATIAL_AMPLITUDE={rain=true,splash=true,snow=true,hail=true,sand=true,ash=true,debris=true,psy=true,fog=true,veil=true,dim=true,cool=true,warm=true,glare=true,gust=true,strike=true}
State._indoorAccum = 0
State._wasIndoors = false
State._pausedWeatherId = nil
State.elapsed = 0             -- seconds of weather clock, for oscillators
State.dirty = false           -- channels hold values the OFF path must clear
State.pinnedBy = "none"       -- what chose the current weather, for the debug row
-- True on the first AUTO roll after the system is switched on.  AUTO is
-- honest weather, so CLEAR carries the biggest weight and spells run for
-- minutes -- which means the most likely first experience of switching the
-- mod on is a long dry sky, indistinguishable from a mod that is not
-- working.  The FIRST spell after switching on is therefore never CLEAR.
-- Every roll after that is unweighted by this.
State.fresh = false
State._bootSnapFog = true
State._controlRevisions = {}
State._controlResponse = 0
-- Where CYCLE has got to. Persisted with the weather transition so a reload
-- cannot repeat/skip catalogue entries in the middle of a player preview.
State.cycleIndex = 0
State.mode = "AUTO"           -- AUTO | CYCLE | FRONT | PIN, decided by authority
State.overrideMap = nil       -- the map an active location override belongs to
-- Soft handoff when regional front / AUTO target changes (map walks).
-- Forced menu pins and legend events still snap.
State.softFrom = nil
State.softTo = nil
State.softT = 0
State.softDur = 0
State.mapsTowardCommit = 0
-- A battle-created sky temporarily owns AUTO/CYCLE until its fresh dwell expires.
-- This is persisted so saving immediately after battle does not let a regional
-- front erase the weather on reload. Explicit player/config pins still outrank it.
State._battleCarry = false
State._weatherLifetimeScale = nil

-- Zero-allocation hot-path scratch. These are immutable control names and a
-- reused AUTO-family table; recreating them inside State.update() only fed GC.
local CONTROL_KEYS={"intensity","rainIntensity","snowIntensity","fogIntensity","sandIntensity","dustIntensity","windIntensity","stormDarkness"}
local FAMILY_SCALE={}

for _, key in ipairs(Types.channels) do State.ch[key] = 0 end

local function rand(a, b)
  if love and love.math and love.math.random then
    if a then return love.math.random(a, b) end
    return love.math.random()
  end
  if a then return math.random(a, b) end
  return math.random()
end

-- ------- region bias
--
-- Geography answers "where does it snow" with ALTITUDE AND WATER -- the
-- two things the map does say.  Seasons (lib/Seasons.lua) multiply the
-- same weights when SEASONS is ON.  A seasonal multiplier of 0 is a hard
-- gate (no snow in summer, no heatwave in winter) even on maps that
-- normally bias toward that weather; non-zero values only lean the dice.
--
-- These are the BUILT-IN defaults.  config.lua's `bias` table is merged
-- over them, so a player adds a region by adding a row rather than by
-- editing this file.

State.BIAS = {
  ROUTE_23        = { frozen = 6.0, fog = 1.6 },
  INDIGO_PLATEAU  = { frozen = 8.0, fog = 1.6 },
  ROUTE_22        = { frozen = 2.0 },
  ROUTE_19        = { fog = 2.6, wet = 1.4 },
  ROUTE_20        = { fog = 2.6, wet = 1.4 },
  ROUTE_21        = { fog = 2.4, wet = 1.4, sandy = 1.8 },
  CINNABAR_ISLAND = { fog = 2.0, wet = 1.3, sunny = 1.8, sandy = 3.5 },
  POKEMON_MANSION_1F = { sandy = 2.0, indoors = true },
  VERMILION_CITY  = { fog = 1.8 },
  LAVENDER_TOWN   = { fog = 3.2 },
  ROUTE_12        = { fog = 1.8, wet = 1.2 },
  VIRIDIAN_FOREST = { fog = 2.2, wet = 1.3 },
}

-- Multiplier for one weather type on one map.  Types are matched by the
-- capability tags they already carry for the battle layer (`wet`,
-- `frozen`, `sunny`, `sandy`) plus a `fog` tag inferred from the channel
-- table -- so a NEW TYPE IS BIASED CORRECTLY without being added to a
-- second list anywhere.
local function biasFor(mapId, def)
  local row = Config.get().bias[mapId or ""] or State.BIAS[mapId or ""]
  local mult = 1
  if row then
    if def.frozen and row.frozen then mult = mult * row.frozen end
    if def.wet and row.wet then mult = mult * row.wet end
    if def.sunny and row.sunny then mult = mult * row.sunny end
    if def.sandy and row.sandy then mult = mult * row.sandy end
    if Types.channel(def, "fog") > 0 and row.fog then mult = mult * row.fog end
  end
  -- Snow, ice and grit anywhere else in Kanto are novelties rather than
  -- forecasts -- but "novelty" tuned for plausibility made them
  -- effectively invisible, so the RARE WX setting scales the suppression
  -- rather than the weather.  The geography still shows through at every
  -- setting except OFTEN: a map that argues for snow keeps its bonus, and
  -- this only decides how hard everywhere else is pushed down.
  local exotic = Settings.exoticScale()
  -- RARE WEATHER=OFF is a hard catalogue gate, exactly as the menu says.
  -- The old path only applied the zero through the out-of-place suppression
  -- branch, so a cold/dry-region-biased map could still roll snow, hail,
  -- sleet, sandstorm or ashfall while the player had explicitly turned rare
  -- weather OFF. Geography may BOOST these families at RARE/NORMAL/OFTEN,
  -- but it must never override an explicit OFF.
  if exotic <= 0 and (def.frozen or def.sandy) then return 0 end
  local function suppress(base)
    -- 1 is the realistic original; higher values relax toward no suppression.
    local relaxed = base + (1 - base) * math.min(1, (exotic - 1) / 6)
    return math.min(1, relaxed)
  end
  if def.frozen and not (row and row.frozen) then mult = mult * suppress(0.2) end
  if def.sandy and not (row and row.sandy) then mult = mult * suppress(0.25) end
  return mult
end

-- ------- the AUTO picker

local function weightOf(def, mapId, previousId, daylight)
  if def.natural == false then return 0 end       -- primal weathers are never rolled
  if not Config.weatherEnabled(def.id) then return 0 end
  -- Hard ban: sun / heat never rolls at night (real night or TIME → NITE).
  -- nightWeight=0 was not enough when TIME OF DAY was off, or when a day
  -- spell was still ticking after sundown.
  if def.sunny then
    local night = false
    if TOD.isNight and TOD.isNight() then night = true
    elseif (tonumber(daylight) or 1) < 0.18 then night = true end
    if night then return 0 end
  end
  local w = (def.weight or 1) * (Config.tuningFor(def.id).weight or 1)
  if def.id == previousId then w = w * 0.15 end   -- rarely repeat a spell
  if def.follows and def.follows[previousId or ""] then w = w * 2.8 end
  if Settings.is("daytime", "on") then
    -- daylight is 1 at noon and ~0 at midnight; blend each type's two
    -- weights along it rather than switching at a threshold, so an evening
    -- is genuinely halfway and not "day until it is suddenly night"
    local day = def.dayWeight or 1
    local night = def.nightWeight or 1
    w = w * (night + (day - night) * daylight)
  end
  -- Seasonal multiplier (1 when SEASONS is OFF).  Applied after geography
  -- so a 0 (summer snow, winter heatwave) kills the roll even on a map
  -- that biases hard toward that weather; non-zero values only lean it.
  w = w * Seasons.multiplier(def)
  return w * biasFor(mapId, def)
end

-- Total-weight roulette over the whole catalogue, so every type stays
-- reachable however the biases stack; a table that somehow sums to zero
-- falls back to CLEAR rather than to nil.
-- `exclude` drops one id from the roll entirely, used for the first spell
-- after switching on.
-- Fronts rolls each region's weather with the SAME weighting the global
-- AUTO uses, so the geography that favours snow on a cold route still
-- does.  Passed as a function rather than required back, because Fronts is
-- required from here and the reverse would be a cycle.
-- `exclude` is passed through: the opening roll uses it to keep a fresh
-- world from starting every front on CLEAR, and dropping it silently was
-- why it did exactly that.

-- True when the sky must not stay sunny (night / NITE).
local function sunForbidden()
  if TOD.isNight and TOD.isNight() then return true end
  if TOD.daylight and (tonumber(TOD.daylight()) or 1) < 0.18 then return true end
  return false
end

-- HOISTED above its first caller. `local function` is not visible above
-- its own declaration, so this resolved to a nil global and threw inside
-- the weather-advance path -- which decides how long a weather lasts.
local function dwellFor(def)
  local lo = (def.minMin or 4) * 60
  local hi = (def.maxMin or 10) * 60
  if hi < lo then hi = lo end
  local seconds = lo + rand() * (hi - lo)
  local tuning = Config.tuningFor(def.id)
  return math.max(2, seconds * Settings.speedScale() * (tuning.duration or 1))
end

local function breakSunnyIfNight(mapId)
  if not sunForbidden() then return nil end
  local def = Types.get(State.id)
  if not (def and def.sunny) then return nil end
  -- Return a natural replacement target so the normal synoptic handoff owns
  -- the visual transition. Forced/menu weather is resolved above AUTO and does
  -- not call this helper. CLEAR is the safe fallback.
  local nextId = State.pick(mapId or State.lastMapId, State.id)
  if not nextId or Types.get(nextId).sunny then nextId = Types.DEFAULT end
  return nextId
end

-- Fronts owns weather away from the player, but the same night-sun rule must
-- apply to those regions too (including Pokegear forecasts). The callback avoids
-- a Fronts -> TimeOfDay dependency cycle.
Fronts.sunForbidden = sunForbidden

function State.resetDwell(id)
  local def=Types.get(id or State.id)
  State.left=dwellFor(def)
  return State.left
end

function State.adoptWeather(id,reason)
  local def=Types.get(id)
  if not def then return false end
  State.id=def.id
  State.pinnedBy=reason or State.pinnedBy
  State._battleCarry = reason == "battle-end"
  if State._battleCarry and State._wasIndoors then
    -- A battle fought indoors still carries its final sky outside. Replace the
    -- pre-battle paused weather and start the 5-minute indoor-change window
    -- from the battle end, not from when the player entered the building.
    State._pausedWeatherId = def.id
    State._indoorAccum = 0
  end
  State.softFrom,State.softTo=nil,nil
  State.softT,State.softDur=0,0
  State.mapsTowardCommit=0
  if Synoptic and Synoptic.reset then Synoptic.reset() end
  State.resetDwell(def.id)
  State.persist()
  return true
end

Fronts.pick = function(mapId, exclude) return State.pick(mapId, exclude) end

function State.pick(mapId, exclude)
  local daylight = TOD.daylight()
  local total, weights = 0, {}
  for i, def in ipairs(Types.list) do
    local w = weightOf(def, mapId, State.id, daylight)
    if w ~= w or w < 0 then w = 0 end             -- NaN and negatives out
    if exclude and def.id == exclude then w = 0 end
    weights[i] = w
    total = total + w
  end
  if total <= 0 then return Types.DEFAULT end
  local roll = rand() * total
  for i, w in ipairs(weights) do
    roll = roll - w
    if roll <= 0 then return Types.list[i].id end
  end
  return Types.list[#Types.list].id
end

-- The rotation CYCLE walks: every natural weather that actually shows
-- something, in catalogue order, minus anything switched off in the
-- config.  Rebuilt each time it is needed rather than cached, because the
-- config can change under a hot reload and the list is nineteen entries.
function State.cycleList()
  local out = {}
  for _, def in ipairs(Types.list) do
    if def.natural ~= false
        and def.id ~= Types.DEFAULT
        and Config.weatherEnabled(def.id) then
      out[#out + 1] = def.id
    end
  end
  return out
end

local function nextInCycle()
  local list = State.cycleList()
  if #list == 0 then return Types.DEFAULT end
  -- Skip sunny entries at night so CYCLE cannot land on SUNNY/HEATWAVE.
  for _ = 1, #list do
    State.cycleIndex = (State.cycleIndex % #list) + 1
    local id = list[State.cycleIndex]
    local def = Types.get(id)
    if not (def and def.sunny and sunForbidden and sunForbidden()) then
      return id
    end
  end
  return Types.DEFAULT
end


-- ------- setting the weather

function State.set(id, snap)
  State.id = Types.get(id).id
  if snap then State.settle() end
  State.persist()
end

-- Slam every channel to the current weather's value.  Used on load and on
-- hot reload, never during play.

-- 2D fog/veil overlay is only for true fog-family weather.
-- Other types may use light atmospheric channels in Types, but those must
-- not paint the screen-space fog bank (boot residual / clear-sky haze).
local FOG_WEATHER = {
  FOG = true, MIST = true, HAUNTED_MIST = true, SMOG = true,
}
function State.isFogWeather(id)
  id = tostring(id or State.id or ""):upper()
  return FOG_WEATHER[id] and true or false
end

function State.settle()
  local def = Types.get(State.id)
  for _, key in ipairs(Types.channels) do
    State.ch[key] = Types.channel(def, key)
  end
  -- Never keep fog/veil unless this weather is fog-family (fixes boot haze).
  if not State.isFogWeather(def.id) then
    State.ch.fog = 0
    State.ch.veil = 0
    State.ch.fogSpeed = 0
  end
  if def.id == "CLEAR" then
    for _, key in ipairs(Types.channels) do
      State.ch[key] = 0
    end
  end
  State.dirty = true
end

function State.clearChannels()
  for _, key in ipairs(Types.channels) do
    State.ch[key] = 0
  end
  State.dirty = true
end

function State.markGentleIntro(seconds)
  State._gentleIntro = math.max(State._gentleIntro or 0, tonumber(seconds) or 6.0)
end

function State.currentRaw() return Types.get(State.id) end
function State.current()
  if State.pinnedBy=="front" and (tonumber(State._spatialStrength) or 1) <= 0.012 then
    return Types.get(Types.DEFAULT)
  end
  return Types.get(State.id)
end

function State.channel(key)
  local v = State.ch[key]
  if type(v) ~= "number" or v ~= v then return 0 end
  return v
end

-- Read-only live synoptic handoff state for the climate and strict-3D bridges.
-- The returned table is module-owned and reused; callers must not mutate it.
function State.synoptic()
  if Synoptic and Synoptic.peek then return Synoptic.peek() end
  return nil
end

-- ------- the tick

-- Seconds for a channel to cover most of the distance to its target.  Fog
-- rolls in slowly, rain starts and stops briskly, and the light changes
-- fastest of all because the sky darkening ahead of a storm is the cue
-- that sells it.  Scaled by config.transitionSeconds.
local TAU = {
  rain = 2.8, rainSpeed = 2.2, rainLen = 1.6, rainAngle = 1.8, splash = 1.4,
  snow = 3.4, snowSpeed = 2.6, snowDrift = 2.8,
  hail = 2.4, sand = 3.0, debris = 2.8, ash = 3.6,
  fog = 3.8, fogSpeed = 3.2, veil = 3.2,
  dim = 2.0, cool = 2.2, warm = 2.2, glare = 1.8,
  gust = 2.4, strike = 1.6,
}
local TAU_CLEAR_OUT = {
  fog = 0.12, fogSpeed = 0.12, veil = 0.10, dim = 0.35,
}
local TAU_DEFAULT = 1.0

local function ease(current, target, dt, tau)
  if current == target then return target end
  -- Exponential approach: frame-rate independent, and it cannot overshoot
  -- however large dt is, which a linear step toward a target can.
  local k = 1 - math.exp(-dt / tau)
  local next_ = current + (target - current) * k
  if math.abs(target - next_) < 0.0005 then return target end
  return next_
end

-- Channels that are AMOUNTS (and so scale with intensity/density) rather
-- than rates, angles or counts (which must not).
local AMOUNT = {
  rain = true, snow = true, hail = true, sand = true, debris = true,
  fog = true, veil = true, dim = true, splash = true, warm = true,
  cool = true, glare = true,
}

-- Resolve the weather this frame should be heading toward, and say who
-- decided.  Returns nil to mean "leave it alone" (AUTO between rolls).
local function resolveTarget(mapId, indoors)
  local cfg = Config.get()

  -- The diagnostic switch outranks everything, including `force`: its job
  -- is to answer "is this mod working", and an answer that could itself be
  -- overridden would not be an answer.
  if Settings.debugRain(Config) then
    State._battleCarry = false
    State.pinnedBy = "debug"
    State.overrideMap = nil
    return "RAIN_HEAVY", true
  end

  if cfg.force then
    State._battleCarry = false
    State.pinnedBy = "config"
    State.overrideMap = nil
    return cfg.force, true
  end

  -- The WEATHER row (mod menu): same pin as OPTIONS ladder / config.force,
  -- from the mod manager instead of a text file.  Below `force` rather
  -- than above it because the file is the deliberate per-playthrough
  -- setting and the row is the convenient one -- and a player who set both
  -- is better served by the one that took more effort to express.
  local always = Settings.alwaysWeather()
  if always then
    State._battleCarry = false
    State.pinnedBy = "always"
    State.overrideMap = nil
    return always, true
  end

  -- WHO OUTRANKS WHOM, and why this order.
  --
  -- The ladder rung is read FIRST when it names a weather, because that
  -- rung is the player standing in the OPTIONS menu choosing a sky. A
  -- location override is a default for the unattended case -- it says
  -- "Lavender Town is usually foggy", not "Lavender Town is always foggy
  -- no matter what you asked for".
  --
  -- Reported from play: PRIML pinned on the row, and the sky (and so the
  -- battle) was the map's weather instead. Reading the override first made
  -- every certainty override a silent veto on the menu, and the player has
  -- no way to see why the row they just moved did nothing.
  --
  -- AUTO is allowed to use geographic/location authority. CYCLE is not:
  -- CYCLE is a single world spell clock and must survive map boundaries until
  -- its own timer expires. Letting a per-map override run first made walking
  -- through a door/route boundary replace the active cycle weather immediately.
  local rung = State.LEVEL_IDS[State.level + 1]
  if rung ~= nil and rung ~= false and rung ~= "AUTO" and rung ~= "CYCLE" then
    State._battleCarry = false
    State.overrideMap = nil
    State.mode = "PIN"
    State.pinnedBy = "menu"
    return rung, false
  end

  -- A move-set battle sky intentionally carries back into the overworld.
  -- AUTO/CYCLE resume only after that new spell has lived for its normal dwell;
  -- only explicit player/config pins above may cancel it.
  if State._battleCarry and (State.left or 0) > 0 then
    State.mode = (rung == "CYCLE") and "CYCLE" or "AUTO"
    State.pinnedBy = "battle-end"
    State.overrideMap = nil
    return nil, false
  end

  local frontsOn = cfg.fronts and cfg.fronts.enabled ~= false

  -- CYCLE is a fallback automatic authority, never a competitor to physical
  -- weather fronts. With fronts OFF it owns one world-persistent spell timer
  -- across map boundaries. With fronts ON the cycle clock is suspended exactly
  -- where it stands and front/weather-cell authority continues below. Turning
  -- fronts OFF later resumes that same cycle rather than having secretly rolled
  -- several unseen weather types underneath the fronts.
  if rung == "CYCLE" and not frontsOn then
    State.mode = "CYCLE"
    State.pinnedBy = "cycle"
    State.overrideMap = nil
    return nil, false
  elseif rung == "CYCLE" and frontsOn then
    State.mode = "FRONT"
    State.pinnedBy = "front"
    State.overrideMap = nil
  end

  local override = Config.locationFor(mapId, indoors)
  if override then
    if override.chance >= 1 then
      State.pinnedBy = "location"
      State.overrideMap = mapId
      return override.weather, true
    end
    -- A chance override is rolled ONCE per arrival, not per frame: the
    -- map is remembered, so walking in and out re-rolls but standing
    -- still does not flicker.
    if State.overrideMap ~= mapId then
      State.overrideMap = mapId
      if rand() < override.chance then
        State.pinnedBy = "location"
        return override.weather, true
      end
      State.pinnedBy = "auto"
    elseif State.pinnedBy == "location" then
      return override.weather, true
    end
  else
    State.overrideMap = nil
  end

  -- THE PSYSTORM, which is not weather but a reaction to what is standing
  -- here.  Above the front -- when Mewtwo's cave is storming and the
  -- region's front says fog, the cave wins -- and below anything the
  -- player or the config asked for explicitly.  The front is only
  -- overruled, never overwritten, so it resumes on the way out.
  local psy = Psystorm.weatherFor(mapId)
  if psy then
    State.pinnedBy = "psystorm"
    return psy, true
  end

  -- A BIRD, if one has stirred here.  Below the psystorm, which is a place
  -- reacting to what is standing in it, and above the region's front,
  -- which is only the ordinary sky.  Like the psystorm it overrules the
  -- front rather than overwriting it, so the front resumes on the way out.
  local bird = getLegendary().update(mapId, indoors)
  if bird then
    State.pinnedBy = "legend"
    return bird, true
  end

  -- THE FRONT OVER THIS MAP, if there is one.
  --
  -- Below everything the player or the config asked for explicitly --
  -- force, a location override, a pinned rung -- and above the global AUTO
  -- clock, which is what it replaces.  A map in no region (every interior,
  -- and anywhere the region table does not reach) falls through to AUTO
  -- exactly as before, so nothing is lost where fronts do not apply.
  --
  -- `parksClock` is true: the global clock must not keep rolling
  -- underneath, or leaving a front's region would drop the player into a
  -- stale global weather that had been advancing unseen.
  State.mode = (rung == "CYCLE" and frontsOn) and "FRONT" or "AUTO"
  local front = Fronts.weatherFor(mapId)
  if front then
    State.pinnedBy = "front"
    -- The fine physical cell is allowed to outlive/cross the coarse regional
    -- source that spawned it. At the player's exact world position it owns the
    -- discrete weather id; the channel amplitudes below still fade continuously
    -- through the cell edge.
    if State._cellWeather and (tonumber(State._spatialStrength) or 0)>.012 then
      return State._cellWeather, true
    end
    if State._cellCloudWeather and (tonumber(State._spatialCloud) or 0)>.012 then
      -- The cloud shield owns presentation before its precipitation core.
      -- State.current() still reports CLEAR while spatialStrength is ~0, so
      -- encounters/audio/gameplay do not pretend it is already raining.
      return State._cellCloudWeather,true
    end
    return front, true
  elseif State._cellWeather and (tonumber(State._spatialStrength) or 0)>.012 then
    State.pinnedBy="front"
    return State._cellWeather,true
  elseif State._cellCloudWeather and (tonumber(State._spatialCloud) or 0)>.012 then
    State.pinnedBy="front"
    return State._cellCloudWeather,true
  end

  if rung == "CYCLE" and frontsOn then
    -- An unmapped/interior region cannot grant CYCLE permission to advance.
    -- Hold the last world weather while fronts continue moving elsewhere.
    State.mode = "FRONT"
    State.pinnedBy = "front"
    return State.id, true
  end

  State.pinnedBy = "auto"
  return nil, false
end

-- The whole per-frame job.  `level` is the ladder rung the engine hands
-- the pipeline; everything below keys off it, including doing nothing at 0.
function State.update(dt, level, mapId, indoors, worldX, worldZ)
  dt = tonumber(dt) or 0
  if dt < 0 or dt ~= dt then dt = 0 end
  if dt > 0.25 then dt = 0.25 end   -- a load hitch is not eight seconds of weather
  if type(State.ch) ~= "table" then State.ch = {} end
  if type(State.id) ~= "string" or State.id == "" then
    State.id = (Types and Types.DEFAULT) or "CLEAR"
  end

  -- The engine OPTIONS ladder and the Weather FX Mod Manager row are two
  -- views of one weather authority. Accept the engine rung FIRST so a newer
  -- OPTIONS edit can replace a stale Mod Manager OFF/named value in this same
  -- tick. (8.1.83 did the OFF test first, which made the OPTIONS WEATHER row
  -- appear inert after the other menu had selected OFF.)
  pcall(function()
    if Settings and Settings.syncWeatherFromLadder then
      Settings.syncWeatherFromLadder(level)
    end
  end)

  -- WEATHER=OFF is a true hard disable, not an alias for AUTO. By this point
  -- both menu surfaces have been reconciled, so this tests the newest player
  -- choice rather than a stale duplicate.
  if Settings.weatherDisabled and Settings.weatherDisabled() then level = 0 end
  local wasOff = (State.level or 0) <= 0
  State.level = level or 0
  if wasOff and State.level > 0 then
    State.fresh = true
    State._battleCarry = false
    State.left = 0
    State.softFrom, State.softTo = nil, nil
    State.softT, State.softDur = 0, 0
    State.mapsTowardCommit = 0
    if Synoptic and Synoptic.reset then Synoptic.reset() end
  end

  -- NOTE: debug rain does NOT fake a level here, and 2.0.1's attempt to
  -- was a real bug.  The engine gates every pipeline stage on
  -- Pipelines.level() before it asks this mod anything, so an internal
  -- override pinned the weather and eased every channel while drawing
  -- nothing at all.  lib/Ladder.lua moves the engine's own number instead.

  if State.level <= 0 then
    -- OFF: no clock, no easing, no draw.  Channels are zeroed ONCE on the
    -- way out -- `dirty` is what makes it once rather than every frame --
    -- so switching back on starts from a clear sky rather than from
    -- wherever the last session's storm had got to, and a session spent
    -- at OFF costs one comparison per frame.
    if State.dirty then
      for _, key in ipairs(Types.channels) do State.ch[key] = 0 end
      State.dirty = false
    end
    return
  end

  State.elapsed = State.elapsed + dt
  State._worldX,State._worldZ=tonumber(worldX) or State._worldX or 0,tonumber(worldZ) or State._worldZ or 0

  -- WEATHER DURATION is a lifetime-only testing control. Apply edits to the
  -- already-running spell immediately by rescaling its remaining dwell time.
  -- Do not touch dt, elapsed, channel easing, particle motion or softT/softDur:
  -- those are visual/simulation clocks and must keep their authored speeds.
  local lifetimeScale = Settings.speedScale()
  local priorLifetimeScale = tonumber(State._weatherLifetimeScale)
  if priorLifetimeScale and priorLifetimeScale > 0
      and math.abs(lifetimeScale - priorLifetimeScale) > 0.000001 then
    local ratio = lifetimeScale / priorLifetimeScale
    if tonumber(State.left) and State.left > 0 then State.left = State.left * ratio end
    if Fronts.rescaleRemaining then Fronts.rescaleRemaining(priorLifetimeScale, lifetimeScale) end
    if StormCells and StormCells.rescaleRemaining then StormCells.rescaleRemaining(priorLifetimeScale,lifetimeScale) end
    State.persist()
  end
  State._weatherLifetimeScale = lifetimeScale

  -- Boot / load: kill any residual 2D fog bank unless weather is fog-family.
  if State._bootSnapFog then
    State._bootSnapFog = false
    if not State.isFogWeather(State.id) then
      State.ch.fog = 0
      State.ch.veil = 0
      State.ch.fogSpeed = 0
    end
  end

  -- ---- Indoor / cave weather gate (overworld) ----
  -- Falling/visible weather is hidden indoors, but the OUTDOOR world keeps
  -- evolving. In particular CYCLE owns one persistent world spell timer across
  -- buildings and map transitions; entering a building must never reroll it.
  local INDOOR_CHANGE_SEC = 5 * 60
  -- DEBUG RAIN is the deliberate exception: its documented purpose is to
  -- prove the precipitation pipeline works everywhere, including indoors.
  -- Scene.drawScale already allows it there; do not zero the source channels
  -- here or the draw path would be enabled with nothing left to draw.
  if indoors and not Settings.debugRain(Config) then
    if not State._wasIndoors then
      State._wasIndoors = true
      State._indoorAccum = 0
      State._pausedWeatherId = State.id
    end
    State._indoorAccum = (State._indoorAccum or 0) + (tonumber(dt) or 0)
    -- No falling/residual weather indoors. Keep only the non-spatial storm
    -- lighting channels so INDOORS=TINT can darken/flash an interior while
    -- Scene.drawScale supplies precipitation=false. In particular `strike` is
    -- kept as a scheduler rate; the bolt itself is suppressed by Draw indoors.
    local indoorLight = { dim = true, cool = true, warm = true, strike = true }
    for _, key in ipairs(Types.channels) do
      if not indoorLight[key] then State.ch[key] = 0 end
    end
    State.dirty = true
    -- Still sample map id so exit transition is detected.
    State.lastMapId = mapId
    -- Fronts keep regional state but do not drive visible weather here.
    Fronts.update(dt, Settings.speedScale())
    local frontsOn=(Config.get().fronts and Config.get().fronts.enabled~=false)
    if StormCells and StormCells.setEnabled then StormCells.setEnabled(frontsOn) end
    if frontsOn and StormCells and StormCells.update then
      local ambient=State._cellAmbient or select(1,Fronts.weatherFor(State._lastOutdoorMapId or mapId)) or Types.DEFAULT
      StormCells.update(dt,State._lastOutdoorMapId or mapId,ambient,State._worldX,State._worldZ,Settings.speedScale())
    end
    local L = getLegendary()
    L.speedScale = Settings.speedScale()
    L.tick(dt)

    -- CYCLE weather belongs to the world, not the current map. Keep its clock
    -- running while the player is indoors. If a transition was already in
    -- progress, advance/commit it invisibly; otherwise advance only when the
    -- dwell timer actually expires. The exit path below therefore resumes the
    -- CURRENT world spell instead of restoring an entry snapshot or rerolling.
    local indoorRung = State.LEVEL_IDS[(State.level or 0) + 1]
    if indoorRung == "CYCLE" and not frontsOn and not State._battleCarry then
      State.mode,State.pinnedBy="CYCLE","cycle"
      if State.softTo then
        State.softT=(State.softT or 0)+dt
        local dur=State.softDur or 32
        if State.softT>=dur then
          State.id=State.softTo
          State.softFrom,State.softTo=nil,nil
          State.softT,State.softDur=0,0
          State.mapsTowardCommit=0
          if Synoptic and Synoptic.reset then Synoptic.reset() end
          State.left=dwellFor(Types.get(State.id))
          State.persist()
        end
      else
        State.left=(State.left or 0)-dt
        if State.left<=0 then
          local nextId=nextInCycle()
          State.id=Types.get(nextId or State.id).id
          State.left=dwellFor(Types.get(State.id))
          State.fresh=false
          State.persist()
        end
      end
    end
    return
  elseif State._wasIndoors then
    local stayed = State._indoorAccum or 0
    local paused = State._pausedWeatherId
    State._wasIndoors = false
    State._indoorAccum = 0
    State._pausedWeatherId = nil
    -- Channels already 0 from indoor gate; ease back up (no settle jump).
    local exitRung=State.LEVEL_IDS[(State.level or 0)+1]
    local exitFrontsOn=(Config.get().fronts and Config.get().fronts.enabled~=false)
    if exitRung=="CYCLE" and not exitFrontsOn then
      -- The cycle clock continued indoors because fronts were OFF. Never restore
      -- the entry snapshot and never reroll merely because a building is a map.
      State.mode,State.pinnedBy="CYCLE","cycle"
      State.overrideMap=nil
      State.persist()
    elseif exitRung=="CYCLE" and exitFrontsOn then
      -- Front authority owns the outdoor world. CYCLE remained frozen indoors;
      -- the next resolve immediately picks up the same persistent moving front.
      State.mode,State.pinnedBy="FRONT","front"
      State.overrideMap=nil
    elseif stayed >= INDOOR_CHANGE_SEC then
      -- AUTO keeps its older long-indoor refresh behavior. Regional fronts are
      -- the authority outdoors, so do not briefly install an unrelated global
      -- roll before correcting toward the local front.
      local frontId = Fronts.weatherFor(mapId)
      local nxt = frontId or State.pick(mapId, paused)
      if not nxt then nxt = paused or Types.DEFAULT end
      State.id = Types.get(nxt).id
      State.pinnedBy = frontId and "front" or "auto"
      State.softFrom, State.softTo = nil, nil
      State.softT, State.softDur = 0, 0
      State.mapsTowardCommit = 0
      State.left = dwellFor(Types.get(State.id))
      if Synoptic and Synoptic.reset then Synoptic.reset() end
      State.persist()
    else
      if paused then
        State.id = paused
        State.softFrom, State.softTo = nil, nil
        State.softT, State.softDur = 0, 0
        State.persist()
      end
    end
    State.markGentleIntro(5.5)
  end

  -- Every region ticks, not just the one underfoot: a front the player
  -- walked out of has to keep running, and the Pokegear card shows skies
  -- over places they are not standing in.
  Fronts.update(dt, Settings.speedScale())
  if not indoors then State._lastOutdoorMapId=mapId end
  local frontsOn=(Config.get().fronts and Config.get().fronts.enabled~=false)
  if StormCells and StormCells.setEnabled then StormCells.setEnabled(frontsOn) end
  if frontsOn and StormCells and StormCells.update then
    local ambient=select(1,Fronts.weatherFor(mapId)) or Types.DEFAULT
    State._cellAmbient=ambient
    local q=StormCells.update(dt,mapId,ambient,State._worldX,State._worldZ,Settings.speedScale())
    State._cellWeather=q and q.weather or nil
    State._cellCloudWeather=(q and (tonumber(q.cloud) or 0)>.012) and (q.cloudWeather or q.weather) or nil
    if State._cellWeather and (tonumber(q.strength) or 0)>.001 then
      -- A cell survives the regional roll that created it; this is what lets a
      -- storm physically finish crossing a map instead of vanishing when the
      -- coarse forecast clock advances underneath it.
      State._spatialStrength=tonumber(q.strength) or 0
      State._spatialCloud=tonumber(q.cloud) or 0
    elseif State._cellCloudWeather then
      -- Cloud/anvil ownership begins BEFORE the rain/snow core. Keep the
      -- discrete storm family alive for the 3D cloud renderer but hold all
      -- spatial amplitude channels at zero until the precipitation footprint
      -- physically reaches the player. This closes the old 150px handoff gap
      -- where a distant front vanished just before local weather could start.
      State._spatialStrength=tonumber(q and q.strength) or 0
      State._spatialCloud=tonumber(q and q.cloud) or 0
    elseif StormCells.isSpatialWeather and StormCells.isSpatialWeather(ambient) then
      State._spatialStrength=tonumber(q and q.strength) or 0
      State._spatialCloud=tonumber(q and q.cloud) or 0
    else
      State._spatialStrength,State._spatialCloud=1,tonumber(q and q.cloud) or 1
    end
  else
    -- Full-map fallback: no hidden cell id/edge is allowed to survive OFF.
    State._cellWeather,State._cellCloudWeather,State._cellAmbient=nil,nil,nil
    State._spatialStrength,State._spatialCloud=1,1
  end
  -- Ticked here beside the front clock because this is where dt exists;
  -- resolveTarget below has no dt, and a tick placed there silently never
  -- expired anything.
  -- the scale is read at ARM time inside Legendary; handing it over here
  -- keeps Legendary free of a Settings dependency
  local L = getLegendary()
  L.speedScale = Settings.speedScale()
  L.tick(dt)
  -- TOD.update is NOT called here.  The clock belongs to the TIME
  -- pipeline, whose update runs whatever the weather ladder is doing --
  -- otherwise turning weather off would stop time, which is exactly the
  -- bug that welding the two together caused in the first place.  Calling
  -- it in both places would also double the cycle rate.

  local mapChanged = (mapId ~= nil and State.lastMapId ~= nil and mapId ~= State.lastMapId)
  if mapChanged and State.softTo then
    State.mapsTowardCommit = (State.mapsTowardCommit or 0) + 1
  end
  State.lastMapId = mapId
  local target, parksClock = resolveTarget(mapId, indoors)
  if not target and not State.softTo and State.mode == "AUTO" and State.pinnedBy == "auto" then
    target = breakSunnyIfNight(mapId)
  end

  -- First outdoor moment this session: weather may begin.
  -- Indoor/cave loads keep channels at 0 until this runs.
  if (State._needOutdoorStart or State._sessionStart) and not indoors then
    State._needOutdoorStart = false
    local always = Settings.alwaysWeather and Settings.alwaysWeather()
    local cfgForce = Config.get() and Config.get().force
    -- Gradual start: set weather id, keep channels at 0, ease ramps intensity.
    -- Never settle() here — that caused the visible jump on load/outdoor entry.
    if always or cfgForce then
      local id = cfgForce or always
      State.id = Types.get(id).id
      State.pinnedBy = cfgForce and "force" or "always"
      State.softFrom, State.softTo = nil, nil
      State.softT, State.softDur = 0, 0
      State._sessionStart = false
      State.clearChannels()
      State.markGentleIntro(7.0)
      State.persist()
    elseif State._sessionStart then
      State._sessionStart = false
      local rung = State.LEVEL_IDS[(State.level or 0) + 1]
      if rung == "AUTO" or rung == nil or rung == false then
        local nextId = State.pick(mapId, nil)
        if nextId then
          State.id = nextId
          State.left = dwellFor(Types.get(nextId))
          State.softFrom, State.softTo = nil, nil
          State.softT, State.softDur = 0, 0
          State.pinnedBy = "auto"
          State.clearChannels()
          State.markGentleIntro(7.0)
          State.persist()
        end
      elseif type(rung) == "string" and rung ~= "CYCLE" then
        State.id = Types.get(rung).id
        State.pinnedBy = "menu"
        State.softFrom, State.softTo = nil, nil
        State.clearChannels()
        State.markGentleIntro(7.0)
        State.persist()
      else
        State.clearChannels()
        State.markGentleIntro(7.0)
      end
    else
      State.clearChannels()
      State.markGentleIntro(6.0)
    end
  end


  local function hardSetWeather(id)
    if not id then return end
    State.id = id
    State.softFrom, State.softTo = nil, nil
    State.softT, State.softDur = 0, 0
    State.mapsTowardCommit = 0
    if Synoptic and Synoptic.reset then Synoptic.reset() end
    State.persist()
  end

  local function beginSoftWeather(toId)
    if not toId or toId == State.id then
      if toId == State.id then
        State.softFrom, State.softTo = nil, nil
        State.softT, State.softDur = 0, 0
        State.mapsTowardCommit = 0
      end
      return
    end
    if State.softTo == toId then return end
    State.softFrom = State.id
    State.softTo = toId
    State.softT = 0
    State.mapsTowardCommit = 0
    local base = tonumber(Config.get().transitionSeconds) or 3.2
    -- AUTO/front changes use a synoptic plan rather than a symmetric renderer
    -- crossfade. Clouds/pressure/wind can lead precipitation, lightning can
    -- arrive late, and clearing skies can keep a broken deck after rain ends.
    -- Manual/config pins never come through here, preserving their immediate
    -- selected-weather sky response.
    if Synoptic and Synoptic.begin then
      local ok,dur=pcall(Synoptic.begin,State.softFrom,State.softTo,base)
      if ok and tonumber(dur) then State.softDur=tonumber(dur) else State.softDur=math.max(32.0,base*10.0) end
    else
      State.softDur = math.max(32.0, base * 10.0)
    end
  end

  -- Menu pin / force / legend / psystorm: snap. Fronts & soft location: blend.
  local HARD_PIN = {
    config = true, force = true, always = true, menu = true, debug = true,
    pin = true, legend = true, psystorm = true,
  }

  if target then
    if HARD_PIN[State.pinnedBy or ""] then
      if State.id ~= target then
        hardSetWeather(target)
        -- A manual weather selection is a player control, not an AUTO front.
        -- Keep the renderer smooth, but make precipitation/lightning reach a
        -- visible target immediately instead of spending 5+ seconds under the
        -- old "gentle intro" multiplier. Natural AUTO/Synoptic changes retain
        -- their long meteorological staging below.
        State._gentleIntro = 0
        State._manualWeatherResponse = 1.0
      end
    else
      beginSoftWeather(target)
    end
    if not parksClock then State.left = math.max(State.left or 0, 0) end
  elseif State.mode == "CYCLE" then
    -- Soft-rotate only when CYCLE itself owns weather. WEATHER FRONTS=ON changes
    -- mode to FRONT above, freezing this timer until fronts are disabled.
    if not State.softTo then
      State.left = (State.left or 0) - dt
      if State.left <= 0 then
        State._battleCarry = false
        local nextId = nextInCycle()
        State.fresh = false
        beginSoftWeather(nextId)
        State.left = dwellFor(Types.get(nextId or State.id))
        State.persist()
      end
    end
  elseif State.mode == "FRONT" then
    -- Physical fronts own the automatic sky. Intentionally do not consume the
    -- global AUTO/CYCLE dwell clock underneath them.
  else
    -- AUTO: soft crossfade into the next pick (never hard-cut the sky).
    if not State.softTo then
      State.left = (State.left or 0) - dt
      if State.left <= 0 then
        if State._battleCarry then
          -- End battle authority cleanly. On the next frame resolveTarget gets
          -- first refusal again, so a regional front/location can resume instead
          -- of an unrelated global AUTO roll stealing the handoff.
          State._battleCarry = false
          State.left = 0
          State.persist()
        else
          local nextId = State.pick(mapId, State.fresh and Types.DEFAULT or nil)
          State.fresh = false
          beginSoftWeather(nextId)
          State.left = dwellFor(Types.get(nextId or State.id))
          State.persist()
        end
      end
    end
  end

  -- Keep the planner lifetime exactly aligned with State.softTo. A map/load or
  -- authority change may cancel a handoff without going through hardSetWeather.
  if not State.softTo and Synoptic and Synoptic.active and Synoptic.active() and Synoptic.reset then
    Synoptic.reset()
  end

  -- Soft weather handoff: advance blend; commit after time or a few maps.
  if State.softTo then
    State.softT = (State.softT or 0) + dt
    local dur = State.softDur or 32
    -- Synoptic timing is physical time, not map-count time. Older revisions
    -- allowed three map crossings to commit at 72%, which could instantly skip
    -- the final rain/lightning/cloud stages simply because the player walked
    -- quickly. Map traversal may continue throughout the handoff, but only the
    -- completed atmospheric plan commits the discrete id.
    local ready = (State.softT >= dur)
    if ready then
      State.id = State.softTo
      State.softFrom, State.softTo = nil, nil
      State.softT, State.softDur = 0, 0
      State.mapsTowardCommit = 0
      if Synoptic and Synoptic.reset then Synoptic.reset() end
      State.left = dwellFor(Types.get(State.id))
      State.persist()
    end
  end

  -- ease every channel toward the active weather (or a blend mid-handoff)
  local def = Types.get(State.id)
  local defTo = State.softTo and Types.get(State.softTo) or nil
  local blendU = 0
  if defTo and State.softDur and State.softDur > 0 then
    if Synoptic and Synoptic.update then
      -- Internal hot-path module: call directly. A pcall here plus one pcall per
      -- channel made the transition planner needlessly expensive on low-end
      -- devices; the optional-module guard already supplies the fallback.
      Synoptic.update(dt,State.id,State.softTo,State.softT,State.softDur)
    end
    blendU = math.min(1, math.max(0, (State.softT or 0) / State.softDur))
    -- Legacy fallback / diagnostics still expose a smooth scalar; individual
    -- channels below use the staged synoptic curves when available.
    blendU = blendU * blendU * (3 - 2 * blendU)
  end
  local tuning = Config.tuningFor(def.id)
  local menuIntensity = Settings.intensity()
  local tuningIntensity = tuning.intensity or 1
  local amount = menuIntensity * tuningIntensity
  local speed = tuning.speed or 1
  -- AUTO intensity multiplies on top, per FAMILY rather than globally, so
  -- the rain, the fog and the lightning breathe on unrelated rhythms
  -- instead of swelling together (which would read as the brightness
  -- being turned up and down).  Computed once per frame per family, not
  -- per channel: five sines a frame, not fifteen.
  local familyScale = nil
  if Settings.get("intensity") == "auto" then
    familyScale = FAMILY_SCALE
    for family in pairs(Settings.AUTO_FAMILIES) do
      familyScale[family] = Settings.autoScale(family, State.elapsed, Config)
    end
  end
  -- Menu dials are controls, not meteorological fronts. Keep natural weather
  -- transitions slow, but make an explicit strength edit visibly take effect
  -- within a fraction of a second. This avoids the old 3-10 second "setting did
  -- nothing" impression while preserving all normal onset/clearing curves.
  for _,k in ipairs(CONTROL_KEYS) do
    local r=Settings.keyRevision and Settings.keyRevision(k) or 0
    if r~=(State._controlRevisions[k] or 0) then State._controlRevisions[k]=r;State._controlResponse=.75 end
  end
  local controlFast=(State._controlResponse or 0)>0
  if controlFast then State._controlResponse=math.max(0,(State._controlResponse or 0)-(tonumber(dt) or 0)) end
  local weatherFast=(State._manualWeatherResponse or 0)>0
  if weatherFast then State._manualWeatherResponse=math.max(0,(State._manualWeatherResponse or 0)-(tonumber(dt) or 0)) end
  local tauScale = math.max(0.05, (Config.get().transitionSeconds or 3.2) / 3.2)
  if State._gentleIntro and State._gentleIntro > 0 then
    State._gentleIntro = State._gentleIntro - (tonumber(dt) or 0)
    if State._gentleIntro < 0 then State._gentleIntro = 0 end
    -- Slower approach during intro so weather builds in instead of popping
    tauScale = tauScale * 1.85
  end

  -- These menu controls are frame constants. 8.1.23 re-read all of them for
  -- every amount channel (and WIND again for gust), creating avoidable Lua
  -- dispatch in the hottest weather loop. Read once; the numerical targets are
  -- identical because settings cannot mutate in the middle of this update.
  local activeId,targetId=State.id,State.softTo
  local sourceFog=State.isFogWeather(activeId)
  local targetFog=targetId and State.isFogWeather(targetId) or false
  local sandId=(targetId=="SANDSTORM" and "SANDSTORM") or (activeId=="SANDSTORM" and "SANDSTORM") or nil
  local dustId=(targetId=="DUSTSTORM" and "DUSTSTORM") or (activeId=="DUSTSTORM" and "DUSTSTORM") or nil
  local sandMul=Settings.sandIntensity and (Settings.sandIntensity() or 1) or 1
  local dustMul=Settings.dustIntensity and (Settings.dustIntensity() or 1) or 1
  local fogMul=Settings.fogIntensity and (Settings.fogIntensity() or 1) or 1
  if Settings.fogOff and Settings.fogOff() then fogMul=0 end
  local rainMul=Settings.rainIntensity and (Settings.rainIntensity() or 1) or 1
  if Settings.rainOff and Settings.rainOff() then rainMul=0 end
  local snowMul=Settings.snowIntensity and (Settings.snowIntensity() or 1) or 1
  if Settings.snowOff and Settings.snowOff() then snowMul=0 end
  local windMul=Settings.windIntensity and (Settings.windIntensity() or 1) or 1
  local darknessMul=Settings.stormDarknessScale and (Settings.stormDarknessScale() or 1) or 1

  for _, key in ipairs(Types.channels) do
    -- INTENSITY scales the TARGET, not the drawn result, so turning it
    -- down makes a storm genuinely lighter rather than making a full storm
    -- transparent -- and channels that are not amounts (fall speed, lean
    -- angle, strikes per minute) are left alone by it.
    local goal = Types.channel(def, key)
    if defTo and blendU > 0 then
      local goalB = Types.channel(defTo, key)
      if Synoptic and Synoptic.active and Synoptic.active() and Synoptic.goal then
        local v=Synoptic.goal(key,goal,goalB)
        if tonumber(v) then goal=tonumber(v) else goal=goal+(goalB-goal)*blendU end
      else
        -- Compatibility fallback for hosts that omit SynopticTransition.
        local u = blendU
        local outW = 1.0 - (u * u)
        local inW = u * (2.0 - u)
        if inW > 1 then inW = 1 end
        if outW < 0 then outW = 0 end
        local mixed = goal * outW + goalB * inW
        if AMOUNT[key] then
          local floor = math.max(goal * outW, goalB * inW)
          goal = math.max(mixed, floor)
        else
          goal = mixed
        end
      end
    end
    local family = familyScale and Settings.CHANNEL_FAMILY[key]
    if AMOUNT[key] then
      local autoFamily = family and familyScale[family] or 1
      local scale = amount * autoFamily
      -- FOG INTENSITY is deliberately independent from the fixed SOFT/NORMAL/
      -- HEAVY INTENSITY row. Keep per-weather tuning, and keep the AUTO haze
      -- oscillator when INTENSITY=AUTO, but do not let the fixed global dial
      -- secretly thicken/thin fog or veil. This matches both the menu help and
      -- the 3D path, which already treated fog separately.
      if key == "fog" or key == "veil" then
        scale = tuningIntensity * autoFamily
      end
      -- During an AUTO/front handoff, family-specific menu dials follow both
      -- ends of the transition. The ids and menu multipliers were cached once
      -- above because they are invariant across every channel in this frame.
      if key == "rain" then
        -- RAIN INTENSITY changes density/count only. rainSpeed/rainLen/rainAngle
        -- are separate channels and deliberately never read this multiplier.
        if rainMul <= 0 then goal = 0
        else goal = math.min(6.0, goal * scale * rainMul) end
      elseif key == "snow" then
        -- Dedicated SNOW INTENSITY is a true percentage multiplier and stacks
        -- with global INTENSITY/AUTO. Do not use the old generic 2.0 cap: the
        -- authored Snow/Blizzard/Thundersnow catalogue legitimately exceeds 2.
        if snowMul <= 0 then goal = 0
        else goal = math.min(45.0, goal * scale * snowMul) end
      elseif key == "sand" then
        -- SAND INTENSITY / DUST INTENSITY scale particles; cap unchanged (2.0).
        if sandId then
          if sandMul <= 0 then goal = 0
          else goal = math.min(2.0, goal * scale * sandMul) end
        elseif dustId then
          if dustMul <= 0 then goal = 0
          else goal = math.min(2.0, goal * scale * dustMul) end
        else
          goal = math.min(2.0, goal * scale)
        end
      elseif key == "fog" or key == "veil" then
        -- Fog-family: FOG INTENSITY. Sand/dust: haze scaled by sand/dust + fog dials.
        -- Caps unchanged (20.0 max).
        if sourceFog or targetFog then
          if fogMul <= 0 then goal = 0
          else goal = math.min(20.0, goal * scale * fogMul) end
        elseif sandId then
          -- Haze toward 25% visibility at 500% (sandHaze 0..0.75 → strong fog).
          local haze = 0
          if Settings.sandHaze then haze = Settings.sandHaze() or 0 end
          if sandMul <= 0 or haze <= 0 then goal = 0
          else
            local m = (0.4 + haze * 12.0) * (fogMul > 0 and math.max(0.25, fogMul) or 1)
            goal = math.min(20.0, goal * scale * m)
          end
        elseif dustId then
          local haze = 0
          if Settings.dustHaze then haze = Settings.dustHaze() or 0 end
          if dustMul <= 0 or haze <= 0 then goal = 0
          else
            local m = (0.4 + haze * 12.0) * (fogMul > 0 and math.max(0.25, fogMul) or 1)
            goal = math.min(20.0, goal * scale * m)
          end
        else
          -- No fog-family weather at either end: preserve the historical
          -- no-screen-haze contract.  Incoming/outgoing fog is handled above.
          goal = 0
        end
      elseif key == "dim" then
        if sandId or dustId then
          -- Sand/dust must not darken the screen; visibility is haze/blur only.
          goal = 0
        else
          goal = math.min(2.0, goal * scale * darknessMul)
        end
      else
        goal = math.min(2.0, goal * scale)
      end
    elseif key == "rainSpeed" or key == "snowSpeed" or key == "fogSpeed" then
      goal = goal * speed
    elseif key == "gust" then
      -- Wind intensity scales the physical gust authority, not simulation time.
      goal = math.min(3.0, goal * windMul)
    elseif family then
      -- `strike` is a RATE, not an amount, so it is not scaled by
      -- INTENSITY -- but it is exactly the thing that should cluster and
      -- go quiet under AUTO, so the family multiplier reaches it here.
      goal = goal * familyScale[family]
    end
    -- Physical front footprint: only amplitudes fade toward the storm edge.
    -- Kinematic channels (fall speed/angle/length/drift) keep authored values,
    -- so walking into a fringe changes amount/intensity, never particle speed.
    if State.pinnedBy=="front" and SPATIAL_AMPLITUDE[key] then
      goal=goal*math.max(0,math.min(1,tonumber(State._spatialStrength) or 1))
    end
    local tau = (TAU[key] or TAU_DEFAULT) * tauScale
    if controlFast and (AMOUNT[key] or key=="gust") then tau=math.min(tau,0.12) end
    -- Manual weather pins should become perceptibly active in the same second
    -- the menu changes. This includes strike rate so Primal/Storm cannot spend
    -- several seconds looking like silent rain. It does NOT affect AUTO/front
    -- transitions, which never set _manualWeatherResponse.
    if weatherFast and (AMOUNT[key] or key=="strike" or key=="gust" or key=="rainSpeed" or key=="rainLen" or key=="rainAngle") then
      tau=math.min(tau,0.14)
    end
    if goal <= 0.0001 and TAU_CLEAR_OUT[key] then
      tau = TAU_CLEAR_OUT[key] * tauScale
    end
    State.ch[key] = ease(State.ch[key] or 0, goal, dt, tau)
  end
  State.dirty = true
end

-- ------- persistence

function State.persist()
  -- In-game benchmark phases temporarily force weather for repeatable timing.
  -- They must never leak that synthetic weather into the player's save.
  if State._suppressPersist then return end
  Fronts.persist()
  if StormCells and StormCells.persist then StormCells.persist() end
  local ok = pcall(function()
    mod.save:set("id", State.id)
    mod.save:set("left", math.floor(State.left or 0))
    mod.save:set("softFrom", State.softFrom or "")
    mod.save:set("softTo", State.softTo or "")
    mod.save:set("softT", tonumber(State.softT) or 0)
    mod.save:set("softDur", tonumber(State.softDur) or 0)
    mod.save:set("cycleIndex", tonumber(State.cycleIndex) or 0)
    mod.save:set("battleCarry", State._battleCarry and 1 or 0)
  end)
  if not ok then
    -- A save bucket that will not take a write is not worth a crash inside
    -- a render tick; the weather simply will not survive the session.
    mod.log:warn("could not write weather state to the mod save")
  end
end

function State.restore()
  -- Always clear process-local transition state first. Loading a different save
  -- must never inherit the previous world's half-finished front.
  State.softFrom, State.softTo = nil, nil
  State.softT, State.softDur = 0, 0
  State.mapsTowardCommit = 0
  local hadSavedWeather = false
  local ok = pcall(function()
    local rawId = mod.save:get("id", nil)
    hadSavedWeather = type(rawId) == "string" and rawId ~= ""
    local id = hadSavedWeather and rawId or Types.DEFAULT
    local left = tonumber(mod.save:get("left", 0)) or 0
    State.id = Types.get(id).id       -- unknown ids degrade to CLEAR
    State.left = math.max(0, left)
    State.cycleIndex = math.max(0, math.floor(tonumber(mod.save:get("cycleIndex", State.cycleIndex or 0)) or 0))
    State._battleCarry = (tonumber(mod.save:get("battleCarry", 0)) or 0) ~= 0

    local sf = mod.save:get("softFrom", "")
    local st = mod.save:get("softTo", "")
    local tt = tonumber(mod.save:get("softT", 0)) or 0
    local td = tonumber(mod.save:get("softDur", 0)) or 0
    if type(sf)=="string" and type(st)=="string" and sf~="" and st~=""
        and Types.byId[sf] and Types.byId[st] and td>0 and tt>=0 and tt<td then
      State.softFrom, State.softTo = sf, st
      State.softT, State.softDur = math.min(tt,td), td
      -- The persisted discrete id is the source until the handoff commits.
      State.id = sf
    end
  end)
  if not ok then
    State.id = Types.DEFAULT
    State.left = 0
    State.softFrom, State.softTo = nil, nil
    State.softT, State.softDur = 0, 0
    hadSavedWeather = false
    State._battleCarry = false
  end
  State.overrideMap = nil
  if Synoptic and Synoptic.reset then Synoptic.reset() end
  if State.softTo and Synoptic and Synoptic.begin then
    pcall(function()
      Synoptic.begin(State.softFrom,State.softTo,Config.get().transitionSeconds or 3.2)
      if Synoptic.update then Synoptic.update(0,State.softFrom,State.softTo,State.softT,State.softDur) end
    end)
  end
  Fronts.restore()
  if StormCells and StormCells.restore then StormCells.restore() end

  -- Start on exactly what the player set:
  --   ALWAYS / config.force → that weather, snapped now
  --   saved AUTO/CYCLE → resume the saved spell/transition
  --   brand-new AUTO world → roll on first outdoor tick
  local forced = nil
  pcall(function()
    local cfg = Config.get()
    if cfg and cfg.force then forced = cfg.force end
  end)
  if not forced and Settings.alwaysWeather then
    forced = Settings.alwaysWeather()
  end
  if forced and Types.get(forced) then
    State.id = Types.get(forced).id
    State._battleCarry = false
    State.pinnedBy = (Config.get() and Config.get().force) and "force" or "always"
    State.left = 0
    State.softFrom, State.softTo = nil, nil
    State.softT, State.softDur = 0, 0
    State._sessionStart = false
  else
    State._sessionStart = not hadSavedWeather
  end

  -- Store intended weather id, but do NOT paint the sky until we know the
  -- player is outdoors. Loading in a cave/building must start with no weather.
  State.settle()
  for _, key in ipairs(Types.channels) do
    State.ch[key] = 0
  end
  State._needOutdoorStart = true
  State._bootSnapFog = true
  State.dirty = true
end

-- ------- for the debug row and the battle layer

function State.describe()
  local def = State.current()
  local rung = State.LEVEL_IDS[(State.level or 0) + 1]
  if rung == false then
    -- Say WHY nothing is happening.  A config with `force` set and the
    -- OPTIONS row on OFF is the single most confusing state this mod can
    -- be in, and a readout that just says "OFF" makes the player hunt for
    -- a bug that is one menu row away.
    if Config.get().force then return "OFF (force ignored - row is OFF)" end
    return "OFF (row is OFF)"
  end
  if State.pinnedBy == "front" then
    return ("FRONT %s"):format(Fronts.describe(State.lastMapId))
  end
  if State.pinnedBy == "auto" or State.pinnedBy == "cycle" then
    return ("%s %s %ds"):format(State.pinnedBy:upper(), def.label,
      math.floor(State.left or 0))
  end
  return ("%s %s"):format(State.pinnedBy:upper(), def.label)
end

return State
