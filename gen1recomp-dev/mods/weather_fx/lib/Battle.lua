-- BATTLE WEATHER.
--
-- =====================================================================
-- THE ONE DESIGN DECISION EVERYTHING ELSE FOLLOWS FROM
-- =====================================================================
--
-- `battle.field.weather` IS THE ONLY SOURCE OF TRUTH, AND IT IS NOT OURS.
--
-- Kanto-Reforged already implements battle weather.  Its Sunny Day / Rain
-- Dance / Sandstorm / Hail moves, its Drought / Drizzle / Sand Stream /
-- Air Lock abilities, its Weather Ball, its Forecast Castform, its Sand
-- Veil and its Chlorophyll and Swift Swim speed multipliers ALL read
-- `battle.field.weather` and expect the strings SUNNY, RAINY, SANDSTORM,
-- HAIL and SNOWY.
--
-- So this mod writes that field, in that vocabulary, and reads it back.
-- It does not keep a weather of its own for battles.  The alternative --
-- a parallel field -- would mean a Rain Dance that made it rain for
-- Reforged's Swift Swim but not for our Water boost, which is exactly the
-- class of bug that makes two mods "incompatible".  One field, two
-- writers, and every reader agrees.
--
-- CAPABILITY DETECTION, NOT VERSION CHECKING.  On load this file asks what
-- is already implemented and switches off its own copy of it.  With
-- Kanto-Reforged installed, Weather Ball / Forecast / Sand Veil /
-- Chlorophyll come from there and this mod adds the parts that are
-- missing; without it, this mod adds what it can, which is less, because
-- Gen 1 has no abilities, no held items and no Weather Ball to begin with.
-- Nothing is applied twice in either case.
--
-- =====================================================================
-- WHAT GATES THIS
-- =====================================================================
--
--   * `config.battle.enabled` -- the master switch.
--   * Effects apply to whatever weather is ALREADY in the field.  With no
--     mod setting weather and no seeding, the field is always nil, every
--     hook is a pass-through, and the battle is byte-for-byte vanilla.
--   * SEEDING -- carrying the overworld's weather into a battle -- is
--     controlled directly by `config.battle.seedFromOverworld` plus the
--     BATTLE WEATHER FX / BATTLE WEATHER DMG menu switches.  The retired
--     WEATHER ruleset gate is not registered or consulted anymore.
--
-- =====================================================================
-- GEN 1 LIMITATIONS, STATED PLAINLY
-- =====================================================================
--
-- Some of the reference behaviour has nowhere to attach in a Gen 1 engine:
--
--   * NO ABILITIES.  Chlorophyll, Ice Body, Sand Veil and the rest need a
--     mod that adds abilities.  Everything here that touches one is inert
--     without Kanto-Reforged, by construction rather than by a version
--     check: `abilityOf` simply never returns anything.
--   * NO HELD ITEMS.  Same: `mon.heldItem` is nil in vanilla, so the
--     weather rocks and Utility Umbrella cost one nil check.
--   * NO WEATHER BALL, NO CASTFORM, NO SYNTHESIS/MOONLIGHT.  These moves
--     and species do not exist in Gen 1.  With Reforged they do, and it
--     implements them.
--   * SOLAR BEAM'S CHARGE TURN uses the engine's battle.charge_required
--     hook. Sun and harsh sun release it immediately; all other conditions
--     preserve the engine/other-mod charge decision.
--   * SPECIAL IS ONE STAT in Gen 1, so "Special Defence up in a
--     sandstorm" raises the same number "Special Attack up" would.  It is
--     applied as a damage reduction on incoming special moves only, which
--     is the half of it that behaves like the modern stat.

local V = ...
local mod = V.mod
local Types = V.require("Types")
local Config = V.require("Config")
local Settings = V.require("Settings")
local State = V.require("WeatherState")
local _hostOk, HostRuntime = pcall(V.require, "HostRuntime")
if not _hostOk or type(HostRuntime) ~= "table" then
  -- Old unit harnesses / pre-adapter hosts: preserve the exact Gen1 path.
  HostRuntime = { nativeGen2BattleWeather = function() return false end }
end

local Battle = {}


-- THE LIVE BATTLE.
--
-- Most hooks are handed it on the ctx, but `battle.turn_order` is not:
-- the engine builds that ctx as `{ rng = self.rng }` and nothing else
-- (BattleState:2309).  Reading `ctx.battle` there returned nil, which
-- meant the weather speed abilities silently never fired -- dead code that
-- every test passed because the tests handed in a ctx that HAD a battle.
-- Tracked from the events instead, which is the only source that works
-- for every hook.
local current = nil

function Battle.current()
  return current
end

function Battle.world3dWeatherOwns()
  local okS,Scene=pcall(V.require,"Scene")
  if not (okS and Scene and Scene.now and Scene.now.visible=="battle" and Scene.now.battleOpaque==false) then return false end
  if Settings.force2dPresent and Settings.force2dPresent() then return false end
  if Settings.allow3dPresent and not Settings.allow3dPresent() then return false end
  local okV,Bridge=pcall(V.require,"VoxelAtmosBridge")
  return okV and Bridge and Bridge.active and Bridge.active() and true or false
end

-- ------- what somebody else already does

Battle.caps = {
  reforged = false,
  evasion = false,       -- Sand Veil
  speed = false,         -- Chlorophyll / Swift Swim
}

local function detectCapabilities()
  -- Reset first: install() is re-run on a hot reload, and a capability
  -- that latched true would stay true after the mod providing it was
  -- removed -- which would silently disable our own copy of it forever.
  Battle.caps.reforged = false
  Battle.caps.evasion = false
  Battle.caps.speed = false
  local ok, handle = pcall(function() return mod.find("Kanto-Reforged") end)
  if ok and handle then
    Battle.caps.reforged = true
    -- Everything in this list is implemented there and must NOT be
    -- implemented here as well, or the multiplier lands twice.
    Battle.caps.evasion = true
    Battle.caps.speed = true
    mod.log:info("Kanto-Reforged detected: deferring Sand Veil and weather speed to it")
  end
end

-- ------- reading the battle
--
-- Every accessor here is total and cheap.  They are called from inside
-- damage and accuracy hooks, which run several times a turn, so none of
-- them allocates and none of them can throw.

-- The weather in force for THIS battler, which is not always the weather
-- in the field: a suppressing ability or a Utility Umbrella removes it for
-- everyone / for its holder.
-- Legacy saves may still contain the removed `battlerules` option.  The
-- Settings helpers translate only its old OFF value as a compatibility
-- fallback; current battle behaviour is controlled by the split FX/DMG rows.
local function animOn()
  local ok, v = pcall(Settings.battleAnimOn)
  if ok then return v and true or false end
  return true
end

local function damageOn()
  local ok, v = pcall(Settings.battleDamageOn)
  if ok then return v and true or false end
  return true
end

-- Crystal 251 owns Gen 2 battle weather (battle.weather = rain/sun/sandstorm).
-- We must not also apply field-weather damage or residual chip.
function Battle.hostCrystal()
  if Battle._hostCrystal ~= nil then return Battle._hostCrystal end
  local found = false
  pcall(function()
    if mod.find and mod.find("CRYSTAL_251") then found = true end
  end)
  Battle._hostCrystal = found
  return found
end

function Battle.effectsEnabled()
  -- Damage / type modifiers only.
  if Battle.hostCrystal() then return false end
  if not damageOn() then return false end
  return Config.get().battle.enabled and true or false
end

function Battle.animEnabled()
  -- Visual weather in battle only.
  if not animOn() then return false end
  return Config.get().battle.enabled and true or false
end

