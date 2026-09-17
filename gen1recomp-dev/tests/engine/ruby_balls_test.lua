-- Poke Ball sprites come from the cart.
--
-- They were baked from the pokeruby decomp into assets/generated/battle/
-- ruby_balls/ -- a directory pack_love.sh excludes -- so Game3:loadRubyBallSheet
-- found nothing on device. Its README called them a "ROM extract" while listing
-- decomp PNGs as the source. Fixture bytes only.
--
--   luajit tests/engine/ruby_balls_test.lua

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

local S = require("tests.harness").suite("ruby balls")
local check = S.check
local eq = S.eq

local Balls = require("src.import.RomExtractorGen3Balls")
local Game3 = require("src.core.Game3")

-- ------------------------------------------------------------ ROM tables

eq(Balls.RUBY_US.sheets, 0x20A92C, "gBallSpriteSheets")
eq(Balls.RUBY_US.palettes, 0x20A98C, "gBallSpritePalettes")
eq(Balls.RUBY_US.count, 12, "twelve ball types")

-- Table order is by sprite tag (55000+), which is NOT the item order the
-- engine maps from; getting these out of step swaps every ball's artwork.
eq(Balls.NAMES[0], "poke", "tag 55000 is the standard ball")
eq(Balls.NAMES[2], "safari", "tag 55002 is safari, ahead of ultra")
eq(Balls.NAMES[3], "ultra", "tag 55003 is ultra")
eq(Balls.NAMES[11], "premier", "tag 55011 is premier")

-- Every name the engine can ask for must be one this module writes.
local written = {}
for i = 0, Balls.RUBY_US.count - 1 do written[Balls.NAMES[i]] = true end
for _, name in pairs(Game3.RUBY_BALL_BY_ITEM) do
  check(written[name], ("the engine's %s ball is extracted"):format(name))
end

eq(Balls.DIR, "assets/generated/battle/ruby_balls/",
  "written where loadRubyBallSheet looks")
eq(Game3.RUBY_BALL_DIR, Balls.DIR, "extractor and loader agree on the path")

-- --------------------------------------------------------------- fixture

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
    math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function lzWrap(raw)
  local out = { string.char(0x10, #raw % 256, math.floor(#raw / 256) % 256, 0) }
  local i = 1
  while i <= #raw do
    local n = math.min(8, #raw - i + 1)
    out[#out + 1] = string.char(0) .. raw:sub(i, i + n - 1)
    i = i + n
  end
  return table.concat(out)
end

-- Twelve tiles: tile t filled with index (t % 3) + 1, so each of the three
-- frames is a flat, distinguishable colour.
local tiles = {}
for t = 0, 11 do
  local idx = (math.floor(t / 4) % 3) + 1
  tiles[#tiles + 1] = string.rep(string.char(idx * 17), 32)
end
local gfx = lzWrap(table.concat(tiles))
local palRaw = {}
for i = 0, 15 do
  local v = 0
  if i == 1 then v = 0x001F elseif i == 2 then v = 0x03E0 elseif i == 3 then v = 0x7C00 end
  palRaw[#palRaw + 1] = u16(v)
end
local pal = lzWrap(table.concat(palRaw))

local SH, PL, GFX, PALD = 0x100, 0x200, 0x300, 0x500
local rom = {}
rom[#rom + 1] = string.rep("\0", SH)
rom[#rom + 1] = u32(0x08000000 + GFX) .. u16(0x180) .. u16(55000)
rom[#rom + 1] = string.rep("\0", PL - SH - 8)
rom[#rom + 1] = u32(0x08000000 + PALD) .. u16(55000) .. u16(0)
rom[#rom + 1] = string.rep("\0", GFX - PL - 8)
rom[#rom + 1] = gfx
rom[#rom + 1] = string.rep("\0", PALD - GFX - #gfx)
rom[#rom + 1] = pal
rom[#rom + 1] = string.rep("\0", 0x400)
rom = table.concat(rom)

local saved = Balls.RUBY_US
Balls.RUBY_US = { sheets = SH, palettes = PL, entry = 8, count = 1,
  tradeBallGfx = 0, tradeBallPal = 0, tradeBallFrames = 1,
  displayGfx = 0, displayPal = 0, displayTiles = 1 }

local strip = Balls.renderBall(rom, 0)
check(strip ~= nil, "a ball renders from the sheet/palette tables")
eq(strip:getWidth(), 48, "three 16px frames side by side")
eq(strip:getHeight(), 16, "one frame tall")

-- The rearrangement is the point: ROM stacks frames down, the engine quads
-- across. Frame n must land at x = n*16, not y = n*16.
eq(math.floor(select(1, strip:getPixel(0, 0)) * 255), 255, "frame 0 is red")
eq(math.floor(select(2, strip:getPixel(16, 0)) * 255), 255, "frame 1 is green at x=16")
eq(math.floor(select(3, strip:getPixel(32, 0)) * 255), 255, "frame 2 is blue at x=32")

Balls.RUBY_US = saved

-- -------------------------------------------------------------- contract

local Contract = require("src.import.CacheContract")
local need = {}
for _, f in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
  need[f] = true
end
check(need["assets/generated/battle/ruby_balls/poke.png"],
  "the ball sheet is a required cache output")
check(need["assets/generated/battle/ruby_balls/poke_closed.png"],
  "and so is the closed frame the catch animation opens from")

S.finish()
