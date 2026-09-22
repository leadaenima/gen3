-- THE TWO FACADES A GEN 3 MOD REACHES FOR: mod.battle and mod.world's verbs.
--
-- `mod.battle` was nil on every Ruby boot, for one reason: Loader's
-- GENERATION_HOMES carried a BattleAPI for generations 1 and 2 and none for 3,
-- so the __index arm resolved no module and answered nil.  A nil facade gives
-- a companion UI nothing to fall back to -- it cannot tell "no battle running"
-- from "this game has no battle API".
--
-- `mod.world` did exist, but its action half was a table of stubs answering
-- `nil, reason`.  Four of those -- warpTo, canFly, flyTo, startWildBattle --
-- are things Game3 already does through verbs of its own, so they are real now
-- and the rest stay honest gaps.
--
-- What is pinned here:
--
--   * generation 3 resolves a BattleAPI at all, and it is Ruby's, not Red's;
--   * snapshot() reads Ruby's battle SHAPE -- battle.player IS the mon, not a
--     battler wrapping one -- and answers nil when no fight is running;
--   * revision only moves when something a reader would redraw for changed;
--   * submit() refuses with a reason rather than being absent, so a
--     cross-generation mod gets a string instead of a crash;
--   * the implemented world verbs reject bad input BEFORE touching the game,
--     and the gap table never claims a verb it does not have.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local BattleAPI = require("src.battle.gen3.BattleAPI")
local WorldAPI = require("src.world.gen3.WorldAPI")

local S = require("tests.harness").suite("gen3 mod facades")
local check, eq = S.check, S.eq

-- ------- the loader wires a Gen 3 battle arm at all

do
  local src = io.open("src/mods/Loader.lua"):read("a")
  local homes = src:match("local GENERATION_HOMES = (%b{})")
  check(homes ~= nil, "the loader has a generation homes table")
  check(homes:find("src.battle.gen3.BattleAPI", 1, true) ~= nil,
    "generation 3 names a BattleAPI")
  check(homes:find("src.world.gen3.WorldAPI", 1, true) ~= nil,
    "and still names its WorldAPI")
end

-- ------- a stand-in Game3
--
-- Only the fields these two facades read.  A fake rather than a boot because
-- the shape is the thing under test: if BattleAPI reached for Gen 1's
-- `battle.player.mon`, this fake would answer nil and the assertions below
-- would catch it.

local function mon(species, name, level, hp, maxHp, moves)
  return { species = species, name = name, level = level, hp = hp,
           maxHp = maxHp, moves = moves or {}, stages = {},
           type1 = 12, type2 = 12 }
end

