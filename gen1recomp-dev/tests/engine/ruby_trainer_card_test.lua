-- Gen 3 trainer card art comes from the cart, not from a baked PNG.
--
-- The art used to be committed under assets/generated/trainer_card/, which
-- pack_love.sh excludes from game.love, so the card drew as a flat fill with
-- text on top in every packaged build while looking correct in a source
-- checkout. Fixture bytes only -- the copyrighted .gba is not in git.
--
--   luajit tests/engine/ruby_trainer_card_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

-- love_stub's ImageData is a no-op, so pixels would be unobservable.
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

local S = require("tests.harness").suite("ruby trainer card")
local check = S.check
local eq = S.eq

local Card = require("src.import.RomExtractorGen3Card")

-- ---------------------------------------------------------------- fixture

local TILES, PAL, MAP = 0x00, 0x400, 0x500
local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end

local rom = {}
-- tile 0 = every pixel index 1; tile 1 = every pixel index 2
-- tile 0: every pixel index 1. tile 1: left half index 2, right half index 1,
-- so a horizontal flip is observable rather than symmetric.
rom[#rom + 1] = string.rep(string.char(0x11), 32)
rom[#rom + 1] = string.rep(string.char(0x22) .. string.char(0x22)
  .. string.char(0x11) .. string.char(0x11), 8)
rom[#rom + 1] = string.rep("\0", PAL - 64)
-- palette: index 1 pure red, index 2 pure green (BGR555)
local pal = { [0] = 0, 0x001F, 0x03E0 }
for i = 0, 15 do rom[#rom + 1] = u16(pal[i] or 0) end
rom[#rom + 1] = string.rep("\0", MAP - PAL - 32)
-- cell 0: tile 1 plain. cell 1: tile 1 with the hflip bit (0x400). cell 2:
-- tile 1 with a palette-bank nibble set (0x1000) -- decoding the entry without
-- masking to 0x3FF would read tile 0x1001 and fall off the sheet.
local CELLS = { [0] = 0x0001, [1] = 0x0401, [2] = 0x1001 }
for cell = 0, Card.MAP_COLS * Card.MAP_ROWS - 1 do
  rom[#rom + 1] = u16(CELLS[cell] or 0)
end
rom = table.concat(rom)

local saved = Card.RUBY_US
Card.RUBY_US = { tiles = TILES, tileCount = 2, frontMap = MAP, backMap = MAP,
  starPal = PAL, starPalStride = 0x60, starGoldPal = PAL, starTile = 1,
  badgeTiles = TILES, badgeBytes = 64, badgePal = PAL }

-- ---------------------------------------------------------------- the card

local front = Card.renderFront(rom, 0)
eq(front:getWidth(), 240, "the card is cropped to the GBA's 240 visible columns")
eq(front:getHeight(), 160, "and is 160 tall")

-- palette index 2 is green, index 1 is red.
local r, g, b = front:getPixel(0, 0)
eq(math.floor(g * 255), 255, "cell 0 is tile 1, whose left half is index 2 -> green")
eq(math.floor(r * 255), 0, "red 0 there")
eq(math.floor(b * 255), 0, "blue 0 there")
eq(math.floor(select(1, front:getPixel(7, 0)) * 255), 255,
  "and its right half is index 1 -> red")

-- hflip: the same tile mirrored, so red now leads and green trails.
eq(math.floor(select(1, front:getPixel(8, 0)) * 255), 255,
  "cell 1 sets the 0x400 hflip bit, so the red half comes first")
eq(math.floor(select(2, front:getPixel(15, 0)) * 255), 255,
  "and the green half is at the right edge")

-- the palette-bank nibble must not leak into the tile id
eq(math.floor(select(2, front:getPixel(16, 0)) * 255), 255,
  "cell 2 carries a 0x1000 palette bank and still resolves to tile 1")

-- 32 columns are mapped but only 30 are on screen; reading past 240 must not
-- wrap or error, which is what the crop in renderMap is for.
check(pcall(function() return front:getPixel(239, 159) end),
  "the bottom-right visible pixel exists")

-- ------------------------------------------------- index 0 stays transparent

local star = Card.renderStar(rom)
eq(star:getWidth(), 8, "the star glyph is one tile")
local _, _, _, a = star:getPixel(0, 0)
eq(a, 1, "a non-zero index is opaque")

Card.RUBY_US = { tiles = TILES, tileCount = 2, frontMap = MAP, backMap = MAP,
  starPal = PAL, starPalStride = 0x60, starGoldPal = PAL, starTile = 0,
  badgeTiles = TILES, badgeBytes = 64, badgePal = PAL }
-- tile 0 is all index 1 here, so force the zero case through the badge sheet
local zeroRom = string.rep("\0", 64) .. rom:sub(65)
Card.RUBY_US.badgeBytes = 64
local badges = Card.renderBadges(zeroRom)
local _, _, _, ba = badges:getPixel(0, 0)
eq(ba, 0, "palette index 0 is keyed to alpha, as GBA OBJ transparency requires")

-- ------------------------------------------------------------ real offsets

Card.RUBY_US = saved
eq(Card.RUBY_US.tiles, 0xE8B4E0, "trainer_card.png tiles")
eq(Card.RUBY_US.frontMap, 0xE8CAC0, "front tilemap")
eq(Card.RUBY_US.backMap, 0xE8CFC0, "back tilemap")
eq(Card.RUBY_US.starPalStride, 0x60, "48 colors between star palettes")
eq(Card.STAR_COUNT, 5, "zero through four stars")

-- The contract must demand the extracted files, or a cache built before they
-- existed still validates and the card ships blank again.
local Contract = require("src.import.CacheContract")
-- The exact version moves with every extractor added, so it is pinned once in
-- ruby_battle_anims_test rather than here; what this suite owns is that the
-- card's own outputs are demanded, which is what forces the re-import.
check(Contract.VERSION_FORMAT.ruby ~= "rom-cache-v10-ruby80:",
  "the ruby cache version moved past the build that lacked card art")
local wanted = false
for _, f in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
  if f == "assets/generated/trainer_card/ruby_front_0.png" then wanted = true end
end
check(wanted, "and the card art is a required cache output")

S.finish()
