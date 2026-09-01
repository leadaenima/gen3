-- Ruby boot cinema.  pokeruby intro.c / title_screen.c graphics are LZ77
-- in the cart; Nintendo tiles stay out of git.
-- Title BG2 is Mode 1 affine 8bpp (tilemap gUnknown_08E9F7E4, BG2X/Y -29/-33).
-- Intro1 BGs are 256x512; intro2 grass+trees scroll at runtime.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local ImageWriter = require("src.import.ImageWriter")

local Cinema = {}

Cinema.SCREEN_W = 240
Cinema.SCREEN_H = 160
Cinema.MAP_PITCH = 32
Cinema.TILE = 8
Cinema.TILE_BYTES = 32
Cinema.TILE_8BPP = 64

-- US Ruby 1.0 (pokeruby English labels). Finders fall back to palettes.
Cinema.RUBY_US = {
  -- gIntroCopyright_Gfx is LZ and ends at 0xE9CA21, padded to the 4-byte
  -- aligned palette; the raw (uncompressed) 32x20 tilemap follows that.
  -- Text is index 15 (white) on index 1 (black).
  copyrightGfx = 0xE9C798,
  copyrightPal = 0xE9CA24,
  copyrightMap = 0xE9CA44,
  copyrightMapBytes = 0x500,
  intro1Pals = 0x406974,
  intro1Maps = { 0x406B74, 0x406F28, 0x40725C, 0x40754C },
  intro1Gfx = 0x407764,
  intro1GfxBytes = 32768,
  -- Task_IntroLoadPart1Graphics REG_BGnVOFS: BG0, BG1, BG2, BG3.
  intro1Vofs = { 0x28, 0x18, 0x50, 0 },
  -- Task_IntroScrollDownAndShowEon subtracts per frame (fixed point >> 16).
  intro1Rate = { 1.5, 1.0, 0.75, 0 },
  intro1W = 256,
  intro1H = 256,
  gfGfx = 0x406380,
  gfGfxBytes = 0x1400,
  gfPal = 0x406360,
  -- Palette_406340 / gUnknown_0840B028 tag 2000. Same tiles as GAME FREAK.
  dropPal = 0x406340,
  -- gIntro1EonPalette / gIntro1EonTiles (0x400 = one 64x32 OBJ).
  eonPal = 0x40ACDC,
  eonGfx = 0x40ACFC,
  eonGfxBytes = 0x400,
  -- gUnknown_08413CCC + gIntro2TreeTiles, then Brendan / bike / Latios.
  treeObjPal = 0x413CCC,
  treeObjGfx = 0x413CEC,
  treeObjGfxBytes = 0x400,
  brendanPal = 0x4143B4,
  brendanGfx = 0x4143D4,
  brendanGfxBytes = 0x3800,
  bikeGfx = 0x415E08,
  bikeGfxBytes = 0x1000,
  latiosPal = 0x416234,
  latiosGfx = 0x416254,
  latiosGfxBytes = 0x1000,
  -- intro.c gIntro3Pokeball* immediately after intro1 tiles.
  ballPal = 0x4098D4,
  ballPalBytes = 0x200,
  ballMap = 0x409AD4,
  ballMapBytes = 0x400,
  ballGfx = 0x409C04,
  ballGfxBytes = 0x4000,
  streakPal = 0x40A758,
  streakGfx = 0x40A778,
  streakGfxBytes = 0x100,
  streakMap = 0x40A7E4,
  streakMapBytes = 0x800,
  miscPal = 0x40A920,
  miscPal2 = 0x40A940,
  miscGfx = 0x40A960,
  miscGfxBytes = 0xA00,
  pokeGfx = 0xD02508,
  pokePal = 0xD025C4,
  -- gTrainerBackPic_Brendan / May + LZ pals (battle_1.c).
  brendanBackGfx = 0xE57AC8,
  brendanBackGfxBytes = 0x2000,
  brendanBackPal = 0xE5A028,
  mayBackGfx = 0xE5889C,
  mayBackGfxBytes = 0x2000,
  mayBackPal = 0xE5A050,
  groudonPal = 0x393210,
  groudonGfx = 0x393250,
  groudonGfxBytes = 8192,
  groudonMap = 0x3939EC,
  groudonMapBytes = 1280,
  lavaMap = 0x393BF8,
  lavaMapBytes = 2048,
  logoGfx = 0xE9D8CC,
  logoGfxBytes = 16384,
  logoMap = 0xE9F7E4,
  logoMapBytes = 1024,
  -- title_screen.c sets BG2X/Y to -29/-33 during setup, then
  -- Task_TitleScreenPhase2 slides the logo up and Phase3 rests at BG2Y 0.
  logoBg2X = -29,
  logoBg2Y = 0,
  versionGfx = 0xE9EFD0,
  versionGfxBytes = 4096,
  logoPal = 0xE9F624,
  logoPalBytes = 0x1C0,
  pressStartGfx = 0xE9D644,
  pressStartGfxBytes = 0x520,
  grassPal = 0x4121FC,
  grassGfx = 0x41225C,
  grassGfxBytes = 8192,
  grassMap = 0x4126DC,
  grassMapBytes = 2048,
  treesPal = 0x413300,
  treesGfx = 0x413340,
  treesGfxBytes = 8192,
  treesMap = 0x4139C8,
  treesMapBytes = 4096,
  intro2W = 256,
  intro2H = 256,
  -- graphics.c gCableCarBG_Pal (64 colours = 0x80). Sky RGB in pal 2
  -- found the row; BG LZ, car LZ, door LZ, cord LZ follow.
  cableCarBgPal = 0xE7EB9C,
  cableCarBgPalBytes = 0x80,
  cableCarPal = 0xE7EC1C,
  cableCarBgGfx = 0xE7EC3C,
  cableCarBgGfxBytes = 0x4000,
  cableCarGfx = 0xE80614,
  cableCarGfxBytes = 0x800,
  cableCarDoorGfx = 0xE80914,
  cableCarDoorGfxBytes = 0x40,
  cableCarCordGfx = 0xE80944,
  cableCarCordGfxBytes = 0x80,
  -- cable_car.c LZ tilemaps packed immediately before the mountain map.
  cableCarChimneyMap = 0x401820,
  cableCarChimneyMapBytes = 360,
  cableCarTreeMap = 0x401978,
  cableCarTreeMapBytes = 960,
  cableCarMountainMap = 0x401AFC,
  cableCarMountainMapBytes = 1200,
  cableCarPylonStemMap = 0x401CD4,
  cableCarPylonStemMapBytes = 120,
  -- egg_hatch.c sEggPalette / sEggHatchTiles / sEggShardTiles. SpriteSheet
  -- tag 12345 at 0x20A3B0 points here (uncompressed 4bpp).
  eggHatchPal = 0x209AD8,
  eggHatchGfx = 0x209AF8,
  eggHatchGfxBytes = 2048,
  eggShardGfx = 0x20A2F8,
  eggShardGfxBytes = 128,
  -- trade.c gUnknown_0820C9F8. Hatch loads these at pal 1 and paints
  -- shadow_map; the in-game trade GBA uses gba_map on the same tiles.
  tradeGbaPal = 0x20C9F8,
  tradeGbaPalBytes = 0xA0,
  tradeGbaGfx = 0x20CA98,
  tradeGbaGfxBytes = 0x1300,
  hatchBgMap = 0x20F798,
  hatchBgMapBytes = 0x1000,
  tradeGbaMap = 0x210798,
  tradeGbaMapBytes = 0x1000,
  -- trade.c after gba_map: cable closeup, pokéball symbol, glow / cable
  -- end / GBA-screen OBJs, then Mode 1 gba_affine.8bpp.
  tradeCableMap = 0x211798,
  tradeCableMapBytes = 0x800,
  tradeBallPal = 0x20C3D8,
  tradeBallGfx = 0x20C3F8,
  tradeBallGfxBytes = 0x600,
  tradeSymbolGfx = 0x20DD98,
  tradeSymbolGfxBytes = 0x1A00,
  tradeSymbolMap = 0x211F98,
  tradeSymbolMapBytes = 0x100,
  tradeCableEndPal = 0x2120B8,
  tradeGlowPal = 0x212118,
  tradeGlow1Gfx = 0x212138,
  tradeGlow1GfxBytes = 0x200,
  tradeGlow2Gfx = 0x212338,
  tradeGlow2GfxBytes = 0x300,
  tradeCableEndGfx = 0x212638,
  tradeCableEndGfxBytes = 0x100,
  tradeGbaScreenGfx = 0x212738,
  tradeGbaScreenGfxBytes = 0x1000,
  tradeAffineGfx = 0x213738,
  tradeAffineGfxBytes = 0x2040,
  tradeAffineMap = 0x215778,
  tradeAffineMapBytes = 0x100,
  -- rotating_gate.c: Fortree then Trick House configs (u16 x,y / u8 shape,ori
  -- / u16 pad), then INCBIN order 1,2,3,5,6,7,0,4. Pal is OBJ tag 0x1108
  -- (gObjectEventPalette5) matching OAM paletteNum 5.
  rotatingGateFortree = 0x3D2964,
  rotatingGatePal = 0x323C48,
  rotatingGatePalTag = 0x1108,
  rotatingGate = {
    [0] = { off = 0x3D5A0C, bytes = 0x200, tw = 4, th = 4 },
    [1] = { off = 0x3D2A0C, bytes = 0x800, tw = 8, th = 8 },
    [2] = { off = 0x3D320C, bytes = 0x800, tw = 8, th = 8 },
    [3] = { off = 0x3D3A0C, bytes = 0x800, tw = 8, th = 8 },
    [4] = { off = 0x3D5C0C, bytes = 0x200, tw = 4, th = 4 },
    [5] = { off = 0x3D420C, bytes = 0x800, tw = 8, th = 8 },
    [6] = { off = 0x3D4A0C, bytes = 0x800, tw = 8, th = 8 },
    [7] = { off = 0x3D520C, bytes = 0x800, tw = 8, th = 8 },
  },
  -- field_effect.c: pokeball_glow.4bpp + pal 04 (tag 0x1007), then
  -- pokecenter monitors, big/small HoF monitors, pal 05 (tag 0x1010).
  pokeballGlowGfx = 0x39E434,
  pokeballGlowGfxBytes = 0x20,
  pokeballGlowPal = 0x39E454,
  pokecenterMon0Gfx = 0x39E474,
  pokecenterMonGfxBytes = 0xC0,
  pokecenterMon1Gfx = 0x39E534,
  pokecenterMonPal = 0x369488,
  hofMonitorBigGfx = 0x39E5F4,
  hofMonitorBigGfxBytes = 0x200,
  hofMonitorSmallGfx = 0x39E7F4,
  hofMonitorSmallGfxBytes = 0x100,
  hofMonitorPal = 0x39E8F4,
  -- region_map.c INCBINs: cursor pal, small/large LZ, Brendan/May icons,
  -- then 8bpp map + 64x64 affine tilemap. Pal loads at BG index 0x70.
  regionMapCursorPal = 0x3E5AD0,
  regionMapCursorSmallLz = 0x3E5AF0,
  regionMapCursorSmallBytes = 0x100,
  regionMapBrendanPal = 0x3E5C20,
  regionMapBrendanGfx = 0x3E5C40,
  regionMapIconBytes = 0x80,
  regionMapMayPal = 0x3E5CC0,
  regionMapMayGfx = 0x3E5CE0,
  regionMapPal = 0x3E5D60,
  regionMapPalCount = 32,
  regionMapPalIndex = 0x70,
  regionMapGfxLz = 0x3E5DA0,
  regionMapGfxBytes = 0x3A40,
  regionMapMapLz = 0x3E6B04,
  regionMapMapBytes = 0x1000,
  regionMapWrap = 512,
  regionMapPitch = 64,
}

