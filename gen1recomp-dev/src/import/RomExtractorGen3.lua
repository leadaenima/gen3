-- Ruby Gen 3 extractor.  Walks gMapGroups, writes every map grid / warp /
-- connection, and one shared atlas per unique (primary, secondary) tileset
-- pair.  Nintendo assets stay out of git -- extract at import time.
-- Parallel to RomExtractor / RomExtractorGen2: a new module, not a branch
-- inside either GB extractor.
local GbaBin = require("src.import.GbaBin")
local GbaHeader = require("src.import.GbaHeader")
local GbaLz77 = require("src.import.GbaLz77")
local GbaText = require("src.import.GbaText")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local BattleData = require("src.import.RomExtractorGen3Battle")
local Gen3Script = require("src.import.Gen3Script")
local BootData = require("src.import.RomExtractorGen3Boot")
local Gen3Ui = require("src.import.RomExtractorGen3Ui")
local Gen3Audio = require("src.import.RomExtractorGen3Audio")
local Gen3Icons = require("src.import.RomExtractorGen3Icons")
local Gen3Party = require("src.import.RomExtractorGen3Party")

local RomExtractorGen3 = {}
RomExtractorGen3.__index = RomExtractorGen3

local STAGE_COUNT = 9
local NAMED_SPECIES = 412
local FONT_GLYPHS = 256
local FONT3_BYTES = 64
local FONT_COLS = 16
local FONT_W = 8
local FONT_H = 16
-- pokeruby sFonts[]: 7 Japanese records, then 7 Latin. Slot 10 is
-- latin FONT3 (type 0, 8x16 4bpp, glyphSize 64, lowerTileOffset 32).
local FONT_TABLE = {
  { 0, 16, 8 }, { 1, 8, 0 }, { 2, 8, 0 }, { 4, 64, 512 },
  { 1, 32, 0 }, { 2, 32, 0 }, { 3, 8, 0 },
  { 0, 16, 8 }, { 1, 8, 0 }, { 2, 8, 0 }, { 0, 64, 32 },
  { 1, 32, 0 }, { 2, 32, 0 }, { 3, 8, 0 },
}
local FONT_RECORD = 12
local LATIN_FONT3_SLOT = 10

local MUS_LITTLEROOT = 405
local MAP_TYPE_TOWN = 1
local PRIMARY_TILES = 512
local PRIMARY_METATILES = 512
local PRIMARY_PALS = 6
local TOTAL_PALS = 13
local TILE_BYTES = 32
local METATILE_BYTES = 16
local MAP_CELL_METATILE = 1023
local MAP_CELL_COLLISION_SHIFT = 10
local MAX_MAP_DIM = 255
local ATLAS_COLS = 32
local ATLAS_ROWS = 32
local ATLAS_METATILES = ATLAS_COLS * ATLAS_ROWS
local METATILE_PX = 16

local DIR_NAME = {
  [1] = "south", [2] = "north", [3] = "west", [4] = "east",
  [5] = "dive", [6] = "emerge",
}

local COORD_EVENT_SIZE = 16
local MAX_COORD_EVENTS = 64
local MAX_MAP_SCRIPT_TAGS = 12
local MAX_SCRIPT_TABLE = 16
RomExtractorGen3.COORD_EVENT_SIZE = COORD_EVENT_SIZE
RomExtractorGen3.MAP_SCRIPT_ON_LOAD = 1
RomExtractorGen3.MAP_SCRIPT_ON_FRAME_TABLE = 2
RomExtractorGen3.MAP_SCRIPT_ON_TRANSITION = 3
RomExtractorGen3.MAP_SCRIPT_ON_WARP_TABLE = 4
RomExtractorGen3.MAP_SCRIPT_ON_RESUME = 5
RomExtractorGen3.MAP_SCRIPT_ON_DIVE_WARP = 6

local MAP_SCRIPT_KEY = {
  [1] = "onLoad",
  [2] = "onFrame",
  [3] = "onTransition",
  [4] = "onWarp",
  [5] = "onResume",
  [6] = "onDiveWarp",
}

local MAP_SCRIPT_TABLE = {
  [2] = true,
  [4] = true,
}

RomExtractorGen3.METATILE_ATTR_LAYER_SHIFT = 12

function RomExtractorGen3.attrBehavior(attr)
  return (attr or 0) % 256
end

function RomExtractorGen3.attrLayerType(attr)
  return math.floor((attr or 0) / 4096) % 16
end

RomExtractorGen3.MUS_LITTLEROOT = MUS_LITTLEROOT
RomExtractorGen3.MAP_TYPE_TOWN = MAP_TYPE_TOWN
RomExtractorGen3.LITTLEROOT_ID = "littleroot_town"
RomExtractorGen3.LITTLEROOT_NAME = "Littleroot Town"
RomExtractorGen3.ATLAS_COLS = ATLAS_COLS
RomExtractorGen3.ATLAS_ROWS = ATLAS_ROWS
RomExtractorGen3.DIR_NAME = DIR_NAME

function RomExtractorGen3.mapId(group, index)
  return ("g%d_%d"):format(group, index)
end

function RomExtractorGen3.tilesetPath(pairId, layer)
  local n = tostring(pairId):gsub("^pair_", "")
  return ("assets/generated/tilesets/pair_%s_%s.png"):format(n, layer)
end

function RomExtractorGen3.spritePath(graphicsId)
  return ("assets/generated/sprites/ow_%d.png"):format(graphicsId)
end

-- trainer_see.c gSpriteImage_839B308 / 839B388 / 839B408: 16x16 4bpp
-- frames for ! / ? / heart. Heart's template uses pal tag 0x1004
-- (gFieldEffectObjectPalette0); ! and ? use TAG_NONE and pick up the
-- same field-effect slot already in OBJ VRAM.
RomExtractorGen3.EMOTE_GFX = 0x39B308
RomExtractorGen3.EMOTE_BYTES = 0x80
RomExtractorGen3.EMOTE_PAL = 0x369488
RomExtractorGen3.EMOTE_NAMES = { "exclaim", "question", "heart" }

function RomExtractorGen3.emotePath(name)
  return ("assets/generated/emotes/%s.png"):format(name)
end

function RomExtractorGen3.emoteFrameOff(name)
  for i = 1, #RomExtractorGen3.EMOTE_NAMES do
    if RomExtractorGen3.EMOTE_NAMES[i] == name then
      return RomExtractorGen3.EMOTE_GFX + (i - 1) * RomExtractorGen3.EMOTE_BYTES
    end
  end
end

function RomExtractorGen3.renderEmote(data, name)
  local frameOff = RomExtractorGen3.emoteFrameOff(name)
  if not frameOff then return nil, "unknown emote" end
  return RomExtractorGen3.renderOwFrame(data, {
    width = 16,
    height = 16,
    frameSize = RomExtractorGen3.EMOTE_BYTES,
    frameOff = frameOff,
  }, RomExtractorGen3.EMOTE_PAL, frameOff)
end

function RomExtractorGen3:extractEmotes()
  local emotes = {}
  for i = 1, #RomExtractorGen3.EMOTE_NAMES do
    local name = RomExtractorGen3.EMOTE_NAMES[i]
    local image = RomExtractorGen3.renderEmote(self.data, name)
    if image then
      local path = RomExtractorGen3.emotePath(name)
      ImageWriter.save(image, path)
      emotes[name] = { path = path, width = 16, height = 16 }
    end
  end
  return emotes
end

function RomExtractorGen3.fontPath()
  return "assets/generated/fonts/font.png"
end

function RomExtractorGen3.glyphInk4bpp(data, off, nbytes)
  if type(data) ~= "string" or type(off) ~= "number" then return 0 end
  local ink = 0
  for i = 0, (nbytes or 0) - 1 do
    local b = data:byte(off + i + 1) or 0
    local lo, hi = b % 16, math.floor(b / 16)
    if lo == 0xE or lo == 0xF then ink = ink + 1 end
    if hi == 0xE or hi == 0xF then ink = ink + 1 end
  end
  return ink
end

function RomExtractorGen3.isLatinFont3(data, off)
  if type(data) ~= "string" or type(off) ~= "number" then return false end
  if off < 0 or off + FONT_GLYPHS * FONT3_BYTES > #data then return false end
  if RomExtractorGen3.glyphInk4bpp(data, off, FONT3_BYTES) > 2 then return false end
  for c = 0xA1, 0xAA do
    local ink = RomExtractorGen3.glyphInk4bpp(data, off + c * FONT3_BYTES, FONT3_BYTES)
    if ink < 8 or ink > 200 then return false end
  end
  for c = 0xBB, 0xD4 do
    local ink = RomExtractorGen3.glyphInk4bpp(data, off + c * FONT3_BYTES, FONT3_BYTES)
    if ink < 8 or ink > 200 then return false end
  end
  for c = 0xD5, 0xEE do
    local ink = RomExtractorGen3.glyphInk4bpp(data, off + c * FONT3_BYTES, FONT3_BYTES)
    if ink < 4 then return false end
  end
  return true
end

