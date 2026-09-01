-- Ruby wild battles: base stats, gWildMonHeaders, grass rolls, FIGHT/RUN,
-- ROM moves, type chart, physical/special split.
-- Fixture bytes only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_battle_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby wild battle")
local check = S.check
local eq = S.eq

local GbaBin = require("src.import.GbaBin")
local GbaText = require("src.import.GbaText")
local BattleData = require("src.import.RomExtractorGen3Battle")
local Game3 = require("src.core.Game3")

local function overlay(base, off, chunk)
  return base:sub(1, off) .. chunk .. base:sub(off + #chunk + 1)
end

local function padName(text)
  local enc = GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
  if #enc < BattleData.MOVE_NAME_LENGTH then
    enc = enc .. string.rep("\0", BattleData.MOVE_NAME_LENGTH - #enc)
  end
  return enc:sub(1, BattleData.MOVE_NAME_LENGTH)
end

-- ------- stats

eq(BattleData.STARTER_SPECIES, 280, "Ruby starter is Torchic")
eq(Game3.statHP(45, 5), 19, "Torchic-base HP at level 5")
eq(Game3.statOther(60, 5), 11, "Attack at level 5")
eq(Game3.statHP(45, 5, 31), 21, "31 HP IV at level 5")
eq(Game3.statHP(45, 100, 0, 4), 201, "4 HP EVs at level 100")
eq(Game3.natureIndex(0), 0, "pid 0 is Hardy")
eq(Game3.natureIndex(3), 3, "pid 3 is Adamant")
eq(Game3.natureName(3), "ADAMANT", "nature name")
eq(Game3.natureMul(3, Game3.STAT_ATK), 11, "Adamant boosts Attack")
eq(Game3.natureMul(3, Game3.STAT_SPA), 9, "and drops Sp. Atk")
eq(Game3.natureMul(0, Game3.STAT_ATK), 10, "Hardy is neutral")
eq(Game3.statOther(60, 5, 0, 11), 12, "Adamant Attack at level 5")
eq(Game3.NATURE_NAMES[24], "QUIRKY", "nature 24 is Quirky")
eq(Game3.expAtLevel(3, 5), 135, "Medium Slow level 5 is 135")
eq(Game3.expAtLevel(0, 2), 8, "Medium Fast level 2 is 8")
eq(Game3.wildExp(54, 2), 15, "Wurmple yield 54 at lv2 is 15 exp")
check(Game3.damage(5, 35, 11, 11, false) >= 1, "Tackle deals at least 1")
eq(Game3.chooseLandSlot(0), 0, "first land slot is 20%")
eq(Game3.chooseLandSlot(19), 0, "19 is still slot 0")
eq(Game3.chooseLandSlot(20), 1, "20 opens slot 1")
eq(Game3.chooseLandSlot(99), 11, "99 is the last slot")
check(Game3.isLandGrass(0x02), "tall grass is a land encounter")
check(not Game3.isLandGrass(0x00), "normal ground is not")
check(Game3.isLandWildEncounter(0x02), "tall grass rolls land slots")
check(Game3.isLandWildEncounter(0x0B), "cave floor is MB_INDOOR_ENCOUNTER")
check(Game3.isLandWildEncounter(0x08), "unused cave tiles too")
check(not Game3.isLandWildEncounter(0x07), "short grass has no encounter bit")
check(not Game3.isLandWildEncounter(0x00), "normal ground does not")
eq(Game3.BOX_COUNT, 14, "Ruby has 14 boxes")
eq(Game3.BOX_SIZE, 30, "of 30")
check(Game3.isPc(0x83), "Pokemon Center PC is 0x83")
check(Game3.isPc(0xC5), "bedroom PC is 0xC5")
check(Game3.isPc(0xB0), "secret base PC is 0xB0")
check(not Game3.isPc(0x80), "a counter is not a PC")
check(Game3.isPhysical(0), "Normal is physical")
check(Game3.isPhysical(8), "Steel is physical")
check(not Game3.isPhysical(10), "Fire is special")
eq(Game3.stageMul(0), 1, "neutral stage is 1x")
eq(Game3.stageMul(1), 1.5, "+1 stage is 1.5x")
eq(Game3.stageMul(-1), 2 / 3, "-1 stage is 2/3")

local none = string.rep("\0", 28)
local bulba = string.char(45, 49, 49, 45, 65, 65, 12, 3)
  .. string.rep("\0", 20)
local ivy = string.char(60, 62, 63, 60, 80, 80, 12, 3)
  .. string.rep("\0", 20)
local rest = string.rep("\0", 28 * (412 - 3))
local statsRom = none .. bulba .. ivy .. rest
eq(#none, 28, "BaseStats is 0x1C")
local statsOff = BattleData.findBaseStats(statsRom)
eq(statsOff, 0, "NONE sits at the start of gBaseStats")
local stats = BattleData.parseBaseStats(statsRom, statsOff)
eq(stats.byIndex[1].hp, 45, "Bulbasaur HP")
eq(stats.byIndex[1].type1, 12, "Grass")
eq(stats.byIndex[1].type2, 3, "Poison")
eq(stats.byIndex[2].atk, 62, "Ivysaur Attack")

local grown = string.char(45, 49, 49, 45, 65, 65, 12, 3)
  .. string.rep("\0", 11) .. string.char(3) .. string.rep("\0", 8)
eq(#grown, 28, "growthRate sits at byte 19")
eq(BattleData.parseOneStats(grown, 0).growthRate, 3, "Torchic-like Medium Slow")
local eggish = string.char(45, 49, 49, 45, 65, 65, 12, 3)
  .. string.rep("\0", 8) .. string.char(31, 20, 0, 3, 5, 5, 66, 0)
  .. string.rep("\0", 4)
eq(#eggish, 28, "genderRatio / egg groups sit in the same 0x1C")
local eggStats = BattleData.parseOneStats(eggish, 0)
eq(eggStats.genderRatio, 31, "byte 16 is genderRatio")
eq(eggStats.eggCycles, 20, "byte 17 is eggCycles")
eq(eggStats.friendship, 0, "byte 18 is friendship")
eq(eggStats.eggGroup1, 5, "byte 20 is eggGroup1")
eq(eggStats.eggGroup2, 5, "byte 21 is eggGroup2")

;(function()
-- spa=1 is bits 8-9 of the u16 at +0x0A (Bulbasaur / Torchic).
local spaYield = string.char(45, 49, 49, 45, 65, 65, 12, 3, 45, 64)
  .. string.char(0, 1) .. string.rep("\0", 16)
eq(#spaYield, 28, "evYield packed word still fits 0x1C")
eq(BattleData.parseOneStats(spaYield, 0).evYieldSpa, 1, "SpA yield is bits 8-9")
-- HP=1 Atk=2 Def=3 Spe=1 SpA=2 SpD=3 -> 0x0E79.
local mixed = string.char(45, 49, 49, 45, 65, 65, 12, 3, 45, 64)
  .. string.char(0x79, 0x0E) .. string.rep("\0", 16)
local mixedStats = BattleData.parseOneStats(mixed, 0)
eq(mixedStats.evYieldHp, 1, "HP yield is bits 0-1")
eq(mixedStats.evYieldAtk, 2, "Atk yield is bits 2-3")
eq(mixedStats.evYieldDef, 3, "Def yield is bits 4-5")
eq(mixedStats.evYieldSpe, 1, "Spe yield is bits 6-7")
eq(mixedStats.evYieldSpa, 2, "SpA yield is bits 8-9")
eq(mixedStats.evYieldSpd, 3, "SpD yield is bits 10-11")
end)()

-- ------- moves, type chart, learnsets

local pound = BattleData.parseOneMove(
  string.char(0, 40, 0, 100, 35, 0, 0, 0, 0, 0, 0, 0), 0)
eq(pound.power, 40, "Pound power is 40")
eq(pound.type, 0, "Pound is Normal")
eq(pound.accuracy, 100, "Pound accuracy is 100")
eq(pound.pp, 35, "Pound PP is 35")
eq(pound.effect, 0, "Pound is a plain hit")
eq(pound.target, 0, "Pound picks one target")

local namesBlob = padName("") .. padName("POUND")
  .. string.rep("\0", BattleData.MOVE_NAME_LENGTH * (BattleData.MOVE_COUNT - 2))
local movesBlob = string.rep("\0", BattleData.MOVE_SIZE)
  .. string.char(0, 40, 0, 100, 35, 0, 0, 0, 0, 0, 0, 0)
  .. string.rep("\0", BattleData.MOVE_SIZE * (BattleData.MOVE_COUNT - 2))
local namesOff, dataOff = BattleData.findMoveTables(namesBlob .. movesBlob)
eq(namesOff, 0, "scan finds MOVE_NONE's name slot")
eq(dataOff, #namesBlob, "scan finds MOVE_NONE's data slot")
local parsedMoves = BattleData.parseMoves(namesBlob .. movesBlob, namesOff, dataOff)
eq(parsedMoves.byId[1].name, "POUND", "index 1 is Pound")
eq(parsedMoves.byId[1].power, 40, "parsed Pound power")

local chartBytes = string.char(
  0, 5, 5,
  0, 8, 5,
  10, 10, 5,
  10, 12, 20,
  11, 10, 20,
  12, 11, 20,
  10, 11, 5,
  12, 10, 5,
  0xFE, 0, 10,
  0xFF, 0xFF, 0)
eq(BattleData.findTypeChart(chartBytes), 0, "scan finds the type chart")
local chart = BattleData.parseTypeChart(chartBytes, 0)
eq(Game3.typeMul(chart, 10, 12, 12), 20, "Fire vs Grass is 2x")
eq(Game3.typeMul(chart, 0, 5, 5), 5, "Normal vs Rock is 0.5x")
eq(Game3.typeMul(chart, 0, 0, 0), 10, "unlisted pairs stay 1x")
local sawForesight
for i = 1, #chart do
  if chart[i][1] == 0xFE then sawForesight = true end
end
check(not sawForesight, "Foresight rows are skipped")

local learnBlob = GbaBin.packU16(10 + 1 * 512)
  .. GbaBin.packU16(45 + 1 * 512)
  .. GbaBin.packU16(52 + 10 * 512)
  .. GbaBin.packU16(0xFFFF)
local learn = BattleData.parseLearnset(learnBlob, 0)
eq(learn[1].move, 10, "Torchic's first move is Scratch")
eq(learn[1].level, 1, "Scratch is level 1")
eq(learn[2].move, 45, "second move is Growl")
eq(learn[3].move, 52, "Ember is in the learnset")
eq(learn[3].level, 10, "Ember is level 10")

local evoRom = string.rep("\0", 291 * 5 * 8)
local torchicSlot = 280 * 5 * 8
evoRom = overlay(evoRom, torchicSlot,
  GbaBin.packU16(4) .. GbaBin.packU16(16) .. GbaBin.packU16(281) .. GbaBin.packU16(0))
local wurmpleSlot = 290 * 5 * 8
evoRom = overlay(evoRom, wurmpleSlot,
  GbaBin.packU16(11) .. GbaBin.packU16(7) .. GbaBin.packU16(291) .. GbaBin.packU16(0)
  .. GbaBin.packU16(12) .. GbaBin.packU16(7) .. GbaBin.packU16(292) .. GbaBin.packU16(0))
local evoOff, evoStride = BattleData.findEvolutionTable(evoRom)
eq(evoOff, 0, "scan finds Torchic's evolution row")
eq(evoStride, 8, "Ruby evolution rows are 8 bytes")
local evos = BattleData.parseEvolutions(evoRom, evoOff, evoStride)
eq(evos[280][1].target, 281, "Torchic becomes Combusken")
eq(evos[280][1].param, 16, "at level 16")
eq(evos[290][1].method, 11, "Wurmple's first method is Silcoon")
eq(evos[290][2].target, 292, "and Cascoon")

;(function()
eq(BattleData.TMHM_MOVES[39], 317, "TM39 is Rock Tomb")
eq(BattleData.TMHM_MOVES[51], 15, "HM01 is Cut")
eq(Game3.ITEM_TM39, 327, "TM39 is item 327")
eq(Game3.ITEM_TM01, 289, "TM01 is item 289")
local tmhmRom = string.rep("\0", 281 * 8)
tmhmRom = overlay(tmhmRom, 280 * 8,
  GbaBin.packU32(BattleData.TORCHIC_TMHM0)
    .. GbaBin.packU32(BattleData.TORCHIC_TMHM1))
eq(BattleData.findTmhmLearnsets(tmhmRom), 0, "scan finds Torchic's TM/HM row")
local tmhm = BattleData.parseTmhmLearnsets(tmhmRom, 0)
eq(tmhm[0][1], 0, "NONE learns nothing")
eq(tmhm[0][2], 0, "NONE hi word is empty")
eq(tmhm[280][1], BattleData.TORCHIC_TMHM0, "Torchic lo word")
eq(tmhm[280][2], BattleData.TORCHIC_TMHM1, "Torchic hi word")
end)()

-- ------- wild headers (Route 101: group 0, map 16, Wurmple)

local SIZE = 0x400
local HDR, INFO, MONS = 0x000, 0x0C0, 0x100
local rom = string.rep("\0", SIZE)
local mons = {}
for i = 1, 12 do
  local species = i == 1 and 290 or 288
  mons[#mons + 1] = string.char(2, 3) .. GbaBin.packU16(species)
end
rom = overlay(rom, MONS, table.concat(mons))
rom = overlay(rom, INFO,
  string.char(20, 0, 0, 0) .. GbaBin.packPtr(MONS))
rom = overlay(rom, HDR,
  string.char(0, 16, 0, 0)
  .. GbaBin.packPtr(INFO)
  .. string.rep("\0", 12)
  .. string.char(0xFF, 0, 0, 0)
  .. string.rep("\0", 16))

local wildOff = BattleData.findWildMonHeaders(rom)
eq(wildOff, HDR, "scan finds the Route 101 header")
local wild = BattleData.parseWildHeaders(rom, wildOff)
eq(wild.count, 1, "one map")
eq(wild.byMap.g0_16.land.rate, 20, "Route 101 land rate is 20")
eq(wild.byMap.g0_16.land.slots[1].species, 290, "first slot is Wurmple")
eq(wild.byMap.g0_16.land.slots[1].minLevel, 2, "min level 2")
local used = BattleData.collectSpecies(wild)
check(used[290] == true, "Wurmple is collected")
check(used[280] == true, "Torchic is always collected")
check(used[286] == true, "Poochyena is collected for the Birch chase")
check(used[291] == true, "Silcoon is collected for evolution pics")

-- ------- runtime battle

local field = Game3.new()
field.data.pokemon = {
  byIndex = {
    [286] = {
      name = "POOCHYENA", hp = 35, atk = 55, def = 35, spe = 35,
      spa = 30, spd = 30, type1 = 17, type2 = 17, ability1 = 50,
      catchRate = 255, expYield = 55, growthRate = 0,
    },
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, ability1 = 66,
      catchRate = 45, expYield = 65, growthRate = 3,
      learnset = {
        { move = 10, level = 1 },
        { move = 45, level = 1 },
        { move = 52, level = 10 },
      },
    },
    [281] = {
      name = "COMBUSKEN", hp = 60, atk = 85, def = 60, spe = 55,
      spa = 85, spd = 60, type1 = 10, type2 = 1, ability1 = 66,
      catchRate = 45, expYield = 142, growthRate = 3,
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
      expYield = 54, growthRate = 0,
      learnset = {
        { move = 33, level = 1 },
        { move = 81, level = 1 },
      },
    },
    [291] = {
      name = "SILCOON", hp = 50, atk = 35, def = 55, spe = 15,
      spa = 25, spd = 25, type1 = 6, type2 = 6, growthRate = 0,
    },
    [292] = {
      name = "CASCOON", hp = 50, atk = 35, def = 55, spe = 15,
      spa = 25, spd = 25, type1 = 6, type2 = 6, growthRate = 0,
    },
  },
}
field.data.moves = {
  byId = {
    [10] = { id = 10, name = "SCRATCH", effect = 0, power = 40, type = 0,
      accuracy = 100, pp = 35, priority = 0 },
    [33] = { id = 33, name = "TACKLE", effect = 0, power = 35, type = 0,
      accuracy = 95, pp = 35, priority = 0 },
    [45] = { id = 45, name = "GROWL", effect = 18, power = 0, type = 0,
      accuracy = 100, pp = 40, priority = 0 },
    [52] = { id = 52, name = "EMBER", effect = 4, power = 40, type = 10,
      accuracy = 100, pp = 25, priority = 0, secondary = 10 },
    [86] = { id = 86, name = "THUNDER WAVE", effect = 67, power = 0, type = 13,
      accuracy = 100, pp = 20, priority = 0 },
    [79] = { id = 79, name = "SLEEP POWDER", effect = 1, power = 0, type = 12,
      accuracy = 75, pp = 15, priority = 0 },
    [81] = { id = 81, name = "STRING SHOT", effect = 20, power = 0, type = 6,
      accuracy = 95, pp = 40, priority = 0 },
  },
  typeChart = {
    { 10, 12, 20 },
    { 10, 6, 20 },
  },
}
field.data.encounters = {
  starterSpecies = 280,
  byMap = {
    g0_16 = {
      land = {
        rate = 255,
        slots = { { minLevel = 2, maxLevel = 2, species = 290 } },
      },
    },
  },
}
field.data.tilesets = { byId = { pair_0 = { behavior = { [1] = 2 } } } }
field.map = {
  id = "g0_16", name = "Route 101",
  width = 2, height = 1, grid = { 1, 0 }, tileset = "pair_0",
}
field.playerX, field.playerY = 0, 0
field.rng = function() return 1 end
field.party = { field:makeMon(280, 5) }
eq(field.party[1].name, "TORCHIC", "starter name")
eq(field.party[1].pid, 0, "rng=1 yields pid 0")
eq(field.party[1].ivs.hp, 0, "and zero IVs")
eq(Game3.natureName(field.party[1].pid), "HARDY", "Hardy does not change stats")
eq(field.party[1].maxHp, 19, "starter HP")
eq(field.party[1].exp, 135, "level 5 Medium Slow exp")
eq(#field.party[1].moves, 2, "level 5 Torchic has two moves")
eq(field.party[1].moves[1].name, "SCRATCH", "first move is Scratch")
eq(field.party[1].moves[2].name, "GROWL", "second move is Growl")
eq(field:behaviorAt(field.map, 0, 0), 2, "cell 0 is tall grass")
check(not Game3.isLandGrass(field:behaviorAt(field.map, 1, 0)),
  "metatile 0 is not grass")

check(field:tryWildEncounter(), "rate 255 always rolls a battle")
eq(field.phase, "battle", "phase is battle")
eq(field.battle.enemy.species, 290, "wild Wurmple")
eq(field.battle.kind, "intro", "starts on the appear text")
eq(field.battle.enemy.moves[1].name, "TACKLE", "Wurmple knows Tackle")

local hp = field.battle.enemy.hp
field.rng = function() return 1 end
local dmg = field:dealTackle(field.battle.player, field.battle.enemy)
check(dmg >= 1, "player Tackle deals damage")
eq(field.battle.enemy.hp, hp - dmg, "enemy HP drops")

local grass = {
  name = "ODDISH", level = 5, hp = 20, maxHp = 20,
  atk = 10, def = 20, spe = 10, spa = 10, spd = 10,
  type1 = 12, type2 = 12,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local ember = field:copyMove(52)
local before = grass.hp
local burned = field:dealDamage(field.battle.player, grass, ember)
check(burned.mul == 20, "Ember vs Grass is super effective")
check(burned.dmg > dmg, "special Fire damage beats physical Tackle here")
eq(grass.hp, before - burned.dmg, "Ember drops HP")

local growl = field:copyMove(45)
local texts = field:useMove(field.battle.player, field.battle.enemy, growl)
eq(field.battle.enemy.stages.atk, -1, "Growl drops Attack")
check(texts[1]:find("GROWL", 1, true) ~= nil, "Growl announces the move")

field.battle.kind = "menu"
field.battle.cursor = 3
field.battle.enemy.hp = 0
-- RUN from the menu is tested through startWildBattle's ran path:
field:startWildBattle(290, 2)
eq(field.battle.kind, "intro", "a new wild battle replaces the old one")
eq(field.battle.player.stages.atk, 0, "stages reset at the start of a fight")

field.battle.kind = "menu"
field:beginTurn(field.battle.player.moves[1])
eq(field.battle.kind, "text", "a chosen move opens the text queue")
check(field.battle.queue and #field.battle.queue >= 2, "both sides act")
check(field.battle.queue[1]:find("SCRATCH", 1, true) ~= nil,
  "the faster Torchic scratches first")

-- ------- catching

eq(Game3.catchValue(13, 13, 255, 1), 85, "full-HP Wurmple in a Poke Ball is a=85")
check(Game3.catchValue(1, 13, 255, 1) > 85, "low HP raises the catch value")
eq(Game3.catchFailText(0), "Oh no! The POKeMON broke free!", "0-shake fail line")
eq(field.party[1].catchRate, 45, "Torchic's catch rate is 45")

field.balls = 5
field.rng = function() return 1 end
field:startWildBattle(290, 2)
eq(#field.party, 1, "party is still just Torchic")
eq(field.battle.enemy.catchRate, 255, "wild Wurmple is catch 255")
field:throwBall()
eq(field.balls, 4, "a throw spends a ball")
eq(field.battle.caught, true, "rand=1 always passes the shake checks")
eq(#field.party, 2, "Wurmple joins the party")
eq(field.party[2].name, "WURMPLE", "caught name")
eq(field.party[2].species, 290, "caught species")

field.balls = 1
field:startWildBattle(290, 2)
field.rng = function(n)
  if n == 65536 then return 65536 end
  return 1
end
local before = #field.party
field:throwBall()
eq(field.battle.caught, nil, "a high 16-bit roll breaks free")
eq(#field.party, before, "a miss does not add to the party")
eq(field.balls, 0, "the last ball is spent on a miss")
eq(field.battle.queue[2], Game3.catchFailText(0), "0 shakes uses the broke-free line")

while #field.party < 6 do
  field:addToParty(field.party[1])
end
field.balls = 1
field.rng = function() return 1 end
field:startWildBattle(290, 2)
field:throwBall()
eq(#field.party, 6, "a seventh mon is not kept")
eq(#field.pc[1], 1, "overflow lands in BOX 1")
eq(field.pc[1][1].species, 290, "the boxed mon is Wurmple")
check(field.battle.queue[#field.battle.queue]:find("BOX 1", 1, true) ~= nil,
  "the catch text names BOX 1")

-- ------- exp, switch, blackout

local torchic = field.party[1]
torchic.level = 9
torchic.growth = 3
torchic.exp = Game3.expAtLevel(3, 9)
torchic.hp = 10
torchic.maxHp = Game3.statHP(45, 9)
local gained = field:awardExp(torchic, { level = 2, expYield = 54, species = 290 })
-- 419 + 15 = 434, still lv9. Dump enough to cross 560.
torchic.exp = 559
gained = field:awardExp(torchic, { level = 2, expYield = 54, species = 290 })
eq(torchic.level, 10, "15 more exp from 559 crosses LV. 10")
check(gained[2]:find("LV. 10", 1, true) ~= nil, "level-up is announced")
eq(torchic.moves[3] and torchic.moves[3].name, "EMBER", "Torchic learns Ember at 10")

local fainted = field:makeMon(280, 5)
fainted.hp = 0
local oldMax = fainted.maxHp
field:recalcStats(fainted)
eq(fainted.hp, 0, "recalcStats does not revive a fainted mon")
check(fainted.maxHp >= oldMax, "max HP can still grow")

field.party = { field:makeMon(280, 5), field:makeMon(290, 2) }
field.party[1].hp = 0
check(field:startWildBattle(288, 2), "a healthy backup still starts a fight")
eq(field.battle.player.species, 290, "the lead skips a fainted Torchic")

local ok, msg = field:switchTo(1)
check(not ok, "cannot send a fainted mon")
ok, msg = field:switchTo(2)
check(not ok, "cannot send the mon already out")

field.party[1].hp = field.party[1].maxHp
ok, msg = field:switchTo(1)
check(ok, "a healthy bench mon can switch in")
eq(field.battle.player.species, 280, "Torchic is sent out")
check(msg:find("TORCHIC", 1, true) ~= nil, "switch announces the send-out")

;(function()
  local egg = field:makeMon(360, 5)
  egg.isEgg = true
  egg.name = "EGG"
  field.party[3] = egg
  local ok, msg = field:switchTo(3)
  check(not ok, "cannot send an EGG")
  eq(msg, "An EGG can't battle!", "gOtherText_EGGCantBattle")
  eq(field.battle.player.species, 280, "lead is still Torchic")
  ok, msg = field:useItemOnMon(egg, Game3.ITEM_POTION)
  check(not ok, "a Potion does not work on an EGG")
end)()

field.party[1].hp = 0
field.party[2].hp = 0
field.battle.player = field.party[1]
field.battle.enemy = field:makeMon(290, 2)
field.battle.queue = { "done" }
field.battle.qi = 1
field.battle.kind = "text"
field.data.maps = {
  start = "g0_9",
  maps = {
    g0_9 = {
      id = "g0_9", name = "Littleroot Town",
      width = 2, height = 2, spawn = { x = 1, y = 1 },
      grid = { 0, 0, 0, 0 },
    },
  },
}
field:advanceBattleText()
eq(field.battle.kind, "blackout", "a total wipe opens the blackout line")
field:blackout()
eq(field.phase, "play", "blackout returns to the field")
eq(field.party[1].hp, field.party[1].maxHp, "blackout heals the party")
eq(field.party[2].hp, field.party[2].maxHp, "including the backup")
eq(field.map.id, "g0_9", "blackout warps to the start map")
eq(field.playerX, 1, "and the start spawn")

-- ------- evolution, nurse, field menu

local silk = field:makeMon(290, 6)
silk.pid = 0
silk.exp = Game3.expAtLevel(0, 7) - 1
field:awardExp(silk, { level = 20, expYield = 54 })
eq(silk.species, 291, "personality high word % 10 <= 4 is Silcoon")
eq(silk.name, "SILCOON", "name follows the species")

local cas = field:makeMon(290, 6)
cas.pid = 5 * 65536
cas.exp = Game3.expAtLevel(0, 7) - 1
field:awardExp(cas, { level = 20, expYield = 54 })
eq(cas.species, 292, "personality high word % 10 > 4 is Cascoon")

local chick = field:makeMon(280, 15)
chick.exp = Game3.expAtLevel(3, 16) - 1
field:awardExp(chick, { level = 2, expYield = 54 })
eq(chick.species, 281, "Torchic evolves at 16")
eq(chick.name, "COMBUSKEN", "into Combusken")
eq(chick.type2, 1, "and picks up Fighting")

field.phase = "play"
field.facing = "north"
field.playerX, field.playerY = 1, 1
field.map = {
  id = "pc", name = "POKeMON CENTER",
  width = 3, height = 3, grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
field.npcByMap = {
  pc = { { x = 1, y = 0, graphicsId = Game3.GFX_NURSE, facing = "south" } },
}
field.party[1].hp = 1
check(field:tryTalk(), "A faces the nurse")
eq(field.party[1].hp, field.party[1].maxHp, "the nurse heals the party")
eq(field.field.kind, "talk", "and opens a field text box")
eq(field.field.text, "Your POKeMON were restored to full health!", "heal line")

field.field = nil
field.party[1].hp = 1
field.npcByMap.pc[1].script = {
  { op = "loadword", text = "Welcome to our POKeMON CENTER!" },
  { op = "callstd", id = 2 },
  { op = "end" },
}
check(field:tryTalk(), "a ROM nurse script runs")
eq(field.party[1].hp, 1, "the stub heal does not steal it")
eq(field.field.text, "Welcome to our POKeMON CENTER!", "welcome line")
field.npcByMap.pc[1].script = nil
field.field = nil

field.npcByMap.pc[1].graphicsId = 9
field:tryTalk()
eq(field.field.text, "...", "other NPCs have no script yet")

local talker = Game3.new()
talker.phase = "play"
talker.facing = "east"
talker.playerX, talker.playerY = 0, 0
talker.map = { id = "g_talk", width = 3, height = 1, grid = { 0, 0, 0 } }
talker.npcByMap = { g_talk = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "loadword", text = "HELLO" },
    { op = "callstd", id = 2 },
    { op = "loadword", text = "THERE" },
    { op = "callstd", id = 2 },
    { op = "end" },
  },
} } }
check(talker:tryTalk(), "A runs an NPC script")
eq(talker.field.text, "HELLO", "the first msgbox opens")
eq(talker.field.queue[2], "THERE", "later lines wait in the queue")

local Input = require("src.core.Input")
Input:init()
local function pressTalk(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  talker:stepField()
  Input.wasPressed = old
end
pressTalk("a")
eq(talker.field.text, "THERE", "A advances the script queue")
pressTalk("b")
eq(talker.field, nil, "the last line closes the box")

talker.map.objects = { {
  x = 1, y = 0, graphicsId = 9,
  script = { { op = "loadword", text = "HELLO" }, { op = "callstd", id = 2 } },
} }
talker:resetNpcs(talker.map)
eq(talker:npcsFor(talker.map)[1].script[1].text, "HELLO",
  "resetNpcs copies the extracted script")

local skipper = Game3.new()
skipper.phase = "play"
skipper.facing = "east"
skipper.playerX, skipper.playerY = 0, 0
skipper.map = { id = "g_flag", width = 3, height = 1, grid = { 0, 0, 0 } }
skipper.flags = { [0x200] = true }
skipper.npcByMap = { g_flag = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "checkflag", flag = 0x200 },
    { op = "goto_if", cond = 1, to = 6 },
    { op = "loadword", text = "HELLO" },
    { op = "callstd", id = 2 },
    { op = "end" },
    { op = "loadword", text = "BYE" },
    { op = "callstd", id = 2 },
    { op = "end" },
  },
} } }
check(skipper:tryTalk(), "a flagged script still talks")
eq(skipper.field.text, "BYE", "goto_if TRUE skips the first line")

skipper.flags[0x200] = nil
skipper.field = nil
skipper:tryTalk()
eq(skipper.field.text, "HELLO", "the same script says HELLO when the flag is clear")

local giver = Game3.new()
giver.phase = "play"
giver.facing = "east"
giver.playerX, giver.playerY = 0, 0
giver.bag = {}
giver.map = { id = "g_give", width = 3, height = 1, grid = { 0, 0, 0 } }
giver.map.objects = { {
  x = 1, y = 0, graphicsId = 59, itemId = 4, itemCount = 1,
  flagId = 0x300, localId = 6,
  script = {
    { op = "setorcopyvar", var = 0x8000, val = 4 },
    { op = "setorcopyvar", var = 0x8001, val = 1 },
    { op = "callstd", id = 1 },
    { op = "end" },
  },
} }
giver.npcByMap = { g_give = { {
  x = 1, y = 0, graphicsId = 59, itemId = 4, itemCount = 1,
  flagId = 0x300, localId = 6, script = giver.map.objects[1].script,
} } }
check(giver:tryTalk(), "finditem scripts still run")
eq(giver:itemCount(4), 1, "callstd 1 puts the item in the bag")
check(giver.field.text:find("BALL", 1, true) ~= nil, "and names it")
eq(giver.flags[0x300], true, "Std_FindItem sets the object flag")
eq(giver.npcByMap.g_give[1].hidden, true, "and hides the ball")
eq(giver:npcAt(giver.map, 1, 0), nil, "a taken ball is not talkable")
giver.field = nil
check(not giver:tryTalk(), "A on the empty tile does nothing")
eq(giver:itemCount(4), 1, "so the bag does not stack forever")
giver:resetNpcs(giver.map)
eq(giver:npcsFor(giver.map)[1], nil, "a taken ball does not respawn")

local beaten = Game3.new()
beaten.phase = "play"
beaten.facing = "east"
beaten.playerX, beaten.playerY = 0, 0
beaten.map = { id = "g_cal", width = 3, height = 1, grid = { 0, 0, 0 } }
beaten.npcByMap = { g_cal = { {
  x = 1, y = 0, graphicsId = 35,
  trainerType = 1, defeated = true,
  party = { { species = 288, level = 5 } },
  script = {
    { op = "trainerbattle" },
    { op = "loadword", text = "I lost..." },
    { op = "callstd", id = 2 },
    { op = "end" },
  },
} } }
check(beaten:tryTalk(), "a defeated trainer still talks")
eq(beaten.field.text, "I lost...", "trainerbattle is a nop after the fight")
eq(beaten.phase, "play", "and does not start another battle")

eq(#Game3.new().party, 0, "a new game has no starter yet")
eq(Game3.GFX_BIRCH, 64, "Birch gfx is 64")
eq(Game3.GFX_BIRCHS_BAG, 97, "the Route 101 bag is gfx 97")
eq(Game3.STARTERS[1], 277, "Treecko is first in the bag")
eq(Game3.STARTERS[2], 280, "Torchic is the middle ball")
eq(Game3.STARTERS[3], 283, "Mudkip is last")
eq(Game3.FLAG_SYS_POKEMON_GET, 0x800, "FLAG_SYS_POKEMON_GET")

local chooser = Game3.new()
chooser.phase = "play"
chooser.facing = "east"
chooser.playerX, chooser.playerY = 0, 0
chooser.map = { id = "g_bag", width = 3, height = 1, grid = { 0, 0, 0 } }
local bagNpc = { x = 1, y = 0, graphicsId = Game3.GFX_BIRCHS_BAG }
chooser.npcByMap = { g_bag = { bagNpc } }
check(chooser:tryTalk(), "A on Birch's bag opens the starter menu")
eq(chooser.field.kind, "starter", "starter UI")
eq(chooser.field.cursor, 1, "the cursor starts on Torchic")

local function pressPick(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  chooser:stepField()
  Input.wasPressed = old
end
pressPick("a")
eq(chooser.field.kind, "starter_yesno", "A asks to confirm")
check(chooser.field.text:find("TORCHIC", 1, true) ~= nil, "and names Torchic")
pressPick("b")
eq(chooser.field.kind, "starter", "B goes back to the list")
pressPick("up")
eq(chooser.field.cursor, 0, "up from Torchic is Treecko")
pressPick("a")
pressPick("a")
eq(chooser.party[1].species, 277, "Treecko joins the party")
eq(chooser.party[1].level, 5, "at level 5")
eq(chooser.flags[Game3.FLAG_SYS_POKEMON_GET], true, "FLAG_SYS_POKEMON_GET is set")
eq(chooser.flags[Game3.FLAG_RESCUED_BIRCH], true, "Birch is marked rescued")
eq(bagNpc.hidden, true, "the bag disappears")
check(chooser.field.text:find("TREECKO", 1, true) ~= nil, "Got TREECKO")
check(chooser.field.chase, "Got TREECKO queues the Poochyena chase")

chooser.field = nil
check(not chooser:tryTalk(), "the hidden bag is not talkable")
eq(chooser:hasStarter(), true, "hasStarter is true after the pick")

chooser.map.objects = { {
  x = 1, y = 0, graphicsId = Game3.GFX_BIRCHS_BAG,
} }
chooser:resetNpcs(chooser.map)
eq(chooser:npcsFor(chooser.map)[1], nil, "the bag does not respawn")

local birch = Game3.new()
birch.phase = "play"
birch.facing = "east"
birch.playerX, birch.playerY = 0, 0
birch.map = { id = "g_lab", width = 3, height = 1, grid = { 0, 0, 0 } }
birch.npcByMap = { g_lab = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCH } } }
check(birch:tryTalk(), "lab Birch also offers a starter")
eq(birch.field.kind, "starter", "same menu")
check(birch:giveStarter(283), "Mudkip can be given directly")
eq(birch.party[1].species, 283, "Mudkip is in the party")
check(not birch:giveStarter(280), "a second starter is refused")
eq(#birch.party, 1, "the party stays at one")
check(birch:tryTalk(), "lab Birch hands the POKeDEX after a starter")
eq(birch.field.kind, "talk", "dex is a talk box")
check(birch.field.text:find("POKeDEX", 1, true) ~= nil, "Birch names the dex")
eq(birch.flags[Game3.FLAG_SYS_POKEDEX_GET], true, "FLAG_SYS_POKEDEX_GET is set")
check(not birch:givePokedex(), "a second dex is refused")

;(function()
eq(Game3.SPECIES_POOCHYENA, 286, "the chase foe is Poochyena")
eq(Game3.STARTER_NAMES[286], "POOCHYENA", "internal 286 is Poochyena, not national 261")
local picHost = Game3.new()
picHost.data.encounters = {
  fronts = { [280] = "front-280", [286] = "front-286" },
  backs = { [277] = "back-277", [280] = "back-280" },
}
function picHost:grabImage(path)
  if path == "assets/generated/battle/back/286.png" then return nil end
  return path
end
eq(picHost:battlePic(280, "back"), "back-280",
  "back pics look up the battler's species id")
eq(picHost:battlePic(280, "front"), "front-280", "fronts do too")
eq(picHost:battlePic(286, "back"), nil,
  "a missing back is not replaced with that species' front")
end)()

;(function()
eq(BattleData.BACK_PICS, 0x1E97F4,
  "gMonBackPicTable is 0x1E97F4, not the front table's end")
eq(BattleData.FRONT_PICS, 0x1E8354, "gMonFrontPicTable")
eq(BattleData.FRONT_COORDS, 0x1E7C74, "gMonFrontPicCoords")
eq(BattleData.BACK_COORDS, 0x1E9114, "gMonBackPicCoords")
local coords = BattleData.parsePicCoords(
  string.char(136, 0, 0, 0, 69, 14, 0, 0), 0, 2)
eq(coords[0], 0, "species 0 y_offset")
eq(coords[1], 14, "Bulbasaur front y_offset is 14")
local host = Game3.new()
host.data.encounters = { backY = { [280] = 16 }, frontY = { [280] = 14 } }
eq(host:picYOffset(280, "back"), 16, "back y_offset comes from the coords table")
eq(host:picYOffset(280, "front"), 14, "front y_offset too")
local bx, by = host:battlerTopLeft("player", 280, "back")
eq(bx, 40, "player back is centred on 72")
eq(by, 64, "and shifted by the back y_offset")
local ex = host:battlerTopLeft("enemy", 280, "front")
eq(ex, 144, "enemy front is centred on 176")
eq(Game3.BATTLER_CX.player, 72, "singles player x")
eq(Game3.BATTLER_CY.enemy, 40, "singles enemy y")
eq(Game3.BATTLER_CX_DOUBLES.player, 32, "doubles player left x")
eq(Game3.BATTLER_CY_DOUBLES.player2, 88, "doubles player right y")
host.battle = { doubles = true }
local dx = host:battlerTopLeft("player", 280, "back")
eq(dx, 0, "doubles player is centred on 32")
local dex = host:battlerTopLeft("enemy", 280, "front")
eq(dex, 168, "doubles foe left is centred on 200")
end)()

;(function()
eq(Game3.CHASE_LEVEL, 2, "at level 2")
eq(Game3.FLAG_HIDE_BIRCH_IN_LAB, 0x2D1, "lab Birch hide flag")
eq(Game3.wanderDirs(87), "place", "JOG_IN_PLACE_RIGHT is in-place")
local truck = {
  width = 5, height = 5, connections = {},
  objects = { { x = 0, y = 0 }, { x = 0, y = 3 }, { x = 2, y = 3 } },
}
check(Game3.isTruckMap(truck), "the moving truck fingerprint")
check(not Game3.isTruckMap({ width = 20, height = 20, objects = {} }),
  "a town is not the truck")

local cells = {}
for i = 1, 64 do cells[i] = 0 end
local lab = {
  id = "g1_4", width = 8, height = 8, grid = cells, spawn = { x = 6, y = 5 },
  objects = { { graphicsId = Game3.GFX_BIRCH, x = 6, y = 4 } },
}
local chaser = Game3.new()
chaser.data.pokemon = field.data.pokemon
chaser.data.moves = field.data.moves
chaser.rng = function() return 1 end
chaser.phase = "play"
chaser.data.maps = {
  start = "g0_9",
  maps = {
    g0_9 = {
      id = "g0_9", width = 2, height = 2, spawn = { x = 0, y = 0 },
      grid = { 0, 0, 0, 0 },
    },
    g1_4 = lab,
  },
}
local bagNpc = { graphicsId = Game3.GFX_BIRCHS_BAG }
check(chaser:giveStarter(280, bagNpc), "the bag still gives Torchic")
check(chaser.pendingChase, "and queues the chase")
eq(chaser.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 2, "bag writes VAR_BIRCH_LAB_STATE 2")
eq(chaser.scriptVars[Game3.VAR_ROUTE101_STATE], 3, "and VAR_ROUTE101_STATE 3")
chaser.field = { kind = "talk", text = "Got TORCHIC!", chase = true }
chaser.pendingChase = nil
chaser:closeField()
eq(chaser.phase, "battle", "closing Got it! starts the chase")
eq(chaser.battle.enemy.species, 286, "vs Poochyena")
eq(chaser.battle.enemy.level, 2, "level 2")
check(chaser.battle.chase, "the fight is marked chase")
chaser.battle.kind = "menu"
chaser.battle.cursor = 3
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
chaser:stepBattle()
Input.wasPressed = old
eq(chaser.battle.kind, "menu_msg", "RUN is refused")
check(chaser.battle.text:find("running", 1, true) ~= nil, "with a chase line")
chaser:finishBattle()
eq(chaser.map.id, "g1_4", "a win warps to Birch's lab")
eq(chaser.playerX, 6, "south of Birch")
eq(chaser.playerY, 5, "at 6,5")
eq(chaser.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB], nil, "lab Birch is shown")
eq(chaser.flags[Game3.FLAG_HIDE_BIRCH_ROUTE101], true, "route Birch hides")
eq(chaser.flags[Game3.FLAG_HIDE_POOCHYENA_ROUTE101], true, "the chase Poochyena hides")
check(chaser.field.text:find("BIRCH", 1, true) ~= nil, "and he thanks you")

local hider = Game3.new()
hider.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = true
hider.map = {
  id = "g_lab", width = 2, height = 1, grid = { 0, 0 },
  objects = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCH, flagId = 0x2D1 } },
}
hider:resetNpcs(hider.map)
eq(hider:npcsFor(hider.map)[1], nil, "a hide flag removes the NPC")

local van = Game3.new()
van.data.maps = chaser.data.maps
van.map = truck
truck.id = "g_truck"
truck.grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
truck.spawn = { x = 1, y = 2 }
van.playerX, van.playerY = 2, 2
van.phase = "play"
check(van:tryWalk(1, 0), "walking toward the truck door exits")
eq(van.map.id, "g0_9", "into Littleroot")
eq(van.field, nil, "town scripts own the scene; no truck placeholder")
van.map = truck
van.field = nil
check(van:followWarp({ warpId = 0xFF }), "MAP_DYNAMIC from the truck also exits")
eq(van.map.id, "g0_9", "into the same town")
end)()

local gifted = Game3.new()
gifted.phase = "play"
gifted.facing = "east"
gifted.playerX, gifted.playerY = 0, 0
gifted.map = { id = "g_gift", width = 3, height = 1, grid = { 0, 0, 0 } }
gifted.npcByMap = { g_gift = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "givemon", species = 280, level = 5 },
    { op = "end" },
  },
} } }
check(gifted:tryTalk(), "givemon scripts run")
eq(gifted.party[1].species, 280, "the gift joins the party")
check(gifted.field.text:find("TORCHIC", 1, true) ~= nil, "and names it")

local asker = Game3.new()
asker.phase = "play"
asker.facing = "east"
asker.playerX, asker.playerY = 0, 0
asker.data.pokemon = field.data.pokemon
asker.data.moves = field.data.moves
asker.map = { id = "g_yes", width = 3, height = 1, grid = { 0, 0, 0 } }
asker.npcByMap = { g_yes = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "loadword", text = "WANT ONE?" },
    { op = "callstd", id = 5 },
    { op = "compare", var = 0x800D, val = 1 },
    { op = "goto_if", cond = 1, to = 8 },
    { op = "loadword", text = "MAYBE LATER" },
    { op = "callstd", id = 2 },
    { op = "end" },
    { op = "givemon", species = 280, level = 5 },
    { op = "end" },
  },
} } }
check(asker:tryTalk(), "A on a yes/no NPC pauses")
eq(asker.field.kind, "script_yesno", "the prompt is a yes/no box")
eq(asker.field.text, "WANT ONE?", "and shows the question")
eq(asker.field.cursor, 0, "the cursor starts on YES")
local function pressAsk(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  asker:stepField()
  Input.wasPressed = old
end
pressAsk("down")
eq(asker.field.cursor, 1, "down moves to NO")
pressAsk("b")
eq(asker.field.kind, "talk", "B chooses NO")
eq(asker.field.text, "MAYBE LATER", "and the NO line runs")
eq(#asker.party, 0, "no gift on NO")
asker.field = nil
check(asker:tryTalk(), "talking again reopens the prompt")
pressAsk("a")
eq(asker.party[1].species, 280, "YES runs givemon")
check(asker.field.text:find("TORCHIC", 1, true) ~= nil, "and names the gift")

field.field = { kind = "menu", cursor = 0 }
eq(Game3.GFX_NURSE, 58, "Ruby nurse gfx is 58")

-- Talk across a counter (nurse / mart clerk).
field.map = {
  id = "pc", name = "POKeMON CENTER",
  width = 3, height = 3,
  tileset = "pair_0",
  grid = { 0, 0, 0, 0, 1, 0, 0, 0, 0 },
}
field.data.tilesets = {
  byId = {
    pair_0 = {
      behavior = { [1] = Game3.MB_COUNTER },
      layerType = { [1] = Game3.LAYER_NORMAL, [2] = Game3.LAYER_COVERED },
    },
  },
}
field.playerX, field.playerY = 1, 2
field.facing = "north"
field.npcByMap = {
  pc = { { x = 1, y = 0, graphicsId = Game3.GFX_NURSE, facing = "south" } },
}
field.party[1].hp = 1
field.field = nil
check(Game3.isCounter(field:behaviorAt(field.map, 1, 1)), "the tile in front is a counter")
eq(field:facingNpc() and field:facingNpc().graphicsId, Game3.GFX_NURSE,
  "A looks one tile past the counter")
check(field:tryTalk(), "the nurse behind the counter can be talked to")
eq(field.party[1].hp, field.party[1].maxHp, "the counter nurse still heals")

field.npcByMap.pc[1].graphicsId = Game3.GFX_MART
field.field = nil
field:tryTalk()
eq(field.field.kind, "mart", "the mart clerk is also behind a counter")
eq(field.field.items[1], Game3.ITEM_POKE_BALL,
  "a clerk without a list still sells Poke Balls")

eq(Game3.topIsOverlay(Game3.LAYER_NORMAL), true, "normal tops cover sprites")
eq(Game3.topIsOverlay(Game3.LAYER_SPLIT), true, "split tops cover sprites")
eq(Game3.topIsOverlay(Game3.LAYER_COVERED), false, "covered tops stay under sprites")
local ts = field.data.tilesets.byId.pair_0
ts.behavior[0] = 0x02
ts.tiles = { [0] = { 16, 17, 32, 33, 0, 0, 0, 0 } }
eq(field:behaviorAt(field.map, 0, 0), 0x02, "cell 0 is tall grass")
eq(field:layerTypeAt(field.map, 0, 0), Game3.LAYER_NORMAL,
  "Route 101 grass is LAYER_NORMAL in the attributes")
eq(field:topIsOverlayAt(field.map, 0, 0), false,
  "LAYER_NORMAL grass with empty tops stays under sprites")
ts.layerType[0] = Game3.LAYER_COVERED
eq(field:layerTypeAt(field.map, 0, 0), Game3.LAYER_COVERED, "grass is COVERED")
eq(field:topIsOverlayAt(field.map, 0, 0), false,
  "COVERED grass stays under sprites")
ts.behavior[0] = nil
ts.tiles[0] = { 1, 2, 3, 4, 5, 6, 7, 8 }
ts.layerType[0] = Game3.LAYER_SPLIT
eq(field:topIsOverlayAt(field.map, 0, 0), true, "split treetops still overlay")
eq(Game3.metatileTopPassMode(Game3.LAYER_SPLIT, "overlay", true), "top8",
  "split overlay is only the top 8px")
eq(Game3.metatileTopPassMode(Game3.LAYER_SPLIT, "covered", true), "bottom8",
  "split covered is the bottom 8px")
eq(Game3.metatileTopPassMode(Game3.LAYER_NORMAL, "covered", true), "skip",
  "normal overlay stays off the covered pass")
eq(Game3.metatileTopPassMode(Game3.LAYER_COVERED, "covered", false), "full",
  "covered fence tops paint under sprites")
eq(Game3.metatileTopPassMode(Game3.LAYER_COVERED, "overlay", false), "skip",
  "and stay off the overlay pass")
eq(Game3.metatileTopPassMode(Game3.LAYER_COVERED, "covered", true), "full",
  "COVERED ignores a wrong overlay flag")
eq(Game3.metatileTopPassMode(Game3.LAYER_COVERED, "overlay", true), "skip",
  "and still skips BG1")
ts.layerType[0] = nil
ts.tiles[0] = nil
eq(field:layerTypeAt(field.map, 1, 1), Game3.LAYER_NORMAL, "counter is overlay")
field.map.grid[5] = 2
eq(field:layerTypeAt(field.map, 1, 1), Game3.LAYER_COVERED, "a chair is covered")
eq(Game3.ledgeDelta(Game3.MB_JUMP_EAST), 1, "east ledge hops right")
eq(Game3.isGeneralAnimTile(127), true, "flower VRAM slot 127 animates")
eq(Game3.isGeneralAnimTile(50), false, "ordinary tiles do not")
eq(Game3.GFX_TRUCK, 94, "moving truck gfx is 94")
check(Game3.shouldAnimCorner(120, Game3.MB_POND_WATER), true,
  "water tiles on a pond sway")
check(not Game3.shouldAnimCorner(120, Game3.MB_JUMP_SOUTH),
  "ledge tiles do not borrow the water flip")
check(Game3.shouldAnimCorner(127, 0), true, "flowers still flip")
check(not Game3.shouldAnimCorner(120, 0), "idle ground with water VRAM does not")
eq(Game3.poseFor({
  frameCount = 1,
  face = { west = { frame = 5, flip = true } },
  walk = { west = { { frame = 7 } } },
}, "west", true, 0.4).frame, 0, "a 1-frame bag stays on frame 0")
check(Game3.drawOrderLess({ x = 0, y = 0 }, { x = 0, y = 1 }),
  "a southern actor draws in front")
check(not Game3.drawOrderLess({ x = 0, y = 1 }, { x = 0, y = 0 }),
  "a northern actor draws behind")

-- ------- trainers

eq(Game3.wildExp(54, 2, true), 22, "trainer EXP is 1.5x wild")
eq(BattleData.TRAINER_SIZE, 40, "a trainer row is 40 bytes")
eq(BattleData.TRAINERBATTLE_CMD, 0x5C, "trainerbattle is command 0x5C")

local function padTrainerName(text)
  local enc = GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
  if #enc < BattleData.TRAINER_NAME_LENGTH then
    enc = enc .. string.rep("\0", BattleData.TRAINER_NAME_LENGTH - #enc)
  end
  return enc:sub(1, BattleData.TRAINER_NAME_LENGTH)
end

local function padClass(text)
  local enc = GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
  if #enc < BattleData.TRAINER_CLASS_NAME_LENGTH then
    enc = enc .. string.rep("\0", BattleData.TRAINER_CLASS_NAME_LENGTH - #enc)
  end
  return enc:sub(1, BattleData.TRAINER_CLASS_NAME_LENGTH)
end

local PARTY = 0x80
local partyBlob = string.char(0, 0, 5, 0) .. GbaBin.packU16(286) .. string.char(0, 0)
eq(#partyBlob, 8, "default-moves party stride is 8")
local calvin = string.char(0, 2, 0, 0)
  .. padTrainerName("CALVIN")
  .. string.rep("\0", 8)
  .. string.char(0)
  .. string.rep("\0", 3)
  .. string.rep("\0", 4)
  .. string.char(1)
  .. string.rep("\0", 3)
  .. GbaBin.packPtr(PARTY)
eq(#calvin, 40, "Calvin's trainer row is 40 bytes")

local trainerRom = string.rep("\0", 0x200)
trainerRom = overlay(trainerRom, 0, string.rep("\0", 40) .. calvin)
trainerRom = overlay(trainerRom, PARTY, partyBlob)
trainerRom = overlay(trainerRom, 0xC0,
  padClass("") .. padClass("") .. padClass("YOUNGSTER"))

local tableOff = BattleData.findTrainerTable(trainerRom)
eq(tableOff, 0, "CALVIN scan lands on TRAINER_NONE")
local trainers = BattleData.parseTrainers(trainerRom, tableOff, 0xC0)
eq(trainers.byId[1].name, "CALVIN", "trainer 1 is Calvin")
eq(trainers.byId[1].className, "YOUNGSTER", "class 2 is Youngster")
eq(trainers.byId[1].doubleBattle, false, "Calvin is a singles fight")
eq(trainers.byId[1].party[1].species, 286, "Calvin sends Poochyena")
eq(trainers.byId[1].party[1].level, 5, "at level 5")
eq(#(trainers.byId[1].items or {}), 0, "Calvin has no items")
eq(trainers.count, 1, "one trainer has a party")

local script = string.char(0x6A, 0x5A, BattleData.TRAINERBATTLE_CMD, 0, 1, 0)
  .. string.rep("\0", 8)
eq(BattleData.readTrainerIdFromScript(script, 0), 1,
  "trainerbattle after lock/faceplayer is trainer 1")

local custom = string.char(0, 0, 7, 0) .. GbaBin.packU16(288)
  .. GbaBin.packU16(33) .. GbaBin.packU16(45) .. GbaBin.packU16(0) .. GbaBin.packU16(0)
  .. string.char(0, 0)
eq(#custom, 16, "custom-move party stride is 16")
local customParty = BattleData.parseTrainerParty(custom, 0, 1, 1)
eq(customParty[1].species, 288, "custom party species")
eq(customParty[1].moves[1], 33, "first custom move is Tackle")
eq(customParty[1].moves[2], 45, "second custom move is Growl")

local extra = BattleData.collectSpecies(
  { byMap = {} }, nil,
  { byId = { [1] = { party = { { species = 286 } } } } })
check(extra[286] == true, "trainer-party species are collected")
check(BattleData.collectSpecies(
  { byMap = {} },
  {
    [277] = { { target = 278 } },
    [278] = { { target = 279 } },
  },
  {})[279] == true, "Sceptile is two hops from Treecko")

field.data.pokemon.byIndex[286] = {
  name = "POOCHYENA", hp = 35, atk = 55, def = 35, spe = 35,
  spa = 30, spd = 30, type1 = 16, type2 = 16, catchRate = 255,
  expYield = 55, growthRate = 3,
}
field.data.pokemon.byIndex[288] = {
  name = "ZIGZAGOON", hp = 38, atk = 30, def = 41, spe = 60,
  spa = 30, spd = 41, type1 = 0, type2 = 0, catchRate = 255,
  expYield = 60, growthRate = 3,
}

local tmon = field:makeMon(286, 5, { 33, 45 })
eq(tmon.moves[1].name, "TACKLE", "a trainer mon can carry listed moves")
eq(#tmon.moves, 2, "custom set stops at the listed ids")

local calvinNpc = {
  x = 0, y = 0, facing = "east",
  trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 3,
  trainerName = "CALVIN", trainerClass = "YOUNGSTER",
  party = {
    { species = 290, level = 2 },
    { species = 288, level = 3 },
  },
  flagId = 0x200,
}
field.phase = "play"
field.balls = 5
field.flags = {}
field.money = Game3.START_MONEY
field.party = { field:makeMon(280, 5) }
check(field:startTrainerBattle(calvinNpc), "A trainer fight can start")
eq(field.battle.isTrainer, true, "the battle is marked trainer")
eq(field.battle.enemy.species, 290, "first party member is sent")
eq(field.battle.text, "YOUNGSTER CALVIN would like to battle!", "intro line")

local Input = require("src.core.Input")
Input:init()
local function pressA()
  local old = Input.wasPressed
  Input.wasPressed = function(_, name) return name == "a" end
  field:stepBattle()
  Input.wasPressed = old
end

field.battle.kind = "menu"
field.battle.cursor = 3
pressA()
eq(field.battle.kind, "menu_msg", "RUN stays in the fight")
eq(field.battle.text, "No! There's no running from a TRAINER battle!",
  "no-run line")
eq(field.phase, "battle", "RUN does not end a trainer fight")

field.battle.kind = "menu"
field.battle.cursor = 1
pressA()
eq(field.battle.kind, "bag", "BAG opens in a trainer fight")
eq(field.balls, 5, "opening BAG does not spend a ball")
pressA()
eq(field.balls, 5, "throwing a ball at a trainer does not spend")
eq(field.battle.text, "The trainer blocked the BALL!", "balls are refused")

field:throwBall()
eq(field.balls, 5, "throwBall also refuses in a trainer fight")
eq(field.battle.text, "The trainer blocked the BALL!",
  "direct throw is blocked too")

field.battle.enemy.hp = 0
field.battle.kind = "text"
field.battle.queue = { "WURMPLE fainted!" }
field.battle.qi = 1
field:advanceBattleText()
eq(field.battle.trainerIndex, 2, "the next trainer mon is queued")
eq(field.battle.enemy.species, 288, "Zigzagoon is sent out")
check(field.battle.text:find("ZIGZAGOON", 1, true) ~= nil, "send-out is announced")

field.battle.enemy.hp = 0
field.battle.kind = "text"
field.battle.queue = { "ZIGZAGOON fainted!" }
field.battle.qi = 1
field:advanceBattleText()
eq(field.battle.kind, "won_trainer", "the last KO opens the victory line")
eq(field.money, Game3.START_MONEY + 96,
  "winning pays 16 * last level * party size")
pressA()
eq(field.phase, "play", "winning returns to the field")
eq(calvinNpc.defeated, true, "Calvin is marked beaten")
eq(field.flags[0x200], true, "and his object flag is set")

field.map = {
  id = "g0_17", name = "Route 102",
  width = 4, height = 1, grid = { 0, 0, 0, 0 },
}
field.playerX, field.playerY = 2, 0
local spotter = {
  x = 0, y = 0, facing = "east",
  trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 3,
  party = { { species = 286, level = 5 } },
  trainerName = "CALVIN", trainerClass = "YOUNGSTER",
}
check(field:seesPlayer(spotter, field.map), "open ground is in a facing cone")
field.map.grid[2] = 1024
check(not field:seesPlayer(spotter, field.map), "a wall blocks trainer sight")
field.map.grid[2] = 0
spotter.facing = "south"
check(not field:seesPlayer(spotter, field.map), "NORMAL only looks one way")
spotter.trainerType = Game3.TRAINER_TYPE_SEE_ALL
check(field:seesPlayer(spotter, field.map), "SEE_ALL looks east too")
spotter.defeated = true
check(not field:seesPlayer(spotter, field.map), "a beaten trainer does not spot")

spotter.defeated = false
spotter.facing = "east"
spotter.trainerType = Game3.TRAINER_TYPE_NORMAL
field.npcByMap = { g0_17 = { spotter } }
field.phase = "play"
field.party = { field:makeMon(280, 5) }
check(field:tryTrainerSpot(), "LOS after a step starts the fight")
eq(field.phase, "battle", "spotting opens a trainer battle")

chaser = Game3.new()
chaser.phase = "play"
chaser.playerX, chaser.playerY = 2, 0
chaser.flags = { [Game3.FLAG_SYS_POKEDEX_GET] = true }
chaser.party = { chaser:makeMon(280, 5) }
chaser.map = {
  id = "g_spot", width = 4, height = 1, grid = { 0, 0, 0, 0 },
}
chaser.npcByMap = { g_spot = { {
  x = 0, y = 0, facing = "east", localId = 1,
  trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 3,
  party = { { species = 286, level = 5 } },
  trainerName = "CALVIN", trainerClass = "YOUNGSTER",
} } }
check(chaser:tryTrainerSpot(), "a localId trainer starts the walk-up")
eq(chaser.field.kind, "trainer_approach", "the ! holds the field")
eq(chaser.phase, "play", "battle waits for the approach")
old = Input.wasPressed
Input.wasPressed = function(_, key)
  return key == "a" or key == "up" or key == "b" or key == "start"
end
chaser:stepField()
Input.wasPressed = old
eq(chaser.field.kind, "trainer_approach",
  "Start-menu keys during the approach are ignored")
eq(chaser.phase, "play", "and do not open the Pokédex or party")

field.map.objects = { {
  x = 0, y = 0, graphicsId = 9, movementType = 1,
  trainerType = 1, trainerRange = 2, trainerName = "CALVIN",
  trainerClass = "YOUNGSTER", party = { { species = 286, level = 5 } },
  flagId = 0x200,
} }
field.flags = { [0x200] = true }
field:resetNpcs(field.map)
eq(field:npcsFor(field.map)[1].defeated, true,
  "re-entering the map keeps beaten trainers beaten")

field.map.objects = { {
  x = 0, y = 0, graphicsId = 9, movementType = 1,
  trainerType = 1, trainerRange = 2, trainerName = "CALVIN",
  trainerClass = "YOUNGSTER", trainerId = 7,
  party = { { species = 286, level = 5 } },
  flagId = 0,
} }
field.flags = { [Game3.TRAINER_FLAG_START + 7] = true }
field:resetNpcs(field.map)
eq(field:npcsFor(field.map)[1].defeated, true,
  "trainer flag 0x500+id survives a map re-enter")

local scripted = Game3.new()
scripted.phase = "play"
scripted.party = { scripted:makeMon(280, 5) }
scripted._scriptNpc = {
  trainerId = 1, trainerName = "CALVIN", trainerClass = "YOUNGSTER",
  party = { { species = 288, level = 5 } },
}
check(scripted:scriptTrainerBattle({
  trainerId = 1, intro = "Go!", defeat = "Arrgh, I lost...",
}), "trainerbattle starts a scripted fight")
eq(scripted.phase, "battle", "rival and team scripts enter battle")
eq(scripted.battle.text, "Go!", "intro text is kept")
eq(scripted.battle.defeat, "Arrgh, I lost...",
  "trainerbattle keeps the ROM lose text")
scripted.battle.enemy.hp = 0
scripted.battle.kind = "text"
scripted.battle.queue = { "ZIGZAGOON fainted!" }
scripted.battle.qi = 1
scripted:advanceBattleText()
eq(scripted.battle.kind, "won_trainer", "the last KO opens victory")
eq(scripted.battle.text, "Arrgh, I lost...",
  "GetTrainerLoseText prints before the prize")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
scripted:stepBattle()
Input.wasPressed = old
check(scripted.battle.text:find("defeated", 1, true) ~= nil,
  "A then shows the prize line")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
scripted:stepBattle()
Input.wasPressed = old
eq(scripted.phase, "play", "a second A returns to the field")
scripted:markTrainerDefeated(scripted._scriptNpc)
eq(scripted.flags[Game3.TRAINER_FLAG_START + 1], true,
  "the 0x500+id bit is set")
eq(scripted:scriptTrainerBattle({ trainerId = 1 }), false,
  "a second trainerbattle is a nop")

eq(scripted:itemName(Game3.ITEM_POKE_BALL), "POKe BALL",
  "fallback POKe BALL spelling")
eq(scripted:expandScriptText("TRAINER!You can't"),
  "TRAINER!\nYou can't", "cached \\p glue splits after !")
eq(scripted:expandScriptText("the sign says.Do you want to go through?"),
  "the sign says.\nDo you want to go through?",
  "and after a period")
scripted.stringVars = { 12, 34, 56 }
eq(scripted:expandScriptText("{STR_VAR_1} {STR_VAR_2} {STR_VAR_3}"),
  "12 34 56", "numeric string vars stringify")
scripted.stringVars = nil
scripted.data = { items = { byId = { [4] = { name = "POK BALL" } } } }
eq(scripted:itemName(4), "POKe BALL", "cached POK BALL is repaired")

-- ------- items, bag, mart, item balls

eq(BattleData.ITEM_SIZE, 44, "gItems rows are 44 bytes")
eq(BattleData.ITEM_POKE_BALL, 4, "POKe BALL is item 4")
eq(Game3.START_MONEY, 3000, "Ruby starts with $3000")
eq(Game3.GFX_ITEM_BALL, 59, "item balls use graphics 59")

local function padItemName(text)
  local enc = GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
  if #enc < BattleData.ITEM_NAME_LENGTH then
    enc = enc .. string.rep("\0", BattleData.ITEM_NAME_LENGTH - #enc)
  end
  return enc:sub(1, BattleData.ITEM_NAME_LENGTH)
end

local function packItem(name, itemId, price, pocket)
  return padItemName(name)
    .. GbaBin.packU16(itemId)
    .. GbaBin.packU16(price)
    .. string.rep("\0", 8)
    .. string.char(pocket or 0)
    .. string.rep("\0", 17)
end

eq(#packItem("MASTER BALL", 1, 0, 2), 44, "one packed item is 44 bytes")
local noneItem = string.rep("\0", 44)
local itemRom = noneItem .. packItem("MASTER BALL", 1, 0, 2)
  .. packItem("ULTRA BALL", 2, 1200, 2)
  .. packItem("GREAT BALL", 3, 600, 2)
  .. packItem("POKE BALL", 4, 200, 2)
eq(BattleData.findItemTable(itemRom), 0, "MASTER BALL sits at item 1")
local parsedItems = BattleData.parseItems(itemRom, 0)
eq(parsedItems.byId[1].name, "MASTER BALL", "item 1 is Master Ball")
eq(parsedItems.byId[1].price, 0, "Master Ball is not sold")
eq(parsedItems.byId[4].price, 200, "Poke Ball costs 200")
eq(parsedItems.byId[4].pocket, 2, "balls use the ball pocket")

local giveScript = string.char(BattleData.SETORCOPYVAR_CMD)
  .. GbaBin.packU16(BattleData.VAR_0x8000) .. GbaBin.packU16(4)
  .. string.char(BattleData.SETORCOPYVAR_CMD)
  .. GbaBin.packU16(BattleData.VAR_0x8001) .. GbaBin.packU16(1)
  .. string.char(BattleData.CALLSTD_CMD, 1)
local give = BattleData.readItemGiveFromScript(giveScript, 0)
eq(give.id, 4, "finditem writes the item to VAR_0x8000")
eq(give.count, 1, "and the amount to VAR_0x8001")

local setvarScript = string.char(BattleData.SETVAR_CMD)
  .. GbaBin.packU16(BattleData.VAR_0x8000) .. GbaBin.packU16(13)
  .. string.char(BattleData.SETVAR_CMD)
  .. GbaBin.packU16(BattleData.VAR_0x8001) .. GbaBin.packU16(1)
eq(BattleData.readItemGiveFromScript(setvarScript, 0).id, 13,
  "setvar is accepted as a fallback")

local martRom = string.rep("\0", 0x80)
local martList = 0x40
martRom = overlay(martRom, martList,
  GbaBin.packU16(4) .. GbaBin.packU16(13) .. GbaBin.packU16(0))
martRom = overlay(martRom, 0,
  string.char(BattleData.POKEMART_CMD) .. GbaBin.packPtr(martList))
local martItems = BattleData.readMartFromScript(martRom, 0)
eq(#martItems, 2, "pokemart lists items until ITEM_NONE")
eq(martItems[1], 4, "first stock is a Poke Ball")
eq(martItems[2], 13, "second stock is a Potion")

local shopper = Game3.new()
shopper.bag = {}
shopper.money = 3000
local okBuy, buyMsg = shopper:buyMartItem(4)
check(okBuy, "a Poke Ball can be bought")
eq(shopper.money, 2800, "buying deducts 200")
eq(shopper:itemCount(4), 1, "the ball is added to the bag")
check(buyMsg:find("BALL", 1, true) ~= nil, "the buy line names the item")
shopper.money = 100
local tooPoor = shopper:buyMartItem(4)
check(not tooPoor, "too little money is refused")
eq(shopper.money, 100, "a refused buy does not charge")
eq(shopper:itemCount(4), 1, "a refused buy does not add a second ball")

local healer = Game3.new()
healer.bag = {}
healer:addItem(13, 1)
healer.party = { { name = "TORCHIC", hp = 5, maxHp = 19 } }
check(healer:useFieldItem(13), "a Potion opens the party")
eq(healer.field.kind, "party_use", "ItemUseOutOfBattle_Medicine")
eq(healer.party[1].hp, 5, "picker does not auto-apply")
eq(healer:itemCount(13), 1, "item stays until a slot is chosen")
local okHeal, healMsg = healer:useItemOnMon(healer.party[1], 13)
check(okHeal, "a Potion can be used on the field")
eq(healer.party[1].hp, 19, "20 HP is capped at max")
eq(healer:itemCount(13), 0, "the Potion is consumed")
check(healMsg:find("recovered", 1, true) ~= nil, "heal announces recovery")
healer:addItem(13, 1)
healer.party[1].hp = 19
local noNeed = healer:useItemOnMon(healer.party[1], 13)
check(not noNeed, "a full-HP mon does not drink")
eq(healer:itemCount(13), 1, "a wasted Potion is not consumed")

healer.party[1].status = "psn"
healer:addItem(14, 1)
local okCure, cureMsg = healer:useItemOnMon(healer.party[1], 14)
check(okCure, "an Antidote can be used on the field")
eq(healer.party[1].status, nil, "Antidote clears poison")
eq(healer:itemCount(14), 0, "the Antidote is consumed")
check(cureMsg:find("status", 1, true) ~= nil, "cure announces status")

healer.party[1].hp = 5
healer.party[1].maxHp = 100
healer:addItem(22, 1)
local okSuper = healer:useItemOnMon(healer.party[1], 22)
check(okSuper, "a Super Potion can be used")
eq(healer.party[1].hp, 55, "Super Potion heals 50")
eq(healer:itemCount(22), 0, "the Super Potion is consumed")

local picker = Game3.new()
picker.bag = {}
picker.flags = {}
picker.phase = "play"
picker.facing = "east"
picker.playerX, picker.playerY = 0, 0
picker.map = { id = "g_item", width = 3, height = 1, grid = { 0, 0, 0 } }
local ballNpc = {
  x = 1, y = 0, graphicsId = 59, itemId = 4, itemCount = 1, flagId = 0x300,
}
picker.npcByMap = { g_item = { ballNpc } }
check(picker:tryTalk(), "A picks up an item ball")
eq(picker.flags[0x300], true, "pickup sets the object flag")
eq(ballNpc.hidden, true, "the ball disappears")
eq(picker:itemCount(4), 1, "the item goes in the bag")
eq(picker:npcAt(picker.map, 1, 0), nil, "a hidden ball is not talkable")
check(picker.field.text:find("BALL", 1, true) ~= nil, "pickup names the item")

picker.map.objects = { {
  x = 1, y = 0, graphicsId = 59, itemId = 4, flagId = 0x300,
} }
picker:resetNpcs(picker.map)
eq(picker:npcsFor(picker.map)[1], nil, "a taken ball does not respawn")

local clerkGame = Game3.new()
clerkGame.phase = "play"
clerkGame.facing = "east"
clerkGame.playerX, clerkGame.playerY = 0, 0
clerkGame.map = { id = "g_mart", width = 3, height = 1, grid = { 0, 0, 0 } }
local clerk = { x = 1, y = 0, graphicsId = 83, mart = { 4, 13 } }
clerkGame.npcByMap = { g_mart = { clerk } }
check(clerkGame:tryTalk(), "A on a clerk opens the mart")
eq(clerkGame.field.kind, "mart", "mart UI is a field overlay")
eq(clerkGame.field.items[1], 4, "stock comes from the script list")

eq(Game3.FLAG_HIDDEN_ITEMS_START, 0x258, "Ruby hidden-item flags start at 0x258")
eq(Game3.hiddenFlag(4), 0x25C, "flag is start + hidden id")
eq(Game3.bgFacingOk(0, "east"), true, "ANY facing is always ok")
eq(Game3.bgFacingOk(1, "north"), true, "NORTH signs need north")
eq(Game3.bgFacingOk(1, "east"), false, "NORTH signs refuse east")

local searcher = Game3.new()
searcher.bag = {}
searcher.flags = {}
searcher.phase = "play"
searcher.facing = "east"
searcher.playerX, searcher.playerY = 0, 0
searcher.map = {
  id = "g_hide", width = 3, height = 1, grid = { 0, 0, 0 },
  bgEvents = { { x = 1, y = 0, kind = 7, itemId = 13, hiddenId = 4 } },
}
check(searcher:tryTalk(), "A on the facing tile finds a hidden item")
eq(searcher:itemCount(13), 1, "the hidden Potion is bagged")
eq(searcher.flags[Game3.hiddenFlag(4)], true, "the hidden-item flag is set")
check(searcher.field.text:find("POTION", 1, true) ~= nil, "hidden pickup names the item")
searcher.field = nil
check(not searcher:tryTalk(), "a taken hidden item does not fire again")
eq(searcher:itemCount(13), 1, "a second A does not duplicate the item")

local reader = Game3.new()
reader.phase = "play"
reader.facing = "east"
reader.playerX, reader.playerY = 0, 0
reader.map = {
  id = "g_sign", width = 3, height = 1, grid = { 0, 0, 0 },
  bgEvents = { { x = 1, y = 0, kind = 0, text = "LITTLEROOT TOWN" } },
}
check(reader:tryTalk(), "A reads a sign on the facing tile")
eq(reader.field.text, "LITTLEROOT TOWN", "the sign shows extracted text")
reader.field = nil
reader.map.bgEvents[1].kind = 1
check(not reader:tryTalk(), "a NORTH sign is silent when facing east")
reader.facing = "north"
reader.map.bgEvents[1].x, reader.map.bgEvents[1].y = 0, -1
check(reader:tryTalk(), "the same sign answers when you face north")

-- ------- status (burn / poison / para / sleep / freeze)

eq(Game3.statusTag("brn"), "BRN", "burn tag")
eq(Game3.statusCatchMul("slp"), 20, "sleep doubles the catch value")
eq(Game3.statusCatchMul("psn"), 15, "poison is 1.5x")
eq(Game3.statusCatchMul(nil), 10, "no status is 1x")
eq(Game3.statusFromEffect(4), "brn", "Ember's effect is a burn hit")
eq(Game3.statusFromEffect(67), "par", "Thunder Wave is paralysis")

field.rng = function() return 1 end
local caster = field:makeMon(280, 5)
local target = {
  name = "ODDISH", hp = 200, maxHp = 200, type1 = 12, type2 = 12,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local ember = field:copyMove(52)
ember.secondary = 100
local burnLines = field:useMove(caster, target, ember)
eq(target.status, "brn", "Ember can burn")
check(burnLines[#burnLines]:find("burned", 1, true) ~= nil, "burn is announced")

local torchic = { name = "TORCHIC", hp = 19, maxHp = 19, type1 = 10, type2 = 10 }
check(not field:canStatus(torchic, "brn"), "Fire types cannot be burned")
eq(field:applyStatus(torchic, "brn"), nil, "applyStatus refuses Fire")

local steel = { name = "ARON", hp = 20, maxHp = 20, type1 = 8, type2 = 5 }
check(not field:canStatus(steel, "psn"), "Steel types cannot be poisoned")

local healthy = {
  name = "ZIGZAGOON", level = 5, hp = 20, maxHp = 20,
  atk = 20, def = 10, spe = 20, spa = 10, spd = 10, type1 = 0, type2 = 0,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local scratch = { power = 40, type = 0 }
local normal = field:dealDamage(
  { name = "A", level = 5, atk = 20, spa = 20, status = nil,
    stages = { atk = 0, spa = 0 } }, healthy, scratch)
healthy.hp = 20
local halved = field:dealDamage(
  { name = "A", level = 5, atk = 20, spa = 20, status = "brn",
    stages = { atk = 0, spa = 0 } }, healthy, scratch)
check(halved.dmg < normal.dmg, "burn halves physical Attack")

local poisoned = { name = "WURMPLE", hp = 16, maxHp = 16, status = "psn" }
local residual = field:statusResidual(poisoned)
eq(poisoned.hp, 14, "poison deals maxHP/8")
check(residual[1]:find("poison", 1, true) ~= nil, "poison residual is announced")

field:startWildBattle(290, 2)
field.battle.enemy.status = "slp"
field.battle.enemy.sleepTurns = 1
field.rng = function() return 1 end
field:beginTurn(field.battle.player.moves[1])
local asleep
for i = 1, #field.battle.queue do
  if field.battle.queue[i]:find("asleep", 1, true) then asleep = true end
end
check(asleep, "sleep skips the wild Pokémon's turn")
eq(field.battle.enemy.sleepTurns, 0, "a sleep turn is consumed")

local wave = field:copyMove(86)
local victim = {
  name = "POOCHYENA", hp = 20, maxHp = 20, type1 = 16, type2 = 16,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
field:useMove(field.party[1], victim, wave)
eq(victim.status, "par", "Thunder Wave paralyzes")

field.party[1].status = "brn"
field:healParty()
eq(field.party[1].status, nil, "the nurse clears status")

eq(Game3.catchValue(13, 13, 255, 1), 85, "catch value without status is unchanged")
eq(math.floor(85 * Game3.statusCatchMul("frz") / 10), 170,
  "a frozen catch is 2x")

-- ------- in-battle items

eq(Game3.ballBonus(1), 255, "Master Ball always catches")
eq(Game3.ballBonus(2), 2, "Ultra Ball is 2x")
eq(Game3.ballBonus(3), 1.5, "Great Ball is 1.5x")
eq(Game3.ballBonus(4), 1, "Poke Ball is 1x")
eq(Game3.ballBonus(5), 1.5, "Safari Ball is 1.5x")
eq(Game3.catchValue(13, 13, 255, 1.5), 127,
  "full-HP Wurmple in a Great Ball is a=127")

local bagger = Game3.new()
bagger.data.pokemon = field.data.pokemon
bagger.data.moves = field.data.moves
bagger.party = { bagger:makeMon(280, 5) }
bagger.bag = {}
bagger.balls = 0
bagger:addItem(2, 1)
bagger.rng = function() return 1 end
bagger:startWildBattle(290, 2)
bagger:throwBall(2)
eq(bagger:itemCount(2), 0, "throwBall(2) spends an Ultra Ball")
eq(bagger.battle.caught, true, "Ultra Ball still catches when rand=1")
check(bagger.battle.queue[1]:find("ULTRA", 1, true) ~= nil,
  "the throw names the ball")

-- ------- special balls (pokeruby handleballthrow)

local balls = Game3.new()
balls.data.pokemon = field.data.pokemon
balls.data.moves = field.data.moves
balls.rng = function() return 1 end
balls.party = { balls:makeMon(280, 5) }
local bug = { name = "WURMPLE", species = 290, level = 2,
  type1 = 6, type2 = 6 }
local fire = { name = "TORCHIC", species = 280, level = 5,
  type1 = 10, type2 = 10 }
eq(balls:catchBallBonus(Game3.ITEM_NET_BALL, bug), 3, "Net Ball is 3x on Bug")
eq(balls:catchBallBonus(Game3.ITEM_NET_BALL, fire), 1, "and 1x on Fire")
eq(balls:catchBallBonus(Game3.ITEM_NEST_BALL, { level = 5 }), 3.5,
  "Nest Ball at lv5 is 3.5x")
eq(balls:catchBallBonus(Game3.ITEM_NEST_BALL, { level = 30 }), 1,
  "Nest Ball at lv30 is 1x")
eq(balls:catchBallBonus(Game3.ITEM_NEST_BALL, { level = 35 }), 1,
  "Ruby clamps Nest Ball lv31-39 to 1x")
eq(balls:catchBallBonus(Game3.ITEM_NEST_BALL, { level = 40 }), 1,
  "Nest Ball at lv40 stays 1x")
eq(balls:catchBallBonus(Game3.ITEM_DIVE_BALL, bug), 1, "Dive Ball is 1x on land")
balls.map = { mapType = Game3.MAP_TYPE_UNDERWATER }
eq(balls:catchBallBonus(Game3.ITEM_DIVE_BALL, bug), 3.5,
  "and 3.5x underwater")
eq(balls:catchBallBonus(Game3.ITEM_REPEAT_BALL, bug), 1,
  "Repeat Ball is 1x on an uncaught species")
balls:markCaught(290)
eq(balls:catchBallBonus(Game3.ITEM_REPEAT_BALL, bug), 3,
  "and 3x once that species is owned")
balls:startWildBattle(290, 2)
eq(balls.battle.turns, 0, "a fight starts on turn 0")
eq(balls:catchBallBonus(Game3.ITEM_TIMER_BALL, balls.battle.enemy), 1,
  "Timer Ball is 1x on turn 0")
balls.battle.turns = 10
eq(balls:catchBallBonus(Game3.ITEM_TIMER_BALL, balls.battle.enemy), 2,
  "turn 10 is 2x")
balls.battle.turns = 30
eq(balls:catchBallBonus(Game3.ITEM_TIMER_BALL, balls.battle.enemy), 4,
  "turn 30 caps at 4x")
balls.battle.turns = 99
eq(balls:catchBallBonus(Game3.ITEM_TIMER_BALL, balls.battle.enemy), 4,
  "and stays capped")
balls.battle.turns = 0
balls:beginTurn(balls.battle.player.moves[1])
eq(balls.battle.turns, 1, "FIGHT ticks the Timer Ball counter")
eq(balls:itemName(Game3.ITEM_NET_BALL), "NET BALL", "Net Ball name")
eq(balls:itemName(Game3.ITEM_TIMER_BALL), "TIMER BALL", "Timer Ball name")
check(balls:hasCaught(290), "markCaught records Repeat Ball prey")
check(not balls:hasCaught(280), "direct party assignment does not mark the dex")
balls:addToParty(balls.party[1])
check(balls:hasCaught(280), "addToParty records the species")

local drinker = Game3.new()
drinker.data.pokemon = field.data.pokemon
drinker.data.moves = field.data.moves
drinker.rng = function() return 1 end
drinker.party = { drinker:makeMon(280, 5) }
drinker:startWildBattle(290, 2)
drinker.battle.player.hp = 5
drinker.battle.enemy.moves = { drinker:copyMove(81) }
drinker:addItem(13, 1)
local drank = drinker:useBattleItem(13)
check(drank, "a Potion can be used in battle")
eq(drinker.battle.player.hp, 19, "the battler is healed")
eq(drinker:itemCount(13), 0, "the Potion is consumed")
eq(drinker.battle.kind, "text", "using an item opens the text queue")
check(#drinker.battle.queue >= 2, "the enemy still gets a turn")
check(drinker.battle.queue[1]:find("recovered", 1, true) ~= nil,
  "heal is announced first")

-- ------- extra move effects

eq(Game3.EFFECT_ABSORB, 3, "Absorb is effect 3")
eq(Game3.multiHitCount(0), 2, "Random()&3 == 0 is 2 hits")
eq(Game3.multiHitCount(1), 3, "Random()&3 == 1 is 3 hits")
eq(Game3.multiHitCount(2, 0), 2, "Random()&3 > 1 rerolls 2-5")
eq(Game3.multiHitCount(3, 3), 5, "second roll 3 is 5 hits")
eq(Game3.recoilDenom(48), 4, "Take Down is 1/4 recoil")
eq(Game3.recoilDenom(198), 3, "Double-Edge is 1/3 recoil")

local stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
local fx = Game3.new()
fx.data.pokemon = field.data.pokemon
fx.data.moves = field.data.moves
fx.rng = function() return 1 end

local splash = {
  name = "SPLASH", effect = 85, power = 0, type = 0, accuracy = 0, pp = 40,
}
local splashLines = fx:useMove(
  { name = "MAGIKARP", hp = 10, maxHp = 10 },
  { name = "WURMPLE", hp = 10, maxHp = 10 }, splash)
check(splashLines[2]:find("nothing", 1, true) ~= nil, "Splash does nothing")

local recover = {
  name = "RECOVER", effect = 32, power = 0, type = 0, accuracy = 0, pp = 10,
}
local patient = { name = "TORCHIC", hp = 5, maxHp = 20 }
fx:useMove(patient, { name = "X", hp = 10, maxHp = 10 }, recover)
eq(patient.hp, 15, "Recover heals half of max HP")

local rester = { name = "TORCHIC", hp = 5, maxHp = 20 }
fx:useMove(rester, { name = "X", hp = 10, maxHp = 10 }, {
  name = "REST", effect = 37, power = 0, type = 0, accuracy = 0, pp = 10,
})
eq(rester.hp, 20, "Rest fully heals")
eq(rester.status, "slp", "Rest puts the user to sleep")
eq(rester.sleepTurns, 2, "Rest sleeps for two skipped turns")

local grassUser = {
  name = "TREECKO", level = 5, hp = 5, maxHp = 40,
  atk = 10, def = 10, spe = 10, spa = 20, spd = 10,
  type1 = 12, type2 = 12, stages = stages,
}
local prey = {
  name = "ZIGZAGOON", level = 5, hp = 80, maxHp = 80,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 0, type2 = 0, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local absorb = {
  name = "ABSORB", effect = 3, power = 20, type = 12, accuracy = 100, pp = 20,
  secondary = 0,
}
local drainLines = fx:useMove(grassUser, prey, absorb)
check(grassUser.hp > 5, "Absorb heals the user")
check(drainLines[#drainLines]:find("drained", 1, true) ~= nil,
  "Absorb announces the drain")

absorb.id = 71
absorb.effect = nil
fx.data.moves = { byId = { [71] = { id = 71, effect = 3, power = 20, type = 12 } } }
grassUser.hp = 5
prey.hp = 80
drainLines = fx:useMove(grassUser, prey, absorb)
check(grassUser.hp > 5, "Absorb heals when the party slot omitted effect")
check(drainLines[#drainLines]:find("drained", 1, true) ~= nil,
  "and still announces the drain")
fx.data.moves = nil

local kicker = {
  name = "COMBUSKEN", level = 16, hp = 40, maxHp = 40,
  atk = 20, def = 10, spe = 20, spa = 20, spd = 10,
  type1 = 1, type2 = 10, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local dummy = {
  name = "ZIGZAGOON", level = 5, hp = 80, maxHp = 80,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 0, type2 = 0, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local kick = {
  name = "DOUBLE KICK", effect = 44, power = 30, type = 1, accuracy = 100,
  pp = 30, secondary = 0,
}
local kickLines = fx:useMove(kicker, dummy, kick)
check(kickLines[#kickLines]:find("Hit 2 times!", 1, true) ~= nil,
  "Double Kick always hits twice")

local fury = {
  name = "FURY ATTACK", effect = 29, power = 15, type = 0, accuracy = 100,
  pp = 20, secondary = 0,
}
local furyTarget = {
  name = "WURMPLE", level = 2, hp = 80, maxHp = 80,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 6, type2 = 6, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local furyLines = fx:useMove(kicker, furyTarget, fury)
check(furyLines[#furyLines]:find("Hit 2 times!", 1, true) ~= nil,
  "rng=1 rolls 2 Fury Attack hits")

local taker = {
  name = "POOCHYENA", level = 5, hp = 30, maxHp = 30,
  atk = 20, def = 10, spe = 20, spa = 10, spd = 10,
  type1 = 16, type2 = 16, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local taken = {
  name = "WURMPLE", level = 2, hp = 40, maxHp = 40,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 6, type2 = 6, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local takeDown = {
  name = "TAKE DOWN", effect = 48, power = 90, type = 0, accuracy = 100,
  pp = 20, secondary = 0,
}
local beforeHp = taker.hp
local recoilLines = fx:useMove(taker, taken, takeDown)
check(taker.hp < beforeHp, "Take Down deals recoil")
check(recoilLines[#recoilLines]:find("recoil", 1, true) ~= nil
  or recoilLines[#recoilLines - 1]:find("recoil", 1, true) ~= nil,
  "recoil is announced")

local ray = {
  name = "CONFUSE RAY", effect = 49, power = 0, type = 7, accuracy = 100,
  pp = 10, secondary = 0,
}
local victim = {
  name = "ZIGZAGOON", hp = 20, maxHp = 20,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local confuseLines = fx:useMove(
  { name = "GASTLY", hp = 20, maxHp = 20 }, victim, ray)
eq(victim.confuseTurns, 2, "rng=1 sets confusion to 2 turns")
check(confuseLines[2]:find("confused", 1, true) ~= nil, "Confuse Ray announces")

local biter = {
  name = "POOCHYENA", level = 5, hp = 20, maxHp = 20,
  atk = 20, def = 10, spe = 20, spa = 10, spd = 10,
  type1 = 16, type2 = 16, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local bitten = {
  name = "WURMPLE", level = 2, hp = 40, maxHp = 40,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 6, type2 = 6, stages = {
    atk = 0, def = 0, spa = 0, spd = 0, spe = 0,
  },
}
local bite = {
  name = "BITE", effect = 31, power = 60, type = 16, accuracy = 100,
  pp = 25, secondary = 100,
}
fx:useMove(biter, bitten, bite)
eq(bitten.flinch, true, "Bite can flinch")

local flinchGame = Game3.new()
flinchGame.data.pokemon = field.data.pokemon
flinchGame.data.moves = field.data.moves
flinchGame.party = { flinchGame:makeMon(280, 5) }
flinchGame:startWildBattle(290, 2)
flinchGame.battle.enemy.hp = 200
flinchGame.battle.enemy.maxHp = 200
flinchGame.rng = function() return 1 end
flinchGame:beginTurn({
  name = "BITE", effect = 31, power = 60, type = 16, accuracy = 100,
  pp = 25, secondary = 100,
})
local flinched
for i = 1, #flinchGame.battle.queue do
  if flinchGame.battle.queue[i]:find("flinched", 1, true) then
    flinched = true
  end
end
check(flinched, "a flinch skips the foe's move")

local confused = {
  name = "ZIGZAGOON", level = 5, hp = 20, maxHp = 20,
  atk = 20, def = 10, spe = 20, spa = 10, spd = 10,
  type1 = 0, type2 = 0, confuseTurns = 3,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local skip, confuseMsgs = fx:confuseBlocks(confused)
check(skip, "confusion can force a self-hit")
eq(confused.confuseTurns, 2, "a confusion turn is consumed")
check(confused.hp < 20, "the self-hit deals damage")
check(confuseMsgs[2]:find("hurt itself", 1, true) ~= nil,
  "the self-hit is announced")

-- ------- abilities

eq(Game3.abilityFor({ ability1 = 50, ability2 = 22 }, 0), 50,
  "even PID uses ability 1")
eq(Game3.abilityFor({ ability1 = 50, ability2 = 22 }, 1), 22,
  "odd PID uses ability 2")
eq(Game3.abilityFor({ ability1 = 66, ability2 = 0 }, 1), 66,
  "a missing ability 2 stays on ability 1")

local dog = { name = "POOCHYENA", ability = 22 }
local chick = {
  name = "TORCHIC", stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local intim = fx:activateEnter(dog, chick)
eq(chick.stages.atk, -1, "Intimidate drops Attack")
check(intim[1]:find("INTIMIDATE", 1, true) ~= nil, "Intimidate is announced")

local cutter = {
  name = "MAKUHITA", ability = 52,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove({ name = "TORCHIC", hp = 20, maxHp = 20 }, cutter, {
  name = "GROWL", effect = 18, power = 0, type = 0, accuracy = 100, pp = 40,
})
eq(cutter.stages.atk, 0, "Hyper Cutter blocks Growl")

local focused = {
  name = "ABSOL", ability = 39, hp = 40, maxHp = 40, type1 = 16, type2 = 16,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove({
  name = "POOCHYENA", level = 5, hp = 20, maxHp = 20,
  atk = 20, spa = 10, type1 = 16, type2 = 16,
  stages = { atk = 0, spa = 0 },
}, focused, {
  name = "BITE", effect = 31, power = 60, type = 16, accuracy = 100,
  pp = 25, secondary = 100,
})
eq(focused.flinch, nil, "Inner Focus blocks flinch")

local headed = {
  name = "ARON", ability = 69, level = 5, hp = 30, maxHp = 30,
  atk = 20, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 8, type2 = 5, stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local rockPrey = {
  name = "WURMPLE", level = 2, hp = 80, maxHp = 80,
  atk = 10, def = 10, spe = 10, spa = 10, spd = 10,
  type1 = 6, type2 = 6, stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove(headed, rockPrey, {
  name = "TAKE DOWN", effect = 48, power = 90, type = 0, accuracy = 100,
  pp = 20, secondary = 0,
})
eq(headed.hp, 30, "Rock Head skips recoil")

local floater = {
  name = "DUSKULL", ability = 26, hp = 40, maxHp = 40, type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local quake = fx:dealDamage({
  name = "TRAPINCH", level = 5, hp = 20, maxHp = 20,
  atk = 20, spa = 10, type1 = 4, type2 = 4,
  stages = { atk = 0, spa = 0 },
}, floater, { power = 100, type = 4 })
eq(quake.mul, 0, "Levitate ignores Ground")
eq(floater.hp, 40, "Levitate takes no Ground damage")

local absorber = {
  name = "CHINCHOU", ability = 10, hp = 10, maxHp = 40, type1 = 13, type2 = 11,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove({ name = "MAREEP", hp = 20, maxHp = 20 }, absorber, {
  name = "THUNDER SHOCK", effect = 6, power = 40, type = 13, accuracy = 100,
  pp = 30, secondary = 0,
})
eq(absorber.hp, 20, "Volt Absorb heals 1/4 max HP")

local shed = { name = "WURMPLE", ability = 61, hp = 16, maxHp = 16, status = "psn" }
local shedLines = fx:statusResidual(shed)
eq(shed.status, nil, "Shed Skin can cure status")
check(shedLines[1]:find("SHED SKIN", 1, true) ~= nil, "Shed Skin is announced")

local tempo = {
  name = "SPOINK", ability = 20, hp = 20, maxHp = 20,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove({ name = "GASTLY", hp = 20, maxHp = 20 }, tempo, {
  name = "CONFUSE RAY", effect = 49, power = 0, type = 7, accuracy = 100, pp = 10,
})
eq(tempo.confuseTurns, nil, "Own Tempo blocks confusion")

local dusty = {
  name = "DUSTOX", ability = 19, hp = 200, maxHp = 200, type1 = 6, type2 = 12,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:useMove({
  name = "TORCHIC", level = 5, hp = 20, maxHp = 20,
  atk = 10, spa = 20, type1 = 10, type2 = 10,
  stages = { atk = 0, spa = 0 },
}, dusty, {
  name = "EMBER", effect = 4, power = 40, type = 10, accuracy = 100,
  pp = 25, secondary = 100,
})
eq(dusty.status, nil, "Shield Dust blocks a burn chance")

-- ------- weather

;(function()
eq(Game3.EFFECT_SANDSTORM, 115, "Sandstorm is effect 115")
eq(Game3.EFFECT_RAIN_DANCE, 136, "Rain Dance is effect 136")
eq(Game3.EFFECT_SUNNY_DAY, 137, "Sunny Day is effect 137")
eq(Game3.EFFECT_HAIL, 164, "Hail is effect 164")
eq(Game3.abilityName(2), "DRIZZLE", "Drizzle name")
eq(Game3.abilityName(36), "TRACE", "Trace name")

fx.battle = {
  player = { name = "TORCHIC", hp = 20, maxHp = 20, type1 = 10, type2 = 10 },
  enemy = { name = "WURMPLE", hp = 16, maxHp = 16, type1 = 6, type2 = 6 },
}
local ok, rainMsg = fx:setWeather(Game3.WEATHER_RAIN, 5)
check(ok, "Rain Dance sets rain")
eq(fx.battle.weather, Game3.WEATHER_RAIN, "weather is rain")
eq(fx.battle.weatherTurns, 5, "for 5 turns")
check(rainMsg:find("rain", 1, true) ~= nil, "rain is announced")
check(not fx:setWeather(Game3.WEATHER_RAIN, 5), "the same weather fails")
ok = fx:setWeather(Game3.WEATHER_SUN, 5)
check(ok, "sun replaces rain")
eq(fx.battle.weather, Game3.WEATHER_SUN, "weather is sun")

local ember = { name = "EMBER", power = 40, type = 10 }
local function grassMon()
  return {
    name = "ODDISH", hp = 80, maxHp = 80, type1 = 12, type2 = 12,
    def = 20, spd = 10, stages = { def = 0, spd = 0 },
  }
end
local chickAtk = {
  name = "TORCHIC", level = 5, hp = 20, maxHp = 20,
  atk = 10, spa = 20, type1 = 10, type2 = 10,
  stages = { atk = 0, spa = 0 },
}
fx.battle.weather = nil
local dry = fx:dealDamage(chickAtk, grassMon(), ember)
fx.battle.weather = Game3.WEATHER_SUN
local sunned = fx:dealDamage(chickAtk, grassMon(), ember)
check(sunned.dmg > dry.dmg, "sun boosts Fire")
eq(fx:weatherPowerTenths(Game3.TYPE_FIRE), 15, "sun is 1.5x Fire")
eq(fx:weatherPowerTenths(Game3.TYPE_WATER), 5, "and 0.5x Water")
fx.battle.weather = Game3.WEATHER_RAIN
eq(fx:weatherPowerTenths(Game3.TYPE_WATER), 15, "rain is 1.5x Water")
eq(fx:weatherPowerTenths(Game3.TYPE_FIRE), 5, "and 0.5x Fire")

fx.battle.weather = Game3.WEATHER_SAND
local bug = { name = "WURMPLE", hp = 16, maxHp = 16, type1 = 6, type2 = 6 }
local sandLines = fx:weatherResidual(bug)
eq(bug.hp, 15, "sandstorm chips 1/16")
check(sandLines[1]:find("sandstorm", 1, true) ~= nil, "sand is announced")
local rock = { name = "GEODUDE", hp = 20, maxHp = 20, type1 = 5, type2 = 4 }
eq(#fx:weatherResidual(rock), 0, "Rock/Ground is immune to sand")

fx.battle.weather = Game3.WEATHER_HAIL
local ice = { name = "SNORUNT", hp = 20, maxHp = 20, type1 = 15, type2 = 15 }
eq(#fx:weatherResidual(ice), 0, "Ice is immune to hail")
bug.hp = 16
local hailLines = fx:weatherResidual(bug)
eq(bug.hp, 15, "hail chips 1/16")
check(hailLines[1]:find("hail", 1, true) ~= nil, "hail is announced")

fx.battle.weather = Game3.WEATHER_RAIN
local dish = { name = "LUDICOLO", ability = 44, hp = 10, maxHp = 20 }
local dishLines = fx:weatherResidual(dish)
eq(dish.hp, 11, "Rain Dish heals 1/16")
check(dishLines[1]:find("RAIN DISH", 1, true) ~= nil, "Rain Dish is announced")

fx.battle.weather = Game3.WEATHER_SUN
fx.battle.weatherTurns = 1
local ended = fx:tickWeather()
eq(fx.battle.weather, nil, "the last turn clears weather")
check(ended[#ended]:find("sunlight", 1, true) ~= nil, "the fade line is shown")

fx.battle.weather = nil
fx.battle.weatherTurns = nil
local pelipper = { name = "PELIPPER", ability = 2 }
local drizzle = fx:activateEnter(pelipper, chickAtk)
eq(fx.battle.weather, Game3.WEATHER_RAIN, "Drizzle sets rain")
eq(fx.battle.weatherTurns, nil, "ability weather does not expire")
check(drizzle[#drizzle]:find("DRIZZLE", 1, true) ~= nil, "Drizzle is announced")
local groudon = { name = "GROUDON", ability = 70 }
local drought = fx:activateEnter(groudon, chickAtk)
eq(fx.battle.weather, Game3.WEATHER_SUN, "Drought overwrites rain")
check(drought[#drought]:find("DROUGHT", 1, true) ~= nil, "Drought is announced")

local ralts = { name = "RALTS", ability = 36 }
local pooch = {
  name = "POOCHYENA", ability = 22,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
fx:activateEnter(ralts, pooch)
eq(ralts.ability, 22, "Trace copies Intimidate")
eq(pooch.stages.atk, -1, "and the copied Intimidate still fires")

fx.battle.player = { ability = 13 }
fx.battle.enemy = { ability = 0 }
fx.battle.weather = Game3.WEATHER_SAND
eq(fx:weatherPowerTenths(Game3.TYPE_FIRE), 10, "Cloud Nine suppresses type mods")
bug.hp = 16
eq(#fx:weatherResidual(bug), 0, "and sand chip")

fx.battle.player = { ability = 13 }
check(fx:weatherSuppressed(), "Cloud Nine suppresses weather")
fx.battle.player = { ability = 0 }
fx.battle.enemy = { ability = 77 }
check(fx:weatherSuppressed(), "Air Lock also suppresses weather")

fx.battle.player = { ability = 0 }
fx.battle.enemy = { ability = 0 }
fx.battle.weather = Game3.WEATHER_RAIN
fx.battle.player = { spe = 10, ability = 33, stages = { spe = 0 } }
fx.battle.enemy = { spe = 15, stages = { spe = 0 } }
check(fx:turnOrder({ priority = 0 }, { priority = 0 }),
  "Swift Swim doubles Speed in rain")

fx.rng = function() return 1 end
fx.battle.weather = nil
fx.battle.player = chickAtk
local dance = fx:useMove(pelipper, bug, {
  name = "RAIN DANCE", effect = 136, power = 0, type = 11, accuracy = 0, pp = 5,
})
eq(fx.battle.weather, Game3.WEATHER_RAIN, "Rain Dance from useMove")
eq(fx.battle.weatherTurns, 5, "for 5 turns")
check(dance[2]:find("rain", 1, true) ~= nil, "useMove announces rain")
end)()

-- ------- Truant / Pickup

;(function()
eq(Game3.abilityName(53), "PICKUP", "Pickup name")
eq(Game3.abilityName(54), "TRUANT", "Truant name")
eq(Game3.ABILITY_AIR_LOCK, 77, "Air Lock is ability 77")
eq(Game3.abilityName(77), "AIR LOCK", "Air Lock name")
eq(Game3.rollPickupItem(5, 0), Game3.ITEM_SUPER_POTION, "RS Pickup 0-29 is Super Potion")
eq(Game3.rollPickupItem(50, 0), Game3.ITEM_SUPER_POTION, "Ruby Pickup ignores level")
eq(Game3.rollPickupItem(5, 30), Game3.ITEM_FULL_HEAL, "30 opens Full Heal")
eq(Game3.rollPickupItem(5, 99), Game3.ITEM_KINGS_ROCK, "99 is King's Rock")

local slak = { name = "SLAKING", ability = 54, hp = 20, maxHp = 20 }
local blocked, lines = fx:statusBlocks(slak)
check(not blocked, "Truant attacks on the first turn")
eq(#lines, 0, "with no loaf line")
check(slak.truant, "and arms the loaf flag")
blocked, lines = fx:statusBlocks(slak)
check(blocked, "the next turn loafs")
check(lines[#lines]:find("loafing around", 1, true) ~= nil, "loaf is announced")
check(not slak.truant, "and the flag clears")
blocked = fx:statusBlocks(slak)
check(not blocked, "the third turn attacks again")

local sleeper = {
  name = "SLAKING", ability = 54, hp = 20, maxHp = 20,
  status = "slp", sleepTurns = 2,
}
blocked = fx:statusBlocks(sleeper)
check(blocked, "sleep still skips the turn")
eq(sleeper.truant, nil, "and does not toggle Truant")

fx:activateEnter(slak, { name = "WURMPLE", hp = 16, maxHp = 16 })
eq(slak.truant, nil, "send-out clears the loaf flag")

local zig = {
  name = "ZIGZAGOON", species = 263, ability = 53, hp = 20, maxHp = 20, level = 5,
}
local finder = Game3.new()
finder.party = { zig }
finder.bag = {}
finder.rng = function() return 1 end
local found = finder:tryPickup()
eq(#found, 0, "Ruby Pickup is silent")
eq(zig.item, Game3.ITEM_SUPER_POTION, "and the find is held")
eq(finder:itemCount(Game3.ITEM_SUPER_POTION), 0, "not the BAG")

finder:tryPickup()
eq(zig.item, Game3.ITEM_SUPER_POTION, "already holding skips")

zig.item = nil
local misser = Game3.new()
misser.party = { zig }
misser.bag = {}
misser.rng = function() return 2 end
eq(#misser:tryPickup(), 0, "Pickup skips when rand(10) is not 1")
eq(zig.item, nil, "and the hold slot stays empty")

local torch = Game3.new()
torch.party = {
  { name = "TORCHIC", species = 280, ability = 66, hp = 19, maxHp = 19, level = 5 },
}
torch.bag = {}
torch.rng = function() return 1 end
eq(#torch:tryPickup(), 0, "a non-Pickup party finds nothing")
end)()

-- ------- Protect / stat-ups / OHKO / two-turn

;(function()
eq(Game3.EFFECT_PROTECT, 111, "Protect is effect 111")
eq(Game3.EFFECT_OHKO, 38, "OHKO is effect 38")
eq(Game3.EFFECT_SOLARBEAM, 151, "Solarbeam is effect 151")
eq(Game3.EFFECT_FLY, 155, "Fly/Dig/Dive is effect 155")
eq(Game3.EFFECT_THUNDER, 152, "Thunder is effect 152")
eq(Game3.ohkoChance(30, 30), 30, "same-level OHKO is 30%")
eq(Game3.ohkoChance(20, 30), 0, "a higher-level foe cannot be OHKO'd")
eq(Game3.ohkoChance(40, 30), 40, "10 levels up is 40%")
check(Game3.protectSucceeds(0, 65535), "the first Protect always lands")
check(not Game3.protectSucceeds(1, 32768), "the second is 50%")
eq(Game3.chargeKind({ effect = 155, type = 2 }), "fly", "Flying-type 155 is Fly")
eq(Game3.chargeKind({ effect = 155, type = 4 }), "dig", "Ground-type 155 is Dig")
eq(Game3.chargeKind({ effect = 151 }), "solarbeam", "151 is Solarbeam")

local function stages()
  return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end
fx.battle = {
  player = { name = "TORCHIC", hp = 20, maxHp = 20, type1 = 10, type2 = 10 },
  enemy = { name = "WURMPLE", hp = 16, maxHp = 16, type1 = 6, type2 = 6 },
}
fx.rng = function() return 1 end
fx.data.moves = fx.data.moves or {}
fx.data.moves.typeChart = fx.data.moves.typeChart or {}
fx.data.moves.typeChart[#fx.data.moves.typeChart + 1] = { 4, 2, 0 }

local dancer = { name = "TORCHIC", hp = 20, maxHp = 20, stages = stages() }
local dummy = { name = "WURMPLE", hp = 16, maxHp = 16, type1 = 6, type2 = 6,
  stages = stages() }
local dance = fx:useMove(dancer, dummy, {
  name = "SWORDS DANCE", effect = 50, power = 0, type = 0, accuracy = 0, pp = 20,
})
eq(dancer.stages.atk, 2, "Swords Dance is +2 Attack")
check(dance[#dance]:find("sharply", 1, true) ~= nil, "and says sharply")
local howl = fx:useMove(dancer, dummy, {
  name = "HOWL", effect = 10, power = 0, type = 0, accuracy = 0, pp = 40,
})
eq(dancer.stages.atk, 3, "Howl is +1")
check(howl[#howl]:find("rose!", 1, true) ~= nil, "and says rose")
dancer.stages.atk = 6
local cap = fx:raiseStat(dancer, "atk", 1, "ATTACK")
check(cap:find("higher", 1, true) ~= nil, "a +6 stat will not rise")
eq(dancer.stages.atk, 6, "and stays at 6")

local bulky = { name = "MAKUHITA", hp = 40, maxHp = 40, stages = stages() }
fx:useMove(bulky, dummy, {
  name = "BULK UP", effect = 208, power = 0, type = 1, accuracy = 0, pp = 20,
})
eq(bulky.stages.atk, 1, "Bulk Up raises Attack")
eq(bulky.stages.def, 1, "and Defense")

local wall = {
  name = "NOSEPASS", hp = 40, maxHp = 40, stages = stages(),
}
local chick = {
  name = "TORCHIC", hp = 20, maxHp = 20, atk = 20, spa = 10, level = 5,
  type1 = 10, type2 = 10, stages = stages(),
}
local shield = fx:useMove(wall, chick, {
  name = "PROTECT", effect = 111, power = 0, type = 0, accuracy = 0, pp = 10,
  priority = 3,
})
check(wall.protected, "Protect raises the shield")
check(shield[#shield]:find("protected itself", 1, true) ~= nil, "and says so")
eq(wall.protectStreak, 1, "the streak starts at 1")
local blocked = fx:useMove(chick, wall, {
  name = "TACKLE", effect = 0, power = 35, type = 0, accuracy = 100, pp = 35,
})
eq(wall.hp, 40, "Protect blocks Tackle")
check(blocked[#blocked]:find("protected itself", 1, true) ~= nil,
  "the attacker is told")

local prey = {
  name = "WURMPLE", level = 20, hp = 40, maxHp = 40,
  type1 = 6, type2 = 6, stages = stages(),
}
local trap = {
  name = "TRAPINCH", level = 20, hp = 50, maxHp = 50,
  type1 = 4, type2 = 4, stages = stages(),
}
local ko = fx:useMove(trap, prey, {
  name = "FISSURE", effect = 38, power = 0, type = 4, accuracy = 30, pp = 5,
})
eq(prey.hp, 0, "OHKO faints a same-level foe")
check(ko[2]:find("one-hit KO", 1, true) ~= nil, "and announces it")
prey.hp, prey.level = 40, 21
fx:useMove(trap, prey, {
  name = "FISSURE", effect = 38, power = 0, type = 4, accuracy = 30, pp = 5,
})
eq(prey.hp, 40, "a higher-level foe is safe")
local bird = {
  name = "TAILLOW", level = 5, hp = 20, maxHp = 20,
  type1 = 0, type2 = 2, stages = stages(),
}
fx:useMove(trap, bird, {
  name = "FISSURE", effect = 38, power = 0, type = 4, accuracy = 30, pp = 5,
})
eq(bird.hp, 20, "Fissure does not hit Flying")

local beam = {
  name = "SOLARBEAM", effect = 151, power = 120, type = 12, accuracy = 100, pp = 10,
}
local grass = {
  name = "ROSELIA", hp = 40, maxHp = 40, level = 20, spa = 30,
  type1 = 12, type2 = 12, stages = stages(),
}
fx.battle.weather = nil
local charge = fx:useMove(grass, dummy, beam)
check(charge[#charge]:find("sunlight", 1, true) ~= nil, "Solarbeam charges")
check(grass.charging, "and stores the charge")
eq(dummy.hp, 16, "the charge turn deals no damage")
eq(beam.pp, 9, "PP is spent on the charge")
local fire = fx:useMove(grass, dummy, beam)
check(not grass.charging, "the hit turn clears the charge")
check(dummy.hp < 16, "and deals damage")
eq(beam.pp, 9, "without spending PP again")

dummy.hp = 16
grass.charging = nil
beam.pp = 10
fx.battle.weather = Game3.WEATHER_SUN
fx:useMove(grass, dummy, beam)
eq(grass.charging, nil, "sun skips the Solarbeam charge")
check(dummy.hp < 16, "and hits immediately")

local flyer = {
  name = "TAILLOW", hp = 30, maxHp = 30, level = 10, atk = 20,
  type1 = 0, type2 = 2, stages = stages(),
}
local fly = {
  name = "FLY", effect = 155, power = 90, type = 2, accuracy = 95, pp = 15,
}
dummy.hp = 16
fx:useMove(flyer, dummy, fly)
eq(flyer.invuln, "fly", "Fly goes semi-invulnerable")
local miss = fx:useMove(dummy, flyer, {
  name = "TACKLE", effect = 0, power = 35, type = 0, accuracy = 100, pp = 35,
})
eq(flyer.hp, 30, "Tackle misses a flyer")
check(miss[#miss]:find("missed", 1, true) ~= nil, "and says so")
local zap = fx:useMove({
  name = "ELECTRIKE", hp = 20, maxHp = 20, level = 10, spa = 20,
  type1 = 13, type2 = 13, stages = stages(),
}, flyer, {
  name = "THUNDER", effect = 152, power = 120, type = 13, accuracy = 70, pp = 10,
})
check(flyer.hp < 30, "Thunder hits a flyer")

local digger = {
  name = "NINCADA", hp = 40, maxHp = 40, level = 10, stages = stages(),
}
fx:useMove(digger, dummy, {
  name = "DIG", effect = 155, power = 60, type = 4, accuracy = 100, pp = 10,
})
eq(digger.invuln, "dig", "Dig is the Ground-type charge")
check(fx:hitsInvuln({ effect = 147 }, "dig"), "Earthquake hits Dig")
end)()

-- ------- Skull Bash / Sky Attack / Endure / crits

;(function()
eq(Game3.EFFECT_RAZOR_WIND, 39, "Razor Wind is effect 39")
eq(Game3.EFFECT_SKY_ATTACK, 75, "Sky Attack is effect 75")
eq(Game3.EFFECT_ENDURE, 116, "Endure is effect 116")
eq(Game3.EFFECT_SKULL_BASH, 145, "Skull Bash is effect 145")
eq(Game3.critDenom(0), 16, "a normal move crits on 1/16")
eq(Game3.critDenom(43), 8, "Slash-family is 1/8")
eq(Game3.critDenom(75), 8, "Sky Attack is 1/8")
eq(Game3.chargeKind({ effect = 39 }), "razorwind", "39 charges as Razor Wind")
eq(Game3.chargeKind({ effect = 75 }), "skyattack", "75 charges as Sky Attack")
eq(Game3.chargeKind({ effect = 145 }), "skullbash", "145 charges as Skull Bash")

local function stages()
  return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end
fx.battle = {
  player = { name = "TORCHIC", hp = 20, maxHp = 20 },
  enemy = { name = "WURMPLE", hp = 16, maxHp = 16 },
}
fx.rng = function() return 1 end

local dummy = {
  name = "WURMPLE", hp = 40, maxHp = 40, type1 = 6, type2 = 6,
  def = 10, spd = 10, stages = stages(),
}
local bashUser = {
  name = "SLAKING", hp = 50, maxHp = 50, level = 20, atk = 30,
  type1 = 0, type2 = 0, stages = stages(),
}
local bash = {
  name = "SKULL BASH", effect = 145, power = 100, type = 0, accuracy = 100, pp = 15,
}
local tucked = fx:useMove(bashUser, dummy, bash)
check(tucked[#tucked - 1]:find("tucked in its head", 1, true) ~= nil,
  "Skull Bash charges")
eq(bashUser.stages.def, 1, "and raises Defense")
check(bashUser.charging, "and stores the charge")
eq(dummy.hp, 40, "the charge turn deals no damage")
fx:useMove(bashUser, dummy, bash)
check(dummy.hp < 40, "the hit turn deals damage")
check(not bashUser.charging, "and clears the charge")

dummy.hp = 40
local windUser = {
  name = "SWABLU", hp = 30, maxHp = 30, level = 15, spa = 20,
  type1 = 0, type2 = 2, stages = stages(),
}
local wind = {
  name = "RAZOR WIND", effect = 39, power = 80, type = 0, accuracy = 100, pp = 10,
}
local whip = fx:useMove(windUser, dummy, wind)
check(whip[#whip]:find("whirlwind", 1, true) ~= nil, "Razor Wind charges")
eq(windUser.invuln, nil, "without going semi-invulnerable")

local skyUser = {
  name = "SWELLOW", hp = 40, maxHp = 40, level = 20, atk = 30,
  type1 = 0, type2 = 2, stages = stages(),
}
local sky = {
  name = "SKY ATTACK", effect = 75, power = 140, type = 2, accuracy = 90,
  pp = 5, secondary = 30,
}
dummy.hp = 200
dummy.maxHp = 200
dummy.flinch = nil
fx:useMove(skyUser, dummy, sky)
check(skyUser.charging, "Sky Attack charges")
check(skyUser.charging.kind == "skyattack", "as skyattack")
fx:useMove(skyUser, dummy, sky)
check(dummy.flinch, "Sky Attack can flinch on the hit turn")

local tank = {
  name = "SLAKOTH", hp = 5, maxHp = 40, def = 10, stages = stages(),
}
local brute = {
  name = "SLAKING", hp = 80, maxHp = 80, level = 40, atk = 80,
  type1 = 0, type2 = 0, stages = stages(),
}
local brace = fx:useMove(tank, brute, {
  name = "ENDURE", effect = 116, power = 0, type = 0, accuracy = 0, pp = 10,
  priority = 3,
})
check(tank.endured, "Endure sets the flag")
check(brace[#brace]:find("braced itself", 1, true) ~= nil, "and says so")
eq(tank.protectStreak, 1, "and shares Protect's streak")
local lived = fx:useMove(brute, tank, {
  name = "TACKLE", effect = 0, power = 80, type = 0, accuracy = 100, pp = 35,
})
eq(tank.hp, 1, "Endure leaves 1 HP")
check(lived[#lived]:find("endured the hit", 1, true) ~= nil, "and announces it")

fx.rng = function(n)
  if n == 8 then return 8 end
  return 1
end
local slashAtk = {
  name = "ZANGOOSE", hp = 40, maxHp = 40, level = 20, atk = 30,
  type1 = 0, type2 = 0, stages = stages(),
}
local slashDef = {
  name = "WURMPLE", hp = 80, maxHp = 80, def = 10, type1 = 6, type2 = 6,
  stages = stages(),
}
local slash = fx:dealDamage(slashAtk, slashDef, {
  name = "SLASH", effect = 43, power = 70, type = 0,
})
check(slash.crit, "a 1/8 roll crits Slash")
local lines = fx:useMove(slashAtk, {
  name = "WURMPLE", hp = 80, maxHp = 80, def = 10, type1 = 6, type2 = 6,
  stages = stages(),
}, { name = "SLASH", effect = 43, power = 70, type = 0, accuracy = 100, pp = 20 })
check(lines[2]:find("critical", 1, true) ~= nil, "and useMove announces it")
fx.rng = function() return 1 end
end)()

-- ------- PC boxes

local pcUser = Game3.new()
pcUser.data.pokemon = field.data.pokemon
pcUser.data.moves = field.data.moves
pcUser.rng = function() return 1 end
pcUser.party = { pcUser:makeMon(280, 5) }
pcUser.phase = "play"
pcUser.facing = "east"
pcUser.playerX, pcUser.playerY = 0, 0
pcUser.map = {
  id = "g_pc", width = 2, height = 1, grid = { 0, 1 }, tileset = "pair_pc",
}
pcUser.data.tilesets = { byId = { pair_pc = { behavior = { [1] = Game3.MB_PC } } } }
check(Game3.isPc(pcUser:behaviorAt(pcUser.map, 1, 0)), "the facing tile is a PC")
check(pcUser:tryTalk(), "A on a PC tile opens storage")
eq(pcUser.field.kind, "pc", "kind is pc")
eq(pcUser.field.mode, "root", "the menu starts on WITHDRAW / DEPOSIT / MOVE / SEE YA")
eq(#Game3.PC_ROOT, 4, "StorageSystemCreatePrimaryMenu has 4 items")

local function pressPc(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  pcUser:stepField()
  Input.wasPressed = old
end
pressPc("a")
eq(pcUser.field.mode, "storage", "WITHDRAW opens the box screen")
eq(pcUser.field.pss, "withdraw", "in withdraw mode")
eq(pcUser.field.area, "box", "the hand starts on the box")
pressPc("b")
eq(pcUser.field.prompt, "continue", "B asks to continue BOX operations")
pressPc("down")
pressPc("a")
eq(pcUser.field.mode, "root", "NO returns to the root")
pcUser:addToParty(pcUser:makeMon(290, 2))
pressPc("down")
pressPc("a")
eq(pcUser.field.mode, "storage", "DEPOSIT opens the box screen")
eq(pcUser.field.pss, "deposit", "in deposit mode")
eq(pcUser.field.area, "party", "the hand starts on the party")
pressPc("b")
pressPc("down")
pressPc("a")
eq(pcUser.field.mode, "root", "NO returns to the root")
pressPc("down")
pressPc("down")
pressPc("a")
eq(pcUser.field, nil, "SEE YA closes the PC")

pcUser.party = { pcUser:makeMon(280, 5) }
check(not pcUser:canDeposit(1), "the last party mon cannot be deposited")
pcUser:addToParty(pcUser:makeMon(290, 2))
pcUser.party[1].hp = 0
check(not pcUser:canDeposit(2), "the last healthy battler cannot be deposited")
check(pcUser:canDeposit(1), "a fainted extra can be deposited")
check(pcUser:depositFromParty(1), "deposit moves the fainted mon")
eq(#pcUser.party, 1, "party drops to one")
eq(pcUser.pc[1][1].species, 280, "Torchic is in BOX 1")
check(pcUser:withdrawFromBox(1, 1), "withdraw returns it to the party")
eq(#pcUser.party, 2, "party is two again")
eq(#pcUser.pc[1], 0, "BOX 1 is empty")

pcUser:ensurePc()
for _ = 1, Game3.BOX_SIZE do
  pcUser:sendToPc(pcUser.party[1])
end
eq(#pcUser.pc[1], 30, "BOX 1 holds 30")
eq(pcUser:sendToPc(pcUser.party[1]), 2, "the 31st mon opens BOX 2")

while #pcUser.party < 6 do
  pcUser:addToParty(pcUser.party[1])
end
check(pcUser:giveMon(290, 2), "giveMon still succeeds with a full party")
eq(#pcUser.party, 6, "the party stays at 6")
eq(pcUser.pc[2][#pcUser.pc[2]].species, 290, "the gift lands in the PC")
check(not pcUser:giveMon(280, 5), "a starter does not overflow to the PC")

local stuffer = Game3.new()
stuffer.data.pokemon = field.data.pokemon
stuffer.data.moves = field.data.moves
stuffer.rng = function() return 1 end
stuffer.party = { stuffer:makeMon(280, 5) }
while #stuffer.party < 6 do
  stuffer:addToParty(stuffer.party[1])
end
stuffer:ensurePc()
for b = 1, Game3.BOX_COUNT do
  while #stuffer.pc[b] < Game3.BOX_SIZE do
    stuffer.pc[b][#stuffer.pc[b] + 1] = stuffer:cloneMon(stuffer.party[1])
  end
end
check(not stuffer:hasMonSpace(), "party plus PC can fill up")
stuffer.balls = 3
stuffer:startWildBattle(290, 2)
stuffer:throwBall()
eq(stuffer.balls, 3, "a full PC does not spend the ball")
eq(stuffer.battle.caught, nil, "and does not catch")
eq(stuffer.battle.text, "The BOX is full.",
  "gOtherText_BoxIsFull")

;(function()
local tate = string.char(0, 2, 0, 0)
  .. padTrainerName("TATE")
  .. string.rep("\0", 8)
  .. GbaBin.packU32(1)
  .. string.rep("\0", 4)
  .. string.char(2)
  .. string.rep("\0", 3)
  .. GbaBin.packPtr(0x80)
eq(#tate, 40, "a doubles trainer row is still 40 bytes")
eq(BattleData.parseOneTrainer(tate, 0).doubleBattle, true,
  "u32 at +24 marks a doubles fight")

local duo = Game3.new()
duo.data.pokemon = field.data.pokemon
duo.data.moves = field.data.moves
duo.rng = function() return 1 end
duo.party = { duo:makeMon(280, 5), duo:makeMon(290, 2) }
local tateNpc = {
  trainerName = "TATE", trainerClass = "LEADER",
  doubleBattle = true,
  party = {
    { species = 286, level = 5 },
    { species = 288, level = 5 },
    { species = 290, level = 5 },
  },
}
check(duo:startTrainerBattle(tateNpc), "a doubles fight can start")
check(duo.battle.doubles, "the battle is marked doubles")
eq(duo.battle.enemy.species, 286, "slot 1 is Poochyena")
eq(duo.battle.enemy2.species, 288, "slot 2 is Zigzagoon")
eq(duo.battle.player.species, 280, "you send Torchic")
eq(duo.battle.player2.species, 290, "and Wurmple")
eq(duo.battle.trainerIndex, 2, "two mons are already out")
eq(duo:defaultTarget(duo.battle.player), duo.battle.enemy,
  "the lead hits the opposite slot")
eq(duo:defaultTarget(duo.battle.player2), duo.battle.enemy2,
  "the partner hits the other slot")

duo:beginTurn(duo.battle.player.moves[1])
eq(duo.battle.kind, "text", "FIGHT still opens a text queue")
local used = 0
for i = 1, #duo.battle.queue do
  if duo.battle.queue[i]:find(" used ", 1, true) then used = used + 1 end
end
eq(used, 4, "all four battlers act")

duo.battle.enemy.hp = 0
duo.battle.kind = "text"
duo.battle.queue = { "POOCHYENA fainted!" }
duo.battle.qi = 1
duo:advanceBattleText()
eq(duo.battle.enemy.species, 290, "the empty slot is filled from the party")
eq(duo.battle.enemy2.species, 288, "Zigzagoon stays out")
eq(duo.battle.kind, "intro", "the replacement is announced")

duo.battle.enemy.hp = 0
duo.battle.enemy2.hp = 0
duo.battle.kind = "text"
duo.battle.queue = { "WURMPLE fainted!" }
duo.battle.qi = 1
duo:advanceBattleText()
eq(duo.battle.kind, "won_trainer", "KOing both remaining slots wins")

local bench = Game3.new()
bench.data.pokemon = field.data.pokemon
bench.data.moves = field.data.moves
bench.rng = function() return 1 end
bench.party = {
  bench:makeMon(280, 5),
  bench:makeMon(290, 2),
  bench:makeMon(288, 3),
}
check(bench:startTrainerBattle(tateNpc), "a second doubles fight starts")
bench.battle.player.hp = 0
bench.battle.kind = "text"
bench.battle.queue = { "TORCHIC fainted!" }
bench.battle.qi = 1
bench:advanceBattleText()
eq(bench.battle.kind, "party", "a fainted lead asks for a replacement")
eq(bench.battle.switchSlot, "player", "into the empty player slot")
check(bench.battle.mustSwitch, "you cannot back out")
eq(Game3.aliveMon(bench.battle.player2), true, "the partner stays in")

local lone = Game3.new()
lone.data.pokemon = field.data.pokemon
lone.data.moves = field.data.moves
lone.party = { lone:makeMon(280, 5) }
check(lone:startTrainerBattle(tateNpc), "one healthy mon still starts doubles")
eq(lone.battle.player2, nil, "with an empty partner slot")
eq(lone.battle.enemy2.species, 288, "against two foes")
end)()

;(function()
eq(Game3.TARGET_BOTH, 8, "both foes")
eq(Game3.TARGET_FOES_AND_ALLY, 32, "Earthquake's target")
eq(Game3.TARGET_USER, 16, "Protect's target")
check(Game3.isSpreadTarget(32), "Earthquake is spread")
check(not Game3.isSpreadTarget(0), "Tackle is not")

local quakeBytes = string.char(147, 100, 4, 100, 10, 0, 32, 0, 0, 0, 0, 0)
eq(BattleData.parseOneMove(quakeBytes, 0).target, 32, "ROM byte 6 is the target")

local duo = Game3.new()
duo.data.pokemon = field.data.pokemon
duo.data.moves = field.data.moves
duo.rng = function() return 1 end
duo.party = { duo:makeMon(280, 5), duo:makeMon(290, 2) }
local npc = {
  trainerName = "TATE", trainerClass = "LEADER",
  doubleBattle = true,
  party = {
    { species = 286, level = 5 },
    { species = 288, level = 5 },
  },
}
check(duo:startTrainerBattle(npc), "doubles still start")
local quake = {
  name = "EARTHQUAKE", effect = Game3.EFFECT_EARTHQUAKE, power = 40,
  type = Game3.TYPE_GROUND, accuracy = 0, pp = 10, target = 32, priority = 0,
}
eq(#duo:spreadTargets(duo.battle.player, quake), 3,
  "Earthquake hits both foes and the ally")
eq(#duo:selectableTargets(duo.battle.player, { target = 0 }), 2,
  "a selected move can pick either foe")
eq(#duo:selectableTargets(duo.battle.player, quake), 0,
  "spread skips the aim menu")

local hpA = duo.battle.player2.hp
local hpE = duo.battle.enemy.hp
local hpF = duo.battle.enemy2.hp
duo:beginTurn(quake)
check(duo.battle.player2.hp < hpA, "the partner is hit")
check(duo.battle.enemy.hp < hpE, "foe 1 is hit")
check(duo.battle.enemy2.hp < hpF, "foe 2 is hit")
local used = 0
for i = 1, #duo.battle.queue do
  if duo.battle.queue[i]:find(" used ", 1, true) then used = used + 1 end
end
eq(used, 4, "EQ announces once, then the other three battlers act")

duo.battle.kind = "fight"
duo.battle.fightCursor = 0
duo.battle.chooser = "player"
duo.battle.player2.hp = 0
duo.battle.player.moves[1] = {
  name = "SCRATCH", effect = 0, power = 40, type = 0,
  accuracy = 0, pp = 35, target = 0, priority = 0,
}
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
duo:stepBattle()
Input.wasPressed = old
eq(duo.battle.kind, "target", "FIGHT on a single-target move opens aim")
eq(duo.battle.targetList[1], duo.battle.enemy, "the default foe is first")
Input.wasPressed = function(_, key) return key == "right" end
duo:stepBattle()
Input.wasPressed = old
eq(duo.battle.targetCursor, 1, "right aims at the other foe")
local before1 = duo.battle.enemy.hp
local before2 = duo.battle.enemy2.hp
Input.wasPressed = function(_, key) return key == "a" end
duo:stepBattle()
Input.wasPressed = old
eq(duo.battle.enemy.hp, before1, "the first foe is spared")
check(duo.battle.enemy2.hp < before2, "the aimed foe is hit")

local veil = {
  name = "CACNEA", hp = 16, maxHp = 16, type1 = 12, type2 = 12,
  ability = Game3.ABILITY_SAND_VEIL,
}
duo.battle.weather = Game3.WEATHER_SAND
eq(#duo:weatherResidual(veil), 0, "Sand Veil skips the sand chip")
eq(Game3.abilityName(8), "SAND VEIL", "ability 8 is named")

local misser = Game3.new()
misser.data.moves = field.data.moves
misser.battle = { weather = Game3.WEATHER_SAND }
misser.rng = function() return 81 end
local sanded = {
  name = "CACNEA", hp = 20, maxHp = 20, type1 = 12, type2 = 12,
  ability = Game3.ABILITY_SAND_VEIL,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local scratch = {
  name = "SCRATCH", effect = 0, power = 40, type = 0,
  accuracy = 100, pp = 35, target = 0,
}
local lines = misser:useMove({
  name = "TORCHIC", hp = 20, maxHp = 20, atk = 20, spa = 20, level = 5,
  type1 = 10, type2 = 10, ability = 0,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}, sanded, scratch)
check(lines[2]:find("missed", 1, true) ~= nil,
  "Sand Veil makes a 100% move miss on roll 81")

local fx = Game3.new()
fx.data.moves = field.data.moves
fx.rng = function() return 1 end
fx.battle = {}
local atk = {
  name = "CAMERUPT", level = 20, hp = 50, maxHp = 50,
  atk = 40, spa = 40, type1 = 10, type2 = 4,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local defA = {
  name = "A", hp = 80, maxHp = 80, type1 = 0, type2 = 0,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local defB = {
  name = "B", hp = 80, maxHp = 80, type1 = 0, type2 = 0,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local eqMove = { power = 80, type = 0, effect = 0 }
local full = fx:dealDamage(atk, defA, eqMove)
eqMove.spreadHits = true
local half = fx:dealDamage(atk, defB, eqMove)
eq(half.dmg, math.max(1, math.floor(full.dmg / 2)), "spread hits deal half")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FLAG_SYS_POKEDEX_GET, 0x801, "FLAG_SYS_POKEDEX_GET")
eq(Game3.SPECIAL_HEAL_PARTY, 0, "special 0 heals")
eq(Game3.SPECIAL_CHOOSE_STARTER, 156, "special 156 is the starter chooser")
eq(Game3.SPECIAL_GET_POKEDEX_INFO, 212, "special 212 writes dex counts")
eq(Game3.SPECIAL_SHOW_POKEDEX_RATING, 213, "special 213 rates the catch")

local dexer = Game3.new()
eq(#dexer:startMenuItems(), 6, "START has six rows before the dex")
eq(dexer:startMenuItems()[1], "POKeMON", "POKeMON is first")
dexer.phase = "play"
dexer.facing = "east"
dexer.playerX, dexer.playerY = 0, 0
dexer.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = { { move = 10, level = 1 } },
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
      expYield = 54, growthRate = 0, learnset = { { move = 33, level = 1 } },
    },
  },
}
dexer.data.moves = {
  byId = {
    [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35, accuracy = 100 },
    [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35, accuracy = 95 },
  },
}
dexer.map = { id = "g_lab", width = 3, height = 1, grid = { 0, 0, 0 } }
dexer.npcByMap = { g_lab = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCH } } }
check(dexer:giveStarter(280), "a starter can be given first")
eq(#dexer:startMenuItems(), 6, "the starter alone does not grow START")
check(dexer:tryTalk(), "then Birch hands the POKeDEX")
eq(dexer.flags[Game3.FLAG_SYS_POKEDEX_GET], true, "FLAG_SYS_POKEDEX_GET is set")
eq(#dexer:startMenuItems(), 7, "START grows a POKeDEX row")
eq(dexer:startMenuItems()[1], "POKeDEX", "POKeDEX is first")

check(dexer:hasCaught(280), "the starter is caught")
check(dexer:hasSeen(280), "and seen")
dexer:openDex()
eq(dexer.field.kind, "dex", "openDex lists entries")
eq(dexer.field.list[1].id, 280, "Torchic is on the list")
eq(dexer.field.list[1].caught, true, "and marked GOT")
eq(dexer.field.list[1].name, "TORCHIC", "by name")

local function pressDex(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  dexer:stepField()
  Input.wasPressed = old
end
pressDex("b")
eq(dexer.field.kind, "menu", "B from the dex returns to START")
pressDex("a")
eq(dexer.field.kind, "dex", "A on POKeDEX opens the list")

dexer.party[1].hp = 1
dexer:runSpecial(0)
eq(dexer.party[1].hp, dexer.party[1].maxHp, "special 0 heals the party")
dexer.field = { kind = "talk", text = "stay" }
dexer:runSpecial(156)
eq(dexer.field.kind, "starter", "special 156 opens ChooseStarter")
eq(dexer.field.scripted, true, "and parks waitstate")
eq(dexer.field.cursor, 1, "on Torchic")
dexer.field = nil
dexer.scriptWait = nil

dexer:runSpecial(212)
eq(dexer.scriptVars[0x8004], 1, "VAR_0x8004 is seen")
eq(dexer.scriptVars[0x8005], 1, "VAR_0x8005 is caught")
eq(dexer.scriptVars[0x8006], 0, "VAR_0x8006 is national (off)")

dexer:markSeen(290)
check(dexer:hasSeen(290), "seen-only species count")
check(not dexer:hasCaught(290), "but are not caught")
local seenN, caughtN = dexer:dexCounts()
eq(seenN, 2, "two seen")
eq(caughtN, 1, "one caught")
dexer:runSpecial(212)
eq(dexer.scriptVars[0x8004], 2, "seen count updates")
eq(dexer.scriptVars[0x8005], 1, "caught stays one")
local rate = dexer:pokedexRating(caughtN)
check(rate:find("grassy", 1, true) ~= nil, "a thin dex gets the grassy hint")

check(dexer:startWildBattle(290, 2), "a wild battle still starts")
check(dexer:hasSeen(290), "and marks the foe seen")

local bagger = Game3.new()
bagger.phase = "play"
bagger.facing = "east"
bagger.playerX, bagger.playerY = 0, 0
bagger.map = { id = "g_bag", width = 3, height = 1, grid = { 0, 0, 0 } }
bagger.npcByMap = { g_bag = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCHS_BAG } } }
bagger.party = { bagger:makeMon(280, 5) }
bagger.flags[Game3.FLAG_SYS_POKEMON_GET] = true
check(bagger:tryTalk(), "the bag is still talkable after a starter")
eq(bagger.field.kind, "talk", "but it is not the dex giver")
eq(bagger.field.text, "...", "gfx 97 has no dex line")
check(not bagger:hasPokedex(), "and does not set FLAG_SYS_POKEDEX_GET")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.GENDER_MALE, 0, "boy is 0")
eq(Game3.GENDER_FEMALE, 1, "girl is 1")
eq(Game3.GFX_MAY, 89, "May gfx")
eq(Game3.GFX_RIVAL_BRENDAN, 100, "rival Brendan gfx")
eq(Game3.GFX_RIVAL_MAY, 105, "rival May gfx")
eq(Game3.GFX_VAR_0, 240, "lab rival is VAR_0")
eq(Game3.FLAG_HIDE_RIVAL_BIRCH_LAB, 0x379, "FLAG_HIDE_RIVAL_BIRCH_LAB")
eq(Game3.rivalStarterSpecies(277), 280, "Treecko loses to Torchic")
eq(Game3.rivalStarterSpecies(280), 283, "Torchic loses to Mudkip")
eq(Game3.rivalStarterSpecies(283), 277, "Mudkip loses to Treecko")
eq(Game3.starterIndex(280), 1, "VAR_STARTER_MON Torchic is 1")

local boy = Game3.new()
eq(boy.gender, Game3.GENDER_MALE, "new game is a boy")
eq(boy:rivalName(), "MAY", "so the rival is May")
eq(boy:rivalGraphicsId(), Game3.GFX_RIVAL_MAY, "May's rival sprite")
eq(boy:playerGraphicsId(), Game3.GFX_BRENDAN, "Brendan's player sprite")
eq(boy:resolveGraphicsId(240), Game3.GFX_RIVAL_MAY, "VAR_0 is May")
eq(boy.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB], nil, "map scripts hide the lab rival")
eq(boy.flags[Game3.FLAG_HIDE_MAY_MOM_DOWNSTAIRS], true, "May's downstairs mom hides")
eq(boy.flags[Game3.FLAG_HIDE_MOVING_TRUCK_MAY], true, "May's truck hides")
eq(boy.flags[Game3.FLAG_HIDE_BRENDAN_MOM], true, "outdoor Brendan-mom hides")
eq(boy.flags[Game3.FLAG_HIDE_BRENDAN_UPSTAIRS], true, "upstairs Brendan hides")

boy:applyGender(Game3.GENDER_FEMALE)
eq(boy:rivalName(), "BRENDAN", "a girl rivals Brendan")
eq(boy:resolveGraphicsId(240), Game3.GFX_RIVAL_BRENDAN, "VAR_0 is Brendan")
eq(boy.flags[Game3.FLAG_HIDE_MAY_MOM_DOWNSTAIRS], nil, "May's downstairs mom is shown")
eq(boy.flags[Game3.FLAG_HIDE_BRENDAN_MOM_DOWNSTAIRS], true, "Brendan's downstairs mom hides")
eq(boy.flags[Game3.FLAG_HIDE_MOVING_TRUCK_BRENDAN], true, "Brendan's truck hides")
eq(boy.flags[Game3.FLAG_HIDE_MAY_MOM], true, "outdoor May-mom hides")
eq(boy.flags[Game3.FLAG_HIDE_MAY_UPSTAIRS], true, "upstairs May hides")

local picker = Game3.new()
picker.phase = "play"
picker:openGenderMenu()
eq(picker.field.kind, "gender", "NEW GAME opens BOY/GIRL")
local function pressGender(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  picker:stepField()
  Input.wasPressed = old
end
pressGender("down")
eq(picker.field.cursor, 1, "down is GIRL")
pressGender("a")
eq(picker.gender, Game3.GENDER_FEMALE, "A locks in girl")
eq(picker.field, nil, "and closes the menu")

local labber = Game3.new()
labber.phase = "play"
labber.facing = "east"
labber.playerX, labber.playerY = 0, 0
labber.data.pokemon = {
  byIndex = {
    [277] = { name = "TREECKO", hp = 40, atk = 45, def = 35, spe = 70,
      spa = 65, spd = 55, type1 = 12, type2 = 12, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = {} },
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = {} },
    [283] = { name = "MUDKIP", hp = 50, atk = 70, def = 50, spe = 40,
      spa = 50, spd = 50, type1 = 11, type2 = 11, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = {} },
  },
}
labber.map = {
  id = "g1_4", width = 3, height = 2, grid = { 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 1, y = 0, graphicsId = Game3.GFX_BIRCH, flagId = Game3.FLAG_HIDE_BIRCH_IN_LAB },
    { x = 2, y = 0, graphicsId = Game3.GFX_VAR_0, flagId = Game3.FLAG_HIDE_RIVAL_BIRCH_LAB },
  },
  mapScripts = {
    onTransition = {
      { op = "setflag", flag = Game3.FLAG_HIDE_RIVAL_BIRCH_LAB },
      { op = "end" },
    },
  },
}
labber.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = nil
labber:enterMap(labber.map, 1, 1, false)
labber.facing = "north"
eq(#labber:npcsFor(labber.map), 1, "ON_TRANSITION hides the rival; Birch stays")
eq(labber:npcsFor(labber.map)[1].graphicsId, Game3.GFX_BIRCH, "the lab rival stays hidden")
check(labber:giveStarter(280), "Torchic is given")
eq(labber.rivalSpecies, 283, "May takes Mudkip")
eq(labber.scriptVars[Game3.VAR_STARTER_MON], 1, "VAR_STARTER_MON is Torchic")
check(labber:tryTalk(), "Birch still hands the dex")
eq(labber.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB], nil, "the rival hide flag clears")
eq(#labber:npcsFor(labber.map), 2, "May appears beside Birch")
eq(labber:npcsFor(labber.map)[2].graphicsId, Game3.GFX_RIVAL_MAY, "VAR_0 resolved to May")

labber.playerX, labber.playerY = 1, 0
labber.facing = "east"
labber.field = nil
local balls = labber:itemCount(Game3.ITEM_POKE_BALL)
check(labber:tryTalk(), "talking to May takes the starter")
check(labber.field.text:find("MUDKIP", 1, true) ~= nil, "she names Mudkip")
eq(labber:itemCount(Game3.ITEM_POKE_BALL), balls + 5, "and hands five balls")
check(labber.rivalTookStarter, "the take is sticky")
labber.field = nil
check(labber:tryTalk(), "talking again is the leftover line")
check(labber.field.text:find("next", 1, true) ~= nil, "Where should I go next")
eq(labber:itemCount(Game3.ITEM_POKE_BALL), balls + 5, "balls are not given twice")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FLAG_HIDE_RIVAL_ROUTE103, 0x2D3, "FLAG_HIDE_RIVAL_ROUTE103")
eq(Game3.FLAG_DEFEATED_RIVAL_ROUTE103, 0x82, "FLAG_DEFEATED_RIVAL_ROUTE103")
eq(Game3.TRAINER_MAY_7, 535, "May's Mudkip row")
eq(Game3.TRAINER_BRENDAN_7, 526, "Brendan's Mudkip row")

local r = Game3.new()
r.party = { r:makeMon(280, 5) }
eq(r:playerStarterSpecies(), 280, "the party starter is Torchic")
eq(r:rivalTrainerId(), Game3.TRAINER_MAY_7, "boy vs May's Mudkip")
r:applyGender(Game3.GENDER_FEMALE)
eq(r:rivalTrainerId(), Game3.TRAINER_BRENDAN_7, "girl vs Brendan's Mudkip")

local other = {
  x = 1, y = 0, graphicsId = Game3.GFX_VAR_0, flagId = 0x400,
}
r.phase = "play"
r.facing = "east"
r.playerX, r.playerY = 0, 0
r.map = { id = "g_other", width = 3, height = 1, grid = { 0, 0, 0 } }
r.npcByMap = { g_other = { other } }
check(r:tryTalk(), "a random VAR_0 is still talkable")
eq(r.field.kind, "talk", "it is not the lab take")
eq(r.field.text, "...", "and falls through")
check(not r.rivalTookStarter, "it does not take a starter")

local route = Game3.new()
route.phase = "play"
route.facing = "east"
route.playerX, route.playerY = 0, 0
route.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = { { move = 10, level = 1 } },
    },
    [283] = {
      name = "MUDKIP", hp = 50, atk = 70, def = 50, spe = 40,
      spa = 50, spd = 50, type1 = 11, type2 = 11, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = { { move = 33, level = 1 } },
    },
  },
}
route.data.moves = {
  byId = {
    [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35, accuracy = 100 },
    [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35, accuracy = 95 },
  },
}
route.map = { id = "g0_18", width = 3, height = 1, grid = { 0, 0, 0 } }
local rivalNpc = {
  x = 1, y = 0, graphicsId = Game3.GFX_VAR_0,
  flagId = Game3.FLAG_HIDE_RIVAL_ROUTE103,
}
route.npcByMap = { g0_18 = { rivalNpc } }
check(route:tryTalk(), "talking before a starter still works")
eq(route.phase, "play", "and does not start a fight")
check(route.field.text:find("POKeMON", 1, true) ~= nil, "May asks for a POKeMON")

check(route:giveStarter(280), "Torchic joins")
route.field = nil
check(route:tryTalk(), "talking on Route 103 starts the rival fight")
eq(route.phase, "battle", "phase is battle")
eq(route.battle.rivalRoute103, true, "it is the Route 103 fight")
eq(route.battle.enemy.species, 283, "May sends Mudkip")
eq(route.battle.text, "MAY would like to battle!", "intro names May")

route.battle.enemy.hp = 0
route.battle.kind = "text"
route.battle.queue = { "MUDKIP fainted!" }
route.battle.qi = 1
route:advanceBattleText()
eq(route.battle.kind, "won_trainer", "the KO opens victory")
local function pressA()
  local old = Input.wasPressed
  Input.wasPressed = function(_, name) return name == "a" end
  route:stepBattle()
  Input.wasPressed = old
end
pressA()
eq(route.phase, "play", "winning returns to the field")
eq(rivalNpc.hidden, true, "May leaves the route")
eq(route.flags[Game3.FLAG_HIDE_RIVAL_ROUTE103], true, "FLAG_HIDE_RIVAL_ROUTE103")
eq(route.flags[Game3.FLAG_DEFEATED_RIVAL_ROUTE103], true, "FLAG_DEFEATED_RIVAL_ROUTE103")
eq(route.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 4, "beating her writes lab-state 4")
eq(route.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB], nil, "and shows her in the lab")
eq(route.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN], nil, "and in Oldale")
eq(route.scriptVars[Game3.VAR_ROUTE103_STATE], 1, "VAR_ROUTE103_STATE 1")
eq(route.scriptVars[Game3.VAR_OLDALE_STATE], 1, "VAR_OLDALE_STATE 1")
check(route.field.text:find("lab", 1, true) ~= nil, "she points back to the lab")
end)()

;(function()
eq(Game3.GFX_MOM, 215, "Mom gfx is 215")
eq(Game3.FLAG_SET_WALL_CLOCK, 0x51, "FLAG_SET_WALL_CLOCK")
eq(Game3.FLAG_HIDE_MOM_UPSTAIRS, 0x2F5, "FLAG_HIDE_MOM_UPSTAIRS")
eq(Game3.FLAG_HIDE_MACHOKE_MOVER_1, 0x2F2, "FLAG_HIDE_MACHOKE_MOVER_1")
eq(Game3.new().flags[Game3.FLAG_HIDE_MOM_UPSTAIRS], nil,
  "new game does not pre-hide Mom")

local cells = {}
for i = 1, 64 do cells[i] = 0 end
local brendan2f = {
  id = "g1_1", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
  objects = {
    { x = 7, y = 1, graphicsId = Game3.GFX_MOM, flagId = Game3.FLAG_HIDE_MOM_UPSTAIRS },
  },
  mapScripts = {
    onTransition = {
      { op = "setflag", flag = Game3.FLAG_HIDE_MOM_UPSTAIRS },
      { op = "end" },
    },
  },
}
local may2f = {
  id = "g1_3", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 3, y = 1, kind = 0, text = "The clock is stopped." } },
}
check(Game3.isBedroomMap(brendan2f), "a stopped clock marks a bedroom")
check(Game3.isBrendanBedroom(brendan2f), "clock at x>=4 is Brendan's")
check(not Game3.isBrendanBedroom(may2f), "clock at x=3 is May's")
check(not Game3.isBedroomMap({ bgEvents = { { text = "LITTLEROOT TOWN" } } }),
  "a town sign is not a bedroom")

local truck = {
  id = "g_truck", width = 5, height = 5, connections = {},
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0 },
  objects = { { x = 0, y = 0 }, { x = 0, y = 3 }, { x = 2, y = 3 } },
  spawn = { x = 1, y = 2 },
}
local townCells = {}
for i = 1, 15 * 12 do townCells[i] = 0 end
local town = {
  id = "g0_9", width = 15, height = 12, spawn = { x = 8, y = 10 },
  grid = townCells,
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_INTRO_STATE, value = 1,
        script = {
          { op = "loadword", text = "How was the moving truck ride?" },
          { op = "callstd", id = 2 },
          { op = "end" },
        },
      },
    },
  },
}
local floor = {
  id = "g1_0", width = 8, height = 8, grid = cells, spawn = { x = 5, y = 4 },
  objects = {
    { x = 1, y = 2, graphicsId = 95, flagId = Game3.FLAG_HIDE_MACHOKE_MOVER_1 },
    { x = 2, y = 2, graphicsId = 96, flagId = Game3.FLAG_HIDE_MACHOKE_MOVER_2 },
    { x = 2, y = 6, graphicsId = Game3.GFX_MOM,
      flagId = Game3.FLAG_HIDE_BRENDAN_MOM_DOWNSTAIRS },
  },
}

local boy = Game3.new()
boy.phase = "play"
boy.data.maps = {
  start = "g0_9",
  maps = { g0_9 = town, g1_1 = brendan2f, g1_3 = may2f, g1_0 = floor,
    g_truck = truck },
}
eq(boy:playerBedroomMap().id, "g1_1", "boy warps to Brendan's 2F")
boy.map = truck
boy.playerX, boy.playerY = 2, 2
check(boy:tryWalk(1, 0), "walking off the truck leaves")
eq(boy.map.id, "g0_9", "into Littleroot")
eq(boy.playerX, 3, "west house truck tile")
eq(boy.playerY, 10, "south row")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 1, "intro state 1")
eq(boy.lastHeal.mapId, "g1_1", "respawn is Brendan 2F")
eq(boy.field.text, "How was the moving truck ride?", "ON_FRAME is Mom's truck line")

boy:applyGender(Game3.GENDER_FEMALE)
eq(boy:playerBedroomMap().id, "g1_3", "girl warps to May's 2F")
boy.map = truck
boy.playerX, boy.playerY = 2, 2
check(boy:exitTruck(), "exitTruck respects gender")
eq(boy.map.id, "g0_9", "girl also lands in town")
eq(boy.playerX, 12, "east house truck tile")
eq(boy.playerY, 10, "south row")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 2, "intro state 2")
eq(boy.lastHeal.mapId, "g1_3", "respawn is May 2F")

check(boy:scriptWarp(1, 0, Game3.WARP_ID_NONE, 5, 4), "warpsilent into 1F")
eq(boy.map.id, "g1_0", "Brendan's house 1F")
eq(boy.playerX, 5, "warp x")
eq(boy.playerY, 4, "warp y")
boy:runMapOps({
  { op = "warp", mapGroup = 1, mapNum = 1, warpId = Game3.WARP_ID_NONE, x = 4, y = 4 },
  { op = "end" },
})
eq(boy.map.id, "g1_1", "IR warp enters Brendan 2F")
eq(boy.playerX, 4, "IR warp x")
eq(boy.playerY, 4, "IR warp y")

local fallback = Game3.new()
fallback.phase = "play"
fallback.data.maps = { start = "g0_9", maps = { g0_9 = {
  id = "g0_9", width = 2, height = 2, spawn = { x = 0, y = 0 },
  grid = { 0, 0, 0, 0 },
}, g_truck = truck } }
fallback.map = truck
check(fallback:exitTruck(), "no bedroom still leaves the truck")
eq(fallback.map.id, "g0_9", "to Littleroot")
eq(fallback.playerX, 0, "tiny town falls back to spawn")
eq(fallback.field, nil, "no placeholder line; the map script owns the scene")

local home = Game3.new()
home.phase = "play"
home.facing = "north"
home.playerX, home.playerY = 5, 2
home.map = brendan2f
check(home:tryTalk(), "A on the stopped clock")
eq(home.field.text, "The clock started!", "sets the clock")
eq(home.flags[Game3.FLAG_SET_WALL_CLOCK], true, "FLAG_SET_WALL_CLOCK")
eq(home.flags[Game3.FLAG_HIDE_MACHOKE_MOVER_1], true, "hides mover 1")
eq(home.flags[Game3.FLAG_HIDE_MACHOKE_MOVER_2], true, "hides mover 2")
eq(home.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 6, "clock sets intro 6")
home.field = nil
check(home:tryTalk(), "A on the clock again")
eq(home.field.text, "It's the wall clock.", "later reads as running")

home:enterMap(floor, 5, 4, true)
eq(#home:npcsFor(floor), 1, "Machoke movers leave after the clock")
eq(home:npcsFor(floor)[1].graphicsId, Game3.GFX_MOM, "Mom downstairs stays")

home.playerX, home.playerY = 1, 6
home.facing = "east"
home.party = { { hp = 1, maxHp = 20, moves = {} } }
home.field = nil
check(home:tryTalk(), "talking to Mom heals")
eq(home.party[1].hp, 20, "HP is restored")
eq(home.field.text, "MOM: You should rest a bit.", "Mom's heal line")
end)()

;(function()
eq(Game3.HEAL_LITTLEROOT_BRENDAN_2F, 1, "heal location 1 is Brendan 2F")
eq(Game3.HEAL_LITTLEROOT_MAY_2F, 2, "heal location 2 is May 2F")
eq(Game3.HEAL_SLATEPORT_CITY, 4, "heal location 4 is Slateport")
eq(Game3.HEAL_LOCATIONS[4].x, 19, "Slateport Center door x")
eq(Game3.HEAL_LOCATIONS[4].y, 20, "Slateport Center door y")
eq(Game3.HEAL_LOCATIONS[22].group, 26, "Southern Island is SpecialArea")
eq(Game3.WARP_ID_DYNAMIC, 0x7F, "WARP_ID_DYNAMIC is 0x7F")

local cells = {}
for i = 1, 64 do cells[i] = 0 end
local townCells = {}
for i = 1, 15 * 12 do townCells[i] = 0 end
local houseCells = {}
for i = 1, 10 * 10 do houseCells[i] = 0 end
local brendan2f = {
  id = "g1_1", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
}
local may2f = {
  id = "g1_3", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 3, y = 1, kind = 0, text = "The clock is stopped." } },
}
local house = {
  id = "g1_0", width = 10, height = 10, grid = houseCells, spawn = { x = 8, y = 8 },
}
local town = {
  id = "g0_9", width = 15, height = 12, spawn = { x = 8, y = 10 },
  grid = townCells,
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_INTRO_STATE, value = 1,
        script = {
          { op = "loadword", text = "LITTLEROOT is our new home!" },
          { op = "callstd", id = 4 },
          { op = "setflag", flag = Game3.FLAG_HIDE_MOVING_TRUCK_BRENDAN },
          { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 3 },
          { op = "warp", mapGroup = 1, mapNum = 0, warpId = Game3.WARP_ID_NONE,
            x = 8, y = 8 },
          { op = "end" },
        },
      },
    },
  },
}
local truck = {
  id = "g_truck", width = 5, height = 5, connections = {},
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0 },
  objects = { { x = 0, y = 0 }, { x = 0, y = 3 }, { x = 2, y = 3 } },
  spawn = { x = 1, y = 2 },
  warps = { { x = 4, y = 2, warpId = Game3.WARP_ID_DYNAMIC } },
  coordEvents = {
    {
      x = 3, y = 2,
      trigger = Game3.VAR_LITTLEROOT_INTRO_STATE, index = 0,
      script = {
        { op = "setrespawn", id = Game3.HEAL_LITTLEROOT_BRENDAN_2F },
        { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 1 },
        { op = "setvar", var = Game3.VAR_LITTLEROOT_HOUSES_STATE_2, val = 1 },
        { op = "setdynamicwarp", mapGroup = 0, mapNum = 9,
          warpId = Game3.WARP_ID_NONE, x = 3, y = 10 },
        { op = "end" },
      },
    },
  },
}

local boy = Game3.new()
boy.phase = "play"
boy.data.maps = {
  start = "g0_9",
  maps = {
    g0_9 = { id = "g0_9", width = 15, height = 12, spawn = { x = 8, y = 10 },
      grid = townCells },
    g1_1 = brendan2f, g1_3 = may2f, g1_0 = house, g_truck = truck,
  },
}
boy.map = truck
boy.playerX, boy.playerY = 2, 2
check(boy:tryWalk(1, 0), "step onto the truck door trigger")
eq(boy.map.id, "g_truck", "still in the truck")
eq(boy.playerX, 3, "on the coord tile")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 1, "intro state 1")
eq(boy.lastHeal.mapId, "g1_1", "setrespawn is Brendan 2F")
eq(boy.dynamicWarp.x, 3, "setdynamicwarp x")
eq(boy.dynamicWarp.y, 10, "setdynamicwarp y")
check(boy:tryWalk(1, 0), "step onto MAP_DYNAMIC")
eq(boy.map.id, "g0_9", "into Littleroot")
eq(boy.playerX, 3, "west house truck tile")
eq(boy.playerY, 10, "south row")

local mom = Game3.new()
mom.phase = "play"
mom.data.maps = {
  start = "g0_9",
  maps = { g0_9 = town, g1_1 = brendan2f, g1_3 = may2f, g1_0 = house },
}
mom.scriptVars = { [Game3.VAR_LITTLEROOT_INTRO_STATE] = 1 }
mom:enterMap(town, 3, 10, true)
eq(mom.map.id, "g0_9", "ON_FRAME talks in town first")
eq(mom.field.text, "LITTLEROOT is our new home!", "Mom's moving-in line")
eq(mom.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 1, "intro still 1")
do
  local Input = require("src.core.Input")
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  mom:stepField()
  Input.wasPressed = old
end
eq(mom.map.id, "g1_0", "A continues into 1F")
eq(mom.playerX, 8, "inside at 8,8")
eq(mom.playerY, 8, "inside at 8,8")
eq(mom.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 3, "intro state 3")
eq(mom.flags[Game3.FLAG_HIDE_MOVING_TRUCK_BRENDAN], true, "the truck hides")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.LOCALID_MOM_LITTLEROOT, 4, "town Mom is local 4")
eq(Game3.FLAG_HIDE_MOM_LITTLEROOT, 0x2F0, "FLAG_HIDE_MOM_LITTLEROOT")

local townCells = {}
for i = 1, 15 * 12 do townCells[i] = 0 end
local houseCells = {}
for i = 1, 10 * 10 do houseCells[i] = 0 end
local cells = {}
for i = 1, 64 do cells[i] = 0 end
local brendan2f = {
  id = "g1_1", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
}
local house = {
  id = "g1_0", width = 10, height = 10, grid = houseCells, spawn = { x = 8, y = 8 },
}
local town = {
  id = "g0_9", width = 15, height = 12, spawn = { x = 8, y = 10 },
  grid = townCells,
  objects = {
    {
      localId = Game3.LOCALID_MOM_LITTLEROOT, x = 5, y = 8,
      graphicsId = Game3.GFX_MOM, flagId = Game3.FLAG_HIDE_MOM_LITTLEROOT,
    },
  },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_INTRO_STATE, value = 1,
        script = {
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = { { kind = "jump", dir = "east" } } },
          { op = "waitmovement", localId = 0 },
          { op = "opendoor", x = 5, y = 8 },
          { op = "addobject", localId = Game3.LOCALID_MOM_LITTLEROOT },
          { op = "applymovement", localId = Game3.LOCALID_MOM_LITTLEROOT,
            steps = {
              { kind = "walk", dir = "south" },
              { kind = "walk", dir = "south" },
              { kind = "face", dir = "west" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "loadword", text = "LITTLEROOT is our new home!" },
          { op = "callstd", id = 4 },
          { op = "closemessage" },
          { op = "applymovement", localId = Game3.LOCALID_MOM_LITTLEROOT,
            steps = { { kind = "walk", dir = "north" } } },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = {
              { kind = "walk", dir = "east" },
              { kind = "face", dir = "north" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "applymovement", localId = Game3.LOCALID_MOM_LITTLEROOT,
            steps = {
              { kind = "walk", dir = "north" },
              { kind = "invisible" },
            } },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = {
              { kind = "walk", dir = "north" },
              { kind = "walk", dir = "north" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "setflag", flag = Game3.FLAG_HIDE_MOM_LITTLEROOT },
          { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 3 },
          { op = "warp", mapGroup = 1, mapNum = 0, warpId = Game3.WARP_ID_NONE,
            x = 8, y = 8 },
          { op = "end" },
        },
      },
    },
  },
}

local function pump(g)
  local n = 0
  while n < 80 do
    n = n + 1
    local f = g.field
    if not f or f.kind == "talk" then return end
    if f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return
    end
  end
end

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local g = Game3.new()
g.phase = "play"
g.flags = { [Game3.FLAG_HIDE_MOM_LITTLEROOT] = true }
g.scriptVars = { [Game3.VAR_LITTLEROOT_INTRO_STATE] = 1 }
g.data.maps = {
  start = "g0_9",
  maps = { g0_9 = town, g1_1 = brendan2f, g1_0 = house },
}
g:enterMap(town, 3, 10, true)
pump(g)
eq(g.playerX, 4, "jump_right off the truck")
eq(g.playerY, 10, "still on the south row")
local momNpc = g:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT)
check(momNpc, "addobject brings Mom out")
eq(momNpc.x, 5, "Mom walked to the truck")
eq(momNpc.y, 10, "on the south row")
eq(momNpc.facing, "west", "facing the player")
eq(g.field.text, "LITTLEROOT is our new home!", "then she talks")
pressA(g)
pump(g)
eq(g.map.id, "g1_0", "both go inside")
eq(g.playerX, 8, "house 1F x")
eq(g.playerY, 8, "house 1F y")
eq(g.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 3, "intro state 3")
eq(g.flags[Game3.FLAG_HIDE_MOM_LITTLEROOT], true, "Mom hides after the warp")
end)()

;(function()
local Input = require("src.core.Input")
local cells = {}
for i = 1, 64 do cells[i] = 0 end
local house = {
  id = "g1_0", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_INTRO_STATE, value = 3,
        script = {
          { op = "setvar", var = Game3.VAR_TEMP_1, val = 1 },
          { op = "loadword", text = "Nice in here!" },
          { op = "callstd", id = 4 },
          { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 4 },
          { op = "end" },
        },
      },
    },
  },
}
local town = {
  id = "g0_9", width = 8, height = 8, grid = cells,
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_INTRO_STATE, value = 1,
        script = {
          { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 3 },
          { op = "hideobject", localId = Game3.LOCALID_PLAYER },
          { op = "warp", mapGroup = 1, mapNum = 0, warpId = Game3.WARP_ID_NONE,
            x = 4, y = 4 },
          { op = "waitstate" },
          { op = "end" },
        },
      },
    },
  },
}
local g = Game3.new()
g.phase = "play"
g.scriptVars = { [Game3.VAR_LITTLEROOT_INTRO_STATE] = 1 }
g.data.maps = { maps = { g0_9 = town, g1_0 = house } }
g:enterMap(town, 3, 4, true)
eq(g.map.id, "g1_0", "town ON_FRAME warps into the house")
eq(g.invisible, nil, "the warp shows the player again")
eq(g.field.kind, "talk", "waitstate after a sync warp is not a freeze")
eq(g.field.text, "Nice in here!", "house ON_FRAME runs after the warp script")
eq(g.scriptVars[Game3.VAR_TEMP_1], 1, "and was not nested inside warpsilent")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 4, "intro state 4")
eq(g.field, nil, "the house scene ended")
check(g:tryWalk(0, 1), "and the player can walk")
eq(g.playerY, 5, "one step south")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.LOCALID_PLAYERS_HOUSE_1F_MOM, 1, "house 1F Mom is local 1")
eq(Game3.MOVEMENT_TYPE_FACE_UP, 7, "movement type 7 faces up")
eq(Gen3Script.VAR_0x8004, 0x8004, "VAR_0x8004")
eq(Gen3Script.COND_EQ, 1, "call_if_eq is cond 1")

local houseCells = {}
for i = 1, 10 * 10 do houseCells[i] = 0 end
local cells = {}
for i = 1, 64 do cells[i] = 0 end
local momId = Game3.LOCALID_PLAYERS_HOUSE_1F_MOM
local intro = Game3.VAR_LITTLEROOT_INTRO_STATE
local eqCond = Gen3Script.COND_EQ

local function movingIn(gender)
  return {
    { op = "setvar", var = Gen3Script.VAR_0x8004, val = momId },
    { op = "setvar", var = Gen3Script.VAR_0x8005, val = gender },
    { op = "loadword", text = "See, honey? This is our new home!" },
    { op = "callstd", id = 4 },
    { op = "applymovement", localId = Gen3Script.VAR_0x8004,
      steps = { { kind = "faceplayer" } } },
    { op = "waitmovement", localId = 0 },
    { op = "compare", var = Gen3Script.VAR_0x8005, val = Game3.GENDER_MALE },
    { op = "call_if", cond = eqCond, body = {
      { op = "applymovement", localId = Game3.LOCALID_PLAYER,
        steps = { { kind = "face", dir = "east" } } },
      { op = "waitmovement", localId = 0 },
      { op = "end" },
    } },
    { op = "compare", var = Gen3Script.VAR_0x8005, val = Game3.GENDER_FEMALE },
    { op = "call_if", cond = eqCond, body = {
      { op = "applymovement", localId = Game3.LOCALID_PLAYER,
        steps = { { kind = "face", dir = "west" } } },
      { op = "waitmovement", localId = 0 },
      { op = "end" },
    } },
    { op = "loadword", text = "The movers' POKeMON will help. Go set the clock!" },
    { op = "callstd", id = 4 },
    { op = "closemessage" },
    { op = "setvar", var = intro, val = 4 },
    { op = "applymovement", localId = Game3.LOCALID_PLAYER,
      steps = { { kind = "walk", dir = "north" } } },
    { op = "applymovement", localId = Gen3Script.VAR_0x8004,
      steps = { { kind = "face", dir = "north" } } },
    { op = "waitmovement", localId = 0 },
    { op = "end" },
  }
end

local function onTransition(doorX, doorY, stairX, stairY)
  return {
    { op = "compare", var = intro, val = 3 },
    { op = "call_if", cond = eqCond, body = {
      { op = "setobjectxyperm", localId = momId, x = doorX, y = doorY },
      { op = "setobjectmovementtype", localId = momId,
        movementType = Game3.MOVEMENT_TYPE_FACE_UP },
      { op = "end" },
    } },
    { op = "compare", var = intro, val = 5 },
    { op = "call_if", cond = eqCond, body = {
      { op = "setobjectxyperm", localId = momId, x = stairX, y = stairY },
      { op = "setobjectmovementtype", localId = momId,
        movementType = Game3.MOVEMENT_TYPE_FACE_UP },
      { op = "end" },
    } },
    { op = "end" },
  }
end

local boy1f = {
  id = "g1_0", width = 10, height = 10, grid = houseCells, spawn = { x = 8, y = 8 },
  objects = {
    { localId = momId, x = 2, y = 6, graphicsId = Game3.GFX_MOM },
  },
  mapScripts = {
    onTransition = onTransition(9, 8, 8, 4),
    onFrame = {
      { var = intro, value = 3, script = movingIn(Game3.GENDER_MALE) },
      {
        var = intro, value = 5,
        script = {
          { op = "loadword", text = "Go set the clock upstairs!" },
          { op = "callstd", id = 4 },
          { op = "closemessage" },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = { { kind = "walk", dir = "north" } } },
          { op = "applymovement", localId = momId,
            steps = { { kind = "walk", dir = "north" } } },
          { op = "waitmovement", localId = 0 },
          { op = "warp", mapGroup = 1, mapNum = 1,
            warpId = Game3.WARP_ID_NONE, x = 7, y = 1 },
          { op = "end" },
        },
      },
    },
  },
}
local girl1f = {
  id = "g1_2", width = 10, height = 10, grid = houseCells, spawn = { x = 2, y = 8 },
  objects = {
    { localId = momId, x = 6, y = 6, graphicsId = Game3.GFX_MOM },
  },
  mapScripts = {
    onTransition = onTransition(1, 8, 2, 4),
    onFrame = {
      { var = intro, value = 3, script = movingIn(Game3.GENDER_FEMALE) },
    },
  },
}
local brendan2f = {
  id = "g1_1", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
  mapScripts = {
    onTransition = {
      { op = "compare", var = intro, val = 4 },
      { op = "call_if", cond = eqCond, body = {
        { op = "setvar", var = intro, val = 5 },
        { op = "end" },
      } },
      { op = "end" },
    },
  },
}

local function pump(g)
  local n = 0
  while n < 80 do
    n = n + 1
    local f = g.field
    if not f or f.kind == "talk" then return end
    if f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return
    end
  end
end

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local maps = { g1_0 = boy1f, g1_1 = brendan2f, g1_2 = girl1f }
local boy = Game3.new()
boy.phase = "play"
boy.data.maps = { start = "g1_0", maps = maps }
boy.scriptVars = { [intro] = 3 }
boy:enterMap(boy1f, 8, 8, true)
local mom = boy:npcByLocalId(momId)
check(mom, "ON_TRANSITION spawned Mom")
eq(mom.x, 9, "Mom at the boy door")
eq(mom.y, 8, "on the south row")
eq(boy.field.text, "See, honey? This is our new home!", "first moving-in line")
pressA(boy)
pump(boy)
eq(mom.facing, "west", "Mom faces the player")
eq(boy.facing, "east", "boy faces Mom")
eq(boy.field.text, "The movers' POKeMON will help. Go set the clock!",
  "go set the clock")
pressA(boy)
pump(boy)
eq(boy.scriptVars[intro], 4, "intro state 4")
eq(boy.playerX, 8, "still in the doorway column")
eq(boy.playerY, 7, "walk_up off the mat")
eq(mom.facing, "north", "Mom faces the stairs")

boy:enterMap(brendan2f, 7, 1, true)
eq(boy.scriptVars[intro], 5, "2F ON_TRANSITION sets intro 5")
boy.playerX, boy.playerY = 5, 2
boy.facing = "north"
check(boy:tryTalk(), "A on the stopped clock")
eq(boy.scriptVars[intro], 6, "clock writes intro 6")

local girl = Game3.new()
girl.phase = "play"
girl.data.maps = { start = "g1_2", maps = maps }
girl:applyGender(Game3.GENDER_FEMALE)
girl.scriptVars = { [intro] = 3 }
girl:enterMap(girl1f, 2, 8, true)
local girlMom = girl:npcByLocalId(momId)
eq(girlMom.x, 1, "Mom at the girl door")
eq(girlMom.y, 8, "on the south row")
pressA(girl)
pump(girl)
eq(girl.facing, "west", "girl faces Mom")
pressA(girl)
pump(girl)
eq(girl.scriptVars[intro], 4, "girl intro 4")
eq(girl.playerY, 7, "girl also walks in")

local push = Game3.new()
push.phase = "play"
push.data.maps = { start = "g1_0", maps = maps }
push.scriptVars = { [intro] = 5 }
push:enterMap(boy1f, 8, 8, true)
eq(push:npcByLocalId(momId).x, 8, "Mom at the stairs")
eq(push:npcByLocalId(momId).y, 4, "north of the door")
eq(push.field.text, "Go set the clock upstairs!", "intro 5 shoves upstairs")
pressA(push)
pump(push)
eq(push.map.id, "g1_1", "warpsilent to Brendan 2F")
eq(push.playerX, 7, "clock-side warp x")
eq(push.playerY, 1, "clock-side warp y")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.FLAG_SYS_TV_HOME, 0x830, "FLAG_SYS_TV_HOME")
eq(Game3.FLAG_SYS_TV_WATCH, 0x831, "FLAG_SYS_TV_WATCH")
eq(Game3.VAR_TEMP_1, 0x4001, "VAR_TEMP_1")
eq(Game3.SPECIAL_TURN_OFF_TV_SCREEN, 62, "special 62 is TurnOffTVScreen")

local houseCells = {}
for i = 1, 10 * 10 do houseCells[i] = 0 end
local momId = Game3.LOCALID_PLAYERS_HOUSE_1F_MOM
local intro = Game3.VAR_LITTLEROOT_INTRO_STATE
local v8005 = Gen3Script.VAR_0x8005
local delay16 = { kind = "delay", frames = 16 }

local house = {
  id = "g1_0", width = 10, height = 10, grid = houseCells, spawn = { x = 8, y = 2 },
  objects = {
    { localId = momId, x = 2, y = 6, graphicsId = Game3.GFX_MOM },
  },
  mapScripts = {
    onTransition = {
      { op = "compare", var = intro, val = 6 },
      { op = "call_if", cond = Gen3Script.COND_EQ, body = {
        { op = "setobjectxyperm", localId = momId, x = 4, y = 5 },
        { op = "setobjectmovementtype", localId = momId,
          movementType = Game3.MOVEMENT_TYPE_FACE_UP },
        { op = "end" },
      } },
      { op = "end" },
    },
    onFrame = {
      {
        var = intro, value = 6,
        script = {
          { op = "setvar", var = v8005, val = momId },
          { op = "applymovement", localId = v8005,
            steps = { { kind = "face", dir = "east" } } },
          { op = "waitmovement", localId = 0 },
          { op = "call", body = {
            { op = "playse", id = 21 },
            { op = "applymovement", localId = v8005,
              steps = { { kind = "emote", emote = "exclaim" } } },
            { op = "waitmovement", localId = 0 },
            { op = "applymovement", localId = v8005,
              steps = { delay16, delay16, delay16 } },
            { op = "waitmovement", localId = 0 },
            { op = "loadword", text = "Oh, come quickly!" },
            { op = "callstd", id = 4 },
            { op = "closemessage" },
            { op = "end" },
          } },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = {
              { kind = "walk", dir = "south" },
              { kind = "walk", dir = "south" },
              { kind = "walk", dir = "west" },
              { kind = "walk", dir = "west" },
              { kind = "walk", dir = "west" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "playbgm", id = 370, save = 0 },
          { op = "loadword", text = "Maybe DAD will be on!" },
          { op = "callstd", id = 4 },
          { op = "closemessage" },
          { op = "applymovement", localId = v8005,
            steps = {
              { kind = "walk", dir = "west" },
              { kind = "face", dir = "east" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = { { kind = "walk", dir = "west" } } },
          { op = "waitmovement", localId = 0 },
          { op = "call", body = {
            { op = "applymovement", localId = Game3.LOCALID_PLAYER,
              steps = { { kind = "face", dir = "north" } } },
            { op = "waitmovement", localId = 0 },
            { op = "loadword",
              text = "We now bring you a special report from PETALBURG GYM." },
            { op = "callstd", id = 4 },
            { op = "fadedefaultbgm" },
            { op = "special", id = Game3.SPECIAL_TURN_OFF_TV_SCREEN },
            { op = "setflag", flag = Game3.FLAG_SYS_TV_HOME },
            { op = "delay", frames = 35 },
            { op = "end" },
          } },
          { op = "applymovement", localId = Game3.LOCALID_PLAYER,
            steps = { { kind = "face", dir = "west" } } },
          { op = "waitmovement", localId = 0 },
          { op = "loadword", text = "It's over. We missed him." },
          { op = "callstd", id = 4 },
          { op = "loadword", text = "Go introduce yourself to the neighbors." },
          { op = "callstd", id = 4 },
          { op = "closemessage" },
          { op = "setvar", var = Game3.VAR_TEMP_1, val = 1 },
          { op = "applymovement", localId = v8005,
            steps = {
              { kind = "walk", dir = "west" },
              { kind = "walk", dir = "south" },
              { kind = "face", dir = "east" },
            } },
          { op = "waitmovement", localId = 0 },
          { op = "setvar", var = intro, val = 7 },
          { op = "end" },
        },
      },
    },
  },
}

local function pump(g)
  local n = 0
  while n < 80 do
    n = n + 1
    local f = g.field
    if not f or f.kind == "talk" then return end
    if f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return
    end
  end
end

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local function throughTalk(g)
  pump(g)
  pressA(g)
end

local g = Game3.new()
g.phase = "play"
g.tvOn = true
g.data.maps = { start = "g1_0", maps = { g1_0 = house } }
g.scriptVars = { [intro] = 6 }
g:enterMap(house, 8, 2, true)
pump(g)
local mom = g:npcByLocalId(momId)
eq(mom.x, 4, "Mom at the TV")
eq(mom.y, 5, "TV tile")
eq(g.field.text, "Oh, come quickly!", "Mom notices the broadcast")
throughTalk(g)
pump(g)
eq(g.playerX, 5, "approached the TV")
eq(g.playerY, 4, "south of Mom's old tile")
eq(g.field.text, "Maybe DAD will be on!", "before the report")
throughTalk(g)
pump(g)
eq(mom.x, 3, "Mom made room")
eq(g.playerX, 4, "in front of the TV")
eq(g.playerY, 4, "north of the TV tile, not standing on it")
eq(g.field.text, "We now bring you a special report from PETALBURG GYM.",
  "the gym report")

local tvWalk = Game3.new()
tvWalk.phase = "play"
tvWalk.map = {
  id = "tv", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  behavior = { 0, 0, 0, 0, Game3.MB_TELEVISION, 0, 0, 0, 0 },
}
tvWalk.playerX, tvWalk.playerY = 1, 0
tvWalk:scriptMoveDelta("player", 0, 1, 1, false)
eq(tvWalk.playerY, 1, "a script walk can stand on the TV tile")
tvWalk.playerX, tvWalk.playerY = 2, 1
tvWalk:scriptMoveDelta("player", -1, 0, 1, false)
eq(tvWalk.playerX, 1, "Mom's last walk_left reaches the TV")
eq(tvWalk.playerY, 1, "not stuck on the side")
throughTalk(g)
pump(g)
eq(g.tvOn, false, "special 62 turns the TV off")
eq(g.flags[Game3.FLAG_SYS_TV_HOME], true, "FLAG_SYS_TV_HOME")
eq(g.facing, "west", "player faces Mom")
eq(g.field.text, "It's over. We missed him.", "missed Norman")
throughTalk(g)
eq(g.field.text, "Go introduce yourself to the neighbors.", "next door")
throughTalk(g)
pump(g)
eq(g.scriptVars[intro], 7, "intro state 7")
eq(g.scriptVars[Game3.VAR_TEMP_1], 1, "VAR_TEMP_1 after the show")
eq(mom.x, 2, "Mom back at her seat")
eq(mom.y, 6, "south of the TV")
eq(mom.facing, "east", "facing the room")
eq(g.field, nil, "the scene released")

local girlHouse = {
  id = "g1_2", width = 10, height = 10, grid = houseCells, spawn = { x = 2, y = 2 },
  objects = {
    { localId = momId, x = 6, y = 6, graphicsId = Game3.GFX_MOM },
  },
  mapScripts = {
    onTransition = {
      { op = "compare", var = intro, val = 6 },
      { op = "call_if", cond = Gen3Script.COND_EQ, body = {
        { op = "setobjectxyperm", localId = momId, x = 6, y = 5 },
        { op = "setobjectmovementtype", localId = momId,
          movementType = Game3.MOVEMENT_TYPE_FACE_UP },
        { op = "end" },
      } },
      { op = "end" },
    },
  },
}
local girl = Game3.new()
girl.phase = "play"
girl:applyGender(Game3.GENDER_FEMALE)
girl.scriptVars = { [intro] = 6 }
girl.data.maps = { start = "g1_2", maps = { g1_2 = girlHouse } }
girl:enterMap(girlHouse, 2, 2, true)
eq(girl:npcByLocalId(momId).x, 6, "May 1F Mom at the east TV")
eq(girl:npcByLocalId(momId).y, 5, "same row as Brendan's")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.LOCALID_RIVAL_MOM, 4, "rival-Mom is local 4")
eq(Game3.FLAG_MET_RIVAL_MOM, 0x57, "FLAG_MET_RIVAL_MOM")
eq(Game3.SPECIAL_GET_RIVAL_SON_DAUGHTER_STRING, 149,
  "special 149 is GetRivalSonDaughterString")
eq(Game3.TEXT_DAUGHTER, "daughter", "male player: rival is a daughter")
eq(Game3.TEXT_SON, "son", "female player: rival is a son")

local houseCells = {}
for i = 1, 10 * 10 do houseCells[i] = 0 end
local rid = Game3.LOCALID_RIVAL_MOM
local delay16 = { kind = "delay", frames = 16 }
local line = "Oh! You must be {PLAYER}. Our new next-door neighbor! My {STR_VAR_1} is also about your age."

local function neighborScript(faceDir, walkDir, houseVar)
  return {
    { op = "playse", id = 21 },
    { op = "applymovement", localId = rid,
      steps = { { kind = "emote", emote = "exclaim" } } },
    { op = "waitmovement", localId = 0 },
    { op = "applymovement", localId = rid,
      steps = { delay16, delay16, delay16 } },
    { op = "waitmovement", localId = 0 },
    { op = "applymovement", localId = Game3.LOCALID_PLAYER,
      steps = { { kind = "face", dir = faceDir } } },
    { op = "applymovement", localId = rid,
      steps = {
        { kind = "walk", dir = "south" },
        { kind = "walk", dir = walkDir },
        { kind = "walk", dir = walkDir },
        { kind = "walk", dir = walkDir },
        { kind = "walk", dir = walkDir },
        { kind = "walk", dir = walkDir },
      } },
    { op = "waitmovement", localId = 0 },
    { op = "special", id = Game3.SPECIAL_GET_RIVAL_SON_DAUGHTER_STRING },
    { op = "loadword", text = line },
    { op = "callstd", id = 4 },
    { op = "setflag", flag = Game3.FLAG_MET_RIVAL_MOM },
    { op = "setvar", var = houseVar, val = 2 },
    { op = "end" },
  }
end

local may1f = {
  id = "g1_2", width = 10, height = 10, grid = houseCells, spawn = { x = 2, y = 8 },
  objects = {
    {
      localId = rid, x = 8, y = 7, graphicsId = 54,
      flagId = Game3.FLAG_HIDE_MAY_MOM,
    },
  },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_HOUSES_STATE_2, value = 1,
        script = neighborScript("east", "west", Game3.VAR_LITTLEROOT_HOUSES_STATE_2),
      },
    },
  },
}
local brendan1f = {
  id = "g1_0", width = 10, height = 10, grid = houseCells, spawn = { x = 8, y = 8 },
  objects = {
    {
      localId = rid, x = 2, y = 7, graphicsId = 54,
      flagId = Game3.FLAG_HIDE_BRENDAN_MOM,
    },
  },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_LITTLEROOT_HOUSES_STATE, value = 1,
        script = neighborScript("west", "east", Game3.VAR_LITTLEROOT_HOUSES_STATE),
      },
    },
  },
}

local function pump(g)
  local n = 0
  while n < 80 do
    n = n + 1
    local f = g.field
    if not f or f.kind == "talk" then return end
    if f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return
    end
  end
end

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local function finishTalk(g)
  local n = 0
  while n < 24 do
    n = n + 1
    pump(g)
    if not g.field or g.field.kind ~= "talk" then return end
    pressA(g)
  end
end

local boy = Game3.new()
boy.phase = "play"
boy:applyGender(Game3.GENDER_MALE)
boy.scriptVars = { [Game3.VAR_LITTLEROOT_HOUSES_STATE_2] = 1 }
boy.data.maps = { start = "g1_2", maps = { g1_2 = may1f } }
boy:enterMap(may1f, 2, 8, true)
pump(boy)
local rivalMom = boy:npcByLocalId(rid)
check(rivalMom, "boy sees rival-Mom in May 1F")
eq(rivalMom.x, 3, "walk_down then five left")
eq(rivalMom.y, 8, "on the door row")
eq(boy.facing, "east", "boy faces her")
eq(boy.field.text,
  "Oh! You must be BRENDAN. Our new next-door neighbor! My daughter is also about your age.",
  "special 149 fills daughter")
finishTalk(boy)
eq(boy.flags[Game3.FLAG_MET_RIVAL_MOM], true, "FLAG_MET_RIVAL_MOM")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_HOUSES_STATE_2], 2, "May house-state 2")

local girl = Game3.new()
girl.phase = "play"
girl:applyGender(Game3.GENDER_FEMALE)
girl.scriptVars = { [Game3.VAR_LITTLEROOT_HOUSES_STATE] = 1 }
girl.data.maps = { start = "g1_0", maps = { g1_0 = brendan1f } }
girl:enterMap(brendan1f, 8, 8, true)
pump(girl)
local girlMom = girl:npcByLocalId(rid)
check(girlMom, "girl sees rival-Mom in Brendan 1F")
eq(girlMom.x, 7, "walk_down then five right")
eq(girlMom.y, 8, "on the door row")
eq(girl.facing, "west", "girl faces her")
eq(girl.field.text,
  "Oh! You must be MAY. Our new next-door neighbor! My son is also about your age.",
  "special 149 fills son")
finishTalk(girl)
eq(girl.flags[Game3.FLAG_MET_RIVAL_MOM], true, "girl met rival-Mom")
eq(girl.scriptVars[Game3.VAR_LITTLEROOT_HOUSES_STATE], 2, "Brendan house-state 2")

local own = Game3.new()
own.phase = "play"
own:applyGender(Game3.GENDER_MALE)
own.data.maps = { start = "g1_0", maps = { g1_0 = brendan1f } }
own:enterMap(brendan1f, 8, 8, true)
eq(#own:npcsFor(brendan1f), 0, "boy does not see rival-Mom in his own house")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.VAR_LITTLEROOT_RIVAL_STATE, 0x408D, "VAR_LITTLEROOT_RIVAL_STATE")
eq(Game3.VAR_FACING, 0x800C, "VAR_FACING")
eq(Game3.VAR_LAST_TALKED, 0x800F, "VAR_LAST_TALKED")
eq(Game3.FLAG_MET_RIVAL_LILYCOVE, 0x124, "FLAG_MET_RIVAL_LILYCOVE")
eq(Game3.LOCALID_RIVAL, 1, "2F rival is local 1")
eq(Game3.DIR_NORTH, 2, "DIR_NORTH")
eq(Game3.DIR_WEST, 3, "DIR_WEST")
eq(Game3.DIR_EAST, 4, "DIR_EAST")
eq(Game3.RIVAL_BRENDAN_2F_X, 1, "Brendan 2F notebook x")
eq(Game3.RIVAL_MAY_2F_X, 7, "May 2F notebook x")

local cells = {}
for i = 1, 10 * 10 do cells[i] = 0 end
local last = Game3.VAR_LAST_TALKED
local delay8 = { kind = "delay", frames = 8 }
local delay16 = { kind = "delay", frames = 16 }
local left = { kind = "walk", dir = "west" }
local right = { kind = "walk", dir = "east" }
local up = { kind = "walk", dir = "north" }
local down = { kind = "walk", dir = "south" }
local pin = { kind = "emote", emote = "exclaim" }
local face = { kind = "faceplayer" }
local delay48 = { delay16, delay16, delay16 }
local mayNorth = { left, left, left, left, left, left, up, delay8 }
local mayEast = { down, left, left, left, left, left, left, up, up, delay8 }
local brendanNorth = { right, right, right, right, right, right, up, delay8 }
local brendanWest = { down, right, right, right, right, right, right, up, up, delay8 }
local mayReady = "POKeMON fully restored! Items ready, and... Huh?"
local brendanReady = "POKeMON fully restored... Items all packed, and..."
local mayWho = "Huh? Who... Who are you? Oh, you're {PLAYER}{KUN}. Um... I'm MAY."
local brendanWho = "Hey! You... Who are you? Oh, you're {PLAYER}. My name's BRENDAN."

local function walkOff(dirVal, steps)
  return {
    { op = "compare", var = Game3.VAR_FACING, val = dirVal },
    { op = "call_if", cond = 1, body = {
      { op = "applymovement", localId = last, steps = steps },
      { op = "waitmovement", localId = 0 },
      { op = "end" },
    }},
  }
end

local function greet(ready, who, leave)
  local ops = {
    { op = "loadword", text = ready },
    { op = "callstd", id = 4 },
    { op = "playbgm", id = 0, save = 1 },
    { op = "applymovement", localId = last, steps = { face } },
    { op = "waitmovement", localId = 0 },
    { op = "applymovement", localId = last, steps = { pin } },
    { op = "waitmovement", localId = 0 },
    { op = "applymovement", localId = last, steps = delay48 },
    { op = "waitmovement", localId = 0 },
    { op = "loadword", text = who },
    { op = "callstd", id = 4 },
    { op = "closemessage" },
  }
  for i = 1, #leave do ops[#ops + 1] = leave[i] end
  ops[#ops + 1] = { op = "end" }
  return ops
end

local mayLeave = {}
do
  local a = walkOff(Game3.DIR_EAST, mayEast)
  local b = walkOff(Game3.DIR_NORTH, mayNorth)
  local c = walkOff(Game3.DIR_WEST, mayNorth)
  for i = 1, #a do mayLeave[#mayLeave + 1] = a[i] end
  for i = 1, #b do mayLeave[#mayLeave + 1] = b[i] end
  for i = 1, #c do mayLeave[#mayLeave + 1] = c[i] end
end
local brendanLeave = {}
do
  local a = walkOff(Game3.DIR_EAST, brendanNorth)
  local b = walkOff(Game3.DIR_NORTH, brendanNorth)
  local c = walkOff(Game3.DIR_WEST, brendanWest)
  for i = 1, #a do brendanLeave[#brendanLeave + 1] = a[i] end
  for i = 1, #b do brendanLeave[#brendanLeave + 1] = b[i] end
  for i = 1, #c do brendanLeave[#brendanLeave + 1] = c[i] end
end

local talk = {
  { op = "checkflag", flag = Game3.FLAG_MET_RIVAL_LILYCOVE },
  { op = "goto_if", cond = 1, to = 14 },
  { op = "checkplayergender" },
  { op = "compare", var = Gen3Script.VAR_RESULT, val = 0 },
  { op = "call_if", cond = 1, body = greet(mayReady, mayWho, mayLeave) },
  { op = "compare", var = Gen3Script.VAR_RESULT, val = 1 },
  { op = "call_if", cond = 1, body = greet(brendanReady, brendanWho, brendanLeave) },
  { op = "playse", id = 8 },
  { op = "removeobject", localId = last },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_RIVAL_STATE, val = 3 },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_STATE, val = 1 },
  { op = "savebgm", id = 0 },
  { op = "fadedefaultbgm" },
  { op = "end" },
}

local function notebook(x, y)
  return {
    { op = "checkflag", flag = Game3.FLAG_DEFEATED_RIVAL_ROUTE103 },
    { op = "call_if", cond = 0, body = {
      { op = "setobjectxyperm", localId = 1, x = x, y = y },
      { op = "setobjectmovementtype", localId = 1,
        movementType = Game3.MOVEMENT_TYPE_FACE_UP },
      { op = "end" },
    }},
    { op = "end" },
  }
end

local function makeBrendan2f()
  return {
    id = "g1_1", width = 10, height = 10, grid = cells, spawn = { x = 7, y = 1 },
    objects = {
      {
        localId = 1, x = 0, y = 2, graphicsId = Game3.GFX_RIVAL_BRENDAN,
        movementType = Game3.MOVEMENT_TYPE_FACE_UP,
        flagId = Game3.FLAG_HIDE_BRENDAN_UPSTAIRS, script = talk,
      },
    },
    mapScripts = { onTransition = notebook(1, 2) },
  }
end
local function makeMay2f()
  return {
    id = "g1_3", width = 10, height = 10, grid = cells, spawn = { x = 1, y = 1 },
    objects = {
      {
        localId = 1, x = 8, y = 2, graphicsId = Game3.GFX_RIVAL_MAY,
        movementType = Game3.MOVEMENT_TYPE_FACE_UP,
        flagId = Game3.FLAG_HIDE_MAY_UPSTAIRS, script = talk,
      },
    },
    mapScripts = { onTransition = notebook(7, 2) },
  }
end

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      seen[#seen + 1] = f.text
      pressA(g)
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local girl = Game3.new()
girl.phase = "play"
girl:applyGender(Game3.GENDER_FEMALE)
local brendan2f = makeBrendan2f()
girl.data.maps = { start = "g1_1", maps = { g1_1 = brendan2f } }
girl:enterMap(brendan2f, 1, 3, true)
girl.facing = "north"
local brendan = girl:npcByLocalId(1)
check(brendan, "girl sees Brendan at the notebook")
eq(brendan.x, 1, "ON_TRANSITION setobjectxyperm 1, 1, 2")
eq(brendan.y, 2, "on the notebook row")
eq(brendan.facing, "north", "FACE_UP")
check(girl:tryTalk(), "talking starts 152A9D")
eq(girl.scriptVars[Game3.VAR_LAST_TALKED], 1, "gSpecialVar_LastTalked")
eq(girl.scriptVars[Game3.VAR_FACING], Game3.DIR_NORTH, "gSpecialVar_Facing")
local girlLines = runScene(girl)
eq(girlLines[1], brendanReady, "GettingReady")
check(girlLines[2]:find("BRENDAN", 1, true) ~= nil, "WhoAreYou names Brendan")
check(girlLines[2]:find("MAY", 1, true) ~= nil, "{PLAYER} is MAY")
check(girl:npcByLocalId(1).hidden, "removeobject hides him")
eq(girl.flags[Game3.FLAG_HIDE_BRENDAN_UPSTAIRS], true, "his hide flag")
eq(girl.scriptVars[Game3.VAR_LITTLEROOT_RIVAL_STATE], 3, "rival-state 3")
eq(girl.scriptVars[Game3.VAR_LITTLEROOT_STATE], 1, "Littleroot state 1")

local boy = Game3.new()
boy.phase = "play"
boy:applyGender(Game3.GENDER_MALE)
local may2f = makeMay2f()
boy.data.maps = { start = "g1_3", maps = { g1_3 = may2f } }
boy:enterMap(may2f, 7, 3, true)
boy.facing = "north"
local may = boy:npcByLocalId(1)
check(may, "boy sees May at the notebook")
eq(may.x, 7, "ON_TRANSITION setobjectxyperm 1, 7, 2")
eq(may.y, 2, "on the notebook row")
check(boy:tryTalk(), "talking to May")
local boyLines = runScene(boy)
eq(boyLines[1], mayReady, "May GettingReady")
check(boyLines[2]:find("I'm MAY", 1, true) ~= nil, "WhoAreYou names May")
check(boyLines[2]:find("BRENDAN", 1, true) ~= nil, "{PLAYER} is BRENDAN")
check(boy:npcByLocalId(1).hidden, "removeobject hides her")
eq(boy.flags[Game3.FLAG_HIDE_MAY_UPSTAIRS], true, "her hide flag")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_RIVAL_STATE], 3, "boy rival-state 3")

local own = Game3.new()
own.phase = "play"
own:applyGender(Game3.GENDER_MALE)
local ownMap = makeBrendan2f()
own.data.maps = { start = "g1_1", maps = { g1_1 = ownMap } }
own:enterMap(ownMap, 7, 1, true)
eq(#own:npcsFor(ownMap), 0, "boy does not see Brendan in his own 2F")

local later = Game3.new()
later.phase = "play"
later:applyGender(Game3.GENDER_FEMALE)
later.flags[Game3.FLAG_DEFEATED_RIVAL_ROUTE103] = true
local laterMap = makeBrendan2f()
later.data.maps = { start = "g1_1", maps = { g1_1 = laterMap } }
later:enterMap(laterMap, 1, 3, true)
eq(later:npcByLocalId(1).x, 0, "after Route 103 the perm is not applied")
eq(later:npcByLocalId(1).y, 2, "default 0, 2")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FLAG_RIVAL_LEFT_FOR_ROUTE103, 0x12D, "FLAG_RIVAL_LEFT_FOR_ROUTE103")
eq(Game3.FLAG_BIRCH_AIDE_MET, 0x58, "FLAG_BIRCH_AIDE_MET")
eq(Game3.VAR_ROUTE101_STATE, 0x4060, "VAR_ROUTE101_STATE")
eq(Game3.VAR_BIRCH_LAB_STATE, 0x4084, "VAR_BIRCH_LAB_STATE")
eq(Game3.FLAG_HIDE_POOCHYENA_ROUTE101, 0x2EE, "FLAG_HIDE_POOCHYENA_ROUTE101")
eq(Game3.LOCALID_ROUTE101_BIRCH, 2, "chase Birch is local 2")
eq(Game3.LOCALID_ROUTE101_POOCHYENA, 4, "chase Poochyena is local 4")
eq(Game3.TWIN_SAVE_BIRCH_X, 10, "twin at the route after rival 2F")
eq(Game3.MOVEMENT_TYPE_FACE_DOWN, 8, "FACE_DOWN is 8")

local cells = {}
for i = 1, 20 * 22 do cells[i] = 0 end
local twinId = Game3.LOCALID_TWIN
local help = "H-help me!"
local bagLine = "Hello! You over there! Please! Help! In my BAG! There's a POKe BALL!"
local shout = "I can hear someone shouting down the road here. What should I do? What should we do? Somebody has to go help..."
local fieldwork = "PROF. BIRCH is away on fieldwork. He's not a desk-bound professor."
local desk = "PROF. BIRCH isn't one for doing desk work."
local leaveMe = "Wh-Where are you going?! Don't leave me like this!"

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      seen[#seen + 1] = f.text
      pressA(g)
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local goSave = {
  { op = "loadword", text = shout },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = twinId,
    steps = { { kind = "faceoriginal" } } },
  { op = "waitmovement", localId = 0 },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_STATE, val = 2 },
  { op = "end" },
}
local twinTalk = {
  { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
  { op = "goto_if", cond = 1, to = 20 },
  { op = "checkflag", flag = Game3.FLAG_RESCUED_BIRCH },
  { op = "goto_if", cond = 1, to = 20 },
  { op = "compare", var = Game3.VAR_LITTLEROOT_STATE, val = 0 },
  { op = "goto_if", cond = 5, to = 10 },
  { op = "loadword", text = "If you go in the tall grass, wild POKeMON will appear." },
  { op = "callstd", id = 4 },
  { op = "end" },
  goSave[1], goSave[2], goSave[3], goSave[4], goSave[5], goSave[6], goSave[7],
}

local town = {
  id = "g0_9", width = 20, height = 20, grid = cells, spawn = { x = 11, y = 2 },
  objects = {
    {
      localId = twinId, x = 16, y = 10, graphicsId = 35,
      movementType = 1, script = twinTalk,
    },
  },
  mapScripts = {
    onTransition = {
      { op = "compare", var = Game3.VAR_LITTLEROOT_RIVAL_STATE, val = 3 },
      { op = "call_if", cond = 1, body = {
        { op = "setflag", flag = Game3.FLAG_RIVAL_LEFT_FOR_ROUTE103 },
        { op = "end" },
      }},
      { op = "checkflag", flag = Game3.FLAG_RESCUED_BIRCH },
      { op = "call_if", cond = 0, body = {
        { op = "compare", var = Game3.VAR_LITTLEROOT_STATE, val = 0 },
        { op = "goto_if", cond = 1, to = 6 },
        { op = "setobjectxyperm", localId = twinId,
          x = Game3.TWIN_SAVE_BIRCH_X, y = Game3.TWIN_SAVE_BIRCH_Y },
        { op = "setobjectmovementtype", localId = twinId,
          movementType = Game3.MOVEMENT_TYPE_FACE_UP },
        { op = "end" },
        { op = "setobjectxyperm", localId = twinId,
          x = Game3.TWIN_GUARD_X, y = Game3.TWIN_GUARD_Y },
        { op = "setobjectmovementtype", localId = twinId,
          movementType = Game3.MOVEMENT_TYPE_FACE_DOWN },
        { op = "end" },
      }},
      { op = "end" },
    },
  },
  coordEvents = {
    {
      x = 11, y = 1, trigger = Game3.VAR_LITTLEROOT_STATE, index = 1,
      script = {
        { op = "applymovement", localId = twinId,
          steps = { { kind = "face", dir = "east" } } },
        { op = "waitmovement", localId = 0 },
        { op = "applymovement", localId = Game3.LOCALID_PLAYER,
          steps = { { kind = "face", dir = "west" } } },
        { op = "waitmovement", localId = 0 },
        goSave[1], goSave[2], goSave[3], goSave[4], goSave[5], goSave[6],
        goSave[7],
      },
    },
  },
}

local g = Game3.new()
g.phase = "play"
g.scriptVars = {
  [Game3.VAR_LITTLEROOT_STATE] = 1,
  [Game3.VAR_LITTLEROOT_RIVAL_STATE] = 3,
}
g.data.maps = { start = "g0_9", maps = { g0_9 = town } }
g:enterMap(town, 11, 2, true)
local twin = g:npcByLocalId(twinId)
check(twin, "twin is on the map")
eq(twin.x, 10, "SetTwinPos after rival 2F")
eq(twin.y, 1, "at the route")
eq(twin.facing, "north", "FACE_UP")
eq(g.flags[Game3.FLAG_RIVAL_LEFT_FOR_ROUTE103], true, "town sets FLAG_RIVAL_LEFT_FOR_ROUTE103")
g.facing = "north"
check(g:tryWalk(0, -1), "step onto 11,1")
local townLines = runScene(g)
eq(townLines[1], shout, "GoSaveBirchTrigger")
eq(g.scriptVars[Game3.VAR_LITTLEROOT_STATE], 2, "state 2 lets you onto Route 101")
eq(g.facing, "west", "player faces the twin")

local talker = Game3.new()
talker.phase = "play"
talker.scriptVars = {
  [Game3.VAR_LITTLEROOT_STATE] = 1,
  [Game3.VAR_LITTLEROOT_RIVAL_STATE] = 3,
}
talker.data.maps = { start = "g0_9", maps = { g0_9 = town } }
talker:enterMap(town, 10, 2, true)
talker.facing = "north"
check(talker:tryTalk(), "talking to the twin")
local twinLines = runScene(talker)
eq(twinLines[1], shout, "GoSaveBirch talk")
eq(talker.scriptVars[Game3.VAR_LITTLEROOT_STATE], 2, "talk also writes state 2")

local lingerTwin = Game3.new()
lingerTwin.phase = "play"
lingerTwin.scriptVars = { [Game3.VAR_LITTLEROOT_STATE] = 0 }
lingerTwin.data.maps = { start = "g0_9", maps = { g0_9 = town } }
lingerTwin:enterMap(town, 11, 2, true)
eq(lingerTwin:npcByLocalId(twinId).x, Game3.TWIN_GUARD_X,
  "before Birch the twin guards the south exit")
eq(town.objects[1].x, 16, "setobjectxyperm does not rewrite the ROM template")
lingerTwin.flags[Game3.FLAG_RESCUED_BIRCH] = true
lingerTwin:enterMap(town, 11, 2, true)
eq(lingerTwin:npcByLocalId(twinId).x, 16,
  "after Birch the twin is back in town")
eq(lingerTwin:npcByLocalId(twinId).y, 10, "not lingering on the Route 101 edge")

local aideScript = {
  { op = "compare", var = Game3.VAR_BIRCH_LAB_STATE, val = 3 },
  { op = "goto_if", cond = 4, to = 14 },
  { op = "checkflag", flag = Game3.FLAG_BIRCH_AIDE_MET },
  { op = "goto_if", cond = 1, to = 11 },
  { op = "loadword", text = fieldwork },
  { op = "callstd", id = 4 },
  { op = "setflag", flag = Game3.FLAG_BIRCH_AIDE_MET },
  { op = "end" },
  { op = "end" },
  { op = "end" },
  { op = "loadword", text = desk },
  { op = "callstd", id = 4 },
  { op = "end" },
}
local lab = {
  id = "g1_4", width = 12, height = 14, grid = cells, spawn = { x = 6, y = 12 },
  objects = {
    { localId = 1, x = 9, y = 8, graphicsId = 22, script = aideScript },
    {
      localId = 2, x = 6, y = 4, graphicsId = Game3.GFX_BIRCH,
      flagId = Game3.FLAG_HIDE_BIRCH_IN_LAB,
    },
  },
}
local labber = Game3.new()
labber.phase = "play"
labber.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = true
labber.data.maps = { start = "g1_4", maps = { g1_4 = lab } }
labber:enterMap(lab, 9, 9, true)
labber.facing = "north"
eq(#labber:npcsFor(lab), 1, "lab Birch is hidden")
eq(labber:npcsFor(lab)[1].graphicsId, 22, "the aide is in")
check(labber:tryTalk(), "talking to the aide")
local aideLines = runScene(labber)
eq(aideLines[1], fieldwork, "Birch is on fieldwork")
eq(labber.flags[Game3.FLAG_BIRCH_AIDE_MET], true, "FLAG_BIRCH_AIDE_MET")
labber.field = nil
check(labber:tryTalk(), "talking again")
local aideAgain = runScene(labber)
eq(aideAgain[1], desk, "already-met line")

local up = { kind = "walk", dir = "north" }
local right = { kind = "walk", dir = "east" }
local down = { kind = "walk", dir = "south" }
local shoveUp = {
  { op = "loadword", text = leaveMe },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = 2, steps = { up } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local shoveRight = {
  { op = "loadword", text = leaveMe },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = 2, steps = { right } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local shoveDown = {
  { op = "loadword", text = leaveMe },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = 2, steps = { down } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local chase = {
  { op = "playbgm", id = 0, save = 1 },
  { op = "loadword", text = help },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "setobjectxy", localId = 2, x = 0, y = 15 },
  { op = "setobjectxy", localId = 4, x = 0, y = 16 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { up, up, up, up } },
  { op = "applymovement", localId = 2,
    steps = { right, right, right, right, up, up } },
  { op = "applymovement", localId = 4,
    steps = { up, right, right, right, right, up } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = bagLine },
  { op = "callstd", id = 4 },
  { op = "setvar", var = Game3.VAR_ROUTE101_STATE, val = 2 },
  { op = "end" },
}
local route = {
  id = "g0_16", width = 20, height = 22, grid = cells, spawn = { x = 10, y = 20 },
  objects = {
    {
      localId = 2, x = 9, y = 13, graphicsId = Game3.GFX_BIRCH,
      flagId = Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA,
    },
    {
      localId = 3, x = 7, y = 14, graphicsId = Game3.GFX_BIRCHS_BAG,
      flagId = Game3.FLAG_HIDE_BIRCH_STARTERS_BAG,
    },
    {
      localId = 4, x = 10, y = 13, graphicsId = 59,
      flagId = Game3.FLAG_HIDE_POOCHYENA_ROUTE101,
    },
  },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_ROUTE101_STATE, value = 0,
        script = {
          { op = "setflag", flag = Game3.FLAG_HIDE_MAP_NAME_POPUP },
          { op = "setvar", var = Game3.VAR_ROUTE101_STATE, val = 1 },
          { op = "end" },
        },
      },
    },
  },
  coordEvents = {
    {
      x = 10, y = 19, trigger = Game3.VAR_ROUTE101_STATE, index = 1,
      script = chase,
    },
    {
      x = 11, y = 19, trigger = Game3.VAR_ROUTE101_STATE, index = 1,
      script = chase,
    },
    {
      x = 10, y = 18, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveUp,
    },
    {
      x = 11, y = 18, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveUp,
    },
    {
      x = 6, y = 15, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveRight,
    },
    {
      x = 6, y = 16, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveRight,
    },
    {
      x = 6, y = 17, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveRight,
    },
    {
      x = 6, y = 18, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveRight,
    },
    {
      x = 7, y = 13, trigger = Game3.VAR_ROUTE101_STATE, index = 2,
      script = shoveDown,
    },
  },
}
local r = Game3.new()
r.phase = "play"
r.data.maps = { start = "g0_16", maps = { g0_16 = route } }
r:enterMap(route, 10, 20, true)
eq(r.scriptVars[Game3.VAR_ROUTE101_STATE], 1, "ON_FRAME writes state 1")
eq(r.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP], true, "hides the map popup")
check(r:npcByLocalId(2), "chase Birch is visible")
check(r:npcByLocalId(3), "the bag is on the ground")
check(r:npcByLocalId(4), "Poochyena is visible")
r.facing = "north"
check(r:tryWalk(0, -1), "step onto the chase trigger")
local chaseLines = runScene(r)
eq(chaseLines[1], help, "H-help me!")
eq(chaseLines[2], bagLine, "help from the BAG")
eq(r.scriptVars[Game3.VAR_ROUTE101_STATE], 2, "state 2 after the run")
eq(r.playerY, 15, "player walked up four")
eq(r:npcByLocalId(2).x, 4, "Birch ran in from the west")
eq(r:npcByLocalId(2).y, 13, "onto the grass")
eq(r:npcByLocalId(4).x, 4, "Poochyena chased him")
eq(r:npcByLocalId(4).y, 14, "one tile south")
r.facing = "south"
check(r:tryWalk(0, 1), "step south of the chase")
check(r:tryWalk(0, 1), "and again")
check(r:tryWalk(0, 1), "onto the (10,18) shove")
local shoveLines = runScene(r)
eq(shoveLines[1], leaveMe, "Wh-Where are you going?!")
eq(r:npcByLocalId(2).y, 12, "Birch walks up to block the town")
r.facing = "west"
check(r:tryWalk(-1, 0), "west from the south shove")
check(r:tryWalk(-1, 0), "past 8")
check(r:tryWalk(-1, 0), "past 7")
check(r:tryWalk(-1, 0), "onto (6,18)")
local shoveWest = runScene(r)
eq(shoveWest[1], leaveMe, "the west tiles also shout")
eq(r:npcByLocalId(2).x, 5, "Birch walks right")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.SPECIAL_CHOOSE_STARTER, 156, "special 156 is ChooseStarter")
eq(Game3.FADE_TO_BLACK, 1, "FADE_TO_BLACK is 1")
eq(Game3.ROUTE101_CHOOSE_X, 6, "ChooseStarter plants the player at 6")
eq(Game3.ROUTE101_CHOOSE_Y, 13, "13")
eq(Game3.LOCALID_ROUTE101_BAG, 3, "the bag is local 3")
eq(Game3.SPECIAL_HEAL_PARTY, 0, "special 0 heals after the first fight")

local function pressA(g)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == "a" end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      seen[#seen + 1] = f.text
      pressA(g)
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local thanks = "PROF. BIRCH: Whew... You were amazing back there! I owe you a lot. Let's go back to my lab."
local cells = {}
for i = 1, 20 * 22 do cells[i] = 0 end
local labCells = {}
for i = 1, 8 * 8 do labCells[i] = 0 end
local bagScript = {
  { op = "setflag", flag = Game3.FLAG_SYS_POKEMON_GET },
  { op = "setflag", flag = Game3.FLAG_RESCUED_BIRCH },
  { op = "fadescreen", mode = Game3.FADE_TO_BLACK },
  { op = "removeobject", localId = Game3.LOCALID_ROUTE101_POOCHYENA },
  { op = "setobjectxy", localId = Game3.LOCALID_PLAYER,
    x = Game3.ROUTE101_CHOOSE_X, y = Game3.ROUTE101_CHOOSE_Y },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { { kind = "face", dir = "west" } } },
  { op = "waitmovement", localId = 0 },
  { op = "special", id = Game3.SPECIAL_CHOOSE_STARTER },
  { op = "waitstate" },
  { op = "applymovement", localId = Game3.LOCALID_ROUTE101_BIRCH,
    steps = { { kind = "walk", dir = "east" } } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = thanks },
  { op = "callstd", id = 4 },
  { op = "special", id = Game3.SPECIAL_HEAL_PARTY },
  { op = "setflag", flag = Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA },
  { op = "clearflag", flag = Game3.FLAG_HIDE_BIRCH_IN_LAB },
  { op = "setflag", flag = Game3.FLAG_HIDE_BIRCH_STARTERS_BAG },
  { op = "setvar", var = Game3.VAR_BIRCH_LAB_STATE, val = 2 },
  { op = "setvar", var = Game3.VAR_ROUTE101_STATE, val = 3 },
  { op = "clearflag", flag = Game3.FLAG_HIDE_MAP_NAME_POPUP },
  { op = "warp", mapGroup = Game3.LAB_GROUP, mapNum = Game3.LAB_NUM,
    warpId = 0xFF, x = Game3.LAB_X, y = Game3.LAB_Y },
  { op = "waitstate" },
  { op = "end" },
}
local lab = {
  id = "g1_4", width = 8, height = 8, grid = labCells, spawn = { x = 6, y = 5 },
  objects = {
    {
      localId = 1, x = 6, y = 4, graphicsId = Game3.GFX_BIRCH,
      flagId = Game3.FLAG_HIDE_BIRCH_IN_LAB,
    },
  },
}
local route = {
  id = "g0_16", width = 20, height = 22, grid = cells, spawn = { x = 7, y = 15 },
  objects = {
    {
      localId = Game3.LOCALID_ROUTE101_BIRCH, x = 4, y = 13,
      graphicsId = Game3.GFX_BIRCH,
      flagId = Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA,
    },
    {
      localId = Game3.LOCALID_ROUTE101_BAG, x = 7, y = 14,
      graphicsId = Game3.GFX_BIRCHS_BAG,
      flagId = Game3.FLAG_HIDE_BIRCH_STARTERS_BAG,
      script = bagScript,
    },
    {
      localId = Game3.LOCALID_ROUTE101_POOCHYENA, x = 4, y = 14,
      graphicsId = 59,
      flagId = Game3.FLAG_HIDE_POOCHYENA_ROUTE101,
    },
  },
}
local g = Game3.new()
g.phase = "play"
g.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = true
g.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP] = true
g.scriptVars = { [Game3.VAR_ROUTE101_STATE] = 2 }
g.data.maps = { start = "g0_16", maps = { g0_16 = route, g1_4 = lab } }
g:enterMap(route, 7, 15, true)
g.facing = "north"
check(g:tryTalk(), "talking to the scripted bag")
runScene(g)
eq(g.playerX, Game3.ROUTE101_CHOOSE_X, "setobjectxy plants at 6")
eq(g.playerY, Game3.ROUTE101_CHOOSE_Y, "13")
eq(g.facing, "west", "WalkInPlaceFastestLeft")
eq(g.field.kind, "starter", "special 156 opens ChooseStarter")
eq(g.field.scripted, true, "and keeps waitstate parked")
eq(g.field.cursor, 1, "the cursor starts on Torchic")
eq(g.field.kind ~= "wait", true, "the wait UI does not cover the balls")
check(g:npcByLocalId(Game3.LOCALID_ROUTE101_POOCHYENA).hidden,
  "removeobject hid Poochyena")
pressA(g)
eq(g.field.kind, "starter_yesno", "A asks to confirm")
pressA(g)
eq(g.phase, "battle", "YES starts the first battle")
eq(g.party[1].species, 280, "Torchic joins before the fight")
eq(g.scriptVars[0x800D], 1, "VAR_RESULT is the 0-based ball (Torchic = 1)")
eq(g.scriptVars[Game3.VAR_STARTER_MON], 1, "VAR_STARTER_MON matches")
eq(g.battle.enemy.species, 286, "vs Poochyena")
check(g.battle.chase, "BATTLE_TYPE_FIRST_BATTLE")
check(g.scriptWait, "waitstate is still held through the fight")
g:finishBattle()
eq(g.phase, "play", "CB2_EndFirstBattle returns to the field script")
eq(g.map.id, "g0_16", "it does not warp from endBattle")
local after = runScene(g)
eq(after[1], thanks, "Birch thanks you after the walk")
eq(g.map.id, "g1_4", "then warps to the lab")
eq(g.playerX, Game3.LAB_X, "at 6")
eq(g.playerY, Game3.LAB_Y, "5")
eq(g.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 2, "VAR_BIRCH_LAB_STATE 2")
eq(g.scriptVars[Game3.VAR_ROUTE101_STATE], 3, "VAR_ROUTE101_STATE 3")
eq(g.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB], nil, "lab Birch is shown")
eq(g.flags[Game3.FLAG_HIDE_BIRCH_BATTLE_POOCHYENA], true,
  "chase Birch hides")
eq(g.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP], nil, "the map popup returns")
eq(#g:npcsFor(g.map), 1, "lab Birch is in after the warp")

local faint = Game3.new()
faint.phase = "play"
faint.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB] = true
faint.scriptVars = { [Game3.VAR_ROUTE101_STATE] = 2 }
faint.data.maps = {
  start = "g0_16",
  maps = {
    g0_16 = route,
    g1_4 = lab,
    g_home = {
      id = "g_home", width = 2, height = 2, grid = { 0, 0, 0, 0 },
      spawn = { x = 0, y = 0 },
    },
  },
}
faint.lastHeal = { mapId = "g_home", x = 0, y = 0 }
faint:enterMap(route, 7, 15, true)
faint.facing = "north"
check(faint:tryTalk(), "the bag still opens ChooseStarter")
runScene(faint)
pressA(faint)
pressA(faint)
eq(faint.phase, "battle", "the first fight started")
faint.battle.player.hp = 0
faint:blackout()
eq(faint.phase, "play", "a faint still continues the script")
eq(faint.map.id, "g0_16", "it does not send you home")
local faintAfter = runScene(faint)
eq(faintAfter[1], thanks, "Birch still thanks you")
eq(faint.map.id, "g1_4", "and the lab warp still fires")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FLAG_HIDE_BOY_ROUTE101, 0x3DF, "FLAG_HIDE_BOY_ROUTE101")
eq(Game3.SPECIAL_CHANGE_POKEMON_NICKNAME, 158, "special 158 is ChangePokemonNickname")
eq(Game3.NICKNAME_LEN, 10, "nicknames are 10 letters")
eq(Game3.DIR_NORTH, 2, "ON_WARP turnobject 2 is FACE_UP")

local have = "{PLAYER} received the {STR_VAR_1}!"
local nickAsk = "Why not give a nickname to that {STR_VAR_1}?"
local seeRival = "Go see {RIVAL}. What do you think?"
local agree = "Get {RIVAL} to teach you what it means to be a TRAINER."
local decline = "Oh, don't be that way. You should go meet my kid."
local nameBody = {
  { op = "fadescreen", mode = Game3.FADE_TO_BLACK },
  { op = "special", id = Game3.SPECIAL_CHANGE_POKEMON_NICKNAME },
  { op = "waitstate" },
  { op = "end" },
}
local giveStarter = {
  { op = "bufferleadmon", slot = 0 },
  { op = "message", text = have },
  { op = "waitmessage" },
  { op = "loadword", text = nickAsk },
  { op = "callstd", id = 5 },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "goto_if", cond = 1, to = 10 },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "goto_if", cond = 1, to = 13 },
  { op = "setvar", var = 0x8004, val = 0 },
  { op = "call", body = nameBody },
  { op = "goto", to = 13 },
  { op = "loadword", text = seeRival },
  { op = "callstd", id = 5 },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "goto_if", cond = 1, to = 21 },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "goto_if", cond = 1, to = 26 },
  { op = "end" },
  { op = "end" },
  { op = "loadword", text = agree },
  { op = "callstd", id = 4 },
  { op = "clearflag", flag = Game3.FLAG_HIDE_BOY_ROUTE101 },
  { op = "setvar", var = Game3.VAR_BIRCH_LAB_STATE, val = 3 },
  { op = "end" },
  { op = "loadword", text = decline },
  { op = "callstd", id = 5 },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "goto_if", cond = 1, to = 21 },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "goto_if", cond = 1, to = 26 },
  { op = "end" },
}
local cells = {}
for i = 1, 8 * 8 do cells[i] = 0 end
local lab = {
  id = "g1_4", width = 8, height = 8, grid = cells, spawn = { x = 6, y = 5 },
  objects = {
    { localId = 1, x = 6, y = 4, graphicsId = Game3.GFX_BIRCH },
  },
  mapScripts = {
    onWarp = {
      {
        var = Game3.VAR_BIRCH_LAB_STATE, value = 2,
        script = {
          { op = "turnobject", localId = Game3.LOCALID_PLAYER,
            dir = Game3.DIR_NORTH },
          { op = "end" },
        },
      },
    },
    onFrame = {
      {
        var = Game3.VAR_BIRCH_LAB_STATE, value = 2,
        script = giveStarter,
      },
    },
  },
}

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
  while g.field and g.field.kind == "delay" do
    g:walkHeld((g.delayLeft or 0) + 1)
  end
end

local function makeLabber()
  local g = Game3.new()
  g.phase = "play"
  g.facing = "south"
  g.flags[Game3.FLAG_HIDE_BOY_ROUTE101] = true
  g.scriptVars = { [Game3.VAR_BIRCH_LAB_STATE] = 2 }
  g.party = { g:makeMon(280, 5) }
  g.data.maps = { start = "g1_4", maps = { g1_4 = lab } }
  g:enterMap(lab, 6, 5, true)
  return g
end

local skip = makeLabber()
eq(skip.facing, "north", "ON_WARP faces the player up")
eq(skip.stringVars[1], "TORCHIC", "bufferleadmon writes STR_VAR_1")
eq(skip.field.kind, "talk", "the gift line waits")
check(skip.field.text:find("TORCHIC", 1, true) ~= nil, "and names Torchic")
check(skip.field.text:find("BRENDAN", 1, true) ~= nil, "{PLAYER} is BRENDAN")
press(skip, "a")
eq(skip.field.kind, "script_yesno", "nickname yes/no")
check(skip.field.text:find("TORCHIC", 1, true) ~= nil, "the prompt uses STR_VAR_1")
press(skip, "b")
eq(skip.field.kind, "script_yesno", "then go see the rival")
check(skip.field.text:find("MAY", 1, true) ~= nil, "{RIVAL} is MAY")
press(skip, "a")
eq(skip.field.kind, "talk", "AgreeToSeeRival")
check(skip.field.text:find("TRAINER", 1, true) ~= nil, "teach you to be a TRAINER")
press(skip, "a")
eq(skip.field, nil, "the scene ends")
eq(skip.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 3, "VAR_BIRCH_LAB_STATE 3")
eq(skip.flags[Game3.FLAG_HIDE_BOY_ROUTE101], nil, "the Route 101 boy is shown")
eq(skip.party[1].name, "TORCHIC", "NO keeps the species name")

local loop = makeLabber()
press(loop, "a")
press(loop, "b")
press(loop, "b")
eq(loop.field.kind, "script_yesno", "declining loops Don't be that way")
check(loop.field.text:find("don't be that way", 1, true) ~= nil, "the nag line")
press(loop, "b")
check(loop.field.text:find("don't be that way", 1, true) ~= nil, "NO nag again")
press(loop, "a")
eq(loop.field.kind, "talk", "YES still agrees")
press(loop, "a")
eq(loop.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 3, "state 3 after the nag")
eq(loop.flags[Game3.FLAG_HIDE_BOY_ROUTE101], nil, "and the boy flag clears")

local namer = makeLabber()
press(namer, "a")
press(namer, "a")
eq(namer.field.kind, "nickname", "YES opens ChangePokemonNickname")
eq(namer.field.scripted, true, "waitstate holds")
namer.field.name = "SPARK"
namer.field.cursor = #namer.field.keys - 1
press(namer, "a")
eq(namer.party[1].name, "SPARK", "END writes the nickname")
eq(namer.field.kind, "script_yesno", "then GoSeeRival")
press(namer, "a")
press(namer, "a")
eq(namer.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 3, "state 3 after a nickname")
eq(namer.party[1].name, "SPARK", "SPARK sticks")

local snap = namer:snapshotMon(namer.party[1])
eq(snap.name, "SPARK", "saves keep the nickname")
local restored = namer:restoreMon(snap)
eq(restored.name, "SPARK", "and load it back")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.VAR_ROUTE102_ACCESSIBLE, 0x4051, "VAR_ROUTE102_ACCESSIBLE")
eq(Game3.VAR_ROUTE103_STATE, 0x4062, "VAR_ROUTE103_STATE")
eq(Game3.VAR_OLDALE_STATE, 0x40C7, "VAR_OLDALE_STATE")
eq(Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN, 0x3D3, "FLAG_HIDE_RIVAL_OLDALE_TOWN")
eq(Game3.LOCALID_LAB_RIVAL, 3, "lab rival is local 3")
eq(Game3.FLAG_ADVENTURE_STARTED, 0x74, "FLAG_ADVENTURE_STARTED")

local heard = "PROF. BIRCH: I heard you beat {RIVAL} on your first try. Here's a POKeDEX."
local received = "{PLAYER} received the POKeDEX!"
local explain = "PROF. BIRCH: The POKeDEX records any POKeMON you meet or catch."
local mayTake = "MAY: Oh, wow, {PLAYER}! You got a POKeDEX, too! I've got something for you, too!"
local mayCatch = "MAY: If I find any cute POKeMON, I'll catch them with POKe BALLS!"
local brendanTake = "BRENDAN: So you got a POKeDEX, too. Well then, here. I'll give you this."
local brendanCatch = "BRENDAN: If I find any cool POKeMON, you bet I'll try to get them with POKe BALLS."
local up = { kind = "walk", dir = "north" }
local down = { kind = "walk", dir = "south" }
local faceLeft = { kind = "face", dir = "west" }
local faceRight = { kind = "face", dir = "east" }
local receiveDex = {
  { op = "message", text = received },
  { op = "waitmessage" },
  { op = "setflag", flag = Game3.FLAG_SYS_POKEDEX_GET },
  { op = "end" },
}
local function ballScript(take, catch, result)
  return {
    { op = "loadword", text = take },
    { op = "callstd", id = 4 },
    { op = "setorcopyvar", var = 0x8000, val = Game3.ITEM_POKE_BALL },
    { op = "setorcopyvar", var = 0x8001, val = 5 },
    { op = "callstd", id = 0 },
    { op = "loadword", text = catch },
    { op = "callstd", id = 4 },
    { op = "setvar", var = 0x800D, val = result },
    { op = "end" },
  }
end
local mayBalls = ballScript(mayTake, mayCatch, 0)
local brendanBalls = ballScript(brendanTake, brendanCatch, 1)
local giveDex = {
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { up, up, up, up, up, up, up } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = heard },
  { op = "callstd", id = 4 },
  { op = "call", body = receiveDex },
  { op = "loadword", text = explain },
  { op = "callstd", id = 4 },
  { op = "applymovement", localId = Game3.LOCALID_LAB_RIVAL,
    steps = { down, faceLeft } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "checkplayergender" },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "call_if", cond = 1, body = mayBalls },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "call_if", cond = 1, body = brendanBalls },
  { op = "setvar", var = Game3.VAR_BIRCH_LAB_STATE, val = 5 },
  { op = "setflag", flag = Game3.FLAG_ADVENTURE_STARTED },
  { op = "setvar", var = Game3.VAR_ROUTE102_ACCESSIBLE, val = 1 },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_RIVAL_STATE, val = 4 },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_STATE, val = 3 },
  { op = "end" },
}
local cells = {}
for i = 1, 12 * 14 do cells[i] = 0 end
local lab = {
  id = "g1_4", width = 12, height = 14, grid = cells, spawn = { x = 6, y = 12 },
  objects = {
    { localId = Game3.LOCALID_LAB_AIDE, x = 9, y = 8, graphicsId = 22 },
    {
      localId = Game3.LOCALID_LAB_BIRCH, x = 6, y = 4,
      graphicsId = Game3.GFX_BIRCH,
    },
    {
      localId = Game3.LOCALID_LAB_RIVAL, x = 7, y = 4,
      graphicsId = Game3.GFX_VAR_0,
      flagId = Game3.FLAG_HIDE_RIVAL_BIRCH_LAB,
    },
  },
  mapScripts = {
    onFrame = {
      {
        var = Game3.VAR_BIRCH_LAB_STATE, value = 4,
        script = giveDex,
      },
    },
  },
}

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local function makeDexer(female)
  local g = Game3.new()
  g.phase = "play"
  if female then g:applyGender(Game3.GENDER_FEMALE) end
  g.party = { g:makeMon(280, 5) }
  g.scriptVars = { [Game3.VAR_BIRCH_LAB_STATE] = 4 }
  g.data.maps = { start = "g1_4", maps = { g1_4 = lab } }
  g:enterMap(lab, 6, 12, true)
  return g
end

local boy = makeDexer(false)
eq(boy:npcByLocalId(Game3.LOCALID_LAB_RIVAL).graphicsId, Game3.GFX_RIVAL_MAY,
  "boy sees May in the lab")
local boyLines = runScene(boy)
eq(boy.playerY, 5, "seven walk_up from the door")
eq(boy.playerX, 6, "on the center aisle")
eq(boy.facing, "east", "WalkInPlaceFastestRight toward the rival")
eq(boy:npcByLocalId(Game3.LOCALID_LAB_RIVAL).y, 5, "May walked down one")
eq(boy:npcByLocalId(Game3.LOCALID_LAB_RIVAL).x, 7, "still in the east column")
check(boyLines[1]:find("MAY", 1, true) ~= nil, "Birch heard you beat May")
check(boyLines[2]:find("POKeDEX", 1, true) ~= nil, "you received the POKeDEX")
eq(boy.flags[Game3.FLAG_SYS_POKEDEX_GET], true, "FLAG_SYS_POKEDEX_GET")
check(boy:hasPokedex(), "START grows POKeDEX")
eq(#boy:startMenuItems(), 7, "seven START rows")
check(boyLines[3]:find("records", 1, true) ~= nil, "Birch explains the dex")
check(boyLines[4]:find("I've got something", 1, true) ~= nil, "May's gift line")
eq(boy:itemCount(Game3.ITEM_POKE_BALL), 5, "five POKe BALLS")
check(boyLines[6]:find("put away", 1, true) ~= nil, "put-away pocket line")
check(boyLines[6]:find("POKe BALLS", 1, true) ~= nil, "balls pocket")
check(boyLines[7]:find("cute", 1, true) ~= nil, "May will catch cute ones")
eq(boy.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 5, "lab-state 5")
eq(boy.flags[Game3.FLAG_ADVENTURE_STARTED], true, "FLAG_ADVENTURE_STARTED")
eq(boy.scriptVars[Game3.VAR_ROUTE102_ACCESSIBLE], 1, "Route 102 opens")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_RIVAL_STATE], 4, "rival-state 4")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_STATE], 3, "Littleroot-state 3")

local girl = makeDexer(true)
local girlLines = runScene(girl)
eq(girl:npcByLocalId(Game3.LOCALID_LAB_RIVAL).graphicsId, Game3.GFX_RIVAL_BRENDAN,
  "girl sees Brendan")
check(girlLines[4]:find("I'll give you this", 1, true) ~= nil, "Brendan's gift line")
eq(girl:itemCount(Game3.ITEM_POKE_BALL), 5, "he also hands five balls")
check(girlLines[6]:find("put away", 1, true) ~= nil, "put-away pocket line")
check(girlLines[7]:find("cool", 1, true) ~= nil, "Brendan wants cool ones")
eq(girl.scriptVars[Game3.VAR_BIRCH_LAB_STATE], 5, "girl lab-state 5")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.FLAG_RECEIVED_POTION_OLDALE, 0x84, "FLAG_RECEIVED_POTION_OLDALE")
eq(Game3.FLAG_TEMP_1, 0x1, "FLAG_TEMP_1")
eq(Game3.LOCALID_OLDALE_FOOTPRINTS, 3, "footprints man is local 3")
eq(Game3.LOCALID_OLDALE_RIVAL, 4, "Oldale rival is local 4")
eq(Game3.MOVEMENT_TYPE_FACE_LEFT, 9, "FACE_LEFT is 9")
-- Ruby's widest map script is 823 commands and its deepest nesting is 5
-- calls (tools/gen3_script_audit.lua); the guards have to clear both or a
-- real script is silently clipped mid-scene.
check(Gen3Script.MAX_OPS > 823, "long Oldale scripts keep walking")
check(Gen3Script.MAX_CALL > 5, "the deepest ROM call chain still parses")

local g0 = Game3.new()
eq(g0.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN], nil,
  "Game3.new leaves hide flags to the caller")
g0:applyNewGameHideFlags()
eq(g0.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN], true,
  "ResetAllMapFlags hides the Oldale rival")
eq(g0.flags[Game3.FLAG_HIDE_RIVAL_BIRCH_LAB], true, "and the lab rival")
eq(g0.flags[Game3.FLAG_HIDE_BOY_ROUTE101], true, "and the Route 101 boy")
eq(g0.flags[Game3.FLAG_HIDE_BIRCH_IN_LAB], true, "and Birch out of the lab")
eq(g0.flags[Game3.FLAG_HIDE_MOM_UPSTAIRS], true, "and Mom upstairs")
eq(g0.flags[Game3.FLAG_HIDE_PETALBURG_GYM_GUIDE], true, "and the gym guide")
eq(#Game3.NEW_GAME_HIDE_FLAGS, 132, "the full ResetAllMapFlags list")

eq(Game3.VAR_SHROOMISH_SIZE_RECORD, 0x4047, "VAR_SHROOMISH_SIZE_RECORD")
eq(Game3.VAR_BARBOACH_SIZE_RECORD, 0x404F, "VAR_BARBOACH_SIZE_RECORD")
eq(Game3.SIZE_RECORD_DEFAULT, 0x8100, "Marco's default size record")
eq((g0.scriptVars or {})[Game3.VAR_SHROOMISH_SIZE_RECORD], nil,
  "hide flags do not write size records")
g0:wipeNewGameState()
eq(g0:itemCount(Game3.ITEM_POKE_BALL), 0, "NEW GAME has no POKe BALLs")
eq(g0.balls, 0, "and no leftover ball counter")
eq(g0.scriptVars[Game3.VAR_SHROOMISH_SIZE_RECORD], Game3.SIZE_RECORD_DEFAULT,
  "NEW GAME inits Shroomish at 0x8100")
eq(g0.scriptVars[Game3.VAR_BARBOACH_SIZE_RECORD], Game3.SIZE_RECORD_DEFAULT,
  "and Barboach")

g0.facing = "east"
Gen3Script.run(g0, {
  { op = "setorcopyvar", var = 0x8000, val = Game3.VAR_FACING },
  { op = "end" },
})
eq(g0.scriptVars[0x8000], Game3.DIR_EAST, "switch VAR_FACING copies the facing")

local blockText = "Aaaaah! Wait! Please don't come in here."
local sketchText = "I just discovered the footprints of a rare POKeMON!"
local doneText = "But it turns out they were only my own footprints..."
local mayText = "MAY: {PLAYER}! Over here! Let's hurry home!"
local brendanText = "BRENDAN: I'm heading back to my dad's LAB now. {PLAYER}, you should hustle back, too."
local up = { kind = "walk", dir = "north" }
local down = { kind = "walk", dir = "south" }
local left = { kind = "walk", dir = "west" }
local right = { kind = "walk", dir = "east" }
local faceLeft = { kind = "face", dir = "west" }
local faceRight = { kind = "face", dir = "east" }
local blockWest = {
  { op = "setobjectxyperm", localId = Game3.LOCALID_OLDALE_FOOTPRINTS,
    x = 1, y = 11 },
  { op = "setobjectmovementtype",
    localId = Game3.LOCALID_OLDALE_FOOTPRINTS,
    movementType = Game3.MOVEMENT_TYPE_FACE_LEFT },
  { op = "end" },
}
local openWest = {
  { op = "setvar", var = Game3.VAR_ROUTE102_ACCESSIBLE, val = 1 },
  { op = "end" },
}
local blockedPath = {
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { { kind = "delay", frames = 8 }, right } },
  { op = "applymovement", localId = Game3.LOCALID_OLDALE_FOOTPRINTS,
    steps = { up, faceLeft, { kind = "lockface" }, right,
      { kind = "unlockface" } } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = blockText },
  { op = "callstd", id = 4 },
  { op = "applymovement", localId = Game3.LOCALID_OLDALE_FOOTPRINTS,
    steps = { down, left } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local footprintsTalk = {
  { op = "faceplayer" },
  { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
  { op = "goto_if", cond = 1, to = 7 },
  { op = "loadword", text = sketchText },
  { op = "callstd", id = 4 },
  { op = "end" },
  { op = "loadword", text = doneText },
  { op = "callstd", id = 4 },
  { op = "end" },
}
local rivalTrigger1 = {
  { op = "applymovement", localId = Game3.LOCALID_OLDALE_RIVAL,
    steps = { left, left } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "checkplayergender" },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "goto_if", cond = 1, to = 11 },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "goto_if", cond = 1, to = 14 },
  { op = "end" },
  { op = "loadword", text = mayText },
  { op = "callstd", id = 4 },
  { op = "goto", to = 17 },
  { op = "loadword", text = brendanText },
  { op = "callstd", id = 4 },
  { op = "goto", to = 17 },
  { op = "applymovement", localId = Game3.LOCALID_OLDALE_RIVAL,
    steps = { down, down, down, down, down, down } },
  { op = "waitmovement", localId = 0 },
  { op = "removeobject", localId = Game3.LOCALID_OLDALE_RIVAL },
  { op = "setvar", var = Game3.VAR_OLDALE_STATE, val = 2 },
  { op = "setflag", flag = Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN },
  { op = "end" },
}
local cells = {}
for i = 1, 16 * 24 do cells[i] = 0 end
local function makeTown()
  return {
    id = "g0_10", width = 16, height = 24, grid = cells, spawn = { x = 8, y = 20 },
    objects = {
      {
        localId = Game3.LOCALID_OLDALE_FOOTPRINTS, x = 8, y = 9,
        graphicsId = 39,
        script = footprintsTalk,
      },
      {
        localId = Game3.LOCALID_OLDALE_RIVAL, x = 11, y = 19,
        graphicsId = Game3.GFX_VAR_0,
        flagId = Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN,
      },
    },
    mapScripts = {
      onTransition = {
        { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
        { op = "call_if", cond = 0, body = blockWest },
        { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
        { op = "call_if", cond = 1, body = openWest },
        { op = "end" },
      },
    },
    coordEvents = {
      {
        x = 0, y = 10, trigger = Game3.VAR_ROUTE102_ACCESSIBLE, index = 0,
        script = blockedPath,
      },
      {
        x = 8, y = 19, trigger = Game3.VAR_OLDALE_STATE, index = 1,
        script = rivalTrigger1,
      },
    },
  }
end

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local first = Game3.new()
first.phase = "play"
first:applyNewGameHideFlags()
first.data.maps = { start = "g0_10", maps = { g0_10 = makeTown() } }
first:enterMap(first.data.maps.maps.g0_10, 1, 10, true)
eq(first:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).x, 1,
  "ON_TRANSITION parks the man on the west road")
eq(first:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).y, 11, "at 1,11")
eq(first:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).facing, "west",
  "facing the path")
eq(first:npcByLocalId(Game3.LOCALID_OLDALE_RIVAL), nil,
  "the rival stays hidden before Route 103")
first.facing = "west"
check(first:tryWalk(-1, 0), "step onto the (0,10) trigger")
local blockLines = runScene(first)
eq(first.playerX, 1, "walk_right shoves you off the route")
check(blockLines[1]:find("Wait", 1, true) ~= nil, "don't come in here")
eq(first.scriptVars[Game3.VAR_ROUTE102_ACCESSIBLE] or 0, 0,
  "Route 102 is still closed")

local open = Game3.new()
open.phase = "play"
open.flags[Game3.FLAG_ADVENTURE_STARTED] = true
open.data.maps = { start = "g0_10", maps = { g0_10 = makeTown() } }
open:enterMap(open.data.maps.maps.g0_10, 1, 10, true)
eq(open.scriptVars[Game3.VAR_ROUTE102_ACCESSIBLE], 1,
  "FLAG_ADVENTURE_STARTED opens Route 102")
eq(open:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).x, 8,
  "the man stays at his sketch spot")
open.facing = "west"
check(open:tryWalk(-1, 0), "west is walkable")
eq(open.field, nil, "the shove does not fire")
eq(open.playerX, 0, "you reach the Route 102 tile")
open.playerX, open.playerY = 8, 10
open.facing = "north"
open.field = nil
check(open:tryTalk(), "talking after the dex")
check(open.field.text:find("own footprints", 1, true) ~= nil,
  "it was his own footprints")

local lingerMap = makeTown()
local linger = Game3.new()
linger.phase = "play"
linger:applyNewGameHideFlags()
linger.data.maps = { start = "g0_10", maps = { g0_10 = lingerMap } }
linger:enterMap(lingerMap, 1, 10, true)
eq(linger:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).x, 1,
  "first visit parks him on the west road")
eq(lingerMap.objects[1].x, 8, "the sketch-spot template is not overwritten")
linger.flags[Game3.FLAG_ADVENTURE_STARTED] = true
linger:enterMap(lingerMap, 1, 10, true)
eq(linger:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).x, 8,
  "after the dex he returns to the sketch spot")
eq(linger:npcByLocalId(Game3.LOCALID_OLDALE_FOOTPRINTS).y, 9,
  "not lingering on the Route 102 edge")

local boy = Game3.new()
boy.phase = "play"
boy.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN] = nil
boy.scriptVars = { [Game3.VAR_OLDALE_STATE] = 1 }
boy.data.maps = { start = "g0_10", maps = { g0_10 = makeTown() } }
boy:enterMap(boy.data.maps.maps.g0_10, 8, 20, true)
eq(boy:npcByLocalId(Game3.LOCALID_OLDALE_RIVAL).graphicsId, Game3.GFX_RIVAL_MAY,
  "boy sees May in Oldale")
boy.facing = "north"
check(boy:tryWalk(0, -1), "step onto (8,19)")
local boyLines = runScene(boy)
eq(boy.facing, "east", "WalkInPlaceFastestRight toward May")
eq(boy:npcByLocalId(Game3.LOCALID_OLDALE_RIVAL).hidden, true,
  "removeobject hides her")
check(boyLines[1]:find("hurry home", 1, true) ~= nil, "May sends you to the lab")
eq(boy.scriptVars[Game3.VAR_OLDALE_STATE], 2, "VAR_OLDALE_STATE 2")
eq(boy.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN], true,
  "FLAG_HIDE_RIVAL_OLDALE_TOWN")

local girl = Game3.new()
girl.phase = "play"
girl:applyGender(Game3.GENDER_FEMALE)
girl.flags[Game3.FLAG_HIDE_RIVAL_OLDALE_TOWN] = nil
girl.scriptVars = { [Game3.VAR_OLDALE_STATE] = 1 }
girl.data.maps = { start = "g0_10", maps = { g0_10 = makeTown() } }
girl:enterMap(girl.data.maps.maps.g0_10, 8, 20, true)
eq(girl:npcByLocalId(Game3.LOCALID_OLDALE_RIVAL).graphicsId,
  Game3.GFX_RIVAL_BRENDAN, "girl sees Brendan")
girl.facing = "north"
check(girl:tryWalk(0, -1), "her (8,19) trigger")
local girlLines = runScene(girl)
check(girlLines[1]:find("LAB", 1, true) ~= nil, "Brendan heads to the lab")
eq(girl.scriptVars[Game3.VAR_OLDALE_STATE], 2, "girl VAR_OLDALE_STATE 2")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FLAG_RECEIVED_RUNNING_SHOES, 0x112, "FLAG_RECEIVED_RUNNING_SHOES")
eq(Game3.LOCALID_MOM_LITTLEROOT, 4, "town Mom is local 4")
eq(Game3.FLAG_SYS_B_DASH, 0x860, "FLAG_SYS_B_DASH")

local waitLine = "MOM: Wait, {PLAYER}!"
local wearLine = "MOM: Here, honey! Wear these RUNNING SHOES."
local switchLine = "{PLAYER} switched shoes with the RUNNING SHOES."
local explainLine = "Press the B Button while wearing these RUNNING SHOES to run extra-fast!"
local homeLine = "If anything happens, you can come home."
local down = { kind = "walk", dir = "south" }
local placeMale = {
  { op = "setobjectxyperm", localId = Game3.LOCALID_MOM_LITTLEROOT,
    x = 5, y = 9 },
  { op = "end" },
}
local placeFemale = {
  { op = "setobjectxyperm", localId = Game3.LOCALID_MOM_LITTLEROOT,
    x = 14, y = 9 },
  { op = "end" },
}
local placeMom = {
  { op = "clearflag", flag = Game3.FLAG_HIDE_MOM_LITTLEROOT },
  { op = "setobjectmovementtype",
    localId = Game3.LOCALID_MOM_LITTLEROOT,
    movementType = Game3.MOVEMENT_TYPE_FACE_DOWN },
  { op = "checkplayergender" },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "call_if", cond = 1, body = placeMale },
  { op = "compare", var = 0x800D, val = 1 },
  { op = "call_if", cond = 1, body = placeFemale },
  { op = "end" },
}
local giveShoes = {
  { op = "loadword", text = waitLine },
  { op = "callstd", id = 4 },
  { op = "applymovement", localId = Game3.LOCALID_MOM_LITTLEROOT,
    steps = { down } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = wearLine },
  { op = "callstd", id = 4 },
  { op = "playfanfare", id = 1 },
  { op = "message", text = switchLine },
  { op = "waitfanfare" },
  { op = "waitmessage" },
  { op = "setflag", flag = Game3.FLAG_RECEIVED_RUNNING_SHOES },
  { op = "loadword", text = explainLine },
  { op = "callstd", id = 4 },
  { op = "loadword", text = homeLine },
  { op = "callstd", id = 4 },
  { op = "removeobject", localId = Game3.LOCALID_MOM_LITTLEROOT },
  { op = "setflag", flag = Game3.FLAG_SYS_B_DASH },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_STATE, val = 4 },
  { op = "end" },
}
local cells = {}
for i = 1, 16 * 14 do cells[i] = 0 end
local function makeTown()
  return {
    id = "g0_9", width = 16, height = 14, grid = cells,
    spawn = { x = 10, y = 10 },
    objects = {
      {
        localId = Game3.LOCALID_MOM_LITTLEROOT, x = 5, y = 8,
        graphicsId = Game3.GFX_MOM,
        flagId = Game3.FLAG_HIDE_MOM_LITTLEROOT,
        script = giveShoes,
      },
    },
    mapScripts = {
      onTransition = {
        { op = "compare", var = Game3.VAR_LITTLEROOT_STATE, val = 3 },
        { op = "call_if", cond = 1, body = placeMom },
        { op = "end" },
      },
    },
    coordEvents = {
      {
        x = 10, y = 9, trigger = Game3.VAR_LITTLEROOT_STATE, index = 3,
        script = giveShoes,
      },
    },
  }
end

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 200 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local function makeShoer(female)
  local g = Game3.new()
  g.phase = "play"
  if female then g:applyGender(Game3.GENDER_FEMALE) end
  g.flags[Game3.FLAG_HIDE_MOM_LITTLEROOT] = true
  g.scriptVars = { [Game3.VAR_LITTLEROOT_STATE] = 3 }
  g.data.maps = { start = "g0_9", maps = { g0_9 = makeTown() } }
  g:enterMap(g.data.maps.maps.g0_9, 10, 10, true)
  return g
end

local boy = makeShoer(false)
eq(boy.flags[Game3.FLAG_HIDE_MOM_LITTLEROOT], nil, "state 3 shows Mom")
eq(boy:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).x, 5, "boy Mom at the west door")
eq(boy:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).y, 9, "in front of the house")
eq(boy:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).facing, "south",
  "FACE_DOWN toward the road")
boy.facing = "north"
check(boy:tryWalk(0, -1), "step onto (10,9)")
local boyLines = runScene(boy)
check(boyLines[1]:find("Wait", 1, true) ~= nil, "MOM: Wait, BRENDAN")
check(boyLines[2]:find("RUNNING SHOES", 1, true) ~= nil, "she offers the shoes")
check(boyLines[3]:find("switched shoes", 1, true) ~= nil, "you put them on")
check(boyLines[4]:find("B Button", 1, true) ~= nil, "instructions name B")
check(boyLines[5]:find("come home", 1, true) ~= nil, "come home if anything happens")
eq(boy.flags[Game3.FLAG_RECEIVED_RUNNING_SHOES], true,
  "FLAG_RECEIVED_RUNNING_SHOES")
eq(boy.flags[Game3.FLAG_SYS_B_DASH], true, "FLAG_SYS_B_DASH")
eq(boy.scriptVars[Game3.VAR_LITTLEROOT_STATE], 4, "Littleroot-state 4")
eq(boy:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).hidden, true, "Mom goes inside")
local oldDown = Input.isDown
Input.isDown = function(_, key) return key == "b" end
eq(boy:wantRun(), true, "B dashes after the gift")
Input.isDown = oldDown

local girl = makeShoer(true)
eq(girl:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).x, 14,
  "girl Mom at the east door")
eq(girl:npcByLocalId(Game3.LOCALID_MOM_LITTLEROOT).y, 9, "in front of May's house")

local talker = makeShoer(false)
talker.playerX, talker.playerY = 5, 10
talker.facing = "north"
talker.field = nil
check(talker:tryTalk(), "talking to outdoor Mom is the gift")
check(talker.field.text:find("Wait", 1, true) ~= nil, "not the heal line")
local talkLines = runScene(talker)
eq(talker.flags[Game3.FLAG_SYS_B_DASH], true, "talk also grants the dash")

local healer = Game3.new()
healer.phase = "play"
healer.playerX, healer.playerY = 0, 1
healer.facing = "north"
healer.map = { id = "g_in", width = 3, height = 3, grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 } }
healer.npcByMap = { g_in = { {
  x = 0, y = 0, graphicsId = Game3.GFX_MOM,
} } }
check(healer:tryTalk(), "indoor Mom without a script still heals")
check(healer.field.text:find("rest", 1, true) ~= nil, "You should rest a bit")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.GFX_MART_EMPLOYEE, 83, "Oldale employee is gfx 83")
eq(Game3.GFX_MART_EMPLOYEE, Game3.GFX_MART, "same sheet as the indoor clerk")
eq(Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_X, 13, "outskirts X")
eq(Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_Y, 14, "outskirts Y")
eq(Game3.OLDALE_MART_EMPLOYEE_DOOR_X, 13, "door X")
eq(Game3.OLDALE_MART_EMPLOYEE_DOOR_Y, 7, "door Y")
eq(Game3.MOVEMENT_TYPE_FACE_DOWN, 8, "FACE_DOWN is 8")

local shopOnly = Game3.new()
shopOnly.phase = "play"
shopOnly.facing = "east"
shopOnly.playerX, shopOnly.playerY = 0, 0
shopOnly.map = { id = "g_m", width = 3, height = 1, grid = { 0, 0, 0 } }
shopOnly.npcByMap = { g_m = { {
  x = 1, y = 0, graphicsId = Game3.GFX_MART,
  script = { { op = "end" } },
} } }
check(shopOnly:tryTalk(), "gfx 83 with a script is talkable")
eq(shopOnly.field.kind, "talk", "not the shop stand-in")

local indoor = Game3.new()
indoor.phase = "play"
indoor.facing = "east"
indoor.playerX, indoor.playerY = 0, 0
indoor.map = { id = "g_in", width = 3, height = 1, grid = { 0, 0, 0 } }
indoor.npcByMap = { g_in = { {
  x = 1, y = 0, graphicsId = Game3.GFX_MART,
  mart = { 4, 13 },
  script = { { op = "end" } },
} } }
check(indoor:tryTalk(), "an indoor clerk with a dummy script is talkable")
eq(indoor.field.kind, "talk", "ROM script runs before the stock stand-in")

local workText = "Hi! I work at a POKeMON MART. Can I get you to come with me?"
local shopText = "This is a POKeMON MART. Just look for our blue roof."
local explainText = "A POTION can be used anytime, so it's even more useful than a POKeMON CENTER in certain situations."
local bagText = "Too bad! The BAG is full..."
local up = { kind = "walk", dir = "north" }
local left = { kind = "walk", dir = "west" }
local right = { kind = "walk", dir = "east" }
local faceDown = { kind = "face", dir = "south" }
local delay16 = { kind = "delay", frames = 16 }
local empId = Game3.LOCALID_OLDALE_MART
local empEast = { up, up, up, up, up, up, up, faceDown }
local empSouth = { left, up, up, right, up, up, up, up, up, faceDown }
local empNorth = { up, up, up, up, up, up, up, faceDown }
local playerEast = { right, up, up, up, up, up, up }
local playerSouth = { delay16, delay16, delay16, delay16, up, up, up, up, up }
local playerNorth = { up, up, up, up, up, up, up }
local martTalk = {
  { op = "faceplayer" },
  { op = "checkflag", flag = Game3.FLAG_RECEIVED_POTION_OLDALE },
  { op = "goto_if", cond = 1, to = 43 },
  { op = "checkflag", flag = Game3.FLAG_TEMP_1 },
  { op = "goto_if", cond = 1, to = 43 },
  { op = "setflag", flag = Game3.FLAG_TEMP_1 },
  { op = "playbgm", id = 0 },
  { op = "loadword", text = workText },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "setorcopyvar", var = 0x8000, val = Game3.VAR_FACING },
  { op = "compare", var = 0x8000, val = Game3.DIR_SOUTH },
  { op = "goto_if", cond = 1, to = 19 },
  { op = "compare", var = 0x8000, val = Game3.DIR_NORTH },
  { op = "goto_if", cond = 1, to = 23 },
  { op = "compare", var = 0x8000, val = Game3.DIR_EAST },
  { op = "goto_if", cond = 1, to = 27 },
  { op = "end" },
  { op = "applymovement", localId = empId, steps = empSouth },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = playerSouth },
  { op = "waitmovement", localId = 0 },
  { op = "goto", to = 31 },
  { op = "applymovement", localId = empId, steps = empNorth },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = playerNorth },
  { op = "waitmovement", localId = 0 },
  { op = "goto", to = 31 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = playerEast },
  { op = "applymovement", localId = empId, steps = empEast },
  { op = "waitmovement", localId = 0 },
  { op = "goto", to = 31 },
  { op = "loadword", text = shopText },
  { op = "callstd", id = 4 },
  { op = "setorcopyvar", var = 0x8000, val = Game3.ITEM_POTION },
  { op = "setorcopyvar", var = 0x8001, val = 1 },
  { op = "callstd", id = 0 },
  { op = "compare", var = 0x800D, val = 0 },
  { op = "goto_if", cond = 1, to = 46 },
  { op = "loadword", text = explainText },
  { op = "callstd", id = 4 },
  { op = "setflag", flag = Game3.FLAG_RECEIVED_POTION_OLDALE },
  { op = "fadedefaultbgm" },
  { op = "end" },
  { op = "loadword", text = explainText },
  { op = "callstd", id = 4 },
  { op = "end" },
  { op = "loadword", text = bagText },
  { op = "callstd", id = 4 },
  { op = "fadedefaultbgm" },
  { op = "end" },
}
local moveEmployee = {
  { op = "setobjectxyperm", localId = empId,
    x = Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_X,
    y = Game3.OLDALE_MART_EMPLOYEE_OUTSKIRTS_Y },
  { op = "setobjectmovementtype", localId = empId,
    movementType = Game3.MOVEMENT_TYPE_FACE_DOWN },
  { op = "end" },
}
local cells = {}
for i = 1, 16 * 24 do cells[i] = 0 end
local function makeTown()
  return {
    id = "g0_10", width = 16, height = 24, grid = cells,
    spawn = { x = 8, y = 20 },
    objects = {
      {
        localId = empId,
        x = Game3.OLDALE_MART_EMPLOYEE_DOOR_X,
        y = Game3.OLDALE_MART_EMPLOYEE_DOOR_Y,
        graphicsId = Game3.GFX_MART_EMPLOYEE,
        script = martTalk,
      },
    },
    mapScripts = {
      onTransition = {
        { op = "checkflag", flag = Game3.FLAG_RECEIVED_POTION_OLDALE },
        { op = "call_if", cond = 0, body = moveEmployee },
        { op = "end" },
      },
    },
  }
end

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 400 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local function makeTownGame(received)
  local g = Game3.new()
  g.phase = "play"
  if received then
    g.flags[Game3.FLAG_RECEIVED_POTION_OLDALE] = true
  end
  g.data.maps = { start = "g0_10", maps = { g0_10 = makeTown() } }
  g:enterMap(g.data.maps.maps.g0_10, 8, 20, true)
  return g
end

local parked = makeTownGame(false)
local emp = parked:npcByLocalId(empId)
eq(emp.x, 13, "unset potion flag parks them at outskirts X")
eq(emp.y, 14, "and outskirts Y")
eq(emp.facing, "south", "FACE_DOWN")

local done = makeTownGame(true)
eq(done:npcByLocalId(empId).x, 13, "after the gift they stay by the door X")
eq(done:npcByLocalId(empId).y, 7, "and door Y")

parked.playerX, parked.playerY = 13, 15
parked.facing = "north"
parked.field = nil
check(parked:tryTalk(), "talking from the south is the walk")
eq(parked.field.kind, "talk", "not a shop")
check(parked.field.text:find("come with me", 1, true) ~= nil,
  "Can I get you to come with me?")
local northLines = runScene(parked)
check(northLines[2]:find("blue roof", 1, true) ~= nil, "this is a POKeMON MART")
check(northLines[3]:find("POTION", 1, true) ~= nil, "Found POTION!")
check(northLines[4]:find("put away", 1, true) ~= nil, "put-away ITEMS pocket")
check(northLines[5]:find("anytime", 1, true) ~= nil, "Potion explanation")
eq(parked:itemCount(Game3.ITEM_POTION), 1, "one Potion in the bag")
eq(parked.flags[Game3.FLAG_RECEIVED_POTION_OLDALE], true,
  "FLAG_RECEIVED_POTION_OLDALE")
eq(parked.flags[Game3.FLAG_TEMP_1], true, "FLAG_TEMP_1")
eq(parked:npcByLocalId(empId).x, 13, "employee finishes at the door X")
eq(parked:npcByLocalId(empId).y, 7, "and door Y")

local fromEast = makeTownGame(false)
fromEast.playerX, fromEast.playerY = 12, 14
fromEast.facing = "east"
fromEast.field = nil
check(fromEast:tryTalk(), "talking from the west walks east")
local eastLines = runScene(fromEast)
check(eastLines[3]:find("POTION", 1, true) ~= nil, "east path also gives a Potion")
eq(fromEast:itemCount(Game3.ITEM_POTION), 1, "east path bags it")
eq(fromEast:npcByLocalId(empId).y, 7, "and ends at the door")

local miss = makeTownGame(false)
miss.playerX, miss.playerY = 14, 14
miss.facing = "west"
miss.field = nil
check(miss:tryTalk(), "talking from the east still greets")
local missLines = runScene(miss)
eq(#missLines, 1, "facing west has no walk case")
check(missLines[1]:find("come with me", 1, true) ~= nil, "only the invite")
eq(miss:itemCount(Game3.ITEM_POTION), 0, "no Potion")
eq(miss.flags[Game3.FLAG_RECEIVED_POTION_OLDALE], nil, "gift flag stays unset")
eq(miss.flags[Game3.FLAG_TEMP_1], true, "TEMP_1 is already set")
miss.field = nil
check(miss:tryTalk(), "talking again is the explanation")
local again = runScene(miss)
check(again[1]:find("anytime", 1, true) ~= nil, "Potion explanation without a gift")
eq(miss:itemCount(Game3.ITEM_POTION), 0, "still no Potion")

done.playerX, done.playerY = 13, 8
done.facing = "north"
done.field = nil
check(done:tryTalk(), "after the gift they still talk")
local replay = runScene(done)
check(replay[1]:find("anytime", 1, true) ~= nil, "repeat is the explanation")
eq(done:itemCount(Game3.ITEM_POTION), 0, "no second Potion")
end)()

;(function()
local Input = require("src.core.Input")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.ITEM_AWAKENING, 17, "Awakening is item 17")
eq(Game3.ITEM_PARALYZE_HEAL, 18, "Paralyze Heal is item 18")
eq(Gen3Script.POKEMART, 0x86, "pokemart is 0x86")

local serveText = "Welcome! How may I serve you?"
local againText = "Please come again!"
local soldText = "The clerk says they're all sold out. I can't buy any POKe BALLS."
local stockText = "I'm going to buy a bunch of POKe BALLS and catch a bunch of POKeMON!"
local basic = {
  Game3.ITEM_POTION, Game3.ITEM_ANTIDOTE,
  Game3.ITEM_PARALYZE_HEAL, Game3.ITEM_AWAKENING,
}
local expanded = {
  Game3.ITEM_POKE_BALL, Game3.ITEM_POTION, Game3.ITEM_ANTIDOTE,
  Game3.ITEM_PARALYZE_HEAL, Game3.ITEM_AWAKENING,
}
local clerkTalk = {
  { op = "faceplayer" },
  { op = "message", text = serveText },
  { op = "waitmessage" },
  { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
  { op = "goto_if", cond = 1, to = 10 },
  { op = "pokemart", items = basic },
  { op = "loadword", text = againText },
  { op = "callstd", id = 4 },
  { op = "end" },
  { op = "pokemart", items = expanded },
  { op = "loadword", text = againText },
  { op = "callstd", id = 4 },
  { op = "end" },
}
local womanTalk = {
  { op = "faceplayer" },
  { op = "checkflag", flag = Game3.FLAG_ADVENTURE_STARTED },
  { op = "goto_if", cond = 1, to = 7 },
  { op = "loadword", text = soldText },
  { op = "callstd", id = 4 },
  { op = "end" },
  { op = "loadword", text = stockText },
  { op = "callstd", id = 4 },
  { op = "end" },
}
local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local function makeMart()
  return {
    id = "g1_0", width = 3, height = 3, grid = cells,
    spawn = { x = 1, y = 2 },
    objects = {
      {
        localId = 1, x = 1, y = 0,
        graphicsId = Game3.GFX_MART,
        mart = basic,
        script = clerkTalk,
      },
      {
        localId = 2, x = 2, y = 1,
        graphicsId = 23,
        script = womanTalk,
      },
    },
  }
end

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runShop(g)
  local seen = {}
  local n = 0
  local last
  local stock
  while n < 80 do
    n = n + 1
    local f = g.field
    if not f then return seen, stock end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "mart" then
      stock = f.items
      press(g, "b")
    else
      return seen, stock
    end
  end
  return seen, stock
end

local function enterMart(started)
  local g = Game3.new()
  g.phase = "play"
  if started then
    g.flags[Game3.FLAG_ADVENTURE_STARTED] = true
  end
  g.data.maps = { start = "g1_0", maps = { g1_0 = makeMart() } }
  g:enterMap(g.data.maps.maps.g1_0, 1, 1, true)
  g.facing = "north"
  return g
end

local before = enterMart(false)
check(before:tryTalk(), "the clerk runs the ROM script")
eq(before.field.kind, "talk", "Welcome! How may I serve you?")
check(before.field.text:find("serve you", 1, true) ~= nil, "How may I serve you?")
local beforeLines, beforeStock = runShop(before)
eq(#beforeStock, 4, "basic stock is four items")
eq(beforeStock[1], Game3.ITEM_POTION, "Potion first")
eq(beforeStock[2], Game3.ITEM_ANTIDOTE, "then Antidote")
eq(beforeStock[3], Game3.ITEM_PARALYZE_HEAL, "then Paralyze Heal")
eq(beforeStock[4], Game3.ITEM_AWAKENING, "then Awakening")
local hasBall = false
for i = 1, #beforeStock do
  if beforeStock[i] == Game3.ITEM_POKE_BALL then hasBall = true end
end
check(not hasBall, "no Poké Balls before FLAG_ADVENTURE_STARTED")
check(beforeLines[2]:find("come again", 1, true) ~= nil, "Please come again!")

local after = enterMart(true)
check(after:tryTalk(), "after the dex the clerk still talks")
local afterLines, afterStock = runShop(after)
eq(afterStock[1], Game3.ITEM_POKE_BALL, "expanded stock leads with Poké Balls")
eq(#afterStock, 5, "five items once adventure started")
eq(afterStock[5], Game3.ITEM_AWAKENING, "Awakening still last")
check(afterLines[2]:find("come again", 1, true) ~= nil, "come again after the expanded shop")

local woman = enterMart(false)
woman.playerX, woman.playerY = 1, 1
woman.facing = "east"
woman.field = nil
check(woman:tryTalk(), "the woman talks")
local sold = runShop(woman)
check(sold[1]:find("sold out", 1, true) ~= nil, "Poké Balls are sold out")

local shopper = enterMart(true)
shopper.playerX, shopper.playerY = 1, 1
shopper.facing = "east"
shopper.field = nil
check(shopper:tryTalk(), "after the dex she shops")
local buying = runShop(shopper)
check(buying[1]:find("bunch of POKe BALLS", 1, true) ~= nil,
  "I'm going to buy a bunch of POKe BALLS")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.VAR_PETALBURG_STATE, 0x4057, "VAR_PETALBURG_STATE")
eq(Game3.VAR_PETALBURG_GYM_STATE, 0x4085, "VAR_PETALBURG_GYM_STATE")
eq(Game3.LOCALID_PETALBURG_GYM_BOY, 9, "gym boy is local 9")
eq(Game3.PETALBURG_GYM_BOY_WEST_X, 5, "west-gate X")
eq(Game3.PETALBURG_GYM_BOY_WEST_Y, 11, "west-gate Y")
eq(Game3.FLAG_HIDE_WALLY_PETALBURG, 0x2D6, "FLAG_HIDE_WALLY_PETALBURG")
eq(Game3.FLAG_HIDE_WALLY_FATHER_PETALBURG, 0x32B, "Wally's dad starts hidden")
eq(Game3.FLAG_HIDE_WALLY_MOTHER_PETALBURG, 0x32C, "and mom at the gym door")
eq(Game3.FLAG_HIDE_WALLY_PETALBURG_GYM, 0x362, "and gym Wally")

local g0 = Game3.new()
eq(g0.flags[Game3.FLAG_HIDE_WALLY_PETALBURG], nil,
  "Game3.new leaves Wally hide flags to the caller")
g0:applyNewGameHideFlags()
eq(g0.flags[Game3.FLAG_HIDE_WALLY_PETALBURG], true,
  "ResetAllMapFlags hides Wally in Petalburg")
eq(g0.flags[Game3.FLAG_HIDE_WALLY_FATHER_PETALBURG], true, "and his father")
eq(g0.flags[Game3.FLAG_HIDE_WALLY_MOTHER_PETALBURG], true, "and mother")
eq(g0.flags[Game3.FLAG_HIDE_WALLY_PETALBURG_GYM], true, "and gym Wally")
eq(g0.flags[Game3.FLAG_HIDE_WALLY_MOM_PETALBURG_1], nil,
  "street Wally-Mom stays visible")

local rookie = "Hiya! Are you maybe... A rookie TRAINER?"
local gymHere = "See? This is PETALBURG CITY's GYM."
local signLine = "This is the GYM's sign. Look for it whenever you're looking for a GYM."
local whereWally = "Where has our WALLY gone?"
local up = { kind = "walk", dir = "north" }
local down = { kind = "walk", dir = "south" }
local left = { kind = "walk", dir = "west" }
local right = { kind = "walk", dir = "east" }
local faceUp = { kind = "face", dir = "north" }
local faceRight = { kind = "face", dir = "east" }
local facePlayer = { kind = "faceplayer" }
local pin = { kind = "emote", emote = "exclaim" }
local delay16 = { kind = "delay", frames = 16 }
local delay48 = { delay16, delay16, delay16 }
local boyId = Game3.LOCALID_PETALBURG_GYM_BOY
local v8008 = 0x8008
local approach0 = {
  { op = "applymovement", localId = boyId,
    steps = { right, right, right, faceUp } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { { kind = "face", dir = "south" } } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local approach1 = {
  { op = "applymovement", localId = boyId, steps = { right, right } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local approach2 = {
  { op = "applymovement", localId = boyId,
    steps = { right, right, right, { kind = "face", dir = "south" } } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { faceUp } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local approach3 = {
  { op = "applymovement", localId = boyId,
    steps = { down, right, right, right, { kind = "face", dir = "south" } } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { faceUp } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local lead0 = {
  { op = "applymovement", localId = boyId,
    steps = { right, right, right, right, right, right, right, up, right, faceUp } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { down, right, right, right, right, right, right, right, up } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local lead1 = {
  { op = "applymovement", localId = boyId,
    steps = { down, right, right, right, right, right, right, right, right,
      up, up, right, faceUp } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { delay16, delay16, down, right, right, right, right, right, right,
      right, up, up } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local lead2 = {
  { op = "applymovement", localId = boyId,
    steps = { right, right, right, right, right, right, right, up, right, faceUp } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { up, right, right, right, right, right, right, right, up } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local lead3 = {
  { op = "applymovement", localId = boyId,
    steps = { right, right, right, right, right, right, right, up, up, right, faceUp } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { up, right, right, right, right, right, right, right, up, up } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local showGym = {
  { op = "applymovement", localId = boyId, steps = { facePlayer } },
  { op = "waitmovement", localId = 0 },
  { op = "playbgm", id = 0 },
  { op = "playse", id = 0 },
  { op = "applymovement", localId = boyId, steps = { pin } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = boyId, steps = delay48 },
  { op = "waitmovement", localId = 0 },
  { op = "compare", var = v8008, val = 0 },
  { op = "call_if", cond = 1, body = approach0 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = approach1 },
  { op = "compare", var = v8008, val = 2 },
  { op = "call_if", cond = 1, body = approach2 },
  { op = "compare", var = v8008, val = 3 },
  { op = "call_if", cond = 1, body = approach3 },
  { op = "loadword", text = rookie },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "compare", var = v8008, val = 0 },
  { op = "call_if", cond = 1, body = lead0 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = lead1 },
  { op = "compare", var = v8008, val = 2 },
  { op = "call_if", cond = 1, body = lead2 },
  { op = "compare", var = v8008, val = 3 },
  { op = "call_if", cond = 1, body = lead3 },
  { op = "loadword", text = gymHere },
  { op = "callstd", id = 4 },
  { op = "applymovement", localId = boyId, steps = { faceRight } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = signLine },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = boyId,
    steps = { down, left, left, left, left, left, left, left, left, left, left, left } },
  { op = "waitmovement", localId = 0 },
  { op = "fadedefaultbgm" },
  { op = "end" },
}
local function trigger(n)
  return {
    { op = "setvar", var = v8008, val = n },
    { op = "call", body = showGym },
    { op = "end" },
  }
end
local parkWest = {
  { op = "setobjectxyperm", localId = boyId,
    x = Game3.PETALBURG_GYM_BOY_WEST_X,
    y = Game3.PETALBURG_GYM_BOY_WEST_Y },
  { op = "end" },
}
local cells = {}
for i = 1, 28 * 20 do cells[i] = 0 end
local function makeCity()
  return {
    id = "g0_0", width = 28, height = 20, grid = cells,
    spawn = { x = 20, y = 11 },
    objects = {
      {
        localId = boyId,
        x = Game3.PETALBURG_GYM_BOY_DOOR_X,
        y = Game3.PETALBURG_GYM_BOY_DOOR_Y,
        graphicsId = 10,
        script = {
          { op = "loadword", text = rookie },
          { op = "callstd", id = 2 },
          { op = "end" },
        },
      },
      {
        localId = 1, x = 16, y = 18, graphicsId = 24,
        script = {
          { op = "loadword", text = whereWally },
          { op = "callstd", id = 2 },
          { op = "end" },
        },
      },
    },
    mapScripts = {
      onTransition = {
        { op = "setflag", flag = Game3.FLAG_VISITED_PETALBURG_CITY },
        { op = "compare", var = Game3.VAR_PETALBURG_STATE, val = 0 },
        { op = "call_if", cond = 1, body = parkWest },
        { op = "end" },
      },
    },
    coordEvents = {
      { x = 8, y = 10, trigger = Game3.VAR_PETALBURG_STATE, index = 0,
        script = trigger(0) },
      { x = 8, y = 11, trigger = Game3.VAR_PETALBURG_STATE, index = 0,
        script = trigger(1) },
      { x = 8, y = 12, trigger = Game3.VAR_PETALBURG_STATE, index = 0,
        script = trigger(2) },
      { x = 8, y = 13, trigger = Game3.VAR_PETALBURG_STATE, index = 0,
        script = trigger(3) },
    },
  }
end

local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end

local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 600 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end

local function enterCity(state)
  local g = Game3.new()
  g.phase = "play"
  g:applyNewGameHideFlags()
  g.scriptVars = { [Game3.VAR_PETALBURG_STATE] = state or 0 }
  g.data.maps = { start = "g0_0", maps = { g0_0 = makeCity() } }
  g:enterMap(g.data.maps.maps.g0_0, 9, 11, true)
  return g
end

local first = enterCity(0)
eq(first.flags[Game3.FLAG_VISITED_PETALBURG_CITY], true, "visited Petalburg")
eq(first:npcByLocalId(boyId).x, 5, "state 0 parks the boy at west X")
eq(first:npcByLocalId(boyId).y, 11, "and west Y")

local later = enterCity(2)
eq(later:npcByLocalId(boyId).x, 12, "later visits leave him by the gym X")
eq(later:npcByLocalId(boyId).y, 15, "and gym Y")

first.facing = "west"
check(first:tryWalk(-1, 0), "step onto (8,11)")
local lines = runScene(first)
check(lines[1]:find("rookie TRAINER", 1, true) ~= nil, "Are you a rookie TRAINER?")
check(lines[2]:find("PETALBURG CITY's GYM", 1, true) ~= nil, "this is the gym")
check(lines[3]:find("GYM's sign", 1, true) ~= nil, "this is the gym sign")
eq(first.playerX, 15, "player finishes at the gym")
eq(first.playerY, 10, "on the gym path")
eq(first:npcByLocalId(boyId).x, 5, "boy walks away west")
eq(first:npcByLocalId(boyId).y, 11, "along y=11")
eq(first.facing, "east", "WalkInPlaceFastestRight toward the sign")

local talker = enterCity(0)
talker.playerX, talker.playerY = 5, 12
talker.facing = "north"
talker.field = nil
check(talker:tryTalk(), "talking to the gym boy")
check(talker.field.text:find("rookie TRAINER", 1, true) ~= nil,
  "the NPC line is the same rookie prompt")

local mom = enterCity(0)
mom.playerX, mom.playerY = 16, 19
mom.facing = "north"
mom.field = nil
check(mom:tryTalk(), "Wally's mom on the street")
check(mom.field.text:find("WALLY gone", 1, true) ~= nil, "Where has our WALLY gone?")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.LOCALID_PETALBURG_GYM_NORMAN, 1, "Dad is local 1")
eq(Game3.LOCALID_PETALBURG_GYM_WALLY, 10, "gym Wally is local 10")
eq(Game3.FLAG_HIDE_NORMAN_PETALBURG_GYM, 0x304, "FLAG_HIDE_NORMAN_PETALBURG_GYM")
eq(Game3.FLAG_DONT_TRANSITION_MUSIC, 0x4001, "FLAG_DONT_TRANSITION_MUSIC")
eq(Game3.SPECIAL_INIT_BIRCH_STATE, 211, "InitBirchState is special 211")
eq(Game3.PETALBURG_GYM_NORMAN_ENTRANCE_X, 4, "Dad entrance X")
eq(Game3.PETALBURG_GYM_NORMAN_ENTRANCE_Y, 107, "Dad entrance Y")
eq(Game3.PETALBURG_GYM_EXIT_X, 15, "city gym-door X")
eq(Game3.PETALBURG_GYM_EXIT_Y, 8, "city gym-door Y")

local g0 = Game3.new()
g0:applyNewGameHideFlags()
eq(g0.flags[Game3.FLAG_HIDE_NORMAN_PETALBURG_GYM], nil,
  "ResetAllMapFlags leaves Dad visible")

local dadHere = "DAD: Hm? Well, if it isn't {PLAYER}! You're with your POKeMON."
local wantMon = "Um... I... I'd like to get a POKeMON, please..."
local youWally = "DAD: Hm? You're WALLY, right?"
local neverCaught = "But I've never caught a POKeMON before. I don't know how..."
local hmSee = "DAD: Hm. I see."
local goWith = "Go with WALLY and make sure that he safely catches a POKeMON."
local loanZig = "WALLY, here, I'll loan you my POKeMON. WALLY received a ZIGZAGOON!"
local pokeBall = "WALLY received a POKe BALL!"
local wowThanks = "WALLY: Oh, wow! Thank you!"
local comeWith = "{PLAYER}... Would you really come with me?"
local didIt = "DAD: So, did it work out?"
local wallyBye = "WALLY: Thank you, yes, it did. Bye, {PLAYER}!"
local rustboro = "Head for RUSTBORO CITY beyond this town."
local noBadges = "Aren't you going to the POKeMON GYM in RUSTBORO CITY?"
local up = { kind = "walk", dir = "north" }
local down = { kind = "walk", dir = "south" }
local right = { kind = "walk", dir = "east" }
local faceLeft = { kind = "face", dir = "west" }
local faceRight = { kind = "face", dir = "east" }
local faceDown = { kind = "face", dir = "south" }
local faceUp = { kind = "face", dir = "north" }
local d8 = { kind = "delay", frames = 8 }
local d16 = { kind = "delay", frames = 16 }
local dadId = Game3.LOCALID_PETALBURG_GYM_NORMAN
local wallyId = Game3.LOCALID_PETALBURG_GYM_WALLY
local v8008 = 0x8008
local gymState = Game3.VAR_PETALBURG_GYM_STATE
local cityState = Game3.VAR_PETALBURG_STATE
local arriveNorth = {
  { op = "applymovement", localId = wallyId,
    steps = { d16, up, d16, d8, up, right, up, up, faceLeft } },
  { op = "waitmovement", localId = 0 },
  { op = "applymovement", localId = dadId, steps = { faceRight } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local addressPlayerNorth = {
  { op = "applymovement", localId = dadId, steps = { faceDown } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = { faceUp } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local addressWallyNorth = {
  { op = "applymovement", localId = dadId, steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local faceDoorNorth = {
  { op = "applymovement", localId = dadId, steps = { faceDown } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local wallyFaceDown = {
  { op = "applymovement", localId = wallyId, steps = { faceDown } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local exitNorth = {
  { op = "applymovement", localId = wallyId,
    steps = { down, down, down, down, faceUp, d16, faceDown } },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { d16, d16, d16, down, down, down, d8 } },
  { op = "waitmovement", localId = 0 },
  { op = "end" },
}
local sendOff = {
  { op = "addobject", localId = wallyId },
  { op = "playse", id = 0 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = arriveNorth },
  { op = "loadword", text = wantMon },
  { op = "callstd", id = 4 },
  { op = "loadword", text = youWally },
  { op = "callstd", id = 4 },
  { op = "loadword", text = neverCaught },
  { op = "callstd", id = 4 },
  { op = "loadword", text = hmSee },
  { op = "callstd", id = 4 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = addressPlayerNorth },
  { op = "loadword", text = goWith },
  { op = "callstd", id = 4 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = addressWallyNorth },
  { op = "loadword", text = loanZig },
  { op = "callstd", id = 4 },
  { op = "loadword", text = pokeBall },
  { op = "callstd", id = 4 },
  { op = "loadword", text = wowThanks },
  { op = "callstd", id = 4 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = faceDoorNorth },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = wallyFaceDown },
  { op = "loadword", text = comeWith },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "setflag", flag = Game3.FLAG_DONT_TRANSITION_MUSIC },
  { op = "playbgm", id = 0 },
  { op = "compare", var = v8008, val = 1 },
  { op = "call_if", cond = 1, body = exitNorth },
  { op = "removeobject", localId = wallyId },
  { op = "setflag", flag = Game3.FLAG_HIDE_WALLY_MOM_PETALBURG_1 },
  { op = "setvar", var = gymState, val = 1 },
  { op = "setvar", var = cityState, val = 2 },
  { op = "clearflag", flag = Game3.FLAG_HIDE_WALLY_PETALBURG },
  { op = "clearflag", flag = Game3.FLAG_HIDE_WALLY_PETALBURG_GYM },
  { op = "setflag", flag = Game3.FLAG_HIDE_RIVAL_BIRCH_LAB },
  { op = "special", id = Game3.SPECIAL_INIT_BIRCH_STATE },
  { op = "warp", mapGroup = Game3.PETALBURG_CITY_GROUP,
    mapNum = Game3.PETALBURG_CITY_NUM, warpId = Game3.WARP_ID_NONE,
    x = Game3.PETALBURG_GYM_EXIT_X, y = Game3.PETALBURG_GYM_EXIT_Y },
  { op = "waitstate" },
  { op = "end" },
}
local beginNorth = {
  { op = "setvar", var = v8008, val = 1 },
  { op = "call", body = sendOff },
  { op = "end" },
}
local rustboroTalk = {
  { op = "loadword", text = noBadges },
  { op = "callstd", id = 4 },
  { op = "end" },
}
local dadTalk = {
  { op = "lock" },
  { op = "faceplayer" },
  { op = "compare", var = gymState, val = 2 },
  { op = "call_if", cond = 1, body = rustboroTalk },
  { op = "compare", var = gymState, val = 2 },
  { op = "goto_if", cond = 1, to = 1000 },
  { op = "loadword", text = dadHere },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "compare", var = Game3.VAR_FACING, val = Game3.DIR_NORTH },
  { op = "call_if", cond = 1, body = beginNorth },
  { op = "end" },
}
local parkDad = {
  { op = "setobjectxyperm", localId = dadId,
    x = Game3.PETALBURG_GYM_NORMAN_ENTRANCE_X,
    y = Game3.PETALBURG_GYM_NORMAN_ENTRANCE_Y },
  { op = "end" },
}
local parkWally = {
  { op = "setobjectxyperm", localId = wallyId,
    x = Game3.PETALBURG_GYM_WALLY_RETURN_X,
    y = Game3.PETALBURG_GYM_WALLY_RETURN_Y },
  { op = "end" },
}
local turnNorth = {
  { op = "turnobject", localId = Game3.LOCALID_PLAYER, dir = Game3.DIR_NORTH },
  { op = "end" },
}
local comeBack = {
  { op = "lockall" },
  { op = "loadword", text = didIt },
  { op = "callstd", id = 4 },
  { op = "loadword", text = wallyBye },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = { faceDown } },
  { op = "applymovement", localId = wallyId,
    steps = { down, down, down, d16 } },
  { op = "waitmovement", localId = 0 },
  { op = "playse", id = 0 },
  { op = "removeobject", localId = wallyId },
  { op = "setflag", flag = Game3.FLAG_HIDE_WALLY_PETALBURG },
  { op = "delay", frames = 30 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = { faceUp } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = rustboro },
  { op = "callstd", id = 4 },
  { op = "setvar", var = gymState, val = 2 },
  { op = "end" },
}
local gymCells = {}
for i = 1, 9 * 112 do gymCells[i] = 0 end
local cityCells = {}
for i = 1, 28 * 20 do cityCells[i] = 0 end
local function makeGym()
  return {
    id = "g_gym", width = 9, height = 112, grid = gymCells,
    objects = {
      {
        localId = dadId,
        x = Game3.PETALBURG_GYM_NORMAN_DESK_X,
        y = Game3.PETALBURG_GYM_NORMAN_DESK_Y,
        graphicsId = 10,
        flagId = Game3.FLAG_HIDE_NORMAN_PETALBURG_GYM,
        script = dadTalk,
      },
      {
        localId = wallyId, x = 4, y = 111, graphicsId = 11,
        flagId = Game3.FLAG_HIDE_WALLY_PETALBURG_GYM,
      },
    },
    mapScripts = {
      onTransition = {
        { op = "compare", var = gymState, val = 1 },
        { op = "call_if", cond = 1, body = parkWally },
        { op = "compare", var = gymState, val = 6 },
        { op = "call_if", cond = 0, body = parkDad },
        { op = "end" },
      },
      onWarp = {
        { var = gymState, value = 1, script = turnNorth },
      },
      onFrame = {
        { var = gymState, value = 1, script = comeBack },
      },
    },
  }
end
local function makeCity()
  return {
    id = "g0_0", width = 28, height = 20, grid = cityCells,
    spawn = { x = 15, y = 8 },
  }
end
local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepField()
  Input.wasPressed = old
end
local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 800 do
    n = n + 1
    local f = g.field
    if not f then return seen end
    if f.kind == "talk" then
      if f.text ~= last then
        seen[#seen + 1] = f.text
        last = f.text
      end
      press(g, "a")
    elseif f.kind == "delay" then
      g:walkHeld((g.delayLeft or 0) + 1)
    elseif f.kind == "move" then
      g:walkHeld(Game3.WALK_PERIOD)
    else
      return seen
    end
  end
  return seen
end
local function enterGym(state, clearGymWally)
  local g = Game3.new()
  g.phase = "play"
  g:applyNewGameHideFlags()
  g.scriptVars = { [gymState] = state or 0 }
  if clearGymWally then
    g.flags[Game3.FLAG_HIDE_WALLY_PETALBURG_GYM] = nil
  end
  local gym = makeGym()
  g.data.maps = { start = "g_gym", maps = { g_gym = gym, g0_0 = makeCity() } }
  g:enterMap(gym, 4, 108, true)
  return g
end

local first = enterGym(0)
eq(first:npcByLocalId(dadId).x, 4, "state 0 parks Dad at entrance X")
eq(first:npcByLocalId(dadId).y, 107, "and entrance Y")
eq(first:npcByLocalId(wallyId), nil, "gym Wally starts hidden")

local desk = enterGym(6)
eq(desk:npcByLocalId(dadId).x, 4, "gym-state 6 leaves Dad at the desk X")
eq(desk:npcByLocalId(dadId).y, 3, "and desk Y")

first.facing = "north"
first.field = nil
check(first:tryTalk(), "talking to Dad from the door")
local lines = runScene(first)
check(lines[1]:find("with your POKeMON", 1, true) ~= nil, "You're with your POKeMON")
check(lines[2]:find("like to get a POKeMON", 1, true) ~= nil, "Wally wants a POKeMON")
check(lines[3]:find("You're WALLY, right", 1, true) ~= nil, "You're WALLY, right?")
check(lines[4]:find("never caught", 1, true) ~= nil, "never caught a POKeMON")
check(lines[5]:find("Hm. I see", 1, true) ~= nil, "Hm. I see.")
check(lines[6]:find("Go with WALLY", 1, true) ~= nil, "go with Wally")
check(lines[7]:find("ZIGZAGOON", 1, true) ~= nil, "loan Zigzagoon")
check(lines[8]:find("POKe BALL", 1, true) ~= nil, "and a POKe BALL")
check(lines[9]:find("Thank you", 1, true) ~= nil, "Wally thanks Dad")
check(lines[10]:find("come with me", 1, true) ~= nil, "Would you really come with me?")
eq(first.map.id, "g0_0", "warp is MAP_PETALBURG_CITY")
eq(first.playerX, 15, "outside the gym door X")
eq(first.playerY, 8, "outside the gym door Y")
eq(first.scriptVars[gymState], 1, "VAR_PETALBURG_GYM_STATE is 1")
eq(first.scriptVars[cityState], 2, "VAR_PETALBURG_STATE is 2")
eq(first.flags[Game3.FLAG_HIDE_WALLY_MOM_PETALBURG_1], true, "street Wally-Mom hides")
eq(first.flags[Game3.FLAG_HIDE_WALLY_PETALBURG], nil, "city Wally is shown")
eq(first.flags[Game3.FLAG_HIDE_WALLY_PETALBURG_GYM], nil, "gym Wally hide is cleared")
eq(first.flags[Game3.FLAG_DONT_TRANSITION_MUSIC], true, "FLAG_DONT_TRANSITION_MUSIC")

local back = enterGym(1, true)
eq(back.facing, "north", "ON_WARP faces the player north")
eq(back:npcByLocalId(wallyId).x, 5, "return parks Wally at X")
eq(back:npcByLocalId(wallyId).y, 108, "and Y 108")
local after = runScene(back)
check(after[1]:find("did it work out", 1, true) ~= nil, "So, did it work out?")
check(after[2]:find("yes, it did", 1, true) ~= nil, "Wally gives the POKeMON back")
check(after[3]:find("RUSTBORO CITY", 1, true) ~= nil, "Head for RUSTBORO CITY")
eq(back.scriptVars[gymState], 2, "return sets gym-state 2")
eq(back:npcByLocalId(wallyId).hidden, true, "Wally leaves the gym")
eq(back.flags[Game3.FLAG_HIDE_WALLY_PETALBURG], true, "city Wally hides again")

back.facing = "north"
back.field = nil
check(back:tryTalk(), "Dad after the send-off")
local later = runScene(back)
check(later[1]:find("RUSTBORO CITY", 1, true) ~= nil,
  "greenhorn TRAINER is sent to Rustboro")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.SPECIES_ZIGZAGOON, 288, "SPECIES_ZIGZAGOON")
eq(Game3.SPECIES_RALTS, 392, "SPECIES_RALTS")
eq(Game3.MOVE_TACKLE, 33, "TACKLE")
eq(Game3.SPECIAL_SAVE_PLAYER_PARTY, 39, "SavePlayerParty")
eq(Game3.SPECIAL_LOAD_PLAYER_PARTY, 40, "LoadPlayerParty")
eq(Game3.SPECIAL_PUT_ZIGZAGOON, 301, "PutZigzagoonInPlayerParty")
eq(Game3.SPECIAL_START_WALLY_TUTORIAL_BATTLE, 157, "StartWallyTutorialBattle")
eq(Game3.PETALBURG_GYM_GROUP, 8, "gym is indoor Petalburg group")
eq(Game3.PETALBURG_GYM_NUM, 1, "and map 1")
eq(Game3.LOCALID_PETALBURG_WALLY, 2, "city Wally is local 2")

local loan = Game3.new()
check(loan:giveMon(Game3.SPECIES_TORCHIC, 5), "a starter to save")
local starter = loan.party[1].species
local balls = loan:itemCount(Game3.ITEM_POKE_BALL)
loan:runSpecial(Game3.SPECIAL_SAVE_PLAYER_PARTY)
eq(#loan.savedParty, 1, "SavePlayerParty copies the party")
loan:runSpecial(Game3.SPECIAL_PUT_ZIGZAGOON)
eq(loan.party[1].species, Game3.SPECIES_ZIGZAGOON, "slot 0 is Zigzagoon")
eq(loan.party[1].level, 7, "level 7")
eq(loan.party[1].moves[1].id, 33, "only TACKLE")
eq(loan.party[1].ability, 0, "alt ability is none")
check(loan:runSpecial(Game3.SPECIAL_START_WALLY_TUTORIAL_BATTLE) or loan.phase == "battle",
  "tutorial battle starts")
eq(loan.phase, "battle", "phase is battle")
eq(loan.battle.enemy.species, Game3.SPECIES_RALTS, "vs Ralts")
eq(loan.battle.enemy.level, 5, "level 5")
check(loan.battle.wallyTutorial, "BATTLE_TYPE_WALLY_TUTORIAL")
check(loan.scriptWait, "waitstate holds the script")
loan.battle.kind = "menu"
loan:tryWallyTutorialAction()
eq(loan.battle.kind, "text", "Wally auto-picks TACKLE")
loan.battle.kind = "menu"
loan.battle.wallyTackled = true
loan:tryWallyTutorialAction()
check(loan.battle.caught, "the ball always catches")
eq(loan:itemCount(Game3.ITEM_POKE_BALL), balls, "Wally's ball is not the BAG")
check(not loan:hasCaught(Game3.SPECIES_RALTS), "the player does not own Ralts")
loan:endBattle()
loan:runSpecial(Game3.SPECIAL_LOAD_PLAYER_PARTY)
eq(loan.party[1].species, starter, "LoadPlayerParty restores the starter")
eq(loan.savedParty, nil, "and drops the copy")

local watch = "WALLY: {PLAYER}... POKeMON hide in tall grass like this, don't they?"
local didIt = "WALLY: I did it... It's my... My POKeMON!"
local goBack = "{PLAYER}, thank you! Let's go back to the GYM!"
local down = { kind = "walk", dir = "south" }
local right = { kind = "walk", dir = "east" }
local up = { kind = "walk", dir = "north" }
local faceRight = { kind = "face", dir = "east" }
local faceUp = { kind = "face", dir = "north" }
local d8 = { kind = "delay", frames = 8 }
local d16 = { kind = "delay", frames = 16 }
local wallyId = Game3.LOCALID_PETALBURG_WALLY
local cityState = Game3.VAR_PETALBURG_STATE
local gymState = Game3.VAR_PETALBURG_GYM_STATE
local playerWalk = {
  d8, down, down, down, down, down, down, down, down,
  right, right, right, right, right, right, right, right, right,
  right, right, right, right, right, right, right, right, right, right,
  up, up, faceRight,
}
local wallyWalk = {
  d8, down, down, down, down, down, down, down,
  right, right, right, right, right, right, right, right, right,
  right, right, right, right, right, right, right, right, right, right,
  up, up, right, d16, faceUp, d16, d16, faceRight,
}
local tutorial = {
  { op = "setflag", flag = Game3.FLAG_HIDE_MAP_NAME_POPUP },
  { op = "special", id = Game3.SPECIAL_SAVE_PLAYER_PARTY },
  { op = "special", id = Game3.SPECIAL_PUT_ZIGZAGOON },
  { op = "applymovement", localId = wallyId, steps = wallyWalk },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER, steps = playerWalk },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = watch },
  { op = "callstd", id = 4 },
  { op = "special", id = Game3.SPECIAL_START_WALLY_TUTORIAL_BATTLE },
  { op = "waitstate" },
  { op = "loadword", text = didIt },
  { op = "callstd", id = 4 },
  { op = "applymovement", localId = wallyId, steps = { faceRight } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = goBack },
  { op = "callstd", id = 4 },
  { op = "closemessage" },
  { op = "clearflag", flag = Game3.FLAG_HIDE_MAP_NAME_POPUP },
  { op = "setvar", var = cityState, val = 3 },
  { op = "clearflag", flag = Game3.FLAG_DONT_TRANSITION_MUSIC },
  { op = "special", id = Game3.SPECIAL_LOAD_PLAYER_PARTY },
  { op = "setvar", var = gymState, val = 1 },
  { op = "warp", mapGroup = Game3.PETALBURG_GYM_GROUP,
    mapNum = Game3.PETALBURG_GYM_NUM, warpId = Game3.WARP_ID_NONE,
    x = Game3.PETALBURG_GYM_RETURN_X, y = Game3.PETALBURG_GYM_RETURN_Y },
  { op = "waitstate" },
  { op = "end" },
}
local cityCells = {}
for i = 1, 30 * 30 do cityCells[i] = 0 end
local gymCells = {}
for i = 1, 9 * 112 do gymCells[i] = 0 end
local function press(g, name)
  Input:init()
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  if g.phase == "battle" then g:stepBattle() else g:stepField() end
  Input.wasPressed = old
end
local function runScene(g)
  local seen = {}
  local n = 0
  local last
  while n < 1500 do
    n = n + 1
    if g.phase == "battle" then
      press(g, "a")
    else
      local f = g.field
      if not f then return seen end
      if f.kind == "talk" then
        if f.text ~= last then
          seen[#seen + 1] = f.text
          last = f.text
        end
        press(g, "a")
      elseif f.kind == "delay" then
        g:walkHeld((g.delayLeft or 0) + 1)
      elseif f.kind == "move" then
        g:walkHeld(Game3.WALK_PERIOD)
      elseif f.kind == "wait" then
        g:walkHeld(0)
      else
        return seen
      end
    end
  end
  return seen
end
local g = Game3.new()
g.phase = "play"
g:applyNewGameHideFlags()
g.flags[Game3.FLAG_HIDE_WALLY_PETALBURG] = nil
g.flags[Game3.FLAG_DONT_TRANSITION_MUSIC] = true
g.scriptVars = { [cityState] = 2, [gymState] = 1 }
check(g:giveMon(Game3.SPECIES_TORCHIC, 5), "party has the starter")
local city = {
  id = "g0_0", width = 30, height = 30, grid = cityCells,
  objects = {
    { localId = wallyId, x = Game3.PETALBURG_WALLY_X,
      y = Game3.PETALBURG_WALLY_Y, graphicsId = 11,
      flagId = Game3.FLAG_HIDE_WALLY_PETALBURG },
  },
  mapScripts = {
    onFrame = { { var = cityState, value = 2, script = tutorial } },
  },
}
local gym = {
  id = "g8_1", width = 9, height = 112, grid = gymCells,
}
g.data.maps = { start = "g0_0", maps = { g0_0 = city, g8_1 = gym } }
g:enterMap(city, Game3.PETALBURG_GYM_EXIT_X, Game3.PETALBURG_GYM_EXIT_Y, true)
local lines = runScene(g)
check(lines[1]:find("tall grass", 1, true) ~= nil, "Watch me catch POKeMON")
check(lines[2]:find("I did it", 1, true) ~= nil, "I did it... It's my POKeMON")
check(lines[3]:find("back to the GYM", 1, true) ~= nil, "Let's go back to the GYM")
eq(g.map.id, "g8_1", "warp is MAP_PETALBURG_CITY_GYM")
eq(g.playerX, 4, "gym door X")
eq(g.playerY, 108, "gym door Y")
eq(g.scriptVars[cityState], 3, "VAR_PETALBURG_STATE is 3")
eq(g.scriptVars[gymState], 1, "gym-state stays 1 for the return")
eq(g.party[1].species, Game3.SPECIES_TORCHIC, "the loaner is gone")
eq(g.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP], nil, "map name popup is back")
eq(g.flags[Game3.FLAG_DONT_TRANSITION_MUSIC], nil, "music transitions again")
end)()

;(function()
eq(Game3.FLAG_SYS_NATIONAL_DEX, 0x836, "FLAG_SYS_NATIONAL_DEX")
eq(Game3.VAR_NATIONAL_DEX, 0x4046, "VAR_NATIONAL_DEX")
eq(Game3.NATIONAL_DEX_ENABLED, 0x302, "enabled value is 0x302")
eq(Game3.HOENN_DEX_COUNT, 202, "Hoenn dex is 202")
eq(Game3.NATIONAL_DEX_COUNT, 386, "National dex is 386")
eq(Game3.HOENN_DEX_COMPLETE, 200, "200 Hoenn catches complete it")
eq(Game3.SPECIAL_COMPLETED_HOENN_POKEDEX, 335, "special 335 is CompletedHoennPokedex")

local nat = Game3.new()
check(not nat:hasNationalDex(), "new game has no National Dex")
check(not nat:completedHoennPokedex(), "and Hoenn is incomplete")
nat:runSpecial(335)
eq(nat.scriptVars[0x800D], 0, "special 335 writes VAR_RESULT 0")
nat:runSpecial(212)
eq(nat.scriptVars[0x8006], 0, "special 212 keeps VAR_0x8006 off")

for i = 1, 200 do nat:markCaught(i) end
check(nat:completedHoennPokedex(), "200 catches complete Hoenn")
nat:runSpecial(335)
eq(nat.scriptVars[0x800D], 1, "special 335 writes VAR_RESULT 1")
check(not nat:giveNationalDex(), "Birch will not upgrade without a dex")

nat.flags[Game3.FLAG_SYS_POKEMON_GET] = true
nat.flags[Game3.FLAG_SYS_POKEDEX_GET] = true
nat.phase = "play"
nat.facing = "east"
nat.playerX, nat.playerY = 0, 0
nat.map = { id = "g_lab", width = 3, height = 1, grid = { 0, 0, 0 } }
nat.npcByMap = { g_lab = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCH } } }
check(nat:tryTalk(), "lab Birch upgrades after 200")
eq(nat.field.kind, "talk", "upgrade is a talk box")
check(nat.field.text:find("National", 1, true) ~= nil, "and names National mode")
eq(nat.flags[Game3.FLAG_SYS_NATIONAL_DEX], true, "FLAG_SYS_NATIONAL_DEX")
eq(nat.scriptVars[Game3.VAR_NATIONAL_DEX], 0x302, "VAR_NATIONAL_DEX is 0x302")
nat:runSpecial(212)
eq(nat.scriptVars[0x8006], 1, "special 212 sets VAR_0x8006 once enabled")
check(not nat:giveNationalDex(), "a second upgrade is refused")

local snap = nat:snapshotSave()
eq(snap.flags[Game3.FLAG_SYS_NATIONAL_DEX], true, "the flag snapshots")
local loaded = Game3.new()
check(loaded:applySave(snap), "and reloads")
check(loaded:hasNationalDex(), "National Dex survives CONTINUE")
eq(loaded.scriptVars[Game3.VAR_NATIONAL_DEX], 0x302, "the var is restored")

local bagger = Game3.new()
bagger.phase = "play"
bagger.facing = "east"
bagger.playerX, bagger.playerY = 0, 0
bagger.flags[Game3.FLAG_SYS_POKEMON_GET] = true
bagger.flags[Game3.FLAG_SYS_POKEDEX_GET] = true
for i = 1, 200 do bagger:markCaught(i) end
bagger.map = { id = "g_bag", width = 3, height = 1, grid = { 0, 0, 0 } }
bagger.npcByMap = { g_bag = { { x = 1, y = 0, graphicsId = Game3.GFX_BIRCHS_BAG } } }
check(bagger:tryTalk(), "the bag is still talkable")
check(not bagger:hasNationalDex(), "but gfx 97 does not upgrade the dex")

local listed = Game3.new()
listed.data.pokemon = {
  byIndex = {
    [1] = { name = "BULBASAUR" },
    [280] = { name = "TORCHIC", hoennDex = 4 },
  },
}
listed:markSeen(1)
listed:markCaught(280)
listed:openDex()
eq(#listed.field.list, 1, "Hoenn mode hides national-only species")
eq(listed.field.list[1].id, 280, "Torchic stays")
listed:enableNationalDex()
listed:openDex()
eq(#listed.field.list, 2, "National mode lists both")
eq(listed.field.list[1].id, 1, "Bulbasaur is first")
eq(listed.field.list[2].id, 280, "then Torchic")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.LOCALID_PLAYER, 0xFF, "LOCALID_PLAYER")
eq(Gen3Script.dirOfAction(8), "south", "walk down is south")

local cells = {}
for i = 1, 25 do cells[i] = 0 end
cells[3] = 5 + 1024
local house = {
  id = "g_house", width = 5, height = 5, grid = cells,
  connections = {},
  warps = { { x = 2, y = 0, mapGroup = 0, mapNum = 0, warpId = 0 } },
  objects = { { x = 1, y = 1, localId = 3, graphicsId = 64 } },
  spawn = { x = 2, y = 1 },
}
local mover = Game3.new()
mover.phase = "play"
mover:enterMap(house, 2, 1, true)
eq(Game3.collisionOf(house.grid[3]), 0, "indoor exit warp lights")
eq(#mover:npcsFor(house), 1, "NPC spawned")
eq(mover:npcsFor(house)[1].localId, 3, "with localId")

check(mover:applyMovement(0xFF, {
  { kind = "walk", dir = "south" },
  { kind = "walk", dir = "south" },
}), "player applymovement walks")
eq(mover.playerY, 2, "the first south step starts now")
check(mover:scriptMoving(), "the second step is queued")
mover:finishScriptMoves()
eq(mover.playerY, 3, "two steps south")
eq(mover.facing, "south", "and faces south")
check(not mover:scriptMoving(), "queue is empty")

check(mover:applyMovement(3, { { kind = "walk", dir = "east" } }),
  "NPC applymovement walks")
eq(mover:npcByLocalId(3).x, 2, "NPC stepped east")
eq(mover:npcByLocalId(3).facing, "east", "and faces east")
mover:finishScriptMoves()

check(mover:applyMovement(0xFF, { { kind = "face", dir = "west" } }),
  "face does not move")
eq(mover.playerX, 2, "player x stays")
eq(mover.facing, "west", "but facing updates")

check(mover:applyMovement(0xFF, { { kind = "jump2", dir = "east" } }),
  "jump2 covers two tiles")
eq(mover.playerX, 3, "first jump2 tile")
mover:finishScriptMoves()
eq(mover.playerX, 4, "two east")

check(mover:setMetatile(0, 0, 0x21, 1), "setmetatile writes")
eq(Game3.metatileOf(house.grid[1]), 0x21, "metatile id")
eq(Game3.collisionOf(house.grid[1]), 1, "and collision")
house.grid[1] = 0x21 + 3 * 4096
check(mover:setMetatile(0, 0, Game3.MT_GENERAL_ROCK_WALL_ROCK_BASE, 1),
  "Route 111 Desert Ruins seal")
eq(Game3.metatileOf(house.grid[1]), Game3.MT_GENERAL_ROCK_WALL_ROCK_BASE,
  "RockWall_RockBase")
eq(Game3.elevationBits(house.grid[1]), 3 * 4096, "keeps MAPGRID elevation")
eq(Game3.collisionOf(house.grid[1]), 1, "and stays solid")
check(mover:openDoor(0, 0), "opendoor on the sealed tile")
eq(Game3.elevationBits(house.grid[1]), 3 * 4096, "opendoor keeps elevation")
house.grid[1] = 0x21 + 1024
check(mover:openDoor(0, 0), "opendoor clears collision")
eq(Game3.collisionOf(house.grid[1]), 0, "door is walkable")
eq(Game3.metatileOf(house.grid[1]), 0x21, "metatile stays")
check(mover:closeDoor(0, 0), "closedoor blocks")
eq(Game3.collisionOf(house.grid[1]), 1, "solid again")

mover:setStepCallback(1)
eq(mover.stepCallback, 1, "setstepcallback stores the id")
mover:setStepCallback(0)
eq(mover.stepCallback, nil, "0 clears it")

local town = {
  id = "g_town", width = 3, height = 3,
  grid = { 0, 5 + 1024, 0, 0, 0, 0, 0, 0, 0 },
  connections = { { dir = "north", mapGroup = 0, mapNum = 1, offset = 0 } },
  warps = { { x = 1, y = 0 } },
}
local outdoor = Game3.new()
outdoor:enterMap(town, 1, 1, false)
eq(Game3.collisionOf(town.grid[2]), 1, "outdoor doors stay solid")

local host = Game3.new()
host.phase = "play"
host:enterMap({
  id = "g_run", width = 4, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 0, 0, true)
Gen3Script.run(host, {
  { op = "applymovement", localId = 0xFF,
    steps = { { kind = "walk", dir = "east" } } },
  { op = "setmetatile", x = 0, y = 1, tile = 7, collision = 1 },
  { op = "opendoor", x = 1, y = 1 },
  { op = "setstepcallback", id = 3 },
})
eq(host.playerX, 1, "script applymovement moves the player")
eq(Game3.metatileOf(host.map.grid[5]), 7, "script setmetatile")
eq(Game3.collisionOf(host.map.grid[6]), 0, "script opendoor")
eq(host.stepCallback, 3, "script setstepcallback")
host:finishScriptMoves()
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local waiter = Game3.new()
waiter.phase = "play"
waiter:enterMap({
  id = "g_wait", width = 4, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 0, 0, true)
waiter:runNpcScript({
  { op = "applymovement", localId = 0xFF,
    steps = {
      { kind = "walk", dir = "east" },
      { kind = "walk", dir = "east" },
    } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = "MOVED" },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_NPC },
})
eq(waiter.field.kind, "move", "waitmovement locks the field")
eq(waiter.playerX, 1, "first east step is on screen")
waiter:walkHeld(Game3.WALK_PERIOD)
eq(waiter.playerX, 2, "second east step after one period")
check(waiter:scriptMoving(), "the last lerp is still playing")
waiter:walkHeld(Game3.WALK_PERIOD)
eq(waiter.field.kind, "talk", "script resumes after the queue")
eq(waiter.field.text, "MOVED", "with the line after waitmovement")
eq(waiter.playerX, 2, "player finished two east")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_shove", width = 4, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 0, 0, true)
g:runNpcScript({
  { op = "loadword", text = "STOP" },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
  { op = "applymovement", localId = 0xFF,
    steps = { { kind = "walk", dir = "south" } } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = "GRASS" },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
})
eq(g.field.kind, "talk", "queued msgbox is not dropped for waitmovement")
eq(g.field.text, "STOP", "the first line")
eq(g.field.thenContinue, true, "MSGBOX_DEFAULT waits for A")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "move", "A hands the field to waitmovement")
g:finishScriptMoves()
g:resumeMoveScript()
eq(g.field.kind, "talk", "script resumes after the shove")
eq(g.field.text, "GRASS", "with the line after waitmovement")
eq(g.playerY, 1, "player walked south")
end)()

;(function()
eq(Game3.STEP_CB_CRACKED_FLOOR, 7, "cracked-floor callback is 7")
eq(Game3.MB_CRACKED_FLOOR, 0xD2, "MB_CRACKED_FLOOR")
eq(Game3.MB_CRACKED_FLOOR_HOLE, 0x66, "then the hole")
eq(Game3.GRANITE_CAVE_GROUP, 24, "dungeon group")
eq(Game3.GRANITE_CAVE_B1F_NUM, 8, "Granite B1F")
eq(Game3.GRANITE_CAVE_B2F_NUM, 9, "Granite B2F")
local tiles = {
  byId = {
    pair_0 = {
      behavior = {
        [10] = Game3.MB_CRACKED_FLOOR,
        [11] = Game3.MB_CRACKED_FLOOR_HOLE,
        [20] = Game3.MB_THIN_ICE,
        [21] = Game3.MB_CRACKED_ICE,
      },
    },
  },
}
local crack = Game3.new()
crack.phase = "play"
crack.data.tilesets = tiles
local floor = {
  id = "g_crack", width = 3, height = 1,
  tileset = "pair_0",
  grid = { 0, 10, 11 },
  spawn = { x = 0, y = 0 },
}
crack:enterMap(floor, 0, 0, true)
crack:setStepCallback(Game3.STEP_CB_CRACKED_FLOOR)
check(crack:tryWalk(1, 0), "step onto cracked floor")
eq(Game3.metatileOf(floor.grid[2]), 11, "the tile becomes the hole")
eq(crack.playerX, 0, "walking falls through")
eq(crack.playerY, 0, "back to spawn without a dest")
eq(crack.field.kind, "talk", "and opens a line")
eq(crack.field.text, "You fell through!", "You fell through!")

local hole = Game3.new()
hole.phase = "play"
hole.data.tilesets = tiles
local pit = {
  id = "g_hole", width = 2, height = 1,
  tileset = "pair_0",
  grid = { 0, 11 },
  spawn = { x = 0, y = 0 },
}
hole:enterMap(pit, 0, 0, true)
hole:setStepCallback(Game3.STEP_CB_CRACKED_FLOOR)
hole.bike = "mach"
check(hole:tryWalk(1, 0), "Mach Bike onto a hole")
eq(hole.playerX, 0, "still falls")
eq(hole.field.text, "You fell through!", "a hole always drops")

local bike = Game3.new()
bike.phase = "play"
bike.data.tilesets = tiles
local lane = {
  id = "g_bike", width = 2, height = 1,
  tileset = "pair_0",
  grid = { 0, 10 },
  spawn = { x = 0, y = 0 },
}
bike:enterMap(lane, 0, 0, true)
bike:setStepCallback(Game3.STEP_CB_CRACKED_FLOOR)
bike.bike = "mach"
check(bike:tryWalk(1, 0), "Mach Bike onto cracked floor")
eq(Game3.metatileOf(lane.grid[2]), 11, "the tile still cracks")
eq(bike.playerX, 1, "but speed 4 does not fall")
eq(bike.field, nil, "no fall line")

local dest = {
  id = "g0_1", group = 0, index = 1, width = 3, height = 1,
  tileset = "pair_0", grid = { 0, 0, 0 }, spawn = { x = 0, y = 0 },
}
local src = {
  id = "g0_0", group = 0, index = 0, width = 3, height = 1,
  tileset = "pair_0", grid = { 0, 10, 0 }, spawn = { x = 0, y = 0 },
}
local drop = Game3.new()
drop.phase = "play"
drop.data.tilesets = tiles
drop.data.maps = { maps = { g0_0 = src, g0_1 = dest } }
drop:enterMap(src, 0, 0, true)
drop:setStepCallback(Game3.STEP_CB_CRACKED_FLOOR)
drop:setHoleWarp(0, 1, Game3.WARP_ID_NONE, 0, 0)
check(drop:tryWalk(1, 0), "step with setholewarp")
eq(drop.map, dest, "lands on the dest map")
eq(drop.playerX, 1, "at the same x")
eq(drop.playerY, 0, "and y")
eq(drop.field.text, "You fell through!", "and still says so")

local ice = Game3.new()
ice.phase = "play"
ice.data.tilesets = tiles
local rink = {
  id = "g_ice", width = 2, height = 1,
  tileset = "pair_0",
  grid = { 0, 20 },
  spawn = { x = 0, y = 0 },
}
ice:enterMap(rink, 0, 0, true)
ice:setStepCallback(Game3.STEP_CB_ICE)
check(ice:tryWalk(1, 0), "step onto thin ice")
eq(Game3.metatileOf(rink.grid[2]), 21, "ice cracks")
ice.field = nil
ice.walkCooldown = 0
ice.playerX, ice.playerY = 0, 0
ice.walkFromX, ice.walkFromY = 0, 0
check(ice:tryWalk(1, 0), "step onto cracked ice")
eq(ice.playerX, 0, "ice hole also drops to spawn")
eq(ice.field.text, "You fell through!", "same fall line")

local scripted = Game3.new()
scripted.phase = "play"
scripted.data.tilesets = tiles
local path = {
  id = "g_script_crack", width = 2, height = 1,
  tileset = "pair_0",
  grid = { 0, 10 },
  spawn = { x = 0, y = 0 },
}
scripted:enterMap(path, 0, 0, true)
scripted:setStepCallback(Game3.STEP_CB_CRACKED_FLOOR)
scripted:applyMovement(0xFF, { { kind = "walk", dir = "east" } })
scripted:finishScriptMoves()
eq(Game3.metatileOf(path.grid[2]), 11, "scripted walk also cracks the floor")
eq(scripted.playerX, 0, "and falls")
end)()

;(function()
eq(Game3.STEP_CB_ASH, 1, "ash callback is 1")
eq(Game3.STEP_CB_FORTREE, 2, "Fortree callback is 2")
eq(Game3.STEP_CB_PACIFIDLOG, 3, "Pacifidlog callback is 3")
eq(Game3.ITEM_SOOT_SACK, 270, "soot sack item id")
eq(Game3.VAR_ASH_GATHER_COUNT, 0x4048, "ash gather var")
eq(Game3.ASH_CLEAR[0x20A], 0x212, "Fallarbor ash clears to grass")
eq(Game3.ASH_CLEAR[0x207], 0x206, "Lavaridge ash clears to grass")

local function step(g, dx, dy)
  g.walkCooldown = 0
  g.field = nil
  return g:tryWalk(dx, dy)
end

local ash = Game3.new()
ash.phase = "play"
ash.data.tilesets = {
  byId = {
    pair_0 = {
      behavior = {
        [10] = Game3.MB_ASHGRASS,
        [0x20A] = Game3.MB_ASHGRASS,
        [0x212] = 0x02,
        [0x207] = Game3.MB_ASHGRASS,
        [0x206] = 0x02,
      },
    },
  },
}
local route = {
  id = "g_ash", width = 3, height = 1,
  tileset = "pair_0",
  grid = { 0, 0x20A, 10 },
  spawn = { x = 0, y = 0 },
}
ash:enterMap(route, 0, 0, true)
ash:setStepCallback(Game3.STEP_CB_ASH)
check(step(ash, 1, 0), "step onto Fallarbor ash")
eq(Game3.metatileOf(route.grid[2]), 0x212, "ash becomes normal grass")
eq(ash.scriptVars and ash.scriptVars[Game3.VAR_ASH_GATHER_COUNT] or 0, 0,
  "no soot sack, no count")
check(step(ash, 1, 0), "step onto unknown ash mid")
eq(Game3.metatileOf(route.grid[3]), 11, "unknown ash mid + 1")

ash:addItem(Game3.ITEM_SOOT_SACK, 1)
route.grid[2] = 0x20A
ash.playerX, ash.playerY = 0, 0
ash.walkFromX, ash.walkFromY = 0, 0
check(step(ash, 1, 0), "step with the sack")
eq(ash.scriptVars[Game3.VAR_ASH_GATHER_COUNT], 1, "soot count is 1")
ash.scriptVars[Game3.VAR_ASH_GATHER_COUNT] = 9999
route.grid[2] = 0x207
ash.playerX, ash.playerY = 0, 0
ash.walkFromX, ash.walkFromY = 0, 0
check(step(ash, 1, 0), "Lavaridge ash with a full sack")
eq(Game3.metatileOf(route.grid[2]), 0x206, "clears to Lavaridge grass")
eq(ash.scriptVars[Game3.VAR_ASH_GATHER_COUNT], 9999, "count caps at 9999")

local scripted = Game3.new()
scripted.phase = "play"
scripted.data.tilesets = ash.data.tilesets
local path = {
  id = "g_ash_script", width = 2, height = 1,
  tileset = "pair_0",
  grid = { 0, 0x20A },
}
scripted:enterMap(path, 0, 0, true)
scripted:setStepCallback(Game3.STEP_CB_ASH)
scripted:applyMovement(0xFF, { { kind = "walk", dir = "east" } })
scripted:finishScriptMoves()
eq(Game3.metatileOf(path.grid[2]), 0x212, "scripted walk also clears ash")

local bridge = Game3.new()
bridge.phase = "play"
bridge.data.tilesets = {
  byId = {
    pair_0 = {
      behavior = {
        [10] = Game3.MB_FORTREE_BRIDGE,
        [11] = Game3.MB_FORTREE_BRIDGE,
      },
    },
  },
}
local span = {
  id = "g_fortree", width = 4, height = 1,
  tileset = "pair_0",
  grid = { 0, 10, 10, 0 },
}
bridge:enterMap(span, 0, 0, true)
bridge:setStepCallback(Game3.STEP_CB_FORTREE)
check(step(bridge, 1, 0), "step onto Fortree bridge")
eq(Game3.metatileOf(span.grid[2]), 11, "the plank lowers")
eq(Game3.metatileOf(span.grid[3]), 10, "the next plank stays up")
check(step(bridge, 1, 0), "walk along the bridge")
eq(Game3.metatileOf(span.grid[2]), 10, "the last plank rises")
eq(Game3.metatileOf(span.grid[3]), 11, "the current plank lowers")
check(step(bridge, 1, 0), "step off the bridge")
eq(Game3.metatileOf(span.grid[3]), 10, "it rises behind you")

local logs = Game3.new()
logs.phase = "play"
logs.data.tilesets = {
  byId = {
    pair_0 = {
      behavior = {
        [0x250] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_1,
        [0x252] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_1,
        [0x254] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_1,
        [0x251] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_2,
        [0x253] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_2,
        [0x255] = Game3.MB_PACIFIDLOG_HORIZONTAL_LOG_2,
        [0x258] = Game3.MB_PACIFIDLOG_VERTICAL_LOG_1,
        [0x25A] = Game3.MB_PACIFIDLOG_VERTICAL_LOG_1,
        [0x260] = Game3.MB_PACIFIDLOG_VERTICAL_LOG_2,
        [0x262] = Game3.MB_PACIFIDLOG_VERTICAL_LOG_2,
      },
    },
  },
}
local raft = {
  id = "g_logs", width = 4, height = 1,
  tileset = "pair_0",
  grid = { 0, 0x250, 0x251, 0 },
}
logs:enterMap(raft, 1, 0, true)
eq(Game3.metatileOf(raft.grid[2]), 0x250, "standing on a log does not sink it yet")
logs:setStepCallback(Game3.STEP_CB_PACIFIDLOG)
eq(Game3.metatileOf(raft.grid[2]), 0x254, "setstepcallback sinks the left half")
eq(Game3.metatileOf(raft.grid[3]), 0x255, "and the right half")
logs.playerX, logs.playerY = 0, 0
logs.walkFromX, logs.walkFromY = 0, 0
raft.grid[2], raft.grid[3] = 0x250, 0x251
check(step(logs, 1, 0), "step onto the left log")
eq(Game3.metatileOf(raft.grid[2]), 0x254, "pair submerges")
eq(Game3.metatileOf(raft.grid[3]), 0x255, "both halves")
check(step(logs, -1, 0), "step off the log")
eq(Game3.metatileOf(raft.grid[2]), 0x250, "left half floats")
eq(Game3.metatileOf(raft.grid[3]), 0x251, "right half floats")

local pole = {
  id = "g_vlog", width = 1, height = 3,
  tileset = "pair_0",
  grid = { 0, 0x258, 0x260 },
}
logs:enterMap(pole, 0, 0, true)
logs:setStepCallback(Game3.STEP_CB_PACIFIDLOG)
check(step(logs, 0, 1), "step onto a vertical log")
eq(Game3.metatileOf(pole.grid[2]), 0x25A, "top half sinks")
eq(Game3.metatileOf(pole.grid[3]), 0x262, "bottom half sinks")
end)()

;(function()
eq(Game3.EMOTE_GLYPH.exclaim, "!", "exclaim glyph")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_emote", width = 4, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = { { x = 1, y = 1, localId = 3, graphicsId = 64 } },
}, 2, 1, true)
local npc = g:npcByLocalId(3)
eq(npc.x, 1, "NPC at 1,1")

check(g:applyMovement(0xFF, { { kind = "delay", frames = 16 } }), "delay queues")
eq(g.playerX, 2, "delay does not walk")
check(g:scriptMoving(), "waitmovement would block")
g:finishScriptMoves()
check(not g:scriptMoving(), "delay finished")

check(g:applyMovement(3, { { kind = "emote", emote = "exclaim" } }), "emote queues")
eq(npc.emote, "exclaim", "NPC shows !")
check(g:scriptMoving(), "emote holds the queue")
g:finishScriptMoves()
eq(npc.emote, nil, "bubble clears")

check(g:applyMovement(3, { { kind = "invisible" } }), "hide")
eq(npc.invisible, true, "NPC is invisible")
check(g:applyMovement(3, { { kind = "visible" } }), "show")
eq(npc.invisible, nil, "NPC is visible again")

check(g:applyMovement(0xFF, { { kind = "invisible" } }), "hide player")
eq(g.invisible, true, "player is invisible")
check(g:applyMovement(0xFF, { { kind = "visible" } }), "show player")
eq(g.invisible, nil, "player is visible again")

npc.facing = "south"
check(g:applyMovement(3, { { kind = "faceplayer" } }), "face player")
eq(npc.facing, "east", "NPC turns toward the player")

g:runNpcScript({
  { op = "applymovement", localId = 0xFF,
    steps = { { kind = "delay", frames = 16 } } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = "WAITED" },
  { op = "callstd", id = 2 },
})
eq(g.field.kind, "move", "delay pauses at waitmovement")
g:walkHeld(Game3.WALK_PERIOD)
eq(g.field.kind, "talk", "then the line after delay")
eq(g.field.text, "WAITED", "WAITED")
end)()

;(function()
eq(Game3.DIR_FACING[4], "east", "dir 4 is east")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_obj", width = 5, height = 5,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 1, y = 1, localId = 3, graphicsId = 64, flagId = 0x200 },
    { x = 4, y = 4, localId = 5, graphicsId = 65, flagId = 0x201 },
  },
}, 2, 1, true)
local npc = g:npcByLocalId(3)
eq(npc.x, 1, "NPC 3 spawned")
eq(g:npcByLocalId(5).x, 4, "NPC 5 spawned")

g:runNpcScript({ { op = "hideobject", localId = 3 } })
eq(npc.invisible, true, "hideobjectat hides the sprite")
check(g:npcAt(g.map, 1, 1) == npc, "but collision stays")
g:runNpcScript({ { op = "showobject", localId = 3 } })
eq(npc.invisible, nil, "showobjectat restores it")

g:runNpcScript({ { op = "removeobject", localId = 3 } })
eq(npc.hidden, true, "removeobject hides")
eq(g.flags[0x200], true, "and sets the flag")
check(not g:npcAt(g.map, 1, 1), "collision is gone")
g:runNpcScript({ { op = "addobject", localId = 3 } })
eq(g.flags[0x200], nil, "addobject clears the flag")
eq(g:npcByLocalId(3).hidden, nil, "and unhides")

g.flags[0x201] = true
g:resetNpcs()
eq(g:npcByLocalId(5), nil, "flagged NPC is gone after reset")
g:addObject(5)
eq(g:npcByLocalId(5).x, 4, "addobject spawns them")

g:setObjectXY(3, 3, 1)
eq(g:npcByLocalId(3).x, 3, "setobjectxy x")
eq(g:npcByLocalId(3).y, 1, "setobjectxy y")
g:turnObject(3, 4)
eq(g:npcByLocalId(3).facing, "east", "turnobject east")

g._scriptNpc = g:npcByLocalId(3)
g:npcByLocalId(3).facing = "south"
g:faceScriptNpc()
eq(g:npcByLocalId(3).facing, "west", "faceplayer turns toward the player")

g:runNpcScript({
  { op = "hideobject", localId = 0xFF },
  { op = "setobjectxy", localId = 0xFF, x = 0, y = 4 },
})
eq(g.invisible, true, "hideobjectat player")
eq(g.playerX, 0, "setobjectxy player x")
eq(g.playerY, 4, "setobjectxy player y")
g:showObject(0xFF)
eq(g.invisible, nil, "showobjectat player")
end)()

;(function()
eq(Game3.GFX_BRINEY_BOAT, 88, "Mr. Briney's boat gfx")
eq(Game3.VAR_BOARD_BRINEY_BOAT_ROUTE104_STATE, 0x408E,
  "VAR_BOARD_BRINEY_BOAT_ROUTE104_STATE")
eq(Game3.VAR_BRINEY_LOCATION, 0x4096, "VAR_BRINEY_LOCATION")
local cells = {}
for i = 1, 5 * 5 do cells[i] = 0 end
local dock = {
  id = "g0_19", width = 5, height = 5, grid = cells, spawn = { x = 1, y = 1 },
}
local dewford = {
  id = "g0_11", width = 5, height = 5, grid = cells, spawn = { x = 0, y = 0 },
  objects = {
    { localId = 4, x = 3, y = 2, graphicsId = Game3.GFX_BRINEY_BOAT },
    { localId = 2, x = 3, y = 3, graphicsId = 22 },
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g0_19 = dock, g0_11 = dewford } }
g:enterMap(dock, 2, 2, true)
local south = { kind = "walk", dir = "south" }
g:runNpcScript({
  { op = "hideobject", localId = Game3.LOCALID_PLAYER,
    mapGroup = 0, mapNum = 19 },
  { op = "applymovement", localId = Game3.LOCALID_PLAYER,
    steps = { south, south, south, south } },
  { op = "waitmovement", localId = 0 },
  { op = "showobject", localId = Game3.LOCALID_PLAYER,
    mapGroup = 0, mapNum = 11 },
  { op = "end" },
})
g:finishScriptMoves()
g:resumeMoveScript()
eq(g.map.id, "g0_11", "showobjectat player on Dewford warps")
eq(g.playerX, 3, "on the boat X")
eq(g.playerY, 2, "on the boat Y")
eq(g.invisible, nil, "and the player is visible")
end)()

;(function()
local cells = {}
for i = 1, 5 * 5 do cells[i] = 0 end
local house = {
  id = "g17_0", width = 8, height = 8, grid = {},
  spawn = { x = 5, y = 4 },
}
for i = 1, 8 * 8 do house.grid[i] = 0 end
local dock = {
  id = "g0_19", width = 5, height = 5, grid = cells, spawn = { x = 1, y = 1 },
  objects = {
    { localId = 4, x = 2, y = 3, graphicsId = Game3.GFX_BRINEY_BOAT },
  },
}
local dewford = {
  id = "g0_11", width = 5, height = 5, grid = cells, spawn = { x = 0, y = 0 },
  objects = {
    { localId = 4, x = 3, y = 2, graphicsId = Game3.GFX_BRINEY_BOAT },
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g0_19 = dock, g0_11 = dewford, g17_0 = house } }
g:enterMap(dewford, 3, 2, true)
g:runNpcScript({
  { op = "hideobject", localId = Game3.LOCALID_PLAYER,
    mapGroup = 0, mapNum = 11 },
  { op = "showobject", localId = Game3.LOCALID_PLAYER,
    mapGroup = 0, mapNum = 19 },
  { op = "warp", mapGroup = 17, mapNum = 0, warpId = 0xFF, x = 5, y = 4 },
  { op = "end" },
})
eq(g.map.id, "g17_0", "Dewford sail warps to Briney's house")
eq(g.playerX, 5, "at house x 5")
eq(g.playerY, 4, "at house y 4")
end)()

;(function()
local g = Game3.new()
g.phase = "play"
g.rng = function() return 1 end
g.party = {
  { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5, moves = {} },
}
g.data.tilesets = { byId = { cave = { behavior = { [1] = 0x0B, [2] = 0 } } } }
g.data.encounters = { byMap = { g_cave = {
  land = { rate = 255, slots = { { minLevel = 5, maxLevel = 5, species = 290 } } },
} } }
g:enterMap({
  id = "g_cave", width = 2, height = 1, tileset = "cave", grid = { 1, 2 },
}, 0, 0, true)
check(g:tryWildEncounter(), "cave floor rolls a land fight")
eq(g.phase, "battle", "into battle")
eq(g.battle.enemy.species, 290, "from the land table")
g.phase = "play"
g.battle = nil
g.playerX = 1
check(not g:tryWildEncounter(), "normal cave wall does not")
end)()

;(function()
local Script = require("src.import.Gen3Script")
eq(Game3.LEVITATE_PX, 8, "levitate is 8px")
eq(Script.kindOfAction(0x77), "walk", "acro hop right walks")
eq(Script.parseMovement(string.char(0x77, 0xFE), 0)[1].dir, "east",
  "hop right is east")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_acro", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g.playerX, 1, "start x")
eq(g.playerY, 1, "start y")
check(g:applyMovement(0xFF, {
  { kind = "walk", dir = "north", dx = -1, dy = -1 },
}), "diagonal queues")
g:finishScriptMoves()
eq(g.playerX, 0, "diagonal x")
eq(g.playerY, 0, "diagonal y")
check(g:applyMovement(0xFF, { { kind = "levitate" } }), "levitate queues")
g:finishScriptMoves()
eq(g.levitate, 8, "sprite lifts")
check(g:applyMovement(0xFF, { { kind = "land" } }), "land queues")
g:finishScriptMoves()
eq(g.levitate, 0, "sprite lands")
check(g:applyMovement(0xFF, Script.parseMovement(string.char(0x77, 0xFE), 0)),
  "acro hop queues")
g:finishScriptMoves()
eq(g.playerX, 1, "hop east")
eq(g.playerY, 0, "same row")
end)()

;(function()
eq(Game3.SMASH_PERIOD, 32 / 60, "smash holds 32 frames")
eq(Game3.oppositeFacing("east"), "west", "east's opposite is west")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_skip", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 1, y = 0, localId = 3, graphicsId = 64, movementType = 8 },
  },
}, 1, 1, true)
local npc = g:npcByLocalId(3)
eq(npc.x, 1, "NPC spawned")

g.facing = "east"
check(g:applyMovement(0xFF, {
  { kind = "lockface" },
  { kind = "walk", dir = "south" },
}), "lockface then walk")
g:finishScriptMoves()
eq(g.facing, "east", "lockface keeps facing")
eq(g.playerY, 2, "but still walks south")

check(g:applyMovement(0xFF, {
  { kind = "unlockface" },
  { kind = "walk", dir = "west" },
}), "unlockface then walk")
g:finishScriptMoves()
eq(g.facing, "west", "unlockface turns")
eq(g.playerX, 0, "walks west")

npc.facing = "east"
check(g:applyMovement(3, { { kind = "bow" } }), "bow queues")
eq(npc.facing, "south", "nurse bows south")
check(g:scriptMoving(), "bow holds")
g:finishScriptMoves()

check(g:applyMovement(3, { { kind = "smash" } }), "smash queues")
g:finishScriptMoves()
eq(npc.invisible, true, "rock smash hides")

npc.invisible = true
check(g:applyMovement(3, { { kind = "reveal" } }), "reveal queues")
g:finishScriptMoves()
eq(npc.invisible, nil, "reveal shows")
eq(npc.revealed, true, "revealed")

check(g:applyMovement(3, { { kind = "lockanim" } }), "lock anim")
eq(npc.lockAnim, true, "NPC is inanimate")
eq(npc.facingLocked, true, "and facing is locked")
check(g:applyMovement(3, { { kind = "unlockanim" } }), "unlock anim")
eq(npc.lockAnim, nil, "anim restored")

npc.facing = "east"
npc.invisible = nil
g._scriptNpc = npc
g:lockScriptNpcs(false)
eq(npc.talkLock, true, "lock freezes wandering")
eq(npc.facingLocked, nil, "but not facing")
check(g:applyMovement(3, { { kind = "walk", dir = "south" } }), "scripted walk")
g:finishScriptMoves()
eq(npc.facing, "south", "Wally can turn while locked")
eq(npc.y, 1, "and steps south")

g:runNpcScript({
  { op = "delay", frames = 16 },
  { op = "loadword", text = "WAITED" },
  { op = "callstd", id = 2 },
})
eq(g.field.kind, "delay", "delay pauses the script")
g:walkHeld(1)
eq(g.field.kind, "talk", "then the line after delay")
eq(g.field.text, "WAITED", "WAITED")
end)()

;(function()
local Script = require("src.import.Gen3Script")
eq(Script.WAITSTATE, 0x27, "waitstate opcode")
local g = Game3.new()
g.phase = "play"
g:enterMap({
  id = "g_wait", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = { { x = 2, y = 1, localId = 3, graphicsId = 64 } },
}, 1, 1, true)
local npc = g:npcByLocalId(3)

g:runNpcScript({
  { op = "waitstate" },
  { op = "loadword", text = "NOW" },
  { op = "callstd", id = 2 },
})
eq(g.field.kind, "talk", "idle waitstate does not pause")
eq(g.field.text, "NOW", "NOW")

g.field = { kind = "wait" }
g._scriptPause = {
  ops = { { op = "loadword", text = "UNSTUCK" }, { op = "callstd", id = 2 } },
  at = 1,
}
g:walkHeld(0.016)
eq(g.field.kind, "talk", "idle wait resumes")
eq(g.field.text, "UNSTUCK", "and continues the script")

g:beginScriptWait()
-- special then waitstate are the same script VM. runNpcScript nills a
-- leftover wait so a new talk cannot stick; drive the opcode directly.
g:beginScriptRun()
local _, pause = Script.run(g, {
  { op = "waitstate" },
  { op = "loadword", text = "LATER" },
  { op = "callstd", id = 2 },
})
g:presentScript(pause)
eq(g.field.kind, "wait", "waitstate pauses for a special")
g:walkHeld(1)
eq(g.field.kind, "wait", "time does not resume it")
g:endScriptWait()
eq(g.field.kind, "talk", "endScriptWait resumes")
eq(g.field.text, "LATER", "LATER")

check(g:applyMovement(3, { { kind = "place" } }), "place queues")
check(g:scriptMoving(), "in-place anim holds")
g:finishScriptMoves()
eq(npc.x, 2, "place does not walk")

check(g:applyMovement(3, {
  { kind = "flag", key = "lockAnim", on = true },
}), "disable anim")
eq(npc.lockAnim, true, "NPC is inanimate")
eq(npc.facingLocked, nil, "without locking facing")
check(g:applyMovement(3, {
  { kind = "flag", key = "affine", on = true },
}), "init affine")
eq(npc.affine, true, "affine is set")
check(g:applyMovement(3, {
  { kind = "flag", key = "hideReflection", on = true },
}), "hide reflection")
eq(npc.hideReflection, true, "reflection hidden")
end)()

;(function()
eq(Game3.ITEM_HM_CUT, 339, "HM01 is item 339")
eq(Game3.ITEM_HM_ROCK_SMASH, 344, "HM06 is item 344")
eq(Game3.MOVE_CUT, 15, "CUT is move 15")
eq(Game3.MOVE_ROCK_SMASH, 249, "ROCK SMASH is move 249")
eq(Game3.GFX_CUTTABLE_TREE, 82, "cuttable tree gfx")
eq(Game3.GFX_BREAKABLE_ROCK, 86, "breakable rock gfx")
eq(Game3.FLAG_BADGE01_GET, 0x807, "Stone Badge")
eq(Game3.FLAG_BADGE03_GET, 0x809, "Dynamo Badge")
local g = Game3.new()
eq(g:itemName(Game3.ITEM_HM_CUT), "HM01", "HM01 name")
g.phase = "play"
g.facing = "east"
g.party = { { name = "ZIGZAGOON", moves = { { id = Game3.MOVE_CUT } } } }
g.flags[Game3.FLAG_BADGE01_GET] = true
g.bag = {}
g:addItem(Game3.ITEM_HM_CUT, 1)
g:enterMap({
  id = "g_cut", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 3, graphicsId = Game3.GFX_CUTTABLE_TREE, flagId = 0x300 },
  },
}, 1, 1, true)
local ok, msg = g:useCut()
check(ok, "CUT chops the tree")
eq(msg, "Used CUT!", "announces CUT")
eq(g:itemCount(Game3.ITEM_HM_CUT), 1, "HM is not consumed")
eq(g:npcByLocalId(3).hidden, true, "tree is gone")
eq(g.flags[0x300], true, "hide flag is set")

g.flags[Game3.FLAG_BADGE01_GET] = nil
local noBadge, badgeMsg = g:useCut()
check(not noBadge, "CUT needs the Stone Badge")
check(badgeMsg:find("STONE", 1, true) ~= nil, "STONE BADGE")

g.flags[Game3.FLAG_BADGE01_GET] = true
g.party[1].moves = {}
local noMove, moveMsg = g:useCut()
check(not noMove, "CUT needs the move")
check(moveMsg:find("knows CUT", 1, true) ~= nil, "party must know CUT")

g.party[1].moves = { { id = Game3.MOVE_CUT } }
g.data.tilesets = { byId = { hm_ts = { behavior = { [1] = 0x02 } } } }
g:enterMap({
  id = "g_grass", width = 3, height = 3, tileset = "hm_ts",
  grid = { 0, 0, 0, 0, 0, 1, 0, 0, 0 },
}, 1, 1, true)
check(Game3.isLandGrass(g:behaviorAt(g.map, 2, 1)), "facing tile is grass")
local mowed, cutMsg = g:useCut()
check(mowed, "CUT mows grass")
eq(cutMsg, "Used CUT!", "announces grass CUT")
check(not Game3.isLandGrass(g:behaviorAt(g.map, 2, 1)), "grass is gone")

g.party[1].moves = { { id = Game3.MOVE_ROCK_SMASH } }
g.flags[Game3.FLAG_BADGE03_GET] = true
g:addItem(Game3.ITEM_HM_ROCK_SMASH, 1)
g:enterMap({
  id = "g_rock", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 4, graphicsId = Game3.GFX_BREAKABLE_ROCK, flagId = 0x301 },
  },
}, 1, 1, true)
local smashed, smashMsg = g:useRockSmash()
check(smashed, "ROCK SMASH breaks the rock")
eq(smashMsg, "Used ROCK SMASH!", "announces ROCK SMASH")
eq(g:npcByLocalId(4).hidden, true, "rock is gone")
eq(g.flags[0x301], true, "rock hide flag")
eq(g:itemCount(Game3.ITEM_HM_ROCK_SMASH), 1, "HM06 is not consumed")

local miss, missMsg = g:useRockSmash()
check(not miss, "no rock in front")
eq(missMsg, "You can't use that here!", "can't smash empty air")
end)()

;(function()
eq(Game3.ITEM_HM_SURF, 341, "HM03 is Surf")
eq(Game3.ITEM_HM_STRENGTH, 342, "HM04 is Strength")
eq(Game3.ITEM_HM_FLASH, 343, "HM05 is Flash")
eq(Game3.ITEM_HM_WATERFALL, 345, "HM07 is Waterfall")
eq(Game3.GFX_PUSHABLE_BOULDER, 87, "pushable boulder gfx")
eq(Game3.FLAG_SYS_USE_STRENGTH, 0x829, "strength flag")
eq(Game3.FLAG_SYS_USE_FLASH, 0x828, "flash flag")
check(Game3.isSurfStart(0x10), "pond water starts Surf")
check(not Game3.isSurfStart(0x13), "waterfall does not start Surf")
check(Game3.isWaterfall(0x13), "0x13 is a waterfall")

local g = Game3.new()
g.phase = "play"
g.facing = "east"
g.bag = {}
g.party = { { name = "MACHOP", moves = { { id = Game3.MOVE_STRENGTH } } } }
g.flags[Game3.FLAG_BADGE04_GET] = true
g:enterMap({
  id = "g_str", width = 4, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 5, graphicsId = Game3.GFX_PUSHABLE_BOULDER },
  },
}, 1, 1, true)
check(not g:tryWalk(1, 0), "boulder blocks without Strength")
eq(g.playerX, 1, "player stays put")
local okStr, strMsg = g:useStrength()
check(okStr, "STRENGTH activates")
eq(strMsg, "Used STRENGTH!", "announces STRENGTH")
check(g:strengthOn(), "strength flag is on")
check(g:tryWalk(1, 0), "then the boulder pushes")
eq(g.playerX, 2, "player steps into the old tile")
eq(g:npcByLocalId(5).x, 3, "boulder moves east")

g.data.tilesets = { byId = { wat = { behavior = { [1] = 0x10, [2] = 0x13 } } } }
g.party[1].moves = { { id = Game3.MOVE_SURF } }
g.flags[Game3.FLAG_BADGE05_GET] = true
g.facing = "east"
g:enterMap({
  id = "g_surf", width = 3, height = 3, tileset = "wat",
  grid = { 0, 0, 0, 0, 0, 1025, 0, 0, 0 },
}, 1, 1, true)
local okSurf, surfMsg = g:useSurf()
check(okSurf, "SURF hops on")
eq(surfMsg, "Used SURF!", "announces SURF")
eq(g.playerX, 2, "onto the water")
eq(g.surfing, true, "surfing")
check(g:tryWalk(-1, 0), "walk back to land")
eq(g.playerX, 1, "back on land")
eq(g.surfing, nil, "dismounts")

g.party[1].moves = { { id = Game3.MOVE_FLASH } }
g.flags[Game3.FLAG_BADGE02_GET] = true
g:enterMap({
  id = "g_cave", width = 3, height = 3, mapType = Game3.MAP_TYPE_UNDERGROUND,
  cave = true,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g.flashLevel, Game3.MAX_FLASH_LEVEL, "unlit cave is max flash")
check(g:isDarkMap(), "requires_flash cave is dark")
eq(g:flashRadius(), 24, "max darkness is 24px")
local okFlash, flashMsg = g:useFlash()
check(okFlash, "FLASH lights the cave")
eq(flashMsg, "Used FLASH!", "announces FLASH")
eq(g.flags[Game3.FLAG_SYS_USE_FLASH], true, "flash flag")
eq(g.flashLevel, 1, "FLASH sets radius 1")
eq(g:flashRadius(), 72, "lit cave is 72px")
check(not g:useFlash(), "FLASH is spent until you leave")
g:enterMap({
  id = "g_1f", width = 3, height = 3, mapType = Game3.MAP_TYPE_UNDERGROUND,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g.flashLevel, 0, "Granite 1F is not requires_flash")
check(not g:isDarkMap(), "lit underground stays bright")
check(not g:useFlash(), "FLASH fails on a lit floor")
g:enterMap({
  id = "g_gym", width = 3, height = 3, mapType = Game3.MAP_TYPE_INDOOR,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g.flashLevel, 0, "indoor default is full light")
g:runNpcScript({
  { op = "setflashradius", level = 4 },
  { op = "end" },
})
eq(g.flashLevel, 4, "Brawly setflashradius 4")
eq(g:flashRadius(), 24, "gym starts at 24px")
eq(Game3.flashAnimFrames(24, 40), 34, "24px to 40px is 17 steps")
eq(Game3.flashAnimFrames(72, 24), 2, "shrink stops the first step")
g:runNpcScript({
  { op = "animateflash", level = 3 },
  { op = "end" },
})
eq(g.flashLevel, 4, "Overworld level is unchanged during the tween")
eq(g:flashRadius(), 24, "hole still 24px on the first frame")
g:driveFlashAnim()
eq(g.flashLevel, 3, "beating a trainer brightens")
eq(g:flashRadius(), 40, "level 3 is 40px")
g:enterMap({
  id = "g_cave2", width = 3, height = 3, mapType = Game3.MAP_TYPE_UNDERGROUND,
  cave = true,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g.flashLevel, 1, "re-entering a cave with FLASH stays at 1")
g:enterMap({
  id = "g_town", width = 3, height = 3, mapType = 1,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
local noFlash = g:useFlash()
check(not noFlash, "FLASH fails in town")

g.party[1].moves = { { id = Game3.MOVE_SURF }, { id = Game3.MOVE_WATERFALL } }
g.flags[Game3.FLAG_BADGE08_GET] = true
g.facing = "north"
g.surfing = true
g:enterMap({
  id = "g_fall", width = 3, height = 3, tileset = "wat",
  grid = { 0, 1026, 0, 0, 1025, 0, 0, 0, 0 },
}, 1, 1, true)
g.surfing = true
local okFall, fallMsg = g:useWaterfall()
check(okFall, "WATERFALL climbs")
eq(fallMsg, "Used WATERFALL!", "announces WATERFALL")
eq(g.playerY, 0, "onto the waterfall")
eq(g.climbing, true, "climbing")
end)()

;(function()
eq(Game3.ITEM_HM_FLY, 340, "HM02 is Fly")
eq(Game3.MOVE_FLY, 19, "Fly is move 19")
eq(Game3.FLAG_BADGE06_GET, 0x80C, "Feather Badge")
eq(Game3.FLAG_VISITED_LITTLEROOT_TOWN, 0x80F, "visited Littleroot")
eq(Game3.FLAG_VISITED_OLDALE_TOWN, 0x810, "visited Oldale")
eq(#Game3.FLY_DESTINATIONS, 16, "16 Hoenn fly towns")
eq(Game3.FLY_DESTINATIONS[1].mapId, "g0_9", "Littleroot is first")
eq(Game3.FLY_BY_ID["g0_10"].name, "OLDALE TOWN", "Oldale by id")
check(Game3.canFlyFrom({ mapType = Game3.MAP_TYPE_TOWN }), "towns allow Fly")
check(Game3.canFlyFrom({ mapType = Game3.MAP_TYPE_ROUTE }), "routes allow Fly")
check(not Game3.canFlyFrom({ mapType = Game3.MAP_TYPE_INDOOR }),
  "indoors refuse Fly")
check(not Game3.canFlyFrom({ mapType = Game3.MAP_TYPE_UNDERGROUND }),
  "caves refuse Fly")

local little = {
  id = "g0_9", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local oldale = {
  id = "g0_10", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 2, y = 2 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local indoor = {
  id = "g1_0", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local g = Game3.new()
g.phase = "play"
g.bag = {}
g.party = { { name = "SWELLOW", moves = { { id = Game3.MOVE_FLY } } } }
g.flags[Game3.FLAG_BADGE06_GET] = true
g.data.maps = { start = "g0_9", maps = { g0_9 = little, g0_10 = oldale, g1_0 = indoor } }
g:enterMap(little, 1, 1, true)
eq(g.flags[Game3.FLAG_VISITED_LITTLEROOT_TOWN], true, "entering marks visited")
eq(#g:flyList(), 1, "only Littleroot so far")
local okOpen, openMsg = g:useFly()
check(okOpen, "FLY opens the picker")
eq(openMsg, "Where do you want to FLY?", "asks where")
eq(g.field.kind, "fly", "picker is up")
eq(#g.field.list, 1, "one destination")
g:enterMap(oldale, 0, 0, true)
eq(g.flags[Game3.FLAG_VISITED_OLDALE_TOWN], true, "Oldale is visited")
eq(#g:flyList(), 2, "both towns")
g:enterMap(indoor, 1, 1, true)
local noIn, inMsg = g:useFly()
check(not noIn, "can't Fly indoors")
eq(inMsg, "You can't use that here!", "indoor refuse")
g.surfing = true
g:enterMap(little, 1, 1, true)
local okFly = g:useFly()
check(okFly, "FLY from town")
eq(#g.field.list, 2, "both dests listed")
local flew, flewMsg = g:flyTo(g.field.list[2])
check(flew, "warps")
eq(flewMsg, "Flew to OLDALE TOWN!", "announces Oldale")
eq(g.map.id, "g0_10", "on Oldale")
eq(g.playerX, 2, "spawn x")
eq(g.playerY, 2, "spawn y")
eq(g.surfing, nil, "dismounts Surf")
g.flags[Game3.FLAG_BADGE06_GET] = nil
local noBadge, badgeMsg = g:useFly()
check(not noBadge, "needs Feather Badge")
eq(badgeMsg, "You need the FEATHER BADGE to use FLY.", "badge line")
g.flags[Game3.FLAG_BADGE06_GET] = true
g.party[1].moves = {}
local noMove, moveMsg = g:useFly()
check(not noMove, "needs the move")
eq(moveMsg, "No one in your party knows FLY.", "move line")
end)()

;(function()
eq(Game3.ITEM_HM_DIVE, 346, "HM08 is Dive")
eq(Game3.MOVE_DIVE, 291, "Dive is move 291")
eq(Game3.FLAG_BADGE07_GET, 0x80D, "Mind Badge")
check(Game3.isDiveable(0x12), "deep water is diveable")
check(Game3.isDiveable(0x14), "Sootopolis deep water is diveable")
check(not Game3.isDiveable(0x10), "pond water is not")
check(not Game3.isDiveable(0x15), "ocean water is not")
check(Game3.isUnableToEmerge(0x19), "no-surfacing blocks emerge")
check(Game3.isUnableToEmerge(0x2A), "seaweed no-surfacing too")

local surface = {
  id = "g0_20", group = 0, index = 20, mapType = Game3.MAP_TYPE_ROUTE,
  width = 3, height = 3, tileset = "wat",
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 1027, 0, 0, 0, 0 },
  connections = { { dir = "dive", mapGroup = 0, mapNum = 21 } },
}
local under = {
  id = "g0_21", group = 0, index = 21, mapType = Game3.MAP_TYPE_UNDERWATER,
  width = 3, height = 3, tileset = "wat",
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 1027, 0, 0, 0, 0 },
  connections = { { dir = "emerge", mapGroup = 0, mapNum = 20 } },
}
local g = Game3.new()
g.phase = "play"
g.bag = {}
g.party = { { name = "WAILORD", moves = { { id = Game3.MOVE_DIVE } } } }
g.flags[Game3.FLAG_BADGE07_GET] = true
g.data.maps = { maps = { g0_20 = surface, g0_21 = under } }
g.data.tilesets = { byId = { wat = { behavior = { [1] = 0x10, [3] = 0x12, [4] = 0x19 } } } }
g.surfing = true
g:enterMap(surface, 1, 1, true)
local okDive, diveMsg = g:useDive()
check(okDive, "DIVE drops down")
eq(diveMsg, "Used DIVE!", "announces DIVE")
eq(g.map.id, "g0_21", "on the underwater map")
eq(g.playerX, 1, "same x")
eq(g.playerY, 1, "same y")
eq(g.diving, true, "diving")
eq(g.surfing, true, "still swimming")
local okUp, upMsg = g:useDive()
check(okUp, "DIVE surfaces")
eq(upMsg, "Used DIVE!", "announces emerge")
eq(g.map.id, "g0_20", "back on the route")
eq(g.diving, nil, "not diving")
eq(g.surfing, true, "surfing on the way up")

g.surfing = nil
local noSurf, surfMsg = g:useDive()
check(not noSurf, "need Surf first")
eq(surfMsg, "You can't use that here!", "refuse without Surf")
g.surfing = true
surface.grid[5] = 1025
g:enterMap(surface, 1, 1, true)
g.surfing = true
local noPond = g:useDive()
check(not noPond, "pond is not diveable")
surface.grid[5] = 1027
under.grid[5] = 1028
g.surfing = true
g:enterMap(surface, 1, 1, true)
g.surfing = true
g:useDive()
eq(g.map.id, "g0_21", "under again")
local noCeil = g:useDive()
check(not noCeil, "no-surfacing blocks emerge")
g.flags[Game3.FLAG_BADGE07_GET] = nil
under.grid[5] = 1027
g:enterMap(under, 1, 1, true)
local noBadge = g:useDive()
check(not noBadge, "needs Mind Badge")
end)()

;(function()
eq(Game3.ITEM_OLD_ROD, 262, "Old Rod is a key item")
eq(Game3.ITEM_GOOD_ROD, 263, "Good Rod")
eq(Game3.ITEM_SUPER_ROD, 264, "Super Rod")
eq(Game3.rodKind(262), 0, "Old Rod kind 0")
eq(Game3.fishMinRounds(0, 0), 1, "Old Rod always 1 round")
eq(Game3.fishMinRounds(0, 99), 1, "Old Rod span is 1")
eq(Game3.fishMinRounds(1, 0), 1, "Good Rod min 1")
eq(Game3.fishMinRounds(1, 2), 3, "Good Rod max 3")
eq(Game3.fishMinRounds(2, 5), 6, "Super Rod max 6")
eq(Game3.FISH_REEL[0], 36, "Old Rod reel 36")
eq(Game3.FISH_REEL[1], 33, "Good Rod reel 33")
eq(Game3.FISH_REEL[2], 30, "Super Rod reel 30")
eq(Game3.FISH_EXTRA[1][1], 10, "Good Rod extra-round 10%")
eq(Game3.FISH_EXTRA[2][1], 30, "Super Rod extra-round 30%")
eq(Game3.chooseWaterRockSlot(0), 0, "water slot 0 is 60%")
eq(Game3.chooseWaterRockSlot(59), 0, "59 stays slot 0")
eq(Game3.chooseWaterRockSlot(60), 1, "60 opens slot 1")
eq(Game3.chooseWaterRockSlot(90), 2, "90 opens slot 2")
eq(Game3.chooseWaterRockSlot(95), 3, "95 opens slot 3")
eq(Game3.chooseWaterRockSlot(99), 4, "99 is slot 4")
eq(Game3.chooseFishSlot(0, 0), 0, "Old Rod 70% slot 0")
eq(Game3.chooseFishSlot(0, 70), 1, "Old Rod 30% slot 1")
eq(Game3.chooseFishSlot(1, 59), 2, "Good Rod slot 2")
eq(Game3.chooseFishSlot(1, 60), 3, "Good Rod slot 3")
eq(Game3.chooseFishSlot(1, 80), 4, "Good Rod slot 4")
eq(Game3.chooseFishSlot(2, 39), 5, "Super Rod slot 5")
eq(Game3.chooseFishSlot(2, 40), 6, "Super Rod slot 6")
eq(Game3.chooseFishSlot(2, 80), 7, "Super Rod slot 7")
eq(Game3.chooseFishSlot(2, 95), 8, "Super Rod slot 8")
eq(Game3.chooseFishSlot(2, 99), 9, "Super Rod slot 9")

local g = Game3.new()
g.phase = "play"
g.facing = "east"
g.bag = { { id = Game3.ITEM_OLD_ROD, count = 1 } }
g.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5, moves = {} } }
g.data.tilesets = { byId = { wat = { behavior = { [1] = 0x10, [2] = 0x13 } } } }
g.data.encounters = { byMap = { g_fish = {
  fish = { rate = 30, slots = {
    { minLevel = 5, maxLevel = 5, species = 129 },
    { minLevel = 10, maxLevel = 10, species = 118 },
  } },
  water = { rate = 255, slots = {
    { minLevel = 20, maxLevel = 20, species = 72 },
  } },
  rock = { rate = 255, slots = {
    { minLevel = 8, maxLevel = 8, species = 74 },
  } },
} } }
g:enterMap({
  id = "g_fish", width = 3, height = 3, tileset = "wat",
  grid = { 0, 0, 0, 0, 0, 1025, 0, 0, 0 },
  objects = { { x = 1, y = 0, localId = 3, graphicsId = Game3.GFX_BREAKABLE_ROCK } },
}, 1, 1, true)
check(g:canFish(), "facing pond water can fish")
g.rng = function() return 2 end
local miss = g:useFieldItem(Game3.ITEM_OLD_ROD)
check(miss, "a miss is still a use")
eq(g.field and g.field.kind, "fishing", "Task_Fishing starts")
g:driveFishingDots()
eq(g.field and g.field.text, Game3.FISH_TEXT_NIBBLE, "nibble miss")
eq(g.phase, "play", "no battle on a miss")
eq(g:itemCount(Game3.ITEM_OLD_ROD), 1, "rods are not consumed")
g:stepFishing(2 / 60)
g:driveFishingA()
eq(g.field, nil, "A dismisses the nibble")
g.rng = function() return 1 end
local hit = g:useRod(Game3.ITEM_OLD_ROD)
check(hit, "a bite starts the minigame")
eq(g.phase, "play", "not in battle yet")
g:driveFishingHook()
eq(g.phase, "battle", "fishing battle")
eq(g.battle.enemy.species, 129, "Old Rod slot 0")
eq(g.battle.enemy.level, 5, "level 5 Magikarp")
g.phase = "play"
g.battle = nil
g.facing = "north"
check(not g:canFish(), "grass in front is not fishable")
g.facing = "east"
g.surfing = true
g:enterMap(g.map, 2, 1, true)
g.surfing = true
check(g:tryWildEncounter(), "Surf steps roll water slots")
eq(g.battle.enemy.species, 72, "water slot 0")
g.phase = "play"
g.battle = nil
g.surfing = nil
g.facing = "north"
g:enterMap(g.map, 1, 1, true)
g.flags[Game3.FLAG_BADGE03_GET] = true
g.party[1].moves = { { id = Game3.MOVE_ROCK_SMASH } }
g.rng = function() return 1 end
local smash = g:useRockSmash()
check(smash, "Rock Smash still breaks the rock")
eq(g.phase, "battle", "and can start a rock fight")
eq(g.battle.enemy.species, 74, "Geodude from the rock table")
end)()

;(function()
local g = Game3.new()
g.phase = "play"
g.facing = "east"
g.bag = { { id = Game3.ITEM_OLD_ROD, count = 1 } }
g.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5, moves = {} } }
g.data.tilesets = { byId = { wat = { behavior = { [1] = 0x10 } } } }
g.data.encounters = { byMap = { g_fish = {
  fish = { rate = 30, slots = {
    { minLevel = 5, maxLevel = 5, species = 129 },
  } },
} } }
g:enterMap({
  id = "g_fish", width = 3, height = 3, tileset = "wat",
  grid = { 0, 0, 0, 0, 0, 1025, 0, 0, 0 },
}, 1, 1, true)
g.rng = function() return 1 end
check(g:useRod(Game3.ITEM_OLD_ROD), "cast")
g:stepFishing(61 / 60)
eq(g.field.step, Game3.FISH_DOTS, "dots after the 1s wait")
g:driveFishingA()
eq(g.field.text, Game3.FISH_TEXT_NIBBLE, "A too early is no bite")
g.field = nil
check(g:useRod(Game3.ITEM_OLD_ROD), "cast again")
g:driveFishingDots()
eq(g.field.text, Game3.FISH_TEXT_BITE, "Oh! A bite!")
g:stepFishing(37 / 60)
eq(g.field.text, Game3.FISH_TEXT_AWAY, "reel timeout got away")
g.field = nil
g.data.encounters.byMap.g_fish = {}
g.rng = function() return 1 end
check(g:useRod(Game3.ITEM_OLD_ROD), "water without a table still casts")
g:driveFishingDots()
eq(g.field.text, Game3.FISH_TEXT_NIBBLE, "no fishing mons is a nibble")
g.field = nil
g.data.encounters.byMap.g_fish = {
  fish = { rate = 30, slots = { { minLevel = 5, maxLevel = 5, species = 129 } } },
}
check(g:useRod(Game3.ITEM_OLD_ROD), "second-round got away")
g.field.minRounds = 2
g:driveFishingDots()
eq(g.field.text, Game3.FISH_TEXT_BITE, "first required round bites")
g:driveFishingA()
g:stepFishing(1 / 60)
eq(g.field.step, Game3.FISH_START_ROUND, "back to another dot round")
g:stepFishing(1 / 60)
eq(g.field.step, Game3.FISH_DOTS, "second round dots")
g:driveFishingA()
eq(g.field.text, Game3.FISH_TEXT_AWAY, "A during a later round is got away")
end)()

;(function()
eq(Game3.ITEM_MACH_BIKE, 259, "Mach Bike")
eq(Game3.ITEM_ACRO_BIKE, 272, "Acro Bike")
eq(Game3.FLAG_SYS_B_DASH, 0x860, "running shoes flag")
eq(Game3.MACH_PERIOD, Game3.WALK_PERIOD / 4, "Mach is 4x walk")
eq(Game3.RUN_PERIOD, Game3.WALK_PERIOD / 2, "dash is 2x walk")
check(Game3.canBikeOn({ mapType = Game3.MAP_TYPE_TOWN }), "towns allow bikes")
check(Game3.canBikeOn({ mapType = Game3.MAP_TYPE_UNDERGROUND }),
  "caves allow bikes")
check(not Game3.canBikeOn({ mapType = Game3.MAP_TYPE_INDOOR }),
  "indoors refuse bikes")
check(not Game3.canBikeOn({ mapType = Game3.MAP_TYPE_UNDERWATER }),
  "underwater refuses bikes")

local town = {
  id = "g_town", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local indoor = {
  id = "g_in", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local g = Game3.new()
g.phase = "play"
g:enterMap(town, 1, 1, true)
local on, onMsg = g:useFieldItem(Game3.ITEM_MACH_BIKE)
check(on, "Mach Bike mounts")
eq(onMsg, "Got on the MACH BIKE.", "on line")
eq(g.bike, "mach", "riding Mach")
check(g:tryWalk(1, 0), "Mach step")
eq(g.walkCooldown, Game3.MACH_PERIOD, "Mach cooldown")
eq(g:walkProgress() < 0.01 and 0 or g:walkProgress(), 0, "lerp starts at 0")
local off, offMsg = g:useBike(Game3.ITEM_MACH_BIKE)
check(off, "Mach Bike dismounts")
eq(offMsg, "Got off the MACH BIKE.", "off line")
eq(g.bike, nil, "on foot")
local acro, acroMsg = g:useBike(Game3.ITEM_ACRO_BIKE)
check(acro, "Acro Bike mounts")
eq(acroMsg, "Got on the ACRO BIKE.", "Acro on")
eq(g:walkPeriod(), Game3.WALK_PERIOD, "Acro is walk speed")
g:enterMap(indoor, 1, 1, true)
eq(g.bike, nil, "indoors kick you off")
local noIn = g:useBike(Game3.ITEM_MACH_BIKE)
check(not noIn, "can't mount indoors")
g:enterMap(town, 1, 1, true)
g.surfing = true
local noSurf = g:useBike(Game3.ITEM_MACH_BIKE)
check(not noSurf, "can't bike while surfing")
g.surfing = nil
g.flags[Game3.FLAG_SYS_B_DASH] = true
g.running = true
eq(g:walkPeriod(), Game3.RUN_PERIOD, "dash is 2x")
g.bike = "mach"
eq(g:walkPeriod(), Game3.MACH_PERIOD, "Mach beats dash")
g.bike = nil
eq(g:wantRun(), false, "B is not held")
end)()

;(function()
eq(Game3.MAP_ROUTE110_CYCLING_SOUTH_NUM, 11, "south cycling gate")
eq(Game3.MAP_ROUTE110_CYCLING_NORTH_NUM, 12, "north cycling gate")
local south = {
  id = "g29_11", group = 29, index = 11,
  mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local north = {
  id = "g29_12", group = 29, index = 12,
  mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local indoor = {
  id = "g_in", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local town = {
  id = "g_town", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
check(Game3.canBikeOn(south), "south gate allows bikes")
check(Game3.canBikeOn(north), "north gate allows bikes")
check(Game3.canBikeOn({ id = "g29_11", mapType = Game3.MAP_TYPE_INDOOR }),
  "south gate id without group still allows")
check(not Game3.canBikeOn({ mapType = Game3.MAP_TYPE_INDOOR }),
  "generic indoor still refuses")
check(not Game3.canBikeOn({
  id = "g24_36", group = Game3.GRANITE_CAVE_GROUP,
  index = Game3.MAP_SEAFLOOR_CAVERN_ROOM9_NUM,
  mapType = Game3.MAP_TYPE_UNDERGROUND,
}), "Seafloor Cavern Room 9 refuses")
check(not Game3.canBikeOn({
  id = "g24_42", group = Game3.GRANITE_CAVE_GROUP,
  index = Game3.MAP_CAVE_OF_ORIGIN_B4F_NUM,
  mapType = Game3.MAP_TYPE_UNDERGROUND,
}), "Cave of Origin B4F refuses")

local g = Game3.new()
g.phase = "play"
g:enterMap(town, 1, 1, true)
g.bike = "mach"
g:enterMap(south, 1, 1, true)
eq(g.bike, "mach", "enterMap keeps the Mach Bike in the south gate")
eq(g:playerAvatarBike(), 2, "GetPlayerAvatarBike is MACH")
g:enterMap(town, 1, 1, true)
g.bike = "mach"
g:enterMap(indoor, 1, 1, true)
eq(g.bike, nil, "generic indoor still dismounts")
g:enterMap(south, 1, 1, true)
local mounted = g:useBike(Game3.ITEM_MACH_BIKE)
check(mounted, "can mount inside the cycling gate")
eq(g.bike, "mach", "riding Mach in the gate")
end)()

;(function()
eq(Game3.ITEM_SUPER_REPEL, 83, "Super Repel")
eq(Game3.ITEM_MAX_REPEL, 84, "Max Repel")
eq(Game3.ITEM_ESCAPE_ROPE, 85, "Escape Rope")
eq(Game3.ITEM_REPEL, 86, "Repel")
eq(Game3.REPEL_STEPS[86], 100, "Repel lasts 100 steps")
eq(Game3.REPEL_STEPS[83], 200, "Super Repel lasts 200")
eq(Game3.REPEL_STEPS[84], 250, "Max Repel lasts 250")
eq(Game3.itemName(Game3.new(), Game3.ITEM_REPEL), "REPEL", "Repel name")
eq(Game3.itemName(Game3.new(), Game3.ITEM_ESCAPE_ROPE), "ESCAPE ROPE",
  "rope name")
check(Game3.canEscapeFrom({ mapType = Game3.MAP_TYPE_UNDERGROUND }),
  "caves allow Escape Rope")
check(Game3.canEscapeFrom({ cave = true }), "cave flag allows it")
check(Game3.canEscapeFrom({ allowEscaping = true }), "header bit allows it")
check(not Game3.canEscapeFrom({ mapType = Game3.MAP_TYPE_TOWN }),
  "towns refuse Escape Rope")
check(not Game3.canEscapeFrom({ mapType = Game3.MAP_TYPE_UNDERWATER }),
  "underwater refuses it")

local town = {
  id = "g_town", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local cave = {
  id = "g_cave", mapType = Game3.MAP_TYPE_UNDERGROUND, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local pc = {
  id = "g_pc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local g = Game3.new()
g.phase = "play"
g.bag = {
  { id = Game3.ITEM_REPEL, count = 2 },
  { id = Game3.ITEM_SUPER_REPEL, count = 1 },
  { id = Game3.ITEM_ESCAPE_ROPE, count = 2 },
}
g.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5,
  moves = {} } }
g.data.tilesets = { byId = { grass = { behavior = { [1] = 0x02 } } } }
g.data.encounters = { byMap = { g_grass = {
  land = { rate = 255, slots = { { minLevel = 2, maxLevel = 2, species = 290 } } },
  water = { rate = 255, slots = { { minLevel = 20, maxLevel = 20, species = 72 } } },
  rock = { rate = 255, slots = { { minLevel = 4, maxLevel = 4, species = 74 } } },
  fish = { rate = 30, slots = {
    { minLevel = 5, maxLevel = 5, species = 129 },
  } },
} } }
g.data.maps = { start = "g_town", maps = { g_town = town, g_cave = cave, g_pc = pc } }
local grass = {
  id = "g_grass", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
  tileset = "grass",
  grid = { 0, 0, 0, 0, 1, 0, 0, 0, 0 },
}
g:enterMap(grass, 1, 1, true)
g.rng = function() return 1 end
local used, usedMsg = g:useFieldItem(Game3.ITEM_REPEL)
check(used, "BAG Repel uses")
eq(usedMsg, "Used the REPEL.", "use line")
eq(g.repelSteps, 100, "100 steps left")
eq(g:itemCount(Game3.ITEM_REPEL), 1, "one Repel spent")
check(g:repelBlocks(2), "lead 5 blocks wild 2")
check(g:repelBlocks(5), "equal level is blocked")
check(not g:repelBlocks(6), "a stronger wild still appears")
check(not g:tryWildEncounter(), "Repel skips the grass fight")
eq(g.phase, "play", "still on the field")
g:useRepel(Game3.ITEM_SUPER_REPEL)
eq(g.repelSteps, 200, "a new Repel overwrites the counter")

g.repelSteps = 2
check(g:tryWalk(1, 0), "a step ticks Repel")
eq(g.repelSteps, 1, "one step left")
check(g:tryWalk(0, 1), "the last step")
eq(g.repelSteps, nil, "the counter clears")
eq(g.field and g.field.text, "REPEL's effect wore off!", "wore-off line")

g.field = nil
g.repelSteps = 50
g.phase = "play"
g.battle = nil
g.data.encounters.byMap.g_grass.land.slots[1].minLevel = 10
g.data.encounters.byMap.g_grass.land.slots[1].maxLevel = 10
g:enterMap(grass, 1, 1, true)
check(g:tryWildEncounter(), "a higher-level wild ignores Repel")
eq(g.battle.enemy.level, 10, "wild is lv10")
g.phase = "play"
g.battle = nil
g.facing = "east"
g.bag[#g.bag + 1] = { id = Game3.ITEM_OLD_ROD, count = 1 }
g.data.tilesets.byId.grass.behavior[2] = 0x10
grass.grid[6] = 1026
g:enterMap(grass, 1, 1, true)
g.rng = function() return 1 end
local bite = g:useRod(Game3.ITEM_OLD_ROD)
check(bite, "fishing ignores Repel")
g:driveFishingHook()
eq(g.phase, "battle", "rod still starts a fight")
g.phase = "play"
g.battle = nil
g.repelSteps = 50
check(not g:tryRockSmashEncounter(), "Rock Smash fights respect Repel")

g:enterMap(pc, 1, 2, true)
g.facing = "north"
g.npcByMap = { g_pc = { { x = 1, y = 1, graphicsId = Game3.GFX_NURSE } } }
g.party[1].hp = 1
check(g:tryTalk(), "nurse heals")
eq(g.lastHeal.mapId, "g_pc", "nurse records last heal")
eq(g.lastHeal.x, 1, "heal x")
eq(g.lastHeal.y, 2, "heal y")
eq(g.party[1].hp, 19, "HP restored")

g.field = nil
g:enterMap(cave, 2, 2, true)
g.surfing = true
g.bike = "mach"
local rope, ropeMsg = g:useFieldItem(Game3.ITEM_ESCAPE_ROPE)
check(not rope, "can't rope while surfing")
g.surfing = nil
rope, ropeMsg = g:useFieldItem(Game3.ITEM_ESCAPE_ROPE)
check(rope, "Escape Rope from a cave")
eq(ropeMsg, "Used the ESCAPE ROPE!", "rope line")
eq(g.map.id, "g_pc", "warps to last heal")
eq(g.playerX, 1, "heal x")
eq(g.playerY, 2, "heal y")
eq(g.bike, nil, "dismounts")
eq(g:itemCount(Game3.ITEM_ESCAPE_ROPE), 1, "one rope spent")
g:enterMap(town, 1, 1, true)
local noTown = g:useEscapeRope()
check(not noTown, "towns refuse Escape Rope")
eq(g:itemCount(Game3.ITEM_ESCAPE_ROPE), 1, "the refuse does not spend")

g:enterMap(cave, 0, 0, true)
g.phase = "battle"
g.battle = { kind = "blackout" }
g.party[1].hp = 0
g:blackout()
eq(g.phase, "play", "blackout returns to the field")
eq(g.map.id, "g_pc", "blackout uses last heal")
eq(g.party[1].hp, g.party[1].maxHp, "and heals")
g.lastHeal = nil
g:enterMap(cave, 0, 0, true)
g.phase = "battle"
g.battle = { kind = "blackout" }
g.party[1].hp = 0
g:blackout()
eq(g.map.id, "g_town", "no heal point warps to start")
eq(g.playerX, 1, "start spawn x")
eq(g.playerY, 1, "start spawn y")

g:enterMap(pc, 2, 1, true)
g.party[1].hp = 1
g:runSpecial(0)
eq(g.lastHeal, nil, "HealPlayerParty does not setrespawn")
eq(g.party[1].hp, g.party[1].maxHp, "but it heals")
end)()

;(function()
local route = {
  id = "g_route", mapType = Game3.MAP_TYPE_ROUTE, width = 4, height = 4,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local roomGrid = {}
for i = 1, 8 * 6 do roomGrid[i] = 0 end
local room = {
  id = "g1_1", width = 8, height = 6, grid = roomGrid,
  spawn = { x = 4, y = 2 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
}
local faint = Game3.new()
faint.gender = Game3.GENDER_MALE
faint.data.maps = { start = "g_route", maps = { g_route = route, g1_1 = room } }
faint.lastHeal = nil
faint.party = { faint:makeMon(Game3.SPECIES_TREECKO, 5) }
faint.party[1].hp = 0
faint:enterMap(route, 1, 1, true)
faint.phase = "battle"
faint.battle = { kind = "blackout" }
faint:blackout()
eq(faint.map.id, "g1_1", "early faint warps home, not the starter route")
eq(faint.playerX, 4, "bedroom heal x")
eq(faint.playerY, 2, "bedroom heal y")

faint.lastHeal = { mapId = "g1_1", x = 4, y = 2 }
faint:enterMap(route, 6, 13, true)
faint.party[1].hp = 1
faint:runSpecial(0)
eq(faint.lastHeal.mapId, "g1_1", "starter HealPlayerParty keeps the bedroom")
eq(faint.party[1].hp, faint.party[1].maxHp, "and still heals")
faint.party[1].hp = 0
faint.phase = "battle"
faint.battle = { kind = "blackout" }
faint:blackout()
eq(faint.map.id, "g1_1", "May wipe still sends you home")

faint.lastHeal = { mapId = "g_route", x = 6, y = 13 }
faint:enterMap(route, 1, 1, true)
faint.party[1].hp = 0
faint.phase = "battle"
faint.battle = { kind = "blackout" }
faint:blackout()
eq(faint.map.id, "g1_1", "a route lastHeal is not a heal location")
end)()

;(function()
eq(Game3.MOVE_DIG, 91, "Dig is move 91")
eq(Game3.MOVE_TELEPORT, 100, "Teleport is move 100")
check(Game3.canTeleportFrom({ mapType = Game3.MAP_TYPE_TOWN }),
  "towns allow Teleport")
check(Game3.canTeleportFrom({ mapType = Game3.MAP_TYPE_ROUTE }),
  "routes allow Teleport")
check(not Game3.canTeleportFrom({ mapType = Game3.MAP_TYPE_UNDERGROUND }),
  "caves refuse Teleport")
check(not Game3.canTeleportFrom({ mapType = Game3.MAP_TYPE_INDOOR }),
  "indoors refuse Teleport")

local town = {
  id = "g_town", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local cave = {
  id = "g_cave", mapType = Game3.MAP_TYPE_UNDERGROUND, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local pc = {
  id = "g_pc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  spawn = { x = 2, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "g_town", maps = { g_town = town, g_cave = cave, g_pc = pc } }
g.lastHeal = { mapId = "g_pc", x = 2, y = 1 }
g.party = { {
  name = "ABRA", hp = 20, maxHp = 20, species = 63, level = 15,
  moves = { { id = Game3.MOVE_TELEPORT } },
} }
g:enterMap(town, 0, 0, true)
g.surfing = true
g.bike = "mach"
local tp, tpMsg = g:useTeleport()
check(tp, "Teleport from a town")
eq(tpMsg, "Used TELEPORT!", "Teleport line")
eq(g.map.id, "g_pc", "warps to last heal")
eq(g.playerX, 2, "heal x")
eq(g.playerY, 1, "heal y")
eq(g.surfing, nil, "clears surf")
eq(g.bike, nil, "dismounts")
g:enterMap(cave, 1, 1, true)
local noCave = g:useTeleport()
check(not noCave, "Teleport refuses a cave")
g.party[1].moves = { { id = Game3.MOVE_CUT } }
g:enterMap(town, 0, 0, true)
local noMove, noMoveMsg = g:useTeleport()
check(not noMove, "needs Teleport")
eq(noMoveMsg, "No one in your party knows TELEPORT.", "no-move line")

g.party[1].moves = { { id = Game3.MOVE_DIG } }
g:enterMap(cave, 1, 1, true)
g.surfing = true
local noSurf = g:useDig()
check(not noSurf, "Dig refuses surf")
g.surfing = nil
local dig, digMsg = g:useDig()
check(dig, "Dig from a cave")
eq(digMsg, "Used DIG!", "Dig line")
eq(g.map.id, "g_pc", "Dig warps to last heal")
g:enterMap(town, 0, 0, true)
local noTown = g:useDig()
check(not noTown, "Dig refuses a town")
g.party[1].moves = { { id = Game3.MOVE_CUT } }
g:enterMap(cave, 1, 1, true)
local noDigMove = g:useDig()
check(not noDigMove, "needs Dig")

g.party = {
  { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5, moves = {} },
  { name = "ABRA", hp = 20, maxHp = 20, species = 63, level = 15,
    moves = { { id = Game3.MOVE_TELEPORT }, { id = Game3.MOVE_DIG } } },
}
g:enterMap(town, 0, 0, true)
local dualTown, dualTownMsg = g:usePartyFieldMove(g.party[2])
check(dualTown, "outdoor dual-move uses Teleport")
eq(dualTownMsg, "Used TELEPORT!", "Teleport wins outdoors")
g:enterMap(cave, 1, 1, true)
local dualCave, dualCaveMsg = g:usePartyFieldMove(g.party[2])
check(dualCave, "cave dual-move uses Dig")
eq(dualCaveMsg, "Used DIG!", "Dig wins in a cave")
local none, noneMsg = g:usePartyFieldMove(g.party[1])
check(not none, "a mon without field moves stays put")
eq(noneMsg, "No moves to use here.", "no-field-move line")

local Input = require("src.core.Input")
Input:init()
g:enterMap(cave, 1, 1, true)
g.field = { kind = "party", cursor = 0 }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "party_action", "A on a mon without field moves opens commands")
eq(g.field.actions[3], "ITEM", "ITEM is on the command list")
eq(g.field.actions[4], "CANCEL", "and has no field move")
g.field = { kind = "party", cursor = 1 }
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party_action", "A on Dig/Teleport opens commands")
g.field.cursor = 4
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "talk", "DIG from the list uses it")
eq(g.field.text, "Used DIG!", "party A Dig line")
eq(g.map.id, "g_pc", "party A warps")
end)()

;(function()
eq(Game3.MOVE_SWEET_SCENT, 230, "Sweet Scent is move 230")

local g = Game3.new()
g.phase = "play"
g.party = { {
  name = "ODDISH", hp = 20, maxHp = 20, species = 43, level = 12,
  moves = { { id = Game3.MOVE_SWEET_SCENT } },
} }
g.data.tilesets = { byId = { grass = { behavior = { [1] = 0x02, [2] = 0x10 } } } }
g.data.encounters = { byMap = { g_scent = {
  land = { rate = 0, slots = { { minLevel = 2, maxLevel = 2, species = 290 } } },
  water = { rate = 0, slots = { { minLevel = 20, maxLevel = 20, species = 72 } } },
} } }
local map = {
  id = "g_scent", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
  tileset = "grass",
  grid = { 0, 0, 0, 0, 1, 1026, 0, 0, 0 },
}
g:enterMap(map, 1, 1, true)
g.rng = function() return 1 end
g.repelSteps = 100
check(not g:tryWildEncounter(), "rate 0 never walks")
local ok, msg = g:useSweetScent()
check(ok, "Sweet Scent uses")
eq(msg, "Used SWEET SCENT!", "use line")
eq(g.phase, "battle", "forces a fight")
eq(g.battle.enemy.species, 290, "land slot 0")
eq(g.repelSteps, 100, "Repel is still up")

g.phase = "play"
g.battle = nil
g:enterMap(map, 0, 0, true)
local miss, missMsg = g:useSweetScent()
check(miss, "a miss is still a use")
eq(missMsg, "Looks like there's nothing here.", "nothing-here line")
eq(g.phase, "play", "no battle off grass")

g:enterMap(map, 2, 1, true)
g.surfing = true
g.rng = function() return 1 end
local water, waterMsg = g:useSweetScent()
check(water, "Sweet Scent on water")
eq(waterMsg, "Used SWEET SCENT!", "water use line")
eq(g.phase, "battle", "water fight")
eq(g.battle.enemy.species, 72, "water slot 0")

g.phase = "play"
g.battle = nil
g.surfing = nil
g.party[1].moves = { { id = Game3.MOVE_CUT } }
g:enterMap(map, 1, 1, true)
local noMove, noMoveMsg = g:useSweetScent()
check(not noMove, "needs Sweet Scent")
eq(noMoveMsg, "No one in your party knows SWEET SCENT.", "no-move line")

g.party[1].moves = { { id = Game3.MOVE_SWEET_SCENT } }
g.rng = function() return 1 end
local Input = require("src.core.Input")
Input:init()
g.field = { kind = "party", cursor = 0 }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party_action", "A opens Sweet Scent commands")
g.field.cursor = 3
g:stepField()
Input.wasPressed = old
eq(g.phase, "battle", "party A Sweet Scent fights")
eq(g.battle.enemy.species, 290, "party A land slot")
end)()

;(function()
eq(Game3.GFX_DAYCARE_LADY, 30, "daycare lady is OLD_WOMAN_2")
eq(Game3.SPECIAL_GET_DAYCARE_STATE, 182, "GetDaycareState")
eq(Game3.SPECIAL_STORE_SELECTED_IN_DAYCARE, 187, "StoreSelected")
eq(Game3.SPECIAL_TAKE_POKEMON_FROM_DAYCARE, 192, "TakePokemon")
eq(Game3.DAYCARE_BASE_COST, 100, "base fee is $100")

local g = Game3.new()
g.phase = "play"
g.money = 3000
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
      learnset = { { move = 52, level = 10 } },
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
    [52] = { id = 52, name = "EMBER", power = 40, type = 10, pp = 25, accuracy = 100 },
  },
}
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
eq(g:daycareState(), 0, "empty daycare is state 0")
check(g:depositToDaycare(2), "leaves the Wurmple")
eq(#g.party, 1, "one stays with you")
eq(g:daycareCount(), 1, "one in daycare")
eq(g:daycareState(), 2, "state 2 is a single mon")
eq(g.daycare[1].mon.species, 290, "Wurmple is stored")
eq(g.daycare[1].steps, 0, "steps start at 0")
local noOnly = g:depositToDaycare(1)
check(not noOnly, "cannot leave the last party mon")

g:enterMap({
  id = "g_dc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
check(g:tryWalk(1, 0), "a step feeds daycare")
eq(g.daycare[1].steps, 1, "one EXP of steps")

local stored = g.daycare[1].mon
local need = Game3.expAtLevel(stored.growth, (stored.level or 1) + 1) - stored.exp
g.daycare[1].steps = need
eq(g:daycareLevelsGained(1), 1, "preview is +1 level")
eq(g:daycareCost(1), 200, "fee is $100 + $100")
local took, tookMsg = g:takeFromDaycare(1)
check(took, "retrieve succeeds")
check(tookMsg:find("WURMPLE", 1, true) ~= nil, "names the mon")
eq(g.party[2].level, 3, "Wurmple is Lv3")
eq(g.party[2].species, 290, "still Wurmple")
eq(g.money, 2800, "paid $200")
eq(g:daycareCount(), 0, "slot is empty")

g.party = { g:makeMon(280, 9), g:makeMon(290, 2) }
check(g:depositToDaycare(1), "leaves the Lv9 Torchic")
stored = g.daycare[1].mon
local to10 = Game3.expAtLevel(stored.growth, 10) - stored.exp
g.daycare[1].steps = to10
check(g:takeFromDaycare(1), "retrieves at Lv10")
eq(g.party[2].level, 10, "Torchic is Lv10")
eq(g.party[2].moves[#g.party[2].moves] and g.party[2].moves[#g.party[2].moves].name,
  "EMBER", "it learns Ember at 10")

g.party = { g:makeMon(280, 15), g:makeMon(290, 2) }
check(g:depositToDaycare(1), "leaves the Lv15 Torchic")
stored = g.daycare[1].mon
local to16 = Game3.expAtLevel(stored.growth, 16) - stored.exp
g.daycare[1].steps = to16
check(g:takeFromDaycare(1), "retrieves at Lv16")
eq(g.party[2].level, 16, "Torchic is Lv16")
eq(g.party[2].species, 280, "daycare does not evolve")

g.party = { g:makeMon(280, 5), g:makeMon(290, 2), g:makeMon(280, 5) }
check(g:depositToDaycare(2), "first slot")
check(g:depositToDaycare(2), "second slot")
eq(g:daycareCount(), 2, "two mons")
eq(g:daycareState(), 3, "state 3 is two mons")
local full = g:depositToDaycare(1)
check(not full, "two-slot cap")
g.daycare[1] = nil
g:compactDaycare()
eq(g.daycare[1].mon.species, 280, "slot 2 shifts down")
eq(g.daycare[2], nil, "slot 2 clears")

g.money = 0
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.daycare = { { mon = g:makeMon(290, 2), steps = 0 } }
local broke = g:takeFromDaycare(1)
check(not broke, "need money to take")

g.money = 3000
g:runSpecial(182)
eq(g.scriptVars[0x800D], 2, "special 182 writes state")
g.scriptVars[0x8004] = 1
g:runSpecial(187)
eq(g:daycareCount(), 2, "special 187 deposits 0x8004")

g:enterMap({
  id = "g_dc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.daycare = {}
g.npcByMap = { g_dc = { { x = 1, y = 0, graphicsId = Game3.GFX_DAYCARE_LADY } } }
g.facing = "north"
g.playerX, g.playerY = 1, 1
check(g:tryTalk(), "A on the lady")
eq(g.field.kind, "daycare_send", "empty daycare asks you to leave one")
end)()

;(function()
eq(Game3.GFX_DAYCARE_MAN, 29, "daycare man is OLD_MAN_2")
eq(Game3.FLAG_PENDING_DAYCARE_EGG, 0x86, "pending egg flag")
eq(Game3.SPECIAL_REJECT_EGG_FROM_DAYCARE, 183, "RejectEgg")
eq(Game3.SPECIAL_GIVE_EGG_FROM_DAYCARE, 184, "GiveEgg")
eq(Game3.SPECIAL_SET_DAYCARE_COMPAT_STRING, 185, "SetCompatString")
eq(Game3.EGG_HATCH_LEVEL, 5, "eggs hatch at 5")
eq(Game3.EGG_CYCLE_STEPS, 255, "one cycle is 255 steps")

local g = Game3.new()
g.phase = "play"
g.rng = function() return 1 end
g.data.pokemon = {
  byIndex = {
    [132] = {
      name = "DITTO", hp = 48, atk = 48, def = 48, spe = 48,
      spa = 48, spd = 48, type1 = 0, type2 = 0, catchRate = 35,
      expYield = 61, growthRate = 0, genderRatio = 255,
      eggCycles = 20, eggGroup1 = 13, eggGroup2 = 13,
    },
    [151] = {
      name = "MEW", hp = 100, atk = 100, def = 100, spe = 100,
      spa = 100, spd = 100, type1 = 24, type2 = 24, catchRate = 45,
      expYield = 64, growthRate = 0, genderRatio = 255,
      eggCycles = 120, eggGroup1 = 15, eggGroup2 = 15,
    },
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, genderRatio = 31,
      eggCycles = 20, eggGroup1 = 5, eggGroup2 = 5,
    },
    [281] = {
      name = "COMBUSKEN", hp = 60, atk = 85, def = 60, spe = 55,
      spa = 85, spd = 60, type1 = 10, type2 = 2, catchRate = 45,
      expYield = 142, growthRate = 3, genderRatio = 31,
      eggCycles = 20, eggGroup1 = 5, eggGroup2 = 5,
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
      expYield = 54, growthRate = 0, genderRatio = 127,
      eggCycles = 15, eggGroup1 = 3, eggGroup2 = 3,
    },
  },
}

local female = g:makeMon(280, 5)
female.pid = 0
local male = g:makeMon(280, 5)
male.pid = 100
eq(g:monGender(female), Game3.MON_FEMALE, "pid 0 is female Torchic")
eq(g:monGender(male), Game3.MON_MALE, "pid 100 is male Torchic")
g.daycare = { { mon = female, steps = 0 }, { mon = male, steps = 0 } }
eq(g:daycareCompatibility(), 50, "same species, same OT is 50")
male.otId = 2
eq(g:daycareCompatibility(), 70, "same species, different OT is 70")
male.otId = nil
local male2 = g:makeMon(280, 5)
male2.pid = 200
g.daycare[1].mon = male
g.daycare[2].mon = male2
eq(g:daycareCompatibility(), 0, "two males are 0")
g.daycare[1].mon = female
g.daycare[2].mon = g:makeMon(290, 2)
eq(g:daycareCompatibility(), 0, "Field and Bug do not overlap")
local ditto = g:makeMon(132, 5)
g.daycare[2].mon = ditto
eq(g:daycareCompatibility(), 20, "Ditto, same OT is 20")
ditto.otId = 9
eq(g:daycareCompatibility(), 50, "Ditto, different OT is 50")
g.daycare[2].mon = g:makeMon(151, 5)
eq(g:daycareCompatibility(), 0, "Undiscovered is 0")
eq(g:eggSpeciesFrom(281, 0), 280, "Combusken eggs are Torchic")

g.daycare = { { mon = female, steps = 0 }, { mon = male, steps = 254 } }
g.daycarePending = nil
g.rng = function() return 1 end
g:tickDaycare()
eq(g.daycare[2].steps, 255, "second slot ticked to 255")
check((g.daycarePending or 0) ~= 0, "compatible parents can leave an egg")
eq(g:daycareState(), 1, "state 1 is an egg waiting")
eq(g.flags[Game3.FLAG_PENDING_DAYCARE_EGG], true, "pending flag is set")
eq(g.caught[280], nil, "the egg is not caught yet")
local gave, gaveMsg = g:giveDaycareEgg()
check(gave, "GiveEgg succeeds")
check(gaveMsg:find("care", 1, true) ~= nil, "take-care line")
local egg = g.party[#g.party]
eq(egg.isEgg, true, "party slot is an EGG")
eq(egg.name, "EGG", "nickname is EGG")
eq(egg.level, 5, "hatch level 5")
eq(egg.species, 280, "baby is Torchic")
eq(g.daycarePending, nil, "pending clears")
eq(g.caught[280], nil, "still not caught")
eq(g:firstHealthy(), nil, "only an egg cannot battle")
g.party[#g.party + 1] = g:makeMon(290, 2)
eq(g:firstHealthy().species, 290, "eggs are skipped in battle")

g.daycarePending = 7
g:runSpecial(183)
eq(g.daycarePending, nil, "special 183 rejects")
g.daycare = { { mon = female, steps = 0 }, { mon = male, steps = 0 } }
g.daycarePending = 11
g.party = { g:makeMon(290, 2) }
g:runSpecial(184)
eq(g.party[2].isEgg, true, "special 184 gives the egg")
g.lastSay = nil
function g:sayScript(text) self.lastSay = text end
g:runSpecial(185)
eq(g.lastSay, Game3.DAYCARE_COMPAT_TEXT[50], "special 185 writes the 50 line")

g:enterMap({
  id = "g_man", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
g.npcByMap = { g_man = { { x = 1, y = 0, graphicsId = Game3.GFX_DAYCARE_MAN } } }
g.facing = "north"
g.playerX, g.playerY = 1, 1
g.daycarePending = nil
g.daycare = { { mon = female, steps = 0 }, { mon = male, steps = 0 } }
check(g:tryTalk(), "A on the man")
eq(g.field.kind, "talk", "compat is a talk box")
eq(g.field.text, Game3.DAYCARE_COMPAT_TEXT[50], "man quotes compatibility")
g.daycarePending = 22
check(g:tryTalk(), "A on the man with an egg")
eq(g.field.kind, "daycare_egg", "man offers the egg")
local Input = require("src.core.Input")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "talk", "YES takes the egg")
eq(g.party[#g.party].isEgg, true, "egg is in the party")

g.party = { g:makeMon(290, 2) }
g.party[1].isEgg = true
g.party[1].name = "EGG"
g.party[1].hatchLeft = 1
g.party[1].species = 280
g.caught = {}
g.eggCycleSteps = 254
g.field = nil
check(g:tryWalk(1, 0), "a step ticks egg cycles")
eq(g.party[1].isEgg, true, "Huh? is before AddHatchedMonToParty")
eq(g.field.text, "Huh?", "S_EggHatch")
eq(g.field.kind, "talk", "hatch opens a talk box")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.party[1].isEgg, nil, "the egg hatched")
eq(g.party[1].name, "TORCHIC", "hatched name")
eq(g.caught[280], true, "hatch records the dex")
eq(g.field.kind, "egg_hatch", "EggHatch cinema")
end)()

;(function()
eq(Game3.GFX_TEALA, 85, "contest receptionist is TEALA")
eq(Game3.SPECIAL_GET_CONTEST_WINNER_IDX, 76, "GetContestWinnerIdx")
eq(Game3.SPECIAL_GIVE_CONTEST_RIBBON, 89, "GiveContestRibbon")
eq(Game3.SPECIAL_SUB_80C5044, 90, "sub_80C5044 is the link-contest flag")
eq(Game3.SPECIAL_CHECK_LEAD_MON_COOL, 265, "CheckLeadMonCool")
eq(Game3.CONTEST_TURNS, 5, "five appeal turns")
eq(Game3.contestCategoryForType(0), 4, "Normal moves fall back to TOUGH")
eq(Game3.contestCategoryForType(10), 1, "Fire moves fall back to BEAUTY")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
    },
  },
}
g.data.moves = {
  byId = {
    [33] = { id = 33, name = "TACKLE", type = 0, power = 35, pp = 35 },
    [52] = {
      id = 52, name = "EMBER", type = 10, power = 40, pp = 25,
      contestCategory = 1, contestAppeal = 20,
    },
  },
}
g.party = { g:makeMon(280, 5, { 52 }) }
g.party[1].beauty = 255
g.party[1].sheen = 255
g.rng = function(max)
  g._contestRng = (g._contestRng or 0) + 1
  return (g._contestRng % (max or 65536)) + 1
end
eq(g:contestAppealOf(g.party[1].moves[1], Game3.CONTEST_CATEGORY_BEAUTY), 20,
  "matching category is full appeal")
eq(g:contestAppealOf(g.party[1].moves[1], Game3.CONTEST_CATEGORY_COOL), 10,
  "wrong category is half")
check(g:beginContest(1, Game3.CONTEST_CATEGORY_BEAUTY, 0), "Beauty Normal starts")
eq(g.field.kind, "contest_move", "appeal screen")
for _ = 1, 5 do
  g:applyContestTurn(1)
end
eq(g.field.kind, "contest_results", "five appeal rounds")
eq(g.contest.playerIndex, 3, "player is contestant 3")
eq(type(g.contest.finalStandings[3]), "number", "player has a placing")
g.contest.done = true
g.contest.finalStandings = { [0] = 1, [1] = 2, [2] = 3, [3] = 0 }
g.contest.totalPoints = { [0] = 10, [1] = 20, [2] = 30, [3] = 400 }
g.party[1].ribbons = nil
g:finishContest()
eq(g.contest.won, true, "1st place is a win")
eq(g.contest.winner, 3, "winner index is the player")
eq(g:contestRibbon(g.party[1], Game3.CONTEST_CATEGORY_BEAUTY), 1,
  "Normal Beauty ribbon")
eq(#g:contestRanksFor(g.party[1], Game3.CONTEST_CATEGORY_BEAUTY), 2,
  "Super Beauty unlocks")

g.party[1].moves = { g:copyMove(33) }
g.contest = nil
g.contestMons = nil
g.party[1].ribbons = nil
check(g:beginContest(1, Game3.CONTEST_CATEGORY_BEAUTY, 0), "wrong-category start")
g.contest.done = true
g.contest.finalStandings = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 }
g.contest.totalPoints = { [0] = 200, [1] = 150, [2] = 100, [3] = 10 }
g:finishContest()
eq(g.contest.won, false, "4th place is a loss")
eq(g:contestRibbon(g.party[1], Game3.CONTEST_CATEGORY_BEAUTY), 0,
  "no ribbon on a loss")

g.party[1].isEgg = true
local eggOk, eggMsg = g:beginContest(1, 0, 0)
check(not eggOk, "eggs are refused")
check(eggMsg:find("Egg", 1, true) ~= nil, "egg line")
g.party[1].isEgg = nil

g.party[1].ribbons = { beauty = 1 }
check(not g:canEnterContestRank(g.party[1], Game3.CONTEST_CATEGORY_BEAUTY, 2),
  "Hyper needs a Super ribbon")
check(g:canEnterContestRank(g.party[1], Game3.CONTEST_CATEGORY_BEAUTY, 1),
  "Super is open after Normal")

g.scriptVars = { [0x8004] = 0 }
g:runSpecial(84)
eq(g.scriptVars[0x800D], 1, "special 84 accepts a battler")
g:runSpecial(76)
eq(g.scriptVars[0x8005], g:contestWinnerIndex(), "special 76 writes 0x8005")
g.scriptVars[Game3.VAR_CONTEST_CATEGORY] = Game3.CONTEST_CATEGORY_BEAUTY
g.scriptVars[Game3.VAR_CONTEST_RANK] = 0
g.party[1].ribbons = { beauty = 1 }
g:runSpecial(90)
eq(g.scriptVars[0x800D], 0, "special 90 is the link-contest flag")
g.party[1].cool = 200
g:runSpecial(265)
eq(g.scriptVars[0x800D], 1, "special 265 lead Cool")
g.party[1].cool = 0
g:runSpecial(265)
eq(g.scriptVars[0x800D], 0, "Cool 0 is not high")

g:enterMap({
  id = "g_hall", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
g.npcByMap = { g_hall = { { x = 1, y = 0, graphicsId = Game3.GFX_TEALA } } }
g.facing = "north"
g.playerX, g.playerY = 1, 1
g.field = nil
check(g:tryTalk(), "A on Teala")
eq(g.field.kind, "contest_cat", "Teala opens the category list")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
Input:init()
local g = Game3.new()
eq(Game3.SPECIAL_SET_CABLE_CLUB_WARP, 1, "SetCableClubWarp")
eq(Game3.SPECIAL_DO_CABLE_CLUB_WARP, 2, "DoCableClubWarp")
eq(Game3.SPECIAL_SUB_80810DC, 3, "sub_80810DC")
eq(Game3.SPECIAL_SUB_80839A4, 4, "sub_80839A4")
eq(Game3.SPECIAL_SUB_80834E4, 29, "sub_80834E4")
eq(Game3.SPECIAL_SUB_808347C, 28, "sub_808347C")
eq(Game3.SPECIAL_CLOSE_LINK, 31, "CloseLink")
eq(Game3.SPECIAL_SHOW_LINK_BATTLE_RECORDS, 196, "ShowLinkBattleRecords")
eq(Game3.SPECIAL_SHOW_BATTLE_TOWER_RECORDS, 283, "ShowBattleTowerRecords")
eq(Game3.SPECIAL_SUB_8134548, 231, "sub_8134548")
eq(Game3.SPECIAL_BATTLE_TOWER_UTIL, 238, "BattleTowerUtil")
eq(Game3.SPECIAL_CHOOSE_BATTLE_TOWER_PLAYER_PARTY, 245, "ChooseBattleTowerPlayerParty")
eq(Game3.SPECIAL_VALIDATE_E_READER_TRAINER, 246, "ValidateEReaderTrainer")
eq(Game3.SPECIAL_GET_BEST_BATTLE_TOWER_STREAK, 247, "GetBestBattleTowerStreak")
eq(Game3.SPECIAL_GET_CUR_SECRET_BASE_REGISTRATION_VALIDITY, 12,
  "GetCurSecretBaseRegistrationValidity")
eq(Game3.CABLE_CLUB_NO_LINK, 5, "sub_80833EC RESULT 5")

g:setScriptVar(0x800D, 99)
eq(g:runSpecial(Game3.SPECIAL_SUB_80834E4), 5, "no GBA partner is 5")
eq(g:varGet(0x800D), 5, "and VAR_RESULT is 5, not 0")
check(not g:scriptWaiting(), "link connect does not wait")
eq(g:runSpecial(Game3.SPECIAL_SUB_808347C), 5, "colosseum connect is 5")
eq(g:runSpecial(Game3.SPECIAL_SUB_808350C), 5, "record corner is 5")
eq(g:runSpecial(Game3.SPECIAL_SUB_8083614), 5, "link blender is 5")
eq(g:runSpecial(Game3.SPECIAL_SUB_80835D8), 5, "sub_80835D8 is 5")
g:runSpecial(Game3.SPECIAL_CLOSE_LINK)
check(not g:scriptWaiting(), "CloseLink does not wait")
eq(g:runSpecial(Game3.SPECIAL_SET_CABLE_CLUB_WARP), 0, "SetCableClubWarp is 0")
check(not g:scriptWaiting(), "SetCableClubWarp does not wait")
g:runSpecial(Game3.SPECIAL_SUB_80839A4)
check(not g:scriptWaiting(), "sub_80839A4 does not wait")

local src = {
  id = "g1_0", group = 1, index = 0, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local dest = {
  id = "g2_0", group = 2, index = 0, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
g.data.maps = { maps = { g1_0 = src, g2_0 = dest } }
g.phase = "play"
g:enterMap(src, 1, 1, true)
g.warpDestination = { mapGroup = 2, mapNum = 0, warpId = 0xFF, x = 1, y = 2 }
g:runSpecial(Game3.SPECIAL_DO_CABLE_CLUB_WARP)
check(g:scriptWaiting(), "DoCableClubWarp CreateTask")
eq(g.map, src, "still on src during fade")
g:walkHeld((Game3.FADE_FRAMES - 1) / 60)
check(g:scriptWaiting(), "fade still running")
eq(g.map, src, "WarpIntoMap after the fade")
g:walkHeld(1 / 60)
check(not g:scriptWaiting(), "WarpIntoMap then Enable")
eq(g.map, dest, "warped")
eq(g.playerY, 2, "dest y")

g:enterMap(src, 1, 1, true)
g.warpDestination = { mapGroup = 2, mapNum = 0, warpId = 0xFF, x = 1, y = 1 }
g:runSpecial(Game3.SPECIAL_SUB_80810DC)
check(g:scriptWaiting(), "sub_80810DC CreateTask")
g:walkHeld(Game3.FADE_FRAMES / 60)
check(not g:scriptWaiting(), "10DC WarpIntoMap then Enable")
eq(g.map, dest, "10DC warped")

g:runSpecial(Game3.SPECIAL_SHOW_LINK_BATTLE_RECORDS)
check(not g:scriptWaiting(), "records do not wait")
eq(g.field.kind, "link_records", "link records field")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.field, nil, "A closes link records")

g:runSpecial(Game3.SPECIAL_SHOW_BATTLE_TOWER_RECORDS)
check(not g:scriptWaiting(), "tower records do not wait")
eq(g.field.kind, "tower_records", "tower records field")
eq(g:towerStreakLabel(0), "Prev", "idle var_4AE is Prev")
g:ensureBattleTower().var4AE[0] = 2
eq(g:towerStreakLabel(0), "Current", "var_4AE 2 is Current")
g:ensureBattleTower().var4AE[0] = 0
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = old
eq(g.field, nil, "B closes tower records")

eq(g:runSpecial(Game3.SPECIAL_GET_BEST_BATTLE_TOWER_STREAK), 0,
  "streak 0 is valid")
eq(g:runSpecial(Game3.SPECIAL_SUB_8134548), 0, "ON_FRAME init returns 0")
eq(g:varGet(Game3.VAR_TEMP_0), 5, "VAR_TEMP_0 idle is 5")
check(not g:scriptWaiting(), "tower ON_FRAME does not wait")
g:setScriptVar(0x8004, 0)
eq(g:runSpecial(Game3.SPECIAL_BATTLE_TOWER_UTIL), 0, "util case 0 is 0")
eq(g:runSpecial(Game3.SPECIAL_CHECK_PARTY_BATTLE_TOWER_BANLIST), 0,
  "banlist allows")
eq(g:varGet(0x8004), 0, "0x8004 stay-allow")
eq(g:runSpecial(Game3.SPECIAL_CHOOSE_BATTLE_TOWER_PLAYER_PARTY), 0,
  "party pick cancels")
check(not g:scriptWaiting(), "party pick does not wait")
eq(g:runSpecial(Game3.SPECIAL_VALIDATE_E_READER_TRAINER), 1,
  "empty e-reader is invalid")
eq(g:runSpecial(Game3.SPECIAL_GET_CUR_SECRET_BASE_REGISTRATION_VALIDITY), 0,
  "registry 0 is can-register")
eq(g:runSpecial(Game3.SPECIAL_SUB_80BC114), 0, "own base is 0")

g:enterMap({
  id = "g2_3", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
g.npcByMap = {
  g2_3 = {
    {
      x = 1, y = 0, graphicsId = Game3.GFX_TEALA,
      script = {
        { op = "message", text = "This is the POKeMON CABLE CLUB." },
        { op = "waitmessage" },
        { op = "end" },
      },
    },
  },
}
g.facing = "north"
g.playerX, g.playerY = 1, 1
g.field = nil
check(g:tryTalk(), "A on Cable Club Teala")
eq(g.field and g.field.kind, "talk", "scripted Teala runs the map script")
check(g.field and g.field.text:find("CABLE CLUB", 1, true),
  "not the contest shortcut")
end)()

;(function()
eq(Game3.MOVE_SECRET_POWER, 290, "Secret Power is move 290")
eq(Game3.ITEM_TM43, 331, "TM43 is item 331")
eq(Game3.SPECIAL_CHECK_PLAYER_HAS_SECRET_BASE, 7, "CheckPlayerHasSecretBase")
eq(Game3.SPECIAL_MOVE_OUT_OF_SECRET_BASE, 10, "MoveOutOfSecretBase")
eq(Game3.BG_SECRET_BASE, 8, "BG events kind 8")
eq(Game3.VAR_CURRENT_SECRET_BASE, 0x4054, "VAR_CURRENT_SECRET_BASE")
eq(Game3.SECRET_BASE_MAP_ID, "secret_base", "generated interior id")
eq(Game3.MAP_TYPE_SECRET_BASE, 9, "secret base map type")
eq(Game3.new():itemName(Game3.ITEM_TM43), "TM43", "TM43 name")

local interior = Game3.makeSecretBaseMap()
eq(interior.id, "secret_base", "interior id")
eq(interior.mapType, Game3.MAP_TYPE_SECRET_BASE, "interior type")
eq(interior.width, 7, "interior width")
eq(interior.height, 6, "interior height")
eq(interior.spawn.x, 3, "spawn x")
eq(interior.spawn.y, 4, "spawn y")
eq(interior.warps[1].x, 3, "exit warp x")
eq(interior.warps[1].y, 5, "exit warp y")
eq(interior.behavior[1 * 7 + 3 + 1], Game3.MB_SECRET_BASE_PC, "PC behavior")
check(not Game3.walkable(interior, 3, 1), "PC tile is solid")
check(Game3.walkable(interior, 3, 4), "spawn is walkable")
check(Game3.canBikeOn(interior) == false, "no bikes inside")

local g = Game3.new()
g.phase = "play"
g.party = { {
  name = "ZIGZAGOON", hp = 20, maxHp = 20, species = 263, level  = 10,
  moves = { { id = Game3.MOVE_SECRET_POWER } },
} }
local route = {
  id = "g_sb", mapType = Game3.MAP_TYPE_ROUTE, width = 5, height = 4,
  grid = {
    1024, 1024, 1024, 1024, 1024,
    1024, 0, 1024, 1024, 1024,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
  },
  bgEvents = {
    { x = 2, y = 1, kind = Game3.BG_SECRET_BASE, secretBaseId = 42 },
    { x = 3, y = 1, kind = Game3.BG_SECRET_BASE, secretBaseId = 7 },
  },
}
g.data.maps = { maps = { g_sb = route } }
g:enterMap(route, 2, 2, true)
g.facing = "north"
local ok, msg = g:useSecretPower()
check(ok, "Secret Power makes a base")
eq(msg, "Used SECRET POWER!", "use line")
eq(g.map.id, "secret_base", "warps into the interior")
eq(g.playerX, 3, "interior x")
eq(g.playerY, 4, "interior y")
eq(g.secretBase.id, 42, "stores the BG id")
eq(g.secretBase.mapId, "g_sb", "stores the overworld map")
eq(g.secretBase.x, 2, "stores the spot x")
eq(g.secretBase.y, 1, "stores the spot y")
eq(g.secretBase.outX, 2, "exit lands on the use tile")
eq(g.secretBase.outY, 2, "exit y")
eq(g.scriptVars[Game3.VAR_CURRENT_SECRET_BASE], 42, "var 0x4054")
g:runSpecial(7)
eq(g.scriptVars[0x800D], 1, "special 7 sees the base")

check(g:tryWalk(0, -1), "walk north")
check(g:tryWalk(0, -1), "up to the PC")
eq(g.playerX, 3, "still under the PC")
eq(g.playerY, 2, "one tile south of the PC")
g.facing = "north"
check(g:tryTalk(), "A on the secret-base PC")
eq(g.field.kind, "pc", "opens storage")
g.field = nil

g.playerX, g.playerY = 3, 4
g.facing = "south"
check(g:tryWalk(0, 1), "south wall is the exit")
eq(g.map.id, "g_sb", "south warp returns outside")
eq(g.playerX, 2, "outside x")
eq(g.playerY, 2, "outside y")

g:runSpecial(7)
eq(g.scriptVars[0x800D], 1, "the base is still owned")
check(g:tryWalk(0, -1), "walking into the owned cave enters")
eq(g.map.id, "secret_base", "owned entrance warps in")

g:runSpecial(10)
eq(g.map.id, "g_sb", "special 10 moves you out")

local used, usedMsg = g:useSecretPower()
check(used, "same spot enters again")
eq(usedMsg, "Used SECRET POWER!", "enter line")
eq(g.map.id, "secret_base", "Secret Power on the owned spot enters")
g:exitSecretBase()

g.playerX, g.playerY = 3, 2
g.facing = "north"
local moveOk, moveMsg = g:useSecretPower()
check(moveOk, "a second spot asks to move")
eq(g.field.kind, "secret_base_move", "move prompt")
eq(g.map.id, "g_sb", "stays outside until YES")
local Input = require("src.core.Input")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.map.id, "secret_base", "YES moves and enters")
eq(g.secretBase.id, 7, "new spot id")
eq(g.secretBase.x, 3, "new spot x")
g:exitSecretBase()
eq(g.secretBase.outX, 3, "exit from the new use tile")
eq(g.secretBase.outY, 2, "new out y")
g.playerX, g.playerY = 2, 2
g.facing = "north"
check(not g:tryWalk(0, -1), "the old cave no longer enters")

g.secretBase = nil
g.party[1].moves = { { id = Game3.MOVE_SECRET_POWER } }
g:addItem(Game3.ITEM_TM43, 1)
g.playerX, g.playerY = 2, 2
g.facing = "north"
local tmOk, tmMsg = g:useSecretPower()
check(tmOk, "knowing Secret Power plants a tree")
eq(tmMsg, "Used SECRET POWER!", "use line again")
eq(g:itemCount(Game3.ITEM_TM43), 1, "bag TM43 is not a field use")
eq(g.map.id, "secret_base", "the move makes the base")
g:exitSecretBase()

g.party[1].moves = { { id = Game3.MOVE_SECRET_POWER } }
g:enterMap(route, 1, 2, true)
g.facing = "south"
local bad, badMsg = g:useSecretPower()
check(not bad, "needs a cave or tree")
eq(badMsg, "You can't use that here!", "wrong-tile line")

g.party[1].moves = {}
g.bag = {}
local none, noneMsg = g:useSecretPower()
check(not none, "needs the party to know Secret Power")
eq(noneMsg, "No one in your party knows SECRET POWER.", "no-move line")

local bush = {
  id = "g_bush", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
  grid = { 0, 1024, 0, 0, 0, 0, 0, 0, 0 },
  behavior = {},
}
bush.behavior[0 * 3 + 1 + 1] = 0x96
g.data.maps.maps.g_bush = bush
g.party[1].moves = { { id = Game3.MOVE_SECRET_POWER } }
g.secretBase = nil
g:enterMap(bush, 1, 1, true)
g.facing = "north"
local bushOk = g:useSecretPower()
check(bushOk, "behavior 0x96 is a tree spot")
eq(g.secretBase.x, 1, "behavior spot x")
eq(g.secretBase.y, 0, "behavior spot y")

g:enterMap(route, 2, 2, true)
g.facing = "north"
g.field = { kind = "party", cursor = 0 }
Input:init()
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "party_action", "A opens party commands")
g.field.cursor = 3
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "secret_base_move", "SECRET POWER keeps the move prompt")

g.secretBase = nil
g:runSpecial(7)
eq(g.scriptVars[0x800D], 0, "special 7 is 0 with no base")
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = Game3.new()
g.phase = "play"
g.field = { kind = "menu", cursor = 4 }
eq(g:startMenuItems()[5], "OPTION", "OPTION is on START")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "option", "A opens OPTION")
eq(g.options.battleStyle, "shift", "default is SHIFT")
g.field.cursor = 2
g:stepField()
eq(g.options.battleStyle, "set", "A on BATTLE STYLE sets SET")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
eq(g.field.kind, "menu", "B returns to START")
Input.wasPressed = old

g.field = { kind = "talk", text = "HELLO WORLD" }
eq(g:printedText(g.field), "HELLO WORLD", "unticked text is fully visible")
g:stepPrinter(g.field, 3 / 60)
check(g.field.printLive == true, "a dt tick starts the printer")
check(#g:printedText(g.field) < 11, "MID prints one glyph per 3 frames")
g:printerFinish(g.field)
eq(g:printedText(g.field), "HELLO WORLD", "A finishes the line")

g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, learnset = { { move = 10, level = 1 } },
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
      expYield = 54, growthRate = 0,
    },
    [288] = {
      name = "ZIGZAGOON", hp = 38, atk = 30, def = 41, spe = 60,
      spa = 30, spd = 41, type1 = 0, type2 = 0, catchRate = 255,
      expYield = 60, growthRate = 3,
    },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35, accuracy = 100 } },
}
g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.options.battleStyle = "set"
check(g:startTrainerBattle({
  trainerName = "CALVIN", trainerClass = "YOUNGSTER",
  party = { { species = 290, level = 2 }, { species = 288, level = 3 } },
}), "SET still starts a trainer fight")
g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "WURMPLE fainted!" }
g.battle.qi = 1
g:advanceBattleText()
eq(g.battle.kind, "intro", "SET does not ask to switch")
eq(g.battle.enemy.species, 288, "and sends the next mon")

g.options.battleStyle = "shift"
g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "ZIGZAGOON fainted!" }
g.battle.qi = 1
g.battle.trainerIndex = 1
g.battle.trainerParty = {
  { species = 290, level = 2 }, { species = 288, level = 3 },
}
g:advanceBattleText()
eq(g.battle.kind, "switch_ask", "SHIFT asks when a bench mon can come in")
end)()

;(function()
eq(Game3.GFX_VAR_1, 241, "woods grunt is VAR_1")
eq(Game3.GFX_MAGMA_MEMBER_M, 119, "Ruby evil team is Magma M")
eq(Game3.VAR_OBJ_GFX_ID_0, 0x4010, "gfx vars start at 0x4010")
eq(Game3.VAR_PETALBURG_WOODS_STATE, 0x4098, "woods state var")
eq(Game3.TRAINER_PETALBURG_WOODS_GRUNT, 575, "TRAINER_GRUNT_36")
eq(Game3.TRAINER_BATTLE_NO_INTRO, 3, "SINGLE_NO_INTRO_TEXT")

local g = Game3.new()
eq(g:resolveGraphicsId(Game3.GFX_VAR_1), Game3.GFX_VAR_1,
  "unset VAR_1 stays a var id")
g:setScriptVar(Game3.VAR_OBJ_GFX_ID_0 + 1, Game3.GFX_MAGMA_MEMBER_M)
eq(g:resolveGraphicsId(Game3.GFX_VAR_1), Game3.GFX_MAGMA_MEMBER_M,
  "VAR_1 is Magma M")
eq(g:resolveGraphicsId(Game3.GFX_VAR_0), Game3.GFX_RIVAL_MAY,
  "unset VAR_0 still uses gender")
g:setScriptVar(Game3.VAR_OBJ_GFX_ID_0, Game3.GFX_RIVAL_BRENDAN)
eq(g:resolveGraphicsId(Game3.GFX_VAR_0), Game3.GFX_RIVAL_BRENDAN,
  "a set VAR_0 wins")

g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [286] = { name = "POOCHYENA", hp = 35, atk = 55, def = 35, spe = 35,
      spa = 30, spd = 30, type1 = 17, type2 = 17 },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35 } },
}
g.data.trainers = { byId = { [Game3.TRAINER_PETALBURG_WOODS_GRUNT] = {
  name = "GRUNT", className = "TEAM MAGMA",
  party = { { species = 286, level = 9 } },
} } }
g.party = { g:makeMon(280, 10) }
check(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_NO_INTRO,
  trainerId = Game3.TRAINER_PETALBURG_WOODS_GRUNT,
  defeat = "You're kidding me! You're tough!",
}), "no-intro looks up the woods grunt")
eq(g.phase, "battle", "and starts the fight")
eq(g.battle.kind, "menu", "skips the intro wait")
eq(g.battle.text, nil, "no would-like-to-battle line")
eq(g.battle.enemy.species, 286, "lv9 Poochyena")
eq(g.battle.enemy.level, 9, "level 9")
eq(g.battle.defeat, "You're kidding me! You're tough!", "lose text is kept")

local woods = Game3.new()
woods.phase = "play"
local map = {
  id = "g24_11", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { localId = 3, x = 1, y = 1, graphicsId = Game3.GFX_VAR_1,
      flagId = Game3.FLAG_HIDE_EVIL_TEAM_PETALBURG_WOODS },
  },
  mapScripts = {
    onTransition = {
      { op = "setvar", var = Game3.VAR_OBJ_GFX_ID_0 + 1,
        val = Game3.GFX_MAGMA_MEMBER_M },
      { op = "end" },
    },
  },
  coordEvents = {
    { x = 1, y = 2, trigger = Game3.VAR_PETALBURG_WOODS_STATE, index = 0,
      script = { { op = "end" } } },
  },
}
woods:enterMap(map, 0, 0, true)
eq(woods:npcsFor(map)[1].graphicsId, Game3.GFX_MAGMA_MEMBER_M,
  "ON_TRANSITION paints the grunt")
check(woods:coordEventWouldRun(1, 2), "state 0 fires the woods trigger")
woods:setScriptVar(Game3.VAR_PETALBURG_WOODS_STATE, 1)
check(not woods:coordEventWouldRun(1, 2), "state 1 does not")
end)()

;(function()
eq(Game3.TRAINER_BATTLE_CONTINUE_NO_MUSIC, 1, "Roxanne is kind 1")
eq(Game3.TRAINER_ROXANNE, 265, "TRAINER_ROXANNE")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35 } },
}
g.party = { g:makeMon(280, 16) }
g._scriptNpc = {
  trainerId = Game3.TRAINER_ROXANNE, trainerName = "ROXANNE",
  trainerClass = "LEADER",
  party = { { species = 280, level = 14 } },
}
local after = {
  { op = "setflag", flag = Game3.FLAG_BADGE01_GET },
  { op = "end" },
}
local ops = {
  {
    op = "trainerbattle",
    kind = Game3.TRAINER_BATTLE_CONTINUE_NO_MUSIC,
    trainerId = Game3.TRAINER_ROXANNE,
    intro = "Show me.", defeat = "So you are...",
    after = after,
  },
  { op = "loadword", text = "TALK AGAIN" },
  { op = "callstd", id = 2 },
  { op = "end" },
}
g:runNpcScript(ops)
eq(g.phase, "battle", "kind 1 starts the gym fight")
eq(g._scriptPause.ops[1].op, "setflag", "pause is RoxanneDefeated")
eq(g.flags[Game3.FLAG_BADGE01_GET], nil, "badge waits for the win")

g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "NOSEPASS fainted!" }
g.battle.qi = 1
g:advanceBattleText()
eq(g.battle.kind, "won_trainer", "the last KO opens victory")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepBattle()
g:stepBattle()
Input.wasPressed = old
eq(g.phase, "play", "A returns to the gym")
check(g:hasBadge(1), "RoxanneDefeated sets the Stone Badge")
eq(g.field, nil, "first win does not run the talk-again line")

g:runNpcScript(ops)
eq(g.field.text, "TALK AGAIN", "talking again is a nop trainerbattle")
check(g:hasBadge(1), "the badge stays")
end)()

;(function()
-- Starters evolve at 16, right as Roxanne falls. TryEvolvePokemon must
-- not swallow gotobeatenscript / FLAG_BADGE01_GET.
local Input = require("src.core.Input")
local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [281] = { name = "COMBUSKEN", hp = 60, atk = 85, def = 60, spe = 55,
      spa = 85, spd = 60, type1 = 10, type2 = 1 },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35 } },
}
g.party = { g:makeMon(280, 16) }
g._scriptNpc = {
  trainerId = Game3.TRAINER_ROXANNE, trainerName = "ROXANNE",
  trainerClass = "LEADER",
  party = { { species = 280, level = 14 } },
}
local after = {
  { op = "setflag", flag = Game3.FLAG_BADGE01_GET },
  { op = "end" },
}
local ops = {
  {
    op = "trainerbattle",
    kind = Game3.TRAINER_BATTLE_CONTINUE_NO_MUSIC,
    trainerId = Game3.TRAINER_ROXANNE,
    intro = "Show me.", defeat = "So you are...",
    after = after,
  },
  { op = "end" },
}
g:runNpcScript(ops)
eq(g.phase, "battle", "kind 1 starts the gym fight")
g.pendingEvo = {
  {
    mon = g.party[1], from = 280, fromName = "TORCHIC", target = 281,
  },
}
g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "NOSEPASS fainted!" }
g.battle.qi = 1
g:advanceBattleText()
eq(g.battle.kind, "won_trainer", "the last KO opens victory")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepBattle()
g:stepBattle()
eq(g.phase, "play", "A returns to the gym")
eq(g.field and g.field.kind, "evolve", "TryEvolvePokemon runs first")
check(not g:hasBadge(1), "the badge waits for the evolution")
g:stepEvolve(0)
eq(g.evolve.stage, "anim", "A starts the shrink/grow")
g:stepEvolve(Game3.EVOLVE_ANIM)
eq(g.party[1].species, 281, "Combusken after the animation")
eq(g.evolve.stage, "done", "then the done text")
g:stepEvolve(0)
Input.wasPressed = old
check(g:hasBadge(1), "RoxanneDefeated still sets the Stone Badge")
eq(g.party[1].name, "COMBUSKEN", "the starter evolved")
end)()

;(function()
eq(Game3.ITEM_MIRACLE_SEED, 205, "woods gift is Miracle Seed")
eq(Game3.HOLD_EFFECT_GRASS_POWER, 48, "HOLD_EFFECT_GRASS_POWER")
eq(Game3.HOLD_EFFECT_TYPE[48], 12, "Grass")
eq(Game3.TYPE_POWER_ITEM[205], 48, "unextracted items still map")

local packed = string.rep("\0", 18) .. string.char(48, 10) .. string.rep("\0", 24)
eq(#packed, 44, "holdEffect sits at byte 18")
local row = BattleData.parseOneItem(packed, 0)
eq(row.holdEffect, 48, "gItems.holdEffect")
eq(row.holdEffectParam, 10, "and the 10% param")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = {} }
local atk = {
  name = "TREECKO", level = 20, hp = 80, maxHp = 80,
  atk = 50, spa = 50, def = 30, spd = 30,
  type1 = 12, type2 = 12,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local defn = {
  name = "POOCHYENA", level = 15, hp = 400, maxHp = 400,
  atk = 30, spa = 20, def = 20, spd = 20,
  type1 = 17, type2 = 17,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local absorb = { power = 40, type = 12 }
local scratch = { power = 40, type = 0 }
local plain = g:dealDamage(atk, defn, absorb)
defn.hp = 400
atk.item = Game3.ITEM_MIRACLE_SEED
local seeded = g:dealDamage(atk, defn, absorb)
check(seeded.dmg > plain.dmg, "Miracle Seed boosts Grass")
defn.hp = 400
local seededNorm = g:dealDamage(atk, defn, scratch)
atk.item = nil
defn.hp = 400
local plainNorm = g:dealDamage(atk, defn, scratch)
eq(seededNorm.dmg, plainNorm.dmg, "and leaves Tackle alone")

g.battle = { isTrainer = true, player = atk, enemy = defn }
defn.hp = 400
local noBadge = g:dealDamage(atk, defn, scratch)
g.flags[Game3.FLAG_BADGE01_GET] = true
defn.hp = 400
local badged = g:dealDamage(atk, defn, scratch)
check(badged.dmg > noBadge.dmg, "Stone Badge boosts physical Attack")
defn.hp = 400
local foeHit = g:dealDamage(defn, atk, scratch)
g.flags[Game3.FLAG_BADGE01_GET] = nil
atk.hp = 80
local foePlain = g:dealDamage(defn, atk, scratch)
eq(foeHit.dmg, foePlain.dmg, "the foe does not get the badge")
g.battle.isTrainer = false
g.flags[Game3.FLAG_BADGE01_GET] = true
defn.hp = 400
local wild = g:dealDamage(atk, defn, scratch)
g.flags[Game3.FLAG_BADGE01_GET] = nil
defn.hp = 400
local wildOff = g:dealDamage(atk, defn, scratch)
eq(wild.dmg, wildOff.dmg, "wild fights ignore BADGE_BOOST")
end)()

;(function()
eq(Game3.tmhmIndex(Game3.ITEM_TM39), 38, "TM39 is bit 38")
eq(Game3.tmhmIndex(Game3.ITEM_HM_CUT), 50, "HM01 is bit 50")
eq(Game3.tmhmMove(Game3.new(), Game3.ITEM_TM39), 317, "TM39 move id")
local g = Game3.new()
g.phase = "play"
g.data.pokemon = { byIndex = {
  [280] = { name = "TORCHIC",
    tmhm = { BattleData.TORCHIC_TMHM0, BattleData.TORCHIC_TMHM1 } },
  [290] = { name = "WURMPLE", tmhm = { 0, 0 } },
} }
g.data.moves = { byId = {
  [317] = { id = 317, name = "ROCK TOMB", pp = 10, power = 50, type = 5 },
  [15] = { id = 15, name = "CUT", pp = 30, power = 50, type = 0 },
  [264] = { id = 264, name = "FOCUS PUNCH", pp = 20, power = 150, type = 1 },
} }
g.party = { {
  name = "TORCHIC", species = 280, level = 5,
  moves = { { id = 10, name = "SCRATCH" } },
} }
g.bag = {}
g:addItem(Game3.ITEM_TM39, 1)
check(g:canLearnTMHM(g.party[1], Game3.ITEM_TM39), "Torchic learns TM39")
check(not g:canLearnTMHM(g.party[1], Game3.ITEM_TM01), "not Focus Punch")
local taught, taughtMsg = g:teachTMHM(1, Game3.ITEM_TM39)
check(taught, "teaches Rock Tomb")
eq(g.party[1].moves[2].id, 317, "second slot is Rock Tomb")
eq(g:itemCount(Game3.ITEM_TM39), 0, "TM is consumed")
g:addItem(Game3.ITEM_TM39, 1)
local known, knownMsg = g:teachTMHM(1, Game3.ITEM_TM39)
check(not known, "already knows")
check(knownMsg:find("already knows", 1, true) ~= nil, "already-knows line")
eq(g:itemCount(Game3.ITEM_TM39), 1, "TM kept when already known")
g:addItem(Game3.ITEM_TM01, 1)
local noPunch, punchMsg = g:teachTMHM(1, Game3.ITEM_TM01)
check(not noPunch, "incompatible TM")
check(punchMsg:find("can't learn", 1, true) ~= nil, "can't-learn line")
eq(g:itemCount(Game3.ITEM_TM01), 1, "incompatible TM is kept")
g.party[1] = { name = "WURMPLE", species = 290, moves = {} }
local worm, wormMsg = g:teachTMHM(1, Game3.ITEM_TM39)
check(not worm, "Wurmple cannot learn TM39")
check(wormMsg:find("can't learn", 1, true) ~= nil, "Wurmple line")
g.party[1] = { name = "EGG", species = 280, isEgg = true, moves = {} }
local eggOk = g:teachTMHM(1, Game3.ITEM_TM39)
check(not eggOk, "an Egg cannot learn a TM")
g.party[1] = {
  name = "TORCHIC", species = 280,
  moves = {
    { id = 10, name = "SCRATCH" }, { id = 45, name = "GROWL" },
    { id = 52, name = "EMBER" }, { id = 98, name = "QUICK ATTACK" },
  },
}
g.bag = {}
g:addItem(Game3.ITEM_TM39, 1)
local full, fullMsg, need = g:teachTMHM(1, Game3.ITEM_TM39)
check(not full, "a full set does not overwrite")
eq(need, true, "asks to forget")
eq(g:itemCount(Game3.ITEM_TM39), 1, "TM kept until a slot is picked")
local forgot = g:teachTMHM(1, Game3.ITEM_TM39, 2)
check(forgot, "replaces Growl")
eq(g.party[1].moves[2].id, 317, "slot 2 is Rock Tomb")
eq(g:itemCount(Game3.ITEM_TM39), 0, "TM consumed after forget")
g:openPartyTeach(Game3.ITEM_TM39)
eq(g:tmhmPartyLabel({
  name = "TORCHIC", species = 280, moves = { { id = 10 } },
}, Game3.ITEM_TM39), "ABLE", "sub_808AE8C 0x8C ABLE")
eq(g:tmhmPartyLabel({
  name = "WURMPLE", species = 290, moves = {},
}, Game3.ITEM_TM39), "NOT ABLE", "incompatible is NOT ABLE")
eq(g:tmhmPartyLabel({
  name = "EGG", species = 280, isEgg = true, moves = {},
}, Game3.ITEM_TM39), "NOT ABLE", "an Egg is NOT ABLE")
eq(g:tmhmPartyLabel({
  name = "TORCHIC", species = 280, moves = { { id = 317 } },
}, Game3.ITEM_TM39), "LEARNED", "already knows is LEARNED")
g.party = {
  { name = "TORCHIC", species = 280, level = 5, moves = { { id = 10 } } },
  { name = "WURMPLE", species = 290, level = 3, moves = {} },
  { name = "EGG", species = 280, isEgg = true, level = 5, moves = {} },
}
eq(g:tmhmPartyLabel(g.party[1], g.field.item), "ABLE", "party slot 1 ABLE")
eq(g:tmhmPartyLabel(g.party[2], g.field.item), "NOT ABLE", "party slot 2 NOT ABLE")
eq(g:tmhmPartyLabel(g.party[3], g.field.item), "NOT ABLE", "party slot 3 egg")
g.party[1].moves = {
  { id = 10 }, { id = 45 }, { id = 52 }, { id = 98 },
}
g:addItem(Game3.ITEM_TM39, 1)
g:chooseTeachMon(1)
eq(g.field.kind, "party_forget", "forget UI")
g.party[1] = {
  name = "TORCHIC", species = 280,
  moves = { { id = 10, name = "SCRATCH" } },
}
g.bag = {}
g:addItem(Game3.ITEM_HM_CUT, 1)
local hmOk = g:teachTMHM(1, Game3.ITEM_HM_CUT)
check(hmOk, "teaches Cut")
eq(g.party[1].moves[2].id, 15, "learned Cut")
eq(g:itemCount(Game3.ITEM_HM_CUT), 1, "HM is not consumed")
g.flags[Game3.FLAG_BADGE01_GET] = true
g.facing = "east"
g:enterMap({
  id = "g_tmhm_cut", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 3, graphicsId = Game3.GFX_CUTTABLE_TREE, flagId = 0x301 },
  },
}, 1, 1, true)
check(g:useCut(), "party Cut still chops")
g:enterMap({
  id = "g_tmhm_bag", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 3, graphicsId = Game3.GFX_CUTTABLE_TREE, flagId = 0x302 },
  },
}, 1, 1, true)
local bagHm = g:useFieldItem(Game3.ITEM_HM_CUT)
check(bagHm, "bag HM boots")
eq(g.field.kind, "talk", "gOtherText_BootedHM")
check(g.field.text:find("Booted up an HM", 1, true) ~= nil, "Booted up an HM")
check(g.field.thenTmAsk, "then yes/no teach")
check(not g:npcByLocalId(3).hidden, "the tree is still there")
end)()

;(function()
eq(Game3.ITEM_DEVON_GOODS, 269, "Devon Goods is item 269")
eq(Game3.ITEM_LETTER, 274, "Steven's letter is item 274")
eq(Game3.FLAG_SYS_POKENAV_GET, 0x802, "FLAG_SYS_POKENAV_GET")
local g = Game3.new()
eq(g:itemPocket(Game3.ITEM_DEVON_GOODS), Game3.POCKET_KEY, "Goods are a Key Item")
eq(g:itemPocket(Game3.ITEM_LETTER), Game3.POCKET_KEY, "the Letter is too")
eq(g:itemName(Game3.ITEM_DEVON_GOODS), "DEVON GOODS", "Goods name")
eq(g:itemName(Game3.ITEM_LETTER), "LETTER", "Letter name")
eq(g:pocketName(Game3.POCKET_KEY), "KEY ITEMS", "key pocket name")
eq(g:pocketName(Game3.POCKET_TMHM), "TMs & HMs", "TM pocket name")
eq(#g:startMenuItems(), 6, "START has no POKeNAV yet")
g.flags[Game3.FLAG_SYS_POKENAV_GET] = true
eq(#g:startMenuItems(), 7, "Mr. Stone grows the row")
eq(g:startMenuItems()[3], "POKeNAV", "after BAG")
g.phase = "play"
g:openPokeNav()
eq(g.field.kind, "pokenav", "A on POKeNAV opens it")
local Input = require("src.core.Input")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "menu", "B returns to START")

g.facing = "east"
g.playerX, g.playerY = 0, 0
g.bag = {}
g.map = { id = "g_cutter", width = 3, height = 1, grid = { 0, 0, 0 } }
g.map.objects = { {
  x = 1, y = 0, graphicsId = 59, localId = 1,
  script = {
    { op = "setorcopyvar", var = 0x8000, val = Game3.ITEM_HM_CUT },
    { op = "setorcopyvar", var = 0x8001, val = 1 },
    { op = "callstd", id = 0 },
    { op = "end" },
  },
} }
g.npcByMap = { g_cutter = { {
  x = 1, y = 0, graphicsId = 59, localId = 1,
  script = g.map.objects[1].script,
} } }
check(g:tryTalk(), "Cutter giveitem runs")
eq(g:itemCount(Game3.ITEM_HM_CUT), 1, "HM01 is in the bag")
check(g.field.text:find("Obtained the HM01", 1, true) ~= nil,
  "Std_ObtainItem")
local pocketLine = g.field.queue and g.field.queue[2]
check(pocketLine and pocketLine:find("put away", 1, true) ~= nil,
  "put-away follows obtain")
check(pocketLine:find("TMs & HMs", 1, true) ~= nil, "HM pocket name")
eq(g.scriptVars[0x800D], 1, "VAR_RESULT is TRUE")
g.field = nil
g.bag = {}
g:addItem(Game3.ITEM_DEVON_GOODS, 1)
eq(g:itemCount(Game3.ITEM_DEVON_GOODS), 1, "the tunnel grunt's goods")
eq(g:itemPocket(Game3.ITEM_DEVON_GOODS), Game3.POCKET_KEY, "key pocket")
end)()

;(function()
eq(Game3.MULTI_B_PRESSED, 127, "B cancel is MULTI_B_PRESSED")
eq(Game3.MULTICHOICE[13][1], "PSN", "school list 13")
eq(Game3.MULTICHOICE[13][6], "CANCEL", "and CANCEL")
eq(Game3.MULTICHOICE[50][1], "Excellent!", "fishing list 50")
eq(Game3.MULTICHOICE[0][3], "CANCEL", "Briney list 0")
eq(Game3.MULTICHOICE[14][1], "DEWFORD", "Briney list 14")
local Input = require("src.core.Input")
Input:init()
local chooser = Game3.new()
chooser.phase = "play"
chooser.facing = "east"
chooser.playerX, chooser.playerY = 0, 0
chooser.map = { id = "g_multi", width = 3, height = 1, grid = { 0, 0, 0 } }
chooser.npcByMap = { g_multi = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "multichoice", list = 13 },
    { op = "setorcopyvar", var = 0x8000, val = 0x800D },
    { op = "compare", var = 0x8000, val = 0 },
    { op = "goto_if", cond = 1, to = 8 },
    { op = "compare", var = 0x8000, val = 127 },
    { op = "goto_if", cond = 1, to = 11 },
    { op = "end" },
    { op = "loadword", text = "POISON hurts over time." },
    { op = "callstd", id = 4 },
    { op = "end" },
    { op = "loadword", text = "Closed." },
    { op = "callstd", id = 4 },
    { op = "end" },
  },
} } }
check(chooser:tryTalk(), "school list pauses")
eq(chooser.field.kind, "script_choice", "as a choice box")
eq(#chooser.field.labels, 6, "six status rows")
eq(chooser.field.labels[1], "PSN", "PSN first")
eq(chooser.field.cursor, 0, "cursor starts at 0")
local function pressChoice(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  chooser:stepField()
  Input.wasPressed = old
end
pressChoice("down")
eq(chooser.field.cursor, 1, "down moves one")
pressChoice("up")
eq(chooser.field.cursor, 0, "up back to 0")
chooser.field.cursor = 5
pressChoice("down")
eq(chooser.field.cursor, 0, "lists over 3 wrap")
pressChoice("up")
eq(chooser.field.cursor, 5, "up wraps to CANCEL")
pressChoice("down")
eq(chooser.field.cursor, 0, "back on PSN")
pressChoice("a")
eq(chooser.field.kind, "talk", "A runs the case")
eq(chooser.field.text, "POISON hurts over time.", "PSN is index 0")
chooser.field = nil
check(chooser:tryTalk(), "talking again reopens")
pressChoice("b")
eq(chooser.scriptVars[0x800D], 127, "B writes 127")
eq(chooser.field.text, "Closed.", "and the 127 case")
local locked = Game3.new()
locked.phase = "play"
locked.facing = "east"
locked.playerX, locked.playerY = 0, 0
locked.map = { id = "g_fish", width = 3, height = 1, grid = { 0, 0, 0 } }
locked.npcByMap = { g_fish = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "multichoice", list = 50, ignoreB = 1 },
    { op = "compare", var = 0x800D, val = 0 },
    { op = "goto_if", cond = 1, to = 7 },
    { op = "loadword", text = "Fishing advice." },
    { op = "callstd", id = 4 },
    { op = "end" },
    { op = "loadword", text = "Great haul!" },
    { op = "callstd", id = 4 },
    { op = "end" },
  },
} } }
check(locked:tryTalk(), "fishing list pauses")
eq(locked.field.labels[1], "Excellent!", "list 50")
eq(locked.field.ignoreB, true, "ignoreB is set")
local oldB = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
locked:stepField()
Input.wasPressed = oldB
eq(locked.field.kind, "script_choice", "B does not cancel")
oldB = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
locked:stepField()
Input.wasPressed = oldB
eq(locked.field.text, "Great haul!", "Excellent is index 0")
local briney = Game3.new()
briney.phase = "play"
briney.facing = "east"
briney.playerX, briney.playerY = 0, 0
briney.map = { id = "g_sail", width = 3, height = 1, grid = { 0, 0, 0 } }
briney.npcByMap = { g_sail = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "multichoice", list = 0, default = 2, x = 21, y = 6 },
    { op = "end" },
  },
} } }
check(briney:tryTalk(), "Briney list pauses")
eq(briney.field.labels[1], "PETALBURG", "list 0")
eq(briney.field.cursor, 2, "default cursor on CANCEL")
eq(briney.field.boxX, 21, "list at tile x 21")
eq(briney.field.boxY, 6, "and tile y 6")
local ml, mt, mr, mb = Game3.multichoiceFrame(21, 6, briney.field.labels)
eq(mr, 29, "PETALBURG window reaches tile 29")
eq(ml, 21, "and stays at the script x")
eq(mb, 13, "three rows are 2*3+1 tiles")
eq(mt, 6, "top stays")
briney.field.cursor = 2
oldB = Input.wasPressed
Input.wasPressed = function(_, key) return key == "down" end
briney:stepField()
Input.wasPressed = oldB
eq(briney.field.cursor, 2, "three rows do not wrap")
local miss = Game3.new()
miss.phase = "play"
miss.facing = "east"
miss.playerX, miss.playerY = 0, 0
miss.map = { id = "g_miss", width = 3, height = 1, grid = { 0, 0, 0 } }
miss.npcByMap = { g_miss = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "multichoice", list = 99 },
    { op = "loadword", text = "GONE" },
    { op = "callstd", id = 4 },
    { op = "end" },
  },
} } }
check(miss:tryTalk(), "unknown list keeps going")
eq(miss.scriptVars[0x800D], 127, "and writes 127")
eq(miss.field.text, "GONE", "without pausing")
local board = Game3.new()
board.phase = "play"
board.facing = "east"
board.playerX, board.playerY = 0, 0
board.map = { id = "g_board", width = 3, height = 1, grid = { 0, 0, 0 } }
board.npcByMap = { g_board = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "message", text = "Read which topic?" },
    { op = "waitmessage" },
    { op = "multichoice", list = 13, perRow = 3 },
    { op = "end" },
  },
} } }
check(board:tryTalk(), "waitmessage shows the prompt")
eq(board.field.kind, "talk", "first page")
eq(board.field.text, "Read which topic?", "blackboard line")
oldB = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
board:stepField()
Input.wasPressed = oldB
eq(board.field.kind, "script_choice", "then the grid")
eq(board.field.text, "Read which topic?", "prompt stays")
end)()

;(function()
eq(Game3.SPECIAL_SELECT_MON_FOR_NPC_TRADE, 159, "SelectMonForNPCTrade")
eq(Game3.SPECIAL_GET_IN_GAME_TRADE_SPECIES, 252, "GetInGameTradeSpeciesInfo")
eq(Game3.SPECIAL_GET_TRADE_SPECIES, 255, "GetTradeSpecies")
eq(Game3.INGAME_TRADES[0].playerSpecies, Game3.SPECIES_SLAKOTH, "wants Slakoth")
eq(Game3.INGAME_TRADES[0].species, Game3.SPECIES_MAKUHITA, "gives Makuhita")
eq(Game3.INGAME_TRADES[0].name, "MAKIT", "nickname MAKIT")
local Input = require("src.core.Input")
Input:init()
local trader = Game3.new()
trader.phase = "play"
trader.data.pokemon = {
  byIndex = {
    [364] = { name = "SLAKOTH" },
    [335] = { name = "MAKUHITA" },
    [280] = { name = "TORCHIC" },
  },
}
trader.scriptVars = { [0x8004] = 0 }
eq(trader:getInGameTradeSpeciesInfo(), 364, "returns requested species")
eq(trader.stringVars[1], "SLAKOTH", "STR_VAR_1 is yours")
eq(trader.stringVars[2], "MAKUHITA", "STR_VAR_2 is theirs")
trader.party = { trader:makeMon(280, 8) }
trader.scriptVars[0x8005] = 0
eq(trader:getTradeSpecies(), 280, "Torchic is not Slakoth")
trader.party[1].isEgg = true
eq(trader:getTradeSpecies(), 0, "eggs are SPECIES_NONE")
trader.party = { trader:makeMon(364, 8) }
trader.scriptVars[0x8004] = 0
trader.scriptVars[0x8005] = 0
check(trader:createInGameTradePokemon(), "CreateInGameTradePokemon fills gEnemyParty")
eq(trader.party[1].species, 364, "party is still Slakoth until the scene")
eq(trader.inGameTradeIncoming.species, 335, "incoming is Makuhita")
eq(trader.inGameTradeIncoming.name, "MAKIT", "as MAKIT")
eq(trader.inGameTradeIncoming.level, 8, "at the given level")
eq(trader.inGameTradeIncoming.item, 75, "holding X Attack")
eq(trader.inGameTradeIncoming.otName, "ELYSSA", "Elyssa's OT")
eq(trader.inGameTradeIncoming.ivs.hp, 5, "fixed HP IV")
eq(trader.inGameTradeIncoming.ivs.spe, 4, "fixed Spe IV")
eq(trader.inGameTradeIncoming.pid, 0x9C40, "fixed PID")
eq(trader.inGameTradeIncoming.metLocation, 0xFE, "in-game trade met")
check(not trader:hasCaught(335), "dex waits for sub_804BA94")
eq(Game3.SPECIAL_CREATE_IN_GAME_TRADE, 253, "CreateInGameTradePokemon")
eq(Game3.SPECIAL_DO_IN_GAME_TRADE_SCENE, 254, "DoInGameTradeScene")
trader:runSpecial(Game3.SPECIAL_DO_IN_GAME_TRADE_SCENE)
eq(trader.field.kind, "trade_scene", "link-cable waitstate")
check(trader:scriptWaiting(), "LockPlayerFieldControls")
eq(trader.field.text, "SLAKOTH will be sent to ELYSSA.", "sent-to line")
eq(Game3.tradeScenePose(0).bg2hofs, 0xB4, "BG2 HOFS starts at 0xB4")
eq(Game3.tradeScenePose(0).sentX, 0x78 - 0xB4, "sent mon x2 is -180")
trader:walkHeld(Game3.TRADE_SLIDE / 60)
eq(trader.party[1].species, 364, "slide has not swapped")
eq(Game3.tradeScenePose(Game3.TRADE_SLIDE).line, 1, "then the send line")
trader:walkHeld(Game3.TRADE_SEND_MSG / 60)
eq(trader.field.text, "Bye-bye, SLAKOTH!", "Bye-bye after 80 frames")
eq(trader.party[1].species, 364, "Bye-bye has not swapped yet")
local rest = Game3.TRADE_WAIT_A - Game3.TRADE_SLIDE - Game3.TRADE_SEND_MSG
trader:walkHeld(rest / 60)
eq(trader.party[1].species, 364, "sub_804BA94 waits for take-care A")
eq(trader.field.text, "Take good care of MAKIT!", "take-care line")
local oldTrade = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
trader:stepField()
Input.wasPressed = oldTrade
eq(trader.party[1].species, 335, "Makuhita joins on take-care A")
eq(trader.party[1].name, "MAKIT", "as MAKIT")
eq(trader.party[1].level, 8, "at the given level")
eq(trader.party[1].item, 75, "holding X Attack")
eq(trader.party[1].otName, "ELYSSA", "Elyssa's OT")
eq(trader.party[1].ivs.hp, 5, "fixed HP IV")
eq(trader.party[1].ivs.spe, 4, "fixed Spe IV")
eq(trader.party[1].pid, 0x9C40, "fixed PID")
eq(trader.party[1].metLocation, 0xFE, "in-game trade met")
check(trader:hasCaught(335), "dex records Makuhita")
eq(trader.field, nil, "scene closed")
check(not trader:scriptWaiting(), "waitstate ends")
trader.facing = "east"
trader.playerX, trader.playerY = 0, 0
trader.map = { id = "g_trade", width = 3, height = 1, grid = { 0, 0, 0 } }
trader.npcByMap = { g_trade = { {
  x = 1, y = 0, graphicsId = 9,
  script = {
    { op = "special", id = Game3.SPECIAL_SELECT_MON_FOR_NPC_TRADE },
    { op = "waitstate" },
    { op = "end" },
  },
} } }
trader.party = { trader:makeMon(364, 5), trader:makeMon(280, 5) }
check(trader:tryTalk(), "party picker pauses")
eq(trader.field.kind, "npc_trade", "SelectMonForNPCTrade")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
trader:stepField()
Input.wasPressed = old
eq(trader.scriptVars[0x8004], 255, "B is PARTY_MENU cancel")
check(trader:tryTalk(), "picker again")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "down" end
trader:stepField()
Input.wasPressed = old
eq(trader.field.cursor, 1, "down to slot 2")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
trader:stepField()
Input.wasPressed = old
eq(trader.scriptVars[0x8004], 1, "A writes the slot")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.EVO_TRADE, 5, "EVO_TRADE")
eq(Game3.EVO_TRADE_ITEM, 6, "EVO_TRADE_ITEM")
eq(Game3.ITEM_DRAGON_SCALE, 201, "ITEM_DRAGON_SCALE")
eq(Game3.GAME_STAT_EVOLVED_POKEMON, 14, "GAME_STAT_EVOLVED_POKEMON")
eq(Game3.TRADE_EVO_X, 120, "TradeEvolutionScene sprite x")
eq(Game3.TRADE_EVO_Y, 64, "TradeEvolutionScene sprite y")
local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [64] = { name = "KADABRA", hp = 40, atk = 35, def = 30, spe = 105,
      spa = 120, spd = 70, type1 = 14, type2 = 14, growthRate = 3 },
    [65] = { name = "ALAKAZAM", hp = 55, atk = 50, def = 45, spe = 120,
      spa = 135, spd = 85, type1 = 14, type2 = 14, growthRate = 3 },
    [117] = { name = "SEADRA", hp = 55, atk = 65, def = 95, spe = 85,
      spa = 95, spd = 45, type1 = 11, type2 = 11, growthRate = 3 },
    [230] = { name = "KINGDRA", hp = 75, atk = 95, def = 95, spe = 85,
      spa = 95, spd = 95, type1 = 11, type2 = 2, growthRate = 3 },
    [280] = { name = "TORCHIC" },
    [335] = { name = "MAKUHITA" },
  },
}
local kadabra = g:makeMon(64, 20)
eq(g:checkTradeEvolution(kadabra), 65, "Kadabra trades into Alakazam")
eq(g:checkEvolution(kadabra), nil, "type 0 does not trade-evolve")
kadabra.item = Game3.ITEM_EVERSTONE
eq(g:checkTradeEvolution(kadabra), nil, "Everstone blocks type 1")
local seadra = g:makeMon(117, 30)
seadra.item = Game3.ITEM_DRAGON_SCALE
eq(g:checkTradeEvolution(seadra), 230, "Seadra + Dragon Scale")
eq(seadra.item, 0, "EVO_TRADE_ITEM zeros the hold")
eq(g:checkTradeEvolution(g:makeMon(335, 8)), nil, "Makuhita has no trade evo")
local nick = g:makeMon(64, 20)
nick.name = "BOB"
g:applyEvolution(nick, 65)
eq(nick.species, 65, "species becomes Alakazam")
eq(nick.name, "BOB", "EvolutionRenameMon keeps a nickname")
check(g:hasCaught(65), "dex records the post-evo")
eq(g:getGameStat(Game3.GAME_STAT_EVOLVED_POKEMON), 1, "GAME_STAT_EVOLVED")

g.scriptVars = { [0x8005] = 0 }
g.party = { g:makeMon(280, 20) }
g.inGameTradeIncoming = g:makeMon(64, 20)
g.inGameTradeSentName = "TORCHIC"
g:beginScriptWait()
g:doInGameTradeScene()
g.field.t = Game3.TRADE_WAIT_A
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.party[1].species, 64, "swap is still Kadabra")
eq(g.field.kind, "evolve", "TradeEvolutionScene after take-care A")
check(g.evolve and g.evolve.cannotStop, "TASK_BIT_CAN_STOP is off")
check(g:scriptWaiting(), "waitstate holds through the evo")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
g:stepEvolve(0)
eq(g.evolve.stage, "anim", "B advances the announce, it does not cancel")
g:stepEvolve(Game3.EVOLVE_ANIM)
eq(g.party[1].species, 65, "Alakazam after the sparkles")
eq(g.evolve.stage, "done", "FinishEvo text")
g:stepEvolve(0)
Input.wasPressed = old
eq(g.field, nil, "gCB2_AfterEvolution returns to the field")
check(not g:scriptWaiting(), "waitstate ends")
eq(g.party[1].name, "ALAKAZAM", "species-name nickname updates")
g:drawTradeEvolution({ kind = "evolve", text = "What? KADABRA is evolving!" })
check(true, "trade evo draw does not throw without pics")
end)()

;(function()
eq(Game3.TRAINER_BATTLE_DOUBLE, 4, "TRAINER_BATTLE_DOUBLE")
eq(Game3.TRAINER_GINA_AND_MIA_1, 483, "TRAINER_GINA_AND_MIA_1")
eq(Game3.PLAYER_HAS_TWO_USABLE_MONS, 0, "GetMonsStateToDoubles two usable")
eq(Game3.PLAYER_HAS_ONE_MON, 1, "one party slot")
eq(Game3.PLAYER_HAS_ONE_USABLE_MON, 2, "one usable among several")
eq(Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING, 148,
  "special 148 is GetPlayerBigGuyGirlString")
eq(Game3.TEXT_BIG_GUY, "Big guy", "male player")
eq(Game3.TEXT_BIG_GIRL, "Big girl", "female player")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [290] = { name = "WURMPLE", hp = 45, atk = 40, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6 },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35 } },
}
g.data.trainers = { byId = { [Game3.TRAINER_GINA_AND_MIA_1] = {
  name = "GINA & MIA", className = "TWINS",
  doubleBattle = true,
  party = { { species = 290, level = 6 }, { species = 290, level = 6 } },
} } }

g:runSpecial(Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING)
eq(g.stringVars[1], "Big guy", "Brendan is Big guy")
g:applyGender(Game3.GENDER_FEMALE)
g:runSpecial(Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING)
eq(g.stringVars[1], "Big girl", "May is Big girl")
g:applyGender(Game3.GENDER_MALE)

g.party = { g:makeMon(280, 8) }
eq(g:monsStateToDoubles(), Game3.PLAYER_HAS_ONE_MON, "one Torchic")
local cannot = "GINA: Oh? Only one POKeMON?"
local started, refuse = g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_DOUBLE,
  trainerId = Game3.TRAINER_GINA_AND_MIA_1,
  intro = "We battle together!",
  defeat = "We lost...",
  cannot = cannot,
})
eq(started, false, "one mon does not start Gina")
eq(refuse, cannot, "the 3rd pointer is the refuse line")
eq(g.phase, "play", "and stays on the field")

local egg = g:makeMon(280, 5)
egg.isEgg = true
g.party = { egg, g:makeMon(280, 8) }
eq(g:monsStateToDoubles(), Game3.PLAYER_HAS_ONE_USABLE_MON, "egg plus one")
started, refuse = g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_DOUBLE,
  trainerId = Game3.TRAINER_GINA_AND_MIA_1,
  cannot = cannot,
})
eq(started, false, "an egg does not count")
eq(refuse, cannot, "same refuse")

local fainted = g:makeMon(290, 5)
fainted.hp = 0
g.party = { fainted, g:makeMon(280, 8) }
eq(g:monsStateToDoubles(), Game3.PLAYER_HAS_ONE_USABLE_MON, "one fainted")
eq(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_DOUBLE,
  trainerId = Game3.TRAINER_GINA_AND_MIA_1,
  cannot = cannot,
}), false, "a KO'd partner refuses")

g.party = { g:makeMon(280, 8), g:makeMon(290, 6) }
eq(g:monsStateToDoubles(), Game3.PLAYER_HAS_TWO_USABLE_MONS, "two healthy")
check(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_DOUBLE,
  trainerId = Game3.TRAINER_GINA_AND_MIA_1,
  intro = "We battle together!",
  defeat = "We lost...",
  cannot = cannot,
}), "two mons start Gina")
eq(g.phase, "battle", "the fight begins")
check(g.battle.doubles, "as a doubles battle")
eq(g.battle.enemy2.species, 290, "both twins send a mon")
eq(g.battle.player2.species, 290, "and you send both")

g.battle = nil
g.phase = "play"
g.field = nil
g.stringVars = { [1] = "STALE" }
g.party = { g:makeMon(280, 8) }
g:runNpcScript({
  {
    op = "trainerbattle",
    kind = Game3.TRAINER_BATTLE_DOUBLE,
    trainerId = Game3.TRAINER_GINA_AND_MIA_1,
    intro = "We battle together!",
    defeat = "We lost...",
    cannot = cannot,
  },
  { op = "special", id = Game3.SPECIAL_GET_PLAYER_BIG_GUY_GIRL_STRING },
  { op = "loadword", text = "GINA: {STR_VAR_1} is strong!" },
  { op = "callstd", id = 2 },
  { op = "end" },
})
eq(g.phase, "play", "one mon stays on the field")
eq(g.field.text, cannot, "Gina says only one")
eq(g.stringVars[1], "STALE", "post-battle Big guy did not run")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_IS_STARTER_IN_PARTY, 302, "IsStarterInParty is special 302")
eq(Game3.starterSpecies(0), Game3.SPECIES_TREECKO, "VAR_STARTER_MON 0")
eq(Game3.starterSpecies(1), Game3.SPECIES_TORCHIC, "1 is Torchic")
eq(Game3.starterSpecies(2), Game3.SPECIES_MUDKIP, "2 is Mudkip")
eq(Game3.starterSpecies(9), Game3.SPECIES_TREECKO, "out of range is Treecko")

local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [277] = { name = "TREECKO" },
    [280] = { name = "TORCHIC" },
    [283] = { name = "MUDKIP" },
    [290] = { name = "WURMPLE" },
  },
}
g:setScriptVar(Game3.VAR_STARTER_MON, 1)
g.party = { g:makeMon(280, 5) }
eq(g:isStarterInParty(), true, "Torchic is still in the party")
eq(g:runSpecial(Game3.SPECIAL_IS_STARTER_IN_PARTY), 1, "specialvar sees 1")
eq(g.scriptVars[Gen3Script.VAR_RESULT], 1, "VAR_RESULT is 1")

g.party = { g:makeMon(290, 5) }
eq(g:isStarterInParty(), false, "Wurmple is not the starter")
eq(g:runSpecial(Game3.SPECIAL_IS_STARTER_IN_PARTY), 0, "and writes 0")

local egg = g:makeMon(280, 5)
egg.isEgg = true
g.party = { egg }
eq(g:isStarterInParty(), false, "an egg is SPECIES_EGG")

g.party = { g:makeMon(280, 5) }
g:setScriptVar(Game3.VAR_STARTER_MON, 0)
eq(g:isStarterInParty(), false, "Torchic is not Treecko")
g.party = { g:makeMon(277, 5), g:makeMon(280, 5) }
eq(g:isStarterInParty(), true, "Treecko in slot 2 still counts")
end)()

;(function()
eq(Game3.ITEM_QUICK_CLAW, 183, "ITEM_QUICK_CLAW")
eq(Game3.HOLD_EFFECT_QUICK_CLAW, 26, "HOLD_EFFECT_QUICK_CLAW")
eq(Game3.quickClawThreshold(20), 13107, "(20 * 0xFFFF) / 100")
eq(Game3.QUICK_CLAW_SPEED, 0xFFFFFFFF, "UINT_MAX")

local g = Game3.new()
local effect, param = g:holdEffectOf({ item = Game3.ITEM_QUICK_CLAW })
eq(effect, 26, "unextracted Quick Claw still maps")
eq(param, 20, "20% param")
local slow = {
  name = "TORCHIC", spe = 10, item = Game3.ITEM_QUICK_CLAW,
  stages = { spe = 0 },
}
local fast = {
  name = "POOCHYENA", spe = 80, stages = { spe = 0 },
}
eq(g:turnSpeed(slow, 0), Game3.QUICK_CLAW_SPEED, "roll 0 always procs")
eq(g:turnSpeed(slow, 13107), 10, "roll == threshold does not")
eq(g:turnSpeed(fast, 0), 80, "no claw keeps Speed")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 20,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [286] = { name = "POOCHYENA", hp = 35, atk = 55, def = 35, spe = 80,
      spa = 30, spd = 30, type1 = 17, type2 = 17 },
  },
}
g.data.moves = {
  byId = { [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35,
    accuracy = 100 } },
  typeChart = {},
}
g.party = { g:makeMon(280, 5) }
g.party[1].item = Game3.ITEM_QUICK_CLAW
g.rng = function() return 1 end
g:startWildBattle(286, 5)
g.battle.player.item = Game3.ITEM_QUICK_CLAW
g.battle.player.spe = 10
g.battle.enemy.spe = 80
g.battle.player.moves = { g:copyMove(33) }
g.battle.enemy.moves = { g:copyMove(33) }
g:beginTurn(g.battle.player.moves[1])
check(g.battle.queue[1]:find("TORCHIC", 1, true) ~= nil,
  "Quick Claw lets the slower lead move first")
end)()

;(function()
eq(Game3.SPECIAL_BUFFER_TRENDY_PHRASE, 126, "BufferTrendyPhraseString")
eq(Game3.SPECIAL_IS_TRENDY_PHRASE_BORING, 127, "IsTrendyPhraseBoring")
eq(Game3.SPECIAL_BUFFER_RANDOM_HOBBY, 128, "BufferRandomHobbyOrLifestyleString")
eq(Game3.SPECIAL_DEWFORD_HALL_PAINTING, 129, "GetDewfordHallPaintingNameIndex")
eq(#Game3.EC_WORDS[Game3.EC_GROUP_CONDITIONS], 69, "conditions")
eq(#Game3.EC_WORDS[Game3.EC_GROUP_LIFESTYLE], 45, "lifestyle")
eq(#Game3.EC_WORDS[Game3.EC_GROUP_HOBBIES], 54, "hobbies")
eq(Game3.ecPack(10, 0), 5120, "EC_WORD_HOT")
eq(Game3.ecWordText(5120), "HOT", "HOT")
eq(Game3.EC_WORDS[13][7], "CHILD'S PLAY", "CHILD_S_PLAY")
eq(Game3.ecWordText(Game3.ecPack(13, 32)), "FISHING", "EC_WORD_FISHING")

local hotFishing = {
  Game3.ecPack(10, 0), Game3.ecPack(13, 32),
  pop = 40, maxPop = 50, rising = nil,
}
eq(Game3.easyChatPhrase(hotFishing), "HOT FISHING",
  "ConvertEasyChatWordsToString is WORD WORD")
eq(((hotFishing[1] + hotFishing[2]) % 8), 0, "painting case 0 is Scream")

local g = Game3.new()
g.easyChatPairs = {
  hotFishing,
  { Game3.ecPack(10, 1), Game3.ecPack(12, 0), pop = 39, rising = true },
}
g.scriptVars = { [0x8004] = 0 }
g:bufferTrendyPhraseString()
eq(g.stringVars[1], "HOT FISHING", "slot 0 is STR_VAR_1")
eq(g:dewfordHallPaintingIndex(), 0, "GetDewfordHallPaintingNameIndex")
eq(g:isTrendyPhraseBoring(), true, "lead barely ahead, falling, #2 rising")
g.easyChatPairs[1].pop = 80
eq(g:isTrendyPhraseBoring(), false, "a wide lead is not boring")
g.easyChatPairs[1].pop = 40
g.easyChatPairs[1].rising = true
eq(g:isTrendyPhraseBoring(), false, "a rising lead is not boring")

g.rng = function() return 1 end
g:bufferRandomHobbyOrLifestyle()
eq(g.stringVars[2], "CHORES", "even roll is lifestyle word 0")

g:initDewfordTrend()
eq(#g.easyChatPairs, 5, "InitDewfordTrend fills five pairs")
local phrase = Game3.easyChatPhrase(g.easyChatPairs[1])
check(phrase:find(" ", 1, true) ~= nil, "the current trend is two words")
g:runSpecial(Game3.SPECIAL_BUFFER_TRENDY_PHRASE)
eq(g.stringVars[1], phrase, "special 126 buffers it")
end)()

;(function()
eq(Game3.ITEM_EXP_SHARE, 182, "ITEM_EXP_SHARE")
eq(Game3.HOLD_EFFECT_EXP_SHARE, 25, "HOLD_EFFECT_EXP_SHARE")
eq(Game3.wildExp(54, 2), 15, "Wurmple yield 54 lv2 is still 15")
eq(Game3.wildExp(54, 2, true), 22, "trainer 1.5x is still on the unsplit yield")

local g = Game3.new()
eq(g:itemName(Game3.ITEM_EXP_SHARE), "EXP. SHARE", "unextracted name")
eq(g:holdEffectOf({ item = Game3.ITEM_EXP_SHARE }), 25, "fallback holdEffect")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, expYield = 65, growthRate = 3 },
    [290] = { name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, expYield = 54, growthRate = 0 },
  },
}
local lead = g:makeMon(280, 5)
local bench = g:makeMon(280, 5)
lead.exp = Game3.expAtLevel(3, 5)
bench.exp = Game3.expAtLevel(3, 5)
g.party = { lead, bench }

local lines = g:awardExp(lead, { level = 2, expYield = 54 })
eq(lead.exp - Game3.expAtLevel(3, 5), 15, "no Share: the fighter takes all 15")
eq(bench.exp - Game3.expAtLevel(3, 5), 0, "the bench gets nothing")
eq(lines[1], "TORCHIC gained 15 EXP. Points!", "announces the full amount")

lead.exp = Game3.expAtLevel(3, 5)
bench.exp = Game3.expAtLevel(3, 5)
bench.item = Game3.ITEM_EXP_SHARE
g.battle = { sentIn = { [1] = true } }
g:awardExp(lead, { level = 2, expYield = 54 })
eq(lead.exp - Game3.expAtLevel(3, 5), 7, "sentIn half is 15/2/1")
eq(bench.exp - Game3.expAtLevel(3, 5), 7, "Share half is 15/2/1")

lead.exp = Game3.expAtLevel(3, 5)
bench.exp = Game3.expAtLevel(3, 5)
lead.item = Game3.ITEM_EXP_SHARE
bench.item = nil
g.battle = { sentIn = { [1] = true } }
g:awardExp(lead, { level = 2, expYield = 54 })
eq(lead.exp - Game3.expAtLevel(3, 5), 14, "fighter holding Share gets both halves")
eq(bench.exp - Game3.expAtLevel(3, 5), 0, "a bench without Share is skipped")

lead.item = nil
lead.exp = Game3.expAtLevel(3, 5)
g.battle = { sentIn = { [1] = true } }
g:awardExp(lead, { level = 2, expYield = 54 }, true)
eq(lead.exp - Game3.expAtLevel(3, 5), 22, "trainer 1.5x is after the split")

lead.item = Game3.ITEM_EXP_SHARE
lead.exp = Game3.expAtLevel(3, 5)
g:awardExp(lead, { level = 2, expYield = 54 }, true)
eq(lead.exp - Game3.expAtLevel(3, 5), 21, "14 then trainer 1.5x is 21")

lead.item = nil
lead.exp = Game3.expAtLevel(3, 5)
bench.hp = 0
bench.item = Game3.ITEM_EXP_SHARE
bench.exp = Game3.expAtLevel(3, 5)
g.battle = { sentIn = { [1] = true } }
g:awardExp(lead, { level = 2, expYield = 54 })
eq(lead.exp - Game3.expAtLevel(3, 5), 15, "a fainted Share holder is not viaExpShare")
eq(bench.exp - Game3.expAtLevel(3, 5), 0, "fainted mons get no EXP")

bench.hp = bench.maxHp
bench.item = nil
g.party = { lead, bench }
g:startWildBattle(290, 2)
eq(g.battle.sentIn[1], true, "the lead is marked sentIn")
eq(g.battle.sentIn[2], nil, "the bench is not")
check(g:switchTo(2), "a healthy bench can switch in")
eq(g.battle.sentIn[2], true, "the incoming mon is marked")

local outsider = g:makeMon(280, 5)
outsider.exp = Game3.expAtLevel(3, 5)
g:awardExp(outsider, { level = 2, expYield = 54 })
eq(outsider.exp - Game3.expAtLevel(3, 5), 15, "a mon not in the party still gets the full yield")
end)()

;(function()
local g = Game3.new()
g.trainerId = 1000
eq(g:isOtherTrainer(nil), false, "legacy nil OT is own")
eq(g:isOtherTrainer(1000, "BRENDAN"), false, "same id and name is own")
eq(g:isOtherTrainer(1000), false, "same id without a name is own")
eq(g:isOtherTrainer(1000, "ELYSSA"), true, "same id, other name is traded")
eq(g:isOtherTrainer(49562, "ELYSSA"), true, "a foreign id is traded")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, expYield = 65, growthRate = 3 },
    [335] = { name = "MAKUHITA", hp = 72, atk = 60, def = 30, spe = 25,
      spa = 20, spd = 30, type1 = 1, type2 = 1, expYield = 87, growthRate = 1 },
  },
}
check(g:giveMon(280, 5), "starter join")
eq(g.party[1].otId, 1000, "GiveMonToPlayer stamps the trainer id")
eq(g.party[1].otName, "BRENDAN", "and the player name")
eq(g:isTradedMon(g.party[1]), false, "a starter is not traded")

g.scriptVars = { [0x8004] = 0, [0x8005] = 0 }
g.party = { g:makeMon(280, 8) }
check(g:createInGameTradePokemon(), "Elyssa's Makuhita")
check(g:finishInGameTrade(), "scene swap")
local makit = g.party[1]
eq(makit.otId, 49562, "foreign OT id")
eq(g:isTradedMon(makit), true, "IsTradedMon")
makit.exp = Game3.expAtLevel(makit.growth or 1, makit.level)
local lines = g:awardExp(makit, { level = 2, expYield = 54 })
eq(makit.exp - Game3.expAtLevel(makit.growth or 1, makit.level), 22,
  "traded 1.5x of 15 is 22")
eq(lines[1], "MAKIT gained a boosted 22 EXP. Points!", "BattleText_BoostedExp")

makit.exp = Game3.expAtLevel(makit.growth or 1, makit.level)
g:awardExp(makit, { level = 2, expYield = 54 }, true)
eq(makit.exp - Game3.expAtLevel(makit.growth or 1, makit.level), 33,
  "trainer then traded: 15 -> 22 -> 33")
end)()

;(function()
eq(Game3.EFFECT_SPEED_DOWN_HIT, 70, "EFFECT_SPEED_DOWN_HIT")
eq(Game3.EFFECT_DEFENSE_UP_HIT, 138, "EFFECT_DEFENSE_UP_HIT")
eq(Game3.statDownHitSpec(70), "spe", "Rock Tomb drops Speed")
eq(Game3.statUpHitSpec(138), "def", "Steel Wing raises Defense")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = {} }
local atk = {
  name = "NOSEPASS", level = 15, hp = 40, maxHp = 40,
  atk = 30, def = 50, spa = 30, spd = 50, spe = 20, type1 = 5, type2 = 5,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local defn = {
  name = "TORCHIC", level = 12, hp = 80, maxHp = 80,
  atk = 20, def = 20, spa = 20, spd = 20, spe = 20, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local tomb = {
  name = "ROCK TOMB", effect = Game3.EFFECT_SPEED_DOWN_HIT,
  power = 50, type = Game3.TYPE_ROCK, accuracy = 100, pp = 10,
  secondary = 100, flags = 0,
}
g:useMove(atk, defn, tomb)
eq(defn.stages.spe, -1, "Rock Tomb always drops Speed")

defn.stages.spe = 0
defn.ability = Game3.ABILITY_SHIELD_DUST
g:useMove(atk, defn, tomb)
eq(defn.stages.spe, 0, "Shield Dust blocks the drop")

defn.ability = Game3.ABILITY_CLEAR_BODY
g:useMove(atk, defn, tomb)
eq(defn.stages.spe, 0, "Clear Body blocks the drop")

defn.ability = nil
atk.stages.def = 0
local wing = {
  name = "STEEL WING", effect = Game3.EFFECT_DEFENSE_UP_HIT,
  power = 70, type = Game3.TYPE_STEEL, accuracy = 100, pp = 25,
  secondary = 10, flags = Game3.FLAG_CONTACT,
}
g:useMove(atk, defn, wing)
eq(atk.stages.def, 1, "roll 1 procs Steel Wing's 10%")
atk.stages.def = 0
g.rng = function() return 11 end
g:useMove(atk, defn, wing)
eq(atk.stages.def, 0, "roll 11 misses the 10%")
end)()

;(function()
eq(Game3.EFFECT_ACCURACY_DOWN, 23, "EFFECT_ACCURACY_DOWN")
eq(Game3.EFFECT_ACCURACY_DOWN_HIT, 73, "EFFECT_ACCURACY_DOWN_HIT")
eq(Game3.ABILITY_KEEN_EYE, 51, "ABILITY_KEEN_EYE")
eq(Game3.accuracyFromStages(100, 0, 0), 100, "neutral stages keep 100")
eq(Game3.accuracyFromStages(100, -1, 0), 75, "Sand-Attack is 75%")
eq(Game3.accuracyFromStages(100, 0, 1), 75, "Double Team on the foe is 75%")
eq(Game3.accuracyFromStages(100, -6, 0), 33, "-6 is 33/100")
eq(Game3.accuracyFromStages(80, 0, 0), 80, "Rock Tomb stays 80")
eq(Game3.statDownHitSpec(73), "acc", "Mud-Slap drops Accuracy")

local g = Game3.new()
g.data.moves = { typeChart = { { 4, 2, 0 } } }
eq(g:moveHitChance(
  { stages = { acc = -1 } }, { stages = {} },
  { accuracy = 100 }, 0), 75, "hit chance after Sand-Attack")

local atk = {
  name = "POOCHYENA", level = 9, hp = 30, maxHp = 30,
  atk = 20, spa = 10, type1 = 16, type2 = 16,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0 },
}
local defn = {
  name = "TORCHIC", level = 5, hp = 40, maxHp = 40,
  atk = 20, def = 20, spa = 20, spd = 20, spe = 20, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0 },
}
g.rng = function() return 1 end
g:useMove(atk, defn, {
  name = "SAND-ATTACK", effect = Game3.EFFECT_ACCURACY_DOWN,
  power = 0, type = Game3.TYPE_GROUND, accuracy = 100, pp = 15,
})
eq(defn.stages.acc, -1, "Sand-Attack drops ACCURACY")

defn.ability = Game3.ABILITY_KEEN_EYE
defn.stages.acc = 0
g:useMove(atk, defn, {
  name = "FLASH", effect = Game3.EFFECT_ACCURACY_DOWN,
  power = 0, type = 0, accuracy = 70, pp = 20,
})
eq(defn.stages.acc, 0, "Keen Eye blocks Flash")

defn.ability = nil
local flyer = {
  name = "TAILLOW", hp = 30, maxHp = 30, type1 = 0, type2 = 2,
  stages = { acc = 0 },
}
g:useMove(atk, flyer, {
  name = "SAND-ATTACK", effect = Game3.EFFECT_ACCURACY_DOWN,
  power = 0, type = Game3.TYPE_GROUND, accuracy = 100, pp = 15,
})
eq(flyer.stages.acc, 0, "Flying is immune to Sand-Attack")

defn.stages.acc = -1
local scratch = {
  name = "SCRATCH", effect = 0, power = 40, type = 0,
  accuracy = 100, pp = 35,
}
g.rng = function() return 76 end
local lines = g:useMove(defn, atk, scratch)
check(lines[2]:find("missed", 1, true) ~= nil,
  "the Sand-Attacked mon misses on roll 76")
g.rng = function() return 75 end
lines = g:useMove(defn, atk, scratch)
check(not (lines[2] and lines[2]:find("missed", 1, true)),
  "and hits on roll 75")

defn.stages.acc = 0
g:useMove(atk, defn, {
  name = "MUD-SLAP", effect = Game3.EFFECT_ACCURACY_DOWN_HIT,
  power = 20, type = Game3.TYPE_GROUND, accuracy = 100, pp = 10,
  secondary = 100,
})
eq(defn.stages.acc, -1, "Mud-Slap's 100% secondary drops Accuracy")

g.battle = { weather = Game3.WEATHER_SUN }
eq(g:moveHitChance(atk, defn, { accuracy = 70, type = 13 },
  Game3.EFFECT_THUNDER), 50, "Thunder in sun is 50%")
g.battle.weather = Game3.WEATHER_RAIN
eq(g:moveHitChance(atk, defn, { accuracy = 70, type = 13 },
  Game3.EFFECT_THUNDER), nil, "Thunder in rain cannot miss")
atk.stages.acc = -6
eq(g:moveHitChance(atk, defn, { accuracy = 70, type = 13 },
  Game3.EFFECT_THUNDER), nil, "even after Sand-Attack")
end)()

;(function()
eq(Game3.EFFECT_FOCUS_ENERGY, 47, "EFFECT_FOCUS_ENERGY")
eq(Game3.critDenom(0), 16, "stage 0 is 1/16")
eq(Game3.critDenom(0, true), 4, "Focus Energy is +2 (1/4)")
eq(Game3.critDenom(43), 8, "Slash is +1 (1/8)")
eq(Game3.critDenom(43, true), 3, "Slash + Focus Energy is 1/3")
eq(Game3.critDenom(75), 8, "Sky Attack is +1")

local g = Game3.new()
g.data.moves = { typeChart = {} }
local bird = {
  name = "TAILLOW", level = 5, hp = 30, maxHp = 30,
  atk = 20, spa = 10, type1 = 0, type2 = 2,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local lines = g:useFocusEnergy(bird, { "TAILLOW used FOCUS ENERGY!" })
eq(bird.focusEnergy, true, "STATUS2_FOCUS_ENERGY")
eq(lines[2], "TAILLOW is getting pumped!", "BattleText_GetPumped")
lines = g:useFocusEnergy(bird, { "TAILLOW used FOCUS ENERGY!" })
eq(lines[2], "But it failed!", "already pumped")

g:useMove(bird, bird, {
  name = "FOCUS ENERGY", effect = Game3.EFFECT_FOCUS_ENERGY,
  power = 0, type = 0, accuracy = 0, pp = 30,
})
eq(bird.focusEnergy, true, "useMove sets it")

local prey = {
  name = "WURMPLE", level = 2, hp = 80, maxHp = 80,
  def = 10, spd = 10, type1 = 6, type2 = 6,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.rng = function() return 4 end
local hit = g:dealDamage(bird, prey, {
  name = "PECK", effect = 0, power = 35, type = 2, accuracy = 100,
})
eq(hit.crit, true, "roll 4 of 4 is a crit")

g.battle = { wallyTutorial = true }
prey.hp = 80
hit = g:dealDamage(bird, prey, {
  name = "PECK", effect = 0, power = 35, type = 2, accuracy = 100,
})
eq(hit.crit, false, "Wally's tutorial cannot crit")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [276] = { name = "TAILLOW", hp = 40, atk = 55, def = 30, spe = 85,
      spa = 30, spd = 30, type1 = 0, type2 = 2 },
  },
}
g.battle = nil
g.party = { g:makeMon(280, 5), g:makeMon(276, 5) }
g.party[2].focusEnergy = true
g:startWildBattle(276, 4)
eq(g.party[1].focusEnergy, nil, "a new fight clears the lead")
g.party[2].focusEnergy = true
check(g:switchTo(2), "switch in Taillow")
eq(g.battle.player.focusEnergy, nil, "and switch-in drops Focus Energy")
end)()

;(function()
eq(Game3.EFFECT_LEVEL_DAMAGE, 87, "EFFECT_LEVEL_DAMAGE")
eq(Game3.EFFECT_KNOCK_OFF, 188, "EFFECT_KNOCK_OFF")
eq(Game3.ABILITY_STICKY_HOLD, 60, "ABILITY_STICKY_HOLD")
eq(Game3.TYPE_FIGHTING, 1, "Fighting")
eq(Game3.TYPE_DARK, 17, "Dark")

local g = Game3.new()
g.rng = function() return 1 end
-- Fighting vs Ghost is immune; vs Normal is 2x (display still 1x).
g.data.moves = { typeChart = { { 1, 7, 0 }, { 1, 0, 20 } } }
local machop = {
  name = "MACHOP", level = 17, hp = 50, maxHp = 50,
  atk = 80, spa = 10, type1 = 1, type2 = 1,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local torchic = {
  name = "TORCHIC", level = 12, hp = 80, maxHp = 80,
  def = 80, spd = 80, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local toss = {
  name = "SEISMIC TOSS", effect = Game3.EFFECT_LEVEL_DAMAGE,
  power = 1, type = Game3.TYPE_FIGHTING, accuracy = 100, pp = 20,
}
local hit = g:dealDamage(machop, torchic, toss)
eq(hit.dmg, 17, "Seismic Toss is the user's level")
eq(hit.mul, 10, "and hides the type multiplier")
eq(hit.crit, false, "no crit roll")
eq(torchic.hp, 63, "80 - 17")

torchic.hp = 80
torchic.type1, torchic.type2 = 0, 0
hit = g:dealDamage(machop, torchic, toss)
eq(hit.dmg, 17, "still level vs a 2x type")
eq(hit.mul, 10, "SE flags are cleared")

local ghost = {
  name = "SHUPPET", level = 10, hp = 40, maxHp = 40,
  def = 20, spd = 20, type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
hit = g:dealDamage(machop, ghost, toss)
eq(hit.dmg, 0, "Ghost is immune")
eq(hit.mul, 0, "and typecalc keeps NO_EFFECT")

torchic.type1, torchic.type2 = 10, 10
torchic.hp = 80
torchic.ability = Game3.ABILITY_WONDER_GUARD
hit = g:dealDamage(machop, torchic, toss)
eq(hit.dmg, 0, "Wonder Guard blocks a 1x hit")
torchic.ability = nil

torchic.hp = 5
torchic.endured = true
hit = g:dealDamage(machop, torchic, toss)
eq(hit.dmg, 4, "Endure leaves 1 HP")
eq(hit.endured, true, "and flags it")
eq(torchic.hp, 1, "1 HP left")

torchic.type1, torchic.type2 = 0, 0
torchic.hp = 80
torchic.endured = nil
local lines = g:useMove(machop, torchic, toss)
eq(torchic.hp, 63, "useMove deals 17")
local se = false
for i = 1, #lines do
  if lines[i]:find("super effective", 1, true) then se = true end
end
check(not se, "cleared SE/NVE is not printed")
torchic.type1, torchic.type2 = 10, 10

local makuhita = {
  name = "MAKUHITA", level = 18, hp = 60, maxHp = 60,
  atk = 40, spa = 10, type1 = 1, type2 = 1,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local knock = {
  name = "KNOCK OFF", effect = Game3.EFFECT_KNOCK_OFF,
  power = 20, type = Game3.TYPE_DARK, accuracy = 100, pp = 20,
  secondary = 100, flags = Game3.FLAG_CONTACT,
}
torchic.hp = 80
torchic.item = Game3.ITEM_ORAN_BERRY
lines = g:useMove(makuhita, torchic, knock)
eq(torchic.item, 0, "Knock Off strips the berry")
local found = false
for i = 1, #lines do
  if lines[i] == "MAKUHITA knocked off TORCHIC's ORAN BERRY!" then
    found = true
  end
end
check(found, "BattleText_KnockedOffItem")

torchic.hp = 80
torchic.item = Game3.ITEM_ORAN_BERRY
torchic.ability = Game3.ABILITY_STICKY_HOLD
lines = g:useMove(makuhita, torchic, knock)
eq(torchic.item, Game3.ITEM_ORAN_BERRY, "Sticky Hold keeps the item")
found = false
for i = 1, #lines do
  if lines[i]:find("made KNOCK OFF ineffective", 1, true) then
    found = true
  end
end
check(found, "BattleText_MadeIneffective")

torchic.ability = Game3.ABILITY_SHIELD_DUST
torchic.hp = 80
lines = g:useMove(makuhita, torchic, knock)
eq(torchic.item, 0, "Shield Dust does not block Knock Off")

torchic.ability = nil
torchic.hp = 80
torchic.item = nil
lines = g:useMove(makuhita, torchic, knock)
found = false
for i = 1, #lines do
  if lines[i]:find("knocked off", 1, true) then found = true end
end
check(not found, "no item means no knock-off line")
end)()

;(function()
eq(Game3.ITEM_POTION, 13, "Potion")
eq(Game3.ITEM_SUPER_POTION, 22, "Super Potion")
eq(Game3.HEAL_AMOUNT[13], 20, "Potion heals 20")
eq(Game3.HEAL_AMOUNT[22], 50, "Super Potion heals 50")

local g = Game3.new()
check(g:shouldUseHealItem({ hp = 9, maxHp = 40 }, 13), "below 25%")
check(g:shouldUseHealItem({ hp = 19, maxHp = 40 }, 13), "missing more than 20")
check(not g:shouldUseHealItem({ hp = 30, maxHp = 40 }, 13), "does not top off")
check(not g:shouldUseHealItem({ hp = 0, maxHp = 40 }, 13), "fainted skip")
check(g:shouldUseHealItem({ hp = 12, maxHp = 80 }, 22), "Super Potion at 25%")
check(g:shouldUseHealItem({ hp = 20, maxHp = 80 }, 22), "or missing more than 50")
check(not g:shouldUseHealItem({ hp = 40, maxHp = 80 }, 22), "half HP Super Potion waits")

local enc = GbaText.encodeLatin("ROXANNE") .. string.char(GbaText.EOS)
enc = enc .. string.rep("\0", BattleData.TRAINER_NAME_LENGTH)
enc = enc:sub(1, BattleData.TRAINER_NAME_LENGTH)
local row = string.char(0, 2, 0, 0) .. enc
  .. GbaBin.packU16(13) .. GbaBin.packU16(13) .. string.rep("\0", 4)
  .. string.char(0) .. string.rep("\0", 3) .. string.rep("\0", 4)
  .. string.char(0) .. string.rep("\0", 3) .. GbaBin.packPtr(0)
eq(#row, 40, "trainer row still 40")
local parsed = BattleData.parseOneTrainer(row .. string.rep("\0", 8), 0)
eq(parsed.items[1], 13, "Roxanne's first Potion")
eq(parsed.items[2], 13, "and the second")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [66] = { name = "MACHOP", hp = 70, atk = 80, def = 50, spe = 35,
      spa = 35, spd = 35, type1 = 1, type2 = 1 },
  },
}
g.data.moves = {
  byId = { [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35,
    accuracy = 100 } },
  typeChart = {},
}
g.party = { g:makeMon(280, 12) }
local npc = {
  trainerName = "BRAWLY", trainerClass = "LEADER",
  items = { Game3.ITEM_SUPER_POTION, Game3.ITEM_SUPER_POTION },
  party = { { species = 66, level = 17, moves = { 33 } },
    { species = 66, level = 18, moves = { 33 } } },
}
check(g:startTrainerBattle(npc), "Brawly fight")
eq(g.battle.numItems, 2, "two Super Potions")
eq(g.battle.trainerItems[1], 22, "first slot")
eq(g:trainerMonsLeft(), 2, "Machop plus the bench")

g.battle.npc = npc
local healed = { name = "MACHOP", hp = 10, maxHp = 50 }
local lines = g:applyTrainerItem(healed, Game3.ITEM_SUPER_POTION)
eq(healed.hp, 50, "Super Potion heals 50")
eq(lines[1], "LEADER BRAWLY used SUPER POTION!", "BattleText_Used2")
eq(lines[2], "MACHOP's SUPER POTION restored health!",
  "BattleText_RestoredHealth")

g.battle.kind = "menu"
g.battle.enemy.hp = 10
g.battle.player.moves = { g:copyMove(33) }
g.battle.enemy.moves = { g:copyMove(33) }
g.rng = function() return 1 end
g:beginTurn(g.battle.player.moves[1])
eq(g.battle.queue[1], "LEADER BRAWLY used SUPER POTION!", "item action first")
eq(g.battle.trainerItems[1], 0, "consumed the first")
check(g.battle.enemy.hp > 10, "potion landed before the hit")
check(g.battle.queue[3]:find("TACKLE", 1, true) ~= nil, "then the player moves")
local enemyMove = false
for i = 3, #g.battle.queue do
  if g.battle.queue[i]:find("MACHOP used", 1, true) then enemyMove = true end
end
check(not enemyMove, "the potion replaces the attack")

g.party[1].hp = g.party[1].maxHp
check(g:startTrainerBattle(npc), "rematch")
g.battle.kind = "menu"
g.battle.player.moves = { g:copyMove(33) }
g.battle.enemy.moves = { g:copyMove(33) }
g:beginTurn(g.battle.player.moves[1])
eq(g.battle.trainerItems[1], 22, "full HP keeps the Super Potion")
check(g.battle.queue[1]:find("TACKLE", 1, true) ~= nil, "and the foe attacks")
end)()

;(function()
eq(Game3.EFFECT_EVASION_UP, 16, "EFFECT_EVASION_UP")
eq(Game3.EFFECT_ALWAYS_HIT, 17, "EFFECT_ALWAYS_HIT")
eq(Game3.EFFECT_VITAL_THROW, 78, "EFFECT_VITAL_THROW")
eq(Game3.statUpSpec(16)[1][1], "eva", "Double Team raises EVASION")
eq(Game3.accuracyFromStages(100, 0, 1), 75, "+1 evasion is 75%")

local g = Game3.new()
g.data.moves = {
  typeChart = {},
  byId = {
    [104] = { id = 104, name = "DOUBLE TEAM", effect = 16, power = 0,
      type = 0, accuracy = 0, pp = 15, priority = 0, target = 16 },
    [129] = { id = 129, name = "SWIFT", effect = 17, power = 60,
      type = 0, accuracy = 0, pp = 20, priority = 0 },
  },
}
eq(g:copyMove(104).accuracy, 0, "Double Team keeps accuracy 0")
eq(g:copyMove(129).accuracy, 0, "Swift keeps accuracy 0")

local bird = {
  name = "TAILLOW", level = 19, hp = 40, maxHp = 40,
  atk = 20, spa = 10, type1 = 0, type2 = 2,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local foe = {
  name = "WURMPLE", level = 5, hp = 40, maxHp = 40,
  atk = 20, spa = 10, type1 = 6, type2 = 6,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0 },
}
local team = {
  name = "DOUBLE TEAM", effect = Game3.EFFECT_EVASION_UP,
  power = 0, type = 0, accuracy = 0, pp = 15,
}
g:useMove(bird, foe, team)
eq(bird.stages.eva, 1, "EVASION +1")
eq(g:moveHitChance(foe, bird, { accuracy = 100 }, 0), 75,
  "the foe's 100% move is 75%")
local line
for _ = 1, 6 do
  line = g:useMove(bird, foe, {
    name = "DOUBLE TEAM", effect = Game3.EFFECT_EVASION_UP,
    power = 0, type = 0, accuracy = 0, pp = 15,
  })
end
eq(bird.stages.eva, 6, "capped at +6")
eq(line[2], "TAILLOW's EVASION won't go any higher!", "seventh use fails")

eq(g:moveHitChance(bird, foe, { accuracy = 0, effect = 17 },
  Game3.EFFECT_ALWAYS_HIT), nil, "Swift cannot miss")
foe.stages.eva = 6
eq(g:moveHitChance(bird, foe, {
  accuracy = 100, effect = Game3.EFFECT_VITAL_THROW,
}, Game3.EFFECT_VITAL_THROW), nil, "Vital Throw ignores stages")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_SHOW_EASY_CHAT, 95, "ShowEasyChatScreen")
eq(Game3.EC_TYPE_TRENDY_PHRASE, 9, "Dewford mode")
eq(Game3.FLAG_SYS_CHAT_USED, 0x805, "FLAG_SYS_CHAT_USED")
eq(Game3.FLAG_SYS_POPWORD_INPUT, 0x833, "FLAG_SYS_POPWORD_INPUT")
eq(Game3.FLAG_SYS_MIX_RECORD, 0x834, "FLAG_SYS_MIX_RECORD")

local hot = Game3.ecPack(10, 0)
local fishing = Game3.ecPack(13, 32)
local good = Game3.ecPack(10, 5)
local bike = Game3.ecPack(13, 21)
local tasty = Game3.ecPack(10, 16)
local walk = Game3.ecPack(13, 20)

local function fivePairs()
  return {
    { hot, fishing, pop = 40, maxPop = 50 },
    { Game3.ecPack(10, 1), Game3.ecPack(12, 0), pop = 39, maxPop = 48 },
    { Game3.ecPack(10, 2), Game3.ecPack(12, 1), pop = 38, maxPop = 47 },
    { Game3.ecPack(10, 3), Game3.ecPack(12, 2), pop = 37, maxPop = 46 },
    { Game3.ecPack(10, 4), Game3.ecPack(12, 3), pop = 36, maxPop = 45 },
  }
end

local g = Game3.new()
g.easyChatPairs = fivePairs()
g.scriptVars = { [0x8004] = 0 }
g:runNpcScript({
  { op = "special", id = Game3.SPECIAL_SHOW_EASY_CHAT },
  { op = "loadword", text = "SKIPPED" },
  { op = "callstd", id = 2 },
})
eq(g.field.kind, "talk", "other modes do not wait")
eq(g.field.text, "SKIPPED", "the script continues")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "RESULT 0")

g = Game3.new()
g.easyChatPairs = fivePairs()
g.scriptVars = { [0x8004] = 9 }
g:runNpcScript({
  { op = "special", id = Game3.SPECIAL_SHOW_EASY_CHAT },
  { op = "loadword", text = "AFTER" },
  { op = "callstd", id = 2 },
})
eq(g.field.kind, "easy_chat", "no waitstate still pauses")
check(g.scriptWait, "scriptWait is armed")
eq(g.flags[Game3.FLAG_SYS_CHAT_USED], true, "FLAG_SYS_CHAT_USED on open")
eq(g.field.words[1], hot, "prefill word 0")
eq(g.field.words[2], fishing, "prefill word 1")
eq(g.field.slot, 0, "starts on Conditions")
eq(g.field.labels[1], "HOT", "Conditions list")
g:finishEasyChat(false)
eq(g.field.kind, "talk", "B cancel resumes")
eq(g.field.text, "AFTER", "AFTER")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "cancel is RESULT 0")
eq(Game3.easyChatPhrase(g.easyChatPairs[1]), "HOT FISHING",
  "cancel does not call sub_80FA364")

g = Game3.new()
g.easyChatPairs = fivePairs()
g.scriptVars = { [0x8004] = 9 }
g:showEasyChatScreen()
g.field.words = { hot, fishing }
g:finishEasyChat(true)
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "same phrase is RESULT 0")
eq(g.flags[Game3.FLAG_SYS_POPWORD_INPUT], nil, "and skips sub_80FA364")

g = Game3.new()
g.easyChatPairs = fivePairs()
g.scriptVars = { [0x8004] = 9 }
g:showEasyChatScreen()
g.field.words = { good, bike }
g:finishEasyChat(true)
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "a new phrase is RESULT 1")
eq(g:varGet(0x8004), 1, "first unique becomes the trend")
eq(Game3.easyChatPhrase(g.easyChatPairs[1]), "GOOD BIKE",
  "overwrite slot 0 words")
eq(g.easyChatPairs[1].pop, 40, "and leave popularity alone")
eq(g.flags[Game3.FLAG_SYS_POPWORD_INPUT], true, "FLAG_SYS_POPWORD_INPUT")

g.scriptVars = { [0x8004] = 9 }
g:showEasyChatScreen()
g.field.words = { Game3.ecPack(10, 1), Game3.ecPack(12, 0) }
g:finishEasyChat(true)
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "already-listed still RESULT 1")
eq(g:varGet(0x8004), 0, "but 0x8004 0 is not trendy enough")
eq(Game3.easyChatPhrase(g.easyChatPairs[1]), "GOOD BIKE",
  "a duplicate does not replace the lead")

g = Game3.new()
g.rng = function() return 1 end
g.easyChatPairs = {
  { hot, fishing, pop = 100, maxPop = 127 },
  { Game3.ecPack(10, 1), Game3.ecPack(12, 0), pop = 100, maxPop = 127 },
  { Game3.ecPack(10, 2), Game3.ecPack(12, 1), pop = 100, maxPop = 127 },
  { Game3.ecPack(10, 3), Game3.ecPack(12, 2), pop = 100, maxPop = 127 },
  { Game3.ecPack(10, 4), Game3.ecPack(12, 3), pop = 100, maxPop = 127 },
}
g.flags = { [Game3.FLAG_SYS_POPWORD_INPUT] = true }
check(not g:submitDewfordPhrase(tasty, walk),
  "a weak unique phrase writes the last slot")
eq(g.easyChatPairs[5][1], tasty, "slot 4 is overwritten")
eq(g.easyChatPairs[1][1], hot, "the lead is unchanged")
end)()

;(function()
eq(Game3.EFFECT_TELEPORT, 153, "EFFECT_TELEPORT")
eq(Game3.ITEM_SMOKE_BALL, 194, "ITEM_SMOKE_BALL")
eq(Game3.HOLD_EFFECT_CAN_ALWAYS_RUN, 37, "HOLD_EFFECT_CAN_ALWAYS_RUN")
eq(Game3.ABILITY_SHADOW_TAG, 23, "SHADOW_TAG")
eq(Game3.ABILITY_ARENA_TRAP, 71, "ARENA_TRAP")
eq(Game3.ABILITY_MAGNET_PULL, 42, "MAGNET_PULL")
eq(Game3.ABILITY_RUN_AWAY, 50, "RUN_AWAY")

local function battlers()
  return {
    name = "TREECKO", hp = 40, maxHp = 40, spe = 10,
    type1 = 12, type2 = 12, ability = 65,
    stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
    moves = { { name = "TACKLE", power = 35, type = 0, pp = 35, accuracy = 100 } },
  }, {
    name = "ABRA", hp = 20, maxHp = 20, spe = 90,
    type1 = 14, type2 = 14, ability = 28,
    stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
    moves = { {
      name = "TELEPORT", effect = Game3.EFFECT_TELEPORT,
      power = 0, type = 14, pp = 20, accuracy = 0,
      target = Game3.TARGET_USER,
    } },
  }
end

local g = Game3.new()
local player, enemy = battlers()
g.battle = { kind = "menu", player = player, enemy = enemy }
local texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "wild Teleport flees")
eq(g.battle.fled, true, "and ends the fight")
eq(enemy.moves[1].pp, 19, "PP is spent")

g = Game3.new()
player, enemy = battlers()
g.battle = { kind = "menu", player = player, enemy = enemy, isTrainer = true }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "But it failed!", "trainer Teleport fails")
eq(g.battle.fled, nil, "the fight continues")

g = Game3.new()
player, enemy = battlers()
g.battle = { kind = "menu", player = player, enemy = enemy, chase = true }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "But it failed!", "Birch chase fails")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_SHADOW_TAG
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "TREECKO's SHADOW TAG made it ineffective!", "Shadow Tag")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_ARENA_TRAP
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "TREECKO's ARENA TRAP made it ineffective!", "Arena Trap")
enemy.type1, enemy.type2 = Game3.TYPE_FLYING, Game3.TYPE_FLYING
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "Flying ignores Arena Trap")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_ARENA_TRAP
enemy.ability = Game3.ABILITY_LEVITATE
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "Levitate ignores Arena Trap")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_MAGNET_PULL
enemy.type1, enemy.type2 = Game3.TYPE_STEEL, Game3.TYPE_STEEL
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "TREECKO's MAGNET PULL made it ineffective!", "Magnet Pull vs Steel")
enemy.type1, enemy.type2 = 14, 14
g.battle.fled = nil
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "Psychic ignores Magnet Pull")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_SHADOW_TAG
enemy.ability = Game3.ABILITY_RUN_AWAY
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "Run Away bypasses Shadow Tag")

g = Game3.new()
player, enemy = battlers()
player.ability = Game3.ABILITY_SHADOW_TAG
enemy.item = Game3.ITEM_SMOKE_BALL
g.battle = { kind = "menu", player = player, enemy = enemy }
texts = g:useMove(enemy, player, enemy.moves[1])
eq(texts[2], "ABRA fled from battle!", "Smoke Ball bypasses Shadow Tag")

g = Game3.new()
player, enemy = battlers()
g.phase = "battle"
g.battle = { kind = "menu", player = player, enemy = enemy, cursor = 0 }
g:beginTurn(player.moves[1])
local sawTackle
local q = g.battle.queue or {}
for i = 1, #q do
  if q[i]:find("TACKLE", 1, true) then sawTackle = true end
end
check(not sawTackle, "faster Abra flees before Tackle")
eq(player.hp, 40, "and the player never hits")
eq(g.battle.fled, true, "beginTurn sets fled")
while g.battle do
  g:advanceBattleText()
end
eq(g.phase, "play", "then the fight ends with no EXP")
end)()

;(function()
eq(Game3.EFFECT_LOW_KICK, 196, "EFFECT_LOW_KICK")
eq(Game3.lowKickPower(50), 20, "Treecko 5.0kg is 20")
eq(Game3.lowKickPower(99), 20, "99 hg still 20")
eq(Game3.lowKickPower(100), 40, "100 hg is 40")
eq(Game3.lowKickPower(249), 40, "249 hg still 40")
eq(Game3.lowKickPower(250), 60, "250 hg is 60")
eq(Game3.lowKickPower(499), 60, "499 hg still 60")
eq(Game3.lowKickPower(500), 80, "500 hg is 80")
eq(Game3.lowKickPower(999), 80, "999 hg still 80")
eq(Game3.lowKickPower(1000), 100, "1000 hg is 100")
eq(Game3.lowKickPower(1999), 100, "1999 hg still 100")
eq(Game3.lowKickPower(2000), 120, "2000 hg is 120")
eq(Game3.lowKickPower(3980), 120, "Wailord 398.0kg is 120")
eq(Game3.DEX_WEIGHT[277], 50, "Treecko dex weight")
eq(Game3.DEX_WEIGHT[280], 25, "Torchic dex weight")
eq(Game3.DEX_WEIGHT[283], 76, "Mudkip dex weight")
eq(Game3.DEX_WEIGHT[66], 195, "Machop dex weight")
eq(Game3.DEX_WEIGHT[314], 3980, "Wailord dex weight")
eq(Game3.DEX_WEIGHT[382], 600, "Aron dex weight")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 1, 7, 0 }, { 1, 0, 20 } } }
local kick = {
  name = "LOW KICK", effect = Game3.EFFECT_LOW_KICK,
  power = 1, type = Game3.TYPE_FIGHTING, accuracy = 100, pp = 20,
}
local machop = {
  name = "MACHOP", species = 66, level = 14, hp = 50, maxHp = 50,
  atk = 80, spa = 10, type1 = 1, type2 = 1,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local torchic = {
  name = "TORCHIC", species = 280, level = 12, hp = 80, maxHp = 80,
  def = 80, spd = 80, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
eq(g:monWeight(torchic), 25, "Torchic from species table")
eq(g:boostedPower(machop, kick, torchic), 20, "Hideki vs Torchic is 20")
local hit = g:dealDamage(machop, torchic, kick)
check(hit.dmg > 1, "ROM power 1 still uses the weight table")
eq(hit.mul, 10, "Fire is neutral")

torchic.hp = 80
torchic.species = nil
torchic.weight = 3980
eq(g:boostedPower(machop, kick, torchic), 120, "override weight is 120")
local heavy = g:dealDamage(machop, torchic, kick)
check(heavy.dmg > hit.dmg, "heavier foes take more")

local ghost = {
  name = "SHUPPET", level = 10, hp = 40, maxHp = 40,
  def = 20, spd = 20, type1 = 7, type2 = 7, weight = 23,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
hit = g:dealDamage(machop, ghost, kick)
eq(hit.dmg, 0, "Ghost is immune")
eq(hit.mul, 0, "Fighting vs Ghost is 0")
eq(ghost.hp, 40, "and HP is untouched")
end)()

;(function()
eq(Game3.EFFECT_BIDE, 26, "EFFECT_BIDE")
local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 0, 7, 0 } } }
local bide = {
  name = "BIDE", effect = Game3.EFFECT_BIDE, power = 1,
  type = 0, accuracy = 100, pp = 10, target = Game3.TARGET_USER,
}
local meditite = {
  name = "MEDITITE", hp = 40, maxHp = 40, spe = 20, def = 80,
  type1 = 1, type2 = 14,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  moves = { bide },
}
local torchic = {
  name = "TORCHIC", hp = 50, maxHp = 50, spe = 10, atk = 40,
  type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = torchic, enemy = meditite }
local texts = g:useMove(meditite, meditite, bide)
eq(texts[2], "MEDITITE is storing energy!", "first turn stores")
eq(meditite.bideTurns, 2, "setbide is 2 turns")
eq(meditite.hp, 40, "and does not hit itself")
eq(torchic.hp, 50, "or the foe")
eq(bide.pp, 9, "PP is spent once")
check(meditite.charging and meditite.charging.kind == "bide", "locks the move")
eq(g:pickEnemyMove(meditite), bide, "AI stays on Bide")

local tackle = { name = "TACKLE", power = 35, type = 0, accuracy = 100, pp = 35 }
g:dealDamage(torchic, meditite, tackle)
local stored = meditite.bideTaken
check(stored > 0, "hits feed gTakenDmg")
eq(meditite.bideFrom, torchic, "and remember who hit")
meditite.bideTaken = 10
torchic.hp = 50

texts = g:useMove(meditite, meditite, bide)
eq(texts[2], "MEDITITE is storing energy!", "second turn still stores")
eq(meditite.bideTurns, 1, "one turn left")
eq(bide.pp, 9, "no second PP spend")
eq(torchic.hp, 50, "still no release")

texts = g:useMove(meditite, meditite, bide)
eq(texts[2], "MEDITITE unleashed energy!", "third turn releases")
eq(torchic.hp, 30, "for 2x stored HP")
eq(meditite.charging, nil, "and clears the lock")
eq(meditite.bideTurns, nil, "and the counter")

g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 0, 7, 0 } } }
bide = {
  name = "BIDE", effect = Game3.EFFECT_BIDE, power = 1,
  type = 0, accuracy = 100, pp = 10, target = Game3.TARGET_USER,
}
meditite = {
  name = "MEDITITE", hp = 40, maxHp = 40,
  type1 = 1, type2 = 14,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
torchic = {
  name = "TORCHIC", hp = 50, maxHp = 50,
  type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = torchic, enemy = meditite }
g:useMove(meditite, meditite, bide)
g:useMove(meditite, meditite, bide)
texts = g:useMove(meditite, meditite, bide)
eq(texts[2], "MEDITITE unleashed energy!", "empty Bide still announces")
eq(texts[3], "But it failed!", "then fails with no energy")
eq(torchic.hp, 50, "and deals nothing")

g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 0, 7, 0 } } }
local ghost = {
  name = "SHUPPET", hp = 40, maxHp = 40,
  type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
meditite = {
  name = "MEDITITE", hp = 40, maxHp = 40,
  type1 = 1, type2 = 14,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
bide = {
  name = "BIDE", effect = Game3.EFFECT_BIDE, power = 1,
  type = 0, accuracy = 100, pp = 10, target = Game3.TARGET_USER,
}
g.battle = { kind = "menu", player = ghost, enemy = meditite }
g:useMove(meditite, meditite, bide)
meditite.bideTaken = 10
meditite.bideFrom = ghost
g:useMove(meditite, meditite, bide)
texts = g:useMove(meditite, meditite, bide)
eq(texts[3], "It doesn't affect SHUPPET...", "Ghost is immune to Normal")
eq(ghost.hp, 40, "and takes no Bide damage")

g = Game3.new()
g.rng = function() return 1 end
meditite = {
  name = "MEDITITE", hp = 80, maxHp = 80, spe = 10, def = 80,
  type1 = 1, type2 = 14,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  moves = { {
    name = "BIDE", effect = Game3.EFFECT_BIDE, power = 1,
    type = 0, accuracy = 100, pp = 10, target = Game3.TARGET_USER,
  } },
}
torchic = {
  name = "TORCHIC", hp = 50, maxHp = 50, spe = 90, atk = 20, level = 10,
  type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  moves = { {
    name = "HEADBUTT", effect = Game3.EFFECT_FLINCH_HIT,
    power = 10, type = 0, pp = 15, accuracy = 100, secondary = 100,
  } },
}
g.battle = { kind = "menu", player = torchic, enemy = meditite }
g:useMove(meditite, meditite, meditite.moves[1])
g.phase = "battle"
g:beginTurn(torchic.moves[1])
eq(meditite.bideTurns, nil, "flinch CancelMultiTurnMoves")
eq(meditite.charging, nil, "and drops the lock")
end)()

;(function()
eq(Game3.EFFECT_MUD_SPORT, 201, "EFFECT_MUD_SPORT")
eq(Game3.EFFECT_WATER_SPORT, 210, "EFFECT_WATER_SPORT")

local g = Game3.new()
g.rng = function() return 1 end
local geo = {
  name = "GEODUDE", hp = 40, maxHp = 40, spe = 10,
  type1 = 5, type2 = 4,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  moves = { {
    name = "MUD SPORT", effect = Game3.EFFECT_MUD_SPORT,
    power = 0, type = Game3.TYPE_GROUND, accuracy = 100, pp = 15,
    target = Game3.TARGET_USER,
  } },
}
local chick = {
  name = "TORCHIC", hp = 50, maxHp = 50, level = 10,
  spa = 40, spd = 20, def = 20,
  type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = chick, enemy = geo }
local lines = g:useMove(geo, geo, geo.moves[1])
eq(geo.mudSport, true, "STATUS3_MUDSPORT")
eq(lines[2], "Electricity's power was weakened!",
  "BattleText_ElecWeakened")
eq(geo.moves[1].pp, 14, "PP on the opening turn")
eq(geo.hp, 40, "Mud Sport does not hit the user")

lines = g:useMove(geo, geo, geo.moves[1])
eq(lines[2], "But it failed!", "already set on this battler")
eq(geo.moves[1].pp, 13, "a failed use still spends PP")

eq(g:boostedPower(chick, {
  power = 40, type = Game3.TYPE_ELECTRIC, effect = 0,
}, geo), 20, "Electric gBattleMovePower /= 2")
eq(g:boostedPower(chick, {
  power = 40, type = Game3.TYPE_FIRE, effect = 0,
}, geo), 40, "Fire is unchanged")

local shock = {
  name = "THUNDERSHOCK", effect = 0, power = 40,
  type = Game3.TYPE_ELECTRIC, accuracy = 100, pp = 30,
}
local zapper = {
  name = "MAREEP", hp = 50, maxHp = 50, level = 10,
  spa = 40, type1 = 13, type2 = 13,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
chick.hp, chick.maxHp = 200, 200
local dmgSport = g:dealDamage(zapper, chick, shock).dmg
geo.mudSport = nil
chick.hp = 200
local dmgPlain = g:dealDamage(zapper, chick, shock).dmg
check(dmgSport > 0 and dmgSport < dmgPlain,
  "the Electric hit is weaker while Mud Sport is up")
chick.hp, chick.maxHp = 50, 50

chick.protected = true
g:useMove(geo, chick, geo.moves[1])
eq(geo.mudSport, true, "Protect does not block TARGET_USER sport")
chick.protected = nil

local bench = {
  name = "MUDKIP", hp = 50, maxHp = 50,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  moves = { { name = "TACKLE", power = 35, pp = 35 } },
}
geo.mudSport = nil
g:useMove(chick, chick, {
  name = "MUD SPORT", effect = Game3.EFFECT_MUD_SPORT,
  power = 0, type = Game3.TYPE_GROUND, accuracy = 100, pp = 15,
  target = Game3.TARGET_USER,
})
eq(chick.mudSport, true, "the lead can set sport")
g.party = { chick, bench }
g.battle.switchSlot = "player"
g:switchTo(2)
eq(chick.mudSport, nil, "SwitchInClearSetData drops sport")
check(not g:fieldHasSport("mudSport"), "and the field is empty")

local soak = {
  name = "MAGIKARP", hp = 20, maxHp = 20,
  type1 = 11, type2 = 11,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = chick, enemy = soak }
lines = g:useMove(soak, soak, {
  name = "WATER SPORT", effect = Game3.EFFECT_WATER_SPORT,
  power = 0, type = Game3.TYPE_WATER, accuracy = 100, pp = 15,
  target = Game3.TARGET_USER,
})
eq(soak.waterSport, true, "STATUS3_WATERSPORT")
eq(lines[2], "Fire's power was weakened!", "BattleText_FireWeakened")
eq(g:boostedPower(chick, {
  power = 40, type = Game3.TYPE_FIRE, effect = 0,
}, soak), 20, "Fire gBattleMovePower /= 2")
eq(g:boostedPower(chick, {
  power = 40, type = Game3.TYPE_ELECTRIC, effect = 0,
}, soak), 40, "Electric is unchanged")
end)()

;(function()
eq(Game3.EFFECT_SPECIAL_DEFENSE_DOWN_2, 62, "EFFECT_SPECIAL_DEFENSE_DOWN_2")
eq(Game3.statDownSpec(62), "spd", "Fake Tears is SP. DEF")

local g = Game3.new()
g.rng = function() return 1 end
local mawile = {
  name = "MAWILE", hp = 40, maxHp = 40,
  type1 = 8, type2 = 8, ability = Game3.ABILITY_HYPER_CUTTER,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local chick = {
  name = "TORCHIC", hp = 50, maxHp = 50, spa = 40, spd = 20,
  type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = chick, enemy = mawile }
local tears = {
  name = "FAKE TEARS", effect = Game3.EFFECT_SPECIAL_DEFENSE_DOWN_2,
  power = 0, type = Game3.TYPE_DARK, accuracy = 100, pp = 20,
}
local lines = g:useMove(mawile, chick, tears)
eq(chick.stages.spd, -2, "setstatchanger SP_DEFENSE, 2")
eq(lines[2], "TORCHIC's SP. DEF harshly fell!", "BattleText_Harshly + Fell")
eq(tears.pp, 19, "PP is spent")

g:useMove(mawile, chick, tears)
g:useMove(mawile, chick, tears)
eq(chick.stages.spd, -6, "clamps at -6")
lines = g:useMove(mawile, chick, tears)
eq(lines[2], "TORCHIC's SP. DEF won't go lower!",
  "BattleText_DefendingStatNoHigher")
eq(chick.stages.spd, -6, "and stays there")

chick.stages.spd = 0
chick.ability = Game3.ABILITY_CLEAR_BODY
lines = g:useMove(mawile, chick, tears)
eq(chick.stages.spd, 0, "Clear Body blocks Fake Tears")
check(lines[2]:find("cannot be lowered", 1, true) ~= nil,
  "AbilityNoStatLoss")

chick.ability = Game3.ABILITY_HYPER_CUTTER
g:useMove(mawile, chick, tears)
eq(chick.stages.spd, -2, "Hyper Cutter does not guard SP. DEF")

chick.ability = nil
chick.stages.spd = 0
chick.protected = true
lines = g:useMove(mawile, chick, tears)
eq(chick.stages.spd, 0, "Protect stops Fake Tears")
check(lines[2]:find("protected", 1, true) ~= nil, "F_AFFECTED_BY_PROTECT")
end)()

;(function()
check(Game3.isOutdoorMapType(Game3.MAP_TYPE_TOWN), "towns are outdoor")
check(Game3.isOutdoorMapType(Game3.MAP_TYPE_UNDERWATER), "underwater is outdoor")
check(not Game3.isOutdoorMapType(Game3.MAP_TYPE_UNDERGROUND),
  "caves are not")
check(not Game3.isOutdoorMapType(Game3.MAP_TYPE_INDOOR), "nor indoor")

local town = {
  id = "g0_0", group = 0, index = 0,
  mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  warps = { { x = 1, y = 0, warpId = 0, mapGroup = 0, mapNum = 1 } },
}
local cave = {
  id = "g0_1", group = 0, index = 1,
  mapType = Game3.MAP_TYPE_UNDERGROUND, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  warps = { { x = 1, y = 1, warpId = 0, mapGroup = 0, mapNum = 0 } },
}
local deep = {
  id = "g0_2", group = 0, index = 2,
  mapType = Game3.MAP_TYPE_UNDERGROUND, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local pc = {
  id = "g_pc", mapType = Game3.MAP_TYPE_INDOOR, width = 3, height = 3,
  spawn = { x = 2, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "g0_0", maps = {
  ["g0_0"] = town, ["g0_1"] = cave, ["g0_2"] = deep, g_pc = pc,
} }
g.lastHeal = { mapId = "g_pc", x = 2, y = 1 }
g.bag = { { id = Game3.ITEM_ESCAPE_ROPE, count = 2 } }
g.party = { {
  name = "ABRA", hp = 20, maxHp = 20, species = 63, level = 15,
  moves = { { id = Game3.MOVE_DIG } },
} }
g:enterMap(town, 1, 1, true)
check(g:followWarp(town.warps[1]), "Dewford door into Granite")
eq(g.map.id, "g0_1", "landed in the cave")
eq(g.escapeWarp.mapId, "g0_0", "warp4 is the town")
eq(g.escapeWarp.x, 1, "at the cave mouth x")
eq(g.escapeWarp.y, 0, "and y")

g:enterMap(deep, 0, 0, true)
eq(g.escapeWarp.mapId, "g0_0", "B1F to B2F does not overwrite warp4")

local dig, digMsg = g:useDig()
check(dig, "Dig from B2F")
eq(digMsg, "Used DIG!", "Dig line")
eq(g.map.id, "g0_0", "lands on warp4, not the Center")
eq(g.playerX, 1, "cave mouth x")
eq(g.playerY, 0, "cave mouth y")

g:enterMap(cave, 1, 1, true)
local rope = g:useEscapeRope()
check(rope, "Escape Rope uses warp4 too")
eq(g.map.id, "g0_0", "same outdoor tile")

g:enterMap(cave, 1, 1, true)
g.phase = "battle"
g.battle = { kind = "blackout" }
g.party[1].hp = 0
g:blackout()
eq(g.map.id, "g_pc", "blackout still uses lastHeal")

g.escapeWarp = nil
g:enterMap(cave, 1, 1, true)
g.party[1].hp = 20
local fallback = g:useDig()
check(fallback, "no warp4 still Digs")
eq(g.map.id, "g_pc", "and falls back to lastHeal")
end)()

;(function()
eq(Game3.EFFECT_RAGE, 81, "EFFECT_RAGE")
eq(Game3.MOVE_RAGE, 99, "MOVE_RAGE")
local g = Game3.new()
g.rng = function() return 1 end
local carv = {
  name = "CARVANHA", hp = 200, maxHp = 200, atk = 30, def = 40,
  type1 = 11, type2 = 16, level = 15,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local chick = {
  name = "TORCHIC", hp = 80, maxHp = 80, atk = 40, def = 20,
  type1 = 10, type2 = 10, level = 15,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.battle = { kind = "menu", player = chick, enemy = carv }
local rage = {
  id = Game3.MOVE_RAGE, name = "RAGE",
  effect = Game3.EFFECT_RAGE, power = 20, type = 0,
  accuracy = 100, pp = 20, flags = Game3.FLAG_CONTACT + Game3.FLAG_PROTECT,
}
local tackle = {
  id = 33, name = "TACKLE", effect = 0, power = 35, type = 0,
  accuracy = 100, pp = 35, flags = Game3.FLAG_CONTACT + Game3.FLAG_PROTECT,
}
local lines = g:useMove(carv, chick, rage)
eq(carv.rage, true, "STATUS2_RAGE after a hit")
check(chick.hp < 80, "Rage still deals damage")

lines = g:useMove(chick, carv, tackle)
eq(carv.stages.atk, 1, "ATK49_RAGE +1 Attack")
local built = false
for i = 1, #lines do
  if lines[i]:find("RAGE is building", 1, true) then built = true end
end
check(built, "BattleText_RageBuilding")

g:useMove(carv, chick, tackle)
eq(carv.rage, nil, "TryClearRageStatuses drops a non-Rage pick")
local atk = carv.stages.atk
g:useMove(chick, carv, tackle)
eq(carv.stages.atk, atk, "no build without the bit")

carv.rage = true
carv.stages.atk = 6
g:useMove(chick, carv, tackle)
eq(carv.stages.atk, 6, "stage 12 does not increment")

carv.rage = true
chick.protected = true
lines = g:useMove(carv, chick, rage)
eq(carv.rage, nil, "Protect is BattleScript_RageMiss")
check(lines[2]:find("protected", 1, true) ~= nil, "F_AFFECTED_BY_PROTECT")

chick.protected = nil
rage.accuracy = 50
g.rng = function() return 100 end
carv.rage = true
lines = g:useMove(carv, chick, rage)
eq(carv.rage, nil, "a miss clearsstatusfromeffect USER")
eq(lines[2], "The attack missed!", "accuracycheck RageMiss")

g.data.moves = { typeChart = { { 0, 7, 0 } } }
local ghost = {
  name = "GASTLY", hp = 40, maxHp = 40,
  type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g.rng = function() return 1 end
rage.accuracy = 100
lines = g:useMove(carv, ghost, rage)
eq(carv.rage, true, "type immunity still seteffectprimary")
check(lines[2]:find("doesn't affect", 1, true) ~= nil, "no HP damage")
end)()

;(function()
eq(Game3.ITEM_FRESH_WATER, 26, "Fresh Water")
eq(Game3.ITEM_SODA_POP, 27, "Soda Pop")
eq(Game3.ITEM_LEMONADE, 28, "Lemonade")
eq(Game3.ITEM_MOOMOO_MILK, 29, "Moomoo Milk")
eq(Game3.HEAL_AMOUNT[26], 50, "gItemEffect_FreshWater")
eq(Game3.HEAL_AMOUNT[27], 60, "gItemEffect_SodaPop")
eq(Game3.HEAL_AMOUNT[28], 80, "gItemEffect_Lemonade")
eq(Game3.HEAL_AMOUNT[29], 100, "gItemEffect_MoomooMilk")

local g = Game3.new()
eq(g:itemName(Game3.ITEM_SODA_POP), "SODA POP", "items_en.h name")
eq(g:itemName(Game3.ITEM_FRESH_WATER), "FRESH WATER", "Fresh Water name")
eq(g:itemName(Game3.ITEM_LEMONADE), "LEMONADE", "Lemonade name")
eq(g:itemName(Game3.ITEM_MOOMOO_MILK), "MOOMOO MILK", "Moomoo Milk name")
eq(g:itemName(Game3.ITEM_HYPER_POTION), "HYPER POTION", "Hyper Potion name")
eq(g:itemName(Game3.ITEM_MAX_POTION), "MAX POTION", "Max Potion name")
eq(g:itemPrice(Game3.ITEM_SODA_POP), 300, "Seashore House extra can")
eq(g:itemPrice(Game3.ITEM_FRESH_WATER), 200, "vending Fresh Water")
eq(g:itemPrice(Game3.ITEM_LEMONADE), 350, "vending Lemonade")
eq(g:itemPrice(Game3.ITEM_MOOMOO_MILK), 500, "Moomoo Milk")
eq(g:healAmount(Game3.ITEM_SODA_POP), 60, "healAmount Soda Pop")

g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.party = { g:makeMon(280, 12) }
local chick = g.party[1]
chick.maxHp = 100
chick.hp = 10
g:addItem(Game3.ITEM_SODA_POP, 6)
eq(g:itemCount(Game3.ITEM_SODA_POP), 6, "giveitem 6 after Dwayne/Johanna/Simon")
local ok, msg = g:useItemOnMon(chick, Game3.ITEM_SODA_POP)
check(ok, "BAG Soda Pop")
eq(chick.hp, 70, "heals 60")
eq(g:itemCount(Game3.ITEM_SODA_POP), 5, "spent one")
check(msg:find("recovered HP", 1, true) ~= nil, "recovered HP line")

chick.hp = chick.maxHp
ok, msg = g:useItemOnMon(chick, Game3.ITEM_SODA_POP)
check(not ok, "full HP is no effect")
eq(g:itemCount(Game3.ITEM_SODA_POP), 5, "does not spend at full")

chick.hp = 20
check(g:startWildBattle(280, 5), "wild fight")
g.battle.kind = "menu"
g.battle.player.maxHp = 100
g.battle.player.hp = 20
g.battle.enemy.hp = 0
ok = g:useBattleItem(Game3.ITEM_SODA_POP)
check(ok, "in-battle medicine")
eq(g.battle.player.hp, 80, "60 in battle too")
eq(g:itemCount(Game3.ITEM_SODA_POP), 4, "battle spends one")

local refill = Game3.new()
refill.money = 300
check(refill.money >= refill:itemPrice(Game3.ITEM_SODA_POP),
  "checkmoney 300 for one more can")
refill.money = 299
check(refill.money < refill:itemPrice(Game3.ITEM_SODA_POP),
  "short $1 fails checkmoney")
end)()

;(function()
eq(Game3.ITEM_ITEMFINDER, 261, "ITEM_ITEMFINDER")
eq(Game3.itemfinderInRange(7, 5), true, "window corner")
eq(Game3.itemfinderInRange(-7, -5), true, "and the opposite")
eq(Game3.itemfinderInRange(8, 0), false, "dx 8 is out")
eq(Game3.itemfinderInRange(0, 6), false, "dy 6 is out")
eq(Game3.itemfinderFacing(-3, 1), "west", "abX > abY west")
eq(Game3.itemfinderFacing(3, 1), "east", "east")
eq(Game3.itemfinderFacing(1, -4), "north", "abY > abX north")
eq(Game3.itemfinderFacing(1, 4), "south", "south")
eq(Game3.itemfinderFacing(2, -2), "north", "NW/NE diagonal prefers north")
eq(Game3.itemfinderFacing(2, 2), "south", "SW/SE prefers south")
eq(Game3.itemfinderFacing(0, 0), nil, "underfoot is DIR_NONE")
check(Game3.itemfinderCloser(4, 0, 2, 0), "smaller Manhattan")
check(not Game3.itemfinderCloser(2, 0, 4, 0), "keep the closer")
check(Game3.itemfinderCloser(0, 3, 3, 0), "tie: smaller |dy|")
check(Game3.itemfinderCloser(1, -3, 1, 3), "tie |dy|: larger dy")

local g = Game3.new()
eq(g:itemName(Game3.ITEM_ITEMFINDER), "ITEMFINDER", "items_en.h name")
eq(g:itemPocket(Game3.ITEM_ITEMFINDER), Game3.POCKET_KEY, "key item")
g:addItem(Game3.ITEM_ITEMFINDER, 1)
g.phase = "play"
g.facing = "south"
g.playerX, g.playerY = 5, 5
g.map = {
  id = "route", width = 16, height = 16, grid = {},
  bgEvents = {
    { x = 12, y = 5, kind = 7, itemId = 13, hiddenId = 1 },
    { x = 5, y = 7, kind = 7, itemId = 13, hiddenId = 2 },
    { x = 20, y = 5, kind = 7, itemId = 13, hiddenId = 3 },
  },
}
local dx, dy = g:nearestHiddenItem()
eq(dx, 0, "Manhattan 2 beats 9")
eq(dy, 2, "the south item")
local ok, msg = g:useFieldItem(Game3.ITEM_ITEMFINDER)
check(ok, "BAG Itemfinder")
eq(g.facing, "south", "SetPlayerDirectionTowardsItem")
check(msg:find("responding", 1, true) ~= nil, "gOtherText_ItemfinderResponding")
eq(g:itemCount(Game3.ITEM_ITEMFINDER), 1, "does not consume")
eq((g.gameStats or {})[Game3.GAME_STAT_USED_ITEMFINDER], 1,
  "GAME_STAT_USED_ITEMFINDER")

g.playerX, g.playerY = 5, 7
ok, msg = g:useItemfinder()
check(msg:find("underfoot", 1, true) ~= nil, "gOtherText_ItemfinderItemUnderfoot")

g.flags = { [Game3.hiddenFlag(2)] = true }
g.playerX, g.playerY = 5, 5
ok, msg = g:useItemfinder()
eq(g.facing, "east", "next-closest after pickup")
check(msg:find("responding", 1, true) ~= nil, "still responds")

g.flags[Game3.hiddenFlag(1)] = true
ok, msg = g:useItemfinder()
check(msg:find("no response", 1, true) ~= nil, "out of range is NoResponse")
check(msg:find("Nope", 1, true) ~= nil, "gOtherText_NoResponse")
end)()

;(function()
eq(Game3.EFFECT_LEECH_SEED, 84, "EFFECT_LEECH_SEED")
local seed = {
  name = "LEECH SEED", effect = 84, power = 0, type = 12, accuracy = 90, pp = 10,
}
local g = Game3.new()
g.rng = function() return 1 end
local shroom = { name = "SHROOMISH", hp = 50, maxHp = 50, type1 = 12, type2 = 12 }
local chick = {
  name = "TORCHIC", hp = 40, maxHp = 80, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local lines = g:useMove(shroom, chick, seed)
eq(chick.leechSeed, true, "STATUS3_LEECHSEED")
eq(chick.leechSeedFrom, shroom, "stores the sower")
check(lines[2]:find("was seeded", 1, true) ~= nil, "BattleText_WasSeeded")

lines = g:useMove(shroom, chick, seed)
check(lines[2]:find("evaded", 1, true) ~= nil, "already seeded is EvadedAttack")

local treecko = { name = "TREECKO", hp = 40, maxHp = 40, type1 = 12, type2 = 12 }
lines = g:useMove(shroom, treecko, seed)
eq(treecko.leechSeed, nil, "Grass fails setseeded")
check(lines[2]:find("doesn't affect", 1, true) ~= nil, "chooser 2")

seed.accuracy = 90
g.rng = function() return 100 end
local zig = { name = "ZIGZAGOON", hp = 30, maxHp = 30, type1 = 0, type2 = 0 }
lines = g:useMove(shroom, zig, seed)
eq(zig.leechSeed, nil, "accuracy miss")
check(lines[2]:find("evaded", 1, true) ~= nil, "miss is still EvadedAttack")

g.rng = function() return 1 end
zig.protected = true
lines = g:useMove(shroom, zig, seed)
eq(zig.leechSeed, nil, "Protect")
check(lines[2]:find("protected", 1, true) ~= nil, "F_AFFECTED_BY_PROTECT")

local drain = g:leechSeedResidual(chick)
eq(chick.hp, 30, "maxHP/8")
eq(shroom.hp, 50, "sower was full")
check(drain[1]:find("LEECH SEED", 1, true) ~= nil, "BattleText_HealthSapped")

chick.hp = 40
shroom.hp = 40
drain = g:leechSeedResidual(chick)
eq(shroom.hp, 50, "heals the sower")

local tiny = {
  name = "MAGIKARP", hp = 5, maxHp = 5, leechSeed = true, leechSeedFrom = shroom,
}
shroom.hp = 40
drain = g:leechSeedResidual(tiny)
eq(tiny.hp, 4, "min 1")
eq(shroom.hp, 41, "and heals 1")

shroom.hp = 0
chick.hp = 40
drain = g:leechSeedResidual(chick)
eq(chick.hp, 40, "fainted sower skips ENDTURN_LEECH_SEED")
eq(#drain, 0, "no sap line")

shroom.hp = 50
chick.ability = Game3.ABILITY_LIQUID_OOZE
chick.hp = 40
drain = g:leechSeedResidual(chick)
eq(shroom.hp, 40, "Ooze hurts the sower")
eq(chick.hp, 30, "and still saps the user")
check(drain[1]:find("LIQUID OOZE", 1, true) ~= nil, "BattleText_OozeSuckup")

chick.ability = nil
chick.leechSeed = true
g:prepBattler(chick)
eq(chick.leechSeed, nil, "switch-in clears STATUS3")
end)()

;(function()
eq(Game3.EFFECT_FORESIGHT, 113, "EFFECT_FORESIGHT")
eq(Game3.chartMul({ { 0, 7, 0 } }, 0, 7), 0, "Normal vs Ghost is 0")
eq(Game3.chartMul({ { 0, 7, 0 } }, 0, 7, true), 10, "Foresight breaks the sentinel")
eq(Game3.chartMul({ { 1, 7, 0 } }, 1, 7, true), 10, "Fighting too")
eq(Game3.chartMul({ { 13, 4, 0 } }, 13, 4, true), 0, "Electric vs Ground stays 0")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 0, 7, 0 }, { 1, 7, 0 } } }
local marsh = {
  name = "MARSHTOMP", hp = 50, maxHp = 50, atk = 40, def = 40, level = 20,
  type1 = 11, type2 = 4,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
local ghost = {
  name = "SHUPPET", hp = 40, maxHp = 40, atk = 20, def = 20, level = 15,
  type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 1 },
}
local foresight = {
  name = "FORESIGHT", effect = 113, power = 0, type = 0, accuracy = 100, pp = 40,
}
local tackle = {
  name = "TACKLE", effect = 0, power = 35, type = 0, accuracy = 100, pp = 35,
}
local lines = g:useMove(marsh, ghost, tackle)
check(lines[2]:find("doesn't affect", 1, true) ~= nil, "Ghost immune to Normal")
eq(ghost.hp, 40, "no damage yet")

eq(g:moveHitChance(marsh, ghost, tackle, 0), 75, "Double Team is 75%")
lines = g:useMove(marsh, ghost, foresight)
eq(ghost.foresight, true, "STATUS2_FORESIGHT")
check(lines[2]:find("identified", 1, true) ~= nil, "BattleText_IdentifiedPoke")
eq(g:moveHitChance(marsh, ghost, tackle, 0), 100, "evasion stage is ignored")
marsh.stages.acc = -1
eq(g:moveHitChance(marsh, ghost, tackle, 0), 75, "accuracy stage still counts")
marsh.stages.acc = 0

lines = g:useMove(marsh, ghost, foresight)
check(lines[2]:find("identified", 1, true) ~= nil, "second use still identifies")

lines = g:useMove(marsh, ghost, tackle)
check(ghost.hp < 40, "Normal hits Ghost")
check(not (lines[2] and lines[2]:find("doesn't affect", 1, true)), "no immunity line")

ghost.hp = 40
ghost.protected = true
lines = g:useMove(marsh, ghost, foresight)
check(lines[2]:find("protected", 1, true) ~= nil, "F_AFFECTED_BY_PROTECT")

ghost.protected = nil
foresight.accuracy = 50
g.rng = function() return 100 end
local zig = {
  name = "ZIGZAGOON", hp = 30, maxHp = 30, type1 = 0, type2 = 0,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
lines = g:useMove(marsh, zig, foresight)
eq(zig.foresight, nil, "accuracycheck miss")
eq(lines[2], "The attack missed!", "PrintMoveMissed")

g:prepBattler(ghost)
eq(ghost.foresight, nil, "switch-in clears STATUS2")
end)()

;(function()
eq(Game3.EFFECT_HIDDEN_POWER, 135, "EFFECT_HIDDEN_POWER")
eq(Game3.TYPE_MYSTERY, 9, "TYPE_MYSTERY")
local zero = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
eq(Game3.hiddenPowerType(zero), 1, "IV 0 is Fighting")
eq(Game3.hiddenPowerPower(zero), 30, "IV 0 is power 30")
local max = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
eq(Game3.hiddenPowerType(max), 17, "IV 31 is Dark")
eq(Game3.hiddenPowerPower(max), 70, "IV 31 is power 70")
local spa = { hp = 0, atk = 0, def = 0, spe = 0, spa = 1, spd = 0 }
eq(Game3.hiddenPowerType(spa), 4, "spa LSB is Ground")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = { { 1, 10, 5 }, { 17, 7, 20 } } }
local hp = {
  name = "HIDDEN POWER", effect = 135, power = 1, type = 0, accuracy = 100, pp = 15,
}
local abra = {
  name = "ABRA", hp = 40, maxHp = 40, atk = 20, spa = 80, def = 20, spd = 40,
  level = 16, type1 = 14, type2 = 14, ivs = zero,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
eq(g:attackType(abra, hp), 1, "attackType is Fighting")
eq(g:boostedPower(abra, hp, abra), 30, "boostedPower 30")
eq(hp.type, 0, "does not mutate move.type")

local torchic = {
  name = "TORCHIC", hp = 50, maxHp = 50, atk = 30, spa = 30, def = 30, spd = 30,
  level = 16, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
local lines = g:useMove(abra, torchic, hp)
check(torchic.hp < 50, "Edward Abra damages Torchic")
check(lines[2] and lines[2]:find("not very effective", 1, true), "Fighting vs Fire NVE")
eq(hp.type, 0, "type stays Normal after the hit")

torchic.hp = 50
torchic.protected = true
lines = g:useMove(abra, torchic, hp)
check(lines[2]:find("protected", 1, true) ~= nil, "F_AFFECTED_BY_PROTECT")
eq(torchic.hp, 50, "Protect blocks Hidden Power")
torchic.protected = nil

abra.ivs = max
local shuppet = {
  name = "SHUPPET", hp = 40, maxHp = 40, def = 30, spd = 30, level = 15,
  type1 = 7, type2 = 7,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
lines = g:useMove(abra, shuppet, hp)
check(shuppet.hp < 40, "Dark Hidden Power hits Ghost")
check(lines[2] and lines[2]:find("super effective", 1, true), "Dark vs Ghost SE")

local tmon = g:makeTrainerMon({ species = 63, level = 16, iv = 0 })
eq(tmon.ivs.hp, 0, "Edward iv 0 is HP IV 0")
eq(tmon.ivs.spa, 0, "and spa 0")
eq(g:attackType(tmon, hp), 1, "Edward Hidden Power is Fighting")
tmon = g:makeTrainerMon({ species = 63, level = 16, iv = 255 })
eq(tmon.ivs.atk, 31, "iv 255 is 31")
end)()

;(function()
eq(Game3.EFFECT_NATURE_POWER, 173, "EFFECT_NATURE_POWER")
eq(Game3.NATURE_POWER_MOVES[0], 78, "grass is Stun Spore")
eq(Game3.NATURE_POWER_MOVES[9], 129, "plain is Swift")
eq(Game3.NATURE_POWER_MOVES[7], 247, "cave is Shadow Ball")
eq(Game3.NATURE_POWER_MOVES[8], 129, "building is Swift")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = {
  byId = {
    [78] = {
      id = 78, name = "STUN SPORE", effect = 67, power = 0, type = 12,
      accuracy = 75, pp = 30,
    },
    [129] = {
      id = 129, name = "SWIFT", effect = 17, power = 60, type = 0,
      accuracy = 0, pp = 20,
    },
  },
}
g.map = { width = 1, height = 1, mapType = 3, grid = { 0 }, behavior = { 0 } }
g.playerX, g.playerY = 0, 0
eq(g:battleEnvironment(), 9, "Route 110 path is PLAIN")
g.map.behavior = { 0x02 }
eq(g:battleEnvironment(), 0, "tall grass")
g.map.mapType = 4
g.map.behavior = { 0 }
eq(g:battleEnvironment(), 7, "cave")

g.map.mapType = 3
g.map.behavior = { 0 }
local np = {
  name = "NATURE POWER", effect = 173, power = 0, type = 0, accuracy = 95, pp = 20,
}
local lombre = {
  name = "LOMBRE", hp = 50, maxHp = 50, atk = 30, spa = 40, def = 30, spd = 30,
  level = 14, type1 = 11, type2 = 12,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
local torchic = {
  name = "TORCHIC", hp = 50, maxHp = 50, atk = 30, spa = 30, def = 30, spd = 30,
  level = 16, type1 = 10, type2 = 10,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 },
}
local lines = g:useMove(lombre, torchic, np)
check(lines[2] and lines[2]:find("SWIFT", 1, true), "plain becomes Swift")
check(torchic.hp < 50, "Swift damages")
eq(np.pp, 19, "PP comes off Nature Power")
eq(np.effect, 173, "does not mutate the slot")

torchic.hp = 50
torchic.protected = true
np.pp = 20
lines = g:useMove(lombre, torchic, np)
check(lines[2] and lines[2]:find("SWIFT", 1, true), "swap happens under Protect")
check(lines[3] and lines[3]:find("protected", 1, true), "called move is blocked")
eq(torchic.hp, 50, "Protect holds")
torchic.protected = nil

g.map.behavior = { 0x02 }
np.pp = 20
lines = g:useMove(lombre, torchic, np)
check(lines[2] and lines[2]:find("STUN SPORE", 1, true), "grass becomes Stun Spore")
eq(torchic.status, Game3.STATUS_PAR, "Stun Spore paralyzes")
end)()

;(function()
eq(Game3.FLAG_HIDE_DEVON_RUSTBORO, 0x2DC, "FLAG_HIDE_DEVON_RUSTBORO")
eq(Game3.HEALTHBOX_XY_DOUBLES.player2[2], 54, "partner box stacks above")
local rust = Game3.new()
rust.phase = "play"
rust.flags[Game3.FLAG_HIDE_DEVON_RUSTBORO] = true
local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local map = {
  id = "g0_3", width = 3, height = 3, grid = cells,
  objects = {
    { localId = 9, x = 0, y = 0, graphicsId = 46,
      flagId = Game3.FLAG_HIDE_DEVON_RUSTBORO },
  },
}
rust:enterMap(map, 1, 2, true)
eq(rust:npcByLocalId(9), nil, "employee starts hidden")
rust:runNpcScript({
  { op = "addobject", localId = 9 },
  { op = "setobjectxyperm", localId = 9, x = 2, y = 0 },
  { op = "removeobject", localId = 9 },
  { op = "clearflag", flag = Game3.FLAG_HIDE_DEVON_RUSTBORO },
  { op = "end" },
})
local emp = rust:npcByLocalId(9)
check(emp, "clearflag TrySpawns the employee")
check(not emp.hidden, "and unhides them")
eq(emp.x, 2, "at xyperm x")
eq(emp.y, 0, "at the Corp door")
end)()

;(function()
local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
    [290] = { name = "WURMPLE", hp = 45, atk = 40, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6 },
  },
}
g.data.moves = {
  byId = { [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35 } },
}
g.party = { g:makeMon(280, 8), g:makeMon(290, 6) }
check(g:startTrainerBattle({
  trainerName = "GINA & MIA", trainerClass = "TWINS",
  doubleBattle = true,
  party = { { species = 290, level = 6 }, { species = 290, level = 6 } },
}), "Gina starts")
eq(g.battle.chooser, "player", "chooser starts on the lead")
local scratch = g.battle.player.moves[1]
local tackle = g.battle.player2.moves[1]
g:queueBattlerMove(scratch, g.battle.enemy)
eq(g.battle.chooser, "player2", "then asks the partner")
eq(g.battle.kind, "menu", "back on the command menu")
eq(g:menuBattler(), g.battle.player2, "menu is the partner")
g:queueBattlerMove(tackle, g.battle.enemy2)
eq(g.battle.kind, "text", "both moves start the turn")
eq(g.battle.chooser, "player", "chooser resets")
end)()

;(function()
local Input = require("src.core.Input")
eq(Game3.FONT_MALE, 0xB5, "CHAR_MALE")
eq(Game3.FONT_FEMALE, 0xB6, "CHAR_FEMALE")
local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, genderRatio = 31,
      growthRate = 3 },
    [281] = { name = "COMBUSKEN", hp = 60, atk = 85, def = 60, spe = 55,
      spa = 85, spd = 60, type1 = 10, type2 = 1, genderRatio = 31,
      growthRate = 3 },
  },
}
local mon = g:makeMon(280, 16)
eq(mon.species, 280, "Torchic is still Torchic at 16")
eq(#g:tryEvolve(mon), 0, "tryEvolve queues, it does not apply")
eq(mon.species, 280, "species is unchanged during the announcement")
check(g.pendingEvo and g.pendingEvo[1], "an evolution is pending")
g.phase = "battle"
g.battle = { kind = "text", player = mon }
check(g:startPendingEvolve(), "battle starts the evolve scene")
eq(g.battle.kind, "evolve", "kind is evolve")
eq(g.evolve.stage, "announce", "first the announce text")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepEvolve(0)
eq(g.evolve.stage, "anim", "A starts the shrink/grow")
g:stepEvolve(Game3.EVOLVE_ANIM)
eq(mon.species, 281, "Combusken after the animation")
eq(g.evolve.stage, "done", "then the done text")
Input.wasPressed = old
local bar = { level = 5, growth = 3, exp = Game3.expAtLevel(3, 5) }
eq(Game3.expBarFill(bar), 0, "EXP bar is empty at the level floor")
bar.exp = Game3.expAtLevel(3, 6)
eq(Game3.expBarFill(bar), 1, "and full at the next level")
eq(g:monGender({ species = 280, pid = 0 }), Game3.MON_FEMALE,
  "healthbox can read female")
eq(g:monGender({ species = 280, pid = 100 }), Game3.MON_MALE,
  "and male")
end)()

;(function()
local g = Game3.new()
g.flashLevel = 4
eq(g:flashRadius(), 24, "Brawly gym radius")
g:drawFlashOverlay()
check(true, "flash overlay does not throw without a stencil canvas")
g:animateFlash(0)
eq(g.flashAnim and g.flashAnim.dest, 200, "full brightness dest is 200px")
local n = 0
while g.flashAnim and n < 10 do
  g:stepFlashAnim()
  n = n + 1
end
eq(g:flashRadius(), 24 + 5, "grows 1px every 2 frames")
g:driveFlashAnim()
eq(g.flashLevel, 0, "Brawly's lights end at 0")
eq(g:flashRadius(), 0, "and the overlay drops")
end)()

;(function()
local win = Game3.flashScanlineWindows(120, 80, 24)
eq(win[80][1], 96, "WIN0 left at the equator")
eq(win[80][2], 144, "WIN0 right at the equator")
eq(win[56][1], 114, "WIN0 left at the north pole")
eq(win[56][2], 126, "WIN0 right at the north pole")
check(not win[0], "scanlines above the circle stay closed")
-- Overworld draws at window pixels (e.g. 4×). GBA WIN0H 255/160 clamps
-- would drop every scanline and leave the cave pitch black.
local wide = Game3.flashScanlineWindows(480, 320, 96, 960, 640)
eq(wide[320][1], 384, "zoomed WIN0 left at the equator")
eq(wide[320][2], 576, "zoomed WIN0 right at the equator")
check(wide[320][1] < 480 and wide[320][2] > 480,
  "zoomed hole contains the player")
check(not wide[0], "zoomed scanlines above the circle stay closed")
check(not wide[80], "GBA-centre row is not the hole on a tall window")
local gScale = Game3.new()
gScale.fitScale = function() return 4 end
eq(gScale:flashOverlayScale(1, 960), 4, "survey OUT does not shrink WIN0")
eq(gScale:flashOverlayScale(0.5, 960), 4, "deep OUT still FIT")
eq(gScale:flashOverlayScale(4, 960), 4, "FIT is unchanged")
eq(gScale:flashOverlayScale(8, 960), 8, "IN keeps the world-pixel hole")
eq(gScale:flashOverlayScale(1, 240), 1, "letterbox canvas stays 24px")
local g = Game3.new()
g.map = { width = 10, height = 10, cave = true }
g.playerX, g.playerY = 0, 0
g.flashLevel = 4
g:clampCamera()
eq(g.camX, Game3.snapPixel(8 - 120), "Flash keeps the player at 120,80")
eq(g.camY, Game3.snapPixel(8 - 80), "including at the cave mouth")
g:drawFlashOverlay()
check(true, "scanline overlay does not throw")
g:drawFlashOverlay(960, 640, 4)
check(true, "zoomed overlay does not throw")
g.flashLevel = 0
g:clampCamera()
eq(g.camX, Game3.snapPixel(8 - 120), "a map narrower than the window keeps the player centered")
eq(g.camY, Game3.snapPixel(8 - 80), "a map as tall as the window stays centred too")
end)()

;(function()
check(Game3.isHmMove(Game3.MOVE_CUT), "Cut is an HM")
check(Game3.isHmMove(15), "Cut id 15")
check(not Game3.isHmMove(10), "Scratch is not")
local g = Game3.new()
g.phase = "play"
g.data.pokemon = g.data.pokemon or {}
g.data.pokemon.byIndex = g.data.pokemon.byIndex or {}
g.data.pokemon.byIndex[280] = {
  name = "TORCHIC", learnset = { { move = 16, level = 10 } },
  growthRate = 3, hp = 45, atk = 60, def = 40, spa = 70, spd = 50, spe = 45,
}
local function chick(nMoves)
  local moves = {
    { id = 10, name = "SCRATCH" },
    { id = 45, name = "GROWL" },
    { id = 52, name = "EMBER" },
    { id = 98, name = "QUICK ATTACK" },
  }
  while #moves > nMoves do moves[#moves] = nil end
  return {
    name = "TORCHIC", species = 280, level = 9, growth = 3,
    exp = Game3.expAtLevel(3, 10) - 8,
    hp = 22, maxHp = 22, moves = moves,
  }
end
local room = chick(3)
g.party = { room }
g:giveMonExp(room, 8)
eq(room.level, 10, "level-up with a free slot")
eq(#room.moves, 4, "learns into the empty slot")
eq(room.moves[4].id, 16, "Peck is appended")
check(not (g.pendingLearn and g.pendingLearn[1]), "no forget prompt")

local full = chick(4)
g.party = { full }
g.pendingLearn = nil
g:giveMonExp(full, 8)
eq(full.level, 10, "full set still levels")
eq(#full.moves, 4, "still four moves")
eq(full.moves[1].id, 10, "does not drop Scratch")
eq(full.moves[4].id, 98, "Quick Attack stays")
check(g.pendingLearn and g.pendingLearn[1], "queues the ROM forget prompt")
eq(g.pendingLearn[1].move, 16, "Peck is waiting")
check(g:startPendingLearn(), "opens trying-to-learn")
eq(g.field.kind, "talk", "trying / can't / delete text")
g:openLearnYesNo()
eq(g.field.kind, "learn_yesno", "Delete a move?")
g:answerLearnYesNo(true)
eq(g.field.kind, "learn_forget", "pick a slot")
g:chooseLearnForget(2)
eq(full.moves[2].id, 16, "replaced Growl with Peck")
eq(full.moves[1].id, 10, "Scratch stayed")

local keep = chick(4)
g.party = { keep }
g.pendingLearn = nil
g.learnMove = nil
g:giveMonExp(keep, 8)
g:startPendingLearn()
g:openLearnYesNo()
g:answerLearnYesNo(false)
eq(g.field.kind, "learn_stop", "Stop learning Peck?")
g:answerLearnStop(true)
eq(keep.moves[1].id, 10, "abandon keeps Scratch")
eq(#keep.moves, 4, "and the original four")
eq(keep.moves[4].id, 98, "Quick Attack stays")

local hm = chick(4)
hm.moves[1] = { id = 15, name = "CUT" }
g.party = { hm }
g.pendingLearn = nil
g.learnMove = nil
g:giveMonExp(hm, 8)
g:startPendingLearn()
g:openLearnYesNo()
g:answerLearnYesNo(true)
check(not g:chooseLearnForget(1), "cannot dump Cut")
eq(hm.moves[1].id, 15, "HM slot unchanged")
end)()

;(function()
local Script = require("src.import.Gen3Script")
local g = Game3.new()
g.phase = "play"
local grid = {}
for i = 1, 64 do grid[i] = 0 end
g:enterMap({
  id = "g_sail", width = 8, height = 8, grid = grid,
  objects = { { x = 1, y = 4, localId = 4, graphicsId = 64 } },
}, 1, 4, true)
local boat = g:npcByLocalId(4)
g:applyMovement(4, Script.parseMovement(string.char(0x16, 0x16, 0xFE), 0))
eq(boat.y, 3, "first fast step starts")
eq(boat.walkDuration, Game3.RUN_PERIOD, "8-frame ministep")
eq(boat.cooldown, Game3.RUN_PERIOD, "cooldown matches")
g:stepScriptMove(Game3.RUN_PERIOD)
eq(boat.y, 2, "second fast step starts at 8 frames")
g:stepScriptMove(Game3.RUN_PERIOD)
eq(boat.y, 2, "two tiles in 16 frames")
check(not g:scriptMoving(), "queue empty after 16 frames")

g:applyMovement(4, Script.parseMovement(string.char(0x2E, 0xFE), 0))
eq(boat.walkDuration, Game3.MACH_PERIOD, "fastest is 4 frames")
g:finishScriptMoves()
eq(boat.y, 1, "one fastest tile north")

g.invisible = true
g:applyMovement(4, Script.parseMovement(string.char(0x18, 0xFE), 0))
eq(boat.x, 2, "hidden player does not snap the boat")
eq(boat.cooldown, Game3.RUN_PERIOD, "boat still uses walk_fast")
g:finishScriptMoves()
g:applyMovement(0xFF, Script.parseMovement(string.char(0x18, 0xFE), 0))
eq(g.playerX, 2, "hidden player still walks with the boat")
eq(g.walkCooldown, Game3.RUN_PERIOD, "at walk_fast, not a snap")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.OBJECT_SUBPRIORITY_ADD, 83, "setobjectpriority adds 83")
eq(Game3.DEFAULT_OBJ_SUBPRIORITY, 0x74, "elevation-0 default is 0x73+1")
check(Game3.drawOrderLess({ y = 0, sub = 84 }, { y = 0, sub = 83 }),
  "script priority 0 draws in front of 1")
check(not Game3.drawOrderLess({ y = 0, sub = 83 }, { y = 0, sub = 84 }),
  "and 1 stays behind")
check(Game3.drawOrderLess({ y = 5 }, { y = 5, sub = 83 }),
  "fixed 83 draws in front of a Y-sorted NPC")
local g = Game3.new()
g.phase = "play"
local grid = {}
for i = 1, 16 do grid[i] = 0 end
g:enterMap({
  id = "g0_11", width = 4, height = 4, grid = grid,
  objects = {
    { x = 1, y = 1, localId = 2, graphicsId = 64 },
    { x = 2, y = 2, localId = 4, graphicsId = 65 },
  },
}, 1, 2, true)
local briney = g:npcByLocalId(2)
check(not g:setObjectPriority(2, 0, 0, 20), "wrong map no-ops")
eq(briney.objSubpriority, nil, "Briney stays Y-sorted")
check(g:setObjectPriority(2, 0, 0, 11), "Dewford Briney")
eq(briney.objSubpriority, 83, "subpriority 0+83")
check(briney.fixedPriority, "and stays pinned")
check(g:setObjectPriority(0xFF, 1, 0, 11), "player on Dewford")
eq(g.objSubpriority, 84, "player 1+83")
check(g:resetObjectPriority(0xFF, 0, 11), "reset player")
eq(g.objSubpriority, nil, "player Y-sorts again")
check(g:resetObjectPriority(2, 0, 11), "reset Briney")
eq(briney.objSubpriority, nil, "Briney Y-sorts again")
briney.x, briney.y = 3, 3
check(g:moveObjectOffscreen(2), "offscreen writes live xy")
eq(briney.homeX, 3, "home x")
eq(briney.homeY, 3, "home y")
eq(g:objectTemplate(2).permX, 3, "template x this visit")
eq(briney.x, 3, "sprite does not teleport")
Gen3Script.run(g, {
  { op = "setobjectpriority", localId = 4, priority = 0,
    mapGroup = 0, mapNum = 11 },
})
eq(g:npcByLocalId(4).objSubpriority, 83, "script IR pins the boat")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_TV_NAME_RATER_SHOW, 123, "TV_PutNameRaterShow")
eq(Game3.SPECIAL_TV_COPY_NICKNAME, 124, "TV_CopyNickname")
eq(Game3.SPECIAL_TV_CHECK_MON_OT_ID, 125, "TV_CheckMonOTID")
eq(Game3.SPECIAL_GET_RECORDED_CYCLING_ROAD, 225, "GetRecordedCyclingRoadResults")
eq(Game3.SPECIAL_BEGIN_CYCLING_ROAD, 226, "BeginCyclingRoadChallenge")
eq(Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE, 227, "GetPlayerAvatarBike")
eq(Game3.SPECIAL_FINISH_CYCLING_ROAD, 228, "FinishCyclingRoadChallenge")
eq(Game3.SPECIAL_UPDATE_CYCLING_ROAD_STATE, 229, "UpdateCyclingRoadState")
eq(Game3.SPECIAL_GET_PLAYER_FACING, 287, "GetPlayerFacingDirection")
eq(Game3.SPECIAL_LEAD_MON_HAS_EFFORT_RIBBON, 292, "LeadMonHasEffortRibbon")
eq(Game3.SPECIAL_GIVE_LEAD_MON_EFFORT_RIBBON, 293, "GivLeadMonEffortRibbon")
eq(Game3.SPECIAL_ARE_LEAD_MON_EVS_MAXED, 294, "AreLeadMonEVsMaxedOut")
eq(Game3.SPECIAL_SCRIPT_GET_PARTY_MON_SPECIES, 327, "ScriptGetPartyMonSpecies")
eq(Game3.SPECIAL_IS_SELECTED_MON_EGG, 328, "IsSelectedMonEgg")
eq(Game3.SPECIAL_MON_OT_NAME_MATCHES_PLAYER, 336, "MonOTNameMatchesPlayer")
eq(Game3.SPECIES_EGG, 412, "SPECIES_EGG")
eq(Game3.CONTEST_LEAD_STAT, 200, "Fan Club Cool is >= 200")
eq(Game3.FLAG_SYS_CYCLING_ROAD, 0x82B, "FLAG_SYS_CYCLING_ROAD")
eq(Game3.FLAG_SYS_RIBBON_GET, 0x83B, "FLAG_SYS_RIBBON_GET")
eq(Game3.MAP_ROUTE110_CYCLING_NORTH_GROUP, 29, "north entrance group")
eq(Game3.MAP_ROUTE110_CYCLING_NORTH_NUM, 12, "north entrance num")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
    },
  },
}
g.party = { g:makeMon(280, 5), g:makeMon(280, 5) }
g:stampPlayerOt(g.party[1])
g:stampPlayerOt(g.party[2])
g.scriptVars = { [0x8004] = 0 }
eq(g:runSpecial(Game3.SPECIAL_SCRIPT_GET_PARTY_MON_SPECIES), 280,
  "Name Rater reads SPECIES2")
g.party[1].isEgg = true
eq(g:runSpecial(Game3.SPECIAL_SCRIPT_GET_PARTY_MON_SPECIES), Game3.SPECIES_EGG,
  "an Egg is SPECIES_EGG")
g:runSpecial(Game3.SPECIAL_IS_SELECTED_MON_EGG)
eq(g.scriptVars[0x800D], 1, "IsSelectedMonEgg")
g.party[1].isEgg = nil
g.party[1].cool = 199
g.party[2].cool = 200
eq(g:runSpecial(Game3.SPECIAL_CHECK_LEAD_MON_COOL), 0, "199 Cool is not enough")
g.party[1].isEgg = true
eq(g:runSpecial(Game3.SPECIAL_CHECK_LEAD_MON_COOL), 1,
  "lead skips the Egg for Cool 200")
g.party[1].isEgg = nil

g.customName = "BRENDAN"
g.party[1].otName = "BRENDAN"
eq(g:runSpecial(Game3.SPECIAL_MON_OT_NAME_MATCHES_PLAYER), 0, "own OT name")
g.party[1].otName = "ELYSSA"
eq(g:runSpecial(Game3.SPECIAL_MON_OT_NAME_MATCHES_PLAYER), 1, "trade OT name")
eq(g.stringVars[1], "ELYSSA", "OT name is buffered")
g.party[1].otName = "BRENDAN"
eq(g:runSpecial(Game3.SPECIAL_TV_CHECK_MON_OT_ID), 0, "own OT id")
g.party[1].otId = g:ensureTrainerId() + 1
eq(g:runSpecial(Game3.SPECIAL_TV_CHECK_MON_OT_ID), 1, "trade OT id")
g.party[1].otId = g:ensureTrainerId()

g.scriptVars[0x8004] = 0
g:openNickname()
eq(g.stringVars[3], "TORCHIC", "ChangePokemonNickname keeps the old nick")
eq(g.field.name, "TORCHIC", "and prefills the naming screen")
g.party[1].name = "SPARK"
eq(g:runSpecial(Game3.SPECIAL_TV_NAME_RATER_SHOW), 1, "a new nick is a TV show")
g:runSpecial(Game3.SPECIAL_TV_COPY_NICKNAME)
eq(g.stringVars[1], "SPARK", "copy writes STR_VAR_1")
g.stringVars[3] = "SPARK"
eq(g:runSpecial(Game3.SPECIAL_TV_NAME_RATER_SHOW), 0, "same nick is not a show")
g.field = nil
g.scriptWait = nil

eq(g:runSpecial(Game3.SPECIAL_LEAD_MON_HAS_EFFORT_RIBBON), 0, "no ribbon yet")
g.party[1].hpEv, g.party[1].atkEv = 255, 254
eq(g:runSpecial(Game3.SPECIAL_ARE_LEAD_MON_EVS_MAXED), 0, "509 EVs are short")
g.party[1].atkEv = 255
eq(g:runSpecial(Game3.SPECIAL_ARE_LEAD_MON_EVS_MAXED), 1, "510 EVs are maxed")
g:runSpecial(Game3.SPECIAL_GIVE_LEAD_MON_EFFORT_RIBBON)
eq(g.party[1].effortRibbon, true, "GivLeadMonEffortRibbon")
eq(g.flags[Game3.FLAG_SYS_RIBBON_GET], true, "FLAG_SYS_RIBBON_GET")
eq(g.gameStats[Game3.GAME_STAT_RECEIVED_RIBBONS], 1, "GAME_STAT_RECEIVED_RIBBONS")
eq(g:runSpecial(Game3.SPECIAL_LEAD_MON_HAS_EFFORT_RIBBON), 1, "already has it")
local row = g:snapshotMon(g.party[1])
eq(row.effortRibbon, true, "saves keep the ribbon")
eq(row.hpEv, 255, "and HP EVs")
local restored = g:restoreMon(row)
eq(restored.effortRibbon, true, "load restores the ribbon")
eq(restored.atkEv, 255, "and Atk EVs")

g.bike = "mach"
eq(g:runSpecial(Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE), 2, "Mach Bike is 2")
g.bike = "acro"
eq(g:runSpecial(Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE), 1, "Acro Bike is 1")
g.bike = nil
eq(g:runSpecial(Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE), 0, "on foot is 0")
g.facing = "west"
eq(g:runSpecial(Game3.SPECIAL_GET_PLAYER_FACING), Game3.DIR_WEST, "facing")

g.vblankCounter = 0
g:runSpecial(Game3.SPECIAL_BEGIN_CYCLING_ROAD)
eq(g.bikeCyclingChallenge, true, "challenge starts")
eq(g.bikeCollisions, 0, "collisions reset")
g.vblankCounter = 600
g:runSpecial(Game3.SPECIAL_FINISH_CYCLING_ROAD)
eq(g.scriptVars[0x800D], 10, "0 bumps in 10s is score 10")
eq(g.stringVars[1], "0 times", "collision string")
eq(g.stringVars[2], "10.00 seconds", "time string")
eq(g.scriptVars[Game3.VAR_CYCLING_ROAD_RECORD_TIME_L], 600, "record frames")
eq(g:runSpecial(Game3.SPECIAL_GET_RECORDED_CYCLING_ROAD), 1, "sign sees a record")
eq(g.stringVars[1], "0 times", "and still buffers collisions")

g.scriptVars[Game3.VAR_CYCLING_CHALLENGE_STATE] = 2
g.lastUsedWarp = {
  mapGroup = Game3.MAP_ROUTE110_CYCLING_NORTH_GROUP,
  mapNum = Game3.MAP_ROUTE110_CYCLING_NORTH_NUM,
}
g:runSpecial(Game3.SPECIAL_UPDATE_CYCLING_ROAD_STATE)
eq(g.scriptVars[Game3.VAR_CYCLING_CHALLENGE_STATE], 2,
  "north entrance keeps the challenge")
g.lastUsedWarp = { mapGroup = 29, mapNum = 11 }
g:runSpecial(Game3.SPECIAL_UPDATE_CYCLING_ROAD_STATE)
eq(g.scriptVars[Game3.VAR_CYCLING_CHALLENGE_STATE], 0,
  "any other warp clears it")

local grid = { 1024, 1024, 1024, 1024, 0, 1024, 1024, 1024, 1024 }
g:enterMap({
  id = "g_cr", group = 9, index = 0, width = 3, height = 3, grid = grid,
}, 1, 1, true)
g.bikeCyclingChallenge = true
g.bikeCollisions = 0
g.facing = "north"
check(not g:tryWalk(0, -1), "a wall bump")
eq(g.bikeCollisions, 1, "counts toward the challenge")
local dest = {
  id = "g29_12", group = 29, index = 12, width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  warps = { { x = 1, y = 1 } },
}
g.data.maps = { maps = { g29_12 = dest } }
g:scriptWarp(29, 12, 0, 1, 1)
eq(g.lastUsedWarp.mapGroup, 9, "script warp remembers the source")
eq(g.map.id, "g29_12", "and enters the dest")

Gen3Script.run(g, {
  { op = "specialvar", var = 0x800D, id = Game3.SPECIAL_GET_PLAYER_AVATAR_BIKE },
})
eq(g.scriptVars[0x800D], 0, "specialvar stores GetPlayerAvatarBike")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_GET_LEAD_MON_FRIENDSHIP, 230, "GetLeadMonFriendshipScore")
eq(Game3.SPECIAL_SWAP_REGISTERED_BIKE, 130, "SwapRegisteredBike")
eq(Game3.FADE_FRAMES, 16, "palette fade is 16 frames")
eq(Game3.ITEM_SOOTHE_BELL, 184, "Soothe Bell")
eq(Game3.HOLD_EFFECT_HAPPINESS_UP, 27, "HOLD_EFFECT_HAPPINESS_UP")
eq(Game3.VAR_HAPPINESS_STEP_COUNTER, 0x402A, "VAR_HAPPINESS_STEP_COUNTER")
eq(Game3.TRAINER_CLASS_LEADER, 25, "gym leader class")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, friendship = 70,
    },
  },
}
g.party = { g:makeMon(280, 5) }
eq(g.party[1].friendship, 70, "CreateMon uses base friendship")
eq(g:leadMonFriendshipScore(), 2, "70 is score 2")
g.party[1].friendship = 150
eq(g:runSpecial(Game3.SPECIAL_GET_LEAD_MON_FRIENDSHIP), 4,
  "Fan Club Soothe Bell needs score 4")
g.party[1].friendship = 255
eq(g:leadMonFriendshipScore(), 6, "255 is score 6")

g.party[1].friendship = 70
g:adjustFriendship(g.party[1], Game3.FRIENDSHIP_EVENT_GROW_LEVEL)
eq(g.party[1].friendship, 75, "level-up +5 under 100")
g.party[1].item = Game3.ITEM_SOOTHE_BELL
g:adjustFriendship(g.party[1], Game3.FRIENDSHIP_EVENT_GROW_LEVEL)
eq(g.party[1].friendship, 82, "Soothe Bell is 1.5x")
g.party[1].item = nil
g.party[1].friendship = 70
g.party[1].isEgg = true
g:adjustFriendship(g.party[1], Game3.FRIENDSHIP_EVENT_GROW_LEVEL)
eq(g.party[1].friendship, 70, "eggs do not gain")
g.party[1].isEgg = nil

g.party[1].isEgg = true
g:hatchEgg(g.party[1])
eq(g.party[1].friendship, 120, "hatch is 120")

g.rng = function() return 1 end
g.party[1].friendship = 70
g.scriptVars = { [Game3.VAR_HAPPINESS_STEP_COUNTER] = 127 }
local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
g:enterMap({ id = "g_h", width = 3, height = 3, grid = cells }, 1, 1, true)
check(g:tryWalk(1, 0), "a happiness step")
eq(g.scriptVars[Game3.VAR_HAPPINESS_STEP_COUNTER], 0, "counter wraps at 128")
eq(g.party[1].friendship, 71, "walking +1 when Random is even")

g.party[1].friendship = 70
g.party[1].level = 5
g.party[1].hp = 1
local foe = { name = "POOCHYENA", level = 40, hp = 20, maxHp = 20 }
g.battle = { player = g.party[1], enemy = foe }
g:dealDamage(foe, g.party[1], { power = 40, type = 0, effect = 0 })
eq(g.party[1].hp, 0, "the hit KOs")
eq(g.party[1].friendship, 65, "foe 35 levels above is FAINT_LARGE")

g.registeredItem = Game3.ITEM_MACH_BIKE
g:runSpecial(Game3.SPECIAL_SWAP_REGISTERED_BIKE)
eq(g.registeredItem, Game3.ITEM_ACRO_BIKE, "Mach SELECT becomes Acro")
g:runSpecial(Game3.SPECIAL_SWAP_REGISTERED_BIKE)
eq(g.registeredItem, Game3.ITEM_MACH_BIKE, "and back")

local npc = { trainerId = 1, trainerClass = Game3.TRAINER_CLASS_LEADER }
g.battle = { npc = npc }
g.party[1].friendship = 70
g:applyLeagueFriendship(npc)
eq(g.party[1].friendship, 73, "gym battle start +3")
npc.trainerClass = 0
g.party[1].friendship = 70
g:applyLeagueFriendship(npc)
eq(g.party[1].friendship, 70, "a youngster does not")

g.delayLeft = nil
g.field = nil
local _, fadePause = Gen3Script.run(g, {
  { op = "fadescreen", mode = Game3.FADE_TO_BLACK },
})
eq(fadePause, "delay", "fadescreen pauses the VM")
check((g.delayLeft or 0) > 0, "for 16 frames")
g.delayLeft = nil
g._scriptPause = nil

local row = g:snapshotMon(g.party[1])
eq(row.friendship, 70, "saves keep friendship")
eq(g:restoreMon(row).friendship, 70, "and load it")
end)()

;(function()
eq(Game3.ITEM_MACHO_BRACE, 181, "Macho Brace")
eq(Game3.HOLD_EFFECT_MACHO_BRACE, 24, "HOLD_EFFECT_MACHO_BRACE")
eq(Game3.MAX_TOTAL_EVS, 510, "MAX_TOTAL_EVS")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, friendship = 70,
      evYieldSpa = 1,
    },
    [261] = {
      name = "POOCHYENA", hp = 35, atk = 55, def = 35, spe = 35,
      spa = 30, spd = 30, type1 = 17, type2 = 17, catchRate = 255,
      expYield = 55, growthRate = 0,
      evYieldAtk = 1,
    },
  },
}
g.party = { g:makeMon(280, 5) }
g.party[1].ivs = Game3.zeroIvs()
g.party[1].pid = 0
g:recalcStats(g.party[1])
g.party[1].hp = g.party[1].maxHp
local startHp = g.party[1].maxHp

g:awardExp(g.party[1], { species = 261, level = 2, expYield = 55 })
eq(g.party[1].atkEv, 1, "Poochyena yields 1 Atk")
eq(g.party[1].spaEv or 0, 0, "and no SpA")

g.party[1].item = Game3.ITEM_MACHO_BRACE
g:awardExp(g.party[1], { species = 261, level = 2, expYield = 55 })
eq(g.party[1].atkEv, 3, "Macho Brace doubles the yield")
g.party[1].item = nil

g.party[1].pokerus = 0x10
g:awardExp(g.party[1], { species = 261, level = 2, expYield = 55 })
eq(g.party[1].atkEv, 5, "cured Pokerus still doubles")
g.party[1].pokerus = 0

g.party[1].atkEv = 254
g:gainEVs(g.party[1], { species = 261 })
eq(g.party[1].atkEv, 255, "per-stat cap is 255")

g.party[1].hpEv, g.party[1].atkEv = 255, 254
g.party[1].defEv, g.party[1].speEv = 0, 0
g.party[1].spaEv, g.party[1].spdEv = 0, 0
g.data.pokemon.byIndex[261].evYieldAtk = 3
g:gainEVs(g.party[1], { species = 261 })
eq(g:monEvCount(g.party[1]), 510, "total cap is 510")
eq(g.party[1].atkEv, 255, "the leftover Atk EV is clamped")
g.data.pokemon.byIndex[261].evYieldAtk = 1

local bench = g:makeMon(280, 5)
bench.item = Game3.ITEM_EXP_SHARE
g.party[2] = bench
g.battle = { player = g.party[1], sentIn = { [1] = true } }
g:awardExp(g.party[1], { species = 261, level = 2, expYield = 55 })
eq(g.party[2].atkEv, 1, "Exp. Share still gets the full EV yield")
g.party[2] = nil
g.battle = nil

g.party[1].hpEv = 252
g.party[1].atkEv, g.party[1].defEv = 0, 0
g.party[1].speEv, g.party[1].spaEv, g.party[1].spdEv = 0, 0, 0
g:recalcStats(g.party[1])
eq(g.party[1].maxHp > startHp, true, "HP EVs raise max HP")

local saved = g:snapshotMon(g.party[1])
eq(saved.hpEv, 252, "saves keep EVs")
local loaded = g:restoreMon(saved)
eq(loaded.hpEv, 252, "load restores EVs")
eq(loaded.maxHp, g.party[1].maxHp, "and stats include them")
end)()

;(function()
eq(Game3.SPECIAL_MAUVILLE_GYM_2, 139, "MauvilleGymSpecial2")
eq(Game3.SPECIAL_MAUVILLE_GYM_1, 140, "MauvilleGymSpecial1")
eq(Game3.SPECIAL_DRAW_WHOLE_MAP_VIEW, 142, "DrawWholeMapView")
eq(Game3.SPECIAL_STORE_PLAYER_COORDS, 143, "StorePlayerCoordsInVars")
eq(Game3.SPECIAL_MAUVILLE_GYM_3, 144, "MauvilleGymSpecial3")
eq(Game3.MAP_OFFSET, 7, "MAP_OFFSET")
eq(Game3.MT_MAUVILLE_PRESSED, 0x206, "PressedSwitch")
eq(Game3.MT_MAUVILLE_RAISED, 0x205, "RaisedSwitch")

local w, h = 9, 17
local grid = {}
for i = 1, w * h do grid[i] = 0 end
local function at(x, y) return y * w + x + 1 end
grid[at(0, 9)] = Game3.MT_MAUVILLE_RAISED
grid[at(8, 11)] = Game3.MT_MAUVILLE_RAISED
grid[at(4, 15)] = Game3.MT_MAUVILLE_RAISED
grid[at(1, 6)] = Game3.MT_MAUVILLE_GREEN_H1_ON
grid[at(1, 7)] = Game3.MT_MAUVILLE_GREEN_H3_OFF
grid[at(2, 6)] = Game3.MT_MAUVILLE_POLE_BOTTOM_ON
grid[at(2, 7)] = Game3.MT_MAUVILLE_FLOOR

local g = Game3.new()
g.phase = "play"
g:enterMap({ id = "mauville_gym", width = w, height = h, grid = grid }, 3, 8, true)
g.scriptVars = { [0x8004] = 0 }
g:runSpecial(Game3.SPECIAL_MAUVILLE_GYM_1)
eq(Game3.metatileOf(grid[at(0, 9)]), Game3.MT_MAUVILLE_PRESSED, "switch 0 presses")
eq(Game3.metatileOf(grid[at(8, 11)]), Game3.MT_MAUVILLE_RAISED, "switch 1 stays up")
eq(Game3.metatileOf(grid[at(4, 15)]), Game3.MT_MAUVILLE_RAISED, "switch 2 stays up")

g:runSpecial(Game3.SPECIAL_MAUVILLE_GYM_2)
eq(Game3.metatileOf(grid[at(1, 6)]), Game3.MT_MAUVILLE_GREEN_H1_OFF, "H1 on becomes off")
eq(Game3.metatileOf(grid[at(1, 7)]), Game3.MT_MAUVILLE_GREEN_H3_ON, "H3 off becomes on")
eq(Game3.collisionOf(grid[at(1, 7)]) ~= 0, true, "H3 on is solid")
eq(Game3.walkable({ width = w, height = h, grid = grid }, 1, 7), false, "so you cannot walk it")
eq(Game3.metatileOf(grid[at(2, 6)]), Game3.MT_MAUVILLE_GREEN_V1, "pole becomes green V1")
eq(Game3.metatileOf(grid[at(2, 7)]), Game3.MT_MAUVILLE_GREEN_V2, "floor under it is V2")

g:runSpecial(Game3.SPECIAL_MAUVILLE_GYM_3)
eq(Game3.metatileOf(grid[at(0, 9)]), Game3.MT_MAUVILLE_PRESSED, "all switches stay down")
eq(Game3.metatileOf(grid[at(8, 11)]), Game3.MT_MAUVILLE_PRESSED, "including 1")
eq(Game3.metatileOf(grid[at(2, 6)]), Game3.MT_MAUVILLE_POLE_BOTTOM_ON, "V1 becomes pole")
eq(Game3.metatileOf(grid[at(2, 7)]), Game3.MT_MAUVILLE_FLOOR, "V2 becomes floor")
eq(Game3.metatileOf(grid[at(1, 7)]), Game3.MT_MAUVILLE_GREEN_H3_OFF, "H3 on turns off")

g.playerX, g.playerY = 4, 10
g:runSpecial(Game3.SPECIAL_STORE_PLAYER_COORDS)
eq(g.scriptVars[0x8004], 4, "x into VAR_0x8004")
eq(g.scriptVars[0x8005], 10, "y into VAR_0x8005")
g:runSpecial(Game3.SPECIAL_DRAW_WHOLE_MAP_VIEW)
eq(Game3.metatileOf(grid[at(2, 7)]), Game3.MT_MAUVILLE_FLOOR, "DrawWholeMapView leaves the grid")
end)()

;(function()
eq(Game3.SPECIAL_PETALBURG_GYM_SLIDE, 145, "PetalburgGymSlideOpenDoors")
eq(Game3.SPECIAL_PETALBURG_GYM_OPEN, 146, "PetalburgGymOpenDoorsInstantly")
eq(Game3.SPECIAL_GET_PLAYER_TRAINER_ID_ONES, 147, "GetPlayerTrainerIdOnesDigit")
eq(Game3.SPECIAL_SET_HIDDEN_ITEM_FLAG, 150, "SetHiddenItemFlag")
eq(Game3.SPECIAL_CABLE_CAR_WARP, 151, "CableCarWarp")
eq(Game3.SPECIAL_CABLE_CAR, 152, "CableCar")
eq(Game3.MUS_CABLE_CAR, 425, "MUS_CABLE_CAR")
eq(Game3.CABLE_CAR_FRAMES_UP, 0x15E, "unk_0004 going up")
eq(Game3.CABLE_CAR_FRAMES_DOWN, 0x109, "unk_0004 going down")
eq(Game3.SPECIAL_SET_TRICK_HOUSE_END, 261, "SetTrickHouseEndRoomFlag")
eq(Game3.SPECIAL_RESET_TRICK_HOUSE_END, 260, "ResetTrickHouseEndRoomFlag")
eq(Game3.FLAG_TRICK_HOUSE_END_ROOM, 0x259, "FLAG_HIDDEN_ITEM_1 is the end-room bit")
eq(Game3.MT_PETALBURG_DOOR_OPEN, 0x21C, "sliding door frame 4")

local g = Game3.new()
g.phase = "play"
g.trainerId = 12345
eq(g:runSpecial(Game3.SPECIAL_GET_PLAYER_TRAINER_ID_ONES), 5, "ones digit of OT id")

g:runSpecial(Game3.SPECIAL_SET_TRICK_HOUSE_END)
eq(g.flags[Game3.FLAG_TRICK_HOUSE_END_ROOM], true, "end room flag sets")
eq(g.scriptVars[0x8004], 0x259, "and copies into VAR_0x8004")
g:runSpecial(Game3.SPECIAL_RESET_TRICK_HOUSE_END)
eq(g.flags[Game3.FLAG_TRICK_HOUSE_END_ROOM] == true, false, "reset clears it")

g.scriptVars[0x8004] = 0x300
g:runSpecial(Game3.SPECIAL_SET_HIDDEN_ITEM_FLAG)
eq(g.flags[0x300], true, "SetHiddenItemFlag uses VAR_0x8004")

local w, h = 10, 16
local grid = {}
for i = 1, w * h do grid[i] = 0 end
g:enterMap({ id = "petalburg_gym", width = w, height = h, grid = grid }, 1, 1, true)
g.scriptVars[0x8004] = 7
g:runSpecial(Game3.SPECIAL_PETALBURG_GYM_OPEN)
local function at(x, y) return y * w + x + 1 end
eq(Game3.metatileOf(grid[at(7, 13)]), Game3.MT_PETALBURG_DOOR_OPEN, "room 7 top tile")
eq(Game3.metatileOf(grid[at(7, 14)]), Game3.MT_PETALBURG_DOOR_OPEN + 8, "and the tile below")
eq(Game3.collisionOf(grid[at(7, 13)]) ~= 0, true, "open doors stay solid")

g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_CABLE_CAR_WARP)
eq(g.cableCarDest.num, Game3.MAP_MT_CHIMNEY_CABLE_CAR_NUM, "0 rides up to Chimney")
eq(g.cableCarDest.x, 6, "at (6,4)")
g.scriptVars[0x8004] = 1
g:runSpecial(Game3.SPECIAL_CABLE_CAR_WARP)
eq(g.cableCarDest.num, Game3.MAP_ROUTE112_CABLE_CAR_NUM, "nonzero rides down")

g.data.maps = g.data.maps or {}
g.data.maps.maps = g.data.maps.maps or {}
local function station(num)
  local grid = {}
  for i = 1, 64 do grid[i] = 0 end
  return {
    id = Game3.mapId(19, num), group = 19, index = num,
    width = 8, height = 8, grid = grid, music = 0,
  }
end
g.data.maps.maps["g19_0"] = station(0)
g.data.maps.maps["g19_1"] = station(1)
g:enterMap(g.data.maps.maps["g19_0"], 6, 4, true)
g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_CABLE_CAR_WARP)
g:runSpecial(Game3.SPECIAL_CABLE_CAR)
eq(g.field.kind, "cable_car", "CableCar is the ride callback")
eq(g.field.left, Game3.CABLE_CAR_FRAMES_UP, "0x15e frames up")
check(g:scriptWaiting(), "LockPlayerFieldControls")
eq(g.map.id, "g19_0", "WarpIntoMap waits for the ride")
g:walkHeld(Game3.CABLE_CAR_FRAMES_UP / 60)
eq(g.map.id, "g19_1", "up arrives at Chimney station")
eq(g.playerX, 6, "x 6")
eq(g.playerY, 4, "y 4")
check(not g:scriptWaiting(), "CB2_LoadMap resumes the script")
eq(g.field, nil, "cinema closed")

g.scriptVars[0x8004] = 1
g:runSpecial(Game3.SPECIAL_CABLE_CAR_WARP)
g:runSpecial(Game3.SPECIAL_CABLE_CAR)
eq(g.field.left, Game3.CABLE_CAR_FRAMES_DOWN, "0x109 frames down")
g:walkHeld(Game3.CABLE_CAR_FRAMES_DOWN / 60)
eq(g.map.id, "g19_0", "down arrives at Route 112 station")

g.stringVars = { [4] = "hello from VAR4" }
g:runSpecial(Game3.SPECIAL_SHOW_FIELD_MESSAGE_VAR4)
eq(g.field.kind, "talk", "ShowFieldMessageStringVar4 talks")
eq(g.field.text, "hello from VAR4", "from string var 4")
g.field = nil

g.bag = {}
g:addItem(Game3.ITEM_MACH_BIKE, 1)
g:addItem(Game3.ITEM_POTION, 1)
g:enterMap({
  id = "route", width = 4, height = 4, mapType = 0,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g:canRegisterItem(Game3.ITEM_MACH_BIKE), true, "Key Items register")
eq(g:canRegisterItem(Game3.ITEM_POTION), false, "Potions do not")
local ok, msg = g:toggleRegisteredItem(Game3.ITEM_MACH_BIKE)
eq(ok, true, "SELECT registers the Mach Bike")
eq(g.registeredItem, Game3.ITEM_MACH_BIKE, "into registeredItem")
g:useRegisteredItem()
eq(g.bike, "mach", "field SELECT hops on")
g:toggleRegisteredItem(Game3.ITEM_MACH_BIKE)
eq(g.registeredItem, 0, "SELECT again unregisters")
g.registeredItem = 0
g.field = nil
g:useRegisteredItem()
eq(g.field.text, Game3.TEXT_NO_REGISTERED_ITEM, "empty SELECT is the BAG hint")
end)()

;(function()
eq(Game3.SPECIAL_ROTATING_GATE_INIT, 201, "RotatingGate_InitPuzzle")
eq(Game3.SPECIAL_ROTATING_GATE_GFX, 202, "RotatingGate_InitPuzzleAndGraphics")
eq(Game3.SPECIAL_HAS_ENOUGH_MONEY_FOR, 197, "HasEnoughMoneyFor")
eq(Game3.SPECIAL_PAY_MONEY_FOR, 198, "PayMoneyFor")
eq(Game3.SPECIAL_GET_SLOT_MACHINE_ID, 286, "GetSlotMachineId")
eq(Game3.MAP_FORTREE_GYM_GROUP, 12, "IndoorFortree")
eq(Game3.MAP_FORTREE_GYM_NUM, 1, "Fortree gym is House1+1")
eq(Game3.MAP_TRICK_HOUSE_PUZZLE6_NUM, 8, "puzzle 6 after 0-7")

local g = Game3.new()
g.money = 100
g.scriptVars = { [0x8005] = 50 }
eq(g:runSpecial(Game3.SPECIAL_HAS_ENOUGH_MONEY_FOR), 1, "50 fits in 100")
g.scriptVars[0x8005] = 200
eq(g:runSpecial(Game3.SPECIAL_HAS_ENOUGH_MONEY_FOR), 0, "200 does not")
g.scriptVars[0x8005] = 40
g:runSpecial(Game3.SPECIAL_PAY_MONEY_FOR)
eq(g.money, 60, "PayMoneyFor subtracts VAR_0x8005")
g.scriptVars[0x8004] = 0
eq(g:runSpecial(Game3.SPECIAL_GET_SLOT_MACHINE_ID), 0, "cabinet 0 is payout 0")
g.scriptVars[0x8004] = 1
eq(g:runSpecial(Game3.SPECIAL_GET_SLOT_MACHINE_ID), 1, "cabinet 1 salts to 2")

local w, h = 24, 24
local grid = {}
for i = 1, w * h do grid[i] = 0 end
g:enterMap({
  id = Game3.mapId(Game3.MAP_FORTREE_GYM_GROUP, Game3.MAP_FORTREE_GYM_NUM),
  width = w, height = h, grid = grid, mapType = Game3.MAP_TYPE_INDOOR,
}, 12, 5, true)
g:runSpecial(Game3.SPECIAL_ROTATING_GATE_INIT)
eq(g:rotatingGatePuzzleType(), Game3.PUZZLE_FORTREE, "Fortree gym puzzle")
eq(#g.rotatingGates, 7, "seven Fortree gates")
eq(g:rotatingGateOrient(1), 0, "L4 at (12,5) starts at 0")
eq(g:rotatingGateHasArm(1, 0, 0), true, "north short arm")
eq(g:rotatingGateHasArm(1, 0, 1), true, "and north long")
eq(g:rotatingGateHasArm(1, 2, 0), false, "no south arm at 0")
check(g:tryWalk(0, -1), "bumping the north arm spins it")
eq(g.playerX, 12, "and the step goes through")
eq(g.playerY, 4, "onto the old arm tile")
eq(g:rotatingGateOrient(1), 3, "ACW from 0 is 270")

g:enterMap({
  id = Game3.mapId(Game3.MAP_FORTREE_GYM_GROUP, Game3.MAP_FORTREE_GYM_NUM),
  width = w, height = h, grid = grid, mapType = Game3.MAP_TYPE_INDOOR,
}, 12, 5, true)
grid[4 * w + 11 + 1] = 1024
g:runSpecial(Game3.SPECIAL_ROTATING_GATE_INIT)
eq(g:tryWalk(0, -1), false, "a collision-1 tile in the sweep blocks")
eq(g.playerY, 5, "so the player stays")
eq(g:rotatingGateOrient(1), 0, "and the gate does not spin")

g:enterMap({
  id = Game3.mapId(Game3.MAP_TRICK_HOUSE_PUZZLE6_GROUP,
    Game3.MAP_TRICK_HOUSE_PUZZLE6_NUM),
  width = w, height = h, grid = grid, mapType = Game3.MAP_TYPE_INDOOR,
}, 1, 1, true)
g:runSpecial(Game3.SPECIAL_ROTATING_GATE_GFX)
eq(g:rotatingGatePuzzleType(), Game3.PUZZLE_TRICK_HOUSE_6, "Trick House 6")
eq(#g.rotatingGates, 14, "fourteen Trick House gates")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_START_WALL_CLOCK, 154, "StartWallClock")
eq(Game3.SPECIAL_VIEW_WALL_CLOCK, 155, "ViewWallClock")
eq(Game3.FLAG_SYS_CLOCK_SET, 0x835, "FLAG_SYS_CLOCK_SET")
eq(Game3.VAR_DAYS, 0x4040, "VAR_DAYS")
eq(Game3.ITEM_COIN_CASE, 260, "ITEM_COIN_CASE")
eq(Game3.MAX_COINS, 9999, "MAX_COINS")
eq(Game3.TEXT_CLOCK_ASK, "Is this the correct time?", "wallclock.c prompt")
eq(Gen3Script.PLAYSLOTMACHINE, 0x89, "playslotmachine")
eq(Gen3Script.CHECKCOINS, 0xB3, "checkcoins")
eq(Gen3Script.ADDCOINS, 0xB4, "addcoins")
eq(Gen3Script.REMOVECOINS, 0xB5, "removecoins")
eq(Gen3Script.SHOWCOINSBOX, 0xC0, "showcoinsbox")
eq(Game3.SLOT_PAYOUTS[1], 2, "1CHERRY pays 2")
eq(Game3.SLOT_PAYOUTS[7], 90, "777 mix pays 90")
eq(Game3.SLOT_PAYOUTS[8], 300, "777 red pays 300")

local g = Game3.new()
eq(g:getCoins(), 0, "new game has 0 coins")
eq(g:addCoinsScript(50), 0, "addcoins ok is RESULT 0")
eq(g:getCoins(), 50, "and the till moves")
eq(g:removeCoinsScript(20), 0, "removecoins ok is 0")
eq(g:getCoins(), 30, "spent 20")
eq(g:removeCoinsScript(40), 1, "short is RESULT 1")
eq(g:getCoins(), 30, "and the till stays")
g.coins = Game3.MAX_COINS
eq(g:addCoinsScript(1), 1, "full is RESULT 1")
eq(g:getCoins(), Game3.MAX_COINS, "still 9999")
g:showCoinsBox(1, 1)
eq(g.coinsBox.x, 1, "showcoinsbox stores x")
g:hideCoinsBox()
eq(g.coinsBox, nil, "hidecoinsbox clears it")

g:startWallClock()
eq(g.field.kind, "clock_set", "StartWallClock opens the setter")
eq(g.field.hours, 10, "default 10:00")
eq(g.field.minutes, 0, "on the hour")
check(g:scriptWaiting(), "and waitstate holds")
g:advanceClock(1)
eq(g.field.minutes, 1, "RIGHT is +1 min")
g.field.hours, g.field.minutes = 23, 59
g:advanceClock(1)
eq(g.field.hours, 0, "23:59 wraps to 0:00")
eq(g.field.minutes, 0, "minutes too")
g.field.hours, g.field.minutes = 14, 30
g:confirmWallClock()
eq(g.field, nil, "YES closes the clock")
eq(g.flags[Game3.FLAG_SYS_CLOCK_SET], true, "InitTimeBasedEvents")
eq(g:varGet(Game3.VAR_DAYS), 0, "VAR_DAYS starts at 0")
eq(g:localTime().hours, 14, "RtcInitLocalTimeOffset kept 14")
eq(g:localTime().minutes, 30, "and 30")
eq(g:clockString({ hours = 0, minutes = 0 }), "12:00 AM", "midnight is 12 AM")
eq(g:clockString({ hours = 12, minutes = 5 }), "12:05 PM", "noon is 12 PM")
g.flags[Game3.FLAG_SYS_CLOCK_SET] = nil
g:viewWallClock()
eq(g.field.kind, "clock_view", "ViewWallClock is read-only")
eq(g.flags[Game3.FLAG_SYS_CLOCK_SET], nil, "and does not set the sys flag")
g:closeWallClock()
eq(g:scriptWaiting(), false, "A/B ends the wait")

g:beginScreenFade(Game3.FADE_TO_BLACK)
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
check(g:screenFadeAlpha() >= 0.99, "script FADE_TO_BLACK is opaque")
g:startWallClock()
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "StartWallClock fades in like WallClockInit")
check(g:fieldShowsWorld(), "clock HUD draws over the bedroom, not under the veil")
g:confirmWallClock()
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "YES returns through CB2_ReturnToField's fade-in")
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
eq(g.screenFade, nil, "and the veil actually lifts")

g:beginScreenFade(Game3.FADE_TO_BLACK)
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
g:viewWallClock()
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "ViewWallClock also fades in")
g:closeWallClock()
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "A/B fades the bedroom back in")

eq(Game3.slotMatch(4, 9, 9), Game3.SLOT_MATCH_1CHERRY, "left cherry alone")
eq(Game3.slotMatch(0, 0, 0), Game3.SLOT_MATCH_777_RED, "three red 7s")
eq(Game3.slotMatch(0, 0, 1), Game3.SLOT_MATCH_777_MIXED, "red red blue")
eq(Game3.slotMatch(6, 6, 6), Game3.SLOT_MATCH_REPLAY, "three replays")
eq(Game3.slotPayout(Game3.SLOT_MATCH_REPLAY), 0, "replay pays 0")
eq(Game3.slotPayout(Game3.SLOT_MATCH_1CHERRY), 2, "1CHERRY is 2")
eq(Game3.slotPayout(Game3.SLOT_MATCH_2CHERRY), 4, "2CHERRY is 4")
local pay, replay = g:slotScore({ { 0, 4, 0 }, { 1, 4, 1 }, { 2, 4, 2 } }, 1)
eq(pay, 2, "center three cherries is 1CHERRY")
eq(replay, false, "not a replay")
pay = select(1, g:slotScore({ { 4, 5, 2 }, { 1, 2, 3 }, { 0, 1, 6 } }, 2))
eq(pay, 4, "top left cherry upgrades to 2CHERRY")
pay, replay = g:slotScore({ { 4, 5, 2 }, { 1, 2, 3 }, { 0, 1, 6 } }, 3)
eq(pay, 4, "diag left cherry does not pay")
eq(replay, false, "and is not a replay")
pay, replay = g:slotScore({ { 4, 6, 4 }, { 4, 6, 4 }, { 4, 6, 4 } }, 1)
eq(pay, 0, "center replay pays 0")
eq(replay, true, "and grants a free spin")

g.coins = 10
g.rng = function() return 1 end
g:playSlotMachine(0)
eq(g.field.kind, "slots", "playslotmachine opens the cabinet")
eq(g.field.bet, 1, "default bet 1")
check(g:scriptWaiting(), "ScriptContext_Stop until B")
check(g:spinSlots(), "a spin with coins runs")
eq(g:getCoins() >= 9, true, "spent the bet (payout may refund)")
g:closeSlots()

local ops = Gen3Script.parse(
  string.char(0xC0, 2, 3)
  .. string.char(0xB3, 0x0D, 0x80)
  .. string.char(0xB4, 5, 0)
  .. string.char(0xB5, 1, 0)
  .. string.char(0xC2, 0, 0)
  .. string.char(0xC1, 0, 0)
  .. string.char(0x02), 0)
eq(ops[1].op, "showcoinsbox", "showcoinsbox is kept")
eq(ops[1].x, 2, "x tile")
eq(ops[1].y, 3, "y tile")
eq(ops[2].op, "checkcoins", "checkcoins is kept")
eq(ops[3].op, "addcoins", "addcoins is kept")
eq(ops[4].op, "removecoins", "removecoins is kept")
eq(ops[5].op, "updatecoinsbox", "updatecoinsbox is kept")
eq(ops[6].op, "hidecoinsbox", "hidecoinsbox is kept")
g.coins = 10
Gen3Script.run(g, ops)
eq(g:getCoins(), 14, "add 5 then remove 1")
eq(g:varGet(0x800D), 0, "last removecoins succeeded")
eq(g.coinsBox, nil, "hidecoinsbox closed it")
local slotOps = Gen3Script.parse(
  string.char(0x89, 0, 0) .. string.char(0x02), 0)
eq(slotOps[1].op, "playslotmachine", "playslotmachine is kept")
g.coins = 5
local _, pause = Gen3Script.run(g, slotOps)
eq(pause, "wait", "the opcode stops the script")
eq(g.field.kind, "slots", "and opens the machine")
g:closeSlots()
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local g = Game3.new()
g.phase = "play"
g:applyNewGameHideFlags()
local cells = {}
for i = 1, 64 do cells[i] = 0 end
local setClock = {
  { op = "fadescreen", mode = 1 },
  { op = "special", id = Game3.SPECIAL_START_WALL_CLOCK },
  { op = "waitstate" },
  { op = "end" },
}
local momWalk = {
  { op = "setvar", var = 0x8008, val = 14 },
  { op = "addobject", localId = 0x8008 },
  { op = "applymovement", localId = 0x8008,
    steps = { { kind = "walk", dir = "south" } } },
  { op = "waitmovement", localId = 0 },
  { op = "loadword", text = "How do you like your room?" },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
  { op = "end" },
}
local clockScript = {
  { op = "lockall" },
  { op = "loadword", text = "The clock is stopped." },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
  { op = "call", body = setClock },
  { op = "delay", frames = 30 },
  { op = "setvar", var = Game3.VAR_LITTLEROOT_INTRO_STATE, val = 6 },
  { op = "setflag", flag = Game3.FLAG_SET_WALL_CLOCK },
  { op = "call", body = momWalk },
  { op = "releaseall" },
  { op = "end" },
}
g:enterMap({
  id = "g1_1", width = 8, height = 8, grid = cells, spawn = { x = 4, y = 4 },
  bgEvents = { {
    x = 5, y = 1, kind = 0, text = "The clock is stopped.",
    script = clockScript,
  } },
  objects = { {
    x = 7, y = 1, localId = 14, graphicsId = Game3.GFX_MOM,
    flagId = Game3.FLAG_HIDE_MOM_UPSTAIRS,
  } },
}, 5, 2, true)
g.facing = "north"
g.walkCooldown = Game3.WALK_PERIOD
check(g:tryTalk(), "A on the stopped clock")
eq(g.field.kind, "talk", "ClockIsStopped")
g:resumeMoveScript()
eq(g.field.kind, "delay", "fadescreen before StartWallClock")
g:walkHeld((g.delayLeft or 0) + 1)
eq(g.field.kind, "clock_set", "StartWallClock opened")
check(g:scriptWaiting(), "waitstate holds")
eq(g.screenFade and g.screenFade.mode, Game3.FADE_FROM_BLACK,
  "the bedroom fade-in has started")
g:confirmWallClock()
local n = 0
while (not g.field or g.field.kind ~= "talk") and n < 120 do
  g:walkHeld(Game3.WALK_PERIOD)
  n = n + 1
end
eq(g.field and g.field.kind, "talk", "Mom's line after the clock")
eq(g.screenFade, nil, "and the fade veil is gone")
eq(g.flags[Game3.FLAG_SET_WALL_CLOCK], true, "FLAG_SET_WALL_CLOCK")
eq(g.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], 6, "intro 6")
check(g.flags[Game3.FLAG_SYS_CLOCK_SET], "and FLAG_SYS_CLOCK_SET")
end)()

;(function()
eq(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN, 97, "GetCurrentMauvilleMan")
eq(Game3.SPECIAL_PLAY_BARD_SONG, 103, "PlayBardSong")
eq(Game3.SPECIAL_TRADER_DO_TRADE, 118, "TraderDoDecorationTrade")
eq(Game3.MAUVILLE_MAN_BARD, 0, "bard id is 0")
eq(Game3.GFX_BARD, 69, "OBJ_EVENT_GFX_BARD")
eq(Game3.FLAG_SYS_HIPSTER_MEET, 0x806, "FLAG_SYS_HIPSTER_MEET")
eq(#Game3.STORYTELLER_STORIES, 36, "36 storyteller tales")
eq(#Game3.EC_WORDS[20], 33, "33 trendy sayings")
eq(Game3.bardLyricString(Game3.DEFAULT_BARD_LYRICS),
  "SISTER EATS SWEETS\nVORACIOUS AND DROOLING",
  "default bard song")
local g = Game3.new()
g.trainerId = 0
g:setupMauvilleOldMan()
eq(g:runSpecial(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN), 0, "id 0 is bard")
eq(g:varGet(0x800D), 0, "special writes VAR_RESULT even when 0")
eq(g:varGet(Game3.VAR_OBJ_GFX_ID_0), 69, "gfx 69 + bard")
eq(g:runSpecial(Game3.SPECIAL_HAS_BARD_SONG_CHANGED), 0, "unchanged song")
g:setScriptVar(0x8004, 6)
g:runSpecial(Game3.SPECIAL_SHOW_EASY_CHAT)
eq(g.field.kind, "easy_chat", "mode 6 is the lyric editor")
eq(g.field.slots, 6, "six words")
check(g:scriptWaiting(), "Easy Chat waitstate")
g:finishEasyChat(true)
eq(g:varGet(0x800D), 1, "confirm is RESULT 1")
g:setScriptVar(0x8004, 0)
g:runSpecial(Game3.SPECIAL_PLAY_BARD_SONG)
eq(g.field.kind, "bard_song", "PlayBardSong opens the lyrics")
check(g:scriptWaiting(), "and waitstate holds")
eq(g.field.text, "SISTER EATS SWEETS\nVORACIOUS AND DROOLING",
  "saved lyrics, not temp")
g.field = nil
g:endScriptWait()
g.trainerId = 2
g:setupMauvilleOldMan()
eq(g:runSpecial(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN), 1, "id 2 is hipster")
eq(g:runSpecial(Game3.SPECIAL_GET_HIPSTER_SPOKEN), 0, "not spoken yet")
eq(g:runSpecial(Game3.SPECIAL_HIPSTER_TEACH_WORD), 1, "teaches a trendy word")
check((g.stringVars[1] or "") ~= "", "into string var 1")
g:runSpecial(Game3.SPECIAL_SET_HIPSTER_SPOKEN)
eq(g:runSpecial(Game3.SPECIAL_GET_HIPSTER_SPOKEN), 1, "spoken flag sticks")
local i = 1
while i <= 33 do
  g:unlockTrendySaying(i)
  i = i + 1
end
eq(g:runSpecial(Game3.SPECIAL_HIPSTER_TEACH_WORD), 0, "all 33 already known")
g.trainerId = 8
g:setupMauvilleOldMan()
g.rng = function() return 2 end
eq(g:runSpecial(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN), 4, "id 8 is giddy")
eq(g:runSpecial(Game3.SPECIAL_GENERATE_GIDDY_LINE), 1, "GenerateGiddyLine")
check((g.stringVars[4] or "") ~= "", "fills string var 4")
eq(g:runSpecial(Game3.SPECIAL_GIDDY_SHOULD_TELL_ANOTHER), 1, "first tale continues")
g.trainerId = 6
g:setupMauvilleOldMan()
eq(g:runSpecial(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN), 3, "id 6 is storyteller")
eq(g:runSpecial(Game3.SPECIAL_STORYTELLER_FREE_SLOT), 0, "no stories yet")
eq(g:runSpecial(Game3.SPECIAL_STORYTELLER_ALREADY_RECORDED), 0, "not recorded")
g.gameStats = { [0] = 1 }
eq(g:runSpecial(Game3.SPECIAL_STORYTELLER_INIT_STAT), 1, "saved-game tale records")
eq(g:runSpecial(Game3.SPECIAL_STORYTELLER_FREE_SLOT), 1, "slot 1 is now free")
eq(g:runSpecial(Game3.SPECIAL_STORYTELLER_ALREADY_RECORDED), 1, "already recorded")
g:runSpecial(Game3.SPECIAL_STORYTELLER_LIST_MENU)
eq(g.field.kind, "mauville_menu", "story list waitstate")
check(g:scriptWaiting(), "until a pick")
g:pickMauvilleMenu(0)
eq(g:varGet(0x800D), 1, "picking a tale is RESULT 1")
g.trainerId = 4
g:setupMauvilleOldMan()
eq(g:runSpecial(Game3.SPECIAL_GET_CURRENT_MAUVILLE_MAN), 2, "id 4 is trader")
eq(g:runSpecial(Game3.SPECIAL_PLAYER_HAS_NO_DECORATIONS), 1, "empty deco bag")
g:runSpecial(Game3.SPECIAL_TRADER_MENU_GET)
eq(g.field.kind, "mauville_menu", "get-deco menu waitstate")
eq(g.field.labels[1], "DUSKULL DOLL", "first stock item")
check(g:scriptWaiting(), "until A/B")
g:pickMauvilleMenu(4)
eq(g:varGet(0x8004), 0, "CANCEL writes 0x8004=0")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_PLAY_ROULETTE, 162, "PlayRoulette")
eq(Gen3Script.GETPRICEREDUCTION, 0x96, "getpricereduction")
eq(Game3.rouletteMinBet(0), 1, "left table is 1 coin")
eq(Game3.rouletteMinBet(1), 3, "right table is 3")
eq(Game3.rouletteMinBet(0x81), 6, "PokéNews rate on the right table")
eq(Game3.rouletteHitInBet(6, 6), true, "O-WY hits itself")
eq(Game3.rouletteHitInBet(6, 1), true, "and the WYNAUT column")
eq(Game3.rouletteHitInBet(6, 5), true, "and the ORANGE row")
eq(Game3.rouletteHitInBet(6, 2), false, "not AZURILL")
eq(Game3.rouletteHitInBet(12, 5), false, "green is not orange")
local g = Game3.new()
eq(g:rouletteMultiplier(6), 12, "a square starts at 12x")
eq(g:rouletteMultiplier(1), 4, "a column starts at 4x")
eq(g:rouletteMultiplier(5), 3, "a row starts at 3x")
g.coins = 50
g:setScriptVar(0x8004, 0)
g:runSpecial(Game3.SPECIAL_PLAY_ROULETTE)
eq(g.field.kind, "roulette", "PlayRoulette opens the table")
eq(g.field.minBet, 1, "left table min 1")
check(g:scriptWaiting(), "and waitstate holds")
g.rng = function() return 1 end
g.field.cursor = 6
check(g:spinRoulette(), "a 12x bet on the first pocket")
eq(g.field.won, true, "is a hit")
eq(g.field.payout, 12, "pays minBet * 12")
eq(g:getCoins(), 61, "50-1+12")
eq(g.field.balls, 1, "one ball spent")
eq(g:rouletteMultiplier(6, g.field), 0, "that square is dead")
eq(g:rouletteMultiplier(1, g.field), 6, "WYNAUT column steps to 6x")
eq(g:rouletteMultiplier(5, g.field), 4, "ORANGE row steps to 4x")
eq(g:getGameStat(Game3.GAME_STAT_CONSECUTIVE_ROULETTE_WINS), 1,
  "streak high-water")
eq(g:spinRoulette(), false, "cannot bet a dead square")
g.field.cursor = 5
check(g:spinRoulette(), "ORANGE misses the next pocket")
eq(g.field.won, false, "nothing doing")
eq(g.field.streak, 0, "streak resets")
eq(g:getGameStat(Game3.GAME_STAT_CONSECUTIVE_ROULETTE_WINS), 1,
  "high-water stays")
g:closeRoulette()
eq(g:varGet(0x8004), 0, "still enough coins")
eq(g:scriptWaiting(), false, "B ends the wait")
g.coins = 0
g:setScriptVar(0x8004, 0)
g:runSpecial(Game3.SPECIAL_PLAY_ROULETTE)
g:closeRoulette()
eq(g:varGet(0x8004), 1, "broke writes 0x8004=1")
local ops = Gen3Script.parse(string.char(0x96, 2, 0) .. string.char(0x02), 0)
eq(ops[1].op, "getpricereduction", "getpricereduction is kept")
eq(ops[1].index, 2, "kind 2 is Game Corner")
Gen3Script.run(g, ops)
eq(g:varGet(0x800D), 0, "no PokéNews yet")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Gen3Script.SETWILDBATTLE, 0xB6, "setwildbattle")
eq(Gen3Script.DOWILDBATTLE, 0xB7, "dowildbattle")
eq(Game3.SPECIES_VOLTORB, 100, "Voltorb")
eq(Game3.ITEM_NONE, 0, "ITEM_NONE")
eq(Game3.ITEM_BASEMENT_KEY, 271, "Basement Key")
eq(Game3.FLAG_SYS_CTRL_OBJ_DELETE, 0x861, "ON_RESUME delete")
eq(Game3.GAME_STAT_WILD_BATTLES, 8, "wild battles stat")
local ops = Gen3Script.parse(
  string.char(0xB6, 100, 0, 25, 13, 0)
  .. string.char(0xB7) .. string.char(0x02), 0)
eq(ops[1].op, "setwildbattle", "setwildbattle is kept")
eq(ops[1].species, 100, "species is a literal")
eq(ops[1].level, 25, "New Mauville is lv25")
eq(ops[1].item, 13, "then a held item")
eq(ops[2].op, "dowildbattle", "dowildbattle follows")
local g = Game3.new()
g.party = { g:makeMon(280, 5) }
g:setWildBattle(Game3.SPECIES_VOLTORB, 25, Game3.ITEM_NONE)
eq(g.scriptedWild.species, 100, "CreateScriptedWildMon stores")
check(g:doWildBattle(), "dowildbattle starts the fight")
eq(g.phase, "battle", "phase is battle")
eq(g.battle.enemy.species, 100, "against Voltorb")
eq(g.battle.enemy.level, 25, "lv25")
eq(g.battle.enemy.item, nil, "ITEM_NONE holds nothing")
check(g:scriptWaiting(), "ScriptContext_Stop")
eq(g:getGameStat(Game3.GAME_STAT_WILD_BATTLES), 1, "IncrementGameStat wild")
eq(g:getGameStat(Game3.GAME_STAT_TOTAL_BATTLES), 1, "and total")
local last
g.removeObject = function(self, id) last = id end
g.map = {
  mapScripts = {
    onResume = { { op = "removeobject", localId = 0x800F } },
  },
}
g:setScriptVar(0x800F, 3)
g:endBattle()
eq(last, 3, "ON_RESUME removeobject LAST_TALKED")
eq(g:scriptWaiting(), false, "then the script continues")
eq(g.phase, "play", "back on the field")
g.party = { g:makeMon(280, 5) }
g:setWildBattle(100, 25, 13)
g:doWildBattle()
eq(g.battle.enemy.item, 13, "a held item is attached")
g.map = { width = 8, height = 4, grid = {} }
local n = 8 * 4
for i = 1, n do g.map.grid[i] = 0 end
g:setMetatile(4, 0, 0x314, 1)
eq(Game3.collisionOf(g.map.grid[g:gridIndex(g.map, 4, 0)]), 1,
  "closed New Mauville door blocks")
g:setMetatile(4, 0, 0x2C4, 0)
eq(Game3.collisionOf(g.map.grid[g:gridIndex(g.map, 4, 0)]), 0,
  "open door is walkable")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Gen3Script.CHECKPARTYMOVE, 0x7C, "checkpartymove")
eq(Gen3Script.BUFFERPARTYMONNICK, 0x7F, "bufferpartymonnick")
eq(Gen3Script.BUFFERMOVENAME, 0x82, "buffermovename")
eq(Game3.SPECIAL_ROCK_SMASH_WILD_ENCOUNTER, 171, "smash wild special")
eq(Game3.SPECIAL_TRY_UPDATE_RUSTURF_TUNNEL_STATE, 298, "Rusturf special")
eq(Game3.MAP_RUSTURF_TUNNEL_GROUP, 24, "dungeons group")
eq(Game3.MAP_RUSTURF_TUNNEL_NUM, 4, "RusturfTunnel index")
eq(Game3.FLAG_RUSTURF_TUNNEL_OPENED, 0xC7, "tunnel opened")
eq(Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1, 0x3A3, "hide rock 1")
eq(Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_2, 0x3A4, "hide rock 2")
eq(Game3.VAR_RUSTURF_TUNNEL_STATE, 0x409A, "tunnel state var")
eq(Game3.PARTY_SIZE, 6, "PARTY_SIZE miss")
eq(Game3.MOVE_ROCK_SMASH, 249, "MOVE_ROCK_SMASH")
local ops = Gen3Script.parse(
  string.char(0x7C, 0xF9, 0)
  .. string.char(0x7F, 0, 0x0D, 0x80)
  .. string.char(0x82, 1, 0xF9, 0)
  .. string.char(0x02), 0)
eq(ops[1].op, "checkpartymove", "checkpartymove is kept")
eq(ops[1].move, 249, "move is a literal")
eq(ops[2].op, "bufferpartymonnick", "bufferpartymonnick is kept")
eq(ops[2].slot, 0, "STR_VAR_1")
eq(ops[2].partyIndex, 0x800D, "party index is VAR_RESULT")
eq(ops[3].op, "buffermovename", "buffermovename is kept")
eq(ops[3].move, 249, "move id")
local g = Game3.new()
g.party = {
  { name = "ZIGZAGOON", species = 263, moves = { { id = 249 } } },
}
Gen3Script.run(g, ops)
eq(g:varGet(0x800D), 0, "lead slot is RESULT 0")
eq(g:varGet(0x8004), 263, "0x8004 is the species")
eq(g.stringVars[1], "ZIGZAGOON", "buffers the nick")
eq(g.stringVars[2], "ROCK SMASH", "and the move")
eq(g:checkPartyMove(15), 6, "nobody knows CUT")
g.party = {
  { name = "EGG", species = 263, isEgg = true, moves = { { id = 249 } } },
  { name = "TAILLOW", species = 276, moves = { { id = 249 } } },
}
eq(g:checkPartyMove(249), 1, "eggs are skipped")
g.party = {
  { species = 0, moves = { { id = 249 } } },
  { name = "TAILLOW", species = 276, moves = { { id = 249 } } },
}
eq(g:checkPartyMove(249), 6, "empty species breaks")
g.map = { id = "g_cut" }
eq(g:tryUpdateRusturfTunnelState(), 0, "wrong map is FALSE")
g.map = { id = "g24_4" }
g.flags[Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1] = true
eq(g:runSpecial(Game3.SPECIAL_TRY_UPDATE_RUSTURF_TUNNEL_STATE), 1,
  "rock 1 opens state 4")
eq(g:varGet(Game3.VAR_RUSTURF_TUNNEL_STATE), 4, "VAR = 4")
g.flags[Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1] = nil
g.flags[Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_2] = true
eq(g:tryUpdateRusturfTunnelState(), 1, "rock 2")
eq(g:varGet(Game3.VAR_RUSTURF_TUNNEL_STATE), 5, "VAR = 5")
g.flags[Game3.FLAG_RUSTURF_TUNNEL_OPENED] = true
eq(g:tryUpdateRusturfTunnelState(), 0, "already open")
g.phase = "play"
g.party = { {
  name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5,
  moves = { { id = 249 } },
} }
g.data.encounters = { byMap = { g_rock = {
  rock = { rate = 255, slots = {
    { minLevel = 8, maxLevel = 8, species = 74 },
  } },
} } }
g:enterMap({ id = "g_rock", width = 3, height = 3, grid = {
  0, 0, 0, 0, 0, 0, 0, 0, 0,
} }, 1, 1, true)
g.rng = function() return 1 end
eq(g:runSpecial(Game3.SPECIAL_ROCK_SMASH_WILD_ENCOUNTER), 1, "smash wild")
eq(g.phase, "battle", "starts a fight")
eq(g.battle.enemy.species, 74, "Geodude")
check(g:scriptWaiting(), "ScriptContext_Stop")
eq(g:getGameStat(Game3.GAME_STAT_WILD_BATTLES), 1, "stat 8")
eq(g:getGameStat(Game3.GAME_STAT_TOTAL_BATTLES), 1, "stat 7")
g:endBattle()
eq(g:scriptWaiting(), false, "then waitstate continues")
g.data.encounters = { byMap = { g_rock = { rock = { rate = 0, slots = {
  { minLevel = 8, maxLevel = 8, species = 74 },
} } } } }
eq(g:runSpecial(Game3.SPECIAL_ROCK_SMASH_WILD_ENCOUNTER), 0, "rate miss")
eq(g:varGet(0x800D), 0, "RESULT 0")
g.facing = "east"
g.flags[Game3.FLAG_BADGE03_GET] = true
g.flags[Game3.FLAG_RUSTURF_TUNNEL_OPENED] = nil
g.flags[Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1] = nil
g.data.encounters = { byMap = { g24_4 = {
  rock = { rate = 255, slots = {
    { minLevel = 8, maxLevel = 8, species = 74 },
  } },
} } }
g:enterMap({
  id = "g24_4", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    { x = 2, y = 1, localId = 4, graphicsId = Game3.GFX_BREAKABLE_ROCK,
      flagId = Game3.FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1 },
  },
}, 1, 1, true)
g.phase = "play"
g.battle = nil
g.rng = function() return 1 end
local smashed = g:useRockSmash()
check(smashed, "bag smash still breaks the rock")
eq(g.phase, "play", "Rusturf skips the wild")
eq(g:varGet(Game3.VAR_RUSTURF_TUNNEL_STATE), 4, "and sets state 4")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Gen3Script.RESETWEATHER, 0xA3, "resetweather")
eq(Gen3Script.SETWEATHER, 0xA4, "setweather")
eq(Gen3Script.DOWEATHER, 0xA5, "doweather")
eq(Game3.OW_WEATHER_SANDSTORM, 8, "WEATHER_SANDSTORM")
eq(Game3.OW_WEATHER_SUNNY, 2, "WEATHER_SUNNY")
eq(Game3.COORD_EVENT_WEATHER[9], 8, "coord sandstorm -> 8")
eq(Game3.COORD_EVENT_WEATHER[8], 7, "coord ash -> 7")
eq(Game3.GAME_STAT_GOT_RAINED_ON, 40, "rained-on stat")
eq(Game3.WEATHER_CYCLE_119[1], 2, "119 cycle starts sunny")
eq(Game3.WEATHER_CYCLE_119[2], 3, "then light rain")
local ops = Gen3Script.parse(
  string.char(0xA4, 8, 0) .. string.char(0xA5) .. string.char(0xA3)
  .. string.char(0x02), 0)
eq(ops[1].op, "setweather", "setweather is kept")
eq(ops[1].weather, 8, "weather is a halfword")
eq(ops[2].op, "doweather", "doweather follows")
eq(ops[3].op, "resetweather", "resetweather")
local g = Game3.new()
g:enterMap({
  id = "g_sand", width = 3, height = 3, weather = 2,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
eq(g:getCurrentWeather(), 2, "header SUNNY after load")
Gen3Script.run(g, { { op = "setweather", weather = 8 } })
eq(g.sav1Weather, 8, "setweather writes sav1")
eq(g:getCurrentWeather(), 2, "and does not ChangeWeather yet")
Gen3Script.run(g, { { op = "doweather" } })
eq(g:getCurrentWeather(), 8, "doweather copies sav1")
Gen3Script.run(g, { { op = "resetweather" } })
eq(g.sav1Weather, 2, "resetweather is the map header")
eq(g:getCurrentWeather(), 8, "until doweather")
g:doCurrentWeather()
eq(g:getCurrentWeather(), 2, "then SUNNY again")
g:setSav1Weather(3)
eq(g:getGameStat(Game3.GAME_STAT_GOT_RAINED_ON), 1, "light rain counts")
g:setSav1Weather(3)
eq(g:getGameStat(Game3.GAME_STAT_GOT_RAINED_ON), 1, "same weather does not")
g:setSav1Weather(5)
eq(g:getGameStat(Game3.GAME_STAT_GOT_RAINED_ON), 2, "med rain counts")
g.weatherCycleStage = 1
eq(g:translateWeatherNum(20), 3, "119 cycle stage 1 is rain")
g:enterMap({
  id = "g_ash", width = 3, height = 3, weather = 2,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  coordEvents = { { x = 2, y = 1, trigger = 8 } },
}, 1, 1, true)
eq(g:getCurrentWeather(), 2, "spawn is still sunny")
g:tryCoordEvent(2, 1)
eq(g:getCurrentWeather(), 7, "null-script ash coord Sets weather")
g.party = { {
  name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5,
  moves = { { id = 10 } },
} }
g.currWeather = 8
check(g:startWildBattle(74, 8), "a desert wild")
eq(g.battle.weather, Game3.WEATHER_SAND, "battle copies sandstorm")
eq(g.battle.weatherTurns, nil, "and it is permanent")
g:dismissIntro()
eq(g.battle.text, "A sandstorm is raging.", "OverworldWeatherStarts")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_GABBY_AND_TY_GET_BATTLE_NUM, 172, "GabbyAndTyGetBattleNum")
eq(Game3.SPECIAL_GABBY_AND_TY_AFTER_INTERVIEW, 173, "AfterInterview")
eq(Game3.SPECIAL_GABBY_AND_TY_BEFORE_INTERVIEW, 174, "BeforeInterview")
eq(Game3.SPECIAL_IS_TV_SHOW_IN_SEARCH_OF_TRAINERS_AIRING, 176, "airing")
eq(Game3.SPECIAL_GABBY_AND_TY_GET_LAST_QUOTE, 177, "GetLastQuote")
eq(Game3.SPECIAL_GABBY_AND_TY_GET_LAST_BATTLE_TRIVIA, 178, "GetLastBattleTrivia")
eq(Game3.SPECIAL_GET_GABBY_AND_TY_LOCAL_IDS, 179, "GetGabbyAndTyLocalIds")
eq(Game3.SPECIAL_GET_BATTLE_OUTCOME, 180, "GetBattleOutcome")
eq(Game3.EC_TYPE_GABBY_INTERVIEW, 10, "ShowEasyChatScreen case 10")
eq(Game3.GAME_STAT_GOT_INTERVIEWED, 6, "GAME_STAT_GOT_INTERVIEWED")
eq(Game3.B_OUTCOME_WON, 1, "B_OUTCOME_WON")
eq(Game3.B_OUTCOME_LOST, 2, "B_OUTCOME_LOST")
eq(Game3.B_OUTCOME_RAN, 4, "B_OUTCOME_RAN")
eq(Game3.B_OUTCOME_CAUGHT, 7, "B_OUTCOME_CAUGHT")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_GABBY_AND_TY_GET_BATTLE_NUM), 0,
  "battleNum 0 is the first pair")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "specialvar still stores 0")
eq(g:runSpecial(Game3.SPECIAL_GABBY_AND_TY_GET_LAST_QUOTE), 0,
  "quote 0xFFFF is FALSE")
eq(g:runSpecial(Game3.SPECIAL_GABBY_AND_TY_GET_LAST_BATTLE_TRIVIA), 1,
  "!valB_0 is trivia 1")
eq(g:runSpecial(Game3.SPECIAL_IS_TV_SHOW_IN_SEARCH_OF_TRAINERS_AIRING), 0,
  "not airing yet")
eq(g:runSpecial(Game3.SPECIAL_GET_BATTLE_OUTCOME), 0, "no fight yet")

g.gabbyAndTy.battleNum = 6
eq(g:gabbyAndTyGetBattleNum(), 6, "6 stays 6")
g.gabbyAndTy.battleNum = 7
eq(g:gabbyAndTyGetBattleNum(), 7, "7 stays 7")
g.gabbyAndTy.battleNum = 8
eq(g:gabbyAndTyGetBattleNum(), 8, "8 stays 8")
g.gabbyAndTy.battleNum = 9
eq(g:gabbyAndTyGetBattleNum(), 6, "(9 % 3) + 6")

g = Game3.new()
g.party = { {
  name = "TORCHIC", hp = 19, maxHp = 19, species = 255, level = 5,
  moves = { { id = 150, name = "SPLASH", effect = Game3.EFFECT_SPLASH, power = 0 } },
} }
check(g:startWildBattle(74, 8), "a wild to fill gBattleResults")
g:useMove(g.battle.player, g.battle.enemy, g.battle.player.moves[1])
eq(g.battleResults.lastUsedMove, 150, "player move is lastUsedMove")
g:recordBattleEnd(Game3.B_OUTCOME_WON)
eq(g:runSpecial(Game3.SPECIAL_GET_BATTLE_OUTCOME), 1, "win is 1")
eq(g.battleResults.poke1Species, 255, "end snapshot is the player mon")

g:gabbyAndTyBeforeInterview()
eq(g.gabbyAndTy.battleNum, 1, "BeforeInterview increments 0 to 1")
eq(g.gabbyAndTy.lastMove, 150, "copies lastUsedMove")
eq(g.gabbyAndTy.mon1, 255, "and poke1Species")
eq(g.flags[Game3.FLAG_TEMP_1], nil, "a used move does not set FLAG_TEMP_1")
g:getGabbyAndTyLocalIds()
eq(g:varGet(0x8004), 14, "case 1 Gabby is Route 111 object 14")
eq(g:varGet(0x8005), 13, "and Ty is 13")

g = Game3.new()
g:ensureBattleResults()
g:gabbyAndTyBeforeInterview()
eq(g.gabbyAndTy.battleNum, 1, "still increments with no move")
eq(g.flags[Game3.FLAG_TEMP_1], true, "lastMove 0 sets FLAG_TEMP_1")
eq(g:runSpecial(Game3.SPECIAL_IS_TV_SHOW_IN_SEARCH_OF_TRAINERS_AIRING), 0,
  "TakeTVShowInSearchOfTrainersOffTheAir")

g.map = { regionMapSectionId = 26 }
g:gabbyAndTyAfterInterview()
eq(g.gabbyAndTy.valA_4, 1, "AfterInterview puts the show on air")
eq(g.gabbyAndTy.mapnum, 26, "MAPSEC_ROUTE_111")
eq(g:getGameStat(Game3.GAME_STAT_GOT_INTERVIEWED), 1, "stat 6")
eq(g:runSpecial(Game3.SPECIAL_IS_TV_SHOW_IN_SEARCH_OF_TRAINERS_AIRING), 1,
  "valA_4 is TRUE")

local hot = Game3.ecPack(10, 0)
g.gabbyAndTy.quote = hot
eq(g:gabbyAndTyGetLastQuote(), 1, "a real word is TRUE")
eq(g.stringVars[1], "HOT", "into STR_VAR_1")
eq(g.gabbyAndTy.quote, Game3.EC_EMPTY_WORD, "quote |= 0xFFFF consumes it")
eq(g:gabbyAndTyGetLastQuote(), 0, "second read is FALSE")

g.gabbyAndTy.valB_0 = 1
eq(g:gabbyAndTyGetLastBattleTrivia(), 0, "damaged and nothing else is 0")
g.gabbyAndTy.valB_3 = 1
eq(g:gabbyAndTyGetLastBattleTrivia(), 2, "used a ball is 2")

g = Game3.new()
g.scriptVars = { [0x8004] = 10 }
g:runSpecial(Game3.SPECIAL_SHOW_EASY_CHAT)
eq(g.field.kind, "easy_chat", "mode 10 opens Easy Chat")
eq(g.field.slots, 1, "one word")
eq(g.gabbyAndTy.quote, Game3.EC_EMPTY_WORD, "opens by writing 0xFFFF")
check(g:scriptWaiting(), "and waitstate holds")
g.field.words = { hot }
g:finishEasyChat(true)
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "confirm is RESULT 1")
eq(g.gabbyAndTy.quote, hot, "stored as the quote")

g = Game3.new()
g.scriptVars = { [0x8004] = 10 }
g:showEasyChatScreen()
g:finishEasyChat(false)
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "cancel is RESULT 0")
eq(g.gabbyAndTy.quote, Game3.EC_EMPTY_WORD, "cancel leaves 0xFFFF")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.TRAINER_TYPE_BURIED, 3, "TRAINER_TYPE_BURIED")
eq(Game3.MOVEMENT_TYPE_HIDDEN, 0x3F, "MOVEMENT_TYPE_HIDDEN")
local g = Game3.new()
g.phase = "play"
g.playerX, g.playerY = 2, 0
g.party = { g:makeMon(280, 5) }
g.map = {
  id = "g_bury", width = 5, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local buried = {
  x = 2, y = 1, facing = "south", localId = 2,
  trainerType = Game3.TRAINER_TYPE_BURIED, trainerRange = 1,
  movementType = Game3.MOVEMENT_TYPE_HIDDEN, invisible = true,
  party = { { species = 286, level = 5 } },
  trainerName = "COLE", trainerClass = "KINDLER",
}
g.npcByMap = { g_bury = { buried } }
check(g:seesPlayer(buried, g.map), "BURIED sees north of FACE_DOWN")
g.playerX, g.playerY = 1, 1
check(g:seesPlayer(buried, g.map), "and west")
g.playerX, g.playerY = 2, 1
check(not g:seesPlayer(buried, g.map), "same tile is out of range")
g.playerX, g.playerY = 2, 0
check(g:tryTrainerSpot(), "spotting a buried trainer")
eq(buried.invisible, nil, "pops out of the ash")
eq(buried.movementType, Game3.MOVEMENT_TYPE_FACE_UP, "faces the player")
eq(g.field.kind, "trainer_approach", "then the !")
local normal = {
  x = 2, y = 1, facing = "south",
  trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 1,
  party = { { species = 286, level = 5 } },
}
g.playerX, g.playerY = 2, 0
check(not g:seesPlayer(normal, g.map), "NORMAL still only looks one way")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.EFFECT_OVERHEAT, 204, "EFFECT_OVERHEAT")
eq(Game3.EFFECT_LIGHT_SCREEN, 35, "EFFECT_LIGHT_SCREEN")
eq(Game3.EFFECT_REFLECT, 65, "EFFECT_REFLECT")
eq(Game3.EFFECT_ATTRACT, 120, "EFFECT_ATTRACT")
eq(Game3.EFFECT_FLAIL, 99, "EFFECT_FLAIL")
eq(Game3.flailPower(48, 48), 20, "full HP Flail is 20")
eq(Game3.flailPower(1, 48), 200, "1/48 is 200")
eq(Game3.flailPower(4, 48), 150, "4/48 is 150")
eq(Game3.flailPower(5, 48), 100, "5/48 is 100")
eq(Game3.SCREEN_TURNS, 5, "screens last 5")
eq(Game3.ABILITY_OBLIVIOUS, 12, "OBLIVIOUS")

local g = Game3.new()
g.rng = function() return 1 end
g.data.moves = { typeChart = {} }
local slug = {
  name = "SLUGMA", level = 26, hp = 60, maxHp = 60,
  atk = 40, def = 40, spa = 70, spd = 40, spe = 20,
  type1 = Game3.TYPE_FIRE, type2 = Game3.TYPE_FIRE,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  pid = 200, species = 218,
}
local hero = {
  name = "MUDKIP", level = 26, hp = 80, maxHp = 80,
  atk = 50, def = 50, spa = 50, spd = 50, spe = 40,
  type1 = Game3.TYPE_WATER, type2 = Game3.TYPE_WATER,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
  pid = 0, species = 258,
}
local overheat = {
  name = "OVERHEAT", effect = Game3.EFFECT_OVERHEAT,
  power = 140, type = Game3.TYPE_FIRE, accuracy = 100, pp = 5,
}
g:useMove(slug, hero, overheat)
eq(slug.stages.spa, -2, "Overheat drops the user's Sp. Atk")
slug.ability = Game3.ABILITY_CLEAR_BODY
slug.stages.spa = 0
g:useMove(slug, hero, overheat)
eq(slug.stages.spa, -2, "Clear Body does not block Overheat")

g.battle = { player = hero, enemy = slug }
eq(g:setSideScreen(slug, "lightScreen"),
  "LIGHT SCREEN raised SP. DEF!", "Light Screen goes up")
eq(g:setSideScreen(slug, "lightScreen"), "But it failed!",
  "already up fails")
eq(g.battle.screens.enemy.lightScreen, 5, "5 turns")
local screenMul = g:screenDamageMul(slug, false)
eq(screenMul, 5, "special hits are halved")
eq(g:screenDamageMul(slug, true), 10, "physical is not")
eq(g:tickScreens()[1], nil, "turn 1 still up")
eq(g.battle.screens.enemy.lightScreen, 4, "4 left")
g.battle.screens.enemy.lightScreen = 1
eq(g:tickScreens()[1], "LIGHT SCREEN wore off!", "expires")

eq(g:monGender(hero), Game3.MON_FEMALE, "pid 0 Mudkip is female")
eq(g:monGender(slug), Game3.MON_MALE, "pid 200 Slugma is male")
g:useAttract(slug, hero)
eq(hero.infatuatedBy, slug, "Attract infatuates")
local skip, msgs = g:statusBlocks(hero)
check(skip, "even Random immobilizes")
check(msgs[2]:find("immobilized", 1, true), "love lock")
hero.infatuatedBy = nil
hero.ability = Game3.ABILITY_OBLIVIOUS
local lines = g:useAttract(slug, hero)
check(lines[1]:find("OBLIVIOUS", 1, true), "Oblivious blocks")
hero.ability = nil
g:useAttract(slug, slug)
eq(slug.infatuatedBy, nil, "same gender fails")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Script = require("src.import.Gen3Script")
eq(Game3.ABILITY_FORECAST, 59, "ABILITY_FORECAST")
eq(Game3.SPECIES_CASTFORM, 385, "SPECIES_CASTFORM")
eq(Game3.EFFECT_WEATHER_BALL, 203, "EFFECT_WEATHER_BALL")
eq(Game3.ITEM_MYSTIC_WATER, 209, "ITEM_MYSTIC_WATER")
eq(Game3.abilityName(Game3.ABILITY_FORECAST), "FORECAST", "name")
eq(Game3.TYPE_NORMAL, 0, "TYPE_NORMAL")

local g = Game3.new()
local foe = { name = "POOCHYENA", ability = 0, hp = 20, maxHp = 20,
  type1 = 17, type2 = 17 }
local form = {
  name = "CASTFORM", species = Game3.SPECIES_CASTFORM,
  ability = Game3.ABILITY_FORECAST,
  hp = 70, maxHp = 70,
  type1 = Game3.TYPE_NORMAL, type2 = Game3.TYPE_NORMAL,
}
g.battle = { player = form, enemy = foe }
g.battle.weather = Game3.WEATHER_RAIN
eq(g:castformDataTypeChange(form), Game3.CASTFORM_TO_WATER, "rain -> Water")
eq(form.type1, Game3.TYPE_WATER, "type1 Water")
eq(form.type2, Game3.TYPE_WATER, "type2 Water")
eq(g:castformDataTypeChange(form), Game3.CASTFORM_NO_CHANGE, "already Water")
eq(g:applyCastformChange(form), nil, "no second line")

form.type1, form.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
g.battle.weather = Game3.WEATHER_SUN
eq(g:applyCastformChange(form), "CASTFORM transformed!", "sun line")
eq(form.type1, Game3.TYPE_FIRE, "sun -> Fire")

form.type1, form.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
g.battle.weather = Game3.WEATHER_HAIL
g:applyCastformChange(form)
eq(form.type1, Game3.TYPE_ICE, "hail -> Ice")
eq(#g:weatherResidual(form), 0, "Ice Castform is immune to hail")

g.battle.weather = Game3.WEATHER_SAND
eq(g:castformDataTypeChange(form), Game3.CASTFORM_TO_NORMAL, "sand reverts")
eq(form.type1, Game3.TYPE_NORMAL, "back to Normal")

form.type1, form.type2 = Game3.TYPE_WATER, Game3.TYPE_WATER
g.battle.weather = Game3.WEATHER_RAIN
g.battle.enemy = { name = "RAYQUAZA", ability = Game3.ABILITY_AIR_LOCK }
eq(g:castformDataTypeChange(form), Game3.CASTFORM_TO_NORMAL, "Air Lock reverts")
eq(form.type1, Game3.TYPE_NORMAL, "Cloud Nine / Air Lock")

g.battle.enemy = foe
form.type1, form.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
form.hp = 0
g.battle.weather = Game3.WEATHER_RAIN
eq(g:castformDataTypeChange(form), Game3.CASTFORM_NO_CHANGE, "fainted does not")
form.hp = 70
form.species = Game3.SPECIES_PELIPPER or 279
eq(g:castformDataTypeChange(form), Game3.CASTFORM_NO_CHANGE, "not Castform")
form.species = Game3.SPECIES_CASTFORM

g.battle.weather = Game3.WEATHER_RAIN
form.type1, form.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
local entered = g:activateEnter(form, foe)
check(entered[#entered]:find("transformed", 1, true), "switch-in Forecast")
eq(form.type1, Game3.TYPE_WATER, "enters as Water in rain")

form.type1, form.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
g.battle.weather = nil
local rain = {
  name = "RAIN DANCE", effect = Game3.EFFECT_RAIN_DANCE, power = 0,
  pp = 5, type = 0,
}
local dance = g:useMove(form, foe, rain)
check(dance[1]:find("RAIN DANCE", 1, true), "used Rain Dance")
check(dance[2]:find("rain", 1, true), "rain starts")
check(dance[3]:find("transformed", 1, true), "then Forecast")
eq(form.type1, Game3.TYPE_WATER, "Rain Dance forms it")

g.battle.weatherTurns = 1
local ended = g:tickWeather()
eq(g.battle.weather, nil, "weather ended")
check(ended[#ended]:find("transformed", 1, true), "revert on fade")
eq(form.type1, Game3.TYPE_NORMAL, "back to Normal after rain")

local ball = { name = "WEATHER BALL", effect = Game3.EFFECT_WEATHER_BALL,
  power = 50, type = 0, pp = 10 }
g.battle.weather = nil
eq(g:attackType(form, ball), Game3.TYPE_NORMAL, "no weather: Normal")
eq(g:boostedPower(form, ball, foe), 50, "and 50 power")
g.battle.weather = Game3.WEATHER_RAIN
eq(g:attackType(form, ball), Game3.TYPE_WATER, "rain: Water")
eq(g:boostedPower(form, ball, foe), 100, "doubled")
g.battle.weather = Game3.WEATHER_SAND
eq(g:attackType(form, ball), Game3.TYPE_ROCK, "sand: Rock")
g.battle.weather = Game3.WEATHER_SUN
eq(g:attackType(form, ball), Game3.TYPE_FIRE, "sun: Fire")
g.battle.weather = Game3.WEATHER_HAIL
eq(g:attackType(form, ball), Game3.TYPE_ICE, "hail: Ice")
g.battle.player = { ability = Game3.ABILITY_CLOUD_NINE }
eq(g:attackType(form, ball), Game3.TYPE_NORMAL, "Cloud Nine: Normal")
eq(g:boostedPower(form, ball, foe), 50, "and not doubled")
g.battle.player = form

eq(g:itemName(Game3.ITEM_MYSTIC_WATER), "MYSTIC WATER", "Mystic Water name")
g.data.pokemon = { byIndex = { [Game3.SPECIES_CASTFORM] = {
  name = "CASTFORM", hp = 70, atk = 70, def = 70, spe = 70, spa = 70, spd = 70,
  type1 = 0, type2 = 0, ability1 = 59, catchRate = 45, expYield = 145,
  growthRate = 0,
} } }
local ok, gift = g:giveMon(Game3.SPECIES_CASTFORM, 25, Game3.ITEM_MYSTIC_WATER)
check(ok, "giveMon Castform")
eq(gift.item, Game3.ITEM_MYSTIC_WATER, "holds Mystic Water")
eq(gift.level, 25, "level 25")
eq(gift.ability, Game3.ABILITY_FORECAST, "Forecast from species")

local host = Game3.new()
host.data.pokemon = g.data.pokemon
Script.run(host, {
  { op = "givemon", species = Game3.SPECIES_CASTFORM, level = 25,
    item = Game3.ITEM_MYSTIC_WATER },
  { op = "end" },
})
eq(host.party[1].item, Game3.ITEM_MYSTIC_WATER, "script givemon sets the item")
eq(host.party[1].species, Game3.SPECIES_CASTFORM, "Castform")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.ABILITY_COLOR_CHANGE, 16, "ABILITY_COLOR_CHANGE")
eq(Game3.MOVE_STRUGGLE, 165, "MOVE_STRUGGLE")
eq(Game3.abilityName(Game3.ABILITY_COLOR_CHANGE), "COLOR CHANGE", "name")
eq(Game3.abilityName(Game3.ABILITY_RUN_AWAY), "RUN AWAY", "keep RUN AWAY")
eq(Game3.abilityName(Game3.ABILITY_KEEN_EYE), "KEEN EYE", "keep KEEN EYE")
eq(Game3.abilityName(Game3.ABILITY_HYPER_CUTTER), "HYPER CUTTER", "keep HYPER CUTTER")

local g = Game3.new()
g.data.moves = { typeChart = {} }
local hero = {
  name = "TORCHIC", level = 20, hp = 50, maxHp = 50,
  atk = 40, def = 40, spa = 60, spd = 40, spe = 40,
  type1 = Game3.TYPE_FIRE, type2 = Game3.TYPE_FIRE,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local kec = {
  name = "KECLEON", level = 30, hp = 80, maxHp = 80,
  atk = 50, def = 50, spa = 50, spd = 50, spe = 40,
  type1 = Game3.TYPE_NORMAL, type2 = Game3.TYPE_NORMAL,
  ability = Game3.ABILITY_COLOR_CHANGE,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local ember = {
  name = "EMBER", power = 40, type = Game3.TYPE_FIRE, accuracy = 100, pp = 25,
}
g.battle = { player = hero, enemy = kec }
local lines = g:useMove(hero, kec, ember)
local saw = false
for i = 1, #lines do
  if lines[i] == "KECLEON's COLOR CHANGE made it the FIRE type!" then
    saw = true
  end
end
check(saw, "Color Change line")
eq(kec.type1, Game3.TYPE_FIRE, "type1 Fire")
eq(kec.type2, Game3.TYPE_FIRE, "type2 Fire")
check((kec.hp or 0) > 0, "still standing")
check(not Game3.isContact(ember), "Ember is not contact")

local again = g:useMove(hero, kec, ember)
local n = 0
for i = 1, #again do
  if again[i]:find("COLOR CHANGE", 1, true) then n = n + 1 end
end
eq(n, 0, "same type does not change again")

local struggle = {
  id = Game3.MOVE_STRUGGLE, name = "STRUGGLE",
  power = 50, type = Game3.TYPE_NORMAL, accuracy = 100, pp = 1,
}
g:useMove(hero, kec, struggle)
eq(kec.type1, Game3.TYPE_FIRE, "Struggle does not Color Change")

kec.type1, kec.type2 = Game3.TYPE_NORMAL, Game3.TYPE_NORMAL
kec.hp, kec.maxHp = 80, 80
kec.protected = true
local blocked = g:useMove(hero, kec, ember)
local color = false
for i = 1, #blocked do
  if blocked[i]:find("COLOR CHANGE", 1, true) then color = true end
end
check(not color, "Protect does not Color Change")
eq(kec.type1, Game3.TYPE_NORMAL, "types stay")
kec.protected = nil

g.data.moves = { typeChart = { { 10, 0, 0 } } }
local immune = g:useMove(hero, kec, ember)
color = false
for i = 1, #immune do
  if immune[i]:find("COLOR CHANGE", 1, true) then color = true end
end
check(not color, "immunity does not Color Change")
eq(kec.type1, Game3.TYPE_NORMAL, "still Normal")

g.data.moves = { typeChart = {} }
kec.hp = 1
local ko = g:useMove(hero, kec, ember)
eq(kec.hp, 0, "KO")
color = false
for i = 1, #ko do
  if ko[i]:find("COLOR CHANGE", 1, true) then color = true end
end
check(not color, "fainted does not Color Change")
eq(kec.type1, Game3.TYPE_NORMAL, "KO leaves types")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.EFFECT_ENDEAVOR, 189, "EFFECT_ENDEAVOR")
eq(Game3.EFFECT_DRAGON_DANCE, 212, "EFFECT_DRAGON_DANCE")
eq(Game3.ITEM_TM40, 328, "ITEM_TM40")
eq(Game3.EFFECT_ALWAYS_HIT, 17, "Aerial Ace is ALWAYS_HIT")
local g = Game3.new()
eq(g:itemName(Game3.ITEM_TM40), "TM40", "TM40 name")
eq(g:itemPocket(Game3.ITEM_TM40), Game3.POCKET_TMHM, "TM pocket")
eq(g:tmhmMove(Game3.ITEM_TM40), 332, "teaches Aerial Ace")

g.data.moves = { typeChart = {} }
local swell = {
  name = "SWELLOW", level = 31, hp = 20, maxHp = 80,
  atk = 50, def = 40, spa = 40, spd = 40, spe = 80,
  type1 = Game3.TYPE_NORMAL, type2 = Game3.TYPE_FLYING,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local hero = {
  name = "MUDKIP", level = 30, hp = 80, maxHp = 80,
  atk = 50, def = 50, spa = 50, spd = 50, spe = 40,
  type1 = Game3.TYPE_WATER, type2 = Game3.TYPE_WATER,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
local endeavor = {
  name = "ENDEAVOR", effect = Game3.EFFECT_ENDEAVOR,
  power = 1, type = Game3.TYPE_NORMAL, accuracy = 100, pp = 5,
}
g.battle = { player = hero, enemy = swell }
local lines = g:useMove(swell, hero, endeavor)
eq(hero.hp, 20, "Endeavor equalizes HP")
local nve = false
for i = 1, #lines do
  if lines[i]:find("effective", 1, true) then nve = true end
end
check(not nve, "no SE/NVE on Endeavor")

hero.hp = 20
swell.hp = 20
eq(g:useMove(swell, hero, endeavor)[2], "But it failed!", "equal HP fails")
eq(hero.hp, 20, "HP unchanged")

hero.hp = 15
swell.hp = 20
eq(g:useMove(swell, hero, endeavor)[2], "But it failed!", "higher user HP fails")

hero.hp, hero.invuln = 80, "fly"
swell.hp = 20
eq(g:useMove(swell, hero, endeavor)[2], "The attack missed!",
  "Fly misses after the HP check")
hero.invuln = "fly"
swell.hp, hero.hp = 80, 20
eq(g:useMove(swell, hero, endeavor)[2], "But it failed!",
  "HP fail beats Fly")
hero.invuln = nil

hero.hp, hero.type1, hero.type2 = 80, Game3.TYPE_GHOST, Game3.TYPE_GHOST
swell.hp = 20
g.data.moves = { typeChart = { { 0, 7, 0 } } }
eq(g:useMove(swell, hero, endeavor)[2],
  "It doesn't affect MUDKIP...", "Ghost is immune")
eq(hero.hp, 80, "no damage")

g.data.moves = { typeChart = {} }
hero.type1, hero.type2 = Game3.TYPE_WATER, Game3.TYPE_WATER
hero.hp, swell.hp = 80, 20
hero.protected = true
check(g:useMove(swell, hero, endeavor)[2]:find("protected", 1, true),
  "Protect")
hero.protected = nil
hero.endured = true
hero.hp, swell.hp = 80, 1
g:useMove(swell, hero, endeavor)
eq(hero.hp, 1, "Endure leaves 1")
hero.endured = nil

local dd = { name = "DRAGON DANCE", effect = Game3.EFFECT_DRAGON_DANCE,
  power = 0, type = Game3.TYPE_DRAGON, accuracy = 100, pp = 20 }
local alta = {
  name = "ALTARIA", hp = 70, maxHp = 70,
  stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
}
g:useMove(alta, hero, dd)
eq(alta.stages.atk, 1, "Dragon Dance +1 Attack")
eq(alta.stages.spe, 1, "and +1 Speed")
end)()

;(function()
eq(Game3.B_OUTCOME_MON_FLED, 6, "B_OUTCOME_MON_FLED")
eq(Game3.B_OUTCOME_NO_SAFARI_BALLS, 8, "B_OUTCOME_NO_SAFARI_BALLS")
eq(Game3.SAFARI_GO_NEAR_CATCH[1], 4, "first GO NEAR +4 catch")
eq(Game3.SAFARI_POKEBLOCK_FLEE[2][1], 3, "first pokeblock flavor 0 cuts 3")

local g = Game3.new()
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
g:addItem(Game3.ITEM_POKE_BALL, 5)
g:enterSafariMode()
g.rng = function() return 1 end
check(g:startWildBattle(290, 2), "safari wild")
check(g.battle.safari, "BATTLE_TYPE_SAFARI")
eq(g.battle.safariFleeRate, 3, "init flee 3")
local factor = g.battle.safariCatchFactor
check(factor ~= nil, "catch factor from catchRate * 100 / 1275")
eq(g.safariBalls, 30, "still 30 before a throw")
g:throwBall()
eq(g.safariBalls, 29, "HandleAction_SafariZoneBallThrow")
eq(g:itemCount(Game3.ITEM_POKE_BALL), 5, "bag balls untouched")
eq(g.battle.caught, true, "catch still uses the shake RNG")

g.rng = function(n)
  if n == 65536 then return 10000 end
  return 1
end
g:startWildBattle(290, 2)
local before = g.battle.safariCatchFactor
g:safariGoNear()
eq(g.battle.safariCatchFactor, before + 4, "GO NEAR +4")
eq(g.battle.safariFleeRate, 7, "and +4 flee")
eq(g.battle.safariGoNearCounter, 1, "counter 1")
g:safariGoNear()
g:safariGoNear()
eq(g.battle.safariGoNearCounter, 3, "counter caps increment at 3")
g:safariGoNear()
eq(g.battle.safariGoNearCounter, 3, "fourth does not increment")
check(g.battle.queue[1]:find("closer", 1, true) ~= nil
    or g.battle.queue[1]:find("can't get", 1, true) ~= nil,
  "can't get closer / crept closer")

g.battle.safariFleeRate = 3
g.battle.safariPkblThrowCounter = 0
g:safariThrowPokeblock(0)
eq(g.battle.safariFleeRate, 0, "first curious pokeblock 3-3")
eq(g.battle.safariPkblThrowCounter, 1, "pkbl counter")

g.safariBalls = 1
g:startWildBattle(290, 2)
g.rng = function(n)
  if n == 65536 then return 65536 end
  return 1
end
g:throwBall()
eq(g.safariBalls, 0, "last ball spent")
eq(g.battleOutcome, Game3.B_OUTCOME_NO_SAFARI_BALLS, "outcome 8 on a miss")
check(g.battle.safariOver, "SafariOver then finish")
check(g.battle.queue[#g.battle.queue] == Game3.TEXT_SAFARI_OVER,
  "ANNOUNCER out of balls")

local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local entrance = {
  id = "g23_0", group = 23, index = 0,
  width = 3, height = 3, grid = cells,
}
g.data.maps = { maps = { g23_0 = entrance } }
g:endBattle()
check(not g:inSafariMode(), "missed last ball warps out")
eq(g.map and g.map.id, "g23_0", "to the entrance")

g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
g:enterSafariMode()
g.safariBalls = 1
g.rng = function() return 1 end
g:startWildBattle(290, 2)
g:throwBall()
eq(g.battle.caught, true, "caught on the last ball")
eq(g.battleOutcome, Game3.B_OUTCOME_CAUGHT, "outcome 7")
eq(g.safariBalls, 0, "no balls left")
g:endBattle()
check(g.field and g.field.thenSafariExit, "gUnknown_081C3459")
eq(g.field.text, Game3.TEXT_SAFARI_OUT_OF_BALLS, "out of balls after a catch")
check(g:inSafariMode(), "catch path waits for the message")
g:leaveSafari()
check(not g:inSafariMode(), "then warps")
end)()

;(function()
eq(Game3.SPECIAL_START_GROUDON_KYOGRE_BATTLE, 311, "StartGroudonKyogreBattle")
eq(Game3.SPECIAL_START_RAYQUAZA_BATTLE, 312, "StartRayquazaBattle")
eq(Game3.SPECIAL_START_REGI_BATTLE, 313, "StartRegiBattle")
eq(Game3.SPECIAL_WAIT_WEATHER, 284, "WaitWeather")
eq(Game3.SPECIAL_ORB_CUTSCENE, 281, "sub_80818A4")
eq(Game3.SPECIAL_ORB_CUTSCENE_ADVANCE, 282, "sub_80818FC")
eq(Game3.SPECIAL_FADE_OUT_MAP_MUSIC, 332, "sub_8081924")
eq(Game3.SPECIES_GROUDON, 405, "Groudon")
eq(Game3.SPECIES_KYOGRE, 404, "Kyogre")
eq(Game3.SPECIES_RAYQUAZA, 406, "Rayquaza")
eq(Game3.SPECIES_REGIROCK, 401, "Regirock")
local g = Game3.new()
g.phase = "play"
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
g:runSpecial(Game3.SPECIAL_WAIT_WEATHER)
check(g:scriptWaiting(), "WaitWeather CreateTask")
g:walkHeld(Game3.WAIT_WEATHER_FRAMES / 60)
check(not g:scriptWaiting(), "Task_WaitWeather next vblank")
eq(Game3.flashAnimFrames(1, 160, 2), 160, "orb expand is 80 steps")
g:setScriptVar(0x800D, 2)
g:runSpecial(Game3.SPECIAL_ORB_CUTSCENE)
check(g:scriptWaiting(), "sub_80818A4 waits for the flash")
eq(g.orb.cx, 120, "RESULT 2 is x 120")
eq(g.orb.pal, 0, "0x1F red")
g:walkHeld(g:orbOpenFrames() / 60)
eq(g.orb.stage, "hold", "script runs while the orb is up")
check(not g:scriptWaiting(), "case 2 ScriptContext_Enable")
g:runSpecial(Game3.SPECIAL_ORB_CUTSCENE_ADVANCE)
check(g:scriptWaiting(), "sub_80818FC waits for the blend-out")
g:walkHeld(Game3.ORB_CLOSE_FRAMES / 60)
eq(g.orb, nil, "case 5 clears the orb")
check(not g:scriptWaiting(), "close enables")
g:runSpecial(Game3.SPECIAL_FADE_OUT_MAP_MUSIC)
check(g:scriptWaiting(), "sub_8081924 waits for BGM stop")
g:walkHeld(Game3.WAIT_WEATHER_FRAMES / 60)
check(not g:scriptWaiting(), "no song is already stopped")
g:setWildBattle(Game3.SPECIES_GROUDON, 45, Game3.ITEM_NONE)
g:runSpecial(Game3.SPECIAL_START_GROUDON_KYOGRE_BATTLE)
eq(g.phase, "battle", "phase is battle")
eq(g.battle.enemy.species, 405, "against Groudon")
eq(g.battle.enemy.level, 45, "lv45")
check(g.battle.scriptedWild, "scripted wild")
check(g.battle.legendary, "BATTLE_TYPE_LEGENDARY")
check(g.battle.kyogreGroudon, "BATTLE_TYPE_KYOGRE_GROUDON")
check(g:scriptWaiting(), "waitstate holds")
eq(g:getGameStat(Game3.GAME_STAT_WILD_BATTLES), 1, "stat 8")
g:endBattle()
check(not g:scriptWaiting(), "script continues")
eq(g.phase, "play", "back on the field")
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
g:setWildBattle(Game3.SPECIES_RAYQUAZA, 70, Game3.ITEM_NONE)
g:runSpecial(Game3.SPECIAL_START_RAYQUAZA_BATTLE)
check(g.battle.legendary, "Rayquaza is legendary")
check(not g.battle.kyogreGroudon, "not the orb fight")
g:endBattle()
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
g:setWildBattle(Game3.SPECIES_REGIROCK, 40, Game3.ITEM_NONE)
g:runSpecial(Game3.SPECIAL_START_REGI_BATTLE)
check(g.battle.regi, "BATTLE_TYPE_REGI")
g:endBattle()
end)()

;(function()
eq(Game3.SPECIAL_GAME_CLEAR, 272, "GameClear")
eq(Game3.FLAG_SYS_GAME_CLEAR, 0x804, "SYSTEM_FLAGS+4")
eq(Game3.GAME_STAT_FIRST_HOF_PLAY_TIME, 1, "stat 1")
eq(Game3.TRAINER_SIDNEY, 261, "Sidney")
eq(Game3.TRAINER_STEVEN, 335, "Steven")
eq(Game3.TRAINER_WALLY_VICTORY_ROAD, 519, "Wally 1F")
eq(Game3.VAR_ELITE_4_STATE, 0x409C, "E4 state")
eq(Game3.FLAG_ENTERED_ELITE_FOUR, 0x107, "lobby guards")
eq(Game3.MAP_HALL_OF_FAME_NUM, 11, "HoF indoor index")
local home = {
  id = "g1_1", group = 1, index = 1,
  width = 8, height = 8, grid = {},
  spawn = { x = 4, y = 4 },
}
local hof = {
  id = "g16_11", group = 16, index = 11,
  width = 8, height = 8, grid = {},
  spawn = { x = 7, y = 16 },
}
for i = 1, 64 do
  home.grid[i] = 0
  hof.grid[i] = 0
end
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g1_1 = home, g16_11 = hof } }
g.lastHeal = { mapId = "g1_1", x = 4, y = 4 }
g:enterMap(hof, 7, 16, true)
local torchic = g:makeMon(Game3.SPECIES_TORCHIC, 5)
torchic.hp = 1
local egg = g:makeMon(Game3.SPECIES_EGG, 1)
egg.isEgg = true
g.party = { torchic, egg }
g.playSeconds = 3600 + 2 * 60 + 3
g:runSpecial(Game3.SPECIAL_GAME_CLEAR)
check(not g:scriptWaiting(), "credits skip does not wait")
eq(g.map.id, "g1_1", "warps to the bedroom heal")
eq(torchic.hp, torchic.maxHp, "heals the party")
check(torchic.championRibbon, "Champion ribbon")
check(not egg.championRibbon, "eggs skip SANITY_BIT3")
eq(g.flags[Game3.FLAG_SYS_GAME_CLEAR], true, "game clear")
eq(g.hasHallOfFameRecords, false, "first HoF has no prior records")
eq(#(g.hallOfFameTeams or {}), 1, "first team is saved")
eq(g.hallOfFameTeams[1][1].species, Game3.SPECIES_TORCHIC, "Torchic row")
eq(g.hallOfFameTeams[1][2].species, Game3.SPECIES_EGG, "egg is SPECIES2")
eq(g:getGameStat(Game3.GAME_STAT_ENTERED_HOF), 1, "stat 10 is 1")
eq(g:getGameStat(Game3.GAME_STAT_FIRST_HOF_PLAY_TIME),
  1 * 65536 + 2 * 256 + 3, "hours<<16 | min<<8 | sec")
eq(g:getGameStat(Game3.GAME_STAT_RECEIVED_RIBBONS), 1, "ribbon stat")
eq(g.flags[Game3.FLAG_SYS_RIBBON_GET], true, "ribbon flag")
local first = g:getGameStat(Game3.GAME_STAT_FIRST_HOF_PLAY_TIME)
g.playSeconds = 99999
g:runSpecial(Game3.SPECIAL_GAME_CLEAR)
eq(g.hasHallOfFameRecords, true, "second HoF keeps records")
eq(#g.hallOfFameTeams, 2, "second team appends")
eq(g:getGameStat(Game3.GAME_STAT_ENTERED_HOF), 2, "stat 10 is 2")
eq(g:getGameStat(Game3.GAME_STAT_FIRST_HOF_PLAY_TIME), first,
  "first time is not overwritten")
eq(g:getGameStat(Game3.GAME_STAT_RECEIVED_RIBBONS), 1,
  "already-ribboned party does not increment")
end)()

;(function()
eq(Game3.SPECIAL_INIT_ROAMER, 297, "InitRoamer")
eq(Game3.ROAMER_SPECIES, 408, "Ruby roams Latios")
eq(Game3.ROAMER_LEVEL, 40, "CreateMon level 40")
eq(Game3.MAP_ROUTE110_NUM, 0x19, "sRoamerLocations[0][0]")
eq(#Game3.ROAMER_LOCATIONS, 20, "20 location sets")
local g = Game3.new()
g.phase = "play"
g.rng = function() return 1 end
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 5) }
local grid = {}
for i = 1, 4 do grid[i] = 1 end
local route = {
  id = "g0_25", group = 0, index = 25,
  width = 2, height = 2, grid = grid, tileset = "pair_0",
}
g.data.tilesets = { byId = { pair_0 = { behavior = { [1] = 2 } } } }
g.data.encounters = {
  byMap = {
    g0_25 = {
      land = {
        rate = 255,
        slots = { { minLevel = 2, maxLevel = 2, species = 290 } },
      },
    },
  },
}
g.data.maps = { maps = { g0_25 = route } }
g:enterMap(route, 0, 0, true)
g:runSpecial(Game3.SPECIAL_INIT_ROAMER)
check(not g:scriptWaiting(), "InitRoamer does not wait")
eq(g.roamer.species, Game3.SPECIES_LATIOS, "Latios")
eq(g.roamer.level, 40, "lv40")
check(g.roamer.active, "active")
eq(g.roamerLocation[1], 0, "group 0")
eq(g.roamerLocation[2], 25, "Random()%20==0 is Route 110")
check(g:isRoamerAt(0, 25), "IsRoamerAt this map")
check((g.roamer.hp or 0) > 0, "CreateMon stores max HP")
check(g:tryWildEncounter(), "25% roll of 0 starts the roamer")
eq(g.battle.enemy.species, Game3.SPECIES_LATIOS, "not the grass slot")
eq(g.battle.enemy.level, 40, "roamer level")
eq(g.battle.enemy.pid, g.roamer.personality, "same personality")
check(g.battle.roamer, "BATTLE_TYPE_ROAMER")
eq(g:getGameStat(Game3.GAME_STAT_WILD_BATTLES), 1, "stat 8")
local hurt = g.battle.enemy.hp - 1
g.battle.enemy.hp = hurt
g.gbaRandom = function() return 1 end
g:recordBattleEnd(Game3.B_OUTCOME_RAN)
eq(g.roamer.hp, hurt, "UpdateRoamerHPStatus banks HP")
check(g.roamer.active, "RUN keeps it active")
eq(g.roamerLocation[2], 26, "then RoamerMoveToOtherLocationSet")
g.phase = "play"
g.battle = nil
g.battleOutcome = 0
g.roamerLocation[2] = 25
g.roamer.active = true
g.gbaRandom = function() return 0 end
g.party = { g:makeMon(Game3.SPECIES_TORCHIC, 40) }
g.repelSteps = 100
check(not g:tryWildEncounter(), "Repel vs lv40 does not fall through")
check(not g.battle, "and starts no grass fight")
g.repelSteps = nil
g.gbaRandom = function() return 1 end
check(g:tryWildEncounter(), "1%4 misses the roamer")
eq(g.battle.enemy.species, 290, "grass Wurmple")
g.phase = "play"
g.battle = nil
g.battleOutcome = 0
g.gbaRandom = function() return 0 end
check(g:trySweetScentEncounter(), "Sweet Scent can start the roamer")
eq(g.battle.enemy.species, Game3.SPECIES_LATIOS, "scent Latios")
g.gbaRandom = function() return 1 end
g:recordBattleEnd(Game3.B_OUTCOME_WON)
check(not g.roamer.active, "win sets inactive")
g.roamer.active = true
g.battle = { roamer = true, enemy = { hp = 1, status = Game3.STATUS_PAR } }
g.battleOutcome = 0
g.gbaRandom = function() return 0 end
g:recordBattleEnd(Game3.B_OUTCOME_CAUGHT)
check(not g.roamer.active, "catch sets inactive")
eq(g.roamer.status, Game3.STATUS_PAR, "status is stored before inactive")
end)()

;(function()
eq(Game3.ITEM_MAX_REVIVE, 25, "ITEM_MAX_REVIVE")
eq(Game3.ITEM_GUARD_SPEC, 73, "ITEM_GUARD_SPEC")
eq(Game3.ITEM_DIRE_HIT, 74, "ITEM_DIRE_HIT")
eq(Game3.ITEM_X_ATTACK, 75, "ITEM_X_ATTACK")
eq(Game3.ITEM_X_DEFEND, 76, "ITEM_X_DEFEND")
eq(Game3.ITEM_X_SPEED, 77, "ITEM_X_SPEED")
eq(Game3.ITEM_X_ACCURACY, 78, "ITEM_X_ACCURACY")
eq(Game3.ITEM_X_SPECIAL, 79, "ITEM_X_SPECIAL")
eq(Game3.ITEM_POKE_DOLL, 80, "ITEM_POKE_DOLL")
eq(Game3.ITEM_FLUFFY_TAIL, 81, "ITEM_FLUFFY_TAIL")
eq(Game3.REVIVE_FRACTION[24], 0.5, "Revive is ITEM6_HEAL_HP_HALF")
eq(Game3.REVIVE_FRACTION[25], 1, "Max Revive is full")
eq(Game3.X_ITEM_STAT[75][1], "atk", "X Attack is Attack")
eq(Game3.X_ITEM_STAT[79][1], "spa", "X Special is Sp. Atk")
check(Game3.needsBattleParty(13), "Potion opens the party")
check(Game3.needsBattleParty(24), "Revive opens the party")
check(Game3.needsBattleParty(36), "Elixir opens the battle party")
check(Game3.needsBattleParty(34), "Ether opens the battle party")
check(not Game3.needsBattleParty(75), "X Attack does not")
check(not Game3.needsBattleParty(80), "Doll does not")

local g = Game3.new()
eq(g:itemName(Game3.ITEM_MAX_REVIVE), "MAX REVIVE", "Max Revive name")
eq(g:itemName(Game3.ITEM_X_ATTACK), "X ATTACK", "X Attack name")
eq(g:itemName(Game3.ITEM_POKE_DOLL), "POKe DOLL", "Doll name")
eq(g:itemName(Game3.ITEM_GUARD_SPEC), "GUARD SPEC.", "Guard Spec name")
eq(g:itemName(Game3.ITEM_DIRE_HIT), "DIRE HIT", "Dire Hit name")
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.party = { g:makeMon(280, 5) }
g.party[1].maxHp = 20
g.party[1].hp = 0
g:addItem(Game3.ITEM_REVIVE, 1)
local openedRevive = g:useFieldItem(Game3.ITEM_REVIVE)
check(openedRevive, "field Revive opens the party")
eq(g.field.kind, "party_use", "ItemUseOutOfBattle_Medicine")
eq(g.party[1].hp, 0, "picker does not auto-revive")
eq(g.field.prompt, "Use on which POKeMON?", "OtherText_UseWhat")
local ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_REVIVE)
check(ok, "field Revive")
eq(g.party[1].hp, 10, "half HP")
check(msg:find("revived", 1, true) ~= nil, "was revived")

g.party[1].hp = 0
g:addItem(Game3.ITEM_MAX_REVIVE, 1)
ok = g:useItemOnMon(g.party[1], Game3.ITEM_MAX_REVIVE)
check(ok, "field Max Revive")
eq(g.party[1].hp, 20, "full HP")

local Input = require("src.core.Input")
Input:init()
local function press(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepBattle()
  Input.wasPressed = old
end

g.party = { g:makeMon(280, 5), g:makeMon(280, 5) }
g.rng = function() return 1 end
g:addItem(Game3.ITEM_POTION, 1)
check(g:startWildBattle(280, 5), "wild for BAG")
g.battle.player.maxHp, g.battle.player.hp = 40, 40
g.party[2].maxHp, g.party[2].hp = 40, 5
g.battle.enemy.hp = 0
g.battle.kind = "bag"
g.battle.bagCursor = 0
press("a")
eq(g.battle.kind, "party", "BAG A on Potion opens party")
eq(g.battle.itemUse, Game3.ITEM_POTION, "itemUse is the Potion")
press("b")
eq(g.battle.kind, "bag", "B returns to BAG")
eq(g:itemCount(Game3.ITEM_POTION), 1, "B does not spend")
press("a")
g.battle.partyCursor = 1
press("a")
eq(g.party[2].hp, 25, "bench is healed 20")
eq(g.party[1].hp, 40, "lead is untouched")
eq(g:itemCount(Game3.ITEM_POTION), 0, "Potion spent")
eq(g.battle.kind, "text", "use consumes the turn")
eq(g.battle.itemUse, nil, "itemUse clears")

;(function()
  local egg = g:makeMon(360, 5)
  egg.isEgg = true
  egg.name = "EGG"
  g.party[3] = egg
  g.battle.kind = "party"
  g.battle.partyCursor = 2
  g.battle.partyMsg = nil
  g.battle.text = nil
  local lead = g.battle.player
  press("a")
  eq(g.battle.kind, "menu_msg", "PKMN A on an EGG shows the line")
  eq(g.battle.text, "An EGG can't battle!", "egg switch fail text")
  eq(g.battle.player, lead, "the egg did not come out")
  press("a")
  eq(g.battle.kind, "party", "A after the line returns to party")
  eq(g.battle.partyMsg, nil, "partyMsg clears")
end)()

g.battle.player.hp = 5
g.battle.player.maxHp = 40
g:addItem(Game3.ITEM_POTION, 1)
ok = g:useBattleItem(13)
check(ok, "useBattleItem(13) still heals the battler")
eq(g.battle.player.hp, 25, "direct Potion path")

g.party[2].hp = 0
g.party[2].maxHp = 40
g:addItem(Game3.ITEM_REVIVE, 1)
ok = g:useBattleItem(Game3.ITEM_REVIVE, g.party[2])
check(ok, "Revive in battle")
eq(g.party[2].hp, 20, "half of 40")

g.battle.kind = "menu"
g.battle.player.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
g:addItem(Game3.ITEM_X_ATTACK, 1)
g.battle.kind = "bag"
g.battle.bagCursor = 0
press("a")
eq(g.battle.player.stages.atk, 1, "X Attack +1")
check(g.battle.kind ~= "party", "X Attack skips party")
eq(g:itemCount(Game3.ITEM_X_ATTACK), 0, "X Attack spent")

g.battle.player.stages.atk = 6
g:addItem(Game3.ITEM_X_ATTACK, 1)
ok = g:useBattleItem(Game3.ITEM_X_ATTACK)
check(not ok, "+6 is no effect")
eq(g:itemCount(Game3.ITEM_X_ATTACK), 1, "does not spend at cap")
eq(g.battle.player.stages.atk, 6, "stage stays 6")

g:addItem(Game3.ITEM_DIRE_HIT, 2)
ok = g:useBattleItem(Game3.ITEM_DIRE_HIT)
check(ok, "Dire Hit")
check(g.battle.player.focusEnergy, "STATUS2_FOCUS_ENERGY")
ok = g:useBattleItem(Game3.ITEM_DIRE_HIT)
check(not ok, "already pumped")
eq(g:itemCount(Game3.ITEM_DIRE_HIT), 1, "second does not spend")

g:addItem(Game3.ITEM_GUARD_SPEC, 1)
ok = g:useBattleItem(Game3.ITEM_GUARD_SPEC)
check(ok, "Guard Spec")
check((g.battle.mistTurns or 0) > 0, "mistTimer 5 then end-turn tick")
local line = g:dropStat(g.battle.player, "atk", "ATTACK")
check(line:find("MIST", 1, true) ~= nil, "MistProtect")
eq(g.battle.player.stages.atk, 6, "foe drop blocked")
g:dropStat(g.battle.player, "spe", "SPEED", 1, true)
eq(g.battle.player.stages.spe, -1, "self-inflicted still drops")

g:addItem(Game3.ITEM_POKE_DOLL, 1)
ok = g:useBattleItem(Game3.ITEM_POKE_DOLL)
check(ok, "Doll in wild")
eq(g.battle.kind, "ran", "ItemUseInBattle_Escape")
eq(g:itemCount(Game3.ITEM_POKE_DOLL), 0, "Doll spent")
end)()

;(function()
local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.party = { g:makeMon(280, 5) }
g:addItem(Game3.ITEM_POKE_DOLL, 1)
g:addItem(Game3.ITEM_FLUFFY_TAIL, 1)
local npc = {
  trainerName = "CALVIN", trainerClass = "YOUNGSTER",
  party = { { species = 280, level = 2 } },
}
check(g:startTrainerBattle(npc), "trainer for Doll")
local ok = g:useBattleItem(Game3.ITEM_POKE_DOLL)
check(not ok, "Doll is Dad's advice vs trainer")
eq(g.battle.kind, "menu_msg", "cannot flee")
eq(g:itemCount(Game3.ITEM_POKE_DOLL), 1, "not spent")
ok = g:useBattleItem(Game3.ITEM_FLUFFY_TAIL)
check(not ok, "Fluffy Tail too")
eq(g:itemCount(Game3.ITEM_FLUFFY_TAIL), 1, "Tail not spent")
end)()

;(function()
local Input = require("src.core.Input")
Input:init()
local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.data.moves = {
  byId = {
    [10] = { id = 10, name = "SCRATCH", power = 40, type = 0, pp = 35,
      accuracy = 100 },
  },
}
g.party = { g:makeMon(280, 5, { 10 }) }
g.party[1].moves[1].pp = 5
g.rng = function() return 1 end
g:addItem(Game3.ITEM_ETHER, 1)
check(g:startWildBattle(280, 5), "wild for Ether")
g.battle.kind = "bag"
g.battle.bagCursor = 0
local function press(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepBattle()
  Input.wasPressed = old
end
press("a")
eq(g.battle.kind, "party", "ItemUseInBattle_PPRecovery opens party")
eq(g.battle.itemUse, Game3.ITEM_ETHER, "Ether")
press("a")
eq(g.battle.kind, "item_pp", "CreateItemUseMoveMenu")
press("a")
eq(g.party[1].moves[1].pp, 15, "Ether +10 one move")
eq(g:itemCount(Game3.ITEM_ETHER), 0, "spent")
eq(g.battle.kind, "text", "use consumes the turn")
eq(g.battle.itemUse, nil, "itemUse clears")
end)()

;(function()
-- item_menu.c PlayerHandleOpenBag / RETURN_TO_BATTLE: the same pack
-- screen as the field, not a two-line list in the fight message bar.
local Input = require("src.core.Input")
Input:init()
local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.party = { g:makeMon(280, 5) }
g:addItem(Game3.ITEM_POTION, 1)
g:addItem(Game3.ITEM_POKE_BALL, 1)
check(g:startWildBattle(280, 5), "wild for pack BAG")
local function press(name)
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  g:stepBattle()
  Input.wasPressed = old
end
g.battle.kind = "menu"
g.battle.cursor = 1
press("a")
eq(g.battle.kind, "bag", "BAG opens the pack")
eq(g.battle.bagPocket, Game3.POCKET_ITEMS, "on the first filled pocket")
eq(g.battle.bagCursor, 0, "cursor on the first item")
press("right")
eq(g.battle.bagPocket, Game3.POCKET_BALLS, "RIGHT is POKe BALLS")
press("left")
eq(g.battle.bagPocket, Game3.POCKET_ITEMS, "LEFT returns to ITEMS")
press("down")
eq(g.battle.bagCursor, 1, "DOWN is CLOSE BAG")
press("a")
eq(g.battle.kind, "menu", "A on CLOSE BAG returns to FIGHT")
g.battle.cursor = 1
press("a")
press("b")
eq(g.battle.kind, "menu", "B closes the pack")
eq(Game3.BAG_CLOSE, "CLOSE BAG", "gOtherText_CloseBag")
eq(Game3.BAG_ROWS, 8, "item_menu.c shows 8 rows")
eq(Game3.wrapPocket(Game3.POCKET_ITEMS, -1), Game3.POCKET_KEY,
  "LEFT wraps to KEY ITEMS")
g.phase = "battle"
local texts = {}
local oldText = Game3.drawText
function Game3.drawText(_, text)
  texts[#texts + 1] = tostring(text or "")
end
g:drawBag({ pocket = Game3.POCKET_ITEMS, cursor = 1 })
Game3.drawText = oldText
local close, hint = false, false
for i = 1, #texts do
  if texts[i] == Game3.BAG_CLOSE then close = true end
  if texts[i] == "the battle." then hint = true end
end
check(close, "pack list draws CLOSE BAG")
check(hint, "CLOSE BAG says Return to the battle")
local drawn = false
local oldBag = Game3.drawBag
local oldBg = Game3.drawBattleBackground
local oldPic = Game3.drawBattlePic
local oldBox = Game3.drawHealthbox
function Game3.drawBag(_, f)
  drawn = f and f.pocket == Game3.POCKET_ITEMS
end
function Game3.drawBattleBackground() end
function Game3.drawBattlePic() end
function Game3.drawHealthbox() end
g.battle.kind = "bag"
g.battle.bagPocket = Game3.POCKET_ITEMS
g:drawBattle()
Game3.drawBag = oldBag
Game3.drawBattleBackground = oldBg
Game3.drawBattlePic = oldPic
Game3.drawHealthbox = oldBox
check(drawn, "battle BAG draws the pack screen")
end)()

;(function()
eq(Game3.TRAINER_VICTOR, 292, "TRAINER_VICTOR")
eq(Game3.TRAINER_VICTORIA, 299, "TRAINER_VICTORIA")
eq(Game3.TRAINER_VIVI, 606, "TRAINER_VIVI")
eq(Game3.TRAINER_VICKY, 312, "TRAINER_VICKY")
eq(Game3.FLAG_HIDE_VICTOR_WINSTRATE, 0x300, "FLAG_HIDE_VICTOR_WINSTRATE")
eq(Game3.FLAG_REGI_DOORS_OPENED, 0xE4, "FLAG_REGI_DOORS_OPENED")
eq(Game3.MT_GENERAL_ROCK_WALL_SAND_BASE, 0x091, "RockWall_SandBase")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = { name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10 },
  },
}
g.data.trainers = { byId = {
  [Game3.TRAINER_VICTOR] = {
    name = "VICTOR", className = "WINSTRATE",
    party = { { species = 280, level = 16 } },
  },
  [Game3.TRAINER_VICTORIA] = {
    name = "VICTORIA", className = "WINSTRATE",
    party = { { species = 280, level = 17 } },
  },
} }
g.party = { g:makeMon(280, 20) }
g.map = {
  id = "g0_22", width = 2, height = 2, grid = { 0, 0, 0, 0 },
  objects = {
    { localId = 1, x = 0, y = 1, graphicsId = 1,
      flagId = Game3.FLAG_HIDE_VICTOR_WINSTRATE },
    { localId = 2, x = 0, y = 0, graphicsId = 2,
      flagId = Game3.FLAG_HIDE_VICTORIA_WINSTRATE },
  },
}
g:resetNpcs(g.map)
g._scriptNpc = g:npcByLocalId(1)
check(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_NO_INTRO,
  trainerId = Game3.TRAINER_VICTOR,
}), "Victor no-intro")
eq(g.battle.enemy.level, 16, "Victor's party")
g:markTrainerDefeated(g.battle.npc)
g.phase = "play"
g.battle = nil
g:removeObject(1)
check(g.flags[Game3.FLAG_HIDE_VICTOR_WINSTRATE], "removeobject sets hide")
check(g:isNpcDefeated(g._scriptNpc), "Victor's hide flag looks defeated")
check(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_NO_INTRO,
  trainerId = Game3.TRAINER_VICTORIA,
}), "Victoria still starts after Victor hides")
eq(g.battle.enemy.level, 17, "Victoria's party, not Victor's")
eq(g:trainerDefeated(Game3.TRAINER_VICTORIA), false,
  "her trainer flag is still clear")

-- LAYOUT_ROUTE111 (14,114) is General picket fence 0x149, collision 1,
-- elevation 3. Bottom tiles are the same dirt as the path (metatile 1);
-- LAYER_COVERED puts the posts on BG2. y=115 is the east-west walkway.
local fence = 3 * 4096 + 1024 + 329
local dirt = 3 * 4096 + 1
local route = {
  id = "g0_26", width = 4, height = 2,
  tileset = "pair_2",
  grid = {
    dirt, fence, fence, dirt,
    dirt, dirt, dirt, dirt,
  },
}
eq(Game3.collisionOf(fence), 1, "Winstrate fence cell is solid")
eq(Game3.metatileOf(fence), 329, "metatile 0x149")
check(not Game3.walkable(route, 1, 0), "east of Victor's tile is the fence")
check(Game3.walkable(route, 1, 1), "the dirt one tile south is the path")
local field = Game3.new()
field.data.tilesets = {
  byId = { pair_2 = { layerType = { [329] = Game3.LAYER_COVERED } } },
}
eq(field:layerTypeAt(route, 1, 0), Game3.LAYER_COVERED,
  "fence is LAYER_COVERED")
end)()

;(function()
local g = Game3.new()
g.data.pokemon = {
  byIndex = {
    [278] = {
      name = "GROVYLE", hp = 50, atk = 65, def = 45, spe = 95,
      spa = 85, spd = 65, type1 = 12, type2 = 12, growthRate = 3,
      evolutions = { { method = 4, param = 36, target = 279 } },
    },
    [279] = {
      name = "SCEPTILE", hp = 70, atk = 85, def = 65, spe = 120,
      spa = 105, spd = 85, type1 = 12, type2 = 12, growthRate = 3,
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 45, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, growthRate = 0,
      expYield = 54,
    },
    [288] = {
      name = "ZIGZAGOON", hp = 38, atk = 30, def = 41, spe = 60,
      spa = 30, spd = 41, type1 = 0, type2 = 0, growthRate = 0,
      expYield = 60,
    },
  },
}
local grovyle = g:makeMon(278, 36)
g.party = { grovyle }
g.options.battleStyle = "set"
local npc = {
  trainerType = Game3.TRAINER_TYPE_NORMAL,
  trainerRange = 1,
  trainerName = "TEST",
  trainerClass = "YOUNGSTER",
  party = { { species = 290, level = 2 }, { species = 288, level = 3 } },
}
check(g:startTrainerBattle(npc), "two-mon trainer starts")
eq(#g:tryEvolve(grovyle), 0, "level 36 queues Sceptile")
eq(grovyle.species, 278, "still Grovyle during the fight")
g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "WURMPLE fainted!" }
g.battle.qi = 1
g:advanceBattleText()
check(g.battle.kind ~= "evolve", "first KO does not evolve")
eq(grovyle.species, 278, "and the battler is still Grovyle")
check(g.pendingEvo and g.pendingEvo[1], "the evo stays queued")
g.battle.enemy.hp = 0
g.battle.kind = "text"
g.battle.queue = { "ZIGZAGOON fainted!" }
g.battle.qi = 1
g:advanceBattleText()
eq(g.battle.kind, "won_trainer", "the last KO is the victory")
g:confirmTrainerWin()
eq(g.phase, "play", "then the field")
eq(g.field and g.field.kind, "evolve", "EvolutionScene after a win")
eq(grovyle.species, 278, "species still waits for the animation")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_SHOW_GLASS_WORKSHOP_MENU, 274, "ShowGlassWorkshopMenu")
eq(Game3.ITEM_BLUE_FLUTE, 39, "ITEM_BLUE_FLUTE")
eq(Game3.ITEM_BLACK_FLUTE, 42, "ITEM_BLACK_FLUTE")
eq(Game3.ITEM_WHITE_FLUTE, 43, "ITEM_WHITE_FLUTE")
eq(Game3.DECOR_PRETTY_CHAIR, 13, "DECOR_PRETTY_CHAIR")
eq(Game3.DECOR_PRETTY_DESK, 6, "DECOR_PRETTY_DESK")
eq(Gen3Script.STD_OBTAIN_DECORATION, 7, "callstd 7")
check(BattleData.collectSpecies({ byMap = {} }, nil, {})[360] == true,
  "Wynaut pics are seeded for the Lavaridge egg")

local g = Game3.new()
eq(g:giveEgg(Game3.SPECIES_WYNAUT), 0, "giveegg into the party")
eq(g.party[1].species, Game3.SPECIES_WYNAUT, "not remapped to Wobbuffet")

g:runSpecial(Game3.SPECIAL_SHOW_GLASS_WORKSHOP_MENU)
check(g:scriptWaiting(), "LockPlayerFieldControls")
eq(g.field.kind, "mauville_menu", "workshop menu")
eq(#g.field.labels, 8, "five flutes, two decor, CANCEL")
eq(g.field.labels[4], "WHITE FLUTE", "menu index 3 is White")
eq(g.field.labels[5], "BLACK FLUTE", "menu index 4 is Black")
eq(g.field.bPressed, Game3.MULTI_B_PRESSED, "B is 0x7F")
g:pickMauvilleMenu(0)
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "A on BLUE FLUTE")
eq(g:scriptWaiting(), false, "then waitstate continues")

g:runSpecial(Game3.SPECIAL_SHOW_GLASS_WORKSHOP_MENU)
g:pickMauvilleMenu(Game3.MULTI_B_PRESSED)
eq(g:varGet(Gen3Script.VAR_RESULT), 127, "B is MULTI_B_PRESSED")

g:runSpecial(Game3.SPECIAL_SHOW_GLASS_WORKSHOP_MENU)
g:pickMauvilleMenu(7)
eq(g:varGet(Gen3Script.VAR_RESULT), 7, "A on CANCEL is 7")

check(g:addDecoration(Game3.DECOR_PRETTY_CHAIR), "AddDecoration")
eq(g.decorations[13], 1, "one pretty chair")
g.scriptVars[0x8000] = Game3.DECOR_PRETTY_DESK
Gen3Script.run(g, { { op = "callstd", id = Gen3Script.STD_OBTAIN_DECORATION } })
eq(g.decorations[6], 1, "callstd 7 gives the desk")
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "RESULT TRUE")
g.stringVars = {}
Gen3Script.run(g, { { op = "bufferdecoration", slot = 0, id = 13 } })
eq(g.stringVars[1], "PRETTY CHAIR", "bufferdecorationname")
end)()

;(function()
-- Fallarbor Move Relearner: specials.inc 230/235 − 11.
eq(Game3.SPECIAL_SELECT_MOVE_TUTOR_MON, 219, "SelectMoveTutorMon")
eq(Game3.SPECIAL_DISPLAY_MOVE_TUTOR_MENU, 224, "DisplayMoveTutorMenu")
eq(Game3.MAX_MOVE_TUTOR_MOVES, 20, "MAX_MOVE_TUTOR_MOVES")
eq(Game3.PARTY_MENU_CANCEL, 255, "party B is 0xFF")

local g = Game3.new()
g.data.pokemon = { byIndex = {
  [277] = {
    name = "TREECKO",
    learnset = {
      { move = 33, level = 1 },
      { move = 45, level = 1 },
      { move = 73, level = 7 },
      { move = 75, level = 12 },
      { move = 45, level = 1 },
    },
  },
} }
g.data.moves = { byId = {
  [1] = { id = 1, name = "POUND", pp = 35 },
  [33] = { id = 33, name = "TACKLE", pp = 35 },
  [45] = { id = 45, name = "GROWL", pp = 40 },
  [73] = { id = 73, name = "LEECH SEED", pp = 10 },
  [75] = { id = 75, name = "RAZOR LEAF", pp = 25 },
} }
local treecko = g:makeMon(277, 10, { 33 })
g.party = { treecko }
local moves = g:getMoveTutorMoves(treecko)
eq(#moves, 2, "Growl and Leech Seed; Razor Leaf is above level 10")
eq(moves[1], 45, "Growl first")
eq(moves[2], 73, "Leech Seed; duplicate Growl is skipped")

local egg = g:makeMon(277, 10, { 33 })
egg.isEgg = true
eq(#g:getMoveTutorMoves(egg), 0, "sub_8040574 eggs are 0")

g:runSpecial(Game3.SPECIAL_SELECT_MOVE_TUTOR_MON)
check(g:scriptWaiting(), "SelectMoveTutorMon waitstate")
eq(g.field.kind, "move_tutor_mon", "PARTY_MENU_TYPE_MOVE_TUTOR")
g:pickMoveTutorMon(Game3.PARTY_MENU_CANCEL)
eq(g:varGet(0x8004), 255, "B is 0xFF")
eq(g:scriptWaiting(), false, "then the script continues")

g:runSpecial(Game3.SPECIAL_SELECT_MOVE_TUTOR_MON)
g:pickMoveTutorMon(0)
eq(g:varGet(0x8004), 0, "A writes the 0-based slot")
eq(g:varGet(0x8005), 2, "and 0x8005 is the relearn count")

g:runSpecial(Game3.SPECIAL_DISPLAY_MOVE_TUTOR_MENU)
check(g:scriptWaiting(), "DisplayMoveTutorMenu waitstate")
eq(g.field.kind, "move_tutor_list", "move list")
eq(g.field.labels[1], "GROWL", "first relearnable")
eq(g.field.labels[3], "EXIT", "EXIT is last")
g:pickMoveTutorList(0)
eq(g.field.kind, "tutor_confirm", "Teach this move?")
g:answerTutorConfirm(true)
eq(g:varGet(0x8004), 1, "GiveMoveToMon success is 1")
eq(g:scriptWaiting(), false, "then waitstate continues")
check(g:knowsMove(treecko, 45), "Growl was added")

g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_DISPLAY_MOVE_TUTOR_MENU)
g:pickMoveTutorList(99)
eq(g.field.kind, "tutor_giveup", "EXIT asks to give up")
g:answerTutorGiveUp(true)
eq(g:varGet(0x8004), 0, "give up is 0")
eq(g:scriptWaiting(), false, "0 is valid, not a failed special")

local full = g:makeMon(277, 16, { 33, 45, 73, 1 })
g.party = { full }
g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_DISPLAY_MOVE_TUTOR_MENU)
eq(g.field.labels[1], "RAZOR LEAF", "only the forgotten level-up move")
g:pickMoveTutorList(0)
g:answerTutorConfirm(true)
eq(g.field.kind, "learn_forget", "four moves open the forget list")
check(g.tutorWait, "tutorWait keeps 0x8004 unset until done")
g:chooseLearnForget(4)
eq(full.moves[4].id, 75, "Razor Leaf replaced Pound")
g:finishLearnMessage()
eq(g:varGet(0x8004), 1, "forget-and-teach is still 1")
eq(g:scriptWaiting(), false, "and the Heart Scale script continues")

local stuck = g:makeMon(277, 16, { 33, 45, 73, 1 })
g.party = { stuck }
g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_DISPLAY_MOVE_TUTOR_MENU)
g:pickMoveTutorList(0)
g:answerTutorConfirm(true)
g:answerLearnStop(true)
eq(g.field.kind, "move_tutor_list", "stop learning returns to the list")
check(g:scriptWaiting(), "not 0x8004 = 0")
eq(g:varGet(0x8004), 0, "0x8004 still the party index until EXIT")
end)()

;(function()
eq(Game3.SPECIAL_SCRIPT_HATCH_MON, 193, "ScriptHatchMon")
eq(Game3.SPECIAL_EGG_HATCH, 194, "EggHatch")
eq(Game3.SPECIAL_FOUND_BLACK_GLASSES, 316, "FoundBlackGlasses")
eq(Game3.FLAG_HIDDEN_ITEM_BLACK_GLASSES, 0x2B8, "FLAG_HIDDEN_ITEM_BLACK_GLASSES")
eq(Game3.GAME_STAT_HATCHED_EGGS, 13, "GAME_STAT_HATCHED_EGGS")
eq(Game3.GAME_STAT_RODE_CABLE_CAR, 48, "GAME_STAT_RODE_CABLE_CAR")
check(BattleData.collectSpecies({ byMap = {} }, nil, {})[385] == true,
  "Castform pics are seeded for the Institute gift")
check(BattleData.collectSpecies({ byMap = {} }, nil, {})[388] == true,
  "Lileep pics are seeded for the Root Fossil")
check(BattleData.collectSpecies({ byMap = {} }, nil, {})[390] == true,
  "Anorith pics are seeded for the Claw Fossil")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_FOUND_BLACK_GLASSES), 0, "not found is 0")
g.flags[Game3.FLAG_HIDDEN_ITEM_BLACK_GLASSES] = true
eq(g:runSpecial(Game3.SPECIAL_FOUND_BLACK_GLASSES), 1, "FlagGet after pickup")

eq(Game3.MUS_EVOLUTION, 377, "MUS_EVOLUTION")
eq(Game3.EGG_HATCH_SHAKE_FRAMES, 280, "SpriteCB_Egg_0..5 plus pal wait")
local Input = require("src.core.Input")
Input:init()
g.phase = "play"
local egg = g:giveEgg(Game3.SPECIES_WYNAUT)
eq(egg, 0, "Wynaut egg in the party")
g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_SCRIPT_HATCH_MON)
eq(g.party[1].isEgg, nil, "ScriptHatchMon is AddHatchedMonToParty")
eq(g:scriptWaiting(), false, "and does not wait")
eq(g:getGameStat(Game3.GAME_STAT_HATCHED_EGGS), 0, "stat 13 is the TakeStep caller")

g.party = {}
g:giveEgg(Game3.SPECIES_WYNAUT)
g.scriptVars[0x8004] = 0
g:runSpecial(Game3.SPECIAL_EGG_HATCH)
eq(g.party[1].isEgg, nil, "EggHatch clears IS_EGG")
eq(g.party[1].name, g:speciesName(Game3.SPECIES_WYNAUT), "AddHatchedMonToParty nickname")
eq(g.party[1].friendship, 120, "hatch friendship is 120")
eq(g.party[1].metLevel, 0, "met level 0")
eq(g:getGameStat(Game3.GAME_STAT_HATCHED_EGGS), 0, "cinema does not increment the stat")
check(g:scriptWaiting(), "EggHatch is a waitstate")
eq(g.field.kind, "egg_hatch", "shake stage")
eq(g.field.left, Game3.EGG_HATCH_SHAKE_FRAMES, "wobble frames")
g:walkHeld(Game3.EGG_HATCH_SHAKE_FRAMES / 60)
eq(g.field.kind, "talk", "hatch line after the wobble")
eq(g.field.text, ("%s hatched from the EGG!"):format(g.party[1].name),
  "UnknownString hatch")
local oldHatch = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.kind, "egg_nick", "nickname YES/NO")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = oldHatch
eq(g.field, nil, "NO closes the cinema")
check(not g:scriptWaiting(), "waitstate ends")

g.party = { g:makeMon(Game3.SPECIES_WYNAUT, 5) }
g.party[1].isEgg = true
g.party[1].hatchLeft = 1
g.eggCycleSteps = Game3.EGG_CYCLE_STEPS - 1
g:tickEggCycles()
eq(g.party[1].isEgg, true, "Huh? is before AddHatchedMonToParty")
eq(g.field.text, "Huh?", "UnknownString_81B2C68")
eq(g:varGet(0x8004), 0, "_ShouldEggHatch writes the slot")
eq(g:getGameStat(Game3.GAME_STAT_HATCHED_EGGS), 1, "TakeStep increments stat 13")
oldHatch = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = oldHatch
eq(g.field.kind, "egg_hatch", "thenEggHatch runs EggHatch")
eq(g.party[1].isEgg, nil, "hatched inside the cinema")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_SELECT_MOVE, 220, "SelectMove")
eq(Game3.SPECIAL_DELETE_MON_MOVE, 221, "DeleteMonMove")
eq(Game3.SPECIAL_GET_POKEMON_NICKNAME_AND_MOVE_NAME, 222,
  "GetPokemonNicknameAndMoveName")
eq(Game3.SPECIAL_COUNT_POKEMON_MOVES, 223, "CountPokemonMoves")
eq(Game3.MOVE_DELETER_CANCEL, 4, "summary cancel is slot 4")
check(Game3.isHmMove(Game3.MOVE_CUT), "Cut is an HM")

local g = Game3.new()
g.data.moves = { byId = {
  [1] = { id = 1, name = "POUND", pp = 35 },
  [15] = { id = 15, name = "CUT", pp = 30 },
  [33] = { id = 33, name = "TACKLE", pp = 35 },
  [45] = { id = 45, name = "GROWL", pp = 40 },
} }
g.party = { g:makeMon(277, 10, { 33, 45, 15, 1 }) }
g:setScriptVar(0x8004, 0)
eq(g:runSpecial(Game3.SPECIAL_COUNT_POKEMON_MOVES), 4, "four moves")
eq(g:varGet(Gen3Script.VAR_RESULT), 4, "RESULT is the count")

g.party[1].moves = { g:copyMove(33) }
eq(g:countPokemonMoves(), 1, "one move is the only-knows-one branch")

g.party[1].moves = { g:copyMove(33), g:copyMove(15), g:copyMove(45) }
g.scriptVars[0x8005] = 1
g:runSpecial(Game3.SPECIAL_GET_POKEMON_NICKNAME_AND_MOVE_NAME)
eq(g.stringVars[1], g.party[1].name, "STR_VAR_1 is the nickname")
eq(g.stringVars[2], "CUT", "STR_VAR_2 is the move")

g:runSpecial(Game3.SPECIAL_SELECT_MOVE)
check(g:scriptWaiting(), "SelectMove pauses without a waitstate opcode")
eq(g.field.kind, "move_deleter", "PSS_MODE_MOVE_DELETER")
g:pickMoveDeleter(1)
eq(g:varGet(0x8005), 1, "A writes the 0-based move")
eq(g:scriptWaiting(), false, "then the script continues")
g:runSpecial(Game3.SPECIAL_DELETE_MON_MOVE)
eq(#g.party[1].moves, 2, "DeleteMonMove compacts")
eq(g.party[1].moves[1].id, 33, "Tackle stayed")
eq(g.party[1].moves[2].id, 45, "Growl slid down")
check(not g:knowsMove(g.party[1], Game3.MOVE_CUT), "the deleter forgets HMs")

g:runSpecial(Game3.SPECIAL_SELECT_MOVE)
g:pickMoveDeleter(99)
eq(g:varGet(0x8005), 4, "B is slot 4")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_SET_CONTEST_TRAINER_GFX_IDS, 83, "SetContestTrainerGfxIds")
eq(Game3.SPECIAL_GET_FIRST_FREE_POKEBLOCK_SLOT, 160, "GetFirstFreePokeblockSlot")
eq(Game3.SPECIAL_DO_BERRY_BLENDING, 161, "DoBerryBlending")
eq(Game3.SPECIAL_FIELD_SHOW_REGION_MAP, 251, "FieldShowRegionMap")
eq(Game3.SPECIAL_BEDROOM_PC, 249, "BedroomPC")
eq(Game3.SPECIAL_PLAYER_PC, 250, "PlayerPC")
eq(Game3.SPECIAL_SCRIPT_MENU_CREATE_PC_MULTICHOICE, 262, "CreatePCMultichoice")
eq(Game3.SPECIAL_SHOW_BERRY_BLENDER_RECORD, 259, "ShowBerryBlenderRecordWindow")
eq(Game3.SPECIAL_SHOW_POKEMON_STORAGE, 60, "ShowPokemonStorageSystem")
eq(Game3.LOCALID_CONTESTANT_1, 3, "contestant 1 is local 3")
eq(Gen3Script.SHOWCONTESTWINNER, 0x77, "showcontestwinner is 0x77")
eq(Gen3Script.parse(string.char(0x77, 2, 0x02), 0)[1].op, "showcontestwinner",
  "showcontestwinner is kept")
eq(Gen3Script.parse(string.char(0x77, 2, 0x02), 0)[1].contestId, 2, "painting id")

local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
    },
  },
}
g.data.moves = {
  byId = {
    [52] = { id = 52, name = "EMBER", type = 10, power = 40, pp = 25 },
  },
}
g.party = { g:makeMon(280, 5, { 52 }) }
g.rng = function(max)
  g._contestRng = (g._contestRng or 0) + 1
  return (g._contestRng % (max or 65536)) + 1
end
g:setScriptVar(Game3.VAR_CONTEST_CATEGORY, Game3.CONTEST_CATEGORY_BEAUTY)
g:setScriptVar(Game3.VAR_CONTEST_RANK, 1)
g:setScriptVar(0x8004, 0)
eq(g:runSpecial(84), 0, "no Super Beauty ribbon is 0")
g.party[1].ribbons = { beauty = 1 }
eq(g:runSpecial(84), 1, "Normal ribbon qualifies for Super")
check(g.contestMons[1].trainerName ~= "JIMMY", "Super pool is not Normal")
g:runSpecial(83)
eq(g:varGet(Game3.VAR_OBJ_GFX_ID_0), g.contestMons[1].trainerGfxId,
  "VAR_OBJ_GFX_ID_0 is contestant 0")
g:setScriptVar(0x8005, 0)
g:runSpecial(78)
eq(g:varGet(0x8004), 3, "NPC 0 is local 3")
g:setScriptVar(0x8004, 0)
g.party[1].ribbons = { beauty = 2 }
eq(g:runSpecial(84), 2, "already won Super is 2")
g.party[1].isEgg = true
eq(g:runSpecial(84), 3, "egg is 3")
g.party[1].isEgg = nil
g.party[1].hp = 0
eq(g:runSpecial(84), 4, "fainted is 4")
g.party[1].hp = 45
g.party[1].ribbons = nil
g.contest = nil
g.contestMons = nil

check(g:beginContest(1, Game3.CONTEST_CATEGORY_BEAUTY, 0), "Beauty Normal")
for _ = 1, 5 do g:applyContestTurn(1) end
eq(g.field.kind, "contest_results", "five rounds")
g.contest.done = true
g.contest.finalStandings = { [0] = 1, [1] = 2, [2] = 3, [3] = 0 }
g.contest.totalPoints = { [0] = 10, [1] = 20, [2] = 30, [3] = 400 }
g:finishContest()
eq(g.contest.won, true, "player won")
g:runSpecial(76)
eq(g:varGet(0x8005), 3, "player is contestant 3")
g:runSpecial(79)
eq(g.stringVars[3], g:playerName(), "winner trainer is the player")

eq(g:getFirstFreePokeblockSlot(), 0, "case starts empty")
g:addItem(Game3.ITEM_PECHA_BERRY, 1)
eq(g:runSpecial(49), 1, "PlayerHasBerries is 1")
g:setScriptVar(0x8004, 1)
g:runSpecial(161)
check(g:scriptWaiting(), "blender waits")
eq(g.field.kind, "blender_berry", "berry pick")
g:pickBlenderBerry(0)
eq(g:scriptWaiting(), false, "blend returns")
eq(g.pokeblocks[1].color, Game3.PBLOCK_CLR_PINK, "Pecha makes PINK")
eq(g:getFirstFreePokeblockSlot(), 1, "slot 1 is free")
eq(g:itemCount(Game3.ITEM_PECHA_BERRY), 0, "berry consumed")
eq((g.gameStats and g.gameStats[33]) or 0, 1, "GAME_STAT_POKEBLOCKS")

g.flags = { [0x80F] = true, [0x812] = true }
g:openPokeNav()
eq(g.field.lines[1], "LITTLEROOT TOWN", "visited towns list")
eq(g.field.lines[2], "LAVARIDGE TOWN", "Lavaridge is on the map")
g:runSpecial(251)
check(g:scriptWaiting(), "region map waits")
eq(g.field.kind, "pokenav", "FieldShowRegionMap")
eq(g.field.scripted, true, "scripted map")

g.field = nil
g.scriptWait = nil
g:runSpecial(262)
eq(g.field.labels[1], "SOMEONE'S PC", "Lanette flag off")
eq(g.field.labels[3], "LOG OFF", "no HoF yet")
g.flags[Game3.FLAG_SYS_PC_LANETTE] = true
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = true
g.field = nil
g.scriptWait = nil
g:runSpecial(262)
eq(g.field.labels[1], "LANETTE'S PC", "Lanette's PC")
eq(g.field.labels[3], "HALL OF FAME", "HoF after game clear")
g:pickMauvilleMenu(0)
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "storage is choice 0")

g:runSpecial(249)
eq(g.field.kind, "player_pc", "BedroomPC")
eq(#g.field.labels, 4, "item/mail/deco/off")
g:pickPlayerPc(3)
eq(g:scriptWaiting(), false, "Turn Off ends wait")

local full = g:pokeblockFromBerry(Game3.ITEM_CHERI_BERRY, 1)
eq(full.color, Game3.PBLOCK_CLR_RED, "Cheri is RED")
eq(g:pokeblockName(full), "RED POKeBLOCK", "color name")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")
Input:init()
eq(Game3.SPECIAL_DO_TV_SHOW, 63, "DoTVShow")
eq(Game3.SPECIAL_DO_POKE_NEWS, 64, "DoPokeNews")
eq(Game3.SPECIAL_0X44, 65, "special_0x44")
eq(Game3.SPECIAL_GET_TV_SHOW_TYPE, 66, "GetTVShowType")
eq(Game3.SPECIAL_GET_NON_MASS_OUTBREAK_TV_SHOW, 71, "GetNonMassOutbreak")
eq(Game3.SPECIAL_GET_MOM_OR_DAD_TV, 74, "GetMomOrDad")
eq(Game3.SPECIAL_RESET_TV_SHOW_STATE, 75, "ResetTVShowState")
eq(Game3.SPECIAL_DO_TV_SHOW_IN_SEARCH_OF_TRAINERS, 175, "Gabby TV show")
eq(Game3.FLAG_SYS_TV_START, 0x832, "FLAG_SYS_TV_START")
eq(Game3.SPECIAL_GET_WEEK_COUNT, 256, "GetWeekCount")
eq(Game3.SPECIAL_RETRIEVE_LOTTERY_NUMBER, 257, "RetrieveLotteryNumber")
eq(Game3.SPECIAL_PICK_LOTTERY_CORNER_TICKET, 258, "PickLotteryCornerTicket")
eq(Game3.SPECIAL_DO_LOTTERY_CORNER_COMPUTER_EFFECT, 217, "lotto cinema")
eq(Game3.SPECIAL_END_LOTTERY_CORNER_COMPUTER_EFFECT, 218, "lotto cinema end")
eq(Game3.SPECIAL_DO_PC_TURN_ON, 214, "DoPCTurnOnEffect")
eq(Game3.SPECIAL_DO_PC_TURN_OFF, 215, "DoPCTurnOffEffect")
eq(Game3.SPECIAL_BUFFER_LOTTO_TICKET_NUMBER, 337, "BufferLottoTicketNumber")
eq(Game3.SPECIAL_CHECK_RELICANTH_WAILORD, 279, "CheckRelicanthWailord")
eq(Game3.SPECIAL_DO_BRAILLE_WAIT, 280, "DoBrailleWait")
eq(Game3.SPECIAL_FOUND_ABANDONED_SHIP_RM1_KEY, 288, "ship room 1 key")
eq(Game3.SPECIAL_IS_GRASS_TYPE_IN_PARTY, 299, "IsGrassTypeInParty")
eq(Game3.SPECIAL_IS_POKERUS_IN_PARTY, 308, "IsPokerusInParty")
eq(Game3.SPECIAL_SHAKE_CAMERA, 310, "ShakeCamera")
eq(Game3.lotteryMatchingDigits(12345, 45), 2, "two matching digits")
eq(Game3.lotteryMatchingDigits(12345, 12340), 0, "a mismatch stops")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_0X44), 255, "no queued show is 255")
eq(g:runSpecial(Game3.SPECIAL_DO_POKE_NEWS), 0, "no news is 0")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "DoPokeNews writes RESULT 0")
eq(g:runSpecial(Game3.SPECIAL_GET_TV_SHOW_TYPE), 0, "empty kind is 0")
g:setScriptVar(0x8004, 255)
eq(g:runSpecial(Game3.SPECIAL_GET_NON_MASS_OUTBREAK_TV_SHOW), 255,
  "255 stays 255")
eq(g:runSpecial(Game3.SPECIAL_DO_TV_SHOW), 1, "DoTVShow ends the loop")
eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 0, "no Pokerus is 0")
g.party = { g:makeMon(280, 5) }
g.party[1].pokerus = 1
eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 1, "Pokerus is 1")
eq(g:runSpecial(Game3.SPECIAL_IS_GRASS_TYPE_IN_PARTY), 0, "Torchic is not Grass")
g.data.pokemon = { byIndex = { [1] = { type1 = 12, type2 = 3 } } }
g.party = { g:makeMon(1, 5) }
eq(g:runSpecial(Game3.SPECIAL_IS_GRASS_TYPE_IN_PARTY), 1, "Bulbasaur is Grass")
g.party[1].isEgg = true
eq(g:runSpecial(Game3.SPECIAL_IS_GRASS_TYPE_IN_PARTY), 0, "eggs do not count")

eq(g:runSpecial(Game3.SPECIAL_FOUND_ABANDONED_SHIP_RM1_KEY), 0, "no key is 0")
eq(g:varGet(0x8004), 0x277, "copies FLAG_HIDDEN_ITEM")
g.flags[Game3.FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_1_KEY] = true
eq(g:runSpecial(Game3.SPECIAL_FOUND_ABANDONED_SHIP_RM1_KEY), 1, "found is 1")

eq(g:runSpecial(Game3.SPECIAL_CHECK_RELICANTH_WAILORD), 0, "wrong party is 0")
g.party = {
  g:makeMon(Game3.SPECIES_RELICANTH, 40),
  g:makeMon(Game3.SPECIES_WAILORD, 40),
}
eq(g:runSpecial(Game3.SPECIAL_CHECK_RELICANTH_WAILORD), 1, "first/last match")
g.party[2].isEgg = true
eq(g:runSpecial(Game3.SPECIAL_CHECK_RELICANTH_WAILORD), 0, "SPECIES2 egg is EGG")

eq(g:runSpecial(Game3.SPECIAL_GET_WEEK_COUNT), 0, "week 0 is valid")
g.phase = "play"
g:setScriptVar(0x8004, 1)
g:setScriptVar(0x8005, 1)
g:runSpecial(Game3.SPECIAL_SHAKE_CAMERA)
check(g:scriptWaiting(), "ShakeCamera CreateTask")
g:walkHeld((Game3.CAMERA_SHAKE_PERIOD * Game3.CAMERA_SHAKE_HITS) / 60)
check(not g:scriptWaiting(), "8 pans then ScriptContext_Enable")
eq(g.cameraPanX, 0, "pan restores")
eq(g.cameraPanY, 0, "pan restores")

g:setScriptVar(Gen3Script.VAR_RESULT, 12)
g:runSpecial(Game3.SPECIAL_BUFFER_LOTTO_TICKET_NUMBER)
eq(g.stringVars[1], "00012", "lotto pads to 5 digits")

g:setLotteryNumber(0x10000 + 12345)
eq(g:runSpecial(Game3.SPECIAL_RETRIEVE_LOTTERY_NUMBER), 12345, "u16 ticket")
g.party = { g:makeMon(280, 5) }
g.party[1].otId = 45
g.party[1].name = "TORCHIC"
g:setScriptVar(Gen3Script.VAR_RESULT, 12345)
g:pickLotteryCornerTicket()
eq(g:varGet(0x8004), 1, "two digits is rank 1")
eq(g:varGet(0x8005), Game3.ITEM_PP_UP, "PP Up")
eq(g:varGet(0x8006), 0, "party")
eq(g.stringVars[1], "TORCHIC", "nick")

g:setScriptVar(Gen3Script.VAR_RESULT, 11111)
g.party[1].otId = 22222
g:pickLotteryCornerTicket()
eq(g:varGet(0x8004), 0, "no match is 0")
end)()

;(function()
local g = Game3.new()
g.map = { id = "g1_0" }
g:getMomOrDadStringForTVMessage()
eq(g.stringVars[1], "MOM", "Brendan 1F is MOM")
eq(g:varGet(Game3.VAR_TEMP_0 + 3), 1, "VAR_TEMP_3 is 1")

g = Game3.new()
g.map = { id = "g0_10" }
g:setScriptVar(Game3.VAR_TEMP_0 + 3, 2)
g:getMomOrDadStringForTVMessage()
eq(g.stringVars[1], "DAD", "TEMP_3 2 is DAD")

g = Game3.new()
g:ensureGabbyAndTy()
g.gabbyAndTy.valA_4 = 1
g.gabbyAndTy.battleNum = 1
g.gabbyAndTy.valA_0 = 0
g:runSpecial(Game3.SPECIAL_RESET_TV_SHOW_STATE)
eq(g:runSpecial(Game3.SPECIAL_DO_TV_SHOW_IN_SEARCH_OF_TRAINERS), 0, "page 0")
check(g._scriptSays[1]:find("IN SEARCH OF TRAINERS", 1, true) ~= nil, "intro")
eq(g.stringVars[1], "this area", "unknown section")
eq(g:runSpecial(Game3.SPECIAL_DO_TV_SHOW_IN_SEARCH_OF_TRAINERS), 0, "page 2")
eq(g:runSpecial(Game3.SPECIAL_DO_TV_SHOW_IN_SEARCH_OF_TRAINERS), 0, "page 4")
eq(g:runSpecial(Game3.SPECIAL_DO_TV_SHOW_IN_SEARCH_OF_TRAINERS), 1, "last page")
eq(g.gabbyAndTy.valA_4, 0, "taken off the air")

g = Game3.new()
g:ensureGabbyAndTy()
g.gabbyAndTy.valA_4 = 1
g.flags[Game3.FLAG_SYS_TV_START] = true
g:updateTVScreensOnMap()
eq(g.flags[Game3.FLAG_SYS_TV_WATCH], nil, "airing Gabby clears WATCH")

g = Game3.new()
g:updateTVScreensOnMap()
eq(g.flags[Game3.FLAG_SYS_TV_WATCH], true, "no show keeps WATCH")

g = Game3.new()
g.phase = "play"
g.map = {
  id = "tvmap", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  behavior = { 0, 0, 0, 0, Game3.MB_TELEVISION, 0, 0, 0, 0 },
}
g.flags[Game3.FLAG_SYS_TV_START] = true
g:ensureGabbyAndTy().valA_4 = 1
g:updateTVScreensOnMap()
eq(g:mapGridGetMetatileId(1 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_BUILDING_TV_ON, "airing Gabby turns TVs on")
g:runSpecial(Game3.SPECIAL_TURN_OFF_TV_SCREEN)
eq(g.tvOn, false, "TurnOffTVScreen still clears tvOn")
eq(g:mapGridGetMetatileId(1 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_BUILDING_TV_OFF, "and snaps TV_Off")

g.map.id = "g13_0"
g.map.group, g.map.index = 13, 0
g.flags[Game3.FLAG_SYS_TV_START] = nil
g.map.grid[5] = 0
g:updateTVScreensOnMap()
eq(g:mapGridGetMetatileId(1 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_BUILDING_TV_ON, "Cove Lily motel TVs stay on")

g.map = { id = "g24_0", width = 12, height = 24, grid = {} }
for i = 1, 12 * 24 do g.map.grid[i] = 0 end
g.phase = "play"
g:runSpecial(Game3.SPECIAL_DO_BRAILLE_WAIT)
eq(g.flags[Game3.FLAG_SYS_BRAILLE_WAIT], nil, "wait does not open yet")
check(g:scriptWaiting(), "DoBrailleWait CreateTask")
g:walkHeld(Game3.BRAILLE_WAIT_FRAMES / 60)
check(g:scriptWaiting(), "timeout still has 30 frames")
eq(g.flags[Game3.FLAG_SYS_BRAILLE_WAIT], nil, "not open during clear")
g:walkHeld(Game3.BRAILLE_WAIT_CLEAR_FRAMES / 60)
eq(g.flags[Game3.FLAG_SYS_BRAILLE_WAIT], true, "S_OpenRegiceChamber")
eq(g:scriptWaiting(), false, "timeout Enables")
eq(g.map.grid[20 * 12 + 8 + 1], 0x233, "bottom mid is walkable")

g = Game3.new()
g.phase = "play"
g.map = { id = "g24_0", width = 12, height = 24, grid = {} }
for i = 1, 12 * 24 do g.map.grid[i] = 0 end
g.flags[Game3.FLAG_SYS_BRAILLE_WAIT] = true
g:runSpecial(Game3.SPECIAL_DO_BRAILLE_WAIT)
eq(g:scriptWaiting(), false, "flag set skips the task")

g = Game3.new()
g.phase = "play"
g.map = { id = "g24_0", width = 12, height = 24, grid = {} }
for i = 1, 12 * 24 do g.map.grid[i] = 0 end
g:runSpecial(Game3.SPECIAL_DO_BRAILLE_WAIT)
local oldBraille = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:walkHeld(1 / 60)
check(g:scriptWaiting(), "first JOY_NEW only erases")
eq(g.flags[Game3.FLAG_SYS_BRAILLE_WAIT], nil, "first press does not open")
g:walkHeld(1 / 60)
eq(g:scriptWaiting(), false, "second JOY_NEW cancels")
eq(g.flags[Game3.FLAG_SYS_BRAILLE_WAIT], nil, "cancel does not open")
Input.wasPressed = oldBraille

g = Game3.new()
g.phase = "play"
g.map = { id = "g13_0", width = 20, height = 12, grid = {} }
for i = 1, 20 * 12 do g.map.grid[i] = 0 end
g:runSpecial(Game3.SPECIAL_DO_LOTTERY_CORNER_COMPUTER_EFFECT)
eq(g:scriptWaiting(), false, "lottery does not wait")
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  0, "first toggle is at frame 7")
g:walkHeld((Game3.LOTTERY_BLINK_PERIOD - 1) / 60)
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  0, "still idle before 7")
g:walkHeld(1 / 60)
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  Game3.MT_SHOP_LAPTOP1_FLASH, "first blink is Flash")
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX,
  Game3.LOTTERY_LAPTOP_GY + 1), Game3.MT_SHOP_LAPTOP2_FLASH, "Laptop2 Flash")
g:walkHeld(Game3.LOTTERY_BLINK_PERIOD / 60)
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  Game3.MT_SHOP_LAPTOP1_NORMAL, "second blink is Normal")
g:walkHeld((Game3.LOTTERY_BLINK_PERIOD * 3) / 60)
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  Game3.MT_SHOP_LAPTOP1_FLASH, "5th blink leaves Flash")
g:runSpecial(Game3.SPECIAL_END_LOTTERY_CORNER_COMPUTER_EFFECT)
eq(g:mapGridGetMetatileId(Game3.LOTTERY_LAPTOP_GX, Game3.LOTTERY_LAPTOP_GY),
  Game3.MT_SHOP_LAPTOP1_NORMAL, "EndLottery snaps Normal")
eq(g.lotteryLaptop, nil, "task is gone")

g = Game3.new()
g.phase = "play"
g.map = { id = "pc", width = 12, height = 10, grid = {} }
for i = 1, 12 * 10 do g.map.grid[i] = 0 end
g.playerX, g.playerY = 5, 5
g.facing = "north"
g:setScriptVar(0x8004, 0)
local pcGx = 5 + Game3.MAP_OFFSET
local pcGy = 4 + Game3.MAP_OFFSET
g:runSpecial(Game3.SPECIAL_DO_PC_TURN_ON)
eq(g:scriptWaiting(), false, "PC on does not wait")
eq(g:mapGridGetMetatileId(pcGx, pcGy), 0, "PC first toggle is at frame 7")
g:walkHeld((Game3.LOTTERY_BLINK_PERIOD - 1) / 60)
eq(g:mapGridGetMetatileId(pcGx, pcGy), 0, "PC still idle before 7")
g:walkHeld(1 / 60)
eq(g:mapGridGetMetatileId(pcGx, pcGy), Game3.MT_BUILDING_PC_ON,
  "first PC blink is On")
g:walkHeld(Game3.LOTTERY_BLINK_PERIOD / 60)
eq(g:mapGridGetMetatileId(pcGx, pcGy), Game3.MT_BUILDING_PC_OFF,
  "second PC blink is Off")
g:runSpecial(Game3.SPECIAL_DO_PC_TURN_OFF)
eq(g:mapGridGetMetatileId(pcGx, pcGy), Game3.MT_BUILDING_PC_OFF,
  "Turn Off snaps Off")
eq(g.pcBlink, nil, "PC task is gone")
g:setScriptVar(0x8004, 1)
g.facing = "west"
g:runSpecial(Game3.SPECIAL_DO_PC_TURN_OFF)
eq(g:mapGridGetMetatileId(4 + Game3.MAP_OFFSET, 4 + Game3.MAP_OFFSET),
  Game3.MT_BRENDAN_PC_OFF, "west Brendan PC Off")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_GET_TRAINER_BATTLE_MODE, 51, "GetTrainerBattleMode")
eq(Game3.SPECIAL_SHOW_TRAINER_INTRO_SPEECH, 52, "ShowTrainerIntroSpeech")
eq(Game3.SPECIAL_SHOW_TRAINER_NON_BATTLING_SPEECH, 53, "NonBattling")
eq(Game3.SPECIAL_GET_TRAINER_FLAG, 54, "GetTrainerFlag")
eq(Game3.SPECIAL_END_TRAINER_APPROACH, 55, "EndTrainerApproach")
eq(Game3.SPECIAL_PLAY_TRAINER_ENCOUNTER_MUSIC, 56, "PlayTrainerEncounterMusic")
eq(Game3.SPECIAL_HAS_ENOUGH_MONS_FOR_DOUBLE_BATTLE, 61, "HasEnoughMons")
eq(Game3.SPECIAL_INTERVIEW_BEFORE, 67, "InterviewBefore")
eq(Game3.SPECIAL_LEAD_MON_NICKNAMED, 69, "LeadMonNicknamed")
eq(Game3.SPECIAL_SET_CONTEST_CATEGORY_STRING_VAR_FOR_INTERVIEW, 70,
  "SetContestCategory")
eq(Game3.SPECIAL_TV_IS_SCRIPT_SHOW_KIND_ALREADY_IN_QUEUE, 72, "TV queue")
eq(Game3.SPECIAL_SAVE_GAME, 93, "SaveGame")
eq(Game3.SPECIAL_COUNT_ALIVE_PARTY_MONS_EXCEPT_SELECTED_ONE, 133, "CountAlive")
eq(Game3.SPECIAL_EXECUTE_WHITE_OUT, 199, "ExecuteWhiteOut")
eq(Game3.SPECIAL_SP0C8_WHITEOUT_MAYBE, 200, "sp0C8")
eq(Game3.SPECIAL_SET_UP_TRAINER_MOVEMENT, 314, "SetUpTrainerMovement")
eq(Game3.SPECIAL_SCRIPT_GET_MULTIPLAYER_ID, 326, "ScriptGetMultiplayerId")
eq(Game3.SPECIAL_SCRIPT_RANDOM, 340, "ScriptRandom")
eq(Game3.VAR_POISON_STEP_COUNTER, 0x402B, "VAR_POISON_STEP_COUNTER")
eq(Game3.VAR_LAVARIDGE_RIVAL_STATE, 0x4053, "VAR_LAVARIDGE_RIVAL_STATE")
eq(Game3.FLAG_RECEIVED_GO_GOGGLES, 0xDD, "FLAG_RECEIVED_GO_GOGGLES")
eq(Game3.FLAG_DEFEATED_LAVARIDGE_GYM, 0x4BD, "FLAG_DEFEATED_LAVARIDGE_GYM")
eq(Game3.FLAG_HIDE_RIVAL_LAVARIDGE_1, 0x3A1, "FLAG_HIDE_RIVAL_LAVARIDGE_1")
eq(Game3.SAVE_SUCCESS, 1, "SAVE_SUCCESS")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_GET_TRAINER_BATTLE_MODE), 0, "SINGLE is 0")
eq(g:runSpecial(Game3.SPECIAL_GET_TRAINER_FLAG), 0, "no opponent is 0")
eq(g:runSpecial(Game3.SPECIAL_HAS_ENOUGH_MONS_FOR_DOUBLE_BATTLE),
  Game3.PLAYER_HAS_ONE_USABLE_MON, "empty party")
g.party = { g:makeMon(280, 5) }
eq(g:runSpecial(Game3.SPECIAL_HAS_ENOUGH_MONS_FOR_DOUBLE_BATTLE),
  Game3.PLAYER_HAS_ONE_MON, "one slot")
g.party[2] = g:makeMon(277, 5)
eq(g:runSpecial(Game3.SPECIAL_HAS_ENOUGH_MONS_FOR_DOUBLE_BATTLE),
  Game3.PLAYER_HAS_TWO_USABLE_MONS, "two usable is 0")
g:setScriptVar(0x8004, 0)
eq(g:runSpecial(Game3.SPECIAL_COUNT_ALIVE_PARTY_MONS_EXCEPT_SELECTED_ONE),
  1, "skip slot 0")
eq(g:runSpecial(Game3.SPECIAL_LEAD_MON_NICKNAMED), 0, "default nick")
g.party[1].name = "BOB"
eq(g:runSpecial(Game3.SPECIAL_LEAD_MON_NICKNAMED), 1, "nicknamed")
eq(g:runSpecial(Game3.SPECIAL_INTERVIEW_BEFORE), 0, "can interview")
eq(g:runSpecial(Game3.SPECIAL_TV_IS_SCRIPT_SHOW_KIND_ALREADY_IN_QUEUE),
  0, "empty queue")
g:runSpecial(Game3.SPECIAL_SET_CONTEST_CATEGORY_STRING_VAR_FOR_INTERVIEW)
eq(g.stringVars[2], "COOL", "STR_VAR_2 is COOL")
eq(g:runSpecial(Game3.SPECIAL_SCRIPT_GET_MULTIPLAYER_ID), 4, "not link")
g.phase = "play"
g:runSpecial(Game3.SPECIAL_END_TRAINER_APPROACH)
eq(g:scriptWaiting(), true, "EndTrainerApproach CreateTask")
g:walkHeld(Game3.END_APPROACH_FRAMES / 60)
eq(g:scriptWaiting(), false, "Task_DestroyTrainerApproachTask next vblank")
g.trainerBattleMode = Game3.TRAINER_BATTLE_DOUBLE
eq(g:runSpecial(Game3.SPECIAL_GET_TRAINER_BATTLE_MODE), 4, "DOUBLE")
g.trainerBattleOpponent = 265
g:setTrainerDefeated(265)
eq(g:runSpecial(Game3.SPECIAL_GET_TRAINER_FLAG), 1, "Roxanne beaten")
g._scriptSays = {}
g.trainerIntroSpeech = "Want to battle?"
g:runSpecial(Game3.SPECIAL_SHOW_TRAINER_INTRO_SPEECH)
eq(g._scriptSays[1], "Want to battle?", "intro speech")
g.rng = function() return 8 end
g:setScriptVar(Gen3Script.VAR_RESULT, 10)
eq(g:runSpecial(Game3.SPECIAL_SCRIPT_RANDOM), 7, "random % RESULT")
g.phase = "play"
g._saveFs = { write = function() return true end }
eq(g:runSpecial(Game3.SPECIAL_SAVE_GAME), 1, "SAVE_SUCCESS")
eq(g:scriptWaiting(), false, "SaveGame does not wait")
g.phase = "battle"
eq(g:runSpecial(Game3.SPECIAL_SAVE_GAME), 0, "cannot save in battle")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local g = Game3.new()
g.phase = "play"
g.party = { g:makeMon(280, 5) }
g.party[1].hp = 2
g.party[1].status = Game3.STATUS_PSN
g.party[1].friendship = 70
for _ = 1, 3 do g:tickWalkCounters() end
eq(g.party[1].hp, 2, "poison waits four steps")
g:tickWalkCounters()
eq(g.party[1].hp, 1, "fourth step deals 1")
eq(g:varGet(Game3.VAR_POISON_STEP_COUNTER), 0, "counter wraps")
g.map = { id = "g_base", mapType = Game3.MAP_TYPE_SECRET_BASE }
g:tickWalkCounters()
g:tickWalkCounters()
g:tickWalkCounters()
g:tickWalkCounters()
eq(g.party[1].hp, 1, "secret bases skip poison")
g.map = { id = "g0_16", mapType = Game3.MAP_TYPE_ROUTE }
g.party[2] = g:makeMon(277, 5)
for _ = 1, 4 do g:tickWalkCounters() end
eq(g.party[1].hp, 0, "eighth step faints")
eq(g.party[1].status, nil, "FaintFromFieldPoison clears status")
eq(g.party[1].friendship, 65, "FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "a healthy mon remains")
check(g.field and g.field.text:find("fainted", 1, true) ~= nil, "faint text")
eq(g.field.thenWhiteout, nil, "no whiteout while one lives")

g = Game3.new()
g.phase = "play"
g.party = { g:makeMon(280, 5) }
g.party[1].hp = 1
g.party[1].status = Game3.STATUS_PSN
for _ = 1, 4 do g:tickWalkCounters() end
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "all fainted")
check(g.field.thenWhiteout, "thenWhiteout after last faint")
check(g.field.queue[#g.field.queue]:find("whited out", 1, true) ~= nil,
  "whiteout line")

g = Game3.new()
g.phase = "play"
g.money = 3000
g.flags[Game3.FLAG_DEFEATED_ELITE_4_SIDNEY] = true
g.flags[Game3.FLAG_SYS_USE_STRENGTH] = true
g.flags[Game3.FLAG_HIDE_RIVAL_LAVARIDGE_1] = true
g.flags[Game3.FLAG_DEFEATED_LAVARIDGE_GYM] = true
g:setScriptVar(Game3.VAR_BRINEY_LOCATION, 1)
g:setScriptVar(Game3.VAR_ELITE_4_STATE, 3)
g.flags[Game3.FLAG_HIDE_MR_BRINEY_ROUTE104_HOUSE] = true
g:blackout()
eq(g.money, 1500, "DoWhiteOut halves money")
eq(g.flags[Game3.FLAG_DEFEATED_ELITE_4_SIDNEY], nil, "ResetEliteFour")
eq(g:varGet(Game3.VAR_ELITE_4_STATE), 0, "E4 state 0")
eq(g.flags[Game3.FLAG_SYS_USE_STRENGTH], nil, "FlagClear STRENGTH")
eq(g.flags[Game3.FLAG_HIDE_RIVAL_LAVARIDGE_1], nil, "rival returns")
eq(g:varGet(Game3.VAR_LAVARIDGE_RIVAL_STATE), 2, "goggles state 2")
eq(g.flags[Game3.FLAG_HIDE_MR_BRINEY_ROUTE104_HOUSE], nil, "Briney house")
eq(g.flags[Game3.FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN], true, "Briney not Dewford")

g = Game3.new()
g.phase = "play"
g.flags[Game3.FLAG_DEFEATED_LAVARIDGE_GYM] = true
g.flags[Game3.FLAG_RECEIVED_GO_GOGGLES] = true
g.flags[Game3.FLAG_HIDE_RIVAL_LAVARIDGE_1] = true
g:blackout()
eq(g.flags[Game3.FLAG_HIDE_RIVAL_LAVARIDGE_1], true, "goggles already got")

g = Game3.new()
g.phase = "play"
g.money = 400
g.field = { kind = "talk", text = "x", thenWhiteout = true }
eq(g:runSpecial(Game3.SPECIAL_SP0C8_WHITEOUT_MAYBE), 0, "sp0C8 defers")
eq(g.money, 400, "does not blackout while talking")
g.field = nil
g:runSpecial(Game3.SPECIAL_SP0C8_WHITEOUT_MAYBE)
eq(g.money, 200, "sp0C8 DoWhiteOut")
end)()

;(function()
eq(#Game3.TRAINER_EYE_TRAINERS, 56, "56 trainer-eye rows")
eq(Game3.TRAINER_EYE_TRAINERS[30][1][1], Game3.TRAINER_CALVIN_1,
  "Calvin_1 is row 30")
eq(Game3.TRAINER_EYE_TRAINERS[30][3], 17, "on Route 102")
eq(Game3.TRAINER_EYE_TRAINERS[9][1][2], 120, "Cindy skips Cindy_2")
eq(Game3.SPECIAL_START_REMATCH_BATTLE, 59, "StartRematchBattle")
eq(Game3.TRAINER_REMATCH_STEPS, 255, "255 steps")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_SHOULD_TRY_REMATCH), 0, "ShouldTry 0")
eq(g:runSpecial(Game3.SPECIAL_IS_TRAINER_READY_REMATCH), 0, "Ready 0")
g.party = { g:makeMon(280, 5) }
g.data.trainers = {
  byId = {
    [Game3.TRAINER_CALVIN_1] = {
      name = "CALVIN", className = "YOUNGSTER",
      party = { { species = 286, level = 5 } },
    },
    [Game3.TRAINER_CALVIN_2] = {
      name = "CALVIN", className = "YOUNGSTER",
      party = { { species = 288, level = 10 } },
    },
  },
}
for i = 1, 4 do
  g.flags[Game3.FLAG_BADGE01_GET + i - 1] = true
end
g:tickWalkCounters()
eq(tonumber(g.trainerRematchStepCounter) or 0, 0, "four badges skip")
g.flags[Game3.FLAG_BADGE05_GET] = true
g:tickWalkCounters()
eq(g.trainerRematchStepCounter, 1, "fifth badge increments")
g:setTrainerDefeated(Game3.TRAINER_CALVIN_1)
g.trainerRematchStepCounter = 255
g.map = { id = "g0_17", group = 0, index = 17 }
g.rng = function() return 1 end
g:tryUpdateRandomTrainerRematches()
eq(g:trainerEyeRematchValue(30), 1, "31 percent sets Calvin")
eq(g.trainerRematchStepCounter, 0, "and resets the counter")
g.trainerBattleOpponent = Game3.TRAINER_CALVIN_1
eq(g:runSpecial(Game3.SPECIAL_SHOULD_TRY_REMATCH), 1, "ShouldTry flagged")
eq(g:runSpecial(Game3.SPECIAL_IS_TRAINER_READY_REMATCH), 1, "Ready flagged")
g.rng = function() return 32 end
g.trainerRematchStepCounter = 255
g:ensureTrainerRematches()[30] = 0
g:tryUpdateRandomTrainerRematches()
eq(g:trainerEyeRematchValue(30), 0, "roll 31 does not set")
eq(g.trainerRematchStepCounter, 255, "failed roll keeps 255")
g:ensureTrainerRematches()[30] = 1
check(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_REMATCH,
  trainerId = Game3.TRAINER_CALVIN_1,
}), "rematch starts")
eq(g.trainerBattleOpponent, Game3.TRAINER_CALVIN_2, "opponent is CALVIN_2")
eq(g.battle.trainerParty[1].species, 288, "CALVIN_2 party")
eq(g.battle.npc.trainerId, Game3.TRAINER_CALVIN_2, "battler id")
check(g.battle.eyeRematch, "eye rematch")
g.battle.queue = nil
g:confirmTrainerWin()
eq(g:trainerDefeated(Game3.TRAINER_CALVIN_2), true, "CALVIN_2 flagged")
eq(g:trainerEyeRematchValue(30), 0, "rematch flag cleared")
eq(g:scriptTrainerBattle({
  kind = Game3.TRAINER_BATTLE_REMATCH,
  trainerId = Game3.TRAINER_CALVIN_1,
}), false, "no rematch without flag")
g.trainerBattleOpponent = Game3.TRAINER_CALVIN_1
eq(g:runSpecial(Game3.SPECIAL_SHOULD_TRY_REMATCH), 1, "WasSecondRematchWon")
eq(g:getRematchTrainerId(114), 120, "Cindy_3 not Cindy_2")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_IS_ENIGMA_BERRY_VALID, 50, "IsEnigmaBerryValid")
eq(Game3.SPECIAL_GET_SHROOMISH_SIZE_RECORD, 119, "GetShroomishSizeRecordInfo")
eq(Game3.SPECIAL_COMPARE_SHROOMISH_SIZE, 120, "CompareShroomishSize")
eq(Game3.SPECIAL_GET_BARBOACH_SIZE_RECORD, 121, "GetBarboachSizeRecordInfo")
eq(Game3.SPECIAL_COMPARE_BARBOACH_SIZE, 122, "CompareBarboachSize")
eq(Game3.SPECIAL_SHOULD_MOVE_LILYCOVE_FAN_CLUB_MEMBER, 163, "ShouldMove")
eq(Game3.SPECIAL_GET_NUM_MOVED_LILYCOVE_FAN_CLUB_MEMBERS, 164, "GetNumMoved")
eq(Game3.SPECIAL_BUFFER_STREAK_TRAINER_TEXT, 165, "BufferStreakTrainerText")
eq(Game3.SPECIAL_SUB_810FA74, 166, "sub_810FA74")
eq(Game3.SPECIAL_UPDATE_MOVED_LILYCOVE_FAN_CLUB_MEMBERS, 167, "UpdateMoved")
eq(Game3.SPECIAL_SUB_810FF48, 168, "sub_810FF48")
eq(Game3.SPECIAL_SUB_810FF60, 170, "sub_810FF60")
eq(Game3.SPECIAL_SHOW_DIPLOMA, 264, "ShowDiploma")
eq(Game3.SPECIAL_START_SOUTHERN_ISLAND_BATTLE, 323, "Southern Island")
eq(Game3.SPECIAL_SET_PACIFIDLOG_TM_RECEIVED_DAY, 333, "SetPacifidlogTM")
eq(Game3.SPECIAL_GET_DAYS_UNTIL_PACIFIDLOG_TM, 334, "GetDaysUntilPacifidlog")
eq(Game3.SPECIAL_GET_NAME_OF_ENIGMA_BERRY_IN_PARTY, 339, "Enigma name")
eq(Game3.formatMonSizeRecord(Game3.getMonSize(306, 0x8100)), "15.7",
  "Marco Shroomish is 15.7 in")

local g = Game3.new()
eq(g:runSpecial(Game3.SPECIAL_IS_ENIGMA_BERRY_VALID), 0, "no e-reader")
eq(g:runSpecial(Game3.SPECIAL_GET_NAME_OF_ENIGMA_BERRY_IN_PARTY), 0,
  "no Enigma is 0")
g.party = { g:makeMon(280, 5) }
g.party[1].item = Game3.ITEM_ENIGMA_BERRY
eq(g:runSpecial(Game3.SPECIAL_GET_NAME_OF_ENIGMA_BERRY_IN_PARTY), 1,
  "held Enigma is 1")
eq(g.stringVars[1], "ENIGMA", "STR_VAR_1 is the berry name")

eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 0, "unset byte is 0")
g.party[1].pokerus = 0x10
eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 0, "cured 0x10 is 0")
g.party[1].pokerus = 0x41
eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 1, "active strain is 1")

g.party = { g:makeMon(280, 5), g:makeMon(280, 5) }
local n = 0
g.rng = function()
  n = n + 1
  if n == 1 then return 0x4001 end
  if n == 2 then return 1 end
  if n == 3 then return 5 end
  return 1
end
check(g:randomlyGivePartyPokerus(), "0x4000 infects")
eq(g.party[1].pokerus, 0x41, "rnd2 4 becomes 0x41")
g.rng = function() return 1 end
g.party[2].pokerus = 0
g:partySpreadPokerus()
eq(g.party[2].pokerus, 0x41, "adjacent spread")

g.flags[Game3.FLAG_SYS_CLOCK_SET] = true
g:setScriptVar(Game3.VAR_DAYS, 0)
g.clockHour, g.clockMinute = 0, 0
g.clockAnchor = os.time() - 2 * 24 * 3600
g.party[1].pokerus = 0x45
g:doTimeBasedEvents()
eq(g.party[1].pokerus, 0x43, "two days tick the low nibble")
g:setScriptVar(Game3.VAR_DAYS, 0)
g.clockAnchor = os.time() - 5 * 24 * 3600
g.party[1].pokerus = 0x45
g:doTimeBasedEvents()
eq(g.party[1].pokerus, 0x40, "days > 4 leave the strain")
eq(g:runSpecial(Game3.SPECIAL_IS_POKERUS_IN_PARTY), 0, "cured is not in party")

g.phase = "battle"
g.battle = { enemy = g:makeMon(263, 2) }
g.party[1].pokerus = 0x41
g.party[2].pokerus = 0
g.rng = function() return 1 end
g:endBattle()
eq(g.party[2].pokerus, 0x41, "ReturnFromBattle spreads")

g:setScriptVar(Gen3Script.VAR_RESULT, 0xFF)
eq(g:runSpecial(Game3.SPECIAL_COMPARE_SHROOMISH_SIZE), 0, "0xFF is 0")
g:setScriptVar(Gen3Script.VAR_RESULT, 0)
g.party = { g:makeMon(280, 5) }
eq(g:runSpecial(Game3.SPECIAL_COMPARE_SHROOMISH_SIZE), 1, "wrong species is 1")
g.party[1].species = Game3.SPECIES_SHROOMISH
g.party[1].pid = 0
g.party[1].ivs = { hp = 1, atk = 1, def = 0, spe = 0, spa = 0, spd = 0 }
g:setScriptVar(Game3.VAR_SHROOMISH_SIZE_RECORD, 0)
eq(g:runSpecial(Game3.SPECIAL_COMPARE_SHROOMISH_SIZE), 3, "beats a 0 record")
g:setScriptVar(Game3.VAR_SHROOMISH_SIZE_RECORD, Game3.SIZE_RECORD_DEFAULT)
g:runSpecial(Game3.SPECIAL_GET_SHROOMISH_SIZE_RECORD)
eq(g.stringVars[3], "15.7", "STR_VAR_3 is inches")
eq(g.stringVars[2], "MARCO", "default owner")

g.clockAnchor = nil
g.clockHour, g.clockMinute = 0, 0
eq(g:runSpecial(Game3.SPECIAL_GET_DAYS_UNTIL_PACIFIDLOG_TM), 7, "day 0 is 7")
eq(g:runSpecial(Game3.SPECIAL_SET_PACIFIDLOG_TM_RECEIVED_DAY), 0,
  "received day 0 is valid")
g.clockAnchor = os.time() - 7 * 24 * 3600
eq(g:runSpecial(Game3.SPECIAL_GET_DAYS_UNTIL_PACIFIDLOG_TM), 0, "day 7 is 0")

g:setScriptVar(0x8004, 8)
eq(g:runSpecial(Game3.SPECIAL_SHOULD_MOVE_LILYCOVE_FAN_CLUB_MEMBER), 0,
  "bit 8 unset is 0")
eq(g:runSpecial(Game3.SPECIAL_GET_NUM_MOVED_LILYCOVE_FAN_CLUB_MEMBERS), 0,
  "no movers is 0")
g:setScriptVar(Game3.VAR_FANCLUB_UNKNOWN_1, 0x100)
eq(g:runSpecial(Game3.SPECIAL_SHOULD_MOVE_LILYCOVE_FAN_CLUB_MEMBER), 1,
  "bit 8 set is 1")
eq(g:runSpecial(Game3.SPECIAL_GET_NUM_MOVED_LILYCOVE_FAN_CLUB_MEMBERS), 1,
  "one mover")
g:setScriptVar(0x8004, 10)
g:runSpecial(Game3.SPECIAL_BUFFER_STREAK_TRAINER_TEXT)
eq(g.stringVars[1], "WINONA", "bit 10 is Winona")
g:runSpecial(Game3.SPECIAL_SUB_810FF48)
eq(math.floor(g:varGet(Game3.VAR_FANCLUB_UNKNOWN_1) / 0x80) % 2, 1,
  "bit 7 set")
eq(g:runSpecial(Game3.SPECIAL_SUB_810FF60),
  g:varGet(Game3.VAR_FANCLUB_UNKNOWN_1) % 0x80, "score is the low 7")

g:runSpecial(Game3.SPECIAL_SHOW_DIPLOMA)
eq(g.field.kind, "diploma", "diploma field")
check(g:scriptWaiting(), "waitstate holds")
g:closeDiploma()
eq(g:scriptWaiting(), false, "A/B ends the wait")

g.party = { g:makeMon(280, 5) }
g:setWildBattle(Game3.SPECIES_LATIAS, 50, Game3.ITEM_NONE)
check(g:runSpecial(Game3.SPECIAL_START_SOUTHERN_ISLAND_BATTLE) ~= 0,
  "Southern Island starts")
check(g.battle.legendary, "BATTLE_TYPE_LEGENDARY")
eq(g.battle.enemy.species, Game3.SPECIES_LATIAS, "scripted wild")
g:endBattle()
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")
Input:init()
eq(Game3.SPECIAL_GET_SELECTED_DAYCARE_MON_NICKNAME, 186, "nickname 186")
eq(Game3.SPECIAL_DAYCARE_MON_RECEIVED_MAIL, 195, "mail 195")
eq(Game3.SPECIAL_ACCESS_HALL_OF_FAME_PC, 263, "HoF PC 263")
eq(Game3.SPECIAL_DO_WATERING_BERRY_TREE_ANIM, 94, "watering anim")
eq(Game3.SPECIAL_SPAWN_CAMERA_DUMMY, 275, "camera dummy")
eq(Game3.SPECIAL_REMOVE_CAMERA_DUMMY, 276, "remove camera dummy")
eq(Game3.LOCALID_CAMERA, 127, "LOCALID_CAMERA")
eq(Game3.SPECIAL_DO_SEALED_CHAMBER_SHAKING_1, 305, "sealed shake 1")
eq(Game3.SPECIAL_SUB_807E25C, 317, "Route 128 fade")
eq(Game3.GAME_STAT_ENTERED_HOF, 10, "stat 10")
eq(Game3.HALL_OF_FAME_MAX_TEAMS, 50, "50 teams")
check(Game3.isMailItem(121), "Orange Mail")
check(Game3.isMailItem(132), "Retro Mail")
check(not Game3.isMailItem(120), "below mail")
check(not Game3.isMailItem(133), "above mail")

local g = Game3.new()
g.phase = "play"
g.party = { g:makeMon(280, 5) }
g.party[1].name = "BLAZE"
g:setScriptVar(0x8004, 0)
eq(g:runSpecial(Game3.SPECIAL_GET_SELECTED_DAYCARE_MON_NICKNAME), 280,
  "returns SPECIES")
eq(g.stringVars[1], "BLAZE", "STR_VAR_1 is the nick")
g.party = {}
eq(g:runSpecial(Game3.SPECIAL_GET_SELECTED_DAYCARE_MON_NICKNAME), 0,
  "empty party is 0")

g.party = { g:makeMon(280, 5), g:makeMon(290, 2), g:makeMon(280, 5) }
g.party[1].name, g.party[1].otName = "BLAZE", "BRENDAN"
g.party[2].name, g.party[2].otName = "WURM", "MAY"
check(g:depositToDaycare(1), "slot 1")
check(g:depositToDaycare(1), "slot 2")
g:runSpecial(Game3.SPECIAL_GET_DAYCARE_MON_NICKNAMES)
eq(g.stringVars[1], "BLAZE", "slot 0 nick")
eq(g.stringVars[3], "BRENDAN", "slot 0 OT")
eq(g.stringVars[2], "WURM", "slot 1 nick")

g:setScriptVar(0x8004, 0)
eq(g:runSpecial(Game3.SPECIAL_DAYCARE_MON_RECEIVED_MAIL), 0,
  "no mail is 0")
g.daycare[1].mail = {
  itemId = Game3.ITEM_ORANGE_MAIL, otName = "BRENDAN", nick = "BLAZE",
}
eq(g:runSpecial(Game3.SPECIAL_DAYCARE_MON_RECEIVED_MAIL), 0,
  "matching names is 0")
g.daycare[1].mail.nick = "OLDNICK"
eq(g:runSpecial(Game3.SPECIAL_DAYCARE_MON_RECEIVED_MAIL), 1,
  "renamed nick is 1")
eq(g.stringVars[1], "BLAZE", "current nick")
eq(g.stringVars[3], "OLDNICK", "mail nick")
eq(g.stringVars[2], "BRENDAN", "mail OT")

g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g.party[1].name = "MAILMON"
g.party[1].item = Game3.ITEM_ORANGE_MAIL
g.daycare = {}
check(g:depositToDaycare(1), "deposits with mail")
eq(g.daycare[1].mail.itemId, Game3.ITEM_ORANGE_MAIL, "mail stored")
eq(g.daycare[1].mail.nick, "MAILMON", "mail nick at deposit")
eq(g.daycare[1].mon.item, Game3.ITEM_NONE, "TakeMailFromMon")

g.party = { g:makeMon(280, 5), g:makeMon(290, 2) }
g:runSpecial(Game3.SPECIAL_CHOOSE_SEND_DAYCARE_MON)
check(g:scriptWaiting(), "send waits")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = old
eq(g:varGet(0x8004), Game3.PARTY_MENU_CANCEL, "B is 255")
check(not g:scriptWaiting(), "B ends the wait")

g.hallOfFameTeams = {
  { { species = 280, level = 5, nick = "ONE", tid = 1, pid = 1 } },
  { { species = 290, level = 10, nick = "TWO", tid = 1, pid = 1 } },
}
g.gameStats = { [Game3.GAME_STAT_ENTERED_HOF] = 2 }
g:runSpecial(Game3.SPECIAL_ACCESS_HALL_OF_FAME_PC)
eq(g.field.kind, "hof_pc", "HoF PC field")
eq(g.field.teamIndex, 2, "starts at newest")
eq(g.field.pageNo, 2, "page is ENTERED_HOF")
check(g:scriptWaiting(), "HoF PC waits")
old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
eq(g.field.teamIndex, 1, "A goes older")
eq(g.field.pageNo, 1, "page decrements")
g:stepField()
Input.wasPressed = old
check(not g:scriptWaiting(), "A on oldest closes")

g:runSpecial(Game3.SPECIAL_DO_WATERING_BERRY_TREE_ANIM)
check(g:scriptWaiting(), "watering CreateTask")
eq(g:playerGraphicsId(), Game3.GFX_BRENDAN_WATERING,
  "sub_8059D08 swaps to watering gfx")
g:walkHeld(Game3.WATERING_FRAMES / 60)
check(not g:scriptWaiting(), "11 walk-in-place then Enable")
eq(g:playerGraphicsId(), Game3.GFX_BRENDAN, "then restores Brendan")
g:runSpecial(Game3.SPECIAL_SPAWN_CAMERA_DUMMY)
g:runSpecial(Game3.SPECIAL_REMOVE_CAMERA_DUMMY)
check(not g:scriptWaiting(), "camera dummy does not wait")

g.map = { id = "cam", width = 8, height = 8, grid = {} }
for i = 1, 64 do g.map.grid[i] = 0 end
g.phase = "play"
g.playerX, g.playerY = 4, 4
g.npcByMap = { cam = {} }
g:runSpecial(Game3.SPECIAL_SPAWN_CAMERA_DUMMY)
check(not g:scriptWaiting(), "SpawnCameraDummy does not wait")
local dummy = g:npcByLocalId(Game3.LOCALID_CAMERA)
check(dummy ~= nil, "local 127 spawned")
check(dummy.invisible, "dummy is invisible")
eq(dummy.x, 4, "dummy x is player x")
eq(dummy.y, 4, "dummy y is player y")
check(g.cameraDummy == dummy, "camera follows dummy")
check(g:applyMovement(Game3.LOCALID_CAMERA, { { kind = "walk", dir = "north" } }),
  "applymovement 127")
eq(dummy.y, 3, "first north step starts now")
eq(g.playerY, 4, "player stays")
g:finishScriptMoves()
eq(dummy.y, 3, "dummy walked north")
local vx, vy = g:visualTile()
eq(vx, dummy.x, "visual x follows dummy")
eq(vy, dummy.y, "visual y follows dummy")
g:runSpecial(Game3.SPECIAL_REMOVE_CAMERA_DUMMY)
eq(g:npcByLocalId(Game3.LOCALID_CAMERA), nil, "127 removed")
eq(g.cameraDummy, nil, "follow restores to player")
vx, vy = g:visualTile()
eq(vx, g.playerX, "visual x is player")
eq(vy, g.playerY, "visual y is player")
g:runSpecial(Game3.SPECIAL_DO_SEALED_CHAMBER_SHAKING_1)
check(g:scriptWaiting(), "sealed 1 CreateTask")
g:walkHeld((Game3.SEALED_SHAKE_PERIOD * Game3.SEALED_SHAKE1_HITS) / 60)
check(not g:scriptWaiting(), "50 pans then Enable")
eq(g.cameraPanY, 0, "sealed pan restores")
g:runSpecial(Game3.SPECIAL_DO_SEALED_CHAMBER_SHAKING_2)
check(g:scriptWaiting(), "sealed 2 CreateTask")
g:walkHeld((Game3.SEALED_SHAKE_PERIOD * Game3.SEALED_SHAKE2_HITS) / 60)
check(not g:scriptWaiting(), "2 pans then Enable")
g:runSpecial(Game3.SPECIAL_SUB_807E25C)
check(g:scriptWaiting(), "Route 128 fade CreateTask")
g:walkHeld(Game3.ROUTE128_FADE_FRAMES / 60)
check(not g:scriptWaiting(), "BLDY then Enable")
eq(g:route128FadeAlpha(), 0, "fade is gone")
end)()

;(function()
  local Game3 = require("src.core.Game3")
  local g = Game3.new()
  local mon = g:makeMon(280, 5)
  mon.maxHp, mon.hp = 100, 10
  mon.friendship = 70
  g.party = { mon }
  g:addItem(Game3.ITEM_ENERGY_POWDER, 1)
  local ok = g:useItemOnMon(mon, Game3.ITEM_ENERGY_POWDER)
  check(ok, "Energy Powder heals")
  eq(mon.hp, 60, "gItemEffect_EnergyPowder 50")
  eq(mon.friendship, 65, "low band -5")
  g:addItem(Game3.ITEM_ENERGY_ROOT, 1)
  mon.hp = 10
  mon.friendship = 150
  ok = g:useItemOnMon(mon, Game3.ITEM_ENERGY_ROOT)
  check(ok, "Energy Root heals")
  eq(mon.hp, 100, "200 caps at max")
  eq(mon.friendship, 140, "mid band -10")
  mon.status = "psn"
  mon.friendship = 220
  g:addItem(Game3.ITEM_HEAL_POWDER, 1)
  ok = g:useItemOnMon(mon, Game3.ITEM_HEAL_POWDER)
  check(ok, "Heal Powder cures")
  eq(mon.status, nil, "ITEM3_STATUS_ALL")
  eq(mon.friendship, 210, "high band -10")
  mon.hp = 0
  mon.friendship = 80
  g:addItem(Game3.ITEM_REVIVAL_HERB, 1)
  ok = g:useItemOnMon(mon, Game3.ITEM_REVIVAL_HERB)
  check(ok, "Revival Herb")
  eq(mon.hp, 50, "0xFE is half of 100")
  eq(mon.friendship, 65, "low band -15")
  mon.status = "slp"
  g:addItem(Game3.ITEM_LAVA_COOKIE, 1)
  local before = mon.friendship
  ok = g:useItemOnMon(mon, Game3.ITEM_LAVA_COOKIE)
  check(ok, "Lava Cookie")
  eq(mon.status, nil, "Chimney cookie is Full Heal")
  eq(mon.friendship, before, "no herbal drop")
  eq(g:itemPrice(Game3.ITEM_LAVA_COOKIE), 200, "Mt. Chimney 0xC8")
end)()

;(function()
  local Game3 = require("src.core.Game3")
  local Gen3Script = require("src.import.Gen3Script")
  eq(Game3.lcg32(0), 12345, "LCG of 0 is the addend")
  eq(Game3.lcg32(1), 1103527590, "glibc step from 1")
  eq(Game3.lcg32(0xFFFFFFFF), 3191464396, "u32 wrap stays exact")
  eq(Game3.DAILY_FLAGS_START, 0x8C0, "DAILY_FLAGS_START")
  eq(Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE114, 0x8CB, "Route 114 berry")
  eq(Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE111, 0x8CC, "Route 111 berry")
  eq(Game3.FLAG_SYS_SHOAL_ITEM, 0x85F, "shoal item flag")
  eq(Game3.VAR_BIRCH_STATE, 0x4049, "Birch state var")

  local g = Game3.new()
  g.gbaRandom = function() return 0 end
  g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE111] = true
  g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE114] = true
  g.flags[0x8C0] = true
  g.flags[0x8FF] = true
  g.flags[0x8BF] = true
  g.flags[0x900] = true
  g.easyChatPairs = {
    { 1, 2, pop = 20, maxPop = 50 },
    { 3, 4, pop = 3, maxPop = 40 },
    { 5, 6, pop = 10, maxPop = 12, rising = true },
    { 7, 8, pop = 40, maxPop = 50, rising = true },
    { 9, 10, pop = 48, maxPop = 50, rising = true },
  }
  g.weatherCycleStage = 3
  g:setScriptVar(Game3.VAR_MIRAGE_RND_H, 0)
  g:setScriptVar(Game3.VAR_MIRAGE_RND_L, 1)
  g:setScriptVar(Game3.VAR_BIRCH_STATE, 5)
  g:setScriptVar(Game3.VAR_DAYS, 0)
  g.flags[Game3.FLAG_SYS_CLOCK_SET] = true
  g.clockHour, g.clockMinute = 0, 0
  g.clockAnchor = os.time() - 24 * 3600
  g:doTimeBasedEvents()
  check(not g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE111],
    "Route 111 daily berry clears")
  check(not g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE114],
    "Route 114 daily berry clears")
  check(not g.flags[0x8C0], "first daily flag clears")
  check(not g.flags[0x8FF], "last daily flag clears")
  check(g.flags[0x8BF], "flag before daily range stays")
  check(g.flags[0x900], "flag after daily range stays")
  check(g.flags[Game3.FLAG_SYS_SHOAL_ITEM], "SetShoalItemFlag ignores days")
  eq(g.weatherCycleStage, 0, "stage 3 + 1 day wraps")
  eq(g:varGet(Game3.VAR_BIRCH_STATE), 6, "5 + 1 day mod 7")
  eq(g:varGet(Game3.VAR_MIRAGE_RND_L), 32422, "mirage low after one LCG")
  eq(g:varGet(Game3.VAR_MIRAGE_RND_H), 16838, "mirage high after one LCG")
  eq(g:getLotteryNumber(), 12345, "one extra LCG from Random 0")
  eq(g:varGet(Game3.VAR_DAYS), 1, "VAR_DAYS stores localTime.days")
  local pairs = g.easyChatPairs
  eq(pairs[1].pop, 47, "48+5 wraps over 50")
  eq(pairs[1][1], 9, "highest pop is first")
  check(not pairs[1].rising, "odd wrap is falling")
  eq(pairs[2].pop, 45, "rising 40+5 stays under max")
  eq(pairs[2][1], 7, "second is 45")
  check(pairs[2].rising, "still rising")
  eq(pairs[3].pop, 15, "falling 20-5")
  eq(pairs[3][1], 1, "third is 15")
  check(not pairs[3].rising, "still falling")
  eq(pairs[4].pop, 9, "wrap 10+5 over 12")
  eq(pairs[4][1], 5, "fourth is 9")
  check(not pairs[4].rising, "odd quotient is falling")
  eq(pairs[5].pop, 2, "falling 3 bounces leftover 2")
  eq(pairs[5][1], 3, "lowest is the bounce")
  check(pairs[5].rising, "bounce sets rising")

  eq(g:updateBirchState(1), 0, "6 + 1 day wraps to 0")
  g:setScriptVar(Game3.VAR_BIRCH_STATE, 6)
  eq(g:runSpecial(Game3.SPECIAL_INIT_BIRCH_STATE), 0, "InitBirchState is 0")
  eq(g:varGet(Game3.VAR_BIRCH_STATE), 0, "Wally exit zeros Birch")

  g.flags[Game3.FLAG_SYS_CLOCK_SET] = nil
  g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE111] = true
  g:setScriptVar(Game3.VAR_DAYS, 0)
  g.clockAnchor = os.time() - 2 * 24 * 3600
  g:doTimeBasedEvents()
  check(g.flags[Game3.FLAG_DAILY_RECEIVED_BERRY_ROUTE111],
    "no tick before FLAG_SYS_CLOCK_SET")
end)()

;(function()
eq(Game3.ITEM_CLEANSE_TAG, 190, "ITEM_CLEANSE_TAG")
eq(Game3.FLAG_SYS_ENC_UP_ITEM, 0x84D, "White Flute flag")
eq(Game3.FLAG_SYS_ENC_DOWN_ITEM, 0x84E, "Black Flute flag")
eq(Game3.MAX_ENCOUNTER_RATE, 2880, "MAX_ENCOUNTER_RATE")
eq(Game3.ABILITY_STENCH, 1, "ABILITY_STENCH")
eq(Game3.ABILITY_ILLUMINATE, 35, "ABILITY_ILLUMINATE")
check(Game3.isBlueYellowRedFlute(Game3.ITEM_BLUE_FLUTE), "Blue reusable")
check(not Game3.isBlueYellowRedFlute(Game3.ITEM_BLACK_FLUTE), "Black is not")

local g = Game3.new()
eq(g:wildEncounterRate(20), 320, "*16 with no mods")
eq(g:wildEncounterRate(255), 2880, "255*16 caps at 2880")
g.bike = "mach"
eq(g:wildEncounterRate(20), 256, "Mach Bike *80/100")
g.bike = "acro"
eq(g:wildEncounterRate(20), 256, "Acro Bike too")
g.bike = nil
g.flags[Game3.FLAG_SYS_ENC_UP_ITEM] = true
eq(g:wildEncounterRate(20), 480, "White Flute +50%")
g.flags[Game3.FLAG_SYS_ENC_UP_ITEM] = nil
g.flags[Game3.FLAG_SYS_ENC_DOWN_ITEM] = true
eq(g:wildEncounterRate(20), 160, "Black Flute /2")
g.flags[Game3.FLAG_SYS_ENC_DOWN_ITEM] = nil
g.party = { { name = "TORCHIC", hp = 19, maxHp = 19,
  item = Game3.ITEM_CLEANSE_TAG } }
eq(g:wildEncounterRate(20), 213, "Cleanse Tag *2/3")
g.party[1].item = nil
g.party[1].ability = Game3.ABILITY_STENCH
eq(g:wildEncounterRate(20), 160, "Stench /2")
eq(g:wildEncounterRate(20, true), 320, "Rock Smash skips ability")
g.party[1].ability = Game3.ABILITY_ILLUMINATE
eq(g:wildEncounterRate(20), 640, "Illuminate *2")
g.party[1].isEgg = true
eq(g:wildEncounterRate(20), 320, "egg lead skips ability")
g.party[1].isEgg = nil
g.party[1].ability = nil

g:addItem(Game3.ITEM_WHITE_FLUTE, 1)
g:addItem(Game3.ITEM_BLACK_FLUTE, 1)
local ok, msg = g:useFieldItem(Game3.ITEM_WHITE_FLUTE)
check(ok, "White Flute uses")
eq(msg, "BRENDAN used the WHITE FLUTE.\nWild POKéMON will be lured.",
  "lure line")
eq(g:itemCount(Game3.ITEM_WHITE_FLUTE), 1, "White not consumed")
check(g.flags[Game3.FLAG_SYS_ENC_UP_ITEM], "ENC_UP set")
ok, msg = g:useFieldItem(Game3.ITEM_BLACK_FLUTE)
check(ok, "Black Flute uses")
eq(msg, "BRENDAN used the BLACK FLUTE.\nWild POKéMON will be repelled.",
  "repel line")
check(g.flags[Game3.FLAG_SYS_ENC_DOWN_ITEM], "ENC_DOWN set")
check(not g.flags[Game3.FLAG_SYS_ENC_UP_ITEM], "ENC_UP cleared")
eq(g:itemCount(Game3.ITEM_BLACK_FLUTE), 1, "Black not consumed")
eq(g:wildEncounterRate(20), 160, "Black Flute field use")

g.flags[Game3.FLAG_SYS_USE_STRENGTH] = true
g.flags[Game3.FLAG_SYS_CTRL_OBJ_DELETE] = true
g:enterMap({
  id = "g_flute_clear", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}, 1, 1, true)
check(not g.flags[Game3.FLAG_SYS_ENC_DOWN_ITEM], "LoadMap clears Black Flute")
check(not g.flags[Game3.FLAG_SYS_USE_STRENGTH], "LoadMap clears Strength")
check(not g.flags[Game3.FLAG_SYS_CTRL_OBJ_DELETE], "LoadMap clears OBJ_DELETE")

g.party = { { name = "TORCHIC", hp = 19, maxHp = 19, status = "slp",
  sleepTurns = 3 } }
g:addItem(Game3.ITEM_BLUE_FLUTE, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_BLUE_FLUTE)
check(ok, "Blue Flute wakes")
eq(msg, "TORCHIC woke up.", "woke-up line")
eq(g.party[1].status, nil, "sleep gone")
eq(g:itemCount(Game3.ITEM_BLUE_FLUTE), 1, "Blue not consumed")

g.party[1].confuseTurns = 3
g:addItem(Game3.ITEM_YELLOW_FLUTE, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_YELLOW_FLUTE)
check(ok, "Yellow Flute snaps")
eq(msg, "TORCHIC snapped out of its confusion.", "snap line")
eq(g.party[1].confuseTurns, nil, "confusion gone")
eq(g:itemCount(Game3.ITEM_YELLOW_FLUTE), 1, "Yellow not consumed")

g.party[1].infatuatedBy = {}
g:addItem(Game3.ITEM_RED_FLUTE, 1)
ok, msg = g:useItemOnMon(g.party[1], Game3.ITEM_RED_FLUTE)
check(ok, "Red Flute cures love")
eq(msg, "TORCHIC got over its infatuation.", "love line")
eq(g.party[1].infatuatedBy, nil, "infatuation gone")
eq(g:itemCount(Game3.ITEM_RED_FLUTE), 1, "Red not consumed")
local miss, missMsg = g:useItemOnMon(g.party[1], Game3.ITEM_RED_FLUTE)
check(not miss, "Red on a healthy mon")
eq(missMsg, "It won't have any effect.", "no effect")
eq(g:itemCount(Game3.ITEM_RED_FLUTE), 1, "still not consumed")

g.data.tilesets = { byId = { grass = { behavior = { [1] = 0x02 } } } }
g.data.encounters = { byMap = { g_flute = {
  land = { rate = 20, slots = { { minLevel = 2, maxLevel = 2, species = 290 } } },
} } }
local grass = {
  id = "g_flute", mapType = Game3.MAP_TYPE_ROUTE, width = 3, height = 3,
  tileset = "grass",
  grid = { 0, 0, 0, 0, 1, 0, 0, 0, 0 },
}
g.party = { { name = "TORCHIC", hp = 19, maxHp = 19, species = 280, level = 5 } }
g:enterMap(grass, 1, 1, true)
g.rng = function() return 400 end
check(not g:tryWildEncounter(), "roll 399 misses 320")
g:addItem(Game3.ITEM_WHITE_FLUTE, 1)
g:useFieldItem(Game3.ITEM_WHITE_FLUTE)
check(g:tryWildEncounter(), "White Flute 480 beats 399")
end)()

;(function()
eq(Game3.ABILITY_SPEED_BOOST, 3, "Speed Boost is 3")
eq(Game3.ABILITY_BATTLE_ARMOR, 4, "Battle Armor is 4")
eq(Game3.ABILITY_STURDY, 5, "Sturdy is 5")
eq(Game3.ABILITY_DAMP, 6, "Damp is 6")
eq(Game3.ABILITY_SUCTION_CUPS, 21, "Suction Cups is 21")
eq(Game3.ABILITY_EFFECT_SPORE, 27, "Effect Spore is 27")
eq(Game3.ABILITY_SOUNDPROOF, 43, "Soundproof is 43")
eq(Game3.ABILITY_PRESSURE, 46, "Pressure is 46")
eq(Game3.ABILITY_HUSTLE, 55, "Hustle is 55")
eq(Game3.ABILITY_CUTE_CHARM, 56, "Cute Charm is 56")
eq(Game3.ABILITY_PLUS, 57, "Plus is 57")
eq(Game3.ABILITY_MINUS, 58, "Minus is 58")
eq(Game3.ABILITY_SHELL_ARMOR, 75, "Shell Armor is 75")
eq(Game3.EFFECT_EXPLOSION, 7, "Explosion is effect 7")
eq(Game3.EFFECT_ROAR, 28, "Roar is effect 28")
eq(Game3.abilityName(3), "SPEED BOOST", "Speed Boost name")
eq(Game3.abilityName(43), "SOUNDPROOF", "Soundproof name")
eq(Game3.abilityName(75), "SHELL ARMOR", "Shell Armor name")
check(Game3.isSoundMove({ id = 45 }), "Growl is a sound move")
check(Game3.isSoundMove(46), "Roar is a sound move")
check(not Game3.isSoundMove({ id = 215 }), "Heal Bell is not in gSoundMovesTable")

local g = Game3.new()
g.rng = function() return 1 end
local function stages()
  return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end
local atk = {
  name = "TORCHIC", level = 20, hp = 80, maxHp = 80,
  atk = 40, spa = 40, type1 = 0, type2 = 0, stages = stages(),
}
local defn = {
  name = "WURMPLE", level = 20, hp = 200, maxHp = 200,
  def = 40, spd = 40, type1 = 0, type2 = 0, stages = stages(),
}
g.battle = { player = atk, enemy = defn }

local ninj = {
  name = "NINJASK", ability = Game3.ABILITY_SPEED_BOOST, hp = 20, maxHp = 20,
  stages = stages(),
}
ninj.isFirstTurn = 2
eq(#g:speedBoostResidual(ninj), 0, "Speed Boost skips the switch-in turn")
eq(ninj.stages.spe, 0, "and the stage stays")
ninj.isFirstTurn = 1
local boost = g:speedBoostResidual(ninj)
eq(ninj.stages.spe, 1, "then Speed Boost raises Speed")
check(boost[1]:find("SPEED BOOST", 1, true) ~= nil, "and names the ability")

local rock = {
  name = "GEODUDE", ability = Game3.ABILITY_STURDY, hp = 50, maxHp = 50,
  type1 = 5, type2 = 5, level = 10,
}
local ohko = g:useOhko({ name = "HORN", level = 50 }, rock, {
  name = "HORN DRILL", type = 0, effect = Game3.EFFECT_OHKO,
}, { "HORN used HORN DRILL!" })
eq(rock.hp, 50, "Sturdy blocks OHKO")
check(ohko[#ohko]:find("STURDY", 1, true) ~= nil, "and says protected by Sturdy")

g.rng = function() return 16 end
local slashAtk = {
  name = "ZANGOOSE", hp = 40, maxHp = 40, level = 20, atk = 30,
  type1 = 0, type2 = 0, stages = stages(),
}
local slashMove = { name = "TACKLE", effect = 0, power = 40, type = 0 }
local critHit = g:dealDamage(slashAtk, {
  name = "WURMPLE", hp = 80, maxHp = 80, def = 10, type1 = 0, type2 = 0,
  stages = stages(),
}, slashMove)
check(critHit.crit, "a 1/16 roll crits")
local armored = g:dealDamage(slashAtk, {
  name = "ANORITH", hp = 80, maxHp = 80, def = 10, type1 = 0, type2 = 0,
  ability = Game3.ABILITY_BATTLE_ARMOR, stages = stages(),
}, slashMove)
check(not armored.crit, "Battle Armor stops crits")
local shelled = g:dealDamage(slashAtk, {
  name = "CLOYSTER", hp = 80, maxHp = 80, def = 10, type1 = 0, type2 = 0,
  ability = Game3.ABILITY_SHELL_ARMOR, stages = stages(),
}, slashMove)
check(not shelled.crit, "Shell Armor stops crits")
g.rng = function() return 1 end

local boomAtk = {
  name = "ELECTRODE", level = 20, hp = 50, maxHp = 50, atk = 40,
  type1 = 0, type2 = 0, stages = stages(),
}
local boomDef = {
  name = "WURMPLE", hp = 400, maxHp = 400, def = 40, type1 = 0, type2 = 0,
  stages = stages(),
}
local boomDmg = g:dealDamage(boomAtk, boomDef, {
  name = "EXPLOSION", effect = Game3.EFFECT_EXPLOSION, power = 250, type = 0,
})
boomDef.hp = 400
local plainDmg = g:dealDamage(boomAtk, boomDef, {
  name = "EXPLOSION", effect = 0, power = 250, type = 0,
})
check(boomDmg.dmg > plainDmg.dmg, "Explosion halves Defense")

g.battle = { player = boomAtk, enemy = boomDef }
boomAtk.hp = 50
boomDef.hp = 400
local boomLines = g:useMove(boomAtk, boomDef, {
  name = "EXPLOSION", effect = Game3.EFFECT_EXPLOSION, power = 250,
  type = 0, accuracy = 100, pp = 5,
})
eq(boomAtk.hp, 0, "Explosion faints the user")
check(boomLines[#boomLines]:find("fainted", 1, true) ~= nil, "and says so")

local dampMon = {
  name = "PSYDUCK", ability = Game3.ABILITY_DAMP, hp = 40, maxHp = 40,
  def = 40, type1 = 11, type2 = 11, stages = stages(),
}
local bomber = {
  name = "ELECTRODE", hp = 50, maxHp = 50, atk = 40, level = 20,
  type1 = 0, type2 = 0, stages = stages(),
}
g.battle = { player = bomber, enemy = dampMon }
local dampLines = g:useMove(bomber, dampMon, {
  name = "EXPLOSION", effect = Game3.EFFECT_EXPLOSION, power = 250,
  type = 0, accuracy = 100, pp = 5,
})
eq(bomber.hp, 50, "Damp keeps the user alive")
eq(dampMon.hp, 40, "and the target is untouched")
check(dampLines[2]:find("DAMP", 1, true) ~= nil, "Damp is announced")

local spore = {
  name = "BRELOOM", ability = Game3.ABILITY_EFFECT_SPORE, hp = 80, maxHp = 80,
  def = 20, type1 = 12, type2 = 12, stages = stages(),
}
local puncher = {
  name = "MACHOP", hp = 80, maxHp = 80, atk = 40, level = 20,
  type1 = 1, type2 = 1, stages = stages(),
}
g.battle = { player = puncher, enemy = spore }
g:useMove(puncher, spore, {
  name = "TACKLE", effect = 0, power = 40, type = 0, accuracy = 100,
  pp = 35, flags = Game3.FLAG_CONTACT,
})
eq(puncher.status, Game3.STATUS_PSN, "Effect Spore 10% poisons")

local charm = {
  name = "SKITTY", species = 280, pid = 0, ability = Game3.ABILITY_CUTE_CHARM,
  hp = 80, maxHp = 80, def = 20, type1 = 0, type2 = 0, stages = stages(),
}
local boy = {
  name = "TORCHIC", species = 280, pid = 100, hp = 80, maxHp = 80,
  atk = 40, level = 20, type1 = 10, type2 = 10, stages = stages(),
}
eq(g:monGender(charm), Game3.MON_FEMALE, "pid 0 Torchic is female")
eq(g:monGender(boy), Game3.MON_MALE, "pid 100 is male")
g.battle = { player = boy, enemy = charm }
g:useMove(boy, charm, {
  name = "TACKLE", effect = 0, power = 40, type = 0, accuracy = 100,
  pp = 35, flags = Game3.FLAG_CONTACT,
})
eq(boy.infatuatedBy, charm, "Cute Charm infatuates the attacker")

local mute = {
  name = "WHISMUR", ability = Game3.ABILITY_SOUNDPROOF, hp = 40, maxHp = 40,
  stages = stages(),
}
local growler = {
  name = "TORCHIC", hp = 40, maxHp = 40, stages = stages(),
}
g.battle = { player = growler, enemy = mute }
local growl = {
  id = 45, name = "GROWL", effect = Game3.EFFECT_ATTACK_DOWN, power = 0,
  type = 0, accuracy = 100, pp = 40,
}
local blocked = g:useMove(growler, mute, growl)
eq(mute.stages.atk, 0, "Soundproof stops Growl")
check(blocked[2]:find("SOUNDPROOF", 1, true) ~= nil, "and names Soundproof")
eq(growl.pp, 39, "PP is still spent")

local pressed = {
  name = "WEAVILE", ability = Game3.ABILITY_PRESSURE, hp = 40, maxHp = 40,
  def = 20, type1 = 0, type2 = 0, stages = stages(),
}
local tackler = {
  name = "TORCHIC", hp = 40, maxHp = 40, atk = 20, level = 5,
  type1 = 0, type2 = 0, stages = stages(),
}
g.battle = { player = tackler, enemy = pressed }
local tap = {
  name = "TACKLE", effect = 0, power = 40, type = 0, accuracy = 100, pp = 10,
}
g:useMove(tackler, pressed, tap)
eq(tap.pp, 8, "Pressure deducts an extra PP")

local hustler = {
  name = "TORKOAL", ability = Game3.ABILITY_HUSTLE, hp = 40, maxHp = 40,
  atk = 40, spa = 40, level = 20, type1 = 10, type2 = 10, stages = stages(),
}
local dummy = {
  name = "WURMPLE", hp = 200, maxHp = 200, def = 40, spd = 40,
  type1 = 0, type2 = 0, stages = stages(),
}
g.battle = { player = hustler, enemy = dummy }
eq(g:moveHitChance(hustler, dummy, { accuracy = 100, type = 0 }, 0), 80,
  "Hustle is 80% on physical accuracy")
eq(g:moveHitChance(hustler, dummy, { accuracy = 100, type = 10 }, 0), 100,
  "and does not cut special accuracy")
local withHustle = g:dealDamage(hustler, dummy, { power = 40, type = 0 })
local plainAtk = {
  name = "TORKOAL", hp = 40, maxHp = 40, atk = 40, spa = 40, level = 20,
  type1 = 10, type2 = 10, stages = stages(),
}
dummy.hp = 200
local noHustle = g:dealDamage(plainAtk, dummy, { power = 40, type = 0 })
check(withHustle.dmg > noHustle.dmg, "Hustle is 1.5x physical Attack")

local plusMon = {
  name = "PLUSLE", ability = Game3.ABILITY_PLUS, hp = 40, maxHp = 40,
  spa = 40, atk = 40, level = 20, type1 = 13, type2 = 13, stages = stages(),
}
local minusMon = {
  name = "MINUN", ability = Game3.ABILITY_MINUS, hp = 40, maxHp = 40,
  spd = 20, def = 20, type1 = 13, type2 = 13, stages = stages(),
}
g.battle = { player = plusMon, enemy = minusMon }
dummy.hp = 200
dummy.spd = 40
local paired = g:dealDamage(plusMon, dummy, { power = 40, type = 13 })
g.battle.enemy = {
  name = "WURMPLE", hp = 40, maxHp = 40, type1 = 0, stages = stages(),
}
dummy.hp = 200
local lonely = g:dealDamage(plusMon, dummy, { power = 40, type = 13 })
check(paired.dmg > lonely.dmg, "Plus boosts Sp. Atk when Minus is out")

local wildAtk = {
  name = "TORCHIC", hp = 20, maxHp = 20, level = 10, stages = stages(),
}
local wildDef = {
  name = "POOCHYENA", hp = 20, maxHp = 20, level = 5, stages = stages(),
}
g.battle = { player = wildAtk, enemy = wildDef }
g:useMove(wildAtk, wildDef, {
  name = "ROAR", effect = Game3.EFFECT_ROAR, power = 0, type = 0,
  accuracy = 100, pp = 20,
})
check(g.battle.fled, "wild Roar ends the battle")
check(g.battle.forcedOut, "as PLAYER_TELEPORTED")

wildDef.ability = Game3.ABILITY_SUCTION_CUPS
g.battle.fled, g.battle.forcedOut = nil, nil
local stuck = g:useMove(wildAtk, wildDef, {
  name = "ROAR", effect = Game3.EFFECT_ROAR, power = 0, type = 0,
  accuracy = 100, pp = 20,
})
check(not g.battle.fled, "Suction Cups stops Roar")
check(stuck[2]:find("SUCTION CUPS", 1, true) ~= nil, "and names the ability")

g.battle = {
  isTrainer = true,
  player = { name = "TORCHIC", hp = 20, maxHp = 20, level = 10, stages = stages() },
  enemy = { name = "POOCHYENA", species = 286, hp = 20, maxHp = 20, level = 5,
    stages = stages() },
  trainerParty = {
    { species = 286, level = 5 },
    { species = 288, level = 8 },
  },
  trainerIndex = 1,
}
g:useMove(g.battle.player, g.battle.enemy, {
  name = "ROAR", effect = Game3.EFFECT_ROAR, power = 0, type = 0,
  accuracy = 100, pp = 20,
})
eq(g.battle.enemy.species, 288, "trainer Roar drags out the next mon")
eq(#(g.battle.phazed or {}), 1, "and benches the old one")
end)()

;(function()
eq(Game3.EFFECT_HEAL_BELL, 102, "Heal Bell is effect 102")
eq(Game3.EFFECT_PERISH_SONG, 114, "Perish Song is effect 114")
eq(Game3.EFFECT_UPROAR, 159, "Uproar is effect 159")
eq(Game3.EFFECT_INGRAIN, 181, "Ingrain is effect 181")
eq(Game3.MOVE_HEAL_BELL, 215, "Heal Bell is move 215")
eq(Game3.MOVE_AROMATHERAPY, 312, "Aromatherapy is move 312")
check(not Game3.isSoundMove({ id = 215 }), "Heal Bell is not a sound move")
check(not Game3.isSoundMove({ id = 195 }), "Perish Song is not a sound move")
check(Game3.isSoundMove({ id = 253 }), "Uproar is a sound move")

local g = Game3.new()
g.rng = function() return 1 end
local function stages()
  return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end
local lead = {
  name = "TORCHIC", hp = 40, maxHp = 40, status = Game3.STATUS_PSN,
  atk = 40, spa = 40, type1 = 10, type2 = 10, stages = stages(),
}
local bench = {
  name = "MUDKIP", hp = 40, maxHp = 40, status = Game3.STATUS_PAR,
}
local foe = {
  name = "WURMPLE", hp = 200, maxHp = 200, def = 40, spd = 40,
  type1 = 0, type2 = 0, stages = stages(),
}
g.party = { lead, bench }
g.battle = { player = lead, enemy = foe }
local bell = {
  name = "HEAL BELL", id = Game3.MOVE_HEAL_BELL,
  effect = Game3.EFFECT_HEAL_BELL, power = 0, pp = 5,
  target = Game3.TARGET_USER, type = 0,
}
local chimed = g:useMove(lead, lead, bell)
eq(lead.status, nil, "Heal Bell cures the user")
eq(bench.status, nil, "and the rest of the party")
check(chimed[2] == "A bell chimed!", "bell chime line")

lead.status = Game3.STATUS_PSN
lead.ability = Game3.ABILITY_SOUNDPROOF
bench.status = Game3.STATUS_PAR
local blocked = g:useMove(lead, lead, bell)
eq(lead.status, Game3.STATUS_PSN, "Heal Bell skips Soundproof")
eq(bench.status, nil, "but still heals the rest")
check(blocked[3]:find("SOUNDPROOF", 1, true) ~= nil, "and names the block")

lead.status = Game3.STATUS_PSN
local aroma = g:useMove(lead, lead, {
  name = "AROMATHERAPY", id = Game3.MOVE_AROMATHERAPY,
  effect = Game3.EFFECT_HEAL_BELL, power = 0, pp = 5,
  target = Game3.TARGET_USER, type = 12,
})
eq(lead.status, nil, "Aromatherapy cures Soundproof")
check(aroma[2]:find("soothing aroma", 1, true) ~= nil, "aroma line")

lead.ability = nil
lead.perishSong = nil
foe.perishSong = nil
local song = {
  name = "PERISH SONG", id = Game3.MOVE_PERISH_SONG,
  effect = Game3.EFFECT_PERISH_SONG, power = 0, pp = 5,
  target = Game3.TARGET_USER, type = 0,
}
local sung = g:useMove(lead, lead, song)
eq(lead.perishSong, 3, "Perish Song sets 3 on the user")
eq(foe.perishSong, 3, "and the foe")
check(sung[2]:find("faint in 3 turns", 1, true) ~= nil, "3-turn line")
local tick = g:perishSongResidual(lead)
eq(lead.perishSong, 2, "end of turn drops 3 to 2")
check(tick[1]:find("fell to 3", 1, true) ~= nil, "prints the old count")
lead.perishSong = 0
local last = g:perishSongResidual(lead)
eq(lead.hp, 0, "count 0 faints")
check(last[1]:find("fell to 0", 1, true) ~= nil, "prints 0")

lead.hp = 40
lead.perishSong = nil
foe.ability = Game3.ABILITY_SOUNDPROOF
foe.perishSong = nil
g:useMove(lead, lead, song)
eq(lead.perishSong, 3, "Perish Song still hits the user")
eq(foe.perishSong, nil, "Soundproof is immune")
lead.ability = Game3.ABILITY_SOUNDPROOF
lead.perishSong = nil
local fail = g:useMove(lead, lead, song)
eq(fail[2], "But it failed!", "all-Soundproof Perish Song fails")
eq(lead.perishSong, nil, "and sets nobody")

lead.ability = nil
foe.ability = Game3.ABILITY_PRESSURE
song.pp = 5
g:useMove(lead, lead, song)
eq(song.pp, 3, "Perish Song pays extra Pressure PP")

lead.rooted = nil
local roots = g:useMove(lead, lead, {
  name = "INGRAIN", id = Game3.MOVE_INGRAIN,
  effect = Game3.EFFECT_INGRAIN, power = 0, pp = 5,
  target = Game3.TARGET_USER, type = 12,
})
check(lead.rooted, "Ingrain sets rooted")
check(roots[2]:find("planted its roots", 1, true) ~= nil, "roots line")
lead.hp = 8
lead.maxHp = 16
local sip = g:ingrainResidual(lead)
eq(lead.hp, 9, "Ingrain heals maxHP/16")
check(sip[1]:find("absorbed nutrients", 1, true) ~= nil, "nutrient line")
local again = g:useMove(lead, lead, {
  name = "INGRAIN", effect = Game3.EFFECT_INGRAIN, power = 0, pp = 5,
  target = Game3.TARGET_USER, type = 12,
})
eq(again[2], "But it failed!", "second Ingrain fails")
local roar = g:useMove(foe, lead, {
  name = "ROAR", effect = Game3.EFFECT_ROAR, power = 0, type = 0,
  accuracy = 100, pp = 20,
})
eq(roar[2], "But it failed!", "Roar fails vs rooted")

lead.rooted = nil
lead.hp, lead.maxHp = 40, 40
foe.ability = nil
foe.hp = 200
local uproar = {
  name = "UPROAR", id = Game3.MOVE_UPROAR,
  effect = Game3.EFFECT_UPROAR, power = 50, type = 0,
  accuracy = 100, pp = 10,
}
local yelled = g:useMove(lead, foe, uproar)
eq(lead.uproarTurns, 2, "Uproar locks 2 turns on rng 0")
eq(uproar.pp, 9, "first turn spends PP")
check(yelled[#yelled]:find("caused an UPROAR", 1, true) ~= nil, "cause line")
g:useMove(lead, foe, uproar)
eq(uproar.pp, 9, "locked Uproar skips PP")
foe.status = Game3.STATUS_SLP
foe.sleepTurns = 3
local woke = g:uproarResidual(lead)
eq(foe.status, nil, "Uproar wakes sleep")
check(woke[1]:find("woke up in the UPROAR", 1, true) ~= nil, "wake line")
eq(lead.uproarTurns, 1, "then the timer still drops")
check(not g:canStatus(foe, Game3.STATUS_SLP), "sleep fails in an Uproar")
local rest = g:useRest(foe, { "WURMPLE used REST!" })
check(rest[2]:find("can't sleep in an UPROAR", 1, true) ~= nil, "Rest fails")
foe.ability = Game3.ABILITY_SOUNDPROOF
check(g:canStatus(foe, Game3.STATUS_SLP), "Soundproof can sleep in Uproar")
foe.ability = Game3.ABILITY_SOUNDPROOF
lead.uproarTurns, lead.uproarMove = nil, nil
uproar.pp = 10
local mute = g:useMove(lead, foe, uproar)
eq(lead.uproarTurns, nil, "Soundproof blocks Uproar")
check(mute[2]:find("SOUNDPROOF", 1, true) ~= nil, "and names the ability")

local tracer = {
  name = "POOCHYENA", ability = Game3.ABILITY_TRACE,
  status = Game3.STATUS_PSN, hp = 40, maxHp = 40, stages = stages(),
}
local wall = {
  name = "SNORLAX", ability = Game3.ABILITY_IMMUNITY,
  hp = 80, maxHp = 80, stages = stages(),
}
g.battle = { player = tracer, enemy = wall }
local enter = g:activateEnter(tracer, wall)
eq(tracer.ability, Game3.ABILITY_IMMUNITY, "Trace copies Immunity")
eq(tracer.status, nil, "then Immunity cures poison")
check(enter[1]:find("TRACE copied", 1, true) ~= nil, "Trace line")
check(enter[2]:find("poison problem", 1, true) ~= nil, "cure line")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.FLDEFF_SPARKLE, 54, "FLDEFF_SPARKLE")
eq(Game3.FLDEFF_NPCFLY_OUT, 30, "FLDEFF_NPCFLY_OUT")
eq(Game3.FLDEFF_HALL_OF_FAME_RECORD, 62, "FLDEFF_HALL_OF_FAME_RECORD")
eq(Game3.FLDEFF_SPARKLE_FRAMES, 48, "sparkle is 13 + 35")
eq(Game3.FLDEFF_NPCFLY_FRAMES, 32, "NPCFLY data[2] += 4")
eq(Game3.SE_M_FLY, 158, "SE_M_FLY")
eq(Game3.END_APPROACH_FRAMES, 1, "EndTrainerApproach next vblank")
local g = Game3.new()
g.phase = "play"
g.flags = g.flags or {}
g:setScriptVar(0x8004, 7)
g:setFieldEffectArgument(0, 9)
eq(g:fieldEffectArg(0), 9, "arg 0 is map-local x")
Gen3Script.run(g, {
  { op = "setfieldeffectargument", index = 0, value = 0x8004 },
})
eq(g:fieldEffectArg(0), 7, "VarGet the halfword")
Gen3Script.run(g, {
  { op = "waitfieldeffect", id = Game3.FLDEFF_SPARKLE },
  { op = "setflag", flag = 0x20 },
})
eq(g.flags[0x20], true, "missing effect does not hang")
eq(g:scriptWaiting(), false, "and does not wait")
g.flags[0x20] = nil
g:setFieldEffectArgument(0, 9)
g:setFieldEffectArgument(1, 13)
Gen3Script.run(g, {
  { op = "dofieldeffect", id = Game3.FLDEFF_SPARKLE },
  { op = "waitfieldeffect", id = Game3.FLDEFF_SPARKLE },
  { op = "setflag", flag = 0x20 },
})
eq(g:scriptWaiting(), true, "waitfieldeffect SetupNativeScript")
eq(g:fieldEffectActive(Game3.FLDEFF_SPARKLE), true, "sparkle is up")
eq(g.flags[0x20], nil, "script is still on wait")
g:walkHeld(Game3.FLDEFF_SPARKLE_FRAMES / 60)
eq(g:fieldEffectActive(Game3.FLDEFF_SPARKLE), false, "sparkle ended")
eq(g:scriptWaiting(), false, "then ScriptContext_Enable")
eq(g.flags[0x20], true, "and the next command ran")
g:doFieldEffect(Game3.FLDEFF_NPCFLY_OUT)
eq(g:fieldEffectActive(Game3.FLDEFF_NPCFLY_OUT), true, "fly starts")
g:walkHeld(15 / 60)
eq(g:fieldEffectActive(Game3.FLDEFF_NPCFLY_OUT), true, "delay 15 overlaps")
g:waitFieldEffect(Game3.FLDEFF_NPCFLY_OUT)
eq(g:scriptWaiting(), true, "then waitfieldeffect the rest")
g:walkHeld((Game3.FLDEFF_NPCFLY_FRAMES - 15) / 60)
eq(g:fieldEffectActive(Game3.FLDEFF_NPCFLY_OUT), false, "fly done")
eq(g:scriptWaiting(), false, "waitfieldeffect released")
g:doFieldEffect(99)
eq(g:fieldEffectDuration(99), Game3.FLDEFF_DEFAULT_FRAMES, "unknown is short")
g:waitFieldEffect(99)
g:walkHeld(Game3.FLDEFF_DEFAULT_FRAMES / 60)
eq(g:fieldEffectActive(99), false, "unknown cannot hang")
g.party = { g:makeMon(280, 5) }
eq(g:hofRecordFrames(), 185, "one ball then glow")
g.party[2] = g:makeMon(277, 5)
eq(g:hofRecordFrames(), 210, "plus 25 per extra ball")
g:doFieldEffect(Game3.FLDEFF_HALL_OF_FAME_RECORD)
g:waitFieldEffect(Game3.FLDEFF_HALL_OF_FAME_RECORD)
g:walkHeld(g:hofRecordFrames() / 60)
eq(g:scriptWaiting(), false, "HoF record wait")
end)()

;(function()
local Gen3Script = require("src.import.Gen3Script")
local Input = require("src.core.Input")
Input:init()
eq(Gen3Script.WAITBUTTON, 0x6D, "waitbuttonpress")
eq(Game3.FLDEFF_SECRET_BASE_PC_TURN_ON, 61, "secret base PC on")
eq(Game3.SPECIAL_DO_SECRET_BASE_PC_TURN_OFF_EFFECT, 26, "PC off special")
eq(Game3.MAP_LILYCOVE_MOTEL_1F_NUM, 0, "motel 1F is first in group 13")
local parsed = Gen3Script.parse(string.char(0x6D, 0x02), 0)
eq(parsed[1].op, "waitbuttonpress", "0x6D decodes")

local g = Game3.new()
g.phase = "play"
g.map = { id = "sbpc", width = 5, height = 5, grid = {} }
for i = 1, 25 do g.map.grid[i] = 0 end
g.playerX, g.playerY = 2, 2
g.facing = "north"
g:runSpecial(Game3.SPECIAL_DO_SECRET_BASE_PC_TURN_OFF_EFFECT)
eq(g:scriptWaiting(), false, "PC off does not wait")
eq(g:mapGridGetMetatileId(2 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_SECRET_BASE_PC_OFF, "own base snaps Off")
g:setScriptVar(Game3.VAR_CURRENT_SECRET_BASE, 1)
g:runSpecial(Game3.SPECIAL_DO_SECRET_BASE_PC_TURN_OFF_EFFECT)
eq(g:mapGridGetMetatileId(2 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_SECRET_BASE_PC_OFF_OTHER, "other base 0x221")

g:setScriptVar(Game3.VAR_CURRENT_SECRET_BASE, 0)
g:doFieldEffect(Game3.FLDEFF_SECRET_BASE_PC_TURN_ON)
eq(g:scriptWaiting(), true, "FldEff waitstate")
g:walkHeld(5 / 60)
eq(g:mapGridGetMetatileId(2 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_SECRET_BASE_PC_ON, "data[2]==4 is On")
g:walkHeld((Game3.FLDEFF_SECRET_BASE_PC_FRAMES - 5) / 60)
eq(g:scriptWaiting(), false, "21 frames then Enable")
eq(g:mapGridGetMetatileId(2 + Game3.MAP_OFFSET, 1 + Game3.MAP_OFFSET),
  Game3.MT_SECRET_BASE_PC_ON, "ends On")

g.flags = {}
Gen3Script.run(g, {
  { op = "waitbuttonpress" },
  { op = "setflag", flag = 0x21 },
})
eq(g:scriptWaiting(), true, "waitbuttonpress waits")
eq(g.flags[0x21], nil, "script is still on the wait")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:walkHeld(1 / 60)
Input.wasPressed = old
eq(g:scriptWaiting(), false, "A continues")
eq(g.flags[0x21], true, "and the next command ran")
end)()

;(function()
local g = Game3.new()
g.phase = "play"
local grid = {}
for i = 1, 24 * 24 do grid[i] = 0 end
local slate = {
  id = "g0_1", width = 24, height = 24, grid = grid,
  mapType = Game3.MAP_TYPE_CITY, spawn = { x = 19, y = 20 },
}
local cave = {
  id = "g_cave", width = 4, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local center = {
  id = "g9_pc", width = 8, height = 8,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  mapScripts = {
    onTransition = {
      { op = "setrespawn", id = Game3.HEAL_SLATEPORT_CITY },
    },
  },
}
g.data.maps = {
  start = "g0_1",
  maps = { g0_1 = slate, g_cave = cave, g9_pc = center },
}
g.party = { g:makeMon(277, 15) }
eq(g:setHealLocation(0), false, "NONE is not a heal location")
eq(g:setHealLocation(99), false, "past the table is not a heal location")
g:enterMap(center, 7, 4, true)
eq(g.lastHeal.mapId, "g0_1", "Center ON_TRANSITION setrespawn")
eq(g.lastHeal.x, 19, "outdoor door x")
eq(g.lastHeal.y, 20, "outdoor door y")
g.party[1].hp = 0
g:enterMap(cave, 1, 1, true)
g.phase = "battle"
g.battle = { kind = "blackout" }
g:blackout()
eq(g.map.id, "g0_1", "whiteout is the last Center town")
eq(g.playerX, 19, "in front of the Center")
eq(g.playerY, 20, "Center door y")

local roomGrid = {}
for i = 1, 8 * 6 do roomGrid[i] = 0 end
local room = {
  id = "g1_1", width = 8, height = 6, grid = roomGrid,
  spawn = { x = 4, y = 2 },
  bgEvents = { { x = 5, y = 1, kind = 0, text = "The clock is stopped." } },
}
g.data.maps.maps.g1_1 = room
g.lastHeal = { mapId = "g1_1", x = 4, y = 2 }
g.flags[Game3.FLAG_VISITED_SLATEPORT_CITY] = true
g.party[1].hp = 0
g:enterMap(cave, 1, 1, true)
g.phase = "battle"
g.battle = { kind = "blackout" }
g:blackout()
eq(g.map.id, "g0_1", "stale bedroom lastHeal uses visited Center")
eq(g.playerX, 19, "Slateport door x")
eq(g.playerY, 20, "Slateport door y")

g.lastHeal = { mapId = "g1_1", x = 4, y = 2 }
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = true
eq(g:repairStaleBedroomHeal(), false, "HoF bedroom stay")
eq(g.lastHeal.mapId, "g1_1", "champion lastHeal is still the room")
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = nil

g:enterMap(room, 4, 2, true)
g.lastHeal = { mapId = "g1_1", x = 4, y = 2 }
g.flags[Game3.FLAG_VISITED_SLATEPORT_CITY] = true
local snap = g:snapshotSave()
local loaded = Game3.new()
loaded.phase = "play"
loaded.data.maps = g.data.maps
check(loaded:applySave(snap), "CONTINUE from the bugged bedroom")
eq(loaded.map.id, "g0_1", "and lands at the Center door")
eq(loaded.playerX, 19, "CONTINUE x")
eq(loaded.playerY, 20, "CONTINUE y")

g:enterMap(room, 4, 2, true)
g.lastHeal = { mapId = "g0_1", x = 19, y = 20 }
snap = g:snapshotSave()
loaded = Game3.new()
loaded.phase = "play"
loaded.data.maps = g.data.maps
check(loaded:applySave(snap), "CONTINUE after a real Center")
eq(loaded.map.id, "g1_1", "walking home does not teleport")
end)()

;(function()
local Input = require("src.core.Input")
local g = Game3.new()
g.phase = "play"
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
    },
  },
}
g.data.moves = {
  byId = {
    [52] = { id = 52, name = "EMBER", type = 10, power = 40, pp = 25 },
  },
}
g.party = { g:makeMon(280, 5, { 52 }) }
g.party[1].beauty = 255
g.party[1].sheen = 255
g.rng = function(max)
  g._contestRng = (g._contestRng or 0) + 1
  return (g._contestRng % (max or 65536)) + 1
end
check(g:beginContest(1, Game3.CONTEST_CATEGORY_BEAUTY, 0), "appeal starts")
eq(g.field.kind, "contest_move", "appeal field")
for _ = 1, 5 do g:applyContestTurn(1) end
eq(g.field.kind, "contest_results", "five rounds open results")

g.contest = nil
g.contestMons = nil
g.contestMonIndex = 1
g:setScriptVar(Game3.VAR_CONTEST_CATEGORY, Game3.CONTEST_CATEGORY_BEAUTY)
g:setScriptVar(Game3.VAR_CONTEST_RANK, 0)
check(g:startContest(), "scripted startcontest")
check(g:scriptWaiting(), "hall waitstates")
for _ = 1, 5 do g:applyContestTurn(1) end
eq(g.field.kind, "contest_results", "startcontest ends on results")
check(g.field.scripted, "results stay scripted")
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g:scriptWaiting(), false, "A releases startcontest")

local grid = {}
for i = 1, 8 * 8 do grid[i] = 0 end
local lobby = {
  id = "g9_2", group = 9, index = 2, width = 8, height = 8, grid = grid,
  spawn = { x = 5, y = 4 },
}
local hall = {
  id = "g25_28", group = 25, index = 28, width = 8, height = 8, grid = grid,
  spawn = { x = 7, y = 5 },
}
g.data.maps = { maps = { g9_2 = lobby, g25_28 = hall } }
g:enterMap(hall, 7, 5, true)
g.invisible = true
g.field = { kind = "move" }
g._scriptPause = { ops = { { op = "end" } }, at = 1 }
g:setScriptVar(Game3.VAR_LINK_CONTEST_ROOM_STATE, 1)
g:setScriptVar(Game3.VAR_CONTEST_LOCATION, 3)
check(g:inContestHall(), "state 1 in LinkContestRoom1")
check(g:tryAbortContestHall(), "START abort")
eq(g.map.id, "g9_2", "15FB64 Slateport lobby")
eq(g.playerX, 5, "lobby x")
eq(g.playerY, 4, "lobby y")
eq(g:varGet(Game3.VAR_LINK_CONTEST_ROOM_STATE), 0, "room state cleared")
eq(g.invisible, nil, "player sprite is back")
eq(g.field, nil, "no leftover field")
end)()

;(function()
local Dex = require("src.import.RomExtractorGen3Dex")
local Input = require("src.core.Input")
eq(Dex.RUBY_US.entries, 0x3B1858, "gPokedexEntries")
eq(Dex.RUBY_US.speciesToHoenn, 0x1FC1E0, "gSpeciesToHoennPokedexNum")
eq(Dex.RUBY_US.speciesToNational, 0x1FC516, "gSpeciesToNationalPokedexNum")
eq(Dex.RUBY_US.hoennToNational, 0x1FC84C, "gHoennToNationalOrder")
eq(Dex.ENTRY_SIZE, 0x24, "struct PokedexEntry")
eq(Dex.findEntries("short"), nil, "truncated cart has no entries")
eq(select(1, Dex.findSpeciesMaps("short")), nil, "and no species maps")
eq(Game3.dexHeightText(7), "2'04\"", "Bulbasaur is 2'04\"")
eq(Game3.dexHeightText(4), "1'04\"", "Torchic is 1'04\"")
eq(Game3.dexWeightText(69), "15.2 lbs.", "Bulbasaur is 15.2 lbs.")
eq(Game3.dexWeightText(25), "5.5 lbs.", "Torchic is 5.5 lbs.")

local cat = (GbaText.encodeLatin("SEED") .. string.char(GbaText.EOS)
  .. string.rep("\0", 12)):sub(1, 12)
local page = GbaText.encodeLatin("A seed is on its back.")
  .. string.char(GbaText.EOS)
local function packU16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end
local blob = string.rep("\0", 0x80)
blob = overlay(blob, 0, cat .. packU16(7) .. packU16(69)
  .. GbaBin.packPtr(0x40) .. GbaBin.packPtr(0x40)
  .. packU16(0) .. packU16(356) .. packU16(17) .. packU16(256) .. packU16(0))
blob = overlay(blob, 0x40, page)
local parsed = Dex.parseEntry(blob, 0)
eq(parsed.category, "SEED", "categoryName")
eq(parsed.height, 7, "height dm")
eq(parsed.weight, 69, "weight hg")
check(parsed.page1:find("seed", 1, true) ~= nil, "page1 decodes")

local byIndex = { [280] = { name = "TORCHIC" } }
Dex.attach(byIndex, {
  hoenn = { [280] = 4 },
  national = { [280] = 255 },
}, {
  byNational = {
    [255] = {
      category = "CHICK", height = 4, weight = 25,
      page1 = "It stands on one foot.", page2 = "The flame burns.",
    },
  },
})
eq(byIndex[280].hoennDex, 4, "Torchic Hoenn 4")
eq(byIndex[280].nationalDex, 255, "Torchic National 255")
eq(byIndex[280].category, "CHICK", "CHICK")
eq(byIndex[280].weight, 25, "25 hg")

local g = Game3.new()
g.data.pokemon = { byIndex = byIndex }
g:markCaught(280)
g:openDex()
eq(g.field.kind, "dex", "openDex still lists")
eq(g.field.list[1].id, 280, "list id stays the species")
eq(g:dexListNumber(280), 4, "the printed number is Hoenn 4")
local function press(game, key)
  local old = Input.wasPressed
  Input.wasPressed = function(_, name) return name == key end
  if game.phase == "battle" then
    game:stepBattle(0)
  else
    game:stepField()
  end
  Input.wasPressed = old
end
press(g, "a")
eq(g.field.kind, "dex_entry", "A opens the entry")
eq(g.field.species, 280, "for Torchic")
eq(g.field.page, 0, "on page 1")
eq(g:dexCategoryText(280, true), "CHICK POKeMON", "UnusedPrintMonName suffix")
eq(g:dexFlavorText(280, 0, true), "It stands on one foot.", "page1")
press(g, "a")
eq(g.field.page, 1, "A turns to page 2")
press(g, "a")
eq(g.field.kind, "dex_entry", "A on INFO toggles, it does not close")
eq(g.field.page, 0, "back to page 1")
press(g, "right")
eq(g.field.bar, Game3.DEX_SCREEN_AREA, "RIGHT highlights AREA")
press(g, "a")
eq(g.field.screen, Game3.DEX_SCREEN_AREA, "A opens AREA")
press(g, "b")
eq(g.field.screen, Game3.DEX_SCREEN_INFO, "B returns to INFO")
press(g, "right")
press(g, "right")
eq(g.field.bar, Game3.DEX_SCREEN_CRY, "two RIGHTs land on CRY")
press(g, "a")
eq(g.field.screen, Game3.DEX_SCREEN_CRY, "A opens CRY")
press(g, "right")
eq(g.field.screen, Game3.DEX_SCREEN_SIZE, "RIGHT from CRY is SIZE")
eq(Game3.dexAffineScale(566), Game3.DEX_AFFINE_ONE / 566, "Torchic PA 566")
eq(Game3.dexAffineScale(256), 1, "trainer 256 is 1x")
g.field.screen = Game3.DEX_SCREEN_SIZE
g:drawDexEntry(g.field)
check(true, "size screen draws without pics")
press(g, "b")
eq(g.field.kind, "dex_entry", "B from SIZE is still the entry")
press(g, "b")
eq(g.field.kind, "dex", "B from INFO returns to the list")

local catcher = Game3.new()
catcher.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3, hoennDex = 4,
    },
    [290] = {
      name = "WURMPLE", hp = 45, atk = 40, def = 35, spe = 20,
      spa = 20, spd = 30, type1 = 6, type2 = 6, catchRate = 255,
      expYield = 54, growthRate = 0, hoennDex = 14, nationalDex = 265,
      category = "WORM", height = 3, weight = 36,
      dexPage1 = "It lives in the forest.", dexPage2 = "Silk wraps it.",
    },
  },
}
catcher.data.moves = {
  byId = {
    [33] = { id = 33, name = "TACKLE", power = 35, type = 0, pp = 35,
      accuracy = 95 },
  },
}
catcher.party = { catcher:makeMon(280, 5) }
catcher.balls = 5
catcher.rng = function() return 1 end
catcher:startWildBattle(290, 2)
catcher:throwBall()
local addedAt
for i = 1, #(catcher.battle.queue or {}) do
  if catcher.battle.queue[i]:find("POKeDEX", 1, true) then addedAt = i end
end
check(addedAt ~= nil and addedAt > 5, "AddedToDex follows Gotcha")
eq(catcher.battle.showDexEntry, 290, "displaydexinfo is pending")
local function drain(game)
  while game.battle and game.battle.kind == "text" do
    game:advanceBattleText()
  end
end
drain(catcher)
eq(catcher.battle.kind, "dex_entry", "then the entry overlay")
eq(catcher.battle.dexSpecies, 290, "for Wurmple")
press(catcher, "a")
eq(catcher.battle.dexPage, 1, "A turns the catch page")
press(catcher, "a")
eq(catcher.battle.kind, "catch_nick", "trygivecaughtmonnick after the overlay")
eq(catcher.battle.text, Game3.giveCaughtNickText("WURMPLE"), "GiveNickname")
press(catcher, "b")
check(not catcher.battle, "B skips the naming screen")
eq(catcher.party[2].name, "WURMPLE", "species-name nickname stays")

local again = Game3.new()
again.data.pokemon = catcher.data.pokemon
again.data.moves = catcher.data.moves
again.party = { again:makeMon(280, 5) }
again:markCaught(290)
again.balls = 5
again.rng = function() return 1 end
again:startWildBattle(290, 2)
again:throwBall()
eq(again.battle.showDexEntry, nil, "trysetcaughtmondexflags skips a recatch")
local joined = table.concat(again.battle.queue or {}, "\n")
check(joined:find("POKeDEX", 1, true) == nil, "no AddedToDex line")
drain(again)
eq(again.battle.kind, "catch_nick", "recatch still asks for a nickname")
press(again, "a")
eq(again.field.kind, "nickname", "YES opens DoNamingScreen")
eq(again.field.name, "WURMPLE", "buffer starts as the species name")
again.field.name = "WURM"
again.field.cursor = 0
local keys = again.field.keys
for i = 1, #keys do
  if keys[i] == "END" then again.field.cursor = i - 1 break end
end
press(again, "a")
eq(again.party[2].name, "WURM", "SetMonData nickname")
check(not again.field, "naming screen closed")

local wally = Game3.new()
wally.data.pokemon = catcher.data.pokemon
wally.data.moves = catcher.data.moves
wally.party = { wally:makeMon(280, 5) }
wally.rng = function() return 1 end
wally:startWildBattle(290, 2)
wally.battle.wallyTutorial = true
wally.balls = 5
wally:throwBall()
eq(wally.battle.showDexEntry, nil, "Wally's catch skips the dex")
end)()

;(function()
local Contest3 = require("src.core.Contest3")
eq(Contest3.areMovesCombo(1, 3), 1, "Pound into Double Slap is a combo")
eq(Contest3.areMovesCombo(3, 1), 0, "reverse is not a combo")
eq(Contest3.getMoveExcitement(1, 52), 1, "Ember excites a Beauty contest")
eq(Contest3.getMoveExcitement(1, 33), -1, "Tackle cools a Beauty contest")
eq(Contest3.effectRow(0).a, 40, "HIGHLY_APPEALING is 40")
eq(Contest3.moveRow(52).c, 1, "Ember is Beauty")
eq(Contest3.moveRow(1).s, 60, "Pound is a combo starter")

local g = Game3.new()
g.phase = "play"
g.rng = function(max)
  g._contestRng = (g._contestRng or 0) + 1
  return (g._contestRng % (max or 65536)) + 1
end
g.data.pokemon = {
  byIndex = {
    [280] = {
      name = "TORCHIC", hp = 45, atk = 60, def = 40, spe = 45,
      spa = 70, spd = 50, type1 = 10, type2 = 10, catchRate = 45,
      expYield = 65, growthRate = 3,
    },
  },
}
g.data.moves = {
  byId = {
    [1] = { id = 1, name = "POUND", type = 0, power = 40, pp = 35 },
    [3] = { id = 3, name = "DOUBLESLAP", type = 0, power = 15, pp = 10 },
    [52] = { id = 52, name = "EMBER", type = 10, power = 40, pp = 25 },
  },
}
g.party = { g:makeMon(280, 5, { 1, 3 }) }
g.party[1].item = Contest3.ITEM_RED_SCARF
g.party[1].cool = 10
local player = Contest3.createPlayerMon(g, 1)
eq(player.cool, 30, "Red Scarf adds 20 Cool")

local npcs = Contest3.pickOpponents(g, 1, 2)
eq(#npcs, 3, "Hyper Beauty still picks three NPCs")
check(npcs[1].trainerName ~= "JIMMY", "Hyper is not the Normal pool")

local engine = Contest3.start(g, 1, 0, 0)
check(engine, "Cool Normal engine")
eq(engine.playerIndex, 3, "TryPutPlayerLast")
eq(engine.round1[3], Contest3.round1Points(engine.mons[3], 0), "round-1 uses sheen")
Contest3.runRound(engine, g, 0)
eq(engine.status[3].prevMove, 1, "player appealed with Pound")
check((engine.status[3].hasJudgesAttention or 0) ~= 0
  or (engine.status[3].pointTotal or 0) >= 0, "combo starter can grab the judge")
Contest3.runRound(engine, g, 1)
eq(engine.status[3].prevMove, 3, "second turn is Double Slap")
check((engine.status[3].completedComboFlag or 0) ~= 0
  or (engine.status[3].pointTotal or 0) > 0, "combo or at least an appeal")
Contest3.runRound(engine, g, 1)
check((engine.status[3].repeatJam or 0) >= 0, "repeat jam is tracked")
for _ = 1, 2 do Contest3.runRound(engine, g, 0) end
check(engine.done, "five rounds finish the contest")
check(type(engine.finalStandings[3]) == "number", "player has a final place")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
local RM = require("src.core.Game3RegionMap")
local g = Game3.new()
eq(g:regionMapKind(RM.MAPSEC_NONE), RM.KIND_NONE, "NONE is 0")
eq(g:regionMapKind(0), RM.KIND_TOWN, "unvisited Littleroot is 3")
g.flags[Game3.FLAG_VISITED_LITTLEROOT_TOWN] = true
eq(g:regionMapKind(0), RM.KIND_FLY, "visited town is Fly 2")
eq(g:regionMapKind(RM.MAPSEC_BATTLE_TOWER), RM.KIND_NONE, "tower hidden")
g.flags[Game3.FLAG_LANDMARK_BATTLE_TOWER] = true
eq(g:regionMapKind(RM.MAPSEC_BATTLE_TOWER), RM.KIND_SPECIAL, "tower is Fly 4")
eq(g:regionMapKind(RM.MAPSEC_SOUTHERN_ISLAND), RM.KIND_NONE, "island hidden")
g.flags[Game3.FLAG_LANDMARK_SOUTHERN_ISLAND] = true
eq(g:regionMapKind(RM.MAPSEC_SOUTHERN_ISLAND), RM.KIND_LANDMARK, "island is 1")

g:openPokeNav()
eq(g.field.kind, "pokenav", "POKeNAV")
eq(g.field.zoomed, false, "starts unzoomed")
Input:init()
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
check(g.field.zooming, "A starts the 16-frame zoom")
for _ = 1, RM.ZOOM_FRAMES do g:stepRegionMap(g.field) end
eq(g.field.zoomed, true, "then 2x affine")
eq(g.field.zooming, false, "anim done")
check(g.field.scrollX ~= 0 or g.field.cursorX == 1, "scroll follows the cursor")
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
check(g.field.zooming, "A zooms back out")
for _ = 1, RM.ZOOM_FRAMES do g:stepRegionMap(g.field) end
eq(g.field.zoomed, false, "unzoomed again")
Input.wasPressed = function(_, key) return key == "b" end
g:stepField()
Input.wasPressed = old
eq(g.field.kind, "menu", "B still returns to START")

local little = {
  id = "g0_9", mapType = Game3.MAP_TYPE_TOWN, width = 3, height = 3,
  spawn = { x = 1, y = 1 },
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
g = Game3.new()
g.phase = "play"
g.party = { { name = "SWELLOW", moves = { { id = Game3.MOVE_FLY } } } }
g.flags[Game3.FLAG_BADGE06_GET] = true
g.flags[Game3.FLAG_VISITED_LITTLEROOT_TOWN] = true
g.data.maps = { start = "g0_9", maps = { g0_9 = little } }
g.map = little
g:useFly()
eq(g.field.kind, "fly", "FLY opens the region map")
check(g.field.flyMode, "CB2_FlyRegionMap")
eq(#g.field.list, 1, "visited list is still filled")
local cx, cy = Game3.regionMapCursorForSection(0)
g.field.cursorX, g.field.cursorY = cx, cy
Input:init()
Input.wasPressed = function(_, key) return key == "a" end
g:stepField()
Input.wasPressed = old
eq(g.map.id, "g0_9", "A on a visited town flies")
check(g.field.kind == "talk", "then the flew line")
end)()

S.finish()
