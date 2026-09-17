-- Battle animation sheets come from the cart, not the decomp checkout.
--
-- Game3MoveAnim / Game3BattleFx used to point SPRITE_DIR at
-- misc/pokeruby-master/.../graphics/battle_anims/sprites/. misc/ is not in
-- pack_love.sh's include list, so on device every sheet was missing --
-- loadTagImage caches `false` on a miss, so each animation quietly fell back to
-- its procedural stand-in with no error. Fixture bytes only.
--
--   luajit tests/engine/ruby_battle_anims_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local ID = {}
ID.__index = ID
function ID:getWidth() return self.w end
function ID:getHeight() return self.h end
function ID:setPixel(x, y, r, g, b, a) self.px[y * self.w + x] = { r, g, b, a } end
function ID:getPixel(x, y)
  local p = self.px[y * self.w + x]
  if not p then return 0, 0, 0, 0 end
  return p[1], p[2], p[3], p[4]
end
function ID:mapPixel(fn)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do self.px[y * self.w + x] = { fn(x, y, 0, 0, 0, 0) } end
  end
end
love.image.newImageData = function(w, h)
  return setmetatable({ w = w, h = h, px = {} }, ID)
end

local S = require("tests.harness").suite("ruby battle anims")
local check = S.check
local eq = S.eq

local Anim = require("src.import.RomExtractorGen3Anim")
local MoveAnim = require("src.core.Game3MoveAnim")
local Fx = require("src.core.Game3BattleFx")

-- ------------------------------------------------- nothing reads misc/ now

eq(MoveAnim.SPRITE_DIR, "assets/generated/battle_anims/",
  "MoveAnim loads sheets from the extracted cache")
eq(Fx.SPRITE_DIR, "assets/generated/battle_anims/",
  "and so does BattleFx")
check(not MoveAnim.SPRITE_DIR:find("misc/", 1, true),
  "no runtime path reaches into the decomp checkout")

-- -------------------------------------------------------------- ROM tables

eq(Anim.RUBY_US.picTable, 0x37E164, "gBattleAnimPicTable")
eq(Anim.RUBY_US.palTable, 0x37EA6C, "gBattleAnimPaletteTable")
eq(Anim.RUBY_US.count, 289, "289 sheets")
eq(Anim.RUBY_US.entry, 8, "CompressedSpriteSheet is ptr + u16 size + u16 tag")

-- Every tag the engine asks for must have a layout, or it extracts at the
-- wrong shape and the draw path (which renders the whole sheet under 40px
-- wide) smears it.
local wanted = { 135, 137, 29, 155, 148, 147, 10, 11, 73, 115, 157, 233 }
for _, tag in ipairs(wanted) do
  check(Anim.SHEET_TILES[tag] ~= nil,
    ("sheet %03d has an explicit layout"):format(tag))
end

-- ---------------------------------------------------------------- fixture

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

-- one 8x8 tile, every pixel index 1, stored uncompressed-style lz77
local tile = string.rep(string.char(0x11), 32)
local function lzWrap(raw)
  local out = { string.char(0x10) .. string.char(#raw % 256)
    .. string.char(math.floor(#raw / 256) % 256) .. string.char(0) }
  local i = 1
  while i <= #raw do
    local n = math.min(8, #raw - i + 1)
    out[#out + 1] = string.char(0) .. raw:sub(i, i + n - 1)
    i = i + n
  end
  return table.concat(out)
end
local sheet = lzWrap(tile)
local pal = {}
for i = 0, 15 do pal[#pal + 1] = u16(i == 1 and 0x001F or 0) end
pal = lzWrap(table.concat(pal))

local PIC, PAL, SHEET, PALDATA = 0x100, 0x200, 0x300, 0x400
local rom = {}
rom[#rom + 1] = string.rep("\0", PIC)
rom[#rom + 1] = u32(0x08000000 + SHEET) .. u16(32) .. u16(10000)
rom[#rom + 1] = string.rep("\0", PAL - PIC - 8)
rom[#rom + 1] = u32(0x08000000 + PALDATA) .. u16(10000) .. u16(0)
rom[#rom + 1] = string.rep("\0", SHEET - PAL - 8)
rom[#rom + 1] = sheet
rom[#rom + 1] = string.rep("\0", PALDATA - SHEET - #sheet)
rom[#rom + 1] = pal
rom = table.concat(rom)

local saved, savedDims = Anim.RUBY_US, Anim.SHEET_TILES
Anim.RUBY_US = { picTable = PIC, palTable = PAL, count = 1, entry = 8 }
Anim.SHEET_TILES = { [0] = { 1, 1 } }

local img = Anim.renderSheet(rom, 0)
check(img ~= nil, "a sheet renders from the pic/palette tables")
eq(img:getWidth(), 8, "one tile wide")
eq(img:getHeight(), 8, "one tile tall")
eq(math.floor(select(1, img:getPixel(0, 0)) * 255), 255,
  "palette index 1 resolves to the ROM palette's red")

-- Index 0 keeps its real colour: keyPalette0Alpha samples pixel (0,0) and keys
-- by colour, exactly as it did for the indexed PNGs these replace.
local _, _, _, a = img:getPixel(0, 0)
eq(a, 1, "sheets are emitted opaque; the engine does the keying")

Anim.RUBY_US, Anim.SHEET_TILES = saved, savedDims

-- ------------------------------------------------------------- the contract

local Contract = require("src.import.CacheContract")
-- A floor, not a pin: every extractor added after this one bumps the version
-- again, and a test that pins the exact string just breaks on the next one.
-- What matters is that the version moved past the build with no anim sheets.
local ver = tonumber(tostring(Contract.VERSION_FORMAT.ruby):match("ruby(%d+):"))
check(ver ~= nil, "the ruby cache version parses")
check(ver >= 82, "and is at or past the bump that added battle anim sheets")
local need = {}
for _, f in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
  need[f] = true
end
check(need["assets/generated/battle_anims/135.png"],
  "a sheet is a required cache output, so a cache without them is rebuilt")

S.finish()
