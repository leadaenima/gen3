-- Ruby Phase 11: Game3 field SAVE / title CONTINUE.
-- Fixture data only -- no .gba.
--   luajit tests/engine/ruby_save_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby save")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
SaveData.resetSlotState()

eq(Game3.SAVE_FORMAT, "gen3-ruby-1", "save format id")
eq(Game3.SAVE_FILE, "save3_ruby.lua", "legacy flat name before launcher slots")
eq(Game3.new().flags[Game3.FLAG_HIDE_BIRCH_IN_LAB], nil,
  "new game does not pre-hide Birch; map scripts do")
eq(Game3.new().flags[Game3.FLAG_HIDE_MOM_UPSTAIRS], nil,
  "new game does not pre-hide Mom; map scripts do")

local function rubySavePath()
  local id = SaveData.activeSlot("ruby")
  if id then return "saves/ruby/" .. id .. ".lua" end
  return Game3.SAVE_FILE
end

local function wipeRubySave()
  local fs = love.filesystem
  fs.remove(Game3.SAVE_FILE)
  fs.remove(Game3.SAVE_FILE .. ".bak")
  fs.remove(Game3.SAVE_FILE .. ".tmp")
  local i = 1
  while i <= 8 do
    local p = "saves/ruby/slot" .. i .. ".lua"
    fs.remove(p)
    fs.remove(p .. ".bak")
    fs.remove(p .. ".tmp")
    i = i + 1
  end
  local opts = SaveData.loadOptions()
  if type(opts.saveSlots) == "table" then opts.saveSlots.ruby = nil end
  SaveData.saveOptions(opts)
  SaveData.resetSlotState()
end

local function withGame()
  local g = Game3.new()
  g.data.pokemon = {
    byIndex = {
      [280] = {
        name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
        spa = 70, spd = 50, type1 = 10, type2 = 10, ability1 = 66,
        catchRate = 45, expYield = 65, growthRate = 3,
        learnset = { { move = 10, level = 1 } },
      },
      [290] = {
        name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
        spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
        expYield = 54, growthRate = 0,
      },
    },
  }
  g.data.moves = {
    byId = {
      [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35, accuracy = 100 },
      [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35, accuracy = 95 },
    },
  }
  -- decoration.c gDecorations rows for the ids these tests handle.
  -- 21 PRETTY FLOWERS is DECORCAT_PLANT; 1 SMALL DESK is DECORCAT_DESK.
  g.data.decorations = {
    count = 121,
    byId = {
      [1] = { permission = 0, shape = 0, width = 1, height = 1,
              category = 0, price = 3000, tiles = { 0x28 }, gfx = 0x28 },
      [21] = { permission = 2, shape = 5, width = 1, height = 2,
               category = 2, price = 3000, tiles = { 0x40, 0x48 }, gfx = 0x40 },
    },
  }
  local map = {
    id = "g0_9", name = "Littleroot Town",
    width = 4, height = 2, grid = { 0, 0, 0, 0, 0, 0, 0, 0 },
    spawn = { x = 1, y = 1 },
    objects = { {
      x = 2, y = 0, graphicsId = 59, itemId = 4, flagId = 0x300,
    } },
  }
  g.data.maps = { start = "g0_9", maps = { g0_9 = map } }
  g.map = map
  g.party = { g:makeMon(280, 5) }
  g.bag = {}
  g.money = 3000
  g.flags = {}
  g.phase = "play"
  g.playerX, g.playerY = 3, 1
  g.facing = "west"
  g:enterMap(map, 3, 1, true)
  return g, map
end

local g = withGame()
g.party[1].hp = 7
g:addItem(13, 2)
g.money = 2400
g.flags[0x200] = true
g.flags[0x300] = true
g.flags[Game3.hiddenFlag(4)] = true
local snap = g:snapshotSave()
eq(snap.format, Game3.SAVE_FORMAT, "snapshot stamps the format")
eq(snap.engine, "gen3", "and the engine")
eq(snap.mapId, "g0_9", "map id is stored")
eq(snap.x, 3, "player x")
eq(snap.y, 1, "player y")
eq(snap.facing, "west", "facing")
eq(snap.money, 2400, "money")
eq(snap.party[1].species, 280, "Torchic is in the party")
eq(snap.party[1].hp, 7, "current HP is stored")
eq(type(snap.party[1].ivs), "table", "IVs are stored")
eq(snap.party[1].ivs.hp, g.party[1].ivs.hp, "HP IV round-trips in the snapshot")
eq(snap.bag[1].id, 13, "bag item id")
eq(snap.bag[1].count, 2, "bag count")
eq(snap.flags[0x200], true, "trainer flags persist")
eq(snap.flags[Game3.hiddenFlag(4)], true, "hidden-item flags persist")
eq(snap.seen[1], 280, "the starter is seen")
eq(snap.caught[1], 280, "and caught")
eq(snap.gender, Game3.GENDER_MALE, "gender defaults to boy")

check(g:writeSave(), "writeSave succeeds on the field")
check(g:hasSave(), "the file is readable")

local loaded, map = withGame()
loaded.party = { loaded:makeMon(280, 5) }
loaded.money = 3000
loaded.bag = {}
loaded.flags = {}
loaded.playerX, loaded.playerY = 0, 0
check(loaded:continueSave(), "CONTINUE applies the snapshot")
eq(loaded.phase, "play", "CONTINUE drops into the field")
eq(loaded.money, 2400, "money comes back")
eq(loaded.party[1].hp, 7, "HP comes back")
eq(loaded.party[1].ivs.hp, g.party[1].ivs.hp, "IVs come back")
eq(Game3.natureName(loaded.party[1].pid), Game3.natureName(g.party[1].pid),
  "nature follows the saved pid")
eq(loaded:itemCount(13), 2, "bag comes back")
eq(loaded.flags[0x200], true, "beaten-trainer flag comes back")
eq(loaded.playerX, 3, "position x comes back")
eq(loaded.playerY, 1, "position y comes back")
eq(loaded.facing, "west", "facing comes back")
eq(loaded:npcsFor(map)[1], nil, "a taken item ball stays gone after reload")
check(loaded:hasSeen(280), "seen comes back")
check(loaded:hasCaught(280), "caught comes back")
eq(loaded.gender, Game3.GENDER_MALE, "gender comes back")

local battler = withGame()
battler.phase = "battle"
check(not battler:writeSave(), "a battle cannot be saved")

local encoded = love.filesystem.read(rubySavePath())
local decoded = SaveSerializer.decode(encoded)
eq(decoded.party[1].species, 280, "the file round-trips through SaveSerializer")

wipeRubySave()
local empty = Game3.new()
check(not empty:hasSave(), "removing the file clears hasSave")