local function bgr555(c)
  local r = (c % 32) * 8 / 255
  local g = (math.floor(c / 32) % 32) * 8 / 255
  local b = (math.floor(c / 1024) % 32) * 8 / 255
  return r, g, b
end

local function readPal(data, off, count)
  count = count or 16
  if off < 0 or off + count * 2 > #data then return nil end
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

local function readPalLz(data, off)
  local raw = lz(data, off, 0x20)
  if not raw then return nil end
  local pal = {}
  for c = 0, 15 do
    pal[c] = { bgr555(GbaBin.u16(raw, c * 2)) }
  end
  return pal
end

local function blit4(image, px, py, tile, pal, hflip, vflip, skip0)
  if not tile or #tile < Cinema.TILE_BYTES then return end
  pal = pal or {}
  for ty = 0, 7 do
    for tx = 0, 7 do
      local sx = hflip and (7 - tx) or tx
      local sy = vflip and (7 - ty) or ty
      local byte = tile:byte(sy * 4 + math.floor(sx / 2) + 1) or 0
      local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if not (skip0 and ci == 0) then
        local col = pal[ci] or { 0, 0, 0 }
        local x, y = px + tx, py + ty
        if x >= 0 and y >= 0 and x < image:getWidth() and y < image:getHeight() then
          image:setPixel(x, y, col[1], col[2], col[3], 1)
        end
      end
    end
  end
end