local function fontGlyphsOff(data, rec)
  local ptr = GbaBin.u32(data, rec + 4)
  if not GbaBin.isRomPtr(ptr, #data) then return nil end
  return GbaBin.romOffset(ptr)
end

function RomExtractorGen3.findFontTable(data)
  if type(data) ~= "string" then return nil end
  local need = #FONT_TABLE * FONT_RECORD
  local last = #data - need
  for off = 0, last, 4 do
    local ok = true
    for i = 1, #FONT_TABLE do
      local rec = off + (i - 1) * FONT_RECORD
      local spec = FONT_TABLE[i]
      if GbaBin.u32(data, rec) ~= spec[1]
          or GbaBin.u16(data, rec + 8) ~= spec[2]
          or GbaBin.u16(data, rec + 10) ~= spec[3]
          or not fontGlyphsOff(data, rec) then
        ok = false
        break
      end
    end
    if ok then return off end
  end
  return nil
end

function RomExtractorGen3.findLatinFont3(data)
  if type(data) ~= "string" then return nil end
  local tableOff = RomExtractorGen3.findFontTable(data)
  if tableOff then
    local rec = tableOff + LATIN_FONT3_SLOT * FONT_RECORD
    local glyphsOff = fontGlyphsOff(data, rec)
    if glyphsOff and RomExtractorGen3.isLatinFont3(data, glyphsOff) then
      return glyphsOff
    end
  end
  local last = #data - FONT_RECORD
  for off = 0, last, 4 do
    if GbaBin.u32(data, off) == 0
        and GbaBin.u16(data, off + 8) == 64
        and GbaBin.u16(data, off + 10) == 32 then
      local glyphsOff = fontGlyphsOff(data, off)
      if glyphsOff and RomExtractorGen3.isLatinFont3(data, glyphsOff) then
        return glyphsOff
      end
    end
  end
  return nil
end

-- pokeruby sFont3Widths: space=3, 'A' (0xBB)=6. USA 1.0 prefix is
-- shared with rev1 for the first 32 bytes except later rows.
local FONT3_WIDTH_PREFIX = string.char(
  3, 6, 6, 6, 6, 6, 6, 6, 6, 6, 8, 6, 6, 6, 6, 6)

function RomExtractorGen3.isFont3WidthTable(data, off)
  if type(data) ~= "string" or type(off) ~= "number" then return false end
  if off < 0 or off + 254 > #data then return false end
  if data:byte(off + 1) ~= 3 then return false end
  if data:byte(off + 0xBB + 1) ~= 6 then return false end
  if data:byte(off + 0xA1 + 1) ~= 6 then return false end
  for i = 0, 253 do
    local w = data:byte(off + i + 1) or 0
    if w < 1 or w > 10 then return false end
  end
  return true
end

function RomExtractorGen3.findFont3Widths(data)
  if type(data) ~= "string" then return nil end
  local at = 1
  while true do
    local found = data:find(FONT3_WIDTH_PREFIX, at, true)
    if not found then return nil end
    local off = found - 1
    if RomExtractorGen3.isFont3WidthTable(data, off) then
      return off
    end
    at = found + 1
  end
end

function RomExtractorGen3.readFont3Widths(data, off)
  if not RomExtractorGen3.isFont3WidthTable(data, off) then return nil end
  local widths = {}
  for i = 0, 255 do
    widths[i + 1] = data:byte(off + i + 1) or 8
  end
  for i = 255, 256 do
    local w = widths[i]
    if not w or w < 1 or w > 10 then widths[i] = 8 end
  end
  return widths
end

local function blit4bppGlyph(image, px, py, data, off)
  local raw = data:sub(off + 1, off + FONT3_BYTES)
  if #raw < FONT3_BYTES then return end
  for y = 0, FONT_H - 1 do
    for x = 0, FONT_W - 1 do
      local c = RomExtractorGen3.colorIndex4bpp(raw, FONT_W, x, y)
      -- ApplyColors_ShadowedFont: 0xF is foreground, 0xE is shadow.
      -- Other non-zero indices are rare leftovers; treat them as ink.
      if c == 0xF then
        image:setPixel(px + x, py + y, 0, 0, 0, 1)
      elseif c == 0xE then
        image:setPixel(px + x, py + y, 0.38, 0.38, 0.42, 1)
      elseif c ~= 0 then
        image:setPixel(px + x, py + y, 0.18, 0.18, 0.20, 1)
      end
    end
  end
end

function RomExtractorGen3.renderFont3Sheet(data, off)
  if not RomExtractorGen3.isLatinFont3(data, off) then
    return nil, "latin font3 is not at that offset"
  end
  local w = FONT_COLS * FONT_W
  local h = (FONT_GLYPHS / FONT_COLS) * FONT_H
  local image = ImageWriter.blank(w, h, 0, 0, 0, 0)
  for code = 0, FONT_GLYPHS - 1 do
    local col = code % FONT_COLS
    local row = math.floor(code / FONT_COLS)
    blit4bppGlyph(image, col * FONT_W, row * FONT_H, data, off + code * FONT3_BYTES)
  end
  return image
end

function RomExtractorGen3.new(romData, manifest, progress, romSha1)
  return setmetatable({
    data = romData,
    manifest = manifest or {},
    progress = progress,
    romSha1 = romSha1,
    stage = 0,
  }, RomExtractorGen3)
end

function RomExtractorGen3:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then
    self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1)
  end
end

function RomExtractorGen3:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / math.max(1, total), STAGE_COUNT,
      name, current, total)
  end
end

function RomExtractorGen3:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

-- One LuaJIT chunk cannot hold every baked map script (65536 constants).
-- Index at maps.lua, one file per map under data/generated/maps/.
function RomExtractorGen3:writeMapPack(maps)
  local Gen3MapPack = require("src.import.Gen3MapPack")
  local index, mapTables = Gen3MapPack.indexFromPack(maps)
  for i = 1, #index.ids do
    local id = index.ids[i]
    LuaWriter.write("data/generated/maps/" .. id .. ".lua", mapTables[id])
  end
  self:write("maps", index)
end

function RomExtractorGen3.findSpeciesNameTable(data)
  if type(data) ~= "string" then return nil end
  local needle = GbaText.BULBASAUR
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local start = at - GbaText.NAME_LENGTH
  if start < 1 then return nil end
  return start
end

function RomExtractorGen3.decodeSpeciesNames(data)
  local start = RomExtractorGen3.findSpeciesNameTable(data)
  if not start then return nil, "species name table not found" end
  local names = {}
  for index = 0, NAMED_SPECIES - 1 do
    local off = start + index * GbaText.NAME_LENGTH
    names[index] = GbaText.decodeName(data:sub(off, off + GbaText.NAME_LENGTH - 1))
  end
  return names
end

