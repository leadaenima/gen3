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
local TILES, GRID, EVENTS, WARPS, DUMMY = 0x2800, 0x2A00, 0x2B00, 0x2C00, 0x2D00

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
  .. GbaBin.packPtr(DUMMY)
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
host.flags = {}
Gen3Script.run(host, ops)
eq(host.flags[0xA5], true, "a defeated gym leader runs the next opcode")
eq(host.flags[0x807], nil, "and does not re-run RoxanneDefeated")

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

local Game3 = require("src.core.Game3")
local field = Game3.new()
field.data.maps = { start = hoenn.start, maps = hoenn.maps }
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

local blocked = Game3.new()
blocked.data.maps = { maps = { g0_0 = { width = 2, height = 1, grid = { 0, 0 },
  objects = { { x = 1, y = 0, graphicsId = 8 } } } } }
blocked:enterMap(blocked.data.maps.maps.g0_0, 0, 0, false)
check(not blocked:tryWalk(1, 0), "an object event occupies its cell")
eq(blocked.playerX, 0, "NPC collision does not move")

field:enterMap(hoenn.maps.g0_0, 0, 0, false)
check(field:tryWalk(0, -1), "walk north off the town")
eq(field.map.id, "g0_1", "north connection is the route")
eq(field.playerY, 1, "appear on the south edge of the route")
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
eq(g:npcAt(indoor, 2, 1), nil, "and does not block the tile")

g.facing = "west"
local npc = g:facingNpc()
check(npc, "wanderer is west of the player")
local ox, oy = npc.x, npc.y
check(g:tryTalk(), "A talks")
eq(npc.facing, "east", "NPC faces the player")
check(npc.talkLock, "and is locked")
npc.wait = 0
npc.cooldown = 0
g:stepNpcs(2)
eq(npc.x, ox, "locked NPC does not wander x")
eq(npc.y, oy, "or y")
eq(npc.facing, "east", "or turn away")
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

S.finish()
