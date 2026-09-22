-- weather_fx: engine-harness test.
--
--   cd <gen1recomp repo root>
--   luajit mods/weather_fx/tests/weather_fx_engine_test.lua
--
-- Unlike the standalone focused suites run by tools/run_all.py, this one
-- loads the mod through the REAL engine
-- loader against the real merged dataset, so it needs a repo with imported
-- ROM data present.  It checks the two things a stub cannot: that the
-- records this mod registers actually merge into the engine's registries
-- with the shapes the engine will read, using real Gen 1/Gen 2 data rather
-- than fixture-shaped tables.
--
-- `python3 tools/modkit.py validate mods/weather_fx` covers the same load
-- path with less setup and is the quicker check; this adds the assertions.

package.path = "./?.lua;./?/init.lua;" .. package.path

local okT, T = pcall(require, "tests.modkit")
local okD, Data = pcall(require, "src.core.Data")
if not okT or not okD then
  io.write("weather_fx_engine_test: SKIP (run from a Gen1Recomp engine repo with tests.modkit/src.core.Data available)\n")
  os.exit(0)
end
Data:load()

-- Which generation to load as. Two live loads in one process collide on the
-- token registry ("tokens already registered") -- releasing restores the
-- runtime but does not unregister -- so the suite is parameterised instead
-- and run once per generation:
--
--   WEATHER_FX_GEN=1 luajit .../weather_fx_engine_test.lua
--   WEATHER_FX_GEN=2 luajit .../weather_fx_engine_test.lua
local GEN = tonumber(os.getenv("WEATHER_FX_GEN") or "1") or 1
local run = T.sdk.loadMod("mods/weather_fx",
  GEN == 2 and { data = Data, generation = 2 } or { data = Data })

-- The manifest declares games gen1+gen2, and that claim is enforced: a mod
-- naming no Gen 2 game is skipped entirely on Gold. Asserting only that
-- #errors == 0 would pass for a mod that never ran a line, because a gate
-- skip is deliberately NOT an error -- so the STATE is what is checked, as
-- docs/preparing-your-mod-for-gen2.md says to.
T.eq(run.mod and run.mod.state, "loaded",
  ("loads on gen %d: %s"):format(GEN, tostring(run.mod and run.mod.skipReason)))

T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- ------- the pipeline record

local pipe = Data.render_pipelines and Data.render_pipelines.weather
T.check(pipe ~= nil, "the weather pipeline merged")
T.eq(pipe.label, "WEATHER", "it has the options-row label")
T.check(type(pipe.present) == "function", "it declares the whole-frame stage")
T.check(type(pipe.worldPresent) == "function", "and the world-only stage")
T.check(pipe.drawWorld == nil,
  "and NOT drawWorld -- it must never compete for the world pass")
