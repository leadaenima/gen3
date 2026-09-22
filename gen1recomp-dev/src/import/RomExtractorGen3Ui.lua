-- Ruby menu / battle window chrome.  pokeruby text_window.c draws every
-- standard menu from a 9-tile frame and the field dialogue box from a
-- 14-tile sheet; battle_bg.c paints the whole bottom battle UI from one
-- tilemap (`gBattleTextboxTilemap`).  All of it lives in the cart, so the
-- runtime blits ROM tiles instead of approximating with rectangles.
-- Nintendo tiles stay out of git; these are generated on import.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Ui = {}

Ui.TILE = 8
Ui.TILE_BYTES = 32
Ui.SCREEN_W = 240
Ui.SCREEN_H = 160
Ui.FRAME_STYLES = 20
Ui.FRAME_TILES = 9
Ui.DIALOG_TILES = 14

-- NUM_BRAILLE_CHARS. Only the first 64 glyphs are braille; the sheet in the
-- cart runs on past them.
Ui.BRAILLE_GLYPHS = 64
Ui.BRAILLE_COLS = 16

-- US Ruby 1.0. graphics.c stores each text window style as 9 tiles (288
-- bytes) immediately followed by its 16-color palette, so the pair strides
-- 0x140.  The battle labels (`gUnknown_08D1212C`, `Tiles_D129AC`) encode
-- their own ROM addresses.
Ui.RUBY_US = {
  frameGfx = 0xE9ADDC,
  framePal = 0xE9AEFC,
  frameStride = 0x140,
  frameGfxBytes = 288,
  dialogGfx = 0xEA0108,
  dialogGfxBytes = 448,
  battleTilesLz = 0xD00000,
  battleTilesBytes = 8192,
  battlePalLz = 0xD004E0,
  battlePalBytes = 64,
  battleMap = 0xD00524,
  battleMapBytes = 4096,
  healthboxGfx = 0xD1216C,
  healthboxBytes = 2112,
  windowPal = 0xD1212C,
  -- text.c sBrailleGlyphs: the braille font, 1bpp and 8 bytes a glyph.
  brailleGlyphs = 0x1E58F0,
  hpBarPal = 0xD1214C,
  -- gBattleWindowLargeGfx / gBattleWindowSmallGfx. No neighbouring label
  -- fixes these, so they were found as the only run of five consecutive LZ
  -- streams decompressing to 4096/2048/2048/2048/4096 bytes.
  healthboxPlayerGfx = 0xD1F52C,
  healthboxEnemyGfx = 0xD1F7E0,
  -- Remaining three LZ streams after Large/Small: 2048, 2048, 4096.
  -- Offsets filled at extract time via GbaLz77.streamEnd.
  namingSheetTable = 0x3CE6A0,
  namingPal0 = 0xE86198,
  namingMenuGfx = 0xE832F8,
  namingMenuMap = 0xE84878,
  -- AXVE pointers: 0x1064A0 gfx, 0x1064B0 pal, 0x1064D0 map; reels 0x3EDC2C.
  slotsGfx = 0xE8F844,
  slotsPal = 0xE95A18,
  slotsMap = 0xE95AB8,
  slotsMapBytes = 20 * 32 * 2,
  slotsTiles = 240,
  slotsReel0 = 0xE977A8,
  -- roulette.c: BG1 4bpp table 08E8096C + 083F88BC; BG2 8bpp wheel
  -- 08E81098 + 083F8A60; pal 083F86BC (0x1C0).
  rouletteBaseGfx = 0xE8096C,
  rouletteWheelGfx = 0xE81098,
  roulettePal = 0x3F86BC,
  rouletteTableMap = 0x3F88BC,
  rouletteMap = 0x3F8A60,
  -- wallclock.c: gMiscClock_Gfx + start tilemap 08E954B0 + male pal.
  clockGfx = 0xE92118,
  clockPal = 0xE94310,
  clockMap = 0xE954B0,
  clockViewMap = 0xE95774,
  pssPal = 0xE9F624,
  pssGfx = 0xE9EFD0,
  pssMap = 0xE9F7E4,
  pokeblockGfx = 0xE78078,
  pokeblockPal = 0xE7883C,
  creditsGfx = 0xEA260C,
  creditsPal = 0xE9F624,
  -- pokenav.c load: stripe tiles 083E007C + map 083DFF8C + pal 083DFECC,
  -- outline tiles 083E05F4 + map 083E0804 + pal 083E05D4.
  pokenavStripeGfx = 0x3E007C,
  pokenavStripeMap = 0x3DFF8C,
  pokenavStripePal = 0x3DFECC,
  pokenavOutlineGfx = 0x3E05F4,
  pokenavOutlineMap = 0x3E0804,
  pokenavOutlinePal = 0x3E05D4,
}

-- Each healthbox is two OBJs drawn side by side: the name/HP box then the
-- Lv box. The player's carries the EXP bar so its halves are 64x64.
Ui.HEALTHBOX = {
  player = { off = "healthboxPlayerGfx", halfW = 64, halfH = 64 },
  enemy = { off = "healthboxEnemyGfx", halfW = 64, halfH = 32 },
  playerDouble = { off = "healthboxPlayerDoubleGfx", halfW = 64, halfH = 32 },
  enemyDouble = { off = "healthboxEnemyDoubleGfx", halfW = 64, halfH = 32 },
  extra = { off = "healthboxExtraGfx", halfW = 64, halfH = 64 },
}