local pre = withGame()
pre.party = {}
pre.flags = {}
check(pre:writeSave(), "an empty party can be saved before the starter")
local resumed = withGame()
resumed.party = { resumed:makeMon(280, 5) }
check(resumed:continueSave(), "CONTINUE reloads a pre-starter save")
eq(#resumed.party, 0, "and keeps the party empty")
wipeRubySave()

local boxed = withGame()
boxed:addToParty(boxed:makeMon(290, 2))
local ok, msg = boxed:depositFromParty(2)
check(ok, "a second party mon deposits")
eq(#boxed.pc[1], 1, "into BOX 1")
eq(boxed.pc[1][1].species, 290, "the boxed mon is Wurmple")
check(boxed:writeSave(), "a boxed save writes")
local restored = withGame()
check(restored:continueSave(), "CONTINUE reloads boxed mons")
eq(restored.pc[1][1].species, 290, "the boxed Wurmple comes back")
eq(#restored.party, 1, "the party stays one")
check(restored:hasCaught(290), "a boxed species stays owned")
check(restored:hasCaught(280), "and so does the party starter")
wipeRubySave()

local dexless = withGame()
local bare = dexless:snapshotSave()
bare.caught = nil
bare.seen = nil
check(dexless:applySave(bare), "a save without caught still applies")
check(dexless:hasCaught(280), "owned species are rebuilt from the party")
check(dexless:hasSeen(280), "and so is seen")
wipeRubySave()

local old = withGame()
local snap = old:snapshotSave()
eq(#snap.pc, Game3.BOX_COUNT, "the snapshot stores 14 boxes")
snap.pc = nil
check(old:applySave(snap), "a save without pc still applies")
eq(#old.pc[1], 0, "and loads an empty PC")

;(function()
local g = withGame()
g.lastHeal = { mapId = "g0_9", x = 4, y = 5 }
g.repelSteps = 87
local snap = g:snapshotSave()
eq(snap.healMapId, "g0_9", "heal map is stored")
eq(snap.healX, 4, "heal x")
eq(snap.healY, 5, "heal y")
eq(snap.repelSteps, 87, "repel steps are stored")
check(g:writeSave(), "heal/repel save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores heal/repel")
eq(loaded.lastHeal.mapId, "g0_9", "heal map comes back")
eq(loaded.lastHeal.x, 4, "heal x comes back")
eq(loaded.lastHeal.y, 5, "heal y comes back")
eq(loaded.repelSteps, 87, "repel steps come back")
wipeRubySave()
local bare = withGame()
bare.lastHeal = { mapId = "g0_9", x = 1, y = 1 }
bare.repelSteps = 10
local oldSnap = bare:snapshotSave()
oldSnap.healMapId, oldSnap.healX, oldSnap.healY, oldSnap.repelSteps = nil, nil, nil, nil
check(bare:applySave(oldSnap), "a save without heal/repel still applies")
eq(bare.lastHeal, nil, "missing heal stays unset")
eq(bare.repelSteps, nil, "missing repel stays unset")
end)()

;(function()
local g = withGame()
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
check(g:depositToDaycare(2), "daycare save deposits")
g.daycare[1].steps = 40
check(g:writeSave(), "daycare save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores daycare")
eq(loaded:daycareCount(), 1, "the slot comes back")
eq(loaded.daycare[1].mon.species, 290, "Wurmple comes back")
eq(loaded.daycare[1].steps, 40, "steps come back")
eq(#loaded.party, 1, "the party stayed one")
wipeRubySave()
local bare = withGame()
bare.daycare = { { mon = bare:makeMon(290, 2), steps = 3 } }
local oldSnap = bare:snapshotSave()
oldSnap.daycare = nil
check(bare:applySave(oldSnap), "a save without daycare still applies")
eq(bare:daycareCount(), 0, "missing daycare stays empty")
end)()

-- Regression: daycareTakeRows() re-runs daycarePreview() every frame the
-- take-list is on screen (input handling and draw both call it). Preview
-- must not queue a real "wants to learn" prompt, or leaving the list open
-- floods pendingLearn and the player gets stuck answering the same prompt
-- forever after closing the DAY-CARE menu.
;(function()
local g = withGame()
g.data.pokemon = g.data.pokemon or {}
g.data.pokemon.byIndex = g.data.pokemon.byIndex or {}
g.data.pokemon.byIndex[280] = {
  name = "TORCHIC", learnset = { { move = 16, level = 10 } },
  growthRate = 3, hp = 45, atk = 60, def = 40, spa = 70, spd = 50, spe = 45,
}
local full = {
  name = "TORCHIC", species = 280, level = 9, growth = 3,
  exp = Game3.expAtLevel(3, 10) - 8,
  hp = 22, maxHp = 22,
  moves = {
    { id = 10, name = "SCRATCH" }, { id = 45, name = "GROWL" },
    { id = 52, name = "EMBER" }, { id = 98, name = "QUICK ATTACK" },
  },
}
g.party = { full, g:makeMon(290, 2) }
check(g:depositToDaycare(1), "deposit the almost-level-10 chick")
g.daycare[1].steps = 8
for i = 1, 200 do g:daycareTakeRows() end
check(not (g.pendingLearn and g.pendingLearn[1]),
  "browsing the take list 200x does not queue a learn prompt")
check(g:takeFromDaycare(1), "take the chick back out")
check(g.pendingLearn and g.pendingLearn[1], "taking it out queues the real prompt")
eq(#g.pendingLearn, 1, "exactly one prompt, not a flood")
eq(g.pendingLearn[1].move, 16, "Peck is waiting")
end)()

;(function()
local g = withGame()
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.daycarePending = 12345
g.eggCycleSteps = 40
g.party[2].isEgg = true
g.party[2].name = "EGG"
g.party[2].hatchLeft = 7
g.caught = { [280] = true }
check(g:writeSave(), "egg save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores pending egg")
eq(loaded.daycarePending, 12345, "pending pid comes back")
eq(loaded.eggCycleSteps, 40, "egg-cycle steps come back")
eq(loaded.party[2].isEgg, true, "party egg comes back")
eq(loaded.party[2].name, "EGG", "nickname stays EGG")
eq(loaded.party[2].hatchLeft, 7, "hatch counter comes back")
eq(loaded.caught[290], nil, "the egg is not harvested as caught")
wipeRubySave()
local bare = withGame()
bare.daycarePending = 9
bare.eggCycleSteps = 3
local oldSnap = bare:snapshotSave()
oldSnap.daycarePending, oldSnap.eggCycleSteps = nil, nil
check(bare:applySave(oldSnap), "a save without egg fields still applies")
eq(bare.daycarePending, nil, "missing pending stays unset")
eq(bare.eggCycleSteps, 0, "missing cycle stays 0")
end)()

;(function()
local g = withGame()
g.party[1].cool = 80
g.party[1].ribbons = { cool = 2 }
check(g:writeSave(), "ribbon save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores ribbons")
eq(loaded.party[1].cool, 80, "Cool condition comes back")
eq(loaded.party[1].ribbons.cool, 2, "Hyper Cool ribbon comes back")
wipeRubySave()
local bare = withGame()
bare.party[1].ribbons = { cute = 1 }
local oldSnap = bare:snapshotSave()
oldSnap.party[1].ribbons = nil
oldSnap.party[1].cool = nil
check(bare:applySave(oldSnap), "a save without ribbons still applies")
eq(bare.party[1].ribbons, nil, "missing ribbons stay unset")
end)()

;(function()
local g = withGame()
g.secretBase = {
  id = 42, mapId = "g0_9", x = 2, y = 0, outX = 2, outY = 1,
}
g:enterMap(g:secretBaseMap(), 3, 4, false)
check(g:writeSave(), "secret base save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the secret base")
eq(loaded.map.id, "secret_base", "CONTINUE from the interior rebuilds it")
eq(loaded.playerX, 3, "interior x comes back")
eq(loaded.playerY, 4, "interior y comes back")
eq(loaded.secretBase.id, 42, "spot id comes back")
eq(loaded.secretBase.mapId, "g0_9", "overworld map comes back")
eq(loaded.secretBase.outX, 2, "exit x comes back")
-- VAR_CURRENT_SECRET_BASE is the ROM's INDEX into secretBases[20], not the
-- layout id: secret_base.c reads secretBases[VarGet(..)].secretBaseId for the
-- layout. Own base is always slot 0 (recordPlayerSecretBase and the
-- "someone else's base" PC-tile check already assume that). The layout stays
-- on secretBase.id, asserted above.
eq(loaded.scriptVars[Game3.VAR_CURRENT_SECRET_BASE], 0, "var 0x4054 is the own-base slot")
wipeRubySave()
local bare = withGame()
bare.secretBase = { id = 1, mapId = "g0_9", x = 0, y = 0, outX = 0, outY = 0 }
local oldSnap = bare:snapshotSave()
oldSnap.secretBase = nil
check(bare:applySave(oldSnap), "a save without a secret base still applies")
eq(bare.secretBase, nil, "missing secret base stays unset")
end)()

;(function()
local g = withGame()
g.customName = "CHAZ"
g.playSeconds = 3723
g.options = {
  textSpeed = 1, battleScene = false, battleStyle = "set", stereo = false,
}
g.flags[Game3.FLAG_BADGE01_GET] = true
g.caught[280] = true
local snap = g:snapshotSave()
eq(snap.playerName, "CHAZ", "CONTINUE stores the trainer name")
eq(snap.playSeconds, 3723, "and the play clock")
eq(snap.dexCount, 1, "and the POKeDEX count")
eq(snap.badgeCount, 1, "and the badge count")
eq(snap.options.battleStyle, "set", "and the OPTION menu")
check(g:writeSave(), "CONTINUE fields write")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores name and time")
eq(loaded:playerName(), "CHAZ", "the trainer name comes back")
eq(loaded.playSeconds, 3723, "play time comes back")
eq(loaded.options.battleStyle, "set", "SET style comes back")
eq(loaded.options.battleScene, false, "BATTLE SCENE OFF comes back")
eq(loaded:badgeCount(), 1, "the Stone Badge comes back")
wipeRubySave()
local bare = withGame()
bare.playSeconds = 9
local oldSnap = bare:snapshotSave()
oldSnap.playerName, oldSnap.playSeconds, oldSnap.options = nil, nil, nil
oldSnap.dexCount, oldSnap.badgeCount = nil, nil
check(bare:applySave(oldSnap), "a save without CONTINUE fields still applies")
eq(bare.playSeconds, 0, "missing time stays zero")
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
check(type(g.trainerId) == "number", "a new game has a trainer ID")
eq(#g:trainerIdString(), 5, "IDNo. is five digits")
eq(g:moneyString(3000), "$3,000", "money uses a $ and commas")
eq(Game3.BADGE_NAMES[1], "STONE", "badge 1 is Stone")
g.field = { kind = "menu", cursor = 2 }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "trainer_card", "START on the name opens the TRAINER CARD")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "menu", "B returns to START")
g.field = { kind = "menu", cursor = 3 }
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "save_ask", "SAVE asks first")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "menu", "B cancels the save")
g:openSaveAsk()
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "talk", "YES writes the file")
check(g.field.text:find("saved the game", 1, true) ~= nil,
  "and uses the pokeruby saved-the-game line")
local id = g.trainerId
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the trainer ID")
eq(loaded.trainerId, id, "the ID comes back")
Input.wasPressed = old
wipeRubySave()
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
eq(g:itemPocket(Game3.ITEM_POTION), Game3.POCKET_ITEMS, "Potion is ITEMS")
eq(g:itemPocket(Game3.ITEM_POKE_BALL), Game3.POCKET_BALLS, "POKe BALL is balls")
eq(g:itemPocket(Game3.ITEM_TM43), Game3.POCKET_TMHM, "TM43 is TMs & HMs")
eq(g:itemPocket(Game3.ITEM_CHERI_BERRY), Game3.POCKET_BERRIES, "Cheri is BERRIES")
eq(g:itemPocket(Game3.ITEM_MACH_BIKE), Game3.POCKET_KEY, "MACH BIKE is KEY ITEMS")
g.data.items = { byId = { [13] = { pocket = 5 } } }
eq(g:itemPocket(13), Game3.POCKET_KEY, "ROM pocket wins when present")
g.data.items = nil
g.party[1].hp = 5
g:addItem(Game3.ITEM_POTION, 1)
g:addItem(Game3.ITEM_POKE_BALL, 3)
g:addItem(Game3.ITEM_TM43, 1)
eq(#g:bagSlotsIn(Game3.POCKET_ITEMS), 1, "ITEMS lists the Potion")
eq(#g:bagSlotsIn(Game3.POCKET_BALLS), 1, "BALLS lists the POKe BALL")
eq(#g:bagSlotsIn(Game3.POCKET_TMHM), 1, "TMs lists TM43")
g.field = { kind = "menu", cursor = g:startMenuIndex("BAG") }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "bag", "START BAG opens the pack")
eq(g.field.pocket, Game3.POCKET_ITEMS, "on the first filled pocket")
Input.wasPressed = function(_, key) return key == "right" end
g:stepField()
eq(g.field.pocket, Game3.POCKET_BALLS, "RIGHT is POKe BALLS")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
-- item_menu.c: A opens the popup first. USE is one entry in it, and for the
-- BALLS pocket the cart's table puts GIVE ahead of it entirely.
eq(g.field.kind, "bag_actions", "A opens the item popup")
eq(g.field.actions[1], "GIVE", "BAG_POCKET_POKE_BALLS leads with GIVE")
eq(g.field.actions[2], "TOSS", "then TOSS")
eq(g.field.actions[#g.field.actions], "CANCEL", "and CANCEL last")
g:openBag()
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "menu", "B returns to START")
eq(g.field.cursor, g:startMenuIndex("BAG"), "on BAG")
g:openBag()
Input.wasPressed = function(_, key) return key == "down" end
g:stepField()
eq(g.field.cursor, 1, "DOWN is CLOSE BAG")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "menu", "A on CLOSE BAG returns to START")
Input.wasPressed = old
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
g.party[2] = g:makeMon(290, 2)
g.party[1].pid = 3
local names = { g.party[1].name, g.party[2].name }
g.field = { kind = "menu", cursor = g:startMenuIndex("POKeMON") }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party", "START POKeMON opens the party")
g:stepField()
eq(g.field.kind, "party_action", "A opens SUMMARY / SWITCH")
eq(g.field.actions[1], "SUMMARY", "SUMMARY is first")
g:stepField()
eq(g.field.kind, "party_summary", "SUMMARY opens the info page")
eq(g.field.page, 0, "page 0 is INFO")
Input.wasPressed = function(_, key) return key == "right" end
g:stepField()
eq(g.field.page, 1, "RIGHT is SKILLS")
g:stepField()
eq(g.field.page, 2, "and then MOVES")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "party_action", "B returns to commands")
g.field.cursor = 1
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party_switch", "SWITCH waits for a slot")
Input.wasPressed = function(_, key) return key == "down" end
g:stepField()
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party", "A swaps and returns")
eq(g.party[1].name, names[2], "slot 1 took slot 2")
eq(g.party[2].name, names[1], "slot 2 took slot 1")
eq(g:partyActions(g.party[1])[3], "ITEM", "ITEM is on the party menu")
Input.wasPressed = old
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
eq(Game3.MSG_WIDTH_PX, 208,
  "FONT3 dialogue inner width is 208px")
eq(Game3.glyphWidth(Game3.fontCode(" ")), 3, "space is 3px")
eq(Game3.glyphWidth(Game3.fontCode("A")), 6, "A is 6px")
local lines = Game3.wrapDialogue(
  "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!")
eq(#lines, 2, "Birch's welcome wraps to two FONT3 lines")
eq(lines[1], "Hi! Sorry to keep you waiting! Welcome to",
  "line 1 fills 208px")
eq(lines[2], "the world of POKeMON!", "line 2 is the rest")
local hard = Game3.wrapDialogue("SUPERCALIFRAGILISTIC")
eq(hard[1], "SUPERCALIFRAGILISTIC", "a 20-glyph word stays on one line")
local split = Game3.wrapDialogue(string.rep("A", 35))
eq(split[1], string.rep("A", 34), "a long token hard-breaks at 208px")
eq(split[2], "A", "and spills the tail")
local nl = Game3.wrapDialogue("HELLO\nWORLD")
eq(nl[1], "HELLO", "\\n is a hard line break")
eq(nl[2], "WORLD", "and starts the next row")

local long = ("The ROCK type is very durable, but it can't stand "
  .. "WATER-type andGRASS-type moves. Come see me afterwards, if you beat "
  .. "the GYM LEADER. Well, go for it!")
eq(#Game3.wrapDialogue(long) > Game3.MSG_LINES, true,
  "gym-guide advice is more than one box")
local g2 = withGame()
g2.field = { kind = "talk", text = long }
g2:stepPrinter(g2.field, 10)
check(not g2:printerBusy(g2.field), "the first box finishes typewriter")
check(g2:dialogueHasMore(g2.field), "a v-arrow remains")
local old2 = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g2:stepField()
eq(g2.field.textPage, 2, "A pages without waiting on the rest of the string")
eq(g2.field.kind, "talk", "the box stays open")
Input.wasPressed = old2

local g = withGame()
g.field = {
  kind = "talk",
  text = "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!",
}
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field, nil, "two FONT3 lines close on one A")
g.field = { kind = "talk", text = "Your POKeMON were restored to full health!" }
g:stepField()
eq(g.field, nil, "the nurse line also fits in one box")
Input.wasPressed = old
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
local prompt = "ACCURACY ROOM, the sign says. Do you want to go through?"
local lines = Game3.wrapDialogue(prompt)
eq(#lines, Game3.MSG_LINES, "the gym door prompt fits in one FONT3 box")
g:openScriptYesNo(prompt)
eq(g.field.kind, "script_yesno", "MSGBOX_YESNO is still yes/no")
g:stepPrinter(g.field, 10)
check(g:yesNoReady(g.field), "YES/NO can show once the box is full")
check(not g:dialogueHasMore(g.field), "there is no leftover page")
g.field.cursor = 1
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.scriptVars[0x800D], 0, "A answers NO")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
Input:init()
eq(Game3.SPECIAL_GET_BERRY_TREE_DATA, 43, "GetBerryTreeData is special 43")
eq(Game3.itemToBerryType(Game3.ITEM_PECHA_BERRY), 3, "Pecha is berry 3")
eq(Game3.itemToBerryType(Game3.ITEM_ORAN_BERRY), 7, "Oran is berry 7")
eq(Game3.berryTypeToItem(3), Game3.ITEM_PECHA_BERRY, "berry 3 is Pecha")
eq(#Game3.NEW_GAME_BERRY_TREES, 160, "80 new-game trees")

local g = withGame()
g:initBerryTrees()
eq(g.berryTrees[1].berry, 3, "Route 102 tree 1 is Pecha")
eq(g.berryTrees[1].stage, Game3.BERRY_STAGE_BERRIES, "and ready to pick")
eq(g.berryTrees[2].berry, 7, "tree 2 is Oran")
eq(g.berryTrees[1].yield, 2, "unwatered yield is min")
g._scriptNpc = { trainerRange = 1, localId = 7 }
g:runSpecial(Game3.SPECIAL_GET_BERRY_TREE_DATA)
eq(g.scriptVars[0x8004], 5, "0x8004 is BERRY_STAGE_BERRIES")
eq(g.scriptVars[0x8006], 2, "0x8006 is the yield")
eq(g.stringVars[1], "PECHA", "STR_VAR_1 is the berry name")
g:runSpecial(Game3.SPECIAL_PLAYER_HAS_BERRIES)
eq(g.scriptVars[0x800D], 0, "the bag has no berries yet")
g:runSpecial(Game3.SPECIAL_PICK_BERRY_TREE)
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), 2, "pick adds the yield")
eq(g.scriptVars[0x8004], 1, "AddBagItem succeeded")
g:runSpecial(Game3.SPECIAL_REMOVE_BERRY_TREE)
g:runSpecial(Game3.SPECIAL_GET_BERRY_TREE_DATA)
eq(g.scriptVars[0x8004], 0, "the plot is empty soil")
g:runSpecial(Game3.SPECIAL_PLAYER_HAS_BERRIES)
eq(g.scriptVars[0x800D], 1, "PlayerHasBerries after the pick")
g:runSpecial(Game3.SPECIAL_BERRY_BAG_MENU)
eq(g.field and g.field.kind, "bag", "ChooseBerry opens the pack")
eq(g.field.pocket, Game3.POCKET_BERRIES, "on the BERRIES pocket")
check(g.field.pickBerry, "ITEMMENULOCATION_BERRY")
check(g:scriptWaiting(), "waitstate holds until a pick")
eq(g.screenFade, nil, "no veil means no fade-in flash")
g:beginScreenFade(Game3.FADE_TO_BLACK)
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
check(g:screenFadeAlpha() >= 0.99, "S_BerryTree held TO_BLACK")
g:runSpecial(Game3.SPECIAL_BERRY_BAG_MENU)
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "the pack fades the veil back in")
local oldPick = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = oldPick
eq(g.scriptVars[Game3.VAR_ITEM_ID], Game3.ITEM_PECHA_BERRY,
  "A writes the highlighted berry")
eq(g.field, nil, "and closes the pack")
g:runSpecial(Game3.SPECIAL_BERRY_BAG_MENU)
oldPick = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = oldPick
eq(g.scriptVars[Game3.VAR_ITEM_ID], 0, "B cancels with item 0")
g.field = nil
g.scriptWait = nil
g.screenFade = nil
-- Same-tick special after fadescreen: alpha is still 0, but the veil exists.
g:beginScreenFade(Game3.FADE_TO_BLACK)
eq(g:screenFadeAlpha() < 0.01, true, "fresh TO_BLACK has not covered yet")
g:runSpecial(Game3.SPECIAL_BERRY_BAG_MENU)
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "ChooseBerry fades in even before the veil is opaque")
g:finishBerryPick(0)
eq(g.field, nil, "cancel still closes the pack")
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "closing the pack keeps the fade-in")
g.screenFade = nil
-- CONTINUE must not keep a plant-bag fade over the zoomed map.
g:beginScreenFade(Game3.FADE_TO_BLACK)
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
g.field = { kind = "bag", pickBerry = true }
g.scriptWait = true
check(g:applySave(g:snapshotSave()), "CONTINUE after a plant fade")
eq(g.screenFade, nil, "CONTINUE drops the veil")
eq(g.field, nil, "and the bag")
eq(g.scriptWait, nil, "and waitstate")

g.scriptVars[Game3.VAR_ITEM_ID] = Game3.ITEM_PECHA_BERRY
local pechaBefore = g:itemCount(Game3.ITEM_PECHA_BERRY)
g:runSpecial(Game3.SPECIAL_PLANT_BERRY_TREE)
eq(g.berryTrees[1].stage, Game3.BERRY_STAGE_PLANTED, "replant is stage 1")
eq(g.berryTrees[1].berry, 3, "and still Pecha")
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), pechaBefore,
  "PlantBerryTree does not spend; the script already removeitem'd")
