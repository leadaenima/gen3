-- Mugshot transition art comes from the cart.
--
-- Baked from the decomp into assets/generated/battle/transitions/ (excluded
-- from game.love), so Game3BattleTransition found nothing on device and fell
-- back to procedural chevrons. Fixture bytes only.
--
--   luajit tests/engine/ruby_transitions_test.lua

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

local S = require("tests.harness").suite("ruby transitions")
local check = S.check
local eq = S.eq

local T = require("src.import.RomExtractorGen3Transition")

eq(T.RUBY_US.tiles, 0x3FC348, "elite four bg tiles")
eq(T.RUBY_US.tilemap, 0x3FDFF4, "elite four bg tilemap")
eq(T.RUBY_US.opponentPals, 0x3FDB00, "opponent palette pointer table")
eq(T.RUBY_US.playerPals, 0x3FDB14, "player palette pointer table")
eq(#T.NAMES, 5, "five Elite Four backgrounds")
eq(T.NAMES[1], "sidney", "order matches the opponent palette table")
eq(T.NAMES[5], "steven", "steven last")

-- ---------------------------------------------------------------- fixture

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local TILES, MAP, OPPT, PLT, OPP, PLAYER = 0x100, 0x400, 0x900, 0x920, 0x940, 0x960
local rom = {}
rom[#rom + 1] = string.rep("\0", TILES)
-- tile 0: every nibble 0. Rendering is pal[15 - n], so this must resolve to
-- palette slot 15, not slot 0 -- that inversion is the whole trick.
rom[#rom + 1] = string.rep(string.char(0x00), 32)
-- tile 1: every nibble 5 -> palette slot 10, the first slot the player owns
rom[#rom + 1] = string.rep(string.char(0x55), 32)
rom[#rom + 1] = string.rep("\0", MAP - TILES - 64)
for cell = 0, 32 * 20 - 1 do rom[#rom + 1] = u16(cell == 1 and 1 or 0) end
rom[#rom + 1] = string.rep("\0", OPPT - MAP - 32 * 20 * 2)
rom[#rom + 1] = u32(0x08000000 + OPP)
rom[#rom + 1] = string.rep("\0", PLT - OPPT - 4)
rom[#rom + 1] = u32(0x08000000 + PLAYER)
rom[#rom + 1] = string.rep("\0", OPP - PLT - 4)
-- Opponent slot 10 is green. Slots 10..15 are BOTH overwritten by the merge,
-- so the opponent's own values there only matter as the thing that must lose.
local o = {}
for i = 0, 15 do
  o[#o + 1] = u16(i == 10 and 0x03E0 or 0)
end
rom[#rom + 1] = table.concat(o)
rom[#rom + 1] = string.rep("\0", PLAYER - OPP - 32)
-- Player colour 0 -> slot 10 (blue), colour 5 -> slot 15 (red).
local pl = {}
for i = 0, 15 do
  local v = 0
  if i == 0 then v = 0x7C00 elseif i == 5 then v = 0x001F end
  pl[#pl + 1] = u16(v)
end
rom[#rom + 1] = table.concat(pl)
rom[#rom + 1] = string.rep("\0", 64)
rom = table.concat(rom)

local saved = T.RUBY_US
T.RUBY_US = { tiles = TILES, tilemap = MAP, opponentPals = OPPT, playerPals = PLT,
  stevenGfx = 0, stevenPal = 0 }

local img = T.renderBackground(rom, 0, 0)
check(img ~= nil, "a background renders from tiles + map + palettes")
eq(img:getWidth(), 256, "full width is 256; the tilemap wraps past the screen")
eq(img:getHeight(), 160, "160 tall")

-- nibble 0 -> pal[15]: reading it as pal[0] would give black here
eq(math.floor(select(1, img:getPixel(0, 0)) * 255), 255,
  "tile nibble 0 resolves through pal[15 - n] to slot 15, not slot 0")

-- tile 1's nibble 5 -> pal[10], which the merge has replaced with the player's
-- first colour, so this is blue rather than the opponent's green.
eq(math.floor(select(3, img:getPixel(8, 0)) * 255), 255,
  "slot 10 carries the player colour merged in by LoadPalette(0xFA, 0xC)")
eq(math.floor(select(2, img:getPixel(8, 0)) * 255), 0,
  "and not the opponent's own slot 10")

local cropped = T.renderBackground(rom, 0, 0, 240)
eq(cropped:getWidth(), 240, "the _240 variant is the visible screen only")

T.RUBY_US = saved

-- -------------------------------------------------------------- contract

local Contract = require("src.import.CacheContract")
local need = {}
for _, f in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
  need[f] = true
end
check(need["assets/generated/battle/transitions/mugshot_bg_steven_240.png"],
  "a mugshot background is a required cache output")
check(need["assets/generated/battle/transitions/steven_mugshot.png"],
  "and so is the portrait drawn over it")

S.finish()