-- Gen2Recomped owns the retail Gen-2 battle-weather vocabulary and mechanics.
-- Keep that native field untouched for RAIN/SUN/SANDSTORM/HAIL. Weather FX-only
-- skies live in wxWeather so the host's Weather.current() never interprets a
-- custom storm as a native weather condition.
local NATIVE_TO_WX = {
  RAIN = "RAINY", SUN = "SUNNY", SANDSTORM = "SANDSTORM", HAIL = "HAIL",
}
local WX_TO_NATIVE = {
  RAINY = "RAIN", SUNNY = "SUN", SANDSTORM = "SANDSTORM", HAIL = "HAIL",
}

local function nativeFieldWeather(battle)
  local field = battle and battle.field
  local w = field and field.weather
  if type(w) ~= "string" or w == "" then return nil end
  return tostring(w):upper()
end

local function fieldWeather(battle)
  local field = battle and battle.field
  local w = nativeFieldWeather(battle)
  if not w and field then w = field.wxWeather end
  if type(w) ~= "string" or w == "" then return nil end
  return tostring(w):upper()
end

local function visualWeather(weather)
  if type(weather) ~= "string" then return weather end
  weather = tostring(weather):upper()
  return NATIVE_TO_WX[weather] or weather
end

local function nativeMechanicsOwn(battle)
  if not HostRuntime.nativeGen2BattleWeather() then return false end
  local raw = nativeFieldWeather(battle)
  return raw ~= nil and NATIVE_TO_WX[raw] ~= nil
end

local function hostWeatherForSeed(weather)
  if not HostRuntime.nativeGen2BattleWeather() then return weather, false end
  local native = WX_TO_NATIVE[weather]
  if native then return native, true end
  return weather, false
end

Battle.visualWeather = visualWeather
Battle.nativeMechanicsOwn = nativeMechanicsOwn

-- Reforged's convention, followed rather than reinvented: the species
-- record's ability, unless the battler has traced one or had it
-- suppressed.  Returns nil in vanilla, where no record has an ability.
local function abilityOf(battle, battler)
  if not (battler and battler.mon) then return nil end
  if battler.expAbilitySuppressed then return nil end
  if battler.expTracedAbility then return battler.expTracedAbility end
  local data = battle and battle.data and battle.data.pokemon
  local def = data and data[battler.mon.species]
  return def and def.ability or nil
end
Battle.abilityOf = abilityOf

local function heldItem(battler)
  return battler and battler.mon and battler.mon.heldItem or nil
end

-- Cloud Nine and friends.  Air Lock is not listed: Kanto-Reforged already
-- clears the field outright when an Air Lock holder enters, which is the
-- same outcome by a different route, and listing it here would suppress a
-- weather that mod had already removed.
local function weatherSuppressed(battle)
  local set = Config.get().battle.suppressSet
  if not next(set) then return false end
  for _, b in ipairs({ battle and battle.player, battle and battle.enemy }) do
    if b and set[abilityOf(battle, b) or ""] then return true end
  end
  return false
end

-- The weather a given battler experiences.  nil for "none".
function Battle.weatherFor(battle, battler)
  if not Battle.effectsEnabled() then return nil end
  local w = fieldWeather(battle)
  if not w then return nil end
  -- Gold/Silver/Crystal already apply their native standard-weather mechanics.
  -- Weather FX still renders them, but its modifier/residual hooks stand down.
  if nativeMechanicsOwn(battle) then return nil end
  if weatherSuppressed(battle) then return nil end
  if Config.battleEffect("heldItems") then
    local umbrella = Config.get().battle.items.umbrella
    if umbrella and heldItem(battler) == umbrella then return nil end
  end
  return visualWeather(w)
end

-- The weather in force generally (no particular battler), for effects that
-- are about the field rather than about one side.
function Battle.weather(battle)
  if not Battle.effectsEnabled() then return nil end
  local w = fieldWeather(battle)
  if not w or nativeMechanicsOwn(battle) or weatherSuppressed(battle) then return nil end
  return visualWeather(w)
end

-- ------- one type has two names
--
-- The engine's type IDs and their DISPLAY names agree for fourteen of the
-- fifteen Gen 1 types. The exception is Psychic: the id is `PSYCHIC_TYPE`
-- and the name is `PSYCHIC` (src/battle/TypeChart.lua). A battler's
-- `curTypes` carries the ID, so a table written with the readable name --
-- which is what every chipType in the catalogue uses -- silently never
-- matches it.
--
-- That is not hypothetical: a PSYSTORM was chipping Alakazam, the one
-- species it exists to spare. Nothing errored; the comparison simply never
-- came out true.
--
-- Normalised in the ONE place battler types are compared, rather than
-- renaming fifteen chipTypes to a form nobody writing this catalogue would
-- think of. Keyed both ways so an id or a name may be passed.
local TYPE_ALIAS = {
  PSYCHIC = "PSYCHIC_TYPE",
  PSYCHIC_TYPE = "PSYCHIC_TYPE",
}

local function hasType(battler, typeName)
  local list = battler and battler.curTypes
  if type(list) ~= "table" then return false end
  local want = TYPE_ALIAS[typeName] or typeName
  for i = 1, #list do
    local have = TYPE_ALIAS[list[i]] or list[i]
    if have == want then return true end
  end
  return false
end
Battle.hasType = hasType

local function categoryOf(move)
  if not move then return "physical" end
  if move.category then return move.category end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.category then
    local ok2, cat = pcall(TypeChart.category, move.type)
    if ok2 and cat then return cat end
  end
  return "physical"
end

local function rollPercent(battle, pct)
  local rng = battle and battle.rng
  local n
  if rng then n = rng(0, 99)
  elseif love and love.math then n = love.math.random(0, 99)
  else n = math.random(0, 99) end
  return n < pct
end

-- ------- 1. TYPE POWER
--
-- The headline effect and the one everybody knows.  Multipliers are the
-- reference ones; the primal weathers are handled in ACCURACY instead,
-- because "the move does not work" is a miss, not zero damage -- returning
-- 0 from a damage hook produces a hit that did nothing, which reads as a
-- bug rather than as a nullified attack.

local POWER = {
  SUNNY      = { FIRE = 1.5, WATER = 0.5 },
  HARSH_SUN  = { FIRE = 1.5 },              -- WATER fails; see accuracy
  RAINY      = { WATER = 1.5, FIRE = 0.5 },
  HEAVY_RAIN = { WATER = 1.5 },             -- FIRE fails; see accuracy
}

-- ------- 1b. AMPLIFIED WEATHER -- NOT REFERENCE BEHAVIOUR
--
-- In the reference games the primal weathers' distinguishing feature IS
-- the nullification: HARSH_SUN boosts FIRE by exactly the same 1.5 that
-- ordinary sun does, and a sandstorm has never boosted any move's power
-- in any generation.  These rows change that -- the matching type hits
-- harder in a primal sky, and a sandstorm powers ROCK and GROUND the way
-- rain powers WATER.
--
-- It is house-rule territory, so it is a switch of its own
-- (`battle.amplified`) rather than folded into `typePower`, and it
-- REPLACES the reference row for that weather rather than stacking with
-- it: two multipliers for one effect is the double-apply bug this mod
-- takes care to avoid everywhere else.
local POWER_AMPLIFIED = {
  HARSH_SUN  = { FIRE = 2.0 },
  HEAVY_RAIN = { WATER = 2.0 },
  SANDSTORM  = { ROCK = 1.5, GROUND = 1.5 },
  -- Ice in a blizzard, by the same logic as sand in a sandstorm: the
  -- weather that hurts everyone else should favour the type that lives
  -- in it.  HAIL and SNOWY both, since the vocabulary carries both.
  HAIL       = { ICE = 1.5 },
  SNOWY      = { ICE = 1.5 },
}

