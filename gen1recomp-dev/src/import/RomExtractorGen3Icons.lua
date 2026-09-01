-- Party menu icons: the little 32x32 sprites that stand in for a Pokemon
-- everywhere it is listed rather than fought (party screen, Pokedex list,
-- PC boxes, the daycare).
--
-- Unlike the battle sprites these are NOT compressed -- pokemon.h includes
-- them as plain `icon.4bpp` -- so there is nothing to decode, only tiles to
-- lay out. Each entry is 32x64: two 32x32 frames that the ROM alternates to
-- make the icon bob (`sMonIconAnims` in pokemon_icon.c).
--
-- All 440 land in one atlas rather than 440 files. The battle extractor
-- writes a PNG per species because it only ships the handful you can
-- actually meet; icons are needed for anything the player can see in a
-- list, which in practice is every species, and 440 separate textures
-- would cost a bind each.
local GbaBin = require("src.import.GbaBin")
local ImageWriter = require("src.import.ImageWriter")

local Icons = {}

Icons.ROM_BASE = 0x08000000
Icons.ATLAS_PATH = "assets/generated/icons/mon_icons.png"

-- SPECIES_NONE .. SPECIES_UNOWN_QMARK, which includes EGG at 412 and the
-- 27 Unown letters above it.
Icons.COUNT = 440
Icons.CELL_W = 32
Icons.CELL_H = 64
Icons.FRAME_H = 32
Icons.COLUMNS = 20
Icons.ICON_BYTES = 1024 -- 32x64 at 4bpp
Icons.PALETTE_COUNT = 3

-- US Ruby 1.0. pokemon_icon.c declares gMonIconTable, then
-- gMonIconPaletteIndices, then gMonIconPaletteTable, and .rodata keeps that
-- order -- the indices sit exactly 440 pointers past the table.
--
-- Found structurally, not guessed: gMonIconTable[SPECIES_NONE] and
-- [SPECIES_BULBASAUR] are both gMonIcon_Bulbasaur, so the array opens with
-- the same pointer twice, and it is the only place in the cart where that
-- is followed by 440 valid pointers.
Icons.RUBY_US = {
  iconTable = 0x3BBD20,
  paletteIndices = 0x3BC400,
  paletteTable = 0x3BC5B8,
  palettes = 0xE966D8,
}

function Icons.isRomPtr(data, ptr)
  return ptr >= Icons.ROM_BASE and ptr < Icons.ROM_BASE + #data
end

function Icons.toOffset(ptr) return ptr - Icons.ROM_BASE end

local function bgr555(c)
  return (c % 32) * 8 / 255,
    (math.floor(c / 32) % 32) * 8 / 255,
    (math.floor(c / 1024) % 32) * 8 / 255
end

-- gMonIconPaletteTable is six {const u16 *data, u16 tag} entries whose data
-- pointers step by one 16-colour palette. Only the first three are real --
-- pokemon_icon.c says so outright -- but the stride is what proves the
-- offset is right, so all six are checked.
function Icons.validate(data)
  local u = Icons.RUBY_US
  if type(data) ~= "string" then return false end
  if u.paletteIndices + Icons.COUNT > #data then return false end
  if GbaBin.u32(data, u.iconTable) ~= GbaBin.u32(data, u.iconTable + 4) then
    return false
  end
  for i = 0, Icons.COUNT - 1 do
    if not Icons.isRomPtr(data, GbaBin.u32(data, u.iconTable + i * 4)) then
      return false
    end
    if GbaBin.u8(data, u.paletteIndices + i) >= Icons.PALETTE_COUNT then
      return false
    end
  end
  local first = GbaBin.u32(data, u.paletteTable)
  if Icons.toOffset(first) ~= u.palettes then return false end
  for i = 0, 5 do
    if GbaBin.u32(data, u.paletteTable + i * 8) ~= first + i * 32 then
      return false
    end
  end
  return true
end

function Icons.readPalettes(data)
  local pals = {}
  for p = 0, Icons.PALETTE_COUNT - 1 do
    local pal = {}
    for c = 0, 15 do
      pal[c] = { bgr555(GbaBin.u16(data, Icons.RUBY_US.palettes + p * 32 + c * 2)) }
    end
    pals[p] = pal
  end
  return pals
end

-- 4bpp, tiles in reading order across a 4-tile-wide cell. Index 0 is the
-- transparency key, as it is for every OBJ.
local function blitIcon(image, px, py, data, off, pal)
  local tilesWide = Icons.CELL_W / 8
  local tiles = Icons.ICON_BYTES / 32
  for t = 0, tiles - 1 do
    local tx = (t % tilesWide) * 8
    local ty = math.floor(t / tilesWide) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = GbaBin.u8(data, off + t * 32 + y * 4 + math.floor(x / 2))
        local ci = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        if ci ~= 0 then
          local col = pal[ci] or { 0, 0, 0 }
          image:setPixel(px + tx + x, py + ty + y, col[1], col[2], col[3], 1)
        end
      end
    end
  end
end

function Icons.render(data)
  if not Icons.validate(data) then return nil end
  local u = Icons.RUBY_US
  local pals = Icons.readPalettes(data)
  local rows = math.ceil(Icons.COUNT / Icons.COLUMNS)
  local image = ImageWriter.blank(Icons.COLUMNS * Icons.CELL_W,
    rows * Icons.CELL_H, 0, 0, 0, 0)
  for species = 0, Icons.COUNT - 1 do
    local ptr = GbaBin.u32(data, u.iconTable + species * 4)
    local off = Icons.toOffset(ptr)
    if off + Icons.ICON_BYTES <= #data then
      local pal = pals[GbaBin.u8(data, u.paletteIndices + species)] or pals[0]
      blitIcon(image, (species % Icons.COLUMNS) * Icons.CELL_W,
        math.floor(species / Icons.COLUMNS) * Icons.CELL_H, data, off, pal)
    end
  end
  return image
end

function Icons.extract(data)
  local image = Icons.render(data)
  if not image then return nil end
  ImageWriter.save(image, Icons.ATLAS_PATH)
  return {
    atlas = Icons.ATLAS_PATH,
    count = Icons.COUNT,
    columns = Icons.COLUMNS,
    cellW = Icons.CELL_W,
    cellH = Icons.CELL_H,
    frameH = Icons.FRAME_H,
  }
end

return Icons
