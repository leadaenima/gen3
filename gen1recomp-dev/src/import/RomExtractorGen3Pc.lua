-- Pokémon Storage System chrome (US Ruby 1.0).
-- pokeruby graphics/pokemon_storage + pokemon_storage_system_{2,4}.c.
-- Nintendo tiles stay out of git; PNGs land under assets/generated/pc/.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")
local Cinema = require("src.import.RomExtractorGen3Cinema")

local Pc = {}

Pc.TILE = 8
Pc.TILE_BYTES = 32

-- US Ruby 1.0 (pokemon_storage_system_2 / _4 / graphics.c).
Pc.RUBY_US = {
  scrollPal = 0x3B6A10,
  scrollTile = 0x3B6A30,
  scrollMapLz = 0x3B6A50,
  scrollMapBytes = 2048,
  -- First wallpaper (Forest): 96-byte triple pal, then tiles LZ, map LZ 720.
  forestPal = 0x3B6F64,
  forestTilesLz = 0x3B6FC4,
  -- Header / misc (graphics.c gPSSMenu*).
  headerGfxLz = 0xE8DEC0,
  headerGfxBytes = 1504,
  menu1Pal = 0xE8E0E6,
  menu2Pal = 0xE8E106,
  headerMapLz = 0xE8E128,
  headerMapBytes = 1280,
  miscGfxLz = 0xE8E244,
  miscGfxBytes = 2912,
  menu3Pal = 0xE8E6A8,
  menu4Pal = 0xE8E6C8,
  miscMapLz = 0xE8E6E8,
  miscMapBytes = 2048,
  -- OBJ sheets (pokemon_storage_system_4.c).
  arrowPal = 0x3BB1E8,
  arrowGfx = 0x3BB208,
  arrowGfxBytes = 0x80,
  handPal = 0x3BB300,
  handAltPal = 0x3BB320,
  handGfx = 0x3BB348,
  handGfxBytes = 0x800,
  handShadowGfx = 0x3BBB48,
  handShadowGfxBytes = 0x80,
}

Pc.WALLPAPERS = {
  "forest", "city", "desert", "savanna", "crag", "volcano", "snow", "cave",
  "beach", "seafloor", "river", "sky", "polkadot", "pokecenter", "machine", "plain",
}

local function bgr555(c)
  return (c % 32) * 8 / 255,
    (math.floor(c / 32) % 32) * 8 / 255,
    (math.floor(c / 1024) % 32) * 8 / 255
end

local function readPal(data, off, count)
  count = count or 16
  if type(data) ~= "string" or off < 0 or off + count * 2 > #data then
    return nil
  end
  local pal = {}
  for c = 0, count - 1 do
    pal[c] = { bgr555(GbaBin.u16(data, off + c * 2)) }
  end
  return pal
end

local function lz(data, off, expect)
  if type(data) ~= "string" or type(off) ~= "number" then return nil end
  if off < 0 or off + 4 > #data then return nil end
  if GbaBin.u8(data, off) ~= 0x10 then return nil end
  local raw = GbaLz77.decompress(data, off)
  if not raw then return nil end
  if expect and #raw ~= expect then return nil end
  return raw
end

local function slice(data, off, n)
  if type(data) ~= "string" or type(off) ~= "number" or type(n) ~= "number" then
    return nil
  end
  if n < 1 or off < 0 or off + n > #data then return nil end
  return data:sub(off + 1, off + n)
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