-- BerryTree_EventScript_1A1577: removeitem VAR_ITEM_ID, 1 then
-- S_PlantBerryTree (special 45 + GAME_STAT_PLANTED_BERRIES).
g:removeBerryTree()
g.scriptVars[Game3.VAR_ITEM_ID] = Game3.ITEM_PECHA_BERRY
local planted = (g.gameStats or {})[Game3.GAME_STAT_PLANTED_BERRIES] or 0
Gen3Script.run(g, {
  { op = "removeitem", item = Game3.VAR_ITEM_ID, count = 1 },
  { op = "special", id = Game3.SPECIAL_PLANT_BERRY_TREE },
  { op = "incrementgamestat", id = Game3.GAME_STAT_PLANTED_BERRIES },
})
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), pechaBefore - 1,
  "talk-to-soil spends one berry, not two")
eq(g.berryTrees[1].stage, Game3.BERRY_STAGE_PLANTED, "and plants it")
eq((g.gameStats or {})[Game3.GAME_STAT_PLANTED_BERRIES], planted + 1,
  "GAME_STAT_PLANTED_BERRIES from the soil script")

local snap = g:snapshotSave()
eq(type(snap.berryTrees), "table", "trees are in the snapshot")
local found
for i = 1, #snap.berryTrees do
  if snap.berryTrees[i].id == 1 then found = snap.berryTrees[i] end
end
eq(found.stage, Game3.BERRY_STAGE_PLANTED, "the planted tree is saved")

g:wipeNewGameState()
eq(g.berryTrees[1].stage, Game3.BERRY_STAGE_BERRIES, "NEW GAME replants")
eq(g.berryTrees[1].berry, 3, "tree 1 is Pecha again")

local host = withGame()
Gen3Script.run(host, {
  { op = "setberrytree", tree = 1, berry = 7, stage = 5 },
})
eq(host.berryTrees[1].berry, 7, "setberrytree plants Oran on tree 1")
eq(host.berryTrees[1].stage, 5, "at the berries stage")

local picker = Game3.new()
picker.phase = "play"
picker.facing = "east"
picker.playerX, picker.playerY = 0, 0
picker:initBerryTrees()
picker.map = { id = "g_berry", width = 3, height = 1, grid = { 0, 0, 0 } }
picker.npcByMap = { g_berry = { {
  x = 1, y = 0, graphicsId = Game3.GFX_BERRY_TREE,
  trainerRange = 1, localId = 7,
  script = {
    { op = "special", id = 43 },
    { op = "compare", var = 0x8004, val = 0 },
    { op = "goto_if", cond = 1, to = 13 },
    { op = "buffernumber", slot = 1, val = 0x8006 },
    { op = "loadword",
      text = "There are {STR_VAR_2} {STR_VAR_1} BERRIES! Do you want to pick?" },
    { op = "callstd", id = 5 },
    { op = "compare", var = 0x800D, val = 1 },
    { op = "goto_if", cond = 1, to = 10 },
    { op = "end" },
    { op = "special", id = 46 },
    { op = "special", id = 47 },
    { op = "end" },
    { op = "message", text = "It's soft, loamy soil." },
    { op = "waitmessage" },
    { op = "end" },
  },
} } }
check(picker:tryTalk(), "A on a berry tree talks")
eq(picker.field.kind, "script_yesno", "ripe berries ask to pick")
check(picker.field.text:find("2 PECHA BERRIES", 1, true) ~= nil,
  "with the yield and name")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
picker:stepField()
Input.wasPressed = old
eq(picker:itemCount(Game3.ITEM_PECHA_BERRY), 2, "YES picks the berries")
eq(picker.berryTrees[1].stage, 0, "and clears the tree")
picker:refreshBerryTreeSprites()
eq(picker.npcByMap.g_berry[1].invisible, true, "empty soil hides the sprite")
picker.field = nil
check(picker:tryTalk(), "talking again is empty soil")
eq(picker.field.text, "It's soft, loamy soil.", "the loamy-soil line")

eq(Game3.ITEM_WAILMER_PAIL, 268, "Wailmer Pail is item 268")
local pailer = Game3.new()
eq(pailer:itemPocket(Game3.ITEM_WAILMER_PAIL), Game3.POCKET_KEY, "key pocket")
eq(pailer:itemName(Game3.ITEM_WAILMER_PAIL), "WAILMER PAIL", "Pail name")
check(not pailer:canGiveHeld(Game3.ITEM_WAILMER_PAIL), "cannot be given")
pailer:initBerryTrees()
pailer:plantBerryTree(1, 3, Game3.BERRY_STAGE_PLANTED, true)
pailer.phase = "play"
pailer.facing = "east"
pailer.playerX, pailer.playerY = 0, 0
pailer.map = { id = "g_pail", width = 3, height = 1, grid = { 0, 0, 0 } }
local treeNpc = pailer:npcFromTemplate({
  x = 1, y = 0, graphicsId = Game3.GFX_BERRY_TREE,
  trainerRange = 1, localId = 1,
}, 1)
eq(treeNpc.invisible, nil, "a planted tree is drawn")
eq(treeNpc.graphicsId, Game3.GFX_BERRY_TREE_EARLY, "planted uses the sprout sheet")
pailer.npcByMap = { g_pail = { treeNpc } }
local okPail, pailMsg = pailer:useFieldItem(Game3.ITEM_WAILMER_PAIL)
check(okPail, "the Pail waters a growing tree")
eq(pailer.berryTrees[1].watered, 1, "one watering")
check(pailMsg:find("delighted", 1, true) ~= nil, "delighted line")
pailer:plantBerryTree(1, 3, Game3.BERRY_STAGE_BERRIES, false)
pailer:refreshBerryTreeSprites()
eq(treeNpc.graphicsId, Game3.GFX_BERRY_TREE_LATE, "ripe uses the tall sheet")
local miss, missMsg = pailer:useFieldItem(Game3.ITEM_WAILMER_PAIL)
check(not miss, "ripe berries cannot be watered")
check(missMsg:find("DAD", 1, true) ~= nil, "Dad's advice")
pailer:plantBerryTree(1, 0, 0, false)
pailer:refreshBerryTreeSprites()
eq(treeNpc.invisible, true, "picked soil is invisible")
check(not pailer:useFieldItem(Game3.ITEM_WAILMER_PAIL), "empty soil cannot be watered")

local healer = Game3.new()
healer.bag = {}
healer.party = { { name = "TORCHIC", hp = 5, maxHp = 19 } }
healer:addItem(Game3.ITEM_ORAN_BERRY, 1)
local okOran, oranMsg = healer:useItemOnMon(healer.party[1], Game3.ITEM_ORAN_BERRY)
check(okOran, "an Oran Berry heals on the field")
eq(healer.party[1].hp, 15, "Oran restores 10 HP")
eq(healer:itemCount(Game3.ITEM_ORAN_BERRY), 0, "and is eaten")
check(oranMsg:find("recovered", 1, true) ~= nil, "heal announces recovery")
healer.party[1].status = "psn"
healer:addItem(Game3.ITEM_PECHA_BERRY, 1)
local okPecha = healer:useItemOnMon(healer.party[1], Game3.ITEM_PECHA_BERRY)
check(okPecha, "a Pecha Berry cures poison")
eq(healer.party[1].status, nil, "poison is gone")
eq(healer:itemCount(Game3.ITEM_PECHA_BERRY), 0, "Pecha is eaten")
healer.party[1].status = "par"
healer:addItem(Game3.ITEM_CHERI_BERRY, 1)
check(healer:useItemOnMon(healer.party[1], Game3.ITEM_CHERI_BERRY),
  "Cheri cures paralysis")
eq(healer.party[1].status, nil, "paralysis is gone")
healer.party[1].hp = 5
healer:addItem(Game3.ITEM_SITRUS_BERRY, 1)
healer:useItemOnMon(healer.party[1], Game3.ITEM_SITRUS_BERRY)
eq(healer.party[1].hp, 19, "Sitrus restores 30, capped at max")

local grower = withGame()
grower:initBerryTrees()
check(grower.berryTrees[1].sparkle, "new-game trees hold a sparkle")
grower:tickBerryTrees(1000)
eq(grower.berryTrees[1].stage, Game3.BERRY_STAGE_BERRIES,
  "sparkle blocks growth")
