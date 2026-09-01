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
eq(loaded.scriptVars[Game3.VAR_CURRENT_SECRET_BASE], 42, "var 0x4054 comes back")
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
eq(g.field.kind, "talk", "A uses the selected pocket item")
eq(g.field.text, "Use this in battle.", "balls stay battle-only")
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
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), pechaBefore - 1,
  "PlantBerryTree spends the berry")

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

;(function()
local g = withGame()
g.trainerId = 2
g:setupMauvilleOldMan()
g:unlockTrendySaying(3)
g.decorations = { [21] = 1 }
check(g:writeSave(), "old man writes")
local loaded = withGame()
check(loaded:continueSave(), "CONTINUE restores the old man")
eq(loaded.mauvilleMan.id, Game3.MAUVILLE_MAN_HIPSTER, "id 2 is still hipster")
eq(loaded:trendySayingUnlocked(3), true, "taught trendy word comes back")
eq(loaded.decorations[21], 1, "PRETTY FLOWERS come back")
eq(loaded:getGameStat(Game3.GAME_STAT_SAVED_GAME) >= 1, true,
  "GAME_STAT_SAVED_GAME counted the write")
wipeRubySave()
local bare = withGame()
local oldSnap = bare:snapshotSave()
oldSnap.mauvilleMan, oldSnap.trendyUnlocked, oldSnap.decorations = nil, nil, nil
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
eq(g.field.kind, "party_use", "picker again")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "bag", "B is HandleDefaultPartyMenuInput cancel")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party_use", "Use again")
g.field.cursor = 6
g:stepField()
eq(g.field.kind, "bag", "A on CANCEL is B_BUTTON")

g.party[1] = { name = "EGG", species = 280, isEgg = true, hp = 0, maxHp = 20 }
g.party[2].hp = 0
g:openBag()
g:stepField()
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

S.finish()
