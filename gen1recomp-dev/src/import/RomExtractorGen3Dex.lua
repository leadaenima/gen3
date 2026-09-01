-- Ruby Pokédex tables: gPokedexEntries plus the species↔dex maps.
-- Flavor text and category names are GBA charset; Nintendo graphics stay
-- out of git.  US Ruby 1.0 offsets are the validated cart locations;
-- find* still scans so a fixture ROM can host the same layout.
local GbaBin = require("src.import.GbaBin")
local GbaText = require("src.import.GbaText")

local Dex = {}

Dex.ENTRY_SIZE = 0x24
Dex.NATIONAL_COUNT = 386
Dex.ENTRY_COUNT = Dex.NATIONAL_COUNT + 1 -- dummy at national 0
Dex.SPECIES_MAP_COUNT = 411 -- species 1..411, indexed as species-1
Dex.HOENN_BULBASAUR = 203
Dex.HOENN_TREECKO = 1
Dex.HOENN_TORCHIC = 4
Dex.NATIONAL_TREECKO = 252
Dex.NATIONAL_TORCHIC = 255
Dex.SPECIES_TREECKO = 277
Dex.SPECIES_TORCHIC = 280

-- US Ruby 1.0.  pokemon_1.c lays the three u16 maps back to back
-- (Hoenn, National, Hoenn→National).  gPokedexEntries is the 0x24
-- struct array; dummy UNKNOWN sits at national 0, SEED Bulbasaur at 1.
Dex.RUBY_US = {
  speciesToHoenn = 0x1FC1E0,
  speciesToNational = 0x1FC516,
  hoennToNational = 0x1FC84C,
  entries = 0x3B1858,
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

return Dex
