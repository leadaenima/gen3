-- Gen 3 Pokenav graphics, read from the player's own cart.
--
-- The Pokenav screens were drawn with flat love.graphics rectangles -- a
-- placeholder with no cart art at all, and nothing under assets/generated to
-- extract from either.
--
-- Addresses come from pokeruby's own symbol names, which ARE addresses
-- (gUnknown_083DFECC -> 0x3DFECC); the handful that are descriptively named
-- were located by matching their bytes, and every one that could be checked
-- against a decomp .bin matched exactly (9/9). Note the decomp ships .png
-- SOURCES next to the .4bpp/.gbapal BUILD PRODUCTS the ROM actually holds --
-- matching against the .png is what makes this look impossible at first.
--
-- VRAM destinations are from pokenav.c, e.g.
--   LZ77UnCompVram(gPokenavOutlineTiles,   VRAM + 0x8020)  -- tiles from index 1
--   LZ77UnCompVram(gPokenavOutlineTilemap, VRAM + 0xE800)
--   LoadPalette   (gPokenavOutlinePalette, 0x40, 0x20)     -- BG palette bank 4
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Pokenav = {}

Pokenav.RUBY_US = {
  -- the device shell: tiles land at VRAM tile 1, hence outlineFirstTile
  outlineTiles = 0x3E05F4,     -- lz77, 43 tiles
  outlineTilemap = 0x3E0804,   -- lz77
  outlinePal = 0x3E05D4,
  outlineFirstTile = 1,

  -- The main menu's BG0 (REG_BG0CNT 0x1F01: charbase 0, screenbase 31).
  -- gUnknown_083DFEEC is DmaCopy16'd to VRAM 0x5000, so a 10-bit tile id
  -- reaches it at 0x5000/32 = 640 -- the tilemap's ids run 641..644 and
  -- resolve to nothing at all if they are read from tile 0. It draws the
  -- cream message box across the bottom, rows 16..19.
  miscTiles = 0x3DFEEC,
  miscTilesBytes = 0xA0,
  miscTilemap = 0x3DFF8C,      -- lz77
  miscPal = 0x3DFECC,
  miscFirstTile = 640,

  -- BG1 (REG_BG1CNT 0x1B0C: charbase 3, screenbase 27): the POKeMON
  -- NAVIGATOR title bar. gPokenavHoennMapMisc_Gfx supplies the tiles and
  -- gUnknown_08E99FB0 the map -- rows 0..1 are the lettering, 2..3 the
  -- gold rules under it, and everything below is one transparent tile so
  -- the bar composites over the device art.
  bannerTiles = 0xE88D4C,      -- gPokenavHoennMapMisc_Gfx, lz77
  bannerTilemap = 0xE99FB0,    -- gUnknown_08E99FB0, lz77
  bannerPal = 0xE89628,        -- gPokenavHoennMap1_Pal, loaded to bank 1

  altTiles = 0x3E005C,
  altTilemap = 0x3E007C,       -- lz77
  altPal = 0x3E003C,

  iconTiles = 0x3E329C,        -- lz77
  iconPal = 0x3E327C,

  trainerEyesTiles = 0x3E0354, -- lz77
  trainerEyesPal = 0x3E0334,

  -- OBJ sheets: sizes from gUnknown_083E4590 / gUnknown_083E4628
  pokeballTiles = 0x3E3680, pokeballBytes = 0x100,
  cancelTiles = 0x3E3780, cancelBytes = 0x20,
  sparkleTiles = 0x3E37C0, sparklePal = 0x3E37A0,
  arrowsTiles = 0x3E3B40, arrowsBytes = 0x80,
  blueLightTiles = 0x3E41D8, blueLightPal = 0x3E41B8, blueLightBytes = 0x100,
  brendanIcon = 0x3E5C40, mayIcon = 0x3E5CE0, iconBytes = 0x80,

  conditionSearch2Pal = 0x3E0294,

  -- src/data/graphics.c. Located by LZ77 content match against the decomp
  -- build products; menu_options is the five cards concatenated by misc.mk
  -- in the order hoennmap, condition, eyes, ribbons, off (32 tiles each).
  -- These are tile SHEETS -- a tilemap places them, so they are extracted
  -- as sheets and the screen layout is the UI's job, not this module's.
  mainMenuGfx = 0xE88358,      -- gPokenavMainMenu_Gfx, lz77, 48 tiles
  menuOptionsGfx = 0xE884CC,   -- gPokenavMenuOptions_Gfx, lz77, 160 tiles
  menuOptionsCards = 5,
  menuOptionsTilesPerCard = 32,
  menuPal1 = 0xE88A28,         -- pokenav1/2/3.gbapal, contiguous
  menuPal2 = 0xE88A48,
  menuPal3 = 0xE88A68,
  -- condition5.gbapal: the palette gSpriteTemplate_83E44F8 hands to the
  -- TRAINER'S EYES header (paletteTag 3); every other header takes
  -- pokenav3 (paletteTag 2) at menuPal3.
  conditionPal5 = 0xE8ACE4,
  -- condition1.gbapal: sub_80F2514 case 1 gives the CONDITION menu's
  -- option cards their own palette, not the main menu's pokenav1.
  conditionPal1 = 0xE89958,
  bottomToolbar = 0xE9A100,    -- gUnknown_08E9A100, bottom_toolbar.bin
  conditionScreen = 0xE9AC4C,  -- gUnknown_08E9AC4C, lz77

  -- sub_80F1BC8 drives three lists through the same four-sprite card format:
  --   arg0 0  main menu        5 cards, topOffset 42, height 20
  --   arg0 1  condition menu   3 cards, topOffset 56, height 20
  --   arg0 2  condition search 6 cards, topOffset 40, height 16
  conditionMenuGfx = 0xE89668, conditionMenuCards = 3,
  conditionOptionsGfx = 0xE8A1E0, conditionOptionsCards = 2,
  conditionOptions2Gfx = 0xE8A5D8,
  -- gPokenavConditionSearch_Gfx. It is not address-named, so it was found
  -- by position: graphics.c orders condition5.gbapal, condition_search,
  -- condition6.gbapal, condition7.bin, trainereyes. condition5 is at
  -- 0xE8ACE4 and ends 32 bytes later; the LZ77 header at 0xE8AD04
  -- declares 6144 bytes = 192 tiles = exactly the six cards sub_80F1BC8
  -- asks for, and trainereyes at 0xE8B204 less two 32-byte palettes puts
  -- condition6 at 0xE8B1C4 and condition7 at 0xE8B1E4. condition7 is
  -- confirmed byte-for-byte against the decomp's condition7.bin, including
  -- the 0xFFFF entry the decomp comments on.
  conditionSearchGfx = 0xE8AD04, conditionSearchCards = 6,
  conditionPal6 = 0xE8B1C4,
  conditionPal7 = 0xE8B1E4,
  -- screen headers (64x48 each)
  mapHeaderGfx = 0xE88A88,
  trainerEyesHeaderGfx = 0xE8B204,
  ribbonsHeaderGfx = 0xE8B3A0,
  conditionHeaderGfx = 0xE89978,   -- condition_menu_header, 64x48
  conditionViewGfx = 0xE89AD8,     -- condition_view, the 200x40 stat strip
  ribbonViewGfx = 0xE9FB1C,        -- ribbon_view, 88x8

  -- pokenav.c sub_80F55AC builds the condition pentagon from this curve:
  -- stat value -> radius in pixels, hand-tuned, one byte per value 0..255.
  -- Geometry rather than art, but it still has to come off the cart.
  conditionRadius = 0x3E4890,
  conditionRadiusCount = 256,
  conditionCx = 0x9B,

  -- sub_80EF428: the help line under the menu. gUnknown_083E31B0 is the
  -- main menu's seven strings (five options, then the two 'nothing here yet'
  -- lines for a locked RIBBONS and TRAINER'S EYES). It prints via
  -- AlignStringInMenuWindow(.., 0xC0, 2) -- centred in 192px -- at
  -- Menu_PrintText(.., 3, 17), i.e. tile (3, 17) = pixels (24, 136).
  menuHelpTable = 0x3E31B0,
  menuHelpCount = 7,
  -- sub_80EF428's other two tables sit immediately after it, and both were
  -- read back word for word off hardware captures. a=1 is the CONDITION
  -- menu (PARTY PKMN / SEARCH / CANCEL) at three strings; a=2 is the
  -- condition search at SIX -- one per contest category plus the CANCEL
  -- row, so COOL / BEAUTY / CUTE / SMART / TOUGH / 'Return to the
  -- CONDITION menu.'. Counting four here dropped TOUGH and CANCEL: the
  -- boundary is the pointer after them, which decodes to garbage.
  conditionHelpTable = 0x3E31CC,
  conditionHelpCount = 3,
  searchHelpTable = 0x3E31D8,
  searchHelpCount = 6,
  conditionCy = 0x5B,              -- 91

  -- Ribbon icons are NOT stored ready to blit. sub_80F37D0 assembles each
  -- one in WRAM from these source tiles, mirroring half-tiles with a nibble
  -- swap ((b << 4) | (b >> 4)) so the icon is symmetric. Located but not yet
  -- assembled -- emitting the raw source would give half-icons.
  -- pokenav.c case 11 of the ribbons init: LZ77UnCompVram(gUnknown_083E040C,
  -- VRAM + 0x8200), i.e. BG3 charbase 2 tile 0x10, which is the tile base
  -- DrawMonRibbonIcons adds to. 24 tiles = 12 icons of two tiles each.
  ribbonIconTiles = 0x3E040C,
  ribbonIconPals = 0x3E3C60,       -- gUnknown_083E3C60, 5 palettes
  -- gPokenavRibbonsIconGfx: u16 pairs of (icon, palette). Not an
  -- address-named symbol, so it was found by its shape -- entry 0 is the
  -- CHAMPION ribbon, then four rank shapes across five contest palettes,
  -- which is exactly Ruby's ribbon order.
  ribbonIconTable = 0x3E4698,
  ribbonIconCount = 32,
  ribbonIconSheets = 12,
  -- condition_screen.bin.lz -> VRAM 0xF000, the BG3 (text window) screen
  -- base. Its tile ids are charbase 0, and condition_view went to VRAM
  -- 0x5000, so ids start at 0x5000/32 = 640.
  conditionScreenMap = 0xE9AC4C,
  conditionScreenFirstTile = 640,
  conditionPal2 = 0xE8A1C0,        -- condition2.gbapal, palette bank 2
}

