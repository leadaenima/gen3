-- Ruby Pokédex tables: gPokedexEntries plus the species↔dex maps.
-- Flavor text and category names are GBA charset; Nintendo graphics stay
-- out of git.  US Ruby 1.0 offsets are the validated cart locations;
-- find* still scans so a fixture ROM can host the same layout.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local GbaText = require("src.import.GbaText")
local ImageWriter = require("src.import.ImageWriter")

local Dex = {}

Dex.ENTRY_SIZE = 0x24
Dex.NATIONAL_COUNT = 386
Dex.ENTRY_COUNT = Dex.NATIONAL_COUNT + 1 -- dummy at national 0
Dex.SPECIES_MAP_COUNT = 411 -- species 1..411, indexed as species-1
Dex.SPECIES_COUNT = 412 -- NONE .. Chimecho (footprint table length)
Dex.HOENN_BULBASAUR = 203
Dex.HOENN_TREECKO = 1
Dex.HOENN_TORCHIC = 4
Dex.NATIONAL_TREECKO = 252
Dex.NATIONAL_TORCHIC = 255
Dex.SPECIES_TREECKO = 277
Dex.SPECIES_TORCHIC = 280
Dex.FOOTPRINT_BYTES = 32
Dex.FOOTPRINT_PX = 16
Dex.FOOTPRINT_COLS = 20
Dex.ENTRY_W = 240
Dex.ENTRY_H = 160
Dex.ENTRY_PATH = "assets/generated/pokedex/entry.png"
Dex.SIZE_PATH = "assets/generated/pokedex/size.png"
Dex.CRY_PATH = "assets/generated/pokedex/cry.png"
Dex.SELECT_BAR_PATH = "assets/generated/pokedex/select_bar.png"
Dex.MAIN_PATH = "assets/generated/pokedex/main.png"
Dex.SELECT_BAR_SUB_PATH = "assets/generated/pokedex/select_bar_sub.png"
Dex.MAIN_NATIONAL_PATH = "assets/generated/pokedex/main_national.png"
Dex.START_MENU_PATH = "assets/generated/pokedex/start_menu.png"
Dex.START_MENU_SEARCH_PATH = "assets/generated/pokedex/start_menu_search.png"
Dex.SEARCH_PATH = "assets/generated/pokedex/search.png"
Dex.START_MENU_H = 96
-- The select bar is a 32x3 tile strip drawn over the bottom of the
-- list screen, not a whole background.
Dex.SELECT_BAR_H = 24
Dex.INTERFACE_PATH = "assets/generated/pokedex/interface.png"
-- gPokedexMenu2_Gfx, the list screen's furniture: the scroll arrows, the
-- START/SEARCH and SELECT/MENU labels, SEEN and OWN, and the digits the
-- counters are built from. A sprite sheet, so its tiles run eight across
-- rather than across the screen.
Dex.INTERFACE_COLS = 8
Dex.INTERFACE_W = 64
-- Measured from the sheet: each band is where one label lives.
-- {y, height} into the interface sheet, plus an optional width.
-- CreateInterfaceSprites: START/MENU/SELECT/SEARCH are 64x32 OAM frames
-- (16px of art + 16px empty) at the bottom-left prompts; SEEN/OWN are the
-- same size on the LEFT panel. Digits are separate 8x16 sprites.
Dex.INTERFACE_BANDS = {
  arrows = { 0, 32 },
  start = { 32, 16 },
  search = { 64, 16 },
  select = { 96, 16 },
  menu = { 128, 16 },
  seen = { 160, 16, 64 },
  own = { 192, 16, 64 },
  digits = { 224, 24 },
}
Dex.FOOTPRINTS_PATH = "assets/generated/pokedex/footprints.png"
-- pokedex.c sub_80C0DC0(14, 0x3FC): 2x2 tiles at screenblock entry 0x119.
Dex.FOOTPRINT_TILE_X = 25
Dex.FOOTPRINT_TILE_Y = 8

