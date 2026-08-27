-- Ruby Phase 58: copyright → intro → title → CONTINUE/NEW GAME/OPTION → Birch.
-- Fixture bytes only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_boot_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("ruby boot cinema")
local check = S.check
local eq = S.eq

local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
local GbaText = require("src.import.GbaText")
local BootData = require("src.import.RomExtractorGen3Boot")

Input:init()

local function press(game, name)
  if game.phase ~= "boot" then return end
  local old = Input.wasPressed
  Input.wasPressed = function(_, key) return key == name end
  game:stepBoot(0)
  Input.wasPressed = old
end

local function mash(game, kind, n)
  n = n or 12
  for _ = 1, n do
    if game.phase ~= "boot" then return true end
    if game.boot and game.boot.kind == kind then return true end
    press(game, "a")
  end
  return game.phase ~= "boot" or (game.boot and game.boot.kind == kind)
end

;(function()
local g = Game3.new()
eq(g.phase, "boot", "new games start in boot")
eq(g.boot.kind, Game3.BOOT_COPYRIGHT, "on the copyright card")
press(g, "a")
press(g, "start")
eq(g.boot.kind, Game3.BOOT_COPYRIGHT, "the copyright card is not skippable")
g:stepBoot(2.9)
eq(g.boot.kind, Game3.BOOT_COPYRIGHT, "it holds for three seconds")
g:stepBoot(0.2)
eq(g.boot.kind, Game3.BOOT_INTRO, "then the intro cinema opens")
press(g, "b")
eq(g.boot.kind, Game3.BOOT_TITLE, "any key skips the intro")
press(g, "select")
eq(g.boot.kind, Game3.BOOT_TITLE, "SELECT does not leave the title")
press(g, "start")
eq(g.boot.kind, Game3.BOOT_MENU, "START opens the main menu")
eq(g:menuActions()[1], "new", "no save: NEW GAME is first")
eq(g:menuActions()[2], "option", "then OPTION")
press(g, "b")
eq(g.boot.kind, Game3.BOOT_TITLE, "B returns to the title")
g:stepBoot(80)
eq(g.boot.kind, Game3.BOOT_COPYRIGHT, "the title loops back after 80s")
end)()