grower._scriptNpc = { trainerRange = 1, localId = 7 }
grower:berryGetTreeData()
check(not grower.berryTrees[1].sparkle, "talking clears the sparkle")
grower:plantBerryTree(1, 3, Game3.BERRY_STAGE_PLANTED, true)
eq(grower.berryTrees[1].stage, Game3.BERRY_STAGE_PLANTED, "bag plant is stage 1")
grower:tickBerryTrees(Game3.berryStageMinutes(3) * 60)
eq(grower.berryTrees[1].stage, Game3.BERRY_STAGE_SPROUTED,
  "one stage after the duration")
grower:tickBerryTrees(Game3.berryStageMinutes(3) * 3 * 60)
eq(grower.berryTrees[1].stage, Game3.BERRY_STAGE_BERRIES,
  "ripe after four stages")
eq(grower.berryTrees[1].yield, 2, "flowering sets the min yield")
end)()

;(function()
local g = withGame()
g:addItem(Game3.ITEM_ORAN_BERRY, 1)
check(g:giveHeldItem(1, Game3.ITEM_ORAN_BERRY), "GIVE hangs an Oran Berry")
eq(g.party[1].item, Game3.ITEM_ORAN_BERRY, "the party mon holds it")
eq(g:itemCount(Game3.ITEM_ORAN_BERRY), 0, "and the bag loses it")
check(not g:canGiveHeld(Game3.ITEM_HM_CUT), "HMs cannot be given")
g:addItem(Game3.ITEM_PECHA_BERRY, 1)
check(g:giveHeldItem(1, Game3.ITEM_PECHA_BERRY), "a second give swaps")
eq(g.party[1].item, Game3.ITEM_PECHA_BERRY, "Pecha is held")
eq(g:itemCount(Game3.ITEM_ORAN_BERRY), 1, "Oran returns to the bag")
local row = g:snapshotMon(g.party[1])
eq(row.item, Game3.ITEM_PECHA_BERRY, "the held item is saved")
eq(g:restoreMon(row).item, Game3.ITEM_PECHA_BERRY, "and restored")
g:takeHeldItem(1)
eq(g.party[1].item, nil, "TAKE clears the hold")
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), 1, "and bags Pecha")

local eater = Game3.new()
local mon = { name = "TORCHIC", hp = 5, maxHp = 20, item = Game3.ITEM_ORAN_BERRY }
local texts = eater:tickHeldItem(mon)
eq(mon.hp, 15, "held Oran heals 10 at half HP")
eq(mon.item, nil, "and is eaten")
check(texts[1]:find("restored", 1, true) ~= nil, "the heal line names restore")
mon.hp = 20
mon.status = "psn"
mon.item = Game3.ITEM_PECHA_BERRY
texts = eater:tickHeldItem(mon)
eq(mon.status, nil, "held Pecha cures poison")
eq(mon.item, nil, "and is eaten")
check(texts[1]:find("cured", 1, true) ~= nil, "the cure line says so")
mon.hp = 20
mon.item = Game3.ITEM_ORAN_BERRY
eq(#eater:tickHeldItem(mon), 0, "full HP does not eat Oran")
eq(mon.item, Game3.ITEM_ORAN_BERRY, "so the berry stays")
end)()

;(function()
local g = withGame()
g:setScriptVar(Game3.VAR_PETALBURG_WOODS_STATE, 1)
g:setScriptVar(Game3.VAR_OBJ_GFX_ID_0 + 1, Game3.GFX_MAGMA_MEMBER_M)
g.scriptVars[0x800D] = 1
check(g:writeSave(), "story vars write")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores story vars")
eq(loaded:varGet(Game3.VAR_PETALBURG_WOODS_STATE), 1, "woods state comes back")
eq(loaded:varGet(Game3.VAR_OBJ_GFX_ID_0 + 1), Game3.GFX_MAGMA_MEMBER_M,
  "gfx var 1 comes back")
eq(loaded:varGet(0x800D), 0, "special vars are not saved")
wipeRubySave()
local bare = withGame()
bare:setScriptVar(Game3.VAR_PETALBURG_WOODS_STATE, 1)
local oldSnap = bare:snapshotSave()
oldSnap.vars = nil
check(bare:applySave(oldSnap), "a save without vars still applies")
eq(bare:varGet(Game3.VAR_PETALBURG_WOODS_STATE), 0, "missing vars stay 0")
end)()

;(function()
local g = withGame()
g.easyChatPairs = {
  { Game3.ecPack(10, 0), Game3.ecPack(13, 32), pop = 40, maxPop = 50 },
  { Game3.ecPack(10, 1), Game3.ecPack(12, 0), pop = 30, rising = true },
}
check(g:writeSave(), "trend save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the trendy phrase")
eq(Game3.easyChatPhrase(loaded.easyChatPairs[1]), "HOT FISHING",
  "Dewford Hall still says HOT FISHING")
eq(loaded.easyChatPairs[1].pop, 40, "popularity comes back")
wipeRubySave()
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.easyChatPairs = nil
check(bare:applySave(oldSnap), "a save without trends still applies")
eq(#bare.easyChatPairs, 5, "and InitDewfordTrend fills five pairs")
end)()

;(function()
local g = withGame()
g.trainerId = 1000
g.party[1].otId = 49562
g.party[1].otName = "ELYSSA"
check(g:isTradedMon(g.party[1]), "MAKIT is traded")
local row = g:snapshotMon(g.party[1])
eq(row.otId, 49562, "OT id is saved")
eq(row.otName, "ELYSSA", "OT name is saved")
local back = g:restoreMon(row)
eq(back.otId, 49562, "OT id comes back")
eq(back.otName, "ELYSSA", "OT name comes back")
check(g:isTradedMon(back), "so IsTradedMon survives CONTINUE")
end)()

;(function()
local g = withGame()
g.coins = 1234
g:rtcInitLocalTimeOffset(15, 45)
check(g:writeSave(), "coins and clock write")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores coins and clock")
eq(loaded:getCoins(), 1234, "Game Corner till comes back")
eq(loaded.clockHour, 15, "wall-clock hour comes back")
eq(loaded.clockMinute, 45, "and minutes")
wipeRubySave()
end)()

;(function()
local g = withGame()
g.sav1Weather = 8
g.currWeather = 8
g.weatherCycleStage = 2
check(g:writeSave(), "weather writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores weather")
eq(loaded.sav1Weather, 8, "sav1 sandstorm")
eq(loaded.currWeather, 8, "and curr")
eq(loaded.weatherCycleStage, 2, "cycle stage")
wipeRubySave()
end)()

-- Anything ON_LOAD writes has to survive CONTINUE too. Lilycove's
-- LilycoveCity_EventScript_SetWailmerMetatiles stamps six solid metatiles
-- over the cove; applySave applies the saved mapLayoutId AFTER enterMap
-- has already run ON_LOAD, and that layout write blanked them -- the cove
-- came back as open water you could surf straight through. overworld.c
-- runs InitMapLayoutData and only then RunOnLoadMapScript, so ON_LOAD has
-- to end up on top.
;(function()
local g = withGame()
local WAILMER = 656
local cove = {
  id = "g0_cove", layoutId = 700, width = 4, height = 2,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0 },
  spawn = { x = 0, y = 0 },
  mapScripts = {
    onLoad = {
      { op = "setmetatile", x = 2, y = 1, tile = WAILMER, collision = 1 },
    },
  },
}
local pristine = {}
for i = 1, 8 do pristine[i] = cove.grid[i] end
g.data.maps.maps.g0_cove = cove
g.data.maps.layouts = { [700] = {
  width = 4, height = 2, grid = pristine, tileset = cove.tileset } }
g:enterMap(cove, 0, 0, true)
local gi = 1 * cove.width + 2 + 1
eq(Game3.metatileOf(cove.grid[gi]), WAILMER, "ON_LOAD stamps the Wailmer")
eq(Game3.collisionOf(cove.grid[gi]), 1, "and they are solid")
check(g:writeSave(), "save at the cove")

local back = withGame()
back.data.maps.maps.g0_cove = cove
back.data.maps.layouts = g.data.maps.layouts
for i = 1, 8 do cove.grid[i] = pristine[i] end
check(back:continueSave(), "CONTINUE back to the cove")
eq(back.map.id, "g0_cove", "lands at the cove")
eq(back.mapLayoutId, 700, "and keeps the saved layout")
eq(Game3.metatileOf(cove.grid[gi]), WAILMER,
  "the Wailmer are still there, not wiped by the layout write")
eq(Game3.collisionOf(cove.grid[gi]), 1, "and still solid")
eq(Game3.walkable(cove, 2, 1), false, "so you cannot surf past early")
wipeRubySave()
end)()

-- An ON_LOAD setmetatile must not outlive the condition that made it.
-- LilycoveCity_OnLoad only stamps the Wailmer while
-- FLAG_EVIL_TEAM_ESCAPED_IN_SUBMARINE is unset; once the hideout scene
-- sets it, ON_LOAD stops writing them -- but the tiles already baked into
-- this engine's shared cached grid stayed put and kept the cove blocked
-- forever. enterMap reverts map.dirtyTiles before the map scripts run,
-- which is what InitMapLayoutData gives the ROM for free, so setmetatile
-- has to record there the same way writeMetatile does.
;(function()
local g = withGame()
local BLOCK, STORY = 656, 0x070
local cove = {
  id = "g0_cove2", width = 4, height = 2,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0 },
  spawn = { x = 0, y = 0 },
  mapScripts = {
    onLoad = {
      { op = "checkflag", flag = STORY },
      { op = "call_if", cond = 0, body = {
          { op = "setmetatile", x = 2, y = 1, tile = BLOCK, collision = 1 },
        } },
    },
  },
}
g.data.maps.maps.g0_cove2 = cove
local gi = 1 * cove.width + 2 + 1

g:enterMap(cove, 0, 0, true)
eq(Game3.metatileOf(cove.grid[gi]), BLOCK, "ON_LOAD stamps the blocker")
eq(Game3.walkable(cove, 2, 1), false, "and it is solid")

g:enterMap(cove, 0, 0, true)
eq(Game3.metatileOf(cove.grid[gi]), BLOCK, "re-entering keeps it while unset")

-- The story flag goes up: ON_LOAD now skips the write.
g.flags[STORY] = true
g:enterMap(cove, 0, 0, true)
eq(Game3.metatileOf(cove.grid[gi]), 0,
  "and the stale tile is reverted, not left baked in")
eq(Game3.walkable(cove, 2, 1), true, "so the way through is open")
end)()

-- A decoration placed in a base has to survive CONTINUE. The grid stamp
-- is applied by enterMap, but applySave then calls setMapLayoutIndex for
-- the saved layout, which rewrites the grid from the layout table -- so
-- the layout has to re-bake, the way the ROM's InitMapLayoutData runs
-- before InitSecretBaseAppearance rather than after it.
;(function()
local g = withGame()
local base = {
  id = "g25_0", group = 25, index = 0, layoutId = 900,
  width = 6, height = 6, grid = {}, behavior = {}, objects = {}, warps = {},
  spawn = { x = 3, y = 4 },
}
for i = 1, 36 do base.grid[i] = 0 end
local pristine = {}
for i = 1, 36 do pristine[i] = base.grid[i] end
g.data.maps.maps.g25_0 = base
g.data.maps.layouts = {
  [900] = { width = 6, height = 6, grid = pristine, tileset = base.tileset },
}
g.secretBase = {
  id = 0, mapId = "g0_9", x = 2, y = 0, outX = 3, outY = 1,
  decorations = Game3.decorSlots(Game3.DECOR_MAX_SECRET_BASE),
  decorationPos = Game3.decorSlots(Game3.DECOR_MAX_SECRET_BASE),
}
g.secretBase.decorations[1] = 1
g.secretBase.decorationPos[1] = Game3.decorPosPack(2, 3)
g:enterMap(base, 3, 4, true)
local gi = 3 * base.width + 2 + 1
local stamped = Game3.metatileOf(base.grid[gi])
eq(stamped, Game3.DECOR_TILE_BASE + 0x28, "the desk bakes into the grid")
check(g:writeSave(), "save inside the base")

local loaded = withGame()
loaded.data.maps.maps.g25_0 = base
loaded.data.maps.layouts = g.data.maps.layouts
for i = 1, 36 do base.grid[i] = pristine[i] end
base._pristineGrid = nil
check(loaded:continueSave(), "CONTINUE back into the base")
eq(loaded.map.id, "g25_0", "lands inside the base")
eq(loaded.secretBase.decorations[1], 1, "the record still lists the desk")
eq(Game3.metatileOf(base.grid[gi]), stamped,
  "and it is back on the grid, not just in the record")
eq(loaded:varGet(Game3.VAR_SECRET_BASE_INITIALIZED), 0,
  "entering arms SecretBase_OnWarp so sub_80BBDD0 re-shows the dolls")
wipeRubySave()
end)()