-- US Ruby 1.0.  pokemon_1.c lays the three u16 maps back to back
-- (Hoenn, National, Hoenn→National).  gPokedexEntries is the 0x24
-- struct array; dummy UNKNOWN sits at national 0, SEED Bulbasaur at 1.
-- Footprint table / menu gfx+layout found structurally (see validate*).
Dex.RUBY_US = {
  speciesToHoenn = 0x1FC1E0,
  speciesToNational = 0x1FC516,
  hoennToNational = 0x1FC84C,
  entries = 0x3B1858,
  footprintTable = 0x3B4EE4,
  menuGfx = 0xE86758,
  menuGfxBytes = 12288,
  menuPal = 0xE87AF4,
  menuPalColors = 48,
  detailLayout = 0xE96BD4,
  -- The other whole-screen layouts share gPokedexMenu_Gfx: pokedex.c
  -- loads that one tile set and then swaps only the tilemap. Each was
  -- located by decompressing candidates and matching the decomp's own
  -- .bin byte for byte, which is also how detailLayout above checks out.
  interfaceGfx = 0xE874C8,
  interfaceBytes = 0x1F00,
  sizeLayout = 0x39F988,
  cryLayout = 0x39F8A0,
  -- gUnknown_08E96738: the list screen's own background, which pokedex.c
  -- unpacks to the BG screen base right after gPokedexMenu_Gfx. Without it
  -- the list had no ROM art at all and was drawn on a flat rectangle.
  mainScreen = 0xE96738,
  -- The rest of the Pokedex, none of which was extracted. Every tilemap was
  -- confirmed by decompressing it and matching the decomp's own .bin or .png
  -- byte for byte; the palettes by matching their JASC .pal converted to
  -- BGR555. pokedex.c LoadPokedexBgPalette picks between menu / national /
  -- search for the same list background, which is why all three are here.
  listOverlay = 0xE9C6DC,
  startMenuMain = 0xE96888,
  startMenuSearch = 0xE96994,
  searchGfx = 0xE87DB0,
  searchLayout = 0xE96D2C,
  searchPal = 0x39F67C,
  searchPalColors = 96,
  nationalPal = 0x39F73C,
  nationalPalColors = 96,
  menu2Pal = 0xE87B54,
  selectBarMain = 0xE96ACC,
  selectBarSubmenu = 0xE96B58,
}

local SEED_NEEDLE = string.char(
  0xCD, 0xBF, 0xBF, 0xBE, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0x07, 0x00, 0x45, 0x00)

local function u16at(data, off)
  return GbaBin.u16(data, off)
end