;(function()
local g = Game3.new()
g.saveExists = true
eq(g:menuActions()[1], "continue", "a save puts CONTINUE first")
eq(#g:menuActions(), 3, "CONTINUE / NEW GAME / OPTION")
function g.hasSave() return true end
g:openMainMenu()
press(g, "a")
eq(g.phase, "boot", "CONTINUE with no file stays on the menu")
check(g.bootHint ~= nil, "and reports the missing save")
eq(g:playTimeString(3723), "1:02", "CONTINUE prints H:MM")
eq(g:playTimeString(0), "0:00", "a new clock is 0:00")
end)()

;(function()
local g = Game3.new()
g:openMainMenu()
press(g, "down")
press(g, "a")
eq(g.boot.kind, Game3.BOOT_OPTION, "OPTION opens the settings")
eq(g.options.textSpeed, 2, "TEXT SPEED starts on MID")
press(g, "a")
eq(g.options.textSpeed, 3, "A cycles MID to FAST")
eq(g.options.stereo, false, "SOUND starts on MONO")
press(g, "down")
press(g, "a")
eq(g.options.battleScene, false, "BATTLE SCENE toggles OFF")
press(g, "b")
eq(g.boot.kind, Game3.BOOT_MENU, "B returns to the main menu")
end)()

;(function()
local g = Game3.new()
g.map = { id = "truck", width = 2, height = 2, grid = { 0, 0, 0, 0 } }
g:openMainMenu()
press(g, "a")
eq(g.boot.kind, Game3.BOOT_BIRCH, "NEW GAME starts Birch's speech")
eq(g.phase, "boot", "and does not skip into the field")
eq(g.gender, nil, "gender is unpicked")
check(mash(g, Game3.BOOT_GENDER), "A walks through Birch to BOY/GIRL")
press(g, "down")
press(g, "a")
eq(g:isFemale(), true, "GIRL applies May")
eq(g.boot.kind, Game3.BOOT_NAME, "then the name list")
eq(g:presetNames()[2], "MAY", "May's presets follow gender")
press(g, "down")
press(g, "a")
eq(g.customName, "MAY", "the first preset is MAY")
eq(g.boot.kind, Game3.BOOT_CONFIRM, "and confirms the name")
check(mash(g, nil, 16), "the rest of Birch ends the speech")
eq(g.phase, "play", "a cached map drops into the field")
eq(g:playerName(), "MAY", "the chosen name is the trainer")
end)()

;(function()
local g = Game3.new()
g:startBirchSpeech()
check(mash(g, Game3.BOOT_GENDER), "Birch reaches gender")
press(g, "a")
eq(g:isFemale(), false, "BOY is Brendan")
press(g, "a")
eq(g.boot.kind, Game3.BOOT_NAMING, "NEW NAME opens the keyboard")
eq(g.boot.name, "BRENDAN", "seeded with the default")
press(g, "b")
press(g, "b")
press(g, "b")
press(g, "b")
press(g, "b")
press(g, "b")
press(g, "b")
eq(g.boot.name, "", "B deletes")
press(g, "a")
eq(g.boot.name, "A", "A types the cursor letter")
-- END is the last key.
g.boot.cursor = #g.boot.keys - 1
press(g, "a")
eq(g.customName, "A", "END confirms the typed name")
eq(g.boot.kind, Game3.BOOT_CONFIRM, "and asks So it's A?")
end)()

;(function()
local skip = Game3.new()
skip.map = { id = "town", width = 2, height = 2, grid = { 0, 0, 0, 0 } }
skip:advance()
eq(skip.phase, "play", "advance() still skips boot when a map is cached")
eq(skip.boot, nil, "and clears the cinema")
local roster = Game3.new()
roster:advance()
eq(roster.phase, "roster", "advance() still opens the species list without a map")
end)()

;(function()
local eos = string.char(GbaText.EOS)
local para = string.char(GbaText.PARA)
local blob = eos
  .. GbaText.encodeLatin(
    "Hi! Sorry to keep you waiting! Welcome to the world of POKeMON!")
  .. para
  .. GbaText.encodeLatin("My name is BIRCH.")
  .. eos
  .. GbaText.encodeLatin("NEW GAME")
  .. eos
local pages = BootData.readPages(blob, "Sorry to keep you waiting")
check(pages ~= nil, "the extractor finds Birch's welcome")
eq(pages[1]:sub(1, 4), "Hi! ", "page 1 keeps the leading line")
eq(pages[2], "My name is BIRCH.", "\\p splits a page")
local data = BootData.extract(blob)
eq(data.menu.newGame, "NEW GAME", "NEW GAME is pulled from the ROM")
eq(data.species.azurill, 350, "Azurill is Birch's demo mon")
eq(data.species.groudon, 405, "Groudon is the title mon")
local decoded = GbaText.decodePages(
  GbaText.encodeLatin("So it's ")
    .. string.char(GbaText.BUFFER, 0x01)
    .. GbaText.encodeLatin("?")
    .. eos)
eq(decoded[1], "So it's {PLAYER}?", "{PLAYER} is a buffer byte")
local strVar = GbaText.decodePages(
  GbaText.encodeLatin("My ")
    .. string.char(GbaText.BUFFER, GbaText.PH_STR_VAR_1)
    .. GbaText.encodeLatin(".")
    .. eos)
eq(strVar[1], "My {STR_VAR_1}.", "STR_VAR_1 is not collapsed to PLAYER")
local lined = GbaText.decodePages(
  GbaText.encodeLatin("LINE")
    .. string.char(GbaText.NEWLINE)
    .. GbaText.encodeLatin("TWO")
    .. eos)
eq(lined[1], "LINE\nTWO", "\\n stays a line break inside a page")
end)()

;(function()
local cells = {}
for i = 1, 25 do cells[i] = 0 end
local townCells = {}
for i = 1, 64 do townCells[i] = 0 end
local truck = {
  id = "g25_40", width = 5, height = 5, connections = {},
  grid = cells, spawn = { x = 1, y = 2 },
  objects = {
    { x = 0, y = 0, localId = 1 },
    { x = 0, y = 3, localId = 2 },
    { x = 2, y = 3, localId = 3 },
  },
}
local town = {
  id = "g0_9", width = 8, height = 8, grid = townCells, spawn = { x = 5, y = 7 },
}
local g = Game3.new()
g.data.maps = { start = "g0_9", maps = { g25_40 = truck, g0_9 = town } }
g.party = { { name = "TORCHIC" } }
g.flags = { [99] = true }
g.scriptVars = { [Game3.VAR_LITTLEROOT_INTRO_STATE] = 6 }
g.money = 9999
g.map = town
g.playerX, g.playerY = 5, 7
g.phase = "boot"
g:startBirchSpeech()
eq(#g.party, 0, "NEW GAME clears the party")
eq(g.flags[99], nil, "and leftover flags")
eq(g.scriptVars[Game3.VAR_LITTLEROOT_INTRO_STATE], nil, "and intro vars")
eq(g.money, Game3.START_MONEY, "and money")
eq(g.boot.kind, Game3.BOOT_BIRCH, "then Birch talks")
eq(g.phase, "boot", "and stays in the cinema")
check(mash(g, Game3.BOOT_GENDER), "A walks through Birch to BOY/GIRL")
press(g, "a")
press(g, "down")
press(g, "a")
eq(g.customName, "BRENDAN", "the first preset is BRENDAN")
check(mash(g, nil, 24), "the rest of Birch ends the speech")
eq(g.phase, "play", "NEW GAME drops into the field, not the species list")
eq(g.map.id, "g25_40", "in the truck")
eq(g.playerX, 2, "dummy warp is layout width/2")
eq(g.playerY, 2, "and height/2")
eq(g.flags[Game3.FLAG_SYS_TV_WATCH], true, "UpdateTVScreensOnMap sets WATCH")
eq(g.scriptVars[Game3.VAR_SHROOMISH_SIZE_RECORD], Game3.SIZE_RECORD_DEFAULT,
  "Shroomish size record is Marco")
eq(g.scriptVars[Game3.VAR_BARBOACH_SIZE_RECORD], Game3.SIZE_RECORD_DEFAULT,
  "Barboach size record is Marco")
end)()

;(function()
local g = Game3.new()
g.data.title = { species = { azurill = 298, groudon = 389 } }
local az, gr = g:bootSpecies()
eq(az, 350, "old caches still show Azurill, not Seedot")
eq(gr, 405, "old caches still show Groudon, not Cradily")
local az2, gr2 = Game3.new():bootSpecies()
eq(az2, 350, "fallback Azurill is SPECIES_AZURILL")
eq(gr2, 405, "fallback Groudon is SPECIES_GROUDON")
end)()

S.finish()