;(function()
local g = withGame()
g.trainerId = 2
g:setupMauvilleOldMan()
g:unlockTrendySaying(3)
check(g:addDecoration(21), "PRETTY FLOWERS go into the plant slots")
check(g:writeSave(), "old man writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the old man")
eq(loaded.mauvilleMan.id, Game3.MAUVILLE_MAN_HIPSTER, "id 2 is still hipster")
eq(loaded:trendySayingUnlocked(3), true, "taught trendy word comes back")
eq(loaded:inventoryContainsDecoration(21), true, "PRETTY FLOWERS come back")
eq(loaded:numDecorationsInInventory(), 1, "and only the one")
eq(loaded:getGameStat(Game3.GAME_STAT_SAVED_GAME) >= 1, true,
  "GAME_STAT_SAVED_GAME counted the write")
wipeRubySave()
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.mauvilleMan, oldSnap.trendyUnlocked, oldSnap.decorInv = nil, nil, nil
oldSnap.gameStats = nil
check(bare:applySave(oldSnap), "a save without the man still applies")
eq(type(bare.mauvilleMan), "table", "and SetupMauvilleOldMan fills him")
end)()

;(function()
local g = withGame()
g:ensureGabbyAndTy()
g.gabbyAndTy.battleNum = 1
g.gabbyAndTy.quote = Game3.ecPack(10, 0)
g.gabbyAndTy.valA_4 = 1
g.gabbyAndTy.mapnum = 26
check(g:writeSave(), "gabby writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores Gabby & Ty")
eq(loaded.gabbyAndTy.battleNum, 1, "battleNum comes back")
eq(loaded.gabbyAndTy.quote, Game3.ecPack(10, 0), "and the quote")
eq(loaded.gabbyAndTy.valA_4, 1, "and airing")
eq(loaded.gabbyAndTy.mapnum, 26, "and MAPSEC")
wipeRubySave()
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.gabbyAndTy = nil
check(bare:applySave(oldSnap), "a save without Gabby still applies")
eq(bare.gabbyAndTy.quote, Game3.EC_EMPTY_WORD, "ResetGabbyAndTy fills quote")
eq(bare.gabbyAndTy.battleNum, 0, "and battleNum 0")
bare.gabbyAndTy.battleNum = 4
bare:wipeNewGameState()
eq(bare.gabbyAndTy.battleNum, 0, "NEW GAME wipes battleNum")
eq(bare.gabbyAndTy.quote, Game3.EC_EMPTY_WORD, "and quote")
end)()

;(function()
local g = withGame()
g.rng = function() return 1 end
g:initRoamer()
g.roamer.hp = 12
g.roamer.status = Game3.STATUS_PAR
check(g:writeSave(), "roamer writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the roamer")
eq(loaded.roamer.species, Game3.SPECIES_LATIOS, "Latios comes back")
eq(loaded.roamer.level, 40, "lv40")
eq(loaded.roamer.hp, 12, "banked HP")
eq(loaded.roamer.status, Game3.STATUS_PAR, "and status")
check(loaded.roamer.active, "still active")
eq(loaded.roamerLocation[2], 25, "and the route, not Petalburg")
eq(loaded.roamer.personality, g.roamer.personality, "same PID")
wipeRubySave()
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.roamer = nil
check(bare:applySave(oldSnap), "a save without a roamer still applies")
check(not bare.roamer.active, "missing roamer is inactive")
bare:initRoamer()
check(bare.roamer.active, "InitRoamer before NEW GAME")
bare:wipeNewGameState()
check(not bare.roamer.active, "NEW GAME clears the roamer")
eq(bare.roamerLocation[2], 0, "and the location RAM")
end)()

;(function()
local g = withGame()
g.trainerRematchStepCounter = 255
g:ensureTrainerRematches()[30] = 1
local snap = g:snapshotSave()
eq(snap.trainerRematchStepCounter, 255, "rematch steps save")
eq(snap.trainerRematches[30], 1, "Calvin rematch saves")
g:wipeNewGameState()
eq(tonumber(g.trainerRematchStepCounter) or 0, 0, "NEW GAME clears steps")
eq(g:trainerEyeRematchValue(30), 0, "and the flag")
check(g:applySave(snap), "rematch save applies")
eq(g.trainerRematchStepCounter, 255, "steps come back")
eq(g:trainerEyeRematchValue(30), 1, "flag comes back")
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.trainerRematches = nil
oldSnap.trainerRematchStepCounter = nil
check(bare:applySave(oldSnap), "old save without rematches applies")
eq(tonumber(bare.trainerRematchStepCounter) or 0, 0, "missing counter is 0")
end)()

;(function()
local g = withGame()
g.party[1].pokerus = 0x41
local row = g:snapshotMon(g.party[1])
eq(row.pokerus, 0x41, "Pokerus saves")
eq(g:restoreMon(row).pokerus, 0x41, "and restores")
end)()

;(function()
local g = withGame()
g.hallOfFameTeams = {
  { { species = 280, level = 50, nick = "ACE", tid = 1, pid = 2 } },
}
local snap = g:snapshotSave()
eq(snap.hallOfFameTeams[1][1].nick, "ACE", "HoF team saves")
g:wipeNewGameState()
eq(#(g.hallOfFameTeams or {}), 0, "NEW GAME clears HoF")
check(g:applySave(snap), "HoF save applies")
eq(g.hallOfFameTeams[1][1].species, 280, "Torchic comes back")
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.hallOfFameTeams = nil
check(bare:applySave(oldSnap), "old save without HoF applies")
eq(#(bare.hallOfFameTeams or {}), 0, "missing HoF is empty")

g = withGame()
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.party[2].item = Game3.ITEM_ORANGE_MAIL
g.party[2].name = "POST"
check(g:depositToDaycare(2), "mail deposit")
eq(g.daycare[1].mail.itemId, Game3.ITEM_ORANGE_MAIL, "mail on the slot")
snap = g:snapshotSave()
eq(snap.daycare[1].mail.nick, "POST", "mail nick saves")
check(g:writeSave(), "mail save writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores mail")
eq(loaded.daycare[1].mail.itemId, Game3.ITEM_ORANGE_MAIL, "mail comes back")
eq(loaded.daycare[1].mail.nick, "POST", "nick comes back")
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.party[1].hp = g.party[1].maxHp
g.party[2].hp = 0
g.bag = {}
g:addItem(Game3.ITEM_REVIVE, 1)
g:openBag()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
-- the popup, then USE (first entry for the ITEMS pocket)
eq(g.field.kind, "bag_actions", "A opens the item popup")
eq(g.field.actions[1], "USE", "BAG_POCKET_ITEMS leads with USE")
g:stepField()
eq(g.field.kind, "party_use", "BAG Revive opens the party")
eq(g.field.from, "bag", "so B can return to the pack")
eq(g.party[2].hp, 0, "does not auto-pick the fainted mon")
g:stepField()
eq(g.field.kind, "talk", "A on the healthy lead is no effect")
check(g.field.text:find("won't have any effect", 1, true) ~= nil,
  "gOtherText_WontHaveAnyEffect")
eq(g.party[2].hp, 0, "still fainted")
eq(g:itemCount(Game3.ITEM_REVIVE), 1, "Revive is kept")
check(g.field.thenBag, "sub_808B224 fades back to the bag")
g:stepField()
eq(g.field.kind, "bag", "A dismisses to the pack")
g:stepField()
g:stepField()  -- the item popup, then USE
eq(g.field.kind, "party_use", "Use again reopens the picker")
Input.wasPressed = function(_, key) return key == "down" end
g:stepField()
eq(g.field.cursor, 1, "DOWN lands on the fainted slot")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "talk", "A on the fainted mon applies")
check(g.field.text:find("revived", 1, true) ~= nil, "was revived")
eq(g.party[2].hp, math.floor((g.party[2].maxHp or 1) * 0.5), "half HP")
eq(g:itemCount(Game3.ITEM_REVIVE), 0, "consumed after a hit")

g:addItem(Game3.ITEM_REVIVE, 1)
g:openBag()
g:stepField()
g:stepField()  -- the item popup, then USE
eq(g.field.kind, "party_use", "picker again")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "bag", "B is HandleDefaultPartyMenuInput cancel")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
g:stepField()  -- the item popup, then USE
eq(g.field.kind, "party_use", "Use again")
g.field.cursor = 6
g:stepField()
eq(g.field.kind, "bag", "A on CANCEL is B_BUTTON")

g.party[1] = { name = "EGG", species = 280, isEgg = true, hp = 0, maxHp = 20 }
g.party[2].hp = 0
g:openBag()
g:stepField()
g:stepField()  -- the item popup, then USE
eq(g.field.kind, "party_use", "Revive on an egg party")
g:stepField()
eq(g.field.kind, "party_use", "sub_808B0C0 egg is SE_FAILURE, stay")
eq(g:itemCount(Game3.ITEM_REVIVE), 1, "egg does not consume")

g.registeredItem = Game3.ITEM_POTION
g:addItem(Game3.ITEM_POTION, 1)
g.party[2].hp = 1
g.party[2].maxHp = 20
g.field = nil
g:useRegisteredItem()
eq(g.field.kind, "party_use", "SELECT Potion opens the picker")
eq(g.field.from, "field", "no bag underneath")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field, nil, "B returns to the overworld")
Input.wasPressed = old
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
g.data.moves.byId[166] = { id = 166, name = "SKETCH", power = 0, type = 0, pp = 1, accuracy = 0 }
g.data.pokemon.byIndex[281] = {
  name = "COMBUSKEN", hp = 60, atk = 85, def = 60, spe = 55,
  spa = 85, spd = 60, type1 = 10, type2 = 1,
}
g.party = { g:makeMon(280, 5, { 10 }) }
g.bag = {}

check(Game3.needsFieldParty(Game3.ITEM_HP_UP), "HP Up opens the party")
check(Game3.needsFieldParty(Game3.ITEM_RARE_CANDY), "Rare Candy opens the party")
check(Game3.needsFieldParty(Game3.ITEM_FIRE_STONE), "stones open the party")
check(Game3.needsMovePick(Game3.ITEM_ETHER), "Ether picks a move")
check(not Game3.needsMovePick(Game3.ITEM_ELIXIR), "Elixir hits every move")

g:addItem(Game3.ITEM_HP_UP, 1)
check(g:useFieldItem(Game3.ITEM_HP_UP), "HP Up opens the picker")
eq(g.field.kind, "party_use", "ItemUseOutOfBattle_Medicine vitamins")
local ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_HP_UP)
check(ok, "HP Up applies")
eq(g.party[1].hpEv, 10, "ITEM4_EV_HP +10")
check(msg:find("HP", 1, true) ~= nil, "gOtherText_WasRaised")
eq(g:itemCount(Game3.ITEM_HP_UP), 0, "consumed")

g.party[1].hp = 0
g:addItem(Game3.ITEM_PROTEIN, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_PROTEIN)
check(ok, "Protein works on a fainted mon")
eq(g.party[1].atkEv, 10, "ATTACK EV")
eq(g.party[1].hp, 0, "still fainted")

g.party[1].hpEv = 100
g:addItem(Game3.ITEM_HP_UP, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_HP_UP)
check(not ok, "vitamin cap is 100")
eq(g:itemCount(Game3.ITEM_HP_UP), 1, "capped vitamin kept")

g.party[1].species = Game3.SPECIES_SHEDINJA
g.party[1].hpEv = 0
ok = g:useItemOnMon(g.party[1], Game3.ITEM_HP_UP)
check(not ok, "IsMedicineIneffective Shedinja")
eq(g:itemCount(Game3.ITEM_HP_UP), 1, "Shedinja HP Up kept")
g.party[1].species = 280

g.party[1].level = 5
g.party[1].hp = 1
g:addItem(Game3.ITEM_RARE_CANDY, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_RARE_CANDY)
check(ok, "Rare Candy")
eq(g.party[1].level, 6, "level +1")
check(msg:find("elevated", 1, true) ~= nil, "gOtherText_ElevatedTo")
eq(g:itemCount(Game3.ITEM_RARE_CANDY), 0, "candy consumed")

g.party[1].level = 100
g:addItem(Game3.ITEM_RARE_CANDY, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_RARE_CANDY)
check(not ok, "level 100 candy")
eq(g:itemCount(Game3.ITEM_RARE_CANDY), 1, "Lv100 candy kept")

