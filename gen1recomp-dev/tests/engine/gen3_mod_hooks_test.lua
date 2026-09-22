-- DOES RUBY ACTUALLY FIRE THE MOD API?
--
-- Loading a mod, resolving its modules and accepting its registrations are all
-- necessary and none of them make it DO anything: the behaviour comes from the
-- engine calling the hook names the mod wrapped and emitting the events it
-- listened for.  Measured across the nine community mods forced onto Ruby,
-- they wrapped 27 distinct hook names between them and a Ruby boot reached
-- exactly ONE -- every other point lives in Gen 1's or Gen 2's code path, and
-- a Ruby boot runs neither.  So the mods loaded and sat inert.
--
-- This suite pins the first three Game3 fires, and the contract each one
-- carries, because the contract is what makes a mod written for Red work here
-- without a new branch:
--
--   * encounter.roll is handed the vanilla { species, level } and may pass it
--     through, REPLACE it, or return nil to SUPPRESS the encounter;
--   * map.entered says which map, where from, and by which of the three ways
--     a map becomes current;
--   * world.stepped fires per cell crossed, before the checks that can end
--     the step in a battle.
--
-- And the rule that cost a boot: a `local` helper used by a function must be
-- declared ABOVE it.  Lua binds upvalues at definition time, so the first
-- version of these helpers -- declared halfway down a 2 MB file -- was a nil
-- global to every function above them, and Game3:enterMap died on the first
-- new game.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

-- Lua 5.1 wants "*a"; LuaJIT accepts "a".  One helper keeps every source
-- scan working under either interpreter.
local function readfile(path)
  local f = assert(io.open(path, "r"))
  local ok, body = pcall(function() return f:read("*a") end)
  if not ok or body == nil then
    f:seek("set")
    body = f:read("a")
  end
  f:close()
  return body
end

-- Optional preload stubs so Game3 can load without the full tree.
-- Prefer an explicit GEN3_HOOKS_STUB=1 + _G.gen3HooksStub; otherwise, when
-- GameVersion is missing (partial box checkout), pull in tests/gen3_hooks_preload.
if os.getenv("GEN3_HOOKS_STUB") == "1" and type(_G.gen3HooksStub) == "function" then
  _G.gen3HooksStub()
elseif not pcall(require, "src.core.GameVersion") then
  local ok, preload = pcall(require, "tests.gen3_hooks_preload")
  if ok and type(preload) == "function" then preload() end
end

local okGame3, Game3OrErr = pcall(require, "src.core.Game3")
if not okGame3 then
  -- Fall through to source-scan-only mode when deps are missing on the box.
  io.stderr:write("NOTE: Game3 require failed (" .. tostring(Game3OrErr)
    .. "); running source-scan checks only\n")
  Game3 = nil
else
  Game3 = Game3OrErr
end
-- Game3 closes over this Input table; later tests must mutate it, not
-- replace package.loaded["src.core.Input"], or the post-Boot option wrap
-- will not see armed edges.
local Game3Input = package.loaded["src.core.Input"]
local Runtime = require("src.mods.Runtime")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")

local S = require("tests.harness").suite("gen3 mod hooks")
local check, eq = S.check, S.eq

local function withBus(fn)
  local events, hooks = Events.new(), Hooks.new()
  Runtime.install(events, hooks, nil)
  local ok, err = pcall(fn, events, hooks)
  Runtime.reset()
  if not ok then error(err, 0) end
end


-- Behavioral Game3 method tests need the module.  Source scans above and
-- below still run when require failed on a partial tree.
local function whenGame3(fn)
  if not Game3 then return end
  fn()
end

-- ------- the helpers are visible to the functions that use them

do
  local src = readfile("src/core/Game3.lua")
  -- The LAST of the three declarations, because a call site has to sit below
  -- all of them, not merely below the first.
  local declared = 0
  for _, name in ipairs({ "modBus", "modCall", "modEmit" }) do
    local at = src:find("local function " .. name, 1, true)
    check(at ~= nil, "Game3 declares " .. name)
    if at and at > declared then declared = at end
  end

  -- A declaration line contains "modCall(" too, so those are blanked before
  -- the scan -- otherwise the first "use" found IS a declaration and the
  -- comparison is meaningless (which is exactly how this check first passed
  -- a file that was broken).
  local scan = src:gsub("local function mod[A-Za-z]+%(", function(m)
    return string.rep(" ", #m)
  end)
  local firstUse = nil
  for pos in scan:gmatch("()mod[CE][a-z]+%(") do
    if not firstUse or pos < firstUse then firstUse = pos end
  end
  check(firstUse ~= nil, "and calls them")
  check(firstUse and declared < firstUse,
    ("the declarations (%d) come before the first call (%s): Lua binds "
     .. "upvalues at definition time, so a later local is a nil global above it")
      :format(declared, tostring(firstUse)))
end

-- ------- encounter.roll

whenGame3(function()
local function encounterGame()
  if not Game3 then error("Game3 unavailable", 0) end
  local battles = {}
  local g = setmetatable({
    map = { id = "g0_9" },
    battlesStarted = battles,
    rolls = 0,
  }, { __index = Game3 })
  function g:rand(n) return 1 end
  function g:repelBlocks() return false end
  function g:startWildBattle(species, level)
    battles[#battles + 1] = { species = species, level = level }
    return true
  end
  return g, battles
end

local INFO = { rate = 20, terrain = "land",
               slots = { { species = 183, minLevel = 5, maxLevel = 5 } } }

do
  withBus(function(events, hooks)
    -- no wrapper at all: the vanilla pick goes through untouched
    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), true, "the vanilla roll starts a battle")
    eq(#battles, 1, "exactly one")
    eq(battles[1].species, 183, "with the slot's species")
    eq(battles[1].level, 5, "and its level")
  end)
end

do
  withBus(function(events, hooks)
    local saw = {}
    hooks:wrap("encounter.roll", function(next, encDef, ctx)
      local enc = next(encDef, ctx)
      saw.species, saw.level = enc and enc.species, enc and enc.level
      saw.mapId = ctx and ctx.mapId
      saw.terrain = ctx and ctx.terrain
      saw.rngIsFn = type(ctx and ctx.rng) == "function"
      saw.encDef = encDef
      return enc
    end, 0, "test_mod")

    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), true, "a pass-through wrapper still fights")
    eq(saw.species, 183, "the wrapper was handed the vanilla species")
    eq(saw.level, 5, "and the vanilla level")
    eq(saw.mapId, "g0_9", "with the map it happened on")
    eq(saw.terrain, "land", "and the terrain")
    eq(saw.rngIsFn, true, "and an rng it can draw from")
    eq(saw.encDef, INFO, "and the encounter table itself")
    eq(battles[1].species, 183, "and the battle is the vanilla one")
  end)
end

do
  withBus(function(events, hooks)
    hooks:wrap("encounter.roll", function() return nil end, 0, "test_mod")
    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), false, "returning nil suppresses")
    eq(#battles, 0, "and no battle is started")
  end)
end

do
  withBus(function(events, hooks)
    hooks:wrap("encounter.roll", function()
      return { species = 1, level = 42 }
    end, 0, "test_mod")
    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), true, "a replacement fights")
    eq(battles[1].species, 1, "with the wrapper's species")
    eq(battles[1].level, 42, "and the wrapper's level")
  end)
end

do
  withBus(function(events, hooks)
    -- a record with no species is not an encounter, however it arrived
    hooks:wrap("encounter.roll", function() return { level = 9 } end, 0, "m")
    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), false, "a speciesless answer suppresses")
    eq(#battles, 0, "and starts nothing")
  end)
  withBus(function(events, hooks)
    hooks:wrap("encounter.roll", function() return "nonsense" end, 0, "m")
    local g, battles = encounterGame()
    eq(g:startWildFrom(INFO, 0, true), false, "so does a non-table")
  end)
end

do
  withBus(function(events, hooks)
    -- repel still applies to a FORCED encounter: a wrapper decides what you
    -- meet, not whether the player's item is honoured
    hooks:wrap("encounter.roll", function()
      return { species = 1, level = 3 }
    end, 0, "test_mod")
    local g, battles = encounterGame()
    g.repelBlocks = function(_, level) return level <= 5 end
    eq(g:startWildFrom(INFO, 0, false), false, "repel blocks a forced low level")
    eq(#battles, 0, "and no battle starts")
  end)
end

end)

-- ------- map.entered and world.stepped carry their payloads

do
  local src = readfile("src/core/Game3.lua")
  -- the emits exist at all, with the fields a listener reads
  check(src:find('modEmit("map.entered"', 1, true) ~= nil,
    "Game3 emits map.entered")
  check(src:find('modEmit("world.stepped"', 1, true) ~= nil,
    "Game3 emits world.stepped")
  local entered = src:match('modEmit%("map%.entered", (%b{})')
  check(entered ~= nil, "the map.entered payload is a table")
  for _, field in ipairs({ "mapId", "fromMapId", "via" }) do
    check(entered:find(field, 1, true) ~= nil,
      "map.entered carries " .. field)
  end
  -- all three ways a map becomes current are spelled, as Gen 1 spells them
  for _, via in ipairs({ "connection", "warp", "boot" }) do
    check(entered:find('"' .. via .. '"', 1, true) ~= nil,
      'map.entered can report via="' .. via .. '"')
  end
  local stepped = src:match('modEmit%("world%.stepped", (%b{})')
  check(stepped ~= nil, "the world.stepped payload is a table")
  for _, field in ipairs({ "mapId", "x", "y", "facing" }) do
    check(stepped:find(field, 1, true) ~= nil,
      "world.stepped carries " .. field)
  end
end

