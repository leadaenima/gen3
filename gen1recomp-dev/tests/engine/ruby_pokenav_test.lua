-- Pokenav art comes from the cart.
--
-- The Pokenav screens were drawn with flat love.graphics rectangles and no
-- pokenav art was extracted at all. Addresses come from pokeruby's symbol
-- names, which are themselves addresses, and from pokenav.c's VRAM loads.
-- Fixture bytes only -- the copyrighted .gba is not in git.
--
--   luajit tests/engine/ruby_pokenav_test.lua

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

local S = require("tests.harness").suite("ruby pokenav")
local check = S.check
local eq = S.eq

local P = require("src.import.RomExtractorGen3Pokenav")

-- ------------------------------------------------------------- addresses

eq(P.RUBY_US.outlineTiles, 0x3E05F4, "gPokenavOutlineTiles")
eq(P.RUBY_US.outlineTilemap, 0x3E0804, "gPokenavOutlineTilemap")
eq(P.RUBY_US.outlinePal, 0x3E05D4, "gPokenavOutlinePalette")
eq(P.RUBY_US.pokeballTiles, 0x3E3680, "gPokenavPokeballTiles")
eq(P.RUBY_US.sparklePal, 0x3E37A0, "gPokenavSparkle_Pal sits just before the gfx")
eq(P.DIR, "assets/generated/pokenav/", "written where the UI will look")

-- pokenav.c loads the outline tiles at VRAM + 0x8020, i.e. tile 1, so tilemap
-- entries are one higher than the sheet index. Reading them as-is shifts every
-- tile by one and the shell comes out as garbage.
eq(P.RUBY_US.outlineFirstTile, 1, "outline tiles are uploaded from VRAM tile 1")

