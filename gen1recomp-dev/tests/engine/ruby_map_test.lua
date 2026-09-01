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
check(not Game3.shouldAnimCorner(127, 0, { 120, 121, 127, 128 }, 1),
  "water-edge foam does not borrow the flower flip")
check(not Game3.shouldAnimCorner(128, 0, { 127, 128, 129, 130 }, 1, 1),
  "solid harbor walls do not blink")
check(Game3.shouldAnimCorner(127, 0, { 127, 128, 129, 130 }, 1, 0),
  "walkable flowers still sway")
check(Game3.shouldAnimCorner(120, Game3.MB_OCEAN_WATER, nil, nil, 1),
  "surfable ocean still sways through collision")
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
check(g:tryWalk(0, 1), "step off the pad")
eq(g.map.id, "g13_23", "still inside")
check(g:tryWalk(0, -1), "step onto MAP_DYNAMIC")
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
check(g:tryWalk(0, -1), "step onto the hideout pad")
eq(g.map.id, "g24_75", "0x67 warps via the pad event")
eq(g.playerX, 1, "dest warp x")
eq(g.playerY, 1, "dest warp y")
check(g.ignoreWarp, "land on the dest pad")

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
  local g = Game3.new()
  g.money = 5000
  g:openMartList({ 1 }, "decor")
  eq(g.field.martKind, "decor", "kind is decor")
  local ok, msg = g:buyMartItem(1, "decor")
  check(ok, "bought a desk")
  eq(g.money, 2000, "SMALL DESK is 3000")
  eq(g.decorations[1], 1, "AddDecoration")
  check(msg:find("SMALL DESK", 1, true) ~= nil, "desk name")
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
g.field = { kind = "party" }
  check(not g:fieldShowsWorld(), "party covers the map")
  g.field = nil
  g.viewW, g.viewH = 480, 320
  g.map = { width = 40, height = 40 }
  g.camX, g.camY = 0, 0
  local x0, y0, x1, y1 = g:visibleRange()
  eq(x1, math.floor(480 / Game3.TILE), "survey view reaches tile 30, not 14")
  eq(y1, math.floor(320 / Game3.TILE), "survey view reaches tile 20, not 9")
  -- Player stays at view centre even on a map bigger than the window, so
  -- connected maps and the 2x2 border stay visible at the edge.
  g.map = { width = 10, height = 10 }
  g.playerX, g.playerY = 0, 0
  g:clampCamera()
  eq(g.camX, Game3.snapPixel(8 - 240), "wide view keeps the player centred")
  eq(g.camY, Game3.snapPixel(8 - 160), "tall view keeps the player centred")
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
  eq(g:borderPad(), Game3.MAP_OFFSET * Game3.TILE, "towns keep the GBA ring")
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

-- Land wanderers stay off water (collision 0 + surfable). Reflections
-- follow IsReflective, including the tile a 32px sprite covers north of
-- the feet, so the pond-bank sign shows a face.
;(function()
  local Game3 = require("src.core.Game3")
  eq(Game3.elevationOf(4 * 4096), 4, "elevation is bits 12-15")
  check(Game3.zMismatch(4, 3), "cycling road is above the dirt")
  check(not Game3.zMismatch(4, 0), "map z 0 is any height")
  check(not Game3.zMismatch(0, 3), "object z 0 skips the check")
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
  check(g:actorReflects(0, 2, false, 32), "bank south of the pond reflects")
  check(not g:actorReflects(2, 2, false, 32), "dry ground does not")
  check(not g:actorReflects(0, 2, true, 32), "hideReflection skips it")
  g.map.behavior = {
    0, 0, 0,
    Game3.MB_OCEAN_WATER, 0, 0,
    Game3.MB_OCEAN_WATER, 0, 0,
  }
  check(not g:actorReflects(0, 2, false, 32), "standing by ocean does not mirror")

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

S.finish()