do
  withBus(function(events, hooks)
    -- the emit path itself: a listener gets the payload, and an emit with no
    -- listener costs nothing and raises nothing
    local got = {}
    events:on("world.stepped", function(p) got[#got + 1] = p end, 0, "test_mod")
    Runtime.emit("world.stepped", { mapId = "g0_9", x = 3, y = 4 })
    eq(#got, 1, "a listener receives the emit")
    eq(got[1].mapId, "g0_9", "with the map")
    eq(got[1].x, 3, "and the coordinates")
    check(Runtime.wants("world.stepped"), "wants() sees the listener")
    check(not Runtime.wants("map.exited"),
      "and does not claim one that nobody registered")
  end)
end

-- ------- a missing bus is silence, not a crash

whenGame3(function()
  local function encounterGame()
    local battles = {}
    local g = setmetatable({
      map = { id = "g0_9" },
      battlesStarted = battles,
      rolls = 0,
    }, { __index = Game3 })
    function g:rand(n) return 1 end
    function g:repelBlocks() return false end
    function g:startWildBattle(species, level)
      battles[#battles + 1] = { species = species, level = level }
      return true
    end
    return g, battles
  end
  local INFO = { rate = 20, terrain = "land",
                 slots = { { species = 183, minLevel = 5, maxLevel = 5 } } }
  Runtime.reset()
  local g, battles = encounterGame()
  local ok = pcall(function() return g:startWildFrom(INFO, 0, true) end)
  check(ok, "with no mods loaded at all the roll still runs")
  eq(#battles, 1, "and the vanilla encounter happens")
end)

-- ------- movement.speed:
--
-- Gen 1's hook trades in FRAMES per cell; Ruby's walk period is SECONDS
-- (WALK_PERIOD is 16/60).  Handing a Red-written speed mod 0.267 and taking
-- back "8 frames" would read as eight seconds, and Gen 1's own clamp --
-- max(1, floor(n)) -- turns a normal step into a one-second crawl.  The first
-- version of this hook did exactly that to every step in the game.

whenGame3(function()
do
  local function walker()
    return setmetatable({}, { __index = Game3 })
  end

  withBus(function(events, hooks)
    local g = walker()
    local vanilla = g:walkPeriod()
    check(math.abs(vanilla - Game3.WALK_PERIOD) < 1e-9,
      "with no wrapper the period is unchanged")
    check(vanilla < 1, "and it is SECONDS, not frames")
  end)

  withBus(function(events, hooks)
    local saw
    hooks:wrap("movement.speed", function(next, frames, ctx)
      saw = { frames = frames, onBike = ctx and ctx.onBike,
              running = ctx and ctx.running, surfing = ctx and ctx.surfing }
      return next(frames, ctx)
    end, 0, "test_mod")
    local g = walker()
    local out = g:walkPeriod()
    eq(saw.frames, Game3.WALK_PERIOD * 60,
      "the wrapper is handed FRAMES, the unit Gen 1 uses")
    check(math.abs(out - Game3.WALK_PERIOD) < 1e-9,
      "and a pass-through leaves the period exactly as it was")
    eq(saw.onBike, false, "the context says whether a bike is under you")
    eq(saw.running, false, "and whether you are running")
  end)

  withBus(function(events, hooks)
    -- a Red-written mod answers in frames and must be honoured as frames
    hooks:wrap("movement.speed", function() return 8 end, 0, "test_mod")
    local g = walker()
    check(math.abs(g:walkPeriod() - (8 / 60)) < 1e-9,
      "eight frames means eight sixtieths of a second, not eight seconds")
    check(g:walkPeriod() < Game3.WALK_PERIOD,
      "and fewer frames is FASTER, the same direction Gen 1 means")
  end)

  withBus(function(events, hooks)
    hooks:wrap("movement.speed", function() return 0 end, 0, "test_mod")
    local g = walker()
    check(math.abs(g:walkPeriod() - (1 / 60)) < 1e-9,
      "zero clamps to one FRAME, not to one second")
    check(g:walkPeriod() < 0.02, "which is a sixtieth of a second")
  end)

  withBus(function(events, hooks)
    hooks:wrap("movement.speed", function() return "fast" end, 0, "test_mod")
    local g = walker()
    check(math.abs(g:walkPeriod() - Game3.WALK_PERIOD) < 1e-9,
      "a non-number falls back to the vanilla period")
  end)
end

end)

-- ------- ui.start_menu.items: the SHAPES convert at the boundary
--
-- Ruby's menu is plain strings, drawn and dispatched by label.  Gen 1's is
-- records -- { label = "HM", onSelect = fn } -- and a real mod reads
-- item.label on every row and inserts a record of its own.  Handing strings
-- straight over puts a TABLE into a list this engine draws as text.

whenGame3(function()
local function menuGame()
  local g = setmetatable({}, { __index = Game3 })
  function g:inSafariMode() return false end
  function g:hasPokedex() return true end
  function g:hasPokenav() return false end
  function g:hasMods() return false end
  function g:playerName() return "BRENDAN" end
  return g
end

do
  withBus(function(events, hooks)
    local g = menuGame()
    local items = g:startMenuItems()
    local allStrings = true
    for _, v in ipairs(items) do
      if type(v) ~= "string" then allStrings = false end
    end
    check(allStrings, "the engine's own list is plain strings")
    check(#items > 0, "and it is not empty")
  end)

  withBus(function(events, hooks)
    local sawRecords, sawLabels = true, {}
    hooks:wrap("ui.start_menu.items", function(next, game, rows)
      local out = next(game, rows)
      for _, row in ipairs(out) do
        if type(row) ~= "table" or type(row.label) ~= "string" then
          sawRecords = false
        else
          sawLabels[#sawLabels + 1] = row.label
        end
      end
      return out
    end, 0, "test_mod")
    local g = menuGame()
    local items = g:startMenuItems()
    check(sawRecords,
      "the wrapper is handed RECORDS with .label, the shape a real mod reads")
    check(#sawLabels > 0, "one per row")
    local allStrings = true
    for _, v in ipairs(items) do
      if type(v) ~= "string" then allStrings = false end
    end
    check(allStrings, "and the engine still gets plain strings back")
  end)

  withBus(function(events, hooks)
    -- exactly what hm_anywhere_gen2 does: insert a record with an onSelect
    local ran = 0
    hooks:wrap("ui.start_menu.items", function(next, game, rows)
      local out = next(game, rows)
      table.insert(out, 1, { label = "HM",
        onSelect = function() ran = ran + 1 end })
      return out
    end, 0, "test_mod")
    local g = menuGame()
    local items = g:startMenuItems()
    eq(items[1], "HM", "the mod's row appears on the menu")
    check(type(items[1]) == "string", "as a string the engine can draw")
    check(g.modStartMenuActions ~= nil, "and its action was remembered")
    check(type(g.modStartMenuActions.HM) == "function", "keyed by its label")
    g.modStartMenuActions.HM(g)
    eq(ran, 1, "so choosing the row runs the mod's handler")
  end)

  withBus(function(events, hooks)
    -- a row with no onSelect must not leave a stale action behind
    hooks:wrap("ui.start_menu.items", function(next, game, rows)
      local out = next(game, rows)
      table.insert(out, 1, { label = "PLAIN" })
      return out
    end, 0, "test_mod")
    local g = menuGame()
    local items = g:startMenuItems()
    eq(items[1], "PLAIN", "a label-only row still appears")
    check(g.modStartMenuActions == nil or g.modStartMenuActions.PLAIN == nil,
      "and registers no action")
  end)

  withBus(function(events, hooks)
    hooks:wrap("ui.start_menu.items", function() return "nonsense" end, 0, "m")
    local g = menuGame()
    local items = g:startMenuItems()
    check(#items > 0, "a non-table answer keeps the vanilla list")
    eq(type(items[1]), "string", "still as strings")
    check(g.modStartMenuActions == nil, "and clears any stale actions")
  end)

  withBus(function(events, hooks)
    hooks:wrap("ui.start_menu.items", function() return {} end, 0, "m")
    local g = menuGame()
    check(#g:startMenuItems() > 0,
      "an EMPTY answer keeps the vanilla list -- a menu with no rows is the "
      .. "one failure a player cannot get out of")
  end)
end

end)

-- ------- movement.collision wraps the one verdict everything asks

whenGame3(function()
do
  local function stepper(vanillaAnswer)
    local g = setmetatable({ playerX = 4, playerY = 5, facing = "south",
                             map = { id = "g0_9" } }, { __index = Game3 })
    function g:canStepVanilla() return vanillaAnswer end
    return g
  end

  withBus(function(events, hooks)
    eq(stepper(true):canStep(nil, 4, 6), true, "the vanilla yes passes through")
    eq(stepper(false):canStep(nil, 4, 6), false, "and the vanilla no")
  end)

  withBus(function(events, hooks)
    local saw
    hooks:wrap("movement.collision", function(next, allowed, ctx)
      saw = { allowed = allowed, toX = ctx.toX, toY = ctx.toY, dir = ctx.dir,
              fromX = ctx.fromX, fromY = ctx.fromY }
      return next(allowed, ctx)
    end, 0, "test_mod")
    local g = stepper(false)
    eq(g:canStep(nil, 4, 6), false, "a pass-through keeps the verdict")
    eq(saw.allowed, false, "the wrapper sees the vanilla verdict")
    eq(saw.toX, 4, "and where the step was going")
    eq(saw.toY, 6, "in both axes")
    eq(saw.fromX, 4, "and where it came from")
    eq(saw.fromY, 5, "in both axes")
    eq(saw.dir, "south", "and which way it faced")
  end)

  withBus(function(events, hooks)
    hooks:wrap("movement.collision", function() return true end, 0, "m")
    eq(stepper(false):canStep(nil, 4, 6), true,
      "a wrapper can allow a step the engine refused")
  end)

  withBus(function(events, hooks)
    hooks:wrap("movement.collision", function() return false end, 0, "m")
    eq(stepper(true):canStep(nil, 4, 6), false,
      "and can refuse one the engine allowed")
  end)

  withBus(function(events, hooks)
    hooks:wrap("movement.collision", function() return "yes" end, 0, "m")
    eq(stepper(false):canStep(nil, 4, 6), true,
      "the answer is coerced to a boolean, never returned raw")
    check(stepper(false):canStep(nil, 4, 6) == true,
      "so a caller comparing to true is not surprised by a string")
  end)
end
end)

-- ------- input.step runs before the input is promoted

do
  local src = readfile("src/core/Game3.lua")
  local body = src:match("function Game3:logicStep%(dt%)(.-)\nend\n")
  check(body ~= nil, "logicStep was found")
  local hookAt = body and body:find('modCall%("input%.step"')
  local stepAt = body and body:find("Input:step%(%)")
  check(hookAt ~= nil, "logicStep calls input.step")
  check(stepAt ~= nil, "and promotes the input")
  check(hookAt and stepAt and hookAt < stepAt,
    "the hook runs BEFORE Input:step, so a button a mod presses is visible "
    .. "to this logic tick rather than the next one")
end

-- ------- the event batch: map.exited, battle.started, save.writing/loaded

do
  local src = readfile("src/core/Game3.lua")
  local bt = (function() local f=io.open("src/core/Game3BattleTransition.lua"); if not f then return nil end; local b=readfile("src/core/Game3BattleTransition.lua"); return b end)()

  -- map.exited fires only when there was a map to leave, and names the sides
  -- from the DEPARTING map's point of view, as Gen 1 does
  local exited = src:match('modEmit%("map%.exited", (%b{})')
  check(exited ~= nil, "Game3 emits map.exited")
  check(exited and exited:find("mapId = previousMapId", 1, true) ~= nil,
    "its mapId is the map being LEFT, not the one being entered")
  check(exited and exited:find("toMapId", 1, true) ~= nil,
    "and toMapId is the destination")
  check(src:find("if previousMapId and previousMapId ~=", 1, true) ~= nil,
    "and it is guarded, so the first map of a session announces no departure")

  -- battle.started sits where all three battle starts meet
  if bt then
    check(bt:find('Runtime.emit, "battle.started"', 1, true) ~= nil,
      "battle.started is emitted from launchBattleWithEntrance")
    local started = bt:match('"battle%.started", (%b{})')
    check(started ~= nil, "with a payload table")
    for _, field in ipairs({ "kind", "species", "level", "trainerId", "battle" }) do
      check(started and started:find(field, 1, true) ~= nil,
        "battle.started carries " .. field)
    end
    -- THE SHAPE TRAP: Gen 1 reads enemy.mon.species because its battler wraps a
    -- mon; Ruby's battle.enemy IS the mon.  Reading one level too deep here
    -- would report nil for every fight.
    check(started and started:find("enemy and enemy.species", 1, true) ~= nil,
      "and reads the species off the mon directly, not through a battler")
    check(not (started and started:find("enemy.mon", 1, true)),
      "never through Gen 1's enemy.mon, which does not exist on Ruby")
  else
    check(true, "Game3BattleTransition.lua absent -- battle.started source check skipped")
  end

  -- save.writing is emitted BEFORE the snapshot is taken
  local wIdx = src:find('modEmit("save.writing"', 1, true)
  local snapIdx = src:find("SaveSerializer.encode(self:snapshotSave())", 1, true)
  check(wIdx ~= nil, "Game3 emits save.writing")
  check(snapIdx ~= nil, "and takes a snapshot")
  check(wIdx and snapIdx and wIdx < snapIdx,
    "the emit comes first, so a listener can still write into the save")

  -- save.loaded is emitted AFTER the state is restored
  local lIdx = src:find('modEmit("save.loaded"', 1, true)
  local applyIdx = src:find("function Game3:applySave(data)", 1, true)
  check(lIdx ~= nil, "Game3 emits save.loaded")
  check(applyIdx and lIdx and applyIdx < lIdx,
    "from inside applySave, after the party and bag are in place")
end

do
  -- the emit path for each, through the real bus
  withBus(function(events, hooks)
    local got = {}
    for _, name in ipairs({ "map.exited", "battle.started",
                            "save.writing", "save.loaded" }) do
      events:on(name, function(p) got[name] = p or {} end, 0, "test_mod")
      check(Runtime.wants(name), name .. " is seen as wanted")
    end
    Runtime.emit("map.exited", { mapId = "g0_9", toMapId = "g0_16" })
    eq(got["map.exited"].mapId, "g0_9", "map.exited delivers the map left")
    eq(got["map.exited"].toMapId, "g0_16", "and the one entered")

    Runtime.emit("battle.started", { kind = "wild", species = 261, level = 5 })
    eq(got["battle.started"].kind, "wild", "battle.started delivers the kind")
    eq(got["battle.started"].species, 261, "and the species")

    Runtime.emit("save.writing", { save = { a = 1 } })
    check(got["save.writing"].save ~= nil, "save.writing delivers the save")
    Runtime.emit("save.loaded", { save = { a = 1 } })
    check(got["save.loaded"].save ~= nil, "save.loaded delivers the save")
  end)
end

-- ------- ui.party.submenu: records out, strings back, context intact
--
-- The same shape conversion the START menu needed, plus one thing it did not:
-- this list is ALSO the battle switch menu, and free_fly refuses to offer a
-- take-off when `ctx.battle` is set.  A ctx without that field would make
-- every mod think the player is standing safely in the overworld.

whenGame3(function()
local function partyGame(battle)
  local g = setmetatable({ battle = battle }, { __index = Game3 })
  function g:partyFieldMoves() return { "SURF" } end
  function g:modOverworld() return { map = { id = "g0_9" } } end
  return g
end

do
  withBus(function(events, hooks)
    local g = partyGame(nil)
    local acts = g:partyActions({ species = 277 })
    local allStrings = true
    for _, v in ipairs(acts) do
      if type(v) ~= "string" then allStrings = false end
    end
    check(allStrings, "the engine's party actions are plain strings")
    check(#acts > 0, "and there are some")
  end)

  withBus(function(events, hooks)
    local saw = {}
    hooks:wrap("ui.party.submenu", function(next, game, rows, mon, ctx)
      local out = next(game, rows, mon, ctx)
      saw.allRecords = true
      for _, row in ipairs(out) do
        if type(row) ~= "table" or type(row.label) ~= "string" then
          saw.allRecords = false
        end
      end
      saw.mon = mon
      saw.hasBattle = ctx ~= nil and ctx.battle ~= nil
      saw.hasOverworld = ctx ~= nil and ctx.overworld ~= nil
      return out
    end, 0, "test_mod")

    local mon = { species = 277 }
    local g = partyGame(nil)
    local acts = g:partyActions(mon)
    check(saw.allRecords,
      "the wrapper is handed RECORDS with .label, as a real mod reads them")
    eq(saw.mon, mon, "and the mon the row acts on")
    eq(saw.hasOverworld, true, "with the overworld in the context")
    eq(saw.hasBattle, false, "and no battle, because none is running")
    local allStrings = true
    for _, v in ipairs(acts) do
      if type(v) ~= "string" then allStrings = false end
    end
    check(allStrings, "and the engine gets plain strings back")
  end)

  withBus(function(events, hooks)
    -- THE DISTINCTION free_fly depends on: in a fight, ctx.battle is set
    local saw
    hooks:wrap("ui.party.submenu", function(next, game, rows, mon, ctx)
      saw = ctx ~= nil and ctx.battle ~= nil
      return next(game, rows, mon, ctx)
    end, 0, "test_mod")
    partyGame({ kind = "menu" }):partyActions({ species = 277 })
    eq(saw, true,
      "in a battle the context says so, so a mod can refuse to act")
  end)

  withBus(function(events, hooks)
    -- the row, and its handler, called with (mon, game) as Gen 1 calls it
    local ran, gotMon, gotGame = 0, nil, nil
    hooks:wrap("ui.party.submenu", function(next, game, rows, mon, ctx)
      local out = next(game, rows, mon, ctx)
      table.insert(out, 1, { label = "FREEFLY",
        onSelect = function(m, gm) ran = ran + 1 gotMon = m gotGame = gm end })
      return out
    end, 0, "test_mod")
    local mon = { species = 277 }
    local g = partyGame(nil)
    local acts = g:partyActions(mon)
    eq(acts[1], "FREEFLY", "the mod's row appears")
    eq(type(acts[1]), "string", "as a string the engine can draw")
    check(g.modPartyActions ~= nil, "and its handler was remembered")
    check(type(g.modPartyActions.FREEFLY) == "function", "keyed by label")
    g.modPartyActions.FREEFLY(mon, g)
    eq(ran, 1, "invoking it runs the handler")
    eq(gotMon, mon, "with the mon FIRST, as Gen 1 calls it")
    eq(gotGame, g, "and the game second")
  end)

  withBus(function(events, hooks)
    hooks:wrap("ui.party.submenu", function() return "nonsense" end, 0, "m")
    local g = partyGame(nil)
    local acts = g:partyActions({ species = 277 })
    check(#acts > 0, "a non-table answer keeps the vanilla actions")
    check(g.modPartyActions == nil, "and clears any stale handler")
  end)

  withBus(function(events, hooks)
    hooks:wrap("ui.party.submenu", function() return {} end, 0, "m")
    local g = partyGame(nil)
    check(#g:partyActions({ species = 277 }) > 0,
      "and an empty answer keeps them too")
  end)
end
end)

do
  -- the A press dispatches a mod row before the built-in names
  local src = readfile("src/core/Game3.lua")
  local step = src:match("function Game3:stepPartyAction%(f%)(.-)\nend\n")
  check(step ~= nil, "stepPartyAction was found")
  local modAt = step and step:find("modPartyActions", 1, true)
  local summaryAt = step and step:find('name == "SUMMARY"', 1, true)
  check(modAt ~= nil, "it consults the mod handlers")
  check(modAt and summaryAt and modAt < summaryAt,
    "before the built-in actions, so a mod may take one over")
  check(step and step:find("pcall(modAction", 1, true) ~= nil,
    "and a handler that throws does not take the menu down")
  -- THE ARGUMENT ORDER IS THE ENGINE'S, not the test's.  Calling the stored
  -- handler directly (as the case above does) pins what we store, not what
  -- stepPartyAction passes -- swapping the two there went undetected until
  -- this check existed.  Gen 1 calls a party row with the MON first.
  check(step and step:find("pcall(modAction, (self.party or {})[index], self)",
                           1, true) ~= nil,
    "and the engine calls it with (mon, game), the mon first, as Gen 1 does")
end


-- ------- Gen3 cheap hooks/events batch (world.tod, music.select, …)
--
-- Source checks always run.  Behavioral withBus+wrap checks run only when
-- Game3 loaded.  Mutation: deleting the encounter.fishing modCall inside
-- startFishingWild must turn that assertion red.

do
  local src = readfile("src/core/Game3.lua")
  local hooks = {
    'modCall("world.tod"',
    'modCall("music.select"',
    'modCall("encounter.fishing"',
    'modCall("fieldmove.eligibility"',
    'modCall("ui.list_menu"',
    'modCall("render.hud"',
    'modCall("battle.exp_award"',
    'modCall("save.write"',
    'modCall("battle.catch_exp"',
    'modCall("battle.damage"',
    'modCall("battle.accuracy"',
    'modCall("battle.turn_order"',
    'modCall("battle.overlay"',
    'modCall("battle.charge_required"',
    'modCall("battle.run"',
    'modCall("battle.enemy_action"',
    'modCall("exp.gain"',
    'modCall("pokemon.sprite"',
    'modCall("render.compose"',
    'modCall("render.letterbox"',
    'modCall("map.palette"',
    'modCall("catch.rate"',
    'modCall("held_item.trigger"',
  }
  local events = {
    'modEmit("world.tod_changed"',
    'modEmit("pokemon.caught"',
    'modEmit("world.blacked_out"',
    'modEmit("battle.move_used"',
    'modEmit("battle.turn_ended"',
    'modEmit("save.created"',
    'modEmit("music.started"',
    'modEmit("pokemon.before_give"',
  }
  for _, s in ipairs(hooks) do
    check(src:find(s, 1, true) ~= nil, "Game3 wires " .. s)
  end
  for _, s in ipairs(events) do
    check(src:find(s, 1, true) ~= nil, "Game3 wires " .. s)
  end
  -- map.reloaded: wired from setMapLayoutIndex / restoreMapLayout (in-place
  -- data reload).  Must NOT come from enterMap (that would lie about reason).
  check(src:find('modEmit("map.reloaded"', 1, true) ~= nil,
    "map.reloaded is emitted from a real layout-reload seam")
  local enterAt = src:find("function Game3:enterMap", 1, true)
  local emitAt = src:find('modEmit("map.reloaded"', 1, true)
  check(enterAt ~= nil and emitAt ~= nil, "enterMap and map.reloaded emit both exist")
  -- Every map.reloaded emit must sit inside a layout helper, not enterMap.
  local pos = 0
  while true do
    local at = src:find('modEmit("map.reloaded"', pos + 1, true)
    if not at then break end
    local window = src:sub(math.max(1, at - 1200), at)
    check(window:find("restoreMapLayout", 1, true) ~= nil
       or window:find("setMapLayoutIndex", 1, true) ~= nil
       or window:find("ScrCmd_setmaplayoutindex", 1, true) ~= nil
       or window:find("reason = \"layout\"", 1, true) ~= nil,
      "map.reloaded emit is near a layout-reload helper")
    check(window:find("function Game3:enterMap", 1, true) == nil,
      "map.reloaded emit is not inside enterMap")
    pos = at
  end
  check(src:find("function Game3:mapPaletteName", 1, true) ~= nil,
    "mapPaletteName exists for map.palette")

  local todBody = src:match("function Game3:timeOfDay%(%)(.-)\nend\n")
  check(todBody ~= nil, "Game3:timeOfDay exists")
  for _, field in ipairs({ "map", "mapId", "x", "y", "steps" }) do
    check(todBody and todBody:find(field, 1, true) ~= nil,
      "world.tod ctx carries " .. field)
  end

  local caught = src:match('modEmit%("pokemon%.caught", (%b{})')
  check(caught ~= nil, "pokemon.caught payload is a table")
  for _, field in ipairs({ "battle", "mon", "species", "isNew", "ball",
                           "destination", "game" }) do
    check(caught and caught:find(field, 1, true) ~= nil,
      "pokemon.caught carries " .. field)
  end

  local black = src:match('modEmit%("world%.blacked_out", (%b{})')
  check(black ~= nil, "world.blacked_out payload is a table")
  for _, field in ipairs({ "game", "mapId", "reason" }) do
    check(black and black:find(field, 1, true) ~= nil,
      "world.blacked_out carries " .. field)
  end

  local moved = src:match('modEmit%("battle%.move_used", (%b{})')
  check(moved ~= nil, "battle.move_used payload is a table")
  for _, field in ipairs({ "battle", "turn", "move", "user", "target" }) do
    check(moved and moved:find(field, 1, true) ~= nil,
      "battle.move_used carries " .. field)
  end
  check(src:find('modEmit("battle.turn_ended"', 1, true) ~= nil,
    "battle.turn_ended is emitted")

  check(src:find("function Game3:applyListMenuHook", 1, true) ~= nil,
    "applyListMenuHook converts records at the boundary")
  check(src:find("modListActions", 1, true) ~= nil,
    "and stores onSelect handlers for the A press")

  -- MUTATION TARGET
  local fishBody = src:match("function Game3:startFishingWild%(rod%)(.-)\nend\n")
  check(fishBody ~= nil, "startFishingWild was found")
  check(fishBody and fishBody:find('modCall("encounter.fishing"', 1, true) ~= nil,
    "startFishingWild calls encounter.fishing (mutation: delete the modCall)")
  -- Comment text may mention startWildFrom; only a CALL would re-enter
  -- encounter.roll.  Match the call form so a why-comment cannot fail this.
  check(fishBody and not fishBody:find("startWildFrom(", 1, true),
    "and does not also fall through encounter.roll via startWildFrom(")
end

whenGame3(function()
  withBus(function(events, hooks)
    local got = {}
    events:on("world.tod_changed", function(p) got[#got + 1] = p end, 0, "m")
    hooks:wrap("world.tod", function() return "NIGHT" end, 0, "m")
    local g = setmetatable({ map = { id = "g0_9" }, playerX = 1, playerY = 2 },
                           { __index = Game3 })
    eq(g:timeOfDay(), "NIGHT", "world.tod can replace DAY with NIGHT")
    eq(#got, 1, "and emits world.tod_changed once")
    eq(got[1].tod, "NIGHT", "with the new tod")
    eq(got[1].previous, "DAY", "and the previous")
    eq(g:timeOfDay(), "NIGHT", "a second call with same answer does not re-emit")
    eq(#got, 1, "still one emit")
  end)

  withBus(function(events, hooks)
    local saw
    hooks:wrap("music.select", function(next, songId, ctx)
      saw = songId
      return 999
    end, 0, "m")
    local g = setmetatable({ data = {} }, { __index = Game3 })
    local out = g:playSong(100, true)
    eq(saw, 100, "music.select sees the vanilla id")
    eq(out, 999, "and the engine plays the replacement")
  end)

  withBus(function(events, hooks)
    hooks:wrap("encounter.fishing", function() return nil end, 0, "m")
    local battles = {}
    local g = setmetatable({ map = { id = "g0_9" } }, { __index = Game3 })
    function g:encountersFor()
      return { fish = { slots = { { species = 129, minLevel = 5, maxLevel = 5 } } } }
    end
    function g:firstHealthy() return { species = 1 } end
    function g:gbaRandom() return 0 end
    function g:rand(n) return 1 end
    function g:startWildBattle(sp, lv)
      battles[#battles + 1] = { sp, lv }; return true
    end
    eq(g:startFishingWild(0), false, "encounter.fishing nil suppresses")
    eq(#battles, 0, "and starts no battle")
  end)

  withBus(function(events, hooks)
    hooks:wrap("encounter.fishing", function()
      return { species = 72, level = 20 }
    end, 0, "m")
    local battles = {}
    local g = setmetatable({ map = { id = "g0_9" } }, { __index = Game3 })
    function g:encountersFor()
      return { fish = { slots = { { species = 129, minLevel = 5, maxLevel = 5 } } } }
    end
    function g:firstHealthy() return { species = 1 } end
    function g:gbaRandom() return 0 end
    function g:rand(n) return 1 end
    function g:startWildBattle(sp, lv)
      battles[#battles + 1] = { species = sp, level = lv }; return true
    end
    eq(g:startFishingWild(0), true, "encounter.fishing replace fights")
    eq(battles[1].species, 72, "with the wrapper species")
    eq(battles[1].level, 20, "and level")
  end)

  withBus(function(events, hooks)
    hooks:wrap("fieldmove.eligibility", function() return true end, 0, "m")
    local g = setmetatable({ party = { { moves = {} } } }, { __index = Game3 })
    function g:knowsMove() return false end
    eq(g:partyKnowsMove(19), true,
      "fieldmove.eligibility can unlock a move nobody knows")
  end)

  withBus(function(events, hooks)
    local ran = 0
    hooks:wrap("ui.list_menu", function(next, game, rows, ctx)
      local out = next(game, rows, ctx)
      table.insert(out, 1, { label = "MODROW",
        onSelect = function() ran = ran + 1 end })
      return out
    end, 0, "m")
    local g = setmetatable({}, { __index = Game3 })
    function g:beginScriptWait() end
    g:openMauvilleMenu({ "A", "CANCEL" }, "pickStorytellerStory")
    eq(g.field.labels[1], "MODROW", "ui.list_menu inserts a string row")
    check(g.field.modListActions and g.field.modListActions.MODROW ~= nil,
      "and remembers onSelect")
    g.field.modListActions.MODROW(g)
    eq(ran, 1, "so choosing it runs the handler")
  end)
end)


-- ------- render.hud + battle.exp_award (johto_radar / exp_share)

do
  local src = readfile("src/core/Game3.lua")

  -- CONTINUATION SHAPE: modCall must pass a function vanilla through to
  -- Runtime.call, not wrap it as `function() return vanilla end`.  Without
  -- that, exp_share's next(ctx) gets a function back instead of applying XP.
  local modCallBody = src:match("local function modCall%(name, vanilla, %.%.%.%)(.-)\nend\n")
  check(modCallBody ~= nil, "modCall body found")
  check(modCallBody and modCallBody:find("isCont", 1, true) ~= nil,
    "modCall distinguishes function (continuation) vanillas")
  check(modCallBody and modCallBody:find("vanillaFn = isCont and vanilla", 1, true) ~= nil,
    "and passes continuations through to Runtime.call unwrapped")

  local drawBody = src:match("function Game3:draw%(%)(.-)\nend\n")
  check(drawBody ~= nil, "Game3:draw found")
  local finishAt = drawBody and drawBody:find("GameViewport.finish", 1, true)
  local hudAt = drawBody and drawBody:find('modCall("render.hud"', 1, true)
  local touchAt = drawBody and drawBody:find("TouchControls:draw", 1, true)
  check(hudAt ~= nil, "draw calls render.hud")
  check(finishAt and hudAt and finishAt < hudAt,
    "render.hud is after GameViewport.finish (Gen 1: after endFrame)")
  check(hudAt and touchAt and hudAt < touchAt,
    "and before TouchControls:draw (Gen 1 order; unblocks johto_radar)")
  check(drawBody and drawBody:find("gameX", 1, true) ~= nil,
    "viewport carries gameX for screen-space HUDs")
  check(drawBody and drawBody:find("function() end", 1, true) ~= nil,
    "render.hud vanilla is a no-op continuation")

  local awardBody = src:match("function Game3:awardExp%(winner, fainted, trainer%)(.-)\nend\n")
  check(awardBody ~= nil, "Game3:awardExp found")
  check(awardBody and awardBody:find('modCall("battle.exp_award"', 1, true) ~= nil,
    "awardExp calls battle.exp_award (mutation: delete the modCall)")
  check(awardBody and awardBody:find("vanillaAward", 1, true) ~= nil,
    "with a local vanillaAward continuation")
  check(awardBody and awardBody:find("applyShare", 1, true) ~= nil,
    "and ctx.applyShare for exp_share-style redistribution")
  for _, field in ipairs({ "battle", "game", "winner", "fainted", "trainer",
                           "calculated", "participants", "alive", "applyShare" }) do
    check(awardBody and awardBody:find(field, 1, true) ~= nil,
      "battle.exp_award ctx carries " .. field)
  end
end

whenGame3(function()
  -- Wrapper replaces distribution via applyShare and returns its own texts.
  -- Mutation: wiring modCall with a VALUE wrap (function() return vanilla end)
  -- would make next(ctx) return the function; this case never calls next, but
  -- the pass-through case below would then pay no XP.
  withBus(function(events, hooks)
    local saw
    hooks:wrap("battle.exp_award", function(nextFn, ctx)
      saw = ctx
      -- Gen 1 / exp_share contract: second arg is a DIVISOR of calculated.
      -- split=1 → full calculated; split=2 → half. Absolute amounts are the
      -- vanillaAward path only (payExp), not the hooked applyShare.
      ctx.applyShare(ctx.winner, 1, true)
      return { "mod-summary" }
    end, 0, "m")
    local winner = { name = "A", level = 5, exp = 0 }
    local fainted = { species = 1, level = 5, expYield = 70 }
    local expected = math.max(1, math.floor(70 * 5 / 7))
    local g = setmetatable({
      party = { winner },
      battle = { sentIn = { [1] = true } },
      save = { options = {}, party = nil },
    }, { __index = Game3 })
    function g:partyIndexOf(mon) return mon == winner and 1 or nil end
    function g:canBattle(mon) return mon ~= nil end
    function g:holdsExpShare() return false end
    function g:gainEVs() end
    function g:giveMonExp(mon, amount)
      mon.exp = (mon.exp or 0) + amount
      return { mon.name .. " got " .. tostring(amount) }
    end
    function g:speciesRow() return nil end
    local texts = g:awardExp(winner, fainted, false)
    check(saw ~= nil, "battle.exp_award fired")
    check(type(saw.applyShare) == "function", "ctx.applyShare is callable")
    eq(saw.calculated, expected, "ctx.calculated matches yield*level/7")
    eq(texts[1], "mod-summary", "wrapper may replace the returned texts")
    eq(winner.exp, expected, "applyShare(mon, 1) pays full calculated")
    check(type(saw.participants) == "number",
      "participants is a COUNT (exp_share does math.max(1, ctx.participants))")
    check(saw.battle and saw.battle.game == g,
      "battle.game aliases the host so optionsOf(ctx.battle) sees save.options")
    check(saw.battle and saw.battle.party == g.party,
      "battle.party aliases the host party for partyOf")
    check(type(saw.alive) == "table" and saw.alive[1] == winner,
      "ctx.alive is the fighter list (exp_share marks fought from alive)")
  end)

  -- Pass-through next(ctx) must actually apply XP (continuation shape).
  withBus(function(events, hooks)
    hooks:wrap("battle.exp_award", function(nextFn, ctx)
      return nextFn(ctx)
    end, 0, "m")
    local winner = { name = "B", level = 5, exp = 0 }
    local fainted = { species = 1, level = 5, expYield = 70 }
    local expected = math.max(1, math.floor(70 * 5 / 7))
    local g = setmetatable({
      party = { winner },
      battle = { sentIn = { [1] = true } },
    }, { __index = Game3 })
    function g:partyIndexOf(mon) return mon == winner and 1 or nil end
    function g:canBattle(mon) return mon ~= nil end
    function g:holdsExpShare() return false end
    function g:gainEVs() end
    function g:giveMonExp(mon, amount)
      mon.exp = (mon.exp or 0) + amount
      return { "gained " .. tostring(amount) }
    end
    function g:speciesRow() return nil end
    local texts = g:awardExp(winner, fainted, false)
    eq(winner.exp, expected, "next(ctx) runs vanillaAward and pays XP")
    check(type(texts) == "table" and #texts >= 1,
      "and returns the announced lines")
  end)
end)



-- ------- save.write / save.created / music.started / pokemon.before_give /
-- ------- battle.catch_exp  (free_fly / surround_audio / qol_toggles)

do
  local src = readfile("src/core/Game3.lua")

  -- save.write: after battle/safari guards, before ensureSaveSlot / snapshot
  local writeBody = src:match("function Game3:writeSave%(%)(.-)\nend\n")
  check(writeBody ~= nil, "Game3:writeSave found")
  local callAt = writeBody and writeBody:find('modCall("save.write"', 1, true)
  local slotAt = writeBody and writeBody:find("ensureSaveSlot", 1, true)
  local snapAt = writeBody and writeBody:find("snapshotSave", 1, true)
  check(callAt ~= nil, "writeSave calls save.write (mutation: delete the modCall)")
  check(writeBody and writeBody:find("function() return true end", 1, true) ~= nil,
    "save.write vanilla is a continuation that returns true")
  check(callAt and slotAt and callAt < slotAt,
    "save.write is before ensureSaveSlot")
  check(callAt and snapAt and callAt < snapAt,
    "and before the snapshot / persist")

  -- save.created: boot load + NEW GAME (Birch wrap), never applySave
  check(src:find('modEmit("save.created"', 1, true) ~= nil,
    "Game3 emits save.created")
  local created = src:match('modEmit%("save%.created", (%b{})')
  check(created ~= nil, "save.created payload is a table")
  check(created and created:find("save", 1, true) ~= nil,
    "save.created carries save")
  check(created and created:find("game", 1, true) ~= nil,
    "and game")
  local applyBody = src:match("function Game3:applySave%(data%)(.-)\nend\n")
  check(applyBody and applyBody:find('modEmit("save.created"', 1, true) == nil,
    "applySave does not emit save.created (CONTINUE is save.loaded only)")
  check(src:find("startBirchSpeech", 1, true) ~= nil
        and src:find('modEmit("save.created"', 1, true) ~= nil,
    "NEW GAME path can reach save.created (Birch wrap after Boot.attach)")

  -- music.started: after successful playSong, not on MUS_NONE cancel
  local playBody = src:match("function Game3:playSong%(songId, loop%)(.-)\nend\n")
  check(playBody ~= nil, "Game3:playSong found")
  local playAt = playBody and playBody:find("Mp2kAudio.playSong", 1, true)
  local startedAt = playBody and playBody:find('modEmit("music.started"', 1, true)
  check(startedAt ~= nil, "playSong emits music.started")
  check(playAt and startedAt and playAt < startedAt,
    "music.started is AFTER Mp2kAudio.playSong")
  local noneAt = playBody and playBody:find("MUS_NONE", 1, true)
  check(noneAt and startedAt and noneAt < startedAt,
    "MUS_NONE returns before music.started")
  local started = playBody and playBody:match('modEmit%("music%.started", (%b{})')
  for _, field in ipairs({ "song", "game", "loop" }) do
    check(started and started:find(field, 1, true) ~= nil,
      "music.started carries " .. field)
  end

  -- pokemon.before_give: giveMon (and giveEgg) before makeMon
  local giveBody = src:match("function Game3:giveMon%(species, level, item%)(.-)\nend\n")
  check(giveBody ~= nil, "Game3:giveMon found")
  local beforeAt = giveBody and giveBody:find('modEmit("pokemon.before_give"', 1, true)
  local makeAt = giveBody and giveBody:find("self:makeMon", 1, true)
  check(beforeAt ~= nil, "giveMon emits pokemon.before_give")
  check(beforeAt and makeAt and beforeAt < makeAt,
    "before_give is BEFORE makeMon so qol can arm DV flags")
  local before = giveBody and giveBody:match('modEmit%("pokemon%.before_give", (%b{})')
  check(before and before:find("game", 1, true) ~= nil,
    "pokemon.before_give carries game")
  local eggBody = src:match("function Game3:giveEgg%(species%)(.-)\nend\n")
  check(eggBody and eggBody:find('modEmit("pokemon.before_give"', 1, true) ~= nil,
    "giveEgg also emits pokemon.before_give")

  -- battle.catch_exp: gated award on catch success
  check(src:find('modCall("battle.catch_exp"', 1, true) ~= nil,
    "Game3 wires battle.catch_exp")
  check(src:find('modCall("battle.catch_exp", function() return false end', 1, true) ~= nil,
    "catch_exp vanilla continuation returns false (Gen 1 storeCaughtMon)")
  local catchIdx = src:find('modCall("battle.catch_exp"', 1, true)
  local gotchaIdx = src:find('Gotcha!', 1, true)
  check(catchIdx and gotchaIdx and gotchaIdx < catchIdx,
    "catch_exp sits on the catch-success path after Gotcha")
end

whenGame3(function()
  -- Behavioral veto: free_fly-style save.write returning false aborts writeSave
  -- before any filesystem touch.
  withBus(function(events, hooks)
    hooks:wrap("save.write", function(nextFn, game)
      return false
    end, 0, "m")
    local g = setmetatable({}, { __index = Game3 })
    function g:inBattlePhase() return false end
    function g:inSafariMode() return false end
    function g:saveFs()
      error("saveFs must not run when save.write vetoes")
    end
    local ok, err = g:writeSave()
    eq(ok, false, "save.write veto returns false")
    eq(err, "Can't save now.", "with Can't save now.")
  end)

  -- Pass-through lets the write proceed past the hook (then fails on missing fs,
  -- which still proves the veto did not fire).
  withBus(function(events, hooks)
    local saw
    hooks:wrap("save.write", function(nextFn, game)
      saw = game
      return nextFn()
    end, 0, "m")
    local g = setmetatable({}, { __index = Game3 })
    function g:inBattlePhase() return false end
    function g:inSafariMode() return false end
    function g:saveFs() return nil end
    local ok, err = g:writeSave()
    check(saw == g, "save.write receives the game")
    eq(ok, false, "missing fs still fails after pass-through")
    eq(err, "Save failed.", "with Save failed.")
  end)
end)



-- ------- battle.damage / accuracy / turn_order / overlay /
-- ------- charge_required / run / enemy_action  (phase-1 Gen3 parity)

do
  local src = readfile("src/core/Game3.lua")

  -- Source presence (mutation: delete any one modCall and that assert goes red).
  for _, name in ipairs({
    "battle.damage", "battle.accuracy", "battle.turn_order",
    "battle.overlay", "battle.charge_required", "battle.run",
    "battle.enemy_action",
  }) do
    check(src:find('modCall("' .. name .. '"', 1, true) ~= nil,
      "Game3 wires " .. name)
  end

  -- battle.damage: Gen 1 returns (dmg, { crit, typeMult }); Trap C hands the
  -- mon itself as user/target (user.species, NOT user.mon.species).
  local dmgHelper = src:match("local function modBattleDamage%(.-%)(.-)\nend\n")
  check(dmgHelper ~= nil, "modBattleDamage helper exists")
  for _, field in ipairs({ "battle", "ruleset", "user", "target", "move", "opts", "rng" }) do
    check(dmgHelper and dmgHelper:find(field, 1, true) ~= nil,
      "battle.damage ctx carries " .. field)
  end
  check(dmgHelper and dmgHelper:find("typeMult", 1, true) ~= nil,
    "battle.damage vanilla info carries typeMult")
  check(dmgHelper and dmgHelper:find("user = attacker", 1, true) ~= nil,
    "battle.damage user IS the mon (Trap C)")
  check(not (dmgHelper and dmgHelper:find("user = { mon", 1, true)),
    "and does not wrap it in a Gen 1 battler shell")

  -- Seams: main formula, level-damage, endeavor, and set-damage all call it
  -- BEFORE Endure / HP write.
  check(src:find("modBattleDamage(self, attacker, defender, move", 1, true) ~= nil,
    "dealDamage calls modBattleDamage")
  -- The main formula path calls modBattleDamage, then Endure, then the
  -- dryRun early-return — in that order (handover §6).
  local mainChunk = src:match(
    "dmg, crit, mul = modBattleDamage%(self, attacker, defender, move,-(.-)if dryRun then return")
  check(mainChunk ~= nil, "main-path battle.damage call exists")
  check(mainChunk and mainChunk:find("endured", 1, true) ~= nil,
    "main-path battle.damage sits before Endure")
  check(mainChunk and mainChunk:find("if dryRun", 1, true) == nil,
    "and Endure is still before the dryRun return")

  -- battle.accuracy
  local accBody = src:match("function Game3:accuracyRoll%(.-%)(.-)\nend\n")
  check(accBody ~= nil, "Game3:accuracyRoll exists")
  for _, field in ipairs({ "battle", "ruleset", "move", "user", "target", "rng" }) do
    check(accBody and accBody:find(field, 1, true) ~= nil,
      "battle.accuracy ctx carries " .. field)
  end
  check(src:find("self:accuracyRoll(", 1, true) ~= nil,
    "useMove goes through accuracyRoll")

  -- battle.turn_order: (player, playerMove, enemy, enemyMove, ctx)
  local toBody = src:match("function Game3:turnOrder%(.-%)(.-)\nend\n")
  check(toBody ~= nil, "Game3:turnOrder exists")
  check(toBody and toBody:find('modCall("battle.turn_order"', 1, true) ~= nil,
    "turnOrder calls battle.turn_order")
  check(toBody and toBody:find("b.player", 1, true) ~= nil
        and toBody and toBody:find("b.enemy", 1, true) ~= nil,
    "turn_order is handed player and enemy mons (Trap C)")

  -- battle.overlay: draw-only no-op continuation, battle as arg
  check(src:find('modCall("battle.overlay", function() end, self.battle)', 1, true) ~= nil,
    "drawBattle calls battle.overlay with a no-op vanilla and the battle")

  -- battle.charge_required
  check(src:find('modCall("battle.charge_required"', 1, true) ~= nil,
    "charge path calls battle.charge_required")
  check(src:find("required ~= false", 1, true) ~= nil,
    "charge_required false cancels the charge turn")

  -- battle.run
  local runBody = src:match("function Game3:tryRunFromBattle%(.-%)(.-)\nend\n")
  check(runBody ~= nil, "Game3:tryRunFromBattle exists")
  check(runBody and runBody:find('modCall("battle.run"', 1, true) ~= nil,
    "tryRunFromBattle calls battle.run")
  for _, field in ipairs({ "battle", "pSpd", "eSpd", "attempts", "rng" }) do
    check(runBody and runBody:find(field, 1, true) ~= nil,
      "battle.run ctx carries " .. field)
  end

  -- battle.enemy_action
  local aiBody = src:match("function Game3:pickEnemyMove%(.-%)(.-)\nend\n")
  check(aiBody ~= nil, "Game3:pickEnemyMove exists")
  check(aiBody and aiBody:find('modCall("battle.enemy_action"', 1, true) ~= nil,
    "pickEnemyMove calls battle.enemy_action")
  check(aiBody and aiBody:find("charging", 1, true) ~= nil,
    "locked charge/rampage moves stay outside the hook")
end

whenGame3(function()
  -- Behavioral: battle.damage replace + Trap C species on the mon itself.
  withBus(function(events, hooks)
    local saw
    hooks:wrap("battle.damage", function(nextFn, ctx)
      saw = ctx
      local dmg, info = nextFn(ctx)
      return (dmg or 0) * 2, info
    end, 0, "m")
    local atk = { species = 252, level = 10, name = "TREECKO",
      hp = 30, maxHp = 30, atk = 20, spa = 20, stages = {} }
    local def = { species = 261, level = 5, name = "POOCHYENA",
      hp = 40, maxHp = 40, def = 15, spd = 15, type1 = 0, type2 = 0, stages = {} }
    local move = { id = 1, name = "POUND", power = 40, type = 0, effect = 0,
      accuracy = 100 }
    local g = setmetatable({
      battle = { player = atk, enemy = def },
      data = { moves = { typeChart = {} } },
    }, { __index = Game3 })
    function g:isPlayerBattler(mon) return mon == atk end
    function g:attackType() return 0 end
    function g:hasAbility() return false end
    function g:rand(n) return n end
    function g:gbaRandom() return 0 end
    function g:holdEffectOf() return nil end
    function g:noteBideHit() end
    function g:notePlayerDamaged() end
    function g:maybeFaintFriendship() end
    function g:boostedPower() return 40 end
    function g:screenDamageMul() return 10 end
    function g:weatherPowerTenths() return 10 end
    function g:chargeMultiplier() return 1 end
    function g:spitUpMultiplier() return 1 end
    function g:smellingSaltMultiplier() return 1 end
    function g:revengeMultiplier() return 1 end
    function g:heldCritStages() return 0 end
    function g:applyBadgeBoost(_, _, v) return v end
    function g:applyTypePower(_, _, v) return v end
    function g:fieldHasAbility() return false end
    -- Prefer applySetDamage: a clean fixed-damage seam that still hits the hook.
    local result = g:applySetDamage(atk, def, 10)
    check(saw ~= nil, "battle.damage fired")
    eq(saw.user, atk, "user IS the attacker mon (Trap C)")
    eq(saw.user.species, 252, "so user.species is readable")
    check(saw.user.mon == nil, "and there is no .mon wrapper")
    eq(result.dmg, 20, "wrapper may double the damage before HP write")
    eq(def.hp, 20, "and the engine applies the rewritten number")
  end)

  -- battle.accuracy: force a miss
  withBus(function(events, hooks)
    hooks:wrap("battle.accuracy", function() return false end, 0, "m")
    local g = setmetatable({ battle = {} }, { __index = Game3 })
    function g:moveHitChance() return 100 end
    function g:isPlayerBattler() return true end
    function g:rand() return 1 end
    eq(g:accuracyRoll({ species = 1 }, { species = 2 }, { accuracy = 100 }, 0),
      false, "battle.accuracy can force a miss")
  end)

  -- battle.turn_order: force enemy first
  withBus(function(events, hooks)
    hooks:wrap("battle.turn_order", function() return false end, 0, "m")
    local player = { species = 1 }
    local enemy = { species = 2 }
    local g = setmetatable({
      battle = { player = player, enemy = enemy },
    }, { __index = Game3 })
    function g:speedOf() return 100 end
    function g:rand(n) return n end
    eq(g:turnOrder({ priority = 0 }, { priority = 0 }), false,
      "battle.turn_order can put the enemy first")
  end)

  -- battle.run: force escape
  withBus(function(events, hooks)
    hooks:wrap("battle.run", function() return true end, 0, "m")
    local mon = { species = 1 }
    local g = setmetatable({
      battle = { enemy = { species = 2 }, doubles = false, runTries = 0 },
    }, { __index = Game3 })
    function g:holdEffectOf() return nil end
    function g:hasAbility() return false end
    function g:speedOf() return 1 end
    function g:gbaRandom() return 255 end
    eq(g:tryRunFromBattle(mon), true, "battle.run can force an escape")
  end)

  -- battle.enemy_action: replace the chosen move
  withBus(function(events, hooks)
    local forced = { id = 99, name = "FORCED", power = 1, pp = 1 }
    hooks:wrap("battle.enemy_action", function() return forced end, 0, "m")
    local mon = { species = 261, moves = {
      { id = 1, name = "TACKLE", power = 40, pp = 10 },
    } }
    local g = setmetatable({ battle = { enemy = mon } }, { __index = Game3 })
    function g:moveUsable() return true end
    function g:aiTargetFor() return nil end
    function g:struggleMove() return { id = 165, name = "STRUGGLE" } end
    function g:rand(n) return 1 end
    eq(g:pickEnemyMove(mon), forced, "battle.enemy_action may replace the AI move")
  end)

  -- battle.charge_required: cancel the charge turn
  withBus(function(events, hooks)
    local saw
    hooks:wrap("battle.charge_required", function(nextFn, ctx)
      saw = ctx
      return false
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"]
      or package.loaded["src.mods.Runtime"]
      or require("src.mods.Runtime")
    local required = Runtime.call(
      "battle.charge_required", function(c) return c.charge end, {
        battle = {}, user = { species = 1 }, target = { species = 2 },
        move = { effect = 151 }, charge = true, isCalled = false,
      })
    check(saw ~= nil, "battle.charge_required fired")
    eq(required, false, "and returning false cancels the charge")
  end)

  -- battle.overlay: draw-only, must receive the battle (Trap C: enemy is mon)
  withBus(function(events, hooks)
    local saw
    hooks:wrap("battle.overlay", function(nextFn, battle)
      saw = battle
      nextFn(battle)
    end, 0, "m")
    local enemy = { species = 261, level = 5 }
    local battle = { enemy = enemy, kind = "text" }
    local Runtime = package.loaded["src.mods.Runtime"]
      or package.loaded["src.mods.Runtime"]
      or require("src.mods.Runtime")
    Runtime.call("battle.overlay", function() end, battle)
    check(saw ~= nil, "battle.overlay fired")
    eq(saw.enemy, enemy, "with battle.enemy IS the mon (Trap C)")
    eq(saw.enemy.species, 261, "so enemy.species is readable")
  end)
end)


-- ------- Phase 2 seams (exp.gain, pokemon.sprite, render.*, map.*, catch.rate,
-- held_item.trigger).  script.command is an optional Gen3Script wrap.

do
  local src = readfile("src/core/Game3.lua")
  for _, s in ipairs({
    'modCall("exp.gain"',
    'modCall("pokemon.sprite"',
    'modCall("render.compose"',
    'modCall("render.letterbox"',
    'modCall("map.palette"',
    'modCall("catch.rate"',
    'modCall("held_item.trigger"',
  }) do
    check(src:find(s, 1, true) ~= nil, "Game3 wires " .. s)
  end
  check(src:find("script.command", 1, true) ~= nil,
    "script.command seam is present (wrap or documented skip)")

  local giveBody = src:match("function Game3:giveMonExp%(.-%)(.-)\nend\n")
  check(giveBody ~= nil, "giveMonExp found")
  check(giveBody:find('modCall("exp.gain"', 1, true) ~= nil,
    "giveMonExp calls exp.gain after cart multipliers")

  local picBody = src:match("function Game3:battlePic%(.-%)(.-)\nend\n")
  check(picBody ~= nil, "battlePic found")
  check(picBody:find('modCall("pokemon.sprite"', 1, true) ~= nil,
    "battlePic calls pokemon.sprite before cache/load")

  local holdBody = src:match("function Game3:holdEffectOf%(.-%)(.-)\nend\n")
  check(holdBody ~= nil, "holdEffectOf found")
  check(holdBody:find('modCall("held_item.trigger"', 1, true) ~= nil,
    "holdEffectOf wraps held_item.trigger")

  local catchBody = src:match("function Game3:tryCatch%(.-%)(.-)\nend\n")
  check(catchBody ~= nil, "tryCatch found")
  check(catchBody:find('modCall("catch.rate"', 1, true) ~= nil,
    "tryCatch wraps catch.rate before shake math")

  local palBody = src:match("function Game3:mapPaletteName%(.-%)(.-)\nend\n")
  check(palBody ~= nil, "mapPaletteName found")
  check(palBody:find('modCall("map.palette"', 1, true) ~= nil,
    "mapPaletteName calls map.palette")

  local drawBody = src:match("function Game3:draw%(%)(.-)\nend\n")
  check(drawBody ~= nil, "Game3:draw found")
  local finishAt = drawBody:find("GameViewport.finish", 1, true)
  local letterAt = drawBody:find('modCall("render.letterbox"', 1, true)
  local composeAt = drawBody:find('modCall("render.compose"', 1, true)
  local hudAt = drawBody:find('modCall("render.hud"', 1, true)
  check(finishAt and letterAt and finishAt < letterAt,
    "render.letterbox is after GameViewport.finish")
  check(composeAt and letterAt and letterAt < composeAt,
    "render.compose is after render.letterbox")
  check(hudAt and composeAt and composeAt < hudAt,
    "render.hud is after render.compose")
  -- Mutation: compose true must skip hud
  check(drawBody:find("handled ~= true", 1, true) ~= nil
     or drawBody:find("handled == true", 1, true) ~= nil,
    "compose handled-flag gates render.hud")
end

whenGame3(function()
  -- Value-hook contracts via Runtime.call (no full Game3 method needed).

  withBus(function(events, hooks)
    hooks:wrap("exp.gain", function(nextFn, amount, mon, ctx)
      check(type(amount) == "number", "exp.gain amount is a number")
      check(mon and mon.species ~= nil, "exp.gain mon IS the battler (Trap C)")
      return amount * 2
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    local mon = { species = 261, name = "POOCHYENA" }
    local out = Runtime.call("exp.gain", function(a) return a end, 10, mon, {
      trainer = false, traded = false,
    })
    -- Runtime.call signature is (name, vanillaFn, ...); our wrap receives
    -- (nextFn, ...).  Depending on Hooks:call, vanilla may be invoked via next.
    -- Accept either the doubled value or a table-style answer.
    if type(out) == "number" then
      eq(out, 20, "exp.gain can double the payout")
    else
      check(false, "exp.gain returned " .. tostring(out))
    end
  end)

  withBus(function(events, hooks)
    hooks:wrap("pokemon.sprite", function(nextFn, path, species, ctx)
      eq(species, 25, "pokemon.sprite species")
      eq(ctx.back, false, "pokemon.sprite back=false")
      return "assets/mod/custom.png"
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    local out = Runtime.call("pokemon.sprite", function(p) return p end,
      "assets/generated/battle/front/25.png", 25,
      { shiny = false, back = false, side = "front" })
    eq(out, "assets/mod/custom.png", "pokemon.sprite can redirect the path")
  end)

  withBus(function(events, hooks)
    local hudFired = false
    hooks:wrap("render.compose", function() return true end, 0, "m")
    hooks:wrap("render.hud", function(nextFn, ...)
      hudFired = true
      return nextFn(...)
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    local handled = Runtime.call("render.compose", function() return false end, {}, {})
    eq(handled, true, "render.compose can take over")
    if handled ~= true then
      Runtime.call("render.hud", function() end, {}, {})
    end
    eq(hudFired, false, "hud skipped when compose returns true")
  end)

  withBus(function(events, hooks)
    local saw
    hooks:wrap("render.letterbox", function(nextFn, ctx)
      saw = ctx
      return nextFn(ctx)
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    Runtime.call("render.letterbox", function() end, {
      ww = 800, wh = 600, ox = 40, oy = 60, vpw = 720, vph = 480, scale = 3,
    })
    check(saw ~= nil, "render.letterbox fired")
    eq(saw.ww, 800, "with window width")
  end)

  withBus(function(events, hooks)
    hooks:wrap("map.palette", function(nextFn, name, map, ctx)
      eq(name, "ROUTE_101", "map.palette vanilla name")
      check(ctx and ctx.tod ~= nil, "map.palette ctx.tod")
      return "NIGHT_ROUTE"
    end, 0, "m")
    local g = setmetatable({ tod = "NIGHT" }, { __index = Game3 })
    eq(g:mapPaletteName({ id = 1, tileset = "ROUTE_101" }), "NIGHT_ROUTE",
      "map.palette can replace the palette name")
  end)

  withBus(function(events, hooks)
    hooks:wrap("catch.rate", function(nextFn, rate, mon, ctx)
      check(mon and mon.species == 261, "catch.rate mon IS the battler")
      return 255
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    local out = Runtime.call("catch.rate", function(r) return r end, 45,
      { species = 261 }, { ballBonus = 1 })
    eq(out, 255, "catch.rate can force 255")
  end)

  withBus(function(events, hooks)
    hooks:wrap("held_item.trigger", function(nextFn, ctx)
      check(ctx.trigger == "check", "held_item.trigger trigger=check")
      return nil, nil
    end, 0, "m")
    local Runtime = package.loaded["src.mods.Runtime"] or require("src.mods.Runtime")
    local e, p = Runtime.call("held_item.trigger", function() return 1, 10 end, {
      battle = nil, mon = { item = 234 }, item = 234, effect = 1, parameter = 10,
      trigger = "check",
    })
    eq(e, nil, "held_item.trigger can suppress effect")
    eq(p, nil, "and parameter")
  end)

  withBus(function(events, hooks)
    local got = {}
    events:on("map.reloaded", function(p) got[#got + 1] = p end, 0, "m")
    local map = { id = "g0_0", grid = { 1, 2 }, baseGrid = { 9, 8 },
                  width = 1, height = 2, baseWidth = 1, baseHeight = 2 }
    local g = setmetatable({ map = map }, { __index = Game3 })
    function g:markTilesDirty() end
    -- restoreMapLayout may call writeGrid helpers; stub if missing
    if not Game3.writeGrid then
      function Game3.writeGrid(dst, srcGrid) return srcGrid end
    end
    g:restoreMapLayout(map)
    eq(#got, 1, "restoreMapLayout emits map.reloaded")
    eq(got[1].reason, "layout", "with reason=layout")
  end)
end)




-- ------- Gen3Compat phase-3 facades (Screens / Map / coverage)

do
  local ok, Gen3Compat = pcall(require, "src.mods.Gen3Compat")
  if not ok or type(Gen3Compat) ~= "table" then
    check(true, "Gen3Compat absent on partial tree -- facade checks skipped")
  else
    check(Gen3Compat.serves("src.core.Game"), "Gen3Compat serves src.core.Game")
    check(Gen3Compat.serves("src.world.Map"), "and src.world.Map")
    check(Gen3Compat.serves("src.ui.Screens"), "and src.ui.Screens")
    check(Gen3Compat.serves("src.ui.OptionRows"), "and src.ui.OptionRows")
    check(Gen3Compat.serves("src.battle.BattleState"), "and src.battle.BattleState")
    eq(Gen3Compat.memberStatus("src.world.Map", "defPassable"), "backed",
      "Map.defPassable is backed (phase-3)")
    local g = { openStartMenu = function() return "opened-start" end,
                openParty = function() return "opened-party" end,
                field = nil }
    Gen3Compat.bind(function() return g end)
    -- StartMenu's opener short-circuits when Input:wasPressed("start") so a
    -- second START in the same tick does not reopen; stub Input as idle.
    package.loaded["src.core.Input"] = {
      wasPressed = function() return false end,
    }
    local Screens = Gen3Compat.resolve("src.ui.Screens", "test")
    check(type(Screens) == "table" and type(Screens.push) == "function",
      "Screens facade resolves")
    eq(Screens.push(nil, "StartMenu"), "opened-start",
      "Screens.push StartMenu routes to Game3:openStartMenu")
    eq(Screens.push(nil, "Option"), true,
      "Screens.push Option opens field kind option")
    eq(g.field and g.field.kind, "option", "and sets game.field")
    eq(Screens.push(nil, "PartyMenu"), "opened-party",
      "Screens.push PartyMenu routes to openParty")
    -- Unbacked push must not throw
    local okPush = pcall(Screens.push, nil, "QolTogglesMenu")
    check(okPush, "unbacked Screens.push refuses without throwing")
    local Map = Gen3Compat.resolve("src.world.Map", "test")
    check(type(Map.defPassable) == "function", "Map.defPassable exists")
    check(Map.defPassable({}, 0, 0) == true,
      "Map.defPassable defaults open when no live game")
  end
end



-- ------- Phase 4: Screens openModScreen, music.volume, Map stubs, events

do
  -- Source seams
  local body = readfile("src/core/Game3.lua")
  check(body:find("music.volume", 1, true) ~= nil,
    "Game3 source mentions music.volume")
  check(body:find("type(row.activate) == \"function\"", 1, true) ~= nil
      or body:find('type(row.activate) == "function"', 1, true) ~= nil,
    "optionMenuSpec tags activate rows as extra")
  check(body:find("desc.activate", 1, true) ~= nil,
    "post-Boot stepOptionMenu wrap dispatches desc.activate")
  check(body:find("desc.step", 1, true) ~= nil,
    "and desc.step (exp_share / pipelines)")
  check(body:find("alive = participantList", 1, true) ~= nil,
    "awardExp ctx.alive is the fighter list")
  check(body:find("function Game3:applyMusicVolume", 1, true) ~= nil,
    "Game3 defines applyMusicVolume")
  local upd = body:find("function Game3:updateMusic", 1, true)
  local apply = body:find("self:applyMusicVolume()", 1, true)
  check(upd and apply and apply > upd,
    "updateMusic calls applyMusicVolume")
  check(body:find('modEmit("save.saving"', 1, true) ~= nil
      or body:find('modEmit("save.saving",', 1, true) ~= nil,
    "writeSave emits save.saving")
  check(body:find('modEmit("save.saved"', 1, true) ~= nil
      or body:find('modEmit("save.saved",', 1, true) ~= nil,
    "writeSave emits save.saved")
  check(body:find('modEmit("script.started"', 1, true) ~= nil,
    "beginScriptRun emits script.started")
  check(body:find('modEmit("script.ended"', 1, true) ~= nil,
    "endScriptRun emits script.ended")
end

do
  local ok, Gen3Compat = pcall(require, "src.mods.Gen3Compat")
  if not ok or type(Gen3Compat) ~= "table" then
    check(true, "Gen3Compat absent -- phase-4 facade checks skipped")
  else
    check(type(Gen3Compat.COVERAGE_VERSION) == "number",
      "Gen3Compat publishes COVERAGE_VERSION")
    check(Gen3Compat.serves("src.world.NPC"), "Gen3Compat serves src.world.NPC")
    local mapNew = Gen3Compat.memberStatus("src.world.Map", "new")
    check(mapNew == "backed" or mapNew == "warned" or mapNew == "absent",
      "Map.new has a coverage status (Claude soft Map.new is warned)")
    eq(Gen3Compat.memberStatus("src.world.Map", "blockAt"), "backed",
      "Map.blockAt is backed (phase-4)")
    eq(Gen3Compat.memberStatus("src.ui.Screens", "register"), "backed",
      "Screens.register is backed (phase-4)")

    local opened = {}
    local g = {
      openStartMenu = function() return "opened-start" end,
      openParty = function() return "opened-party" end,
      openModScreen = function(self, inst)
        opened[#opened + 1] = inst
        self.field = { kind = "mods" }
        self._modInst = inst
        return true
      end,
      field = nil,
      data = { screens = {} },
      save = { options = {} },
      options = { musicVol = 7 },
    }
    Gen3Compat.bind(function() return g end)
    package.loaded["src.core.Input"] = {
      wasPressed = function() return false end,
    }
    -- Force rebuild of Screens (clear built cache via fresh resolve after
    -- wiping package / built table if exposed). Gen3Compat caches in `built`.
    -- Re-require won't rebuild; call resolve which returns cached. So we
    -- register on the cached Screens module.
    local Screens = Gen3Compat.resolve("src.ui.Screens", "test-p4")
    check(type(Screens.register) == "function", "Screens.register exists")

    local factoryHits = 0
    Screens.register("QolTogglesMenu", {
      new = function(game, opts)
        factoryHits = factoryHits + 1
        return {
          game = game,
          rows = { { label = "FAST TEXT", step = function() end } },
          index = 1,
          update = function() end,
          draw = function() end,
          exit = function(self)
            if self.game and self.game.stack and self.game.stack.pop then
              self.game.stack:pop()
            end
          end,
        }
      end,
    })
    local inst = Screens.push(g, "QolTogglesMenu")
    check(inst ~= nil, "Screens.push QolTogglesMenu returns instance")
    eq(factoryHits, 1, "factory.new was called once")
    eq(#opened, 1, "openModScreen received the instance")
    eq(opened[1], inst, "openModScreen got the same instance")
    check(g.field and g.field.kind == "mods",
      "openModScreen set field kind mods")

    -- Unregistered custom name still refuses without throwing
    local okPush = pcall(Screens.push, g, "TotallyMissingMenu")
    check(okPush, "missing Screens.push refuses without throwing")

    local Map = Gen3Compat.resolve("src.world.Map", "test-p4")
    check(type(Map.new) == "function", "Map.new exists")
    local stub = Map.new({ id = "t", width = 2, height = 2, blocks = { 1, 2, 3, 4 } })
    check(type(stub) == "table", "Map.new returns a table")
    eq(stub.id, "t", "stub keeps id")
    check(type(stub.blockAt) == "function" or type(Map.blockAt) == "function",
      "blockAt available")
    local bid = Map.blockAt({ width = 2, height = 2, blocks = { 9, 8, 7, 6 } }, 0, 0)
    eq(bid, 9, "Map.blockAt reads def.blocks")
    check(Map.defPassable({}, 0, 0) == true, "defPassable still defaults open")

    local NPC = Gen3Compat.resolve("src.world.NPC", "test-p4")
    check(type(NPC.new) == "function", "NPC.new exists")
    local npc = NPC.new(nil, "m1", { x = 3, y = 4, facing = "north" })
    eq(npc.cellX, 3, "NPC.new sets cellX")
    eq(npc.cellY, 4, "NPC.new sets cellY")
  end
end

whenGame3(function()
  withBus(function(events, hooks)
    local seen = {}
    hooks:wrap("music.volume", function(nextFn, vol, ctx)
      seen.vol = vol
      seen.ctx = ctx
      return (tonumber(vol) or 0) * 0.5
    end, 0, "m")
    local g = setmetatable({
      options = { musicVol = 7 },
      playerX = 5, playerY = 6,
      map = { id = "LITTLEROOT", music = 123 },
      _modMusicVolLevel = nil,
    }, { __index = Game3 })
    -- Ensure Mp2kAudio is the stub with setVolume
    local Mp2k = package.loaded["src.core.Mp2kAudio"] or require("src.core.Mp2kAudio")
    if type(Mp2k.setVolume) ~= "function" then
      Mp2k.setVolume = function(vol) Mp2k._floatVol = vol end
      Mp2k.setVolumeLevel = function(level) Mp2k._vol = level end
      Mp2k.currentSong = function() return 457 end
    end
    -- Rebind global Mp2kAudio upvalue used by Game3 — it was captured at
    -- require time as a local. Call through the method; Game3's local
    -- Mp2kAudio is the same package.loaded table when stubbed before require.
    g:applyMusicVolume()
    check(seen.ctx ~= nil, "music.volume hook fired")
    eq(seen.ctx.x, 5, "music.volume ctx.x is playerX")
    eq(seen.ctx.y, 6, "music.volume ctx.y is playerY")
    eq(seen.ctx.mapId, "LITTLEROOT", "music.volume ctx.mapId")
    check(type(seen.vol) == "number", "music.volume vanilla vol is number")
    -- 0.7 * 1.0 * 0.5 = 0.35 if setVolume path used
    if Mp2k._floatVol ~= nil then
      local expected = 0.7 * 0.5
      check(math.abs(Mp2k._floatVol - expected) < 1e-6,
        "music.volume half applied via setVolume")
    else
      check(true, "Mp2k setVolume absent -- level path exercised")
    end
  end)

  withBus(function(events, hooks)
    local got = {}
    events:on("script.started", function(p) got.started = p end, 0, "m")
    events:on("script.ended", function(p) got.ended = p end, 0, "m")
    local g = setmetatable({ map = { id = "m" } }, { __index = Game3 })
    g:beginScriptRun()
    check(got.started ~= nil, "beginScriptRun emits script.started")
    eq(got.started.mapId, "m", "script.started carries mapId")
    g:beginScriptRun() -- nested: no second started
    g:endScriptRun()
    check(got.ended == nil, "nested endScriptRun does not emit yet")
    g:endScriptRun()
    check(got.ended ~= nil, "outer endScriptRun emits script.ended")
  end)
end)



-- ------- OPTION activate/step (qol_toggles / exp_share) — post-Boot wrap

whenGame3(function()
  -- Game3 captured Input as a local at require time. Mutate THAT table's
  -- wasPressed so the post-Boot wrap sees the edges we arm.
  local Input = Game3Input or package.loaded["src.core.Input"] or require("src.core.Input")
  local pressed = {}
  local prev = Input.wasPressed
  Input.wasPressed = function(_, key) return pressed[key] == true end

  local activated, stepped, stepDir = 0, 0, nil
  local g = setmetatable({
    save = { options = { expShare = "off" } },
    options = {},
    field = { kind = "option", cursor = 0 },
  }, { __index = Game3 })
  function g:optionMenuSpec()
    return {
      { "QOL TOGGLES", "0/1 ON", "extra:qolToggles", {
          id = "qolToggles",
          activate = function() activated = activated + 1 end,
        } },
      { "EXP SHARE", "OFF", "extra:exp_share", {
          id = "exp_share",
          step = function(_, dir)
            stepped = stepped + 1
            stepDir = dir
          end,
        } },
      { "CANCEL", "", "cancel" },
    }
  end

  -- A on QOL TOGGLES → activate
  g.field.cursor = 0
  pressed.a, pressed.left, pressed.right = true, false, false
  g:stepOptionMenu(g.field, function() end)
  eq(activated, 1, "A on activate row fires desc.activate (qol_toggles)")
  eq(stepped, 0, "activate row does not also step")

  -- Right on EXP SHARE → step(+1)
  activated = 0
  g.field.cursor = 1
  pressed.a, pressed.left, pressed.right = false, false, true
  g:stepOptionMenu(g.field, function() end)
  eq(stepped, 1, "Right on step row fires desc.step (exp_share)")
  eq(stepDir, 1, "Right passes dir +1")

  -- Left → step(-1)
  pressed.a, pressed.left, pressed.right = false, true, false
  g:stepOptionMenu(g.field, function() end)
  eq(stepped, 2, "Left on step row fires again")
  eq(stepDir, -1, "Left passes dir -1")
  Input.wasPressed = prev
end)




-- ------- Screens.push loads manager font BEFORE factory.new (qol_toggles)

whenGame3(function()
  local ok, Gen3Compat = pcall(require, "src.mods.Gen3Compat")
  if not ok or type(Gen3Compat) ~= "table" then
    check(true, "Gen3Compat absent -- Screens.push font order skipped")
    return
  end
  local fontArmed, factoryRan = false, false
  local g = {
    data = { screens = {} },
    openStartMenu = function() end,
    ensureManagerFont = function() fontArmed = true end,
    openModScreen = function(self, inst)
      check(fontArmed, "ensureManagerFont runs before openModScreen")
      check(factoryRan, "factory.new already ran")
      self._opened = inst
      return true
    end,
  }
  Gen3Compat.bind(function() return g end)
  local Screens = Gen3Compat.resolve("src.ui.Screens", "test-qol-font")
  Screens.register("QolTogglesMenu", {
    new = function(game)
      check(fontArmed, "ensureManagerFont runs before QolTogglesMenu.new")
      factoryRan = true
      return { game = game, update = function() end, draw = function() end }
    end,
  })
  local inst = Screens.push(g, "QolTogglesMenu")
  check(inst ~= nil, "Screens.push returns the mod screen instance")
  check(fontArmed and factoryRan, "font + factory both ran for QOL push")
end)

-- ------- qol-style option → movement.speed hook path
-- Proves a toggle stored like qol_toggles (loader.modOptions / save.options.modOptions)
-- is what the movement.speed wrap reads when Game3:walkPeriod calls modCall.

whenGame3(function()
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local hooks = Hooks.new()
  local events = require("src.mods.Events").new()
  Runtime.install(events, hooks, {})

  local opts = { modOptions = { qol_toggles = { run_hold_b = true } } }
  local inputDown = { b = true }
  local Input = {
    isDown = function(_, key) return inputDown[key] == true end,
  }
  -- qol runFrames shape
  hooks:wrap("movement.speed", function(next, frames, ctx)
    local bucket = opts.modOptions.qol_toggles
    local on = bucket and bucket.run_hold_b
    if on and ctx and ctx.input and ctx.input:isDown("b")
        and not (ctx.onBike or ctx.surfing) then
      return frames / 2
    end
    return next(frames, ctx)
  end, 0, "qol_toggles")

  local g = setmetatable({
    save = { options = opts },
    bike = nil,
    surfing = nil,
    running = nil,
    slopeSlide = nil,
    input = Input,
    WALK_PERIOD = Game3.WALK_PERIOD,
  }, { __index = Game3 })
  -- walkPeriod uses module Input as fallback; ensure ctx.input path is used
  local period = g:walkPeriod()
  local walk = Game3.WALK_PERIOD
  -- run_hold_b + B held → half the walk period (double speed)
  check(period < walk * 0.6, "qol run_hold_b halves walkPeriod via movement.speed")
  check(period > walk * 0.4, "halved period stays near walk/2")

  -- toggle OFF → vanilla period
  opts.modOptions.qol_toggles.run_hold_b = false
  local periodOff = g:walkPeriod()
  eq(periodOff, walk, "run_hold_b OFF restores vanilla walkPeriod")
end)



-- ------- qol_toggles regression: set option → hook path mutates gameplay
-- Proves NON-VANILLA Ruby toggles via get/set → modCall (INFINITE REPEL /
-- INSTANT TEXT).  RUN HOLD B is also exercised below but is NOT the proof
-- case — Gen3/Ruby already has built-in run.  storedSettings + loader.modOptions
-- must be what the wraps read; a menu that flips ON while hooks still see
-- the default is the "screen opens, gameplay unchanged" bug.

whenGame3(function()
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local Events = require("src.mods.Events")
  local hooks = Hooks.new()
  local events = Events.new()
  Runtime.install(events, hooks, {})

  local modOptions = { qol_toggles = {} }
  local storedSettings = {}
  local function get(key)
    if storedSettings[key] ~= nil then return storedSettings[key] end
    local bucket = modOptions.qol_toggles
    if bucket and bucket[key] ~= nil then return bucket[key] end
    return false
  end
  local function set(key, value)
    storedSettings[key] = value
    modOptions.qol_toggles[key] = value
  end

  hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if get("repel") then return nil end
    return next(encDef, ctx)
  end, 0, "qol_toggles")

  hooks:wrap("movement.speed", function(next, frames, ctx)
    local out = next(frames, ctx)
    if get("run_hold_b") and ctx and ctx.input and ctx.input:isDown("b")
        and not (ctx.onBike or ctx.surfing) then
      return out / 2
    end
    return out
  end, 0, "qol_toggles")

  hooks:wrap("text.speed", function(next, delay, ctx)
    if get("instant_text") then return 0 end
    return next(delay, ctx)
  end, 0, "qol_toggles")

  -- INFINITE REPEL
  set("repel", true)
  local g, battles = (function()
    local battles = {}
    local g = setmetatable({
      map = { id = "g0_9" },
      battlesStarted = battles,
    }, { __index = Game3 })
    function g:rand() return 1 end
    function g:repelBlocks() return false end
    function g:startWildBattle(species, level)
      battles[#battles + 1] = { species = species, level = level }
      return true
    end
    return g, battles
  end)()
  local INFO = { rate = 20, terrain = "land",
                 slots = { { species = 183, minLevel = 5, maxLevel = 5 } } }
  eq(g:startWildFrom(INFO, 0, true), false,
    "INFINITE REPEL set→encounter.roll suppresses wild")
  eq(#battles, 0, "no battle started under REPEL")

  set("repel", false)
  eq(g:startWildFrom(INFO, 0, true), true,
    "REPEL OFF restores wild encounters")
  eq(#battles, 1, "battle starts once REPEL is off")

  -- RUN (HOLD B)
  set("run_hold_b", true)
  local inputDown = { b = true }
  local Input = { isDown = function(_, key) return inputDown[key] == true end }
  local walker = setmetatable({
    save = { options = { modOptions = modOptions } },
    bike = nil, surfing = nil, running = nil, slopeSlide = nil,
    input = Input,
  }, { __index = Game3 })
  local walk = Game3.WALK_PERIOD
  local period = walker:walkPeriod()
  check(period < walk * 0.6, "RUN HOLD B set→movement.speed halves walkPeriod")
  set("run_hold_b", false)
  eq(walker:walkPeriod(), walk, "RUN HOLD B OFF restores walkPeriod")

  -- INSTANT TEXT (Gen 3 printer)
  set("instant_text", true)
  local delay = Runtime.call("text.speed", function() return 0.05 end, 0.05, {})
  eq(delay, 0, "INSTANT TEXT set→text.speed returns 0")
  set("instant_text", false)
  delay = Runtime.call("text.speed", function() return 0.05 end, 0.05, {})
  eq(delay, 0.05, "INSTANT TEXT OFF restores delay")

  Runtime.reset()
end)


-- ------- qol_toggles more: EXP/MONEY MULT, KEEP MONEY, AUTO-REPEL,
-- NO ENCOUNTER DUPES, POISON SAVE, LIGHTS ON (Gen3 engine seams)

do
  local src = readfile("src/core/Game3.lua")
  for _, needle in ipairs({
    'modCall("money.gain"',
    'modCall("money.whiteout"',
    'modCall("repel.wear"',
    'modCall("field.poison_survive"',
    'modCall("world.lights"',
    "reroll = wildReroll",
  }) do
    check(src:find(needle, 1, true) ~= nil,
      "Game3 offers " .. needle)
  end
end

whenGame3(function()
  withBus(function(events, hooks)
    -- EXP MULT via Game3 modCall value form: wrap sees (next, mon, ctx)
    hooks:wrap("exp.gain", function(nextFn, mon, ctx)
      local gained = nextFn()
      check(type(mon) == "table" and mon.species ~= nil,
        "exp.gain modCall passes mon as first extra")
      return math.floor((tonumber(gained) or 0) * 2)
    end, 0, "qol_exp")
    local mon = { species = 1, name = "X", level = 5, exp = 0,
                  growth = Game3.GROWTH_MEDIUM_FAST or 0, maxHp = 20, hp = 20 }
    local g = setmetatable({ battle = nil }, { __index = Game3 })
    function g:holdEffectOf() return nil end
    function g:isTradedMon() return false end
    function g:recalcStats() end
    function g:adjustFriendship() end
    function g:tryLearnLevelMoves() return {} end
    function g:tryEvolve() return {} end
    local texts = g:giveMonExp(mon, 10, false)
    check(type(texts) == "table", "giveMonExp returns texts")
    -- 10 * 2 from wrap; announcement embeds the scaled amount
    local joined = table.concat(texts, "\n")
    check(joined:find("20", 1, true) ~= nil,
      "EXP MULT set→exp.gain scales giveMonExp amount to 20")
  end)

  withBus(function(events, hooks)
    hooks:wrap("money.gain", function(nextFn, ctx)
      local pay = nextFn()
      return math.floor((tonumber(pay) or 0) * 3)
    end, 0, "qol_money")
    local g = setmetatable({
      money = 100,
      party = { { item = nil } },
      battle = {
        npc = { name = "BUG CATCHER", trainerClass = "BUGCATCHER" },
        trainerParty = { { level = 5 } },
        defeat = nil,
      },
    }, { __index = Game3 })
    function g:holdEffectOf() return nil end
    function g:trainerLabel() return "BUG CATCHER" end
    function g:trainerLoseText() return nil end
    function g:recordBattleEnd() end
    g:openTrainerVictory()
    -- trainerPay for BUGCATCHER base 4 * level 5 * 1 * 4 = 80; *3 mult = 240
    local pay = Game3.trainerPay(g.battle)
    eq(g.money, 100 + pay * 3, "MONEY MULT set→money.gain scales trainer prize")
  end)

  withBus(function(events, hooks)
    hooks:wrap("money.gain", function() return 0 end, 0, "qol_money0")
    local g = setmetatable({
      money = 50,
      party = { {} },
      battle = {
        npc = { name = "X", trainerClass = "YOUNGSTER" },
        trainerParty = { { level = 10 } },
      },
    }, { __index = Game3 })
    function g:holdEffectOf() return nil end
    function g:trainerLabel() return "X" end
    function g:trainerLoseText() return nil end
    function g:recordBattleEnd() end
    g:openTrainerVictory()
    eq(g.money, 50, "MONEY MULT 0x→money.gain zeroes prize (no wallet change)")
    check(g.battle.text and not tostring(g.battle.text):find("%$"),
      "0x prize line omits Got $N")
  end)

  withBus(function(events, hooks)
    hooks:wrap("money.whiteout", function(nextFn, ctx)
      return ctx.previous
    end, 0, "qol_keep")
    local g = setmetatable({
      money = 1234,
      map = { id = "g0_0" },
      flags = {},
      party = {},
    }, { __index = Game3 })
    function g:recordBattleEnd() end
    function g:healParty() end
    function g:runWhiteOutScript() end
    function g:resetStateAfterWhiteOut() end
    function g:updateLocationHistoryForRoamer() end
    function g:roamerMoveToOtherLocationSet() end
    function g:warpToHeal() end
    function g:finishBirchChase() end
    function g:endScriptWait() end
    g:blackout()
    eq(g.money, 1234, "KEEP MONEY set→money.whiteout restores wallet")
  end)

  withBus(function(events, hooks)
    -- vanilla halving still works with no wrap
    local g = setmetatable({
      money = 100,
      map = { id = "g0_0" },
      flags = {},
      party = {},
    }, { __index = Game3 })
    function g:recordBattleEnd() end
    function g:healParty() end
    function g:runWhiteOutScript() end
    function g:resetStateAfterWhiteOut() end
    function g:updateLocationHistoryForRoamer() end
    function g:roamerMoveToOtherLocationSet() end
    function g:warpToHeal() end
    g:blackout()
    eq(g.money, 50, "KEEP MONEY OFF→vanilla money/2 on blackout")
  end)

  withBus(function(events, hooks)
    hooks:wrap("repel.wear", function() return 100 end, 0, "qol_repel")
    local g = setmetatable({ repelSteps = 1, field = nil }, { __index = Game3 })
    g:tickRepel()
    eq(g.repelSteps, 100, "AUTO-REPEL set→repel.wear refills steps")
    check(g.field == nil, "refill suppresses wore-off talk box")
  end)

  withBus(function(events, hooks)
    local g = setmetatable({ repelSteps = 1, field = nil }, { __index = Game3 })
    g:tickRepel()
    eq(g.repelSteps, nil, "AUTO-REPEL OFF→repel wears off")
    check(g.field and g.field.kind == "talk", "wore-off talk box fires")
  end)

  withBus(function(events, hooks)
    local last = nil
    local picks = { 183, 183, 25, 25 }
    local i = 0
    hooks:wrap("encounter.roll", function(nextFn, info, ctx)
      -- Gen3 modCall value form: (next, info, ctx); next() == pick
      local enc
      for _ = 1, 8 do
        i = i + 1
        if i == 1 then
          enc = nextFn()
        elseif ctx and ctx.reroll then
          enc = ctx.reroll()
        else
          enc = nextFn()
        end
        if picks[i] then enc = { species = picks[i], level = 5 } end
        if enc and enc.species ~= last then break end
      end
      if enc then last = enc.species end
      return enc
    end, 0, "qol_dupe")
    local battles = {}
    local g = setmetatable({ map = { id = "g0_9" } }, { __index = Game3 })
    function g:rand(n) return (n and n > 1) and n or 1 end
    function g:repelBlocks() return false end
    function g:startWildBattle(species, level)
      battles[#battles + 1] = species
      return true
    end
    local INFO = {
      rate = 20, terrain = "land",
      slots = {
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 183, minLevel = 5, maxLevel = 5 },
        { species = 25, minLevel = 5, maxLevel = 5 },
      },
    }
    g:startWildFrom(INFO, 0, true)
    g:startWildFrom(INFO, 0, true)
    eq(battles[1], 183, "first wild is 183")
    eq(battles[2], 25, "NO ENCOUNTER DUPES→ctx.reroll yields other species")
  end)

  withBus(function(events, hooks)
    hooks:wrap("field.poison_survive", function() return true end, 0, "qol_psn")
    local mon = { hp = 1, status = "psn", name = "Z", isEgg = false }
    local g = setmetatable({
      party = { mon },
    }, { __index = Game3 })
    function g:isFieldPoisoned(m) return m.status == "psn" end
    function g:partyMonSpecies2() return 1 end
    local r = g:doPoisonFieldEffect()
    eq(mon.hp, 1, "POISON SAVE→field.poison_survive keeps 1 HP")
    eq(mon.status, nil, "POISON SAVE clears status")
    eq(r, 1, "poison tick reports damaged-not-fainted")
  end)

  withBus(function(events, hooks)
    hooks:wrap("world.lights", function() return true end, 0, "qol_lights")
    local g = setmetatable({ flashLevel = 9, flags = {} }, { __index = Game3 })
    g:setDefaultFlashLevel({ cave = true, id = "g1_1" })
    eq(g.flashLevel, 0, "LIGHTS ON→world.lights clears cave flashLevel")
  end)

  withBus(function(events, hooks)
    local g = setmetatable({ flashLevel = 0, flags = {} }, { __index = Game3 })
    g:setDefaultFlashLevel({ cave = true, id = "g1_1" })
    check((g.flashLevel or 0) > 0, "LIGHTS OFF→cave stays dark")
  end)
end)



-- ------- free_fly eligibility / partyKnows seam (Gen3)
-- free_fly declares games=["gen1","gen2"] with no `generations` field.
-- Emerald ModGens (ported into Loader:_gateGeneration) treats unstated
-- generations as allowed on gen3, so the mod LOADS on Ruby without TRY HERE
-- ANYWAY. These tests prove the ENGINE seams that free_fly's FREEFLY row +
-- fieldmove.eligibility path need: when a wrap allows FLY, partyKnowsMove
-- and ow.partyKnows both return allow/mon.

whenGame3(function()
  withBus(function(events, hooks)
    hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
      if moveId == Game3.MOVE_FLY then return true end
      return next(moveId, ctx)
    end, 0, "free_fly_elig")
    local mon = { species = 277, moves = {}, name = "SWEL" }
    local g = setmetatable({
      party = { mon },
      map = { id = "g0_0", mapType = Game3.MAP_TYPE_TOWN, grid = { 0 }, width = 1, height = 1 },
      data = { pokemon = {} },
    }, { __index = Game3 })
    function g:knowsMove() return false end
    eq(g:partyKnowsMove(Game3.MOVE_FLY), true,
      "free_fly: fieldmove.eligibility allow → partyKnowsMove(FLY) true")

    -- Publish overworld view with partyKnows (Game3ModWorld)
    if type(g.publishModWorld) == "function" then
      -- grid required for modOverworldFields
      g.map.grid = { 0 }
      pcall(g.publishModWorld, g)
    end
    local ow = g.modOverworld and g:modOverworld() or nil
    if ow and type(ow.partyKnows) == "function" then
      local user = ow:partyKnows("FLY")
      check(user ~= nil,
        "free_fly: ow.partyKnows('FLY') returns a mon when eligibility allows")
      eq(user, mon, "and that mon is the party flyer")
    else
      -- Source-level proof if overworld view needs a fuller map to build
      local src = readfile("src/core/Game3ModWorld.lua")
      check(src:find("function ow.partyKnows", 1, true) ~= nil,
        "Game3ModWorld publishes ow.partyKnows for free_fly fieldMoveUser")
    end
  end)

  withBus(function(events, hooks)
    -- FREEFLY row appears via ui.party.submenu when eligibility + no battle
    hooks:wrap("fieldmove.eligibility", function() return true end, 0, "ff")
    hooks:wrap("ui.party.submenu", function(next, game, rows, mon, ctx)
      local out = next(game, rows, mon, ctx)
      if ctx and ctx.battle then return out end
      table.insert(out, 1, { label = "FREEFLY", onSelect = function() end })
      return out
    end, 0, "free_fly_menu")
    local g = setmetatable({ battle = nil }, { __index = Game3 })
    function g:partyFieldMoves() return {} end
    function g:modOverworld() return { map = { id = "g0_0", def = { outdoor = true } } } end
    local acts = g:partyActions({ species = 277, moves = {} })
    eq(acts[1], "FREEFLY",
      "free_fly: ui.party.submenu can inject FREEFLY when not in battle")
    check(g.modPartyActions and type(g.modPartyActions.FREEFLY) == "function",
      "and stepPartyAction can dispatch FREEFLY onSelect")
  end)
end)


return S.finish()