Pokenav.DIR = "assets/generated/pokenav/"
Pokenav.SCREEN_W, Pokenav.SCREEN_H = 240, 160
Pokenav.COLS, Pokenav.ROWS = 32, 20

local function bgr555(v)
  return (v % 32) / 31,
    (math.floor(v / 32) % 32) / 31,
    (math.floor(v / 1024) % 32) / 31
end

local function palAt(data, off)
  local pal = {}
  for i = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(data, off + i * 2))
    pal[i] = { r, g, b }
  end
  return pal
end

local function bytesAt(data, off, lz, count)
  if lz then return GbaLz77.decompress(data, off) end
  return data:sub(off + 1, off + count)
end

local function putTile(image, pixels, tile, px, py, pal, hflip, vflip, key0)
  for y = 0, 7 do
    for x = 0, 7 do
      local sx = hflip and (7 - x) or x
      local sy = vflip and (7 - y) or y
      local o = tile * 32 + sy * 4 + math.floor(sx / 2)
      local byte = (o >= 0 and o < #pixels) and pixels:byte(o + 1) or 0
      local idx
      if sx % 2 == 0 then idx = byte % 16 else idx = math.floor(byte / 16) end
      if key0 and idx == 0 then
        image:setPixel(px + x, py + y, 0, 0, 0, 0)
      else
        local c = pal[idx] or pal[0]
        image:setPixel(px + x, py + y, c[1], c[2], c[3], 1)
      end
    end
  end
end

-- A full BG layer: tilemap entries index the sheet, offset by the VRAM tile
-- the sheet was uploaded to.
function Pokenav.renderLayer(data, tilesOff, tilesLz, tilesBytes, mapOff, mapLz,
    palOff, firstTile, key0)
  local pixels = bytesAt(data, tilesOff, tilesLz, tilesBytes)
  local tm = bytesAt(data, mapOff, mapLz, Pokenav.COLS * Pokenav.ROWS * 2)
  if not (pixels and tm) or #tm < 2 then return nil end
  local pal = palAt(data, palOff)
  local image = ImageWriter.blank(Pokenav.SCREEN_W, Pokenav.SCREEN_H, 0, 0, 0,
    key0 and 0 or 1)
  for row = 0, Pokenav.ROWS - 1 do
    for col = 0, (Pokenav.SCREEN_W / 8) - 1 do
      local at = (row * Pokenav.COLS + col) * 2
      if at + 1 < #tm then
        local lo, hi = tm:byte(at + 1, at + 2)
        local e = lo + hi * 256
        putTile(image, pixels, (e % 1024) - (firstTile or 0), col * 8, row * 8,
          pal, math.floor(e / 1024) % 2 == 1, math.floor(e / 2048) % 2 == 1,
          key0 and true or false)
      end
    end
  end
  return image
end

-- An OBJ sheet laid out as one row of 8x8 tiles, index 0 keyed to alpha.
-- tilesWide matters: the screen headers are 64x48 (8 tiles across, 6 down).
-- Laying every tile in one row turned a header into a 384x8 strip that ran
-- off the screen edge.
function Pokenav.renderSheet(data, off, byteCount, palOff, lz, tilesWide)
  local pixels = bytesAt(data, off, lz, byteCount)
  if not pixels or #pixels < 32 then return nil end
  local pal = palAt(data, palOff)
  local tiles = math.floor(#pixels / 32)
  local wide = tilesWide or tiles
  if wide < 1 then wide = 1 end
  local tall = math.ceil(tiles / wide)
  local image = ImageWriter.blank(wide * 8, tall * 8, 0, 0, 0, 0)
  for t = 0, tiles - 1 do
    putTile(image, pixels, t, (t % wide) * 8, math.floor(t / wide) * 8,
      pal, false, false, true)
  end
  return image
end

-- The five screen headers are pairs of OBJ sprites, not single images.
-- sub_80F29B8 creates two of them 64px apart (final x 32 and 96, centred,
-- so left edges 0 and 64) at y 49 with a 32px height -- top edge 33.
-- Each one takes its tiles from a different anim frame of
-- gSpriteAnimTable_83E44D4: frame 0, frame 32, frame 64.
--
-- Frame 0 is always 8 tiles across by 4 down. On the four 48-tile sheets
-- the second frame only has 16 tiles left, and they are 4 across by 4 down
-- -- the tile-occupancy runs '### . ### . ### . . . .', a stride of 4, not
-- of 8. Blitting those 16 tiles 8-wide splits the last syllable off and
-- strands it: CONDITION came out as CONDITIO, a gap, then a lone N.
-- The 96-tile map header is the exception -- it has two full 8-wide right
-- halves, one for FULL VIEW and one for the zoomed view.
function Pokenav.renderHeader(data, off, palOff, rightFirst, rightWide)
  local pixels = GbaLz77.decompress(data, off)
  if not pixels or #pixels < 32 * 32 then return nil end
  local pal = palAt(data, palOff)
  local tiles = math.floor(#pixels / 32)
  rightFirst = rightFirst or 32
  rightWide = rightWide or 4
  local rightCount = math.min(tiles - rightFirst, rightWide * 4)
  if rightCount < 0 then rightCount = 0 end
  local image = ImageWriter.blank(64 + rightWide * 8, 32, 0, 0, 0, 0)
  for t = 0, 31 do
    putTile(image, pixels, t, (t % 8) * 8, math.floor(t / 8) * 8,
      pal, false, false, true)
  end
  for i = 0, rightCount - 1 do
    putTile(image, pixels, rightFirst + i,
      64 + (i % rightWide) * 8, math.floor(i / rightWide) * 8,
      pal, false, false, true)
  end
  return image
end

-- The condition screen's backdrop is BG3, which on this screen is the text
-- window (gWindowTemplate_81E7080: BG 3, charbase 0, screenbase 30). Nothing
-- in pokenav.c writes charbase 0, so the low tiles are the window font; a
-- 10-bit tile id still reaches VRAM 0x5000, where condition_view was
-- uploaded, so every id in condition_screen.bin is 640 or above.
--
-- Its filler tile is a one-pixel green/blue interlace: the cart alpha-blends
-- BG2 over it (BLDCNT 0x844, BLDALPHA 0x40B) inside WIN0V 56..121 and covers
-- the rest with the header sprite and the toolbar. We draw neither, so the
-- raw stripes would fill the screen. The cart also patches the window's own
-- background colour to condition2 entry 15 for this screen, which is what
-- shows behind the text, so the filler is flattened to that instead.
-- The filler tile is a one-pixel green/blue interlace, and it SHOWS: a
-- hardware capture of the condition screen has it striping the whole
-- background around the panels, alternating 73E373 and 849AFF row by row.
--
-- An earlier version flattened it to the flat window colour, flood-filling
-- the stripe indices in from the screen edge. That was a workaround for a
-- problem that did not exist -- the art was right and the inference that
-- BG2 and the toolbar must be hiding it was wrong. Draw every tile.
function Pokenav.renderConditionScreen(data)
  local u = Pokenav.RUBY_US
  local pixels = GbaLz77.decompress(data, u.conditionViewGfx)
  local tm = GbaLz77.decompress(data, u.conditionScreenMap)
  if not (pixels and tm) then return nil end
  local pal = palAt(data, u.conditionPal2)
  local first = u.conditionScreenFirstTile
  local W, H = Pokenav.SCREEN_W, Pokenav.SCREEN_H
  local image = ImageWriter.blank(W, H, 0, 0, 0, 1)
  for row = 0, Pokenav.ROWS - 1 do
    for col = 0, (W / 8) - 1 do
      local at = (row * Pokenav.COLS + col) * 2
      if at + 1 < #tm then
        local lo, hi = tm:byte(at + 1, at + 2)
        local e = lo + hi * 256
        putTile(image, pixels, (e % 1024) - first, col * 8, row * 8, pal,
          math.floor(e / 1024) % 2 == 1, math.floor(e / 2048) % 2 == 1,
          false)
      end
    end
  end
  return image
end

-- DrawMonRibbonIcons builds each 16x16 icon from just TWO tiles: the left
-- column is tile and tile+1, the right column is the same pair with the
-- tilemap's hflip bit (0x400) set. Storing 12 whole icons would be wrong --
-- only the left halves exist in the cart.
function Pokenav.renderRibbonIcons(data)
  local u = Pokenav.RUBY_US
  local pixels = GbaLz77.decompress(data, u.ribbonIconTiles)
  if not pixels then return nil end
  local count = u.ribbonIconCount
  local image = ImageWriter.blank(count * 16, 16, 0, 0, 0, 0)
  for i = 0, count - 1 do
    local at = u.ribbonIconTable + i * 4
    if at + 3 >= #data then break end
    local a0, a1, b0, b1 = data:byte(at + 1, at + 4)
    local icon = a0 + a1 * 256
    local pal = palAt(data, u.ribbonIconPals + (b0 + b1 * 256) * 32)
    for half = 0, 1 do
      for sub = 0, 1 do
        putTile(image, pixels, icon * 2 + half,
          i * 16 + sub * 8, half * 8, pal, sub == 1, false, true)
      end
    end
  end
  return image
end

-- pokenav.c sub_80F1BC8 draws each option as FOUR 32x16 sprites side by
-- side (unk320[i][j], j 0..3) with animNum = (option - 1) * 4 + j, so the
-- 160-tile sheet is 20 anims of 8 tiles, each laid out 4 tiles wide by 2
-- tall. Blitting the sheet in raw tile order instead interleaves the rows
-- and the labels come out unreadable.
function Pokenav.renderMenuCards(data, gfxOff, cardCount, palOff)
  local u = Pokenav.RUBY_US
  local pixels = GbaLz77.decompress(data, gfxOff or u.menuOptionsGfx)
  if not pixels then return nil end
  local pal = palAt(data, palOff or u.menuPal1)
  local cards = cardCount or u.menuOptionsCards
  local image = ImageWriter.blank(128, 16 * cards, 0, 0, 0, 0)
  for card = 0, cards - 1 do
    for seg = 0, 3 do
      local base = (card * 4 + seg) * 8
      for t = 0, 7 do
        putTile(image, pixels, base + t,
          seg * 32 + (t % 4) * 8, card * 16 + math.floor(t / 4) * 8,
          pal, false, false, true)
      end
    end
  end
  return image
end

-- sub_80F55AC indexes this with the raw stat, so it ships as data.
function Pokenav.readRadiusTable(data)
  local u = Pokenav.RUBY_US
  local out = {}
  for i = 0, u.conditionRadiusCount - 1 do
    out[i + 1] = GbaBin.u8(data, u.conditionRadius + i)
  end
  return out
end

-- BG3 (REG_BG3CNT 0x1C0B): a single tile at charbase 0x8000 repeated over
-- all 640 cells, which is why the outline's tiles start at index 1. Its
-- colours are NOT a stored palette -- sub_80EF624 interpolates a 16-step
-- gradient between two entries of gUnknown_083E003C at runtime, which is the
-- shimmer on the device. We bake the first step; the cycling is the UI's job.
function Pokenav.renderBackground(data)
  local u = Pokenav.RUBY_US
  local tile = data:sub(u.altTiles + 1, u.altTiles + 0x20)
  local tm = GbaLz77.decompress(data, u.altTilemap)
  if not (tile and tm) or #tile < 0x20 then return nil end
  local pal = palAt(data, u.altPal)
  local image = ImageWriter.blank(Pokenav.SCREEN_W, Pokenav.SCREEN_H, 0, 0, 0, 1)
  for row = 0, Pokenav.ROWS - 1 do
    for col = 0, (Pokenav.SCREEN_W / 8) - 1 do
      putTile(image, tile, 0, col * 8, row * 8, pal, false, false, false)
    end
  end
  return image
end

-- Hardware composites BG3 (the patterned field) under BG2 (the device
-- shell). Emitting them as two files meant the runtime had to load both and
-- draw them in order, and when only one arrived the screen came out as bare
-- line art on black. Compositing here leaves the UI a single image to draw.
function Pokenav.renderScreen(data)
  local u = Pokenav.RUBY_US
  local back = Pokenav.renderBackground(data)
  local shell = Pokenav.renderLayer(data, u.outlineTiles, true, nil,
    u.outlineTilemap, true, u.outlinePal, u.outlineFirstTile, true)
  if not back then return shell end
  if not shell then return back end
  for y = 0, Pokenav.SCREEN_H - 1 do
    for x = 0, Pokenav.SCREEN_W - 1 do
      local r, g, b, a = shell:getPixel(x, y)
      if (a or 0) > 0 then back:setPixel(x, y, r, g, b, 1) end
    end
  end
  return back
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

-- A help-line table, decoded with decodePages so the cart's own line
-- breaks survive (decodeText would flatten them to spaces).
function Pokenav.readHelpTable(data, off, count)
  local GbaText = require("src.import.GbaText")
  local out = {}
  for i = 0, count - 1 do
    local ptr = GbaBin.u32(data, off + i * 4)
    if not GbaBin.isRomPtr(ptr, #data) then break end
    local at = ptr - GbaBin.ROM_BASE
    local pages = GbaText.decodePages(data:sub(at + 1, at + 128), 128)
    out[i + 1] = pages[1] or ""
  end
  return out
end

function Pokenav.readMenuHelp(data)
  local GbaText = require("src.import.GbaText")
  local u = Pokenav.RUBY_US
  local out = {}
  for i = 0, u.menuHelpCount - 1 do
    local ptr = GbaBin.u32(data, u.menuHelpTable + i * 4)
    if not GbaBin.isRomPtr(ptr, #data) then break end
    local off = ptr - GbaBin.ROM_BASE
    local pages = GbaText.decodePages(data:sub(off + 1, off + 128), 128)
    out[i + 1] = pages[1] or ""
  end
  return out
end

function Pokenav.extractData(data)
  local LuaWriter = require("src.import.LuaWriter")
  local u = Pokenav.RUBY_US
  if type(data) ~= "string" or #data < u.conditionRadius + u.conditionRadiusCount then
    return false
  end
  local ok = pcall(LuaWriter.write, "data/generated/pokenav.lua", {
    conditionRadius = Pokenav.readRadiusTable(data),
    menuHelp = Pokenav.readMenuHelp(data),
    conditionHelp = Pokenav.readHelpTable(data,
      Pokenav.RUBY_US.conditionHelpTable, Pokenav.RUBY_US.conditionHelpCount),
    searchHelp = Pokenav.readHelpTable(data,
      Pokenav.RUBY_US.searchHelpTable, Pokenav.RUBY_US.searchHelpCount),
    conditionCx = u.conditionCx,
    conditionCy = u.conditionCy,
  })
  return ok and true or false
end

function Pokenav.extract(data)
  local u = Pokenav.RUBY_US
  if type(data) ~= "string" or #data < u.mayIcon + u.iconBytes then return 0 end
  local n = 0
  local function put(image, name)
    if save(image, Pokenav.DIR .. name) then n = n + 1 end
  end
  put(Pokenav.renderScreen(data), "screen.png")
  put(Pokenav.renderBackground(data), "background.png")
  put(Pokenav.renderLayer(data, u.outlineTiles, true, nil, u.outlineTilemap,
    true, u.outlinePal, u.outlineFirstTile, true), "outline.png")
  put(Pokenav.renderLayer(data, u.miscTiles, false, u.miscTilesBytes,
    u.miscTilemap, true, u.miscPal, u.miscFirstTile, true), "misc_layer.png")
  put(Pokenav.renderLayer(data, u.bannerTiles, true, nil,
    u.bannerTilemap, true, u.bannerPal, 0, true), "banner.png")
  put(Pokenav.renderLayer(data, u.altTiles, false, 0x20, u.altTilemap, true,
    u.altPal, 0), "alt_layer.png")
  put(Pokenav.renderSheet(data, u.pokeballTiles, u.pokeballBytes, u.outlinePal,
    false), "pokeball.png")
  put(Pokenav.renderSheet(data, u.sparkleTiles, 0x380, u.sparklePal, false),
    "sparkle.png")
  put(Pokenav.renderSheet(data, u.arrowsTiles, u.arrowsBytes, u.sparklePal,
    false), "arrows.png")
  put(Pokenav.renderSheet(data, u.blueLightTiles, u.blueLightBytes,
    u.blueLightPal, false), "blue_light.png")
  put(Pokenav.renderSheet(data, u.brendanIcon, u.iconBytes, u.iconPal, false),
    "brendan_icon.png")
  put(Pokenav.renderSheet(data, u.mayIcon, u.iconBytes, u.iconPal, false),
    "may_icon.png")
  -- gSpriteTemplate_83E4850 is a 32x32 OBJ (square size 2) whose anim table
  -- steps frames 0/16/32/../112 -- eight frames of sixteen tiles. Four
  -- tiles across gives the cart's 32x256 strip; with no width the whole
  -- thing came out as a single 1024x8 row.
  put(Pokenav.renderSheet(data, u.iconTiles, nil, u.iconPal, true, 4),
    "icons.png")
  put(Pokenav.renderSheet(data, u.trainerEyesTiles, nil, u.trainerEyesPal, true),
    "trainer_eyes.png")
  put(Pokenav.renderHeader(data, u.mainMenuGfx, u.menuPal3),
    "main_menu_header.png")
  put(Pokenav.renderMenuCards(data), "menu_options.png")
  -- sub_80F1BC8: rows with i > 2 get oam.paletteNum = sprite palette tag 1,
  -- which sub_80F2514 loaded with pokenav2. Under pokenav1 the RIBBONS card
  -- reads black, so the last two rows need their own sheet.
  put(Pokenav.renderMenuCards(data, u.menuOptionsGfx, u.menuOptionsCards,
    u.menuPal2), "menu_options_alt.png")
  -- sub_80F2514 case 1 loads gPokenavConditionMenu_Pal (condition1) on tag
  -- 0 and loads NOTHING on tag 1, so all three rows are on condition1 --
  -- the i > 2 repoint cannot fire on a three-row list. This had been
  -- rendered on pokenav1, which is the root menu's palette.
  put(Pokenav.renderMenuCards(data, u.conditionMenuGfx, u.conditionMenuCards,
    u.conditionPal1), "condition_menu.png")
  -- sub_80F2514 case 2 loads condition6 on tag 0 and condition7 on tag 1,
  -- and sub_80F1BC8 repoints rows past the third to tag 1 -- so COOL,
  -- BEAUTY and CUTE come off condition6 and SMART, TOUGH and CANCEL off
  -- condition7. Rendered on one palette the split shows immediately: all
  -- six read as reds and pinks instead of the five contest colours.
  put(Pokenav.renderMenuCards(data, u.conditionSearchGfx,
    u.conditionSearchCards, u.conditionPal6), "condition_search.png")
  put(Pokenav.renderMenuCards(data, u.conditionSearchGfx,
    u.conditionSearchCards, u.conditionPal7), "condition_search_alt.png")
  put(Pokenav.renderMenuCards(data, u.conditionOptionsGfx,
    u.conditionOptionsCards, u.conditionPal1), "condition_options.png")
  put(Pokenav.renderHeader(data, u.mapHeaderGfx, u.menuPal3, 32, 8),
    "map_header.png")
  put(Pokenav.renderHeader(data, u.mapHeaderGfx, u.menuPal3, 64, 8),
    "map_header_zoom.png")
  put(Pokenav.renderHeader(data, u.trainerEyesHeaderGfx, u.conditionPal5),
    "trainer_eyes_header.png")
  put(Pokenav.renderHeader(data, u.ribbonsHeaderGfx, u.menuPal3),
    "ribbons_header.png")
  put(Pokenav.renderHeader(data, u.conditionHeaderGfx, u.menuPal3),
    "condition_header.png")
  put(Pokenav.renderConditionScreen(data), "condition_screen.png")
  put(Pokenav.renderRibbonIcons(data), "ribbon_icons.png")
  put(Pokenav.renderSheet(data, u.conditionViewGfx, nil, u.menuPal1, true, 25),
    "condition_view.png")
  put(Pokenav.renderSheet(data, u.ribbonViewGfx, nil, u.menuPal1, true),
    "ribbon_view.png")
  if Pokenav.extractData(data) then n = n + 1 end
  return n
end

return Pokenav