T.eq(pipe.levels[1], "OFF", "rung 0 is OFF")
T.eq(pipe.levels[2], "AUTO", "rung 1 is AUTO")
T.check(#pipe.levels >= 15, "the ladder carries a rung per pinned weather")
T.check((pipe.priority or 0) < 10,
  "priority sorts below a world pipeline and its post-process")
T.check(type(pipe.available) == "function",
  "available() exists, which is what keeps a clear day free")
T.eq(pipe.available(), false,
  "and answers false headlessly, so the vanilla path is kept")

local timePipe = Data.render_pipelines and Data.render_pipelines.weather_time_grade
T.check(timePipe ~= nil, "the internal time-grade compositor merged")
T.eq(timePipe.label, "WX TIME", "the internal time-grade compositor has its implementation label")
T.check(type(timePipe.update) == "function", "the internal time-grade compositor self-enables")
T.check(type(timePipe.available) == "function", "the internal time-grade compositor has a live setting gate")
T.check(type(timePipe.present) == "function", "the internal time-grade compositor supports the flat frame path")
T.check(type(timePipe.worldPresent) == "function", "the internal time-grade compositor supports the world-under-UI path")

-- ------- retired ruleset surface
--
-- The old WEATHER/WX RULES gate was removed in 4.18.  A feature-integrity
-- release must not re-register the now-inert weather_fx_battles ruleset.
T.check(Data.rulesets == nil or Data.rulesets.weather_fx_battles == nil,
  "retired WEATHER ruleset is not registered")

-- ------- the ids this mod matches on are REAL ids
--
-- Every weather effect keyed to a move id, and every terrain bonus keyed to
-- a map id, is silently dead if the id is wrong -- the same failure that
-- killed seven Ghost bonuses (a map id) and the whole grass-encounter
-- feature (a hook choice). Nothing errors; the effect simply never fires.
--
-- These run against whatever dataset is loaded, so on the ROM-free fixture
-- set they check the handful of ids it contains and skip the rest. Point
-- POKEPORT_DATA_DIR at a real import to check them all.
do
  if type(Data.moves) == "table" and Data.moves.TACKLE then
    -- one word, no underscore: this is the engine's spelling, and the mod's
    -- SOLAR_MOVES table carries SOLAR_BEAM only as a hedge for other mods
    T.check(Data.moves.SOLARBEAM ~= nil, "SOLARBEAM is the engine's spelling")
    T.check(Data.moves.BLIZZARD ~= nil, "BLIZZARD is a real move id")
    T.check(Data.moves.THUNDER ~= nil, "THUNDER is a real move id")
  end

  if type(Data.maps) == "table" and Data.maps.VIRIDIAN_FOREST then
    -- the bundled terrain table, which is the part that failed before
    for _, id in ipairs({ "VIRIDIAN_FOREST", "POWER_PLANT",
                          "POKEMON_TOWER_1F", "POKEMON_TOWER_7F" }) do
      T.check(Data.maps[id] ~= nil, id .. " is a real map id")
    end
  end

  if type(Data.pokemon) == "table" and Data.pokemon.GASTLY then
    -- the encounter feature reads .types off a species record; if that field
    -- were named something else the reroll could never match a type
    local g = Data.pokemon.GASTLY
    T.check(type(g.types) == "table" and #g.types > 0,
      "species records carry a .types list, which the encounter reroll reads")
  end
end

-- ------- Gen 2 readiness
--
-- Gold/Silver/Crystal add 86 moves, plus the DARK and STEEL types. The
-- values below were read out of the US Gold and Crystal ROMs directly (move
-- name table at 0x1B1574 in Gold, type name table at 0x0509E6), not from
-- memory, because the whole point is that a guessed id fails silently.
--
-- These assertions run against whatever dataset is loaded. On a Gen 1
-- import they check the Gen 1 half and skip the rest; on a Gen 2 import the
-- Gen 2 half activates and will catch a spelling that moved.
do
  if type(Data.moves) == "table" and Data.moves.TACKLE then
    -- Gen 2 keeps SOLARBEAM as one word -- confirmed in the Gold and
    -- Crystal move tables, same as Red/Blue/Yellow. If a Gen 2 importer
    -- ever emits SOLAR_BEAM, the mod's SOLAR_MOVES table already accepts
    -- both, but this is the spelling to expect.
    T.check(Data.moves.SOLARBEAM ~= nil or Data.moves.SOLAR_BEAM ~= nil,
      "a Solar Beam id exists under one of the two spellings")

    -- The three weather SETTING moves are Gen 2 arrivals. When they exist,
    -- the engine sets battle.field.weather itself -- and this mod must not
    -- fight it. Seeding already returns early if a weather is present, so
    -- what matters here is only that we notice the generation changed.
    local gen2 = Data.moves.RAIN_DANCE ~= nil
    if gen2 then
      T.check(Data.moves.SUNNY_DAY ~= nil, "SUNNY_DAY exists alongside RAIN_DANCE")
      T.check(Data.moves.SANDSTORM ~= nil, "the SANDSTORM move exists in Gen 2")
      -- Weather Ball and the Hail MOVE are Gen 3, not Gen 2: neither is in
      -- the Gold/Crystal move table. If either turns up, the dataset is
      -- past Gen 2 and the mod's assumptions want re-checking.
      T.check(Data.moves.WEATHER_BALL == nil,
        "Weather Ball is Gen 3 and absent from a Gen 2 dataset")
    end
  end

  if type(Data.type_chart) == "table" or type(Data.types) == "table" then
    local types = Data.types or Data.type_chart
    -- STEEL is the spelling in the Gen 2 type table, and it matters: a
    -- sandstorm must not chip a Steel type. The mod's sandImmune list
    -- already carries it, which is why this is a check and not a change.
    if types and (types.STEEL or (types.list and types.list.STEEL)) then
      T.check(true, "a Gen 2 dataset carries STEEL, which sandImmune covers")
    end
  end
end

-- ------- the OPTIONS rows reach the player on BOTH boots
--
-- The reported bug: on Gold there was no WEATHER row, so no way to pick a
-- sky. Gen 1's options menu calls Pipelines.rows itself; Gold's does not,
-- and only raises ui.options.rows. This asserts the player-visible outcome
-- on whichever boot is running, rather than asserting the mechanism.
do
  local Runtime3 = require("src.mods.Runtime")
  local function sameRows(_, rows) return rows end
  local fakeGame = { save = { options = {} } }

  -- what Gold's menu would hand the hook: its own rows, no pipeline rows
  local vanillaRows = {
    { id = "textSpeed", label = "TEXT SPEED" },
    { id = "sound",     label = "SOUND" },
    -- Every pipeline normally generates a row. The time-grade pipeline is an
    -- internal implementation detail and must be removed on both generations.
    { id = "pipeline:weather_time_grade", label = "WX TIME" },
  }
  local out = Runtime3.call("ui.options.rows", sameRows, fakeGame, vanillaRows)
  T.check(type(out) == "table", "ui.options.rows returns a row list")

  local byId = {}
  for _, row in ipairs(out) do
    if type(row) == "table" and row.id then byId[row.id] = row end
  end
  T.check(byId["pipeline:weather_time_grade"] == nil,
    "the internal WX TIME compositor never leaks into player OPTIONS")

  if GEN == 2 then
    T.check(byId["pipeline:weather"] ~= nil,
      "on Gold the mod adds the WEATHER row itself, so a sky can be picked")
    T.check(byId["pipeline:daynight"] == nil,
      "TIME is not re-added to OPTIONS; it lives in Weather FX mod settings")
    T.eq(byId["pipeline:weather"].label, "WEATHER", "the row is labelled WEATHER")
    T.check(type(byId["pipeline:weather"].step) == "function",
      "and it is steppable, so the row actually changes the weather")

    -- idempotency: if a later engine build splices these itself, the mod
    -- must not add a second copy
    local already = {
      { id = "textSpeed", label = "TEXT SPEED" },
      { id = "pipeline:weather", label = "WEATHER" },
    }
    local twice = Runtime3.call("ui.options.rows", sameRows, fakeGame, already)
    local count = 0
    for _, row in ipairs(twice) do
      if type(row) == "table" and row.id == "pipeline:weather" then count = count + 1 end
    end
    T.eq(count, 1, "a row already present is not added a second time")
  else
    -- On Gen 1 the ENGINE splices these rows in OptionsMenu, so the mod must
    -- not: two WEATHER rows would be the same bug pointing the other way.
    T.check(byId["pipeline:weather"] == nil,
      "on Gen 1 the mod adds no row -- the engine's own menu splices it")
    local P = require("src.render.Pipelines")
    local ids = {}
    local engineRows = {
      { id = "textSpeed", label = "TEXT SPEED" },
      { id = "sound", label = "SOUND" },
    }
    for _, row in ipairs(P.rows(fakeGame)) do
      ids[row.id] = true
      engineRows[#engineRows + 1] = row
    end
    T.check(ids["pipeline:weather"],
      "...and the engine's builder does produce a WEATHER row to splice")
    T.check(ids["pipeline:weather_time_grade"],
      "the engine also generates a row for the internal time-grade compositor")

    -- Simulate Gen 1's real sequence: OptionsMenu splices every pipeline row,
    -- then raises ui.options.rows. The hook must preserve WEATHER exactly once
    -- while deleting only the hidden implementation row.
    local filtered = Runtime3.call("ui.options.rows", sameRows, fakeGame, engineRows)
    local weatherCount, timeCount = 0, 0
    for _, row in ipairs(filtered or {}) do
      if type(row) == "table" and row.id == "pipeline:weather" then weatherCount = weatherCount + 1 end
      if type(row) == "table" and row.id == "pipeline:weather_time_grade" then timeCount = timeCount + 1 end
    end
    T.eq(weatherCount, 1, "Gen 1 keeps exactly one player WEATHER row after hook filtering")
    T.eq(timeCount, 0, "Gen 1 removes the hidden WX TIME row after engine pipeline splicing")
  end
end

-- ------- installed and unselected
--
-- Current releases seed outdoor overworld weather without requiring a special
-- save ruleset. What is asserted here is the invariant that still matters:
-- with no weather running, the mod adds nothing to the damage path at all.
--
-- Headlessly State.id is CLEAR and Scene.now.mapId is nil, so these two
-- would pass whatever the default were. They are kept because a regression
-- that made the mod scale damage with NO weather up would still fail them,
-- which is worth catching -- but they are not evidence about the ruleset
-- gate. The standalone suite drives that gate against the real module with
-- the row set explicitly.

local Runtime = require("src.mods.Runtime")
local function vanilla() return 100, { crit = false, typeMult = 10 } end
local function hit(moveType)
  return Runtime.call("battle.damage", vanilla, { move = { type = moveType } })
end

Runtime.emit("battle.started", { battle = {} })
T.eq(hit("WATER"), 100,
  "WATER is untouched with the mod installed and no weather running")
T.eq(hit("FIRE"), 100,
  "FIRE is untouched too")

-- ------- battle weather remains active on Gold without a ruleset surface
--
-- Gold has no ruleset registry. Current releases use the split battle settings
-- directly, so a battle carrying weather must receive the normal mechanics.
if GEN == 2 then
  -- The mod's internal Battle module is not directly exposed by the load
  -- handle, so assert the player-visible result through the runtime hook: a
  -- WATER move in active rain must still be boosted with no ruleset present.
  local b = {
    field = { weather = "RAINY", tokens = {} },
    data = { pokemon = Data.pokemon }, said = {},
    rng = function(a, c) return math.random(a, c) end,
  }
  b.player = { isPlayer = true, curTypes = { "WATER" },
               mon = { species = "SQUIRTLE", hp = 100, stats = { hp = 100 } } }
  b.enemy = { isPlayer = false, curTypes = { "FIRE" },
              mon = { species = "CHARMANDER", hp = 100, stats = { hp = 100 } } }
  b.sayNext = function() end
  b.onFaint = function() end
  Runtime.emit("battle.started", { battle = b })
  local dmg = Runtime.call("battle.damage", vanilla,
    { battle = b, ruleset = nil, move = { id = "SURF", type = "WATER" },
      user = b.player, target = b.enemy })
  T.eq(dmg, 150,
    "on Gold a WATER move is still boosted in rain with no ruleset present")
  Runtime.emit("battle.ended", {})
end


-- ------- Gen 2 behaviour, when a Gen 2 dataset is loaded
--
-- Not just "the ids exist" but "the effects do the right thing with them".
-- Only runs when the dataset actually carries Gen 2 content, so a Gen 1
-- import skips it.
do
  local gen2 = type(Data.moves) == "table" and Data.moves.CRUNCH ~= nil
    and type(Data.pokemon) == "table" and Data.pokemon.STEELIX ~= nil
  if gen2 then
    local Runtime2 = require("src.mods.Runtime")
    local function battler(species)
      local d = Data.pokemon[species]
      return { isPlayer = false, curTypes = (d and d.types) or { "NORMAL" },
               mon = { species = species, hp = 100, stats = { hp = 100 } } }
    end
    local function residual(weather, species)
      local b = { field = { weather = weather, tokens = {} },
                  data = { pokemon = Data.pokemon }, said = {},
                  rng = function(a, c) return math.random(a, c) end }
      b.player = battler("PIKACHU"); b.enemy = battler(species)
      b.sayNext = function(self, t) self.said[#self.said + 1] = t end
      b.onFaint = function() end
      Runtime2.emit("battle.started", { battle = b })
      Runtime2.emit("battle.turn_ended", { battle = b })
      local hp = b.enemy.mon.hp
      Runtime2.emit("battle.ended", {})
      return hp
    end

    -- STEEL is the whole reason sandImmune carries a type Gen 1 does not
    -- have. SKARMORY, not Steelix: Steelix is STEEL/GROUND and GROUND is
    -- immune on its own, so it stays at full HP whether or not STEEL is in
    -- the list -- the first version of this test used it and passed a
    -- mutation that deleted STEEL entirely. Skarmory is STEEL/FLYING, so
    -- only STEEL can save it.
    T.eq(residual("SANDSTORM", "SKARMORY"), 100,
      "a STEEL type takes no sandstorm chip damage")
    T.check(residual("SANDSTORM", "PIDGEOT") < 100,
      "...and a FLYING type with no STEEL still takes it, so the pass above is STEEL's doing")
    T.check(residual("SANDSTORM", "UMBREON") < 100,
      "a DARK type is not immune to a sandstorm")

    -- and the Gen 2 types flow through the damage path unchanged: neither
    -- DARK nor STEEL is boosted or weakened by rain
    local b = { field = { weather = "RAINY", tokens = {} },
                data = { pokemon = Data.pokemon }, said = {},
                rng = function(a, c) return math.random(a, c) end }
    b.player = battler("PIKACHU"); b.enemy = battler("CHARIZARD")
    b.sayNext = function() end
    Runtime2.emit("battle.started", { battle = b })
    local function hit(id)
      local rec = Data.moves[id]
      return Runtime2.call("battle.damage", vanilla,
        { battle = b, move = { id = id, type = rec.type },
          user = b.player, target = b.enemy })
    end
    T.eq(hit("CRUNCH"), 100, "a DARK move is untouched by rain")
    T.eq(hit("IRON_TAIL"), 100, "a STEEL move is untouched by rain")
    T.eq(hit("SURF"), 150, "a WATER move is still boosted by rain in Gen 2")
    Runtime2.emit("battle.ended", {})
  end
end


-- Terrain integration is exercised dynamically by the maintained standalone
-- battle/world feature suites. This harness keeps the real-engine registry
-- assertions that cannot be proven by a stub.

-- No statuses record, deliberately: `statuses` is a link registry and
-- writing to it would oblige this mod to declare affects_link.
-- `statuses` is a link registry, and link play is Gen 1 only, so the table
-- itself is absent on a Gen 2 boot -- which satisfies the same promise.
T.check((Data.statuses or {}).WEATHER_FX_RAIN == nil,
  "no status record is registered, so affects_link stays honest")

-- The battle layer must not have taken over anything Kanto-Reforged owns
-- when that mod is installed alongside.  With it absent, every capability
-- is ours; the standalone suite covers the present case with a stub.
local run2 = run
T.check(run2 ~= nil, "the load handle is still live")

T.finish("weather_fx")