function Cinema.paintTilemap(image, tiles, map, pals, mapW, mapH, scrollX, scrollY, skip0)
  if not (image and tiles and map) then return image end
  pals = pals or {}
  mapW = mapW or Cinema.MAP_PITCH
  mapH = mapH or math.floor(#map / 2 / mapW)
  scrollX = scrollX or 0
  scrollY = scrollY or 0
  local tw = image:getWidth()
  local th = image:getHeight()
  local x0 = math.floor(scrollX / 8)
  local y0 = math.floor(scrollY / 8)
  local tilesN = math.floor(#tiles / Cinema.TILE_BYTES)
  for row = 0, math.floor((th - 1) / 8) do
    for col = 0, math.floor((tw - 1) / 8) do
      local mx = (x0 + col) % mapW
      local my = y0 + row
      if my >= 0 and my < mapH then
        local entry = GbaBin.u16(map, (my * mapW + mx) * 2)
        local id = entry % 1024
        if id < tilesN then
          local palN = math.floor(entry / 4096) % 16
          local hflip = math.floor(entry / 1024) % 2 == 1
          local vflip = math.floor(entry / 2048) % 2 == 1
          local pal = pals[palN] or pals[0]
          local tile = tiles:sub(id * Cinema.TILE_BYTES + 1,
            (id + 1) * Cinema.TILE_BYTES)
          blit4(image, col * 8 - (scrollX % 8), row * 8 - (scrollY % 8),
            tile, pal, hflip, vflip, skip0)
        end
      end
    end
  end
  return image
end

-- Mode 1 affine BG, 8-bit tilemap, 256-color tiles. AFF256x256 wraps 256.
function Cinema.paintAffine8(image, tiles, map, pal, bg2x, bg2y, wrap, pitch)
  if not (image and tiles and map) then return image end
  pal = pal or {}
  bg2x = bg2x or 0
  bg2y = bg2y or 0
  wrap = wrap or 256
  pitch = pitch or 32
  local tw, th = image:getWidth(), image:getHeight()
  local tilesN = math.floor(#tiles / Cinema.TILE_8BPP)
  local mapN = #map
  for sy = 0, th - 1 do
    for sx = 0, tw - 1 do
      local tx = (sx + bg2x) % wrap
      local ty = (sy + bg2y) % wrap
      if tx < 0 then tx = tx + wrap end
      if ty < 0 then ty = ty + wrap end
      local col, row = math.floor(tx / 8), math.floor(ty / 8)
      local idx = row * pitch + col + 1
      if idx >= 1 and idx <= mapN then
        local id = map:byte(idx) or 0
        if id < tilesN then
          local px, py = tx % 8, ty % 8
          local ci = tiles:byte(id * Cinema.TILE_8BPP + py * 8 + px + 1) or 0
          if ci ~= 0 then
            local c = pal[ci]
            if c then
              image:setPixel(sx, sy, c[1], c[2], c[3], 1)
            end
          end
        end
      end
    end
  end
  return image
end

local function blitObj4(image, tiles, pal, tile0, tw, th, dx, dy)
  if not (image and tiles and pal) then return end
  local tilesN = math.floor(#tiles / Cinema.TILE_BYTES)
  for row = 0, th - 1 do
    for col = 0, tw - 1 do
      local id = tile0 + row * tw + col
      if id >= 0 and id < tilesN then
        local tile = tiles:sub(id * Cinema.TILE_BYTES + 1,
          (id + 1) * Cinema.TILE_BYTES)
        blit4(image, dx + col * 8, dy + row * 8, tile, pal, false, false, true)
      end
    end
  end
end

local function blitObj8(image, tiles, pal, tile0, tw, th, dx, dy)
  if not (image and tiles and pal) then return end
  local tilesN = math.floor(#tiles / Cinema.TILE_8BPP)
  for row = 0, th - 1 do
    for col = 0, tw - 1 do
      local id = tile0 + row * tw + col
      if id >= 0 and id < tilesN then
        local base = id * Cinema.TILE_8BPP
        for ty = 0, 7 do
          for tx = 0, 7 do
            local ci = tiles:byte(base + ty * 8 + tx + 1) or 0
            if ci ~= 0 then
              local c = pal[ci]
              if c then
                local x, y = dx + col * 8 + tx, dy + row * 8 + ty
                if x >= 0 and y >= 0 and x < image:getWidth()
                    and y < image:getHeight() then
                  image:setPixel(x, y, c[1], c[2], c[3], 1)
                end
              end
            end
          end
        end
      end
    end
  end
end

function Cinema.renderCopyright(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.copyrightGfx, 1376)
  local pal = readPal(data, u.copyrightPal, 16)
  local map = data:sub(u.copyrightMap + 1, u.copyrightMap + u.copyrightMapBytes)
  if not (gfx and pal and #map == u.copyrightMapBytes) then return nil end
  local image = ImageWriter.blank(Cinema.SCREEN_W, Cinema.SCREEN_H, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, gfx, map, { [0] = pal }, 32, 20, 0, 0, false)
end

-- The four part-1 BGs parallax at different rates, so each stays its own
-- 256x256 layer and the runtime scrolls them independently. Only BG3 is
-- opaque; the rest keep color 0 transparent.
function Cinema.renderIntro1Layers(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.intro1Gfx, u.intro1GfxBytes)
  if not gfx then return nil end
  local pals = {}
  for i = 0, 15 do
    pals[i] = readPal(data, u.intro1Pals + i * 32, 16)
    if not pals[i] then return nil end
  end
  local layers = {}
  for i = 1, 4 do
    local map = lz(data, u.intro1Maps[i], 2048)
    if not map then return nil end
    local opaque = i == 4
    local image = ImageWriter.blank(u.intro1W, u.intro1H, 0, 0, 0,
      opaque and 1 or 0)
    Cinema.paintTilemap(image, gfx, map, pals, 32, 32, 0, 0, not opaque)
    layers[i] = image
  end
  return layers
end

function Cinema.renderGameFreak(data)
  -- CreateGameFreakLogo(120, 80): 9x 16x16 + 8x 8x8 + 32x64 OBJ.
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.gfGfx, u.gfGfxBytes)
  local pal = readPal(data, u.gfPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(Cinema.SCREEN_W, Cinema.SCREEN_H, 0, 0, 0, 0)
  local letters = { 80, 84, 88, 92, 96, 100, 104 }
  local big = {
    { 0, -72 }, { 1, -56 }, { 2, -40 }, { 3, -24 }, { 4, 8 },
    { 5, 24 }, { 3, 40 }, { 1, 56 }, { 6, 72 },
  }
  local small = {
    { 0, -28 }, { 1, -20 }, { 2, -12 }, { 3, -4 },
    { 2, 4 }, { 4, 12 }, { 5, 20 }, { 3, 28 },
  }
  -- Letters are CreateSprite'd first (lower OAM index = in front of the G).
  blitObj4(image, gfx, pal, 128, 4, 8, 120 - 16, 76 - 32)
  for i = 1, #big do
    local cx, cy = 120 + big[i][2], 76
    blitObj4(image, gfx, pal, letters[big[i][1] + 1], 2, 2, cx - 8, cy - 8)
  end
  for i = 1, #small do
    local cx, cy = 120 + small[i][2], 92
    blitObj4(image, gfx, pal, 112 + small[i][1], 1, 1, cx - 4, cy - 4)
  end
  return image
end

local function sheetOf(data, gfxOff, gfxBytes, palOff, frames, tw, th)
  local gfx = lz(data, gfxOff, gfxBytes)
  local pal = readPal(data, palOff, 16)
  if not (gfx and pal) then return nil end
  local fw, fh = tw * Cinema.TILE, th * Cinema.TILE
  local image = ImageWriter.blank(fw * frames, fh, 0, 0, 0, 0)
  local tilesPer = tw * th
  for i = 0, frames - 1 do
    blitObj4(image, gfx, pal, i * tilesPer, tw, th, i * fw, 0)
  end
  return image
end

-- CreateWaterDrop: 32x32 drop (anim 2, tile 0) and 64x32 splash (anim 3, tile 48).
function Cinema.renderIntro1Drop(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.gfGfx, u.gfGfxBytes)
  local pal = readPal(data, u.dropPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(32, 32, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, 4, 4, 0, 0)
  return image
end

function Cinema.renderIntro1Splash(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.gfGfx, u.gfGfxBytes)
  local pal = readPal(data, u.dropPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(64, 32, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 48, 8, 4, 0, 0)
  return image
end

function Cinema.renderIntro1Eon(data)
  local u = Cinema.RUBY_US
  return sheetOf(data, u.eonGfx, u.eonGfxBytes, u.eonPal, 1, 8, 4)
end

-- gUnknown_08416C10: 32x32 (tile 0) + two 16x32 (tiles 16 and 24).
function Cinema.renderIntro2TreeObj(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.treeObjGfx, u.treeObjGfxBytes)
  local pal = readPal(data, u.treeObjPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(64, 32, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, 4, 4, 0, 0)
  blitObj4(image, gfx, pal, 16, 2, 4, 32, 0)
  blitObj4(image, gfx, pal, 24, 2, 4, 48, 0)
  return image
end

-- 7x 64x64 rider (gSpriteTemplate_8416CDC). Bicycle is a separate 64x32.
function Cinema.renderIntro2Brendan(data)
  local u = Cinema.RUBY_US
  return sheetOf(data, u.brendanGfx, u.brendanGfxBytes, u.brendanPal, 7, 8, 8)
end

function Cinema.renderIntro2Bike(data)
  local u = Cinema.RUBY_US
  return sheetOf(data, u.bikeGfx, u.bikeGfxBytes, u.brendanPal, 4, 8, 4)
end

-- Two 64x64 halves (anim 0 / 1) side by side = 128x64 Latios.
function Cinema.renderIntro2Latios(data)
  local u = Cinema.RUBY_US
  return sheetOf(data, u.latiosGfx, u.latiosGfxBytes, u.latiosPal, 2, 8, 8)
end

-- Mode 1 AFF256x256 8bpp pokéball. Runtime zoom is Game3.intro3Ball.
function Cinema.renderIntro3Ball(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.ballPal, 256)
  local map = lz(data, u.ballMap, u.ballMapBytes)
  local gfx = lz(data, u.ballGfx, u.ballGfxBytes)
  if not (pal and map and gfx) then return nil end
  local image = ImageWriter.blank(256, 256, 0, 0, 0, 0)
  return Cinema.paintAffine8(image, gfx, map, pal, 0, 0)
end

function Cinema.renderIntro3Streaks(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.streakPal, 16)
  local gfx = lz(data, u.streakGfx, u.streakGfxBytes)
  local map = lz(data, u.streakMap, u.streakMapBytes)
  if not (pal and gfx and map) then return nil end
  local image = ImageWriter.blank(256, 256, 0, 0, 0, 0)
  return Cinema.paintTilemap(image, gfx, map, { [0] = pal }, 32, 32, 0, 0, true)
end

-- 4x 64x64 back-pic frames. pals are LZ 0x20.
function Cinema.renderIntro3Trainer(data, who)
  local u = Cinema.RUBY_US
  local gfxOff, palOff, bytes = u.brendanBackGfx, u.brendanBackPal,
    u.brendanBackGfxBytes
  if who == "may" then
    gfxOff, palOff, bytes = u.mayBackGfx, u.mayBackPal, u.mayBackGfxBytes
  end
  local gfx = lz(data, gfxOff, bytes)
  local pal = readPalLz(data, palOff)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(256, 64, 0, 0, 0, 0)
  for i = 0, 3 do
    blitObj4(image, gfx, pal, i * 64, 8, 8, i * 64, 0)
  end
  return image
end

function Cinema.renderIntro3Brendan(data)
  return Cinema.renderIntro3Trainer(data, "brendan")
end

function Cinema.renderIntro3May(data)
  return Cinema.renderIntro3Trainer(data, "may")
end

function Cinema.renderIntro3Poke(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.pokeGfx)
  local pal = readPalLz(data, u.pokePal)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, 2, 2, 0, 0)
  return image
end

function Cinema.renderIntro3Misc(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.miscGfx, u.miscGfxBytes)
  local pal = readPal(data, u.miscPal, 16)
  if not (gfx and pal) then return nil end
  -- Tile 16 is the 64x64 blast; tile 1 is the 8x8 pop spark.
  local blast = ImageWriter.blank(64, 64, 0, 0, 0, 0)
  blitObj4(blast, gfx, pal, 16, 8, 8, 0, 0)
  local spark = ImageWriter.blank(8, 8, 0, 0, 0, 0)
  blitObj4(spark, gfx, pal, 1, 1, 1, 0, 0)
  return blast, spark
end

-- pal 2004 (misc2): water drop tile 2, ember tile 10. Both 16x16.
function Cinema.renderIntro3AttackGfx(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.miscGfx, u.miscGfxBytes)
  local pal = readPal(data, u.miscPal2, 16)
  if not (gfx and pal) then return nil end
  local water = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObj4(water, gfx, pal, 2, 2, 2, 0, 0)
  local ember = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObj4(ember, gfx, pal, 10, 2, 2, 0, 0)
  return water, ember
end

function Cinema.renderIntro2Layers(data)
  -- load_intro_part2_graphics(1) + sub_8148C78: the 0x1000 tree map fills
  -- screenbase 6 (BG3, pri 3) and 7 (BG2, pri 2). Grass is BG1 pri 1.
  local u = Cinema.RUBY_US
  local grass = lz(data, u.grassGfx, u.grassGfxBytes)
  local gmap = lz(data, u.grassMap, u.grassMapBytes)
  local gpal = readPal(data, u.grassPal, 16)
  local trees = lz(data, u.treesGfx, u.treesGfxBytes)
  local tmap = lz(data, u.treesMap, u.treesMapBytes)
  local tpal = readPal(data, u.treesPal, 16)
  if not (grass and gmap and gpal) then return nil end
  local sky = (tpal and tpal[0]) or gpal[0] or { 0, 0, 0 }
  local treeImg = ImageWriter.blank(u.intro2W, u.intro2H, sky[1], sky[2], sky[3], 1)
  local midImg = ImageWriter.blank(u.intro2W, u.intro2H, 0, 0, 0, 0)
  if trees and tmap and tpal then
    Cinema.paintTilemap(treeImg, trees, tmap, { [0] = tpal }, 32, 64, 0, 0, false)
    Cinema.paintTilemap(midImg, trees, tmap, { [0] = tpal }, 32, 64, 0, 256, true)
  end
  local grassImg = ImageWriter.blank(u.intro2W, u.intro2H, 0, 0, 0, 0)
  Cinema.paintTilemap(grassImg, grass, gmap, { [0] = gpal }, 32, 32, 0, 0, true)
  return treeImg, grassImg, midImg
end

function Cinema.renderIntro2(data)
  local treeImg, grassImg, midImg = Cinema.renderIntro2Layers(data)
  if not treeImg then return nil end
  local function over(front)
    if not front then return end
    local w, h = front:getDimensions()
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = front:getPixel(x, y)
        if a > 0 then treeImg:setPixel(x, y, r, g, b, a) end
      end
    end
  end
  over(midImg)
  over(grassImg)
  return treeImg
end

function Cinema.renderTitle(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.groudonGfx, u.groudonGfxBytes)
  local gmap = lz(data, u.groudonMap, u.groudonMapBytes)
  local lmap = lz(data, u.lavaMap, u.lavaMapBytes)
  local dark = readPal(data, u.groudonPal, 16)
  local glow = readPal(data, u.groudonPal + 32, 16)
  if not (gfx and gmap and lmap and dark) then return nil end
  -- title_screen.c LoadPalette(..., 0xE0): pal 14 is groudon_dark, pal 15
  -- is groudon_glow (lava). 0xEF (pal 14 color 15) is the pulsing marking.
  -- Color 0 on both maps is transparent; paint Groudon over lava so the
  -- body is not buried without EVA/EVB blend.
  local mark = (glow and glow[9]) or dark[15]
  local body = {}
  for i = 0, 15 do body[i] = dark[i] end
  body[15] = mark
  local pals = { [0] = dark, [14] = body, [15] = glow or dark }
  local bg = dark[0]
  local image = ImageWriter.blank(Cinema.SCREEN_W, Cinema.SCREEN_H,
    bg[1], bg[2], bg[3], 1)
  Cinema.paintTilemap(image, gfx, lmap, pals, 32, 32, 0, 0, true)
  Cinema.paintTilemap(image, gfx, gmap, pals, 32, 20, 0, 0, true)
  local logoPal = {}
  for c = 0, math.floor(u.logoPalBytes / 2) - 1 do
    logoPal[c] = { bgr555(GbaBin.u16(data, u.logoPal + c * 2)) }
  end
  local logoTiles = lz(data, u.logoGfx, u.logoGfxBytes)
  local logoMap = lz(data, u.logoMap, u.logoMapBytes)
  if logoTiles and logoMap then
    Cinema.paintAffine8(image, logoTiles, logoMap, logoPal, u.logoBg2X, u.logoBg2Y)
  end
  local version = lz(data, u.versionGfx, u.versionGfxBytes)
  if version then
    -- Two 64x32 8bpp OBJ. CreateSprite x/y are centers; y goal is 66.
    blitObj8(image, version, logoPal, 0, 8, 4, 98 - 32, 66 - 16)
    blitObj8(image, version, logoPal, 32, 8, 4, 162 - 32, 66 - 16)
  end
  local press = lz(data, u.pressStartGfx, u.pressStartGfxBytes)
  if press then
    -- CreateCopyrightBanner(120, 148): five 32x8 OBJ, x starts at 56.
    local x = 120 - 64
    for i = 0, 4 do
      blitObj4(image, press, logoPal, 12 + i * 4, 4, 1, x + i * 32 - 16, 148 - 4)
    end
  end
  return image
end

function Cinema.renderPressStart(data)
  local u = Cinema.RUBY_US
  local press = lz(data, u.pressStartGfx, u.pressStartGfxBytes)
  local logoPal = {}
  for c = 0, math.floor(u.logoPalBytes / 2) - 1 do
    logoPal[c] = { bgr555(GbaBin.u16(data, u.logoPal + c * 2)) }
  end
  if not press then return nil end
  local image = ImageWriter.blank(Cinema.SCREEN_W, Cinema.SCREEN_H, 0, 0, 0, 0)
  -- CreatePressStartBanner(120, 108): three 32x8 OBJ, x starts at 88.
  local x = 120 - 32
  for i = 0, 2 do
    blitObj4(image, press, logoPal, i * 4, 4, 1, x + i * 32 - 16, 108 - 4)
  end
  return image
end

local function save(image, path)
  if not image then return nil end
  local ok = pcall(ImageWriter.save, image, path)
  if not ok then return nil end
  return path
end

-- gCableCarPylonHookTilemapEntries. Palette 3, tiles 0-9.
Cinema.PYLON_HOOK = {
  0x3000, 0x3001, 0x3002, 0x3003, 0x3004,
  0x3005, 0x3006, 0x3007, 0x3008, 0x3009,
}

local function newScreen()
  local t = {}
  for i = 1, 1024 do t[i] = 0 end
  return t
end

-- CableCarUtil_CopyWrapped: dest is a 32x32 screenblock.
local function copyWrapped(dest, src, srcOff, left, top, width, height)
  if not src then return end
  local si = srcOff or 0
  local y = top
  for _ = 1, height do
    local x = left
    for _ = 1, width do
      dest[(y % 32) * 32 + (x % 32) + 1] = GbaBin.u16(src, si * 2)
      si = si + 1
      x = x + 1
    end
    y = y + 1
  end
end

local function packScreen(cells)
  local unpack = table.unpack or unpack
  local parts, buf, n = {}, {}, 0
  for i = 1, 1024 do
    local e = cells[i] or 0
    buf[#buf + 1] = e % 256
    buf[#buf + 1] = math.floor(e / 256) % 256
    if #buf >= 256 then
      n = n + 1
      parts[n] = string.char(unpack(buf))
      buf = {}
    end
  end
  if #buf > 0 then
    n = n + 1
    parts[n] = string.char(unpack(buf))
  end
  return table.concat(parts)
end

local function readBgPals(data, off)
  local pals = {}
  for i = 0, 3 do
    pals[i] = readPal(data, off + i * 32, 16)
    if not pals[i] then return nil end
  end
  return pals
end

local function paintScreen(tiles, pals, cells, skip0, fill)
  local image = ImageWriter.blank(256, 256,
    fill and fill[1] or 0, fill and fill[2] or 0,
    fill and fill[3] or 0, fill and 1 or 0)
  return Cinema.paintTilemap(image, tiles, packScreen(cells), pals,
    32, 32, 0, 0, skip0)
end

function Cinema.renderCableCar(data)
  local u = Cinema.RUBY_US
  local tiles = lz(data, u.cableCarBgGfx, u.cableCarBgGfxBytes)
  local pals = readBgPals(data, u.cableCarBgPal)
  local mountain = lz(data, u.cableCarMountainMap, u.cableCarMountainMapBytes)
  local trees = lz(data, u.cableCarTreeMap, u.cableCarTreeMapBytes)
  local chimney = lz(data, u.cableCarChimneyMap, u.cableCarChimneyMapBytes)
  local stem = lz(data, u.cableCarPylonStemMap, u.cableCarPylonStemMapBytes)
  local carTiles = lz(data, u.cableCarGfx, u.cableCarGfxBytes)
  local doorTiles = lz(data, u.cableCarDoorGfx, u.cableCarDoorGfxBytes)
  local cordTiles = lz(data, u.cableCarCordGfx, u.cableCarCordGfxBytes)
  local carPal = readPal(data, u.cableCarPal, 16)
  if not (tiles and pals and mountain and trees and chimney and stem) then
    return nil
  end
  local mt = newScreen()
  copyWrapped(mt, mountain, 0, 0, 0, 30, 20)
  local tr = newScreen()
  copyWrapped(tr, trees, 0, 0, 17, 32, 15)
  local py = newScreen()
  local hook = ""
  for i = 1, #Cinema.PYLON_HOOK do
    local e = Cinema.PYLON_HOOK[i]
    hook = hook .. string.char(e % 256, math.floor(e / 256) % 256)
  end
  copyWrapped(py, hook, 0, 0, 0, 5, 2)
  copyWrapped(py, stem, 0, 0, 2, 2, 20)
  local ch = newScreen()
  -- cable_car.c case 6: five 12x3 chimney strips onto BG0.
  copyWrapped(ch, chimney, 0x48, 0, 14, 12, 3)
  copyWrapped(ch, chimney, 0x6C, 12, 17, 12, 3)
  copyWrapped(ch, chimney, 0x90, 24, 20, 12, 3)
  copyWrapped(ch, chimney, 0x00, 0, 17, 12, 3)
  copyWrapped(ch, chimney, 0x24, 0, 20, 12, 3)
  copyWrapped(ch, chimney, 0x00, 12, 20, 12, 3)
  copyWrapped(ch, chimney, 0x24, 12, 23, 12, 3)
  copyWrapped(ch, chimney, 0x00, 24, 23, 12, 3)
  local out = {
    mountain = paintScreen(tiles, pals, mt, false, pals[2] and pals[2][1]),
    trees = paintScreen(tiles, pals, tr, true),
    pylon = paintScreen(tiles, pals, py, true),
    chimney = paintScreen(tiles, pals, ch, true),
  }
  if carTiles and carPal then
    local car = ImageWriter.blank(64, 64, 0, 0, 0, 0)
    blitObj4(car, carTiles, carPal, 0, 8, 8, 0, 0)
    out.car = car
  end
  if doorTiles and carPal then
    local door = ImageWriter.blank(16, 8, 0, 0, 0, 0)
    blitObj4(door, doorTiles, carPal, 0, 2, 1, 0, 0)
    out.door = door
  end
  if cordTiles and carPal then
    local cord = ImageWriter.blank(16, 16, 0, 0, 0, 0)
    blitObj4(cord, cordTiles, carPal, 0, 2, 2, 0, 0)
    out.cord = cord
  end
  return out
end

function Cinema.renderEggHatch(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.eggHatchPal, 16)
  local tiles = slice(data, u.eggHatchGfx, u.eggHatchGfxBytes)
  local shards = slice(data, u.eggShardGfx, u.eggShardGfxBytes)
  if not (pal and tiles) then return nil end
  local egg = ImageWriter.blank(128, 32, 0, 0, 0, 0)
  for i = 0, 3 do
    blitObj4(egg, tiles, pal, i * 16, 4, 4, i * 32, 0)
  end
  local shard
  if shards then
    shard = ImageWriter.blank(32, 8, 0, 0, 0, 0)
    blitObj4(shard, shards, pal, 0, 4, 1, 0, 0)
  end
  return { egg = egg, shard = shard }
end

function Cinema.renderHatchBg(data, mapOff)
  local u = Cinema.RUBY_US
  local gfx = slice(data, u.tradeGbaGfx, u.tradeGbaGfxBytes)
  local map = slice(data, mapOff or u.hatchBgMap, u.hatchBgMapBytes)
  if not (gfx and map) then return nil end
  local pals = { [0] = { [0] = { 0, 0, 0 } } }
  for i = 0, 4 do
    pals[i + 1] = readPal(data, u.tradeGbaPal + i * 32, 16)
    if not pals[i + 1] then return nil end
  end
  local image = ImageWriter.blank(256, 256, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, gfx, map, pals, 32, 32, 0, 0, true)
end

-- LoadPalette(gUnknown_0820C9F8, 0x10, 0xa0): 8bpp indices 16-95.
local function tradePal256(data)
  local pal = {}
  for i = 0, 15 do pal[i] = { 0, 0, 0 } end
  local u = Cinema.RUBY_US
  for i = 0, 4 do
    local slot = readPal(data, u.tradeGbaPal + i * 32, 16)
    if not slot then return nil end
    for c = 0, 15 do pal[16 + i * 16 + c] = slot[c] end
  end
  return pal
end

function Cinema.renderTradeCable(data)
  local u = Cinema.RUBY_US
  local gfx = slice(data, u.tradeGbaGfx, u.tradeGbaGfxBytes)
  local map = slice(data, u.tradeCableMap, u.tradeCableMapBytes)
  if not (gfx and map) then return nil end
  local pals = { [0] = { [0] = { 0, 0, 0 } } }
  for i = 0, 4 do
    pals[i + 1] = readPal(data, u.tradeGbaPal + i * 32, 16)
    if not pals[i + 1] then return nil end
  end
  local image = ImageWriter.blank(256, 256, 0, 0, 0, 1)
  return Cinema.paintTilemap(image, gfx, map, pals, 32, 32, 0, 0, true)
end

function Cinema.renderTradeAffine(data)
  local pal = tradePal256(data)
  local gfx = slice(data, Cinema.RUBY_US.tradeAffineGfx,
    Cinema.RUBY_US.tradeAffineGfxBytes)
  local map = slice(data, Cinema.RUBY_US.tradeAffineMap,
    Cinema.RUBY_US.tradeAffineMapBytes)
  if not (pal and gfx and map) then return nil end
  local image = ImageWriter.blank(128, 128, 0, 0, 0, 0)
  return Cinema.paintAffine8(image, gfx, map, pal, 0, 0, 128, 16)
end

function Cinema.renderTradeSymbol(data)
  local pal = tradePal256(data)
  local gfx = slice(data, Cinema.RUBY_US.tradeSymbolGfx,
    Cinema.RUBY_US.tradeSymbolGfxBytes)
  local map = slice(data, Cinema.RUBY_US.tradeSymbolMap,
    Cinema.RUBY_US.tradeSymbolMapBytes)
  if not (pal and gfx and map) then return nil end
  local image = ImageWriter.blank(128, 128, 0, 0, 0, 0)
  return Cinema.paintAffine8(image, gfx, map, pal, 0, 0, 128, 16)
end

function Cinema.renderTradeBall(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.tradeBallPal, 16)
  local tiles = slice(data, u.tradeBallGfx, u.tradeBallGfxBytes)
  if not (pal and tiles) then return nil end
  local image = ImageWriter.blank(192, 16, 0, 0, 0, 0)
  for i = 0, 11 do
    blitObj4(image, tiles, pal, i * 4, 2, 2, i * 16, 0)
  end
  return image
end

function Cinema.renderTradeLinkObjs(data)
  local u = Cinema.RUBY_US
  local glowPal = readPal(data, u.tradeGlowPal, 16)
  local endPal = readPal(data, u.tradeCableEndPal, 16)
  local glow1 = slice(data, u.tradeGlow1Gfx, u.tradeGlow1GfxBytes)
  local glow2 = slice(data, u.tradeGlow2Gfx, u.tradeGlow2GfxBytes)
  local cord = slice(data, u.tradeCableEndGfx, u.tradeCableEndGfxBytes)
  local screen = slice(data, u.tradeGbaScreenGfx, u.tradeGbaScreenGfxBytes)
  if not (glowPal and endPal and glow1 and glow2 and cord and screen) then
    return nil
  end
  local g1 = ImageWriter.blank(32, 32, 0, 0, 0, 0)
  blitObj4(g1, glow1, glowPal, 0, 4, 4, 0, 0)
  local g2 = ImageWriter.blank(48, 32, 0, 0, 0, 0)
  blitObj4(g2, glow2, glowPal, 0, 2, 4, 0, 0)
  blitObj4(g2, glow2, glowPal, 8, 2, 4, 16, 0)
  blitObj4(g2, glow2, glowPal, 16, 2, 4, 32, 0)
  local endImg = ImageWriter.blank(16, 32, 0, 0, 0, 0)
  blitObj4(endImg, cord, endPal, 0, 2, 4, 0, 0)
  local scr = ImageWriter.blank(256, 32, 0, 0, 0, 0)
  for i = 0, 3 do
    blitObj4(scr, screen, endPal, i * 32, 8, 4, i * 64, 0)
  end
  return { glow1 = g1, glow2 = g2, cableEnd = endImg, gbaScreen = scr }
end

-- L1/T1 are 32x32 (OAM size 2); the rest are 64x64 (size 3). Color 0 is
-- transparent; the bars are indices 14-15 on pal 5.
function Cinema.renderRotatingGate(data, shape)
  local spec = Cinema.RUBY_US.rotatingGate[shape]
  if not spec then return nil end
  local gfx = slice(data, spec.off, spec.bytes)
  local pal = readPal(data, Cinema.RUBY_US.rotatingGatePal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(spec.tw * Cinema.TILE, spec.th * Cinema.TILE,
    0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, spec.tw, spec.th, 0, 0)
  return image
end

function Cinema.renderRotatingGates(data)
  local out = {}
  for shape = 0, 7 do
    out[shape] = Cinema.renderRotatingGate(data, shape)
    if not out[shape] then return nil end
  end
  return out
end

-- 8x8 pokéball glow (OAM size 0). Pal tag 0x1007.
function Cinema.renderPokeballGlow(data)
  local u = Cinema.RUBY_US
  local gfx = slice(data, u.pokeballGlowGfx, u.pokeballGlowGfxBytes)
  local pal = readPal(data, u.pokeballGlowPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(8, 8, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, 1, 1, 0, 0)
  return image
end

-- Big 64x16 + small 32x16 HoF screens (pal tag 0x1010).
function Cinema.renderHofMonitors(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.hofMonitorPal, 16)
  local bigGfx = slice(data, u.hofMonitorBigGfx, u.hofMonitorBigGfxBytes)
  local smallGfx = slice(data, u.hofMonitorSmallGfx, u.hofMonitorSmallGfxBytes)
  if not (pal and bigGfx and smallGfx) then return nil end
  local big = ImageWriter.blank(64, 16, 0, 0, 0, 0)
  blitObj4(big, bigGfx, pal, 0, 8, 2, 0, 0)
  local small = ImageWriter.blank(32, 16, 0, 0, 0, 0)
  blitObj4(small, smallGfx, pal, 0, 4, 2, 0, 0)
  return { big = big, small = small }
end

-- Affine 8bpp Hoenn map (BG2 512x512, unzoomed origin 0,0). Pal at 0x70.
function Cinema.renderRegionMap(data)
  local u = Cinema.RUBY_US
  if type(data) ~= "string"
      or #data < u.regionMapPal + u.regionMapPalCount * 2 then
    return nil
  end
  local gfx = lz(data, u.regionMapGfxLz, u.regionMapGfxBytes)
  local map = lz(data, u.regionMapMapLz, u.regionMapMapBytes)
  if not (gfx and map) then return nil end
  local pal = {}
  for i = 0, u.regionMapPalCount - 1 do
    pal[u.regionMapPalIndex + i] = { bgr555(GbaBin.u16(data,
      u.regionMapPal + i * 2)) }
  end
  local image = ImageWriter.blank(Cinema.SCREEN_W, Cinema.SCREEN_H, 0, 0, 0, 1)
  return Cinema.paintAffine8(image, gfx, map, pal, 0, 0,
    u.regionMapWrap, u.regionMapPitch)
end

-- Two 16x16 cursor frames (OAM size 1).
function Cinema.renderRegionMapCursor(data)
  local u = Cinema.RUBY_US
  local gfx = lz(data, u.regionMapCursorSmallLz, u.regionMapCursorSmallBytes)
  local pal = readPal(data, u.regionMapCursorPal, 16)
  if not (gfx and pal) then return nil end
  local image = ImageWriter.blank(32, 16, 0, 0, 0, 0)
  blitObj4(image, gfx, pal, 0, 2, 2, 0, 0)
  blitObj4(image, gfx, pal, 4, 2, 2, 16, 0)
  return image
end

function Cinema.renderRegionMapIcons(data)
  local u = Cinema.RUBY_US
  local bPal = readPal(data, u.regionMapBrendanPal, 16)
  local mPal = readPal(data, u.regionMapMayPal, 16)
  local bGfx = slice(data, u.regionMapBrendanGfx, u.regionMapIconBytes)
  local mGfx = slice(data, u.regionMapMayGfx, u.regionMapIconBytes)
  if not (bPal and mPal and bGfx and mGfx) then return nil end
  local brendan = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObj4(brendan, bGfx, bPal, 0, 2, 2, 0, 0)
  local may = ImageWriter.blank(16, 16, 0, 0, 0, 0)
  blitObj4(may, mGfx, mPal, 0, 2, 2, 0, 0)
  return { brendan = brendan, may = may }
end

-- Two 24x16 pokécenter screens side by side.
function Cinema.renderPokecenterMonitor(data)
  local u = Cinema.RUBY_US
  local pal = readPal(data, u.pokecenterMonPal, 16)
  local a = slice(data, u.pokecenterMon0Gfx, u.pokecenterMonGfxBytes)
  local b = slice(data, u.pokecenterMon1Gfx, u.pokecenterMonGfxBytes)
  if not (pal and a and b) then return nil end
  local image = ImageWriter.blank(48, 16, 0, 0, 0, 0)
  blitObj4(image, a, pal, 0, 3, 2, 0, 0)
  blitObj4(image, b, pal, 0, 3, 2, 24, 0)
  return image
end

function Cinema.extract(data)
  if type(data) ~= "string" or #data < 0x4139C8 then return {} end
  local out = {
    copyright = save(Cinema.renderCopyright(data),
      "assets/generated/title/copyright.png"),
    intro2 = save(Cinema.renderIntro2(data),
      "assets/generated/intro/intro2.png"),
    gamefreak = save(Cinema.renderGameFreak(data),
      "assets/generated/intro/gamefreak.png"),
    title = save(Cinema.renderTitle(data),
      "assets/generated/title/title_screen.png"),
    pressStart = save(Cinema.renderPressStart(data),
      "assets/generated/title/press_start.png"),
  }
  local layers = Cinema.renderIntro1Layers(data)
  if layers then
    for i = 1, 4 do
      out["intro1bg" .. (i - 1)] = save(layers[i],
        "assets/generated/intro/intro1_bg" .. (i - 1) .. ".png")
    end
  end
  local trees, grass, mid = Cinema.renderIntro2Layers(data)
  if trees then
    out.intro2trees = save(trees, "assets/generated/intro/intro2_trees.png")
  end
  if mid then
    out.intro2bg2 = save(mid, "assets/generated/intro/intro2_bg2.png")
  end
  if grass then
    out.intro2grass = save(grass, "assets/generated/intro/intro2_grass.png")
  end
  out.intro1drop = save(Cinema.renderIntro1Drop(data),
    "assets/generated/intro/intro1_drop.png")
  out.intro1splash = save(Cinema.renderIntro1Splash(data),
    "assets/generated/intro/intro1_splash.png")
  out.intro1eon = save(Cinema.renderIntro1Eon(data),
    "assets/generated/intro/intro1_eon.png")
  out.intro2treesobj = save(Cinema.renderIntro2TreeObj(data),
    "assets/generated/intro/intro2_treesobj.png")
  out.intro2brendan = save(Cinema.renderIntro2Brendan(data),
    "assets/generated/intro/intro2_brendan.png")
  out.intro2bike = save(Cinema.renderIntro2Bike(data),
    "assets/generated/intro/intro2_bike.png")
  out.intro2latios = save(Cinema.renderIntro2Latios(data),
    "assets/generated/intro/intro2_latios.png")
  out.intro3ball = save(Cinema.renderIntro3Ball(data),
    "assets/generated/intro/intro3_ball.png")
  out.intro3streaks = save(Cinema.renderIntro3Streaks(data),
    "assets/generated/intro/intro3_streaks.png")
  out.intro3brendan = save(Cinema.renderIntro3Brendan(data),
    "assets/generated/intro/intro3_brendan.png")
  out.intro3may = save(Cinema.renderIntro3May(data),
    "assets/generated/intro/intro3_may.png")
  out.intro3poke = save(Cinema.renderIntro3Poke(data),
    "assets/generated/intro/intro3_poke.png")
  local blast, spark = Cinema.renderIntro3Misc(data)
  out.intro3blast = save(blast, "assets/generated/intro/intro3_blast.png")
  out.intro3spark = save(spark, "assets/generated/intro/intro3_spark.png")
  local water, ember = Cinema.renderIntro3AttackGfx(data)
  out.intro3water = save(water, "assets/generated/intro/intro3_water.png")
  out.intro3ember = save(ember, "assets/generated/intro/intro3_ember.png")
  local car = Cinema.renderCableCar(data)
  if car then
    out.cableCarMountain = save(car.mountain,
      "assets/generated/cable_car/mountain.png")
    out.cableCarTrees = save(car.trees,
      "assets/generated/cable_car/trees.png")
    out.cableCarPylon = save(car.pylon,
      "assets/generated/cable_car/pylon.png")
    out.cableCarChimney = save(car.chimney,
      "assets/generated/cable_car/chimney.png")
    out.cableCarCar = save(car.car, "assets/generated/cable_car/car.png")
    out.cableCarDoor = save(car.door, "assets/generated/cable_car/door.png")
    out.cableCarCord = save(car.cord, "assets/generated/cable_car/cord.png")
  end
  local hatch = Cinema.renderEggHatch(data)
  if hatch then
    out.eggHatch = save(hatch.egg, "assets/generated/egg_hatch/egg.png")
    out.eggShard = save(hatch.shard, "assets/generated/egg_hatch/shard.png")
  end
  out.hatchBg = save(Cinema.renderHatchBg(data),
    "assets/generated/egg_hatch/hatch_bg.png")
  out.tradeGba = save(Cinema.renderHatchBg(data, Cinema.RUBY_US.tradeGbaMap),
    "assets/generated/trade/gba.png")
  out.tradeCable = save(Cinema.renderTradeCable(data),
    "assets/generated/trade/cable.png")
  out.tradeAffine = save(Cinema.renderTradeAffine(data),
    "assets/generated/trade/affine.png")
  out.tradeSymbol = save(Cinema.renderTradeSymbol(data),
    "assets/generated/trade/symbol.png")
  out.tradeBall = save(Cinema.renderTradeBall(data),
    "assets/generated/trade/ball.png")
  local link = Cinema.renderTradeLinkObjs(data)
  if link then
    out.tradeGlow1 = save(link.glow1, "assets/generated/trade/glow1.png")
    out.tradeGlow2 = save(link.glow2, "assets/generated/trade/glow2.png")
    out.tradeCableEnd = save(link.cableEnd,
      "assets/generated/trade/cable_end.png")
    out.tradeGbaScreen = save(link.gbaScreen,
      "assets/generated/trade/gba_screen.png")
  end
  local gates = Cinema.renderRotatingGates(data)
  if gates then
    for shape = 0, 7 do
      out["rotatingGate" .. shape] = save(gates[shape],
        "assets/generated/rotating_gates/" .. shape .. ".png")
    end
  end
  out.pokeballGlow = save(Cinema.renderPokeballGlow(data),
    "assets/generated/field/pokeball_glow.png")
  local hofMon = Cinema.renderHofMonitors(data)
  if hofMon then
    out.hofMonitorBig = save(hofMon.big,
      "assets/generated/field/hof_monitor_big.png")
    out.hofMonitorSmall = save(hofMon.small,
      "assets/generated/field/hof_monitor_small.png")
  end
  out.pokecenterMonitor = save(Cinema.renderPokecenterMonitor(data),
    "assets/generated/field/pokecenter_monitor.png")
  out.regionMap = save(Cinema.renderRegionMap(data),
    "assets/generated/pokenav/region_map.png")
  out.regionMapCursor = save(Cinema.renderRegionMapCursor(data),
    "assets/generated/pokenav/cursor.png")
  local icons = Cinema.renderRegionMapIcons(data)
  if icons then
    out.regionMapBrendan = save(icons.brendan,
      "assets/generated/pokenav/brendan.png")
    out.regionMapMay = save(icons.may,
      "assets/generated/pokenav/may.png")
  end
  return out
end

return Cinema
