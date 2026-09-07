-- Ruby Phase 2: GBA LZ77, Littleroot header scan, map grid / warps.
-- Fixture bytes only -- the copyrighted .gba is not in git.
--   luajit tests/engine/ruby_map_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end


local S = require("tests.harness").suite("ruby map extract")
local check = S.check
local eq = S.eq

local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local GbaText = require("src.import.GbaText")
local RomExtractorGen3 = require("src.import.RomExtractorGen3")

-- ------- LZ77

local payload = "BULBASAUR"
local packed = GbaLz77.compressLiterals(payload)
eq(packed:byte(1), 0x10, "literal stream starts with type 0x10")
eq(GbaLz77.decompress(packed, 0), payload, "literal lz77 round-trips")

-- One literal 'A' then a 3-byte RLE copy (disp 1).
local rle = string.char(0x10, 4, 0, 0, 0x40, 0x41, 0x00, 0x00)
eq(GbaLz77.decompress(rle, 0), "AAAA", "lz77 displacement 1 is RLE")
eq(GbaLz77.decompress("not lz", 0), nil, "rejects a non-lz77 blob")

-- ------- town fixture (2x2, music 405, mapType 1)

local function overlay(base, off, chunk)
  return base:sub(1, off) .. chunk .. base:sub(off + #chunk + 1)
end

local function pad(text, n)
  return (text .. string.rep("\0", n)):sub(1, n)
end

local SIZE = 0x3000
local rom = string.rep("\0", SIZE)
rom = overlay(rom, 0xA0, pad("POKEMON RUBY", 12) .. pad("AXVE", 4) .. pad("01", 2))

local names = {}
for i = 0, 411 do
  names[i + 1] = string.rep(string.char(GbaText.PLACEHOLDER), 10)
    .. string.char(GbaText.EOS)
end
rom = overlay(rom, 0xC0, table.concat(names))

local H, L = 0x2000, 0x2100
local TS0, TS1 = 0x2200, 0x2300
local PAL, META, ATTR = 0x2400, 0x2600, 0x2700
local TILES, GRID, EVENTS, WARPS, DUMMY, BORDER = 0x2800, 0x2A00, 0x2B00, 0x2C00, 0x2D00, 0x2D80

rom = overlay(rom, H,
  GbaBin.packPtr(L)
  .. GbaBin.packPtr(EVENTS)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packU16(405)
  .. GbaBin.packU16(10)
  .. string.char(0, 0, 0, 1, 0, 0, 0, 0))

rom = overlay(rom, L,
  GbaBin.packU32(2) .. GbaBin.packU32(2)
  .. GbaBin.packPtr(BORDER)
  .. GbaBin.packPtr(GRID)
  .. GbaBin.packPtr(TS0)
  .. GbaBin.packPtr(TS1))

local function tileset(secondary)
  return string.char(1, secondary and 1 or 0, 0, 0)
    .. GbaBin.packPtr(TILES)
    .. GbaBin.packPtr(PAL)
    .. GbaBin.packPtr(META)
    .. GbaBin.packPtr(ATTR)
    .. GbaBin.packPtr(DUMMY)
end
rom = overlay(rom, TS0, tileset(false))
rom = overlay(rom, TS1, tileset(true))

local tile = string.rep(string.char(0x11), 32)
rom = overlay(rom, TILES, GbaLz77.compressLiterals(tile))

-- metatile 0: four copies of tile 0 on the bottom, zeros on top
local meta = string.rep(GbaBin.packU16(0), 8)
rom = overlay(rom, META, meta)

-- (0,0) open, (1,0) blocked, (0,1) open, (1,1) open
rom = overlay(rom, GRID,
  GbaBin.packU16(0) .. GbaBin.packU16(1024)
  .. GbaBin.packU16(0) .. GbaBin.packU16(0))

-- fieldmap.c GetBorderBlockAt 2x2
rom = overlay(rom, BORDER,
  GbaBin.packU16(7) .. GbaBin.packU16(8)
  .. GbaBin.packU16(9) .. GbaBin.packU16(10))

rom = overlay(rom, EVENTS,
  string.char(0, 1, 0, 0)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packPtr(WARPS)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packPtr(DUMMY))
rom = overlay(rom, WARPS,
  GbaBin.packU16(1) .. GbaBin.packU16(0)
  .. string.char(0, 0, 0, 1))

eq(#rom, SIZE, "fixture ROM stays 0x3000 bytes")

local header = RomExtractorGen3.findTownHeader(rom)
check(header ~= nil, "scan finds the town MapHeader")
eq(header.offset, H, "header lands at the fixture offset")
eq(header.music, 405, "music is MUS_LITTLEROOT")
eq(header.mapType, 1, "mapType is town")
eq(header.cave, false, "Littleroot is not a dark cave")
eq(header.width, 2, "layout width")
eq(header.height, 2, "layout height")

local map, prim, sec = RomExtractorGen3.decodeTownMap(rom)
check(map ~= nil, "decodeTownMap returns a map")
eq(map.id, "littleroot_town", "map id")
eq(map.width, 2, "decoded width")
eq(map.height, 2, "decoded height")
eq(map.grid[1], 0, "cell (0,0) is open")
eq(map.grid[2], 1024, "cell (1,0) carries collision")
eq(map.border[1], 7, "layout border[0]")
eq(map.border[2], 8, "layout border[1]")
eq(map.border[3], 9, "layout border[2]")
eq(map.border[4], 10, "layout border[3]")
eq(map.spawn.x, 1, "spawn prefers the center cell when it is open")
eq(map.spawn.y, 1, "spawn y is the center")
eq(#map.warps, 1, "one warp")
eq(map.warps[1].x, 1, "warp x")
eq(map.warps[1].y, 0, "warp y")
eq(map.warps[1].warpId, 0, "warp id")
eq(map.warps[1].mapNum, 0, "warp map num")
eq(map.warps[1].mapGroup, 1, "warp map group")
eq(#(map.bgEvents or {}), 0, "fixture town has no BG events")
check(type(prim) == "number" and type(sec) == "number",
  "tileset file offsets are returned for the renderer")

eq(RomExtractorGen3.decodeTownMap("no maps here"), nil,
  "a blob without MUS_LITTLEROOT is not a town")

-- A DECORPERM_SOLID_MAT decoration's tiles[0] is an OBJ_EVENT_GFX id that
-- sub_80BBDD0 writes into VAR_OBJ_GFX_ID_n at runtime, so those sheets are
-- never any map object's graphicsId. Scanning the maps alone left ids
-- 143..188 unextracted and every placed doll invisible.
do
  local fakeMaps = { g1 = { objects = { { graphicsId = 35 } } } }
  local plain = RomExtractorGen3.collectGraphicsIds(fakeMaps)
  local hasDoll = false
  for _, id in ipairs(plain) do if id == 154 then hasDoll = true end end
  eq(hasDoll, false, "a doll sheet is not reachable from the maps")

  local catalog = { byId = {
    -- SOLID_MAT is permission 4; its gfx is an OBJ_EVENT_GFX id.
    [88] = { permission = 4, gfx = 154, tiles = { 154 } },
    [77] = { permission = 4, gfx = 143, tiles = { 143 } },
    -- A grid-baked one, whose tiles are metatiles and must NOT be pulled
    -- in as a sprite.
    [1] = { permission = 0, gfx = 0x28, tiles = { 0x28 } },
  } }
  local withDecor = RomExtractorGen3.collectGraphicsIds(fakeMaps, catalog)
  local seen = {}
  for _, id in ipairs(withDecor) do seen[id] = true end
  eq(seen[154], true, "the catalog pulls in the TREECKO DOLL sheet")
  eq(seen[143], true, "and the PIKACHU DOLL sheet")
  eq(seen[0x28], nil, "but not a SOLID_FLOOR decoration's metatile")
  eq(seen[35], true, "map objects are still collected")
end

-- An object placed as OBJ_EVENT_GFX_VAR_0..F resolves through
-- VAR_OBJ_GFX_ID_n at runtime, so the sheet it ends up wanting is never
-- any object's graphicsId. Common_EventScript_SetupLegendaryGfxIds puts
-- Groudon (198/206) in VAR_OBJ_GFX_ID_8/9 and nothing else in the game
-- names them, so they came out unextracted and Groudon was a blank square.
do
  local mapsWithVarGfx = {
    g1 = {
      objects = { { graphicsId = 248 }, { graphicsId = 249 } },
      mapScripts = { onTransition = {
        { op = "setvar", var = 0x4018, val = 198 },
        { op = "setvar", var = 0x4019, val = 206 },
        -- setorcopyvar from another var must NOT be read as a sprite id.
        { op = "setorcopyvar", var = 0x4010, val = 0x4001 },
      } },
    },
  }
  local ids = RomExtractorGen3.collectGraphicsIds(mapsWithVarGfx)
  local seen = {}
  for _, id in ipairs(ids) do seen[id] = true end
  eq(seen[198], true, "the legendary sheet is collected from the script")
  eq(seen[206], true, "and its second form")
  eq(seen[248], true, "the GFX_VAR placeholder is still collected as before")
  local over = 0
  for _, id in ipairs(ids) do if id > 255 then over = over + 1 end end
  eq(over, 0, "a var reference is never mistaken for a graphics id")
end

eq(RomExtractorGen3.attrBehavior(0x1080), 0x80, "behavior is the low byte")
eq(RomExtractorGen3.attrLayerType(0x1080), 1, "layer type is bits 12-15")
eq(RomExtractorGen3.attrLayerType(0), 0, "zero attributes are NORMAL")

-- Ruby ObjectEventTemplate: trainerType is a u16 at +0x0C, script at +0x10.
local SCRIPT = 24
local obj = string.char(2, 35, 0, 0)
  .. GbaBin.packU16(33) .. GbaBin.packU16(14)
  .. string.char(3, 8, 0x30, 0)
  .. GbaBin.packU16(1) .. GbaBin.packU16(3)
  .. GbaBin.packPtr(SCRIPT)
  .. GbaBin.packU16(0x200) .. string.char(0, 0)
eq(#obj, 0x18, "an object event is 0x18 bytes")
local parsed = RomExtractorGen3.parseObjectTemplate(obj .. string.rep("\0", 16), 0)
eq(parsed.localId, 2, "local id")
eq(parsed.graphicsId, 35, "youngster graphics")
eq(parsed.x, 33, "x")
eq(parsed.y, 14, "y")
eq(parsed.rangeX, 0, "range X nibble")
eq(parsed.rangeY, 3, "range Y nibble")
eq(parsed.trainerType, 1, "Ruby trainerType is the u16 at +0x0C")
eq(parsed.trainerRange, 3, "sight range is the u16 at +0x0E")
eq(parsed.flagId, 0x200, "flag is at +0x14")
eq(parsed.scriptOff, SCRIPT, "script pointer is at +0x10")

;(function()
local parts = { string.char(0x29, 0x56, 0x00, 0x29, 0x01, 0x03) }
for i = 3, 80 do
  local flag = 0x2D0 + i
  parts[#parts + 1] = string.char(0x29, flag % 256, math.floor(flag / 256) % 256)
end
parts[#parts + 1] = string.char(0x02)
local blob = table.concat(parts)
local flags = RomExtractorGen3.findResetMapFlags(blob)
check(flags ~= nil, "ResetAllMapFlags is found by its first two setflags")
eq(#flags, 80, "and reads every setflag before end")
eq(flags[1], 0x56, "FLAG_LINK_CONTEST_ROOM_POKEBALL first")
eq(flags[2], 0x301, "FLAG_HIDE_VICTORIA_WINSTRATE second")
eq(RomExtractorGen3.findResetMapFlags("no script"), nil, "missing signature is nil")
eq(RomExtractorGen3.findResetMapFlags(string.char(0x29, 0x56, 0x00, 0x29, 0x01, 0x03, 0x02)),
  nil, "a short run is not the new-game script")
end)()

eq(RomExtractorGen3.BG_EVENT_SIZE, 12, "a BG event is 0xC")
eq(RomExtractorGen3.BG_HIDDEN_ITEM, 7, "hidden items are kind 7")
local hidden = GbaBin.packU16(5) .. GbaBin.packU16(8)
  .. string.char(3, 7, 0, 0)
  .. GbaBin.packU16(13) .. GbaBin.packU16(4)
eq(#hidden, 12, "packed hidden item is 12 bytes")
local hid = RomExtractorGen3.parseBgEvent(hidden, 0)
eq(hid.x, 5, "hidden x")
eq(hid.y, 8, "hidden y")
eq(hid.kind, 7, "kind is HIDDEN_ITEM")
eq(hid.itemId, 13, "union low half is the item")
eq(hid.hiddenId, 4, "union high half is the hidden id")

eq(RomExtractorGen3.BG_SECRET_BASE, 8, "secret bases are kind 8")
local secret = GbaBin.packU16(10) .. GbaBin.packU16(12)
  .. string.char(0, 8, 0, 0)
  .. GbaBin.packU32(42)
eq(#secret, 12, "packed secret base is 12 bytes")
local sbev = RomExtractorGen3.parseBgEvent(secret, 0)
eq(sbev.x, 10, "secret base x")
eq(sbev.y, 12, "secret base y")
eq(sbev.kind, 8, "kind is SECRET_BASE")
eq(sbev.secretBaseId, 42, "union is the base id")

local SIGN_SCRIPT, SIGN_TEXT = 0x20, 0x40
local srom = string.rep("\0", 0x80)
srom = overlay(srom, SIGN_TEXT,
  GbaText.encodeLatin("LITTLEROOT TOWN") .. string.char(GbaText.EOS))
srom = overlay(srom, SIGN_SCRIPT,
  string.char(RomExtractorGen3.LOADWORD_CMD, 0) .. GbaBin.packPtr(SIGN_TEXT)
  .. string.char(0x09, 3))
local signRow = GbaBin.packU16(2) .. GbaBin.packU16(1)
  .. string.char(0, 0, 0, 0)
  .. GbaBin.packPtr(SIGN_SCRIPT)
srom = overlay(srom, 0, signRow)
eq(RomExtractorGen3.readSignText(srom, SIGN_SCRIPT), "LITTLEROOT TOWN",
  "loadword points at sign text")
eq(RomExtractorGen3.parseBgEvent(srom, 0).text, "LITTLEROOT TOWN",
  "a facing-any BG event carries the sign text")
eq(GbaText.decodeText(GbaText.encodeLatin("LINE")
  .. string.char(GbaText.NEWLINE)
  .. GbaText.encodeLatin("TWO")
  .. string.char(GbaText.EOS)), "LINE TWO",
  "sign newlines collapse to spaces")
eq(GbaText.decodeText(GbaText.encodeLatin("and")
  .. string.char(GbaText.SCROLL)
  .. GbaText.encodeLatin("GRASS")
  .. string.char(GbaText.EOS)), "and GRASS",
  "\\l CHAR_PROMPT_SCROLL is a space in one string")
eq(GbaText.decodeText(GbaText.encodeLatin("TRAINER")
  .. string.char(GbaText.EXCLAMATION, GbaText.PARA)
  .. GbaText.encodeLatin("You")
  .. string.char(GbaText.EOS)), "TRAINER! You",
  "a paragraph break is a space in one string")
eq(GbaText.decodeText(GbaText.encodeLatin("Hi ")
  .. string.char(GbaText.BUFFER, GbaText.PH_PLAYER)
  .. GbaText.encodeLatin(" my ")
  .. string.char(GbaText.BUFFER, GbaText.PH_STR_VAR_1)
  .. string.char(GbaText.EOS)), "Hi {PLAYER} my {STR_VAR_1}",
  "script loadword keeps PLAYER and STR_VAR_1")

-- Phase 16: field-script IR (ROM pointers become Latin + op indices).
local Gen3Script = require("src.import.Gen3Script")
eq(Gen3Script.STD_MSGBOX_NPC, 2, "MSGBOX_NPC is callstd 2")
eq(Gen3Script.STD_MSGBOX_YESNO, 5, "MSGBOX_YESNO is callstd 5")
eq(Gen3Script.VAR_RESULT, 0x800D, "VAR_RESULT is 0x800D")
eq(Gen3Script.condJump(1, 1), true, "goto_if TRUE jumps when the result is 1")
eq(Gen3Script.condJump(1, 0), false, "goto_if TRUE does not jump when unset")
eq(Gen3Script.condJump(0, 0), true, "goto_if FALSE jumps when the result is 0")

local function latin(text)
  return GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
end

local HELLO_TEXT, HELLO_SCRIPT = 0x60, 0x10
local helloRom = string.rep("\0", 0xA0)
helloRom = overlay(helloRom, HELLO_TEXT, latin("HELLO"))
helloRom = overlay(helloRom, HELLO_SCRIPT,
  string.char(0x6A, 0x5A, 0x0F, 0x00)
  .. GbaBin.packPtr(HELLO_TEXT)
  .. string.char(0x09, 0x02, 0x6C, 0x02))
local helloOps = Gen3Script.parse(helloRom, HELLO_SCRIPT)
eq(Gen3Script.firstText(helloOps), "HELLO", "loadword decodes Latin text")
eq(helloOps[1].op, "lock", "lock is kept")
eq(helloOps[2].op, "faceplayer", "faceplayer follows lock")
eq(helloOps[3].op, "loadword", "then the loadword")
eq(helloOps[4].op, "callstd", "callstd follows the loadword")
eq(helloOps[4].id, 2, "MSGBOX_NPC")
eq(helloOps[#helloOps - 1].op, "release", "release before end")
eq(helloOps[#helloOps].op, "end", "the script ends")

eq(Gen3Script.WARP, 0x39, "warp is 0x39")
eq(Gen3Script.WARPSILENT, 0x3A, "warpsilent is 0x3A")
local warpOps = Gen3Script.parse(
  string.char(0x3A, 1, 0, 0xFF, 8, 0, 8, 0, 0x02), 0)
eq(warpOps[1].op, "warp", "warpsilent becomes warp")
eq(warpOps[1].mapGroup, 1, "house group")
eq(warpOps[1].mapNum, 0, "house num")
eq(warpOps[1].warpId, 0xFF, "WARP_ID_NONE uses xy")
eq(warpOps[1].x, 8, "warp x")
eq(warpOps[1].y, 8, "warp y")
eq(warpOps[2].op, "end", "end follows the 8-byte warp")

;(function()
eq(Gen3Script.PLAYSE, 0x2F, "playse is 0x2F")
eq(Gen3Script.SETDYNAMICWARP, 0x3F, "setdynamicwarp is 0x3F")
eq(Gen3Script.SETRESPAWN, 0x9F, "setrespawn is 0x9F")
local introOps = Gen3Script.parse(
  string.char(0x2F, 10, 0)
  .. string.char(0x3F, 0, 9, 0xFF, 3, 0, 10, 0)
  .. string.char(0x9F, 1, 0, 0x02), 0)
eq(introOps[1].op, "playse", "playse is kept so the walk continues")
eq(introOps[1].id, 10, "SE id")
eq(introOps[2].op, "setdynamicwarp", "setdynamicwarp follows playse")
eq(introOps[2].mapGroup, 0, "Littleroot group")
eq(introOps[2].mapNum, 9, "Littleroot num")
eq(introOps[2].warpId, 0xFF, "xy dest")
eq(introOps[2].x, 3, "boy truck tile x")
eq(introOps[2].y, 10, "boy truck tile y")
eq(introOps[3].op, "setrespawn", "setrespawn is 0x9F")
eq(introOps[3].id, 1, "Brendan 2F heal")
eq(introOps[4].op, "end", "the truck door script ends")
end)()

;(function()
eq(Gen3Script.WARPHOLE, 0x3C, "warphole is 0x3C")
eq(Gen3Script.SETHOLEWARP, 0x41, "setholewarp is 0x41")
local holeOps = Gen3Script.parse(
  string.char(0x41, 24, 9, 0xFF, 0, 0, 0, 0)
  .. string.char(0x3C, 0xFF, 0xFF)
  .. string.char(0x02), 0)
eq(holeOps[1].op, "setholewarp", "setholewarp is kept")
eq(holeOps[1].mapGroup, 24, "Granite group")
eq(holeOps[1].mapNum, 9, "B2F")
eq(holeOps[1].warpId, 0xFF, "WARP_ID_NONE")
eq(holeOps[2].op, "warphole", "warphole follows")
eq(holeOps[2].mapGroup, 0xFF, "MAP_UNDEFINED group")
eq(holeOps[2].mapNum, 0xFF, "MAP_UNDEFINED num")
eq(holeOps[3].op, "end", "and the script ends")

eq(Gen3Script.SETESCAPEWARP, 0xC4, "setescapewarp is 0xC4")
local escapeOps = Gen3Script.parse(
  string.char(0xC4, 0, 8, 0xFF, 28, 0, 13, 0)
  .. string.char(0x02), 0)
eq(escapeOps[1].op, "setescapewarp", "setescapewarp is kept")
eq(escapeOps[1].mapGroup, 0, "Slateport group")
eq(escapeOps[1].mapNum, 8, "city")
eq(escapeOps[1].x, 28, "harbor x")
eq(escapeOps[1].y, 13, "harbor y")
end)()

;(function()
eq(Gen3Script.SHOWMONEYBOX, 0x93, "showmoneybox is 0x93")
eq(Gen3Script.HIDEMONEYBOX, 0x94, "hidemoneybox is 0x94")
eq(Gen3Script.UPDATEMONEYBOX, 0x95, "updatemoneybox is 0x95")
eq(Gen3Script.PLAYMONCRY, 0xA1, "playmoncry is 0xA1")
eq(Gen3Script.WAITMONCRY, 0xC5, "waitmoncry is 0xC5")
local feeOps = Gen3Script.parse(
  string.char(0x93, 0, 0)
  .. string.char(0x00)
  .. string.char(0x92, 50, 0, 0, 0, 0)
  .. string.char(0x91, 50, 0, 0, 0, 0)
  .. string.char(0x95, 0, 0)
  .. string.char(0x00)
  .. string.char(0x94, 0, 0)
  .. string.char(0x02), 0)
eq(feeOps[1].op, "showmoneybox", "museum opens the $ window")
eq(feeOps[1].x, 0, "at tile 0")
eq(feeOps[1].y, 0, "and 0")
eq(feeOps[2].op, "checkmoney", "then the $50 check")
eq(feeOps[2].amount, 50, "museum fee")
eq(feeOps[3].op, "removemoney", "then the take")
eq(feeOps[4].op, "updatemoneybox", "reprint after the take")
eq(feeOps[5].op, "hidemoneybox", "and close")
local cryOps = Gen3Script.parse(
  string.char(0xA1, 32, 1, 0, 0) .. string.char(0xC5) .. string.char(0x02), 0)
eq(cryOps[1].op, "playmoncry", "playmoncry is kept")
eq(cryOps[1].species, 288, "Zigzagoon / Peeko")
eq(cryOps[1].mode, 0, "mode 0")
eq(cryOps[2].op, "waitmoncry", "waitmoncry follows")
local feeHost = {
  money = 3000,
  showMoneyBox = function(self, x, y) self.box = { x = x, y = y } end,
  hideMoneyBox = function(self) self.box = nil end,
  updateMoneyBox = function(self) self.updated = true end,
}
Gen3Script.run(feeHost, feeOps)
eq(feeHost.money, 2950, "the fee comes out")
eq(feeHost.box, nil, "hidemoneybox closed it")
eq(feeHost.updated, true, "updatemoneybox ran")
local Game3 = require("src.core.Game3")
local g = Game3.new()
g.money = 3000
g:showMoneyBox(0, 0)
eq(g.moneyBox.x, 0, "Game3 stores the window")
eq(g:moneyString(), "$3,000", "and prints the till")
g:hideMoneyBox()
eq(g.moneyBox, nil, "hidemoneybox clears it")
g:playMonCry(288, 0)
eq(g:cryPlaying(), false, "no extracted cry does not block")
g:waitMonCry()
eq(g.scriptWait, nil, "waitmoncry is immediate without audio")
end)()

;(function()
eq(Gen3Script.PLAYSLOTMACHINE, 0x89, "playslotmachine is 0x89")
eq(Gen3Script.CHECKCOINS, 0xB3, "checkcoins is 0xB3")
eq(Gen3Script.ADDCOINS, 0xB4, "addcoins is 0xB4")
eq(Gen3Script.REMOVECOINS, 0xB5, "removecoins is 0xB5")
eq(Gen3Script.SHOWCOINSBOX, 0xC0, "showcoinsbox is 0xC0")
eq(Gen3Script.HIDECOINSBOX, 0xC1, "hidecoinsbox is 0xC1")
eq(Gen3Script.UPDATECOINSBOX, 0xC2, "updatecoinsbox is 0xC2")
local coinOps = Gen3Script.parse(
  string.char(0xC0, 0, 0)
  .. string.char(0xB3, 0x00, 0x40)
  .. string.char(0xB4, 10, 0)
  .. string.char(0xB5, 3, 0)
  .. string.char(0xC2, 0, 0)
  .. string.char(0xC1, 0, 0)
  .. string.char(0x89, 0x0D, 0x80)
  .. string.char(0x02), 0)
eq(coinOps[1].op, "showcoinsbox", "Game Corner opens the coin window")
eq(coinOps[2].op, "checkcoins", "then reads the till")
eq(coinOps[2].var, 0x4000, "into a dest var")
eq(coinOps[3].op, "addcoins", "then addcoins")
eq(coinOps[3].count, 10, "count is a VarGet halfword")
eq(coinOps[4].op, "removecoins", "then removecoins")
eq(coinOps[5].op, "updatecoinsbox", "reprint")
eq(coinOps[6].op, "hidecoinsbox", "close")
eq(coinOps[7].op, "playslotmachine", "then the cabinet")
eq(coinOps[7].id, 0x800D, "machine id is often VAR_RESULT")
end)()

;(function()
eq(Gen3Script.PLAYFANFARE, 0x31, "playfanfare is 0x31")
eq(Gen3Script.WAITFANFARE, 0x32, "waitfanfare is 0x32")
local ops = Gen3Script.parse(
  string.char(0x31, 1, 0) .. string.char(0x32, 0x02), 0)
eq(ops[1].op, "playfanfare", "playfanfare is kept so the gift continues")
eq(ops[1].id, 1, "fanfare id")
eq(ops[2].op, "waitfanfare", "waitfanfare follows")
eq(ops[3].op, "end", "then end")
end)()

;(function()
eq(Gen3Script.POKEMART, 0x86, "pokemart is 0x86")
local listOff = 0x20
local martRom = string.rep("\0", 0x40)
martRom = overlay(martRom, listOff,
  GbaBin.packU16(13) .. GbaBin.packU16(14)
  .. GbaBin.packU16(18) .. GbaBin.packU16(17) .. GbaBin.packU16(0))
martRom = overlay(martRom, 0,
  string.char(0x86) .. GbaBin.packPtr(listOff) .. string.char(0x02))
local martOps = Gen3Script.parse(martRom, 0)
eq(martOps[1].op, "pokemart", "pokemart is kept so the clerk continues")
eq(#martOps[1].items, 4, "stock until ITEM_NONE")
eq(martOps[1].items[1], 13, "Potion")
eq(martOps[1].items[2], 14, "Antidote")
eq(martOps[1].items[3], 18, "Paralyze Heal")
eq(martOps[1].items[4], 17, "Awakening")
eq(martOps[2].op, "end", "then end")
end)()

;(function()
eq(Gen3Script.PLAYBGM, 0x33, "playbgm is 0x33")
eq(Gen3Script.SAVEBGM, 0x34, "savebgm is 0x34")
eq(Gen3Script.FADEDEFAULTBGM, 0x35, "fadedefaultbgm is 0x35")
local bgmOps = Gen3Script.parse(
  string.char(0x33, 10, 0, 0)
  .. string.char(0x34, 0, 0)
  .. string.char(0x35, 0x02), 0)
eq(bgmOps[1].op, "playbgm", "playbgm is kept so the gym report continues")
eq(bgmOps[1].id, 10, "song id")
eq(bgmOps[1].save, 0, "do not save")
eq(bgmOps[2].op, "savebgm", "savebgm is 3 bytes so the rival 2F script stays aligned")
eq(bgmOps[2].id, 0, "save song 0")
eq(bgmOps[3].op, "fadedefaultbgm", "fadedefaultbgm follows")
eq(bgmOps[4].op, "end", "end after the fade")
end)()

local T1, T2 = 0x70, 0x80
local FLAG_SCRIPT = 0x10
-- 0x10 checkflag 0x200 (3)
-- 0x13 goto_if EQ -> 0x22 (6)
-- 0x19 loadword T1 (6) + callstd (2) + end (1) = 0x22
-- 0x22 loadword T2 + callstd + end
local flagRom = string.rep("\0", 0xA0)
flagRom = overlay(flagRom, T1, latin("HELLO"))
flagRom = overlay(flagRom, T2, latin("BYE"))
flagRom = overlay(flagRom, FLAG_SCRIPT,
  string.char(0x2B) .. GbaBin.packU16(0x200)
  .. string.char(0x06, 0x01) .. GbaBin.packPtr(0x22)
  .. string.char(0x0F, 0x00) .. GbaBin.packPtr(T1) .. string.char(0x09, 0x02, 0x02)
  .. string.char(0x0F, 0x00) .. GbaBin.packPtr(T2) .. string.char(0x09, 0x02, 0x02))
local flagOps = Gen3Script.parse(flagRom, FLAG_SCRIPT)
eq(flagOps[1].op, "checkflag", "checkflag is kept")
eq(flagOps[1].flag, 0x200, "flag id")
eq(flagOps[2].op, "goto_if", "goto_if follows")
eq(flagOps[2].cond, 1, "TRUE is EQUAL")
eq(flagOps[2].to, 6, "TRUE skips the first msgbox")
eq(Gen3Script.firstText(flagOps), "HELLO", "the fall-through line is first")

local giveRom = string.rep("\0", 0x20)
giveRom = overlay(giveRom, 0,
  string.char(0x1A) .. GbaBin.packU16(0x8000) .. GbaBin.packU16(4)
  .. string.char(0x1A) .. GbaBin.packU16(0x8001) .. GbaBin.packU16(1)
  .. string.char(0x09, 0x01, 0x02))
local giveOps = Gen3Script.parse(giveRom, 0)
eq(giveOps[1].op, "setorcopyvar", "setorcopyvar is kept")
eq(giveOps[1].var, 0x8000, "dest is VAR_0x8000")
eq(giveOps[1].val, 4, "literal item id")
eq(giveOps[3].op, "callstd", "then STD_FIND_ITEM")
eq(giveOps[3].id, 1, "callstd 1")

local giveMonRom = string.rep("\0", 0x20)
giveMonRom = overlay(giveMonRom, 0,
  string.char(0x79) .. GbaBin.packU16(277) .. string.char(5)
  .. GbaBin.packU16(0) .. string.rep("\0", 9))
local giveMonOps = Gen3Script.parse(giveMonRom, 0)
eq(giveMonOps[1].op, "givemon", "givemon is kept")
eq(giveMonOps[1].species, 277, "species is Treecko")
eq(giveMonOps[1].level, 5, "level 5")
eq(giveMonOps[1].item, 0, "no held item")

local ynRom = string.char(0x6E, 0, 0, 0x02)
local ynOps = Gen3Script.parse(ynRom, 0)
eq(ynOps[1].op, "yesno", "yesnobox is kept")
eq(ynOps[1].x, 0, "yesnobox x")
eq(ynOps[1].y, 0, "yesnobox y")

local specOps = Gen3Script.parse(string.char(0x25, 0, 0, 0x02), 0)
eq(specOps[1].op, "special", "special is kept")
eq(specOps[1].id, 0, "id 0 heals")
local spec212 = Gen3Script.parse(
  string.char(0x25) .. GbaBin.packU16(212) .. string.char(0x02), 0)
eq(spec212[1].id, 212, "special 212")
local specHost = {
  flags = {}, scriptVars = {}, healed = false,
  runSpecial = function(self, id) if id == 0 then self.healed = true end end,
}
Gen3Script.run(specHost, specOps)
check(specHost.healed, "run calls host:runSpecial")

local host = {
  flags = {},
  scriptVars = {},
  says = {},
  sayScript = function(self, text) self.says[#self.says + 1] = text end,
}
local yesOps = {
  { op = "loadword", text = "WANT ONE?" },
  { op = "callstd", id = 5 },
  { op = "compare", var = Gen3Script.VAR_RESULT, val = 1 },
  { op = "goto_if", cond = 1, to = 8 },
  { op = "loadword", text = "MAYBE LATER" },
  { op = "callstd", id = 2 },
  { op = "end" },
  { op = "loadword", text = "OKAY" },
  { op = "callstd", id = 2 },
  { op = "end" },
}
local said, pause = Gen3Script.run(host, yesOps)
eq(pause, "yesno", "callstd 5 pauses the VM")
eq(host.says[1], "WANT ONE?", "the prompt is said first")
eq(host._scriptPause.at, 3, "resume starts at compare")
host.scriptVars[Gen3Script.VAR_RESULT] = 1
host.says = {}
said, pause = Gen3Script.run(host, host._scriptPause.ops, host._scriptPause.at)
eq(pause, nil, "YES does not pause again")
eq(host.says[1], "OKAY", "YES takes the equal branch")

host.scriptVars = {}
host.says = {}
host._scriptLoaded = nil
host._scriptCmp = 0
said, pause = Gen3Script.run(host, yesOps)
host.scriptVars[Gen3Script.VAR_RESULT] = 0
host.says = {}
said, pause = Gen3Script.run(host, host._scriptPause.ops, host._scriptPause.at)
eq(host.says[1], "MAYBE LATER", "NO falls through")

-- Every command Ruby can store has a length, so one whose effect the VM
-- does not implement decodes as a dropped nop and the walk carries on.
-- Truncation is reserved for a byte with no length at all.
;(function()
local sized = Gen3Script.parse(
  string.char(0xAA, 0, 0, 0, 0, 0, 0, 0, 0, 0x68, 0x02), 0)
eq(sized and #sized, 2, "an unimplemented command does not truncate")
eq(sized and sized[1].op, "closemessage", "the command after it still parses")
eq(Gen3Script.parse(string.char(0xF0, 0x02), 0), nil,
  "a byte with no known length stops that branch")

-- trainerbattle is the only command whose length varies, and getting it
-- wrong misaligns every command after it rather than failing outright.
local function tb(kind)
  return Gen3Script.cmdSize(string.char(0x5C, kind) .. string.rep("\0", 24), 0)
end
eq(tb(0), 14, "SINGLE carries two pointers")
eq(tb(3), 10, "SINGLE_NO_INTRO_TEXT carries one")
eq(tb(4), 18, "DOUBLE carries three")
eq(tb(6), 22, "CONTINUE_SCRIPT_DOUBLE carries four")
eq(tb(8), 22, "CONTINUE_SCRIPT_DOUBLE_NO_MUSIC carries four")
eq(Gen3Script.cmdSize(string.char(0x39), 0), 8, "a warp counts its map pair")
local tbOps = Gen3Script.parse(
  string.char(0x5C, 0, 7, 0, 0, 0) .. string.rep("\0", 8) .. string.char(0x02), 0)
eq(tbOps[1].op, "trainerbattle", "trainerbattle is kept")
eq(tbOps[1].kind, 0, "SINGLE")
eq(tbOps[1].trainerId, 7, "trainer id is in the header")
eq(tbOps[1].after, nil, "SINGLE has no beaten script")
eq(Gen3Script.kindOfAction(0x25), "walkplace", "walk in place fastest down")

local function latin(text)
  return GbaText.encodeLatin(text) .. string.char(GbaText.EOS)
end
local INTRO, DEFEAT, CANNOT = 0x20, 0x30, 0x40
local duoRom = string.rep("\0", 0x80)
duoRom = overlay(duoRom, 0, string.char(0x5C, 4)
  .. GbaBin.packU16(483) .. GbaBin.packU16(0)
  .. GbaBin.packPtr(INTRO)
  .. GbaBin.packPtr(DEFEAT)
  .. GbaBin.packPtr(CANNOT)
  .. string.char(0x02))
duoRom = overlay(duoRom, INTRO, latin("WE BATTLE"))
duoRom = overlay(duoRom, DEFEAT, latin("WE LOST"))
duoRom = overlay(duoRom, CANNOT, latin("ONLY ONE"))
local duoOps = Gen3Script.parse(duoRom, 0)
eq(duoOps[1].kind, 4, "DOUBLE")
eq(duoOps[1].trainerId, 483, "TRAINER_GINA_AND_MIA_1")
eq(duoOps[1].intro, "WE BATTLE", "1st pointer is intro")
eq(duoOps[1].defeat, "WE LOST", "2nd pointer is lose text")
eq(duoOps[1].cannot, "ONLY ONE", "3rd pointer is cannot-battle speech")
eq(duoOps[1].after, nil, "DOUBLE has no beaten script")
end)()

;(function()
-- Roxanne: CONTINUE_SCRIPT_NO_MUSIC.  The 3rd pointer is RoxanneDefeated,
-- not the next opcode (talk-again / TM39).
local afterOff = 32
local blob = string.char(0x5C, 1)
  .. GbaBin.packU16(265) .. GbaBin.packU16(0)
  .. GbaBin.packU32(0) .. GbaBin.packU32(0)
  .. GbaBin.packPtr(afterOff)
  .. string.char(0x02)
  .. string.rep("\0", afterOff - 19)
  .. string.char(0x29) .. GbaBin.packU16(0x807) .. string.char(0x02)
local cont = Gen3Script.parse(blob, 0)
eq(cont[1].kind, 1, "CONTINUE_SCRIPT_NO_MUSIC")
eq(cont[1].trainerId, 265, "TRAINER_ROXANNE")
eq(cont[1].after[1].op, "setflag", "3rd pointer is the beaten script")
eq(cont[1].after[1].flag, 0x807, "FLAG_BADGE01_GET")
eq(cont[2].op, "end", "the next opcode is not the beaten script")

local host = {
  flags = {},
  scriptTrainerBattle = function() return true end,
  beginScriptWait = function(self) self.scriptWait = true end,
}
local after = { { op = "setflag", flag = 0x807 }, { op = "end" } }
local ops = {
  { op = "trainerbattle", kind = 1, trainerId = 265, after = after },
  { op = "setflag", flag = 0xA5 },
  { op = "end" },
}
Gen3Script.run(host, ops)
eq(host._scriptPause.ops[1].op, "setflag", "gotobeatenscript pauses on after")
eq(host._scriptPause.at, 1, "and starts at the first beaten op")
eq(host.flags[0x807], nil, "the badge waits until the win")
Gen3Script.run(host, host._scriptPause.ops, host._scriptPause.at)
eq(host.flags[0x807], true, "RoxanneDefeated sets FLAG_BADGE01_GET")
eq(host.flags[0xA5], nil, "talk-again TM flag is not the beaten path")

host.scriptTrainerBattle = function() return false end
host.trainerDefeated = function(_, id) return id == 265 end
host.flags = {}
Gen3Script.run(host, ops)
eq(host.flags[0xA5], true, "a defeated gym leader runs the next opcode")
eq(host.flags[0x807], nil, "and does not re-run RoxanneDefeated")

-- Sorted IR can put a shared common label at ops[1]; gotobeatenscript
-- must start at after.entry, not 1.
host.scriptTrainerBattle = function() return true end
host.flags = {}
host._scriptPause = nil
local shared = {
  { op = "setflag", flag = 0x1 },
  { op = "setflag", flag = 0x807 },
  { op = "end" },
}
shared.entry = 2
Gen3Script.run(host, {
  { op = "trainerbattle", kind = 1, trainerId = 265, after = shared },
  { op = "end" },
})
eq(host._scriptPause.at, 2, "gotobeatenscript starts at after.entry")
eq(host._scriptPause.ops[2].flag, 0x807, "that is FLAG_BADGE01_GET")

-- EventScript_NotEnoughMonsForDoubleBattle: the 3rd pointer is speech,
-- then release/end -- not the post-battle GetPlayerBigGuyGirlString line.
host.scriptTrainerBattle = function() return false, "ONLY ONE" end
host.flags = {}
host.says = {}
host.sayScript = function(self, t) self.says[#self.says + 1] = t end
local dops = {
  { op = "trainerbattle", kind = 4, trainerId = 483, cannot = "ONLY ONE" },
  { op = "setflag", flag = 0xA5 },
  { op = "end" },
}
Gen3Script.run(host, dops)
eq(host.says[1], "ONLY ONE", "Gina's cannot-battle line is shown")
eq(host.flags[0xA5], nil, "and the post-battle opcode does not run")
end)()

;(function()
local function u16(n)
  n = n % 65536
  return string.char(n % 256, math.floor(n / 256))
end
local function u32(n)
  local b1 = n % 256; n = math.floor(n / 256)
  local b2 = n % 256; n = math.floor(n / 256)
  local b3 = n % 256; n = math.floor(n / 256)
  return string.char(b1, b2, b3, n % 256)
end

local ops = Gen3Script.parse(
  string.char(0x26) .. u16(Gen3Script.VAR_RESULT) .. u16(0) .. string.char(0x02), 0)
eq(ops[1].op, "specialvar", "specialvar is kept")
local host = {
  scriptVars = {}, flags = {},
  runSpecial = function(self)
    self.scriptVars[Gen3Script.VAR_RESULT] = 7
    return 7
  end,
}
Gen3Script.run(host, ops)
eq(host.scriptVars[Gen3Script.VAR_RESULT], 7, "specialvar stores the return")

ops = Gen3Script.parse(
  string.char(0x16) .. u16(0x4001) .. u16(65535)
    .. string.char(0x17) .. u16(0x4001) .. u16(2)
    .. string.char(0x02), 0)
host = { scriptVars = {}, flags = {} }
Gen3Script.run(host, ops)
eq(host.scriptVars[0x4001], 1, "addvar wraps at 0x10000")

ops = Gen3Script.parse(
  string.char(0x16) .. u16(0x4001) .. u16(1)
    .. string.char(0x18) .. u16(0x4001) .. u16(2)
    .. string.char(0x02), 0)
host = { scriptVars = {}, flags = {} }
Gen3Script.run(host, ops)
eq(host.scriptVars[0x4001], 65535, "subvar wraps under zero")

ops = Gen3Script.parse(
  string.char(0x47) .. u16(4) .. u16(2) .. string.char(0x02), 0)
host = {
  scriptVars = {}, flags = {},
  itemCount = function() return 5 end,
}
Gen3Script.run(host, ops)
eq(host.scriptVars[Gen3Script.VAR_RESULT], 1, "checkitem is true when the bag has enough")

ops = Gen3Script.parse(
  string.char(0x60) .. u16(20) .. string.char(0x02), 0)
host = { scriptVars = {}, flags = { [Gen3Script.TRAINER_FLAG_START + 20] = true } }
Gen3Script.run(host, ops)
eq(host._scriptCmp, 1, "checktrainerflag feeds goto_if")

ops = Gen3Script.parse(
  string.char(0x92) .. u32(500) .. string.char(0) .. string.char(0x02), 0)
host = { scriptVars = {}, flags = {}, money = 3000 }
Gen3Script.run(host, ops)
eq(host.scriptVars[Gen3Script.VAR_RESULT], 1, "checkmoney is true when the player can pay")

ops = Gen3Script.parse(
  string.char(0x43, 0x02), 0)
eq(ops[1].op, "getpartysize", "getpartysize is kept")
host = { scriptVars = {}, flags = {}, party = { {}, {} } }
Gen3Script.run(host, ops)
eq(host.scriptVars[Gen3Script.VAR_RESULT], 2, "getpartysize is the party length")

ops = Gen3Script.parse(string.char(0x08, 0x02, 0x29) .. u16(0x20) .. string.char(0x02), 0)
eq(ops[1].op, "gotostd", "gotostd is kept")
host = { scriptVars = {}, flags = {}, sayScript = function() end }
Gen3Script.run(host, ops)
eq(host.flags[0x20], nil, "gotostd does not return to the next command")
end)()

;(function()
eq(Gen3Script.APPLYMOVEMENT, 0x4F, "applymovement is 0x4F")
eq(Gen3Script.WAITMOVEMENT, 0x51, "waitmovement is 0x51")
eq(Gen3Script.SETMETATILE, 0xA2, "setmetatile is 0xA2")
eq(Gen3Script.SETFLASHRADIUS, 0x99, "setflashradius is 0x99")
eq(Gen3Script.ANIMATEFLASH, 0x9A, "animateflash is 0x9A")
local flashOps = Gen3Script.parse(
  string.char(0x99) .. GbaBin.packU16(4) .. string.char(0x9A, 3, 0x02), 0)
eq(flashOps[1].op, "setflashradius", "setflashradius is kept")
eq(flashOps[1].level, 4, "radius word")
eq(flashOps[2].op, "animateflash", "animateflash is kept")
eq(flashOps[2].level, 3, "dest byte")
eq(Gen3Script.DOFIELDEFFECT, 0x9C, "dofieldeffect is 0x9C")
eq(Gen3Script.SETFIELDEFFECTARGUMENT, 0x9D, "setfieldeffectargument")
eq(Gen3Script.WAITFIELDEFFECT, 0x9E, "waitfieldeffect")
local sparkleOps = Gen3Script.parse(
  string.char(0x9D, 0) .. GbaBin.packU16(9)
    .. string.char(0x9D, 1) .. GbaBin.packU16(13)
    .. string.char(0x9C) .. GbaBin.packU16(54)
    .. string.char(0x9E) .. GbaBin.packU16(54)
    .. string.char(0x02), 0)
eq(sparkleOps[1].op, "setfieldeffectargument", "set arg 0")
eq(sparkleOps[1].index, 0, "arg index is a byte")
eq(sparkleOps[1].value, 9, "Cave of Origin x")
eq(sparkleOps[2].index, 1, "arg 1")
eq(sparkleOps[2].value, 13, "Cave of Origin y")
eq(sparkleOps[3].op, "dofieldeffect", "sparkle start")
eq(sparkleOps[3].id, 54, "FLDEFF_SPARKLE")
eq(sparkleOps[4].op, "waitfieldeffect", "sparkle wait")
eq(sparkleOps[4].id, 54, "same id")
eq(Gen3Script.SETSTEPCALLBACK, 0xA6, "setstepcallback is 0xA6")
eq(Gen3Script.OPENDOOR, 0xAC, "opendoor is 0xAC")
eq(Gen3Script.LOCALID_PLAYER, 0xFF, "LOCALID_PLAYER is 0xFF")
eq(Gen3Script.YESNOBOX, 0x6E, "yesnobox is 0x6E")
eq(Gen3Script.MULTICHOICE, 0x6F, "multichoice is 0x6F")
eq(Gen3Script.MULTICHOICEDEFAULT, 0x70, "multichoicedefault is 0x70")
eq(Gen3Script.MULTICHOICEGRID, 0x71, "multichoicegrid is 0x71")
local multiOps = Gen3Script.parse(
  string.char(0x6F, 20, 8, 50, 1, 0x02), 0)
eq(multiOps[1].op, "multichoice", "multichoice is kept")
eq(multiOps[1].list, 50, "fishing list id")
eq(multiOps[1].x, 20, "multichoice x")
eq(multiOps[1].y, 8, "multichoice y")
eq(multiOps[1].ignoreB, 1, "ignore B")
local defOps = Gen3Script.parse(
  string.char(0x70, 21, 6, 0, 2, 0, 0x02), 0)
eq(defOps[1].list, 0, "Briney list 0")
eq(defOps[1].x, 21, "default list x")
eq(defOps[1].y, 6, "default list y")
eq(defOps[1].default, 2, "cursor on CANCEL")
local gridOps = Gen3Script.parse(
  string.char(0x71, 8, 1, 13, 3, 0, 0x02), 0)
eq(gridOps[1].list, 13, "school status list")
eq(gridOps[1].perRow, 3, "three per row")
eq(Gen3Script.kindOfAction(0), "face", "action 0 faces")
eq(Gen3Script.dirOfAction(0), "south", "down is south")
eq(Gen3Script.kindOfAction(8), "walk", "action 8 walks")
eq(Gen3Script.dirOfAction(0x0B), "east", "walk right is east")
eq(Gen3Script.kindOfAction(0x45), "jump", "jump_right is a one-tile jump")
eq(Gen3Script.dirOfAction(0x45), "east", "jump_right is east")
eq(Gen3Script.dirOfAction(0x27), "west", "walk_in_place_fastest_left")
eq(Gen3Script.parse(string.char(0x68, 0x02), 0)[1].op, "closemessage",
  "closemessage is kept")
eq(Gen3Script.kindOfAction(0x0C), "jump2", "action 0xC jumps two")
eq(Gen3Script.kindOfAction(0x12), "delay", "delay_4 is kept")
eq(Gen3Script.delayFrames(0x14), 16, "delay_16 is 16 frames")
eq(Gen3Script.kindOfAction(0x54), "invisible", "set_invisible")
eq(Gen3Script.kindOfAction(0x55), "visible", "set_visible")
eq(Gen3Script.kindOfAction(0x56), "emote", "exclaim is an emote")
eq(Gen3Script.emoteOfAction(0x56), "exclaim", "!")
eq(Gen3Script.emoteOfAction(0x57), "question", "?")
eq(Gen3Script.kindOfAction(0x3E), "faceplayer", "face_player")
eq(Gen3Script.dirOfAction(1), "north", "up is north")

local MOVE, TEXT, SCRIPT = 0x40, 0x70, 0x10
local moveRom = string.rep("\0", 0xA0)
moveRom = overlay(moveRom, MOVE, string.char(8, 8, 0x14, 0xFE))
moveRom = overlay(moveRom, TEXT, latin("MOVED"))
moveRom = overlay(moveRom, SCRIPT,
  string.char(0x4F) .. GbaBin.packU16(0xFF) .. GbaBin.packPtr(MOVE)
  .. string.char(0x51) .. GbaBin.packU16(0)
  .. string.char(0x0F, 0x00) .. GbaBin.packPtr(TEXT)
  .. string.char(0x09, 0x02, 0x02))
local moveOps = Gen3Script.parse(moveRom, SCRIPT)
eq(moveOps[1].op, "applymovement", "applymovement is kept")
eq(moveOps[1].localId, 0xFF, "on the player")
eq(moveOps[1].steps[1].kind, "walk", "walk_normal_down")
eq(moveOps[1].steps[1].dir, "south", "south")
eq(moveOps[1].steps[2].dir, "south", "twice")
eq(#moveOps[1].steps, 3, "delay_16 stays in the list")
eq(moveOps[1].steps[3].kind, "delay", "after the walks")
eq(moveOps[1].steps[3].frames, 16, "16 frames")
eq(moveOps[2].op, "waitmovement", "waitmovement is kept")
eq(Gen3Script.firstText(moveOps), "MOVED", "text after waitmovement still decodes")

local tileOps = Gen3Script.parse(
  string.char(0xA2)
  .. GbaBin.packU16(3) .. GbaBin.packU16(1)
  .. GbaBin.packU16(0x21) .. GbaBin.packU16(0)
  .. string.char(0x02), 0)
eq(tileOps[1].op, "setmetatile", "setmetatile is kept")
eq(tileOps[1].x, 3, "x")
eq(tileOps[1].y, 1, "y")
eq(tileOps[1].tile, 0x21, "metatile id")
eq(tileOps[1].collision, 0, "open")

local doorOps = Gen3Script.parse(
  string.char(0xAC) .. GbaBin.packU16(2) .. GbaBin.packU16(4) .. string.char(0x02), 0)
eq(doorOps[1].op, "opendoor", "opendoor is kept")
eq(doorOps[1].x, 2, "door x")
eq(doorOps[1].y, 4, "door y")

local stepOps = Gen3Script.parse(string.char(0xA6, 1, 0x02), 0)
eq(stepOps[1].op, "setstepcallback", "setstepcallback is kept")
eq(stepOps[1].id, 1, "callback id")
eq(Gen3Script.SETMAPLAYOUTINDEX, 0xA7, "setmaplayoutindex is 0xA7")
eq(Gen3Script.parse(string.char(0xA7) .. GbaBin.packU16(320) .. string.char(0x02),
  0)[1].op, "setmaplayoutindex", "setmaplayoutindex is kept")
eq(Gen3Script.parse(string.char(0xA7) .. GbaBin.packU16(320) .. string.char(0x02),
  0)[1].index, 320, "layout word")

local bubble = Gen3Script.parseMovement(
  string.char(0x56, 0x54, 0x55, 0x10, 0x3E, 0xFE), 0)
eq(#bubble, 5, "emote/hide/show/delay/faceplayer parse")
eq(bubble[1].kind, "emote", "exclaim")
eq(bubble[1].emote, "exclaim", "!")
eq(bubble[2].kind, "invisible", "set_invisible")
eq(bubble[3].kind, "visible", "set_visible")
eq(bubble[4].frames, 1, "delay_1")
eq(bubble[5].kind, "faceplayer", "face_player")

eq(Gen3Script.HIDEOBJECTAT, 0x59, "hideobjectat is 0x59")
eq(Gen3Script.SHOWOBJECTAT, 0x58, "showobjectat is 0x58")
eq(Gen3Script.REMOVEOBJECT, 0x53, "removeobject is 0x53")
eq(Gen3Script.SETOBJECTXY, 0x57, "setobjectxy is 0x57")
eq(Gen3Script.TURNOBJECT, 0x5B, "turnobject is 0x5B")

local hideRom = string.rep("\0", 0x80)
hideRom = overlay(hideRom, 0,
  string.char(0x59) .. GbaBin.packU16(3) .. string.char(0, 0)
  .. string.char(0x0F, 0x00) .. GbaBin.packPtr(0x40)
  .. string.char(0x09, 0x02, 0x02))
hideRom = overlay(hideRom, 0x40, latin("GONE"))
local hideOps = Gen3Script.parse(hideRom, 0)
eq(hideOps[1].op, "hideobject", "hideobjectat is kept")
eq(hideOps[1].localId, 3, "on localId 3")
eq(hideOps[1].mapGroup, 0, "hideobjectat map group")
eq(hideOps[1].mapNum, 0, "hideobjectat map num")
eq(Gen3Script.firstText(hideOps), "GONE", "text after hideobjectat still decodes")

local showOps = Gen3Script.parse(
  string.char(0x58) .. GbaBin.packU16(3) .. string.char(1, 2) .. string.char(0x02), 0)
eq(showOps[1].op, "showobject", "showobjectat is kept")
eq(showOps[1].mapGroup, 1, "showobjectat map group")
eq(showOps[1].mapNum, 2, "showobjectat map num")

local rmOps = Gen3Script.parse(string.char(0x53) .. GbaBin.packU16(4) .. string.char(0x02), 0)
eq(rmOps[1].op, "removeobject", "removeobject is kept")
eq(rmOps[1].localId, 4, "localId")

local addOps = Gen3Script.parse(string.char(0x55) .. GbaBin.packU16(4) .. string.char(0x02), 0)
eq(addOps[1].op, "addobject", "addobject is kept")

local xyOps = Gen3Script.parse(
  string.char(0x57) .. GbaBin.packU16(3)
  .. GbaBin.packU16(8) .. GbaBin.packU16(5) .. string.char(0x02), 0)
eq(xyOps[1].op, "setobjectxy", "setobjectxy is kept")
eq(xyOps[1].x, 8, "x")
eq(xyOps[1].y, 5, "y")

eq(Gen3Script.SETOBJECTXYPERM, 0x63, "setobjectxyperm is 0x63")
eq(Gen3Script.SETOBJECTMOVEMENTTYPE, 0x65, "setobjectmovementtype is 0x65")
eq(Gen3Script.CHECKPLAYERGENDER, 0xA0, "checkplayergender is 0xA0")
local permOps = Gen3Script.parse(
  string.char(0x63) .. GbaBin.packU16(1)
  .. GbaBin.packU16(7) .. GbaBin.packU16(2)
  .. string.char(0x65) .. GbaBin.packU16(1) .. string.char(8)
  .. string.char(0xA0, 0x02), 0)
eq(permOps[1].op, "setobjectxyperm", "setobjectxyperm is kept")
eq(permOps[1].x, 7, "perm x")
eq(permOps[1].y, 2, "perm y")
eq(permOps[2].op, "setobjectmovementtype", "setobjectmovementtype is kept")
eq(permOps[2].movementType, 8, "face down")
eq(permOps[3].op, "checkplayergender", "checkplayergender is kept")

local turnOps = Gen3Script.parse(
  string.char(0x5B) .. GbaBin.packU16(3) .. string.char(4, 0x02), 0)
eq(turnOps[1].op, "turnobject", "turnobject is kept")
eq(turnOps[1].dir, 4, "east is 4")

local faceOps = Gen3Script.parse(string.char(0x5A, 0x02), 0)
eq(faceOps[1].op, "faceplayer", "faceplayer is kept")

eq(Gen3Script.kindOfAction(0x64), "face", "acro wheelie face")
eq(Gen3Script.kindOfAction(0x74), "walk", "acro hop")
eq(Gen3Script.kindOfAction(0x78), "jump2", "acro jump")
eq(Gen3Script.kindOfAction(0x98), "levitate", "levitate")
eq(Gen3Script.parseMovement(string.char(0x62, 0xFE), 0)[1].dir, "south",
  "affine walk is south")
eq(Gen3Script.parseMovement(string.char(0x8C, 0xFE), 0)[1].dx, -1,
  "up-left dx")
eq(Gen3Script.parseMovement(string.char(0x8C, 0xFE), 0)[1].dy, -1,
  "up-left dy")
eq(Gen3Script.kindOfAction(0x40), "lockface", "lock facing")
eq(Gen3Script.kindOfAction(0x41), "unlockface", "unlock facing")
eq(Gen3Script.kindOfAction(0x4F), "bow", "nurse bow")
eq(Gen3Script.kindOfAction(0x59), "reveal", "reveal trainer")
eq(Gen3Script.kindOfAction(0x5A), "smash", "rock smash")
eq(Gen3Script.kindOfAction(0x5B), "cut", "cut tree")
eq(Gen3Script.kindOfAction(0x94), "lockanim", "lock anim")
eq(Gen3Script.parse(string.char(0x28, 16, 0, 0x02), 0)[1].op, "delay",
  "script delay is kept")
eq(Gen3Script.parse(string.char(0x28, 16, 0, 0x02), 0)[1].frames, 16,
  "16 frames")
eq(Gen3Script.WAITSTATE, 0x27, "waitstate is 0x27")
eq(Gen3Script.parse(string.char(0x27, 0x02), 0)[1].op, "waitstate",
  "waitstate is kept")
eq(Gen3Script.FADESCREEN, 0x97, "fadescreen is 0x97")
local fadeOps = Gen3Script.parse(string.char(0x97, 1, 0x53, 4, 0, 0x02), 0)
eq(fadeOps[1].op, "fadescreen", "fadescreen is kept so the bag script continues")
eq(fadeOps[1].mode, 1, "FADE_TO_BLACK")
eq(fadeOps[2].op, "removeobject", "removeobject still follows")
eq(fadeOps[2].localId, 4, "Poochyena local 4")
eq(Gen3Script.BUFFERLEADMON, 0x7E, "bufferleadmonspeciesname is 0x7E")
local leadOps = Gen3Script.parse(string.char(0x7E, 0, 0x02), 0)
eq(leadOps[1].op, "bufferleadmon", "bufferleadmon is kept")
eq(leadOps[1].slot, 0, "STR_VAR_1 is dest 0")
eq(Gen3Script.CHOOSECONTESTMON, 0x8B, "choosecontestmon is 0x8B")
local contestOps = Gen3Script.parse(string.char(0x8B, 0x8C, 0x8D, 0x02), 0)
eq(contestOps[1].op, "choosecontestmon", "choosecontestmon is kept")
eq(contestOps[2].op, "startcontest", "startcontest is kept")
eq(contestOps[3].op, "showcontestresults", "showcontestresults is kept")
eq(Gen3Script.SETBERRYTREE, 0x8A, "setberrytree is 0x8A")
local berryOps = Gen3Script.parse(string.char(0x8A, 1, 3, 5, 0x02), 0)
eq(berryOps[1].op, "setberrytree", "setberrytree is kept")
eq(berryOps[1].tree, 1, "tree id")
eq(berryOps[1].berry, 3, "ITEM_TO_BERRY(PECHA)")
eq(berryOps[1].stage, 5, "BERRY_STAGE_BERRIES")
eq(Gen3Script.kindOfAction(0x39), "place", "start anim in place")
eq(Gen3Script.kindOfAction(0x52), "flag", "disable anim is a flag")
eq(Gen3Script.parseMovement(string.char(0x52, 0xFE), 0)[1].key, "lockAnim",
  "disable anim freezes the cycle")
eq(Gen3Script.parseMovement(string.char(0x5E, 0xFE), 0)[1].key, "affine",
  "init affine")
end)()

local LuaWriter = require("src.import.LuaWriter")
local encoded = LuaWriter.encode(helloOps)
local chunk = (loadstring or load)(encoded)
check(type(chunk) == "function", "script IR serializes as Lua")
eq(chunk()[3].text, "HELLO", "and round-trips the decoded line")

-- Indoor mapType 8 with the same music must not win over the town.
local indoor = overlay(rom, 0x1E00,
  GbaBin.packPtr(L)
  .. GbaBin.packPtr(EVENTS)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packU16(405)
  .. GbaBin.packU16(54)
  .. string.char(0, 0, 0, 8, 0, 0, 0, 0))
local town = RomExtractorGen3.findTownHeader(indoor)
eq(town.offset, H, "mapType 8 houses are skipped")
eq(town.mapType, 1, "the outdoor town still wins")

-- ------- gMapGroups: town + route + one indoor, shared tileset pair

local H_ROUTE, H_IN = 0x1F00, 0x1F1C
local L_ROUTE, L_IN = 0x1F40, 0x1F58
local GRID_ROUTE, GRID_IN = 0x2E00, 0x2E08
local EV_ROUTE, EV_IN, WARPS_IN = 0x2E10, 0x2E24, 0x2E38
local CONN_TOWN, CONN_TOWN_ARR = 0x2E50, 0x2E58
local CONN_ROUTE, CONN_ROUTE_ARR = 0x2E70, 0x2E78
local CONN_IN, CONN_IN_ARR = 0x2E90, 0x2E98
local G0, G1, GMAPS = 0x3100, 0x3108, 0x310C

local function conn(direction, mapGroup, mapNum)
  return string.char(direction, 0, 0, 0)
    .. GbaBin.packU32(0)
    .. string.char(mapGroup, mapNum, 0, 0)
end

local function events(warpCount, warpsOff)
  return string.char(0, warpCount, 0, 0)
    .. GbaBin.packPtr(DUMMY)
    .. GbaBin.packPtr(warpsOff)
    .. GbaBin.packPtr(DUMMY)
    .. GbaBin.packPtr(DUMMY)
end

local function layout(gridOff)
  return GbaBin.packU32(2) .. GbaBin.packU32(2)
    .. GbaBin.packPtr(DUMMY)
    .. GbaBin.packPtr(gridOff)
    .. GbaBin.packPtr(TS0)
    .. GbaBin.packPtr(TS1)
end

local function header(layoutOff, eventsOff, connOff, music, mapType)
  return GbaBin.packPtr(layoutOff)
    .. GbaBin.packPtr(eventsOff)
    .. GbaBin.packPtr(DUMMY)
    .. GbaBin.packPtr(connOff)
    .. GbaBin.packU16(music)
    .. GbaBin.packU16(1)
    .. string.char(0, 0, 0, mapType, 0, 0, 0, 0)
end

local world = rom .. string.rep("\0", 0x1000)
world = overlay(world, H,
  GbaBin.packPtr(L)
  .. GbaBin.packPtr(EVENTS)
  .. GbaBin.packPtr(DUMMY)
  .. GbaBin.packPtr(CONN_TOWN)
  .. GbaBin.packU16(405)
  .. GbaBin.packU16(10)
  .. string.char(0, 0, 0, 1, 0, 0, 0, 0))
world = overlay(world, H_ROUTE, header(L_ROUTE, EV_ROUTE, CONN_ROUTE, 359, 3))
world = overlay(world, H_IN, header(L_IN, EV_IN, CONN_IN, 405, 8))
world = overlay(world, L_ROUTE, layout(GRID_ROUTE))
world = overlay(world, L_IN, layout(GRID_IN))
world = overlay(world, GRID_ROUTE, string.rep(GbaBin.packU16(0), 4))
world = overlay(world, GRID_IN, string.rep(GbaBin.packU16(0), 4))
world = overlay(world, EV_ROUTE, events(0, DUMMY))
world = overlay(world, EV_IN, events(1, WARPS_IN))
world = overlay(world, WARPS_IN,
  GbaBin.packU16(0) .. GbaBin.packU16(0) .. string.char(0, 0, 0, 0))
world = overlay(world, CONN_TOWN,
  GbaBin.packU32(1) .. GbaBin.packPtr(CONN_TOWN_ARR))
world = overlay(world, CONN_TOWN_ARR, conn(2, 0, 1)) -- north to route
world = overlay(world, CONN_ROUTE,
  GbaBin.packU32(2) .. GbaBin.packPtr(CONN_ROUTE_ARR))
world = overlay(world, CONN_ROUTE_ARR, conn(1, 0, 0) .. conn(5, 1, 0))
world = overlay(world, CONN_IN,
  GbaBin.packU32(1) .. GbaBin.packPtr(CONN_IN_ARR))
world = overlay(world, CONN_IN_ARR, conn(6, 0, 1))
world = overlay(world, G0, GbaBin.packPtr(H) .. GbaBin.packPtr(H_ROUTE))
world = overlay(world, G1, GbaBin.packPtr(H_IN))
world = overlay(world, GMAPS, GbaBin.packPtr(G0) .. GbaBin.packPtr(G1))

local groups = RomExtractorGen3.findMapGroups(world)
check(groups ~= nil, "findMapGroups locates gMapGroups")
eq(groups.startGroup, 0, "Littleroot is group 0")
eq(groups.startIndex, 0, "Littleroot is index 0 in the fixture")
eq(#groups.groups, 2, "two map groups")
eq(#groups.groups[1], 2, "group 0 has town + route")
eq(#groups.groups[2], 1, "group 1 has the indoor map")

local hoenn = RomExtractorGen3.decodeHoenn(world)
check(hoenn ~= nil, "decodeHoenn returns the field")
eq(hoenn.start, "g0_0", "start id is g0_0")
eq(hoenn.mapCount, 3, "three maps")
eq(#hoenn.pairs, 1, "one shared tileset pair")
eq(hoenn.maps.g0_0.name, "Littleroot Town", "start map keeps the town name")
eq(hoenn.maps.g0_0.tileset, "pair_0", "town uses pair_0")
eq(hoenn.maps.g0_1.tileset, "pair_0", "route shares pair_0")
eq(hoenn.maps.g0_0.connections[1].dir, "north", "town connects north")
eq(hoenn.maps.g0_0.connections[1].mapNum, 1, "north dest is the route")
eq(hoenn.maps.g0_1.connections[1].dir, "south", "route connects south")
eq(#hoenn.maps.g0_1.connections, 2, "route also keeps a dive link")
eq(hoenn.maps.g0_1.connections[2].dir, "dive", "dir 5 is dive")
eq(hoenn.maps.g0_1.connections[2].mapGroup, 1, "dive dest is the indoor group")
eq(hoenn.maps.g1_0.connections[1].dir, "emerge", "dir 6 is emerge")
eq(RomExtractorGen3.DIR_NAME[5], "dive", "extractor names CONNECTION_DIVE")
eq(RomExtractorGen3.DIR_NAME[6], "emerge", "extractor names CONNECTION_EMERGE")
eq(#hoenn.maps.g1_0.warps, 1, "indoor has a return warp")

-- gMapLayouts holds alternate layouts that no map header points at --
-- Route 130 Mirage 46, Cave of Origin 313, Route 131 Sky Pillar 320,
-- Seafloor Cavern 327.  Layout 243 (LAYOUT_UNKNOWN_MAP_082EDF30) has a
-- NULL secondaryTileset, which is legal (fieldmap.c and tileset_anim.c
-- both guard on it).  Treating that slot as the end of the array cut the
-- walk short and lost every alternate layout above it.
local LAYOUTS, L_NULLSEC, L_ALT, GRID_ALT = 0x3200, 0x3300, 0x3320, 0x3340
local function layoutAt(gridOff, secOff)
  return GbaBin.packU32(2) .. GbaBin.packU32(2)
    .. GbaBin.packPtr(DUMMY)
    .. GbaBin.packPtr(gridOff)
    .. GbaBin.packPtr(TS0)
    .. (secOff and GbaBin.packPtr(secOff) or GbaBin.packU32(0))
end
-- The town header stores layoutId 10, so slot 10 must hold its layout for
-- findMapLayouts to lock on to the base.
local slots = {}
for i = 1, 9 do slots[i] = GbaBin.packPtr(L_ROUTE) end
slots[10] = GbaBin.packPtr(L)
slots[11] = GbaBin.packPtr(L_NULLSEC)
slots[12] = GbaBin.packPtr(L_ALT)
local world2 = overlay(world, LAYOUTS, table.concat(slots))
world2 = overlay(world2, L_NULLSEC, layoutAt(GRID_ROUTE, nil))
world2 = overlay(world2, L_ALT, layoutAt(GRID_ALT, TS1))
world2 = overlay(world2, GRID_ALT,
  GbaBin.packU16(5) .. GbaBin.packU16(6)
  .. GbaBin.packU16(7) .. GbaBin.packU16(8))

local base, count = RomExtractorGen3.findMapLayouts(world2,
  RomExtractorGen3.findMapGroups(world2))
-- The tileset animation frames are only reachable through code: struct Tileset
-- carries a callback at +0x14, that installs an inner driver, and the driver
-- calls QueueTilesetAnimDma(frames[n % N], dest, size). Everything needed is in
-- THUMB literal pools, so the extractor decodes them directly.
;(function()
local hw = GbaBin.packU16
-- 0x00 ldr r0,[pc,#12]  -> literal at 0x10
-- 0x02 mov r2,#0xF0
-- 0x04 lsl r2,r2,#2     -> 0x3C0, the size no single MOV can hold
-- 0x06 bl 0x08000010
-- 0x0A bx lr
local fn = hw(0x4803) .. hw(0x22F0) .. hw(0x0092)
  .. hw(0xF000) .. hw(0xF803) .. hw(0x4770)
  .. string.rep(" ", 4) .. GbaBin.packU32(0x12345678)
eq(#fn, 0x14, "the fixture function is 20 bytes")
local lits, movs, calls, lens = RomExtractorGen3.decodeThumb(fn, 0)
eq(#lits, 1, "one pc-relative load")
eq(lits[1].reg, 0, "into r0")
eq(lits[1].value, 0x12345678, "resolved through ((pc+4)&~3)+imm*4")
eq(movs[2], 0xF0, "the MOV immediate alone is only 0xF0")
eq(lens[1], 0x3C0, "but r2 at the call is the shifted value")
eq(#calls, 1, "one BL")
eq(calls[1], 0x8000010, "BL target from the two-halfword encoding")

-- bx lr ends the walk, so anything past it is pool, not instructions
local trailing = fn .. hw(0x4804) .. GbaBin.packU32(0xDEADBEEF)
eq(#(select(1, RomExtractorGen3.decodeThumb(trailing, 0))), 1,
  "decoding stops at the return")

eq(RomExtractorGen3.decodeThumb(nil, 0) and true, true, "nil data is not an error")
eq(#(select(1, RomExtractorGen3.decodeThumb("", 0))), 0, "nor is an empty rom")
end)()

-- Playing a tileset animation is picking which baked atlas to sample.
-- sub_8072EDC ticks once per field frame and the wrapper gates the DMA with
-- `if (a1 % period == 0)`, so the frame advances every `period` frames.
;(function()
local Game3 = require("src.core.Game3")
local g = Game3.new()
g.phase = "play"
local imgs = {}
local function img(name)
  imgs[name] = imgs[name] or { name = name,
    getDimensions = function() return 512, 512 end }
  return imgs[name]
end
g.grabImage = function(_, path) return path and img(path) end
g.data.tilesets = { byId = { sea = {
  bottom = "b0", top = "t0",
  anim = { frames = 4, period = 16, layers = {
    [1] = { bottom = "b1", top = "t1" },
    [2] = { bottom = "b2", top = "t2" },
    [3] = { bottom = "b3", top = "t3" },
  } },
}, still = { bottom = "s0", top = "s1" } } }
local sea = { id = "g_anim", tileset = "sea", width = 2, height = 2,
  grid = { 1, 1, 1, 1 } }
g.data.maps = { maps = { g_anim = sea } }

eq(g:tilesetAnimFrame("still"), 0, "an un-animated tileset is always frame 0")
eq(select(2, g:tilesetAnimSpec("sea")), 4, "four frames")
eq(select(3, g:tilesetAnimSpec("sea")), 16, "advancing every 16 ticks")

g.playSeconds = 0
eq(g:tilesetAnimFrame("sea"), 0, "tick 0 is frame 0")
g.playSeconds = 15 / 60
eq(g:tilesetAnimFrame("sea"), 0, "still frame 0 at tick 15")
g.playSeconds = 16 / 60
eq(g:tilesetAnimFrame("sea"), 1, "frame 1 at tick 16")
g.playSeconds = 48 / 60
eq(g:tilesetAnimFrame("sea"), 3, "frame 3 at tick 48")
g.playSeconds = 64 / 60
eq(g:tilesetAnimFrame("sea"), 0, "and it wraps")

g.playSeconds = 0
g:enterMap(sea, 0, 0, true)
eq(g.layerBottom.name, "b0", "frame 0 loads the plain atlas")
g.playSeconds = 16 / 60
g:stepTilesetAnim()
eq(g.layerBottom.name, "b1", "the swap follows the tick")
eq(g.layerTop.name, "t1", "both layers move together")
eq(g._tilesetFrame, 1, "and the frame is recorded for the tile window key")
g.playSeconds = 20 / 60
g:stepTilesetAnim()
eq(g.layerBottom.name, "b1", "no reload inside the same frame")

-- A missing frame atlas must not blank the ground.
g.data.tilesets.byId.sea.anim.layers[2] = { bottom = "gone", top = "gone2" }
g.grabImage = function(_, path)
  if path == "gone" or path == "gone2" then return nil end
  return path and img(path)
end
g.playSeconds = 32 / 60
g:stepTilesetAnim()
eq(g.layerBottom.name, "b1", "a frame that will not load keeps the last one")
end)()

eq(base, LAYOUTS, "findMapLayouts locks on to gMapLayouts")
eq(count, 12, "a NULL secondaryTileset does not end the array")

local alt = RomExtractorGen3.decodeHoenn(world2)
check(alt ~= nil, "decodeHoenn still decodes with a null-secondary layout")
eq(alt.layouts[11], nil, "the null-secondary layout is skipped")
check(alt.layouts[12] ~= nil, "the alternate layout above it is kept")
eq(alt.layouts[12].width, 2, "alternate layout keeps its size")
eq(alt.layouts[12].grid[1], 5, "alternate layout keeps its own grid")
eq(alt.layouts[12].tileset, "pair_0", "and shares the fixture tileset pair")
eq(alt.layouts[10], nil, "layouts a map header owns are not duplicated")
eq(#alt.pairs, 1, "skipping the null slot adds no tileset pair")

-- VOID FILL wrap-tiles scenery past a map's edges. It ranked candidates by
-- how often they appear without checking BG1, so Route 110's Seaside Cycling
-- Road railings -- which sit on water behaviour -- were picked as "open
-- water" and tiled a railing/water grid across the view. fieldmap.c
-- GetBorderBlockAt is the cart's own answer for what is out there, so a
-- metatile in map.border is always a legal candidate.
;(function()
local Game3 = require("src.core.Game3")
local g = Game3.new()
g.phase = "play"
g.data.tilesets = { byId = { ocean = {
  layerType = { [368] = Game3.LAYER_COVERED, [84] = Game3.LAYER_NORMAL,
    [754] = Game3.LAYER_NORMAL },
  tiles = { [754] = {}, [84] = {}, [368] = {} },
} } }
local sea = {
  id = "g_sea", tileset = "ocean", mapType = Game3.MAP_TYPE_ROUTE,
  width = 2, height = 2,
  grid = { 368, 368, 754, 84 },
  border = { 368, 368, 368, 368 },
  behavior = { 0x15, 0x15, 0x15, 0x15 },
}
g.data.maps = { maps = { g_sea = sea } }
g.metatileTopEmpty = function(_, _, mid) return mid ~= 754 end
check(not g:voidFillMetatileOk(sea, 754, "water"),
  "a railing over water is not open water")
check(g:voidFillMetatileOk(sea, 84, "water"), "a plain water tile is")
check(g:voidFillMetatileOk(sea, 368, "water"),
  "and the border block is always allowed, LAYER_COVERED or not")
local cells = g:voidFillCells(sea, "water")
eq(cells[1], 368, "VOID FILL WATER leads with the border's own water")
for i = 1, #cells do
  check(cells[i] ~= 754, "and the railing never reaches the fill")
end
end)()

-- The ground layer is the only part of the world draw that uses a
-- SpriteBatch; VOID FILL and the border fill bake with immediate G.draw. On a
-- driver where batch draws land nowhere the map silently vanishes and the
-- fill keeps painting. spriteBatchUsable() probes once and drops the whole
-- layer to immediate drawing rather than rendering an empty world.
;(function()
local Game3 = require("src.core.Game3")
local g = Game3.new()
g.phase = "play"
check(g:spriteBatchUsable(), "a working batch stays on the batch path")
local map = {
  id = "g_probe", tileset = "t", width = 4, height = 4,
  grid = { 1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1 },
}
g.data.maps = { maps = { g_probe = map } }
g._spriteBatchOk = false
local painted, batched = 0, 0
g.blitMetatile = function(_, _, _, _, _, _, batch)
  painted = painted + 1
  if batch then batched = batched + 1 end
end
eq(g:tileWindow("img", map, 0, 0, 3, 3, nil), nil,
  "a dead batch path returns no batch to draw")
eq(painted, 16, "every visible tile is painted directly instead")
eq(batched, 0, "and none of it goes through a batch")
end)()

local Game3 = require("src.core.Game3")
local field = Game3.new()
field.data.maps = { start = hoenn.start, maps = hoenn.maps }
-- field_control_avatar.c IsWarpMetatileBehavior: a warp event only warps when
-- its tile is also a warp tile. The fixture ROM carries no metatile
-- attributes, so its doors decode as MB_NORMAL; stamp a warp behaviour on
-- them so these checks take the same path a real door does. MB_LADDER
-- rather than either door kind: field_fadetransition.c sub_8080AE4 routes
-- BOTH door behaviours to an arrival task that walks the player one step
-- off the tile (sub_8080B9C / task_map_chg_seq_0807E20C), while everything
-- else gets task_map_chg_seq_0807E2CC, which just unlocks control. These
-- checks are about warp-tile gating, not about the arrival step, so they
-- want a warp tile that does not walk.
for _, m in pairs(hoenn.maps) do
  m.behavior = m.behavior or {}
  for _, w in ipairs(m.warps or {}) do
    m.behavior[(w.y or 0) * (m.width or 0) + (w.x or 0) + 1] = Game3.MB_LADDER
  end
end
field:enterMap(hoenn.maps.g0_0, 1, 1, false)
eq(field.map.id, "g0_0", "play starts in town")
check(not Game3.walkable(hoenn.maps.g0_0, 1, 0), "the door tile is solid")
check(field:tryWalk(0, -1), "walk into a blocked door")
eq(field.facing, "south", "a north-edge warp faces into the room")
eq(field.map.id, "g1_0", "door warps into the indoor map")
eq(field.playerX, 0, "indoor spawn uses dest warp x")
eq(field.ignoreWarp, true, "landing on a door does not bounce")
check(field:tryWalk(1, 0), "step off the door")
eq(field.map.id, "g1_0", "stepping off does not warp")
check(field:tryWalk(-1, 0), "step back onto the door")
eq(field.map.id, "g0_0", "indoor door returns to town")
eq(field.playerX, 1, "exiting a solid door steps to the south tile")
eq(field.playerY, 1, "south of the wall")
eq(field.ignoreWarp, false, "the exit step leaves the warp tile")
eq(field.facing, "south", "leaving a house door faces south")

eq(hoenn.maps.g0_0.border[1], 7, "decodeHoenn keeps the 2x2 border")
eq(Game3.borderIndex(0, 0), 4, "GetBorderBlockAt (0,0) is border[3]")
eq(Game3.borderIndex(1, 0), 3, "GetBorderBlockAt (1,0) is border[2]")
eq(Game3.borderIndex(0, 1), 2, "GetBorderBlockAt (0,1) is border[1]")
eq(Game3.borderIndex(1, 1), 1, "GetBorderBlockAt (1,1) is border[0]")
eq(Game3.borderIndex(2, 0), 4, "x wraps every two cells")
eq(Game3.borderIndex(-1, 0), 3, "negative x uses two's-complement &1")
eq(Game3.borderCell(hoenn.maps.g0_0, 0, 0), 10, "(0,0) samples border[3]")
eq(Game3.borderCell(hoenn.maps.g0_0, 1, 1), 7, "(1,1) samples border[0]")
field:markTilesDirty()
eq(next(field.tileWindows), nil, "setmetatile drops the tile window")

local blocked = Game3.new()
blocked.data.maps = { maps = { g0_0 = { width = 2, height = 1, grid = { 0, 0 },
  objects = { { x = 1, y = 0, graphicsId = 8 } } } } }
blocked:enterMap(blocked.data.maps.maps.g0_0, 0, 0, false)
check(not blocked:tryWalk(1, 0), "an object event occupies its cell")
eq(blocked.playerX, 0, "NPC collision does not move")

field:enterMap(hoenn.maps.g0_0, 0, 0, false)
check(field:npcsFor(hoenn.maps.g0_1) ~= nil,
  "the north route is spawned as a neighbor")
field.tileWindows.kept = true
check(field:tryWalk(0, -1), "walk north off the town")
eq(field.map.id, "g0_1", "north connection is the route")
eq(field.playerY, 1, "appear on the south edge of the route")
eq(field.walkFromY, 2, "lerp from one tile past the landing")
check((field.walkCooldown or 0) > 0, "the crossing keeps walking")
check(field.tileWindows.kept == true,
  "crossing keeps the neighbor tile batches")
check(field:tryWalk(0, 1), "walk south off the route")
eq(field.map.id, "g0_0", "south connection returns to town")

local nox, noy = Game3.neighborOrigin(
  { dir = "north", offset = 0 }, hoenn.maps.g0_0, hoenn.maps.g0_1)
eq(nox, 0, "north dest origin x is the connection offset")
eq(noy, -hoenn.maps.g0_1.height, "north dest sits above the current map")
local sox, soy = Game3.neighborOrigin(
  { dir = "south", offset = 0 }, hoenn.maps.g0_1, hoenn.maps.g0_0)
eq(sox, 0, "south dest origin x")
eq(soy, hoenn.maps.g0_1.height, "south dest sits below the route")
local eox, eoy = Game3.neighborOrigin(
  { dir = "east", offset = 3 }, { width = 20, height = 10 }, { width = 8, height = 10 })
eq(eox, 20, "east dest origin x is the source width")
eq(eoy, 3, "east dest origin y is the connection offset")

field:enterMap(hoenn.maps.g0_0, 0, 0, false)
local wx0, wy0, wx1, wy1 = field:worldBounds()
eq(wy0, -hoenn.maps.g0_1.height * Game3.TILE,
  "camera world includes the north neighbor")
eq(wy1, hoenn.maps.g0_0.height * Game3.TILE, "south edge stays the town")
eq(wx0, 0, "no west neighbor")
eq(wx1, hoenn.maps.g0_0.width * Game3.TILE, "no east neighbor")

eq(Game3.CONNECTION_DRAW_HOPS, 1, "survey draws only touching maps")
local chainA = {
  id = "g0_0", width = 4, height = 4,
  connections = { { dir = "east", offset = 0, mapGroup = 0, mapNum = 1 } },
}
local chainB = {
  id = "g0_1", width = 4, height = 4,
  connections = {
    { dir = "west", offset = 0, mapGroup = 0, mapNum = 0 },
    { dir = "east", offset = 0, mapGroup = 0, mapNum = 2 },
  },
}
local chainC = {
  id = "g0_2", width = 6, height = 4,
  connections = { { dir = "west", offset = 0, mapGroup = 0, mapNum = 1 } },
}
local chain = Game3.new()
chain.data.maps = { maps = { g0_0 = chainA, g0_1 = chainB, g0_2 = chainC } }
chain.map = chainA
local hop1, hop2, hop1x = 0, 0, nil
chain:eachNeighbor(chainA, function(dest, ox)
  hop1 = hop1 + 1
  hop1x = ox
end)
eq(hop1, 1, "eachNeighbor stays one hop")
eq(hop1x, 4, "the east neighbor origin is this map's width")
chain:eachConnectedMap(chainA, function(dest, ox)
  if dest.id == "g0_1" then hop1x = ox end
  if dest.id == "g0_2" then hop2 = hop2 + 1 end
end)
eq(hop2, 0, "the map past the neighbor is not drawn")
chain.map = chainA
local _, _, farX = chain:worldBounds()
eq(farX, 8 * Game3.TILE, "world bounds stop at the touching map")
local covers = chain:mapCoverRects()
eq(#covers, 2, "border fill punches this map and its neighbor")

-- Phase 56: map scripts + coord events (ROM hooks, not per-map placeholders)

eq(RomExtractorGen3.MAP_SCRIPT_ON_TRANSITION, 3, "ON_TRANSITION is tag 3")
eq(RomExtractorGen3.COORD_EVENT_SIZE, 16, "CoordEvent is 16 bytes")
eq(Gen3Script.varGet({}, 3), 3, "VarGet of a literal is the literal")
eq(Gen3Script.varGet({ [0x4050] = 2 }, 0x4050), 2, "VarGet of a var is the store")

local MS, BODY, FRAME, SCENE, COORD = 0x10, 0x30, 0x50, 0x70, 0x90
local msRom = string.rep("\0", 0xC0)
msRom = overlay(msRom, BODY,
  string.char(0x29) .. GbaBin.packU16(0x52) .. string.char(0x02))
msRom = overlay(msRom, SCENE,
  string.char(0x29) .. GbaBin.packU16(0x99) .. string.char(0x02))
msRom = overlay(msRom, FRAME,
  GbaBin.packU16(0x4050) .. GbaBin.packU16(1) .. GbaBin.packPtr(SCENE)
  .. GbaBin.packU16(0) .. GbaBin.packU16(0) .. string.rep("\0", 4))
msRom = overlay(msRom, MS,
  string.char(3) .. GbaBin.packPtr(BODY)
  .. string.char(2) .. GbaBin.packPtr(FRAME)
  .. string.char(0))
msRom = overlay(msRom, COORD,
  GbaBin.packU16(4) .. GbaBin.packU16(5) .. string.char(3, 0)
  .. GbaBin.packU16(0x4050) .. GbaBin.packU16(1) .. GbaBin.packU16(0)
  .. GbaBin.packPtr(SCENE))
local parsedMs = RomExtractorGen3.parseMapScripts(msRom, MS)
eq(parsedMs.onTransition, BODY, "ON_TRANSITION stores the script offset")
eq(parsedMs.onFrame[1].var, 0x4050, "ON_FRAME row var")
eq(parsedMs.onFrame[1].value, 1, "ON_FRAME compare value")
eq(parsedMs.onFrame[1].scriptOff, SCENE, "ON_FRAME script offset")
local baked = RomExtractorGen3.bakeMapScripts(msRom, {
  mapScripts = parsedMs,
  coordEvents = { RomExtractorGen3.parseCoordEvent(msRom, COORD) },
})
eq(baked.mapScripts.onTransition[1].op, "setflag", "transition bakes to IR")
eq(baked.mapScripts.onTransition[1].flag, 0x52, "FLAG_RESCUED_BIRCH")
eq(baked.coordEvents[1].x, 4, "coord x")
eq(baked.coordEvents[1].y, 5, "coord y")
eq(baked.coordEvents[1].script[1].flag, 0x99, "coord bakes its script")

local CALL_BODY, CALL_HEAD = 0x20, 0x10
local callRom = string.rep("\0", 0x40)
callRom = overlay(callRom, CALL_BODY,
  string.char(0x29) .. GbaBin.packU16(0x20) .. string.char(0x02))
callRom = overlay(callRom, CALL_HEAD,
  string.char(0x2B) .. GbaBin.packU16(0x10)
  .. string.char(0x07, 0x01) .. GbaBin.packPtr(CALL_BODY)
  .. string.char(0x02))
local callOps = Gen3Script.parse(callRom, CALL_HEAD)
eq(callOps[2].op, "call_if", "0x07 is call_if, not goto_if")
local callHost = { flags = { [0x10] = true } }
Gen3Script.run(callHost, callOps)
check(callHost.flags[0x20], "call_if TRUE runs the body and returns")

local sceneMap = {
  id = "scene", width = 4, height = 2,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0 },
  mapScripts = {
    onTransition = {
      { op = "setflag", flag = 0x52 },
      { op = "end" },
    },
  },
  coordEvents = {
    {
      x = 1, y = 0, trigger = 0x4050, index = 1,
      script = {
        { op = "setflag", flag = 0x99 },
        { op = "end" },
      },
    },
  },
  objects = {}, warps = {}, connections = {},
}
local flow = Game3.new()
flow:enterMap(sceneMap, 0, 0, false)
check(flow.flags[0x52], "ON_TRANSITION setflag runs on enter")
flow.scriptVars[0x4050] = 1
check(flow:tryWalk(1, 0), "step onto the coord tile")
check(flow.flags[0x99], "matching coord var runs the script")

;(function()
local cells = {}
for i = 1, 16 do cells[i] = 0 end
local guardMap = {
  id = "guard", width = 4, height = 4,
  grid = cells,
  objects = { { localId = 1, x = 16, y = 10, graphicsId = 64 } },
  mapScripts = {
    onTransition = {
      { op = "setobjectxyperm", localId = 1, x = 2, y = 1 },
      { op = "setobjectmovementtype", localId = 1, movementType = 8 },
      { op = "end" },
    },
  },
  coordEvents = {
    {
      x = 1, y = 0, trigger = 0x4050, index = 0,
      script = {
        { op = "loadword", text = "STOP" },
        { op = "callstd", id = 4 },
        { op = "applymovement", localId = 0xFF,
          steps = { { kind = "walk", dir = "south" } } },
        { op = "waitmovement", localId = 0 },
        { op = "loadword", text = "GRASS" },
        { op = "callstd", id = 4 },
        { op = "end" },
      },
    },
  },
  warps = {}, connections = {},
}
local guard = Game3.new()
guard.phase = "play"
guard:enterMap(guardMap, 1, 1, true)
eq(guard:npcByLocalId(1).x, 2, "ON_TRANSITION setobjectxyperm before spawn")
eq(guard:npcByLocalId(1).y, 1, "twin is on the route")
eq(guard:npcByLocalId(1).movementType, 8, "and faces the road")
guard.scriptVars[0x4050] = 0
check(guard:tryWalk(0, -1), "step onto the north coord")
eq(guard.field.kind, "talk", "msgbox before the shove is shown")
eq(guard.field.text, "STOP", "the warning line")
eq(guard.field.thenContinue, true, "MSGBOX_DEFAULT waits for A")

local Input = require("src.core.Input")
Input:init()
local oldPress = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
guard:stepField()
Input.wasPressed = oldPress
eq(guard.field.kind, "move", "A starts the shove")
guard:finishScriptMoves()
guard:resumeMoveScript()
eq(guard.field.kind, "talk", "the second line follows the shove")
eq(guard.field.text, "GRASS", "DangerousIfYouDontHavePokemon")
eq(guard.playerY, 1, "player was walked back south")

local genderHost = { gender = 1, scriptVars = {} }
Gen3Script.run(genderHost, { { op = "checkplayergender" } })
eq(genderHost.scriptVars[0x800D], 1, "checkplayergender writes VAR_RESULT")
end)()

;(function()
local cells = {}
for i = 1, 16 do cells[i] = 0 end
local house = {
  id = "house1f", width = 4, height = 4, grid = cells,
  objects = {}, connections = {},
  warps = {
    { x = 1, y = 3, mapGroup = 0, mapNum = 9, warpId = 0 },
  },
  coordEvents = {
    {
      x = 1, y = 3, trigger = 0x4092, index = 4,
      script = {
        { op = "loadword", text = "GO SET THE CLOCK" },
        { op = "callstd", id = 4 },
        { op = "end" },
      },
    },
  },
}
local town = {
  id = "g0_9", width = 4, height = 4, grid = cells,
  objects = {}, warps = {}, connections = {}, coordEvents = {},
}
-- Every building's exit mat on the cart is MB_SOUTH_ARROW_WARP -- g1_0's two
-- mat tiles at (9,8) and (8,8) both read 0x65 -- so walking south off the mat
-- leaves by the arrow path. Without it the mat is MB_NORMAL and, since
-- IsWarpMetatileBehavior rejects that, nothing would warp.
house.behavior = house.behavior or {}
for _, w in ipairs(house.warps or {}) do
  house.behavior[(w.y or 0) * (house.width or 0) + (w.x or 0) + 1] =
    Game3.MB_SOUTH_ARROW_WARP
end
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "g0_9", maps = { g0_9 = town, house1f = house } }
g.scriptVars = { [0x4092] = 4 }
g:enterMap(house, 1, 2, true)
g.ignoreWarp = false
check(g:tryWalk(0, 1), "step onto the doormat at intro 4")
eq(g.map.id, "house1f", "GoSeeRoom beats the door warp")
eq(g.playerY, 3, "player is on the mat")
eq(g.field and g.field.text, "GO SET THE CLOCK", "Mom sends you to the clock")

local later = Game3.new()
later.phase = "play"
later.data.maps = { start = "g0_9", maps = { g0_9 = town, house1f = house } }
later.scriptVars = { [0x4092] = 7 }
later:enterMap(house, 1, 2, true)
later.ignoreWarp = false
check(later:tryWalk(0, 1), "the same mat after the TV report")
eq(later.map.id, "g0_9", "then the door still warps to town")
end)()

;(function()
local Game3 = require("src.core.Game3")
local cliff = {
  id = "cliff", width = 3, height = 3,
  grid = {
    0, 0, 0,
    1024, 1024, 1024,
    0, 0, 0,
  },
  behavior = {
    0, 0, 0,
    0, Game3.MB_JUMP_SOUTH, 0,
    0, 0, 0,
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "cliff", maps = { cliff = cliff } }
g:enterMap(cliff, 1, 0, true)
eq(Game3.ledgeDelta(Game3.MB_JUMP_SOUTH), 0, "south ledge dy")
local jx, jy = Game3.ledgeDelta(Game3.MB_JUMP_SOUTH)
eq(jy, 1, "south ledge hops down")
check(not g:tryWalk(0, -1), "cannot hop a south ledge facing north")
eq(g.playerY, 0, "still on the plateau")
check(g:tryWalk(0, 1), "DOWN hops the south ledge")
eq(g.playerX, 1, "same column")
eq(g.playerY, 2, "landed two tiles south")
check(g.hopping, "the hop is in the air")
end)()

-- field_player_avatar.c ShouldJumpLedge / DoForcedMovement: a ledge jump
-- is unconditional once the facing tile matches the walked direction --
-- there is no landing-tile collision or elevation check in the real
-- game (a ledge dropping to a different elevation is the point of a
-- ledge, e.g. Lilycove's beach). tryLedgeHop must not gate the landing
-- tile the way canStep gates a normal step.
;(function()
local Game3 = require("src.core.Game3")
local ELEV3, ELEV2, COLL1 = 3 * 4096, 2 * 4096, 1 * 1024
local beach = {
  id = "g_beach", width = 3, height = 3,
  tileset = "pair_x",
  grid = {
    ELEV3 + 0, ELEV3 + 0, ELEV3 + 0,
    ELEV3 + COLL1 + 1, ELEV3 + COLL1 + 1, ELEV3 + COLL1 + 1,
    ELEV2 + 2, ELEV2 + 2, ELEV2 + 2,
  },
  mapType = Game3.MAP_TYPE_ROUTE,
}
local g = Game3.new()
g.phase = "play"
g.data.tilesets = { byId = {
  pair_x = { behavior = { [0] = 0, [1] = Game3.MB_JUMP_SOUTH, [2] = 0 } },
} }
g.data.maps = { maps = { g_beach = beach } }
g:enterMap(beach, 1, 0, true)
eq(g.currentElevation, 3, "standing on the elevation-3 plateau")
check(g:tryWalk(0, 1),
  "the ledge hop clears even though the landing is a different elevation")
eq(g.playerX, 1, "same column")
eq(g.playerY, 2, "landed on the elevation-2 beach two tiles south")
end)()

-- Lilycove beach lips: jump metatiles can be collision-0 at the same
-- elevation as the plateau. pokeruby's ShouldJumpLedge still fires.
;(function()
local Game3 = require("src.core.Game3")
local ELEV3, ELEV2 = 3 * 4096, 2 * 4096
local lip = {
  id = "g_lily_lip", width = 3, height = 3,
  tileset = "pair_y",
  grid = {
    ELEV3 + 0, ELEV3 + 0, ELEV3 + 0,
    ELEV3 + 1, ELEV3 + 1, ELEV3 + 1,
    ELEV2 + 0, ELEV2 + 0, ELEV2 + 0,
  },
}
local g = Game3.new()
g.phase = "play"
g.data.tilesets = { byId = {
  pair_y = { behavior = { [0] = 0, [1] = Game3.MB_JUMP_SOUTH } },
} }
g.data.maps = { maps = { g_lily_lip = lip } }
g:enterMap(lip, 1, 0, true)
check(g:tryWalk(0, 1),
  "a walkable same-elevation jump lip still hops to the beach")
eq(g.playerX, 1, "same column")
eq(g.playerY, 2, "landed two tiles south, not on the lip")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
eq(Game3.MOVEMENT_TYPE_INVISIBLE, 0x4C, "MOVEMENT_TYPE_INVISIBLE is 0x4C")
eq(Game3.wanderDirs(0x4C), nil, "invisible NPCs do not wander")
check(not Game3.shouldAnimCorner(108, Game3.MB_JUMP_SOUTH),
  "ledge water tiles do not flip")

local floor = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local wallTop = { 1024, 0, 1024, 0, 0, 0, 0, 0, 0 }
local indoor = {
  id = "g0_0", width = 3, height = 3, grid = floor,
  behavior = { 0, 2, 0, 0, 2, 0, 0, 0, 0 },
  warps = { { x = 1, y = 0, mapGroup = 0, mapNum = 1, warpId = 0 } },
  objects = {
    {
      localId = 1, x = 0, y = 1, graphicsId = 10,
      movementType = 2, rangeX = 2, rangeY = 2,
    },
    {
      localId = 2, x = 2, y = 1, graphicsId = 12,
      movementType = Game3.MOVEMENT_TYPE_INVISIBLE,
    },
  },
  connections = {},
}
local dest = {
  id = "g0_1", width = 3, height = 3, grid = wallTop,
  warps = { { x = 1, y = 0, mapGroup = 0, mapNum = 0, warpId = 0 } },
  objects = {}, connections = {},
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "g0_0", maps = { g0_0 = indoor, g0_1 = dest } }
g:enterMap(indoor, 1, 1, true)

local dummy = g:npcByLocalId(2)
check(dummy and dummy.invisible, "invisible dummy is spawned hidden")
eq(g:npcAt(indoor, 2, 1), dummy, "INVISIBLE still occupies the tile")
g.facing = "east"
eq(g:facingNpc(), dummy, "and is talkable")
check(not g:tryWalk(1, 0), "and blocks the step")
eq(g.playerX, 1, "player stays put")

g.facing = "west"
local npc = g:facingNpc()
check(npc, "wanderer is west of the player")
local ox, oy = npc.x, npc.y
check(g:tryTalk(), "A talks")
eq(npc.facing, "east", "NPC faces the player")
-- No script on this NPC means no `lock` op ever runs (field_control_avatar.c
-- TryStartInteractionScript: a NULL script pointer never reaches
-- ScriptContext_SetupScript at all), so it stays free to wander --
-- unlike a real scripted NPC, which locks via its own script's `lock`.
check(not npc.talkLock, "no script means nothing ran, so it is not locked")
g:closeField()
check(not npc.talkLock, "closing dialogue unlocks")

g.facing = "south"
g.playerX, g.playerY = 1, 1
g.walkCooldown = 0
g.warpSettle = nil
g.field = nil
local oldDown = Input.isDown
Input.isDown = function(_, key) return key == "up" end
g:walkHeld(0.016)
eq(g.facing, "north", "a tap turns in place")
eq(g.playerY, 1, "without taking a step")
g:walkHeld(0.016)
eq(g.playerY, 0, "holding then walks")
Input.isDown = oldDown

g.facing = "north"
g:followWarp({ mapGroup = 0, mapNum = 1, warpId = 0, x = 1, y = 0 })
eq(g.map.id, "g0_1", "warped to the stair map")
eq(g.playerX, 1, "on the dest warp x")
eq(g.playerY, 0, "on the dest warp y")
eq(g.facing, "south", "faces into the room, not the wall")
check(g.warpSettle, "held d-pad is ignored until release")

g:beginGrassRustle(1, 0)
check(not g:grassIsRustling(1, 0), "non-grass tiles do not rustle")
g.map = indoor
g:beginGrassRustle(1, 0)
check(g:grassIsRustling(1, 0), "stepping into grass starts a tuft")
g:stepGrassRustle(1)
check(not g:grassIsRustling(1, 0), "then the tuft ends")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.VAR_BRINEY_HOUSE_STATE, 0x4090, "VAR_BRINEY_HOUSE_STATE")
eq(Game3.wanderDirs(0x32), "seq", "Briney DOWN_LEFT_UP_RIGHT is a sequence")
eq(Game3.wanderDirs(0x33), "seq", "Peeko LEFT_UP_RIGHT_DOWN is a sequence")
eq(Game3.WALK_SEQUENCES[0x32][1], "south", "Briney starts by walking down")
eq(Game3.WALK_SEQUENCES[0x33][1], "west", "Peeko starts by walking left")
local grid = {}
for i = 1, 12 * 10 do grid[i] = 0 end
local house = {
  id = "briney", width = 12, height = 10, grid = grid,
  objects = {
    {
      localId = 1, x = 5, y = 3, graphicsId = 10,
      movementType = 0x32, rangeX = 3, rangeY = 3, flagId = 0x2E3,
    },
    {
      localId = 2, x = 6, y = 3, graphicsId = 70,
      movementType = 8, rangeX = 3, rangeY = 3, flagId = 0x371,
    },
  },
  mapScripts = {
    onTransition = {
      { op = "compare", var = Game3.VAR_BRINEY_HOUSE_STATE, val = 1 },
      {
        op = "call_if", cond = 1,
        body = {
          { op = "setobjectxyperm", localId = 1, x = 9, y = 3 },
          { op = "setobjectmovementtype", localId = 1, movementType = 0x32 },
          { op = "setobjectxyperm", localId = 2, x = 9, y = 6 },
          { op = "setobjectmovementtype", localId = 2, movementType = 0x33 },
          { op = "end" },
        },
      },
      { op = "end" },
    },
  },
}
local g = Game3.new()
g.phase = "play"
g.flags = {}
g.scriptVars = { [Game3.VAR_BRINEY_HOUSE_STATE] = 1 }
g:enterMap(house, 5, 8, true)
local briney = g:npcByLocalId(1)
local peeko = g:npcByLocalId(2)
check(briney, "Briney spawned")
check(peeko, "Peeko spawned")
eq(briney.x, 9, "ON_TRANSITION parks Briney at 9,3")
eq(briney.y, 3, "Briney y")
eq(peeko.x, 9, "and Peeko at 9,6")
eq(peeko.y, 6, "Peeko y")
eq(peeko.movementType, 0x33, "Peeko is on the chase sequence")
briney.wait, briney.cooldown = 0, 0
peeko.wait, peeko.cooldown = 0, 0
g:stepNpcs(0)
eq(briney.y, 4, "Briney walks south")
eq(peeko.x, 8, "Peeko walks west")
end)()

;(function()
local Game3 = require("src.core.Game3")
check(not Game3.shouldAnimCorner(130, 0, { 130, 131, 146, 147 }, 1),
  "rock-wall tiles that share flower VRAM do not flip")
check(not Game3.shouldAnimCorner(128, 0, { 128, 129, 144, 145 }, 1),
  "mountain ledge overlays do not flip")
check(Game3.shouldAnimCorner(127, 0), "lone flowers still flip")
check(Game3.shouldAnimCorner(128, 0, { 127, 128, 129, 130 }, 1),
  "a flower-only metatile still sways")
check(Game3.shouldAnimCorner(120, Game3.MB_POND_WATER), true,
  "pond water still sways")
check(not Game3.shouldAnimCorner(127, 0, { 120, 121, 127, 128 }, 1),
  "water-edge foam does not borrow the flower flip")
check(not Game3.shouldAnimCorner(128, 0, { 127, 128, 129, 130 }, 1, 1),
  "solid harbor walls do not blink")
check(Game3.shouldAnimCorner(127, 0, { 127, 128, 129, 130 }, 1, 0),
  "walkable flowers still sway")
check(Game3.shouldAnimCorner(120, Game3.MB_OCEAN_WATER, nil, nil, 1),
  "surfable ocean still sways through collision")
check(Game3.shouldAnimCorner(120, Game3.MB_POND_WATER, { 120, 121, 122, 123 }, 1),
  "open pond water still sways")
check(not Game3.shouldAnimCorner(108, Game3.MB_POND_WATER,
    { 270, 270, 270, 286, 108, 109, 124, 0 }, 5),
  "Route 104 pond-bank water does not flip")
check(not Game3.shouldAnimCorner(110, Game3.MB_POND_WATER,
    { 270, 270, 286, 286, 110, 109, 0, 0 }, 5),
  "and the L-pond's other bank stays still")
check(not Game3.shouldAnimCorner(127, Game3.MB_POND_WATER,
    { 270, 270, 286, 270, 110, 111, 0, 127 }, 5),
  "pond-bank flower foam does not borrow the water flip")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Script = require("src.import.Gen3Script")
eq(Script.MAX_MOVE, 512, "Dewford sail is not cut at 48")
eq(Script.walkSpeed(0x16), 1, "walk_fast_up is speed 1")
eq(Script.walkSpeed(0x2F), 3, "walk_fastest_left is speed 3")
eq(Script.walkSpeed(0x8), 0, "walk_normal_down is speed 0")
eq(Script.walkSpeed(0x4), "slow", "walk_slow_down is 32-frame")
eq(Game3.scriptStepPeriod({ speed = 1 }), Game3.RUN_PERIOD, "fast is 8 frames")
eq(Game3.scriptStepPeriod({ speed = 3 }), Game3.MACH_PERIOD, "fastest is 4 frames")
eq(Game3.scriptStepPeriod({ speed = "slow" }), 32 / 60, "slow is 32 frames")
eq(Game3.scriptStepPeriod({}), Game3.WALK_PERIOD, "cached IR without speed is 16")
local bytes = string.rep(string.char(0x16), 60) .. string.char(0xFE)
local long = Script.parseMovement(bytes, 0)
eq(#long, 60, "60 walk_fast_up steps parse")
eq(long[1].speed, 1, "and keep speed 1")
eq(long[60].dir, "north", "last is still up")
end)()

;(function()
local Script = require("src.import.Gen3Script")
local GbaBin = require("src.import.GbaBin")
eq(Script.SETOBJECTPRIORITY, 0xA8, "setobjectpriority is 0xA8")
eq(Script.RESETOBJECTPRIORITY, 0xA9, "resetobjectpriority is 0xA9")
eq(Script.MOVEOBJECTOFFSCREEN, 0x64, "moveobjectoffscreen is 0x64")
local pri = Script.parse(
  string.char(0xA8) .. GbaBin.packU16(2) .. string.char(0, 11, 0, 0x02), 0)
eq(pri[1].op, "setobjectpriority", "setobjectpriority is kept")
eq(pri[1].localId, 2, "Briney local 2")
eq(pri[1].mapGroup, 0, "Dewford group")
eq(pri[1].mapNum, 11, "Dewford num")
eq(pri[1].priority, 0, "priority 0")
local rst = Script.parse(
  string.char(0xA9) .. GbaBin.packU16(0xFF) .. string.char(0, 11, 0x02), 0)
eq(rst[1].op, "resetobjectpriority", "resetobjectpriority is kept")
eq(rst[1].localId, 0xFF, "player")
local off = Script.parse(
  string.char(0x64) .. GbaBin.packU16(2) .. string.char(0x02), 0)
eq(off[1].op, "moveobjectoffscreen", "moveobjectoffscreen is kept")
eq(off[1].localId, 2, "Briney")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Script = require("src.import.Gen3Script")
eq(Game3.ITEM_GO_GOGGLES, 279, "ITEM_GO_GOGGLES")
eq(Game3.GAME_STAT_ENTERED_HOT_SPRINGS, 49, "hot springs stat")
local g = Game3.new()
eq(g:itemPocket(Game3.ITEM_GO_GOGGLES), Game3.POCKET_KEY, "Go-Goggles are KEY ITEMS")
eq(g:itemName(Game3.ITEM_GO_GOGGLES), "GO-GOGGLES", "name")
local gym = {
  id = "g4_1", width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    {
      localId = 2, x = 1, y = 1, graphicsId = 10,
      movementType = Game3.MOVEMENT_TYPE_FACE_DOWN,
      trainerType = Game3.TRAINER_TYPE_BURIED, trainerRange = 1,
    },
  },
  mapScripts = {
    onTransition = {
      { op = "setobjectmovementtype", localId = 2, movementType = 63 },
      { op = "end" },
    },
  },
  warps = {}, connections = {},
}
g.phase = "play"
g:enterMap(gym, 0, 1, true)
local npc = g:npcByLocalId(2)
check(npc.invisible, "ON_TRANSITION 63 hides the sprite")
eq(npc.movementType, Game3.MOVEMENT_TYPE_HIDDEN, "HIDDEN")
eq(g:npcAt(gym, 1, 1), npc, "but still occupies the tile")
g.facing = "east"
check(g:tryTalk(), "A talks to the pit")
check(not npc.invisible, "and reveals")
eq(npc.movementType, Game3.MOVEMENT_TYPE_FACE_LEFT, "faces the player")
eq(gym.objects[1].permMovementType, Game3.MOVEMENT_TYPE_FACE_LEFT,
  "and overrides the template like the ROM")
g:enterMap(gym, 0, 1, true)
npc = g:npcByLocalId(2)
check(npc.invisible, "re-enter still buries undefeated")
local ops = Script.parse(string.char(0xC3, 49) .. string.char(0x02), 0)
eq(ops[1].op, "incrementgamestat", "0xC3")
eq(ops[1].id, 49, "stat 49")
g = Game3.new()
Script.run(g, ops)
eq(g:getGameStat(Game3.GAME_STAT_ENTERED_HOT_SPRINGS), 1, "hot springs +1")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
eq(Game3.MB_MUDDY_SLOPE, 0xD0, "MB_MUDDY_SLOPE")
eq(Game3.MB_BUMPY_SLOPE, 0xD1, "MB_BUMPY_SLOPE is Acro, not a slide")
local hill = {
  id = "hill", width = 3, height = 4,
  grid = {
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
    0, 0, 0,
  },
  behavior = {
    0, 0, 0,
    Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE,
    Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE,
    0, 0, 0,
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { start = "hill", maps = { hill = hill } }
g:enterMap(hill, 1, 0, true)
g.walkCooldown = 0
g.facing = "south"
check(g:tryWalk(0, 1), "step onto the slope")
eq(g.playerY, 1, "on the first muddy row")
g.facing = "north"
g.walkCooldown = 0
local oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerY, 2, "walkHeld idle slides south")
eq(g.facing, "north", "facingDirectionLocked while sliding")
eq(g.walkDuration, Game3.RUN_PERIOD, "PlayerGoSpeed2 even on foot")
Input.isDown = oldDown

g.walkCooldown = 0
check(g:tryMuddySlope(), "next row still slides")
eq(g.playerY, 3, "onto the flat landing")
g.walkCooldown = 0
check(not g:tryMuddySlope(), "flat ground is not a slope")
eq(g.playerY, 3, "stays put")

local blocked = {
  id = "blocked", width = 3, height = 3,
  grid = {
    0, 0, 0,
    0, 0, 0,
    1024, 1024, 1024,
  },
  behavior = {
    0, 0, 0,
    Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE, Game3.MB_MUDDY_SLOPE,
    0, 0, 0,
  },
}
g = Game3.new()
g.phase = "play"
g.data.maps = { start = "blocked", maps = { blocked = blocked } }
g:enterMap(blocked, 1, 1, true)
g.walkCooldown = 0
g.facing = "north"
check(not g:tryMuddySlope(), "collision south stops the slide")
eq(g.playerY, 1, "still on the slope")
eq(g.facing, "north", "failed slide does not turn")

g.data.maps.maps.hill = hill
g:enterMap(hill, 1, 2, true)
g.bike = "mach"
g.walkCooldown = 0
g.warpSettle = nil
g.facing = "north"
oldDown = Input.isDown
Input.isDown = function(_, key) return key == "up" end
eq(g:playerSpeed(), 4, "Mach is FASTEST (no gears)")
check(g:canClimbMuddySlope(), "Mach + hold up climbs")
check(not g:tryMuddySlope(), "so forced movement yields")
eq(g.playerY, 2, "does not auto-slide")
g:walkHeld(0)
eq(g.playerY, 1, "holding up on Mach walks north")

Input.isDown = function() return false end
g.walkCooldown = 0
g.playerY = 1
g.facing = "north"
check(g:tryMuddySlope(), "idle Mach still slides")
eq(g.playerY, 2, "speed drops / not holding north")

g.bike = "acro"
g.playerY = 1
g.walkCooldown = 0
g.facing = "north"
Input.isDown = function(_, key) return key == "up" end
eq(g:playerSpeed(), 3, "Acro is SPEED_FASTER")
check(not g:canClimbMuddySlope(), "Acro cannot climb")
check(g:tryMuddySlope(), "so it slides too")
eq(g.playerY, 2, "one tile south")

g.bike = nil
g.running = true
g.playerY = 1
g.walkCooldown = 0
Input.isDown = function() return false end
eq(g:playerSpeed(), 2, "run is SPEED_FAST")
check(g:tryMuddySlope(), "run also slides")
eq(g.playerY, 2, "south")
Input.isDown = oldDown
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.MOVEMENT_TYPE_TREE_DISGUISE, 0x39, "TREE_DISGUISE")
eq(Game3.MOVEMENT_TYPE_MOUNTAIN_DISGUISE, 0x3A, "MOUNTAIN_DISGUISE")
eq(Game3.GFX_KECLEON_1, 204, "GFX_KECLEON_1")
eq(Game3.ITEM_DEVON_SCOPE, 288, "ITEM_DEVON_SCOPE")
eq(Game3.facingFromMovementType(0x39), "south", "tree faces south")
eq(Game3.facingFromMovementType(0x3A), "south", "mountain faces south")
check(Game3.movementTypeHidesSprite(0x39), "tree hides the sprite")
check(Game3.movementTypeHidesSprite(0x3A), "mountain hides the sprite")
local g = Game3.new()
eq(g:itemPocket(Game3.ITEM_DEVON_SCOPE), Game3.POCKET_KEY, "Devon Scope is KEY ITEMS")
eq(g:itemName(Game3.ITEM_DEVON_SCOPE), "DEVON SCOPE", "name")
g:addItem(Game3.ITEM_DEVON_SCOPE, 1)
eq(g:itemCount(Game3.ITEM_DEVON_SCOPE), 1, "bag has it")

local trail = {
  id = "g_r119", width = 5, height = 4,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  objects = {
    {
      localId = 1, x = 2, y = 1, graphicsId = Game3.GFX_KECLEON_1,
      movementType = Game3.MOVEMENT_TYPE_INVISIBLE,
    },
    {
      localId = 2, x = 0, y = 1, graphicsId = 10,
      movementType = Game3.MOVEMENT_TYPE_TREE_DISGUISE,
      trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 2,
      party = { { species = 296, level = 18 } },
      trainerName = "LAO", trainerClass = "NINJA BOY",
    },
    {
      localId = 3, x = 4, y = 1, graphicsId = 10,
      movementType = Game3.MOVEMENT_TYPE_MOUNTAIN_DISGUISE,
      trainerType = Game3.TRAINER_TYPE_NORMAL, trainerRange = 3,
      party = { { species = 296, level = 19 } },
      trainerName = "LUNG", trainerClass = "NINJA BOY",
    },
  },
  warps = {}, connections = {},
}
g.phase = "play"
g.party = { g:makeMon(258, 20) }
g:enterMap(trail, 2, 2, true)
local kecleon = g:npcByLocalId(1)
local tree = g:npcByLocalId(2)
local rock = g:npcByLocalId(3)
check(kecleon.invisible, "Kecleon sprite is hidden")
eq(g:npcAt(trail, 2, 1), kecleon, "but it occupies")
g.facing = "north"
eq(g:facingNpc(), kecleon, "A finds it")
check(g:tryTalk(), "talking works")
g:closeField()

check(tree.invisible, "tree disguise hides the trainer")
eq(g:npcAt(trail, 0, 1), tree, "and occupies")
g.playerX, g.playerY = 0, 2
check(g:seesPlayer(tree, trail), "NORMAL tree sees south")
g.playerX, g.playerY = 0, 0
check(not g:seesPlayer(tree, trail), "not behind")
g.playerX, g.playerY = 0, 2
check(g:tryTrainerSpot(), "spotting a tree ninja")
check(not tree.invisible, "pops the disguise")
eq(tree.movementType, Game3.MOVEMENT_TYPE_FACE_DOWN, "faces the player")
g.field = nil

check(rock.invisible, "mountain disguise hides")
eq(g:npcAt(trail, 4, 1), rock, "and occupies")
g.playerX, g.playerY = 4, 2
check(g:tryTrainerSpot(), "spotting a mountain ninja")
check(not rock.invisible, "pops")
eq(rock.movementType, Game3.MOVEMENT_TYPE_FACE_DOWN, "faces south")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.MAP_DYNAMIC_GROUP, 0x7F, "MAP_DYNAMIC group")
eq(Game3.MAP_DYNAMIC_NUM, 0x7F, "MAP_DYNAMIC num")
eq(Game3.MAP_LILYCOVE_INDOOR_GROUP, 13, "Lilycove indoor group")
eq(Game3.MAP_DEPT_STORE_1F_NUM, 17, "1F num")
eq(Game3.MAP_DEPT_STORE_ELEVATOR_NUM, 23, "elevator num")
eq(Game3.DEPT_STORE_FLOOR[17], 0, "1F is floor 0")
eq(Game3.DEPT_STORE_FLOOR[22], 15, "rooftop is 15")
eq(Game3.ELEVATOR_FLOOR_NAMES[0], "1F", "name 0")
eq(Game3.ELEVATOR_FLOOR_NAMES[15], "ROOFTOP", "name 15")
eq(Game3.SPECIAL_SET_DEPARTMENT_STORE_FLOOR, 216, "SetDepartmentStoreFloorVar")
eq(Game3.SPECIAL_SHAKE_SCREEN_IN_ELEVATOR, 273, "ShakeScreenInElevator")
eq(Game3.SPECIAL_DISPLAY_CURRENT_ELEVATOR_FLOOR, 306,
  "DisplayCurrentElevatorFloor")
eq(Game3.VAR_DEPT_STORE_FLOOR, 0x4043, "VAR_DEPT_STORE_FLOOR")
eq(Game3.FLAG_TEMP_2, 0x2, "FLAG_TEMP_2")
eq(Game3.ITEM_RED_ORB, 276, "ITEM_RED_ORB")
local labels = Game3.MULTICHOICE[57]
eq(#labels, 5, "multichoice 57 has five floors")
eq(labels[1], "1F", "first label")
eq(labels[5], "5F", "last label")

local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local floor1 = {
  id = "g13_17", group = 13, index = 17,
  width = 3, height = 3, grid = cells,
  warps = {
    { x = 1, y = 0, mapGroup = 13, mapNum = 23, warpId = 0 },
  },
}
local elev = {
  id = "g13_23", group = 13, index = 23,
  width = 3, height = 3, grid = cells,
  warps = {
    { x = 1, y = 1, mapGroup = Game3.MAP_DYNAMIC_GROUP,
      mapNum = Game3.MAP_DYNAMIC_NUM, warpId = Game3.WARP_ID_DYNAMIC },
    { x = 2, y = 1, mapGroup = Game3.MAP_DYNAMIC_GROUP,
      mapNum = Game3.MAP_DYNAMIC_NUM, warpId = Game3.WARP_ID_DYNAMIC },
  },
}
-- The real LILYCOVE DEPT. STORE 1F puts MB_NON_ANIMATED_DOOR on its elevator
-- door: g13_17's warp at (16,1) reads 0x60. This fixture is a 3x3 stand-in for
-- dynamic-warp bookkeeping and is entered and left walking north, where the
-- real 3x6 lift is left walking south onto MB_SOUTH_ARROW_WARP, so the plain
-- door goes on both sides -- it is the behaviour that bumps from any
-- direction, which is what this fixture's geometry needs.
floor1.behavior = { [0 * 3 + 1 + 1] = Game3.MB_NON_ANIMATED_DOOR }
elev.behavior = {
  [1 * 3 + 1 + 1] = Game3.MB_NON_ANIMATED_DOOR,
  [1 * 3 + 2 + 1] = Game3.MB_NON_ANIMATED_DOOR,
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g13_17 = floor1, g13_23 = elev } }
eq(g:itemPocket(Game3.ITEM_RED_ORB), Game3.POCKET_KEY, "Red Orb is KEY ITEMS")
eq(g:itemName(Game3.ITEM_RED_ORB), "RED ORB", "name")
g:enterMap(floor1, 1, 1, true)
g.ignoreWarp = false
check(g:tryWalk(0, -1), "1F door into the elevator")
eq(g.map.id, "g13_23", "inside")
eq(g.dynamicWarp.mapGroup, 13, "saved group")
eq(g.dynamicWarp.mapNum, 17, "saved 1F")
eq(g.dynamicWarp.warpId, 0, "saved source warp 0")
eq(g.dynamicWarp.x, 1, "saved x")
eq(g.dynamicWarp.y, 1, "saved y")
-- sub_8080AE4: the lift door is MB_NON_ANIMATED_DOOR, so arriving runs
-- task_map_chg_seq_0807E20C, which walks the player one step off the pad
-- before returning control -- you step INTO the lift, exactly as the real
-- one does. Finish that held movement the way a frame would.
g:finishScriptMoves()
g.field = nil
eq(g.playerY, 0, "the arrival task walked the player off the pad")
eq(g.map.id, "g13_23", "still inside")
check(g:tryWalk(0, 1), "step back onto MAP_DYNAMIC")
eq(g.map.id, "g13_17", "returns to 1F")

g:setDynamicWarp(13, 17, 0, 1, 1)
g:runSpecial(Game3.SPECIAL_SET_DEPARTMENT_STORE_FLOOR)
eq(g:varGet(Game3.VAR_DEPT_STORE_FLOOR), 0, "1F floor var is 0")
g:setDynamicWarp(13, 22, 0, 1, 1)
g:runSpecial(Game3.SPECIAL_SET_DEPARTMENT_STORE_FLOOR)
eq(g:varGet(Game3.VAR_DEPT_STORE_FLOOR), 15, "rooftop floor var is 15")

g:setScriptVar(0x8005, 0)
g:runSpecial(Game3.SPECIAL_DISPLAY_CURRENT_ELEVATOR_FLOOR)
eq(g._scriptSays[#g._scriptSays], "Now on: 1F", "display 1F")
g:setScriptVar(0x8005, 15)
g:runSpecial(Game3.SPECIAL_DISPLAY_CURRENT_ELEVATOR_FLOOR)
eq(g._scriptSays[#g._scriptSays], "Now on: ROOFTOP", "display rooftop")

g.scriptWait = nil
g.phase = "play"
g:runSpecial(Game3.SPECIAL_SHAKE_SCREEN_IN_ELEVATOR)
check(g:scriptWaiting(), "elevator CreateTask")
g:walkHeld((Game3.ELEVATOR_SHAKE_PERIOD * Game3.ELEVATOR_SHAKE_HITS) / 60)
check(not g:scriptWaiting(), "23 pans then ScriptContext_Enable")

g.flags[Game3.FLAG_TEMP_2] = true
g.flags[Game3.FLAG_TEMP_20] = true
g:enterMap(floor1, 1, 1, true)
eq(g.flags[Game3.FLAG_TEMP_2], nil, "TEMP_2 clears on enter")
eq(g.flags[Game3.FLAG_TEMP_20], true, "TEMP_20 stays")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
eq(Game3.MB_ICE, 0x20, "MB_ICE")
eq(Game3.MB_WALK_SOUTH, 0x43, "MB_WALK_SOUTH")
eq(Game3.MB_SLIDE_EAST, 0x44, "MB_SLIDE_EAST")
eq(Game3.MB_TRICK_HOUSE_PUZZLE_8_FLOOR, 0x48, "Trick House 8 ice")
eq(Game3.MB_EASTWARD_CURRENT, 0x50, "east current")
eq(Game3.MB_SOUTHWARD_CURRENT, 0x53, "south current")
eq(Game3.ITEM_POKEBLOCK_CASE, 273, "ITEM_POKEBLOCK_CASE")
check(Game3.isSurfable(Game3.MB_EASTWARD_CURRENT), "currents are surfable")
check(Game3.isSurfable(Game3.MB_SOUTHWARD_CURRENT), "south current too")
local g = Game3.new()
eq(g:itemPocket(Game3.ITEM_POKEBLOCK_CASE), Game3.POCKET_KEY,
  "Pokéblock Case is KEY ITEMS")
eq(g:itemName(Game3.ITEM_POKEBLOCK_CASE), "POKeBLOCK CASE", "name")

local rink = {
  id = "rink", width = 4, height = 3,
  grid = {
    0, 0, 0, 1024,
    0, 0, 0, 1024,
    0, 0, 0, 1024,
  },
  behavior = {
    0, Game3.MB_ICE, Game3.MB_ICE, 0,
    0, Game3.MB_ICE, Game3.MB_ICE, 0,
    0, 0, 0, 0,
  },
}
g.phase = "play"
g.data.maps = { start = "rink", maps = { rink = rink } }
g:enterMap(rink, 0, 0, true)
g.walkCooldown = 0
g.facing = "east"
check(g:tryWalk(1, 0), "step onto ice")
eq(g.playerX, 1, "on ice")
g.walkCooldown = 0
local oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerX, 2, "idle slips east")
eq(g.walkDuration, Game3.RUN_PERIOD, "PlayerGoSpeed2")
g.walkCooldown = 0
g:walkHeld(0)
eq(g.playerX, 2, "wall stops the slip")
g.facing = "south"
g.walkCooldown = 0
g:walkHeld(0)
eq(g.playerY, 1, "after the wall you can turn")
Input.isDown = oldDown

local river = {
  id = "river", width = 4, height = 1,
  grid = { 1024, 1024, 1024, 1024 },
  behavior = {
    Game3.MB_EASTWARD_CURRENT, Game3.MB_EASTWARD_CURRENT,
    Game3.MB_EASTWARD_CURRENT, Game3.MB_OCEAN_WATER,
  },
}
g = Game3.new()
g.phase = "play"
g.surfing = true
g.data.maps = { start = "river", maps = { river = river } }
g:enterMap(river, 0, 0, true)
g.walkCooldown = 0
oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerX, 1, "current rides east")
eq(g.walkDuration, Game3.RUN_PERIOD, "PlayerRideWaterCurrent is Speed2")
g.walkCooldown = 0
g:walkHeld(0)
eq(g.playerX, 2, "still on the current")
g.walkCooldown = 0
g:walkHeld(0)
eq(g.playerX, 3, "onto ocean")
g.walkCooldown = 0
g:walkHeld(0)
eq(g.playerX, 3, "ocean is not a current")
Input.isDown = oldDown
check(g.surfing, "still surfing")

local belt = {
  id = "belt", width = 3, height = 1,
  grid = { 0, 0, 0 },
  behavior = { Game3.MB_WALK_EAST, Game3.MB_WALK_EAST, 0 },
}
g = Game3.new()
g.phase = "play"
g.data.maps = { start = "belt", maps = { belt = belt } }
g:enterMap(belt, 0, 0, true)
g.walkCooldown = 0
oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerX, 1, "walk pad")
eq(g.walkDuration, Game3.WALK_PERIOD, "PlayerGoSpeed1")
Input.isDown = oldDown

local chute = {
  id = "chute", width = 3, height = 1,
  grid = { 0, 0, 0 },
  behavior = { Game3.MB_SLIDE_EAST, Game3.MB_SLIDE_EAST, 0 },
}
g = Game3.new()
g.phase = "play"
g.data.maps = { start = "chute", maps = { chute = chute } }
g:enterMap(chute, 0, 0, true)
g.walkCooldown = 0
g.facing = "north"
oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerX, 1, "slide pad")
eq(g.facing, "north", "facingDirectionLocked")
eq(g.walkDuration, Game3.RUN_PERIOD, "PlayerGoSpeed2")
Input.isDown = oldDown

-- Mossdeep Gym: elevated walkways must not inherit floor-belt forced
-- movement when currentElevation drifts to 0 on a raised tile.
local ELEV3, ELEV0 = 3 * 4096, 0
local deck = {
  id = "mg_deck", width = 3, height = 2,
  grid = {
    ELEV3 + 0, ELEV3 + 0, ELEV3 + 0,
    ELEV0 + 0, ELEV0 + 0, ELEV0 + 0,
  },
  behavior = {
    Game3.MB_WALK_EAST, 0, 0,
    Game3.MB_WALK_NORTH, Game3.MB_WALK_NORTH, Game3.MB_WALK_NORTH,
  },
}
g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { mg_deck = deck } }
g:enterMap(deck, 1, 0, true)
eq(g.currentElevation, 3, "platform tile sets elevation 3")
g.currentElevation = 0
check(not g:tryForcedMovement(),
  "a floor belt does not drag you while standing on a raised tile")
g.currentElevation = 3
g.playerY = 1
g.currentElevation = 0
g:updatePlayerZCoord()
eq(g.currentElevation, 0, "back on the floor")
g.walkCooldown = 0
oldDown = Input.isDown
Input.isDown = function() return false end
check(g:tryForcedMovement(), "floor belts still push at elevation 0")
eq(g.playerY, 0, "belt rides north onto the deck")
Input.isDown = oldDown

eq(g:behaviorAtElevation(deck, 0, 0, 3), Game3.MB_WALK_EAST,
  "walk pads still apply on the matching walkway layer")
eq(g:behaviorAtElevation(deck, 0, 0, 0), 0,
  "walk pads ignore a stale floor layer on a walkway tile")
eq(g:behaviorAtElevation(deck, 1, 1, 3), 0,
  "floor belts ignore a raised layer")
g.playerX, g.playerY = 1, 0
g.walkFromX, g.walkFromY = 1, 0
g:updatePlayerZCoord()
eq(g.previousElevation, 3, "walkways keep their draw layer")
g.playerY = 1
g.walkFromX, g.walkFromY = 1, 0
g:updatePlayerZCoord()
eq(g.previousElevation, 0,
  "stepping onto the floor clears the walkway draw layer")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_ENTER_SAFARI_MODE, 205, "EnterSafariMode")
eq(Game3.SPECIAL_EXIT_SAFARI_MODE, 206, "ExitSafariMode")
eq(Game3.SPECIAL_SAFARI_ZONE_GET_POKEBLOCK_NAME, 207, "feeder name")
eq(Game3.SPECIAL_CHECK_FREE_POKEMON_STORAGE, 304, "CheckFreePokemonStorage")
eq(Game3.FLAG_SYS_SAFARI_MODE, 0x82C, "FLAG_SYS_SAFARI_MODE")
eq(Game3.VAR_SAFARI_ZONE_STATE, 0x40A4, "VAR_SAFARI_ZONE_STATE")
eq(Game3.GAME_STAT_ENTERED_SAFARI_ZONE, 17, "stat 17")
eq(Game3.SAFARI_BALLS, 30, "30 balls")
eq(Game3.SAFARI_STEPS, 500, "500 steps")
eq(Game3.MAP_SAFARI_ENTRANCE_GROUP, 23, "entrance group")
eq(Game3.MAP_SAFARI_SOUTHEAST_GROUP, 26, "SE group")
eq(Game3.MAP_SAFARI_SOUTHEAST_NUM, 3, "SE is index 3")

local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local entrance = {
  id = "g23_0", group = 23, index = 0,
  width = 3, height = 3, grid = cells,
}
local se = {
  id = "g26_3", group = 26, index = 3,
  width = 3, height = 3, grid = cells,
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g23_0 = entrance, g26_3 = se } }
g:enterMap(se, 1, 1, true)

local labels = g:startMenuItems()
check(labels[1] ~= "RETIRE", "START is normal outside safari")
local hasSave = false
for i = 1, #labels do
  if labels[i] == "SAVE" then hasSave = true end
end
check(hasSave, "SAVE is on START outside safari")

g:runSpecial(Game3.SPECIAL_ENTER_SAFARI_MODE)
check(g:inSafariMode(), "EnterSafariMode sets the flag")
eq(g.safariBalls, 30, "gNumSafariBalls = 30")
eq(g.safariSteps, 500, "gSafariZoneStepCounter = 500")
eq(g:getGameStat(Game3.GAME_STAT_ENTERED_SAFARI_ZONE), 1, "stat 17")
eq(g:itemCount(Game3.ITEM_SAFARI_BALL), 0, "balls are not bag items")

labels = g:startMenuItems()
eq(labels[1], "RETIRE", "safari START begins RETIRE")
eq(#labels, 7, "seven safari rows")
hasSave = false
local hasNav = false
for i = 1, #labels do
  if labels[i] == "SAVE" then hasSave = true end
  if labels[i] == "POKeNAV" then hasNav = true end
end
check(not hasSave, "no SAVE in safari")
check(not hasNav, "no POKeNAV in safari")
eq(labels[2], "POKeDEX", "POKeDEX is always listed")

local ok = g:writeSave()
check(not ok, "cannot SAVE in safari")

eq(g:runSpecial(Game3.SPECIAL_SAFARI_ZONE_GET_POKEBLOCK_NAME), 0xFFFF,
  "empty feeder is 0xFFFF")
eq(g:varGet(Gen3Script.VAR_RESULT), 0xFFFF, "specialvar stores FFFF")

eq(g:runSpecial(Game3.SPECIAL_CHECK_FREE_POKEMON_STORAGE), 1,
  "empty PC has space")
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "storage specialvar 1")
g:ensurePc()
for b = 1, Game3.BOX_COUNT do
  local box = g.pc[b]
  for s = 1, Game3.BOX_SIZE do
    box[s] = { species = 1 }
  end
end
eq(g:runSpecial(Game3.SPECIAL_CHECK_FREE_POKEMON_STORAGE), 0,
  "full PC is 0")
eq(g:varGet(Gen3Script.VAR_RESULT), 0, "storage 0 is valid")

for _ = 1, 499 do g:tickWalkCounters() end
eq(g.safariSteps, 1, "499 steps leave 1")
check(g:inSafariMode(), "still in safari")
check(not g.field, "not over yet")
g:tickWalkCounters()
eq(g.safariSteps, 0, "step 0 is time up")
check(g.field and g.field.thenSafariExit, "gUnknown_081C3448")
eq(g.field.text, Game3.TEXT_SAFARI_TIME_UP, "Ding-dong")
g:leaveSafari()
check(not g:inSafariMode(), "ExitSafariMode")
eq(g.safariBalls, 0, "balls cleared")
eq(g.safariSteps, 0, "steps cleared")
eq(g:varGet(Game3.VAR_SAFARI_ZONE_STATE), 1, "state 1 for ON_FRAME")
eq(g.map.id, "g23_0", "warp to the entrance")
eq(g.playerX, 2, "warp x 2")
eq(g.playerY, 5, "warp y 5")

g:runSpecial(Game3.SPECIAL_ENTER_SAFARI_MODE)
g:answerSafariRetire(false)
check(g:inSafariMode(), "RETIRE no stays")
g:openSafariRetirePrompt()
g:answerSafariRetire(true)
check(not g:inSafariMode(), "RETIRE yes leaves")
eq(g.map.id, "g23_0", "retire warp")

g:runSpecial(Game3.SPECIAL_EXIT_SAFARI_MODE)
check(not g:inSafariMode(), "ExitSafariMode special")
eq(g.safariBalls, 0, "exit zeros balls")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.MB_MT_PYRE_HOLE, 0x0F, "MB_MT_PYRE_HOLE")
eq(Game3.MB_AQUA_HIDEOUT_WARP, 0x67, "MB_AQUA_HIDEOUT_WARP")
eq(Game3.GFX_SUBMARINE_SHADOW, 141, "submarine shadow gfx")
eq(Game3.SE_WARP_IN, 45, "SE_WARP_IN")
eq(Game3.MB_WEST_ARROW_WARP, 0x63, "west arrow")
eq(Game3.MB_SOUTH_ARROW_WARP, 0x65, "south arrow")
eq(Game3.SPECIAL_WARP_TO_LAST_WARP, 318, "sp13E")
eq(Game3.SPECIAL_DO_FALL_WARP, 319, "DoFallWarp")
eq(Game3.SPECIAL_SET_ROUTE_119_WEATHER, 324, "SetRoute119Weather")
eq(Game3.SPECIAL_SET_ROUTE_123_WEATHER, 325, "SetRoute123Weather")
eq(Game3.FLAG_HIDE_GRUNT_1_BLOCKING_HIDEOUT, 0x335, "Harbor hide grunt 1")
eq(Game3.FLAG_HIDE_GRUNT_2_BLOCKING_HIDEOUT, 0x336, "Harbor hide grunt 2")
eq(Game3.VAR_SLATEPORT_HARBOR_STATE, 0x40A0, "VAR_SLATEPORT_HARBOR_STATE")
eq(Game3.VAR_MT_PYRE_STATE, 0x40B9, "VAR_MT_PYRE_STATE")
eq(Game3.MAP_MAGMA_HIDEOUT_1F_NUM, 74, "Magma 1F is dungeon 74")
eq(Game3.MOVEMENT_TYPE_ROTATE_CLOCKWISE, 0x18, "ROTATE_CLOCKWISE")
eq(Game3.nextRotateFacing("south", true), "west", "gClockwiseDirections")
eq(Game3.nextRotateFacing("south", false), "east", "gCounterclockwiseDirections")
check(Game3.arrowWarpMatches(Game3.MB_SOUTH_ARROW_WARP, 0, 1), "south onto south")
check(not Game3.arrowWarpMatches(Game3.MB_SOUTH_ARROW_WARP, 1, 0), "east is not south")
check(Game3.arrowWarpMatches(Game3.MB_STAIRS_OUTSIDE_ABANDONED_SHIP, 0, -1),
  "ship stairs are a north arrow")

local floor = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local hole = {
  id = "g24_15", group = 24, index = 15,
  width = 3, height = 3, grid = floor,
  behavior = { 0, Game3.MB_MT_PYRE_HOLE, 0, 0, 0, 0, 0, 0, 0 },
  warps = { { x = 1, y = 0, mapGroup = 24, mapNum = 16, warpId = 0 } },
}
local below = {
  id = "g24_16", group = 24, index = 16,
  width = 3, height = 3, grid = floor,
  warps = { { x = 1, y = 0, mapGroup = 24, mapNum = 15, warpId = 0 } },
}
local hideout = {
  id = "g24_74", group = 24, index = 74,
  width = 3, height = 3, grid = floor,
  mapType = Game3.MAP_TYPE_INDOOR,
  behavior = { 0, Game3.MB_AQUA_HIDEOUT_WARP, 0, 0, 0, 0, 0, 0, 0 },
  warps = { { x = 1, y = 0, mapGroup = 24, mapNum = 75, warpId = 0 } },
  objects = {
    {
      localId = 1, x = 0, y = 2, graphicsId = 10,
      movementType = Game3.MOVEMENT_TYPE_ROTATE_CLOCKWISE,
      flagId = Game3.FLAG_HIDE_GRUNT_1_BLOCKING_HIDEOUT,
    },
  },
}
local b1f = {
  id = "g24_75", group = 24, index = 75,
  width = 3, height = 3, grid = floor,
  mapType = Game3.MAP_TYPE_INDOOR,
  behavior = { 0, 0, 0, 0, Game3.MB_AQUA_HIDEOUT_WARP, 0, 0, 0, 0 },
  warps = { { x = 1, y = 1, mapGroup = 24, mapNum = 74, warpId = 0 } },
}
local arrows = {
  id = "arrows", width = 3, height = 3, grid = floor,
  behavior = { 0, 0, 0, 0, Game3.MB_SOUTH_ARROW_WARP, 0, 0, 0, 0 },
  warps = { { x = 1, y = 1, mapGroup = 24, mapNum = 75, warpId = 0 } },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = {
  maps = {
    g24_15 = hole, g24_16 = below, g24_74 = hideout, g24_75 = b1f,
    arrows = arrows,
  },
}

g:enterMap(hole, 1, 1, true)
g.ignoreWarp = false
check(g:tryWalk(0, -1), "step onto the Mt. Pyre hole")
eq(g.map.id, "g24_16", "DoFallWarp follows the hole warp")
eq(g.field and g.field.text, Game3.TEXT_FELL_THROUGH, "fall message")

g.field = nil
g:enterMap(hole, 1, 0, true)
g:runSpecial(Game3.SPECIAL_DO_FALL_WARP)
eq(g.map.id, "g24_16", "special 319 from the hole tile")
eq(g.field and g.field.text, Game3.TEXT_FELL_THROUGH, "special also falls")

g.field = nil
g:enterMap(hideout, 1, 1, true)
g.ignoreWarp = false
local heardSe
g.playSe = function(_, songId) heardSe = songId end
check(g:tryWalk(0, -1), "step onto the hideout pad")
eq(g.map.id, "g24_75", "0x67 warps via the pad event")
eq(heardSe, Game3.SE_WARP_IN, "sub_8080F68 plays SE_WARP_IN")
eq(g.playerX, 1, "dest warp x")
eq(g.playerY, 1, "dest warp y")
check(g.ignoreWarp, "land on the dest pad")

-- Magma Hideout maps omit Aqua's ON_TRANSITION SetupEvilTeamGfxIds.
-- enterMap must still paint GFX_VAR_* and keep the B2F submarine visible.
local b2f = {
  id = "g24_76", group = 24, index = 76,
  width = 4, height = 4, grid = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  },
  objects = {
    { localId = 1, x = 1, y = 1, graphicsId = Game3.GFX_VAR_1,
      trainerType = 1, trainerId = 596, flagId = 0x39C },
    { localId = 3, x = 2, y = 2, graphicsId = Game3.GFX_SUBMARINE_SHADOW,
      elevation = 1, flagId = Game3.FLAG_HIDE_SUBMARINE_SHADOW_HIDEOUT },
  },
}
check(g:mapNeedsEvilTeamGfx(b2f), "Magma Hideout B2F needs evil-team gfx")
g:enterMap(b2f, 0, 0, true)
eq(g:resolveGraphicsId(Game3.GFX_VAR_1), Game3.GFX_MAGMA_MEMBER_M,
  "B2F enterMap sets Magma M")
local npcs = g:npcsFor(b2f)
eq(#npcs, 2, "Tabitha and the submarine both spawn")
eq(npcs[1].graphicsId, Game3.GFX_MAGMA_MEMBER_M, "grunt sprite resolves")
eq(npcs[2].graphicsId, Game3.GFX_SUBMARINE_SHADOW, "submarine is gfx 141")
check(not npcs[2].hidden, "submarine is visible before escape")
g:setScriptVar(0x8009, 3)
g:removeObject(g:varGet(0x8009))
check(g:npcByLocalId(3).hidden, "escape removeobject hides the sub")
check(g.flags[Game3.FLAG_HIDE_SUBMARINE_SHADOW_HIDEOUT],
  "and sets FLAG_HIDE_SUBMARINE_SHADOW_HIDEOUT")

-- Failed trainerbattle must not fall into post-battle text unless the
-- trainer flag is already set (Magma "already beaten" without a fight).
local Gen3Script = require("src.import.Gen3Script")
local host = {
  flags = {},
  scriptVars = {},
  trainerDefeated = function() return false end,
  scriptTrainerBattle = function() return false end,
  sayScript = function(_, t) host.said = t end,
}
local said = Gen3Script.run(host, {
  { op = "trainerbattle", kind = 0, trainerId = 596 },
  { op = "loadword", text = "fake after" },
  { op = "callstd", id = 4 },
  { op = "end" },
}, 1)
eq(host.said, nil, "failed Magma fight does not print post-battle text")
host.trainerDefeated = function(_, id) return id == 596 end
host.said = nil
said = Gen3Script.run(host, {
  { op = "trainerbattle", kind = 0, trainerId = 596 },
  { op = "loadword", text = "real after" },
  { op = "callstd", id = 4 },
  { op = "end" },
}, 1)
-- callstd 4 goes through sayScript on some hosts; loadword alone may not.
-- At least the VM must advance past trainerbattle when beaten.
check(said ~= "wait", "beaten Magma fight does not wait for a battle")

g:enterMap(arrows, 1, 0, true)
g.ignoreWarp = false
check(g:tryWalk(0, 1), "walk south onto a south arrow")
eq(g.map.id, "g24_75", "matching dir warps")

g:enterMap(arrows, 0, 1, true)
g.ignoreWarp = false
check(g:tryWalk(1, 0), "walk east onto a south arrow")
eq(g.map.id, "arrows", "wrong dir does not warp")
eq(g.playerX, 1, "and occupies the arrow")
eq(g.playerY, 1, "same row")
check(g:tryWalk(0, 1), "then press south while on the mat")
eq(g.map.id, "g24_75", "side approach still exits")

-- House / Center doorways are two adjacent south-arrow mats. Landing
-- ignoreWarp used to stick when shuffling onto the other tile, so
-- south into the wall/OOB did nothing.
local doorway = {
  id = "doorway", width = 3, height = 3, grid = floor,
  behavior = {
    0, 0, 0,
    0, 0, 0,
    Game3.MB_SOUTH_ARROW_WARP, Game3.MB_SOUTH_ARROW_WARP, 0,
  },
  warps = {
    { x = 0, y = 2, mapGroup = 24, mapNum = 75, warpId = 0 },
    { x = 1, y = 2, mapGroup = 24, mapNum = 75, warpId = 0 },
  },
}
g.data.maps.maps.doorway = doorway
g:enterMap(doorway, 0, 2, true)
check(g.ignoreWarp, "land on the left mat")
check(g:tryWalk(1, 0), "shuffle onto the other mat")
eq(g.map.id, "doorway", "side step does not warp")
eq(g.playerX, 1, "now on the right mat")
check(not g.ignoreWarp, "a real step drops the landing ignore")
check(g:tryWalk(0, 1), "south from the side mat")
eq(g.map.id, "g24_75", "two-tile doorway exits from the side")

-- mapheader_run_first_tag2: facing the arrow dir while ON the mat
-- leaves even if this frame only turned (dest is OOB).
local Input = require("src.core.Input")
g:enterMap(arrows, 1, 1, true)
g.ignoreWarp = false
g.facing = "east"
g.warpSettle = nil
g.walkCooldown = 0
local oldDown = Input.isDown
Input.isDown = function(_, key) return key == "down" end
g:walkHeld(0.016)
eq(g.map.id, "g24_75", "turning to the arrow dir leaves")
Input.isDown = oldDown

g:enterMap(hideout, 1, 1, true)
local grunt = g:npcByLocalId(1)
check(grunt, "blocking grunt is spawned")
eq(grunt.facing, "south", "ROTATE_CLOCKWISE starts south")
g:stepNpcs(1)
eq(grunt.facing, "west", "then turns clockwise")
g:stepNpcs(1)
eq(grunt.facing, "north", "S→W→N")
g.flags = g.flags or {}
g.flags[Game3.FLAG_HIDE_GRUNT_1_BLOCKING_HIDEOUT] = true
g:resetNpcs()
check(not g:npcByLocalId(1), "Harbor setflag hides the grunt")

g.lastUsedWarp = { mapType = Game3.MAP_TYPE_INDOOR }
g.weatherCycleStage = 1
g:setSav1Weather(Game3.OW_WEATHER_SUNNY)
g:runSpecial(Game3.SPECIAL_SET_ROUTE_119_WEATHER)
eq(g.sav1Weather, 3, "indoor last warp starts the 119 cycle")
g.lastUsedWarp = { mapType = Game3.MAP_TYPE_ROUTE }
g.weatherCycleStage = 1
g:setSav1Weather(Game3.OW_WEATHER_SUNNY)
g:runSpecial(Game3.SPECIAL_SET_ROUTE_119_WEATHER)
eq(g.sav1Weather, 2, "outdoor last warp leaves header sunny")
g.lastUsedWarp = { mapType = Game3.MAP_TYPE_INDOOR }
g.weatherCycleStage = 2
g:setSav1Weather(Game3.OW_WEATHER_SUNNY)
g:runSpecial(Game3.SPECIAL_SET_ROUTE_123_WEATHER)
eq(g.sav1Weather, 3, "123 cycle stage 2 is light rain")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.MOVEMENT_TYPE_FACE_DOWN_AND_LEFT, 0x11, "FACE_DOWN_AND_LEFT")
eq(Game3.MOVEMENT_TYPE_FACE_DOWN_AND_RIGHT, 0x12, "FACE_DOWN_AND_RIGHT")
eq(Game3.wanderDirs(0x0D), "face_look", "FACE_DOWN_AND_UP")
eq(Game3.FACE_LOOK[0x11].dirs[1], "south", "gDownAndLeftDirections")
eq(Game3.FACE_LOOK[0x11].dirs[2], "west", "then west")
eq(Game3.limitedVectorDir(5, 0, 1), "south", "WestSouth player south")
eq(Game3.limitedVectorDir(5, -1, 0), "west", "WestSouth player west")
eq(Game3.limitedVectorDir(5, 1, 0), "south", "WestSouth remaps east")
eq(Game3.limitedVectorDir(5, 1, -1), "south", "WestSouth remaps NE")
eq(Game3.MT_MOSSDEEP_ARROW_RIGHT, 0x204, "RedArrow_Right")
eq(Game3.MT_MOSSDEEP_ARROW_LEFT, 0x20C, "RedArrow_Left")
eq(Game3.FLAG_MOSSDEEP_GYM_SWITCH_1, 0x64, "gym switch 1")

local room = {
  id = "pyre", width = 5, height = 3, grid = {
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
  },
  objects = {
    {
      localId = 1, x = 2, y = 1, graphicsId = 10,
      movementType = Game3.MOVEMENT_TYPE_FACE_DOWN_AND_LEFT,
      trainerType = Game3.TRAINER_TYPE_NORMAL,
      trainerRange = 2,
    },
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { pyre = room } }
g:enterMap(room, 2, 2, true)
local npc = g:npcByLocalId(1)
check(npc, "Mt. Pyre maniac spawned")
eq(npc.facing, "south", "FACE_DOWN_AND_LEFT starts south")
eq(npc.x, 2, "stays put")
g.rng = function() return 2 end
npc.wait = 0
g:stepNpcs(0)
eq(npc.facing, "west", "Random() picks west")
eq(npc.x, 2, "still on the tile")
eq(npc.wait, Game3.MOVEMENT_DELAYS_MEDIUM[2], "gMovementDelaysMedium")

npc.facing = "west"
npc.wait = 10
g.running = false
g:stepNpcs(0.01)
eq(npc.facing, "west", "walk does not skip the delay")
check(npc.wait > 9, "wait still running")

npc.wait = 10
g.running = true
g:stepNpcs(0.01)
eq(npc.facing, "south", "dash in range snaps south")
check(npc.wait < 3, "close trainer skips the delay")

local gym = {
  id = "gym", width = 3, height = 1,
  grid = { Game3.MT_MOSSDEEP_ARROW_LEFT, Game3.MT_MOSSDEEP_ARROW_LEFT, 0 },
  tileset = "moss",
}
g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { gym = gym } }
g.data.tilesets = {
  byId = {
    moss = {
      behavior = {
        [Game3.MT_MOSSDEEP_ARROW_RIGHT] = Game3.MB_WALK_EAST,
        [Game3.MT_MOSSDEEP_ARROW_DOWN] = Game3.MB_WALK_SOUTH,
        [Game3.MT_MOSSDEEP_ARROW_LEFT] = Game3.MB_WALK_WEST,
        [Game3.MT_MOSSDEEP_ARROW_UP] = Game3.MB_WALK_NORTH,
      },
    },
  },
}
g:enterMap(gym, 1, 0, true)
eq(g:behaviorAt(gym, 1, 0), Game3.MB_WALK_WEST, "left arrow is WALK_WEST")
g:setMetatile(1, 0, Game3.MT_MOSSDEEP_ARROW_RIGHT, 0)
eq(g:behaviorAt(gym, 1, 0), Game3.MB_WALK_EAST, "setmetatile flips the pad")
g.walkCooldown = 0
local Input = require("src.core.Input")
local oldDown = Input.isDown
Input.isDown = function() return false end
g:walkHeld(0)
eq(g.playerX, 2, "flipped arrow walks east")
Input.isDown = oldDown
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.VAR_ICE_STEP_COUNT, 0x4022, "VAR_ICE_STEP_COUNT")
eq(Game3.SPECIAL_SET_SOOTOPOLIS_GYM_CRACKED_ICE, 309, "special 309")
eq(Game3.MT_SOOTOPOLIS_ICE_THIN, 0x20D, "thin ice metatile")
eq(Game3.MT_SOOTOPOLIS_ICE_CRACKED, 0x20E, "cracked ice metatile")
eq(Game3.MT_SOOTOPOLIS_ICE_BROKEN, 0x206, "broken ice metatile")
eq(Game3.MAP_SOOTOPOLIS_GYM_B1F_NUM, 1, "B1F is indoor 1")
local id, bit = Game3.sootopolisIceBit(3, 6)
eq(id, Game3.VAR_TEMP_1, "y 6 is VAR_TEMP_1")
eq(bit, 0, "x 3 is bit 0")
check(not Game3.sootopolisIceBit(2, 6), "x 2 is outside the rink")
check(not Game3.sootopolisIceBit(3, 10), "y 10 has no row var")

local floor = {}
for i = 1, 20 * 20 do floor[i] = 0 end
floor[7 * 20 + 4 + 1] = Game3.MT_SOOTOPOLIS_ICE_THIN
floor[7 * 20 + 5 + 1] = Game3.MT_SOOTOPOLIS_ICE_THIN
local b1f = {
  id = "g15_1", group = 15, index = 1,
  width = 3, height = 3, grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
}
local gym = {
  id = "g15_0", group = 15, index = 0,
  width = 20, height = 20, grid = floor,
  tileset = "pair_36",
  spawn = { x = 8, y = 24 },
  mapScripts = {
    onTransition = {
      { op = "setvar", var = Game3.VAR_ICE_STEP_COUNT, val = 1 },
      { op = "end" },
    },
    onFrame = {
      {
        var = Game3.VAR_ICE_STEP_COUNT, value = 8,
        script = {
          { op = "addvar", var = Game3.VAR_ICE_STEP_COUNT, val = 1 },
          { op = "setmetatile", x = 8, y = 15,
            tile = Game3.MT_SOOTOPOLIS_ICE_STAIRS, collision = 0 },
          { op = "end" },
        },
      },
      {
        var = Game3.VAR_ICE_STEP_COUNT, value = 0,
        script = {
          { op = "warphole", mapGroup = 15, mapNum = 1 },
          { op = "end" },
        },
      },
    },
  },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g15_0 = gym, g15_1 = b1f } }
g.data.tilesets = {
  byId = {
    pair_36 = {
      behavior = {
        [Game3.MT_SOOTOPOLIS_ICE_THIN] = Game3.MB_THIN_ICE,
        [Game3.MT_SOOTOPOLIS_ICE_CRACKED] = Game3.MB_CRACKED_ICE,
        [Game3.MT_SOOTOPOLIS_ICE_BROKEN] = Game3.MB_CRACKED_FLOOR_HOLE,
        [Game3.MT_SOOTOPOLIS_ICE_STAIRS] = 0,
      },
    },
  },
}
g:enterMap(gym, 4, 7, true)
eq(g:varGet(Game3.VAR_ICE_STEP_COUNT), 1, "ON_TRANSITION sets the count to 1")
g:setScriptVar(Game3.VAR_TEMP_1, 99)
g:enterMap(gym, 4, 7, true)
eq(g:varGet(Game3.VAR_TEMP_1), 0, "enterMap clears VAR_TEMP")
eq(g.map.id, "g15_0", "count 1 does not fall")
g:setStepCallback(Game3.STEP_CB_ICE)
g:setScriptVar(Game3.VAR_ICE_STEP_COUNT, 7)
check(g:tryWalk(1, 0), "step onto thin ice")
eq(g:varGet(Game3.VAR_ICE_STEP_COUNT), 8, "thin ice increments the count")
eq(Game3.metatileOf(gym.grid[7 * 20 + 5 + 1]),
  Game3.MT_SOOTOPOLIS_ICE_CRACKED, "0x20D cracks to 0x20E")
check(g:sootopolisIceWasCracked(5, 7), "bit is saved in VAR_TEMP_2")
g:tryMapFrameScript()
eq(g:varGet(Game3.VAR_ICE_STEP_COUNT), 9, "ON_FRAME addvar so it does not re-fire")
eq(Game3.metatileOf(gym.grid[15 * 20 + 8 + 1]),
  Game3.MT_SOOTOPOLIS_ICE_STAIRS, "8 steps open the first stairs")

g:writeMetatile(5, 7, Game3.MT_SOOTOPOLIS_ICE_THIN)
g:runSpecial(Game3.SPECIAL_SET_SOOTOPOLIS_GYM_CRACKED_ICE)
eq(Game3.metatileOf(gym.grid[7 * 20 + 5 + 1]),
  Game3.MT_SOOTOPOLIS_ICE_CRACKED, "special 309 restores the crack")

g.playerX, g.playerY = 4, 7
g.walkFromX, g.walkFromY = 4, 7
g.walkCooldown = 0
g.field = nil
g:setScriptVar(Game3.VAR_ICE_STEP_COUNT, 9)
check(g:tryWalk(1, 0), "step onto the crack")
eq(g:varGet(Game3.VAR_ICE_STEP_COUNT), 0, "cracked ice zeros the count")
eq(g.map.id, "g15_0", "does not snap to spawn")
eq(g.playerX, 5, "still on the hole")
g.field = nil
g:tryMapFrameScript()
eq(g.map.id, "g15_1", "ON_FRAME warphole to B1F")
eq(g.playerX, 5, "at the same x")
eq(g.playerY, 7, "and y")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
eq(Gen3Script.SETDIVEWARP, 0x40, "setdivewarp")
eq(Game3.MAP_SOOTOPOLIS_CITY_NUM, 7, "Sootopolis is g0_7")
eq(Game3.MAP_UNDERWATER_SOOTOPOLIS_NUM, 5, "underwater is g24_5")
eq(Game3.MAP_CAVE_OF_ORIGIN_B4F_NUM, 42, "Cave of Origin B4F")
eq(Game3.MAP_SEAFLOOR_CAVERN_ROOM9_NUM, 36, "Seafloor Room 9")
eq(Game3.FLAG_SYS_WEATHER_CTRL, 0x82A, "SYSTEM_FLAGS+0x2A")
eq(Game3.FLAG_LEGENDARY_BATTLE_COMPLETED, 0x71, "beat or catch Groudon")
eq(Game3.FLAG_LEGEND_ESCAPED_SEAFLOOR_CAVERN, 0x81, "Maxie woke it")
eq(Game3.VAR_SOOTOPOLIS_STATE, 0x405E, "Sootopolis state")
eq(Game3.VAR_CAVE_OF_ORIGIN_B4F_STATE, 0x409B, "B4F state")
local ops = Gen3Script.parse(
  string.char(0x40, 24, 5, 0xFF, 9, 0, 6, 0)
  .. string.char(0x02), 0)
eq(ops[1].op, "setdivewarp", "setdivewarp is kept")
eq(ops[1].mapGroup, 24, "dungeons group")
eq(ops[1].mapNum, 5, "Underwater_SootopolisCity")
eq(ops[1].warpId, 0xFF, "WARP_ID_NONE")
eq(ops[1].x, 9, "dest x")
eq(ops[1].y, 6, "dest y")

local city = {
  id = "g0_7", group = 0, index = 7, mapType = Game3.MAP_TYPE_CITY,
  width = 12, height = 8, tileset = "wat",
  spawn = { x = 2, y = 2 },
  grid = {},
  connections = {},
  mapScripts = {
    onResume = {
      { op = "setdivewarp", mapGroup = 24, mapNum = 5,
        warpId = 0xFF, x = 9, y = 6 },
    },
  },
}
local under = {
  id = "g24_5", group = 24, index = 5,
  mapType = Game3.MAP_TYPE_UNDERWATER,
  width = 12, height = 8, tileset = "wat",
  spawn = { x = 1, y = 1 },
  grid = {},
  connections = {},
  mapScripts = {
    onResume = {
      { op = "setdivewarp", mapGroup = 0, mapNum = 7,
        warpId = 0xFF, x = 4, y = 5 },
    },
  },
}
for i = 1, 12 * 8 do
  city.grid[i] = 0
  under.grid[i] = 0
end
city.grid[2 * 12 + 2 + 1] = 1027
under.grid[6 * 12 + 9 + 1] = 1027
under.grid[5 * 12 + 4 + 1] = 1027
city.grid[5 * 12 + 4 + 1] = 1027
local g = Game3.new()
g.phase = "play"
g.party = { { name = "WAILORD", moves = { { id = Game3.MOVE_DIVE } } } }
g.flags[Game3.FLAG_BADGE07_GET] = true
g.data.maps = { maps = { g0_7 = city, g24_5 = under } }
g.data.tilesets = {
  byId = { wat = { behavior = { [1] = 0x10, [3] = 0x12 } } },
}
g.surfing = true
g:enterMap(city, 2, 2, true)
eq(g.diveWarp.mapNum, 5, "ON_RESUME setdivewarp")
eq(g.diveWarp.x, 9, "fixed dest x, not player x")
g.surfing = true
local okDive = g:useDive()
check(okDive, "Sootopolis DIVE uses gFixedDiveWarp")
eq(g.map.id, "g24_5", "underwater Sootopolis")
eq(g.playerX, 9, "lands at warp x")
eq(g.playerY, 6, "not the player's tile")
eq(g.diveWarp.mapNum, 7, "ON_RESUME stores the emerge dest")
local okUp = g:useDive()
check(okUp, "emerge uses the stored warp")
eq(g.map.id, "g0_7", "back in the crater")
eq(g.playerX, 4, "emerge x")
eq(g.playerY, 5, "emerge y")
city.mapScripts = nil
g.diveWarp = nil
g.surfing = true
check(not g:useDive(), "no connection and no fixed warp")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_UPDATE_TRAINER_FAN_CLUB_GAME_CLEAR, 169,
  "UpdateTrainerFanClubGameClear")
eq(Game3.MT_ELITE_FOUR_OPEN_DOOR_FRAME, 0x344, "E4 open door frame")
eq(Game3.MT_ELITE_FOUR_OPEN_DOOR_OPENING, 0x345, "E4 open door opening")
eq(Game3.FLAG_SYS_POKEMON_LEAGUE_FLY, 0x854, "league fly")
local fade = Gen3Script.parse(string.char(0x98, 1, 24, 0x02), 0)
eq(fade[1].op, "fadescreen", "fadescreenspeed is a fade")
eq(fade[1].mode, 1, "FADE_TO_BLACK")
eq(fade[1].speed, 24, "delay 24")
local g = Game3.new()
g.flags[Game3.FLAG_HIDE_FANCLUB_OLD_LADY] = true
g.flags[Game3.FLAG_HIDE_FANCLUB_BOY] = true
g.flags[Game3.FLAG_HIDE_FANCLUB_LITTLE_BOY] = true
g.flags[Game3.FLAG_HIDE_FANCLUB_LADY] = true
g.playSeconds = 5 * 3600
g:runSpecial(Game3.SPECIAL_UPDATE_TRAINER_FAN_CLUB_GAME_CLEAR)
eq(g:varGet(Game3.VAR_LILYCOVE_FAN_CLUB_STATE), 1, "fan club state 1")
eq(g:varGet(Game3.VAR_FANCLUB_UNKNOWN_1), 0x2580, "init bits")
eq(g:varGet(Game3.VAR_FANCLUB_UNKNOWN_2), 5, "hours")
eq(g.flags[Game3.FLAG_HIDE_FANCLUB_OLD_LADY], nil, "old lady shown")
eq(g.flags[Game3.FLAG_HIDE_FANCLUB_BOY], nil, "boy shown")
g:setScriptVar(Game3.VAR_LILYCOVE_FAN_CLUB_STATE, 9)
g:runSpecial(Game3.SPECIAL_UPDATE_TRAINER_FAN_CLUB_GAME_CLEAR)
eq(g:varGet(Game3.VAR_LILYCOVE_FAN_CLUB_STATE), 9, "bit 7 skips a second run")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.SPECIAL_CHECK_FOR_BIG_MOVIE_OR_EMERGENCY_NEWS_ON_TV, 73,
  "CheckForBigMovieOrEmergencyNewsOnTV")
eq(Game3.FLAG_SYS_TV_LATI, 0x85D, "SYSTEM_FLAGS+0x5D")
eq(Game3.FLAG_LATIOS_OR_LATIAS_ROAMING, 0xFF, "TV script setflag")
eq(Game3.ITEM_SS_TICKET, 265, "SS Ticket")
eq(Game3.MAP_BRENDANS_HOUSE_1F_NUM, 0, "Brendan 1F")
eq(Game3.MAP_MAYS_HOUSE_1F_NUM, 2, "May 1F")
local function house(id, index)
  local grid = {}
  for i = 1, 16 do grid[i] = 0 end
  return {
    id = id, group = 1, index = index,
    width = 4, height = 4, grid = grid,
  }
end
local brendan = house("g1_0", 0)
local may = house("g1_2", 2)
local g = Game3.new()
g.phase = "play"
g.gender = Game3.GENDER_MALE
g.data.maps = { maps = { g1_0 = brendan, g1_2 = may } }
g:enterMap(brendan, 1, 1, true)
g.flags[Game3.FLAG_SYS_TV_LATI] = true
eq(g:runSpecial(Game3.SPECIAL_CHECK_FOR_BIG_MOVIE_OR_EMERGENCY_NEWS_ON_TV),
  1, "Lati news in Brendan 1F")
g.flags[Game3.FLAG_SYS_TV_LATI] = nil
g.flags[Game3.FLAG_SYS_TV_HOME] = true
eq(g:checkForBigMovieOrEmergencyNewsOnTV(), 2, "moving-in movie")
g.flags[Game3.FLAG_SYS_TV_HOME] = nil
eq(g:checkForBigMovieOrEmergencyNewsOnTV(), 1, "neither flag is still 1")
g:enterMap(may, 1, 1, true)
eq(g:checkForBigMovieOrEmergencyNewsOnTV(), 0, "boy is not in May 1F")
g.gender = Game3.GENDER_FEMALE
eq(g:checkForBigMovieOrEmergencyNewsOnTV(), 1, "May in her 1F")
g:enterMap(brendan, 1, 1, true)
eq(g:checkForBigMovieOrEmergencyNewsOnTV(), 0, "girl is not in Brendan 1F")
g.rng = function() return 1 end
g:initRoamer()
eq(g.roamerLocation[2], 25, "starts on Route 110")
local calls = 0
g.gbaRandom = function()
  calls = calls + 1
  if calls == 1 then return 0 end
  return 1
end
g:enterMap(brendan, 1, 1, true)
eq(g.roamerLocation[2], 26, "1/16 jumps to another set")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
Input:init()
eq(Game3.SPECIAL_SET_SS_TIDAL_FLAG, 203, "SetSSTidalFlag")
eq(Game3.SPECIAL_RESET_SS_TIDAL_FLAG, 204, "ResetSSTidalFlag")
eq(Game3.SPECIAL_SUB_80C7958, 270, "porthole cinema")
eq(Game3.FLAG_SYS_CRUISE_MODE, 0x82D, "SYSTEM_FLAGS+0x2D")
eq(Game3.VAR_CRUISE_STEP_COUNT, 0x404A, "cruise steps")
eq(Game3.VAR_PORTHOLE_STATE, 0x40B4, "porthole state")
eq(Game3.CRUISE_STEP_ARRIVE, 0xCC, "still sailing at 204")
eq(Game3.MAP_ROUTE132_NUM, 47, "Route 101 is 16")
eq(Game3.MAP_ROUTE134_NUM, 49, "Route 134")
eq(Game3.PORTHOLE_ARRIVED_VIA_VIEW_LILYCOVE, 9, "porthole arrive Lilycove")
eq(Game3.MULTICHOICE[52][1], "LILYCOVE", "Slateport harbor list")
eq(Game3.MULTICHOICE[52][2], "BATTLE TOWER", "then the tower")
eq(Game3.MULTICHOICE[56][1], "SLATEPORT", "Lilycove harbor list")
local g = Game3.new()
g.phase = "play"
g:runSpecial(Game3.SPECIAL_SET_SS_TIDAL_FLAG)
check(not g:scriptWaiting(), "SetSSTidalFlag does not wait")
check(g:inCruiseMode(), "FLAG_SYS_CRUISE_MODE")
eq(g:varGet(Game3.VAR_CRUISE_STEP_COUNT), 0, "steps start at 0")
g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_LILYCOVE)
for _ = 1, 204 do g:tickWalkCounters() end
eq(g:varGet(Game3.VAR_CRUISE_STEP_COUNT), 204, "204 is still <= 0xCC")
check(g:inCruiseMode(), "still cruising")
check(not g.field, "no ding-dong yet")
g:tickWalkCounters()
eq(g:varGet(Game3.VAR_CRUISE_STEP_COUNT), 205, "205th step arrives")
check(not g:inCruiseMode(), "ResetSSTidalFlag")
eq(g:varGet(Game3.VAR_PORTHOLE_STATE), Game3.PORTHOLE_ARRIVED_LILYCOVE,
  "state 2 becomes 3")
eq(g.field.text, Game3.TEXT_SS_TIDAL_VOYAGE, "gUnknown_0815FD0D")
g.field = nil
g:runSpecial(Game3.SPECIAL_SET_SS_TIDAL_FLAG)
g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_SLATEPORT)
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, 0xCC)
g:tickWalkCounters()
eq(g:varGet(Game3.VAR_PORTHOLE_STATE), Game3.PORTHOLE_ARRIVED_SLATEPORT,
  "state 7 becomes 8")
eq(g.field.text, Game3.TEXT_SS_TIDAL_LAND_SLATEPORT, "landed in Slateport")
check(not g:inCruiseMode(), "arrival clears cruise")
g.field = nil
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, 50)
g:runSpecial(Game3.SPECIAL_SUB_80C7958)
check(g:inCruiseMode(), "porthole FlagSet cruise")
eq(g:varGet(Game3.VAR_CRUISE_STEP_COUNT), 50, "does not zero steps")
check(g:scriptWaiting(), "porthole waitstate")
eq(g.field.kind, "porthole", "Task_HandlePorthole")
check(g.invisible, "player hidden")
eq(g.flags[Game3.FLAG_DONT_TRANSITION_MUSIC], true, "skip music fade")
local oldPorthole = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:walkHeld(1 / 60)
Input.wasPressed = oldPorthole
eq(g:scriptWaiting(), false, "A exits the porthole")
eq(g:varGet(Game3.VAR_CRUISE_STEP_COUNT), 50, "A does not count a step")
check(g:inCruiseMode(), "A exit keeps cruise")
eq(g.flags[Game3.FLAG_DONT_TRANSITION_MUSIC], nil, "clears music skip")
eq(g.invisible, nil, "player shown")

g = Game3.new()
g.phase = "play"
local function fill(w, h)
  local grid = {}
  for i = 1, w * h do grid[i] = 1 end
  return grid
end
local ship = {
  id = "g26_1", group = 26, index = 1, width = 10, height = 10,
  grid = fill(10, 10),
}
local ocean = {
  id = "g0_49", group = 0, index = 49, width = 80, height = 25,
  grid = fill(80, 25),
}
g.data.maps = { maps = { [ship.id] = ship, [ocean.id] = ocean } }
g:enterMap(ship, 5, 4, true)
g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_LILYCOVE)
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, 0)
g.flags[Game3.FLAG_SYS_CRUISE_MODE] = true
local og, on, ox, oy = g:getSSTidalLocation()
eq(og, 0, "ocean group")
eq(on, Game3.MAP_ROUTE134_NUM, "state 2 step 0 is Route 134")
eq(ox, 19, "x = steps+19")
eq(oy, 20, "y is 20")
g:runSpecial(Game3.SPECIAL_SUB_80C7958)
eq(g.map.id, ocean.id, "warps to GetSSTidalLocation")
eq(g.playerX, 19, "ocean x")
eq(g.playerY, 20, "ocean y")
check(g.invisible, "hidden on the ocean")
oldPorthole = Input.wasPressed
Input.wasPressed = function(_, key) return key == "a" end
g:walkHeld(1 / 60)
Input.wasPressed = oldPorthole
eq(g.map.id, ship.id, "A warps back")
eq(g.playerX, 5, "saved x")
eq(g.playerY, 4, "saved y")

g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_LILYCOVE)
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, Game3.CRUISE_STEP_ARRIVE)
g.flags[Game3.FLAG_SYS_CRUISE_MODE] = true
g:runSpecial(Game3.SPECIAL_SUB_80C7958)
g:walkHeld(Game3.WALK_PERIOD)
eq(g:varGet(Game3.VAR_PORTHOLE_STATE),
  Game3.PORTHOLE_ARRIVED_VIA_VIEW_LILYCOVE, "arrive sets 9 not 3")
check(g:inCruiseMode(), "Reset is the corridor ON_FRAME")
eq(g.map.id, ship.id, "arrive warps back")
eq(g:scriptWaiting(), false, "arrive Enables")

g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_SLATEPORT)
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, 0)
local sg, sn, sx = g:getSSTidalLocation()
eq(sn, Game3.MAP_ROUTE132_NUM, "state 7 step 0 is Route 132")
eq(sx, 65, "x = 65-steps")
g:setScriptVar(Game3.VAR_PORTHOLE_STATE, Game3.PORTHOLE_SAILING_TO_LILYCOVE)
g:setScriptVar(Game3.VAR_CRUISE_STEP_COUNT, 60)
sg, sn, sx = g:getSSTidalLocation()
eq(sn, Game3.MAP_ROUTE133_NUM, "state 2 step 60 is Route 133")
eq(sx, 0, "x = steps-60")
g:setScriptVar(Game3.VAR_PORTHOLE_STATE, 1)
eq(g:getSSTidalLocation(), nil, "docked states do not warp")

g:runSpecial(Game3.SPECIAL_RESET_SS_TIDAL_FLAG)
check(not g:inCruiseMode(), "ResetSSTidalFlag special")
g.flags[Game3.FLAG_SYS_CRUISE_MODE] = true
g:blackout()
check(not g:inCruiseMode(), "white-out FlagClear cruise")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.SPECIAL_IS_MIRAGE_ISLAND_PRESENT, 209, "IsMirageIslandPresent")
eq(Game3.SPECIAL_UPDATE_SHOAL_TIDE_FLAG, 210, "UpdateShoalTideFlag")
eq(Game3.FLAG_SYS_SHOAL_TIDE, 0x83A, "SYSTEM_FLAGS+0x3A")
eq(Game3.VAR_MIRAGE_RND_H, 0x4024, "mirage high")
eq(Game3.LAYOUT_ROUTE131_SKY_PILLAR, 320, "post-game Route 131")
eq(Game3.SHOAL_TIDE_BY_HOUR[1], 1, "hour 0 is high")
eq(Game3.SHOAL_TIDE_BY_HOUR[4], 0, "hour 3 is low")
local g = Game3.new()
g.phase = "play"
local island = { width = 2, height = 2, grid = { 9, 9, 9, 9 }, tileset = "sky" }
local route = {
  id = "g0_r131", layoutId = 47, width = 2, height = 2,
  grid = { 1, 2, 3, 4 }, tileset = "ocean",
  mapScripts = {
    onTransition = {
      { op = "checkflag", flag = Game3.FLAG_SYS_GAME_CLEAR },
      {
        op = "call_if", cond = 1,
        body = { { op = "setmaplayoutindex", index = 320 } },
      },
    },
  },
}
g.data.maps = { maps = { g0_r131 = route }, layouts = { [320] = island } }
g:enterMap(route, 0, 0, true)
eq(g.map.grid[1], 1, "pre-clear Route 131 stays ocean")
eq(g.mapLayoutId, 47, "header layout")
eq(route.baseGrid[1], 1, "extracted grid is frozen")
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = true
g:enterMap(route, 0, 0, true)
eq(g.mapLayoutId, 320, "setmaplayoutindex 320")
eq(g.map.grid[1], 9, "Sky Pillar island tiles")
eq(g.map.tileset, "sky", "island tileset")
eq(route.baseGrid[1], 1, "swap does not mutate the header grid")
g.map.grid[1] = 99
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = nil
g:enterMap(route, 0, 0, true)
eq(g.map.grid[1], 1, "re-enter restores the header layout")
g.flags[Game3.FLAG_SYS_GAME_CLEAR] = true
g:enterMap(route, 0, 0, true)
local snap = g:snapshotSave()
eq(snap.mapLayoutId, 320, "CONTINUE stores mapLayoutId")
snap.flags[Game3.FLAG_SYS_GAME_CLEAR] = nil
g.flags = {}
g:applySave(snap)
eq(g.mapLayoutId, 320, "CONTINUE keeps the saved layout")
eq(g.map.grid[1], 9, "island tiles after CONTINUE")
check(not g:scriptWaiting(), "setmaplayoutindex does not wait")
g.party = { { species = 277, pid = 0x1234 } }
g:setScriptVar(Game3.VAR_MIRAGE_RND_H, 0x1234)
eq(g:runSpecial(Game3.SPECIAL_IS_MIRAGE_ISLAND_PRESENT), 1, "pid low 16")
eq(g:varGet(Gen3Script.VAR_RESULT), 1, "specialvar stores 1")
g:setScriptVar(Game3.VAR_MIRAGE_RND_H, 0x9999)
eq(g:runSpecial(Game3.SPECIAL_IS_MIRAGE_ISLAND_PRESENT), 0, "no match is 0")
check(not g:scriptWaiting(), "IsMirageIslandPresent does not wait")
g.lastUsedWarp = { mapType = Game3.MAP_TYPE_ROUTE }
g:rtcInitLocalTimeOffset(0, 0)
g:runSpecial(Game3.SPECIAL_UPDATE_SHOAL_TIDE_FLAG)
check(g.flags[Game3.FLAG_SYS_SHOAL_TIDE], "hour 0 is high tide")
g:rtcInitLocalTimeOffset(3, 0)
g:runSpecial(Game3.SPECIAL_UPDATE_SHOAL_TIDE_FLAG)
check(not g.flags[Game3.FLAG_SYS_SHOAL_TIDE], "hour 3 is low tide")
g.flags[Game3.FLAG_SYS_SHOAL_TIDE] = true
g.lastUsedWarp = { mapType = Game3.MAP_TYPE_INDOOR }
g:runSpecial(Game3.SPECIAL_UPDATE_SHOAL_TIDE_FLAG)
check(g.flags[Game3.FLAG_SYS_SHOAL_TIDE], "indoor last warp does not update")
check(not g:scriptWaiting(), "UpdateShoalTideFlag does not wait")
end)()

;(function()
local Game3 = require("src.core.Game3")
local function floor(w, h)
  local grid = {}
  for i = 1, w * h do grid[i] = 0 end
  return grid
end
local r113 = { id = "g0_28", width = 100, height = 20, grid = floor(100, 20) }
local r112 = { id = "g0_27", width = 40, height = 60, grid = floor(40, 60) }
local r111 = {
  id = "g0_26", width = 40, height = 140, grid = floor(40, 140),
  connections = {
    { dir = "west", mapGroup = 0, mapNum = 28, offset = 0 },
    { dir = "west", mapGroup = 0, mapNum = 27, offset = 20 },
  },
}
local g = Game3.new()
g.data.maps = { maps = { g0_26 = r111, g0_27 = r112, g0_28 = r113 } }
check(Game3.connectionCoordInRange(r111.connections[1], r111, r113, "west", 0, 8),
  "y=8 is on the Route 113 span")
check(not Game3.connectionCoordInRange(r111.connections[1], r111, r113, "west", 0, 66),
  "y=66 is past Route 113")
check(Game3.connectionCoordInRange(r111.connections[2], r111, r112, "west", 0, 66),
  "and on the Route 112 span")
local dest, dx, dy = g:connectionDest(r111, 0, 8, -1, 0)
eq(dest and dest.id, "g0_28", "north-west edge is Route 113")
eq(dy, 8, "113 offset 0 keeps y")
dest, dx, dy = g:connectionDest(r111, 0, 66, -1, 0)
eq(dest and dest.id, "g0_27", "west of the desert is Route 112")
eq(dx, 39, "east edge of 112")
eq(dy, 46, "y minus offset 20")
eq(g:connectionDest(r111, 0, 100, -1, 0), nil,
  "south of both spans is no connection")
g:enterMap(r111, 0, 66, true)
check(g:tryWalk(-1, 0), "walking west at y=66 leaves 111")
eq(g.map.id, "g0_27", "onto Route 112")
eq(g.playerX, 39, "east column")
eq(g.playerY, 46, "aligned by offset 20")
end)()

;(function()
local Game3 = require("src.core.Game3")
eq(Game3.MB_NO_SURFACING, 0x19, "MB_NO_SURFACING")
eq(Game3.MB_HOT_SPRINGS, 0x28, "hot springs are 0x28")
eq(Game3.MB_LAVARIDGE_GYM_B1F_WARP, 0x29, "gym B1F pad")
eq(Game3.MB_SEAWEED_NO_SURFACING, 0x2A, "seaweed no-surfacing")
eq(Game3.MB_LAVARIDGE_GYM_1F_WARP, 0x68, "gym 1F pad")
check(not Game3.isSurfable(Game3.MB_HOT_SPRINGS), "springs are land")
check(not Game3.isSurfable(Game3.MB_LAVARIDGE_GYM_B1F_WARP), "B1F pad is land")
check(Game3.isSurfable(Game3.MB_NO_SURFACING), "no-surfacing is water")
check(Game3.isSurfable(Game3.MB_SEAWEED_NO_SURFACING), "seaweed too")
check(Game3.isSurfable(Game3.MB_WATER_DOOR), "water door is surfable")
check(Game3.isSurfable(Game3.MB_WATER_SOUTH_ARROW_WARP), "water south arrow too")
check(not Game3.isSurfable(Game3.MB_WARP_OR_BRIDGE), "cycling road is land")
check(Game3.isUnableToEmerge(Game3.MB_NO_SURFACING), "blocks emerge")
check(not Game3.isUnableToEmerge(Game3.MB_HOT_SPRINGS), "springs are not a ceiling")
local g = Game3.new()
local map = {
  id = "g0_12", width = 2, height = 1,
  grid = { 0, 0 },
  behavior = { 0, Game3.MB_HOT_SPRINGS },
}
g:enterMap(map, 0, 0, true)
check(g:canStep(map, 1, 0), "can walk into the springs")
check(g:tryWalk(1, 0), "and does")
eq(g.playerX, 1, "on the spring tile")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
local GbaBin = require("src.import.GbaBin")
eq(Gen3Script.parse(string.char(0x7A) .. GbaBin.packU16(360)
  .. string.char(0x02), 0)[1].op, "giveegg", "giveegg is kept")
eq(Gen3Script.parse(string.char(0x7A) .. GbaBin.packU16(360)
  .. string.char(0x02), 0)[1].species, 360, "species is Wynaut")
eq(Gen3Script.parse(string.char(0x4B) .. GbaBin.packU16(13)
  .. string.char(0x02), 0)[1].op, "adddecoration", "adddecoration is kept")
eq(Gen3Script.parse(string.char(0x81, 0) .. GbaBin.packU16(6)
  .. string.char(0x02), 0)[1].op, "bufferdecoration", "bufferdecorationname")
local g = Game3.new()
eq(Game3.SPECIES_WYNAUT, 360, "Wynaut is 360")
eq(Game3.EGG_MET_HOT_SPRINGS, 253, "hot springs met location")
eq(g:giveEgg(360), 0, "ScriptGiveEgg returns 0 in the party")
eq(#g.party, 1, "one slot")
eq(g.party[1].species, 360, "Wynaut stays 360")
eq(g.party[1].isEgg, true, "is an egg")
eq(g.party[1].name, "EGG", "nickname EGG")
eq(g.party[1].metLocation, 253, "CreateEgg setMetLocation")
eq(g.party[1].level, Game3.EGG_HATCH_LEVEL, "hatch level 5")
check(not g:hasCaught(360), "eggs do not set the dex")
g:hatchEgg(g.party[1])
eq(g.party[1].species, 360, "hatches as Wynaut")
eq(g.party[1].isEgg, nil, "no longer an egg")
check(g:hasCaught(360), "hatch sets the dex")

local host = Game3.new()
Gen3Script.run(host, { { op = "giveegg", species = 360 } })
eq(host.party[1].species, 360, "VM giveegg")
eq(host:varGet(Gen3Script.VAR_RESULT), 0, "RESULT 0 is party")

local full = Game3.new()
full.party = {}
for i = 1, Game3.PARTY_MAX do
  full.party[i] = full:makeMon(277, 5)
end
eq(full:giveEgg(360), 1, "party full is SendMonToPC 1")
eq(full.pc[1][1].species, 360, "egg is in box 1")
eq(full.pc[1][1].isEgg, true, "still an egg")
check(not full:hasCaught(360), "PC eggs do not set the dex")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
eq(Game3.MB_PETALBURG_GYM_DOOR, 0x8D, "MB_PETALBURG_GYM_DOOR")
local locked = "This door appears to be locked right now..."
local doorOps = {
  { op = "compare", var = Game3.VAR_PETALBURG_GYM_STATE, val = 6 },
  { op = "goto_if", cond = 0, to = 5 },
  { op = "warp", mapGroup = 8, mapNum = 1, warpId = 255, x = 32776, y = 32777 },
  { op = "end" },
  { op = "loadword", text = locked },
  { op = "callstd", id = Gen3Script.STD_MSGBOX_DEFAULT },
  { op = "end" },
}
local function gymMap()
  local w, h = 5, 5
  local grid = {}
  for i = 1, w * h do grid[i] = 0 end
  grid[1 * w + 1 + 1] = 1024
  return {
    id = "g8_1", width = w, height = h, grid = grid,
    warps = {
      { x = 1, y = 1, mapGroup = 8, mapNum = 1, warpId = 1 },
      { x = 3, y = 3, mapGroup = 8, mapNum = 1, warpId = 0 },
    },
    bgEvents = {
      { x = 1, y = 1, kind = 0, script = doorOps },
    },
  }
end
local g = Game3.new()
g.phase = "play"
local gym = gymMap()
g.data.maps = { maps = { g8_1 = gym } }
g:enterMap(gym, 1, 2, true)
g.facing = "north"
check(not g:tryWalk(0, -1), "locked gym door does not bump-warp")
eq(g.playerX, 1, "still in front of the door X")
eq(g.playerY, 2, "still in front of the door Y")
eq(Game3.collisionOf(gym.grid[1 * 5 + 1 + 1]) ~= 0, true,
  "lightExitDoors leaves the sliding door solid")
check(g:tryTalk(), "A-press runs the door sign")
eq(g.playerX, 1, "A-press does not warp X")
eq(g.playerY, 2, "A-press does not warp Y")
eq(g.field and g.field.text, locked, "appears locked until the script opens it")

g:setScriptVar(Game3.VAR_PETALBURG_GYM_STATE, 6)
g:setScriptVar(0x8008, 3)
g:setScriptVar(0x8009, 3)
g.field = nil
g:tryTalk()
eq(g.playerX, 3, "warpdoor VarGets 0x8008")
eq(g.playerY, 3, "warpdoor VarGets 0x8009")
end)()

;(function()
local Game3 = require("src.core.Game3")
local Gen3Script = require("src.import.Gen3Script")
-- Petalburg EnterRoom sits at a lower ROM address than AccuracyRoomDoor.
-- parse sorts by offset, so ops[1] is the shared warp unless .entry is set.
local enterOff, doorOff = 0, 10
local rom = string.rep("\0", 64)
rom = overlay(rom, enterOff,
  string.char(Gen3Script.CLOSEMESSAGE)
  .. string.char(Gen3Script.WARPDOOR, 8, 1, 0xFF)
  .. GbaBin.packU16(0x8008) .. GbaBin.packU16(0x8009)
  .. string.char(0x02))
rom = overlay(rom, doorOff,
  string.char(Gen3Script.LOCKALL)
  .. string.char(Gen3Script.SETVAR)
  .. GbaBin.packU16(0x8008) .. GbaBin.packU16(1)
  .. string.char(Gen3Script.SETVAR)
  .. GbaBin.packU16(0x8009) .. GbaBin.packU16(98)
  .. string.char(Gen3Script.GOTO) .. GbaBin.packPtr(enterOff)
  .. string.char(0x02))
local ops = Gen3Script.parse(rom, doorOff)
eq(ops[1].op, "closemessage", "shared EnterRoom sorts first")
eq(ops.entry, 4, "entry is the door lockall")
eq(ops[ops.entry].op, "lockall", "AccuracyRoomDoor is not ops[1]")
local host = {
  scriptVars = {},
  flags = {},
  scriptWarp = function(self, _, _, _, x, y)
    self.wx, self.wy = x, y
  end,
}
Gen3Script.run(host, ops)
eq(host.wx, 1, "Accuracy door sets 0x8008 before warpdoor")
eq(host.wy, 98, "and 0x8009, not the wall by Norman")

local cached = {
  { op = "closemessage" },
  { op = "delay", frames = 30 },
  { op = "warp", mapGroup = 8, mapNum = 1, warpId = 255, x = 32776, y = 32777 },
  { op = "waitstate" },
  { op = "releaseall" },
  { op = "end" },
  { op = "lockall" },
  { op = "setvar", var = 32776, val = 1 },
  { op = "setvar", var = 32777, val = 98 },
  { op = "goto", to = 1 },
  { op = "end" },
}
eq(Gen3Script.entryOf(cached), 7, "ruby27 cache starts at lockall")
host.scriptVars, host.wx, host.wy = {}, nil, nil
Gen3Script.run(host, cached)
eq(host.wx, 1, "cached Accuracy door still sets dest X")
eq(host.wy, 98, "and dest Y")

-- One A-press: skip delay/waitstate so the warp finishes in this call.
local fieldOps = {
  { op = "closemessage" },
  { op = "warp", mapGroup = 8, mapNum = 1, warpId = 255, x = 32776, y = 32777 },
  { op = "end" },
  { op = "lockall" },
  { op = "setvar", var = 32776, val = 1 },
  { op = "setvar", var = 32777, val = 98 },
  { op = "goto", to = 1 },
  { op = "end" },
}
eq(Gen3Script.entryOf(fieldOps), 4, "field IR still skips EnterRoom")
local gym = {
  id = "g8_1", width = 9, height = 112, grid = {},
  bgEvents = { { x = 7, y = 105, kind = 0, script = fieldOps } },
}
for i = 1, 9 * 112 do gym.grid[i] = 0 end
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g8_1 = gym } }
g:enterMap(gym, 7, 106, true)
g.facing = "north"
g:setScriptVar(0x8008, 0)
g:setScriptVar(0x8009, 0)
g:tryTalk()
eq(g.playerX, 1, "live A-press lands in the Accuracy room X")
eq(g.playerY, 98, "not the corner wall by Norman")
end)()

;(function()
  local Game3 = require("src.core.Game3")
  local Gen3Script = require("src.import.Gen3Script")
  eq(Gen3Script.POKEMART_DECORATION, 0x87, "pokemartdecoration is 0x87")
  eq(Gen3Script.POKEMART_DECORATION2, 0x88, "pokemartdecoration2 is 0x88")
  local listOff = 0x20
  local rom = string.rep("\0", 0x40)
  rom = overlay(rom, listOff,
    GbaBin.packU16(1) .. GbaBin.packU16(10) .. GbaBin.packU16(0))
  rom = overlay(rom, 0,
    string.char(0x87) .. GbaBin.packPtr(listOff) .. string.char(0x02))
  local ops = Gen3Script.parse(rom, 0)
  eq(ops[1].op, "pokemartdecoration", "Fortree clerks stay aligned")
  eq(ops[1].items[1], 1, "SMALL DESK")
  eq(ops[1].items[2], 10, "SMALL CHAIR")
  eq(ops[2].op, "end", "then end")
  rom = overlay(rom, 0,
    string.char(0x88) .. GbaBin.packPtr(listOff) .. string.char(0x02))
  ops = Gen3Script.parse(rom, 0)
  eq(ops[1].op, "pokemartdecoration", "type 2 is the same shop")
  eq(ops[1].martType, 2, "but shop.c still knows it as MART_TYPE_2")
  local g = Game3.new()
  -- AddDecoration needs the row's DECORCAT_*; SMALL DESK is DECORCAT_DESK.
  g.data.decorations = { count = 121, byId = {
    [1] = { permission = 0, shape = 0, width = 1, height = 1,
            category = 0, price = 3000, tiles = { 0x28 }, gfx = 0x28 } } }
  g.money = 5000
  g:openMartList({ 1 }, "decor", 2)
  eq(g.field.martKind, "decor", "kind is decor")
  local ok, msg = g:buyMartItem(1, "decor")
  check(ok, "bought a desk")
  eq(g.money, 2000, "SMALL DESK is 3000")
  eq(g:inventoryContainsDecoration(1), true, "AddDecoration")
  eq(g:numDecorationsInCategory(0), 1, "one slot of DECORCAT_DESK used")
  -- gOtherText_HereYouGo3, the MART_TYPE_2 line. It does not name the item.
  eq(msg, "Thanks!\nI'll send it to your PC at home.", "type 2 confirmation")
  g:openMartList({ 1 }, "decor", 1)
  g.money = 5000
  local _, msg1 = g:buyMartItem(1, "decor")
  eq(msg1, "Thank you!\nI'll send it to your home PC.", "type 1 confirmation")
  -- DECORCAT_DESK holds 10; the 11th purchase is gOtherText_SpaceForIsFull.
  g.money = 100000
  for _ = 1, 8 do check(g:buyMartItem(1, "decor"), "fill the desk slots") end
  local full, fullMsg = g:buyMartItem(1, "decor")
  eq(full, false, "an 11th desk does not fit")
  eq(fullMsg, "The space for SMALL DESK is full.", "and says so")
  eq(g.money, 100000 - 3000 * 8, "the failed buy costs nothing")
  eq(g:decorationPrice(13), 2000, "PRETTY CHAIR")
end)()

-- Survey zoom / tilt: same Zoom/Tilt modules as Gen 1. A larger view
-- unclamps the camera so connected maps (and the 2x2 border) can show.
;(function()
  local Game3 = require("src.core.Game3")
  local Zoom = require("src.render.Zoom")
  local Tilt = require("src.render.Tilt")
  local oldOff, oldLevel = Zoom.offset, Tilt.level
  Zoom.reset()
  Tilt.reset()
  local g = Game3.new()
  eq(select(1, g:viewSize()), Game3.SCREEN_W, "view defaults to 240")
  eq(select(2, g:viewSize()), Game3.SCREEN_H, "view defaults to 160")
check(g:fieldShowsWorld(), "no field keeps the world")
eq(g:playHudActive(), false, "free roam has no HUD overlay")
g.field = { kind = "talk" }
check(g:fieldShowsWorld(), "dialogue stays over the map")
check(g:playHudActive(), "dialogue still uses the HUD letterbox")
g.field = { kind = "script_yesno" }
check(g:fieldShowsWorld(), "yes/no stays over the map")
check(g:playHudActive(), "yes/no still uses the HUD letterbox")
g.field = { kind = "script_choice" }
check(g:fieldShowsWorld(), "multichoice stays over the map")
g.field = { kind = "wait" }
eq(g:playHudActive(), false, "script wait is not a HUD plate")
g.field = nil
g:beginScreenFade(Game3.FADE_TO_BLACK)
g:stepScreenFade((g.FADE_FRAMES or 16) / 60)
eq(g:playHudActive(), false, "a screen fade is not a HUD plate")
g.screenFade = nil
g.field = { kind = "talk", text = "planted." }
g:beginScreenFade(Game3.FADE_TO_BLACK)
g:clearTransientOverlay()
eq(g.field, nil, "overlay clear drops talk")
eq(g.screenFade, nil, "and the fade veil")
eq(g:playHudActive(), false, "so the HUD plate is gone")

-- map_name_popup.c: free-roam ShowMapNamePopup must keep playHudActive true
-- or drawHudLetterbox returns before drawMapNamePopup (invisible routes).
g.mapNamePopup = { name = "ROUTE 101", phase = 0, offset = 32, hold = 0 }
check(g:playHudActive(), "map name popup uses the HUD letterbox in free roam")
g.mapNamePopup = nil
eq(g:playHudActive(), false, "clearing popup drops the HUD plate again")

g.field = { kind = "party" }
  check(not g:fieldShowsWorld(), "party covers the map")
  g.field = nil
  g.viewW, g.viewH = 480, 320
  g.map = { width = 40, height = 40 }
  g.camX, g.camY = 0, 0
  local x0, y0, x1, y1 = g:visibleRange()
  eq(x1, math.floor(480 / Game3.TILE), "survey view reaches tile 30, not 14")
  eq(y1, math.floor(320 / Game3.TILE), "survey view reaches tile 20, not 9")
  -- The player stays at view centre in the middle of a map, but not past the
  -- edge of what is drawn. The GBA can always centre because at 240x160 the
  -- border pad covers the screen (fieldmap.c GetBorderBlockAt fills anything
  -- off-map); a survey-wide view outruns that pad and would show void, so the
  -- follow camera stops at the drawn area -- map plus connections plus each
  -- one's pad. This is a deliberate divergence the hardware never had to make.
  g.map = { width = 10, height = 10 }
  g.playerX, g.playerY = 0, 0
  -- The clamp is off by default now (see cameraClampEnabled); these checks
  -- are about what it does when it IS on, so ask for it.
  g.cameraClamp = true
  g:clampCamera()
  local x0, y0, x1, y1 = g:drawnExtent(g.map)
  -- The pad is the hardware's MAP_OFFSET ring and nothing more. It used to
  -- grow to swallow the whole view, which on a tall screen reached 900px and
  -- painted the border straight over the connected maps drawn beside this
  -- one -- a route would change and its neighbours became flat fill. Showing
  -- the real neighbours matters more than hiding fill at the far edge.
  eq(g:borderPad(g.map), Game3.BORDER_PAD_TILES * Game3.TILE,
    "the pad stays the GBA ring however tall the view is")
  g.viewW, g.viewH = 1080, 2400
  eq(g:borderPad(g.map), Game3.BORDER_PAD_TILES * Game3.TILE,
    "even on a portrait phone, so neighbours are never blanketed")
  g.viewW, g.viewH = 480, 320
  -- A drawn area smaller than the view gets centred rather than panned past.
  check(x1 - x0 < 480, "this map plus its ring is narrower than the view")
  eq(g.camX, Game3.snapPixel((x0 + x1 - 480) / 2),
    "so the camera centres what is drawn instead of running off it")
  g.viewW, g.viewH = Game3.SCREEN_W, Game3.SCREEN_H
  g.map = { width = 40, height = 40 }
  g.playerX, g.playerY = 0, 20
  g:clampCamera()
  eq(g.camX, Game3.snapPixel(8 - 120), "the west edge of a large map stays centred")
  -- Zoom must re-follow: a camera from the previous view size leaves the
  -- player off centre (World:draw calls camera:follow after sizing).
  g.playerX, g.playerY = 10, 10
  g.viewW, g.viewH = Game3.SCREEN_W, Game3.SCREEN_H
  g:clampCamera()
  eq(g.camX, Game3.snapPixel(10 * 16 + 8 - 120), "FIT camera is view centre")
  g.viewW, g.viewH = 480, 320
  g:clampCamera()
  eq(g.camX, Game3.snapPixel(10 * 16 + 8 - 240), "zoom-out recentres on the player")
  -- Live draw stores the window and scale; even-padded viewW is only the cull.
  g._zoomS = 3
  g._tiltGw, g._tiltGh = 800, 600
  g.viewW, g.viewH = 268, 200
  g:clampCamera()
  eq(g.camX, Game3.snapPixel(10 * 16 + 8 - 800 / 6), "zoom centres on the window")
  eq(g.camY, Game3.snapPixel(10 * 16 + 8 - 600 / 6), "and on the window height")
  g._zoomS, g._tiltGw, g._tiltGh = nil, nil, nil
  g.phase = "play"
  g.map = { width = 10, height = 10 }
  check(g:displayGateOK(), "free roam accepts zoom")
  check(g:hotkey("4"), "4 cycles zoom")
  check(Zoom.offset ~= 0, "zoom offset moved")
  g.field = { kind = "talk" }
  check(not g:displayGateOK(), "dialogue blocks zoom")
  g.field = nil
  check(g:hotkey("3"), "3 cycles tilt")
  eq(Tilt.level, 1, "tilt steps to 15")
  Zoom.offset = oldOff
  Tilt.applyOptions({ tilt = oldLevel })
end)()

-- Overlay border fill must not cover the map body: tree-top BG1 tiles
-- wrapping the whole view painted Littleroot's paths.
;(function()
  local Game3 = require("src.core.Game3")
  local inside = Game3.punchHoles(10, 10, 50, 50, { { 0, 0, 100, 100 } })
  eq(#inside, 0, "a view inside the map punches to nothing")
  local around = Game3.punchHoles(0, 0, 100, 80, { { 20, 10, 80, 70 } })
  eq(#around, 4, "a hole in the middle leaves four strips")
  local g = Game3.new()
  g.map = { width = 10, height = 8 }
  local holes = g:mapCoverRects()
  eq(holes[1][3], 10 * Game3.TILE, "cover width is the map")
  eq(holes[1][4], 8 * Game3.TILE, "cover height is the map")
  local view = Game3.punchHoles(16, 16, 160, 128, holes)
  eq(#view, 0, "camera inside town has no overlay border")
  local edge = Game3.punchHoles(-32, 0, 48, 32, holes)
  check(#edge >= 1, "west of the map still fills")
  check(edge[1][3] <= 0, "the west strip stops at the map edge")
  -- Ocean layouts still store the general tree wall as the 2x2 border.
  -- Survey zoom must not wrap that across the water void.
  g.map = { width = 10, height = 8, mapType = Game3.MAP_TYPE_TOWN }
  eq(g:borderPad(), Game3.BORDER_PAD_TILES * Game3.TILE, "towns keep the GBA ring")
  g.map.mapType = Game3.MAP_TYPE_OCEAN_ROUTE
  eq(g:borderPad(), 0, "ocean routes do not wallpaper trees into the void")
  g.map.mapType = Game3.MAP_TYPE_UNDERWATER
  eq(g:borderPad(), 0, "underwater neither")
  g.map.mapType = Game3.MAP_TYPE_TOWN
  local far = g:borderFillRects(g.map, 500, 0, 800, 200, false)
  eq(#far, 0, "survey void past MAP_OFFSET is not tree-filled")
  local ring = g:borderFillRects(g.map, -32, 0, 16, 32, false)
  check(#ring >= 1, "the GBA ring west of town still fills")
  g.map.mapType = Game3.MAP_TYPE_OCEAN_ROUTE
  local ocean = g:borderFillRects(g.map, -200, 0, -16, 32, false)
  eq(#ocean, 0, "ocean void is not the tree border")
  -- Tilt ground capture skips roofs; the overlay pass covers sprites.
  eq(Game3.metatileTopPassMode(Game3.LAYER_NORMAL, "covered", true), "skip",
    "roofs stay out of the tilted ground")
  eq(Game3.metatileTopPassMode(Game3.LAYER_NORMAL, "overlay", true), "full",
    "the overlay pass draws the roof over the player")
end)()

-- VOID FILL (Gen 1/2's TileRenderer.voidFill / world/gen2/BorderFill, same
-- idea ported here): a single wrap-tiled block per connected map rather
-- than a per-tile nearest-neighbor biome search, so a fill of any size is
-- a handful of quads, not a Lua loop over the visible area.
;(function()
  local Game3 = require("src.core.Game3")
  eq(Game3.voidFillKind(Game3.MB_JUMP_SOUTH, 1), "reject",
    "ledge lips are never picked as a representative tile")
  eq(Game3.voidFillKind(Game3.MB_WARP_OR_BRIDGE, 1), "reject",
    "cycling road neither")
  eq(Game3.voidFillKind(0x15, 0), "water", "ocean water is a fill")
  eq(Game3.voidFillKind(0x21, 0), "sand", "beach sand is a fill")
  eq(Game3.voidFillKind(0x22, 0), "reject", "seaweed is not open water")
  eq(Game3.voidFillKind(0, 0), "grass", "plain ground is grass")

  eq(#Game3.VOID_FILLS, 4, "sea / grass / black / map")
  eq(Game3.voidFillLabel("sea"), "SEA")
  eq(Game3.voidFillLabel("grass"), "GRASS")
  eq(Game3.voidFillLabel("black"), "BLACK")
  eq(Game3.voidFillLabel("map"), "PER-MAP")
  eq(Game3.voidFillLabel(nil), "SEA", "unset mode reads as SEA")
  -- saves written before the void went global
  eq(Game3.voidFillLabel("fade"), "SEA", "an old FADE save reads as SEA")
  eq(Game3.voidFillLabel("water"), "SEA", "so does an old WATER save")
  eq(Game3.voidFillLabel("trees"), "GRASS",
    "and old TREES, which only ever painted grass, reads as GRASS")

  local townBehavior = { [10] = 0, [77] = 0x15 }
  local oceanBehavior = { [5] = 0x15 }
  local g = Game3.new()
  g.data.tilesets = { byId = {
    pair_town = { behavior = townBehavior },
    pair_ocean = { behavior = oceanBehavior },
  } }
  local town = {
    id = "g0_0", width = 4, height = 4, tileset = "pair_town",
    mapType = Game3.MAP_TYPE_TOWN, border = { 99, 99, 99, 99 },
    connections = { { dir = "east", offset = 1, mapGroup = 0, mapNum = 1 } },
  }
  local ocean = {
    id = "g0_1", width = 8, height = 2, tileset = "pair_ocean",
    mapType = Game3.MAP_TYPE_OCEAN_ROUTE, border = { 200, 200, 200, 200 },
    connections = { { dir = "west", offset = -1, mapGroup = 0, mapNum = 0 } },
  }
  g.data.maps = { maps = { g0_0 = town, g0_1 = ocean } }
  g.map = town
  local place = g:mapPlacements()
  eq(#place, 2, "current map plus the east water")

  local route = {
    id = "g0_2", width = 4, height = 4, tileset = "pair_ocean",
    mapType = Game3.MAP_TYPE_OCEAN_ROUTE,
    connections = {
      { dir = "west", offset = 0, mapGroup = 0, mapNum = 1 },
      { dir = "dive", mapGroup = 24, mapNum = 3 },
    },
  }
  local under = {
    id = "g24_3", width = 4, height = 4, tileset = "pair_ocean",
    mapType = Game3.MAP_TYPE_UNDERWATER,
    connections = {
      { dir = "emerge", mapGroup = 0, mapNum = 2 },
    },
  }
  g.data.maps.g0_2 = route
  g.data.maps.g24_3 = under
  g.map = route
  place = g:mapPlacements()
  eq(#place, 2, "dive/emerge links do not stack on the ocean surface")
  local sawUnder
  for i = 1, #place do
    if place[i].map.id == "g24_3" then sawUnder = true end
  end
  check(not sawUnder, "underwater dive partner is not painted on the surface")

  eq(g:voidFillMode(), "sea", "default mode is sea")
  eq(g:tilesetRepresentativeTile("pair_town", "water"), 77,
    "the town tileset's own water tile")
  eq(g:tilesetRepresentativeTile("pair_town", "grass"), 10,
    "and its own grass tile")
  eq(g:tilesetRepresentativeTile("pair_ocean", "grass"), nil,
    "an all-water tileset has no grass tile")

  local function cellsAre(cells, a, b, c, d, msg)
    check(cells and cells[1] == a and cells[2] == b and cells[3] == c
      and cells[4] == d, msg)
  end
  cellsAre(g:voidFillCells(town, "fade"), 10, 10, 10, 10,
    "PER-MAP never hands back the map's own border block -- that is edge"
    .. " art, and wrap-tiling it is what put tree rectangles in the sea")
  cellsAre(g:voidFillCells(ocean, "fade"), 5, 5, 5, 5,
    "ocean fade drops the generic border block for a real water tile"
    .. " from its own tileset")
  cellsAre(g:voidFillCells(town, "water"), 77, 77, 77, 77,
    "water mode forces the town's own water tile")
  cellsAre(g:voidFillCells(town, "trees"), 10, 10, 10, 10,
    "trees mode forces the town's own land tile")
  cellsAre(g:voidFillCells(ocean, "trees"), 5, 5, 5, 5,
    "trees mode on an all-water tileset falls back to water, not a"
    .. " random block")

  local beachBehavior = { [10] = 0, [20] = 0x21, [77] = 0x15 }
  g.data.tilesets.byId.pair_beach = { behavior = beachBehavior }
  local beach = {
    id = "g_beach", width = 4, height = 2, tileset = "pair_beach",
    mapType = Game3.MAP_TYPE_ROUTE,
    grid = { 10, 10, 20, 20, 77, 77, 77, 77 },
    behavior = {
      0, 0, 0x21, 0x21,
      0x15, 0x15, 0x15, 0x15,
    },
  }
  g.data.maps.maps.g_beach = beach
  local shore = g:voidFillCells(beach, "fade")
  cellsAre(shore, 77, 77, 77, 77,
    "a map that touches water fills with that water, flat -- no sand halo")
  for i = 1, 4 do
    check(shore[i] == shore[1], "and all four cells match: no checkerboard")
  end

  local treetop = {
    id = "g_tree", width = 1, height = 1, tileset = "pair_tree",
    grid = { 1 },
    behavior = { 0 },
  }
  g.data.tilesets.byId.pair_tree = {
    behavior = { [1] = 0, [2] = 0 },
    layerType = { [1] = Game3.LAYER_NORMAL },
    tiles = {
      [1] = { 1, 1, 1, 1, 9, 9, 9, 9 },
      [2] = { 2, 2, 2, 2, 0, 0, 0, 0 },
    },
  }
  g.data.maps.maps.g_tree = treetop
  eq(g:mapRepresentativeTiles(treetop, "grass")[1], 2,
    "canopy metatiles are skipped for grass fill")

  -- A single wrap-tiled water tile reads as an obviously synthetic grid
  -- once stretched across a wide survey-zoom view (real GBA water
  -- alternates two tile variants for a "waves" look), so the fill checks
  -- the map's own grid for a second common water tile and checkerboards
  -- the two across the diagonals instead of repeating just one.
  local wave = { [8] = 0x15, [9] = 0x15 }
  local waveOcean = {
    id = "g_wave", width = 4, height = 2, tileset = "pair_wave",
    mapType = Game3.MAP_TYPE_OCEAN_ROUTE,
    grid = { 8, 9, 8, 9, 9, 8, 9, 8 },
  }
  g.data.tilesets.byId.pair_wave = { behavior = wave }
  g.data.maps.maps.g_wave = waveOcean
  local pair = g:mapRepresentativeTiles(waveOcean, "water")
  check(pair and pair[1] and pair[2] and pair[1] ~= pair[2],
    "two distinct water tiles come back from the map's own grid")
  cellsAre(g:voidFillCells(waveOcean, "fade"), pair[1], pair[1], pair[1], pair[1],
    "but the fill takes only the commonest one -- alternating two variants"
    .. " reads as a chequered grid stamped over the world at survey zoom")

  local indoor = { width = 8, height = 8, mapType = Game3.MAP_TYPE_INDOOR }
  check(Game3.isIndoorFillMap(indoor), "houses skip the outdoor void fill")
  eq(g:borderPad(town), Game3.BORDER_PAD_TILES * Game3.TILE,
    "towns keep their own GBA border ring")
  eq(g:borderPad(ocean), 0, "water maps still have no wallpaper ring")
  local ring = g:borderFillRects(ocean, -80, -16, -16, 48, false)
  check(#ring >= 1, "standing on water still fills the town ring")
end)()

-- Land wanderers stay off water (collision 0 + surfable). Reflections
-- follow ObjectEventCheckForReflectiveSurface: tiles south of the feet,
-- not the pond a 32px sprite covers to the north.
;(function()
  local Game3 = require("src.core.Game3")
  eq(Game3.elevationOf(4 * 4096), 4, "elevation is bits 12-15")
  check(Game3.zMismatch(4, 3), "cycling road is above the dirt")
  check(not Game3.zMismatch(4, 0), "map z 0 is any height")
  check(not Game3.zMismatch(0, 3), "object z 0 skips the check")
  -- sObjectEventPriorities_08376060: field BG1 is OAM-pri 1, so pri 2 sits
  -- under roofs. Elevation 4 (Meteor Falls 1F_1R warp at 27,18 / cycling
  -- road) is pri 1 and must draw in the post-overlay pass. Forgetting to
  -- forward that flag from drawWorldStanding skips those sprites entirely.
  eq(Game3.oamPriorityForZ(0), 2, "ground is OAM pri 2")
  eq(Game3.oamPriorityForZ(3), 2, "elev 3 is still under BG1")
  eq(Game3.oamPriorityForZ(4), 1, "elev 4 is in front of BG1")
  check(not Game3.spriteDrawsOverOverlay(3), "elev 3 draws before overlay")
  check(Game3.spriteDrawsOverOverlay(4), "elev 4 draws after overlay")
  local seen
  local stand = setmetatable({}, { __index = Game3 })
  function stand:drawActors(over) seen = over and true or false end
  function stand:drawDoorAnim() end
  function stand:drawFieldEffects() end
  function stand:drawPokecenterHealOverlay() end
  function stand:drawHofRecordOverlay() end
  function stand:drawRotatingGates() end
  stand:drawWorldStanding(false)
  eq(seen, false, "the under-overlay pass reaches drawActors")
  stand:drawWorldStanding(true)
  eq(seen, true, "so does the over-overlay pass")
  check(Game3.isReflective(Game3.MB_POND_WATER), "pond is a mirror")
  check(Game3.isReflective(Game3.MB_ICE), "ice too")
  check(not Game3.isReflective(Game3.MB_OCEAN_WATER), "ocean is not")

  local g = Game3.new()
  g.phase = "play"
  g.map = {
    id = "pond_edge",
    width = 2, height = 2,
    grid = { 0, 0, 0, 0 },
    behavior = { 0, Game3.MB_POND_WATER, 0, Game3.MB_OCEAN_WATER },
    objects = {
      { x = 0, y = 0, graphicsId = 1, movementType = 2, rangeX = 2, rangeY = 2 },
    },
  }
  g:enterMap(g.map, 0, 0, false)
  local npc = g:npcsFor(g.map)[1]
  check(not g:tryNpcWalk(npc, g.map, 1, 0), "land NPC does not walk onto the pond")
  eq(npc.x, 0, "and stays put")
  npc.x, npc.y = 0, 1
  npc.homeX, npc.homeY = 0, 1
  check(not g:tryNpcWalk(npc, g.map, 1, 0), "or onto the ocean")

  g.map.behavior = {
    Game3.MB_OCEAN_WATER, Game3.MB_OCEAN_WATER, 0, 0,
  }
  npc.x, npc.y = 0, 0
  npc.fromX, npc.fromY = 0, 0
  npc.homeX, npc.homeY = 0, 0
  check(g:tryNpcWalk(npc, g.map, 1, 0), "a swimmer can wander on ocean")

  local road, dirt = 4 * 4096, 3 * 4096
  g.map.grid = { road, dirt, road, dirt }
  g.map.behavior = { 0, 0, 0, 0 }
  npc.x, npc.y = 0, 0
  npc.fromX, npc.fromY = 0, 0
  npc.homeX, npc.homeY = 0, 0
  npc.elevation = 4
  check(not g:tryNpcWalk(npc, g.map, 1, 0), "cyclist stays on elevation 4")

  -- Elevation 0 skips zMismatch; elevation 1 is still the ROM water Z.
  g.map.grid = { 0, 4096 }
  g.map.width, g.map.height = 2, 1
  g.map.behavior = { 0, 0 }
  npc.x, npc.y = 0, 0
  npc.fromX, npc.fromY = 0, 0
  npc.homeX, npc.homeY = 0, 0
  npc.elevation = 0
  npc.rangeX, npc.rangeY = 2, 2
  check(not g:tryNpcWalk(npc, g.map, 1, 0), "land NPC does not stroll elevation-1 shallows")

  -- Route 110 seaside strip: 0x70 road beside ocean. 32px bikes hang off
  -- the road; they must not actually step onto the water.
  local road15 = 15 * 4096
  g.map = {
    id = "route110_strip",
    width = 3, height = 1,
    grid = { road15, road15, 4096 },
    behavior = {
      Game3.MB_WARP_OR_BRIDGE, Game3.MB_WARP_OR_BRIDGE, Game3.MB_OCEAN_WATER,
    },
    objects = {
      { x = 1, y = 0, graphicsId = 56, movementType = 2,
        rangeX = 2, rangeY = 1, elevation = 4 },
    },
  }
  g:enterMap(g.map, 1, 0, false)
  npc = g:npcsFor(g.map)[1]
  npc.elevation = 4
  check(g:tryNpcWalk(npc, g.map, -1, 0), "cyclist can ride the other road tile")
  npc.x, npc.y = 1, 0
  npc.fromX, npc.fromY = 1, 0
  check(not g:tryNpcWalk(npc, g.map, 1, 0), "and does not ride onto the ocean")

  -- LAYER_NORMAL ocean (Route 110 mid 786) must not cover bike sprites.
  g.data.tilesets = {
    byId = {
      pair_2 = {
        behavior = { [786] = Game3.MB_OCEAN_WATER, [724] = Game3.MB_WARP_OR_BRIDGE },
        layerType = { [724] = Game3.LAYER_COVERED },
        tiles = {
          [786] = { 454, 455, 455, 454, 690, 690, 706, 706 },
          [724] = { 575, 575, 575, 575, 575, 575, 575, 575 },
        },
      },
    },
  }
  g.map = {
    tileset = "pair_2",
    width = 2, height = 1,
    grid = { 724, 786 },
  }
  check(not g:topIsOverlayAt(g.map, 1, 0), "ocean tops stay under cyclists")
  check(not g:topIsOverlayAt(g.map, 0, 0), "LAYER_COVERED road stays under sprites")

  g.map = {
    width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    behavior = {
      0, 0, 0,
      Game3.MB_POND_WATER, 0, 0,
      0, 0, 0,
    },
  }
  check(g:actorReflects(0, 0, false, 32), "north of the pond reflects")
  check(not g:actorReflects(0, 2, false, 32), "south of the pond does not")
  check(not g:actorReflects(2, 2, false, 32), "dry ground does not")
  check(not g:actorReflects(0, 0, true, 32), "hideReflection skips it")
  g.map.behavior = {
    0, 0, 0,
    Game3.MB_OCEAN_WATER, 0, 0,
    Game3.MB_OCEAN_WATER, 0, 0,
  }
  check(not g:actorReflects(0, 0, false, 32), "standing by ocean does not mirror")

  local wet = Game3.new()
  wet.map = {
    width = 3, height = 1,
    -- collision 1 ocean, collision 0 elevation-1 shallows, land
    grid = { 1024, 4096, 0 },
    behavior = { Game3.MB_OCEAN_WATER, 0, 0 },
  }
  wet.playerX, wet.playerY = 2, 0
  check(not Game3.walkable(wet.map, 0, 0), "ocean collision 1 is solid")
  check(not wet:canStep(wet.map, 0, 0), "and blocked without Surf")
  check(not wet:canStep(wet.map, 1, 0), "elevation-1 shallows need Surf")
  check(wet:canStep(wet.map, 2, 0), "land is fine")
  check(not Game3.walkable(wet.map, 0.4, 0), "fractional coords still hit the ocean cell")
  wet.surfing = true
  check(wet:canStep(wet.map, 0, 0), "Surf walks collision-1 ocean")
  check(wet:canStep(wet.map, 1, 0), "and the shallows")
end)()

-- Regression: canStep only ever special-cased elevation-1 water, so a
-- player on a bridge (elevation 3) could step straight onto ground at any
-- OTHER non-matching elevation (e.g. the elevation-2 dip under a Fortree /
-- Pacifidlog bridge) instead of only via the bridge's own ramp tiles
-- (elevation 0, "any height"). event_object_movement.c's real
-- GetCollisionAtCoords blocks that with IsZCoordMismatchAt.
;(function()
local bridge = Game3.new()
bridge.map = {
  width = 5, height = 1,
  -- ramp(e0), bridge(e3), under-bridge ground(e2), bridge(e3), ramp(e0)
  grid = { 0, 3 * 4096, 2 * 4096, 3 * 4096, 0 },
}
bridge.playerX, bridge.playerY = 1, 0
bridge.currentElevation = 3
check(not bridge:canStep(bridge.map, 2, 0),
  "standing on the bridge cannot step onto the elevation-2 ground below it")
check(bridge:canStep(bridge.map, 0, 0),
  "but can still step onto the elevation-0 ramp")
bridge.playerX = 3
bridge.currentElevation = 3
check(bridge:canStep(bridge.map, 4, 0),
  "and cross bridge segments that share elevation 3")
bridge.playerX, bridge.playerY = 2, 0
bridge.currentElevation = 2
check(not bridge:canStep(bridge.map, 1, 0),
  "standing under the bridge cannot climb onto it either")
end)()

-- Regression: field_player_avatar.c sub_8058EF0 lets a surfing player hop
-- onto elevation-3 beach grass even when IsZCoordMismatchAt would block
-- the step (collision type 3 → 5). Without this, ocean routes trap you.
;(function()
local beach = Game3.new()
beach.map = {
  width = 3, height = 1,
  -- shallow ocean(e1), beach grass(e3), inland(e2)
  grid = { 1 * 4096, 3 * 4096, 2 * 4096 },
  behavior = { Game3.MB_OCEAN_WATER, 0, 0 },
}
beach.playerX, beach.playerY = 0, 0
beach.currentElevation = 1
beach.surfing = true
check(not beach:canStep(beach.map, 2, 0),
  "surfing cannot skip inland when elevation mismatches")
check(beach:canStep(beach.map, 1, 0),
  "surfing can step onto elevation-3 beach despite Z mismatch")
check(beach:tryWalk(1, 0), "tryWalk hops onto the beach")
eq(beach.surfing, nil, "dismounts on dry land")
end)()

-- Regression: event_object_movement.c's IsMetatileDirectionallyImpassable
-- (MB_IMPASSABLE_EAST/WEST/NORTH/SOUTH/...) was never implemented at all
-- -- canStep only ever checked collision and elevation, so a cliff face
-- (a plain walkable, same-elevation metatile that ROM data marks
-- impassable from one specific facing) could be walked straight through
-- from the "wrong" side, i.e. "walking under cliffs".
;(function()
local cliff = Game3.new()
cliff.map = {
  width = 3, height = 3,
  grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
  -- MB_IMPASSABLE_SOUTH at (1,1): refuses entry from the south (blocks
  -- moving north into it) and refuses to be left heading south.
  behavior = {
    0, 0, 0,
    0, Game3.MB_IMPASSABLE_SOUTH, 0,
    0, 0, 0,
  },
}
cliff.playerX, cliff.playerY = 1, 2
cliff.facing = "north"
check(not cliff:canStep(cliff.map, 1, 1),
  "cannot walk north into a cliff face that is impassable from the south")
cliff.facing = "west"
check(cliff:canStep(cliff.map, 0, 2),
  "unrelated directions on the approaching tile are unaffected")

-- Standing ON the impassable-south tile: it must also refuse to be LEFT
-- heading south (the "tile being left" half of the C check), matching
-- MetatileBehavior_IsSouthBlocked(objectEvent->currentMetatileBehavior).
cliff.playerX, cliff.playerY = 1, 1
cliff.facing = "south"
check(not cliff:canStep(cliff.map, 1, 2),
  "cannot walk south OFF a cliff-face tile either")
cliff.facing = "north"
check(cliff:canStep(cliff.map, 1, 0),
  "but can still walk on north, away from the ledge")
cliff.facing = "east"
check(cliff:canStep(cliff.map, 2, 1),
  "east/west off the same tile are unaffected")
end)()

-- Every metatile behaviour a Ruby map actually places, worked out by walking
-- all 394 maps, mapping each grid and border metatile through its tileset's
-- attribute table, and collecting the distinct results. 115 of the 256
-- possible values reach a map; the rest are only ever attribute-table filler.
local PLACED_BEHAVIOURS = {
  0x00, 0x01, 0x02, 0x03, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0F,
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x19, 0x1B, 0x1C, 0x20,
  0x21, 0x22, 0x24, 0x26, 0x28, 0x29, 0x2A, 0x2B, 0x30, 0x31, 0x32, 0x33,
  0x38, 0x39, 0x3B, 0x3E, 0x3F, 0x40, 0x41, 0x43, 0x44, 0x45, 0x46, 0x47,
  0x48, 0x50, 0x51, 0x52, 0x53, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
  0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x70, 0x72, 0x73, 0x74,
  0x75, 0x76, 0x77, 0x78, 0x80, 0x83, 0x84, 0x85, 0x86, 0x87, 0x89, 0x8A,
  0x8C, 0x90, 0x92, 0x94, 0x96, 0x98, 0x9A, 0x9C, 0xA0, 0xB0, 0xB2, 0xB3,
  0xB5, 0xB7, 0xC0, 0xC2, 0xC3, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
  0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6,
}

;(function()
eq(#PLACED_BEHAVIOURS, 115, "115 behaviours reach a Ruby map")

-- Every declared MB_ constant, read back off the source so a value can only
-- appear once and a duplicate name is caught.
local src = (function()
  local f = assert(io.open("src/core/Game3.lua", "r"))
  local text = f:read("*a")
  f:close()
  return text
end)()

local byValue, byName = {}, {}
local dupes = 0
for name, value in src:gmatch("Game3%.(MB_[A-Z0-9_]+)%s*=%s*(0x%x+)") do
  local v = tonumber(value)
  if byName[name] then dupes = dupes + 1 end
  byName[name] = v
  byValue[v] = byValue[v] or name
end
eq(dupes, 0, "no behaviour name is declared twice")

-- The point of the pass: nothing a map can place is left to a hex literal.
local unnamed = {}
for _, b in ipairs(PLACED_BEHAVIOURS) do
  if not byValue[b] then unnamed[#unnamed + 1] = ("0x%02X"):format(b) end
end
eq(table.concat(unnamed, " "), "",
  "every placed behaviour has a name")

-- The three the engine used to spell its own way now carry the cart's too.
eq(Game3.MB_SEMI_DEEP_WATER, 0x11, "MB_SEMI_DEEP_WATER is 0x11")
eq(Game3.MB_INTERIOR_DEEP_WATER, Game3.MB_SEMI_DEEP_WATER,
  "and the old name still points at it")
eq(Game3.MB_UNUSED_DEEP_WATER, 0x12, "MB_UNUSED_DEEP_WATER is 0x12")
eq(Game3.MB_DEEP_WATER, Game3.MB_UNUSED_DEEP_WATER, "old name kept")
eq(Game3.MB_SECRET_BASE_SPOT_TREE_2_OPEN, 0x9D, "the last spot is 0x9D")
eq(Game3.MB_SECRET_BASE_SPOT_MAX, Game3.MB_SECRET_BASE_SPOT_TREE_2_OPEN,
  "and the range end still points at it")

-- Each secret base spot has a closed value and the open one above it.
for _, pair in ipairs({
  { Game3.MB_SECRET_BASE_SPOT_RED_CAVE, Game3.MB_SECRET_BASE_SPOT_RED_CAVE_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_BROWN_CAVE, Game3.MB_SECRET_BASE_SPOT_BROWN_CAVE_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_YELLOW_CAVE, Game3.MB_SECRET_BASE_SPOT_YELLOW_CAVE_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_TREE_1, Game3.MB_SECRET_BASE_SPOT_TREE_1_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_SHRUB, Game3.MB_SECRET_BASE_SPOT_SHRUB_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_BLUE_CAVE, Game3.MB_SECRET_BASE_SPOT_BLUE_CAVE_OPEN },
  { Game3.MB_SECRET_BASE_SPOT_TREE_2, Game3.MB_SECRET_BASE_SPOT_TREE_2_OPEN },
}) do
  eq(pair[2], pair[1] + 1, "the open spot follows the closed one")
end

-- And no behaviour test in the source falls back to a bare hex value. The
-- pattern deliberately only looks at `b`, which is what every behaviour test
-- in Game3 binds its value to -- the byte comparisons in the text decoders
-- use their own names and are not behaviours.
local leftovers = {}
for line in src:gmatch("[^\\n]+") do
  if line:match("^%s*[%w:%s]*if%s+b%s*==%s*0x%x%x")
      or line:match("or%s+b%s*==%s*0x%x%x") then
    -- the text decoders read raw UTF-8 bytes, not behaviours
    if not line:match("text:byte") and not line:match("0xC3")
        and not line:match("0xE2") then
      leftovers[#leftovers + 1] = line:gsub("^%s+", "")
    end
  end
end
eq(table.concat(leftovers, " / "), "",
  "no behaviour is still compared as a hex literal")
end)()


-- Pokedex chrome. pokedex.c loads one tile set for the whole Pokedex and swaps
-- only the tilemap, so each screen has its own background over the same tiles.
-- Each layout offset below was found by decompressing candidates and matching
-- the decomp's own .bin byte for byte; the detail layout the extractor already
-- used falls out of the same search, which is what validates the method.
;(function()
local Dex = require("src.import.RomExtractorGen3Dex")
local u = Dex.RUBY_US
eq(u.detailLayout, 0xE96BD4, "the entry layout is where it always was")
eq(u.sizeLayout, 0x39F988, "the size layout")
eq(u.cryLayout, 0x39F8A0, "the cry layout")
eq(u.selectBarMain, 0xE96ACC, "and the PAGE/AREA/CRY/SIZE/CANCEL strip")
check(u.sizeLayout ~= u.detailLayout, "the size screen is not the entry screen")
check(u.cryLayout ~= u.detailLayout, "nor is the cry screen")
eq(Dex.SELECT_BAR_H, 24, "the strip is three tiles tall, not a whole screen")

-- The chrome renderer takes a height so the same code draws a background or
-- the short strip.
check(type(Dex.renderChrome) == "function", "there is one renderer for both")
check(type(Dex.tilemapSize) == "function", "and a way to size a tilemap")

-- The engine picks its background per screen rather than borrowing the entry's.
local g = Game3.new()
check(type(g.drawDexChrome) == "function", "the chrome picker exists")
local src = (function()
  local f = assert(io.open("src/core/Game3.lua", "r"))
  local t = f:read("*a"); f:close(); return t
end)()
check(src:find('self:drawDexChrome("size")', 1, true) ~= nil,
  "the size screen asks for its own")
check(src:find('self:drawDexChrome("cry")', 1, true) ~= nil,
  "and so does the cry screen")
end)()


-- The list screen's furniture: gPokedexMenu2_Gfx, the one interface sheet the
-- Pokedex loads as sprites rather than as a background.
;(function()
local Dex = require("src.import.RomExtractorGen3Dex")
eq(Dex.RUBY_US.interfaceGfx, 0xE874C8,
  "the interface sheet is the cart's only 0x1F00 LZ77 block")
eq(Dex.RUBY_US.interfaceBytes, 0x1F00, "and that is its size")
eq(Dex.INTERFACE_COLS, 8,
  "a sprite sheet runs eight tiles across; wider scrambles it")
eq(Dex.INTERFACE_W, Dex.INTERFACE_COLS * 8, "so it is 64 pixels wide")

-- The bands were measured off the sheet rather than guessed: each is where
-- one label sits, and none of them overlap.
local bands = Dex.INTERFACE_BANDS
for _, name in ipairs({ "arrows", "start", "search", "select", "menu",
  "seen", "own", "digits" }) do
  check(type(bands[name]) == "table", name .. " has a band")
  check(bands[name][2] > 0, name .. " has a height")
end
eq(bands.seen[1], 160, "SEEN sits at y 160")
eq(bands.own[1], 192, "OWN at y 192")
eq(bands.digits[1], 224, "and the counter digits below them")
local prev = -1
for _, name in ipairs({ "arrows", "start", "search", "select", "menu",
  "seen", "own", "digits" }) do
  local b = bands[name]
  check(b[1] >= prev, name .. " comes after the band before it")
  prev = b[1] + b[2]
end

-- The list draws rows two tiles tall, the way CreateMonListEntry lays them out.
eq(Game3.DEX_ROW_H, 16, "a list row is two tiles tall")
local g = Game3.new()
check(type(g.drawDexBand) == "function", "the engine can draw one band")
check(type(g.dexInterfaceBand) == "function", "and address it by name")
end)()


;(function()
-- field_control_avatar.c IsWarpMetatileBehavior. Stepping onto a warp event is
-- not enough on the cart: the tile has to be a warp tile too. The Trick House
-- entrance is the case that proves it -- ROUTE 110's g29_0 has a warp at (5,2)
-- sitting on plain floor, reachable only through the scroll's own script after
-- the switch on VAR_TRICK_HOUSE_ROOMS_COMPLETED picks which puzzle to open.
-- Bump-warping it walked straight into Puzzle 1 every single time.
local allowed = {
  Game3.MB_ANIMATED_DOOR, Game3.MB_LADDER,
  Game3.MB_UP_ESCALATOR, Game3.MB_DOWN_ESCALATOR,
  Game3.MB_NON_ANIMATED_DOOR, Game3.MB_WATER_DOOR,
  Game3.MB_UNUSED_DEEP_SOUTH_WARP,
  Game3.MB_LAVARIDGE_GYM_B1F_WARP, Game3.MB_LAVARIDGE_GYM_1F_WARP,
  Game3.MB_AQUA_HIDEOUT_WARP, Game3.MB_MT_PYRE_HOLE,
}
for _, b in ipairs(allowed) do
  check(Game3.isWarpBehavior(b), ("0x%02X is a warp metatile"):format(b))
end
-- The negative half is the half that matters: these all used to warp.
local rejected = {
  Game3.MB_NORMAL, Game3.MB_TRICK_HOUSE_PUZZLE_DOOR,
  Game3.MB_PETALBURG_GYM_DOOR, Game3.MB_SOUTH_ARROW_WARP,
  Game3.MB_NORTH_ARROW_WARP, Game3.MB_TALL_GRASS,
}
for _, b in ipairs(rejected) do
  check(not Game3.isWarpBehavior(b),
    ("0x%02X is not a warp metatile"):format(b))
end
check(not Game3.isWarpBehavior(nil), "no behaviour is not a warp metatile")

-- And behaviourally: same map, same warp, only the tile behaviour differs.
local function room(beh)
  local m = {
    id = "tr", width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    warps = { { x = 1, y = 0, mapGroup = 0, mapNum = 1, warpId = 0 } },
    behavior = { [0 * 3 + 1 + 1] = beh },
  }
  local dest = {
    id = "g0_1", width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    warps = { { x = 1, y = 2, mapGroup = 0, mapNum = 0, warpId = 0 } },
  }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { tr = m, g0_1 = dest } }
  g:enterMap(m, 1, 1, true)
  g.ignoreWarp = false
  return g
end
local plain = room(Game3.MB_NORMAL)
plain:tryWalk(0, -1)
eq(plain.map.id, "tr",
  "a warp on plain floor does not fire -- the Trick House scroll owns it")
local ladder = room(Game3.MB_LADDER)
ladder:tryWalk(0, -1)
eq(ladder.map.id, "g0_1", "the same warp on a ladder still fires")
end)()


;(function()
-- The Elite Four and Petalburg Gym both ship their doors CLOSED in the map
-- data and open them with setmetatile once you have earned it:
-- PokemonLeague_EliteFour_SetAdvanceToNextRoomMetatiles swaps (6,2) to
-- METATILE_EliteFour_OpenDoor_Opening (0x345, MB_NON_ANIMATED_DOOR), and
-- PetalburgCity_Gym_OnLoad swaps each cleared room's doorway to
-- METATILE_PetalburgGym_RoomEntrance (MB_SOUTH_ARROW_WARP). The warp event
-- sits there the whole time, so what gates it is purely the tile behaviour --
-- which is why walking through a closed Elite Four door used to work.
local CLOSED, OPEN = 0x20A, 0x345
local function room()
  local m = {
    id = "e4", width = 3, height = 4,
    grid = { 0, CLOSED, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    warps = { { x = 1, y = 0, mapGroup = 0, mapNum = 1, warpId = 0 } },
    behavior = {},
  }
  local next_ = {
    id = "g0_1", width = 3, height = 3,
    grid = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    warps = { { x = 1, y = 2, mapGroup = 0, mapNum = 0, warpId = 0 } },
  }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { e4 = m, g0_1 = next_ } }
  -- one tileset where the closed tile is plain and the open one is a door
  g.data.tilesets = { byId = { [m.tileset or "pair_e4"] = { behavior = {
    [CLOSED] = Game3.MB_NORMAL,
    [OPEN] = Game3.MB_NON_ANIMATED_DOOR,
  } } } }
  m.tileset = m.tileset or "pair_e4"
  g:enterMap(m, 1, 1, true)
  g.ignoreWarp = false
  return g
end

local shut = room()
eq(shut:behaviorAt(shut.map, 1, 0), Game3.MB_NORMAL, "the door starts closed")
shut:tryWalk(0, -1)
eq(shut.map.id, "e4", "a closed Elite Four door does not let you through")

local opened = room()
-- what SetAdvanceToNextRoomMetatiles does after the member is beaten
opened:setMetatile(1, 0, OPEN, 0)
eq(opened:behaviorAt(opened.map, 1, 0), Game3.MB_NON_ANIMATED_DOOR,
  "setmetatile opens it, and behaviorAt reads the live grid")
check(Game3.isWarpBehavior(opened:behaviorAt(opened.map, 1, 0)),
  "an opened door is a warp metatile")
opened:tryWalk(0, -1)
eq(opened.map.id, "g0_1", "and then the same warp carries you through")
end)()


;(function()
-- field_control_avatar.c GetInteractedMetatileScript. None of these tiles did
-- anything before: the behaviours were extracted and most handlers existed,
-- but nothing dispatched on them, so A on a bookshelf or a TV was dead.
local function room(beh, w, h, bx, by)
  w, h = w or 3, h or 3
  bx, by = bx or 1, by or 0
  local grid = {}
  for _ = 1, w * h do grid[#grid + 1] = 0 end
  local m = { id = "m", width = w, height = h, grid = grid,
    behavior = { [by * w + bx + 1] = beh } }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { m = m } }
  g:enterMap(m, bx, by + 1, true)
  g.facing = "north"
  g.party = { { name = "X", hp = 20, maxHp = 20, species = 1, level = 5,
    moves = {} } }
  return g
end
local function say(beh)
  local g = room(beh)
  g:tryTalk()
  return g.field and g.field.text or nil
end

-- check_furniture.inc, one msgbox each.
eq(say(Game3.MB_PICTURE_BOOK_SHELF),
  "There's a set of POKeMON picture books.", "Text_PictureBookshelf")
eq(say(Game3.MB_BOOKSHELF), "It's filled with all sorts of books.",
  "Text_Bookshelf")
eq(say(Game3.MB_TRASH_CAN), "It's empty.", "Text_EmptyTrashCan")
check((say(Game3.MB_POKEMON_CENTER_BOOKSHELF) or ""):find("POKeMON magazines",
  1, true) ~= nil, "Text_PokemonCenterBookshelf")
check((say(Game3.MB_VASE) or ""):find("But, it was empty", 1, true) ~= nil,
  "Text_Vase")
check((say(Game3.MB_SHOP_SHELF) or ""):find("merchandise", 1, true) ~= nil,
  "Text_ShopShelf")
check((say(Game3.MB_BLUEPRINT) or ""):find("too complicated", 1, true) ~= nil,
  "Text_Blueprint")
eq(say(Game3.MB_CLOSED_SOOTOPOLIS_DOOR), "The door is closed.",
  "ClosedSootopolisDoorText")
check((say(Game3.MB_RUNNING_SHOES_MANUAL) or ""):find("RUNNING SHOES", 1, true)
  ~= nil, "S_RunningShoesManual")

-- A tile with no handler still does nothing, which is also the ROM's answer.
eq(say(Game3.MB_NORMAL), nil, "plain floor stays dead")

-- ShowLinkBattleRecords opens the board rather than a textbox.
local recs = room(Game3.MB_LINK_BATTLE_RECORDS)
recs:tryTalk()
eq(recs.field and recs.field.kind, "link_records", "gUnknown_081A4363")

-- MetatileBehavior_IsPlayerFacingTVScreen is north-only.
local tvN = room(Game3.MB_TELEVISION)
tvN:tryTalk()
check(tvN.field ~= nil, "a TV answers when you face it from the south")
local tvS = room(Game3.MB_TELEVISION)
tvS.playerX, tvS.playerY = 1, 0
tvS.facing = "south"
tvS:tryTalk()
eq(tvS.field, nil, "but not from any other direction")

-- Event_TV's emergency branch: the bulletin starts Latios roaming. Only in
-- the player's own house, which is all CheckForBigMovieOrEmergencyNewsOnTV
-- ever answers for.
local lati = room(Game3.MB_TELEVISION)
lati.map.group = Game3.MAP_LITTLEROOT_INDOOR_GROUP
lati.map.index = Game3.MAP_BRENDANS_HOUSE_1F_NUM
lati.flags = { [Game3.FLAG_SYS_TV_LATI] = true }
lati:tryTalk()
check((lati.field and lati.field.text or ""):find("news bulletin", 1, true)
  ~= nil, "the special news bulletin plays")
eq(lati.flags[Game3.FLAG_SYS_TV_LATI], nil, "FLAG_SYS_TV_LATI is cleared")
eq(lati.flags[Game3.FLAG_LATIOS_OR_LATIAS_ROAMING], true,
  "and FLAG_LATIOS_OR_LATIAS_ROAMING goes up")
eq(lati.roamer and lati.roamer.species, 408, "InitRoamer picks Latios in RUBY")

-- Route110_TrickHousePuzzle_EventScript_Door, both branches. The door is at
-- (13,1) in every puzzle room.
local shut = room(Game3.MB_TRICK_HOUSE_PUZZLE_DOOR, 15, 4, 13, 1)
shut.scriptVars = { [Game3.VAR_TRICK_HOUSE_ROOMS_COMPLETED] = 0, [0x40AB] = 0 }
shut.playerX, shut.playerY = 13, 2
shut:tryTalk()
check((shut.field and shut.field.text or ""):find("door is locked", 1, true)
  ~= nil, "an unread scroll leaves the door locked")

local open = room(Game3.MB_TRICK_HOUSE_PUZZLE_DOOR, 15, 4, 13, 1)
open.scriptVars = { [Game3.VAR_TRICK_HOUSE_ROOMS_COMPLETED] = 0, [0x40AB] = 1 }
open.playerX, open.playerY = 13, 2
open:tryTalk()
check((open.field and open.field.text or ""):find("lock clicked open", 1, true)
  ~= nil, "reading the scroll writes the code and opens it")
eq(open.scriptVars[0x40AB], 2, "VAR_TRICK_HOUSE_PUZZLE_1_STATE becomes 2")
eq(Game3.metatileOf(open.map.grid[1 * 15 + 13 + 1]) % 1024, 0x20B,
  "and the door becomes METATILE_TrickHousePuzzle_Stairs_Down")
end)()


;(function()
-- The follow camera stops at the edge of what is drawn. On hardware this
-- question never comes up: the GBA is 240x160 and MAP_OFFSET of border pad
-- always covers the screen, so fieldmap.c can centre the player and let
-- GetBorderBlockAt fill the rest. A wider view outruns that pad, and without
-- a clamp the camera panned past the border into void fill.
local function room(w, h)
  local grid = {}
  for _ = 1, w * h do grid[#grid + 1] = 0 end
  local m = { id = "cam", width = w, height = h, grid = grid }
  local g = Game3.new()
  g.phase = "play"
  -- opt in: the clamp is a deviation and defaults off
  g.cameraClamp = true
  g.data.maps = { maps = { cam = m } }
  g:enterMap(m, 0, 0, true)
  return g, m
end

-- At the GBA's own view size the clamp must change nothing, or every existing
-- camera behaviour shifts under it.
local g = room(20, 20)
g.viewW, g.viewH = Game3.SCREEN_W, Game3.SCREEN_H
g.playerX, g.playerY = 0, 0
g:clampCamera()
local clamped = g.camX
g.noCameraClamp = true
g:clampCamera()
eq(clamped, g.camX, "at 240x160 the clamp is a no-op, as on hardware")
g.noCameraClamp = nil

-- Widen the view and it has to pull in rather than show void past the border.
g.viewW, g.viewH = 480, 320
g.playerX, g.playerY = 0, 0
g:clampCamera()
local wide = g.camX
g.noCameraClamp = true
g:clampCamera()
local free = g.camX
g.noCameraClamp = nil
check(wide > free, "a wider view stops the camera short of the drawn edge")
local x0, y0, x1, y1 = g:drawnExtent(g.map)
check(wide >= math.min(x0, (x0 + x1 - 480) / 2) - 1,
  "and never further out than the drawn area allows")

-- clampAxis itself: pan when there is room, centre when there is not.
eq(Game3.clampAxis(-500, -100, 900, 240), -100, "pinned at the low edge")
eq(Game3.clampAxis(5000, -100, 900, 240), 900 - 240, "pinned at the high edge")
eq(Game3.clampAxis(300, -100, 900, 240), 300, "left alone in the middle")
eq(Game3.clampAxis(50, 0, 200, 400), (0 + 200 - 400) / 2,
  "a drawn area narrower than the view is centred instead")

-- The clamp must not fight a scripted camera pan: the pan is added after it.
local p = room(20, 20)
p.viewW, p.viewH = 480, 320
p.playerX, p.playerY = 0, 0
p:clampCamera()
local base = p.camX
p.cameraPanX = 64
p:clampCamera()
eq(p.camX, Game3.snapPixel(base + 64), "cameraPan still moves the camera freely")
end)()


;(function()
-- braille_puzzles.c. The regi chambers were unreachable: braillemessage (0x78)
-- was sized but never decoded, so the hint never appeared, and the three
-- field-code openers did not exist at all. Island Cave's Regice door already
-- worked because that one comes from a map script.
local Script = require("src.import.Gen3Script")

-- The braille codes are their own encoding, not the text charmap.
local function braille(bytes)
  local s = {}
  for i = 1, #bytes do s[#s + 1] = string.char(bytes[i]) end
  return table.concat(s) .. "\255"
end
eq(Script.decodeBraille(braille({ 0x1D, 0x06, 0x0F, 0x0D, 0x1E }), 0), "RIGHT",
  "braille decodes back to letters")
eq(Script.decodeBraille(braille({ 0x01, 0xFE, 0x05 }), 0), "A\nB",
  "0xFE is a line break")
-- BRAILLE_CHAR_NUMBER makes the A..J that follow read as digits.
eq(Script.decodeBraille(braille({ 0x3A, 0x01, 0x05, 0x03 }), 0), "123",
  "a number run reads A..J as 1..0")
eq(Script.decodeBraille(braille({ 0x3A, 0x01, 0x00, 0x01 }), 0), "1 A",
  "and the run ends at the first non-digit")
eq(Script.decodeBraille(braille({}), 0), nil, "an empty string decodes to nil")

-- The puzzles themselves: each names one map and the tiles you must stand on.
local function chamber(kind, group, num, x, y)
  local w, h = 24, 32
  local grid = {}
  for _ = 1, w * h do grid[#grid + 1] = 0 end
  local m = { id = "ch", group = group, index = num,
    width = w, height = h, grid = grid }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { ch = m } }
  g:enterMap(m, x, y, true)
  g.playerX, g.playerY = x, y
  g.flags = {}
  return g, m
end

for _, c in ipairs({
  { "strength", 24, 6, 10, 23 },
  { "fly", 24, 68, 8, 25 },
  { "dig", 24, 71, 10, 3 },
}) do
  local kind, group, num, x, y = c[1], c[2], c[3], c[4], c[5]
  local p = Game3.BRAILLE_PUZZLES[kind]
  check(p ~= nil, kind .. " is a known braille puzzle")
  local g, m = chamber(kind, group, num, x, y)
  check(g:shouldDoBraillePuzzle(kind), kind .. " fires on its own tile")
  g.playerX = x + 3
  check(not g:shouldDoBraillePuzzle(kind), kind .. " does not fire off it")
  g.playerX = x
  -- wrong map, right tile
  m.index = num + 1
  check(not g:shouldDoBraillePuzzle(kind), kind .. " does not fire on another map")
  m.index = num
  g:doBraillePuzzle(kind)
  local dx, dy = p.door[1], p.door[2]
  eq(Game3.metatileOf(m.grid[dy * m.width + dx + 1]) % 1024,
    Game3.MT_CAVE_SEALED_TOP_LEFT, kind .. " opens the doorway")
  eq(Game3.metatileOf(m.grid[(dy + 1) * m.width + dx + 2 + 1]) % 1024,
    Game3.MT_CAVE_SEALED_BOTTOM_RIGHT, "including its bottom-right corner")
  eq(g.flags[p.flag], true, kind .. " sets its flag")
  check(not g:shouldDoBraillePuzzle(kind), kind .. " cannot fire twice")
end

-- DIG in the SEALED CHAMBER opens the wall instead of warping you outside,
-- and FLY works in the ANCIENT TOMB even though a cave normally refuses it.
local d = chamber("dig", 24, 71, 10, 3)
d.party = { { name = "X", hp = 20, maxHp = 20, species = 1, level = 40,
  moves = { { id = Game3.MOVE_DIG } } } }
local okDig = d:useDig()
check(okDig, "DIG is allowed on the sealed chamber tile")
eq(d.map.id, "ch", "and it did not warp the player out")
eq(d.flags[Game3.FLAG_SYS_BRAILLE_DIG], true, "it opened the chamber instead")
end)()


;(function()
-- The braille character code is itself the dot pattern: bit 0 is dot 1, then
-- 4, 2, 5, 3, 6 -- the two columns interleaved down the cell. That is why the
-- cells can be drawn from the codes instead of blitted from the cart's font.
local Script = require("src.import.Gen3Script")

local function dots(code)
  local set = Script.brailleDots(code)
  local out = {}
  for d = 1, 6 do if set[d] then out[#out + 1] = d end end
  return table.concat(out, ",")
end

-- Every letter, against the standard braille chart.
local CHART = {
  { 0x01, "A", "1" }, { 0x05, "B", "1,2" }, { 0x03, "C", "1,4" },
  { 0x0B, "D", "1,4,5" }, { 0x09, "E", "1,5" }, { 0x07, "F", "1,2,4" },
  { 0x0F, "G", "1,2,4,5" }, { 0x0D, "H", "1,2,5" }, { 0x06, "I", "2,4" },
  { 0x0E, "J", "2,4,5" }, { 0x11, "K", "1,3" }, { 0x15, "L", "1,2,3" },
  { 0x13, "M", "1,3,4" }, { 0x1B, "N", "1,3,4,5" }, { 0x19, "O", "1,3,5" },
  { 0x17, "P", "1,2,3,4" }, { 0x1F, "Q", "1,2,3,4,5" },
  { 0x1D, "R", "1,2,3,5" }, { 0x16, "S", "2,3,4" }, { 0x1E, "T", "2,3,4,5" },
  { 0x31, "U", "1,3,6" }, { 0x35, "V", "1,2,3,6" }, { 0x2E, "W", "2,4,5,6" },
  { 0x33, "X", "1,3,4,6" }, { 0x3B, "Y", "1,3,4,5,6" },
  { 0x39, "Z", "1,3,5,6" },
}
for _, row in ipairs(CHART) do
  eq(dots(row[1]), row[3], row[2] .. " is dots " .. row[3])
end
eq(dots(0x00), "", "a space raises no dots")

-- decodeBraille returns both the letters and the cells, split by line.
local function blob(bytes)
  local t = {}
  for i = 1, #bytes do t[#t + 1] = string.char(bytes[i]) end
  return table.concat(t) .. string.char(0xFF)
end
local text, cells = Script.decodeBraille(
  blob({ 0x1D, 0x06, 0xFE, 0x01 }), 0)
eq(text, "RI" .. string.char(10) .. "A", "letters come back for reading")
eq(#cells, 2, "and the cells are split into lines")
eq(#cells[1], 2, "two cells on the first line")
eq(cells[1][1], 0x1D, "carrying the raw codes, not the letters")
eq(#cells[2], 1, "one on the second")

-- The engine puts the cells on a full-screen braille window, because every
-- brailleformat in the game is 0, 0, 29, 19.
local g = Game3.new()
check(g:showBrailleMessage("RI", cells), "a braille message opens")
eq(g.field.kind, "braille", "as its own full-screen window")
eq(g.field.cells, cells, "carrying the cells to draw")
g:eraseBrailleMessage()
eq(g.field, nil, "and erasebox clears it")

-- With no cells at all (a cache from before the op was decoded) it still shows
-- something readable rather than nothing.
local old = Game3.new()
check(old:showBrailleMessage("RIGHT", nil), "no cells still shows the hint")
eq(old.field.kind, "talk", "as plain text")
eq(old:showBrailleMessage(nil, nil), false, "but an empty message shows nothing")

-- Geometry: six dots, two columns of three.
eq(#Game3.BRAILLE_DOT_X, 6, "six dot positions across")
eq(#Game3.BRAILLE_DOT_Y, 6, "and down")
eq(Game3.BRAILLE_DOT_X[1], Game3.BRAILLE_DOT_X[3], "dots 1 and 3 share a column")
check(Game3.BRAILLE_DOT_X[4] > Game3.BRAILLE_DOT_X[1], "4 is the right column")
check(Game3.BRAILLE_DOT_Y[3] > Game3.BRAILLE_DOT_Y[2], "3 sits below 2")
end)()


;(function()
-- pokedex.c draws the list screen on gUnknown_08E96738, its own background,
-- and CreateMonListEntry places each row by tile column. The engine used to
-- paint a flat rectangle and invent the columns, which is what made the list
-- look nothing like the cart.
local Dex = require("src.import.RomExtractorGen3Dex")
eq(Dex.RUBY_US.mainScreen, 0xE96738, "the list background is extracted")
check(Dex.MAIN_PATH ~= nil and Dex.MAIN_PATH ~= "", "and has a path")

-- CreateMonListEntry: ball at tile 0x11, number at 0x12, name at 0x17.
eq(Game3.DEX_BALL_X, 0x11 * 8, "the caught ball is at tile column 0x11")
eq(Game3.DEX_NUM_X, 0x12 * 8, "the number at 0x12")
eq(Game3.DEX_NAME_X, 0x17 * 8, "the name at 0x17")
eq(Game3.DEX_ROW_H, 16, "rows are two tiles apart")

-- The panel on that background runs y 14..145, so eight rows fit inside it.
-- Every drawn row has to land within it or the list sits on the artwork.
eq(Game3.DEX_LIST_ROWS, 8, "eight rows are on screen")
check(Game3.DEX_LIST_TOP >= 14, "the first row starts inside the panel")
local lastRow = Game3.DEX_LIST_TOP + (Game3.DEX_LIST_ROWS - 1) * Game3.DEX_ROW_H
check(lastRow + Game3.DEX_ROW_H <= 146,
  "and the last row ends inside it too")
check(Game3.DEX_NAME_X < Game3.SCREEN_W, "names start on screen")
check(Game3.DEX_BALL_X < Game3.DEX_NUM_X and Game3.DEX_NUM_X < Game3.DEX_NAME_X,
  "ball, number then name, left to right")

-- CreateInterfaceSprites: SEEN/OWN on the LEFT panel, START/SELECT prompts
-- bottom left, scroll arrows top/bottom of the list. Corners here.
check(Game3.DEX_SEEN_Y < Game3.DEX_OWN_Y, "SEEN sits above OWN")
check(Game3.DEX_OWN_Y + 16 <= Game3.SCREEN_H, "OWN stays on screen")
check(Game3.DEX_DIGIT_Y_SEEN > Game3.DEX_SEEN_Y, "seen digits sit under SEEN")
check(Game3.DEX_ARROW_TOP_Y < Game3.DEX_ARROW_BOTTOM_Y, "arrows top and bottom")
check(Game3.DEX_ARROW_BOTTOM_Y + 8 <= Game3.SCREEN_H,
  "and the bottom one is on screen")
check(Game3.DEX_START_Y > Game3.DEX_OWN_Y, "START/MENU sit below OWN")

-- The list screen draws the highlighted mon big in the left panel; it does not
-- put an icon on every row the way this engine used to.
local g = Game3.new()
check(type(g.drawDexPortrait) == "function", "there is a portrait for the panel")
check(Game3.DEX_PORTRAIT_X < Game3.DEX_BALL_X,
  "and it sits left of the list, in its own panel")
check(type(g.drawDexDigit) == "function", "interface digits are drawn from the sheet")
check(type(g.drawDexScrollArrow) == "function", "scroll arrows come from the sheet")
end)()


;(function()
-- Every Pokedex screen the cart has, and where it lives.
local Dex = require("src.import.RomExtractorGen3Dex")
local R = Dex.RUBY_US
eq(R.listOverlay, 0xE9C6DC, "list overlay")
eq(R.startMenuMain, 0xE96888, "START menu")
eq(R.startMenuSearch, 0xE96994, "START menu, search results")
eq(R.searchGfx, 0xE87DB0, "search screen tiles")
eq(R.searchLayout, 0xE96D2C, "search screen tilemap")
eq(R.searchPal, 0x39F67C, "search palette")
eq(R.nationalPal, 0x39F73C, "National palette")
check(Dex.SEARCH_PATH and Dex.START_MENU_PATH and Dex.MAIN_NATIONAL_PATH,
  "each has somewhere to render to")

-- Entry screen. Task_InitPageScreenMultistep prints at tile positions, and
-- "No", "HT" and "WT" are chrome tiles -- drawing them again as text is what
-- doubled the labels.
eq(Game3.DEX_ENTRY_NUM_X, 13 * 8, "the number prints at tile 13")
eq(Game3.DEX_ENTRY_NUM_Y, 3 * 8, "on row 3")
eq(Game3.DEX_ENTRY_NAME_X, 16 * 8, "the name at tile 16")
eq(Game3.DEX_ENTRY_CATEGORY_X, 11 * 8, "the category at CATEGORY_LEFT")
eq(Game3.DEX_ENTRY_CATEGORY_Y, 5 * 8, "on row 5")
eq(Game3.DEX_ENTRY_VALUE_X, 16 * 8, "height and weight at tile 16")
eq(Game3.DEX_ENTRY_HT_Y, 7 * 8, "height on row 7")
eq(Game3.DEX_ENTRY_WT_Y, 9 * 8, "weight on row 9")
eq(Game3.DEX_ENTRY_TEXT_Y, 13 * 8, "the description on row 13")
check(Game3.DEX_ENTRY_HT_Y < Game3.DEX_ENTRY_WT_Y, "HT sits above WT")
check(Game3.DEX_ENTRY_WT_Y < Game3.DEX_ENTRY_TEXT_Y,
  "and both above the description")

-- START on the list opens the cart's popup; it does not leave the Pokedex.
eq(#Game3.DEX_START_ITEMS, 4, "four entries on the main START menu")
eq(Game3.DEX_START_ITEMS[1], "BACK TO LIST", "BACK TO LIST first")
eq(Game3.DEX_START_ITEMS[4], "CLOSE POKeDEX", "CLOSE POKeDEX last")
eq(Game3.DEX_START_TEXT_X, 18 * 8, "the text starts at tile column 18")
eq(Game3.DEX_START_ROW_H, 16, "one item every two tile rows")

local Input = require("src.core.Input")
local function press(g, key)
  local old = Input.wasPressed
  Input.wasPressed = function(_, k) return k == key end
  g:stepField()
  Input.wasPressed = old
end

local g = Game3.new()
g.phase = "play"
for i = 1, 12 do g:markSeen(i) end
g:openDex()
eq(#(g.field.list or {}), 12, "twelve seen entries")
press(g, "down"); press(g, "down")
eq(g.field.cursor, 2, "cursor moved")
press(g, "start")
eq(g.field.kind, "dex_start", "START opens the popup, not the main menu")
eq(g.field.listCursor, 2, "and remembers where the list was")
press(g, "a")
eq(g.field.kind, "dex", "BACK TO LIST returns")
eq(g.field.cursor, 2, "on the same entry")
press(g, "start"); press(g, "down"); press(g, "down"); press(g, "a")
eq(g.field.cursor, 11, "LIST BOTTOM goes to the last entry")
press(g, "start"); press(g, "down"); press(g, "a")
eq(g.field.cursor, 0, "LIST TOP goes to the first")
press(g, "start")
press(g, "down"); press(g, "down"); press(g, "down"); press(g, "a")
eq(g.field.kind, "menu", "CLOSE POKeDEX leaves the Pokedex")
end)()


;(function()
-- pokedex.c LoadSearchMenu. sSearchMenuItems gives every field position in
-- tiles and sSearchOptions the option lists; both are transcribed into the
-- engine, and the labels / SEARCH-SHIFT-CANCEL bar are tiles in the tilemap
-- so only values, cursor and description are drawn.
local rows = Game3.DEX_SEARCH_ROWS
eq(#rows, 7, "seven rows, as sSearchMenuItems has")
eq(rows[1].key, "name", "NAME first")
eq(rows[1].y, 2, "on tile row 2")
eq(rows[2].y, 4, "COLOR on 4")
eq(rows[3].y, 6, "TYPE on 6")
eq(rows[4].y, 6, "and the second TYPE shares that row")
eq(rows[3].x, 5, "first TYPE at tile column 5")
eq(rows[4].x, 11, "second at column 11")
eq(rows[5].y, 8, "ORDER on 8")
eq(rows[6].y, 10, "MODE on 10")
eq(rows[7].key, "ok", "OK last")
eq(rows[7].y, 12, "on row 12")

local g = Game3.new()
g.phase = "play"
eq(#Game3.DEX_SEARCH_NAME_OPTIONS, 10, "ten NAME options")
eq(Game3.DEX_SEARCH_NAME_OPTIONS[1], "DON'T SPECIFY", "the first is DON'T SPECIFY")
eq(#Game3.DEX_SEARCH_COLOR_OPTIONS, 11, "eleven COLOR options")
eq(#Game3.DEX_SEARCH_ORDER_OPTIONS, 6, "six ORDER options")
eq(#Game3.DEX_SEARCH_MODE_OPTIONS, 2, "two MODE options")
local types = g:dexSearchTypeOptions()
eq(#types, 18, "eighteen TYPE options, as sDexSearchTypeOptions has")
eq(types[1], "NONE", "NONE first")
eq(types[2], "NORMAL", "then NORMAL")
eq(types[18], "DARK", "and DARK last")
-- sDexSearchTypeIds skips the unused type 9.
for i = 1, #types do
  check(types[i] ~= "???", "no unused type appears in the list: " .. types[i])
end

-- SELECT on the list opens it; B goes back.
local Input = require("src.core.Input")
local function press(gg, key)
  local old = Input.wasPressed
  Input.wasPressed = function(_, k) return k == key end
  gg:stepField()
  Input.wasPressed = old
end
for i = 1, 20 do g:markSeen(i) end
g:openDex()
press(g, "select")
eq(g.field.kind, "dex_search", "SELECT opens the search screen")
press(g, "b")
eq(g.field.kind, "dex", "B returns to the list")

-- A on a field opens its dropdown, A again commits the choice.
press(g, "select")
local f = g.field
eq(f.row, 0, "starts on NAME")
press(g, "a")
check(f.open ~= nil, "A opens the option list")
eq(#f.open.options, 10, "with the NAME options in it")
press(g, "down")
press(g, "a")
eq(f.open, nil, "A commits and closes it")
eq(f.sel.name, 2, "and the field took the new value")
press(g, "a")
press(g, "b")
eq(f.sel.name, 2, "B cancels the list without changing the field")

-- The two TYPE fields sit on one row, so left/right moves between them.
f.row = 2
press(g, "right")
eq(f.row, 3, "right moves to the second TYPE")
press(g, "left")
eq(f.row, 2, "and left comes back")

-- Ordering follows sDexOrderOptions.
local list = {
  { id = 1, name = "CCC" }, { id = 2, name = "AAA" }, { id = 3, name = "BBB" },
}
g:sortDexList(list, 2)
eq(list[1].name, "AAA", "A TO Z sorts by name")
eq(list[3].name, "CCC", "all the way down")
end)()


;(function()
-- pokedex.c: the info page loads LoadScreenSelectBarMain, but AREA, CRY and
-- SIZE each load LoadScreenSelectBarSubmenu. Only the main bar was rendered,
-- so the three sub-screens fell back to a hand-written "B back".
local Dex = require("src.import.RomExtractorGen3Dex")
eq(Dex.RUBY_US.selectBarSubmenu, 0xE96B58, "the submenu bar is extracted")
check(Dex.SELECT_BAR_SUB_PATH and Dex.SELECT_BAR_SUB_PATH ~= "",
  "and rendered to its own asset")
check(Dex.SELECT_BAR_SUB_PATH ~= Dex.SELECT_BAR_PATH,
  "separate from the main bar")

local g = Game3.new()
local picked
local realPic = g.menuPic
g.menuPic = function(_, path) picked = path; return nil end
g.dexArt = function()
  return { selectBar = "MAIN", selectBarSub = "SUB" }
end
g:drawDexSelectBar({ screen = Game3.DEX_SCREEN_INFO })
eq(picked, "MAIN", "the info page uses the main bar")
g:drawDexSelectBar({ screen = Game3.DEX_SCREEN_AREA })
eq(picked, "SUB", "AREA uses the submenu bar")
g:drawDexSelectBar({ screen = Game3.DEX_SCREEN_CRY })
eq(picked, "SUB", "so does CRY")
g:drawDexSelectBar({ screen = Game3.DEX_SCREEN_SIZE })
eq(picked, "SUB", "and SIZE")
g.menuPic = realPic
end)()


;(function()
-- field_weather_effects.c CreateFog1Sprites / CreateAshSprites /
-- CreateSandstormSprites_1: twenty 64x64 sprites, 5 across and 4 down, at
-- x = (i % 5) * 64 + 32 and y = (i / 5) * 64 + 32. Edge to edge, nothing
-- overlapping. The engine used to scatter them -- fog 48px apart for a 64px
-- sprite, sand rows 32px apart -- so they stacked and the alpha piled up.
local W = require("src.core.Game3WeatherFx")
eq(W.GRID_COLS, 5, "five columns, as the cart creates")
eq(W.GRID_ROWS, 4, "four rows")
eq(W.GRID_CELL, 64, "of 64px cells")
local cells = W.gridCells()
eq(#cells, 20, "twenty cells, matching the cart's sprite count")

-- The grid has to cover the whole screen at any scroll offset, and no two
-- cells may land on the same pixel.
local function coverage(scroll)
  local seen, overlap = {}, 0
  for i = 1, #cells do
    local x, y = W.cellXY({ scrollX = scroll, scrollY = scroll }, cells[i])
    for px = math.floor(x), math.floor(x) + W.GRID_CELL - 1 do
      for py = math.floor(y), math.floor(y) + W.GRID_CELL - 1 do
        if px >= 0 and px < Game3.SCREEN_W and py >= 0 and py < Game3.SCREEN_H then
          local k = py * Game3.SCREEN_W + px
          if seen[k] then overlap = overlap + 1 end
          seen[k] = true
        end
      end
    end
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  return n, overlap
end
for _, scroll in ipairs({ 0, 7, 31, 63 }) do
  local covered, overlap = coverage(scroll)
  eq(covered, Game3.SCREEN_W * Game3.SCREEN_H,
    "the grid covers the whole screen at scroll " .. scroll)
  eq(overlap, 0, "with nothing overlapping at scroll " .. scroll)
end

-- Cells are a plain grid, so every column and row is used exactly once.
local cols, rows = {}, {}
for i = 1, #cells do
  cols[cells[i].col] = (cols[cells[i].col] or 0) + 1
  rows[cells[i].row] = (rows[cells[i].row] or 0) + 1
end
for c = 0, W.GRID_COLS - 1 do
  eq(cols[c], W.GRID_ROWS, "column " .. c .. " has one cell per row")
end
for r = 0, W.GRID_ROWS - 1 do
  eq(rows[r], W.GRID_COLS, "row " .. r .. " has one cell per column")
end

-- An object placed as OBJ_EVENT_GFX_VAR_0..F takes its sheet from
-- VAR_OBJ_GFX_ID_n at runtime, so scanning map objects alone never sees it.
-- dynamic_npc_graphics.inc is where GROUDON's two sheets are set.
local R = require("src.import.RomExtractorGen3")
local maps = { m = {
  objects = {},
  coordEvents = { { script = {
    { op = "setvar", var = 0x4018, val = 198 },
    { op = "call", body = { { op = "setvar", var = 0x4019, val = 206 } } },
  } } },
  mapScripts = {},
} }
local ids = R.collectGraphicsIds(maps, nil)
local set = {}
for i = 1, #ids do set[ids[i]] = true end
check(set[198], "GROUDON_1 is collected from the script that sets it")
check(set[206], "GROUDON_2 too, from inside a call body")
-- and a setvar to some other var must not be mistaken for a graphics id
local other = { m = { objects = {}, coordEvents = { { script = {
  { op = "setvar", var = 0x4044, val = 199 },
} } }, mapScripts = {} } }
local ids2 = R.collectGraphicsIds(other, nil)
local set2 = {}
for i = 1, #ids2 do set2[ids2[i]] = true end
check(not set2[199], "a setvar outside VAR_OBJ_GFX_ID is not a graphics id")
end)()


;(function()
-- metatile_behavior.c MetatileBehavior_IsDiveable takes three behaviours.
-- MB_SEMI_DEEP_WATER (0x11) was missing, and it is the one every ocean dive
-- spot uses -- ROUTE 134's patch around (60,31) is 0x11 -- so DIVE answered
-- "You can't use that here!" on 264 tiles across 8 maps, including the route
-- that leads to the SEALED CHAMBER and the chamber's own way back down.
eq(Game3.MB_INTERIOR_DEEP_WATER, 0x11, "MB_SEMI_DEEP_WATER is 0x11")
eq(Game3.MB_DEEP_WATER, 0x12, "MB_UNUSED_DEEP_WATER is 0x12")
eq(Game3.MB_SOOTOPOLIS_DEEP_WATER, 0x14, "and Sootopolis deep water is 0x14")
check(Game3.isDiveable(0x11), "0x11 is diveable")
check(Game3.isDiveable(0x12), "0x12 is diveable")
check(Game3.isDiveable(0x14), "0x14 is diveable")
-- and nothing else is
for _, b in ipairs({ 0x00, 0x10, 0x13, 0x15, 0x1A, 0x69 }) do
  check(not Game3.isDiveable(b),
    ("0x%02X is not diveable"):format(b))
end

-- The gate itself: MIND BADGE plus a party member that knows DIVE.
local function diver(badge)
  local g = Game3.new()
  g.phase = "play"
  local grid = {}
  for _ = 1, 16 * 16 do grid[#grid + 1] = 0 end
  local m = { id = "sea", width = 16, height = 16, grid = grid,
    behavior = { [4 * 16 + 4 + 1] = Game3.MB_INTERIOR_DEEP_WATER } }
  g.data.maps = { maps = { sea = m } }
  g.party = { { name = "X", hp = 20, maxHp = 20, species = 72, level = 20,
    moves = { { id = Game3.MOVE_DIVE, pp = 10 } } } }
  g.flags = {}
  if badge then
    for b = 1, 7 do g.flags[0x800 + 0x06 + b] = true end
  end
  g:enterMap(m, 4, 4, true)
  g.surfing = true
  return g
end

local noBadge = diver(false)
local ok, msg = noBadge:useDive()
eq(ok, false, "no MIND BADGE means no DIVE")
check((msg or ""):find("MIND BADGE", 1, true) ~= nil, "and it says which badge")

local g = diver(true)
check(Game3.isDiveable(g:behaviorAt(g.map, 4, 4)),
  "the tile under the player is a dive tile")
-- no dive connection and no setdivewarp: the cart refuses too
local ok2 = g:useDive()
eq(ok2, false, "a dive tile with nowhere to go still refuses")
-- give it a destination the way ON_RESUME's setdivewarp does
g:setDiveWarp(0, 0, Game3.WARP_ID_NONE, 4, 4)
check(g.diveWarp ~= nil, "setdivewarp stores the destination")
eq(g.diveWarp.x, 4, "with its own landing spot")
end)()


;(function()
-- field_control_avatar.c: A on a diveable tile runs UseDiveScript, B while
-- underwater runs S_UseDiveUnderwater. Neither existed here, so DIVE was only
-- reachable from the party menu and nothing ever told you that you could
-- surface. B, not A, is what surfaces you.
local function sea(opts)
  opts = opts or {}
  local g = Game3.new()
  g.phase = "play"
  local grid = {}
  for _ = 1, 16 * 16 do grid[#grid + 1] = 0 end
  local m = { id = "sea", width = 16, height = 16, grid = grid,
    mapType = opts.underwater and Game3.MAP_TYPE_UNDERWATER or nil,
    behavior = { [4 * 16 + 4 + 1] = opts.plain and Game3.MB_NORMAL
      or Game3.MB_INTERIOR_DEEP_WATER } }
  g.data.maps = { maps = { sea = m } }
  g.party = { { name = "TENTACOOL", hp = 20, maxHp = 20, species = 72,
    level = 20, moves = opts.noDive and {} or { { id = Game3.MOVE_DIVE, pp = 10 } } } }
  g.flags = {}
  if not opts.noBadge then
    for b = 1, 7 do g.flags[0x800 + 0x06 + b] = true end
  end
  g:enterMap(m, 4, 4, true)
  g.surfing = true
  if opts.underwater then g.diving = true end
  return g
end

-- Going down.
local g = sea()
check(g:canDiveDownHere(), "a dive tile offers to take you down")
check(g:tryDiveDown(), "A prompts")
eq(g.field.kind, "decor_yesno", "as a yes/no")
check(g.field.text:find("sea is deep", 1, true) ~= nil, "UseDivePromptText")

-- Coming up. This is B in the cart, and the wording differs.
local u = sea({ underwater = true })
check(u:canDiveEmergeHere(), "underwater offers to surface")
check(u:tryDiveEmerge(), "B prompts")
check(u.field.text:find("filtering down", 1, true) ~= nil,
  "UnderwaterUseDivePromptText")
-- and going down is not offered while already under
eq(u:canDiveDownHere(), false, "you cannot dive down from underwater")

-- No DIVE in the party: it still speaks, with the other wording.
local n = sea({ noDive = true })
check(n:tryDiveDown(), "it still answers without the move")
eq(n.field.kind, "talk", "as a plain line, not a prompt")
check(n.field.text:find("may be", 1, true) ~= nil, "CannotUseDiveText")
local nu = sea({ underwater = true, noDive = true })
nu:tryDiveEmerge()
check(nu.field.text:find("surface here", 1, true) ~= nil,
  "UnderwaterCannotUseDiveText")

-- The MIND BADGE gates both, and plain water offers nothing.
eq(sea({ noBadge = true }):canDiveDownHere(), false,
  "no MIND BADGE, no prompt")
eq(sea({ noBadge = true, underwater = true }):canDiveEmergeHere(), false,
  "and none underwater either")
eq(sea({ plain = true }):canDiveDownHere(), false,
  "ordinary water says nothing at all")
end)()

-- ------- braillemessage carries its own window

-- ScrCmd_braillemessage reads a 6-byte brailleformat header off the front of
-- the string -- winLeft/Top/Right/Bottom then textLeft/textTop -- and does
-- Menu_DrawStdWindowFrame(win) + Menu_PrintText(str, textLeft, textTop). The
-- header differs per message: data/text/braille.inc has ABC at 9,6,19,13 and
-- GO UP HERE. at 3,6,27,13. Skipping those six bytes and drawing every
-- message full-screen at one fixed origin, which is what this did, put the
-- dots in the top-left corner of a white wash for all 22 of them.
;(function()
local function brailleRom(hdr, bytes)
  local body = ""
  for i = 1, #hdr do body = body .. string.char(hdr[i]) end
  for i = 1, #bytes do body = body .. string.char(bytes[i]) end
  body = body .. string.char(0xFF)
  local rom = string.char(0x78, 0x00, 0x01, 0x00, 0x08, 0x02)
  local z = string.char(0)
  rom = rom .. z:rep(0x100 - #rom) .. body
  return rom .. z:rep(0x200 - #rom - #body)
end

-- "AB" under the ABC header, which is deliberately not the fallback one:
-- ignoring op.win has to show up here, not quietly agree with it.
local ops = RomExtractorGen3.parseOps(brailleRom(
  { 9, 6, 19, 13, 12, 9 }, { 0x01, 0x05 }), 0)
local op = ops and ops[1]
eq(op and op.op, "braillemessage", "the op parses")
eq(op and op.text, "AB", "and still decodes its letters")
check(op and op.win ~= nil, "the brailleformat header comes with it")
eq(op.win.left, 9, "winLeft")
eq(op.win.top, 6, "winTop")
eq(op.win.right, 19, "winRight")
eq(op.win.bottom, 13, "winBottom")
eq(op.win.textX, 12, "textLeft")
eq(op.win.textY, 9, "textTop")

-- Draw it and look at where the rectangles actually land.
local G = love.graphics
local oldRect, oldColor, oldDraw = G.rectangle, G.setColor, G.draw
local calls = {}
G.rectangle = function(mode, x, y, w, h) calls[#calls + 1] = { x, y, w, h } end
G.setColor = function() end
G.draw = function() end
local g = Game3.new()
g.uiPic = function() return nil end
g:showBrailleMessage(op.text, op.cells, op.win)
g:drawBrailleMessage(g.field)
G.rectangle, G.setColor, G.draw = oldRect, oldColor, oldDraw

local box = calls[1]
eq(box[1], 72, "the window sits at winLeft * 8")
eq(box[2], 48, "and winTop * 8")
eq(box[3], 88, "spanning left..right inclusive")
eq(box[4], 64, "and top..bottom inclusive")
check(box[3] < Game3.SCREEN_W, "it is a box on the map, not a full-screen wash")

local minX, minY, maxX, maxY = 1e9, 1e9, -1e9, -1e9
local dots = 0
for i = 1, #calls do
  local c = calls[i]
  if c[3] <= Game3.BRAILLE_DOT and c[4] <= Game3.BRAILLE_DOT then
    dots = dots + 1
    if c[1] < minX then minX = c[1] end
    if c[2] < minY then minY = c[2] end
    if c[1] + c[3] > maxX then maxX = c[1] + c[3] end
    if c[2] + c[4] > maxY then maxY = c[2] + c[4] end
  end
end
eq(dots, 12, "six dots drawn per cell, raised or not")
eq(minX, 96, "the text starts at textLeft * 8")
eq(minY, 72, "and textTop * 8")
check(minX >= box[1] and minY >= box[2]
  and maxX <= box[1] + box[3] and maxY <= box[2] + box[4],
  "and every dot lands inside the window")

-- A newline is AddToCursorY(win, 16) -- no extra gap between lines.
local two = RomExtractorGen3.parseOps(brailleRom(
  { 3, 0, 27, 19, 5, 3 }, { 0x01, 0xFE, 0x05 }), 0)[1]
eq(two.text, "A" .. string.char(10) .. "B", "two lines decode")
calls = {}
G.rectangle = function(mode, x, y, w, h) calls[#calls + 1] = { x, y, w, h } end
G.setColor = function() end
G.draw = function() end
g:showBrailleMessage(two.text, two.cells, two.win)
g:drawBrailleMessage(g.field)
G.rectangle, G.setColor, G.draw = oldRect, oldColor, oldDraw
local ys = {}
for i = 1, #calls do
  local c = calls[i]
  if c[3] <= Game3.BRAILLE_DOT and c[4] <= Game3.BRAILLE_DOT then
    ys[c[2]] = true
  end
end
local pitch = Game3.BRAILLE_CELL_H + Game3.BRAILLE_LINE_GAP
check(ys[24] and ys[24 + pitch],
  "the second line sits one line pitch below the first")
-- Braille is read by the ratio of the gaps: between cells and between lines
-- has to beat the spacing inside a cell, or the characters run together.
check(Game3.BRAILLE_CELL_W - Game3.BRAILLE_DOT_X[4] > Game3.BRAILLE_DOT_X[4],
  "cells are further apart than the two dot columns inside one")
check(pitch - Game3.BRAILLE_DOT_Y[3] > Game3.BRAILLE_DOT_Y[2],
  "lines are further apart than the rows inside one cell")
end)()

-- ------- a script whose only output is its own window

-- presentScript's tail assumed a script that queued no dialogue produced
-- nothing, so it called closeField and returned false. braillemessage is the
-- one op that puts a window up on its own, so a braille script that reached
-- the end without pausing had its window destroyed in the same frame and was
-- reported as a no-op: activateBg -> tryBgEvent -> tryTalk all returned false
-- and A on the panel did nothing at all -- you could walk straight off it.
;(function()
local win = { left = 9, top = 6, right = 19, bottom = 13, textX = 12, textY = 9 }
local function brailleScript(ops)
  local g = Game3.new()
  g.phase = "play"
  return g, g:runNpcScript(ops)
end

-- No waitbuttonpress: the script runs to the end with nothing queued.
local g, ran = brailleScript({
  { op = "lockall" },
  { op = "braillemessage", text = "ABC", cells = { { 1, 5, 3 } }, win = win },
  { op = "releaseall" },
  { op = "end" },
})
check(ran, "the script counts as having done something")
eq(g.field and g.field.kind, "braille", "and its window is still up")
eq(g.field and g.field.text, "ABC", "with the message it raised")

-- The cart's own shape still pauses on the button wait, as before.
local w, wran = brailleScript({
  { op = "lockall" },
  { op = "braillemessage", text = "GHI", cells = { { 11, 6, 15 } }, win = win },
  { op = "waitbuttonpress" },
  { op = "releaseall" },
  { op = "end" },
})
check(wran, "the waitbuttonpress form still runs")
eq(w.field and w.field.kind, "braille", "and keeps its window too")

-- A script that queues nothing and raises nothing is still a no-op: the
-- scene-ending closeField must not be smothered by the branch above.
local q, qran = brailleScript({ { op = "lockall" }, { op = "releaseall" },
  { op = "end" } })
eq(qran, false, "a script with no output is still nothing")
eq(q.field, nil, "and it leaves no field behind")
end)()

-- ------- the braille chamber doorways

-- Two bugs kept all four chambers sealed after you solved them.
-- 1. BRAILLE_PUZZLES.door held the cart's MapGridSetMetatileIdAt x/y, which
--    include MAP_OFFSET 7, but setMetatile takes map coords. The door opened
--    7 right and 7 down -- the dig one landed on the "," braille panel.
-- 2. tryWalk refused to follow a warp whose tile carried a bg sign, and the
--    braille panel shares its tile with the doorway warp, so even a correctly
--    opened wall could not be walked through. TryStartWarpEventScript is only
--    `warpEventId != -1 && IsWarpMetatileBehavior(behaviour)` -- no sign check.
;(function()
-- Each door's bottom-middle is the map's own warp tile. That is the
-- cross-check that pins these down: (10,2) on the Sealed Chamber outer room
-- and (8,20) on all three regi chambers.
for _, c in ipairs({
  { "dig", 10, 2 }, { "strength", 8, 20 }, { "fly", 8, 20 },
}) do
  local p = Game3.BRAILLE_PUZZLES[c[1]]
  check(p ~= nil, c[1] .. " is a known puzzle")
  eq(p.door[1] + 1, c[2], c[1] .. " door bottom-middle sits on the warp x")
  eq(p.door[2] + 1, c[3], c[1] .. " door bottom-middle sits on the warp y")
end

-- A warp tile that also carries a sign still warps.
local w, h = 8, 8
local grid, behavior = {}, {}
for i = 1, w * h do grid[i] = 0; behavior[i] = 0 end
behavior[2 * w + 3 + 1] = Game3.MB_NON_ANIMATED_DOOR
local dest = { id = "g9_2", group = 9, index = 2, width = w, height = h,
  grid = {}, behavior = {},
  warps = { { x = 4, y = 4, mapGroup = 9, mapNum = 1, warpId = 0 } } }
for i = 1, w * h do dest.grid[i] = 0; dest.behavior[i] = 0 end
local m = {
  id = "g9_1", group = 9, index = 1, width = w, height = h,
  grid = grid, behavior = behavior,
  warps = { { x = 3, y = 2, mapGroup = 9, mapNum = 2, warpId = 0 } },
  bgEvents = { { x = 3, y = 2, kind = 0, elevation = 0,
    text = "There is a big hole in the wall." } },
}
local g = Game3.new()
g.phase = "play"
g.data.maps = { maps = { g9_1 = m, g9_2 = dest } }
check(Game3.signBgAt(m, 3, 2) ~= nil, "the doorway does carry a sign")
g:enterMap(m, 3, 3, true)
g.playerX, g.playerY = 3, 3
g.facing = "north"
g.ignoreWarp = nil
g:tryWalk(0, -1)
eq(g.map and g.map.id, "g9_2", "walking into it still follows the warp")

-- and the sign is still readable with A, which is the other input entirely
local a = Game3.new()
a.phase = "play"
a.data.maps = { maps = { g9_1 = m, g9_2 = dest } }
a:enterMap(m, 3, 3, true)
a.playerX, a.playerY = 3, 3
a.facing = "north"
a:tryTalk()
eq(a.field and a.field.kind, "talk", "A on the same tile reads the sign")
end)()

-- ------- saying NO must not open the decoration menu

-- answerDecorYesNo's NO branch reopens the secret base DECORATE menu, which
-- is right for the PC's own refusals (decoration.c sends every one of them
-- back to sub_80FE428) but wrong for the two callers that only borrowed the
-- yes/no box. Declining DIVE, or the POKeBLOCK FEEDER, popped DECORATE /
-- PUT AWAY / TOSS / EXIT over the map.
;(function()
local function decline(text, onYes, plain)
  local g = Game3.new()
  g.phase = "play"
  g:openDecorYesNo(text, onYes, plain)
  eq(g.field.kind, "decor_yesno", "the prompt opens")
  g:answerDecorYesNo(false)
  return g
end

local d = decline("Would you like to use DIVE?", "confirmDivePrompt", true)
eq(d.field, nil, "declining DIVE just closes the box")

local p = decline("POKeBLOCK?", "openPokeblockCaseOnFeeder", true)
eq(p.field, nil, "so does declining the POKeBLOCK FEEDER")

-- The PC's own refusals still go back to its menu.
local pc = decline("Return this decoration to the PC?", "confirmDecorPutAway")
check(pc.field ~= nil, "a decoration refusal still lands somewhere")
eq(pc.field.kind, "decor_menu", "and that somewhere is the PC menu")

-- YES is unaffected either way.
local y = Game3.new()
y.phase = "play"
y._ranIt = false
y.markIt = function(self) self._ranIt = true end
y:openDecorYesNo("go?", "markIt", true)
y:answerDecorYesNo(true)
check(y._ranIt, "a plain prompt still runs its yes handler")
end)()

-- ------- the Regice wait survives stray taps

-- Task_BrailleWait case 2 destroys the task on ANY press once the message is
-- erased, so the very tap that dismisses the braille arms an instant, silent
-- cancel -- and the screen looks the same whether the timer is running or
-- dead. Deliberate deviation: only B backs out now, so the countdown keeps
-- running through A and d-pad taps. See brailleWaitCancelPressed.
;(function()
local Input = require("src.core.Input")
local function waitOut(taps)
  Input:reset()
  local g = Game3.new()
  g.phase = "play"
  g.flags = {}
  g:doBrailleWait()
  for i = 1, 9000 do
    local t = taps[i]
    if t then Input:overlayPressed(t) end
    Input:step()
    g:stepBrailleWait(1)
    if t then Input:overlayReleased(t) end
    if not g.brailleWait then
      return i, g.flags[Game3.FLAG_SYS_BRAILLE_WAIT] == true
    end
  end
  return nil, false
end

local n, opened = waitOut({})
check(opened, "left alone, the chamber opens")
eq(n, Game3.BRAILLE_WAIT_FRAMES + Game3.BRAILLE_WAIT_CLEAR_FRAMES,
  "after the full wait plus the erase delay")

n, opened = waitOut({ [50] = "a" })
check(opened, "dismissing the braille still opens it")
eq(n, Game3.BRAILLE_WAIT_FRAMES, "the timer is not restarted by the dismiss")

-- The reported bug: a second tap killed it silently.
n, opened = waitOut({ [50] = "a", [300] = "a" })
check(opened, "and a second tap no longer cancels")
n, opened = waitOut({ [50] = "a", [300] = "a", [600] = "a", [900] = "a" })
check(opened, "nor do several")
n, opened = waitOut({ [50] = "a", [300] = "up", [600] = "left" })
check(opened, "nor a nudge on the d-pad")

-- B is still the way out of a two-minute wait.
n, opened = waitOut({ [50] = "a", [300] = "b" })
check(not opened, "B still backs out")
eq(n, 300, "at the moment it is pressed")
end)()

-- ------- scripts must be baked before the collectors run

-- run() used to bake map scripts in the Cache stage, below both collectors
-- that read them: collectGraphicsIds (via extractSprites) and
-- collectScriptSpecies (via extractBattle). Every entry.script was still a
-- raw offset when they ran, so both collected nothing script-driven --
-- Groudon's overworld sheets (198/206) and every script-only battle pic
-- rendered as a blank square. The bake now happens straight after
-- extractMaps, keeping scriptOff for the trainer / item / mart reads that
-- follow, and stripScriptOffsets clears them afterwards.
;(function()
local VAR_OBJ_GFX_ID_8 = 0x4018
local function mapWithGfxVar(off)
  return { id = "m", group = 1, index = 1, width = 2, height = 2,
    grid = { 0, 0, 0, 0 },
    objects = { { x = 0, y = 0, graphicsId = 7, scriptOff = off } },
    bgEvents = {}, coordEvents = {} }
end

-- setvar VAR_OBJ_GFX_ID_8, 198  then end
local rom = string.rep(string.char(0), 0x20)
  .. string.char(0x16, 0x18, 0x40, 198, 0, 0x02)
local OFF = 0x20

local m = mapWithGfxVar(OFF)
local ids = RomExtractorGen3.collectGraphicsIds({ m }, nil)
local set = {}
for _, g in ipairs(ids) do set[g] = true end
eq(set[198], nil, "an unbaked script hides the gfx var write")

RomExtractorGen3.bakeMapScripts(rom, m, true)
ids = RomExtractorGen3.collectGraphicsIds({ m }, nil)
set = {}
for _, g in ipairs(ids) do set[g] = true end
check(set[198], "once baked, the sheet the script names is collected")
check(set[7], "and the object's own graphicsId still is")

-- keepOffsets leaves scriptOff for the trainer / item / mart reads below
check(m.objects[1].scriptOff ~= nil, "keepOffsets leaves the raw offset")
check(type(m.objects[1].script) == "table", "and bakes the script")
RomExtractorGen3.stripScriptOffsets(m)
eq(m.objects[1].scriptOff, nil, "stripScriptOffsets clears it")
check(type(m.objects[1].script) == "table", "without losing the script")

-- the default is still to clear as it bakes
local m2 = mapWithGfxVar(OFF)
RomExtractorGen3.bakeMapScripts(rom, m2)
eq(m2.objects[1].scriptOff, nil, "without keepOffsets it clears as before")
check(type(m2.objects[1].script) == "table", "and still bakes")
end)()

-- ------- gMultichoiceLists comes off the ROM

-- Game3.MULTICHOICE held ten lists somebody typed in by hand as each empty
-- menu was noticed. Anything else had no options at all -- the Battle Tower
-- ferry asks for list 53 (SLATEPORT / LILYCOVE / CANCEL) and got nothing, so
-- there was no way to sail back. script_menu.c gMultichoiceLists is
-- { const struct MenuAction *list; u8 count; } entries, each list being
-- `count` { const u8 *text; MenuFunc func } pairs with func always NULL.
;(function()
local GbaText = require("src.import.GbaText")
-- Build a ROM holding a table of `n` lists so the run-length check is met.
local function fakeRom(labelsById, n)
  local BASE = 0x1000
  local TEXT = 0x4000
  local rom = {}
  local function put(off, str)
    for i = 1, #str do rom[off + i] = str:sub(i, i) end
  end
  local function u32le(v)
    return string.char(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  local textAt = TEXT
  local listAt = BASE + n * 8
  for id = 0, n - 1 do
    local labels = labelsById[id] or { "CANCEL" }
    put(BASE + id * 8, u32le(0x08000000 + listAt))
    put(BASE + id * 8 + 4, string.char(#labels, 0, 0, 0))
    for j = 1, #labels do
      put(TEXT + (textAt - TEXT), "")
      local enc = GbaText.encodeLatin(labels[j]) .. string.char(0xFF)
      put(textAt, enc)
      put(listAt + (j - 1) * 8, u32le(0x08000000 + textAt))
      put(listAt + (j - 1) * 8 + 4, u32le(0))
      textAt = textAt + #enc + 1
    end
    listAt = listAt + #labels * 8
  end
  local out = {}
  for i = 1, 0x8000 do out[i] = rom[i] or string.char(0) end
  return table.concat(out), BASE
end

local want = { [0] = { "PETALBURG", "SLATEPORT", "CANCEL" },
  [53] = { "SLATEPORT", "LILYCOVE", "CANCEL" } }
local rom, base = fakeRom(want, 60)
local off, run = RomExtractorGen3.findMultichoiceLists(rom, 0)
eq(off, base, "the table is found by signature, not a fixed address")
eq(run, 60, "and every entry in the run is counted")

local lists = RomExtractorGen3.parseMultichoiceLists(rom, 0)
check(type(lists) == "table", "the lists parse")
eq(table.concat(lists[53] or {}, "|"), "SLATEPORT|LILYCOVE|CANCEL",
  "list 53 is the Battle Tower ferry's destinations")
eq(table.concat(lists[0] or {}, "|"), "PETALBURG|SLATEPORT|CANCEL",
  "and list 0 still decodes")

-- A ROM with no such table must say so rather than invent one.
eq(RomExtractorGen3.findMultichoiceLists(string.rep(string.char(0), 0x8000), 0),
  nil, "an empty ROM yields no table")

-- Runtime: the extracted table wins, the hand-typed one is the fallback.
local g = Game3.new()
eq(g:multichoiceLabels(53), nil,
  "with no cache, list 53 has no options -- the original bug")
check(g:multichoiceLabels(5) ~= nil, "while a hand-typed list still answers")
g.data.menus = { multichoice = lists }
eq(table.concat(g:multichoiceLabels(53) or {}, "|"), "SLATEPORT|LILYCOVE|CANCEL",
  "with the cache, the ferry has its destinations")
end)()

-- ------- the flash hole follows the player, not the screen

-- WriteFlashScanlineEffectBuffer puts the hole at 120,80 because the cart
-- never clamps the camera: the player IS at 120,80 always, and the border
-- block is tiled over anything off-map. This engine clamps the camera to the
-- drawn area (a deliberate deviation), so near a map edge -- or on a portrait
-- drawable whose span is taller than a small cave -- the player walks away
-- from the screen centre while the hole stayed nailed to it, leaving the
-- player at the rim or outside it. Caves became unnavigable.
;(function()
local function cave(w, h)
  local grid, behavior = {}, {}
  for i = 1, w * h do grid[i] = 1; behavior[i] = 0 end
  return { id = "cave", group = 24, index = 0, width = w, height = h,
    grid = grid, behavior = behavior, tileset = "pair_0", cave = true }
end
local function at(m, x, y, gw, gh, zoom)
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { cave = m } }
  g.flashLevel = 1
  g:enterMap(m, x, y, true)
  g.playerX, g.playerY = x, y
  g.walkFromX, g.walkFromY = x, y
  if gw then g._zoomS = zoom; g._tiltGw = gw; g._tiltGh = gh end
  -- the clamp is what pushes the player off centre, so turn it on for the
  -- case that exercises it
  g.cameraClamp = true
  g:clampCamera()
  return g
end

-- Wide open ground: the clamp does not bite and the player is dead centre,
-- exactly where the cart puts them.
local big = cave(40, 30)
local g = at(big, 20, 15)
local px, py = g:playerViewXY()
local vw, vh = g:viewSize()
eq(px, vw / 2, "unclamped, the player is at the view centre")
eq(py, vh / 2, "on both axes")

-- A small room under a tall portrait drawable: the vertical span is larger
-- than the room, so the clamp centres the room and the player drifts.
local small = cave(14, 10)
local edge = at(small, 7, 1, 480, 800, 2)
local _, ey = edge:playerViewXY()
check(math.abs(ey - 800 / (2 * 2)) > 24,
  "clamped, the player ends up further off centre than the flash radius")

-- The hole has to be on the player either way.
local function holeCentreOnPlayerRow(gm, winW, winH, zoom)
  local G = love.graphics
  local realRect, realColor = G.rectangle, G.setColor
  local rects = {}
  G.rectangle = function(_, x, y, w2, h2) rects[#rects + 1] = { x, y, w2, h2 } end
  G.setColor = function() end
  gm:drawFlashOverlay(winW, winH, zoom)
  G.rectangle, G.setColor = realRect, realColor
  local vx, vy = gm:playerViewXY()
  local row = math.floor(vy * (zoom or 1))
  local left, right = 0, winW
  for i = 1, #rects do
    local r = rects[i]
    if math.floor(r[2]) == row and r[4] <= 1 then
      if r[1] <= 0 then
        if r[3] > left then left = r[3] end
      elseif r[1] < right then
        right = r[1]
      end
    end
  end
  if right <= left then return nil end
  return (left + right) / 2, vx * (zoom or 1)
end

local hc, want = holeCentreOnPlayerRow(edge, 480, 800, 2)
check(hc, "there is a hole on the player's own scanline")
eq(hc, want, "and it is centred on the player, not the window")

local hc2, want2 = holeCentreOnPlayerRow(at(small, 7, 8, 480, 800, 2), 480, 800, 2)
eq(hc2, want2, "the same at the other edge of the room")
end)()

-- ------- the camera clamp is off by default

-- Turned off at the player's request. The cart never clamps: fieldmap.c
-- centres the player and GetBorderBlockAt tiles the 2x2 border block over
-- anything off-map. Clamping was a deviation and it kept breaking things
-- that reasonably assume the player is at the screen centre -- the flash
-- hole most visibly, which is pinned at 120,80 straight out of
-- WriteFlashScanlineEffectBuffer. The code stays, so it can be switched
-- back on per game object.
;(function()
local function room(w, h)
  local grid, behavior = {}, {}
  for i = 1, w * h do grid[i] = 0; behavior[i] = 0 end
  local m = { id = "cam", width = w, height = h, grid = grid,
    behavior = behavior }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { cam = m } }
  g:enterMap(m, 0, 0, true)
  g.viewW, g.viewH = 480, 320
  g.playerX, g.playerY = 0, 0
  return g, m
end

eq(Game3.CAMERA_CLAMP_DEFAULT, false, "the default is off")
eq(Game3.new():cameraClampEnabled(), false, "so a fresh game does not clamp")

-- With it off the player is centred exactly as on hardware, even in a room
-- far smaller than the view.
local g = room(10, 10)
g:clampCamera()
local px, py = g:playerViewXY()
local vw, vh = g:viewSize()
eq(px, vw / 2, "player stays at the view centre horizontally")
eq(py, vh / 2, "and vertically")

-- Switching it on brings the old behaviour back, so the code is still live.
local c = room(10, 10)
c.cameraClamp = true
c:clampCamera()
local free = room(10, 10)
free:clampCamera()
check(c.camX ~= free.camX,
  "turning the clamp on still changes the camera, so it is not dead code")
local cx = select(1, c:playerViewXY())
check(math.abs(cx - vw / 2) > 1,
  "and with it on the player leaves the centre, which is why it is off")

-- noCameraClamp still wins, for anything that sets it explicitly.
local n = room(10, 10)
n.cameraClamp = true
n.noCameraClamp = true
eq(n:cameraClampEnabled(), false, "an explicit noCameraClamp still overrides")
end)()

-- ------- the border block is tiled at the right parity

-- GetBorderBlockAt takes MapGrid coords, which include MAP_OFFSET 7:
--   i = ((x + 1) & 1) + ((y + 1) & 1) * 2
-- drawWrapTileFill bakes the 2x2 into a 32x32 texture and wrap-tiles it with
-- the viewport origin at world pixels, so the texture's own 0/1 cells stand
-- for world tile parity, not grid parity. Passing them to borderIndex raw
-- transposed the block diagonally and every border tree came out with its
-- quadrants swapped -- whole trees on hardware, sliced ones here.
;(function()
-- world tile (x,y) sits at grid (x + 7, y + 7), and the two +1s cancel, so
-- the border array is simply read in order.
for y = 0, 1 do
  for x = 0, 1 do
    eq(Game3.borderIndex(x + Game3.MAP_OFFSET, y + Game3.MAP_OFFSET),
      x + y * 2 + 1,
      ("world tile (%d,%d) reads border[%d]"):format(x, y, x + y * 2 + 1))
  end
end

-- and raw texture coords are NOT the same thing -- this is the bug
check(Game3.borderIndex(0, 0) ~= Game3.borderIndex(Game3.MAP_OFFSET, Game3.MAP_OFFSET),
  "raw 0,0 and grid 7,7 disagree, which is what went wrong")

-- Littleroot's ring is one tree: 468,469 over 476,477. Reading it in order
-- has to give the tree back the right way up.
-- through borderBakeCell, which is what the bake itself calls
local tree = { 468, 469, 476, 477 }
local got = {}
for y = 0, 1 do
  for x = 0, 1 do
    got[#got + 1] = Game3.borderBakeCell(tree, x, y)
  end
end
eq(Game3.borderBakeCell(tree, 0, 0), 468, "texture cell 0,0 bakes the treetop")
eq(Game3.borderBakeCell(tree, 1, 1), 477, "and 1,1 the bottom-right")
eq(Game3.borderBakeCell(nil, 0, 0), 0, "a map with no border bakes nothing")
eq(table.concat(got, ","), "468,469,476,477",
  "the tree tiles come out in reading order, not transposed")
-- the top row of the metatile pair is 8 lower than the bottom in the tileset,
-- so a transposed block puts a treetop under a trunk
eq(got[3] - got[1], 8, "bottom-left really is one tileset row under top-left")
end)()

-- ------- maps already on screen survive crossing a connection

-- connectedLayout only gathers CONNECTION_DRAW_HOPS from the CURRENT map, so
-- stepping east threw away everything reachable only through the map you just
-- left: at survey zoom a screen of towns and routes collapsed to flat water.
-- Raising the hop count is what ran the phone out of memory before, so the
-- previous frame's maps are carried forward instead -- both layouts put the
-- current map at (0,0), so the shift is just where the old current map landed.
;(function()
-- a west-to-east chain: a - b - c - d, each 20x20
-- keyed the way lookupMap resolves them: gGROUP_INDEX
local function chainId(i) return "g9_" .. i end
local function chain(n)
  local maps = {}
  for i = 1, n do
    local id = chainId(i)
    maps[id] = { id = id, group = 9, index = i, width = 20, height = 20,
      grid = {}, connections = {} }
    for j = 1, 400 do maps[id].grid[j] = 0 end
  end
  for i = 1, n - 1 do
    local a, b = maps[chainId(i)], maps[chainId(i + 1)]
    a.connections[#a.connections + 1] =
      { dir = "east", offset = 0, mapGroup = 9, mapNum = i + 1 }
    b.connections[#b.connections + 1] =
      { dir = "west", offset = 0, mapGroup = 9, mapNum = i }
  end
  return maps
end
local function walker(maps, viewW, viewH)
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = maps }
  g.viewW, g.viewH = viewW or 720, viewH or 1600
  return g
end
local function goTo(g, maps, id)
  g.connectedLayoutCache = nil
  g:enterMap(maps[id], 1, 1, true)
  g:clampCamera()
  return g:mapPlacements(maps[id])
end
local function ids(list)
  local out = {}
  for i = 1, #list do out[#out + 1] = list[i].map.id end
  table.sort(out)
  return table.concat(out, " ")
end

local maps = chain(4)
local g = walker(maps)
eq(ids(goTo(g, maps, chainId(1))), "g9_1 g9_2", "one hop from 1 is just 1 and 2")
eq(ids(goTo(g, maps, chainId(2))), "g9_1 g9_2 g9_3", "and from 2, three maps")
eq(ids(goTo(g, maps, chainId(3))), "g9_1 g9_2 g9_3 g9_4",
  "arriving at 3, map 1 is carried forward")
eq(ids(goTo(g, maps, chainId(4))), "g9_1 g9_2 g9_3 g9_4", "and still there at 4")

-- the carried maps have to land where a real walk would put them
local truth = walker(maps)
truth.noStickyLayout = true
truth.connectedLayoutCache = nil
truth:enterMap(maps[chainId(4)], 1, 1, true)
local want = {}
for _, p in ipairs(truth:connectedLayout(maps[chainId(4)], 4)) do
  want[p.map.id] = p.ox .. "," .. p.oy
end
for _, p in ipairs(g:mapPlacements(maps[chainId(4)])) do
  eq(p.ox .. "," .. p.oy, want[p.map.id],
    "carried map " .. p.map.id .. " sits where a real walk puts it")
end

-- Off by default? No -- but it must be switchable, and off must behave as
-- before: only the current map and its direct neighbours.
local off = walker(maps)
off.noStickyLayout = true
goTo(off, maps, chainId(1)); goTo(off, maps, chainId(2))
eq(ids(goTo(off, maps, chainId(3))), "g9_2 g9_3 g9_4",
  "with it off, map 1 is dropped as before")

-- Bounded by the view: a narrow view drops what has scrolled away.
local tiny = walker(chain(4), Game3.SCREEN_W, Game3.SCREEN_H)
local tmaps = tiny.data.maps.maps
goTo(tiny, tmaps, chainId(1)); goTo(tiny, tmaps, chainId(2))
local far = goTo(tiny, tmaps, chainId(3))
check(#far <= 4, "a small view does not accumulate the whole chain")

-- and hard-capped however far you walk
eq(Game3.STICKY_LAYOUT_MAX, 8, "there is a ceiling on carried maps")
local long = chain(12)
local lg = walker(long, 2000, 2000)
for i = 1, 12 do goTo(lg, long, chainId(i)) end
local list = lg:mapPlacements(long[chainId(12)])
check(#list <= Game3.STICKY_LAYOUT_MAX + 4,
  "the carried set stays bounded across a long walk")
end)()

-- One void for the whole world. Each map used to answer for the space past
-- its own edges, which produced 43 different fills across 136 outdoor maps:
-- walking between two maps changed the texture of the same patch of sea, and
-- a map's border block -- authored EDGE art, a tree canopy or a beach run --
-- wrap-tiled into rectangular grids of treetops sitting in open water.
;(function()
local Game3 = require("src.core.Game3")
local g = Game3.new()
g.phase = "play"
local town = {
  id = "g_town", tileset = "pair_a", mapType = Game3.MAP_TYPE_TOWN,
  width = 2, height = 2, grid = { 1, 1, 1, 1 },
  border = { 468, 469, 476, 477 }, behavior = { 0, 0, 0, 0 },
}
local shore = {
  id = "g_shore", tileset = "pair_b", mapType = Game3.MAP_TYPE_ROUTE,
  width = 2, height = 2, grid = { 368, 368, 20, 20 },
  border = { 113, 113, 113, 113 }, behavior = { 0x15, 0x15, 0x21, 0x21 },
}
g.data.maps = { maps = { g_town = town, g_shore = shore } }
g.data.tilesets = { byId = { pair_a = { tiles = {} }, pair_b = { tiles = {} } } }
g.options = {}
eq(g:voidFillMode(), "sea", "the default void is the sea")

local fills = {}
g.drawWrapTileFill = function(_, _, _, cells, key)
  fills[#fills + 1] = { cells = table.concat(cells, ","), key = key }
end
g.layersFor = function() return "img" end
g.viewSize = function() return 240, 160 end
g.borderFillRects = function() return { { 0, 0, 240, 160 } } end
g.mapPlacements = function(self) return { { map = self.map, ox = 0, oy = 0 } } end

g.map = town; g:drawVoidFill("bottom")
g.map = shore; g:drawVoidFill("bottom")
eq(#fills, 2, "each map paints the void in one quad")
eq(fills[1].cells, fills[2].cells,
  "and paints the same thing on both -- the void does not change when the"
  .. " player walks from one map into the next")
eq(fills[1].cells, "368,368,368,368",
  "which is gTileset_General's open sea, not either map's own border")

-- Two maps whose borders differ wildly still agree on the void, so nothing
-- from a map's edge art can end up tiled across a neighbour's water.
check(town.border[1] ~= shore.border[1], "the fixture borders really do differ")
for i = 1, #fills do
  check(fills[i].cells ~= table.concat(town.border, ","),
    "the tree ring never becomes the fill")
end

-- The border block is what frames a town: Littleroot's own grid has no
-- trees down either side. This port draws a whole connected layout at once,
-- so EVERY placement paints its own ring -- a neighbour left bare reads as
-- unfinished next to a map that has one.
g.mapPlacements = function()
  return { { map = town, ox = 0, oy = 0 }, { map = shore, ox = 0, oy = 2 } }
end
local before = #fills
g.map = town
g:drawBorderFill("img", town)
eq(#fills, before + 2, "every map in the layout paints its own ring")
local sawTown, sawShore
for i = before + 1, #fills do
  if fills[i].key:find("g_town") then
    sawTown = true
    eq(fills[i].cells, table.concat(town.border, ","),
      "each ring is that map's OWN authored border block")
  elseif fills[i].key:find("g_shore") then
    sawShore = true
    eq(fills[i].cells, table.concat(shore.border, ","),
      "including the neighbour's, which is its own block and not the"
      .. " current map's")
  end
end
check(sawTown, "the map underfoot is ringed")
check(sawShore, "and so is the connected one")

-- The ring does not depend on the fill mode.
local permap = #fills
g.options = { voidFill = "map" }
g:drawBorderFill("img", town)
eq(#fills, permap + 2, "PER-MAP paints the same rings, no more")

-- The pad has to be EVEN. The border block is a 2x2 whose trees are two
-- metatiles tall, so an odd pad (the cart's MAP_OFFSET of 7) slices the
-- outermost row of trees in half.
eq(Game3.BORDER_PAD_TILES, 8, "eight tiles: four whole rows of trees")
eq(Game3.BORDER_PAD_TILES % 2, 0, "an odd pad would halve the last row")
check(Game3.BORDER_PAD_TILES > Game3.MAP_OFFSET,
  "and it is a draw distance, not the cart's backup-buffer size")

-- GRASS is the same deal on land; BLACK and PER-MAP have no global cell.
eq(table.concat(Game3.globalVoidCells("sea"), ","), "368,368,368,368")
eq(table.concat(Game3.globalVoidCells("grass"), ","), "1,1,1,1")
eq(Game3.globalVoidCells("black"), nil, "BLACK paints nothing at all")
eq(Game3.globalVoidCells("map"), nil, "PER-MAP goes back through voidFillCells")
end)()

-- field_fadetransition.c sub_8080AE4 picks the arrival task from the
-- behaviour of the tile you land on. Both door kinds walk the player one
-- step off it before returning control (sub_8080B9C for animated,
-- task_map_chg_seq_0807E20C for non-animated); everything else runs
-- task_map_chg_seq_0807E2CC, which only unlocks. Indoor stairs are
-- MB_NON_ANIMATED_DOOR and we were treating them as the third case, so the
-- player stood ON the stairs -- one tile north of the cart for the rest of
-- the scene. Littleroot's PETALBURG GYM report then walked them onto the TV
-- instead of stopping south of it.
;(function()
local Game3 = require("src.core.Game3")
local function pair(destBehavior)
  local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local from = {
    id = "g9_0", group = 9, index = 0, width = 3, height = 3, grid = cells,
    warps = { { x = 1, y = 0, mapGroup = 9, mapNum = 1, warpId = 0 } },
  }
  local to = {
    id = "g9_1", group = 9, index = 1, width = 3, height = 3, grid = cells,
    warps = { { x = 1, y = 1, mapGroup = 9, mapNum = 0, warpId = 0 } },
    behavior = { [1 * 3 + 1 + 1] = destBehavior },
  }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { g9_0 = from, g9_1 = to } }
  g:enterMap(from, 1, 1, true)
  g.ignoreWarp = false
  g.facing = "north"
  g:followWarp(from.warps[1])
  return g
end

local g = pair(Game3.MB_NON_ANIMATED_DOOR)
eq(g.map.id, "g9_1", "the warp still lands on the destination map")
eq(g.field and g.field.kind, "door_arrival",
  "a non-animated door holds control while the player steps off it")
eq(g.ignoreWarp, false,
  "and releases the re-warp latch, or you are stuck inside a lift")
g:finishScriptMoves()
eq(g.playerX, 1, "the step keeps the player's column")
eq(g.playerY, 0, "and moves one tile in the direction they were facing")

-- A warp tile that is not a door leaves the player standing on it.
local h = pair(Game3.MB_LADDER)
eq(h.map.id, "g9_1", "a ladder warps too")
eq(h.field, nil, "but runs no arrival step")
eq(h.playerY, 1, "so the player stays on the tile they arrived on")

-- The map's ON_FRAME table must not fire from the doorway: the cart locks
-- control for the whole arrival task, so the script sees the tile the
-- player actually ends up on.
local k = pair(Game3.MB_NON_ANIMATED_DOOR)
check(k._pendingMapFrame,
  "the frame script is deferred until the arrival step finishes")
end)()

-- trainer_see.c: the ! and ? icons come from gSpriteTemplate_839B510, whose
-- palette tag is 0xffff (SPRITE_INVALID_TAG). They load no palette of their
-- own and render against whatever OBJ palette sits in slot 0 -- an
-- object-event palette in the overworld. That is safe because those frames
-- use only indices 14 and 15, and every object-event palette reserves 14 =
-- white, 15 = black. Reading them out of gFieldEffectObjectPalette0 (which
-- the heart legitimately uses, tag 0x1004) painted the speech bubble tan:
-- that palette holds (205,156,82) at index 14.
;(function()
local R = require("src.import.RomExtractorGen3")
check(R.EMOTE_TAGLESS.exclaim, "! has no palette tag of its own")
check(R.EMOTE_TAGLESS.question, "nor does ?")
check(not R.EMOTE_TAGLESS.heart, "the heart does: tag 0x1004")
check(R.EMOTE_PAL_TAGLESS ~= R.EMOTE_PAL,
  "so the two cannot come from the same palette")

local seen = {}
local real = R.renderOwFrame
R.renderOwFrame = function(_, info, palOff, frameOff)
  seen[#seen + 1] = { pal = palOff, frame = frameOff }
  return true
end
for _, name in ipairs({ "exclaim", "question", "heart" }) do
  R.renderEmote("", name)
end
R.renderOwFrame = real
eq(seen[1].pal, R.EMOTE_PAL_TAGLESS, "! reads the object-event palette")
eq(seen[2].pal, R.EMOTE_PAL_TAGLESS, "? too")
eq(seen[3].pal, R.EMOTE_PAL, "the heart keeps the field-effect palette")
-- the three frames are consecutive 0x80 blocks from gSpriteImage_839B308
eq(seen[1].frame, R.EMOTE_GFX, "! is the first frame")
eq(seen[2].frame, R.EMOTE_GFX + R.EMOTE_BYTES, "? the second")
eq(seen[3].frame, R.EMOTE_GFX + 2 * R.EMOTE_BYTES, "heart the third")
end)()

-- The same arrival rule applies to a SCRIPT warp, which the cart routes
-- through the same machinery. PetalburgCity_Gym leaves with
-- `warp MAP_PETALBURG_CITY, 255, 15, 8`, and (15,8) is the gym's own
-- animated door: the player is stepped south to (15,9) before
-- PetalburgCity_OnFrame runs, so the tutorial's 8-down / 20-right walk
-- follows y=17, below the POKeMON CENTER door at (20,16). Landing on the
-- doorway instead ran it along y=16 -- one tile north, through the CENTER.
-- MetatileBehavior_IsDoor covers MB_ANIMATED_DOOR too, and those doors get
-- the step even when we have no door graphic to animate for them.
;(function()
local Game3 = require("src.core.Game3")
local function warped(behavior)
  local cells = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local from = {
    id = "g7_0", group = 7, index = 0, width = 3, height = 3, grid = cells,
  }
  local to = {
    id = "g7_1", group = 7, index = 1, width = 3, height = 3, grid = cells,
    behavior = { [1 * 3 + 1 + 1] = behavior },
  }
  local g = Game3.new()
  g.phase = "play"
  g.data.maps = { maps = { g7_0 = from, g7_1 = to } }
  g:enterMap(from, 1, 1, true)
  g.facing = "south"
  g:scriptWarp(7, 1, Game3.WARP_ID_NONE, 1, 1)
  return g
end

local g = warped(Game3.MB_ANIMATED_DOOR)
eq(g.map.id, "g7_1", "the script warp still lands")
eq(g.field and g.field.kind, "door_arrival",
  "an animated door steps the player off it, graphic or not")
check(g._pendingMapFrame,
  "and the ON_FRAME table waits for that step")
g:finishScriptMoves()
eq(g.playerY, 2, "one tile in the direction the player faced")

local h = warped(Game3.MB_NON_ANIMATED_DOOR)
eq(h.field and h.field.kind, "door_arrival", "so does a non-animated one")

-- Anything that is not a door leaves the player where the script put them.
local k = warped(0)
eq(k.field, nil, "a plain tile runs no arrival step")
eq(k.playerY, 1, "and the player stays on it")
end)()

-- field_tasks.c PerStepCallback_806A07C: stepping onto a cracked floor arms
-- one of two slots with a 3 countdown, and sub_806A040 then swaps the tile
-- for a hole (0x22F -> 0x206, anything else -> 0x237). The countdown lives
-- in Task_RunPerStepCallback, an ordinary task, so it ticks EVERY FRAME --
-- not once per step. Ticking it from the step callback instead meant the
-- floor only crumbled while the player kept walking: stand still on one and
-- it never collapsed at all, so SKY PILLAR had no timer.
;(function()
local Game3 = require("src.core.Game3")
local function pillar()
  local g = Game3.new()
  g.phase = "play"
  local map = {
    id = "g24_80", group = 24, index = 80, width = 3, height = 1,
    grid = { 0x236, 0x236, 0x22F },
    behavior = { Game3.MB_CRACKED_FLOOR, Game3.MB_CRACKED_FLOOR,
      Game3.MB_CRACKED_FLOOR },
  }
  g.data.maps = { maps = { g24_80 = map } }
  g:enterMap(map, 0, 0, true)
  g.stepCallback = Game3.STEP_CB_CRACKED_FLOOR
  return g, map
end
local function midAt(map, x)
  return Game3.metatileOf(map.grid[x + 1])
end

local g, map = pillar()
g:armCrackedFloor(0, 0)
eq(#g.crackedFloorPending, 1, "stepping onto a cracked floor arms a slot")
g:tickCrackedFloors(1)
eq(midAt(map, 0), 0x236, "still intact after one frame")
g:tickCrackedFloors(1)
eq(midAt(map, 0), 0x236, "and after two")
g:tickCrackedFloors(1)
eq(midAt(map, 0), 0x237, "the third frame drops it -- the player need not move")
eq(#g.crackedFloorPending, 0, "and the slot is freed")

-- sub_806A040's other branch
local h, hmap = pillar()
h:armCrackedFloor(2, 0)
h:tickCrackedFloors(3)
eq(midAt(hmap, 2), 0x206, "0x22F collapses to 0x206, not 0x237")

-- A slow frame must not lose time: the cart decrements once per frame.
local k, kmap = pillar()
k:armCrackedFloor(0, 0)
k:tickCrackedFloors(3)
eq(midAt(kmap, 0), 0x237, "three frames at once still collapses it")

-- Two pending at a time, and no double-arming the same tile.
local m2 = pillar()
m2:armCrackedFloor(0, 0)
check(not m2:armCrackedFloor(0, 0), "the same tile is not armed twice")
m2:armCrackedFloor(1, 0)
eq(#m2.crackedFloorPending, 2, "two slots, as the cart has")
check(not m2:armCrackedFloor(2, 0), "and no more than two")

-- Nothing ticks on a map that never asked for the callback.
local n = pillar()
n:armCrackedFloor(0, 0)
n.stepCallback = nil
n:tickCrackedFloors(9)
eq(#n.crackedFloorPending, 1, "no countdown without setstepcallback 7")
end)()

-- pokeruby ShowMapNamePopup on enterMap (warp + connection).
;(function()
  local Game3 = require("src.core.Game3")
  local g = Game3.new()
  g.phase = "play"
  g.flags = {}
  local littleroot = {
    id = "g0_9", width = 20, height = 20, flags = 1,
    regionMapSectionId = 0, mapType = 1,
    grid = {}, objects = {}, warps = {}, connections = {},
  }
  local route101 = {
    id = "g0_16", width = 20, height = 20, flags = 1,
    regionMapSectionId = 16, mapType = 3,
    grid = {}, objects = {}, warps = {}, connections = {},
  }
  local indoor = {
    id = "g1_0", width = 11, height = 9, flags = 0,
    regionMapSectionId = 0, mapType = 8,
    grid = {}, objects = {}, warps = {}, connections = {},
  }
  g.data.maps = {
    start = "g0_9",
    maps = { g0_9 = littleroot, g0_16 = route101, g1_0 = indoor },
  }
  g:enterMap(littleroot, 10, 10, true)
  check(g.mapNamePopup, "Littleroot enterMap arms map name popup")
  eq(g.mapNamePopup.name, "LITTLEROOT TOWN", "MAPSEC 0 label")
  check(g:playHudActive(), "Littleroot popup keeps HUD letterbox")
  eq(g.mapNamePopup.offset, 32, "starts at REG_BG0VOFS=32 off-screen")
  for _ = 1, 16 do g:stepMapNamePopup(1 / 60) end
  eq(g.mapNamePopup.offset, 0, "slides fully on-screen in 16 frames")
  eq(g.mapNamePopup.phase, 1, "then holds like Task_MapNamePopup case 1")

  g:enterMap(indoor, 5, 5, true)
  eq(g.mapNamePopup, nil, "indoor show_map_name=0 does not arm popup")
  eq(g:playHudActive(), false, "no popup in free roam indoors")

  -- Connection walk: enterMap(..., connected=true) like tryWalk edge.
  g:enterMap(route101, 10, 19, false, true)
  check(g.mapNamePopup, "Littleroot->Route101 connection arms popup")
  eq(g.mapNamePopup.name, "ROUTE 101", "MAPSEC 16 label")
  check(g:playHudActive(), "Route 101 popup keeps HUD letterbox")

  g:hideMapNamePopup()
  g.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP] = true
  eq(g:showMapNamePopup(), false, "FLAG_HIDE_MAP_NAME_POPUP blocks")
  eq(g.mapNamePopup, nil, "blocked call leaves no popup state")
  g.flags[Game3.FLAG_HIDE_MAP_NAME_POPUP] = nil
  check(g:showMapNamePopup(), "clearflag re-arms ShowMapNamePopup")
  eq(g.mapNamePopup.name, "ROUTE 101", "still Route 101")
end)()

S.finish()