function Dex.readText(data, ptr)
  if not GbaBin.isRomPtr(ptr, #data) then return "" end
  local off = GbaBin.romOffset(ptr)
  local blob = data:sub(off + 1, off + 200)
  local pages = GbaText.decodePages(blob, 200)
  if #pages < 1 then return GbaText.decodeText(blob, 200) end
  return table.concat(pages, "\n")
end

function Dex.parseEntry(data, offset)
  if type(data) ~= "string" or offset < 0
      or offset + Dex.ENTRY_SIZE > #data then
    return nil
  end
  local cat = GbaText.decodeName(data:sub(offset + 1, offset + 12))
  local p1 = GbaBin.u32(data, offset + 16)
  local p2 = GbaBin.u32(data, offset + 20)
  return {
    category = cat,
    height = u16at(data, offset + 12),
    weight = u16at(data, offset + 14),
    page1 = Dex.readText(data, p1),
    page2 = Dex.readText(data, p2),
    pokemonScale = u16at(data, offset + 0x1A),
    pokemonOffset = GbaBin.s16(data, offset + 0x1C),
    trainerScale = u16at(data, offset + 0x1E),
    trainerOffset = GbaBin.s16(data, offset + 0x20),
  }
end

function Dex.validEntries(data, offset)
  if type(data) ~= "string" or not offset then return false end
  if offset < 0 or offset + Dex.ENTRY_SIZE * 2 > #data then return false end
  local dummy = Dex.parseEntry(data, offset)
  local bulba = Dex.parseEntry(data, offset + Dex.ENTRY_SIZE)
  if not dummy or not bulba then return false end
  if dummy.category ~= "UNKNOWN" then return false end
  if dummy.height ~= 0 or dummy.weight ~= 0 then return false end
  if bulba.category ~= "SEED" then return false end
  if bulba.height ~= 7 or bulba.weight ~= 69 then return false end
  local torchic = Dex.parseEntry(data,
    offset + Dex.NATIONAL_TORCHIC * Dex.ENTRY_SIZE)
  if not torchic or torchic.category ~= "CHICK" then return false end
  if torchic.height ~= 4 or torchic.weight ~= 25 then return false end
  return true
end

function Dex.findEntries(data)
  if type(data) ~= "string" then return nil end
  local u = Dex.RUBY_US.entries
  if Dex.validEntries(data, u) then return u end
  local at = data:find(SEED_NEEDLE, 1, true)
  if not at then return nil end
  local start = at - 1 - Dex.ENTRY_SIZE
  if start >= 0 and Dex.validEntries(data, start) then return start end
  return nil
end

function Dex.validSpeciesMaps(data, hoennOff, nationalOff, orderOff)
  if type(data) ~= "string" then return false end
  local last = Dex.SPECIES_MAP_COUNT * 2
  if not hoennOff or not nationalOff or not orderOff then return false end
  if hoennOff < 0 or nationalOff < 0 or orderOff < 0 then return false end
  if hoennOff + last > #data or nationalOff + last > #data
      or orderOff + last > #data then
    return false
  end
  if u16at(data, hoennOff) ~= Dex.HOENN_BULBASAUR then return false end
  local treecko = (Dex.SPECIES_TREECKO - 1) * 2
  local torchic = (Dex.SPECIES_TORCHIC - 1) * 2
  if u16at(data, hoennOff + treecko) ~= Dex.HOENN_TREECKO then return false end
  if u16at(data, hoennOff + torchic) ~= Dex.HOENN_TORCHIC then return false end
  if u16at(data, nationalOff) ~= 1 then return false end
  if u16at(data, nationalOff + treecko) ~= Dex.NATIONAL_TREECKO then
    return false
  end
  if u16at(data, nationalOff + torchic) ~= Dex.NATIONAL_TORCHIC then
    return false
  end
  if u16at(data, orderOff) ~= Dex.NATIONAL_TREECKO then return false end
  if u16at(data, orderOff + 6) ~= Dex.NATIONAL_TORCHIC then return false end
  return true
end

function Dex.findSpeciesMaps(data)
  if type(data) ~= "string" then return nil, nil, nil end
  local u = Dex.RUBY_US
  if Dex.validSpeciesMaps(data, u.speciesToHoenn, u.speciesToNational,
      u.hoennToNational) then
    return u.speciesToHoenn, u.speciesToNational, u.hoennToNational
  end
  local needle = string.char(0xFC, 0x00, 0xFD, 0x00, 0xFE, 0x00, 0xFF, 0x00,
    0x00, 0x01)
  local search = 1
  while true do
    local at = data:find(needle, search, true)
    if not at then return nil, nil, nil end
    local orderOff = at - 1
    local nationalOff = orderOff - Dex.SPECIES_MAP_COUNT * 2
    local hoennOff = nationalOff - Dex.SPECIES_MAP_COUNT * 2
    if Dex.validSpeciesMaps(data, hoennOff, nationalOff, orderOff) then
      return hoennOff, nationalOff, orderOff
    end
    search = at + 1
  end
end

function Dex.parseEntries(data, offset)
  offset = offset or Dex.findEntries(data)
  if not offset then return nil end
  local byNational = {}
  for n = 0, Dex.NATIONAL_COUNT do
    local row = Dex.parseEntry(data, offset + n * Dex.ENTRY_SIZE)
    if row then byNational[n] = row end
  end
  return { offset = offset, byNational = byNational }
end

function Dex.parseSpeciesMaps(data, hoennOff, nationalOff, orderOff)
  if not hoennOff then
    hoennOff, nationalOff, orderOff = Dex.findSpeciesMaps(data)
  end
  if not hoennOff then return nil end
  local hoenn, national, order = {}, {}, {}
  for i = 0, Dex.SPECIES_MAP_COUNT - 1 do
    local species = i + 1
    hoenn[species] = u16at(data, hoennOff + i * 2)
    national[species] = u16at(data, nationalOff + i * 2)
    order[species] = u16at(data, orderOff + i * 2)
  end
  return {
    hoennOff = hoennOff,
    nationalOff = nationalOff,
    orderOff = orderOff,
    hoenn = hoenn,
    national = national,
    hoennToNational = order,
  }
end

function Dex.attach(byIndex, maps, entries)
  if type(byIndex) ~= "table" then return nil end
  if maps then
    for species, n in pairs(maps.hoenn or {}) do
      local row = byIndex[species]
      if row then row.hoennDex = n end
    end
    for species, n in pairs(maps.national or {}) do
      local row = byIndex[species]
      if row then row.nationalDex = n end
    end
  end
  local byNational = entries and entries.byNational
  if byNational and maps and maps.national then
    for species, nat in pairs(maps.national) do
      local row = byIndex[species]
      local ent = byNational[nat]
      if row and ent then
        row.category = ent.category
        row.height = ent.height
        row.weight = ent.weight
        row.dexPage1 = ent.page1
        row.dexPage2 = ent.page2
        row.pokemonScale = ent.pokemonScale
        row.pokemonOffset = ent.pokemonOffset
        row.trainerScale = ent.trainerScale
        row.trainerOffset = ent.trainerOffset
      end
    end
  end
  return byIndex
end

function Dex.apply(data, byIndex)
  if type(byIndex) ~= "table" then return nil end
  local maps = Dex.parseSpeciesMaps(data)
  local entries = Dex.parseEntries(data)
  if not maps and not entries then return nil end
  Dex.attach(byIndex, maps, entries)
  return {
    maps = maps,
    entries = entries,
  }
end

local function isRomPtr(data, ptr)
  return type(data) == "string" and GbaBin.isRomPtr(ptr, #data)
end

function Dex.validFootprintTable(data, offset)
  if type(data) ~= "string" or not offset then return false end
  if offset < 0 or offset + Dex.SPECIES_COUNT * 4 > #data then return false end
  local a = GbaBin.u32(data, offset)
  local b = GbaBin.u32(data, offset + 4)
  if a ~= b or not isRomPtr(data, a) then return false end
  local torch = GbaBin.u32(data, offset + Dex.SPECIES_TORCHIC * 4)
  if not isRomPtr(data, torch) then return false end
  local o = GbaBin.romOffset(torch)
  if o + Dex.FOOTPRINT_BYTES > #data then return false end
  -- Torchic's print is non-empty 1bpp (not an LZ header).
  if data:byte(o + 1) == 0x10 then return false end
  local nonzero = 0
  for i = 0, Dex.FOOTPRINT_BYTES - 1 do
    if data:byte(o + 1 + i) ~= 0 then nonzero = nonzero + 1 end
  end
  return nonzero >= 8
end

function Dex.findFootprintTable(data)
  if type(data) ~= "string" then return nil end
  local u = Dex.RUBY_US.footprintTable
  if Dex.validFootprintTable(data, u) then return u end
  for off = 0, #data - Dex.SPECIES_COUNT * 4, 4 do
    if Dex.validFootprintTable(data, off) then return off end
  end
  return nil
end

function Dex.validMenuChrome(data, gfxOff, palOff, layoutOff)
  if type(data) ~= "string" then return false end
  if not (gfxOff and palOff and layoutOff) then return false end
  local gfx = GbaLz77.decompress(data, gfxOff)
  local layout = GbaLz77.decompress(data, layoutOff)
  if not (gfx and layout) then return false end
  if #gfx < Dex.RUBY_US.menuGfxBytes then return false end
  if #layout ~= 1280 then return false end
  -- menu1.pal colour 0 is the olive key (JASC 123,131,0 → 0x020F).
  if GbaBin.u16(data, palOff) ~= 0x020F then return false end
  if GbaBin.u16(data, palOff + 2) ~= 0x7FFF then return false end
  return true
end

function Dex.findMenuChrome(data)
  if type(data) ~= "string" then return nil end
  local u = Dex.RUBY_US
  if Dex.validMenuChrome(data, u.menuGfx, u.menuPal, u.detailLayout) then
    return u.menuGfx, u.menuPal, u.detailLayout
  end
  return nil
end

local function bgr555(c)
  return (c % 32) * 8 / 255,
    (math.floor(c / 32) % 32) * 8 / 255,
    (math.floor(c / 1024) % 32) * 8 / 255
end

local function tileColorIndex(tiles, tid, px, py)
  local base = tid * 32
  local row = tiles:byte(base + py * 4 + math.floor(px / 2) + 1) or 0
  if px % 2 == 0 then return row % 16 end
  return math.floor(row / 16)
end

function Dex.renderEntryChrome(data, gfxOff, palOff, layoutOff)
  gfxOff = gfxOff or Dex.RUBY_US.menuGfx
  palOff = palOff or Dex.RUBY_US.menuPal
  layoutOff = layoutOff or Dex.RUBY_US.detailLayout
  if not Dex.validMenuChrome(data, gfxOff, palOff, layoutOff) then
    return nil, "pokedex menu chrome not found"
  end
  local gfx = assert(GbaLz77.decompress(data, gfxOff))
  local layout = assert(GbaLz77.decompress(data, layoutOff))
  local banks = math.floor(Dex.RUBY_US.menuPalColors / 16)
  local pals = {}
  for bank = 0, banks - 1 do
    pals[bank] = {}
    for c = 0, 15 do
      local r, g, b = bgr555(GbaBin.u16(data, palOff + (bank * 16 + c) * 2))
      pals[bank][c] = { r, g, b }
    end
  end
  local image = ImageWriter.blank(Dex.ENTRY_W, Dex.ENTRY_H, 0, 0, 0, 1)
  local rows = Dex.ENTRY_H / 8
  local cols = Dex.ENTRY_W / 8
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local e = GbaBin.u16(layout, (row * 32 + col) * 2)
      local tid = e % 1024
      local hflip = math.floor(e / 1024) % 2 == 1
      local vflip = math.floor(e / 2048) % 2 == 1
      local pi = math.floor(e / 4096) % 16
      local pal = pals[pi % banks] or pals[0]
      for ty = 0, 7 do
        for tx = 0, 7 do
          local sx = hflip and (7 - tx) or tx
          local sy = vflip and (7 - ty) or ty
          local ci = tileColorIndex(gfx, tid, sx, sy)
          local colr = pal[ci] or { 0, 0, 0 }
          image:setPixel(col * 8 + tx, row * 8 + ty,
            colr[1], colr[2], colr[3], 1)
        end
      end
    end
  end
  return image
end

-- A tilemap is 2 bytes per tile; a full screen is 32x20 and the select bar is
-- the bottom 32x3 strip drawn over it.
function Dex.tilemapSize(data, off)
  local map = GbaLz77.decompress(data, off)
  return map and #map or nil
end

-- renderEntryChrome with the height left open, so the same code draws a whole
-- background or the short strip the select bar occupies.
function Dex.renderChrome(data, gfxOff, palOff, layoutOff, height, colors)
  height = height or Dex.ENTRY_H
  local gfx = GbaLz77.decompress(data, gfxOff)
  local layout = GbaLz77.decompress(data, layoutOff)
  if not (gfx and layout) then return nil, "chrome not found" end
  local rows = height / 8
  local cols = Dex.ENTRY_W / 8
  if #layout < rows * cols * 2 then return nil, "tilemap too small" end
  local banks = math.floor((colors or Dex.RUBY_US.menuPalColors) / 16)
  local pals = {}
  for bank = 0, banks - 1 do
    pals[bank] = {}
    for c = 0, 15 do
      local r, g, b = bgr555(GbaBin.u16(data, palOff + (bank * 16 + c) * 2))
      pals[bank][c] = { r, g, b }
    end
  end
  local image = ImageWriter.blank(Dex.ENTRY_W, height, 0, 0, 0, 1)
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local e = GbaBin.u16(layout, (row * 32 + col) * 2)
      local tid = e % 1024
      local hflip = math.floor(e / 1024) % 2 == 1
      local vflip = math.floor(e / 2048) % 2 == 1
      local pi = math.floor(e / 4096) % 16
      local pal = pals[pi % banks] or pals[0]
      for ty = 0, 7 do
        for tx = 0, 7 do
          local sx = hflip and (7 - tx) or tx
          local sy = vflip and (7 - ty) or ty
          local ci = tileColorIndex(gfx, tid, sx, sy)
          local colr = pal[ci] or { 0, 0, 0 }
          -- Colour 0 is the olive key menu1.pal carries (0x020F): where the
          -- screen shows through, not a colour to paint. Painting it is what
          -- puts an olive slab across the lower half of the cry screen.
          local a = (ci == 0) and 0 or 1
          image:setPixel(col * 8 + tx, row * 8 + ty,
            colr[1], colr[2], colr[3], a)
        end
      end
    end
  end
  return image
end

function Dex.renderFootprints(data, tableOff)
  tableOff = tableOff or Dex.findFootprintTable(data)
  if not tableOff then return nil, "footprint table not found" end
  local cols = Dex.FOOTPRINT_COLS
  local rows = math.ceil(Dex.SPECIES_COUNT / cols)
  local cell = Dex.FOOTPRINT_PX
  local image = ImageWriter.blank(cols * cell, rows * cell, 0, 0, 0, 0)
  for species = 0, Dex.SPECIES_COUNT - 1 do
    local ptr = GbaBin.u32(data, tableOff + species * 4)
    if isRomPtr(data, ptr) then
      local o = GbaBin.romOffset(ptr)
      local raw = {}
      for i = 1, Dex.FOOTPRINT_BYTES do
        raw[i] = data:byte(o + i) or 0
      end
      local fp = ImageWriter.decode1bpp(raw, cell, cell, true)
      local col = species % cols
      local row = math.floor(species / cols)
      ImageWriter.blit(image, fp, col * cell, row * cell)
    end
  end
  return image, tableOff
end

-- A 4bpp sprite sheet laid out eight tiles across, which is how the sheet is
-- ordered; anything wider scrambles it.
function Dex.renderInterface(data, gfxOff, palOff)
  gfxOff = gfxOff or Dex.RUBY_US.interfaceGfx
  palOff = palOff or Dex.RUBY_US.menuPal
  local gfx = GbaLz77.decompress(data, gfxOff)
  if not gfx or #gfx ~= Dex.RUBY_US.interfaceBytes then
    return nil, "pokedex interface sheet not found"
  end
  local pal = {}
  for c = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(data, palOff + c * 2))
    pal[c] = { r, g, b }
  end
  local tiles = math.floor(#gfx / 32)
  local cols = Dex.INTERFACE_COLS
  local rows = math.ceil(tiles / cols)
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for tid = 0, tiles - 1 do
    local tx = (tid % cols) * 8
    local ty = math.floor(tid / cols) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local ci = tileColorIndex(gfx, tid, x, y)
        local colr = pal[ci] or { 0, 0, 0 }
        image:setPixel(tx + x, ty + y,
          colr[1], colr[2], colr[3], (ci == 0) and 0 or 1)
      end
    end
  end
  return image
end

function Dex.extractArt(data)
  local gfx, pal, layout = Dex.findMenuChrome(data)
  if not gfx then return nil, "pokedex menu chrome not found" end
  local entry = Dex.renderEntryChrome(data, gfx, pal, layout)
  if not entry then return nil, "could not render pokedex entry chrome" end
  ImageWriter.save(entry, Dex.ENTRY_PATH)
  local prints, tableOff = Dex.renderFootprints(data)
  if not prints then return nil, tableOff or "footprints failed" end
  ImageWriter.save(prints, Dex.FOOTPRINTS_PATH)
  -- The size and cry screens were drawing the entry chrome, which is simply
  -- the wrong background; each has its own tilemap over the same tiles.
  local size = Dex.renderChrome(data, gfx, pal, Dex.RUBY_US.sizeLayout)
  if size then ImageWriter.save(size, Dex.SIZE_PATH) end
  local cry = Dex.renderChrome(data, gfx, pal, Dex.RUBY_US.cryLayout)
  if cry then ImageWriter.save(cry, Dex.CRY_PATH) end
  local bar = Dex.renderChrome(data, gfx, pal,
    Dex.RUBY_US.selectBarMain, Dex.SELECT_BAR_H)
  if bar then ImageWriter.save(bar, Dex.SELECT_BAR_PATH) end
  -- pokedex.c: the info page loads LoadScreenSelectBarMain, but the area,
  -- cry and size screens all load LoadScreenSelectBarSubmenu instead. Only
  -- the main one was ever rendered, so the sub-screens had no bar at all.
  local barSub = Dex.renderChrome(data, gfx, pal,
    Dex.RUBY_US.selectBarSubmenu, Dex.SELECT_BAR_H)
  if barSub then ImageWriter.save(barSub, Dex.SELECT_BAR_SUB_PATH) end
  local iface = Dex.renderInterface(data, Dex.RUBY_US.interfaceGfx, pal)
  if iface then ImageWriter.save(iface, Dex.INTERFACE_PATH) end
  local main = Dex.renderChrome(data, gfx, pal, Dex.RUBY_US.mainScreen)
  if main then ImageWriter.save(main, Dex.MAIN_PATH) end
  -- Same background, National palette: LoadPokedexBgPalette swaps only this.
  local mainNat = Dex.renderChrome(data, gfx, Dex.RUBY_US.nationalPal,
    Dex.RUBY_US.mainScreen, nil, Dex.RUBY_US.nationalPalColors)
  if mainNat then ImageWriter.save(mainNat, Dex.MAIN_NATIONAL_PATH) end
  local startMenu = Dex.renderChrome(data, gfx, pal,
    Dex.RUBY_US.startMenuMain, Dex.START_MENU_H)
  if startMenu then ImageWriter.save(startMenu, Dex.START_MENU_PATH) end
  local startSearch = Dex.renderChrome(data, gfx, pal,
    Dex.RUBY_US.startMenuSearch, Dex.START_MENU_H)
  if startSearch then
    ImageWriter.save(startSearch, Dex.START_MENU_SEARCH_PATH)
  end
  -- The search screen has its own tile set and palette, not the menu ones.
  local search = Dex.renderChrome(data, Dex.RUBY_US.searchGfx,
    Dex.RUBY_US.searchPal, Dex.RUBY_US.searchLayout, nil,
    Dex.RUBY_US.searchPalColors)
  if search then ImageWriter.save(search, Dex.SEARCH_PATH) end
  return {
    entry = Dex.ENTRY_PATH,
    size = size and Dex.SIZE_PATH or nil,
    cry = cry and Dex.CRY_PATH or nil,
    selectBar = bar and Dex.SELECT_BAR_PATH or nil,
    selectBarSub = barSub and Dex.SELECT_BAR_SUB_PATH or nil,
    main = main and Dex.MAIN_PATH or nil,
    mainNational = mainNat and Dex.MAIN_NATIONAL_PATH or nil,
    startMenu = startMenu and Dex.START_MENU_PATH or nil,
    startMenuSearch = startSearch and Dex.START_MENU_SEARCH_PATH or nil,
    startMenuH = Dex.START_MENU_H,
    search = search and Dex.SEARCH_PATH or nil,
    selectBarH = Dex.SELECT_BAR_H,
    interface = iface and Dex.INTERFACE_PATH or nil,
    interfaceBands = Dex.INTERFACE_BANDS,
    interfaceW = Dex.INTERFACE_W,
    footprints = Dex.FOOTPRINTS_PATH,
    footprintTable = tableOff,
    footprintCols = Dex.FOOTPRINT_COLS,
    footprintPx = Dex.FOOTPRINT_PX,
    footprintTileX = Dex.FOOTPRINT_TILE_X,
    footprintTileY = Dex.FOOTPRINT_TILE_Y,
    speciesCount = Dex.SPECIES_COUNT,
    menuGfx = gfx,
    menuPal = pal,
    detailLayout = layout,
  }
end

return Dex
