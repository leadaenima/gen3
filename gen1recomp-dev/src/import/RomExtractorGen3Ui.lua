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
  namingSheetTable = 0x3CE6A0,
  namingPal0 = 0xE86198,
  namingMenuGfx = 0xE832F8,
  namingMenuMap = 0xE84878,
  -- slot_machine.c sub_8106448: pal gUnknown_08E95A18 (5 banks),
  -- map gUnknown_08E95AB8 (20*32 raw), tiles LZ gSlotMachine_Gfx (233).
  slotsPal = 0xE95A18,
  slotsMap = 0xE95AB8,
  slotsMapBytes = 20 * 32 * 2,
  slotsTiles = 233,
  slotsReel0 = 0xE96C00,
  -- roulette.c: base tiles 08E8096C, pal 083F86BC (0x1C0), map 083F8A60.
  rouletteBaseGfx = 0xE8096C,
  roulettePal = 0x3F86BC,
  rouletteMap = 0x3F8A60,
  pssPal = 0xE9F624,
  pssGfx = 0xE9EFD0,
  pssMap = 0xE9F7E4,
  pokeblockGfx = 0xE78078,
  pokeblockPal = 0xE7883C,
  creditsGfx = 0xEA260C,
  creditsPal = 0xE9F624,
}

-- Each healthbox is two OBJs drawn side by side: the name/HP box then the
-- Lv box. The player's carries the EXP bar so its halves are 64x64.
Ui.HEALTHBOX = {
  player = { off = "healthboxPlayerGfx", halfW = 64, halfH = 64 },
  enemy = { off = "healthboxEnemyGfx", halfW = 64, halfH = 32 },
}

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
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
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
  local tiles = GbaLz77.decompress(data, gfxOff)
  local map = GbaLz77.decompress(data, mapOff)
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
  local want = u.slotsTiles * Ui.TILE_BYTES
  local gfxOff, tiles = Ui.findLzSize(data, want, 0xE8E000, 0xE96000)
  if not tiles then
    gfxOff, tiles = Ui.findLzSize(data, want, 0xE80000, 0xEA0000)
  end
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
  local start = Ui.RUBY_US.slotsReel0
  local found
  for off = 0xE96000, 0xE98800, 0x20 do
    local ok = true
    for i = 0, 6 do
      local at = off + i * 0x200
      if at + 0x200 > #data then ok = false break end
    end
    if ok then found = off break end
  end
  if not found then found = start end
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
  local tiles = GbaLz77.decompress(data, u.rouletteBaseGfx)
  local map = GbaLz77.decompress(data, u.rouletteMap)
  local pal = readPal(data, u.roulettePal, 16)
  if not (tiles and pal) then return nil end
  if not map then
    map = data:sub(u.rouletteMap + 1, u.rouletteMap + 0x800)
  end
  local image = ImageWriter.blank(Ui.SCREEN_W, Ui.SCREEN_H, 0, 0, 0, 1)
  local maxTiles = math.floor(#tiles / Ui.TILE_BYTES)
  local mapW = 32
  local mapH = math.min(20, math.max(1, math.floor(#map / (mapW * 2))))
  for ty = 0, mapH - 1 do
    for tx = 0, 29 do
      local entry = GbaBin.u16(map, (ty * mapW + tx) * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        blitTile(image, tx * 8, ty * 8, tiles, tid, pal,
          math.floor(entry / 0x400) % 2 == 1,
          math.floor(entry / 0x800) % 2 == 1, false)
      end
    end
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

function Ui.extract(data)
  if type(data) ~= "string" or #data < 0xEA0108 + 448 then return {} end
  local statusPillPath = Ui.saveStatusPills(data)
  return {
    frames = save(Ui.renderFrames(data), "assets/generated/ui/window_frames.png"),
    -- text.c sDownArrowTiles; shipped under assets/generated/ui (no new extract).
    down_arrow = "assets/generated/ui/down_arrow.png",
    dialogue = save(Ui.renderDialogueFrame(data),
      "assets/generated/ui/dialogue_frame.png"),
    battleMessage = save(Ui.renderBattleBar(data, "message"),
      "assets/generated/ui/battle_message.png"),
    battleActions = save(Ui.renderBattleBar(data, "actions"),
      "assets/generated/ui/battle_actions.png"),
    battleMoves = save(Ui.renderBattleBar(data, "moves"),
      "assets/generated/ui/battle_moves.png"),
    battleBarY = Ui.BATTLE_BAR_Y,
    healthbox = save(Ui.renderHealthbox(data),
      "assets/generated/ui/healthbox.png"),
    healthboxHp = save(Ui.renderHealthbox(data, Ui.RUBY_US.hpBarPal),
      "assets/generated/ui/healthbox_hp.png"),
    healthboxPlayer = save(Ui.renderHealthboxFrame(data, "player"),
      "assets/generated/ui/healthbox_player.png"),
    healthboxEnemy = save(Ui.renderHealthboxFrame(data, "enemy"),
      "assets/generated/ui/healthbox_enemy.png"),
    statusPills = statusPillPath,
    braille = save(Ui.renderBraille(data), "assets/generated/ui/braille.png"),
    brailleCols = Ui.BRAILLE_COLS,
    brailleGlyphs = Ui.BRAILLE_GLYPHS,
    namingButtons = save(Ui.renderNamingButtons(data),
      "assets/generated/ui/naming_buttons.png"),
    namingBg = save(Ui.renderMapped(data, Ui.RUBY_US.namingMenuGfx,
      Ui.RUBY_US.namingPal0, Ui.RUBY_US.namingMenuMap),
      "assets/generated/ui/naming_bg.png"),
    roulette = save(Ui.renderRouletteBoard(data),
      "assets/generated/ui/roulette.png"),
    pss = save(Ui.renderMapped(data, Ui.RUBY_US.pssGfx,
      Ui.RUBY_US.pssPal, Ui.RUBY_US.pssMap),
      "assets/generated/ui/pss.png"),
    slots = save(Ui.renderSlotsCabinet(data),
      "assets/generated/ui/slots.png"),
    slotReels = save(Ui.renderSlotReels(data),
      "assets/generated/ui/slot_reels.png"),
    pokeblockSheet = save(Ui.renderLzSheet(data, Ui.RUBY_US.pokeblockGfx,
      Ui.RUBY_US.pokeblockPal, 8),
      "assets/generated/ui/pokeblock_sheet.png"),
    credits = save(Ui.renderLzSheet(data, Ui.RUBY_US.creditsGfx,
      Ui.RUBY_US.creditsPal, 10),
      "assets/generated/ui/credits.png"),
    frameStyles = Ui.FRAME_STYLES,
    frameTile = Ui.TILE,
  }
end

return Ui