function Ui.discoverHealthboxStreams(data)
  local u = Ui.RUBY_US
  local off = u.healthboxPlayerGfx
  local sizes = { 4096, 2048, 2048, 2048, 4096 }
  local offs = {}
  for i = 1, #sizes do
    offs[i] = off
    local nxt = GbaLz77.streamEnd(data, off)
    if not nxt then return offs end
    off = nxt
    -- LZ streams in this run are 4-byte aligned.
    off = math.floor((off + 3) / 4) * 4
  end
  u.healthboxPlayerDoubleGfx = offs[3] or u.healthboxEnemyGfx
  u.healthboxEnemyDoubleGfx = offs[4] or u.healthboxEnemyGfx
  u.healthboxExtraGfx = offs[5] or u.healthboxPlayerGfx
  return offs
end

-- draw_status_ailment_maybe: 24x8 pills from gHealthboxElementsGfxTable
-- (tiles in healthbox_elements.4bpp) with gBattleInterfaceStatusIcons_DynPal
-- FillPalette'd onto palette index 12 (battler0 + 12). US Ruby 1.0.
Ui.STATUS_DYNPAL = 0xE903F8
Ui.STATUS_FILL_INDEX = 12
Ui.STATUS_PILL_W = 24
Ui.STATUS_PILL_H = 8
-- name, first tile id, DynPal index (psn/par/slp/frz/brn)
Ui.STATUS_PILLS = {
  { "psn", 0x15, 0 },
  { "par", 0x18, 1 },
  { "slp", 0x1B, 2 },
  { "frz", 0x1E, 3 },
  { "brn", 0x21, 4 },
}


-- text_window.c sDialogueFrameTilemap: 7 wide x 5 tall, entries carry the
-- GBA flip bits (0x0400 h, 0x0800 v) so corners mirror.
Ui.DIALOG_TILEMAP = {
  { 1, 3, 4, 4, 5, 6, 9 },
  { 11, 9, 9, 9, 9, 0x040B, 9 },
  { 7, 9, 9, 9, 9, 10, 9 },
  { 0x080B, 9, 9, 9, 9, 0x0C0B, 9 },
  { 0x0801, 0x0803, 0x0804, 0x0804, 0x0805, 0x0806, 9 },
}

local function bgr555(c)
  return (c % 32) * 8 / 255,
    (math.floor(c / 32) % 32) * 8 / 255,
    (math.floor(c / 1024) % 32) * 8 / 255
end

local function readPal(data, off, count)
  count = count or 16
  if type(data) ~= "string" or off < 0 or off + count * 2 > #data then return nil end
  local pal = {}
  for c = 0, count - 1 do
    pal[c] = { bgr555(GbaBin.u16(data, off + c * 2)) }
  end
  return pal
end

local function palFromRaw(raw, base)
  local pal = {}
  for c = 0, 15 do
    local lo = raw:byte(base + c * 2 + 1) or 0
    local hi = raw:byte(base + c * 2 + 2) or 0
    pal[c] = { bgr555(lo + hi * 256) }
  end
  return pal
end

-- One 8x8 4bpp tile. Index 0 is transparent when `skip0`.
local function blitTile(image, px, py, tiles, id, pal, hflip, vflip, skip0)
  local base = id * Ui.TILE_BYTES
  if base + Ui.TILE_BYTES > #tiles then return end
  local w, h = image:getWidth(), image:getHeight()
  for ty = 0, 7 do
    for tx = 0, 7 do
      local sx = hflip and (7 - tx) or tx
      local sy = vflip and (7 - ty) or ty
      local byte = tiles:byte(base + sy * 4 + math.floor(sx / 2) + 1) or 0
      local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if not (skip0 and ci == 0) then
        local col = pal[ci] or { 0, 0, 0 }
        local x, y = px + tx, py + ty
        if x >= 0 and y >= 0 and x < w and y < h then
          image:setPixel(x, y, col[1], col[2], col[3], 1)
        end
      end
    end
  end
end

Ui.blitTile = blitTile

-- The 20 standard menu frames, stacked as 20 rows of a 3x3 tile block.
-- Row order matches `optionsWindowFrameType`, tile order matches
-- DrawStandardFrame: TL, top, TR / left, fill, right / BL, bottom, BR.
function Ui.renderFrames(data)
  local u = Ui.RUBY_US
  local image = ImageWriter.blank(3 * Ui.TILE, Ui.FRAME_STYLES * 3 * Ui.TILE,
    0, 0, 0, 0)
  for style = 0, Ui.FRAME_STYLES - 1 do
    local gfx = u.frameGfx + style * u.frameStride
    local pal = readPal(data, u.framePal + style * u.frameStride, 16)
    if not pal then return nil end
    local tiles = data:sub(gfx + 1, gfx + u.frameGfxBytes)
    if #tiles < u.frameGfxBytes then return nil end
    for t = 0, Ui.FRAME_TILES - 1 do
      local col, row = t % 3, math.floor(t / 3)
      blitTile(image, col * Ui.TILE, (style * 3 + row) * Ui.TILE,
        tiles, t, pal, false, false, false)
    end
  end
  return image
end

-- The field dialogue box, expanded from the 7x5 template to the ROM's
-- 26x4 interior (STD_DLG_FRAME_WIDTH/HEIGHT) plus its border.
function Ui.renderDialogueFrame(data, palOff)
  local u = Ui.RUBY_US
  local tiles = data:sub(u.dialogGfx + 1, u.dialogGfx + u.dialogGfxBytes)
  if #tiles < u.dialogGfxBytes then return nil end
  local pal = readPal(data, palOff or u.framePal, 16)
  if not pal then return nil end
  local image = ImageWriter.blank(7 * Ui.TILE, 5 * Ui.TILE, 0, 0, 0, 0)
  for row = 1, 5 do
    for col = 1, 7 do
      local entry = Ui.DIALOG_TILEMAP[row][col]
      local id = entry % 1024
      local hflip = math.floor(entry / 0x400) % 2 == 1
      local vflip = math.floor(entry / 0x800) % 2 == 1
      blitTile(image, (col - 1) * Ui.TILE, (row - 1) * Ui.TILE,
        tiles, id, pal, hflip, vflip, true)
    end
  end
  return image