g.party[1].level = 15
g.pendingEvo = nil
g:addItem(Game3.ITEM_RARE_CANDY, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_RARE_CANDY)
check(ok, "candy to evo level")
eq(g.party[1].level, 16, "Lv. 16")
check(g.pendingEvo and g.pendingEvo[1] and g.pendingEvo[1].target == 281,
  "tryEvolve queues, does not resolve")
eq(g.party[1].species, 280, "still Torchic")
g.pendingEvo = nil

local move = g.party[1].moves[1]
move.pp = 5
g:addItem(Game3.ITEM_ELIXIR, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_ELIXIR)
check(ok, "Elixir")
eq(move.pp, 15, "Elixir +10 all moves")
eq(msg, "PP was restored.", "gOtherText_PPRestored")

g:addItem(Game3.ITEM_ETHER, 1)
g.field = { kind = "bag" }
check(g:useFieldItem(Game3.ITEM_ETHER), "Ether opens the party")
eq(g.field.kind, "party_use", "ItemUseOutOfBattle_PPRecovery")
g:chooseUseMon(1)
eq(g.field.kind, "party_pp", "CreateItemUseMoveMenu")
eq(g.field.prompt, "Restore which move?", "OtherText_RestoreWhatMove")
eq(g:itemCount(Game3.ITEM_ETHER), 1, "not consumed until a move")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "talk", "Ether on Scratch")
eq(g.field.text, "PP was restored.", "restored")
eq(move.pp, 25, "Ether +10 one move")
eq(g:itemCount(Game3.ITEM_ETHER), 0, "consumed")

g.party[1].moves = { g:copyMove(10) }
g:addItem(Game3.ITEM_PP_UP, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_PP_UP, 1)
check(ok, "PP Up")
eq(g.party[1].moves[1].ppUps, 1, "one PP Up")
eq(g.party[1].moves[1].maxPp, 42, "35 + 20%")
check(msg:find("PP increased", 1, true) ~= nil, "gOtherText_PPIncreased")

g.party[1].moves = { g:copyMove(166) }
g:addItem(Game3.ITEM_PP_UP, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_PP_UP, 1)
check(not ok, "PP Up needs max PP > 4")
eq(g:itemCount(Game3.ITEM_PP_UP), 1, "Sketch PP Up kept")
g:addItem(Game3.ITEM_PP_MAX, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_PP_MAX, 1)
check(ok, "PP Max has no > 4 check")
eq(g.party[1].moves[1].ppUps, 3, "PP Max writes 3")

g.data.pokemon.byIndex[280].evolutions = {
  { method = Game3.EVO_ITEM, param = Game3.ITEM_FIRE_STONE, target = 281 },
}
g.party[1] = g:makeMon(280, 5)
g.pendingEvo = nil
g:addItem(Game3.ITEM_FIRE_STONE, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_FIRE_STONE)
check(ok, "Fire Stone")
eq(g.pendingEvo[1].target, 281, "GetEvolutionTargetSpecies type 2")
eq(g.party[1].species, 280, "scene not resolved")
eq(g:itemCount(Game3.ITEM_FIRE_STONE), 0, "stone consumed")

g.pendingEvo = nil
g.party[1].item = Game3.ITEM_EVERSTONE
g:addItem(Game3.ITEM_FIRE_STONE, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_FIRE_STONE)
check(not ok, "Everstone blocks type 2")
eq(g:itemCount(Game3.ITEM_FIRE_STONE), 1, "blocked stone kept")
g.party[1].item = nil

g.party = { g:makeMon(280, 5), g:makeMon(280, 5) }
g.party[1].hp = 0
g.party[2].hp = 0
g:addItem(Game3.ITEM_SACRED_ASH, 1)
g.field = { kind = "bag" }
check(g:useFieldItem(Game3.ITEM_SACRED_ASH), "Sacred Ash")
eq(g.party[1].hp, g.party[1].maxHp, "ash slot 1")
eq(g.party[2].hp, g.party[2].maxHp, "ash slot 2")
eq(g:itemCount(Game3.ITEM_SACRED_ASH), 0, "consumed if any hit")
eq(g.field.kind, "talk", "ash reports")
check(g.field.thenBag, "sub_808B224 after ash")
g:addItem(Game3.ITEM_SACRED_ASH, 1)
ok, msg = g:useSacredAsh()
check(not ok, "ash with nobody fainted")
eq(msg, "It won't have any effect.", "gOtherText_WontHaveAnyEffect")
eq(g:itemCount(Game3.ITEM_SACRED_ASH), 1, "wasted ash kept")
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = withGame()
g.bag = {}
g.coins = 50
g.customName = "BRENDAN"

local ok, msg = g:useFieldItem(Game3.ITEM_NUGGET)
check(not ok, "CannotUse")
check(msg:find("DAD's advice", 1, true) ~= nil, "gOtherText_DadsAdvice")
check(msg:find("BRENDAN", 1, true) ~= nil, "names the player")

ok, msg = g:useFieldItem(Game3.ITEM_X_ATTACK)
check(not ok, "X Attack is field CannotUse")
check(msg:find("DAD's advice", 1, true) ~= nil, "X items Dad")

ok, msg = g:useFieldItem(Game3.ITEM_COIN_CASE)
check(ok, "Coin Case")
eq(msg, "Your COINS:\n50", "gOtherText_Coins3")

g.field = { kind = "bag" }
ok = g:useFieldItem(Game3.ITEM_ORANGE_MAIL)
check(ok, "Mail")
eq(g.field.kind, "mail_read", "ItemUseOutOfBattle_Mail")
eq(g.field.item, Game3.ITEM_ORANGE_MAIL, "the letter")
check(g.field.thenBag, "B returns to the pack")

g.field = { kind = "bag" }
ok = g:useFieldItem(Game3.ITEM_POKEBLOCK_CASE)
check(ok, "Pokéblock Case")
eq(g.field.kind, "pokeblock_case", "ItemUseOutOfBattle_PokeblockCase")
eq(g.field.labels[#g.field.labels], "CANCEL", "CANCEL row")
check(g.field.labels[1]:find("empty", 1, true) ~= nil, "empty case")

g.party = {}
ok, msg = g:useFieldItem(Game3.ITEM_POTION)
check(not ok, "type 1 with no party")
eq(msg, "There is no\nPOKéMON.", "gOtherText_NoPokemon")
g.party = { g:makeMon(280, 5) }

g:initBerryTrees()
g:plantBerryTree(1, 0, 0, false)
g.facing = "east"
g.playerX, g.playerY = 0, 0
g.map = { id = "g_plant", width = 3, height = 1, grid = { 0, 0, 0 } }
local soil = g:npcFromTemplate({
  x = 1, y = 0, graphicsId = Game3.GFX_BERRY_TREE,
  trainerRange = 1, localId = 1,
}, 1)
g.npcByMap = { g_plant = { soil } }
g:refreshBerryTreeSprites()
eq(soil.invisible, true, "empty soil hides the sprite")
g:addItem(Game3.ITEM_ORAN_BERRY, 1)
ok = g:useFieldItem(Game3.ITEM_ORAN_BERRY)
check(ok, "berry on empty soil plants")
eq(g.field.kind, "talk", "S_PlantBerryTreeFromBag")
check(g.field.text:find("ORAN BERRY", 1, true) ~= nil, "planted one ORAN")
eq(g:itemCount(Game3.ITEM_ORAN_BERRY), 0, "the berry is spent")
eq(g.berryTrees[1].stage, Game3.BERRY_STAGE_PLANTED, "stage 1")
eq((g.gameStats or {})[Game3.GAME_STAT_PLANTED_BERRIES], 1,
  "GAME_STAT_PLANTED_BERRIES")

g.facing = "west"
g:addItem(Game3.ITEM_ORAN_BERRY, 1)
g.party[1].hp = 5
g.party[1].maxHp = 19
ok = g:useFieldItem(Game3.ITEM_ORAN_BERRY)
check(ok, "Oran not facing soil is medicine")
eq(g.field.kind, "party_use", "the berry's fieldUseFunc")

local figy = 143
g:addItem(figy, 1)
ok, msg = g:useFieldItem(figy)
check(not ok, "Figy is CannotUse off soil")
check(msg:find("DAD's advice", 1, true) ~= nil, "Figy Dad")
eq(g:itemCount(figy), 1, "Figy kept")

g.field = { kind = "bag" }
g:addItem(Game3.ITEM_HM_CUT, 1)
ok = g:useFieldItem(Game3.ITEM_HM_CUT)
check(ok, "HM boots")
eq(g.field.kind, "talk", "gOtherText_BootedHM")
check(g.field.text:find("Booted up an HM", 1, true) ~= nil, "Booted up an HM")
check(g.field.thenTmAsk, "then DisplayTeachMonTMHMYesNoChoice")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
local sawYesNo = false
local n = 0
while g.field and g.field.kind ~= "party_teach" and n < 16 do
  if g.field.kind == "tm_yesno" then sawYesNo = true end
  g:stepField()
  n = n + 1
end
check(sawYesNo, "YES/NO at (7,7)")
eq(g.field.kind, "party_teach", "YES is TeachMonTMMove")
g.field = { kind = "bag" }
g:useFieldItem(Game3.ITEM_HM_CUT)
n = 0
while g.field and g.field.kind ~= "tm_yesno" and n < 16 do
  g:stepField()
  n = n + 1
end
eq(g.field.kind, "tm_yesno", "ask again")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
if g.field and g.field.kind == "tm_yesno" then g:stepField() end
eq(g.field.kind, "bag", "NO returns to the pack")
Input.wasPressed = old

g.party[1].level = 5
g.party[1].hp = 1
g:addItem(Game3.ITEM_RARE_CANDY, 1)
g.field = { kind = "bag" }
check(g:useFieldItem(Game3.ITEM_RARE_CANDY), "candy picker")
g:chooseUseMon(1)
eq(g.field.kind, "talk", "gOtherText_ElevatedTo")
check(g.field.thenCandy, "stat-growth window")
eq(g.field.thenCandy[1].name, "HP", "StatDataTypes")
eq(g.field.thenCandy[6].name, "SPEED", "SPEED last")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "candy_stats", "page 0 is the deltas")
eq(g.field.page, 0, "first page")
g:stepField()
eq(g.field.page, 1, "second page is the new values")
g:stepField()
eq(g.field.kind, "bag", "thenBag after both pages")
Input.wasPressed = old
end)()