local function blit4(image, px, py, tile, pal, skip0)
  if not tile or #tile < Pc.TILE_BYTES then return end
  pal = pal or {}
  for ty = 0, 7 do
    for tx = 0, 7 do
      local byte = tile:byte(ty * 4 + math.floor(tx / 2) + 1) or 0
      local ci = (tx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if not (skip0 and ci == 0) then
        local col = pal[ci]
        if col then
          local a = 1
          -- Hand cursor keys magenta (0x7F1F) out of the sheet.
          if col[1] >= 0.95 and col[2] <= 0.05 and col[3] >= 0.95 then
            a = 0
          end
          local x, y = px + tx, py + ty
          if x >= 0 and y >= 0 and x < image:getWidth() and y < image:getHeight() then
            image:setPixel(x, y, col[1], col[2], col[3], a)
          end
        end
      end
    end
  end
end

local function blitObjSheet(image, tiles, pal, tile0, tw, th, dx, dy)
  if not (image and tiles and pal) then return end
  local tilesN = math.floor(#tiles / Pc.TILE_BYTES)
  for row = 0, th - 1 do
    for col = 0, tw - 1 do
      local id = tile0 + row * tw + col
      if id >= 0 and id < tilesN then
        local tile = tiles:sub(id * Pc.TILE_BYTES + 1, (id + 1) * Pc.TILE_BYTES)
        blit4(image, dx + col * 8, dy + row * 8, tile, pal, true)
      end
    end
  end
end

local function lzCompressedLen(data, off)
  if GbaBin.u8(data, off) ~= 0x10 then return nil end
  local size = GbaBin.u8(data, off + 1)
    + GbaBin.u8(data, off + 2) * 256
    + GbaBin.u8(data, off + 3) * 65536
  local i = off + 4
  local written = 0
  while written < size do
    local flags = GbaBin.u8(data, i)
    i = i + 1
    for bit = 0, 7 do
      if written >= size then break end
      if math.floor(flags / (2 ^ (7 - bit))) % 2 == 1 then
        local b1 = GbaBin.u8(data, i)
        i = i + 2
        written = written + math.floor(b1 / 16) + 3
      else
        i = i + 1
        written = written + 1
      end
    end
  end
  return i - off, size
end

function Pc.readWallpaperPals(data, palOff)
  local pals = {}
  for i = 0, 2 do
    pals[i] = readPal(data, palOff + i * 32, 16)
    if not pals[i] then return nil end
  end
  return pals
end

function Pc.renderWallpaper(data, palOff, tilesOff)
  local pals = Pc.readWallpaperPals(data, palOff)
  local tiles = lz(data, tilesOff)
  if not (pals and tiles and #tiles % Pc.TILE_BYTES == 0) then return nil end
  local tileLen = lzCompressedLen(data, tilesOff)
  if not tileLen then return nil end
  local mapOff = tilesOff + tileLen
  local guard = 0
  while GbaBin.u8(data, mapOff) ~= 0x10 do
    mapOff = mapOff + 1
    guard = guard + 1
    if guard > 16 then return nil end
  end
  local map = lz(data, mapOff, 720)
  if not map then return nil end
  local image = ImageWriter.blank(160, 144, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, tiles, map, pals, 20, 18, 0, 0, false)
end

function Pc.renderAllWallpapers(data)
  local out = {}
  local palOff = Pc.RUBY_US.forestPal
  local tilesOff = Pc.RUBY_US.forestTilesLz
  for i = 1, #Pc.WALLPAPERS do
    local name = Pc.WALLPAPERS[i]
    local img = Pc.renderWallpaper(data, palOff, tilesOff)
    if not img then return nil end
    out[name] = img
    if i < #Pc.WALLPAPERS then
      local tileLen = lzCompressedLen(data, tilesOff)
      if not tileLen then return nil end
      local mapOff = tilesOff + tileLen
      while GbaBin.u8(data, mapOff) ~= 0x10 do
        mapOff = mapOff + 1
        if mapOff > tilesOff + tileLen + 8 then return nil end
      end
      local mapLen = lzCompressedLen(data, mapOff)
      if not mapLen then return nil end
      local next = mapOff + mapLen
      -- 96-byte triple palette, then next tiles LZ.
      local probe = next
      local guard = 0
      while GbaBin.u8(data, probe + 96) ~= 0x10 do
        probe = probe + 1
        guard = guard + 1
        if guard > 16 then return nil end
      end
      palOff = probe
      tilesOff = probe + 96
    end
  end
  return out
end

local function remapTileBase(map, base)
  if not map or (base or 0) == 0 then return map end
  local parts = {}
  for i = 1, #map, 2 do
    local lo, hi = map:byte(i, i + 1)
    local e = lo + (hi or 0) * 256
    local id = e % 1024
    local meta = e - id
    if id >= base then
      id = id - base
    else
      id = 0
    end
    e = meta + id
    parts[#parts + 1] = string.char(e % 256, math.floor(e / 256) % 256)
  end
  return table.concat(parts)
end

function Pc.renderHeader(data)
  local u = Pc.RUBY_US
  local tiles = lz(data, u.headerGfxLz, u.headerGfxBytes)
  local map = lz(data, u.headerMapLz, u.headerMapBytes)
  local p0 = readPal(data, u.menu2Pal, 16)
  local p1 = readPal(data, u.menu1Pal, 16)
  if not (tiles and map and p0 and p1) then return nil end
  -- Tilemap ids are VRAM indices after LoadBgTiles at base 640.
  map = remapTileBase(map, 640)
  local image = ImageWriter.blank(80, 160, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, tiles, map, { [0] = p0, [1] = p1 },
    32, 20, 0, 0, false)
end

function Pc.renderMiscRegion(data, srcCol, srcRow, cols, rows)
  local u = Pc.RUBY_US
  local tiles = lz(data, u.miscGfxLz, u.miscGfxBytes)
  local map = lz(data, u.miscMapLz, u.miscMapBytes)
  -- LoadPalette menu3→0x20, menu4→0x30 (banks 2 / 3).
  local p2 = readPal(data, u.menu3Pal, 16)
  local p3 = readPal(data, u.menu4Pal, 16)
  if not (tiles and map and p2 and p3) then return nil end
  -- Misc tiles load at VRAM base 832.
  map = remapTileBase(map, 832)
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, tiles, map, { [2] = p2, [3] = p3 },
    32, 32, srcCol * 8, srcRow * 8, false)
end

function Pc.renderScrollingBg(data)
  local u = Pc.RUBY_US
  local pal = readPal(data, u.scrollPal, 16)
  local tile = slice(data, u.scrollTile, 32)
  if not (pal and tile) then return nil end
  local image = ImageWriter.blank(8, 8, 0, 0, 0, 1)
  blit4(image, 0, 0, tile, pal, false)
  return image
end

function Pc.renderHand(data)
  local u = Pc.RUBY_US
  local pal = readPal(data, u.handPal, 16)
  local tiles = slice(data, u.handGfx, u.handGfxBytes)
  if not (pal and tiles) then return nil end
  -- Four 32×32 frames stacked (point / grab / SELECT / unused).
  local image = ImageWriter.blank(32, 128, 0, 0, 0, 0)
  for frame = 0, 3 do
    blitObjSheet(image, tiles, pal, frame * 16, 4, 4, 0, frame * 32)
  end
  return image
end

function Pc.renderHandShadow(data)
  local u = Pc.RUBY_US
  local pal = readPal(data, u.handPal, 16)
  local tiles = slice(data, u.handShadowGfx, u.handShadowGfxBytes)
  if not (pal and tiles) then return nil end
  local image = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObjSheet(image, tiles, pal, 0, 2, 2, 0, 0)
  return image
end

function Pc.renderArrow(data)
  local u = Pc.RUBY_US
  local pal = readPal(data, u.arrowPal, 16)
  local tiles = slice(data, u.arrowGfx, u.arrowGfxBytes)
  if not (pal and tiles) then return nil end
  -- Two 8×16 frames stacked → 8×32 sheet (Game3Pc quads y=0 / y=16).
  local image = ImageWriter.blank(8, 32, 0, 0, 0, 0)
  blitObjSheet(image, tiles, pal, 0, 1, 2, 0, 0)
  blitObjSheet(image, tiles, pal, 2, 1, 2, 0, 16)
  return image
end

function Pc.extract(data)
  if type(data) ~= "string" or #data < 0xE8F000 then return {} end
  local out = {}
  out.scroll = save(Pc.renderScrollingBg(data),
    "assets/generated/pc/scrolling_bg.png")
  out.header = save(Pc.renderHeader(data),
    "assets/generated/pc/header.png")
  out.party = save(Pc.renderMiscRegion(data, 0, 0, 12, 22),
    "assets/generated/pc/party_panel.png")
  out.partyBar = save(Pc.renderMiscRegion(data, 0, 20, 12, 2),
    "assets/generated/pc/party_close_bar.png")
  out.btnClose = save(Pc.renderMiscRegion(data, 12, 0, 9, 2),
    "assets/generated/pc/btn_close.png")
  out.btnCloseFlash = save(Pc.renderMiscRegion(data, 12, 2, 9, 2),
    "assets/generated/pc/btn_close_flash.png")
  out.hand = save(Pc.renderHand(data),
    "assets/generated/pc/hand_cursor.png")
  out.shadow = save(Pc.renderHandShadow(data),
    "assets/generated/pc/hand_cursor_shadow.png")
  out.arrow = save(Pc.renderArrow(data),
    "assets/generated/pc/arrow.png")
  local papers = Pc.renderAllWallpapers(data)
  if papers then
    for name, img in pairs(papers) do
      out["wp_" .. name] = save(img,
        ("assets/generated/pc/wallpapers/%s.png"):format(name))
    end
  end
  return out
end

return Pc