-- ------- 1c. TERRAIN -- ALSO NOT REFERENCE BEHAVIOUR
--
-- A per-map type bonus, read from `config.battle.terrain`.  Inspired by
-- the Gen 6+ Terrain moves, but Gen 1 has no terrain-setting move to
-- attach to, so it is a property of WHERE the battle is fought instead:
-- Bug and Grass under a forest canopy, Electric in the Power Plant,
-- Ghost in the tower.
--
-- Independent of weather by design -- a battle in Viridian Forest gets
-- the canopy bonus whether or not it is raining, which is why the damage
-- hook below can no longer bail out early just because the sky is clear.
local function terrainScale(ctx)
  -- `effectsEnabled` first, and NOT just `battleEffect("terrain")`: the
  -- latter answers "is this individual effect switched on" and misses the
  -- mod-manager rules row, which `effectsEnabled` folds in.  Every weather
  -- effect reaches that gate through `weatherFor`; terrain has no weather
  -- to look up, so it has to ask directly or the manager's off switch
  -- would silently leave terrain running.
  if not Battle.effectsEnabled() then return 1 end
  if not Config.battleEffect("terrain") then return 1 end
    local mapId = Battle.mapId
  if not mapId then return 1 end
  local table_ = Config.get().battle.terrain
  local row = table_ and table_[mapId]
  if not row then return 1 end
  local moveType = ctx.move and ctx.move.type
  if not moveType then return 1 end
  local mult = row[moveType]
  if type(mult) ~= "number" then return 1 end
  return mult
end

-- Solar Beam is halved in anything that is not sun.  Named by move id so a
-- mod that renames it stops matching rather than mis-matching.
local SOLAR_MOVES = { SOLARBEAM = true, SOLAR_BEAM = true, SOLAR_BLADE = true }
local SOLAR_SKIP_CHARGE = { SUNNY = true, HARSH_SUN = true }

local function solarSkipsCharge(ctx)
  if not ctx or not Config.battleEffect("solarBeam") then return false end
  local moveId = ctx.move and tostring(ctx.move.id or ""):upper()
  if not SOLAR_MOVES[moveId] then return false end
  local weather = Battle.weatherFor(ctx.battle, ctx.user)
  return weather and SOLAR_SKIP_CHARGE[weather] and true or false
end

local DIMMED_FOR_SOLAR = { RAINY = true, HEAVY_RAIN = true, ELECTRIC_STORM = true,
                           VERDANT_RAIN = true, BRAWL_WIND = true, SMOG = true,
                           DUSTSTORM = true, FLOCKSTORM = true, SWARM = true,
                           HAUNTED_MIST = true, DRAGONSTORM = true,
                           SANDSTORM = true,
                           HAIL = true, SNOWY = true, FOG = true }

-- Is the amplified house rule on?
--
-- Two answers can disagree: the OPTIONS row and `battle.effects.amplified`
-- in config.lua. The row wins when it says anything definite, and its AUTO
-- default defers to the file -- so adding the row gave players a way to
-- answer without taking the file's answer away from anyone who had already
-- set it.
--
-- Read through Settings rather than Config because this is a menu question;
-- an unreadable row falls through to the file, which is the behaviour every
-- version before the row had.
local function amplifiedOn()
  local ok, row = pcall(Settings.get, "amplified")
  if ok and row == "on" then return true end
  if ok and row == "off" then return false end
  return Config.battleEffect("amplified")
end

local function damageScale(battle, ctx, weather)
  local scale = 1
  local moveType = ctx.move and ctx.move.type
  local moveId = ctx.move and ctx.move.id

  if Config.battleEffect("typePower") then
    -- The amplified row REPLACES the reference one for that weather when
    -- it exists; it never multiplies on top of it.
    local row = (amplifiedOn() and POWER_AMPLIFIED[weather])
      or POWER[weather]
    if row and moveType and row[moveType] then scale = scale * row[moveType] end
  end

  if Config.battleEffect("solarBeam") and moveId and SOLAR_MOVES[moveId] then
    if DIMMED_FOR_SOLAR[weather] then scale = scale * 0.5 end
  end

  return scale
end

-- ------- 2. ACCURACY

-- Perfect accuracy under the right sky, and a penalty under the wrong one.
local ACCURACY = {
  THUNDER   = { RAINY = "always", HEAVY_RAIN = "always", ELECTRIC_STORM = "always", SUNNY = 50, HARSH_SUN = 50 },
  HURRICANE = { RAINY = "always", HEAVY_RAIN = "always", SUNNY = 50, HARSH_SUN = 50 },
  BLIZZARD  = { HAIL = "always", SNOWY = "always" },
  -- the reference's three "-storm" moves, present only with a mod that
  -- adds them; harmless entries otherwise
  BLEAKWIND_STORM = { RAINY = "always", HEAVY_RAIN = "always" },
  WILDBOLT_STORM  = { RAINY = "always", HEAVY_RAIN = "always" },
  SANDSEAR_STORM  = { RAINY = "always", HEAVY_RAIN = "always" },
}

-- Fog reduces everyone's accuracy, which is the one thing Gen 4 fog did.
local FOG_ACCURACY = 0.85

-- The primal weathers nullify the opposing type outright.
local NULLIFIED = {
  HARSH_SUN = "WATER",
  HEAVY_RAIN = "FIRE",
}

-- ------- 0. SAYING WHAT THE WEATHER IS DOING
--
-- THE COMPLAINT THIS FIXES: the weather changed the fight and never said so.
-- Chip damage announces itself every turn, and a nullified move explains
-- itself when it fails -- but the boosts and dampenings, which are the
-- effects that decide most turns, were invisible. A player could fight a
-- whole battle in heavy rain without being told why their Fire moves were
-- doing half damage.
--
-- Written as GAME MESSAGES, not an overlay. The battle already has a text
-- queue with the right font, timing and pacing; a drawn panel would have to
-- reinvent all three and would still look like something bolted on. Two
-- lines at most, in the voice the residual messages already use.
--
-- DERIVED, never a second table. Every line below is generated from POWER,
-- POWER_AMPLIFIED and NULLIFIED -- the same tables the damage hook reads. A
-- hand-written list would be a second source of truth that drifts the moment
-- a weather is retuned, and the failure mode is the worst kind: the game
-- confidently telling the player something that is no longer true.
--
-- WHAT IS DELIBERATELY NOT SAID:
--   * Effects that apply to BOTH sides identically. Rain boosts Water for
--     everyone, so "PLAYER: Water up / ENEMY: Water up" is noise -- it reads
--     as asymmetry where there is none. Sides are named only where they
--     actually differ, which in practice is nothing here: Gen 1 weather is
--     symmetric. If an asymmetric effect is ever added, this is where it
--     goes.
--   * Chip damage. It already announces itself every turn and repeating it
--     up front doubles the message for no information.
--   * Terrain and accuracy. Accuracy is a per-move surprise that reads
--     better when the move fails; terrain is a property of the place, not
--     the sky.

local TYPE_WORD = {
  FIRE = "FIRE", WATER = "WATER", GRASS = "GRASS", ELECTRIC = "ELECTRIC",
  ICE = "ICE", ROCK = "ROCK", GROUND = "GROUND", FLYING = "FLYING",
  BUG = "BUG", POISON = "POISON", FIGHTING = "FIGHTING", GHOST = "GHOST",
  DRAGON = "DRAGON", NORMAL = "NORMAL", PSYCHIC = "PSYCHIC",
  PSYCHIC_TYPE = "PSYCHIC",
}