-- --------------------------------------------------------------- fixture

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local TILES, PAL, MAP = 0x40, 0x200, 0x300
local rom = {}
rom[#rom + 1] = string.rep("\0", TILES)
-- sheet index 0 is every pixel index 1; index 1 is index 2
rom[#rom + 1] = string.rep(string.char(0x11), 32)
rom[#rom + 1] = string.rep(string.char(0x22), 32)
rom[#rom + 1] = string.rep("\0", PAL - TILES - 64)
local pal = {}
for i = 0, 15 do
  local v = 0
  if i == 1 then v = 0x001F elseif i == 2 then v = 0x03E0 end
  pal[#pal + 1] = u16(v)
end
rom[#rom + 1] = table.concat(pal)
rom[#rom + 1] = string.rep("\0", MAP - PAL - 32)
-- tile ids are VRAM-relative: 1 -> sheet 0, 2 -> sheet 1
for cell = 0, 32 * 20 - 1 do
  rom[#rom + 1] = u16(cell == 1 and 2 or 1)
end
rom[#rom + 1] = string.rep("\0", 0x200)
rom = table.concat(rom)

local saved = P.RUBY_US
P.RUBY_US = { outlineTiles = TILES, outlineTilemap = MAP, outlinePal = PAL,
  outlineFirstTile = 1 }

local img = P.renderLayer(rom, TILES, false, 64, MAP, false, PAL, 1)
check(img ~= nil, "a BG layer renders from tiles + tilemap + palette")
eq(img:getWidth(), 240, "the visible screen is 240 wide")
eq(img:getHeight(), 160, "and 160 tall")
eq(math.floor(select(1, img:getPixel(0, 0)) * 255), 255,
  "tilemap id 1 minus the VRAM base resolves to sheet tile 0 -> red")
eq(math.floor(select(2, img:getPixel(8, 0)) * 255), 255,
  "and id 2 resolves to sheet tile 1 -> green")

local sheet = P.renderSheet(rom, TILES, 64, PAL, false)
eq(sheet:getWidth(), 16, "an OBJ sheet is laid out as a row of tiles")
eq(sheet:getHeight(), 8, "one tile tall")

P.RUBY_US = saved

-- -------------------------------------------------------------- contract

local Contract = require("src.import.CacheContract")
local need = {}
for _, f in ipairs(Contract.VERSION_REQUIRED_FILES_OVERRIDE.ruby or {}) do
  need[f] = true
end
check(need["assets/generated/pokenav/outline.png"],
  "the Pokenav shell is a required cache output")
local ver = tonumber(tostring(Contract.VERSION_FORMAT.ruby):match("ruby(%d+):"))
check(ver ~= nil and ver >= 86, "and the cache version moved so caches re-import")

-- ---------------------------------------------- menu geometry + labels

local Game3 = require("src.core.Game3")

-- pokenav.c sub_80F1BC8 arg0 == 0: topOffset 42, height 20, five options.
eq(Game3.POKENAV_ROW_H, 20, "row pitch is the cart's height 20")
eq(Game3.POKENAV_TOP, 34, "and topOffset 42 less the 8px sprite centre")
eq(Game3.POKENAV_CARD_X, 136, "resting x is 152 less the 16px centre offset")
eq(Game3.POKENAV_SLIDE_FROM, 104, "rows start 256-152 px to the right")

local items = Game3.new():pokenavMenuItems()
eq(#items, 5, "five options, as menu_options has five cards")
eq(items[1], "HOENN MAP", "cart label, not MAP")
eq(items[3], "TRAINER'S EYES", "cart label, not TRAINER'S EYE")
eq(items[5], "SWITCH OFF", "cart label, not CANCEL")

-- The slide runs from off-screen right to the resting x, later rows trailing.
local g = Game3.new()
local f = { cursor = 0, slide = 0 }
local x0 = g:pokenavRowX(f, 0)
eq(x0, Game3.POKENAV_CARD_X + Game3.POKENAV_SLIDE_FROM,
  "at slide 0 the first row is still fully off to the right")
f.slide = 1
eq(g:pokenavRowX(f, 0), Game3.POKENAV_CARD_X, "the first row lands at the resting x")
check(g:pokenavRowX(f, 4) > Game3.POKENAV_CARD_X,
  "and at that point a later row is still arriving -- the rows are staggered")

-- But the stagger must RESOLVE. Each row subtracts i * ROW_STAGGER from the
-- progress, so the slide has to run past 1.0 or the last row parks short of
-- its rest position forever -- which is exactly what shipped, with this test
-- asserting the parked position as correct.
-- Drive it from the span the draw actually caps at, so a cap that is too
-- small fails here rather than shipping.
f.slide = Game3.pokenavSlideSpan()
for i = 0, Game3.POKENAV_ROWS_MAX - 1 do
  eq(g:pokenavRowX(f, i), Game3.POKENAV_CARD_X,
    ("row %d finishes at the resting x"):format(i))
end

-- ------------------------------------------- the card tile arrangement

-- Each option is four 32x16 segments of 8 tiles laid out 4 wide by 2 tall.
-- Blitting the 160-tile sheet in raw order interleaves the rows and the
-- labels become unreadable, so drive the real renderer and pin where a tile
-- lands: tile 4 starts a segment's SECOND row, so it must sit BELOW tile 0.
local function lzWrap(raw)
  local out = { string.char(0x10, #raw % 256, math.floor(#raw / 256) % 256, 0) }
  local i2 = 1
  while i2 <= #raw do
    local n = math.min(8, #raw - i2 + 1)
    out[#out + 1] = string.char(0) .. raw:sub(i2, i2 + n - 1)
    i2 = i2 + n
  end
  return table.concat(out)
end

-- tile 0 -> colour 1 (red), tile 4 -> colour 2 (green), everything else 3
local sheet = {}
for n = 0, 159 do
  local idx = 3
  if n == 0 then idx = 1 elseif n == 4 then idx = 2 end
  sheet[#sheet + 1] = string.rep(string.char(idx * 17), 32)
end
local blob = lzWrap(table.concat(sheet))
local PALOFF, GFXOFF = 0x20, 0x100
local pieces = { string.rep(string.char(0), PALOFF) }
for i2 = 0, 15 do
  local v = 0
  if i2 == 1 then v = 0x001F elseif i2 == 2 then v = 0x03E0 elseif i2 == 3 then v = 0x7C00 end
  pieces[#pieces + 1] = string.char(v % 256, math.floor(v / 256) % 256)
end
pieces[#pieces + 1] = string.rep(string.char(0), GFXOFF - PALOFF - 32)
pieces[#pieces + 1] = blob
local romCards = table.concat(pieces)

local savedUS = P.RUBY_US
P.RUBY_US = { menuOptionsGfx = GFXOFF, menuPal1 = PALOFF,
  menuOptionsCards = 5, menuOptionsTilesPerCard = 32 }
local cards = P.renderMenuCards(romCards)
check(cards ~= nil, "the card sheet renders")
eq(cards:getWidth(), 128, "a card is four 32px segments wide")
eq(cards:getHeight(), 80, "five cards of 16px")
eq(math.floor(select(1, cards:getPixel(0, 0)) * 255), 255,
  "tile 0 is the top-left of the first segment")
eq(math.floor(select(2, cards:getPixel(0, 8)) * 255), 255,
  "tile 4 starts the segment's second row, so it sits 8px BELOW tile 0")
eq(math.floor(select(2, cards:getPixel(32, 0)) * 255), 0,
  "and NOT 32px to its right, which is what raw tile order would give")
P.RUBY_US = savedUS

-- ------------------------------------------- the condition pentagon

-- pokenav.c sub_80F55AC: vertex 0 is COOL straight up from (0x9B, 0x5B), then
-- TOUGH, SMART, CUTE, BEAUTY counter-clockwise. Reading them in the usual
-- stat order (cool/beauty/cute/smart/tough) mirrors the graph.
local pg = Game3.new()
eq(Game3.PENTAGON_CX, 0x9B, "pentagon centre x")
eq(Game3.PENTAGON_CY, 0x5B, "pentagon centre y")
eq(Game3.PENTAGON_KEYS[2], "tough", "the second vertex is TOUGH, not BEAUTY")
eq(Game3.PENTAGON_KEYS[5], "beauty", "and BEAUTY is last")

local flat = pg:conditionPentagon({ cool = 255, tough = 255, smart = 255,
  cute = 255, beauty = 255 })
eq(#flat, 5, "five vertices")
eq(flat[1][1], Game3.PENTAGON_CX, "vertex 0 sits directly above the centre")
check(flat[1][2] < Game3.PENTAGON_CY, "and above it, not below")
-- a regular pentagon: the two upper-side vertices share a y, as do the lower
eq(flat[2][2], flat[5][2], "the upper pair are level")
eq(flat[3][2], flat[4][2], "and so are the lower pair")
check(flat[2][1] > Game3.PENTAGON_CX, "vertex 2 is to the right")
check(flat[5][1] < Game3.PENTAGON_CX, "vertex 5 to the left")

-- an all-zero mon collapses to the centre, which is what the cart shows for
-- an empty slot (0x9B, 0x5B).
local zero = pg:conditionPentagon({})
check(math.abs(zero[1][2] - Game3.PENTAGON_CY) <= 6,
  "a blank mon draws a tiny pentagon at the centre")

-- Pin the exact vertices for a maxed mon. The loose symmetry checks above
-- miss the +1 angle correction at index 2 and the pixel nudge on the left
-- side, so without this a geometry drift passes clean.
local want = { { 155, 56 }, { 189, 81 }, { 176, 120 }, { 134, 120 }, { 121, 81 } }
for i = 1, 5 do
  eq(flat[i][1], want[i][1], ("vertex %d x"):format(i))
  eq(flat[i][2], want[i][2], ("vertex %d y"):format(i))
end

-- At radius 35 the +1 angle correction at index 2 happens to round away, so
-- the maxed case above cannot see it. It bites at 40 of the 61 radii; stat 16
-- maps to radius 12, where it moves the vertex a pixel.
local mid = pg:conditionPentagon({ cool = 16, tough = 16, smart = 16,
  cute = 16, beauty = 16 })
local wantMid = { { 155, 79 }, { 167, 88 }, { 163, 101 }, { 147, 101 }, { 143, 88 } }
for i = 1, 5 do
  eq(mid[i][1], wantMid[i][1], ("mid-range vertex %d x"):format(i))
  eq(mid[i][2], wantMid[i][2], ("mid-range vertex %d y"):format(i))
end


-- ------------------------------------------------------- screen headers
--
-- sub_80F29B8 creates the header as TWO sprites 64px apart, each taking a
-- different anim frame of gSpriteAnimTable_83E44D4 (frame 0, 32, 64).
-- Frame 0 is 8 tiles across by 4 down. On the four 48-tile sheets the
-- second frame has only 16 tiles left and they are laid FOUR across, not
-- eight -- the occupancy runs '### . ### . ### . . . .', a stride of 4.
-- Reading them 8-wide split the title: CONDITION rendered as CONDITIO, a
-- gap, then a stranded N.
local function lz77(payload)
  local out = { string.char(0x10, #payload % 256,
    math.floor(#payload / 256) % 256, math.floor(#payload / 65536) % 256) }
  local i = 1
  while i <= #payload do
    out[#out + 1] = string.char(0)
    out[#out + 1] = payload:sub(i, i + 7)
    i = i + 8
  end
  return table.concat(out)
end

-- every tile is pixel index 1 except tile 36, which is index 2
local function headerSheet(tileCount, oddTile)
  local t = {}
  for n = 0, tileCount - 1 do
    t[#t + 1] = string.rep(string.char(n == oddTile and 0x22 or 0x11), 32)
  end
  return table.concat(t)
end

local HOFF, HPAL = 0x80, 0x2000
local function headerRom(tileCount, oddTile)
  local body = lz77(headerSheet(tileCount, oddTile))
  local parts = { string.rep(string.char(0), HOFF), body,
    string.rep(string.char(0), HPAL - HOFF - #body) }
  local pal = {}
  for i = 0, 15 do
    local v = 0
    if i == 1 then v = 0x001F elseif i == 2 then v = 0x03E0 end
    pal[#pal + 1] = u16(v)
  end
  parts[#parts + 1] = table.concat(pal)
  parts[#parts + 1] = string.rep(string.char(0), 0x200)
  return table.concat(parts)
end

local hdrRom = headerRom(48, 36)
local hdr = P.renderHeader(hdrRom, HOFF, HPAL)
check(hdr ~= nil, 'a 48-tile header sheet composes')
eq(hdr:getWidth(), 96, 'a 64px left block plus a 32px right block')
eq(hdr:getHeight(), 32, 'the sprite pair is 32 tall')

-- tile 36 is the fifth tile of the right block. Four across puts it on the
-- second row at (64, 8); eight across would put it at (96, 0), off the end.
eq(math.floor(select(2, hdr:getPixel(64, 8)) * 255), 255,
  'the right block starts a new row every four tiles')
eq(math.floor(select(1, hdr:getPixel(64, 0)) * 255), 255,
  'and its first row is still the plain tile')
eq(math.floor(select(1, hdr:getPixel(0, 0)) * 255), 255,
  'the left block fills from the sheet origin')
-- the right block never reads past the end of the sheet: a short sheet
-- leaves the rows it has no tiles for clear instead of wrapping.
local short = P.renderHeader(headerRom(40, -1), HOFF, HPAL)
eq(math.floor(select(1, short:getPixel(64, 8)) * 255), 255,
  'the eight tiles it does have fill two rows')
eq(select(4, short:getPixel(64, 16)), 0, 'and it stops where the sheet does')

-- the 96-tile map sheet is the exception: two full 8-wide right halves,
-- one for FULL VIEW and one for the zoomed view
local mapHdr = P.renderHeader(headerRom(96, 68), HOFF, HPAL, 64, 8)
eq(mapHdr:getWidth(), 128, 'the map header is two 64px blocks')
eq(math.floor(select(2, mapHdr:getPixel(96, 0)) * 255), 255,
  'whose right half is laid eight across')

-- --------------------------------------------- menu card palette split
--
-- sub_80F1BC8: rows past the third get oam.paletteNum = the sprite palette
-- at tag 1, which sub_80F2514 loaded with pokenav2. The RIBBONS card's body
-- uses indices C..E, which only pokenav1 lacks -- drawn with pokenav1 it
-- comes out solid black.
eq(P.RUBY_US.menuPal1, 0xE88A28, 'pokenav1.gbapal')
eq(P.RUBY_US.menuPal2, 0xE88A48, 'pokenav2.gbapal')
eq(P.RUBY_US.menuPal3, 0xE88A68, 'pokenav3.gbapal, which the headers take')
eq(P.RUBY_US.conditionPal1, 0xE89958,
  'the CONDITION option cards have their own palette, not the main menu one')

local rowSheets = {}
local gm = Game3.new()
gm.drawPokenavChrome = function() end
gm.drawPokenavHeader = function() end
gm.pokenavImage = function(_, name)
  rowSheets[#rowSheets + 1] = name
  return { getDimensions = function() return 128, 80 end }
end
gm:drawPokenavMenu({ slide = 99, cursor = 0 })
local altCount = 0
for _, name in ipairs(rowSheets) do
  if name == 'menu_options_alt.png' then altCount = altCount + 1 end
end
eq(altCount, 2, 'the last two rows come off the pokenav2 sheet')

-- ------------------------------------------------ header vs text title
--
-- 'has and nil or title' always yields the title in Lua, so the first cut
-- of this drew the header art AND the placeholder text over it.
local titles = {}
local gt = Game3.new()
gt.drawPokenavChrome = function(_, title) titles[#titles + 1] = title or false end
gt.drawPokenavHeader = function() return true end
gt.pokenavImage = function() return {} end
gt:drawPokenavScreen('condition_header.png', 'CONDITION')
eq(titles[1], false, 'with header art the chrome draws no text title')
gt.pokenavImage = function() return nil end
gt:drawPokenavScreen('condition_header.png', 'CONDITION')
eq(titles[2], 'CONDITION', 'without it the text title is the fallback')

-- the header sits where sub_80F29B8 parks the sprites: x 32 and 96 centred
-- on a 64px width is a left edge of 0, and y 49 on a 32px height is 33.
eq(Game3.POKENAV_HEADER_X, 0, 'header left edge')
eq(Game3.POKENAV_HEADER_Y, 33, 'header top edge')


-- --------------------------------------------- condition screen backdrop
--
-- BG3 on this screen is the text window (charbase 0), and condition_view
-- went to VRAM 0x5000, so condition_screen.bin's tile ids start at 640.
eq(P.RUBY_US.conditionScreenMap, 0xE9AC4C, 'condition_screen.bin.lz')
eq(P.RUBY_US.conditionScreenFirstTile, 640, '0x5000 / 32')
eq(P.RUBY_US.conditionPal2, 0xE8A1C0, 'condition2.gbapal, palette bank 2')

-- condition_view tile 0 is a 1px interlace of palette indices 5 and 3, and
-- it is what the player actually sees around the panels: a capture of the
-- stock screen stripes 73E373 green against 849AFF blue, row by row, across
-- the whole field.
--
-- An earlier renderer flood-filled those two indices in from the screen edge
-- and replaced them with the flat window colour, on the theory that BG2 and
-- the bottom toolbar had to be covering them. They do not. Indices 5 and 3
-- are also the SMART and BEAUTY blob colours inside the panel, so that fill
-- was erasing real art in two places at once to hide art that was correct.
-- Every tile draws; nothing is skipped and nothing is filled.
local CV, CM, CP = 0x80, 0x800, 0x3000
local function conditionRom()
  local tiles = {}
  local t0 = {}
  for y = 0, 7 do
    local n = (y % 2 == 0) and 5 or 3
    t0[#t0 + 1] = string.rep(string.char(n * 16 + n), 4)
  end
  -- tile 1 carries the interlace and surrounds the panel, the way the real
  -- field tile does; tile 0 is left blank so a renderer that special-cased
  -- it has nothing to hide behind.
  tiles[#tiles + 1] = string.rep(string.char(0), 32)      -- 0: blank
  tiles[#tiles + 1] = table.concat(t0)                    -- 1: the interlace
  tiles[#tiles + 1] = string.rep(string.char(0x55), 32)   -- 2: solid index 5
  tiles[#tiles + 1] = string.rep(string.char(0x11), 32)   -- 3: solid index 1
  local gfx = lz77(table.concat(tiles))
  local map = {}
  for row = 0, 19 do
    for col = 0, 31 do
      local tile = 1
      if row >= 8 and row <= 10 and col >= 8 and col <= 10 then
        tile = (row == 9 and col == 9) and 2 or 3
      end
      map[#map + 1] = u16(640 + tile)
    end
  end
  local tm = lz77(table.concat(map))
  local parts = { string.rep(string.char(0), CV), gfx,
    string.rep(string.char(0), CM - CV - #gfx), tm,
    string.rep(string.char(0), CP - CM - #tm) }
  local pal = {}
  for i = 0, 15 do
    local v = 0
    if i == 1 then v = 0x001F elseif i == 3 then v = 0x7C00
    elseif i == 5 then v = 0x03E0 elseif i == 15 then v = 0x7FFF end
    pal[#pal + 1] = u16(v)
  end
  parts[#parts + 1] = table.concat(pal)
  parts[#parts + 1] = string.rep(string.char(0), 0x200)
  return table.concat(parts)
end

local savedRuby = P.RUBY_US
P.RUBY_US = { conditionViewGfx = CV, conditionScreenMap = CM,
  conditionScreenFirstTile = 640, conditionPal2 = CP }
local cs = P.renderConditionScreen(conditionRom())
check(cs ~= nil, 'the condition screen backdrop composes')
eq(cs:getWidth(), 240, 'a full screen wide')
eq(cs:getHeight(), 160, 'and tall')

-- the field keeps its stripes: green on even rows, blue on odd, all the way
-- to the screen edge, which is exactly where the old flood fill started
eq(math.floor(select(2, cs:getPixel(0, 0)) * 255), 255,
  'row 0 of the field is the green stripe, not a flat fill')
eq(math.floor(select(1, cs:getPixel(0, 0)) * 255), 0, 'green, not white')
eq(math.floor(select(3, cs:getPixel(0, 1)) * 255), 255, 'row 1 is the blue one')
eq(math.floor(select(2, cs:getPixel(0, 1)) * 255), 0,
  'blue, not white -- a fill to the window colour would read as both')
eq(math.floor(select(2, cs:getPixel(0, 2)) * 255), 255, 'row 2 green again')
-- the same two indices inside the panel are blob art and are equally kept
eq(math.floor(select(2, cs:getPixel(76, 76)) * 255), 255,
  'a solid run of the stripe colour inside the panel is a blob, and stays')
eq(math.floor(select(1, cs:getPixel(76, 76)) * 255), 0, 'still green')
-- and the panel border around it is ordinary art
eq(math.floor(select(1, cs:getPixel(68, 68)) * 255), 255, 'the ring is drawn')
P.RUBY_US = savedRuby

-- ------------------------------------------------------- ribbon icons
--
-- DrawMonRibbonIcons builds a 16x16 icon from TWO tiles: the left column is
-- tile and tile+1, the right column is the same pair with the tilemap hflip
-- bit set. Only the left halves exist in the cart.
eq(P.RUBY_US.ribbonIconTiles, 0x3E040C,
  'gUnknown_083E040C, uploaded to VRAM 0x8200 = charbase 2 tile 0x10')
eq(P.RUBY_US.ribbonIconPals, 0x3E3C60, 'five contest palettes')
eq(P.RUBY_US.ribbonIconTable, 0x3E4698, 'gPokenavRibbonsIconGfx')
eq(P.RUBY_US.ribbonIconCount, 32, 'CHAMPION, 5 categories x 4 ranks, then 11')

local RI, RP, RT = 0x80, 0x400, 0x600
local function ribbonRom()
  -- tile 0 has its left column set and nothing else, so a mirrored copy
  -- lands on the right column and a plain one does not
  local t = {}
  for y = 0, 7 do t[#t + 1] = string.char(0x20, 0, 0, 0) end
  local gfx = lz77(table.concat(t) .. string.rep(string.char(0), 32))
  local parts = { string.rep(string.char(0), RI), gfx,
    string.rep(string.char(0), RP - RI - #gfx) }
  local pal = {}
  for i = 0, 15 do
    pal[#pal + 1] = u16(i == 2 and 0x001F or 0)
  end
  parts[#parts + 1] = table.concat(pal)
  parts[#parts + 1] = string.rep(string.char(0), RT - RP - 32)
  parts[#parts + 1] = u16(0) .. u16(0)   -- icon 0, palette 0
  parts[#parts + 1] = string.rep(string.char(0), 0x200)
  return table.concat(parts)
end
P.RUBY_US = { ribbonIconTiles = RI, ribbonIconPals = RP, ribbonIconTable = RT,
  ribbonIconCount = 1 }
local icons = P.renderRibbonIcons(ribbonRom())
check(icons ~= nil, 'the ribbon icons assemble')
eq(icons:getWidth(), 16, 'one 16px icon per entry')
eq(icons:getHeight(), 16, 'each two tiles tall')
eq(math.floor(select(1, icons:getPixel(1, 0)) * 255), 255,
  'the left column comes straight off the sheet')
eq(math.floor(select(1, icons:getPixel(14, 0)) * 255), 255,
  'and the right column is its mirror, not a second stored tile')
eq(select(4, icons:getPixel(0, 0)), 0, 'index 0 stays transparent')
P.RUBY_US = savedRuby

-- the condition screen asks for its own backdrop, not the menu device field
local asked = {}
local gb = Game3.new()
gb.drawPokenavChrome = function() end
gb.drawPokenavHeader = function() return true end
gb.drawText = function() end
gb.pokenavImage = function(_, name) asked[name] = true; return {} end
gb:drawPokenavScreen('condition_header.png', 'CONDITION', 'condition_screen.png')
check(asked['condition_screen.png'],
  'the sub-screen draws the cart backdrop the screen actually has')


-- ------------------------------------------------ text line spacing
--
-- FONT3 is 16 pixels tall and font4 is 8. Rows laid out on a pitch shorter
-- than their own face overlap, and it is invisible in a preview that
-- substitutes a shorter placeholder font -- which is exactly how the
-- condition stat list ended up on a 12px pitch and the ribbon list ended up
-- starting four pixels inside the nickname. Drive the real draw and assert
-- that nothing sharing a column collides.
local function columnOverlaps(screen, setup)
  local rows = {}
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function() return true end
  g.drawPokenavScreen = function() return true end
  g.pokenavImage = function() return nil end
  g.drawCursor = function() end
  g.drawRibbonIcon = function() return true end
  g.ribbonDescription = function() return { "CHAMPION RIBBON", "Won the league" } end
  g.conditionPentagon = function() return {} end
  g.menuArt = function() return { font = "font_small.png" } end
  g.menuPic = function() return nil end
  -- width from the cart's own sFont3Widths; font4 glyphs are never wider,
  -- so using it for the small face too can only over-estimate, and an
  -- over-estimate that still passes is a real clearance.
  local function put(t, x, y, h)
    rows[#rows + 1] = { text = tostring(t), x = x, y = y, h = h,
      w = Game3.textWidth(tostring(t)) }
  end
  g.drawText = function(_, t, x, y) put(t, x, y, 16) end
  g.drawSmallText = function(_, _art, t, x, y) put(t, x, y, 8) end
  setup(g)
  screen(g)
  local bad = nil
  for i = 1, #rows do
    for j = i + 1, #rows do
      local a, b = rows[i], rows[j]
      local left = math.max(a.x, b.x)
      local right = math.min(a.x + a.w, b.x + b.w)
      local top = math.max(a.y, b.y)
      local bot = math.min(a.y + a.h, b.y + b.h)
      if right > left and bot > top and not bad then
        bad = ('%s at (%d,%d) and %s at (%d,%d) overlap %dx%d'):format(
          a.text, a.x, a.y, b.text, b.x, b.y, right - left, bot - top)
      end
    end
  end
  return bad, #rows
end

;(function()
  local mon = { name = "ZIGZAGOON", cool = 120, tough = 200, smart = 60,
                cute = 255, beauty = 90, sheen = 40 }
  local bad, n = columnOverlaps(
    function(g) g:drawPokenavCondition({ monIndex = 1 }) end,
    function(g) g.party = { mon } end)
  check(n > 5, "the condition screen drew its stat column")
  check(bad == nil, "condition rows clear each other: " .. tostring(bad))
end)()

;(function()
  local mon = { name = "ZIGZAGOON", cool = 1, tough = 1, smart = 1,
                cute = 1, beauty = 1, sheen = 1 }
  local bad, n = columnOverlaps(
    function(g) g:drawPokenavRibbons({ monIndex = 1, cursor = 1,
      ribbons = { 1, 2, 3, 4, 5, 6, 7 } }) end,
    function(g) g.party = { mon } end)
  check(n > 4, "the ribbons screen drew its list")
  check(bad == nil, "ribbon rows clear each other: " .. tostring(bad))
end)()

-- the stat list is on the 8px face, so its pitch only has to clear 8
check(Game3.POKENAV_STAT_ROW >= 8,
  "the condition stat pitch clears the font4 line height")
check(Game3.POKENAV_STAT_TOP >= 62 + 16,
  "and the first row starts below the FONT3 nickname")


-- ------------------------------------------- title bar and message box
--
-- The root menu draws three BGs, and two of them were missing entirely.
-- REG_BG1CNT 0x1B0C (charbase 3, screenbase 27) is the POKeMON NAVIGATOR
-- bar: gPokenavHoennMapMisc_Gfx tiles under the gUnknown_08E99FB0 map, on
-- gPokenavHoennMap1_Pal at bank 1. REG_BG0CNT 0x1F01 (charbase 0, screenbase
-- 31) is the cream message box across the bottom.
eq(P.RUBY_US.bannerTiles, 0xE88D4C, "gPokenavHoennMapMisc_Gfx")
eq(P.RUBY_US.bannerTilemap, 0xE99FB0, "gUnknown_08E99FB0")
eq(P.RUBY_US.bannerPal, 0xE89628, "gPokenavHoennMap1_Pal")

-- gUnknown_083DFEEC is DmaCopy16'd to VRAM 0x5000, so its tiles answer to ids
-- 640 and up -- the map's ids are 641..644. Read from tile 0 they resolve to
-- nothing and the box never appears, which is how it went missing.
eq(P.RUBY_US.miscTiles, 0x3DFEEC, "gUnknown_083DFEEC")
eq(P.RUBY_US.miscTilemap, 0x3DFF8C, "gUnknown_083DFF8C")
eq(P.RUBY_US.miscFirstTile, 640, "0x5000 / 32")

-- The device emblem: sub_80F4024 makes it a 32x32 OBJ at (218, 14), so its
-- corner is (202, -2), and gSpriteAnimTable_83E4844 steps eight frames
-- sixteen tiles apart at twelve ticks each.
eq(Game3.POKENAV_ICON_X, 202, "218 less the 16px centre offset")
eq(Game3.POKENAV_ICON_Y, -2, "14 less the same, so it clips the top edge")
eq(Game3.POKENAV_ICON_FRAMES, 8, "eight anim frames")
eq(Game3.POKENAV_ICON_TICKS, 12, "twelve ticks a frame")
eq(Game3.pokenavIconFrame(0), 0, "first frame at rest ")
eq(Game3.pokenavIconFrame(12 / 60), 1, "advances after twelve ticks")
eq(Game3.pokenavIconFrame(8 * 12 / 60), 0, "and wraps after eight")

-- the root menu has to actually draw all three
;(function()
  local asked = {}
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function() return true end
  g.drawText = function() end
  g.pokenavImage = function(_, name)
    asked[name] = true
    return { getDimensions = function() return 128, 256 end }
  end
  g:drawPokenavMenu({ slide = 99, cursor = 0 })
  check(asked["banner.png"], "the root menu draws the NAVIGATOR title bar")
  check(asked["misc_layer.png"], "and the message box along the bottom")
  check(asked["icons.png"], "and the animated device emblem")
end)()


-- --------------------------------------- stat column vs the graph panel
--
-- condition_screen.bin puts the graph panel's left edge at x 96 on every row
-- of the stat band. The values were left-aligned at 84, so a three-digit one
-- ran six pixels under the panel border; they are right-aligned now.
eq(Game3.POKENAV_STAT_VALUE_RIGHT, 94, "two pixels clear of the panel")
check(Game3.POKENAV_STAT_VALUE_RIGHT < 96,
  "which is where condition_screen.bin starts drawing the panel")
;(function()
  local worst, at = 0, nil
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function() return true end
  g.drawPokenavScreen = function() return true end
  g.pokenavImage = function() return nil end
  g.conditionPentagon = function() return {} end
  g.menuArt = function() return nil end   -- force the FONT3 path, the wider one
  local function note(t, x, y)
    if y < 76 then return end
    local right = x + Game3.textWidth(tostring(t))
    if right > worst then worst, at = right, tostring(t) end
  end
  g.drawText = function(_, t, x, y) note(t, x, y) end
  g.drawSmallText = function(_, _a, t, x, y) note(t, x, y) end
  g.party = { { name = "ZIGZAGOON", cool = 120, tough = 200, smart = 60,
               cute = 255, beauty = 90, sheen = 40 } }
  g:drawPokenavCondition({ monIndex = 1 })
  check(worst <= 96,
    ("the stat column stays out of the panel (%s reached x %d)"):format(
      tostring(at), worst))
end)()


-- ------------------------------------------- menu pop-out and help line
--
-- sub_80F22B0: once a row has finished sliding in, the SELECTED one keeps
-- going -- its x2 offset steps 4px a frame until it reaches -16 -- while the
-- others step back toward 0 at the same rate. That pop-out is the whole of
-- how the cart shows the selection; it does NOT dim the unselected rows, and
-- the engine used to draw them at 0.72 grey instead of popping anything.
eq(Game3.POKENAV_POP_OUT, -16, "the selected row rests 16px left")
eq(Game3.POKENAV_POP_STEP, 4, "moving 4px a frame")
;(function()
  local g = Game3.new()
  local f = { cursor = 1 }
  -- one frame in, it has only moved one step
  eq(g:pokenavPopOut(f, 1, 1), -4, "one frame is one step")
  for _ = 1, 10 do g:pokenavPopOut(f, 1, 1) end
  eq(g:pokenavPopOut(f, 1, 1), Game3.POKENAV_POP_OUT,
    "and it settles at -16 rather than running past")
  -- an unselected row returns to flush
  for _ = 1, 10 do g:pokenavPopOut(f, 1, 0) end
  eq(g:pokenavPopOut(f, 1, 0), 0, "a deselected row comes back to 0")
end)()

;(function()
  -- and the cards draw untinted, selection or not
  local alphas = {}
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function() return true end
  g.drawPokenavOverlay = function() end
  g.drawPokenavIcon = function() end
  g.pokenavHelpText = function() return nil end
  g.drawText = function() end
  g.pokenavImage = function()
    return { getDimensions = function() return 128, 80 end }
  end
  local realDraw = love.graphics.draw
  local realSet = love.graphics.setColor
  local cur = { 1, 1, 1, 1 }
  love.graphics.setColor = function(r, gg, b, a) cur = { r, gg, b, a } end
  love.graphics.draw = function() alphas[#alphas + 1] = cur[1] end
  g:drawPokenavMenu({ slide = 99, cursor = 1 })
  love.graphics.draw = realDraw
  love.graphics.setColor = realSet
  local dim = 0
  for _, r in ipairs(alphas) do if r < 0.99 then dim = dim + 1 end end
  eq(dim, 0, "no card is drawn dimmed -- the cart never tints them")
end)()

-- sub_80EF428: AlignStringInMenuWindow(.., 0xC0, 2) centres the help line in
-- 192px, and Menu_PrintText(.., 3, 17) puts it at tile (3, 17) = (24, 136).
-- gUnknown_083E31B0 holds seven strings for five rows: the extra two are the
-- 'no RIBBON winners' / 'no TRAINERS registered' lines for a locked option.
eq(P.RUBY_US.menuHelpTable, 0x3E31B0, "gUnknown_083E31B0")
eq(P.RUBY_US.menuHelpCount, 7, "five options plus two empty-state lines")
eq(Game3.POKENAV_HELP_X, 24, "tile 3 across")
eq(Game3.POKENAV_HELP_Y, 136, "tile 17 down")
eq(Game3.POKENAV_HELP_W, 0xC0, "centred in 192px")
;(function()
  local g = Game3.new()
  g.pokenavData = function()
    return { menuHelp = { "one", " Check POKeMON in detail.", "three" } }
  end
  eq(g:pokenavHelpText({ cursor = 1 }), " Check POKeMON in detail.",
    "the line follows the cursor")
  eq(g:pokenavHelpText({ cursor = 9 }), nil, "and is absent past the end")
  g.pokenavData = function() return nil end
  eq(g:pokenavHelpText({ cursor = 0 }), nil, "or without the data pack")
end)()

-- ...and drawPokenavMenu has to apply it. Asserting only the helper let the
-- call site be removed silently -- the same gap that lost the bag's dots.
;(function()
  local xs = {}
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function() return true end
  g.drawPokenavOverlay = function() end
  g.drawPokenavIcon = function() end
  g.pokenavHelpText = function() return nil end
  g.drawText = function() end
  g.pokenavImage = function()
    return { getDimensions = function() return 128, 80 end }
  end
  local realDraw = love.graphics.draw
  love.graphics.draw = function(_, _, x) xs[#xs + 1] = x end
  local f = { slide = 99, cursor = 1 }
  for _ = 1, 8 do
    for i = #xs, 1, -1 do xs[i] = nil end
    g:drawPokenavMenu(f)
  end
  love.graphics.draw = realDraw
  check(#xs >= 5, "five rows drew")
  eq(xs[2], xs[1] + Game3.POKENAV_POP_OUT,
    "the cursor row draws a full pop-out left of its neighbours")
  eq(xs[3], xs[1], "and the others stay flush")
end)()


-- --------------------------------------- the sub-screen help tables
--
-- sub_80EF428 takes a table selector: 0 is the root menu's seven strings,
-- 1 the CONDITION menu's three, 2 the condition search's six. The three
-- tables are contiguous -- 0x3E31B0 + 7*4 = 0x3E31CC + 3*4 = 0x3E31D8 --
-- which is what fixes each count: the word after the last entry of one
-- table is the first entry of the next, and the word after the search
-- table decodes to garbage.
eq(P.RUBY_US.conditionHelpTable, P.RUBY_US.menuHelpTable + P.RUBY_US.menuHelpCount * 4,
  "the CONDITION table starts where the root menu's ends")
eq(P.RUBY_US.searchHelpTable,
  P.RUBY_US.conditionHelpTable + P.RUBY_US.conditionHelpCount * 4,
  "and the search table where CONDITION's ends")
eq(P.RUBY_US.conditionHelpTable, 0x3E31CC, 'gUnknown_083E31CC')
eq(P.RUBY_US.searchHelpTable, 0x3E31D8, 'gUnknown_083E31D8')
eq(P.RUBY_US.conditionHelpCount, 3, 'PARTY PKMN / SEARCH / CANCEL')
eq(P.RUBY_US.searchHelpCount, 6,
  'five contest categories and the CANCEL row, not just four')

-- and the strings themselves, off the cart, checked against the captures
do
  local rf = io.open('misc/Pokemon - Ruby Version (USA).gba', 'rb')
  if rf then
    local rom = rf:read('*a')
    rf:close()
    local cond = P.readHelpTable(rom, P.RUBY_US.conditionHelpTable,
      P.RUBY_US.conditionHelpCount)
    eq(#cond, 3, 'three CONDITION lines decode')
    eq(cond[1], ' Check party POKeMON in detail.', 'PARTY PKMN')
    eq(cond[2], ' Check all POKeMON in detail.', 'SEARCH')
    eq(cond[3], ' Return to the POKeNAV menu.', 'CANCEL')
    local srch = P.readHelpTable(rom, P.RUBY_US.searchHelpTable,
      P.RUBY_US.searchHelpCount)
    eq(#srch, 6, 'six search lines decode')
    eq(srch[1], ' Find cool POKeMON.', 'COOL')
    eq(srch[5], ' Find tough POKeMON.', 'TOUGH, which a count of 4 cut off')
    eq(srch[6], ' Return to the CONDITION menu.', 'and its CANCEL row')
    -- the word past the end is not a string, which is what ends the table
    local past = P.readHelpTable(rom, P.RUBY_US.searchHelpTable + 6 * 4, 1)
    check(past[1] == nil or past[1]:find('POKeMON') == nil,
      'nothing readable follows the search table')
    -- the root menu's own lines still read, including the two locked ones
    local menu = P.readMenuHelp(rom)
    eq(#menu, 7, 'seven root-menu lines')
    eq(menu[1], ' Check the map of the HOENN region.', 'HOENN MAP')
    eq(menu[6], ' There are no RIBBON winners.',
      'the locked-RIBBONS line sub_80EF428(0, 5) prints')
    eq(menu[7], ' No TRAINERS are registered.',
      "and the locked TRAINER'S EYES one")
  end
end

-- extractData has to ship all three, or the sub-screens have no help line
do
  local rf = io.open('misc/Pokemon - Ruby Version (USA).gba', 'rb')
  if rf then
    local rom = rf:read('*a')
    rf:close()
    local wrote
    local LuaWriter = require('src.import.LuaWriter')
    local realWrite = LuaWriter.write
    LuaWriter.write = function(_, t) wrote = t end
    P.extractData(rom)
    LuaWriter.write = realWrite
    check(wrote ~= nil, 'extractData writes the pokenav data pack')
    eq(#(wrote.menuHelp or {}), 7, 'the pack carries the root menu help')
    eq(#(wrote.conditionHelp or {}), 3, 'the CONDITION menu help')
    eq(#(wrote.searchHelp or {}), 6, 'and the search help')
  end
end


-- ------------------------------- RIBBONS and TRAINER'S EYES when empty
--
-- pokenav_before.c case 4 and case 6: pressing A on an option that exists
-- but has nothing behind it does NOT open the screen. The cart plays
-- PlaySE(0x20) -- SE_FAILURE -- swaps the help line for one of the two
-- trailing strings in gUnknown_083E31B0, and parks in state 0xFF. The
-- engine used to open a blank RIBBONS screen and an empty TRAINER'S EYES
-- list instead, which is why those two strings had been extracted but were
-- unreachable.
eq(Game3.POKENAV_REJECT_RIBBONS, 6, 'sub_80EF428(0, 5), 1-based')
eq(Game3.POKENAV_REJECT_TRAINERS, 7, 'sub_80EF428(0, 6), 1-based')
;(function()
  local Input = require("src.core.Input")
  local g = Game3.new()
  g.party = {}
  g.pc = {}
  g.trainersEyeList = function() return {} end
  g.pokenavData = function()
    return { menuHelp = {
      'map', 'condition', 'eyes', 'ribbons', 'switch off',
      ' There are no RIBBON winners.', ' No TRAINERS are registered.',
    } }
  end
  local played = {}
  g.playSe = function(_, id) played[#played + 1] = id end
  local function press(key)
    local old = Input.wasPressed
    Input.wasPressed = function(_, k) return k == key end
    g:stepPokenavMenu(g.field)
    Input.wasPressed = old
  end

  local items = g:pokenavMenuItems()
  local ribbonRow, eyeRow
  for i, name in ipairs(items) do
    if name == 'RIBBONS' then ribbonRow = i - 1 end
    if name == "TRAINER'S EYES" then eyeRow = i - 1 end
  end
  check(ribbonRow ~= nil, 'the menu has a RIBBONS row')
  check(eyeRow ~= nil, "and a TRAINER'S EYES row")

  -- no mon anywhere holds a ribbon
  check(not g:hasRibbonWinner(), 'an empty party and empty boxes win nothing')
  g.field = { kind = 'pokenav_menu', cursor = ribbonRow, items = items }
  press('a')
  eq(g.field.kind, 'pokenav_menu',
    'A on an empty RIBBONS does not open the screen')
  eq(g.field.reject, Game3.POKENAV_REJECT_RIBBONS, 'it parks in state 0xFF')
  eq(played[#played], Game3.SE_FAILURE, 'with the error tone, not SE_SELECT')
  eq(g:pokenavHelpText(g.field), ' There are no RIBBON winners.',
    'and the help line says so')
  -- A again only dismisses it; it does not then open the screen
  press('a')
  eq(g.field.reject, nil, 'the next A clears the rejection')
  eq(g.field.kind, 'pokenav_menu', 'without opening anything')
  eq(g:pokenavHelpText(g.field), 'ribbons', 'the normal line comes back')
  -- and moving off it clears it too
  press('a')
  eq(g.field.reject, Game3.POKENAV_REJECT_RIBBONS, 'rejected again')
  press('down')
  eq(g.field.reject, nil, 'DOWN clears it')
  check(g.field.cursor ~= ribbonRow, 'and moves in the same press')

  -- the same for an unregistered TRAINER'S EYES
  g.field = { kind = 'pokenav_menu', cursor = eyeRow, items = items }
  press('a')
  eq(g.field.kind, 'pokenav_menu', 'A on an empty TRAINER list is refused')
  eq(g.field.reject, Game3.POKENAV_REJECT_TRAINERS, 'with the other string')
  eq(g:pokenavHelpText(g.field), ' No TRAINERS are registered.',
    'which is the one the cart prints')

  -- one ribbon anywhere in storage unlocks it, boxes included
  g.pc = {}
  for b = 1, Game3.BOX_COUNT do g.pc[b] = {} end
  g.pc[Game3.BOX_COUNT][30] = { championRibbon = true }
  check(g:hasRibbonWinner(),
    'a ribbon in the last slot of the last box counts -- sub_80F6250 walks' ..
    ' every box before the party')
  g.field = { kind = 'pokenav_menu', cursor = ribbonRow, items = items }
  press('a')
  eq(g.field.reject, nil, 'so A is not refused')
  eq(g.field.kind, 'pokenav_ribbons', 'and the screen opens')
end)()


-- ------------------------- the CONDITION menu and the condition search
--
-- sub_80F1BC8 is one routine driving three card lists, differing only in
-- topOffset / height / row count. Pinning all three together is what keeps
-- the shared draw honest -- a geometry change that suits one list and
-- breaks another shows up here rather than on screen.
;(function()
  local L = Game3.POKENAV_LISTS
  -- arg0 0: topOffset 42, height 20, 5 rows
  eq(L.menu.top, 34, 'the root menu cards start at 42 - 8')
  eq(L.menu.rowH, 20, 'on a 20px pitch')
  -- arg0 1: topOffset 56, height 20, 3 rows
  eq(L.condition.top, 48, 'the CONDITION menu at 56 - 8')
  eq(L.condition.rowH, 20, 'same pitch')
  -- arg0 2: topOffset 40, height 16, 6 rows
  eq(L.search.top, 32, 'the search list at 40 - 8')
  eq(L.search.rowH, 16, 'and a tighter 16px pitch, to fit six rows')
  -- the i > 2 palette repoint fires for arg0 0 and 2 only; a three-row
  -- list cannot reach it, and sub_80F2514 case 1 loads no tag-1 palette
  eq(L.menu.alt, 3, 'the root menu repoints from row 3')
  eq(L.search.alt, 3, 'so does the search list')
  eq(L.condition.alt, nil,
    'the CONDITION menu does not -- it has no tag-1 palette to repoint to')
  eq(L.condition.help, 'conditionHelp', 'sub_80EF428 table 1')
  eq(L.search.help, 'searchHelp', 'table 2')
  -- the six rows have to fit above the message box at y 136
  check(L.search.top + L.search.rowH * 6 <= Game3.POKENAV_HELP_Y,
    'six 16px rows clear the help line')
end)()

-- the sheets: condition_menu on condition1, the search split across
-- condition6 (COOL/BEAUTY/CUTE) and condition7 (SMART/TOUGH/CANCEL)
eq(P.RUBY_US.conditionSearchGfx, 0xE8AD04,
  'gPokenavConditionSearch_Gfx, found by position in graphics.c')
eq(P.RUBY_US.conditionSearchCards, 6, '192 tiles / 32 per card')
eq(P.RUBY_US.conditionPal6, 0xE8B1C4, 'sprite palette tag 0')
eq(P.RUBY_US.conditionPal7, 0xE8B1E4, 'and tag 1')
eq(Game3.POKENAV_LISTS.search.sheet, 'condition_search.png', 'tag 0 sheet')
eq(Game3.POKENAV_LISTS.search.altSheet, 'condition_search_alt.png',
  'tag 1 sheet -- one sheet for both would flatten five contest colours')
do
  local rf = io.open('misc/Pokemon - Ruby Version (USA).gba', 'rb')
  if rf then
    local rom = rf:read('*a')
    rf:close()
    local u = P.RUBY_US
    -- 6144 bytes decompress out of the search sheet: exactly six cards of
    -- four 32x16 segments, which is what sub_80F1BC8 asks for
    local GbaLz77 = require("src.import.GbaLz77")
    local px = GbaLz77.decompress(rom, u.conditionSearchGfx)
    check(px ~= nil, 'the search sheet decompresses')
    eq(#px / 32, 192, '192 tiles = 6 cards x 4 segments x 8 tiles')
    -- condition7 is the one the decomp flags for holding 0xFFFF where a
    -- palette would normally hold 0x7FFF; that makes it self-identifying
    local lo, hi = rom:byte(u.conditionPal7 + 3, u.conditionPal7 + 4)
    eq(lo + hi * 256, 0xFFFF,
      'condition7 second entry is the 0xFFFF the decomp comments on')
    local img = P.renderMenuCards(rom, u.conditionSearchGfx,
      u.conditionSearchCards, u.conditionPal6)
    check(img ~= nil, 'and the six cards render')
    eq(img:getWidth(), 128, '128px wide')
    eq(img:getHeight(), 96, 'six 16px rows tall')
  end
end

-- CONDITION opens the menu, not the graph
;(function()
  local Input = require("src.core.Input")
  local g = Game3.new()
  g.party = { { name = 'ZIGZAGOON', cool = 10, beauty = 90 } }
  g.pc = {}
  local function press(key, fn)
    local old = Input.wasPressed
    Input.wasPressed = function(_, k) return k == key end
    fn(g, g.field)
    Input.wasPressed = old
  end
  g:openPokenavCondition()
  eq(g.field.kind, 'pokenav_condition_menu',
    'CONDITION opens its three-row menu, not the graph')
  eq(#g.field.items, 3, 'PARTY PKMN / SEARCH / CANCEL')
  eq(g.field.items[1], 'PARTY PKMN', 'first row')
  eq(g.field.items[3], 'CANCEL', 'last row')
  -- PARTY PKMN reaches the graph over the party
  press('a', Game3.stepPokenavConditionMenu)
  eq(g.field.kind, 'pokenav_condition', 'PARTY PKMN opens the graph')
  eq(#g.field.list, 1, 'over the party')
  eq(g.field.searchKey, nil, 'unsorted')
  -- and B from the graph lands back on the menu, not out at the root
  press('b', Game3.stepPokenavCondition)
  eq(g.field.kind, 'pokenav_condition_menu',
    'B backs out one level, to the CONDITION menu')
  -- SEARCH reaches the six-row list
  g.field.cursor = 1
  press('a', Game3.stepPokenavConditionMenu)
  eq(g.field.kind, 'pokenav_condition_search', 'SEARCH opens the list')
  eq(#g.field.items, 6, 'five categories plus CANCEL')
  eq(g.field.items[5], 'TOUGH', 'TOUGH is the fifth')
  eq(g.field.items[6], 'CANCEL', 'CANCEL the sixth')
  -- CANCEL on the search goes back up, it does not open a graph
  g.field.cursor = 5
  press('a', Game3.stepPokenavSearch)
  eq(g.field.kind, 'pokenav_condition_menu', 'CANCEL backs out')
  -- CANCEL on the CONDITION menu goes out to the root
  g.field.cursor = 2
  press('a', Game3.stepPokenavConditionMenu)
  eq(g.field.kind, 'pokenav_menu', 'and CANCEL there leaves CONDITION')
end)()

-- sub_80ECC08 maps rows 0..4 onto MON_DATA_COOL 22, BEAUTY 23, CUTE 24,
-- SMART 33, TOUGH 47 and sorts the results on that stat. Row 5 is CANCEL
-- and has no key.
eq(#Game3.POKENAV_SEARCH_KEYS, 5, 'five sortable categories')
eq(Game3.POKENAV_SEARCH_KEYS[4], 'smart', 'row 3 is SMART, not TOUGH')
eq(Game3.POKENAV_SEARCH_KEYS[5], 'tough', 'row 4 is TOUGH')
eq(Game3.POKENAV_SEARCH_KEYS[6], nil, 'and CANCEL has none')
;(function()
  local Input = require("src.core.Input")
  local g = Game3.new()
  g.party = { { name = 'A', cool = 10, tough = 5 },
              { name = 'B', cool = 200, tough = 5 } }
  g.pc = {}
  for b = 1, Game3.BOX_COUNT do g.pc[b] = {} end
  g.pc[1][1] = { name = 'BOXED', cool = 255, tough = 5 }
  -- PARTY PKMN is the party only, in party order
  local party = g:conditionList(nil)
  eq(#party, 2, 'the party path does not reach into storage')
  eq(party[1].name, 'A', 'and keeps party order')
  -- SEARCH covers storage too and sorts highest first
  local found = g:conditionList('cool')
  eq(#found, 3, 'the search reaches boxed POKeMON -- Check all POKeMON')
  eq(found[1].name, 'BOXED', 'sorted on the chosen stat, highest first')
  eq(found[2].name, 'B', 'then the next highest')
  eq(found[3].name, 'A', 'then the lowest')
  -- Ties have to keep party-then-box order. Three entries is not enough to
  -- show that: LuaJIT's sort leaves a 3-element all-tied run alone whether
  -- or not the comparator breaks ties, so a 3-mon fixture passes even with
  -- the fallback deleted. Sixteen scrambles badly without it.
  local many = Game3.new()
  many.party = {}
  many.pc = {}
  for b = 1, Game3.BOX_COUNT do many.pc[b] = {} end
  for i = 1, 6 do
    many.party[i] = { name = ('P%d'):format(i), tough = 7 }
  end
  for i = 1, 10 do
    many.pc[1][i] = { name = ('S%d'):format(i), tough = 7 }
  end
  local tied = many:conditionList('tough')
  eq(#tied, 16, 'six in the party and ten in storage')
  local order = {}
  for i = 1, #tied do order[i] = tied[i].name end
  eq(table.concat(order, ' '),
    'P1 P2 P3 P4 P5 P6 S1 S2 S3 S4 S5 S6 S7 S8 S9 S10',
    'an all-tied sort keeps party order then box order')
  -- and picking a category lands on the graph over that sorted list
  g:openPokenavSearch()
  g.field.cursor = 0
  local old = Input.wasPressed
  Input.wasPressed = function(_, k) return k == 'a' end
  g:stepPokenavSearch(g.field)
  Input.wasPressed = old
  eq(g.field.kind, 'pokenav_condition', 'COOL opens the graph')
  eq(g.field.searchKey, 'cool', 'carrying the sort key')
  eq(g.field.list[1].name, 'BOXED', 'over the sorted list')
end)()

-- the help line follows whichever table the screen named
;(function()
  local g = Game3.new()
  g.pokenavData = function()
    return { menuHelp = { 'root' }, conditionHelp = { 'cond' },
      searchHelp = { 'srch' } }
  end
  eq(g:pokenavHelpText({ cursor = 0 }), 'root',
    'the default table is the root menu')
  eq(g:pokenavHelpText({ cursor = 0 }, 'conditionHelp'), 'cond',
    'the CONDITION menu reads its own')
  eq(g:pokenavHelpText({ cursor = 0 }, 'searchHelp'), 'srch',
    'and the search reads a third')
end)()

-- both new screens must actually reach a draw, and draw their own cards
;(function()
  local asked = {}
  local g = Game3.new()
  g.drawPokenavChrome = function() end
  g.drawPokenavHeader = function(_, n) asked[n] = true; return true end
  g.drawPokenavOverlay = function() end
  g.drawPokenavIcon = function() end
  g.drawText = function() end
  g.pokenavHelpText = function() return nil end
  g.pokenavImage = function(_, n)
    asked[n] = true
    return { getDimensions = function() return 128, 96 end }
  end
  g:drawPokenavConditionMenu({ slide = 99, cursor = 0 })
  check(asked['condition_menu.png'], 'the CONDITION menu draws its cards')
  check(asked['condition_header.png'], 'under the CONDITION header')
  asked = {}
  g:drawPokenavSearch({ slide = 99, cursor = 0 })
  check(asked['condition_search.png'], 'the search draws its tag-0 cards')
  check(asked['condition_search_alt.png'],
    'and its tag-1 cards for SMART, TOUGH and CANCEL')
end)()

S.finish()