local function romPtr(data, offset)
  local ptr = GbaBin.u32(data, offset)
  if not GbaBin.isRomPtr(ptr, #data) then return nil end
  return ptr, GbaBin.romOffset(ptr)
end

function RomExtractorGen3.parseMapHeader(data, offset)
  if type(data) ~= "string" or offset < 0 or offset + 0x1C > #data then
    return nil
  end
  local layoutPtr, layoutOff = romPtr(data, offset)
  local eventsPtr, eventsOff = romPtr(data, offset + 4)
  local scriptsPtr, scriptsOff = romPtr(data, offset + 8)
  local connectionsWord = GbaBin.u32(data, offset + 12)
  local connectionsOff
  if connectionsWord ~= 0 then
    if not GbaBin.isRomPtr(connectionsWord, #data) then return nil end
    connectionsOff = GbaBin.romOffset(connectionsWord)
  end
  if not (layoutPtr and eventsPtr and scriptsPtr) then
    return nil
  end
  local width = GbaBin.s32(data, layoutOff)
  local height = GbaBin.s32(data, layoutOff + 4)
  if width < 1 or height < 1 or width > MAX_MAP_DIM or height > MAX_MAP_DIM then
    return nil
  end
  return {
    offset = offset,
    layoutPtr = layoutPtr,
    layoutOff = layoutOff,
    eventsOff = eventsOff,
    scriptsOff = scriptsOff,
    connectionsOff = connectionsOff,
    music = GbaBin.u16(data, offset + 0x10),
    layoutId = GbaBin.u16(data, offset + 0x12),
    regionMapSectionId = GbaBin.u8(data, offset + 0x14),
    cave = GbaBin.u8(data, offset + 0x15) ~= 0,
    weather = GbaBin.u8(data, offset + 0x16),
    mapType = GbaBin.u8(data, offset + 0x17),
    width = width,
    height = height,
  }
end

function RomExtractorGen3.findTownHeader(data, musicId, mapType)
  if type(data) ~= "string" then return nil end
  musicId = musicId or MUS_LITTLEROOT
  mapType = mapType or MAP_TYPE_TOWN
  local needle = GbaBin.packU16(musicId)
  local i = 1
  while true do
    local at = data:find(needle, i, true)
    if not at then return nil end
    local musicOff = at - 1
    if musicOff >= 0x10 and musicOff % 4 == 0 then
      local header = RomExtractorGen3.parseMapHeader(data, musicOff - 0x10)
      if header and header.music == musicId and header.mapType == mapType then
        return header
      end
    end
    i = at + 1
  end
end

local function isHeaderPtr(data, ptr)
  if not GbaBin.isRomPtr(ptr, #data) then return false end
  return RomExtractorGen3.parseMapHeader(data, GbaBin.romOffset(ptr)) ~= nil
end

function RomExtractorGen3.findMapGroups(data)
  local town = RomExtractorGen3.findTownHeader(data)
  if not town then return nil, "Littleroot Town map header not found" end
  local needle = GbaBin.packPtr(town.offset)
  local at = data:find(needle, 1, true)
  if not at then return nil, "map group pointer to Littleroot not found" end
  local entryOff = at - 1
  local group0 = entryOff
  while group0 >= 4 do
    local prev = GbaBin.u32(data, group0 - 4)
    if not isHeaderPtr(data, prev) then break end
    group0 = group0 - 4
  end
  local g0ptr = GbaBin.packPtr(group0)
  local groupsOff
  local search = 1
  while true do
    local hit = data:find(g0ptr, search, true)
    if not hit then break end
    local off = hit - 1
    local nextPtr = GbaBin.u32(data, off + 4)
    if off ~= group0 and GbaBin.isRomPtr(nextPtr, #data) then
      groupsOff = off
      break
    end
    search = hit + 1
  end
  if not groupsOff then return nil, "gMapGroups not found" end
  local groupStarts = {}
  for i = 0, 63 do
    local _, start = romPtr(data, groupsOff + i * 4)
    if not start then break end
    groupStarts[#groupStarts + 1] = start
  end
  if #groupStarts < 1 then return nil, "empty gMapGroups" end
  local groups = {}
  local startGroup, startIndex
  for gi, start in ipairs(groupStarts) do
    local stop = groupStarts[gi + 1] or groupsOff
    local count = math.floor((stop - start) / 4)
    if count < 1 then count = 1 end
    local headers = {}
    for mi = 0, count - 1 do
      local _, ho = romPtr(data, start + mi * 4)
      local header = ho and RomExtractorGen3.parseMapHeader(data, ho)
      if header then
        headers[#headers + 1] = header
        if header.offset == town.offset then
          startGroup, startIndex = gi - 1, mi
        end
      end
    end
    groups[#groups + 1] = headers
  end
  if startGroup == nil then
    return nil, "Littleroot is not inside gMapGroups"
  end
  return {
    groups = groups,
    startGroup = startGroup,
    startIndex = startIndex,
    town = town,
  }
end

-- gMapLayouts is an array of MapLayout pointers. GetMapLayout uses
-- gMapLayouts[mapLayoutId - 1]. Alternate layouts (Route 131 Sky Pillar
-- island 320, Mirage 46, Shoal high tide 169/170, Ruby CoO 313 / Seafloor
-- 327) have no map header, so walking gMapGroups would miss them.
local MAX_MAP_LAYOUTS = 400

function RomExtractorGen3.findMapLayouts(data, found)
  local town = found and found.town
  if type(data) ~= "string" or not town or not town.layoutOff
      or not town.layoutId or town.layoutId < 1 then
    return nil
  end
  local function layoutLooksValid(layoutOff)
    if layoutOff < 0 or layoutOff + 24 > #data then return false end
    local width = GbaBin.s32(data, layoutOff)
    local height = GbaBin.s32(data, layoutOff + 4)
    if width < 1 or height < 1 or width > MAX_MAP_DIM
        or height > MAX_MAP_DIM then
      return false
    end
    local _, mapOff = romPtr(data, layoutOff + 12)
    local primPtr = romPtr(data, layoutOff + 16)
    local secPtr = romPtr(data, layoutOff + 20)
    return mapOff ~= nil and primPtr ~= nil and secPtr ~= nil
  end
  local needle = GbaBin.packPtr(town.layoutOff)
  local search = 1
  local best, bestCount
  while true do
    local hit = data:find(needle, search, true)
    if not hit then break end
    local off = hit - 1
    if off % 4 == 0 then
      local base = off - (town.layoutId - 1) * 4
      if base >= 0 and base % 4 == 0 then
        local _, lo = romPtr(data, base + (town.layoutId - 1) * 4)
        if lo == town.layoutOff then
          local count = 0
          for id = 1, MAX_MAP_LAYOUTS do
            local _, slot = romPtr(data, base + (id - 1) * 4)
            if not slot or not layoutLooksValid(slot) then break end
            count = count + 1
          end
          if count > (bestCount or 0) then
            best, bestCount = base, count
          end
        end
      end
    end
    search = hit + 1
  end
  if not best or (bestCount or 0) < 1 then return nil end
  return best, bestCount
end

local function parseTileset(data, offset)
  local compressed = GbaBin.u8(data, offset) ~= 0
  local secondary = GbaBin.u8(data, offset + 1) ~= 0
  local tilesPtr, tilesOff = romPtr(data, offset + 4)
  local palsPtr, palsOff = romPtr(data, offset + 8)
  local metaPtr, metaOff = romPtr(data, offset + 12)
  if not (tilesPtr and palsPtr and metaPtr) then
    return nil, "tileset pointers are not in ROM"
  end
  local tiles
  if compressed then
    local decoded, err = GbaLz77.decompress(data, tilesOff)
    if not decoded then return nil, err end
    tiles = decoded
  else
    tiles = data:sub(tilesOff + 1, tilesOff + PRIMARY_TILES * TILE_BYTES)
  end
  return {
    compressed = compressed,
    secondary = secondary,
    tiles = tiles,
    palsOff = palsOff,
    metaOff = metaOff,
    attrOff = select(2, romPtr(data, offset + 16)),
  }
end

local function parseLayout(data, layoutOff)
  local width = GbaBin.s32(data, layoutOff)
  local height = GbaBin.s32(data, layoutOff + 4)
  local _, borderOff = romPtr(data, layoutOff + 8)
  local _, mapOff = romPtr(data, layoutOff + 12)
  local primPtr, primOff = romPtr(data, layoutOff + 16)
  local secPtr, secOff = romPtr(data, layoutOff + 20)
  if not (mapOff and primPtr and secPtr) then
    return nil, "map layout pointers are not in ROM"
  end
  local cells = width * height
  if mapOff + cells * 2 > #data then
    return nil, "map grid is truncated"
  end
  local grid = {}
  for i = 0, cells - 1 do
    grid[i + 1] = GbaBin.u16(data, mapOff + i * 2)
  end
  -- fieldmap.c GetBorderBlockAt: a 2x2 of u16 cells, wrap-tiled with
  -- `(x+1)&1 + ((y+1)&1)*2`. Older caches omit this; the runtime fills
  -- with the void colour until a re-import.
  local border
  if borderOff and borderOff + 8 <= #data then
    border = {
      GbaBin.u16(data, borderOff),
      GbaBin.u16(data, borderOff + 2),
      GbaBin.u16(data, borderOff + 4),
      GbaBin.u16(data, borderOff + 6),
    }
  end
  return {
    width = width,
    height = height,
    grid = grid,
    border = border,
    primaryOff = primOff,
    secondaryOff = secOff,
  }
end

local function parseWarps(data, eventsOff)
  local warps = {}
  if not eventsOff or eventsOff + 20 > #data then return warps end
  local count = GbaBin.u8(data, eventsOff + 1)
  local _, warpsOff = romPtr(data, eventsOff + 8)
  if not warpsOff then return warps end
  for i = 0, count - 1 do
    local o = warpsOff + i * 8
    if o + 8 > #data then break end
    warps[#warps + 1] = {
      x = GbaBin.s16(data, o),
      y = GbaBin.s16(data, o + 2),
      elevation = GbaBin.u8(data, o + 4),
      warpId = GbaBin.u8(data, o + 5),
      mapNum = GbaBin.u8(data, o + 6),
      mapGroup = GbaBin.u8(data, o + 7),
    }
  end
  return warps
end

function RomExtractorGen3.parseCoordEvent(data, o)
  if type(data) ~= "string" or type(o) ~= "number" then return nil end
  if o + COORD_EVENT_SIZE > #data then return nil end
  local ev = {
    x = GbaBin.s16(data, o),
    y = GbaBin.s16(data, o + 2),
    elevation = GbaBin.u8(data, o + 4),
    trigger = GbaBin.u16(data, o + 6),
    index = GbaBin.u16(data, o + 8),
  }
  ev.scriptOff = select(2, romPtr(data, o + 12))
  return ev
end

local function parseCoordEvents(data, eventsOff)
  local events = {}
  if not eventsOff or eventsOff + 20 > #data then return events end
  local count = GbaBin.u8(data, eventsOff + 2)
  if count > MAX_COORD_EVENTS then count = MAX_COORD_EVENTS end
  local _, off = romPtr(data, eventsOff + 12)
  if not off then return events end
  for i = 0, count - 1 do
    local row = RomExtractorGen3.parseCoordEvent(data, off + i * COORD_EVENT_SIZE)
    if not row then break end
    events[#events + 1] = row
  end
  return events
end

local function parseScriptTable(data, off)
  local rows = {}
  if type(off) ~= "number" then return rows end
  for _ = 1, MAX_SCRIPT_TABLE do
    if off + 8 > #data then break end
    local var = GbaBin.u16(data, off)
    if var == 0 then break end
    rows[#rows + 1] = {
      var = var,
      value = GbaBin.u16(data, off + 2),
      scriptOff = select(2, romPtr(data, off + 4)),
    }
    off = off + 8
  end
  return rows
end

function RomExtractorGen3.parseMapScripts(data, scriptsOff)
  local out = {}
  if type(data) ~= "string" or type(scriptsOff) ~= "number" then return out end
  local p = scriptsOff
  for _ = 1, MAX_MAP_SCRIPT_TAGS do
    if p >= #data then break end
    local tag = GbaBin.u8(data, p)
    if tag == 0 then break end
    local key = MAP_SCRIPT_KEY[tag]
    local destOff = select(2, romPtr(data, p + 1))
    p = p + 5
    if key and destOff then
      if MAP_SCRIPT_TABLE[tag] then
        out[key] = parseScriptTable(data, destOff)
      else
        out[key] = destOff
      end
    end
  end
  return out
end

function RomExtractorGen3.parseOps(data, off)
  if type(off) ~= "number" then return nil end
  local ops = Gen3Script.parse(data, off)
  if type(ops) ~= "table" then return nil end
  for i = 1, #ops do
    if ops[i] and ops[i].op ~= "end" then return ops end
  end
  return nil
end

local function bakeScriptField(data, row)
  if type(row) ~= "table" then return end
  if row.scriptOff then
    row.script = RomExtractorGen3.parseOps(data, row.scriptOff)
    row.scriptOff = nil
  end
end

function RomExtractorGen3.bakeMapScripts(data, map)
  if type(map) ~= "table" then return map end
  local events = map.coordEvents
  if type(events) == "table" then
    for i = 1, #events do bakeScriptField(data, events[i]) end
  end
  local bgs = map.bgEvents
  if type(bgs) == "table" then
    for i = 1, #bgs do bakeScriptField(data, bgs[i]) end
  end
  local ms = map.mapScripts
  if type(ms) == "table" then
    for _, key in ipairs({ "onLoad", "onTransition", "onResume", "onDiveWarp" }) do
      if type(ms[key]) == "number" then
        ms[key] = RomExtractorGen3.parseOps(data, ms[key])
      end
    end
    for _, key in ipairs({ "onFrame", "onWarp" }) do
      local rows = ms[key]
      if type(rows) == "table" then
        for i = 1, #rows do bakeScriptField(data, rows[i]) end
      end
    end
  end
  local objects = map.objects
  if type(objects) == "table" then
    for i = 1, #objects do
      local o = objects[i]
      if o and o.scriptOff then
        o.script = RomExtractorGen3.parseOps(data, o.scriptOff) or o.script
        o.scriptOff = nil
      end
    end
  end
  return map
end

-- pokeruby struct ObjectEventTemplate is 0x18.  Emerald packs trainerType
-- as a u8 at +0x0B; Ruby uses a u16 at +0x0C and the script pointer at
-- +0x10.  x/y are map cells, not the 7-tile in-engine border.
local OBJECT_EVENT_SIZE = 0x18
local MAX_OBJECTS = 64
local GFX_INFO_SIZE = 0x24
local MAX_OW_GFX = 256
local PAL_TAG_MIN = 0x1100
local PAL_TAG_MAX = 0x11FF
local PLAYER_GFX_ID = 0
local PLAYER_FORM_GFX = {
  0, 1, 2, 63, 89, 90, 91, 92, 100, 105, 111, 112, 191, 192,
}
-- Map templates only stamp gfx 60. get_berry_tree_graphics swaps 61/62.
-- Both share gObjectEventPicTable_PechaBerryTree (16x16 then 16x32).
local BERRY_TREE_STAGE_GFX = { 61, 62 }
-- Woods/Rustboro grunts are OBJ_EVENT_GFX_VAR_1 until SetupEvilTeamGfxIds
-- writes Magma/Aqua. collectGraphicsIds never sees 117-120 on the map.
local EVIL_TEAM_GFX = { 117, 118, 119, 120, 195, 196 }

-- EventScript_ResetAllMapFlags: setflag FLAG_LINK_CONTEST_ROOM_POKEBALL
-- (0x56) then FLAG_HIDE_VICTORIA_WINSTRATE (0x301), then ~130 more setflags,
-- then call berry-tree init. New game runs this so story NPCs stay hidden.
function RomExtractorGen3.findResetMapFlags(data)
  if type(data) ~= "string" then return nil end
  local needle = string.char(0x29, 0x56, 0x00, 0x29, 0x01, 0x03)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local flags = {}
  local off = at - 1
  while off + 2 < #data and GbaBin.u8(data, off) == 0x29 do
    flags[#flags + 1] = GbaBin.u16(data, off + 1)
    off = off + 3
  end
  local nextCmd = GbaBin.u8(data, off)
  if nextCmd ~= 0x04 and nextCmd ~= 0x02 then return nil end
  if #flags < 80 then return nil end
  return flags
end

function RomExtractorGen3.parseObjectTemplate(data, o)
  if type(data) ~= "string" or type(o) ~= "number" then return nil end
  if o + OBJECT_EVENT_SIZE > #data then return nil end
  return {
    localId = GbaBin.u8(data, o),
    graphicsId = GbaBin.u8(data, o + 1),
    kind = GbaBin.u8(data, o + 2),
    x = GbaBin.s16(data, o + 4),
    y = GbaBin.s16(data, o + 6),
    elevation = GbaBin.u8(data, o + 8),
    movementType = GbaBin.u8(data, o + 9),
    rangeX = GbaBin.u8(data, o + 10) % 16,
    rangeY = math.floor(GbaBin.u8(data, o + 10) / 16) % 16,
    trainerType = GbaBin.u16(data, o + 0x0C),
    trainerRange = GbaBin.u16(data, o + 0x0E),
    scriptOff = select(2, romPtr(data, o + 0x10)),
    flagId = GbaBin.u16(data, o + 0x14),
  }
end

local function parseObjects(data, eventsOff)
  local objects = {}
  if not eventsOff or eventsOff + 20 > #data then return objects end
  local count = GbaBin.u8(data, eventsOff)
  if count > MAX_OBJECTS then count = MAX_OBJECTS end
  local _, objOff = romPtr(data, eventsOff + 4)
  if not objOff then return objects end
  for i = 0, count - 1 do
    local row = RomExtractorGen3.parseObjectTemplate(data, objOff + i * OBJECT_EVENT_SIZE)
    if not row then break end
    objects[#objects + 1] = row
  end
  return objects
end

local BG_EVENT_SIZE = 0x0C
local MAX_BG_EVENTS = 64
local LOADWORD_CMD = 0x0F
RomExtractorGen3.BG_EVENT_SIZE = BG_EVENT_SIZE
RomExtractorGen3.BG_HIDDEN_ITEM = 7
RomExtractorGen3.BG_SECRET_BASE = 8
RomExtractorGen3.LOADWORD_CMD = LOADWORD_CMD

function RomExtractorGen3.readSignText(data, scriptOff)
  if type(data) ~= "string" or type(scriptOff) ~= "number" then return nil end
  for i = 0, 47 do
    if scriptOff + i + 6 > #data then break end
    if GbaBin.u8(data, scriptOff + i) == LOADWORD_CMD then
      local _, textOff = romPtr(data, scriptOff + i + 2)
      if textOff then
        local text = GbaText.decodeText(data:sub(textOff + 1, textOff + 96))
        if text ~= "" then return text end
      end
    end
  end
end

function RomExtractorGen3.parseBgEvent(data, o)
  if type(data) ~= "string" or type(o) ~= "number" then return nil end
  if o + BG_EVENT_SIZE > #data then return nil end
  local kind = GbaBin.u8(data, o + 5)
  local ev = {
    x = GbaBin.u16(data, o),
    y = GbaBin.u16(data, o + 2),
    elevation = GbaBin.u8(data, o + 4),
    kind = kind,
  }
  if kind == RomExtractorGen3.BG_HIDDEN_ITEM or kind == 5 or kind == 6 then
    ev.itemId = GbaBin.u16(data, o + 8)
    ev.hiddenId = GbaBin.u16(data, o + 10)
  elseif kind == RomExtractorGen3.BG_SECRET_BASE then
    ev.secretBaseId = GbaBin.u32(data, o + 8)
  else
    local _, scriptOff = romPtr(data, o + 8)
    if scriptOff then
      ev.scriptOff = scriptOff
      ev.text = RomExtractorGen3.readSignText(data, scriptOff)
    end
  end
  return ev
end

local function parseBgEvents(data, eventsOff)
  local events = {}
  if not eventsOff or eventsOff + 20 > #data then return events end
  local count = GbaBin.u8(data, eventsOff + 3)
  if count > MAX_BG_EVENTS then count = MAX_BG_EVENTS end
  local _, bgOff = romPtr(data, eventsOff + 16)
  if not bgOff then return events end
  for i = 0, count - 1 do
    local row = RomExtractorGen3.parseBgEvent(data, bgOff + i * BG_EVENT_SIZE)
    if not row then break end
    events[#events + 1] = row
  end
  return events
end

local function parseConnections(data, connectionsOff)
  local out = {}
  if not connectionsOff or connectionsOff + 8 > #data then return out end
  local count = GbaBin.u32(data, connectionsOff)
  if count == 0 or count > 16 then return out end
  local _, arrOff = romPtr(data, connectionsOff + 4)
  if not arrOff then return out end
  for i = 0, count - 1 do
    local o = arrOff + i * 12
    if o + 12 > #data then break end
    local dir = DIR_NAME[GbaBin.u8(data, o)]
    if dir then
      out[#out + 1] = {
        dir = dir,
        offset = GbaBin.s32(data, o + 4),
        mapGroup = GbaBin.u8(data, o + 8),
        mapNum = GbaBin.u8(data, o + 9),
      }
    end
  end
  return out
end

local function validOwSize(n)
  return n == 8 or n == 16 or n == 24 or n == 32 or n == 48 or n == 64
end

function RomExtractorGen3.parseGraphicsInfo(data, offset)
  if type(data) ~= "string" or offset < 0 or offset + GFX_INFO_SIZE > #data then
    return nil
  end
  local width = GbaBin.s16(data, offset + 8)
  local height = GbaBin.s16(data, offset + 10)
  if not (validOwSize(width) and validOwSize(height)) then return nil end
  local size = GbaBin.u16(data, offset + 6)
  local palTag = GbaBin.u16(data, offset + 2)
  if palTag < PAL_TAG_MIN or palTag > PAL_TAG_MAX then return nil end
  if size < 32 or size > 4096 then return nil end
  local imagesPtr, imagesOff = romPtr(data, offset + 28)
  if not imagesPtr then return nil end
  -- Berry trees share gObjectEventPicTable_PechaBerryTree: three 16x16
  -- dirt/sprout images, then six 16x32 bushes. gfx 62 is 16x32, so the
  -- first entries are the wrong size. Skip that prefix; stop at the next
  -- mismatch (the following berry table starts at 16x16 again).
  local expected = width * height / 2
  local frames = {}
  local started = false
  for n = 0, 31 do
    local p, off = romPtr(data, imagesOff + n * 8)
    local sz = GbaBin.u16(data, imagesOff + n * 8 + 4)
    if not p then break end
    if sz == expected then
      started = true
      frames[#frames + 1] = off
    elseif started then
      break
    end
  end
  if #frames == 0 then return nil end
  return {
    offset = offset,
    tileTag = GbaBin.u16(data, offset),
    paletteTag = palTag,
    size = size,
    width = width,
    height = height,
    paletteSlot = GbaBin.u8(data, offset + 12) % 16,
    imagesOff = imagesOff,
    animsOff = select(2, romPtr(data, offset + 24)),
    frameOff = frames[1],
    frameSize = expected,
    frames = frames,
    frameCount = #frames,
  }
end

local OW_DIRS = { "south", "north", "west", "east" }
local ANIM_END = -1
local ANIM_JUMP = -2
local ANIM_LOOP = -3
local MAX_ANIM_FRAME = 31

local function defaultOwPoses()
  local face, walk = {}, {}
  for i = 1, #OW_DIRS do
    local d = OW_DIRS[i]
    face[d] = { frame = 0, flip = false }
    walk[d] = {}
  end
  return { face = face, walk = walk }
end

function RomExtractorGen3.parseAnimScript(data, offset)
  if type(data) ~= "string" or not offset or offset + 4 > #data then return nil end
  local frames = {}
  for c = 0, 15 do
    local o = offset + c * 4
    if o + 4 > #data then break end
    local typ = GbaBin.s16(data, o)
    if typ == ANIM_END or typ == ANIM_JUMP then
      break
    elseif typ == ANIM_LOOP then
      -- skip; walk loops are JUMP(0) at the end
    elseif typ >= 0 and typ <= MAX_ANIM_FRAME then
      local u = GbaBin.u32(data, o)
      frames[#frames + 1] = {
        frame = typ,
        duration = math.floor(u / 65536) % 64,
        flip = math.floor(u / 2 ^ 22) % 2 == 1,
      }
    else
      return nil
    end
  end
  if #frames == 0 then return nil end
  return frames
end

function RomExtractorGen3.parseOwAnims(data, animsOff)
  local poses = defaultOwPoses()
  if type(data) ~= "string" or not animsOff then return poses end
  local scripts = {}
  for i = 0, 7 do
    local _, off = romPtr(data, animsOff + i * 4)
    scripts[i + 1] = off and RomExtractorGen3.parseAnimScript(data, off) or nil
    if not scripts[i + 1] and i < 4 then break end
  end
  for i = 1, 4 do
    local d = OW_DIRS[i]
    local stand = scripts[i]
    if stand and stand[1] then
      poses.face[d] = { frame = stand[1].frame, flip = stand[1].flip and true or false }
    elseif i == 4 and poses.face.west then
      poses.face.east = { frame = poses.face.west.frame, flip = not poses.face.west.flip }
    end
    local go = scripts[i + 4]
    if go then
      poses.walk[d] = go
    end
  end
  return poses
end

function RomExtractorGen3.maxAnimFrame(poses)
  local maxF = 0
  local function consider(p)
    if type(p) == "table" and type(p.frame) == "number" and p.frame > maxF then
      maxF = p.frame
    end
  end
  if type(poses) ~= "table" then return 0 end
  for _, d in ipairs(OW_DIRS) do
    consider(poses.face and poses.face[d])
    local walk = poses.walk and poses.walk[d]
    if type(walk) == "table" then
      for i = 1, #walk do consider(walk[i]) end
    end
  end
  return maxF
end

function RomExtractorGen3.findObjectEventGraphics(data)
  if type(data) ~= "string" then return nil, "no ROM data" end
  local needle = GbaBin.packU16(PAL_TAG_MIN)
  local best
  local search = 1
  while true do
    local at = data:find(needle, search, true)
    if not at then break end
    local palOff = at - 1
    if palOff >= 2 and (palOff - 2) % 4 == 0 then
      local info = RomExtractorGen3.parseGraphicsInfo(data, palOff - 2)
      if info and info.width == 16 and info.height == 32 then
        local packed = GbaBin.packPtr(info.offset)
        local psearch = 1
        while true do
          local hit = data:find(packed, psearch, true)
          if not hit then break end
          local tableOff = hit - 1
          if tableOff % 4 == 0 then
            local _, nextOff = romPtr(data, tableOff + 4)
            if nextOff and RomExtractorGen3.parseGraphicsInfo(data, nextOff) then
              local n = 0
              while n < MAX_OW_GFX do
                if not romPtr(data, tableOff + n * 4) then break end
                n = n + 1
              end
              if n >= 8 and (not best or n > best.count) then
                best = { tableOff = tableOff, count = n }
              end
            end
          end
          psearch = hit + 1
        end
      end
    end
    search = at + 1
  end
  if not best then return nil, "object event graphics table not found" end
  local byId = {}
  for i = 0, best.count - 1 do
    local _, off = romPtr(data, best.tableOff + i * 4)
    byId[i] = off and RomExtractorGen3.parseGraphicsInfo(data, off) or nil
  end
  return {
    tableOff = best.tableOff,
    count = best.count,
    byId = byId,
  }
end

local function parsePaletteRun(data, off)
  local n, byTag = 0, {}
  while n < 48 do
    local o = off + n * 8
    if o + 8 > #data then break end
    local ptr, palOff = romPtr(data, o)
    local tag = GbaBin.u16(data, o + 4)
    if not ptr or tag < PAL_TAG_MIN or tag > PAL_TAG_MAX then break end
    byTag[tag] = palOff
    n = n + 1
  end
  return n, byTag
end

function RomExtractorGen3.findObjectEventPalettes(data, graphics)
  if type(data) ~= "string" then return nil, "no ROM data" end
  if graphics then
    local maxOff = 0
    for i = 0, (graphics.count or 0) - 1 do
      local info = graphics.byId[i]
      if info and info.offset > maxOff then maxOff = info.offset end
    end
    if maxOff > 0 then
      local n, byTag = parsePaletteRun(data, maxOff + GFX_INFO_SIZE)
      if n >= 6 then
        return {
          tableOff = maxOff + GFX_INFO_SIZE,
          count = n,
          byTag = byTag,
        }
      end
    end
  end
  local bestN, bestOff, bestTags = 0, nil, nil
  local i = 0
  while i + 48 <= #data do
    local n, byTag = parsePaletteRun(data, i)
    if n > bestN then
      bestN, bestOff, bestTags = n, i, byTag
    end
    if n > 1 then
      i = i + n * 8
    else
      i = i + 4
    end
  end
  if bestN < 6 then return nil, "object event palettes not found" end
  return { tableOff = bestOff, count = bestN, byTag = bestTags }
end

function RomExtractorGen3.colorIndex4bpp(raw, width, x, y)
  if type(raw) ~= "string" or type(width) ~= "number" then return 0 end
  local tw = math.floor(width / 8)
  if tw < 1 or x < 0 or y < 0 then return 0 end
  local col, row = math.floor(x / 8), math.floor(y / 8)
  local ti = row * tw + col
  local tx, ty = x % 8, y % 8
  local start = ti * TILE_BYTES + ty * 4 + math.floor(tx / 2)
  local byte = raw:byte(start + 1) or 0
  if tx % 2 == 0 then return byte % 16 end
  return math.floor(byte / 16)
end

function RomExtractorGen3.collectGraphicsIds(maps)
  local used = {}
  for i = 1, #PLAYER_FORM_GFX do
    used[PLAYER_FORM_GFX[i]] = true
  end
  for i = 1, #BERRY_TREE_STAGE_GFX do
    used[BERRY_TREE_STAGE_GFX[i]] = true
  end
  for i = 1, #EVIL_TEAM_GFX do
    used[EVIL_TEAM_GFX[i]] = true
  end
  if type(maps) == "table" then
    for _, map in pairs(maps) do
      local objects = map and map.objects
      if type(objects) == "table" then
        for i = 1, #objects do
          local gid = objects[i] and objects[i].graphicsId
          if type(gid) == "number" then used[gid] = true end
        end
      end
    end
  end
  local ids = {}
  for gid in pairs(used) do ids[#ids + 1] = gid end
  table.sort(ids)
  return ids
end

local function collisionOf(cell)
  return math.floor(cell / 2 ^ MAP_CELL_COLLISION_SHIFT) % 4
end

local function pickSpawn(grid, width, height)
  local cx, cy = math.floor(width / 2), math.floor(height / 2)
  local function walkable(x, y)
    if x < 0 or y < 0 or x >= width or y >= height then return false end
    return collisionOf(grid[y * width + x + 1]) == 0
  end
  if walkable(cx, cy) then return cx, cy end
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if walkable(x, y) then return x, y end
    end
  end
  return 0, 0
end

function RomExtractorGen3.decodeTownMap(data)
  local header = RomExtractorGen3.findTownHeader(data)
  if not header then return nil, "Littleroot Town map header not found" end
  local layout, err = parseLayout(data, header.layoutOff)
  if not layout then return nil, err end
  local warps = parseWarps(data, header.eventsOff)
  local sx, sy = pickSpawn(layout.grid, layout.width, layout.height)
  local map = {
    id = RomExtractorGen3.LITTLEROOT_ID,
    name = RomExtractorGen3.LITTLEROOT_NAME,
    width = layout.width,
    height = layout.height,
    music = header.music,
    layoutId = header.layoutId,
    mapType = header.mapType,
    weather = header.weather,
    regionMapSectionId = header.regionMapSectionId,
    cave = header.cave,
    spawn = { x = sx, y = sy },
    grid = layout.grid,
    border = layout.border,
    warps = warps,
    objects = parseObjects(data, header.eventsOff),
    bgEvents = parseBgEvents(data, header.eventsOff),
    coordEvents = parseCoordEvents(data, header.eventsOff),
    mapScripts = RomExtractorGen3.parseMapScripts(data, header.scriptsOff),
    connections = parseConnections(data, header.connectionsOff),
  }
  return map, layout.primaryOff, layout.secondaryOff
end

local function bgr555(c)
  local r = (c % 32) * 8
  local g = (math.floor(c / 32) % 32) * 8
  local b = (math.floor(c / 1024) % 32) * 8
  return r / 255, g / 255, b / 255
end

local function loadPalettes(data, primary, secondary)
  local pals = {}
  for pal = 0, TOTAL_PALS - 1 do
    pals[pal] = {}
    local base = pal < PRIMARY_PALS and primary.palsOff or secondary.palsOff
    for c = 0, 15 do
      local r, g, b = bgr555(GbaBin.u16(data, base + pal * 32 + c * 2))
      pals[pal][c] = { r, g, b }
    end
  end
  return pals
end

local function tileBytes(tileset, tileId)
  local localId = tileId
  if tileset.secondary then
    if tileId < PRIMARY_TILES then return nil end
    localId = tileId - PRIMARY_TILES
  elseif tileId >= PRIMARY_TILES then
    return nil
  end
  local start = localId * TILE_BYTES
  if start + TILE_BYTES > #tileset.tiles then return nil end
  return tileset.tiles:sub(start + 1, start + TILE_BYTES)
end

local function blitTile(image, x, y, raw, palette, hflip, vflip, skip0)
  if not raw or #raw < TILE_BYTES then return end
  for ty = 0, 7 do
    for tx = 0, 7 do
      local sx = hflip and (7 - tx) or tx
      local sy = vflip and (7 - ty) or ty
      local byte = raw:byte(sy * 4 + math.floor(sx / 2) + 1)
      local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if not (skip0 and ci == 0) then
        local col = palette[ci] or { 1, 0, 1 }
        image:setPixel(x + tx, y + ty, col[1], col[2], col[3], 1)
      end
    end
  end
end

function RomExtractorGen3.renderOwFrame(data, info, palOff, frameOff)
  if not (info and palOff) then return nil, "missing sprite info" end
  local w, h = info.width, info.height
  local expected = info.frameSize or (w * h / 2)
  frameOff = frameOff or info.frameOff
  local raw = data:sub(frameOff + 1, frameOff + expected)
  if #raw < expected then return nil, "sprite frame is truncated" end
  local pal = {}
  for c = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(data, palOff + c * 2))
    pal[c] = { r, g, b }
  end
  local image = ImageWriter.blank(w, h, 0, 0, 0, 0)
  local tw = w / 8
  local tiles = tw * (h / 8)
  for ti = 0, tiles - 1 do
    local col = ti % tw
    local row = math.floor(ti / tw)
    local start = ti * TILE_BYTES
    blitTile(image, col * 8, row * 8,
      raw:sub(start + 1, start + TILE_BYTES), pal, false, false, true)
  end
  return image
end

function RomExtractorGen3.renderOwSheet(data, info, palOff, frameCount)
  frameCount = frameCount or (info.frameCount or 1)
  if frameCount < 1 then frameCount = 1 end
  local w, h = info.width, info.height
  if frameCount == 1 then
    return RomExtractorGen3.renderOwFrame(data, info, palOff, info.frames and info.frames[1])
  end
  local sheet = ImageWriter.blank(w * frameCount, h, 0, 0, 0, 0)
  for i = 1, frameCount do
    local off = info.frames and info.frames[i] or info.frameOff
    local frame, err = RomExtractorGen3.renderOwFrame(data, info, palOff, off)
    if not frame then return nil, err end
    ImageWriter.blit(sheet, frame, (i - 1) * w, 0)
  end
  return sheet
end

local function metatileTiles(data, tileset, metatileId)
  local localId = metatileId
  if tileset.secondary then
    if metatileId < PRIMARY_METATILES then return nil end
    localId = metatileId - PRIMARY_METATILES
  elseif metatileId >= PRIMARY_METATILES then
    return nil
  end
  local base = tileset.metaOff + localId * METATILE_BYTES
  if base + METATILE_BYTES > #data then return nil end
  local tiles = {}
  for i = 0, 7 do
    tiles[i] = GbaBin.u16(data, base + i * 2)
  end
  return tiles
end

local function drawMetatile(image, data, primary, secondary, pals, mx, my, mid, top)
  local tileset = mid < PRIMARY_METATILES and primary or secondary
  local tiles = metatileTiles(data, tileset, mid)
  if not tiles then return end
  local start = top and 4 or 0
  for i = 0, 3 do
    local t = tiles[start + i]
    local tid = t % 1024
    local hflip = math.floor(t / 1024) % 2 == 1
    local vflip = math.floor(t / 2048) % 2 == 1
    local pal = math.floor(t / 4096) % 16
    local src = tid < PRIMARY_TILES and primary or secondary
    blitTile(
      image,
      mx * METATILE_PX + (i % 2) * 8,
      my * METATILE_PX + math.floor(i / 2) * 8,
      tileBytes(src, tid),
      pals[pal] or pals[0],
      hflip, vflip, top)
  end
end

function RomExtractorGen3.renderTilesetPair(data, primaryOff, secondaryOff, used)
  local primary, pErr = parseTileset(data, primaryOff)
  if not primary then return nil, pErr end
  local secondary, sErr = parseTileset(data, secondaryOff)
  if not secondary then return nil, sErr end
  local pals = loadPalettes(data, primary, secondary)
  local w = ATLAS_COLS * METATILE_PX
  local h = ATLAS_ROWS * METATILE_PX
  local bottom = ImageWriter.blank(w, h, 0, 0, 0, 1)
  local top = ImageWriter.blank(w, h, 0, 0, 0, 0)
  -- Paint every readable metatile, not only those on a map. onLoad
  -- setmetatile (moving boxes, books, doors) writes IDs that never
  -- appear in the grid; skipping them left opaque-black atlas cells.
  for mid = 0, ATLAS_METATILES - 1 do
    local col = mid % ATLAS_COLS
    local row = math.floor(mid / ATLAS_COLS)
    drawMetatile(bottom, data, primary, secondary, pals, col, row, mid, false)
    drawMetatile(top, data, primary, secondary, pals, col, row, mid, true)
  end
  return bottom, top
end

local function pairKey(primOff, secOff)
  return primOff .. ":" .. secOff
end

local function loadBehaviors(data, primaryOff, secondaryOff, used)
  local primary = parseTileset(data, primaryOff)
  local secondary = parseTileset(data, secondaryOff)
  local behavior, layerType, tiles = {}, {}, {}
  if not (primary and secondary) then return behavior, layerType, tiles, false end
  local overworldAnim = false
  for mid = 0, ATLAS_METATILES - 1 do
    local ts, localId
    if mid < PRIMARY_METATILES then
      ts, localId = primary, mid
    else
      ts, localId = secondary, mid - PRIMARY_METATILES
    end
    if ts and ts.attrOff then
      local attr = GbaBin.u16(data, ts.attrOff + localId * 2)
      local b = RomExtractorGen3.attrBehavior(attr)
      behavior[mid] = b
      if (not used or used[mid]) and (b == 0x02 or b == 0x03 or b == 0x07
          or b == 0x10 or b == 0x15 or b == 0x24) then
        overworldAnim = true
      end
      local layer = RomExtractorGen3.attrLayerType(attr)
      if layer ~= 0 then layerType[mid] = layer end
    end
    local row = metatileTiles(data, ts, mid)
    if row then
      local ids = {}
      for i = 0, 7 do ids[i + 1] = row[i] % 1024 end
      tiles[mid] = ids
    end
  end
  return behavior, layerType, tiles, overworldAnim
end

function RomExtractorGen3.decodeHoenn(data)
  local found, err = RomExtractorGen3.findMapGroups(data)
  if not found then return nil, err end
  local maps = {}
  local pairsByKey = {}
  local pairOrder = {}
  local startId
  for gi, headers in ipairs(found.groups) do
    local group = gi - 1
    for mi, header in ipairs(headers) do
      local index = mi - 1
      local layout, layoutErr = parseLayout(data, header.layoutOff)
      if layout then
        local key = pairKey(layout.primaryOff, layout.secondaryOff)
        local pair = pairsByKey[key]
        if not pair then
          pair = {
            primaryOff = layout.primaryOff,
            secondaryOff = layout.secondaryOff,
            used = {},
          }
          pairsByKey[key] = pair
          pairOrder[#pairOrder + 1] = pair
          pair.id = "pair_" .. (#pairOrder - 1)
        end
        for i = 1, #layout.grid do
          pair.used[layout.grid[i] % (MAP_CELL_METATILE + 1)] = true
        end
        if layout.border then
          for i = 1, #layout.border do
            pair.used[layout.border[i] % (MAP_CELL_METATILE + 1)] = true
          end
        end
        local id = RomExtractorGen3.mapId(group, index)
        local sx, sy = pickSpawn(layout.grid, layout.width, layout.height)
        local isStart = group == found.startGroup and index == found.startIndex
        if isStart then startId = id end
        maps[id] = {
          id = id,
          name = isStart and RomExtractorGen3.LITTLEROOT_NAME or id,
          group = group,
          index = index,
          width = layout.width,
          height = layout.height,
          music = header.music,
          layoutId = header.layoutId,
          mapType = header.mapType,
          weather = header.weather,
          regionMapSectionId = header.regionMapSectionId,
          cave = header.cave,
          tileset = pair.id,
          spawn = { x = sx, y = sy },
          grid = layout.grid,
          border = layout.border,
          warps = parseWarps(data, header.eventsOff),
          objects = parseObjects(data, header.eventsOff),
          bgEvents = parseBgEvents(data, header.eventsOff),
          coordEvents = parseCoordEvents(data, header.eventsOff),
          mapScripts = RomExtractorGen3.parseMapScripts(data, header.scriptsOff),
          connections = parseConnections(data, header.connectionsOff),
        }
      elseif group == found.startGroup and index == found.startIndex then
        return nil, layoutErr or "start map layout is unreadable"
      end
    end
  end
  if not startId then return nil, "start map was not decoded" end
  local usedLayoutIds = {}
  for _, map in pairs(maps) do
    local lid = tonumber(map.layoutId)
    if lid then usedLayoutIds[lid] = true end
  end
  local extraLayouts = {}
  local layoutsOff = RomExtractorGen3.findMapLayouts(data, found)
  if layoutsOff then
    for id = 1, MAX_MAP_LAYOUTS do
      local _, lo = romPtr(data, layoutsOff + (id - 1) * 4)
      if not lo then break end
      local layout = parseLayout(data, lo)
      if not layout then break end
      local key = pairKey(layout.primaryOff, layout.secondaryOff)
      local pair = pairsByKey[key]
      if not pair then
        pair = {
          primaryOff = layout.primaryOff,
          secondaryOff = layout.secondaryOff,
          used = {},
        }
        pairsByKey[key] = pair
        pairOrder[#pairOrder + 1] = pair
        pair.id = "pair_" .. (#pairOrder - 1)
      end
      for i = 1, #layout.grid do
        pair.used[layout.grid[i] % (MAP_CELL_METATILE + 1)] = true
      end
      if layout.border then
        for i = 1, #layout.border do
          pair.used[layout.border[i] % (MAP_CELL_METATILE + 1)] = true
        end
      end
      if not usedLayoutIds[id] then
        extraLayouts[id] = {
          width = layout.width,
          height = layout.height,
          grid = layout.grid,
          border = layout.border,
          tileset = pair.id,
        }
      end
    end
  end
  return {
    start = startId,
    maps = maps,
    pairs = pairOrder,
    layouts = extraLayouts,
    startGroup = found.startGroup,
    startIndex = found.startIndex,
    mapCount = (function()
      local n = 0
      for _ in pairs(maps) do n = n + 1 end
      return n
    end)(),
  }
end

function RomExtractorGen3:extractHeader()
  self:beginStage("Header")
  local header, err = GbaHeader.parse(self.data)
  if not header then error(err or "not a GBA ROM") end
  self.header = header
  self:tick("Header", 1, 1)
  return header
end

function RomExtractorGen3:extractPokemon()
  self:beginStage("Pokemon")
  local names, err = RomExtractorGen3.decodeSpeciesNames(self.data)
  if not names then error(err) end
  local named = 0
  local byIndex = {}
  for index = 0, NAMED_SPECIES - 1 do
    local name = names[index] or ""
    if not GbaText.isBlankName(name) then named = named + 1 end
    byIndex[index] = { id = index, name = name }
  end
  local statsOff = BattleData.findBaseStats(self.data)
  local stats = statsOff and BattleData.parseBaseStats(self.data, statsOff)
  if stats then
    for index = 0, NAMED_SPECIES - 1 do
      local row = byIndex[index]
      local st = stats.byIndex[index]
      if row and st then
        row.hp, row.atk, row.def = st.hp, st.atk, st.def
        row.spe, row.spa, row.spd = st.spe, st.spa, st.spd
        row.type1, row.type2 = st.type1, st.type2
        row.catchRate, row.expYield = st.catchRate, st.expYield
        row.growthRate = st.growthRate
        row.genderRatio = st.genderRatio
        row.eggCycles = st.eggCycles
        row.eggGroup1, row.eggGroup2 = st.eggGroup1, st.eggGroup2
        row.ability1, row.ability2 = st.ability1, st.ability2
      end
    end
  end
  local Dex = require("src.import.RomExtractorGen3Dex")
  local dex = Dex.apply(self.data, byIndex)
  self:tick("Pokemon", NAMED_SPECIES, NAMED_SPECIES)
  return {
    names = names,
    byIndex = byIndex,
    count = NAMED_SPECIES,
    named = named,
    statsOffset = statsOff,
    dexOffset = dex and dex.entries and dex.entries.offset,
    hoennDexOffset = dex and dex.maps and dex.maps.hoennOff,
  }
end

function RomExtractorGen3:extractMaps()
  self:beginStage("Maps")
  local hoenn, err = RomExtractorGen3.decodeHoenn(self.data)
  if not hoenn then error(err) end
  local tilesets = {
    atlasCols = ATLAS_COLS,
    atlasRows = ATLAS_ROWS,
    tileSize = METATILE_PX,
    byId = {},
  }
  local total = hoenn.mapCount + #hoenn.pairs
  local done = 0
  for _, pair in ipairs(hoenn.pairs) do
    local bottom, top = RomExtractorGen3.renderTilesetPair(
      self.data, pair.primaryOff, pair.secondaryOff, pair.used)
    if not bottom then error(top or "could not render a tileset pair") end
    local id = pair.id
    local bottomPath = RomExtractorGen3.tilesetPath(id, "bottom")
    local topPath = RomExtractorGen3.tilesetPath(id, "top")
    ImageWriter.save(bottom, bottomPath)
    ImageWriter.save(top, topPath)
    local behavior, layerType, tiles, overworldAnim = loadBehaviors(
      self.data, pair.primaryOff, pair.secondaryOff, pair.used)
    tilesets.byId[id] = {
      id = id,
      bottom = bottomPath,
      top = topPath,
      behavior = behavior,
      layerType = layerType,
      tiles = tiles,
      overworldAnim = overworldAnim or nil,
    }
    done = done + 1
    self:tick("Maps", done, total)
  end
  self:tick("Maps", total, total)
  return {
    start = hoenn.start,
    atlasCols = ATLAS_COLS,
    tileSize = METATILE_PX,
    maps = hoenn.maps,
    mapCount = hoenn.mapCount,
    tilesetCount = #hoenn.pairs,
    tilesets = tilesets,
    layouts = hoenn.layouts,
  }
end

function RomExtractorGen3:extractSprites(maps)
  self:beginStage("Sprites")
  local graphics, gErr = RomExtractorGen3.findObjectEventGraphics(self.data)
  if not graphics then error(gErr) end
  local pals, pErr = RomExtractorGen3.findObjectEventPalettes(self.data, graphics)
  if not pals then error(pErr) end
  local ids = RomExtractorGen3.collectGraphicsIds(maps and maps.maps)
  local byId = {}
  local count = 0
  for i = 1, #ids do
    local gid = ids[i]
    local info = graphics.byId[gid]
    local palOff = info and (pals.byTag[info.paletteTag]
      or pals.byTag[PAL_TAG_MIN + 3]
      or pals.byTag[PAL_TAG_MIN])
    if info and palOff then
      local poses = RomExtractorGen3.parseOwAnims(self.data, info.animsOff)
      local need = RomExtractorGen3.maxAnimFrame(poses) + 1
      local have = info.frameCount or 1
      local frameCount = have
      if need > 1 then
        frameCount = math.min(have, math.max(need, 1))
      end
      local image, err = RomExtractorGen3.renderOwSheet(
        self.data, info, palOff, frameCount)
      if not image then error(err or ("could not render ow_" .. gid)) end
      local path = RomExtractorGen3.spritePath(gid)
      ImageWriter.save(image, path)
      byId[gid] = {
        id = gid,
        path = path,
        width = info.width,
        height = info.height,
        frameCount = frameCount,
        face = poses.face,
        walk = poses.walk,
      }
      count = count + 1
    end
    self:tick("Sprites", i, #ids)
  end
  if not byId[PLAYER_GFX_ID] then
    error("player overworld sprite (ow_0) was not extracted")
  end
  if not byId[61] or not byId[62] then
    error("berry tree stage sprites (ow_61/ow_62) were not extracted")
  end
  if not byId[191] or not byId[192] then
    error("watering sprites (ow_191/ow_192) were not extracted")
  end
  self:tick("Sprites", #ids, #ids)
  return {
    playerGraphicsId = PLAYER_GFX_ID,
    count = count,
    byId = byId,
    emotes = self:extractEmotes(),
  }
end

function RomExtractorGen3:extractUi()
  self:beginStage("Fonts")
  local off = RomExtractorGen3.findLatinFont3(self.data)
  if not off then error("latin FONT3 (8x16 4bpp) was not found") end
  local image, err = RomExtractorGen3.renderFont3Sheet(self.data, off)
  if not image then error(err or "could not render latin FONT3") end
  local path = RomExtractorGen3.fontPath()
  ImageWriter.save(image, path)
  local widthOff = RomExtractorGen3.findFont3Widths(self.data)
  local widths = widthOff and RomExtractorGen3.readFont3Widths(self.data, widthOff)
  self:tick("Fonts", 1, 2)
  -- Menu/battle window chrome shares this stage: it is the same "draw text
  -- somewhere" surface and costs one more pass over the cart.
  local ui = Gen3Ui.extract(self.data)
  self:tick("Fonts", 2, 2)
  return {
    image = path,
    glyphW = FONT_W,
    glyphH = FONT_H,
    cols = FONT_COLS,
    count = FONT_GLYPHS,
    offset = off,
    kind = "font3",
    widths = widths,
    widthOffset = widthOff,
  }, ui
end

function RomExtractorGen3:extractBattle()
  self:beginStage("Battle")
  local wildOff = BattleData.findWildMonHeaders(self.data)
  if not wildOff then error("gWildMonHeaders not found") end
  local encounters = BattleData.parseWildHeaders(self.data, wildOff)
  if not encounters then error("wild encounter table is unreadable") end
  local evoOff, evoStride = BattleData.findEvolutionTable(self.data)
  local evolutions = evoOff and BattleData.parseEvolutions(self.data, evoOff, evoStride)
  local trainers
  local trainerOff, classOff = BattleData.findTrainerTable(self.data)
  if trainerOff then
    trainers = BattleData.parseTrainers(self.data, trainerOff, classOff)
  end
  local itemOff = BattleData.findItemTable(self.data)
  local items = itemOff and BattleData.parseItems(self.data, itemOff)
  local frontOff, backOff, palOff = BattleData.findPicTables(self.data)
  if not (frontOff and backOff and palOff) then
    error("pokemon pic tables not found")
  end
  local used = BattleData.collectSpecies(encounters, evolutions, trainers)
  local ids = {}
  for species in pairs(used) do ids[#ids + 1] = species end
  table.sort(ids)
  local fronts, backs = {}, {}
  for i = 1, #ids do
    local species = ids[i]
    local image, err = BattleData.renderMonPic(
      self.data, frontOff + species * 8, palOff + species * 8)
    if not image then
      if species == BattleData.STARTER_SPECIES then
        error(err or "could not render Torchic's front pic")
      end
    else
      local path = BattleData.frontPath(species)
      ImageWriter.save(image, path)
      fronts[species] = path
    end
    local back, backErr = BattleData.renderMonPic(
      self.data, backOff + species * 8, palOff + species * 8)
    if not back then
      if species == BattleData.STARTER_SPECIES then
        error(backErr or "could not render Torchic's back pic")
      end
    else
      local path = BattleData.backPath(species)
      ImageWriter.save(back, path)
      backs[species] = path
    end
    self:tick("Battle", i, #ids)
  end
  if not fronts[BattleData.STARTER_SPECIES] then
    error("starter front pic was not extracted")
  end
  if not backs[BattleData.STARTER_SPECIES] then
    error("starter back pic was not extracted")
  end
  local frontCoordOff, backCoordOff = BattleData.findPicCoords(self.data)
  local frontY = frontCoordOff and BattleData.parsePicCoords(self.data, frontCoordOff)
  local backY = backCoordOff and BattleData.parsePicCoords(self.data, backCoordOff)
  local battleBgs = BattleData.extractEnvironments(self.data)
  local namesOff, dataOff = BattleData.findMoveTables(self.data)
  if not (namesOff and dataOff) then error("move tables not found") end
  local moves = BattleData.parseMoves(self.data, namesOff, dataOff)
  if not moves then error("move data is unreadable") end
  local chartOff = BattleData.findTypeChart(self.data)
  if not chartOff then error("type effectiveness table not found") end
  moves.typeChart = BattleData.parseTypeChart(self.data, chartOff)
  local learnOff = BattleData.findLearnsets(self.data)
  if not learnOff then error("level-up learnsets not found") end
  local learnsets = BattleData.parseLearnsets(self.data, learnOff)
  local tmhmOff = BattleData.findTmhmLearnsets(self.data)
  if not tmhmOff then error("TM/HM learnsets not found") end
  local tmhmLearnsets = BattleData.parseTmhmLearnsets(self.data, tmhmOff)
  self:tick("Battle", #ids, #ids)
  return {
    starterSpecies = BattleData.STARTER_SPECIES,
    encounterCount = encounters.count,
    frontCount = (function()
      local n = 0
      for _ in pairs(fronts) do n = n + 1 end
      return n
    end)(),
    byMap = encounters.byMap,
    fronts = fronts,
    backs = backs,
    frontY = frontY,
    backY = backY,
    bgs = battleBgs,
    moves = moves,
    learnsets = learnsets,
    tmhmLearnsets = tmhmLearnsets,
    evolutions = evolutions,
    trainers = trainers,
    items = items,
  }
end

function RomExtractorGen3:extractAudio()
  self:beginStage("Audio")
  local audio = Gen3Audio.extract(self.data)
  if not audio then error("the MP2K song table was not found") end
  self:tick("Audio", 1, 1)
  return audio
end

-- Mon icons and party menu chrome share a stage: both are menu furniture
-- and the icons are what the party screen puts in its boxes.
function RomExtractorGen3:extractMenus()
  self:beginStage("Menus")
  local icons = Gen3Icons.extract(self.data)
  if not icons then error("gMonIconTable was not found") end
  self:tick("Menus", 1, 2)
  local party = Gen3Party.extract(self.data)
  if not party then error("the party menu graphics group was not found") end
  self:tick("Menus", 2, 2)
  return { icons = icons, party = party }
end

function RomExtractorGen3:run()
  local header = self:extractHeader()
  local pokemon = self:extractPokemon()
  local maps = self:extractMaps()
  local sprites = self:extractSprites(maps)
  local font, ui = self:extractUi()
  local battle = self:extractBattle()
  local audio = self:extractAudio()
  local menus = self:extractMenus()
  self:beginStage("Cache")
  self:write("header", {
    title = header.title,
    gameCode = header.gameCode,
    maker = header.maker,
    version = header.version,
    sha1 = self.romSha1,
    generation = 3,
    engine = "gen3",
  })
  self:write("constants", {
    generation = 3,
    engine = "gen3",
    screenWidth = 240,
    screenHeight = 160,
    tileSize = 16,
    gameCode = header.gameCode,
    title = header.title,
    speciesCount = pokemon.count,
    namedSpecies = pokemon.named,
    startMap = maps.start,
    mapCount = maps.mapCount,
    tilesetCount = maps.tilesetCount,
    spriteCount = sprites.count,
    encounterCount = battle.encounterCount,
    starterSpecies = battle.starterSpecies,
    battleFrontCount = battle.frontCount,
    moveCount = battle.moves and battle.moves.count or 0,
    trainerCount = battle.trainers and battle.trainers.count or 0,
    itemCount = battle.items and battle.items.named or 0,
    resetMapFlags = RomExtractorGen3.findResetMapFlags(self.data),
  })
  if battle.learnsets then
    for index = 0, pokemon.count - 1 do
      local row = pokemon.byIndex[index]
      if row then row.learnset = battle.learnsets[index] or {} end
    end
  end
  if battle.evolutions then
    for index = 0, pokemon.count - 1 do
      local row = pokemon.byIndex[index]
      if row then row.evolutions = battle.evolutions[index] or {} end
    end
  end
  if battle.tmhmLearnsets then
    for index = 0, pokemon.count - 1 do
      local row = pokemon.byIndex[index]
      if row then row.tmhm = battle.tmhmLearnsets[index] end
    end
  end
  if maps.maps then
    for _, map in pairs(maps.maps) do
      local objects = map.objects or {}
      for i = 1, #objects do
        local o = objects[i]
        if o and o.scriptOff then
          if (o.trainerType or 0) > 0 and battle.trainers then
            local id = BattleData.readTrainerIdFromScript(self.data, o.scriptOff)
            local tr = id and battle.trainers.byId and battle.trainers.byId[id]
            if tr then
              o.trainerId = id
              o.trainerName = tr.name
              o.trainerClass = tr.className
              o.doubleBattle = tr.doubleBattle
              o.party = tr.party
              o.items = tr.items
            end
          end
          local give = BattleData.readItemGiveFromScript(self.data, o.scriptOff)
          if give then
            o.itemId = give.id
            o.itemCount = give.count
          end
          local mart = BattleData.readMartFromScript(self.data, o.scriptOff)
          if mart and #mart > 0 then o.mart = mart end
        end
      end
      RomExtractorGen3.bakeMapScripts(self.data, map)
    end
  end
  self:write("pokemon", pokemon)
  local tilesets = maps.tilesets
  maps.tilesets = nil
  local layouts = maps.layouts
  maps.layouts = nil
  self:writeMapPack(maps)
  if type(layouts) == "table" and next(layouts) then
    self:write("layouts", { byId = layouts })
  end
  self:write("tilesets", tilesets)
  self:write("sprites", sprites)
  self:write("font", font)
  self:write("ui", ui or {})
  self:write("audio", audio)
  self:write("menus", menus)
  self:write("encounters", {
    starterSpecies = battle.starterSpecies,
    count = battle.encounterCount,
    byMap = battle.byMap,
    fronts = battle.fronts,
    backs = battle.backs,
    frontY = battle.frontY,
    backY = battle.backY,
    bgs = battle.bgs,
  })
  self:write("moves", battle.moves)
  self:write("trainers", battle.trainers or { byId = {}, count = 0 })
  self:write("items", battle.items or { byId = {}, count = 0, named = 0 })
  self:write("title", BootData.extract(self.data))
  self:tick("Cache", 1, 1)
end

return RomExtractorGen3