-- The one-line description of the sky itself, taken from the catalogue so a
-- new weather needs no entry here.
-- Gen1 battle text boxes are 2 lines × ~18 characters. Fit every WX line
-- to that so nothing scrolls; UI mods still render via sayNext (their box).
local BOX_W, BOX_H = 18, 2

local function fitBattleBox(text)
  text = tostring(text or ""):gsub("\r", ""):gsub("\t", " "):gsub("\n", " ")
  local words = {}
  for w in text:gmatch("%S+") do
    while #w > BOX_W do
      words[#words + 1] = w:sub(1, BOX_W)
      w = w:sub(BOX_W + 1)
    end
    if w ~= "" then words[#words + 1] = w end
  end
  local rows, cur = {}, ""
  for _, w in ipairs(words) do
    local trial = (cur == "") and w or (cur .. " " .. w)
    if #trial <= BOX_W then
      cur = trial
    else
      if cur ~= "" then
        rows[#rows + 1] = cur
        if #rows >= BOX_H then
          cur = nil
          break
        end
      end
      cur = w
    end
  end
  if cur and #rows < BOX_H then rows[#rows + 1] = cur end
  if #rows == 0 then return "" end
  return table.concat(rows, "\n")
end

local function skyLine(weather)
  local def = Types.forBattleWeather(weather)
  local label = (def and def.battleText) or nil
  if label then return label end
  local WORDS = {
    RAINY = "It is raining!",
    HEAVY_RAIN = "A heavy rain\nis falling!",
    SUNNY = "The sunlight is\nstrong!",
    HARSH_SUN = "The sunlight is\nharsh!",
    SANDSTORM = "A sandstorm is\nraging!",
    HAIL = "Hail is falling!",
    SNOWY = "It is snowing!",
    FOG = "A deep fog\nrolled in!",
    STRONG_WINDS = "Mysterious winds\nare blowing!",
  }
  if WORDS[weather] then return WORDS[weather] end
  -- `label` is the OPTIONS-row abbreviation -- "PSY", "BRAWL", "VRAIN" --
  -- sized for a menu column, not a sentence. Reading it out gives "The PSY
  -- is swirling!". The typed storms all carry a chipType, which is the full
  -- type word, so that is the better source; label is the last resort.
  local word = (def and def.chipType and (TYPE_WORD[def.chipType] or def.chipType))
  if word then
    return ("A %s storm\nis swirling!"):format(word)
  end
  local name = (def and def.label) or weather
  return ("The %s is\nswirling!"):format(tostring(name))
end

-- Everything the damage tables say about this sky, as player-facing lines.
-- Returns at most two: one for what grew stronger, one for what weakened.
function Battle.effectLines(weather)
  if not Config.battleEffect("typePower") then return {} end
  local row = (amplifiedOn() and POWER_AMPLIFIED[weather]) or POWER[weather]
  local up, down = {}, {}
  if row then
    for typeName, mult in pairs(row) do
      local word = TYPE_WORD[typeName] or typeName
      if mult > 1 then up[#up + 1] = word
      elseif mult < 1 then down[#down + 1] = word end
    end
  end
  -- A nullified type is the strongest statement the weather makes, so it is
  -- reported as its own line rather than lumped in with "weakened".
  local dead = NULLIFIED[weather]
  local lines = {}
  table.sort(up); table.sort(down)
  if up[1] then
    lines[#lines + 1] = ("%s moves\ngrew stronger!"):format(table.concat(up, " and "))
  end
  if dead then
    lines[#lines + 1] = ("%s moves\ncannot be used!"):format(TYPE_WORD[dead] or dead)
  elseif down[1] then
    lines[#lines + 1] = ("%s moves\nweakened!"):format(table.concat(down, " and "))
  end
  return lines
end

-- Queue the opening announcement.  Guarded end to end: a battle that cannot
-- take messages simply does not get them.
-- Announce only when the *weather identity* changes (start or mid-battle change).
-- Never re-say the same weather every turn.
-- Queue battle text EXACTLY like residual chip / other battle messages:
-- `battle:sayNext(text)` only. That uses the engine's normal confirm path
-- (A on controller / Space on keyboard) — not sayNextAuto / sayAuto.
local function sayBattleLine(battle, text)
  if not (battle and text and text ~= "") then return false end
  if type(battle.sayNext) ~= "function" then return false end
  -- Always fit to the standard 2-line battle box; engine/UI mods draw it
  text = fitBattleBox(text)
  if text == "" then return false end
  local ok = pcall(function() battle:sayNext(text) end)
  return ok and true or false
end

local function announce(battle, weather)
  if not (battle and weather) then return end
  if not Config.battleEffect("announce") then return end
  if not (Battle.effectsEnabled() or Battle.animEnabled()) then return end
  weather = visualWeather(tostring(weather))
  if weather == "" then return end
  if type(battle.sayNext) ~= "function" then return end
  battle.field = battle.field or {}
  local last = battle.field.wxAnnouncedFor
  if last == weather then return end

  -- Always engine sayNext (Anime Realism keeps drawTextArea ownership).
  local lines = { skyLine(weather) }
  local short = false
  pcall(function()
    local Compat = V.require("Compat")
    if Compat and Compat.battleProfile and Compat.battleProfile().announceShort then
      short = true
    end
  end)
  if not short then
    for _, line in ipairs(Battle.effectLines(weather) or {}) do
      lines[#lines + 1] = line
    end
  end

  local okAny = false
  for i = 1, #lines do
    if sayBattleLine(battle, lines[i]) then okAny = true end
  end
  if okAny then
    battle.field.wxAnnouncedFor = weather
    Battle._announcedWeather = weather
  end
end
Battle.announce = announce

-- Map battle.field.weather strings to overworld Weather FX ids.
local BATTLE_TO_OW = {
  RAIN = "RAIN_HEAVY", RAINY = "RAIN_HEAVY", HEAVY_RAIN = "HEAVY_RAIN",
  SUN = "SUNNY", SUNNY = "SUNNY", HARSH_SUN = "HARSH_SUN",
  SANDSTORM = "SANDSTORM", HAIL = "HAIL", SNOWY = "SNOW_LIGHT",
  FOG = "FOG", STRONG_WINDS = "STRONG_WINDS",
}


-- ------- 3. RESIDUAL DAMAGE

-- Every typed weather uses the same 1/16 residual rule.  The weather
-- catalogue supplies `chipType`, so adding a new type of weather does not
-- require another hard-coded branch here.
local RESIDUAL_TEXT = {
  NORMAL = "is buffeted\nby the PLAIN FRONT!",
  FIRE = "is scorched\nby the HEAT!",
  WATER = "is battered\nby the RAIN!",
  ELECTRIC = "is jolted\nby the STORM!",
  GRASS = "is worn down\nby the VERDANT RAIN!",
  ICE = "is pelted\nby the ICE!",
  FIGHTING = "is battered\nby the FIGHTING WINDS!",
  POISON = "is poisoned\nby the SMOG!",
  GROUND = "is battered\nby the DUSTSTORM!",
  FLYING = "is battered\nby the FLOCKSTORM!",
  PSYCHIC = "is battered\nby PSYCHIC ENERGY!",
  BUG = "is swarmed\nby the INSECTS!",
  ROCK = "is buffeted\nby the SANDSTORM!",
  GHOST = "is chilled\nby the HAUNTED MIST!",
  DRAGON = "is battered\nby DRAGONIC ENERGY!",
}

-- Abilities that turn residual weather into healing, or that heal anyway.
-- All of these are inert without an ability mod.
local HEALS = {
  ICE_BODY  = { HAIL = 1 / 16, SNOWY = 1 / 16 },
  RAIN_DISH = { RAINY = 1 / 16, HEAVY_RAIN = 1 / 16 },
  DRY_SKIN  = { RAINY = 1 / 8, HEAVY_RAIN = 1 / 8 },
}
local BURNS = {
  DRY_SKIN    = { SUNNY = 1 / 8, HARSH_SUN = 1 / 8 },
  SOLAR_POWER = { SUNNY = 1 / 8, HARSH_SUN = 1 / 8 },
}
-- Abilities that ignore residual weather damage entirely.
local RESIDUAL_IMMUNE = {
  OVERCOAT = true, MAGIC_GUARD = true, SAND_VEIL = true, SAND_RUSH = true,
  SAND_FORCE = true, ICE_BODY = true, SNOW_CLOAK = true, SLUSH_RUSH = true,
}

local function maxHpOf(battler)
  local mon = battler and battler.mon
  return (mon and mon.stats and mon.stats.hp) or (mon and mon.maxHp) or 0
end

local function displayName(b)
  local mon = b and b.mon
  local name = (mon and (mon.nickname or mon.species)) or "?"
  if b and b.isPlayer == false then return "Enemy " .. name end
  return name
end

-- One battler's end-of-turn weather effect.  Returns a message or nil.
local function residualFor(battle, b, weather)
  if not (b and b.mon and b.mon.hp and b.mon.hp > 0) then return nil end
  local cfg = Config.get().battle
  local ability = abilityOf(battle, b)
  local maxHp = maxHpOf(b)
  if maxHp <= 0 then return nil end

  -- healing first: an Ice Body holder in hail heals instead of chipping
  if Config.battleEffect("healing") and ability then
    local heal = HEALS[ability] and HEALS[ability][weather]
    if heal and b.mon.hp < maxHp then
      b.mon.hp = math.min(maxHp, b.mon.hp + math.max(1, math.floor(maxHp * heal)))
      return displayName(b) .. "'s\n" .. ability:gsub("_", " ") .. " restored HP!"
    end
    local burn = BURNS[ability] and BURNS[ability][weather]
    if burn then
      local hurt = math.max(1, math.floor(maxHp * burn))
      b.mon.hp = math.max(cfg.residualDamage.canFaint and 0 or 1, b.mon.hp - hurt)
      return displayName(b) .. " is hurt\nby the sunlight!"
    end
  end

  if not Config.battleEffect("residual") then return nil end
  -- Snow / Blizzard / Sleet / Thundersnow must NEVER residual-chip.
  -- Only HAIL deals ICE residual (Gen 9-style: Snow raises Def, does not chip).
  -- Field string SNOWY is shared by all soft snow weathers; treat it as no-chip
  -- even if a catalogue row is wrong or a host aliases snow to hail.
  local w = tostring(weather or ""):upper()
  if w == "SNOWY" or w == "SNOW" or w == "SNOW_LIGHT" or w == "BLIZZARD"
      or w == "SLEET" or w == "THUNDERSNOW" or w == "TSNOW" then
    return nil
  end
  -- Resolve the field weather back to the catalogue.  Shared battle
  -- strings such as RAINY/SNOWY are intentionally represented by their
  -- canonical typed weather, while unique fronts retain their own type.
  local def = Types.forBattleWeather(weather)
  if not def then
    -- Host may pass an overworld id (e.g. BLIZZARD) instead of a battle string.
    def = Types.get(weather)
  end
  if not def or not def.chipType then return nil end
  -- Belt-and-braces: frozen weathers other than HAIL never chip.
  if def.frozen and def.id ~= "HAIL" then return nil end
  if def.chipType == "ICE" and def.id ~= "HAIL" then return nil end
  if ability and RESIDUAL_IMMUNE[ability] then return nil end
  -- Harsh sun (Drought): Ground types do not take residual chip (Groudon, etc.).
  if weather == "HARSH_SUN" and hasType(b, "GROUND") then return nil end

  -- A weather hurts every battler except the matching Gen-1 type.  Dual
  -- types are immune if either type matches, just as the existing
  -- sandstorm/hail rules did.
  -- Through hasType, NOT an inline compare: the engine's Psychic id is
  -- `PSYCHIC_TYPE` while its display name is `PSYCHIC`, and every chipType in
  -- the catalogue is written the readable way. Compared directly, a PSYSTORM
  -- chipped Alakazam -- the one species it exists to spare -- and nothing
  -- errored, because a comparison that is never true looks exactly like a
  -- Pokemon that simply is not immune.
  if hasType(b, def.chipType) then return nil end

  local hurt = math.max(1, math.floor(maxHp * (cfg.residualDamage.fraction or 1 / 16)))
  local floor_ = cfg.residualDamage.canFaint and 0 or 1
  b.mon.hp = math.max(floor_, b.mon.hp - hurt)
  local text = RESIDUAL_TEXT[def.chipType]
    or ("is battered\nby the " .. tostring(def.label or weather) .. "!")
  return displayName(b) .. "\n" .. text
end

-- ------- 4. SPECIAL DEFENCE IN A SANDSTORM
--
-- Applied as a damage reduction on incoming special moves rather than as a
-- stat change, because Gen 1 has ONE Special stat and raising it would
-- raise the attacker's side of it too.

local function sandstormDefence(ctx, weather)
  if weather ~= "SANDSTORM" then return 1 end
  if not Config.battleEffect("defenseBoost") then return 1 end
  if categoryOf(ctx.move) ~= "special" then return 1 end
  local battle = ctx.battle
  local target = ctx.target
      or (battle and ctx.attacker == battle.player and battle.enemy)
      or (battle and battle.player)
  if hasType(target, "ROCK") then return 2 / 3 end
  return 1
end

-- ------- 5. STRONG WINDS
--
-- Moves that would be super effective on a Flying type are cut.  The
-- effectiveness is read out of the vanilla result rather than recomputed,
-- so this stays correct under any type-chart mod.

local function strongWinds(weather, info, target)
  if weather ~= "STRONG_WINDS" then return 1 end
  if not hasType(target, "FLYING") then return 1 end
  local mult = info and info.typeMult
  -- the engine carries effectiveness in tenths (10 = neutral)
  if type(mult) == "number" and mult > 10 then return 0.5 end
  return 1
end

-- ------- installation

function Battle.install()
  detectCapabilities()

  -- The old WEATHER ruleset was retired in 4.18 when battle visuals and
  -- mechanics became explicit independent settings.  Do not register a
  -- selectable ruleset that no longer gates anything: that would be dead UI
  -- and, on Gen 2, a registry write the engine cannot dispatch.

  -- ------- seeding the field from the sky
  --
  -- This is the only path that puts overworld weather into a battle that
  -- would otherwise have none. The old WX RULES gate is retired; current
  -- BATTLE WEATHER FX / DMG switches control visuals and mechanics instead.

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    current = battle
    pcall(function() local C = V.require("Compat"); if C and C.refresh then C.refresh() end end)

    -- Anime Realism + 1st person: leave FPV for the fight (AR battle UI expects 3rd).
    -- Restored on battle.ended when we suspended it.
    Battle._fpSuspendedForAnime = false
    pcall(function()
      local Compat = V.require("Compat")
      local Settings = V.require("Settings")
      if not (Compat and Compat.hasAnimeRealism and Compat.hasAnimeRealism()) then return end
      if not (Settings and Settings.isFirstPerson and Settings.isFirstPerson()) then return end
      if Settings.setFirstPersonEngaged and Settings.setFirstPersonEngaged(false) then
        Battle._fpSuspendedForAnime = true
        pcall(function()
          mod.log:info("Anime Realism battle: switched 1st person → 3rd for fight")
        end)
      end
    end)

    -- Captured HERE, above the seeding early-returns below, because
    -- terrain is not gated on seeding or on being outdoors: a cave or a
    -- tower is exactly where a terrain bonus should still apply.
    --
    -- Terrain is captured independently of weather seeding: caves and
    -- towers are exactly where a terrain bonus may still apply.  The
    -- BATTLE WEATHER DMG setting is the player-facing authority for whether
    -- battle mechanics run at all.
    do
      local ok, Scene = pcall(V.require, "Scene")
      local mapId = (ok and Scene and Scene.now and Scene.now.mapId) or nil
      Battle.mapId = mapId
    end

    -- Once, on the first battle: report any configured map id that is not a
    -- real map.
    Battle.checkMapIds()

    if not battle then return end
    local cfg = Config.get().battle or {}
    if cfg.seedFromOverworld == false then return end
    if not (Battle.effectsEnabled() or Battle.animEnabled()) then return end

    -- Indoors/caves: do not seed overworld weather into indoor battles.
    local Scene = select(2, pcall(V.require, "Scene"))
    local indoors = false
    pcall(function()
      if Scene and Scene.now then
        indoors = Scene.now.indoors and true or false
        -- The old line here was:
        --     if not Scene.now.mapId then indoors = false end
        -- meant to stop the title screen (which has no map) reading as indoors.
        -- But a battle is exactly when the overworld goes unsampleable, so this
        -- also fired every time a battle started underground: no map id ->
        -- "not indoors" -> the sky gets seeded into a cave fight. That is the
        -- reported SS Anne / cave / building bug.
        --
        -- Scene now holds the last known indoors across unsampleable frames, so
        -- the map id is no longer the thing to test. Only distrust it when the
        -- scene has never sampled an overworld at all, which is the real title
        -- screen case.
        if not (Scene.now.mapId or Scene.now.owKnown) then indoors = false end
      end
    end)
    Battle._startedIndoors = indoors
    if indoors then
      battle.field = battle.field or {}
      -- Do not clear weather already set by a move/ability mid-setup
      if not battle.field.weather then
        battle.field.weather = nil
      end
      return
    end

    local weather = nil
    pcall(function()
      local def=(State.current and State.current()) or Types.get(State.id)
      weather = def and def.battle or (def and Types.battleWeather(def.id))
    end)
    -- Outside the physical footprint of a localized front State.current() is
    -- CLEAR even while the regional synoptic source is stormy, so a battle on
    -- the dry side of a map is not incorrectly seeded as rain/storm.
    if not weather and State.current then
      pcall(function() local def=State.current();weather=def and def.battle or nil end)
    end
    if not weather or weather == "" then return end

    battle.field = battle.field or {}
    -- Prefer whatever an ability/move already set
    if battle.field.weather and battle.field.weather ~= "" then
      Battle._lastBattleWeather = battle.field.weather
      return
    end

    -- Gen2Recomped's native Weather module owns retail RAIN/SUN/SANDSTORM/HAIL.
    -- Seed those using its vocabulary. Weather FX-only conditions go in a
    -- sidecar field so the native updater cannot accidentally apply Gen-2
    -- semantics to an unknown custom weather id.
    local hostWeather, native = hostWeatherForSeed(weather)
    if HostRuntime.nativeGen2BattleWeather() and not native then
      battle.field.wxWeather = weather
    else
      battle.field.weather = hostWeather
      if HostRuntime.nativeGen2BattleWeather() then
        if cfg.seededTurns then
          battle.field.weatherTurns = cfg.seededTurns
          battle.field.weatherPermanent = nil
        else
          -- Overworld weather is environmental, not a five-turn move effect.
          battle.field.weatherTurns = nil
          battle.field.weatherPermanent = true
        end
      elseif cfg.seededTurns then
        battle.field.weatherTurns = cfg.seededTurns
      end
    end
    Battle._lastBattleWeather = native and hostWeather or weather
    pcall(function() mod.save:set("battleWeather", Battle._lastBattleWeather) end)
    -- Opening text HERE (same tick as seed) so it is queued as early as possible
    pcall(announce, battle, Battle._lastBattleWeather)
  end)

  -- ------- the opening announcement
  --
  -- A SECOND handler, deliberately, rather than a call inside the seeding
  -- block above. That block returns early in several valid cases -- indoors,
  -- a sky already set by an ability, seeding disabled -- and every one of those
  -- returns is correct for SEEDING and wrong for ANNOUNCING: the player
  -- still needs to know what they are fighting in when some other mod put
  -- the weather there, or when the sky came from a move.
  --
  -- Registered after, so it runs after, so `battle.field.weather` is final
  -- whoever set it.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    if not (Battle.effectsEnabled() or Battle.animEnabled()) then return end
    local w = fieldWeather(battle)
    if (not w or w == "") and type(battle.weather) == "string" then
      w = tostring(battle.weather):upper()
    end
    -- No overworld fallback here. If the sky should carry into an outdoor
    -- fight, the earlier seeding handler has already written the field. An
    -- empty field is intentionally dry (notably indoors/caves), so announcing
    -- the exterior sky here would make UI and mechanics disagree.
    if w and w ~= "" then
      announce(battle, w)
    end
  end)

  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    -- Restore 1st person if we left it for an Anime Realism battle.
    if Battle._fpSuspendedForAnime then
      Battle._fpSuspendedForAnime = false
      pcall(function()
        local Settings = V.require("Settings")
        if Settings and Settings.setFirstPersonEngaged then
          Settings.setFirstPersonEngaged(true)
          pcall(function()
            mod.log:info("Anime Realism battle: restored 1st person after fight")
          end)
        end
      end)
    end
    local last = Battle._lastBattleWeather
    pcall(function()
      if not last and battle then
        last = fieldWeather(battle)
        if not last and type(battle.weather) == "string" then
          last = tostring(battle.weather):upper()
        end
      end
    end)
    current = nil
    Battle.mapId = nil
    Battle._announcedWeather = nil
    pcall(function() mod.save:set("battleWeather", nil) end)

    -- Carry final battle weather into overworld UNLESS player forced a weather in options.
    -- The native Gen2 RAIN/SUN vocabulary is mapped explicitly above.
    if Battle.hostCrystal() then
      Battle._lastBattleWeather = nil
      return
    end
    pcall(function()
      local Settings = V.require("Settings")
      local State = V.require("WeatherState")
      local Types = V.require("Types")
      local forced = nil
      if Settings.alwaysWeather then forced = Settings.alwaysWeather() end
      if not forced then
        local cfg = Config.get()
        if cfg and cfg.force then forced = cfg.force end
      end
      if forced then
        -- Manual / forced weather stays authoritative
        return
      end
      if not last then return end
      local ow = BATTLE_TO_OW[last] or last
      local def = Types.get and Types.get(ow)
      if def and def.id and State then
        if State.adoptWeather then
          State.adoptWeather(def.id, "battle-end")
        elseif State.setWeather then
          State.setWeather(def.id, "battle-end")
          if State.resetDwell then State.resetDwell(def.id) end
          State.softFrom, State.softTo = nil, nil
          State.softT, State.softDur = 0, 0
        else
          State.id = def.id
          State.pinnedBy = "battle-end"
        end
      end
    end)
    Battle._lastBattleWeather = nil
  end)

  -- ------- charge flow
  -- Current Gen1Recomp exposes this decision explicitly.  Returning false
  -- releases Solar Beam immediately in sun/harsh sun; every other move and
  -- weather preserves the answer from earlier hooks / the engine.
  mod.hooks:wrap("battle.charge_required", function(next_, ctx)
    local required = next_(ctx)
    if required == false then return false end
    if Battle.hostCrystal() then return required end
    if solarSkipsCharge(ctx) then return false end
    return required
  end)

  -- ------- damage

  mod.hooks:wrap("battle.damage", function(next_, ctx)
    if Battle.hostCrystal() then return next_(ctx) end
    if not ctx then return next_(ctx) end
    local battle = ctx.battle
    -- The engine names it `user` (BattleState:2226); `attacker` is
    -- accepted too so a mod that re-dispatches with its own ctx still
    -- works.
    local attacker = ctx.user or ctx.attacker
    local weather = Battle.weatherFor(battle, attacker)

    -- Terrain is a property of the MAP, not the sky, so it is computed
    -- before the weather check and the early-out now asks whether there
    -- is anything at all to apply.  Without this a forest bonus would
    -- only work while it happened to be raining.
    local terrain = terrainScale(ctx)
    if not weather and terrain == 1 then return next_(ctx) end

    local scale = terrain
    if weather then
      scale = scale * damageScale(battle, ctx, weather) * sandstormDefence(ctx, weather)
    end

    local damage, info = next_(ctx)
    if type(damage) ~= "number" then return damage, info end

    -- Damage.compute returns 0 for a status move or a move with no power
    -- (Damage.lua:139).  A WATER-type status move under rain would
    -- otherwise be scaled to 0 and then floored UP to 1 by the clamp
    -- below -- turning Withdraw into a one-point attack.  Zero stays zero.
    if damage <= 0 then return damage, info end

    local target = ctx.target
    scale = scale * strongWinds(weather, info, target)

    if scale == 1 then return damage, info end
    -- Pass `info` through untouched or the crit and type-effectiveness
    -- flags vanish from every caller downstream.
    return math.max(1, math.floor(damage * scale)), info
  end)

  -- ------- accuracy

  mod.hooks:wrap("battle.accuracy", function(next_, ctx)
    if Battle.hostCrystal() then return next_(ctx) end
    if not ctx then return next_(ctx) end
    local battle = ctx.battle
    local weather = Battle.weatherFor(battle, ctx.user)
    if not weather then return next_(ctx) end
    local moveId = ctx.move and ctx.move.id
    local moveType = ctx.move and ctx.move.type

    -- the primal nullifications: the move simply does not work
    local dead = NULLIFIED[weather]
    if dead and moveType == dead and Config.battleEffect("typePower") then
      if battle and battle.sayNext then
        local msg = (weather == "HARSH_SUN")
          and "The Water attack\nevaporated in the\nharsh sunlight!"
          or "The Fire attack\nfizzled out in the\nheavy rain!"
        pcall(function() battle:sayNext(msg) end)
      end
      return false
    end

    if Config.battleEffect("accuracy") and moveId then
      local row = ACCURACY[moveId]
      local verdict = row and row[weather]
      if verdict == "always" then return true end
      if type(verdict) == "number" then
        if not rollPercent(battle, verdict) then return false end
        return next_(ctx)
      end
      if weather == "FOG" then
        -- everything is a little harder to land in fog; applied as an
        -- extra independent roll rather than by editing the move's
        -- accuracy, which this hook is not given
        if not rollPercent(battle, math.floor(FOG_ACCURACY * 100)) then
          return false
        end
      end
    end

    -- Sand Veil / Snow Cloak, only when nobody else provides them.
    if Config.battleEffect("evasion") and not Battle.caps.evasion then
      local target = ctx.target
      local ability = abilityOf(battle, target)
      if (ability == "SAND_VEIL" and weather == "SANDSTORM")
          or (ability == "SNOW_CLOAK" and (weather == "HAIL" or weather == "SNOWY")) then
        if rollPercent(battle, 20) then return false end
      end
    end

    return next_(ctx)
  end)

  -- ------- speed
  --
  -- Only when nobody else provides it.  The hook hands over both battlers
  -- and their moves and expects the one that goes first, so the vanilla
  -- answer is taken and then overruled only when exactly one side is
  -- boosted -- which avoids reimplementing priority, ties and the
  -- tie-break roll.

  -- RETURNS A BOOLEAN, NOT A BATTLER.  TurnOrder.firstMover returns
  -- "does `a` go first" (TurnOrder.lua:50-59), and the engine assigns the
  -- hook's result straight into `pFirst`.  Returning a battler table here
  -- was always truthy, so the player would have moved first every time a
  -- weather speed ability was in play -- a corrupted turn order rather
  -- than a missing effect.  It never fired only because the ctx had no
  -- battle to read; both halves are fixed together.
  mod.hooks:wrap("battle.turn_order", function(next_, a, aMove, b, bMove, ctx)
    if Battle.hostCrystal() then return next_(a, aMove, b, bMove, ctx) end
    local first = next_(a, aMove, b, bMove, ctx)
    if Battle.caps.speed or not Config.battleEffect("speed") then return first end
    local battle = (ctx and ctx.battle) or current
    local weather = Battle.weather(battle)
    if not weather then return first end

    local BOOST = {
      CHLOROPHYLL = { SUNNY = true, HARSH_SUN = true },
      SWIFT_SWIM  = { RAINY = true, HEAVY_RAIN = true },
      SAND_RUSH   = { SANDSTORM = true },
      SLUSH_RUSH  = { HAIL = true, SNOWY = true },
    }
    local function boosted(x)
      local ability = abilityOf(battle, x)
      local row = ability and BOOST[ability]
      return row and row[weather] and true or false
    end
    local aFast, bFast = boosted(a), boosted(b)
    -- Only a same-priority turn is reordered, and only when exactly one
    -- side is boosted -- otherwise the vanilla answer already stands.
    if aFast == bFast then return first end
    local aPri = (aMove and aMove.priority) or 0
    local bPri = (bMove and bMove.priority) or 0
    if aPri ~= bPri then return first end
    return aFast and true or false
  end)

  -- ------- residual, healing, and the held-item extenders

  -- Watch mid-battle weather changes (Rain Dance, Sunny Day, etc.)
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle or battle.result then return end
    -- Always track last field weather for post-battle OW handoff
    local fw = fieldWeather(battle) or (battle.weather and tostring(battle.weather):upper()) or nil
    if fw then
      Battle._lastBattleWeather = fw
      if Battle.effectsEnabled() or Battle.animEnabled() then
        -- Re-announce only if identity changed (Rain Dance mid-fight, etc.)
        if battle.field and battle.field.wxAnnouncedFor ~= visualWeather(fw) then
          pcall(announce, battle, fw)
        end
      end
    end
  end)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle or battle.result then return end
    local cfg = Config.get().battle
    if not Battle.effectsEnabled() then return end

    -- AI Rivals and other documented double-battle decorators expose the
    -- second active battlers as player2/enemy2. Visit all four, once each;
    -- ordinary battles still take the same two-element path.
    local seen = {}
    local battlers = {}
    for _, key in ipairs({ "player", "enemy", "player2", "enemy2" }) do
      if battle[key] then battlers[#battlers + 1] = battle[key] end
    end
    for _, b in ipairs(battlers) do
      if b and not seen[b] then
        seen[b] = true
        local weather = Battle.weatherFor(battle, b)
        if weather then
          local ok, message = pcall(residualFor, battle, b, weather)
          if ok and message and battle.sayNext then
            pcall(function() battle:sayNext(message) end)
            -- The engine's own residual sweep has already run and called
            -- onFaint for anything it killed; ours runs after it, so a
            -- knockout here is ours to report.
            if b.mon.hp <= 0 and battle.onFaint then
              pcall(function() battle:onFaint(b) end)
            end
          end
        end
      end
    end
  end)

  -- Weather rocks: a move that set the weather this turn gets extra turns
  -- if its user is holding the matching rock.
  mod.events:on("battle.move_used", function(ev)
    if not Config.battleEffect("heldItems") then return end
    local battle = ev and ev.battle
    local field = battle and battle.field
    if not (field and field.weather and field.weatherTurns) then return end
    local user = ev.user or ev.battler or ev.attacker
    local item = heldItem(user)
    if not item then return end
    local cfg = Config.get().battle.items
    if cfg.extenders[item] == field.weather then
      field.weatherTurns = field.weatherTurns + (cfg.extendBy or 3)
      -- once per set, not once per turn: the flag rides on the field and
      -- the field is rebuilt whenever the weather changes
      if field.weatherRockApplied ~= field.weather then
        field.weatherRockApplied = field.weather
      end
    end
  end)

  return true
end

-- ------- for the debug row and the tests

-- What the debug row prints for `btl`.  A bare "-" was the single most
-- expensive thing on this readout: "the sky changes but the battle is dry"
-- has at least four different causes and the row named none of them, so the
-- answer was always "read Battle.lua".  Now it says which gate closed, in
-- the same shape `art:behind!not-installed` and `terr:off` already use.
--
-- `!` is a gate that actually stopped this battle. Current releases use
-- independent BATTLE WEATHER FX / DMG switches; the pre-4.18 WX RULES
-- gate is retired and is not part of the active battle contract.
-- ------- map ids that do not exist
--
-- A terrain bonus or location override keyed to a map that does not exist
-- does nothing at all, silently: no error, no warning, and no way to tell it
-- apart from one that is working but has not come up yet. Not hypothetical --
-- the bundled table shipped `POKEMONTOWER_1F` (the engine calls it
-- `POKEMON_TOWER_1F`) and seven Ghost bonuses were dead for a release with
-- nothing saying so.
--
-- Read LAZILY on the first battle rather than at config-load time: config
-- loads before the dataset is guaranteed merged, and comparing against an
-- empty registry would report every id as unknown.
--
-- On the table rather than a local so the suite can re-arm it; the mod
-- itself only ever sets it true.
Battle.mapIdsChecked = false

function Battle.checkMapIds()
  if Battle.mapIdsChecked then return end
  Battle.mapIdsChecked = true

  local known, count = {}, 0
  local ok = pcall(function()
    for id in mod.content.maps:each() do
      known[id] = true
      count = count + 1
    end
  end)
  if not ok or count == 0 then return end   -- cannot say; stay quiet

  -- Ids the mod SHIPS, which are deliberately cross-generation: the terrain
  -- table carries Kanto rows and Johto rows together because only 76 of Gen
  -- 1's 222 maps exist on Gold. Whichever set is not the running game's will
  -- never match, and that is correct rather than a mistake -- so warning
  -- about them would mean every Kanto boot complains about six Johto ids and
  -- every Gold boot about eight Kanto ones, which is how a useful warning
  -- becomes noise people learn to ignore.
  --
  -- Both sets are verified against the engine's own manifests
  -- (tools/rom_manifest.json and tools/rom_manifest_gold.json), so the check
  -- that matters is the one on ids a PLAYER added.
  local BUNDLED = Config.bundledMapIds and Config.bundledMapIds() or {}

  local function report(label, tbl)
    if type(tbl) ~= "table" then return end
    local bad, good = {}, 0
    for mapId in pairs(tbl) do
      if type(mapId) == "string" then
        if known[mapId] then good = good + 1
        elseif not BUNDLED[mapId] then bad[#bad + 1] = mapId end
      end
    end
    -- If NOT ONE configured id is a known map, the likelier explanation is
    -- that this is not the dataset those ids were written for -- a trimmed
    -- or fixture set, or another region -- than that every single one is a
    -- typo. Warning about all of them there would train people to ignore the
    -- warning. The stated cost: a config with exactly one entry and a typo in
    -- it gets nothing. The case this exists for, one bad id among several
    -- good ones, is still caught.
    if good == 0 then return end
    table.sort(bad)
    for _, mapId in ipairs(bad) do
      mod.log:warn(
        "%s: %q is not a map id in this dataset, so it will never match. "
        .. "Check it against the DEBUG HUD's map: field.", label, mapId)
    end
  end

  local cfg = Config.get()
  report("battle.terrain", cfg.battle and cfg.battle.terrain)
  -- `locations` has the same failure mode and predates the terrain table, so
  -- it is checked here too rather than left as the one silent one.
  report("locations", cfg.locations)
end


  -- Battle weather visuals (particles). Gated by BATTLE WX FX every frame.
  pcall(function()
    local BD = V.require("BattleDraw")
    if not BD or mod._wxBattleOverlay then return end
    mod._wxBattleOverlay = true
    -- Priority 50: below Colosseum UI / gen3_battle_ui (9000) so UI draws after
    -- chain returns; we still call next first, then paint weather under them.
    local wrapFn = function(next_, battle, ...)
      -- Lua 5.1/LuaJIT: nested functions cannot use `...` — capture first.
      local va = { ... }
      local underUI = false
      pcall(function()
        local Compat = V.require("Compat")
        if Compat and Compat.battleProfile then
          underUI = Compat.battleProfile().weatherUnderUI == true
        end
      end)
      local function paintWeather()
        if not battle then return end
        -- A nonopaque voxel battle is literally the overworld 3D scene. Let the
        -- world atmosphere own it; painting BattleDraw here would stack a flat
        -- 2D weather sheet over the correctly rendered 3D storm.
        if Battle.world3dWeatherOwns and Battle.world3dWeatherOwns() then
          -- DramalessAtmos advances and consumes BattleDraw during the normal
          -- frame update. This overlay must therefore do nothing: no duplicate
          -- 2D draw and no second easing tick.
          return
        end
        if not Battle.animEnabled() then
          pcall(function() BD.reset() end)
          return
        end
        pcall(function()
          local g = love.graphics
          local prevCanvas, prevBlend, prevAMode
          local pr, pg, pb, pa
          pcall(function()
            prevCanvas = g.getCanvas and g.getCanvas() or nil
            prevBlend, prevAMode = g.getBlendMode()
            pr, pg, pb, pa = g.getColor()
          end)
          BD.tick(1 / 60, battle)
          BD.draw(1 / 60, battle)
          pcall(function()
            if g.setCanvas then g.setCanvas(prevCanvas) end
            if prevBlend then g.setBlendMode(prevBlend, prevAMode) end
            if pr then g.setColor(pr, pg, pb, pa) end
          end)
        end)
      end
      local function runNext()
        if type(next_) ~= "function" then return end
        local okN, errN = pcall(function()
          return next_(battle, unpack(va))
        end)
        if not okN then
          pcall(function() mod.log:warn("battle.overlay chain: %s", tostring(errN)) end)
        end
      end
      -- With Anime Realism: weather first, their chrome/UI second (on top).
      if underUI then
        paintWeather()
        runNext()
      else
        runNext()
        paintWeather()
      end
    end
    local okW = pcall(function()
      mod.hooks:wrap("battle.overlay", wrapFn, 50)
    end)
    if not okW then
      mod.hooks:wrap("battle.overlay", wrapFn)
    end
  end)


function Battle.describe()
  local w = mod.save:get("battleWeather", nil)
  if w then return w end

  local cfg = Config.get().battle
  if not cfg.enabled then return "-!battle-off" end
  if not cfg.seedFromOverworld then return "-!seed-off" end

  local ok, Scene = pcall(V.require, "Scene")
  if ok and Scene and Scene.now and Scene.now.indoors then
    return "-!indoors"
  end

  return "-"
end

return Battle