end

-- battle_bg.c LoadBattleTextboxAndBackground copies all 0x1000 bytes of
-- `gBattleTextboxTilemap` to one BG, so it is a 64x32 map: two 32x32
-- screenblocks side by side. It holds three 6-row bottom-bar layouts and
-- the game scrolls whichever one it needs to y=112.
Ui.BATTLE_BAR_ROWS = 6
Ui.BATTLE_BAR_Y = 112
-- menu.pal index 7: light interior of the battle textbox tiles.
Ui.BATTLE_BAR_FILL = { 213 / 255, 205 / 255, 213 / 255 }
Ui.BATTLE_BARS = {
  -- block (0 = left, 1 = right), first row
  message = { 0, 14 },
  actions = { 1, 2 },
  moves = { 1, 22 },
}

-- One bottom-bar layout, as a 240x48 overlay to blit at y=112.
function Ui.renderBattleBar(data, layout)
  local u = Ui.RUBY_US
  local spec = Ui.BATTLE_BARS[layout or "message"]
  if not spec then return nil end
  local tiles = GbaLz77.decompress(data, u.battleTilesLz)
  local palRaw = GbaLz77.decompress(data, u.battlePalLz)
  if not (tiles and palRaw) then return nil end
  if #tiles ~= u.battleTilesBytes then return nil end
  local map = data:sub(u.battleMap + 1, u.battleMap + u.battleMapBytes)
  if #map < u.battleMapBytes then return nil end
  local pals = {}
  for i = 0, 15 do pals[i] = palFromRaw(palRaw, (i % 2) * 32) end
  local block, row0 = spec[1], spec[2]
  local cols = Ui.SCREEN_W / Ui.TILE
  local fill = (pals[0] and pals[0][7]) or Ui.BATTLE_BAR_FILL
  local image = ImageWriter.blank(Ui.SCREEN_W, Ui.BATTLE_BAR_ROWS * Ui.TILE,
    fill[1], fill[2], fill[3], 1)
  for row = 0, Ui.BATTLE_BAR_ROWS - 1 do
    for col = 0, cols - 1 do
      local i = block * 1024 + (row0 + row) * 32 + col
      local entry = GbaBin.u16(map, i * 2)
      local pal = pals[math.floor(entry / 4096) % 16] or pals[0]
      blitTile(image, col * Ui.TILE, row * Ui.TILE, tiles, entry % 1024, pal,
        math.floor(entry / 0x400) % 2 == 1,
        math.floor(entry / 0x800) % 2 == 1,
        true)
    end
  end
  return image
end