local function fakeGame(battle)
  local warps, battles = {}, {}
  local g = {
    battle = battle,
    party = { mon(277, "TREECKO", 12, 34, 34) },
    map = { id = "g0_9", grid = { 1, 2, 3, 4 }, width = 2, height = 2 },
    playerX = 1, playerY = 1, facing = "down",
    warps = warps, battlesStarted = battles,
    knownMoves = {}, badges = {},
  }
  function g:lookupMap(group, num)
    if group == 0 and (num == 9 or num == 16) then
      return { id = ("g%d_%d"):format(group, num) }
    end
    return nil
  end
  function g:scriptWarp(group, num, warpId, x, y)
    warps[#warps + 1] = { group = group, num = num, warpId = warpId,
                          x = x, y = y }
    return true
  end
  function g:partyKnowsMove(id) return self.knownMoves[id] == true end
  function g:hasBadge(n) return self.badges[n] == true end
  function g:startWildBattle(species, level)
    battles[#battles + 1] = { species = species, level = level }
    return true
  end
  function g:flyTo(dest)
    self.flewTo = dest
    return true
  end
  function g:speciesRow(id) return { name = "SPECIES" .. tostring(id) } end
  return g
end

-- ------- BattleAPI

do
  local g = fakeGame(nil)
  local api = BattleAPI.new(g)
  check(api ~= nil, "a Gen 3 battle api is constructed")
  eq(api:snapshot(), nil, "no battle means no snapshot")
  local ok, why = api:submit({ id = 1, kind = "menu", choice = "fight" })
  eq(ok, nil, "submit outside a battle refuses")
  eq(why, "no battle", "and says why")
end

do
  -- Ruby's shape: battle.player IS the mon.  A reader written against Gen 1
  -- would look for battle.player.mon and find nothing.
  local battle = {
    kind = "menu", turns = 3, text = "Wild POOCHYENA appeared!",
    cursor = 0, fightCursor = 0, partyCursor = 0,
    player = mon(277, "TREECKO", 12, 20, 34,
      { { id = 1, name = "POUND", pp = 35, maxPp = 35, power = 40 } }),
    enemy = mon(261, "POOCHYENA", 5, 21, 21),
  }
  local g = fakeGame(battle)
  local api = BattleAPI.new(g)
  local snap = api:snapshot()
  check(type(snap) == "table", "a running battle produces a snapshot")
  -- stated before anything indexes it: a reader that went looking for Gen 1's
  -- battle.player.mon finds nil here, and this says so rather than throwing
  check(type(snap.player) == "table",
    "the player is read off battle.player, which on Ruby IS the mon")
  check(type(snap.enemy) == "table", "and the enemy off battle.enemy")
  eq(snap.kind, "wild", "no trainer and no safari reads as a wild battle")
  eq(snap.catchable, true, "which is catchable")
  eq(snap.prompt, "menu", "battle.kind menu maps to the Gen 1 menu prompt")
  eq(snap.turn, 3, "the turn comes from battle.turns")
  eq(snap.player.name, "TREECKO", "the player mon is read off battle.player")
  eq(snap.player.hp, 20, "with its live hp")
  eq(snap.player.maxHp, 34, "and its max")
  eq(snap.enemy.name, "POOCHYENA", "and the enemy off battle.enemy")
  eq(snap.message[1], "Wild POOCHYENA appeared!", "the message is the text")
  eq(#snap.moves, 1, "moves come from the player mon")
  eq(snap.moves[1].name, "POUND", "with their names")
  eq(snap.moves[1].slot, 1, "and their slot")
  eq(#snap.party, 1, "the party is the game's own")
  eq(snap.party[1].slot, 1, "with slots")

  -- prompts that have no Gen 1 meaning must not invent one
  battle.kind = "fight"
  eq(api:snapshot().prompt, "moves", "the fight menu is the move prompt")
  battle.kind = "evolve"
  eq(api:snapshot().prompt, "locked",
    "a screen with no Gen 1 meaning is locked, not guessed")
  battle.kind = "intro"
  eq(api:snapshot().prompt, "advance", "the intro advances")

  -- kinds
  battle.isTrainer = true
  eq(api:snapshot().kind, "trainer", "a trainer flag reads as a trainer fight")
  eq(api:snapshot().catchable, false, "which is not catchable")
  battle.isTrainer = nil
  battle.safari = { balls = 30 }
  eq(api:snapshot().kind, "safari", "a safari context reads as safari")
  eq(api:snapshot().safariBalls, 30, "and reports its balls")
  battle.safari = nil
end

do
  -- revision is the thing a reader polls, so it must be quiet when nothing
  -- changed and must move when something did
  local battle = {
    kind = "menu", turns = 1, text = "x",
    player = mon(277, "TREECKO", 12, 20, 34),
    enemy = mon(261, "POOCHYENA", 5, 21, 21),
  }
  local api = BattleAPI.new(fakeGame(battle))
  local r1 = api:snapshot().revision
  eq(api:snapshot().revision, r1, "an unchanged battle keeps its revision")
  eq(api:snapshot().revision, r1, "twice over")
  battle.player.hp = 19
  local r2 = api:snapshot().revision
  check(r2 ~= r1, "a hp change moves the revision")
  battle.text = "different"
  check(api:snapshot().revision ~= r2, "so does a new message")
end

do
  -- present and refusing beats absent: a Gen 1 mod calls submit and must get
  -- a string back, not a "attempt to call a nil value"
  local battle = { kind = "menu", player = mon(1, "A", 1, 1, 1),
                   enemy = mon(2, "B", 1, 1, 1) }
  local api = BattleAPI.new(fakeGame(battle))
  check(type(api.submit) == "function", "submit exists")
  local ok, why = api:submit({ id = 1, kind = "menu", choice = "fight" })
  eq(ok, nil, "and refuses")
  check(type(why) == "string" and why:find("mod.input", 1, true) ~= nil,
    "naming the seam that does work")
  local bad, badWhy = api:submit("not a table")
  eq(bad, nil, "a non-table intent is refused")
  check(type(badWhy) == "string", "with a reason")
end

-- ------- the world verbs

local function worldFor(g)
  return WorldAPI.new(g, "test_mod")
end

do
  local g = fakeGame(nil)
  local w = worldFor(g)

  -- every refusal must happen BEFORE the game is touched
  local a, why = w:warpTo("NOT_A_MAP_ID", 1, 1)
  eq(a, nil, "a non Gen 3 map id is refused")
  check(why:find("g0_9", 1, true) ~= nil, "and the reason shows the shape wanted")
  eq(#g.warps, 0, "and nothing was warped")

  a, why = w:warpTo("g99_99", 1, 1)
  eq(a, nil, "an unknown map is refused")
  eq(why, "unknown map: g99_99", "by name")
  eq(#g.warps, 0, "still nothing warped")

  a = w:warpTo("g0_16", "x", 1)
  eq(a, nil, "non-integer coordinates are refused")
  eq(#g.warps, 0, "still nothing warped")

  a = w:warpTo("g0_16", 1.5, 1)
  eq(a, nil, "and so is a fractional one")
  eq(#g.warps, 0, "still nothing warped")

  -- the real thing goes through Game3's own verb
  eq(w:warpTo("g0_16", 5, 6, "up"), true, "a good warp is taken")
  eq(#g.warps, 1, "exactly one warp was issued")
  eq(g.warps[1].group, 0, "to the right group")
  eq(g.warps[1].num, 16, "and map")
  eq(g.warps[1].x, 5, "at the x asked for")
  eq(g.warps[1].y, 6, "and the y")
  eq(g.facing, "up", "and the facing was applied")
end

do
  local g = fakeGame(nil)
  local w = worldFor(g)
  eq(w:canFly(), false, "no FLY in the party means no fly")
  eq(select(1, w:flyTo("g0_9")), nil, "and flyTo refuses")

  local Game3 = require("src.core.Game3")

  -- THREE GATES, TESTED ONE AT A TIME.  canFly asks the game for the move,
  -- the badge and the map, and any one of them refusing is enough -- so each
  -- case below leaves exactly ONE of them failing.  Tested any other way the
  -- assertions pass for the wrong reason: with an indoor map, dropping the
  -- badge check entirely still answers false and the test still goes green.
  g.map.mapType = Game3.MAP_TYPE_TOWN
  g.knownMoves[19] = true          -- Game3.MOVE_FLY
  g.badges[6] = true
  eq(w:canFly(), true, "move, badge and an outdoor map allow fly")

  g.badges[6] = false
  eq(w:canFly(), false, "the badge alone missing refuses it")
  g.badges[6] = true

  g.knownMoves[19] = false
  eq(w:canFly(), false, "the move alone missing refuses it")
  g.knownMoves[19] = true

  g.map.mapType = Game3.MAP_TYPE_INDOOR or 8
  eq(w:canFly(), false, "and an indoor map alone refuses it")
  eq(w:canFly(), false, "which is the cart's own rule, not the party's")
end

do
  local g = fakeGame(nil)
  local w = worldFor(g)
  eq(select(1, w:startWildBattle("x", 5)), nil, "a non-numeric species is refused")
  eq(select(1, w:startWildBattle(261, "x")), nil, "and a non-numeric level")
  eq(#g.battlesStarted, 0, "neither started a battle")
  eq(w:startWildBattle(261, 5), true, "a good one starts")
  eq(#g.battlesStarted, 1, "exactly one")
  eq(g.battlesStarted[1].species, 261, "with the species asked for")
end

do
  -- no overworld is its own answer, separate from bad input
  local w = worldFor({ })
  eq(select(1, w:warpTo("g0_16", 1, 1)), nil, "warpTo needs a world")
  eq(select(2, w:warpTo("g0_16", 1, 1)), "no overworld", "and says so")
  eq(w:canFly(), false, "canFly is false without a world, not an error")
end

do
  -- the gap table must not claim a verb that now exists, and the verbs it
  -- does list must still answer the two-value shape
  local gaps = WorldAPI.UNIMPLEMENTED
  check(type(gaps) == "table", "the gap table is published")
  for _, name in ipairs({ "warpTo", "canFly", "flyTo", "startWildBattle" }) do
    eq(gaps[name], nil, name .. " is implemented, so it is not listed as a gap")
    check(type(WorldAPI[name]) == "function", name .. " is a real function")
  end
  local remaining = 0
  for name, reason in pairs(gaps) do
    remaining = remaining + 1
    check(type(reason) == "string" and reason ~= "",
      name .. " states a reason")
    local w = worldFor(fakeGame(nil))
    local value, why = w[name](w)
    eq(value, nil, name .. " still answers nil")
    eq(why, reason, "with the published reason")
  end
  check(remaining > 0, "and the honest gaps are still declared")
end

-- ------- a mod's own screen, opened on Game3's stack
--
-- Ruby has no general state stack -- its menus are field states -- but it
-- runs a real StateStack for the mod manager, and a mod screen borrows those
-- rails.  What it must NOT borrow is the manager's exit: that returns the
-- player to the START menu with the cursor on MODS, and a screen opened while
-- walking has to come back to walking.

do
  local Gen3Compat = require("src.mods.Gen3Compat")
  local pushed, opened = {}, {}
  local stack = {
    states = {},
    push = function(self, inst) self.states[#self.states + 1] = inst end,
  }
  local g = {
    data = { screens = {} },
    field = nil,
    stack = nil,
    openStartMenu = function() return true end,
    modOptionsStore = function() end,
    ensureManagerFont = function() end,
    modStack = function() return stack end,
  }
  -- a stand-in for Game3:openModScreen with the same contract
  function g:openModScreen(inst)
    if type(inst) ~= "table" then return false end
    opened[#opened + 1] = inst
    self.modScreenReturn = self.field
    self.modScreenOpen = true
    self.field = { kind = "mods" }
    return true
  end
  -- THE CLOSE IS THE ENGINE'S, NOT A STAND-IN.  An earlier version of this
  -- suite wrote its own closeModScreen here and asserted against that, which
  -- pinned the test's reimplementation and nothing else: deleting Game3's
  -- restore branch entirely left it green.  Game3.closeModManager is called
  -- directly on this fake instead, so the assertions are about the shipped
  -- rule -- a mod screen returns to the field it was opened from, and only
  -- the manager falls back to the START menu.
  local Game3 = require("src.core.Game3")
  function g:closeModScreen()
    return Game3.closeModManager(self)
  end
  function g:startMenuIndex() return 7 end

  Gen3Compat.bind(function() return g end)
  local Screens = Gen3Compat.resolve("src.ui.Screens")

  -- nothing registered: the old degrade path, not a crash
  eq(Screens.push(nil, "NoSuchScreen"), nil, "an unregistered screen refuses")
  eq(#opened, 0, "and opens nothing")

  -- a registered factory table
  local built = 0
  g.data.screens.QuestLog = { new = function(game)
    built = built + 1
    return { marker = "quest" }
  end }
  local inst = Screens.push(nil, "QuestLog")
  eq(built, 1, "the factory was called once")
  check(type(inst) == "table", "and handed back the instance")
  eq(inst.screenId, "QuestLog", "stamped with its id")
  eq(#opened, 1, "which was opened on the game")
  eq(g.field.kind, "mods", "the field switched to the mod-screen rail")

  -- and it comes back to WALKING, not to the START menu
  g:closeModScreen()
  eq(g.field, nil, "closing returns the player to walking, not the START menu")

  -- a bare function is a factory too (Gen 1's other accepted form)
  g.data.screens.Bare = function() return { marker = "bare" } end
  local bare = Screens.push(nil, "Bare")
  check(type(bare) == "table", "a bare function factory works")
  eq(bare.screenId, "Bare", "and is stamped")
  g:closeModScreen()

  -- a factory that throws must refuse, not propagate
  g.data.screens.Exploding = { new = function() error("boom") end }
  local before = #opened
  -- pcall'd HERE too: the point is that the throw does not escape Screens.push
  -- and take the game with it, so the assertion has to survive it escaping in
  -- order to report that it did
  local survived, blew = pcall(Screens.push, nil, "Exploding")
  check(survived, "a throwing factory does not propagate out of push")
  eq(survived and blew or nil, nil, "it refuses instead")
  eq(#opened, before, "and nothing was opened")

  -- a record that is not a factory at all
  g.data.screens.Nonsense = 42
  eq(Screens.push(nil, "Nonsense"), nil, "a non-factory record refuses")

  -- the field a screen returns to is the one that was live, whatever it was
  g.field = { kind = "menu", cursor = 3 }
  Screens.push(nil, "QuestLog")
  eq(g.field.kind, "mods", "opening from a menu still switches rail")
  g:closeModScreen()
  eq(g.field.kind, "menu", "and closing returns to that menu")
  eq(g.field.cursor, 3, "with its cursor intact")

  -- the other half of the same branch: with no screen open, the engine's close
  -- is the MANAGER's close, which lands on the START menu with MODS selected
  g.field = { kind = "anything" }
  g.modScreenOpen, g.modScreenReturn = nil, nil
  g:closeModScreen()
  eq(g.field.kind, "menu",
    "closing with no mod screen open is the manager's exit: the START menu")
  eq(g.field.cursor, 7, "with the cursor the game chose")

  Gen3Compat.bind(nil)
end

return S.finish()