-- (#536 parity) a save made mid-surf must resume surfing and dismount on land.
do
  local surfMap = {
    id = "g_surf_save", width = 3, height = 3, tileset = "wat",
    -- shore tile (1,1) is elevation 3: Surf only ever dismounts landing at
    -- elevation 3 (field_player_avatar.c sub_8058EF0), not any land tile.
    grid = { 0, 0, 0, 0, 3 * 4096, 1025, 0, 0, 0 },
  }
  local tilesets = { byId = { wat = { behavior = { [1] = 0x10, [2] = 0x13 } } } }
  local function surfGame()
    local g = withGame()
    g.data.tilesets = tilesets
    g.data.maps = { start = "g_surf_save", maps = { g_surf_save = surfMap } }
    g.party[1].moves = { { id = Game3.MOVE_SURF } }
    g.flags[Game3.FLAG_BADGE05_GET] = true
    g:enterMap(surfMap, 2, 1, true)
    g.surfing = true
    return g
  end
  local g = surfGame()
  local snap = g:snapshotSave()
  eq(snap.surfing, true, "snapshot records surfing=true")
  eq(snap.mapId, "g_surf_save", "snapshot records surf map")
  eq(snap.x, 2, "snapshot records surf x")
  eq(snap.y, 1, "snapshot records surf y")

  local loaded = surfGame()
  check(loaded:applySave(snap), "surf save applies")
  eq(loaded.surfing, true, "CONTINUE restores surfing on water")
  eq(loaded.playerX, 2, "surf x restored")
  eq(loaded.playerY, 1, "surf y restored")
  check(loaded:tryWalk(-1, 0), "can walk back to land after reload")
  eq(loaded.playerX, 1, "back on land after reload")
  eq(loaded.surfing, nil, "dismounts after reload")

  -- Old saves without a surfing field on water auto-repair.
  snap.surfing = nil
  loaded = surfGame()
  check(loaded:applySave(snap), "legacy surf save applies")
  eq(loaded.surfing, true, "legacy save on water infers surfing")
  check(loaded:tryWalk(-1, 0), "legacy save can leave the water")
  eq(loaded.surfing, nil, "legacy save dismounts on land")
end

-- CONTINUE on Route 110's cycling path remounts. Avatar flags are EWRAM;
-- FLAG_SYS_CYCLING_ROAD and the bag bike are what the save actually keeps.
do
  local road = {
    id = "g0_33", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  }
  local gate = {
    id = "g29_11", group = 29, index = 11,
    mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  }
  local indoor = {
    id = "g_pc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  }
  local railMap = {
    id = "g_rail", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    behavior = { 0, 0, 0, 0, Game3.MB_VERTICAL_RAIL, 0, 0, 0, 0 },
  }
  local function bikeGame(map)
    map = map or road
    local g = withGame()
    g.data.maps = { start = map.id, maps = { [map.id] = map, g0_33 = road,
      g29_11 = gate, g_pc = indoor, g_rail = railMap } }
    g:addItem(Game3.ITEM_ACRO_BIKE, 1)
    g.registeredItem = Game3.ITEM_ACRO_BIKE
    g.flags[Game3.FLAG_SYS_CYCLING_ROAD] = true
    g:enterMap(map, 1, 1, true)
    g.bike = "acro"
    return g
  end

  local g = bikeGame()
  local snap = g:snapshotSave()
  eq(snap.bike, "acro", "snapshot records the Acro Bike")
  local loaded = bikeGame()
  loaded.bike = nil
  check(loaded:applySave(snap), "bike save applies")
  eq(loaded.bike, "acro", "CONTINUE restores the bike on the cycling path")
  eq(loaded:playerGraphicsId(), Game3.GFX_BRENDAN_ACRO_BIKE,
    "CONTINUE uses the Acro Bike sprite")

  snap.bike = nil
  loaded = bikeGame()
  loaded.bike = nil
  check(loaded:applySave(snap), "legacy cycling save applies")
  eq(loaded.bike, "acro", "FLAG_SYS_CYCLING_ROAD remounts the registered bike")

  local gateSnap = bikeGame(gate):snapshotSave()
  loaded = bikeGame(gate)
  loaded.bike = nil
  check(loaded:applySave(gateSnap), "gate bike save applies")
  eq(loaded.bike, "acro", "CONTINUE keeps the bike in the cycling gate")

  snap.bike = nil
  snap.mapId = "g_pc"
  loaded = bikeGame()
  loaded.bike = nil
  check(loaded:applySave(snap), "indoor cycling-flag save applies")
  eq(loaded.bike, nil, "stuck cycling flag does not remount indoors")

  local railG = bikeGame(railMap)
  railG.flags[Game3.FLAG_SYS_CYCLING_ROAD] = nil
  local railSnap = railG:snapshotSave()
  railSnap.bike = nil
  loaded = bikeGame(railMap)
  loaded.bike = nil
  loaded.flags[Game3.FLAG_SYS_CYCLING_ROAD] = nil
  check(loaded:applySave(railSnap), "rail save applies")
  eq(loaded.bike, "acro", "standing on a cycling-road rail remounts")
end

-- TRAINER'S EYE, the PokeNav list sub_80F6C20 builds. Ruby has no Match Call
-- and no registration step: the list is derived from the trainer flags every
-- time it opens.
;(function()
local g = Game3.new()
g.flags = {}
g.data = { maps = { maps = {} }, trainers = { byId = {
  [37] = { name = "ROSE" },
  [265] = { name = "ROXANNE" },
  [266] = { name = "BRAWLY" },
} } }
-- stand in a map for each rematch row so the section lookup has something
for i = 1, #Game3.TRAINER_EYE_TRAINERS do
  local row = Game3.TRAINER_EYE_TRAINERS[i]
  g.data.maps.maps[Game3.mapId(row[2], row[3])] = { regionMapSectionId = 19 }
end

eq(#Game3.TRAINERS_EYE_GYM_LEADERS, 13,
  "sGymLeaderTrainersEye holds the eight leaders, the Elite Four and STEVEN")
eq(Game3.TRAINERS_EYE_GYM_BASE, 56,
  "and they are numbered on from the 56 rematch rows")
eq(Game3.TRAINERS_EYE_GYM_LEADERS[1][1], 265, "ROXANNE leads the table")
eq(Game3.TRAINERS_EYE_GYM_LEADERS[13][1], 335, "STEVEN closes it")

eq(#g:trainersEyeList(), 0, "nothing beaten, nothing listed")

-- A rematch-table trainer appears once beaten
local first = Game3.TRAINER_EYE_TRAINERS[1][1][1]
g:setTrainerDefeated(first)
local list = g:trainersEyeList()
eq(#list, 1, "a beaten trainer is listed")
eq(list[1].opponentId, first, "by their first opponent id")
eq(list[1].rematchTableIdx, 0, "the rematch row index is zero-based")
eq(list[1].rematchNo, 0, "and no rematch is pending yet")
eq(list[1].regionMapSectionId, 19, "the section comes off the row's own map")

-- A gym leader appears after the rematch rows, whatever the order beaten
g:setTrainerDefeated(266)                    -- BRAWLY, the second gym row
list = g:trainersEyeList()
eq(#list, 2, "the gym leader joins the list")
eq(list[2].opponentId, 266, "after the rematch rows")
eq(list[2].rematchTableIdx, Game3.TRAINERS_EYE_GYM_BASE + 1,
  "with an index carried on from 56")
eq(list[2].regionMapSectionId, 2, "and its own fixed section, DEWFORD TOWN")
check(list[2].gymLeader, "flagged as a gym leader")

-- Only a rematch row can want a rematch
eq(Game3.trainersEyeWantsRematch(list[1]), false, "no rematch pending")
g:ensureTrainerRematches()[1] = 3
list = g:trainersEyeList()
eq(list[1].rematchNo, 3, "the rematch number is read off the save")
eq(Game3.trainersEyeWantsRematch(list[1]), true, "which is what marks the row")
eq(Game3.trainersEyeWantsRematch(list[2]), false,
  "a gym leader is always zero -- sub_80F6C20 never reads a flag for them")

-- Beating everything gives 56 + 13 rows in table order
g.flags = {}
g.trainerRematches = {}
for i = 1, #Game3.TRAINER_EYE_TRAINERS do
  g:setTrainerDefeated(Game3.TRAINER_EYE_TRAINERS[i][1][1])
end
for i = 1, #Game3.TRAINERS_EYE_GYM_LEADERS do
  g:setTrainerDefeated(Game3.TRAINERS_EYE_GYM_LEADERS[i][1])
end
list = g:trainersEyeList()
eq(#list, 69, "every row, once beaten")
eq(list[1].rematchTableIdx, 0, "indices run from zero")
eq(list[56].rematchTableIdx, 55, "through the rematch rows")
eq(list[57].rematchTableIdx, 56, "then straight on into the gym leaders")
eq(list[69].rematchTableIdx, 68, "to the last of them")
end)()

-- gTrainerEyeDescriptions, found by shape rather than by symbol: the decomp
-- leaves it extern, so the extractor scans for 69 pointers whose targets are
-- four EOS-terminated lines laid end to end.
;(function()
local Battle = require("src.import.RomExtractorGen3Battle")
eq(Battle.TRAINER_EYE_DESCRIPTIONS, 69,
  "one description per rematch row plus one per gym leader")
eq(Battle.TRAINER_EYE_LINES, 4, "each is four lines")

local g = Game3.new()
g.data = { trainers = { eyeDescriptions = {
  [0] = { "a", "b", "c", "d" },
  [56] = { "rock", "solid", "through", "battling" },
} } }
eq(g:trainersEyeDescription({ rematchTableIdx = 0 })[1], "a",
  "a rematch row reads its own four lines")
eq(g:trainersEyeDescription({ rematchTableIdx = 56 })[1], "rock",
  "and a gym leader reads on from 56 in the same table")
eq(g:trainersEyeDescription({ rematchTableIdx = 3 }), nil,
  "a row with no text reads back nothing rather than a blank")
eq(g:trainersEyeDescription(nil), nil, "and so does no row at all")
end)()


-- gRibbonDescriptions is [25][2] and extern in the decomp, so it is located by
-- the shape of its contest half: five category names, each shared by four
-- ranks.
;(function()
local Battle = require("src.import.RomExtractorGen3Battle")
eq(Battle.RIBBON_DESCRIPTIONS, 25,
  "the Hall of Fame ribbon, 5 x 4 contest ribbons, two tower, artist, effort")
eq(Battle.RIBBON_CONTEST_GROUPS * Battle.RIBBON_CONTEST_RANKS, 20,
  "the contest half is twenty of them")

local g = Game3.new()
local ribbons = {}
for i = 0, Game3.RIBBON_COUNT - 1 do ribbons[i] = { "line one", "line two" } end
g.data = { trainers = { ribbonDescriptions = ribbons } }

-- a contest ribbon holds the highest rank won, so Master implies the rest
local mon = { ribbons = { cool = 4, beauty = 1 } }
check(g:monHasRibbon(mon, 1), "COOL Normal")
check(g:monHasRibbon(mon, 4), "up to COOL Master")
check(g:monHasRibbon(mon, 5), "BEAUTY Normal")
check(not g:monHasRibbon(mon, 6), "but not BEAUTY Super")
check(not g:monHasRibbon(mon, 9), "and no CUTE at all")
eq(#g:monRibbons(mon), 5, "five ribbons in total")

mon.championRibbon = true
check(g:monHasRibbon(mon, Game3.RIBBON_CHAMPION), "the CHAMPION ribbon reads off its own flag")
mon.effortRibbon = true
check(g:monHasRibbon(mon, Game3.RIBBON_EFFORT), "and so does the effort one")
mon.artistRibbon = true
check(g:monHasRibbon(mon, Game3.RIBBON_ARTIST), "and the artist's")
eq(#g:monRibbons(mon), 8, "which brings it to eight")

-- The BATTLE TOWER is not implemented, so neither of its ribbons is ever held.
check(not g:monHasRibbon(mon, Game3.RIBBON_WINNING), "no LV50 tower ribbon")
check(not g:monHasRibbon(mon, Game3.RIBBON_VICTORY), "no LV100 tower ribbon")

eq(g:monHasRibbon(nil, 0), false, "no mon, no ribbon")
eq(g:monHasRibbon(mon, 99), false, "and nothing outside the table")
eq(g:ribbonDescription(1)[1], "line one", "a description reads back by index")
eq(g:ribbonDescription(99), nil, "and an unknown index reads back nothing")

-- The PokeNav offers all four of the cart's entries.
local items = g:pokenavMenuItems()
eq(items[1], "MAP", "MAP")
eq(items[2], "CONDITION", "CONDITION")
eq(items[3], "TRAINER'S EYE", "TRAINER'S EYE")
eq(items[4], "RIBBONS", "RIBBONS")

-- RIBBONS opens on the lead mon and follows it across the party.
g.party = {
  { name = "A", ribbons = { cool = 2 } },
  { name = "B", ribbons = {} },
}
g.phase = "play"
g:openPokenavRibbons()
eq(g.field.kind, "pokenav_ribbons", "the ribbons screen opens")
eq(#g.field.ribbons, 2, "with the lead mon's two")
g.field.monIndex = 2
g.field.ribbons = g:monRibbons(g.party[2])
eq(#g.field.ribbons, 0, "and none for the second")
end)()


-- C3: the setwarp opcode and the two specials the map scripts still called
-- without a handler.
;(function()
local Script = require("src.import.Gen3Script")
local g = Game3.new()
g.scriptVars = {}

-- Overworld_SetWarpDestination. The Safari Zone's out-of-steps exit is the one
-- caller reachable in a normal run: MAP_ROUTE121_SAFARI_ZONE_ENTRANCE, 255, 2, 5.
Script.run(g, { { op = "setwarp", mapGroup = 0, mapNum = 17,
  warpId = 255, x = 2, y = 5 } })
local w = g.warpDestination
check(w ~= nil, "setwarp now reaches the host")
eq(w.mapNum, 17, "the destination map is kept")
eq(w.warpId, 255, "and the warp id")
eq(w.x, 2, "and the coordinates")
eq(w.y, 5, "both of them")
check(g:takeWarpDestination() ~= nil, "the destination can be taken")
eq(g:takeWarpDestination(), nil, "and only once")

-- setwarp reads its coordinates through VarGet, like its siblings.
g.scriptVars[0x8000] = 9
Script.run(g, { { op = "setwarp", mapGroup = 1, mapNum = 2,
  warpId = 3, x = 0x8000, y = 5 } })
eq(g.warpDestination.x, 9, "a var-held coordinate is resolved")
g:takeWarpDestination()

-- sub_80EB7C4: the Lilycove boards you read, not the Easy Chat editor. Four
-- boards, each with its own row and column shape.
eq(Game3.SPECIAL_SHOW_EASY_CHAT_BOARD, 96, "the board special is 96")
eq(Game3.SPECIAL_SHOW_EASY_CHAT, 95, "the editor is the one below it")
eq(Game3.EC_BOARD_COUNT, 4, "four boards")
eq(Game3.EC_BOARD_SHAPE[0][1], 2, "the first is two words across")
eq(Game3.EC_BOARD_SHAPE[1][1], 3, "the rest are three")

g.scriptVars[0x8004] = 0
eq(g:runSpecial(Game3.SPECIAL_SHOW_EASY_CHAT_BOARD), 1, "a valid board runs")
g.scriptVars[0x8004] = Game3.EC_BOARD_COUNT
eq(g:runSpecial(Game3.SPECIAL_SHOW_EASY_CHAT_BOARD), 0,
  "and the cart returns without doing anything past the last one")

-- An empty board says nothing rather than inventing text: the boards are
-- written over the link cable, so in a single-player run they are blank.
g.scriptVars[0x8004] = 0
g._scriptSays = nil
g:runSpecial(Game3.SPECIAL_SHOW_EASY_CHAT_BOARD)
eq(g._scriptSays, nil, "an empty board prints nothing")

-- A board with words in it reads them back in rows.
local board = g:easyChatBoard(0)
check(type(board) == "table", "a board can be addressed")
eq(g:easyChatBoardText(9), nil, "but only the four that exist")

-- What is left. Walking every map script turns up 184 distinct specials, and
-- after this pass exactly one of them still has no handler: 41, sub_80C5568,
-- which sets a saved callback and opens the contest entry screen. Four uses on
-- one map, and it needs the contest system rather than a handler of its own, so
-- it is recorded rather than stubbed. runSpecial returns 0 for it, which is
-- what an unknown special has always done.
eq(g:runSpecial(41), 0, "special 41 is the one still unhandled")
check(rawget(Game3, "SPECIAL_CONTEST_ENTRY_SCREEN") == nil,
  "and it is not declared, so the coverage sweep cannot count it as done")
end)()



;(function()
-- item_menu.c sItemPopupMenuChoicesTable. Picking a bag item opens a popup;
-- it does not use the item outright. Without it there was no route to GIVE
-- from the bag at all, so a held item like the EXP. SHARE could only answer
-- with DAD's advice -- the "you can't use that here" line.
local g = Game3.new()
g.phase = "play"

-- The per-pocket action lists, in the cart's own order. ITEM_ACTION_NONE
-- entries in that table are padding and are dropped.
eq(table.concat(g:bagActionsFor(Game3.POCKET_ITEMS), ","),
  "USE,TOSS,GIVE,CANCEL", "BAG_POCKET_ITEMS")
eq(table.concat(g:bagActionsFor(Game3.POCKET_BALLS), ","),
  "GIVE,TOSS,CANCEL", "BAG_POCKET_POKE_BALLS leads with GIVE")
eq(table.concat(g:bagActionsFor(Game3.POCKET_TMHM), ","),
  "USE,GIVE,CANCEL", "BAG_POCKET_TMs_HMs has no TOSS")
eq(table.concat(g:bagActionsFor(Game3.POCKET_BERRIES), ","),
  "CHECK TAG,USE,TOSS,GIVE,CANCEL", "BAG_POCKET_BERRIES leads with CHECK TAG")
eq(table.concat(g:bagActionsFor(Game3.POCKET_KEY), ","),
  "USE,REGISTER,CANCEL", "BAG_POCKET_KEY_ITEMS has REGISTER, no TOSS or GIVE")

-- A key item cannot be tossed even if something asks for it.
local keyed = Game3.new()
keyed.phase = "play"
keyed.bag = {}
keyed:addItem(Game3.ITEM_RED_ORB, 1)
local tossed, why = keyed:tossBagItem(Game3.ITEM_RED_ORB, 1)
eq(tossed, false, "a KEY ITEM refuses to be tossed")
check((why or ""):find("important", 1, true) ~= nil, "and says why")
eq(keyed:itemCount(Game3.ITEM_RED_ORB), 1, "so it is still in the pack")

-- The whole EXP. SHARE route, which is the bug this fixes.
local Input = require("src.core.Input")
local function press(gg, key)
  local old = Input.wasPressed
  Input.wasPressed = function(_, k) return k == key end
  gg:stepField()
  Input.wasPressed = old
end

local h = Game3.new()
h.phase = "play"
h.party = { { name = "TREECKO", hp = 20, maxHp = 20, species = 277,
  level = 10, moves = {} } }
h.bag = {}
h:addItem(Game3.ITEM_EXP_SHARE, 1)
h:openBag()
press(h, "a")
eq(h.field.kind, "bag_actions", "A on the EXP. SHARE opens the popup")
eq(h.field.actions[3], "GIVE", "GIVE is the third entry for ITEMS")
press(h, "down")
press(h, "down")
eq(h.field.actions[(h.field.cursor or 0) + 1], "GIVE", "cursor reaches GIVE")
press(h, "a")
eq(h.field.kind, "party_give", "GIVE opens the party")
eq(h.field.from, "bag", "and knows it came from the pack")
press(h, "a")
eq(h.party[1].item, Game3.ITEM_EXP_SHARE, "TREECKO is holding it")
eq(h:itemCount(Game3.ITEM_EXP_SHARE), 0, "and it left the bag")
check((h.field and h.field.text or ""):find("given the", 1, true) ~= nil,
  "with the line saying so, not a silent hand-off")

-- TAKE puts it back.
local ok2, msg2 = h:takeHeldItem(1)
check(ok2, "TAKE returns it")
eq(h.party[1].item, nil, "the mon holds nothing")
eq(h:itemCount(Game3.ITEM_EXP_SHARE), 1, "and the pack has it again")
check((msg2 or ""):find("Received", 1, true) ~= nil, "with its own line")

-- CANCEL goes back to the pack rather than doing anything.
local c = Game3.new()
c.phase = "play"
c.bag = {}
c:addItem(Game3.ITEM_POTION, 2)
c:openBag()
press(c, "a")
eq(c.field.kind, "bag_actions", "popup opens")
c.field.cursor = #c.field.actions - 1
press(c, "a")
eq(c.field.kind, "bag", "CANCEL returns to the pack")
eq(c:itemCount(Game3.ITEM_POTION), 2, "and nothing was consumed")

-- TOSS drops one.
c:openBag()
press(c, "a")
c.field.cursor = 1
eq(c.field.actions[2], "TOSS", "TOSS is second for ITEMS")
press(c, "a")
eq(c:itemCount(Game3.ITEM_POTION), 1, "one POTION is gone")
end)()

-- ------- using SECRET POWER when you already have a base

-- gUnknown_081A2C51 opens with CheckPlayerHasSecretBase and jumps straight
-- to AskToMoveSecretBase when slot 0 is taken. This engine defers those
-- questions until you are standing in the new base (see useSecretPower), and
-- every piece was there -- askMoveSecretBaseInside, the decorations follow-up,
-- commitSecretBaseMove, and the decline branch that un-digs and hands the old
-- record back. Nothing called them: enterNewSecretBase entered the base
-- itself instead of going through secretBaseCreationWarp, so _secretBaseMoveFrom
-- was set, carried across createSecretBase, and never read. Using SECRET POWER
-- on a second spot silently moved your base and dropped you inside it.
;(function()
local function atSpot()
  local w, h = 8, 8
  local grid, behavior = {}, {}
  for i = 1, w * h do grid[i] = 0; behavior[i] = 0 end
  -- MB_SECRET_BASE_SPOT_YELLOW_CAVE one tile north of the player
  behavior[2 * w + 3 + 1] = Game3.MB_SECRET_BASE_SPOT_YELLOW_CAVE
  local m = { id = "route", group = 0, index = 42, width = w, height = h,
    grid = grid, behavior = behavior }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { route = m } }
  g.party = { { name = "LOMBRE", hp = 1, maxHp = 1, species = 271, level = 40,
    moves = { { id = Game3.MOVE_SECRET_POWER, pp = 10 } } } }
  g.flags = {}
  g.secretBase = { mapId = "old", x = 1, y = 1, id = 102 }
  g:enterMap(m, 3, 3, true)
  g.playerX, g.playerY = 3, 3
  g.facing = "north"
  return g
end

-- Walk the whole thing: prompt, field effect, discovery line, then the base.
local function useSecretPower(g)
  g:trySecretPowerInteract()
  g:answerSecretBaseYesNo(true)
  g:finishSecretPowerEntrance()
  local pending = g._secretPowerEnter
  g._secretPowerEnter = nil
  g.field = nil
  g:enterNewSecretBase(pending)
end

local g = atSpot()
check(g:trySecretPowerInteract(), "a spot you do not own offers SECRET POWER")
eq(g.field.kind, "secret_base_yesno", "as a yes/no, not an outright move")

g = atSpot()
useSecretPower(g)
check(g.field ~= nil, "it does not drop you in without a word")
eq(g.field.kind, "secret_base_yesno", "AskToMoveSecretBase's first question")
check(g.field.text:find("only make one", 1, true) ~= nil,
  "UnknownString_81A3C71 names the one-base rule")

-- NO: EventScript_1A2F3A backs out and sub_80BC440 un-digs the new one.
g = atSpot()
useSecretPower(g)
g:answerSecretBaseYesNo(false)
check(g._secretBaseRestore ~= nil, "declining restores the old record")
eq(g._secretBaseRestore.mapId, "old", "and it is the base you already had")
eq(g._secretBaseRestore.x, 1, "at its own tile")

-- YES: the decorations warning, then the move commits.
g = atSpot()
useSecretPower(g)
g:answerSecretBaseYesNo(true)
eq(g.field.kind, "secret_base_yesno", "then the decorations warning")
check(g.field.text:find("decorations", 1, true) ~= nil,
  "SecretBase_Text_AllDecorationsWillBeReturned")
g:answerSecretBaseYesNo(true)
eq(g.secretBase.mapId, "route", "both yeses move the base to the new spot")
eq(g.secretBase.x, 3, "at the tile you dug")
eq(g.secretBase.y, 2, "one north of where you stood")
check(g._secretBaseMoveFrom == nil, "and the pending move is consumed")

-- With no base yet, CheckPlayerHasSecretBase is 0 and nothing is asked.
local fresh = atSpot()
fresh.secretBase = nil
useSecretPower(fresh)
check(fresh._secretBaseMoveFrom == nil, "a first base asks no move question")
eq(fresh.secretBase and fresh.secretBase.mapId, "route",
  "it is just created where you dug")
end)()

-- ------- FIRST COMES RELICANTH. LAST COMES WAILORD.

-- CheckRelicanthWailord compares MON_DATA_SPECIES2 against SPECIES_RELICANTH
-- and SPECIES_WAILORD, which are INTERNAL species ids (381 and 314), not
-- National Dex numbers. The dex numbers 369 and 321 are TROPIUS and TORKOAL
-- in internal order, so the check was asking for a TROPIUS in front and a
-- TORKOAL at the back and the Sealed Chamber could not be opened at all.
;(function()
eq(Game3.SPECIES_RELICANTH, 381, "RELICANTH is the internal id, not dex 369")
eq(Game3.SPECIES_WAILORD, 314, "WAILORD is the internal id, not dex 321")

local function party(list)
  local g = Game3.new()
  g.party = {}
  for i, sp in ipairs(list) do
    g.party[i] = { name = "M" .. i, species = sp, level = 40,
      hp = 1, maxHp = 1 }
  end
  return g
end
local R, W, OTHER = Game3.SPECIES_RELICANTH, Game3.SPECIES_WAILORD, 277

eq(party({ R, OTHER, OTHER, OTHER, OTHER, W }):checkRelicanthWailord(), 1,
  "RELICANTH first and WAILORD last opens it")
eq(party({ R, W }):checkRelicanthWailord(), 1,
  "a party of just the two works as well")
-- The order the player is most likely to get wrong: both present, reversed.
eq(party({ OTHER, OTHER, OTHER, OTHER, W, R }):checkRelicanthWailord(), 0,
  "WAILORD fifth and RELICANTH last does not")
eq(party({ W, OTHER, OTHER, OTHER, OTHER, R }):checkRelicanthWailord(), 0,
  "and neither does the straight swap")
eq(party({ R, OTHER, W, OTHER }):checkRelicanthWailord(), 0,
  "WAILORD has to be in the LAST filled slot")
eq(party({ OTHER, OTHER }):checkRelicanthWailord(), 0, "neither of them, no")

-- gPlayerPartyCount - 1 is the last filled slot, so a shorter party still works
local g = party({ R, OTHER, W })
eq(g:checkRelicanthWailord(), 1, "three mons, WAILORD last, still opens it")
end)()

S.finish()
