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
local Zoom = require("src.render.Zoom")
local Tilt = require("src.render.Tilt")
local oldOff, oldLevel = Zoom.offset, Tilt.level
Zoom.reset()
Tilt.reset()
local g = Game3.new()
g.phase = "play"
g.field = { kind = "option", cursor = 7 }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "right" end
g:stepOptionMenu(g.field, function() end)
check(Zoom.offset ~= 0, "RIGHT on ZOOM steps the ladder")
eq(g.options.zoom, Zoom.offset, "options store the zoom offset")
g.field.cursor = 8
g:stepOptionMenu(g.field, function() end)
eq(Tilt.level, 1, "RIGHT on TILT is 15")
eq(g.options.tilt, 1, "options store the tilt level")
Input.wasPressed = function(_, key) return key == "left" end
g:stepOptionMenu(g.field, function() end)
eq(Tilt.level, 0, "LEFT on TILT goes back to OFF")
Input.wasPressed = old
Zoom.offset = oldOff
Tilt.applyOptions({ tilt = oldLevel })
end)()

;(function()
local GameSpeed = require("src.core.GameSpeed")
local g = Game3.new()
g.persistDisplayOptions = function() end
eq(#g:optionMenuSpec(), 10, "OPTION has cart rows plus GAME SPEED")
eq(g:optionMenuSpec()[5][3], "speedOverworld", "OVERWORLD SPEED follows SOUND")
eq(g:logicSpeed(), 1, "boot is menu speed at 1X")
g.phase = "play"
eq(g:speedCategory(), "overworld", "the field is overworld")
g.phase = "battle"
eq(g:speedCategory(), "battle", "a fight is battle")
g.options.speedBattle = 10
eq(g:logicSpeed(), 10, "battle reads speedBattle")
g.speedOverride = 4
eq(g:logicSpeed(), 4, "speedOverride wins")
g.speedOverride = nil
g.phase = "play"
g.field = { kind = "option", cursor = 4 }
local old = Input.wasPressed
Input.wasPressed = function(_, key) return key == "right" end
g:stepOptionMenu(g.field, function() end)
Input.wasPressed = old
eq(g.options.speedOverworld, 2, "RIGHT on OVERWORLD SPEED is 2X")
eq(GameSpeed.levelLabel(g.options.speedOverworld), "2X", "the label is 2X")
g:_cycleSpeed(1)
eq(g.options.speedOverworld, 3, "hotkey 1 cycles the active category")
eq(g.options.speedBattle, 10, "and leaves battle alone")
g.phase = "boot"
g.options.speedMenu = 10
local steps = 0
function g:logicStep() steps = steps + 1 end
g._speedClock = nil
g:update(1 / 60)
check(steps >= 8, "10X MENU SPEED runs many logic steps in one frame")
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
local scrolled = GbaText.decodePages(
  GbaText.encodeLatin("WATER-type and")
    .. string.char(GbaText.SCROLL)
    .. GbaText.encodeLatin("GRASS-type moves.")
    .. eos)
eq(scrolled[1], "WATER-type and\nGRASS-type moves.",
  "\\l scrolls to the next line in the box")
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

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
local none = Cinema.extract("short")
eq(none.copyright, nil, "a tiny dump has no copyright still")
eq(none.title, nil, "and no title still")
eq(none.cableCarMountain, nil, "and no cable-car mountain still")
eq(Cinema.RUBY_US.copyrightMapBytes, 0x500, "copyright tilemap is 0x500")
eq(Cinema.RUBY_US.intro1GfxBytes, 32768, "intro1 tileset is 1024 tiles")
eq(Cinema.RUBY_US.logoMap, 0xE9F7E4, "title logo uses the affine tilemap")
eq(Cinema.RUBY_US.logoMapBytes, 1024, "affine map is 32x32 bytes")
eq(Cinema.RUBY_US.logoBg2X, -29, "BG2X is -29px after sub_813CE30")
eq(Cinema.RUBY_US.logoBg2Y, 0, "the logo rests at BG2Y 0 after Phase2 slides it up")
eq(Cinema.RUBY_US.intro1H, 256, "each intro1 BG screenblock is 256x256")
eq(Game3.intro1MapY(0x28, 0), 0x28, "BG0 VOFS 0x28 shows sheet y=40")
eq(Game3.intro1MapY(0x28, 0) ~= nil, true, "that row has tiles")
eq(Game3.intro1MapY(-208, 0), nil,
  "after the pan BG0 is in the cleared 256x512 screenblock")
eq(Game3.intro1MapY(400, 0), nil, "y>=256 is the DmaClear'd half")
eq(Game3.intro1MapY(500, 0), nil, "still empty before wrap")
eq(Game3.intro1MapY(512, 0), 0, "512 wraps back to the top of the sheet")
eq(Cinema.RUBY_US.copyrightPal, 0xE9CA24, "copyright palette follows the LZ gfx")
eq(Cinema.RUBY_US.copyrightMap, 0xE9CA44, "and the raw tilemap follows the palette")
eq(Game3.intro1LayerVofs(0, 0), 0x28, "BG0 starts at VOFS 0x28")
eq(Game3.intro1LayerVofs(0, 2), 0x50, "BG2 starts at VOFS 0x50")
eq(Game3.intro1LayerVofs(0, 3), 0, "BG3 starts at 0 and never scrolls")
eq(Game3.intro1LayerVofs(1000 / 60, 3), 0, "BG3 still does not scroll")
eq(Game3.intro1LayerVofs(740 / 60, 0), 0x28 - 1.5, "BG0 falls 1.5px per frame")
eq(Game3.intro1LayerVofs(740 / 60, 1), 0x18 - 1.0, "BG1 falls 1px per frame")
eq(Game3.intro1LayerVofs(740 / 60, 2), 0x50 - 0.75, "BG2 falls 0.75px per frame")
eq(Cinema.RUBY_US.intro2W, 256, "intro2 trees+grass are 256 wide")
eq(Cinema.RUBY_US.dropPal, 0x406340, "water-drop pal is Palette_406340")
eq(Cinema.RUBY_US.eonGfx, 0x40ACFC, "intro1 Latios tiles follow the eon pal")
eq(Cinema.RUBY_US.eonGfxBytes, 0x400, "one 64x32 OBJ")
eq(Cinema.RUBY_US.brendanGfx, 0x4143D4, "intro2 Brendan tiles")
eq(Cinema.RUBY_US.bikeGfx, 0x415E08, "intro2 bicycle tiles")
eq(Cinema.RUBY_US.latiosGfx, 0x416254, "intro2 Latios tiles")
eq(Cinema.RUBY_US.ballPal, 0x4098D4, "intro3 pokéball pal is 256 colors")
eq(Cinema.RUBY_US.ballGfx, 0x409C04, "intro3 pokéball 8bpp tiles")
eq(Cinema.RUBY_US.ballGfxBytes, 0x4000, "AFF256x256 8bpp is 256 tiles")
eq(Cinema.RUBY_US.streakMap, 0x40A7E4, "intro3 streak tilemap")
eq(Cinema.RUBY_US.brendanBackGfx, 0xE57AC8, "Brendan back pic")
eq(Cinema.RUBY_US.mayBackPal, 0xE5A050, "May back pal is LZ")
eq(Cinema.RUBY_US.pokeGfx, 0xD02508, "gInterfaceGfx_PokeBall")
eq(Cinema.RUBY_US.miscGfx, 0x40A960, "gIntro3MiscTiles")
eq(Cinema.RUBY_US.miscGfxBytes, 0xA00, "blast + sparks share one sheet")
eq(Cinema.RUBY_US.miscPal2, 0x40A940, "attack FX use intro3 misc pal 2")
eq(Cinema.renderIntro3Ball("short"), nil, "truncated cart has no pokéball")
eq(Game3.intro3Frame(2068), nil, "part 3 starts after frame 2068")
eq(Game3.intro3Frame(2069), 0, "Task_IntroLoadPart3Graphics resets the counter")
eq(Game3.intro3Ball(0).scale, 1 / 256, "pokéball starts tiny (sx = 0x10000/z)")
check(Game3.intro3Ball(40).scale > Game3.intro3Ball(0).scale,
  "data[1]+=data[2] zooms the ball in")
eq(Game3.intro3Actors(79)[1], nil, "Sharpedo is not out before frame 80")
eq(Game3.intro3Actors(80)[1].species, 331, "sub_813CE88(SPECIES_SHARPEDO) at 80")
eq(Game3.intro3Actors(152)[1].species, 361, "Duskull front at 152")
eq(Game3.intro3Actors(250)[1].trainer, true, "trainer back pic walks in at 219")
eq(Game3.intro3Actors(250)[1].y, 96, "sub_813CFA8 y=0x60")
eq(Game3.intro3Actors(400)[2].species, 280, "Torchic pops from the ball at 384")
eq(Game3.intro3Actors(400)[3].species, 283, "Mudkip pops with it")
local popBalls = Game3.intro3ThrownBalls(383)
local popMons = Game3.intro3Actors(384)
eq(popMons[2].x, popBalls[1].x, "Torchic pops at the landed ball, not 16,104")
eq(popMons[2].y, popBalls[1].y, "Torchic y matches the ball")
eq(popMons[3].x, popBalls[2].x, "Mudkip pops at its landed ball, not 12,106")
eq(popMons[3].y, popBalls[2].y, "Mudkip y matches the ball")
check(popMons[2].x > 100, "the ball has flown well past the throw origin")
eq(Game3.intro3Actors(650)[1].species, 283, "Mudkip back pic dashes in at 624")
eq(Game3.intro3Actors(800)[1] ~= nil, true, "all four rush at 781")
eq(Game3.intro3StreakScroll(100), nil, "BG2 streaks are off during the fly-in")
check(Game3.intro3StreakScroll(500) ~= nil, "streaks run while Sharpedo dashes")
eq(#Game3.intro3ThrownBalls(250), 0, "no balls until the trainer arrives")
eq(#Game3.intro3ThrownBalls(310), 2, "two pokéballs fly at the throw")
eq(Game3.intro3ThrownBalls(310)[1].x > 16, true, "the first ball moves right")
eq(#Game3.intro3Attacks(620), 0, "no water until Mudkip finishes the dash")
check(#Game3.intro3Attacks(650) > 0, "InitIntroMudkipAttackAnim sprays after idle")
eq(Game3.intro3Attacks(650)[1].kind, "water", "tile 2 is the water drop")
local function countKind(list, kind)
  local n = 0
  for i = 1, #list do
    if list[i].kind == kind then n = n + 1 end
  end
  return n
end
eq(countKind(Game3.intro3Attacks(705), "ember"), 0, "Torchic has not started embers yet")
check(countKind(Game3.intro3Attacks(720), "ember") > 0,
  "InitIntroTorchicAttackAnim adds embers")
eq(Game3.intro3Attacks(780)[1], nil, "gUnknown_0203931A kills the beams at 776")
local g3 = Game3.new()
g3.boot.kind = Game3.BOOT_INTRO
g3.boot.t = 2069 / 60
g3:drawIntro()
g3.boot.t = (2069 + 80) / 60
g3:drawIntro()
g3.boot.t = (2069 + 800) / 60
g3:drawIntro()
g3.boot.t = (2069 + 946) / 60 - 0.02
g3:stepBoot(0)
eq(g3.boot.kind, Game3.BOOT_INTRO, "part 3 is still playing at local 945")
g3:stepBoot(0.03)
eq(g3.boot.kind, Game3.BOOT_TITLE, "MainCB2_EndIntro at local 946")
local d0 = Game3.intro1Drops(0)
eq(d0[1].kind, "drop", "the hanging drop exists at frame 0")
eq(d0[1].x, 236, "CreateWaterDrop(236, -14)")
eq(d0[1].y, -14, "above the pond")
eq(#Game3.intro1Drops(367), 1, "second drop is not out yet")
eq(#Game3.intro1Drops(368), 2, "frame 368 spawns the left drop")
eq(#Game3.intro1Drops(384), 3, "frame 384 spawns the right drop")
eq(Game3.intro1Eon(879), nil, "Latios is hidden before 880")
check(Game3.intro1Eon(880) ~= nil, "CreateSprite at frame 880")
eq(Game3.intro1Eon(880).x, 200, "anchored at (200, 160)")
eq(Game3.intro2Bike(1026), nil, "no rider before part 2")
eq(Game3.intro2Bike(1027).x, 0x110 - 1, "starts at 0x110 then x--")
eq(Game3.intro2Bike(1027).y, 100, "intro_create_brendan_sprite y=100")
eq(Game3.intro2Bike(1027).anim, 0, "pedal anim starts on tile 0")
eq(Game3.intro2Bike(1030).anim, 0, "Unknown_40AE38 duration 4")
eq(Game3.intro2Bike(1031).anim, 1, "then tile 64")
eq(Game3.intro2Bike(1397).anim, 0, "still pedaling before 1398")
eq(Game3.intro2Bike(1398).anim, 4, "data[0]=2 starts look-back / wheelie")
eq(Game3.intro2Bike(1401).anim, 4, "Unknown_40AE60 first frame lasts 4")
eq(Game3.intro2Bike(1402).anim, 5, "then tile 0x140")
eq(Game3.intro2Bike(1406).anim, 6, "then tile 0x180 and hold")
eq(Game3.intro2Bike(1586).anim, 6, "data[0]=3 starts on 0x180")
eq(Game3.intro2Bike(1601).anim, 6, "Unknown_40AE70 duration 16")
eq(Game3.intro2Bike(1602).anim, 5, "then tile 0x140")
eq(Game3.intro2Bike(1618).anim, 4, "then tile 256 and hold")
eq(Game3.intro2Latios(1027).x, -64, "Latios starts off the left")
eq(Game3.intro2BobY(1026), 0, "no camera bob in part 1")
-- sub_8148C78: trees BG3 pri 3 (back), grass BG1 pri 1 (front).
eq(Game3.intro1ScrollY(0), 0, "intro1 holds VOFS until frame 739")
eq(Game3.intro1ScrollY(739 / 60), 0, "scroll starts at 739")
eq(Game3.intro1ScrollY(740 / 60), 1, "then +1px per frame")
eq(Game3.intro1ScrollY(904 / 60), 165, "and stops at frame 904")
eq(Game3.intro1ScrollY(1000 / 60), 165, "later frames keep the last VOFS")
eq(Game3.intro2ScrollX(1027 / 60), 0, "bike scroll starts at part 2")
eq(Game3.intro2ScrollX((1027 + 1) / 60), 4, "grass moves ~4px per frame")
eq(Game3.intro2ScrollX((1027 + 4) / 60, 4 * (0x400 / 0x4000)), 1,
  "BG2 trees move 0.25px per frame")
eq(Game3.intro2ScrollX((1027 + 256) / 60, 4 * (0x10 / 0x4000)), 1,
  "BG3 trees move 1px per 256 frames")
local fake = {
  w = 16, h = 8, px = {},
  getWidth = function(s) return s.w end,
  getHeight = function(s) return s.h end,
  setPixel = function(s, x, y, r)
    s.px[y * s.w + x] = r
  end,
}
local tiles = string.rep("\0", 64) .. string.rep("\1", 64)
local map = string.char(1) .. string.rep("\0", 1023)
Cinema.paintAffine8(fake, tiles, map, { [1] = { 1, 0, 0 } }, 0, 0)
eq(fake.px[0], 1, "affine map[0]=1 paints tile 1 at screen 0,0")
eq(fake.px[8], nil, "the next tile column stays empty")
local miss = {
  w = 8, h = 8, px = {},
  getWidth = function(s) return s.w end,
  getHeight = function(s) return s.h end,
  setPixel = function(s, x, y, r)
    s.px[y * s.w + x] = r
  end,
}
local tile2 = string.rep("\2", 64)
Cinema.paintAffine8(miss, tile2, string.char(0) .. string.rep("\0", 1023),
  { [1] = { 1, 0, 0 } }, 0, 0)
eq(miss.px[0], nil, "an 8bpp index with no pal entry is skipped, not white")

-- Color 0 on a front layer must not bury the back layer (intro2 grass
-- over trees, title lava over Groudon).
local stack = {
  w = 8, h = 8, px = {},
  getWidth = function(s) return s.w end,
  getHeight = function(s) return s.h end,
  setPixel = function(s, x, y, r, g, b)
    s.px[y * s.w + x] = { r, g, b }
  end,
}
local backTile = string.rep("\2", 32)
local frontTile = string.rep("\0", 32)
local map0 = string.rep("\0", 2048)
Cinema.paintTilemap(stack, backTile, map0, { [0] = { [2] = { 1, 0, 0 } } },
  32, 32, 0, 0, false)
eq(stack.px[0][1], 1, "back layer paints an opaque pixel")
Cinema.paintTilemap(stack, frontTile, map0, { [0] = { [0] = { 0, 1, 0 } } },
  32, 32, 0, 0, true)
eq(stack.px[0][1], 1, "front color 0 keeps the back pixel")
local g = Game3.new()
eq(g:cinemaPic("copyright"), nil, "tests have no extracted cinema")
g:drawCopyright()
g:drawIntro()
g.boot.t = 560 / 60
g:drawIntro()
g.boot.t = 800 / 60
g:drawIntro()
g.boot.t = 1027 / 60
g:drawIntro()
g:drawTitleScreen()
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.cableCarBgPal, 0xE7EB9C, "gCableCarBG_Pal")
eq(Cinema.RUBY_US.cableCarGfx, 0xE80614, "gCableCar_Gfx")
eq(Cinema.RUBY_US.cableCarMountainMap, 0x401AFC, "mountain tilemap LZ")
eq(Cinema.RUBY_US.cableCarMountainMapBytes, 1200, "30x20 u16s")
eq(Cinema.RUBY_US.cableCarTreeMapBytes, 960, "32x15 u16s")
eq(Cinema.RUBY_US.cableCarChimneyMapBytes, 360, "12x15 u16s")
eq(Cinema.renderCableCar("short"), nil, "truncated cart has no ride tiles")
local up0 = Game3.cableCarScroll(0, false)
eq(up0.bg3h, 0xB0, "BG3 HOFS starts at 0xB0 going up")
eq(up0.bg3v, 0x10, "BG3 VOFS starts at 0x10")
eq(up0.bg1h, 0, "BG1 HOFS starts at 0")
eq(up0.bg1v, 0x50, "BG1 VOFS starts at 0x50")
eq(up0.carX, 0xB0, "car x is 0xB0")
eq(up0.carY, 0x2B, "car y is 0x2B")
eq(up0.doorX, 0xC8, "door x is 0xC8")
eq(up0.doorY, 0x63, "door y is 0x63")
local up8 = Game3.cableCarScroll(8, false)
eq(up8.bg1h, -1, "BG1 HOFS -1 every 8 frames")
eq(up8.bg1v, 0x50 - 1, "and VOFS with it")
eq(up8.bg3h, 0xB0 - 8, "BG3 HOFS -1 every frame")
eq(up8.bg3v, 0x10 - 4, "BG3 VOFS -1 every 2 frames")
local down0 = Game3.cableCarScroll(0, true)
eq(down0.bg3h, 0x60, "going down BG3 HOFS 0x60")
eq(down0.bg3v, 0xE8, "BG3 VOFS 0xE8")
eq(down0.bg1v, 0x04, "BG1 VOFS 0x04")
eq(down0.carX, 0x68, "car x 0x68")
eq(down0.carY, 0x09, "car y 0x09")
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.eggHatchPal, 0x209AD8, "sEggPalette")
eq(Cinema.RUBY_US.eggHatchGfx, 0x209AF8, "sEggHatchTiles")
eq(Cinema.RUBY_US.eggHatchGfxBytes, 2048, "four 32x32 frames")
eq(Cinema.RUBY_US.eggShardGfx, 0x20A2F8, "sEggShardTiles")
eq(Cinema.RUBY_US.tradeGbaGfx, 0x20CA98, "gUnknown_0820CA98")
eq(Cinema.RUBY_US.hatchBgMap, 0x20F798, "shadow_map.bin")
eq(Cinema.RUBY_US.tradeGbaMap, 0x210798, "gba_map.bin")
eq(Cinema.renderEggHatch("short"), nil, "truncated cart has no egg tiles")
eq(Cinema.renderHatchBg("short"), nil, "and no hatch BG")
local still = Game3.eggHatchPose(0)
eq(still.frame, 0, "pal wait is frame 0")
eq(still.x2, 0, "and does not wobble")
eq(still.egg, true, "egg is up")
eq(still.mon, false, "the hatched mon is hidden")
local crack = Game3.eggHatchPose(Game3.EGG_HATCH_WAIT + 14)
eq(crack.frame, 1, "Egg_0 data[0]==15 starts anim 1")
eq(crack.x2, 0, "amp 1 truncates Sin to 0")
local mid = Game3.eggHatchPose(Game3.EGG_HATCH_WAIT + 20 + 30 + 1)
eq(mid.frame, 1, "Egg_1 still anim 1 before 15")
eq(mid.x2, 1, "amp 2 wobbles a pixel")
local cracked = Game3.eggHatchPose(Game3.EGG_HATCH_WAIT + 20 + 30 + 14)
eq(cracked.frame, 2, "Egg_1 data[0]==15 starts anim 2")
local reveal = Game3.eggHatchPose(240)
eq(reveal.egg, false, "Egg_5 hides the shell")
eq(reveal.mon, true, "and shows the front pic")
eq(Game3.EGG_HATCH_X, 0x78, "CreateSprite x")
eq(Game3.EGG_HATCH_Y, 0x4B, "CreateSprite y")
eq(Game3.EGG_HATCH_MON_Y, 70, "front pic y is 70")
eq(#Game3.eggHatchShards(0), 0, "no shards during pal wait")
eq(#Game3.eggHatchShards(Game3.EGG_HATCH_WAIT + 14), 1,
  "Egg_0 crack throws one shard")
eq(Game3.eggHatchShards(Game3.EGG_HATCH_WAIT + 14)[1].x, 120,
  "CreateEggShardSprite x is 120")
eq(Game3.eggHatchShards(Game3.EGG_HATCH_WAIT + 14)[1].y, 60,
  "and y is 60")
eq(#Game3.eggHatchShards(Game3.EGG_HATCH_WAIT + 20 + 30 + 20 + 30 + 14), 2,
  "Egg_2 crack throws two more after the first has fallen")
local fade = Game3.eggHatchPose(Game3.EGG_HATCH_WAIT + 20 + 30 + 20 + 30 + 38 + 51)
eq(fade.egg, true, "Egg_4 still shows the shell")
check(fade.flash > 0, "and the white fade has started")
local t5 = Game3.EGG_HATCH_WAIT + 20 + 30 + 20 + 30 + 38 + 51
  + Game3.EGG_HATCH_FADE
local hatch = Game3.eggHatchPose(t5)
eq(hatch.mon, true, "Egg_5 shows the front pic")
eq(hatch.egg, false, "and hides the shell")
eq(hatch.monY, Game3.EGG_HATCH_MON_Y - 1, "y -= 1 on the first Egg_5 frame")
eq(hatch.scale, 0x28 / 0x100, "affine anim 1 starts at 0x28")
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.tradeCableMap, 0x211798, "cable_closeup_map.bin")
eq(Cinema.RUBY_US.tradeCableMapBytes, 0x800, "32x32 u16s")
eq(Cinema.RUBY_US.tradeBallGfx, 0x20C3F8, "gTradeBallTiles")
eq(Cinema.RUBY_US.tradeBallGfxBytes, 0x600, "twelve 16x16 frames")
eq(Cinema.RUBY_US.tradeSymbolGfx, 0x20DD98, "pokeball_symbol.8bpp")
eq(Cinema.RUBY_US.tradeAffineGfx, 0x213738, "gba_affine.8bpp")
eq(Cinema.RUBY_US.tradeAffineMap, 0x215778, "AFF128x128")
eq(Cinema.renderTradeCable("short"), nil, "truncated cart has no cable map")
eq(Cinema.renderTradeAffine("short"), nil, "and no affine GBA")
local slide = Game3.tradeScenePose(0)
eq(slide.bg, "platform", "DoTradeAnim starts on the platform")
eq(slide.bg2hofs, 0xB4, "bg2hofs is 0xB4")
eq(slide.sent, true, "the sent mon is on the left")
eq(Game3.tradeScenePose(Game3.TRADE_SLIDE).bg2hofs, 0, "slide ends at HOFS 0")
eq(Game3.tradeScenePose(Game3.TRADE_SLIDE).line, 1, "then WillBeSent")
eq(Game3.tradeScenePose(Game3.TRADE_SLIDE + Game3.TRADE_SEND_MSG).line, 2,
  "80 frames later ByeBye")
eq(Game3.tradeScenePose(Game3.TRADE_SLIDE + Game3.TRADE_SEND_MSG).ball, true,
  "with the trade ball")
local care = Game3.tradeScenePose(Game3.TRADE_WAIT_A)
eq(care.line, 4, "TakeGoodCare")
eq(care.waitA, true, "JOY_NEW A runs sub_804BA94")
eq(Game3.tradeScenePose(Game3.TRADE_WAIT_A - 1).waitA, false,
  "not before the 60-frame delay")
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.rotatingGateFortree, 0x3D2964, "Fortree gate config")
eq(Cinema.RUBY_US.rotatingGatePal, 0x323C48, "gObjectEventPalette5")
eq(Cinema.RUBY_US.rotatingGatePalTag, 0x1108, "OBJ_EVENT_PAL_TAG_5")
eq(Cinema.RUBY_US.rotatingGate[0].off, 0x3D5A0C, "L1 tiles after the 0x800s")
eq(Cinema.RUBY_US.rotatingGate[0].bytes, 0x200, "L1 is 32x32")
eq(Cinema.RUBY_US.rotatingGate[3].off, 0x3D3A0C, "L4 is file 3")
eq(Cinema.RUBY_US.rotatingGate[3].bytes, 0x800, "L4 is 64x64")
eq(Cinema.RUBY_US.rotatingGate[4].off, 0x3D5C0C, "T1 follows L1")
eq(Cinema.renderRotatingGate("short", 3), nil, "truncated cart has no gates")
eq(Game3.rotatingGateSize(0), 32, "L1 is OAM size 2")
eq(Game3.rotatingGateSize(4), 32, "T1 is OAM size 2")
eq(Game3.rotatingGateSize(3), 64, "L4 is OAM size 3")
eq(Game3.ROTATING_GATE_AFFINE[1], -64, "90° is -64")
eq(Game3.ROTATING_GATE_AFFINE[3], 64, "270° is +64")
eq(Game3.rotatingGateAngle(0), 0, "ori 0 is unrotated")
eq(Game3.rotatingGateAngle(1), -64 * math.pi / 128, "ori 1 is clockwise 90")
local rr, rg, rb = Game3.rgb555(Game3.ORB_PAL_RED)
eq(rr, 31 * 8 / 255, "orb pal 0 is 0x1F red")
eq(rg, 0, "with no green")
eq(rb, 0, "and no blue")
local br, bg, bb = Game3.rgb555(Game3.ORB_PAL_BLUE)
eq(br, 0, "orb pal 1 is 0x7C00")
eq(bg, 0, "blue, not teal")
eq(bb, 31 * 8 / 255, "B=31")
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.pokeballGlowGfx, 0x39E434, "pokeball_glow.4bpp")
eq(Cinema.RUBY_US.pokeballGlowGfxBytes, 0x20, "one 8x8 tile")
eq(Cinema.RUBY_US.pokeballGlowPal, 0x39E454, "pal 04 tag 0x1007")
eq(Cinema.RUBY_US.pokecenterMon0Gfx, 0x39E474, "pokecenter monitor 0")
eq(Cinema.RUBY_US.pokecenterMonGfxBytes, 0xC0, "24x16")
eq(Cinema.RUBY_US.pokecenterMon1Gfx, 0x39E534, "pokecenter monitor 1")
eq(Cinema.RUBY_US.pokecenterMonPal, 0x369488, "gFieldEffectObjectPalette0")
eq(Cinema.RUBY_US.hofMonitorBigGfx, 0x39E5F4, "big_hof_monitor.4bpp")
eq(Cinema.RUBY_US.hofMonitorBigGfxBytes, 0x200, "64x16")
eq(Cinema.RUBY_US.hofMonitorSmallGfx, 0x39E7F4, "small_hof_monitor.4bpp")
eq(Cinema.RUBY_US.hofMonitorSmallGfxBytes, 0x100, "32x16 INCBIN")
eq(Cinema.RUBY_US.hofMonitorPal, 0x39E8F4, "pal 05 tag 0x1010")
eq(Cinema.renderPokeballGlow("short"), nil, "truncated cart has no glow")
eq(Cinema.renderHofMonitors("short"), nil, "and no HoF monitors")
eq(Cinema.renderPokecenterMonitor("short"), nil, "and no Center monitor")
local t0 = Game3.pokeballGlowPose(0, 1)
eq(#t0.balls, 1, "first ball is immediate")
eq(t0.balls[1][1], 0x75, "HoF origin x")
eq(t0.balls[1][2], 0x34, "HoF origin y")
eq(t0.monitors, false, "screens wait 32 frames after the last ball")
eq(t0.pcMonitor, false, "Center screen too")
local t25 = Game3.pokeballGlowPose(25, 2)
eq(#t25.balls, 2, "second ball at gap 25")
eq(t25.balls[2][1], 0x75 + 6, "gUnknown_0839F2A8[1].x")
eq(t25.balls[2][2], 0x34, "same row")
local glow = Game3.pokeballGlowPose(32, 1)
eq(glow.monitors, true, "HoF screens on the first blink frame")
eq(glow.pcMonitor, true, "Center StartSpriteAnim(1)")
eq(glow.pcFrame, 0, "anim 1 starts on image 0")
local odd = Game3.pokeballGlowPose(48, 1)
eq(odd.monitors, false, "HoF invisible on the odd 16")
eq(odd.pcMonitor, true, "Center anim keeps running")
eq(odd.pcFrame, 1, "image 1 after 16 frames")
eq(#Game3.pokeballGlowPose(Game3.HOF_BALL_LIVE, 1).balls, 0,
  "balls free when glow data[0] > 4")
local pc = Game3.pokeballGlowPose(0, 1, Game3.POKECENTER_BALL_X,
  Game3.POKECENTER_BALL_Y)
eq(pc.balls[1][1], 0x5D, "Center origin x")
eq(pc.balls[1][2], 0x24, "Center origin y")
eq(Game3.multiplyInvertedPaletteRgb(0, 16, 16, 0), 31 + 31 * 32,
  "factor 16 drives R/G to 31")
eq(Game3.multiplyInvertedPaletteRgb(0x7FFF, 16, 16, 16), 0x7FFF,
  "white stays white")
eq(Game3.multiplyInvertedPaletteRgb(0, 0, 0, 0), 0, "factor 0 is rest")
local mid = Game3.multiplyInvertedPaletteRgb(16, 8, 0, 0)
eq(mid, 16 + math.floor((31 - 16) * 8 / 16), "R += ((31-R)*8)>>4")
eq(Game3.glowPulsePhase(0), nil, "stage 1 has no pal write")
eq(Game3.glowPulsePhase(31), nil, "still waiting 32")
local p0, st0 = Game3.glowPulsePhase(32)
eq(p0, 0, "stage 2 starts at phase 0")
eq(st0, true, "and staggers colors")
eq(Game3.glowPulsePhase(32 + 8), 1, "8 frames later")
local p3, st3 = Game3.glowPulsePhase(32 + 96)
eq(p3, 0, "stage 3 is unified")
eq(st3, false, "no stagger")
eq(Game3.glowPulsePhase(32 + 96 + 24), nil, "stage 4 pal at rest")
eq(Game3.glowPulseFactor(0), 16, "phase 0 is 16")
eq(Game3.glowPulseFactor(3), 0, "phase 3 is 0")
local glowPulse = Game3.pokeballGlowPose(32, 1)
eq(glowPulse.pulse, 16, "pose carries the factor")
eq(glowPulse.pulseStagger, true, "stagger flag")
end)()

;(function()
local Cinema = require("src.import.RomExtractorGen3Cinema")
eq(Cinema.RUBY_US.regionMapCursorPal, 0x3E5AD0, "cursor.gbapal")
eq(Cinema.RUBY_US.regionMapCursorSmallLz, 0x3E5AF0, "cursor_small.4bpp.lz")
eq(Cinema.RUBY_US.regionMapCursorSmallBytes, 0x100, "two 16x16 frames")
eq(Cinema.RUBY_US.regionMapBrendanPal, 0x3E5C20, "brendan_icon.gbapal")
eq(Cinema.RUBY_US.regionMapMayGfx, 0x3E5CE0, "may_icon.4bpp")
eq(Cinema.RUBY_US.regionMapPal, 0x3E5D60, "region_map.gbapal")
eq(Cinema.RUBY_US.regionMapPalIndex, 0x70, "LoadPalette dest 0x70")
eq(Cinema.RUBY_US.regionMapGfxLz, 0x3E5DA0, "region_map.8bpp.lz")
eq(Cinema.RUBY_US.regionMapGfxBytes, 0x3A40, "233 8bpp tiles")
eq(Cinema.RUBY_US.regionMapMapLz, 0x3E6B04, "region_map_map.bin.lz")
eq(Cinema.RUBY_US.regionMapMapBytes, 0x1000, "64x64 affine map")
eq(Cinema.renderRegionMap("short"), nil, "truncated cart has no map")
eq(Cinema.renderRegionMapCursor("short"), nil, "and no cursor")
eq(Game3.MAPSEC_NONE, 88, "MAPSEC_NONE follows DYNAMIC")
eq(Game3.regionMapName(0), "LITTLEROOT TOWN", "section 0")
eq(Game3.regionMapSectionAt(5, 13), 0, "Littleroot is layout (4,11)")
local cx, cy = Game3.regionMapCursorForSection(0)
eq(cx, 5, "cursor x is entry.x + 1")
eq(cy, 13, "cursor y is entry.y + 2")
eq(Game3.regionMapSectionAt(0, 0), Game3.MAPSEC_NONE, "outside the 28x15")
eq(Game3.regionMapName(Game3.MAPSEC_NONE), "", "NONE has no label")
eq(Game3.MAPSEC_BATTLE_TOWER, 58, "MAPSEC_BATTLE_TOWER")
eq(Game3.MAPSEC_SOUTHERN_ISLAND, 73, "MAPSEC_SOUTHERN_ISLAND")
local RM = require("src.core.Game3RegionMap")
local w, h = RM.entrySize(8)
eq(w, 1, "Slateport width 1")
eq(h, 2, "Slateport height 2")
w, h = RM.entrySize(9)
eq(w, 2, "Mauville width 2")
eq(h, 1, "Mauville height 1")
local zs, zy = RM.zoomScrollForCursor(1, 2)
eq(zs, -44, "min cursor is scrollX min")
eq(zy, -52, "min cursor is scrollY min")
local zcx, zcy = RM.zoomCellFromScroll(-44, -52)
eq(zcx, 1, "scroll back to cursor x")
eq(zcy, 2, "scroll back to cursor y")
local mx, my = RM.screenXY(4, 4, 0, 0, 256)
eq(mx, 4, "unzoomed map pixel is screen pixel")
eq(my, 4, "unzoomed y too")
local flowers = RM.landmarkNames(19, 0, {})
eq(#flowers, 0, "Flower Shop waits on FLAG_LANDMARK")
flowers = RM.landmarkNames(19, 0, { [RM.FLAG_LANDMARK_FLOWER_SHOP] = true })
eq(flowers[1], "FLOWER SHOP", "flag shows the shop")
local woods = RM.landmarkNames(19, 1, {})
eq(woods[1], "PETALBURG WOODS", "woods has no flag")
eq(#woods, 1, "Briney cottage still hidden")
end)()

S.finish()