-- healthbox_elements.4bpp: HP/EXP bar segments, status pills and the
-- healthbox border, as a flat 32-byte tile array.
function Ui.renderHealthbox(data, palOff)
  local u = Ui.RUBY_US
  local tiles = data:sub(u.healthboxGfx + 1, u.healthboxGfx + u.healthboxBytes)
  if #tiles < u.healthboxBytes then return nil end
  local pal = readPal(data, palOff or u.windowPal, 16)
  if not pal then return nil end
  local count = math.floor(#tiles / Ui.TILE_BYTES)
  local cols = 16
  local rows = math.ceil(count / cols)
  local image = ImageWriter.blank(cols * Ui.TILE, rows * Ui.TILE, 0, 0, 0, 0)
  for t = 0, count - 1 do
    blitTile(image, (t % cols) * Ui.TILE, math.floor(t / cols) * Ui.TILE,
      tiles, t, pal, false, false, true)
  end
  return image
end

-- The assembled healthbox frame, ready to blit. Halves are 1D OBJ tile
-- runs: 8 tiles per row, left half first.
function Ui.renderHealthboxFrame(data, kind)
  local spec = Ui.HEALTHBOX[kind]
  if not spec then return nil end
  local tiles = GbaLz77.decompress(data, Ui.RUBY_US[spec.off])
  if not tiles then return nil end
  local perHalf = (spec.halfW / 8) * (spec.halfH / 8)
  if math.floor(#tiles / Ui.TILE_BYTES) < perHalf * 2 then return nil end
  local pal = readPal(data, Ui.RUBY_US.windowPal, 16)
  if not pal then return nil end
  local image = ImageWriter.blank(spec.halfW * 2, spec.halfH, 0, 0, 0, 0)
  for half = 0, 1 do
    for t = 0, perHalf - 1 do
      blitTile(image,
        half * spec.halfW + (t % 8) * Ui.TILE,
        math.floor(t / 8) * Ui.TILE,
        tiles, half * perHalf + t, pal, false, false, true)
    end
  end
  return image
end


-- Battle-interface status pills (24x8): three healthbox_elements tiles per
-- ailment with DynPal colour on index 12. Sheet order matches
-- Game3.BATTLE_STATUS_PILL_ORDER (psn/par/slp/frz/brn).
function Ui.renderStatusPills(data)
  local u = Ui.RUBY_US
  local tiles = data:sub(u.healthboxGfx + 1, u.healthboxGfx + u.healthboxBytes)
  if #tiles < u.healthboxBytes then return nil end
  local basePal = readPal(data, u.windowPal, 16)
  if not basePal then return nil end
  if type(data) ~= "string" or #data < Ui.STATUS_DYNPAL + 10 then return nil end
  local dyn = {}
  for i = 0, 4 do
    dyn[i] = { bgr555(GbaBin.u16(data, Ui.STATUS_DYNPAL + i * 2)) }
  end
  local rows = #Ui.STATUS_PILLS
  local image = ImageWriter.blank(Ui.STATUS_PILL_W, rows * Ui.STATUS_PILL_H,
    0, 0, 0, 0)
  for row, spec in ipairs(Ui.STATUS_PILLS) do
    local tile0, di = spec[2], spec[3]
    local pal = {}
    for c = 0, 15 do pal[c] = basePal[c] end
    pal[Ui.STATUS_FILL_INDEX] = dyn[di]
    local py = (row - 1) * Ui.STATUS_PILL_H
    for t = 0, 2 do
      blitTile(image, t * Ui.TILE, py, tiles, tile0 + t, pal, false, false, true)
    end
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  -- Same call as tilesets/sprites/font in RomExtractorGen3.lua.
  -- Do not pcall-and-drop: a failed write must surface like every other sheet.
  ImageWriter.save(image, path)
  return path
end

-- Sheet plus the five individual 24x8 PNGs Game3.BATTLE_STATUS_PILL_PATH uses.
function Ui.saveStatusPills(data)
  local sheet = Ui.renderStatusPills(data)
  local sheetPath = save(sheet, "assets/generated/ui/battle_status_pills.png")
  if not sheetPath then return nil, nil end
  local individuals = {}
  for row, spec in ipairs(Ui.STATUS_PILLS) do
    local pill = ImageWriter.blank(Ui.STATUS_PILL_W, Ui.STATUS_PILL_H, 0, 0, 0, 0)
    ImageWriter.blit(pill, sheet, 0, 0, 0, (row - 1) * Ui.STATUS_PILL_H,
      Ui.STATUS_PILL_W, Ui.STATUS_PILL_H)
    individuals[spec[1]] = save(pill,
      ("assets/generated/ui/battle_status_%s.png"):format(spec[1]))
  end
  return sheetPath, individuals
end


-- The braille font, so the regi chambers can show the real dots rather than
-- the letters they spell. LoadFixedWidthFont_Braille reads 8 bytes a glyph,
-- unshadowed, which is exactly decode1bpp's layout.
function Ui.renderBraille(data, off)
  off = off or Ui.RUBY_US.brailleGlyphs
  if type(data) ~= "string" or #data < off + Ui.BRAILLE_GLYPHS * 8 then
    return nil, "braille font not found"
  end
  local cols = Ui.BRAILLE_COLS
  local rows = math.ceil(Ui.BRAILLE_GLYPHS / cols)
  local image = ImageWriter.blank(cols * Ui.TILE, rows * Ui.TILE, 0, 0, 0, 0)
  for i = 0, Ui.BRAILLE_GLYPHS - 1 do
    local raw = {}
    for b = 1, 8 do raw[b] = data:byte(off + i * 8 + b) or 0 end
    local glyph = ImageWriter.decode1bpp(raw, Ui.TILE, Ui.TILE, true)
    ImageWriter.blit(image, glyph,
      (i % cols) * Ui.TILE, math.floor(i / cols) * Ui.TILE)
  end
  return image
end

function Ui.renderMapped(data, gfxOff, palOff, mapOff)
  local okTiles, tiles = pcall(GbaLz77.decompress, data, gfxOff)
  if not okTiles then tiles = nil end
  local okMap, map = pcall(GbaLz77.decompress, data, mapOff)
  if not okMap then map = nil end
  if not tiles then return nil end
  if not map then
    map = data:sub(mapOff + 1, mapOff + 0x800)
  end
  local pal = readPal(data, palOff, 16)
  if not pal then return nil end
  local mapW = 32
  local mapH = math.min(20, math.max(1, math.floor(#map / (mapW * 2))))
  local image = ImageWriter.blank(mapW * 8, mapH * 8, 0, 0, 0, 0)
  local maxTiles = math.floor(#tiles / Ui.TILE_BYTES)
  for ty = 0, mapH - 1 do
    for tx = 0, mapW - 1 do
      local entry = GbaBin.u16(map, (ty * mapW + tx) * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        blitTile(image, tx * 8, ty * 8, tiles, tid, pal,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, true)
      end
    end
  end
  return image
end

function Ui.renderLzSheet(data, gfxOff, palOff, cols)
  local tiles = GbaLz77.decompress(data, gfxOff)
  if not tiles then return nil end
  local pal = readPal(data, palOff, 16)
  if not pal then
    local palBytes = GbaLz77.decompress(data, palOff)
    if palBytes and #palBytes >= 32 then
      pal = {}
      for c = 0, 15 do
        local v = palBytes:byte(c * 2 + 1) + palBytes:byte(c * 2 + 2) * 256
        pal[c] = { bgr555(v) }
      end
    end
  end
  if not pal then return nil end
  cols = cols or 8
  local n = math.floor(#tiles / Ui.TILE_BYTES)
  local rows = math.max(1, math.floor((n + cols - 1) / cols))
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for t = 0, n - 1 do
    blitTile(image, (t % cols) * 8, math.floor(t / cols) * 8,
      tiles, t, pal, false, false, true)
  end
  return image
end

function Ui.findLzSize(data, want, from, to)
  from = from or 0
  to = to or (#data - 4)
  for off = from, to do
    if data:byte(off + 1) == 0x10 then
      local size = data:byte(off + 2) + data:byte(off + 3) * 256
        + data:byte(off + 4) * 65536
      if size == want then
        local raw = GbaLz77.decompress(data, off)
        if raw and #raw == want then return off, raw end
      end
    end
  end
end

function Ui.renderSlotsCabinet(data)
  local u = Ui.RUBY_US
  local tiles = GbaLz77.decompress(data, u.slotsGfx)
  if not tiles then return nil end
  local pals = {}
  for p = 0, 4 do
    pals[p] = readPal(data, u.slotsPal + p * 32, 16)
  end
  if not pals[0] then return nil end
  local map = data:sub(u.slotsMap + 1, u.slotsMap + u.slotsMapBytes)
  if #map < u.slotsMapBytes then return nil end
  local image = ImageWriter.blank(Ui.SCREEN_W, Ui.SCREEN_H, 0, 0, 0, 1)
  local maxTiles = math.floor(#tiles / Ui.TILE_BYTES)
  for ty = 0, 19 do
    for tx = 0, 29 do
      local entry = GbaBin.u16(map, (ty * 32 + tx) * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        local bank = math.floor(entry / 4096) % 16
        local pal = pals[bank] or pals[0]
        blitTile(image, tx * 8, ty * 8, tiles, tid, pal,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, false)
      end
    end
  end
  return image
end

-- 7 reel OBJs, 32x32, 0x200 raw 4bpp. Hunt a run of seven 0x200 sheets
-- before gSpriteImage_8E98828 using the first slots pal.
function Ui.renderSlotReels(data)
  local pal = readPal(data, Ui.RUBY_US.slotsPal, 16)
  if not pal then return nil end
  local found = Ui.RUBY_US.slotsReel0
  local image = ImageWriter.blank(32 * 7, 32, 0, 0, 0, 0)
  for i = 0, 6 do
    local tiles = data:sub(found + i * 0x200 + 1, found + (i + 1) * 0x200)
    if #tiles >= 0x200 then
      for t = 0, 15 do
        blitTile(image, i * 32 + (t % 4) * 8, math.floor(t / 4) * 8,
          tiles, t, pal, false, false, true)
      end
    end
  end
  return image
end

function Ui.renderRouletteBoard(data)
  local u = Ui.RUBY_US
  local tableTiles = GbaLz77.decompress(data, u.rouletteBaseGfx)
  local tableMap = GbaLz77.decompress(data, u.rouletteTableMap)
  local wheelTiles = GbaLz77.decompress(data, u.rouletteWheelGfx)
  local wheelMap = GbaLz77.decompress(data, u.rouletteMap)
  local pal16 = readPal(data, u.roulettePal, 16)
  local pal256 = readPal(data, u.roulettePal, 112)
  if not (tableTiles and tableMap and wheelTiles and wheelMap and pal16 and pal256) then
    return nil
  end
  local image = ImageWriter.blank(Ui.SCREEN_W, Ui.SCREEN_H, 0.18, 0.38, 0.55, 1)
  local maxW = math.floor(#wheelTiles / 64)
  for ty = 0, 15 do
    for tx = 0, 15 do
      local entry = GbaBin.u16(wheelMap, (ty * 32 + tx) * 2)
      local tid = entry % 1024
      if tid < maxW then
        local hf = math.floor(entry / 0x400) % 2 == 1
        local vf = math.floor(entry / 0x800) % 2 == 1
        local base = tid * 64
        for row = 0, 7 do
          for col = 0, 7 do
            local sx = hf and (7 - col) or col
            local sy = vf and (7 - row) or row
            local ci = wheelTiles:byte(base + sy * 8 + sx + 1) or 0
            if ci > 0 then
              local colr = pal256[ci] or pal256[0]
              local x = tx * 8 + col
              local y = ty * 8 + row + 16
              if x >= 0 and y >= 0 and x < Ui.SCREEN_W and y < Ui.SCREEN_H then
                image:setPixel(x, y, colr[1], colr[2], colr[3], 1)
              end
            end
          end
        end
      end
    end
  end
  local maxT = math.floor(#tableTiles / Ui.TILE_BYTES)
  local pals = {}
  for p = 0, 13 do
    pals[p] = readPal(data, u.roulettePal + p * 32, 16) or pal16
  end
  local ox, oy = 112, 8
  for ty = 0, 12 do
    for tx = 0, 15 do
      local entry = GbaBin.u16(tableMap, (ty * 16 + tx) * 2)
      local tid = entry % 1024
      local bank = math.floor(entry / 4096) % 16
      if tid < maxT then
        blitTile(image, ox + tx * 8, oy + ty * 8, tableTiles, tid,
          pals[bank] or pal16,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, false)
      end
    end
  end
  return image
end

-- naming_screen.c gUnknown_083CE6A0: twelve OBJ sheets as {ptr, size, tag},
-- verified against the cart -- every size and tag matches the decomp. The
-- palette each one wants comes from its sprite template's paletteTag, which
-- gUnknown_083CE708 maps onto gNamingScreenPalettes (note tag 6 reuses
-- palette 4). Do NOT infer these from the baked PNGs that used to live in
-- assets/naming: several of them are tinted wrong, and
-- change_keyboard_button was stored with its transparency inverted, so it
-- rendered as a hole in a white block instead of a rounded chip.
--
--   tileTag 0 back / 1 ok      -> template 83CE610 / 83CE628, palTag 6 -> 4
--   tileTag 2 keyboard box     -> template 83CE5C8,           palTag 4
--   tileTag 3 keyboard button  -> template 83CE5E0,           palTag 1
--   tileTag 4/5/6 page labels  -> template 83CE5F8,           palTag 4
--   tileTag 7/8/9 cursors      -> template 83CE640,           palTag 5
--   tileTag 10/11 caret+under  -> template 83CE658 / 83CE670, palTag 3
-- menu_helpers.c CreateVerticalScrollIndicators. One sprite template
-- (gSpriteTemplate_83E59D0) covers both vertical arrows -- anim frame 0 is
-- the up arrow and frame 1 the down -- laid out H_RECTANGLE, so its two
-- tiles sit side by side for 16x8. The horizontal pair is V_RECTANGLE, so
-- those two tiles STACK for 8x16; read side by side they come out as
-- meaningless diagonal shards.
Ui.SCROLL_ARROW_PAL = 0x3E5948          -- Palette_3E5948
Ui.SCROLL_ARROWS = {
  { name = 'up', off = 0x3E5808, w = 2, h = 1 },
  { name = 'down', off = 0x3E5848, w = 2, h = 1 },
  { name = 'left', off = 0x3E5888, w = 1, h = 2 },
  { name = 'right', off = 0x3E58C8, w = 1, h = 2 },
}

-- All four on one 16x32 sheet: up at (0,0,16,8), down at (0,8,16,8),
-- left at (0,16,8,16), right at (8,16,8,16).
function Ui.renderScrollArrows(data)
  local pal = readPal(data, Ui.SCROLL_ARROW_PAL, 16)
  if not pal then return nil end
  local image = ImageWriter.blank(16, 32, 0, 0, 0, 0)
  local place = { up = { 0, 0 }, down = { 0, 8 }, left = { 0, 16 },
    right = { 8, 16 } }
  for _, spec in ipairs(Ui.SCROLL_ARROWS) do
    local at = place[spec.name]
    local bytes = spec.w * spec.h * Ui.TILE_BYTES
    local tiles = data:sub(spec.off + 1, spec.off + bytes)
    if #tiles < bytes then return nil end
    for t = 0, spec.w * spec.h - 1 do
      blitTile(image, at[1] + (t % spec.w) * Ui.TILE,
        at[2] + math.floor(t / spec.w) * Ui.TILE, tiles, t, pal,
        false, false, true)
    end
  end
  return image
end

Ui.NAMING_SHEET_TABLE = 0x3CE6A0
Ui.NAMING_PAL_TABLE = 0x3CE708
Ui.NAMING_SHEETS = {
  { name = 'back_button', cols = 5, pal = 4 },
  { name = 'ok_button', cols = 5, pal = 4 },
  { name = 'change_keyboard_box', cols = 5, pal = 4 },
  { name = 'change_keyboard_button', cols = 4, pal = 1 },
  { name = 'lower_text', cols = 3, pal = 4 },
  { name = 'upper_text', cols = 3, pal = 4 },
  { name = 'others_text', cols = 3, pal = 4 },
  { name = 'cursor', cols = 2, pal = 5 },
  { name = 'active_cursor_small', cols = 2, pal = 5 },
  { name = 'active_cursor_big', cols = 2, pal = 5 },
  { name = 'right_pointing_triangle', cols = 1, pal = 3 },
  { name = 'underscore', cols = 1, pal = 3 },
}

-- THE NAMING SCREEN'S BG LAYERS AND PC ICONS, off the cart.
--
-- These five were the last art in the tree baked from pokeruby rather than
-- read from the ROM, and they shipped inside the APK (pack_love.sh only
-- excludes assets/generated).
--
-- naming_screen.c paints them from one tile sheet, gNamingScreenMenu_Gfx
-- (0x800 = 64 tiles, palette 0 of gNamingScreenPalettes), through two
-- painters that do NOT agree on stride: sub_80B7698 walks a keyboard page
-- 30 entries to the row, sub_80B76E0 walks the frame 32 to the row. Reading
-- the frame at 30 drifts two tiles per row and draws a diagonal band across
-- the screen -- which is how the stride was found.
--
-- Both add gMenuMessageBoxContentTileOffset, the VRAM base the sheet is
-- loaded at, so the ids are relative to the sheet and a standalone render
-- reads them straight.
--
-- Verified against the cart: bg_stripes, keyboard_upper and keyboard_lower
-- come out identical to the baked PNGs they replace, to the pixel.
-- keyboard_others differs in 94 pixels, which are the symbols
-- PrintKeyboardCharacters draws with the font at runtime -- the baked file
-- had them painted in; we draw them with Font3, like the cart.
Ui.NAMING_BG_GFX = 0xE85998
Ui.NAMING_BG_GFX_SIZE = 0x800
Ui.NAMING_SCREEN_COLS = 30
Ui.NAMING_SCREEN_ROWS = 20
Ui.NAMING_SCREENS = {
  { name = 'bg_stripes', map = 0xE86258, stride = 32 },
  { name = 'keyboard_upper', map = 0x3CEBF8, stride = 30 },
  { name = 'keyboard_lower', map = 0x3CE748, stride = 30 },
  { name = 'keyboard_others', map = 0x3CF0A8, stride = 30 },
}

function Ui.renderNamingScreen(data, index)
  local spec = Ui.NAMING_SCREENS[index]
  if not spec then return nil end
  local tiles = data:sub(Ui.NAMING_BG_GFX + 1,
    Ui.NAMING_BG_GFX + Ui.NAMING_BG_GFX_SIZE)
  if #tiles < Ui.NAMING_BG_GFX_SIZE then return nil end
  local pals = {}
  for p = 0, 5 do
    pals[p] = readPal(data, Ui.RUBY_US.namingPal0 + p * 32, 16)
  end
  if not pals[0] then return nil end
  local cols, rows = Ui.NAMING_SCREEN_COLS, Ui.NAMING_SCREEN_ROWS
  local need = (spec.stride * (rows - 1) + cols) * 2
  local map = data:sub(spec.map + 1, spec.map + need)
  if #map < need then return nil end
  local image = ImageWriter.blank(cols * Ui.TILE, rows * Ui.TILE, 0, 0, 0, 0)
  local maxTiles = math.floor(#tiles / Ui.TILE_BYTES)
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      local entry = GbaBin.u16(map, (ty * spec.stride + tx) * 2)
      local tid = entry % 1024
      local bank = math.floor(entry / 0x1000) % 16
      if tid < maxTiles then
        blitTile(image, tx * Ui.TILE, ty * Ui.TILE, tiles, tid,
          pals[bank] or pals[0],
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, true)
      end
    end
  end
  return image
end

-- The two PC-box icon frames the BOX NAME template shows. Plain 4bpp, two
-- tiles across and three down at palette 0, one after the other in the ROM.
Ui.NAMING_PC_ICONS = { 0x3CE094, 0x3CE154 }
Ui.NAMING_PC_COLS = 2
Ui.NAMING_PC_ROWS = 3

function Ui.renderNamingPcIcon(data, index)
  local off = Ui.NAMING_PC_ICONS[index]
  if not off then return nil end
  local cols, rows = Ui.NAMING_PC_COLS, Ui.NAMING_PC_ROWS
  local size = cols * rows * Ui.TILE_BYTES
  local tiles = data:sub(off + 1, off + size)
  if #tiles < size then return nil end
  local pal = readPal(data, Ui.RUBY_US.namingPal0, 16)
  if not pal then return nil end
  local image = ImageWriter.blank(cols * Ui.TILE, rows * Ui.TILE, 0, 0, 0, 0)
  for t = 0, cols * rows - 1 do
    blitTile(image, (t % cols) * Ui.TILE, math.floor(t / cols) * Ui.TILE,
      tiles, t, pal, false, false, true)
  end
  return image
end

-- One naming-screen OBJ sheet. Tiles are 1D: row-major at the sprite's own
-- width, which is why `cols` is part of the table rather than guessed.
function Ui.renderNamingSheet(data, index)
  local spec = Ui.NAMING_SHEETS[index]
  if not spec then return nil end
  local at = Ui.NAMING_SHEET_TABLE + (index - 1) * 8
  local ptr = GbaBin.u32(data, at)
  local size = GbaBin.u16(data, at + 4)
  if not GbaBin.isRomPtr(ptr, #data) or size < 32 then return nil end
  local off = ptr - GbaBin.ROM_BASE
  local tiles = data:sub(off + 1, off + size)
  if #tiles < size then return nil end
  local pal = readPal(data, Ui.RUBY_US.namingPal0 + spec.pal * 32, 16)
  if not pal then return nil end
  local n = math.floor(size / 32)
  local cols = spec.cols
  local rows = math.ceil(n / cols)
  local image = ImageWriter.blank(cols * Ui.TILE, rows * Ui.TILE, 0, 0, 0, 0)
  for t = 0, n - 1 do
    blitTile(image, (t % cols) * Ui.TILE, math.floor(t / cols) * Ui.TILE,
      tiles, t, pal, false, false, true)
  end
  return image
end

function Ui.renderNamingButtons(data)
  local u = Ui.RUBY_US
  local pal = readPal(data, u.namingPal0, 16)
  if not pal then return nil end
  local image = ImageWriter.blank(80, 24, 0, 0, 0, 0)
  for sheet = 0, 1 do
    local ptr = GbaBin.u32(data, u.namingSheetTable + sheet * 8)
    local sz = GbaBin.u16(data, u.namingSheetTable + sheet * 8 + 4)
    if GbaBin.isRomPtr(ptr, #data) and sz >= 32 then
      local off = ptr - GbaBin.ROM_BASE
      local tiles = data:sub(off + 1, off + sz)
      local n = math.floor(sz / 32)
      for t = 0, n - 1 do
        blitTile(image, sheet * 40 + (t % 5) * 8, math.floor(t / 5) * 8,
          tiles, t, pal, false, false, true)
      end
    end
  end
  return image
end

function Ui.renderPokenav(data)
  local u = Ui.RUBY_US
  local stripe = GbaLz77.decompress(data, u.pokenavStripeGfx)
  local stripeMap = GbaLz77.decompress(data, u.pokenavStripeMap)
  local stripePal = readPal(data, u.pokenavStripePal, 16)
  local outline = GbaLz77.decompress(data, u.pokenavOutlineGfx)
  local outlineMap = GbaLz77.decompress(data, u.pokenavOutlineMap)
  local outlinePal = readPal(data, u.pokenavOutlinePal, 16)
  if not (stripe and stripeMap and stripePal and outline and outlineMap and outlinePal) then
    return nil
  end
  local image = ImageWriter.blank(Ui.SCREEN_W, Ui.SCREEN_H, 0, 0, 0, 1)
  local maxS = math.floor(#stripe / Ui.TILE_BYTES)
  for ty = 0, 19 do
    for tx = 0, 29 do
      local entry = GbaBin.u16(stripeMap, (ty * 32 + tx) * 2)
      local tid = entry % 1024
      if tid < maxS then
        blitTile(image, tx * 8, ty * 8, stripe, tid, stripePal,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, false)
      end
    end
  end
  local maxO = math.floor(#outline / Ui.TILE_BYTES)
  for ty = 0, 19 do
    for tx = 0, 29 do
      local entry = GbaBin.u16(outlineMap, (ty * 32 + tx) * 2)
      local tid = entry % 1024
      if tid >= 1 then tid = tid - 1 end
      if tid < maxO then
        blitTile(image, tx * 8, ty * 8, outline, tid, outlinePal,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, true)
      end
    end
  end
  return image
end

local function safe(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

function Ui.extract(data)
  if type(data) ~= "string" or #data < 0xEA0108 + 448 then return {} end
  local statusPillPath = safe(Ui.saveStatusPills, data)
  return {
    frames = save(safe(Ui.renderFrames, data), "assets/generated/ui/window_frames.png"),
    -- text.c sDownArrowTiles; shipped under assets/generated/ui (no new extract).
    down_arrow = "assets/generated/ui/down_arrow.png",
    dialogue = save(safe(Ui.renderDialogueFrame, data),
      "assets/generated/ui/dialogue_frame.png"),
    battleMessage = save(safe(Ui.renderBattleBar, data, "message"),
      "assets/generated/ui/battle_message.png"),
    battleActions = save(safe(Ui.renderBattleBar, data, "actions"),
      "assets/generated/ui/battle_actions.png"),
    battleMoves = save(safe(Ui.renderBattleBar, data, "moves"),
      "assets/generated/ui/battle_moves.png"),
    battleBarY = Ui.BATTLE_BAR_Y,
    healthbox = save(safe(Ui.renderHealthbox, data),
      "assets/generated/ui/healthbox.png"),
    healthboxHp = save(safe(Ui.renderHealthbox, data, Ui.RUBY_US.hpBarPal),
      "assets/generated/ui/healthbox_hp.png"),
    healthboxPlayer = save(safe(Ui.renderHealthboxFrame, data, "player"),
      "assets/generated/ui/healthbox_player.png"),
    healthboxEnemy = save(safe(Ui.renderHealthboxFrame, data, "enemy"),
      "assets/generated/ui/healthbox_enemy.png"),
    healthboxPlayerDouble = (function()
      Ui.discoverHealthboxStreams(data)
      return save(safe(Ui.renderHealthboxFrame, data, "playerDouble"),
        "assets/generated/ui/healthbox_player_double.png")
    end)(),
    healthboxEnemyDouble = save(safe(Ui.renderHealthboxFrame, data, "enemyDouble"),
      "assets/generated/ui/healthbox_enemy_double.png"),
    healthboxExtra = save(safe(Ui.renderHealthboxFrame, data, "extra"),
      "assets/generated/ui/healthbox_extra.png"),
    statusPills = statusPillPath,
    braille = save(safe(Ui.renderBraille, data), "assets/generated/ui/braille.png"),
    brailleCols = Ui.BRAILLE_COLS,
    brailleGlyphs = Ui.BRAILLE_GLYPHS,
    scrollArrows = save(safe(Ui.renderScrollArrows, data),
      "assets/generated/ui/scroll_arrows.png"),
    namingSheets = (function()
      local paths = {}
      for i, spec in ipairs(Ui.NAMING_SHEETS) do
        paths[spec.name] = save(safe(Ui.renderNamingSheet, data, i),
          'assets/generated/naming/' .. spec.name .. '.png')
      end
      -- the BG layers and the box icons, which used to be baked PNGs
      for i, spec in ipairs(Ui.NAMING_SCREENS) do
        paths[spec.name] = save(safe(Ui.renderNamingScreen, data, i),
          'assets/generated/naming/' .. spec.name .. '.png')
      end
      for i = 1, #Ui.NAMING_PC_ICONS do
        paths['pc_icon_' .. (i - 1)] = save(
          safe(Ui.renderNamingPcIcon, data, i),
          ('assets/generated/naming/pc_icon_%d.png'):format(i - 1))
      end
      return paths
    end)(),
    namingButtons = save(safe(Ui.renderNamingButtons, data),
      "assets/generated/ui/naming_buttons.png"),
    namingBg = save(safe(Ui.renderMapped, data, Ui.RUBY_US.namingMenuGfx,
      Ui.RUBY_US.namingPal0, Ui.RUBY_US.namingMenuMap),
      "assets/generated/ui/naming_bg.png"),
    roulette = save(safe(Ui.renderRouletteBoard, data),
      "assets/generated/ui/roulette.png"),
    pss = save(safe(Ui.renderMapped, data, Ui.RUBY_US.pssGfx,
      Ui.RUBY_US.pssPal, Ui.RUBY_US.pssMap),
      "assets/generated/ui/pss.png"),
    slots = save(safe(Ui.renderSlotsCabinet, data),
      "assets/generated/ui/slots.png"),
    slotReels = save(safe(Ui.renderSlotReels, data),
      "assets/generated/ui/slot_reels.png"),
    pokeblockSheet = save(safe(Ui.renderLzSheet, data, Ui.RUBY_US.pokeblockGfx,
      Ui.RUBY_US.pokeblockPal, 8),
      "assets/generated/ui/pokeblock_sheet.png"),
    credits = save(safe(Ui.renderLzSheet, data, Ui.RUBY_US.creditsGfx,
      Ui.RUBY_US.creditsPal, 10),
      "assets/generated/ui/credits.png"),
    pokenav = save(safe(Ui.renderPokenav, data),
      "assets/generated/ui/pokenav.png"),
    clock = save(safe(Ui.renderMapped, data, Ui.RUBY_US.clockGfx,
      Ui.RUBY_US.clockPal, Ui.RUBY_US.clockMap),
      "assets/generated/ui/clock.png"),
    clockView = save(safe(Ui.renderMapped, data, Ui.RUBY_US.clockGfx,
      Ui.RUBY_US.clockPal, Ui.RUBY_US.clockViewMap),
      "assets/generated/ui/clock_view.png"),
    frameStyles = Ui.FRAME_STYLES,
    frameTile = Ui.TILE,
  }
end

return Ui
