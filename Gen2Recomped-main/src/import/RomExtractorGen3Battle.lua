-- Ruby battle tables: gBaseStats, gWildMonHeaders, LZ77 pics,
-- gBattleMoves, type chart, level-up learnsets.
-- Nintendo assets stay out of git -- extract at import time.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local GbaText = require("src.import.GbaText")
local ImageWriter = require("src.import.ImageWriter")
local GbaHeader = require("src.import.GbaHeader")
local SapphireOff = require("src.import.RomExtractorGen3Sapphire")

local Battle = {}

Battle.SPECIES_COUNT = 412
Battle.BASE_STATS_SIZE = 0x1C
Battle.PIC_PX = 64
Battle.PIC_BYTES = 2048
Battle.PAL_BYTES = 32
Battle.LAND_SLOTS = 12
Battle.WATER_SLOTS = 5
Battle.ROCK_SLOTS = 5
Battle.FISH_SLOTS = 10
Battle.STARTER_SPECIES = 280 -- Torchic, Ruby's fire starter
-- ANIM_TAG_GOLD_STARS = ANIM_SPRITES_START(10000)+233; sheet is 0xC0 bytes
-- (6 tiles = 16x24). Used by TryShinyAnimation send-out sparkles.
Battle.GOLD_STARS_TAG = 10233
Battle.GOLD_STARS_BYTES = 0xC0
Battle.GOLD_STARS_W = 16
Battle.GOLD_STARS_H = 24
Battle.POKERUBY_GOLD_STARS =
  "misc/pokeruby-master/pokeruby-master/graphics/battle_anims/sprites/233.png"
Battle.FRONT_PICS = 0x1E8354
Battle.BACK_PICS = 0x1E97F4
Battle.FRONT_COORDS = 0x1E7C74
Battle.BACK_COORDS = 0x1E9114
Battle.ENV_COUNT = 10
Battle.STARTERS = { 277, 280, 283 }
Battle.TILE_BYTES = 32
Battle.MOVE_COUNT = 355
Battle.MOVE_SIZE = 12
Battle.MOVE_NAME_LENGTH = 13
Battle.EVOS_PER_MON = 5
Battle.EVO_SIZE = 8
Battle.EVO_LEVEL = 4
Battle.EVO_LEVEL_SILCOON = 11
Battle.EVO_LEVEL_CASCOON = 12
Battle.TRAINER_SIZE = 40
Battle.TRAINER_COUNT = 0x2B6
Battle.TRAINER_NAME_LENGTH = 12
Battle.TRAINER_CLASS_COUNT = 58
Battle.TRAINER_CLASS_NAME_LENGTH = 13
Battle.TRAINERBATTLE_CMD = 0x5C
Battle.SETVAR_CMD = 0x16
Battle.SETORCOPYVAR_CMD = 0x1A
Battle.CALLSTD_CMD = 0x09
Battle.POKEMART_CMD = 0x86
Battle.VAR_0x8000 = 0x8000
Battle.VAR_0x8001 = 0x8001
Battle.ITEM_SIZE = 44
Battle.ITEM_NAME_LENGTH = 14
Battle.ITEM_COUNT = 349
Battle.ITEM_POKE_BALL = 4
Battle.ITEM_POTION = 13
Battle.ABILITY_OVERGROW = 65
Battle.ABILITY_BLAZE = 66
Battle.ABILITY_TORRENT = 67
Battle.ITEM_TM01 = 289
Battle.TMHM_COUNT = 58
-- pokeruby TMHMMoves[] in party_menu.c: TM01..TM50 then HM01..HM08.
Battle.TMHM_MOVES = {
  264, 337, 352, 347, 46, 92, 258, 339, 331, 237,
  241, 269, 58, 59, 63, 113, 182, 240, 202, 219,
  218, 76, 231, 85, 87, 89, 216, 91, 94, 247,
  280, 104, 115, 351, 53, 188, 201, 126, 317, 332,
  259, 263, 290, 156, 213, 168, 211, 285, 289, 315,
  15, 19, 57, 70, 148, 249, 127, 291,
}

local function packTmhmBits(bits)
  local lo, hi = 0, 0
  for i = 1, #bits do
    local b = bits[i]
    if b < 32 then lo = lo + 2 ^ b else hi = hi + 2 ^ (b - 32) end
  end
  return lo, hi
end

-- Torchic: TM06/10/11/17/21/27/28/32/35/38/39/40/42-45/50, HM01/04/06.
Battle.TORCHIC_TMHM0, Battle.TORCHIC_TMHM1 = packTmhmBits({
  5, 9, 10, 16, 20, 26, 27, 31, 34, 37, 38, 39, 41, 42, 43, 44, 49, 50, 53, 55,
})

-- US Ruby 1.0 (AXVE rev 0).  find* still scans so fixture ROMs work.
-- Front table is 412*8 bytes and ends at 0x1E9034; back coords sit next,
-- then gMonBackPicTable at 0x1E97F4 (pokeruby back_pic_table.inc).
local RUBY_US = {
  baseStats = 0x1FEC18,
  frontPics = 0x1E8354,
  frontCoords = 0x1E7C74,
  backCoords = 0x1E9114,
  backPics = 0x1E97F4,
  palettes = 0x1EA5B4,
  -- gMonShinyPaletteTable (US Ruby 1.0); normal table is 412*8 then a gap.
  shinyPalettes = 0x1EB374,
  -- gBattleAnimSpriteSheet_233 / Palette_233 (ANIM_TAG_GOLD_STARS).
  goldStarsGfx = 0xD28910,
  goldStarsPal = 0xD28994,
  wildHeaders = 0x39D454,
  moveNames = 0x1F8320,
  moveData = 0x1FB12C,
  typeChart = 0x1F9720,
  learnsets = 0x207BC8,
  tmhmLearnsets = nil, -- findTmhmLearnsets scans; 0x207BC8 is level-up pointers
  evolutions = 0x203B68,
  trainers = 0x1F04FC,
  trainerClasses = 0x1F0208,
  items = 0x3C5564,
  environmentTable = 0x1F95AC,
}
Battle.RUBY_US = RUBY_US

function Battle.us(data)
  return GbaHeader.mergeUs(data, RUBY_US, SapphireOff.Battle)
end

-- Overlay keys when present, else the Ruby module constants.
local function usOff(data, key)
  local v = Battle.us(data)[key]
  if type(v) == "number" then return v end
  return Battle[key]
end


local function romPtr(data, offset)
  local ptr = GbaBin.u32(data, offset)
  if not GbaBin.isRomPtr(ptr, #data) then return nil end
  return ptr, GbaBin.romOffset(ptr)
end

function Battle.frontPath(species)
  return ("assets/generated/battle/front/%d.png"):format(species)
end

function Battle.backPath(species)
  return ("assets/generated/battle/back/%d.png"):format(species)
end

function Battle.frontShinyPath(species)
  return ("assets/generated/battle/front_shiny/%d.png"):format(species)
end

function Battle.backShinyPath(species)
  return ("assets/generated/battle/back_shiny/%d.png"):format(species)
end

function Battle.goldStarsPath()
  return "assets/generated/battle/gold_stars.png"
end

function Battle.isStarter(species)
  local list = Battle.STARTERS
  for i = 1, #list do
    if list[i] == species then return true end
  end
  return false
end

function Battle.parseOneStats(data, offset)
  if type(data) ~= "string" or offset + Battle.BASE_STATS_SIZE > #data then
    return nil
  end
  -- pokeruby BaseStats: u16 bitfields at +0x0A, 2 bits per stat
  -- (HP, Atk, Def, Spe, SpA, SpD), then item1/item2 at +0x0C/+0x0E.
  local evWord = GbaBin.u16(data, offset + 10)
  return {
    hp = GbaBin.u8(data, offset),
    atk = GbaBin.u8(data, offset + 1),
    def = GbaBin.u8(data, offset + 2),
    spe = GbaBin.u8(data, offset + 3),
    spa = GbaBin.u8(data, offset + 4),
    spd = GbaBin.u8(data, offset + 5),
    type1 = GbaBin.u8(data, offset + 6),
    type2 = GbaBin.u8(data, offset + 7),
    catchRate = GbaBin.u8(data, offset + 8),
    expYield = GbaBin.u8(data, offset + 9),
    evYieldHp = evWord % 4,
    evYieldAtk = math.floor(evWord / 4) % 4,
    evYieldDef = math.floor(evWord / 16) % 4,
    evYieldSpe = math.floor(evWord / 64) % 4,
    evYieldSpa = math.floor(evWord / 256) % 4,
    evYieldSpd = math.floor(evWord / 1024) % 4,
    genderRatio = GbaBin.u8(data, offset + 16),
    eggCycles = GbaBin.u8(data, offset + 17),
    friendship = GbaBin.u8(data, offset + 18),
    growthRate = GbaBin.u8(data, offset + 19),
    eggGroup1 = GbaBin.u8(data, offset + 20),
    eggGroup2 = GbaBin.u8(data, offset + 21),
    ability1 = GbaBin.u8(data, offset + 22),
    ability2 = GbaBin.u8(data, offset + 23),
    safariFleeRate = GbaBin.u8(data, offset + 24),
    -- struct BaseStats 0x19: bodyColor is the low 7 bits, noFlip the top.
    -- The Pokedex COLOR search reads it and had nothing to read before.
    bodyColor = GbaBin.u8(data, offset + 25) % 128,
    noFlip = math.floor(GbaBin.u8(data, offset + 25) / 128) == 1,
  }
end

function Battle.parseBaseStats(data, offset)
  if type(data) ~= "string" then return nil end
  local byIndex = {}
  for i = 0, Battle.SPECIES_COUNT - 1 do
    local row = Battle.parseOneStats(data, offset + i * Battle.BASE_STATS_SIZE)
    if not row then return nil end
    byIndex[i] = row
  end
  return { offset = offset, byIndex = byIndex }
end

function Battle.findBaseStats(data)
  if type(data) ~= "string" then return nil end
  if Battle.parseOneStats(data, Battle.us(data).baseStats + Battle.BASE_STATS_SIZE)
      and GbaBin.u8(data, Battle.us(data).baseStats + Battle.BASE_STATS_SIZE) == 45 then
    return Battle.us(data).baseStats
  end
  local needle = string.char(45, 49, 49, 45, 65, 65, 12, 3)
  local search = 1
  while true do
    local at = data:find(needle, search, true)
    if not at then return nil end
    local bulba = at - 1
    local start = bulba - Battle.BASE_STATS_SIZE
    if start >= 0 then
      local ivy = bulba + Battle.BASE_STATS_SIZE
      local noneOk = true
      for i = 0, Battle.BASE_STATS_SIZE - 1 do
        if GbaBin.u8(data, start + i) ~= 0 then noneOk = false; break end
      end
      if noneOk and GbaBin.u8(data, ivy) == 60 and GbaBin.u8(data, ivy + 1) == 62 then
        return start
      end
    end
    search = at + 1
  end
end

local function parseMons(data, infoOff, slots)
  if not infoOff then return nil end
  local _, monsOff = romPtr(data, infoOff + 4)
  if not monsOff then return nil end
  local list = {}
  for i = 0, slots - 1 do
    local o = monsOff + i * 4
    list[#list + 1] = {
      minLevel = GbaBin.u8(data, o),
      maxLevel = GbaBin.u8(data, o + 1),
      species = GbaBin.u16(data, o + 2),
    }
  end
  return {
    rate = GbaBin.u8(data, infoOff),
    slots = list,
  }
end

local function parseWildKind(data, headerOff, field, slots)
  local _, infoOff = romPtr(data, headerOff + field)
  if not infoOff then return nil end
  return parseMons(data, infoOff, slots)
end

function Battle.parseWildHeader(data, offset)
  if type(data) ~= "string" or offset + 20 > #data then return nil end
  local group = GbaBin.u8(data, offset)
  local mapNum = GbaBin.u8(data, offset + 1)
  if group == 0xFF then return nil, true end
  if group > 40 then return nil end
  return {
    mapGroup = group,
    mapNum = mapNum,
    land = parseWildKind(data, offset, 4, Battle.LAND_SLOTS),
    water = parseWildKind(data, offset, 8, Battle.WATER_SLOTS),
    rock = parseWildKind(data, offset, 12, Battle.ROCK_SLOTS),
    fish = parseWildKind(data, offset, 16, Battle.FISH_SLOTS),
  }
end

function Battle.parseWildHeaders(data, offset)
  local byMap = {}
  local count = 0
  for i = 0, 511 do
    local row, term = Battle.parseWildHeader(data, offset + i * 20)
    if term then break end
    if not row then break end
    local id = ("g%d_%d"):format(row.mapGroup, row.mapNum)
    byMap[id] = row
    count = count + 1
  end
  if count < 1 then return nil end
  return { offset = offset, count = count, byMap = byMap }
end

local function looksLikeWildTable(data, offset)
  local first = Battle.parseWildHeader(data, offset)
  -- Both RS tables start at Littleroot (group 0, map 0). A mid-table
  -- hit can still contain Route 101/Zigzagoon later, so the first row
  -- has to be the real start.
  if not first or first.mapGroup ~= 0 or first.mapNum ~= 0 then
    return false
  end
  local pack = Battle.parseWildHeaders(data, offset)
  if not pack then return false end
  local route = pack.byMap.g0_16
  if not (route and route.land and route.land.slots and route.land.slots[1]) then
    return false
  end
  return route.land.slots[1].species == 290
end

function Battle.findWildMonHeaders(data)
  if type(data) ~= "string" then return nil end
  if looksLikeWildTable(data, Battle.us(data).wildHeaders) then
    return Battle.us(data).wildHeaders
  end
  local needle = string.char(0, 16, 0, 0)
  local search = 1
  while true do
    local at = data:find(needle, search, true)
    if not at then return nil end
    local off = at - 1
    local land = GbaBin.u32(data, off + 4)
    if GbaBin.isRomPtr(land, #data) then
      local start = off
      while start >= 20 do
        local prev = start - 20
        local g = GbaBin.u8(data, prev)
        if g == 0xFF or g > 40 then break end
        local p = GbaBin.u32(data, prev + 4)
        if p ~= 0 and not GbaBin.isRomPtr(p, #data) then break end
        start = prev
      end
      if looksLikeWildTable(data, start) then return start end
    end
    search = at + 1
  end
end

local function picEntryOk(data, offset)
  local size = GbaBin.u16(data, offset + 4)
  if size ~= Battle.PIC_BYTES then return false end
  local _, picOff = romPtr(data, offset)
  if not picOff then return false end
  local raw = GbaLz77.decompress(data, picOff)
  return raw ~= nil and #raw == Battle.PIC_BYTES
end

function Battle.findPicTables(data)
  if type(data) ~= "string" then return nil end
  local front, back, pal = Battle.us(data).frontPics, Battle.us(data).backPics, Battle.us(data).palettes
  local shinyPal = Battle.us(data).shinyPalettes
  if picEntryOk(data, front + 8) and picEntryOk(data, back + 8) then
    local fp = GbaBin.u32(data, front + 8)
    local bp = GbaBin.u32(data, back + 8)
    if fp ~= bp then
      return front, back, pal, shinyPal
    end
  end
  return nil
end

function Battle.parsePicCoords(data, offset, count)
  if type(data) ~= "string" or type(offset) ~= "number" then return nil end
  count = count or Battle.SPECIES_COUNT
  if offset + count * 4 > #data then return nil end
  local y = {}
  for i = 0, count - 1 do
    y[i] = GbaBin.u8(data, offset + i * 4 + 1)
  end
  return y
end

function Battle.findPicCoords(data)
  if type(data) ~= "string" then return nil end
  local front, back = Battle.us(data).frontCoords, Battle.us(data).backCoords
  if GbaBin.u8(data, front) == 136 and GbaBin.u8(data, front + 4) == 69
      and GbaBin.u8(data, back) == 136 then
    return front, back
  end
  return nil
end

-- 5 bits per channel: 31 is full brightness, so the scale is /31, not *8.
-- Multiplying by 8 caps every channel at 248/255 and quietly darkens all
-- of it -- the bag's yellow came out F8C058 where the cart is FFC55A.
local function bgr555(c)
  return (c % 32) / 31,
    (math.floor(c / 32) % 32) / 31,
    (math.floor(c / 1024) % 32) / 31
end

local function blitTile(image, x, y, raw, palette, hflip, vflip)
  if not raw or #raw < Battle.TILE_BYTES or not image then return end
  local iw = (image.getWidth and image:getWidth()) or image.width or 240
  local ih = (image.getHeight and image:getHeight()) or image.height or 160
  for ty = 0, 7 do
    local py = y + ty
    if py >= 0 and py < ih then
      for tx = 0, 7 do
        local px = x + tx
        if px >= 0 and px < iw then
          local sx = hflip and (7 - tx) or tx
          local sy = vflip and (7 - ty) or ty
          local byte = raw:byte(sy * 4 + math.floor(sx / 2) + 1) or 0
          local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
          if ci ~= 0 then
            local col = palette[ci] or { 1, 0, 1 }
            image:setPixel(px, py, col[1], col[2], col[3], 1)
          end
        end
      end
    end
  end
end

function Battle.renderMonPic(data, sheetOff, palOff)
  local _, picOff = romPtr(data, sheetOff)
  local _, palDataOff = romPtr(data, palOff)
  if not (picOff and palDataOff) then return nil, "pic pointers are not in ROM" end
  local raw, err = GbaLz77.decompress(data, picOff)
  if not raw or #raw < Battle.PIC_BYTES then
    return nil, err or "pic lz77 failed"
  end
  local palBytes, palErr = GbaLz77.decompress(data, palDataOff)
  if not palBytes or #palBytes < Battle.PAL_BYTES then
    return nil, palErr or "palette lz77 failed"
  end
  local pal = {}
  for c = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(palBytes, c * 2))
    pal[c] = { r, g, b }
  end
  local w = Battle.PIC_PX
  local image = ImageWriter.blank(w, w, 0, 0, 0, 0)
  local tw = w / 8
  local tiles = tw * tw
  for ti = 0, tiles - 1 do
    local col = ti % tw
    local row = math.floor(ti / tw)
    local start = ti * Battle.TILE_BYTES
    blitTile(image, col * 8, row * 8,
      raw:sub(start + 1, start + Battle.TILE_BYTES), pal)
  end
  return image
end

function Battle.bgPath(env)
  return ("assets/generated/battle/bg/%d.png"):format(env)
end

local function envRowPtrs(data, offset)
  local _, tiles = romPtr(data, offset)
  local _, map = romPtr(data, offset + 4)
  local _, pal = romPtr(data, offset + 16)
  if not (tiles and map and pal) then return nil end
  -- Tiles/map are LZ77. Palette is usually LZ77 too; a few rows store a
  -- raw 16-color bank. Accept either so PLAIN/BUILDING never drop out.
  if GbaBin.u8(data, tiles) ~= 0x10 then return nil end
  if GbaBin.u8(data, map) ~= 0x10 then return nil end
  local palByte = GbaBin.u8(data, pal)
  if palByte ~= 0x10 and palByte ~= 0x00 then
    -- raw palettes still have to look like 15-bit color words
    if (GbaBin.u16(data, pal) or 0) > 0x7FFF then return nil end
  end
  return tiles, map, pal
end

-- pokeruby sBattleEnvironmentTable: 10 rows of 5 pointers. PLAIN reuses
-- BUILDING tiles/map with a different palette.
local function looksLikeEnvTable(data, off)
  if type(off) ~= "number" then return false end
  local t8 = GbaBin.u32(data, off + 8 * 20)
  local t9 = GbaBin.u32(data, off + 9 * 20)
  if not (t8 == t9 and GbaBin.isRomPtr(t8, #data)) then return false end
  local p8 = GbaBin.u32(data, off + 8 * 20 + 16)
  local p9 = GbaBin.u32(data, off + 9 * 20 + 16)
  if p8 == p9 then return false end
  if not (envRowPtrs(data, off + 8 * 20)
      and envRowPtrs(data, off + 9 * 20)
      and envRowPtrs(data, off)) then
    return false
  end
  for i = 1, 7 do
    if not envRowPtrs(data, off + i * 20) then return false end
  end
  return true
end

function Battle.findEnvironmentTable(data)
  if type(data) ~= "string" then return nil end
  local hinted = Battle.us(data).environmentTable
  if looksLikeEnvTable(data, hinted) then return hinted end
  local span = Battle.ENV_COUNT * 20
  local last = #data - span
  for off = 0, last, 4 do
    if looksLikeEnvTable(data, off) then return off end
  end
end

function Battle.renderBattleBg(data, tilesOff, mapOff, palOff)
  local tiles = GbaLz77.decompress(data, tilesOff)
  local map = GbaLz77.decompress(data, mapOff)
  local palBytes = GbaLz77.decompress(data, palOff)
  if type(palBytes) ~= "string" or #palBytes < Battle.PAL_BYTES then
    palBytes = data:sub(palOff + 1, palOff + Battle.PAL_BYTES * 4)
  end
  if not (tiles and map and palBytes) then return nil end
  if #tiles < Battle.TILE_BYTES or #map < 2 then return nil end
  local pals = {}
  local palCount = math.min(4, math.floor(#palBytes / Battle.PAL_BYTES))
  for p = 0, palCount - 1 do
    local pal = {}
    for c = 0, 15 do
      local r, g, b = bgr555(GbaBin.u16(palBytes, p * Battle.PAL_BYTES + c * 2))
      pal[c] = { r, g, b }
    end
    pals[p] = pal
  end
  if not pals[0] then return nil end
  local mapW = 32
  local mapH = math.floor(#map / (mapW * 2))
  if mapH < 1 then mapH = 1 end
  if mapH > 32 then mapH = 32 end
  local image = ImageWriter.blank(240, 160, 0.45, 0.70, 0.52, 1)
  local maxTiles = math.floor(#tiles / Battle.TILE_BYTES)
  for ty = 0, 19 do
    if ty >= mapH then break end
    for tx = 0, 29 do
      local entry = GbaBin.u16(map, (ty * mapW + tx) * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        local hflip = math.floor(entry / 1024) % 2 == 1
        local vflip = math.floor(entry / 2048) % 2 == 1
        -- LoadCompressedPalette(..., 0x20, 0x60): terrain uses BG pal
        -- slots 2..4. The compressed file is those three banks in order.
        -- Mapping bank-1 sent ground tiles to the wrong row and baked the
        -- dark slatted slab into battle/bg/*.png.
        local bank = math.floor(entry / 4096) % 16
        local palIndex = bank - 2
        if palIndex < 0 then palIndex = 0 end
        local pal = pals[palIndex] or pals[0]
        local raw = tiles:sub(tid * Battle.TILE_BYTES + 1,
          (tid + 1) * Battle.TILE_BYTES)
        for py = 0, 7 do
          for px = 0, 7 do
            local sx = hflip and (7 - px) or px
            local sy = vflip and (7 - py) or py
            local byte = raw:byte(sy * 4 + math.floor(sx / 2) + 1)
            if byte then
              local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
              local col = pal[ci] or pal[0]
              if col then
                image:setPixel(tx * 8 + px, ty * 8 + py,
                  col[1], col[2], col[3], 1)
              end
            end
          end
        end
      end
    end
  end
  return image
end

function Battle.extractEnvironments(data)
  local bgs = {}
  local tableOff = Battle.findEnvironmentTable(data)
  if not tableOff then
    error("battle environment table not found")
  end
  for env = 0, Battle.ENV_COUNT - 1 do
    local tilesOff, mapOff, palOff = envRowPtrs(data, tableOff + env * 20)
    if not (tilesOff and mapOff and palOff) then
      error(("battle background %d pointers are invalid"):format(env))
    end
    local image = Battle.renderBattleBg(data, tilesOff, mapOff, palOff)
    if not image then
      error(("battle background %d did not render"):format(env))
    end
    local path = Battle.bgPath(env)
    ImageWriter.save(image, path)
    bgs[env] = path
    bgs[tostring(env)] = path
  end
  return bgs
end

-- ANIM_TAG_GOLD_STARS sheet for TryShinyAnimation. Prefer the same pokeruby
-- 233.png the engine falls back to; otherwise LZ77 the cart graphic so a
-- reimport without the decomp tree still keeps sparkle art in the cache.
function Battle.readPokerubyGoldStarsPng()
  local rel = Battle.POKERUBY_GOLD_STARS
  local bytes
  if love and love.filesystem and love.filesystem.read then
    bytes = love.filesystem.read(rel)
  end
  if type(bytes) ~= "string" or #bytes < 8 then
    local candidates = { rel }
    if love and love.filesystem and love.filesystem.getSource then
      local src = love.filesystem.getSource()
      if type(src) == "string" and src ~= "" then
        local base = src:gsub("[/\\]+$", "")
        candidates[#candidates + 1] = base .. "/" .. rel
        candidates[#candidates + 1] = base .. "\\" .. rel:gsub("/", "\\")
      end
    end
    for i = 1, #candidates do
      local f = io.open(candidates[i], "rb")
      if f then
        bytes = f:read("*a")
        f:close()
        if type(bytes) == "string" and #bytes >= 8 then break end
        bytes = nil
      end
    end
  end
  if type(bytes) ~= "string" or #bytes < 8 then return nil end
  if bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
  return bytes
end

function Battle.copyGoldStarsFromPokeruby()
  local bytes = Battle.readPokerubyGoldStarsPng()
  if not bytes then return nil end
  local CacheFs = require("src.import.CacheFs")
  local ok, err = CacheFs.write(Battle.goldStarsPath(), bytes)
  if not ok then return nil, err end
  return Battle.goldStarsPath()
end

function Battle.findGoldStars(data)
  if type(data) ~= "string" then return nil end
  local gfx = Battle.us(data).goldStarsGfx
  local pal = Battle.us(data).goldStarsPal
  if GbaBin.u8(data, gfx) == 0x10 then
    local size = GbaBin.u8(data, gfx + 1)
      + GbaBin.u8(data, gfx + 2) * 256
      + GbaBin.u8(data, gfx + 3) * 65536
    if size == Battle.GOLD_STARS_BYTES and GbaBin.u8(data, pal) == 0x10 then
      return gfx, pal
    end
  end
  -- CompressedSpriteSheet { ptr, size=0xC0, tag=10233 }
  local tag = Battle.GOLD_STARS_TAG
  local needle = string.char(
    Battle.GOLD_STARS_BYTES % 256,
    math.floor(Battle.GOLD_STARS_BYTES / 256) % 256,
    tag % 256,
    math.floor(tag / 256) % 256)
  local search = 1
  while true do
    local at = data:find(needle, search, true)
    if not at then return nil end
    local entry = at - 1 - 4
    if entry >= 0 then
      local _, sheetOff = romPtr(data, entry)
      if sheetOff and GbaBin.u8(data, sheetOff) == 0x10 then
        local palNeedle = string.char(
          tag % 256, math.floor(tag / 256) % 256, 0, 0)
        local psearch = 1
        while true do
          local pat = data:find(palNeedle, psearch, true)
          if not pat then break end
          local pe = pat - 1 - 4
          if pe >= 0 then
            local _, palOff = romPtr(data, pe)
            if palOff and GbaBin.u8(data, palOff) == 0x10 then
              return sheetOff, palOff
            end
          end
          psearch = pat + 1
        end
      end
    end
    search = at + 1
  end
end

function Battle.renderGoldStars(data)
  local sheetOff, palOff = Battle.findGoldStars(data)
  if not (sheetOff and palOff) then return nil, "gold stars gfx not found" end
  local raw, err = GbaLz77.decompress(data, sheetOff)
  if not raw or #raw < Battle.GOLD_STARS_BYTES then
    return nil, err or "gold stars lz77 failed"
  end
  local palBytes, palErr = GbaLz77.decompress(data, palOff)
  if not palBytes or #palBytes < Battle.PAL_BYTES then
    return nil, palErr or "gold stars palette lz77 failed"
  end
  local pal = {}
  for c = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(palBytes, c * 2))
    pal[c] = { r, g, b }
  end
  local w, h = Battle.GOLD_STARS_W, Battle.GOLD_STARS_H
  local image = ImageWriter.blank(w, h, 0, 0, 0, 0)
  local tw = w / 8
  local tiles = (w / 8) * (h / 8)
  for ti = 0, tiles - 1 do
    local col = ti % tw
    local row = math.floor(ti / tw)
    local start = ti * Battle.TILE_BYTES
    blitTile(image, col * 8, row * 8,
      raw:sub(start + 1, start + Battle.TILE_BYTES), pal)
  end
  return image
end

function Battle.extractGoldStars(data)
  local copied = Battle.copyGoldStarsFromPokeruby()
  if copied then return copied end
  local image, err = Battle.renderGoldStars(data)
  if not image then return nil, err end
  local path = Battle.goldStarsPath()
  ImageWriter.save(image, path)
  return path
end

-- Species a map script hands over or throws at you: setwildbattle for the
-- legendaries, givemon for the fossils and Castform, giveegg for Wynaut. None
-- of these appear in a wild table, an evolution or a trainer's party, so
-- collectSpecies used to miss every one of them and they had to be added to
-- the list below by hand as each was noticed. Reading them off the scripts
-- covers the whole class instead of the ones somebody hit.
-- `data` is the ROM. run() bakes map scripts in the Cache stage, which is
-- AFTER extractBattle calls this -- so every entry.script was still a raw
-- offset here and type(script) == "table" was false on every one of them.
-- This collected nothing at all on a real import, which is why the regis,
-- the weather trio and Latias had no battle pic: the renderer skips a
-- species it was never told about, silently. Parse from scriptOff when the
-- bake has not happened yet.
local function opsFor(entry, data)
  if type(entry) ~= "table" then return nil end
  if type(entry.script) == "table" then return entry.script end
  local off = tonumber(entry.scriptOff)
  if not (off and data) then return nil end
  local RomExtractorGen3 = require("src.import.RomExtractorGen3RS")
  return RomExtractorGen3.parseOps(data, off)
end

local function scanOps(ops, into, depth)
  if type(ops) ~= "table" or (depth or 0) > 8 then return end
  for i = 1, #ops do
    local op = ops[i]
    if type(op) == "table" then
      if op.op == "setwildbattle" or op.op == "givemon"
          or op.op == "giveegg" then
        local id = tonumber(op.species)
        if id and id > 0 then into[id] = true end
      end
      -- call_if / goto_if carry their ops under body
      scanOps(op.body, into, (depth or 0) + 1)
    end
  end
end

function Battle.collectScriptSpecies(maps, into, data)
  into = into or {}
  local pack = maps and (maps.maps or maps)
  if type(pack) ~= "table" then return into end
  for _, map in pairs(pack) do
    if type(map) == "table" then
      -- Not ipairs over a built table: a map with no bgEvents leaves a hole
      -- and ipairs stops there, which would skip coordEvents entirely --
      -- and coordEvents is where the legendary cutscenes live.
      local groups = {}
      groups[#groups + 1] = map.objects
      groups[#groups + 1] = map.bgEvents
      groups[#groups + 1] = map.coordEvents
      for g = 1, #groups do
        local group = groups[g]
        for i = 1, #group do
          scanOps(opsFor(group[i], data), into, 0)
        end
      end
      -- mapScripts is keyed (onLoad / onResume / ...), never an array, so
      -- the old ipairs over it walked nothing. onLoad-style keys hold ops
      -- directly; onFrame / onWarp hold rows that each carry a script.
      local ms = map.mapScripts
      if type(ms) == "table" then
        for _, v in pairs(ms) do
          if type(v) == "table" then
            if v[1] and type(v[1]) == "table" and v[1].op ~= nil then
              scanOps(v, into, 0)
            else
              for i = 1, #v do scanOps(opsFor(v[i], data), into, 0) end
            end
          elseif type(v) == "number" and data then
            local RomExtractorGen3 = require("src.import.RomExtractorGen3RS")
            scanOps(RomExtractorGen3.parseOps(data, v), into, 0)
          end
        end
      end
    end
  end
  return into
end

function Battle.collectSpecies(encounters, evolutions, trainers, maps, data)
  local used = {
    [Battle.STARTER_SPECIES] = true,
    [277] = true,
    [278] = true, -- Grovyle
    [279] = true, -- Sceptile (Treecko's second hop)
    [281] = true, -- Combusken
    [282] = true, -- Blaziken
    [283] = true,
    [284] = true, -- Marshtomp
    [285] = true, -- Swampert
    [286] = true, -- Poochyena (Birch chase; not national dex 261)
    [291] = true, -- Silcoon
    [292] = true, -- Cascoon
    [293] = true, -- Beautifly
    [294] = true, -- Dustox
    [350] = true, -- Azurill (Birch speech)
    [360] = true, -- Wynaut (Lavaridge giveegg)
    [385] = true, -- Castform (Weather Institute givemon)
    [388] = true, -- Lileep (Devon Root Fossil)
    [390] = true, -- Anorith (Devon Claw Fossil)
    [404] = true, -- Kyogre
    [405] = true, -- Groudon (title / intro)
    -- The roamer is the one legendary no table names: roamer.c takes it
    -- from ROAMER_SPECIES, which is LATIOS in Ruby and LATIAS in
    -- Sapphire. Southern Island's setwildbattle covers the other one, so
    -- collectScriptSpecies finds one but never this.
    [407] = true, -- Latias
    [408] = true, -- Latios (ROAMER_SPECIES)
  }
  Battle.collectScriptSpecies(maps, used, data)
  local byMap = encounters and encounters.byMap
  if type(byMap) == "table" then
    for _, row in pairs(byMap) do
      local kinds = { row.land, row.water, row.rock, row.fish }
      for k = 1, #kinds do
        local slots = kinds[k] and kinds[k].slots
        if slots then
          for i = 1, #slots do
            local id = slots[i] and slots[i].species
            if type(id) == "number" and id > 0 then used[id] = true end
          end
        end
      end
    end
  end
  if type(evolutions) == "table" then
    local extra = {}
    for id in pairs(used) do extra[#extra + 1] = id end
    local i = 1
    while i <= #extra do
      local list = evolutions[extra[i]]
      if type(list) == "table" then
        for e = 1, #list do
          local t = list[e] and list[e].target
          if type(t) == "number" and t > 0 and not used[t] then
            used[t] = true
            extra[#extra + 1] = t
          end
        end
      end
      i = i + 1
    end
  end
  if type(trainers) == "table" then
    local byId = trainers.byId or trainers
    for _, tr in pairs(byId) do
      local party = tr and tr.party
      if type(party) == "table" then
        for i = 1, #party do
          local id = party[i] and party[i].species
          if type(id) == "number" and id > 0 then used[id] = true end
        end
      end
    end
  end
  return used
end

local function s8(v)
  if v >= 0x80 then return v - 256 end
  return v
end

function Battle.parseOneMove(data, offset)
  if type(data) ~= "string" or offset + Battle.MOVE_SIZE > #data then
    return nil
  end
  return {
    effect = GbaBin.u8(data, offset),
    power = GbaBin.u8(data, offset + 1),
    type = GbaBin.u8(data, offset + 2),
    accuracy = GbaBin.u8(data, offset + 3),
    pp = GbaBin.u8(data, offset + 4),
    secondary = GbaBin.u8(data, offset + 5),
    target = GbaBin.u8(data, offset + 6),
    priority = s8(GbaBin.u8(data, offset + 7)),
    flags = GbaBin.u8(data, offset + 8),
  }
end

function Battle.parseMoves(data, namesOff, dataOff)
  if type(data) ~= "string" then return nil end
  local byId = {}
  for i = 0, Battle.MOVE_COUNT - 1 do
    local row = Battle.parseOneMove(data, dataOff + i * Battle.MOVE_SIZE)
    if not row then return nil end
    local no = namesOff + i * Battle.MOVE_NAME_LENGTH
    row.id = i
    row.name = GbaText.decodeName(data:sub(no + 1, no + Battle.MOVE_NAME_LENGTH))
    if row.name == "" then row.name = ("MOVE %d"):format(i) end
    byId[i] = row
  end
  return { byId = byId, count = Battle.MOVE_COUNT }
end

function Battle.findMoveTables(data)
  if type(data) ~= "string" then return nil end
  local names, moves = Battle.us(data).moveNames, Battle.us(data).moveData
  local pound = Battle.parseOneMove(data, moves + Battle.MOVE_SIZE)
  local label = GbaText.decodeName(data:sub(
    names + Battle.MOVE_NAME_LENGTH + 1,
    names + Battle.MOVE_NAME_LENGTH * 2))
  if pound and pound.power == 40 and pound.type == 0 and label == "POUND" then
    return names, moves
  end
  local needle = GbaText.encodeLatin("POUND") .. string.char(GbaText.EOS)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local namesOff = at - 1 - Battle.MOVE_NAME_LENGTH
  if namesOff < 0 then return nil end
  local dataNeedle = string.char(0, 40, 0, 100, 35)
  local hit = data:find(dataNeedle, 1, true)
  if not hit then return nil end
  return namesOff, hit - 1 - Battle.MOVE_SIZE
end

function Battle.parseTypeChart(data, offset)
  if type(data) ~= "string" then return nil end
  local rows = {}
  for i = 0, 255 do
    local o = offset + i * 3
    if o + 3 > #data then break end
    local a, b, m = GbaBin.u8(data, o), GbaBin.u8(data, o + 1), GbaBin.u8(data, o + 2)
    if a == 0xFF and b == 0xFF then break end
    if a ~= 0xFE then
      rows[#rows + 1] = { a, b, m }
    end
  end
  if #rows < 8 then return nil end
  return rows
end

function Battle.findTypeChart(data)
  if type(data) ~= "string" then return nil end
  local off = Battle.us(data).typeChart
  local chart = Battle.parseTypeChart(data, off)
  if chart and chart[1] and chart[1][1] == 0 and chart[1][2] == 5 then
    return off
  end
  local needle = string.char(0, 5, 5, 0, 8, 5, 10, 10, 5)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  return at - 1
end

function Battle.parseLearnset(data, offset)
  local list = {}
  for i = 0, 31 do
    local w = GbaBin.u16(data, offset + i * 2)
    if w == 0xFFFF then break end
    list[#list + 1] = { move = w % 512, level = math.floor(w / 512) }
  end
  return list
end

function Battle.parseLearnsets(data, tableOff)
  local bySpecies = {}
  for i = 0, Battle.SPECIES_COUNT - 1 do
    local _, off = romPtr(data, tableOff + i * 4)
    if off then
      bySpecies[i] = Battle.parseLearnset(data, off)
    else
      bySpecies[i] = {}
    end
  end
  return bySpecies
end

function Battle.findLearnsets(data)
  if type(data) ~= "string" then return nil end
  local function torchicScratch(off)
    if type(off) ~= "number" then return false end
    local _, torchic = romPtr(data, off + Battle.STARTER_SPECIES * 4)
    if not torchic then return false end
    local first = Battle.parseLearnset(data, torchic)[1]
    return first and first.move == 10 and first.level == 1
  end
  local hinted = Battle.us(data).learnsets
  if torchicScratch(hinted) then return hinted end
  -- 412 pointers; US RS tables sit just past 0x207000.
  local span = Battle.SPECIES_COUNT * 4
  local first, last = 0, #data - span
  if #data > 0x40000 then
    first = 0x200000
    last = math.min(last, 0x210000)
  end
  for off = first, last, 4 do
    if torchicScratch(off) then
      local _, bulb = romPtr(data, off + 4)
      local b = bulb and Battle.parseLearnset(data, bulb)[1]
      if b and b.move == 33 and b.level == 1 then return off end
    end
  end
end

function Battle.parseTmhmLearnsets(data, tableOff)
  local bySpecies = {}
  if type(data) ~= "string" or type(tableOff) ~= "number" then return bySpecies end
  for i = 0, Battle.SPECIES_COUNT - 1 do
    local o = tableOff + i * 8
    if o + 8 > #data then break end
    bySpecies[i] = { GbaBin.u32(data, o), GbaBin.u32(data, o + 4) }
  end
  return bySpecies
end

function Battle.looksLikeTmhmLearnsets(data, off)
  if type(data) ~= "string" or type(off) ~= "number" then return false end
  if off < 0 or off + (Battle.STARTER_SPECIES + 1) * 8 > #data then return false end
  if GbaBin.u32(data, off) ~= 0 or GbaBin.u32(data, off + 4) ~= 0 then
    return false
  end
  local o = off + Battle.STARTER_SPECIES * 8
  return GbaBin.u32(data, o) == Battle.TORCHIC_TMHM0
    and GbaBin.u32(data, o + 4) == Battle.TORCHIC_TMHM1
end

function Battle.findTmhmLearnsets(data)
  if type(data) ~= "string" then return nil end
  if Battle.looksLikeTmhmLearnsets(data, Battle.us(data).tmhmLearnsets) then
    return Battle.us(data).tmhmLearnsets
  end
  local span = (Battle.STARTER_SPECIES + 1) * 8
  if #data < span then return nil end
  local last = #data - span
  local first = 0
  if #data > 0x40000 then
    first = 0x1E0000
    last = math.min(last, 0x220000)
  end
  for off = first, last, 8 do
    if Battle.looksLikeTmhmLearnsets(data, off) then return off end
  end
end

function Battle.parseEvolutions(data, tableOff, stride)
  stride = stride or Battle.EVO_SIZE
  local bySpecies = {}
  for i = 0, Battle.SPECIES_COUNT - 1 do
    local list = {}
    for e = 0, Battle.EVOS_PER_MON - 1 do
      local o = tableOff + (i * Battle.EVOS_PER_MON + e) * stride
      local method = GbaBin.u16(data, o)
      if method ~= 0 and method < 32 then
        list[#list + 1] = {
          method = method,
          param = GbaBin.u16(data, o + 2),
          target = GbaBin.u16(data, o + 4),
        }
      end
    end
    bySpecies[i] = list
  end
  return bySpecies
end

local function torchicEvoAt(data, tableOff, stride)
  if type(data) ~= "string" then return false end
  local o = tableOff + Battle.STARTER_SPECIES * Battle.EVOS_PER_MON * stride
  if o + 6 > #data then return false end
  return GbaBin.u16(data, o) == Battle.EVO_LEVEL
    and GbaBin.u16(data, o + 2) == 16
    and GbaBin.u16(data, o + 4) == 281
end

function Battle.findEvolutionTable(data)
  if type(data) ~= "string" then return nil end
  local off = Battle.us(data).evolutions
  if torchicEvoAt(data, off, 8) then return off, 8 end
  if torchicEvoAt(data, off, 6) then return off, 6 end
  local needle = GbaBin.packU16(Battle.EVO_LEVEL)
    .. GbaBin.packU16(16)
    .. GbaBin.packU16(281)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local hit = at - 1
  for _, stride in ipairs({ 8, 6 }) do
    local start = hit - Battle.STARTER_SPECIES * Battle.EVOS_PER_MON * stride
    if start >= 0 and torchicEvoAt(data, start, stride) then
      return start, stride
    end
  end
  return nil
end

-- A 64-byte window missed real trainerbattle commands in the actual Ruby
-- ROM (lock/faceplayer/msgbox/checkflag preambles before the grunt's
-- trainerbattle command run past it, up to +353 bytes seen in practice).
-- 512 covers those with margin while still bounded.
function Battle.readTrainerIdFromScript(data, scriptOff)
  if type(data) ~= "string" or type(scriptOff) ~= "number" then return nil end
  for i = 0, 511 do
    if scriptOff + i + 4 > #data then break end
    if GbaBin.u8(data, scriptOff + i) == Battle.TRAINERBATTLE_CMD then
      local kind = GbaBin.u8(data, scriptOff + i + 1)
      local id = GbaBin.u16(data, scriptOff + i + 2)
      if kind <= 9 and id > 0 and id < Battle.TRAINER_COUNT then
        return id
      end
    end
  end
end

function Battle.parseTrainerParty(data, partyOff, size, flags)
  flags = flags or 0
  size = size or 0
  if size < 1 then return {} end
  if size > 6 then size = 6 end
  local custom = flags % 2 == 1
  local item = math.floor(flags / 2) % 2 == 1
  local stride = 8
  if custom then stride = 16 end
  if item and not custom then stride = 8 end
  local party = {}
  for i = 0, size - 1 do
    local o = partyOff + i * stride
    local species = GbaBin.u16(data, o + 4)
    local level = GbaBin.u8(data, o + 2)
    if species > 0 and species < Battle.SPECIES_COUNT and level > 0 and level <= 100 then
      local mon = { species = species, level = level }
      if custom then
        local moves = {}
        for m = 0, 3 do
          local mv = GbaBin.u16(data, o + 6 + m * 2)
          if mv > 0 then moves[#moves + 1] = mv end
        end
        if #moves > 0 then mon.moves = moves end
      end
      party[#party + 1] = mon
    end
  end
  return party
end

function Battle.parseClassNames(data, offset)
  local names = {}
  if type(data) ~= "string" or type(offset) ~= "number" then return names end
  for i = 0, Battle.TRAINER_CLASS_COUNT - 1 do
    local no = offset + i * Battle.TRAINER_CLASS_NAME_LENGTH
    names[i] = GbaText.decodeName(data:sub(no + 1, no + Battle.TRAINER_CLASS_NAME_LENGTH))
  end
  return names
end

function Battle.parseOneTrainer(data, offset, classNames)
  if type(data) ~= "string" or offset + Battle.TRAINER_SIZE > #data then
    return nil
  end
  local flags = GbaBin.u8(data, offset)
  local class = GbaBin.u8(data, offset + 1)
  local pic = GbaBin.u8(data, offset + 3)
  local name = GbaText.decodeName(data:sub(
    offset + 5, offset + 4 + Battle.TRAINER_NAME_LENGTH))
  local doubleBattle = GbaBin.u32(data, offset + 24) ~= 0
  local items = {}
  for i = 0, 3 do
    local id = GbaBin.u16(data, offset + 16 + i * 2)
    if id ~= 0 then items[#items + 1] = id end
  end
  -- struct Trainer: bool8 doubleBattle at 0x18, u32 aiFlags at 0x1C. The AI
  -- flags pick which scoring passes battle_ai runs for this trainer; without
  -- them every opponent has to fall back to choosing at random.
  local aiFlags = GbaBin.u32(data, offset + 28)
  local partySize = GbaBin.u8(data, offset + 32)
  local _, partyOff = romPtr(data, offset + 36)
  local party = {}
  if partyOff and partySize > 0 then
    party = Battle.parseTrainerParty(data, partyOff, partySize, flags)
  end
  return {
    flags = flags,
    class = class,
    encounterMusic = GbaBin.u8(data, offset + 2),
    pic = pic,
    className = (classNames and classNames[class]) or "TRAINER",
    name = name ~= "" and name or "TRAINER",
    doubleBattle = doubleBattle,
    aiFlags = aiFlags,
    partySize = partySize,
    party = party,
    items = items,
  }
end

function Battle.parseTrainers(data, tableOff, classOff)
  local classes = {}
  if classOff then
    classes = Battle.parseClassNames(data, classOff)
  end
  local byId = {}
  local count = 0
  for i = 0, Battle.TRAINER_COUNT - 1 do
    local row = Battle.parseOneTrainer(data, tableOff + i * Battle.TRAINER_SIZE, classes)
    if row then
      row.id = i
      byId[i] = row
      if #(row.party or {}) > 0 then count = count + 1 end
    end
  end
  return { byId = byId, classes = classes, count = count }
end

local function looksLikeTrainerTable(data, offset)
  local row = Battle.parseOneTrainer(data, offset + Battle.TRAINER_SIZE)
  if not (row and row.party and #row.party >= 1) then return false end
  local name = row.name or ""
  return #name >= 2 and name ~= "TRAINER"
end

function Battle.findTrainerTable(data)
  if type(data) ~= "string" then return nil end
  if looksLikeTrainerTable(data, Battle.us(data).trainers) then
    return Battle.us(data).trainers, Battle.us(data).trainerClasses
  end
  local needle = GbaText.encodeLatin("CALVIN") .. string.char(GbaText.EOS)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local structOff = at - 1 - 4
  if structOff < 0 then return nil end
  -- Walk back one trainer at a time until TRAINER_NONE (empty name, no party).
  local start = structOff
  for _ = 1, Battle.TRAINER_COUNT do
    if start < Battle.TRAINER_SIZE then
      start = 0
      break
    end
    local prev = start - Battle.TRAINER_SIZE
    local name = GbaText.decodeName(data:sub(
      prev + 5, prev + 4 + Battle.TRAINER_NAME_LENGTH))
    local partySize = GbaBin.u8(data, prev + 32)
    start = prev
    if name == "" and partySize == 0 then break end
  end
  if looksLikeTrainerTable(data, start) then return start, nil end
  if looksLikeTrainerTable(data, structOff - Battle.TRAINER_SIZE) then
    return structOff - Battle.TRAINER_SIZE, nil
  end
  if looksLikeTrainerTable(data, structOff) then return structOff, nil end
end

function Battle.parseOneItem(data, offset)
  if type(data) ~= "string" or offset + Battle.ITEM_SIZE > #data then
    return nil
  end
  local name = GbaText.decodeName(data:sub(
    offset + 1, offset + Battle.ITEM_NAME_LENGTH))
  -- struct Item: description pointer at +0x14. Bag ItemListMenu_InitDescription
  -- prints these lines (0xFE newlines) under the list; without them the port
  -- fell back to the item name and looked empty/wrong.
  local description = ""
  local descPtr = GbaBin.u32(data, offset + 20)
  if GbaBin.isRomPtr(descPtr, #data) then
    local descOff = GbaBin.romOffset(descPtr)
    local pages = GbaText.decodePages(data:sub(descOff + 1, descOff + 128), 128)
    description = pages[1] or ""
  end
  return {
    name = name,
    itemId = GbaBin.u16(data, offset + 14),
    price = GbaBin.u16(data, offset + 16),
    holdEffect = GbaBin.u8(data, offset + 18),
    holdEffectParam = GbaBin.u8(data, offset + 19),
    description = description,
    pocket = GbaBin.u8(data, offset + 26),
    -- The rest of struct Item. importance marks a key item, and the two use
    -- function pointers are what say whether an item does anything at all in
    -- the field or in battle -- NULL for most, a shared handler for the rest.
    importance = GbaBin.u8(data, offset + 24),
    type = GbaBin.u8(data, offset + 27),
    fieldUseFunc = GbaBin.u32(data, offset + 28),
    battleUsage = GbaBin.u8(data, offset + 32),
    battleUseFunc = GbaBin.u32(data, offset + 36),
    secondaryId = GbaBin.u8(data, offset + 40),
  }
end

function Battle.parseItems(data, tableOff)
  local byId = {}
  local named = 0
  for i = 0, Battle.ITEM_COUNT - 1 do
    local row = Battle.parseOneItem(data, tableOff + i * Battle.ITEM_SIZE)
    if row then
      row.id = i
      if row.itemId == 0 then row.itemId = i end
      byId[i] = row
      if row.name ~= "" then named = named + 1 end
    end
  end
  return { byId = byId, count = Battle.ITEM_COUNT, named = named }
end

local function looksLikeItemTable(data, offset)
  local master = Battle.parseOneItem(data, offset + Battle.ITEM_SIZE)
  return master and master.name == "MASTER BALL" and master.price == 0
end

function Battle.findItemTable(data)
  if type(data) ~= "string" then return nil end
  if looksLikeItemTable(data, Battle.us(data).items) then
    return Battle.us(data).items
  end
  local needle = GbaText.encodeLatin("MASTER BALL") .. string.char(GbaText.EOS)
  local at = data:find(needle, 1, true)
  if not at then return nil end
  local start = at - 1 - Battle.ITEM_SIZE
  if start >= 0 and looksLikeItemTable(data, start) then return start end
end

function Battle.readItemGiveFromScript(data, scriptOff)
  if type(data) ~= "string" or type(scriptOff) ~= "number" then return nil end
  local item, count
  for i = 0, 79 do
    if scriptOff + i + 5 > #data then break end
    local cmd = GbaBin.u8(data, scriptOff + i)
    if cmd == Battle.SETVAR_CMD or cmd == Battle.SETORCOPYVAR_CMD then
      local dest = GbaBin.u16(data, scriptOff + i + 1)
      local val = GbaBin.u16(data, scriptOff + i + 3)
      if dest == Battle.VAR_0x8000 and val > 0 and val < Battle.ITEM_COUNT then
        item = val
      elseif dest == Battle.VAR_0x8001 and val > 0 and val <= 99 then
        count = val
      end
    end
  end
  if item then return { id = item, count = count or 1 } end
end

function Battle.parseMartList(data, offset)
  local items = {}
  if type(data) ~= "string" or type(offset) ~= "number" then return items end
  for i = 0, 15 do
    if offset + i * 2 + 2 > #data then break end
    local id = GbaBin.u16(data, offset + i * 2)
    if id == 0 then break end
    if id < Battle.ITEM_COUNT then items[#items + 1] = id end
  end
  return items
end

function Battle.readMartFromScript(data, scriptOff)
  if type(data) ~= "string" or type(scriptOff) ~= "number" then return nil end
  for i = 0, 63 do
    if scriptOff + i + 5 > #data then break end
    if GbaBin.u8(data, scriptOff + i) == Battle.POKEMART_CMD then
      local _, listOff = romPtr(data, scriptOff + i + 1)
      if listOff then
        local items = Battle.parseMartList(data, listOff)
        if #items > 0 then return items end
      end
    end
  end
end


-- gTrainerEyeDescriptions. pokeruby leaves this one extern, so it comes off
-- the cart by shape rather than by symbol. LoadTrainerEyesDescriptionLines
-- takes the pointer for a row and then walks forward past three EOS bytes, so
-- every entry is four terminated strings laid end to end, and entry k+1 starts
-- exactly where entry k finished. That -- 69 of them in a row, one per rematch
-- row plus one per gym leader -- is signature enough to find it alone.
Battle.TRAINER_EYE_DESCRIPTIONS = 69
Battle.TRAINER_EYE_LINES = 4
Battle.TRAINER_EYE_MAX_LINE = 120

local function eyeTextByte(c)
  if c == GbaText.EOS then return nil end
  -- The description text uses letters, digits, spaces, the accented E of
  -- POKeMON, ordinary punctuation and the buffer placeholders.
  if c >= 0xBB and c <= 0xEE then return true end
  if c >= 0xA1 and c <= 0xAA then return true end
  if c == 0x00 or c == 0x1B or c == 0x2D then return true end
  if c >= 0xAB and c <= 0xBA then return true end
  if c >= 0x55 and c <= 0x59 then return true end
  return false
end

-- One EOS-terminated line. Returns its length and the offset of the EOS.
local function eyeLine(data, off)
  local i = off
  local last = math.min(#data - 1, off + Battle.TRAINER_EYE_MAX_LINE)
  while i <= last do
    local c = GbaBin.u8(data, i)
    if c == GbaText.EOS then return i - off, i end
    if not eyeTextByte(c) then return nil end
    i = i + 1
  end
  return nil
end

-- Four lines back to back. Returns the offset just past the last EOS.
local function eyeEntryEnd(data, off)
  local p = off
  for _ = 1, Battle.TRAINER_EYE_LINES do
    local len, eos = eyeLine(data, p)
    if not len or len < 3 then return nil end
    p = eos + 1
  end
  return p
end

local function eyePointer(data, off)
  local v = GbaBin.u32(data, off)
  if v < 0x08000000 or v >= 0x08000000 + #data then return nil end
  return v - 0x08000000
end

function Battle.findTrainerEyeDescriptions(data)
  local off = 0
  local limit = #data - 4 * Battle.TRAINER_EYE_DESCRIPTIONS
  while off <= limit do
    local first = eyePointer(data, off)
    local finish = first and eyeEntryEnd(data, first)
    if finish then
      local run, k, prev = 1, off + 4, finish
      while run < Battle.TRAINER_EYE_DESCRIPTIONS do
        local t = eyePointer(data, k)
        -- the next row's text must begin where this one ended
        if t ~= prev then break end
        local e = eyeEntryEnd(data, t)
        if not e then break end
        run, prev, k = run + 1, e, k + 4
      end
      if run >= Battle.TRAINER_EYE_DESCRIPTIONS then return off end
    end
    off = off + 4
  end
  return nil
end

function Battle.parseTrainerEyeDescriptions(data, tableOff)
  tableOff = tableOff or Battle.findTrainerEyeDescriptions(data)
  if not tableOff then return nil end
  local out = {}
  for i = 0, Battle.TRAINER_EYE_DESCRIPTIONS - 1 do
    local at = eyePointer(data, tableOff + i * 4)
    if not at then return nil end
    local lines, p = {}, at
    for _ = 1, Battle.TRAINER_EYE_LINES do
      local _, eos = eyeLine(data, p)
      if not eos then return nil end
      local chars = {}
      for j = p, eos - 1 do
        chars[#chars + 1] = GbaText.decodeByte(GbaBin.u8(data, j))
      end
      lines[#lines + 1] = table.concat(chars)
      p = eos + 1
    end
    out[i] = lines
  end
  return out
end


-- gRibbonDescriptions is [25][2]: two lines per ribbon, and unlike the
-- Trainer's Eye table its text sits before it rather than after. What makes it
-- findable is the shape of the contest half -- five categories of four ranks,
-- where each group of four shares one "COOL CONTEST" style first line and
-- differs only in the rank on the second. Five runs of four identical first
-- pointers in a row is a fingerprint nothing else in the cart carries.
Battle.RIBBON_DESCRIPTIONS = 25
Battle.RIBBON_CONTEST_GROUPS = 5
Battle.RIBBON_CONTEST_RANKS = 4
Battle.RIBBON_MAX_LINE = 90

local function ribbonPointer(data, off)
  local v = GbaBin.u32(data, off)
  if v < 0x08000000 or v >= 0x08000000 + #data then return nil end
  return v - 0x08000000
end

local function ribbonLine(data, off)
  local i = off
  local last = math.min(#data - 1, off + Battle.RIBBON_MAX_LINE)
  local chars = {}
  while i <= last do
    local c = GbaBin.u8(data, i)
    if c == GbaText.EOS then
      local text = table.concat(chars)
      -- a run of spaces is padding, not a description
      if #text < 3 or not text:find("[^ ]") then return nil end
      return text
    end
    local ch = GbaText.decodeByte(c)
    -- decodeByte turns anything it does not know into an empty string, so a
    -- run of control bytes would read as a short blank rather than fail
    if ch == "" and c ~= GbaText.SPACE then return nil end
    chars[#chars + 1] = ch
    i = i + 1
  end
  return nil
end

function Battle.findRibbonDescriptions(data)
  local limit = #data - 8 * Battle.RIBBON_DESCRIPTIONS
  for off = 0, limit, 4 do
    local ok = true
    local seen = {}
    -- the five groups of four ranks, each sharing a first line, and the five
    -- category names are five different strings
    for g = 0, Battle.RIBBON_CONTEST_GROUPS - 1 do
      local base = ribbonPointer(data, off + (1 + 4 * g) * 8)
      if not base or seen[base] then ok = false break end
      seen[base] = true
      for r = 1, Battle.RIBBON_CONTEST_RANKS - 1 do
        if ribbonPointer(data, off + (1 + 4 * g + r) * 8) ~= base then
          ok = false
          break
        end
      end
      if not ok then break end
    end
    if ok then
      -- and every one of the fifty pointers must read as a line
      for i = 0, Battle.RIBBON_DESCRIPTIONS * 2 - 1 do
        local t = ribbonPointer(data, off + i * 4)
        if not t or not ribbonLine(data, t) then
          ok = false
          break
        end
      end
      if ok then return off end
    end
  end
  return nil
end

function Battle.parseRibbonDescriptions(data, tableOff)
  tableOff = tableOff or Battle.findRibbonDescriptions(data)
  if not tableOff then return nil end
  local out = {}
  for i = 0, Battle.RIBBON_DESCRIPTIONS - 1 do
    local a = ribbonPointer(data, tableOff + i * 8)
    local b = ribbonPointer(data, tableOff + i * 8 + 4)
    local l1 = a and ribbonLine(data, a)
    local l2 = b and ribbonLine(data, b)
    if not (l1 and l2) then return nil end
    out[i] = { l1, l2 }
  end
  return out
end

Battle.ANIM_PIC_COUNT = 286
Battle.ANIM_PIC_TABLE = 0x37E164
Battle.ANIM_PAL_TABLE = 0x37EA54
Battle.ANIM_SCRIPT_TABLE = 0x1C7168
Battle.ANIM_TAG_BASE = 0x2710

function Battle.animPath(id)
  return ("assets/generated/battle/anims/%d.png"):format(id)
end

function Battle.renderAnimSheet(data, picOff, palOff)
  local _, gfxOff = romPtr(data, picOff)
  local _, palDataOff = romPtr(data, palOff)
  if not (gfxOff and palDataOff) then return nil end
  local raw = GbaLz77.decompress(data, gfxOff)
  local palBytes = GbaLz77.decompress(data, palDataOff)
  if not raw or #raw < 32 or not palBytes or #palBytes < 32 then return nil end
  local pal = {}
  for c = 0, 15 do
    pal[c] = { bgr555(GbaBin.u16(palBytes, c * 2)) }
  end
  local tiles = math.floor(#raw / Battle.TILE_BYTES)
  local cols = 8
  if tiles <= 4 then cols = math.max(1, tiles) end
  local rows = math.max(1, math.floor((tiles + cols - 1) / cols))
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for t = 0, tiles - 1 do
    blitTile(image, (t % cols) * 8, math.floor(t / cols) * 8,
      raw:sub(t * Battle.TILE_BYTES + 1, (t + 1) * Battle.TILE_BYTES), pal)
  end
  return image
end

-- THE SHEETS AGAIN, THIS TIME IN FRAMES.
--
-- renderAnimSheet lays the cart's tiles out eight to a row, which is the
-- order they are STORED in, not the picture they make: a 32x32 particle is
-- sixteen tiles in 1D order, and eight-to-a-row cuts it in half and puts the
-- halves on two rows. Nothing could draw a particle from that, which is part
-- of why the old renderer settled for one scaled smear.
--
-- Given the frame size a template asks for, the same tiles compose properly:
-- frame k is (w/8)*(h/8) consecutive tiles filling a w x h box, and the
-- frames sit left to right. One image per (sheet, size) pair the scripts
-- actually use -- the size is the template's, so a sheet used at two sizes
-- gets two images, which is what the createsprites ask for.
function Battle.animFramedPath(id, w, h)
  return ("assets/generated/battle/anims/%d_%dx%d.png"):format(id, w, h)
end

function Battle.renderAnimSheetFramed(data, picOff, palOff, w, h)
  local _, gfxOff = romPtr(data, picOff)
  local _, palDataOff = romPtr(data, palOff)
  if not (gfxOff and palDataOff) then return nil end
  local raw = GbaLz77.decompress(data, gfxOff)
  local palBytes = GbaLz77.decompress(data, palDataOff)
  if not raw or #raw < 32 or not palBytes or #palBytes < 32 then return nil end
  local pal = {}
  for c = 0, 15 do pal[c] = { bgr555(GbaBin.u16(palBytes, c * 2)) } end
  local tw, th = math.floor(w / 8), math.floor(h / 8)
  local per = tw * th
  if per < 1 then return nil end
  local tiles = math.floor(#raw / Battle.TILE_BYTES)
  local frames = math.floor(tiles / per)
  if frames < 1 then return nil end
  local image = ImageWriter.blank(frames * w, h, 0, 0, 0, 0)
  for f = 0, frames - 1 do
    for t = 0, per - 1 do
      local src = f * per + t
      blitTile(image,
        f * w + (t % tw) * 8, math.floor(t / tw) * 8,
        raw:sub(src * Battle.TILE_BYTES + 1, (src + 1) * Battle.TILE_BYTES), pal)
    end
  end
  return image, frames
end

-- `wanted` is the set of (sheet, w, h) the move scripts ask for, gathered by
-- parseMoveAnimPlans; nothing else is rendered, so a sheet no move draws
-- costs nothing.
function Battle.extractAnimFrames(data, wanted)
  local out = {}
  local pics = usOff(data, "ANIM_PIC_TABLE")
  local pals = usOff(data, "ANIM_PAL_TABLE")
  for key in pairs(wanted or {}) do
    local id, w, h = key:match("^(%d+)|(%d+)|(%d+)$")
    id, w, h = tonumber(id), tonumber(w), tonumber(h)
    if id and w and h then
      local img, frames = Battle.renderAnimSheetFramed(data,
        pics + id * 8, pals + id * 8, w, h)
      if img then
        local path = Battle.animFramedPath(id, w, h)
        ImageWriter.save(img, path)
        out[key] = { path = path, w = w, h = h, frames = frames }
      end
    end
  end
  return out
end

function Battle.extractAnimSheets(data)
  local sheets = {}
  local pics = usOff(data, "ANIM_PIC_TABLE")
  local pals = usOff(data, "ANIM_PAL_TABLE")
  for i = 0, Battle.ANIM_PIC_COUNT - 1 do
    local img = Battle.renderAnimSheet(data,
      pics + i * 8, pals + i * 8)
    if img then
      local path = Battle.animPath(i)
      ImageWriter.save(img, path)
      sheets[i] = path
    end
  end
  return sheets
end

local function lz77At(data, off)
  if type(off) ~= "number" or off < 0 or off >= #data then return nil end
  if (data:byte(off + 1) or 0) ~= 0x10 then return nil end
  return GbaLz77.decompress(data, off)
end

function Battle.animBgPath(id)
  return ("assets/generated/battle/anims/bg_%d.png"):format(id)
end

function Battle.surfPath(side, muddy)
  if muddy then
    return ("assets/generated/battle/anims/surf_%s_muddy.png"):format(side)
  end
  return ("assets/generated/battle/anims/surf_%s.png"):format(side)
end

function Battle.surfLife()
  local S = Battle.SURF_WAVE
  return (S.HOLD + S.FADE) * S.STEP
end

function Battle.surfMotionShape()
  local S = Battle.SURF_WAVE
  return {
    width = S.CELLS * S.BLOCKS * 8,
    height = S.ROWS * 8,
    player = { x = S.PLAYER.x, y = S.PLAYER.y, dx = S.PLAYER.dx, dy = S.PLAYER.dy },
    opponent = { x = S.OPPONENT.x, y = S.OPPONENT.y, dx = S.OPPONENT.dx, dy = S.OPPONENT.dy },
    fade = S.FADE, hold = S.HOLD, step = S.STEP, blendOf = S.BLEND_OF,
    life = Battle.surfLife(),
  }
end

-- Entries 0 and 1 of gBattleAnimBackgroundTable are the same three pointers.
function Battle.findAnimBgTable(data)
  if Battle._bgTableData == data then return Battle._bgTableAt end
  Battle._bgTableData = data
  Battle._bgTableAt = nil
  if type(data) ~= "string" then return nil end
  local A = Battle.ANIM_BG
  local need = A.COUNT * A.ENTRY
  local last = #data - need
  if last < 0 then return nil end
  local off = 0
  while off <= last do
    if data:sub(off + 1, off + 12) == data:sub(off + 13, off + 24) then
      local ok = true
      local i = 0
      while i < A.COUNT do
        local base = off + i * A.ENTRY
        local k = 0
        while k < 3 do
          if not GbaBin.isRomPtr(GbaBin.u32(data, base + k * 4), #data) then
            ok = false
            break
          end
          k = k + 1
        end
        if not ok then break end
        i = i + 1
      end
      if ok then
        local imgOff = GbaBin.romOffset(GbaBin.u32(data, off))
        local palOff = GbaBin.romOffset(GbaBin.u32(data, off + 4))
        local pal = lz77At(data, palOff)
        local img = lz77At(data, imgOff)
        if pal and #pal == Battle.PAL_BYTES and img and #img >= Battle.TILE_BYTES then
          Battle._bgTableAt = off
          return off
        end
      end
    end
    off = off + 4
  end
  return nil
end

function Battle.renderAnimBg(data, tableOff, id)
  local A = Battle.ANIM_BG
  if type(id) ~= "number" or id < 0 or id >= A.COUNT then return nil end
  local base = tableOff + id * A.ENTRY
  local imgPtr = GbaBin.u32(data, base)
  local palPtr = GbaBin.u32(data, base + 4)
  local mapPtr = GbaBin.u32(data, base + 8)
  if not (GbaBin.isRomPtr(imgPtr, #data) and GbaBin.isRomPtr(palPtr, #data)
      and GbaBin.isRomPtr(mapPtr, #data)) then
    return nil
  end
  local tiles = lz77At(data, GbaBin.romOffset(imgPtr))
  local palBytes = lz77At(data, GbaBin.romOffset(palPtr))
  local map = lz77At(data, GbaBin.romOffset(mapPtr))
  if not (tiles and palBytes and map) then return nil end
  if #tiles < Battle.TILE_BYTES or #palBytes < Battle.PAL_BYTES or #map < 2 then
    return nil
  end
  local pal = {}
  for c = 0, 15 do
    pal[c] = { bgr555(GbaBin.u16(palBytes, c * 2)) }
  end
  local maxTiles = math.floor(#tiles / Battle.TILE_BYTES)
  local image = ImageWriter.blank(A.VIEW_W * 8, A.VIEW_H * 8, 0, 0, 0, 1)
  local mapH = math.floor(#map / (A.MAP_W * 2))
  if mapH < 1 then mapH = 1 end
  local ty = 0
  while ty < A.VIEW_H do
    if ty >= mapH then break end
    local tx = 0
    while tx < A.VIEW_W do
      local entry = GbaBin.u16(map, (ty * A.MAP_W + tx) * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        local hflip = math.floor(entry / 1024) % 2 == 1
        local vflip = math.floor(entry / 2048) % 2 == 1
        blitTile(image, tx * 8, ty * 8,
          tiles:sub(tid * Battle.TILE_BYTES + 1, (tid + 1) * Battle.TILE_BYTES),
          pal, hflip, vflip)
        -- Colour 0 is the field (BG_DARK's black), not a hole.
        local col0 = pal[0]
        if col0 then
          local py = 0
          while py < 8 do
            local px = 0
            while px < 8 do
              local sx = hflip and (7 - px) or px
              local sy = vflip and (7 - py) or py
              local raw = tiles:sub(tid * Battle.TILE_BYTES + 1,
                (tid + 1) * Battle.TILE_BYTES)
              local byte = raw:byte(sy * 4 + math.floor(sx / 2) + 1) or 0
              local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
              if ci == 0 then
                image:setPixel(tx * 8 + px, ty * 8 + py,
                  col0[1], col0[2], col0[3], 1)
              end
              px = px + 1
            end
            py = py + 1
          end
        end
      end
      tx = tx + 1
    end
    ty = ty + 1
  end
  return image
end

local function composeSurfMap(tiles, tmap, colors, S)
  if not (tiles and tmap and colors) then return nil end
  local wide = S.CELLS * S.BLOCKS
  local image = ImageWriter.blank(wide * 8, S.ROWS * 8, 0, 0, 0, 0)
  local maxTiles = math.floor(#tiles / Battle.TILE_BYTES)
  local cy = 0
  while cy < S.ROWS do
    local cx = 0
    while cx < wide do
      local block = math.floor(cx / S.CELLS)
      local c = block * S.CELLS * S.ROWS + cy * S.CELLS + (cx % S.CELLS)
      local entry = GbaBin.u16(tmap, c * 2)
      local tid = entry % 1024
      if tid < maxTiles then
        local hflip = math.floor(entry / 1024) % 2 == 1
        local vflip = math.floor(entry / 2048) % 2 == 1
        blitTile(image, cx * 8, cy * 8,
          tiles:sub(tid * Battle.TILE_BYTES + 1, (tid + 1) * Battle.TILE_BYTES),
          colors, hflip, vflip)
      end
      cx = cx + 1
    end
    cy = cy + 1
  end
  return image
end

local function palFromBytes(praw)
  local colors = {}
  local i = 0
  while i < 16 do
    colors[i] = { bgr555(GbaBin.u16(praw, i * 2)) }
    i = i + 1
  end
  return colors
end

local function forEachAnimTask(plans, fn)
  for _, plan in pairs(plans or {}) do
    local tasks = plan.tasks or {}
    local i = 1
    while i <= #tasks do fn(tasks[i], plan) i = i + 1 end
    tasks = plan.hitTasks or {}
    i = 1
    while i <= #tasks do fn(tasks[i], plan) i = i + 1 end
    local arms = plan.argEq
    if type(arms) == "table" then
      local a = 1
      while a <= #arms do
        tasks = arms[a].tasks or {}
        i = 1
        while i <= #tasks do fn(tasks[i], plan) i = i + 1 end
        a = a + 1
      end
    end
  end
end

local function surfPoolHasLiterals(data, at)
  local S = Battle.SURF_WAVE
  local seen = {}
  local words = Battle.poolWords(data, at, S.SCAN)
  local i = 1
  while i <= #words do
    seen[words[i]] = true
    i = i + 1
  end
  local function has(lo)
    return seen[lo] or seen[lo + 0xFFFF0000] or false
  end
  return has(0xFF20) and has(0xFFD0) and has(0xFFFE) and has(0xFFFF)
end

function Battle.findSurfTask(data, plans)
  if Battle._surfData == data then return Battle._surfAt end
  Battle._surfData = data
  Battle._surfAt = nil
  if type(data) ~= "string" then return nil end
  local byFn, argcOk = {}, {}
  forEachAnimTask(plans, function(t)
    local fn = t.fn
    if not fn then return end
    local flat = fn - (fn % 2)
    byFn[flat] = byFn[flat] or {}
    local list = byFn[flat]
    list[#list + 1] = t
    local n = #(t.args or {})
    local a0 = t.args and t.args[1]
    if n ~= 1 or (a0 ~= 0 and a0 ~= 1) then
      argcOk[flat] = false
    elseif argcOk[flat] ~= false then
      argcOk[flat] = true
    end
  end)
  for fn, ok in pairs(argcOk) do
    if ok then
      local at = fn
      if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
      if at >= 0 and at < #data and surfPoolHasLiterals(data, at) then
        Battle._surfAt = at
        return at
      end
    end
  end
  return nil
end

function Battle.classifySurf(data, plans)
  local at = Battle.findSurfTask(data, plans)
  if not at then return end
  local shape = Battle.surfMotionShape()
  forEachAnimTask(plans, function(t, plan)
    if plan.surf then return end
    local fn = t.fn
    if not fn then return end
    local dest = fn - (fn % 2)
    if dest >= GbaBin.ROM_BASE then dest = dest - GbaBin.ROM_BASE end
    if dest ~= at then return end
    plan.surf = shape
    local a0 = t.args and t.args[1]
    if a0 == 1 then plan.surfMuddy = true end
  end)
end

function Battle.findSineTable(data)
  if Battle._sineData == data then return Battle._sineAt end
  Battle._sineData = data
  Battle._sineAt = nil
  if type(data) ~= "string" or #data < 512 then return nil end
  local off = 0
  local last = #data - 512
  while off <= last do
    if GbaBin.u16(data, off) == 0
        and GbaBin.u16(data, off + 128) == 256
        and GbaBin.u16(data, off + 256) == 0
        and GbaBin.s16(data, off + 384) == -256 then
      Battle._sineAt = off
      return off
    end
    off = off + 2
  end
  return nil
end

function Battle.afterimageShape()
  local A = Battle.ANIM_AFTERIMAGE
  return {
    copies = A.COPIES,
    steps = A.STEPS,
    framesPerStep = A.FRAMES_PER_STEP,
    phaseStep = A.PHASE_STEP,
    radiusDiv = A.RADIUS_DIV,
    angleDiv = A.ANGLE_DIV,
    life = A.STEPS * A.FRAMES_PER_STEP,
  }
end

function Battle.isSineTable(data, off)
  if type(data) ~= "string" or off < 0 or off + 385 >= #data then return false end
  return GbaBin.u16(data, off) == 0
    and GbaBin.u16(data, off + 128) == 256
    and GbaBin.u16(data, off + 256) == 0
    and GbaBin.s16(data, off + 384) == -256
end

function Battle.classifyAfterimage(data, plans)
  if type(data) ~= "string" then return end
  local A = Battle.ANIM_AFTERIMAGE
  local function atOf(fn)
    if not fn then return nil end
    local at = fn - (fn % 2)
    if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
    if at < 0 or at >= #data then return nil end
    return at
  end
  local function poolsSine(at)
    if not at then return false end
    local words = Battle.poolWords(data, at, A.SCAN)
    local i = 1
    while i <= #words do
      local dest = words[i]
      local off
      if GbaBin.isRomPtr(dest, #data) then
        off = dest - (dest % 2) - GbaBin.ROM_BASE
      elseif dest >= 0 and dest + 385 < #data then
        off = dest - (dest % 2)
      end
      if off and Battle.isSineTable(data, off) then return true end
      i = i + 1
    end
    return false
  end
  local copyAt
  local seen = {}
  forEachAnimTask(plans, function(t)
    if copyAt then return end
    if #(t.args or {}) ~= 0 then return end
    local at = atOf(t.fn)
    if not at or seen[at] then return end
    seen[at] = true
    if poolsSine(at) then copyAt = at return end
    local dests = Battle.blTargets(data, at, A.SCAN)
    local i = 1
    while i <= #dests do
      if poolsSine(dests[i]) then copyAt = dests[i] return end
      i = i + 1
    end
    local words = Battle.poolWords(data, at, A.SCAN)
    i = 1
    while i <= #words do
      local dest = words[i]
      if GbaBin.isRomPtr(dest, #data) then
        local inner = dest - (dest % 2) - GbaBin.ROM_BASE
        if poolsSine(inner) then copyAt = inner return end
      end
      i = i + 1
    end
  end)
  if not copyAt then return end
  local shape = Battle.afterimageShape()
  forEachAnimTask(plans, function(t, plan)
    if plan.afterimage then return end
    if #(t.args or {}) ~= 0 then return end
    local at = atOf(t.fn)
    if not at then return end
    local names = at == copyAt or poolsSine(at)
    if not names then
      local dests = Battle.blTargets(data, at, A.SCAN)
      local i = 1
      while i <= #dests do
        if dests[i] == copyAt then names = true break end
        i = i + 1
      end
    end
    if not names then
      local words = Battle.poolWords(data, at, A.SCAN)
      local i = 1
      while i <= #words do
        local flat = words[i] - (words[i] % 2)
        if flat == copyAt or flat == copyAt + GbaBin.ROM_BASE then
          names = true
          break
        end
        i = i + 1
      end
    end
    if names then plan.afterimage = shape end
  end)
end

function Battle.readAffineTable(data, off)
  local A = Battle.ANIM_AFFINE
  if off < 0 or off + A.STRIDE * A.MIN_STEPS >= #data then return nil end
  local steps = {}
  local i = 0
  while i < A.MAX_STEPS do
    local base = off + i * A.STRIDE
    if base + 7 >= #data then return nil end
    local first = GbaBin.u16(data, base)
    if first == A.END then
      if #steps < A.MIN_STEPS then return nil end
      local life, sx, sy, s = 0, 0, 0, 1
      while s <= #steps do
        life = life + steps[s].dur
        sx = sx + steps[s].dx * steps[s].dur
        sy = sy + steps[s].dy * steps[s].dur
        s = s + 1
      end
      return {
        kind = "affine",
        steps = steps,
        life = life,
        base = A.BASE,
        closes = (sx == 0 and sy == 0) or nil,
      }
    end
    if first == A.LOOP or first == A.JUMP then return nil end
    local dx = GbaBin.s16(data, base)
    local dy = GbaBin.s16(data, base + 2)
    local rot = GbaBin.u8(data, base + 4)
    local dur = GbaBin.u8(data, base + 5)
    local pad = GbaBin.u16(data, base + 6)
    if pad ~= 0 then return nil end
    if math.abs(dx) > A.MAX_DELTA or math.abs(dy) > A.MAX_DELTA then return nil end
    if dur < 1 or dur > A.MAX_DURATION then return nil end
    steps[#steps + 1] = { dx = dx, dy = dy, rot = rot, dur = dur }
    i = i + 1
  end
  return nil
end

local function appendPlanPose(plan, rec, hit)
  if not rec then return end
  local key = hit and "hitPoses" or "poses"
  local list = plan[key]
  if type(list) ~= "table" then
    list = {}
    plan[key] = list
  end
  list[#list + 1] = rec
end

function Battle.affinePoseFrom(t, table)
  if not table then return nil end
  local hops = t.args and t.args[2] or 1
  if hops < 1 then hops = 1 end
  local who = (t.args and t.args[1]) or 0
  return {
    at = t.at or 0,
    kind = "affine",
    steps = table.steps,
    life = table.life * hops,
    base = table.base,
    hops = hops,
    target = (who % 2 == 1) or nil,
    partner = (who >= 2) or nil,
  }
end

function Battle.classifyAffine(data, plans)
  if type(data) ~= "string" then return end
  local A = Battle.ANIM_AFFINE
  local tableOf, argc, bad = {}, {}, {}
  forEachAnimTask(plans, function(t)
    local fn = t.fn
    if not fn or bad[fn] then return end
    local n = #(t.args or {})
    if argc[fn] == nil then argc[fn] = n
    elseif argc[fn] ~= n then
      bad[fn] = true
      tableOf[fn] = nil
      return
    end
    if tableOf[fn] then return end
    local at = fn - (fn % 2)
    if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
    if at < 0 or at >= #data then return end
    local words = Battle.poolWords(data, at, A.SCAN)
    local i = 1
    while i <= #words do
      local dest = words[i]
      if GbaBin.isRomPtr(dest, #data) then
        local found = Battle.readAffineTable(data, dest - GbaBin.ROM_BASE)
        if found then
          tableOf[fn] = found
          break
        end
      end
      i = i + 1
    end
  end)
  forEachAnimTask(plans, function(t, plan)
    if bad[t.fn] then return end
    local table = tableOf[t.fn]
    if not table then return end
    appendPlanPose(plan, Battle.affinePoseFrom(t, table))
  end)
end

function Battle.minimizeLife()
  local M = Battle.ANIM_MINIMIZE
  return M.FRAMES * M.CYCLES + M.WAIT + (M.FRAMES / 2)
end

function Battle.minimizeShape(at)
  local M = Battle.ANIM_MINIMIZE
  return {
    at = at or 0,
    kind = "minimize",
    life = Battle.minimizeLife(),
    base = M.BASE,
    step = M.STEP,
    shrink = M.SHRINK,
    frames = M.FRAMES,
    cycles = M.CYCLES,
    wait = M.WAIT,
  }
end

function Battle.minimizeBodyOk(data, at)
  local M = Battle.ANIM_MINIMIZE
  local A = Battle.ANIM_AFTERIMAGE
  if not at or at < 0 or at >= #data then return false end
  local has100, has28 = false, false
  local i = 0
  while i < A.SCAN do
    local off = at + i * 2
    if off + 1 >= #data then break end
    local h = GbaBin.u16(data, off)
    if h == M.BASE then has100 = true end
    if h == M.STEP then has28 = true end
    local hi = math.floor(h / 256)
    if (hi >= 0x20 and hi <= 0x27 or hi >= 0x30 and hi <= 0x37)
        and (h % 256) == M.STEP then
      has28 = true
    end
    i = i + 1
  end
  local words = Battle.poolWords(data, at, A.SCAN)
  i = 1
  while i <= #words do
    if words[i] == M.BASE then has100 = true end
    if words[i] == M.STEP then has28 = true end
    i = i + 1
  end
  return has100 and has28
end

function Battle.classifyMinimize(data, plans)
  if type(data) ~= "string" then return end
  local argcOk, bodyOk = {}, {}
  forEachAnimTask(plans, function(t)
    local fn = t.fn
    if not fn then return end
    local n = #(t.args or {})
    if n ~= 0 then
      argcOk[fn] = false
    elseif argcOk[fn] ~= false then
      argcOk[fn] = true
    end
  end)
  local match
  local matches = 0
  for fn, ok in pairs(argcOk) do
    if ok then
      local at = fn - (fn % 2)
      if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
      if Battle.minimizeBodyOk(data, at) then
        matches = matches + 1
        match = fn
      end
    end
  end
  if matches ~= 1 then return end
  forEachAnimTask(plans, function(t, plan)
    if t.fn ~= match then return end
    if plan.afterimage then return end
    appendPlanPose(plan, Battle.minimizeShape(t.at or 0))
  end)
end

function Battle.extractSurfWave(data, plans)
  local at = Battle.findSurfTask(data, plans)
  if not at then return nil end
  local S = Battle.SURF_WAVE
  local words = Battle.poolWords(data, at, S.SCAN)
  local tiles, maps, pals = nil, {}, {}
  local i = 1
  while i <= #words do
    local w = words[i]
    if GbaBin.isRomPtr(w, #data) then
      local raw = lz77At(data, GbaBin.romOffset(w))
      if raw then
        if #raw == S.TILE_BYTES and not tiles then
          tiles = raw
        elseif #raw == S.MAP_BYTES and #maps < 2 then
          maps[#maps + 1] = raw
        elseif #raw == S.PAL_BYTES and #pals < 2 then
          pals[#pals + 1] = raw
        end
      end
    end
    i = i + 1
  end
  if not (tiles and maps[1] and maps[2] and pals[1]) then return nil end
  -- First 4096 in the pool is the opponent arm (GetBattlerSide == 1).
  local shape = Battle.surfMotionShape()
  local function stamp(side, tmap, praw, muddy)
    local colors = palFromBytes(praw)
    local image = composeSurfMap(tiles, tmap, colors, S)
    if not image then return nil end
    local rel = Battle.surfPath(side, muddy)
    ImageWriter.save(image, rel)
    return rel
  end
  local ok, err = pcall(function()
    shape.player.image = stamp("player", maps[2], pals[1], false)
    shape.opponent.image = stamp("opponent", maps[1], pals[1], false)
    if pals[2] then
      shape.muddyPlayer = stamp("player", maps[2], pals[2], true)
      shape.muddyOpponent = stamp("opponent", maps[1], pals[2], true)
    end
  end)
  if not ok or not (shape.player.image and shape.opponent.image) then
    return nil
  end
  return shape
end

function Battle.extractAnimBgs(data, plans)
  Battle._bgTableData, Battle._bgTableAt = nil, nil
  Battle._surfData, Battle._surfAt = nil, nil
  local bgs = {}
  local tableOff = Battle.findAnimBgTable(data)
  if tableOff then
    local id = 0
    while id < Battle.ANIM_BG.COUNT do
      local ok, img = pcall(Battle.renderAnimBg, data, tableOff, id)
      if ok and img then
        local path = Battle.animBgPath(id)
        ImageWriter.save(img, path)
        bgs[id] = path
        bgs[tostring(id)] = path
      end
      id = id + 1
    end
  end
  local wave = Battle.extractSurfWave(data, plans)
  if wave then
    forEachAnimTask(plans, function(t, plan)
      if plan.surf then return end
      local fn = t.fn
      if not fn then return end
      local at = fn - (fn % 2)
      if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
      if at ~= Battle._surfAt then return end
      local rec = Battle.surfMotionShape()
      rec.player.image = wave.player.image
      rec.opponent.image = wave.opponent.image
      rec.muddyPlayer = wave.muddyPlayer
      rec.muddyOpponent = wave.muddyOpponent
      local a0 = t.args and t.args[1]
      if a0 == 1 then
        rec.player.image = wave.muddyPlayer or rec.player.image
        rec.opponent.image = wave.muddyOpponent or rec.opponent.image
      end
      plan.surf = rec
    end)
  end
  return bgs
end

-- A MOVE ANIMATION IS A PROGRAM, not a sheet.
--
-- gBattleAnims_Moves (0x1C7168, confirmed against pokeruby's own
-- `gBattleAnims_Moves:: @ 81C7168`) holds one script pointer per move, and
-- battle_anim.c runs it a command at a time. This used to read the FIRST
-- BYTE of that script, keep a sprite tag if one happened to be there, and
-- hand the renderer a single sheet id -- which is why every move in Hoenn
-- drew the same expanding smear whatever it was.
--
-- The walk below is the cart's own: every length is what the matching
-- ScriptCmd_* in battle_anim.c advances sBattleAnimScriptPtr by, and the
-- opcodes are its sScriptCmdTable in order. `call`/`return` keep a stack,
-- `goto` follows, and jumpifcontest FALLS THROUGH (not a contest). jumpargeq
-- dests are remembered and walked as variant arms: Magnitude's pictures
-- sit entirely behind arg 15, so the fall-through is `end`.
--
-- Verified move by move against pokeruby: all 355 pointers equal the decomp
-- label addresses, and walking data/battle_anim_scripts.s the same way gives
-- the same createsprite count and the same total delay for all 355.
Battle.ANIM_CMD_LEN = {
  [0x00] = 3, [0x01] = 3, [0x04] = 2, [0x05] = 1, [0x09] = 3, [0x0A] = 2,
  [0x0B] = 2, [0x0C] = 3, [0x0D] = 1, [0x10] = 4, [0x12] = 6, [0x14] = 2,
  [0x15] = 1, [0x16] = 1, [0x17] = 1, [0x18] = 2, [0x19] = 4, [0x1A] = 2,
  [0x1B] = 7, [0x1C] = 6, [0x1D] = 5, [0x1E] = 3, [0x20] = 1, [0x22] = 2,
  [0x23] = 2, [0x24] = 5, [0x25] = 4, [0x26] = 7, [0x27] = 7, [0x28] = 2,
  [0x29] = 1, [0x2A] = 2, [0x2B] = 2, [0x2C] = 2, [0x2D] = 2, [0x2E] = 2,
  [0x2F] = 1,
}
Battle.ANIM_END = { [0x08] = true, [0x06] = true, [0x07] = true }
Battle.ANIM_MAX_STEPS = 4000
Battle.ANIM_MAX_DEPTH = 24
Battle.ANIM_MAX_EVENTS = 64
Battle.ANIM_MAX_ARGEQ = 8
-- An argument past a battler's own box is not a pixel offset, whatever else
-- the template's callback reads it as.
Battle.ANIM_MAX_OFFSET = 64
-- struct SpriteTemplate: u16 tileTag, u16 paletteTag, then oam/anims/images/
-- affineAnims/callback. The callback is the last word, twenty bytes in.
Battle.TEMPLATE_ANIMS = 8
Battle.TEMPLATE_CALLBACK = 20
-- union AnimCmd: low halfword is the image (or END/JUMP/LOOP), next six bits
-- are how long that image is held. END is 0xFFFF (does not repeat); JUMP and
-- LOOP sit just below it.
Battle.ANIMCMD_END = 0xFFFD
Battle.ANIMCMD_STOP = 0xFFFF
Battle.ANIMCMD_MAX = 32
-- StartAnimLinearTranslation (pokeruby rom_8077ABC.c): data[1] = pos1.x,
-- data[3] = pos1.y, then InitAnimLinearTranslation. Same four halfwords as
-- Emerald; the function's address is found by this shape, not a symbol.
Battle.ANIM_MOTION = {
  LINEAR_SHAPE = { 0x8c20, 0x8620, 0x8c60, 0x86a0 },
  LINEAR_AT = 2,
  SCAN = 48,
  MIN_FRAMES = 1,
  MAX_FRAMES = 120,
  -- InitAnimArcTranslation: 0x8000 / duration after the shared linear stores.
  ARC_CONST = 0x8000,
  MIN_ARC_AMP = 4,
  MAX_ARC_AMP = 80,
  MIN_ORBIT = 8,
  MAX_ORBIT = 64,
  MIN_ORBIT_N = 4,
  MIN_ORBIT_ANGLES = 3,
  MAX_DRIFT = 8,
  MAX_DRIFT_FRAMES = 40,
  EWRAM_LO = 0x02000000,
  EWRAM_HI = 0x02040000,
}
-- AnimTask_ShakeMon / ShakeMon2 argument shape: battler, x, y, count, delay.
-- Both axes nonzero is TranslateMonElliptical (Tail Whip 12,4), not a shake.
Battle.ANIM_SHAKE = {
  MAX_BATTLER = 8,
  MAX_COUNT = 255,
  MAX_DELAY = 16,
}
-- AnimTask_HorizontalShake / sub_80E1864: who, intensity, duration.
-- Earthquake is (5, 10, 50) then (4, 10, 50). Five-arg ShakeMon is not this.
Battle.ANIM_CAM = {
  MAX_AMP = 16,
  MIN_DUR = 8,
  MAX_DUR = 80,
}
-- UnpackSelectedBattleAnimPalettes / BlendMonInAndOut.
-- 15-bit BGR, 32767 white; coeff is out of 16 (BlendPalettes).
Battle.ANIM_BLEND = {
  MAX_SELECTOR = 31,
  MAX_STEP = 32,
  COLOUR_MAX = 32767,
  FULL = 16,
  BRIGHT = 255,
}
-- Mon-sprite tasks that are not ShakeMon: ellipse (both axes), scale,
-- sway (period is hundreds), wind-up lunge (7 args), shake-and-sink.
Battle.ANIM_POSE = {
  MAX_AMP = 64,
  MAX_LOOPS = 8,
  MAX_SPEED = 5,
  MAX_PERIOD = 8192,
  MIN_PERIOD = 256,
  MAX_HALVES = 32,
  MAX_SCALE = 32,
  MAX_TRAVEL = 160,
  MAX_FRAMES = 120,
  MAX_WAIT = 60,
  MAX_SINK = 256,
}
-- gBattleAnimBackgroundTable: 27 records of {image, pal, tilemap}. 0 and 1
-- are the same three pointers (BG_DARK_ / BG_DARK).
Battle.ANIM_BG = {
  COUNT = 27,
  ENTRY = 12,
  MAP_W = 32,
  VIEW_W = 30,
  VIEW_H = 20,
}
-- AnimTask_CreateSurfWave. Motion numbers are the C literals, not addresses.
-- HBlank shear stays out; the layer scrolls flat like Emerald.
Battle.SURF_WAVE = {
  TILE_BYTES = 8192,
  MAP_BYTES = 4096,
  PAL_BYTES = 32,
  CELLS = 32,
  BLOCKS = 2,
  ROWS = 32,
  POOL = { 0x0000FF20, 0x0000FFD0, 0x0000FFFE, 0x0000FFFF },
  PLAYER = { x = 0, y = -48, dx = -2, dy = 1 },
  OPPONENT = { x = -224, y = 256, dx = 2, dy = -1 },
  FADE = 13,
  HOLD = 54,
  STEP = 2,
  BLEND_OF = 16,
  SCAN = 260,
}
-- Double Team copies: 2 ghosts, 64 steps of 2 frames, gSineTable /6 and /13.
Battle.ANIM_AFTERIMAGE = {
  COPIES = 2,
  STEPS = 64,
  FRAMES_PER_STEP = 2,
  PHASE_STEP = 128,
  RADIUS_DIV = 6,
  ANGLE_DIV = 13,
  SCAN = 120,
  PAL = 0x2771,
}
-- AffineAnimCmd, 8 bytes, closed by 0x7FFF. Deltas per frame, base 256.
Battle.ANIM_AFFINE = {
  END = 0x7FFF,
  LOOP = 0x7FFD,
  JUMP = 0x7FFE,
  STRIDE = 8,
  MAX_STEPS = 16,
  MIN_STEPS = 2,
  BASE = 256,
  MAX_DELTA = 512,
  MAX_DURATION = 255,
  SCAN = 240,
}
-- Minimize: scale 256 += 0x28 for 32 frames, three times.
Battle.ANIM_MINIMIZE = {
  BASE = 256,
  STEP = 0x28,
  SHRINK = 0x50,
  FRAMES = 32,
  CYCLES = 3,
  WAIT = 32,
}
-- First operand is a song id. Lengths are ANIM_CMD_LEN; 0x1F is variable.
Battle.SOUND_OPS = {
  [0x09] = true,  -- playse
  [0x19] = true,  -- playsewithpan
  [0x1B] = true,  -- panse
  [0x1C] = true,  -- loopsewithpan
  [0x1D] = true,  -- waitplaysewithpan
  [0x26] = true,  -- panse_adjustnone
  [0x27] = true,  -- panse_adjustall
}
Battle.SE_MIN = 1
Battle.SE_MAX = 500
Battle.SE_LOOP_MAX = 16
Battle.ANIM_PARTICLE_FRAMES = 18
-- pokeruby data/battle_anim_scripts.s: delay-opcode totals and createsprite
-- counts for the Route 101 set. waitforvisualfinish is not a delay.
Battle.ROUTE101 = {
  { id = 33, name = "TACKLE", delay = 6, sprites = 2 },
  { id = 10, name = "SCRATCH", delay = 0, sprites = 1 },
  { id = 52, name = "EMBER", delay = 36, sprites = 6 },
  { id = 55, name = "WATER_GUN", delay = 20, sprites = 5 },
  { id = 45, name = "GROWL", delay = 45, sprites = 6 },
}

-- OBJ size by the OAM's shape and size bits. The hardware's table, not a
-- choice: shape 0 is square, 1 wide, 2 tall.
Battle.ANIM_OBJ_DIM = {
  [0] = { { 8, 8 }, { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { { 16, 8 }, { 32, 8 }, { 32, 16 }, { 64, 32 } },
  [2] = { { 8, 16 }, { 8, 32 }, { 16, 32 }, { 32, 64 } },
}

-- How big the particle this template spawns actually is. The size belongs to
-- the TEMPLATE, not to the sheet: 242 of the createsprites in Hoenn draw a
-- sheet at a size some other template draws it at differently, so a
-- per-sheet answer would be wrong for one of them.
local function animFrameSize(data, tmpl)
  if not GbaBin.isRomPtr(tmpl, #data) then return nil end
  local oam = GbaBin.u32(data, tmpl - GbaBin.ROM_BASE + 4)
  if not GbaBin.isRomPtr(oam, #data) then return nil end
  local off = oam - GbaBin.ROM_BASE
  local shape = math.floor(GbaBin.u16(data, off) / 0x4000) % 4
  local size = math.floor(GbaBin.u16(data, off + 2) / 0x4000) % 4
  local row = Battle.ANIM_OBJ_DIM[shape]
  local wh = row and row[size + 1]
  if not wh then return nil end
  return wh[1], wh[2]
end

-- struct SpriteTemplate is { u16 tileTag, u16 paletteTag, ptr oam, ... }, so
-- the sheet a createsprite draws from is the tag at the template's first
-- halfword, and ANIM_TAG_BASE (0x2710 = ANIM_TAG_BONE) makes it an index
-- into the particle sheets we already extract.
local function animSheetOf(data, tmpl)
  if not GbaBin.isRomPtr(tmpl, #data) then return nil end
  local tag = GbaBin.u16(data, tmpl - GbaBin.ROM_BASE)
  local id = tag - Battle.ANIM_TAG_BASE
  if id >= 0 and id < Battle.ANIM_PIC_COUNT then return id end
  return nil
end

local function inOffsetRange(v)
  return v <= Battle.ANIM_MAX_OFFSET and v >= -Battle.ANIM_MAX_OFFSET
end

-- LDR Rd,[PC,#imm] literals in the first `count` Thumb instructions.
function Battle.poolWords(data, at, count)
  local out = {}
  local limit = #data
  for i = 0, (count or 16) - 1 do
    local off = at + i * 2
    if off + 1 >= limit then break end
    local h = GbaBin.u16(data, off)
    if math.floor(h / 2048) == 0x09 then
      local pc = off + 4
      local base = pc - (pc % 4)
      local wordOff = base + (h % 256) * 4
      if wordOff + 3 < limit then
        out[#out + 1] = GbaBin.u32(data, wordOff)
      end
    end
  end
  return out
end

-- Thumb BL destinations in the first `count` instructions. A BL is two
-- halfwords (0xF000 / 0xF800) and is how a callback names InitAnimSpritePos
-- or sub_8078764 -- those helpers are not in its literal pool.
function Battle.blTargets(data, at, count)
  local out = {}
  local limit = #data
  local i = 0
  local n = (count or 64) - 1
  while i < n do
    local off = at + i * 2
    if off + 3 >= limit then break end
    local hi = GbaBin.u16(data, off)
    local lo = GbaBin.u16(data, off + 2)
    if math.floor(hi / 2048) == 0x1E and math.floor(lo / 2048) == 0x1F then
      local high = hi % 2048
      if high >= 1024 then high = high - 2048 end
      local pc = off + 4
      out[#out + 1] = pc + high * 4096 + (lo % 2048) * 2
      i = i + 2
    else
      i = i + 1
    end
  end
  return out
end

local function fileOff(word)
  if not word then return nil end
  local at = word - (word % 2)
  if at >= GbaBin.ROM_BASE then at = at - GbaBin.ROM_BASE end
  return at
end

-- InitAnimArcTranslation builds 0x8000 / data[0] after the same x/y stores
-- as StartAnimLinearTranslation. A pool 0x8000, or mov #0x80; lsl #8, is
-- how the two are told apart -- they share LINEAR_SHAPE, and Arc is first
-- in rom_8077ABC.c.
local function poolHasWord(data, at, want)
  local words = Battle.poolWords(data, at, Battle.ANIM_MOTION.SCAN)
  for i = 1, #words do
    if words[i] == want then return true end
  end
  return false
end

local function builds8000(data, at)
  local M = Battle.ANIM_MOTION
  if poolHasWord(data, at, M.ARC_CONST) then return true end
  local limit = #data - 1
  local last = at + M.SCAN * 2
  if last > limit then last = limit end
  local off = at
  while off + 3 <= last do
    local h = GbaBin.u16(data, off)
    if math.floor(h / 256) >= 0x20 and math.floor(h / 256) <= 0x27
        and (h % 256) == 0x80 then
      local j = 1
      while j <= 4 do
        local n = off + j * 2
        if n + 1 > last then break end
        local h2 = GbaBin.u16(data, n)
        if math.floor(h2 / 2048) == 0 and math.floor(h2 / 64) % 32 == 8 then
          return true
        end
        j = j + 1
      end
    end
    off = off + 2
  end
  return false
end

local function findLinearShape(data, wantArc)
  local M = Battle.ANIM_MOTION
  local sh = M.LINEAR_SHAPE
  local needle = string.char(
    sh[1] % 256, math.floor(sh[1] / 256) % 256,
    sh[2] % 256, math.floor(sh[2] / 256) % 256,
    sh[3] % 256, math.floor(sh[3] / 256) % 256,
    sh[4] % 256, math.floor(sh[4] / 256) % 256)
  local from = 1
  while true do
    local i = data:find(needle, from, true)
    if not i then break end
    local shapeAt = i - 1
    if shapeAt % 2 == 0 then
      local fn = shapeAt - M.LINEAR_AT * 2
      if fn >= 0 then
        if builds8000(data, fn) == wantArc then return fn end
      end
    end
    from = i + 1
  end
  return nil
end

-- StartAnimLinearTranslation as a file offset, or nil. Memoised per ROM
-- string so 355 scripts do not rescan 16MB. Skips InitAnimArcTranslation.
function Battle.findStartAnimLinear(data)
  if Battle._linearData == data then return Battle._linearAt end
  Battle._linearData = data
  Battle._linearAt = findLinearShape(data, false)
  return Battle._linearAt
end

function Battle.findInitAnimArc(data)
  if Battle._arcData == data then return Battle._arcAt end
  Battle._arcData = data
  Battle._arcAt = findLinearShape(data, true)
  return Battle._arcAt
end

local function namesHelper(data, at, helper)
  if not helper then return false end
  local want = helper + GbaBin.ROM_BASE
  local words = Battle.poolWords(data, at, Battle.ANIM_MOTION.SCAN)
  for i = 1, #words do
    local flat = words[i] - (words[i] % 2)
    if flat == want then return true end
  end
  local dests = Battle.blTargets(data, at, Battle.ANIM_MOTION.SCAN)
  for i = 1, #dests do
    if dests[i] == helper then return true end
  end
  return false
end

-- Where this template's callback starts the sprite, and whether it hands
-- the sprite to StartAnimLinearTranslation (attacker → target over arg 4)
-- or InitAnimArcTranslation (same lerp plus a sine bulge on y).
-- InitAnimSpritePos vs sub_8078764 are found by the adjacent EWRAM bytes
-- they load (gBattleAnimAttacker / gBattleAnimTarget), not by a symbol.
function Battle.animMotionOf(data, callback, helpers)
  if not callback then return nil, nil end
  helpers = helpers or Battle._animHelpers
  local at = fileOff(callback)
  if not at or at < 0 or at >= #data then return nil, nil end
  local linear = (helpers and helpers.linear) or Battle.findStartAnimLinear(data)
  local arc = (helpers and helpers.arc) or Battle.findInitAnimArc(data)
  local from, motion = nil, nil
  if namesHelper(data, at, linear) then
    motion = "linear"
    from = "attacker"
  elseif namesHelper(data, at, arc) then
    motion = "arc"
    from = "attacker"
  end
  if not from and helpers then
    local dests = Battle.blTargets(data, at, Battle.ANIM_MOTION.SCAN)
    for i = 1, #dests do
      if helpers.initTarget and dests[i] == helpers.initTarget then
        from = "target"
        break
      elseif helpers.initAttacker and dests[i] == helpers.initAttacker then
        from = "attacker"
        break
      end
    end
  end
  return from, motion
end

-- InitAnimSpritePos and sub_8078764 load gBattleAnimAttacker and
-- gBattleAnimTarget, two adjacent EWRAM bytes. Sprite callbacks BL them.
function Battle.discoverAnimHelpers(data, plans)
  local linear = Battle.findStartAnimLinear(data)
  local M = Battle.ANIM_MOTION
  local ewrOf = {}
  local seen = {}
  local function noteCb(cb)
    if not cb or seen[cb] then return end
    seen[cb] = true
    local at = fileOff(cb)
    if not at then return end
    local dests = Battle.blTargets(data, at, M.SCAN)
    for i = 1, #dests do
      local dest = dests[i]
      if dest >= 0 and dest < #data then
        local words = Battle.poolWords(data, dest, 24)
        for w = 1, #words do
          local addr = words[w]
          if addr >= M.EWRAM_LO and addr < M.EWRAM_HI then
            ewrOf[dest] = ewrOf[dest] or {}
            ewrOf[dest][addr] = (ewrOf[dest][addr] or 0) + 1
          end
        end
      end
    end
  end
  for _, plan in pairs(plans or {}) do
    local events = plan.events or {}
    for i = 1, #events do
      noteCb(events[i].cb)
    end
    events = plan.hitEvents or {}
    for i = 1, #events do
      noteCb(events[i].cb)
    end
  end
  local initAttacker, initTarget
  local best = 0
  local fns = {}
  for fn in pairs(ewrOf) do fns[#fns + 1] = fn end
  for a = 1, #fns do
    for b = a + 1, #fns do
      local fa, fb = fns[a], fns[b]
      for addr in pairs(ewrOf[fa]) do
        if ewrOf[fb][addr + 1] then
          local score = (ewrOf[fa][addr] or 0) + (ewrOf[fb][addr + 1] or 0)
          if score > best then
            best = score
            initAttacker, initTarget = fa, fb
          end
        elseif ewrOf[fb][addr - 1] then
          local score = (ewrOf[fa][addr] or 0) + (ewrOf[fb][addr - 1] or 0)
          if score > best then
            best = score
            initAttacker, initTarget = fb, fa
          end
        end
      end
    end
  end
  local helpers = {
    linear = linear,
    arc = Battle.findInitAnimArc(data),
    initAttacker = initAttacker,
    initTarget = initTarget,
  }
  Battle._animHelpers = helpers
  return helpers
end

local function eachPlanEvent(plans, fn)
  for _, plan in pairs(plans or {}) do
    local events = plan.events or {}
    for i = 1, #events do fn(events[i]) end
    events = plan.hitEvents or {}
    for i = 1, #events do fn(events[i]) end
    local arms = plan.argEq
    if type(arms) == "table" then
      for a = 1, #arms do
        events = arms[a].events or {}
        for i = 1, #events do fn(events[i]) end
      end
    end
  end
end

local function applyArcArgs(e)
  local a = e.args
  if type(a) ~= "table" then return end
  if a[5] then e.travel = a[5] end
  if a[6] then e.amp = a[6] end
end

local function classifyOneEvent(data, e, helpers)
  local from, motion = Battle.animMotionOf(data, e.cb, helpers)
  if motion then
    e.motion = motion
    e.from = from or e.from
    if motion == "arc" then applyArcArgs(e) end
  elseif from then
    e.from = from
    if e.motion == "linear" and from == "target" then
      e.motion = nil
    end
  end
end

function Battle.classifyEventMotion(data, plans)
  local helpers = Battle._animHelpers or Battle.discoverAnimHelpers(data, plans)
  eachPlanEvent(plans, function(e)
    classifyOneEvent(data, e, helpers)
  end)
  Battle.classifyEventPaths(plans)
end

function Battle.arcShapeOk(e)
  local M = Battle.ANIM_MOTION
  local a = e and e.args
  if type(a) ~= "table" or #a < 6 then return false end
  local dur = a[5] or 0
  if dur < M.MIN_FRAMES or dur > M.MAX_FRAMES then return false end
  local amp = a[6] or 0
  if amp < 0 then amp = -amp end
  if amp < M.MIN_ARC_AMP or amp > M.MAX_ARC_AMP then return false end
  return true
end

function Battle.circleShapeOk(e)
  local M = Battle.ANIM_MOTION
  local a = e and e.args
  if type(a) ~= "table" or #a ~= 2 then return false end
  local dur, ang = a[1] or 0, a[2] or -1
  if dur < M.MIN_ORBIT or dur > M.MAX_ORBIT then return false end
  if ang < 0 or ang > 255 then return false end
  return true
end

function Battle.driftShapeOk(e)
  local M = Battle.ANIM_MOTION
  local a = e and e.args
  if type(a) ~= "table" or #a ~= 3 then return false end
  local dx, dy, dur = a[1] or 0, a[2] or 0, a[3] or 0
  if dx == 0 and dy == 0 then return false end
  if dx > M.MAX_DRIFT or dx < -M.MAX_DRIFT then return false end
  if dy > M.MAX_DRIFT or dy < -M.MAX_DRIFT then return false end
  if dur < M.MIN_FRAMES or dur > M.MAX_DRIFT_FRAMES then return false end
  return true
end

function Battle.classifyEventPaths(plans)
  local byCb = {}
  eachPlanEvent(plans, function(e)
    local cb = e.cb
    if not cb then return end
    byCb[cb] = byCb[cb] or {}
    local list = byCb[cb]
    list[#list + 1] = e
  end)
  for _, list in pairs(byCb) do
    local linear, allArc, allCircle, allDrift = false, true, true, true
    local angles, nAng = {}, 0
    for i = 1, #list do
      local e = list[i]
      if e.motion == "linear" then linear = true end
      if not Battle.arcShapeOk(e) then allArc = false end
      if not Battle.circleShapeOk(e) then allCircle = false end
      if not Battle.driftShapeOk(e) then allDrift = false end
      local a = e.args
      if a and a[2] ~= nil and angles[a[2]] == nil then
        angles[a[2]] = true
        nAng = nAng + 1
      end
    end
    local M = Battle.ANIM_MOTION
    if linear then
      -- Ember's 6th operand is 1, not a sine amp.
    elseif allArc then
      for i = 1, #list do
        list[i].motion = "arc"
        if not list[i].from then list[i].from = "attacker" end
        applyArcArgs(list[i])
      end
    elseif allCircle and #list >= M.MIN_ORBIT_N and nAng >= M.MIN_ORBIT_ANGLES then
      for i = 1, #list do
        local e = list[i]
        local dur = e.args[1]
        e.motion = "circle"
        e.from = "attacker"
        e.orbit = dur
        e.angle = e.args[2]
        e.travel = dur * 2
        e.x, e.y = nil, nil
      end
    elseif allDrift then
      for i = 1, #list do
        local e = list[i]
        e.motion = "drift"
        if not e.from then e.from = "attacker" end
        e.travel = e.args[3]
        e.dx, e.dy = nil, nil
      end
    end
  end
end

function Battle.shakeShapeOk(t)
  local S = Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local who = t.args[1]
  if not who or who < 0 or who > S.MAX_BATTLER then return false end
  local x, y = t.args[2] or 0, t.args[3] or 0
  if x > Battle.ANIM_MAX_OFFSET or x < -Battle.ANIM_MAX_OFFSET then return false end
  if y > Battle.ANIM_MAX_OFFSET or y < -Battle.ANIM_MAX_OFFSET then return false end
  -- one axis: ShakeMon. both set: elliptical translate (Tail Whip).
  if x ~= 0 and y ~= 0 then return false end
  local count, delay = t.args[4] or 0, t.args[5] or -1
  if count < 1 or count > S.MAX_COUNT then return false end
  if delay < 0 or delay > S.MAX_DELAY then return false end
  return true
end

-- Three args: battler-like who, intensity, duration (Earthquake 5,10,50).
function Battle.camShakeShapeOk(t)
  local C = Battle.ANIM_CAM
  local S = Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 3 then
    return false
  end
  local who, amp, dur = t.args[1] or -1, t.args[2] or 0, t.args[3] or 0
  if who < 0 or who > S.MAX_BATTLER then return false end
  -- 0 means "use gAnimMovePower/10+3" (Magnitude). Earthquake passes 10.
  if amp < 0 or amp > C.MAX_AMP then return false end
  if dur < C.MIN_DUR or dur > C.MAX_DUR then return false end
  return true
end

-- Six args: selector 0..31, delay, cycles, from, to, 15-bit BGR.
-- Recover 2,0,6,0,11,12287. Bide red 31 is a legal colour (not "bright").
function Battle.blendPulseShapeOk(t)
  local B = Battle.ANIM_BLEND
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 6 then
    return false
  end
  local sel = t.args[1]
  if sel == nil or sel < 0 or sel > B.MAX_SELECTOR then return false end
  for i = 2, 5 do
    local v = t.args[i] or 999
    if v > B.MAX_STEP or v < -B.MAX_STEP then return false end
  end
  local colour = t.args[6]
  return colour ~= nil and colour >= 0 and colour <= B.COLOUR_MAX
end

-- Five args, colour LAST: selector, delay, from, to, BGR.
-- White impact flash. Selector may be 1920 (HAZE positions).
function Battle.blendFlashShapeOk(t)
  local B = Battle.ANIM_BLEND
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local sel = t.args[1]
  if sel == nil or sel < 0 then return false end
  for i = 2, 4 do
    local v = t.args[i] or 999
    if v > B.MAX_STEP or v < -B.MAX_STEP then return false end
  end
  local colour = t.args[5]
  return colour ~= nil and colour >= 0 and colour <= B.COLOUR_MAX
end

-- AnimTask_BlendMonInAndOut: battler, colour, peak, delay, cycles.
-- Colour is SECOND. Last is a cycle count, never a 15-bit white.
function Battle.blendMonShapeOk(t)
  local B = Battle.ANIM_BLEND
  local S = Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local who = t.args[1]
  if who == nil or who < 0 or who > S.MAX_BATTLER then return false end
  local colour = t.args[2]
  if colour == nil or colour < 0 or colour > B.COLOUR_MAX then return false end
  local peak, delay, cycles = t.args[3] or 0, t.args[4] or -1, t.args[5] or 0
  if peak < 1 or peak > B.FULL then return false end
  if delay < 0 or delay > S.MAX_DELAY then return false end
  if cycles < 1 or cycles > B.FULL then return false end
  return true
end

local function poseAmpOk(v, lo, hi)
  if v == nil then return false end
  if v < 0 then v = -v end
  return v >= lo and v <= hi
end

-- TranslateMonElliptical: battler, w, h both nonzero, loops, speed 0-5.
-- Tail Whip RespectSide is 12, 4, 2, 3. Both axes set so it is not ShakeMon.
function Battle.ellipseShapeOk(t)
  local P, S = Battle.ANIM_POSE, Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local who = t.args[1]
  if who == nil or who < 0 or who > S.MAX_BATTLER then return false end
  local w, h = t.args[2] or 0, t.args[3] or 0
  if w == 0 or h == 0 then return false end
  if not poseAmpOk(w, 1, P.MAX_AMP) then return false end
  if not poseAmpOk(h, 1, P.MAX_AMP) then return false end
  local loops, speed = t.args[4] or 0, t.args[5] or -1
  if loops < 1 or loops > P.MAX_LOOPS then return false end
  if speed < 0 or speed > P.MAX_SPEED then return false end
  return true
end

-- ScaleMonAndRestore: dx, dy, duration, battler, mode.
-- Hidden Power / Recover squeeze is -7, -7, 11, ATTACKER, 0.
function Battle.scaleShapeOk(t)
  local P, S = Battle.ANIM_POSE, Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local dx, dy = t.args[1] or 0, t.args[2] or 0
  if dx == 0 and dy == 0 then return false end
  if dx < -P.MAX_SCALE or dx > P.MAX_SCALE then return false end
  if dy < -P.MAX_SCALE or dy > P.MAX_SCALE then return false end
  local dur = t.args[3] or 0
  if dur < 1 or dur > P.MAX_SCALE then return false end
  local who = t.args[4]
  if who == nil or who < 0 or who > S.MAX_BATTLER then return false end
  local mode = t.args[5] or 0
  if mode ~= 0 and mode ~= 1 then return false end
  return true
end

-- SwayMon: axis, amp, period, halves, battler. Period is hundreds of
-- units; ShakeMon's third arg is a pixel axis and never 256+.
function Battle.swayShapeOk(t)
  local P, S = Battle.ANIM_POSE, Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local axis = t.args[1]
  if axis ~= 0 and axis ~= 1 then return false end
  if not poseAmpOk(t.args[2], 1, P.MAX_AMP) then return false end
  local period = t.args[3] or 0
  if period < P.MIN_PERIOD or period > P.MAX_PERIOD then return false end
  local halves = t.args[4] or 0
  if halves < 1 or halves > P.MAX_HALVES then return false end
  local who = t.args[5]
  if who == nil or who < 0 or who > S.MAX_BATTLER then return false end
  return true
end

-- WindUpLunge: battler, x1, arc, t1, wait, x2, t2. Take Down is 7-arg.
function Battle.lungeShapeOk(t)
  local P, S = Battle.ANIM_POSE, Battle.ANIM_SHAKE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 7 then
    return false
  end
  local who = t.args[1]
  if who == nil or who < 0 or who > S.MAX_BATTLER then return false end
  if not poseAmpOk(t.args[2], 1, P.MAX_TRAVEL) then return false end
  local arc = t.args[3] or 0
  if arc < 0 or arc > P.MAX_AMP then return false end
  local t1, wait = t.args[4] or 0, t.args[5] or -1
  if t1 < 1 or t1 > P.MAX_FRAMES then return false end
  if wait < 0 or wait > P.MAX_WAIT then return false end
  if not poseAmpOk(t.args[6], 1, P.MAX_TRAVEL) then return false end
  local t2 = t.args[7] or 0
  if t2 < 1 or t2 > P.MAX_FRAMES then return false end
  return true
end

-- ShakeAndSinkMon: battler, x, delay, subpixel speed, duration.
-- Arg 4 is 8.8 speed (96), not a ShakeMon delay.
function Battle.sinkShapeOk(t)
  local Sh, P = Battle.ANIM_SHAKE, Battle.ANIM_POSE
  if type(t) ~= "table" or type(t.args) ~= "table" or #t.args ~= 5 then
    return false
  end
  local who = t.args[1]
  if who == nil or who < 0 or who > Sh.MAX_BATTLER then return false end
  if not poseAmpOk(t.args[2], 1, Battle.ANIM_MAX_OFFSET) then return false end
  local delay = t.args[3] or -1
  if delay < 0 or delay > Sh.MAX_DELAY then return false end
  local speed = t.args[4] or 0
  if speed < 1 or speed > P.MAX_SINK then return false end
  local dur = t.args[5] or 0
  if dur <= Sh.MAX_DELAY or dur > P.MAX_FRAMES then return false end
  return true
end

local function eachPlanTask(plans, fn)
  for _, plan in pairs(plans or {}) do
    local tasks = plan.tasks or {}
    for i = 1, #tasks do fn(tasks[i]) end
    tasks = plan.hitTasks or {}
    for i = 1, #tasks do fn(tasks[i]) end
    local arms = plan.argEq
    if type(arms) == "table" then
      for a = 1, #arms do
        tasks = arms[a].tasks or {}
        for i = 1, #tasks do fn(tasks[i]) end
      end
    end
  end
end

local function shakesFrom(tasks, fnOk)
  local list = {}
  for i = 1, #(tasks or {}) do
    local t = tasks[i]
    if fnOk[t.fn] then
      local who = t.args[1] or 0
      list[#list + 1] = {
        at = t.at or 0,
        target = (who % 2 == 1) or nil,
        x = t.args[2] or 0,
        y = t.args[3] or 0,
        count = t.args[4] or 1,
        delay = t.args[5] or 0,
      }
    end
  end
  if #list > 0 then return list end
  return nil
end

local function camsFrom(tasks, fnOk)
  local list = {}
  for i = 1, #(tasks or {}) do
    local t = tasks[i]
    if fnOk[t.fn] then
      list[#list + 1] = {
        at = t.at or 0,
        x = t.args[2] or 0,
        y = 0,
        count = t.args[3] or 1,
        delay = 0,
        power = ((t.args[2] or 0) == 0) or nil,
      }
    end
  end
  if #list > 0 then return list end
  return nil
end

function Battle.classifyCams(plans)
  local fnOk = {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    if fnOk[fn] ~= false then
      fnOk[fn] = Battle.camShakeShapeOk(t) and (fnOk[fn] ~= false) or false
    end
  end)
  for _, plan in pairs(plans or {}) do
    plan.cams = camsFrom(plan.tasks, fnOk)
    plan.hitCams = camsFrom(plan.hitTasks, fnOk)
    local arms = plan.argEq
    if type(arms) == "table" then
      for i = 1, #arms do
        arms[i].cams = camsFrom(arms[i].tasks, fnOk)
      end
    end
  end
end

local function blendBit(sel, n)
  return math.floor((sel or 0) / (2 ^ n)) % 2 == 1
end

local function pushBlendSides(list, t, rec)
  local sel = t.args[1] or 0
  local n = 0
  local function add(target, partner, side)
    list[#list + 1] = {
      at = rec.at, target = target, partner = partner, side = side, sel = sel,
      oneWay = rec.oneWay, step = rec.step, cycles = rec.cycles,
      from = rec.from, to = rec.to, colour = rec.colour,
    }
    n = n + 1
  end
  if blendBit(sel, 1) then add(nil, nil, nil) end
  if blendBit(sel, 3) then add(nil, true, nil) end
  if blendBit(sel, 2) then add(true, nil, nil) end
  if blendBit(sel, 4) then add(true, true, nil) end
  if blendBit(sel, 0) then add(nil, nil, "bg") end
  if blendBit(sel, 7) or blendBit(sel, 8) then add(nil, nil, "player") end
  if blendBit(sel, 9) or blendBit(sel, 10) then add(nil, nil, "enemy") end
  return n
end

local function fillBlendHolds(list, scriptFrames)
  for i = 1, #list do
    local one = list[i]
    if one.oneWay or one.from == one.to then
      local nextAt = nil
      for j = 1, #list do
        local other = list[j]
        if other ~= one
            and (other.target or false) == (one.target or false)
            and other.side == one.side
            and (other.at or 0) > (one.at or 0)
            and (nextAt == nil or other.at < nextAt) then
          nextAt = other.at
        end
      end
      local last = nextAt or scriptFrames or ((one.at or 0) + 1)
      one.hold = math.max(1, last - (one.at or 0))
    end
  end
end

local function blendsFrom(tasks, kindOf, scriptFrames)
  local list = {}
  for i = 1, #(tasks or {}) do
    local t = tasks[i]
    local kind = kindOf[t.fn]
    if kind == "pulse" then
      pushBlendSides(list, t, {
        at = t.at or 0,
        step = math.max(1, (t.args[2] or 0) + 1),
        cycles = math.max(1, t.args[3] or 1),
        from = t.args[4] or 0,
        to = t.args[5] or 0,
        colour = t.args[6] or 0,
      })
    elseif kind == "flash" then
      pushBlendSides(list, t, {
        at = t.at or 0,
        oneWay = true,
        step = math.max(1, (t.args[2] or 0) + 1),
        cycles = 1,
        from = t.args[3] or 0,
        to = t.args[4] or 0,
        colour = t.args[5] or 0,
      })
    elseif kind == "mon" then
      local who = t.args[1] or 0
      list[#list + 1] = {
        at = t.at or 0,
        target = (who % 2 == 1) or nil,
        partner = (who == 2 or who == 3) or nil,
        step = math.max(1, t.args[4] or 1),
        cycles = math.max(1, t.args[5] or 1),
        from = 0,
        to = t.args[3] or 1,
        colour = t.args[2] or 0,
      }
    end
  end
  if #list < 1 then return nil end
  fillBlendHolds(list, scriptFrames)
  return list
end

function Battle.classifyBlends(plans)
  local pulseOk, flashOk, monOk = {}, {}, {}
  local flashBright, monBright = {}, {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    if pulseOk[fn] ~= false then
      pulseOk[fn] = Battle.blendPulseShapeOk(t) and (pulseOk[fn] ~= false) or false
    end
    if flashOk[fn] ~= false then
      flashOk[fn] = Battle.blendFlashShapeOk(t) and (flashOk[fn] ~= false) or false
    end
    if (t.args[#t.args] or 0) > Battle.ANIM_BLEND.BRIGHT then
      flashBright[fn] = true
    end
    if monOk[fn] ~= false then
      monOk[fn] = Battle.blendMonShapeOk(t) and (monOk[fn] ~= false) or false
    end
    if (t.args[2] or 0) > Battle.ANIM_BLEND.BRIGHT then
      monBright[fn] = true
    end
  end)
  local argc = {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    local n = #t.args
    if argc[fn] == nil then argc[fn] = n
    elseif argc[fn] ~= n then
      pulseOk[fn], flashOk[fn], monOk[fn] = false, false, false
    end
  end)
  local kindOf = {}
  for fn, ok in pairs(pulseOk) do
    if ok then kindOf[fn] = "pulse" end
  end
  for fn, ok in pairs(flashOk) do
    if ok and flashBright[fn] and not kindOf[fn] then
      kindOf[fn] = "flash"
    end
  end
  for fn, ok in pairs(monOk) do
    if ok and monBright[fn] and not kindOf[fn] then
      kindOf[fn] = "mon"
    end
  end
  for _, plan in pairs(plans or {}) do
    plan.blends = blendsFrom(plan.tasks, kindOf, plan.frames)
    plan.hitBlends = blendsFrom(plan.hitTasks, kindOf, plan.hitFrames)
    local arms = plan.argEq
    if type(arms) == "table" then
      for i = 1, #arms do
        arms[i].blends = blendsFrom(arms[i].tasks, kindOf, arms[i].frames)
      end
    end
  end
end

local function poseWho(who)
  who = who or 0
  return (who % 2 == 1) or nil, (who >= 2) or nil
end

local function posesFrom(tasks, kindOf, ellipseFlip)
  local list = {}
  for i = 1, #(tasks or {}) do
    local t = tasks[i]
    local kind = kindOf[t.fn]
    if kind then
      local a = t.args
      local rec = { at = t.at or 0, kind = kind }
      if kind == "ellipse" then
        rec.w, rec.h = a[2] or 0, a[3] or 0
        rec.loops, rec.speed = a[4] or 1, a[5] or 0
        rec.flip = ellipseFlip[t.fn] and true or nil
        rec.target, rec.partner = poseWho(a[1])
      elseif kind == "scale" then
        rec.dx, rec.dy = a[1] or 0, a[2] or 0
        rec.duration, rec.mode = a[3] or 1, a[5] or 0
        rec.target, rec.partner = poseWho(a[4])
      elseif kind == "sway" then
        rec.axis, rec.amp = a[1] or 0, a[2] or 0
        rec.period, rec.halves = a[3] or 256, a[4] or 1
        rec.flip = true
        rec.target, rec.partner = poseWho(a[5])
      elseif kind == "lunge" then
        rec.x1, rec.arc, rec.t1 = a[2] or 0, a[3] or 0, a[4] or 1
        rec.wait, rec.x2, rec.t2 = a[5] or 0, a[6] or 0, a[7] or 1
        rec.flip = true
        rec.target, rec.partner = poseWho(a[1])
      elseif kind == "sink" then
        rec.x, rec.delay = a[2] or 0, a[3] or 0
        rec.speed, rec.duration = a[4] or 0, a[5] or 1
        rec.target, rec.partner = poseWho(a[1])
      end
      list[#list + 1] = rec
    end
  end
  if #list > 0 then return list end
  return nil
end

function Battle.classifyMotions(plans)
  local ellOk, scOk, swOk, luOk, skOk = {}, {}, {}, {}, {}
  local ellNeg = {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    if ellOk[fn] ~= false then
      ellOk[fn] = Battle.ellipseShapeOk(t) and (ellOk[fn] ~= false) or false
    end
    if scOk[fn] ~= false then
      scOk[fn] = Battle.scaleShapeOk(t) and (scOk[fn] ~= false) or false
    end
    if swOk[fn] ~= false then
      swOk[fn] = Battle.swayShapeOk(t) and (swOk[fn] ~= false) or false
    end
    if luOk[fn] ~= false then
      luOk[fn] = Battle.lungeShapeOk(t) and (luOk[fn] ~= false) or false
    end
    if skOk[fn] ~= false then
      skOk[fn] = Battle.sinkShapeOk(t) and (skOk[fn] ~= false) or false
    end
    if (t.args[2] or 0) < 0 then ellNeg[fn] = true end
  end)
  local argc = {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    local n = #t.args
    if argc[fn] == nil then argc[fn] = n
    elseif argc[fn] ~= n then
      ellOk[fn], scOk[fn], swOk[fn], luOk[fn], skOk[fn] = false, false, false, false, false
    end
  end)
  local kindOf, ellipseFlip = {}, {}
  for fn, ok in pairs(luOk) do
    if ok then kindOf[fn] = "lunge" end
  end
  for fn, ok in pairs(ellOk) do
    if ok and not kindOf[fn] then
      kindOf[fn] = "ellipse"
      if not ellNeg[fn] then ellipseFlip[fn] = true end
    end
  end
  for fn, ok in pairs(scOk) do
    if ok and not kindOf[fn] then kindOf[fn] = "scale" end
  end
  for fn, ok in pairs(swOk) do
    if ok and not kindOf[fn] then kindOf[fn] = "sway" end
  end
  for fn, ok in pairs(skOk) do
    if ok and not kindOf[fn] then kindOf[fn] = "sink" end
  end
  for _, plan in pairs(plans or {}) do
    plan.poses = posesFrom(plan.tasks, kindOf, ellipseFlip)
    plan.hitPoses = posesFrom(plan.hitTasks, kindOf, ellipseFlip)
    local arms = plan.argEq
    if type(arms) == "table" then
      for i = 1, #arms do
        arms[i].poses = posesFrom(arms[i].tasks, kindOf, ellipseFlip)
      end
    end
  end
end

function Battle.classifyShakes(plans)
  local fnOk = {}
  eachPlanTask(plans, function(t)
    local fn = t.fn
    if fnOk[fn] ~= false then
      fnOk[fn] = Battle.shakeShapeOk(t) and (fnOk[fn] ~= false) or false
    end
  end)
  for _, plan in pairs(plans or {}) do
    plan.shakes = shakesFrom(plan.tasks, fnOk)
    plan.hitShakes = shakesFrom(plan.hitTasks, fnOk)
    local arms = plan.argEq
    if type(arms) == "table" then
      for i = 1, #arms do
        arms[i].shakes = shakesFrom(arms[i].tasks, fnOk)
        arms[i].tasks = nil
      end
    end
    plan.tasks = nil
    plan.hitTasks = nil
  end
end

function Battle.particleLife(e)
  if type(e) ~= "table" then return Battle.ANIM_PARTICLE_FRAMES end
  local travel = tonumber(e.travel)
  if travel and travel > 0 then return travel end
  local held = e.held
  if type(held) == "table" and #held > 0 then
    local total = 0
    for i = 1, #held do
      total = total + (held[i][2] or 1)
    end
    if total < 1 then return Battle.ANIM_PARTICLE_FRAMES end
    if e.loops then
      if total > Battle.ANIM_PARTICLE_FRAMES then return total end
      return Battle.ANIM_PARTICLE_FRAMES
    end
    return total
  end
  return Battle.ANIM_PARTICLE_FRAMES
end

function Battle.pushSound(sounds, f, id)
  id = tonumber(id)
  if not id or id < Battle.SE_MIN or id > Battle.SE_MAX then return end
  if #sounds >= Battle.ANIM_MAX_EVENTS then return end
  sounds[#sounds + 1] = { f = f or 0, id = id }
end

-- Handwritten seChain wins; otherwise the cart's own playse list.
function Battle.mergeSeChain(hand, cart)
  if type(hand) == "table" and #hand > 0 then return hand end
  if type(cart) == "table" and #cart > 0 then return cart end
  return nil
end

function Battle.recordSoundOp(data, pc, op, frame, sounds)
  local se = GbaBin.u16(data, pc + 1)
  if op == 0x1C then
    -- loopsewithpan: se, pan, wait, times
    local wait = data:byte(pc + 5) or 0
    local times = data:byte(pc + 6) or 0
    if times < 1 then times = 1 end
    if times > Battle.SE_LOOP_MAX then times = Battle.SE_LOOP_MAX end
    for i = 0, times - 1 do
      Battle.pushSound(sounds, frame + i * wait, se)
    end
  elseif op == 0x1D then
    -- waitplaysewithpan: the wait is a task, not a delay opcode
    local wait = data:byte(pc + 5) or 0
    Battle.pushSound(sounds, frame + wait, se)
  else
    Battle.pushSound(sounds, frame, se)
  end
end

-- The template's ANIMATION: a run of {image, hold} until END/JUMP/LOOP.
function Battle.spriteAnimTimeline(data, tmpl, width, height)
  local tw = math.floor((width or 0) / 8)
  local th = math.floor((height or 0) / 8)
  local per = tw * th
  if per < 1 then return nil end
  if not GbaBin.isRomPtr(tmpl, #data) then return nil end
  local anims = GbaBin.u32(data, tmpl - GbaBin.ROM_BASE + Battle.TEMPLATE_ANIMS)
  if not GbaBin.isRomPtr(anims, #data) then return nil end
  local first = GbaBin.u32(data, anims - GbaBin.ROM_BASE)
  if not GbaBin.isRomPtr(first, #data) then return nil end
  local held, loops, total = {}, false, 0
  for i = 0, Battle.ANIMCMD_MAX - 1 do
    local o = first - GbaBin.ROM_BASE + i * 4
    if o < 0 or o + 3 >= #data then return nil end
    local word = GbaBin.u32(data, o)
    local low = word % 65536
    if low >= Battle.ANIMCMD_END then
      loops = (low ~= Battle.ANIMCMD_STOP)
      break
    end
    if low % per ~= 0 then return nil end
    local duration = math.floor(word / 65536) % 64
    if duration < 1 then duration = 1 end
    held[#held + 1] = { math.floor(low / per), duration }
    total = total + duration
  end
  if #held == 0 or total < 1 then return nil end
  return held, loops, total
end

local function readCreateSprite(data, pc, frame)
  local tmpl = GbaBin.u32(data, pc + 1)
  local battler = data:byte(pc + 6) or 0
  local argc = data:byte(pc + 7) or 0
  local args = {}
  local n = argc
  if n > 8 then n = 8 end
  for i = 0, n - 1 do
    args[i + 1] = GbaBin.s16(data, pc + 7 + i * 2)
  end
  local x, y, dx, dy
  if argc >= 1 and inOffsetRange(args[1] or 0) then x = args[1] end
  if argc >= 2 and inOffsetRange(args[2] or 0) then y = args[2] end
  if argc >= 3 and inOffsetRange(args[3] or 0) then dx = args[3] end
  if argc >= 4 and inOffsetRange(args[4] or 0) then dy = args[4] end
  local M = Battle.ANIM_MOTION
  local travel
  if argc >= 5 then
    local v = args[5] or 0
    if v >= M.MIN_FRAMES and v <= M.MAX_FRAMES then travel = v end
  end
  local callback
  if GbaBin.isRomPtr(tmpl, #data) then
    callback = GbaBin.u32(data, tmpl - GbaBin.ROM_BASE + Battle.TEMPLATE_CALLBACK)
  end
  local from, motion = Battle.animMotionOf(data, callback)
  -- No shared helper in this dump: the projectile family still passes a
  -- duration as the fifth operand (Ember 20, Water Gun 40). Sit sprites
  -- on Route 101 pass four or fewer (Tackle splat, Scratch, Growl).
  if not motion and travel and not Battle.findStartAnimLinear(data) then
    -- Ember's 6th operand is 1, not a sine amp. Leech Seed's -32 is.
    if not Battle.arcShapeOk({ args = args }) then
      motion = "linear"
      from = "attacker"
    end
  end
  if motion == "linear" and not from then from = "attacker" end
  if not from then
    from = (battler >= 0x80) and "target" or "attacker"
  end
  local fw, fh = animFrameSize(data, tmpl)
  local held, loops = Battle.spriteAnimTimeline(data, tmpl, fw, fh)
  return {
    f = frame,
    sheet = animSheetOf(data, tmpl),
    w = fw, h = fh,
    battler = battler % 0x80,
    -- bit 7 is ANIMSPRITE_IS_TARGET: Cmd_createsprite reads it for a
    -- SUBPRIORITY, not a place. `from` is who the callback sits on.
    target = battler >= 0x80 or nil,
    x = x, y = y, dx = dx, dy = dy,
    from = from, motion = motion, travel = travel,
    held = held, loops = loops or nil,
    args = args, cb = callback,
  }, pc + 7 + argc * 2
end

function Battle.walkMoveAnim(data, entry)
  local pc, frame, steps = entry, 0, 0
  local stack, events, tasks, sounds = {}, {}, {}, {}
  local extra = { fades = {} }
  while steps < Battle.ANIM_MAX_STEPS do
    steps = steps + 1
    if pc < 0 or pc + 1 > #data then return nil, "ran off the rom" end
    local op = data:byte(pc + 1)
    if Battle.ANIM_END[op] then
      return events, nil, frame, tasks, sounds, extra
    elseif op == 0x02 then                       -- createsprite
      local event, nextPc = readCreateSprite(data, pc, frame)
      if #events < Battle.ANIM_MAX_EVENTS then
        events[#events + 1] = event
      end
      pc = nextPc
    elseif op == 0x03 then                       -- createvisualtask
      local fn = GbaBin.u32(data, pc + 1)
      local argc = data:byte(pc + 7) or 0
      local args = {}
      local n = argc
      if n > 8 then n = 8 end
      for i = 0, n - 1 do
        args[i + 1] = GbaBin.s16(data, pc + 7 + i * 2)
      end
      if #tasks < Battle.ANIM_MAX_EVENTS then
        tasks[#tasks + 1] = { fn = fn, args = args, at = frame }
      end
      pc = pc + 7 + argc * 2
    elseif op == 0x1F then                       -- createsoundtask
      local argc = data:byte(pc + 6) or 0
      if argc >= 1 then
        Battle.pushSound(sounds, frame, GbaBin.u16(data, pc + 6))
      end
      pc = pc + 6 + argc * 2
    elseif Battle.SOUND_OPS[op] then
      Battle.recordSoundOp(data, pc, op, frame, sounds)
      pc = pc + (Battle.ANIM_CMD_LEN[op] or 3)
    elseif op == 0x05 then                       -- waitforvisualfinish
      local hold = frame
      for i = 1, #events do
        local die = (events[i].f or 0) + Battle.particleLife(events[i])
        if die > hold then hold = die end
      end
      for i = 1, #tasks do
        local at = tasks[i].at or 0
        if at > hold then hold = at end
      end
      frame = hold
      pc = pc + 1
    elseif op == 0x04 then                       -- delay
      frame = frame + (data:byte(pc + 2) or 0)
      pc = pc + 2
    elseif op == 0x0E then                       -- call
      local dest = GbaBin.u32(data, pc + 1)
      if not GbaBin.isRomPtr(dest, #data) then return nil, "bad call pointer" end
      if #stack >= Battle.ANIM_MAX_DEPTH then return nil, "call depth" end
      stack[#stack + 1] = pc + 5
      pc = dest - GbaBin.ROM_BASE
    elseif op == 0x0F then                       -- return
      if #stack < 1 then return nil, "return with no call" end
      pc = stack[#stack]
      stack[#stack] = nil
    elseif op == 0x13 then                       -- goto
      local dest = GbaBin.u32(data, pc + 1)
      if not GbaBin.isRomPtr(dest, #data) then return nil, "bad goto pointer" end
      pc = dest - GbaBin.ROM_BASE
    elseif op == 0x11 then                       -- choosetwoturnanim
      -- First arm is the turn the move is selected (charge / fly-up).
      -- Second arm is the hitting turn; remembered, not walked here.
      local d1 = GbaBin.u32(data, pc + 1)
      local d2 = GbaBin.u32(data, pc + 5)
      if GbaBin.isRomPtr(d2, #data) then
        extra.twoTurnHit = d2 - GbaBin.ROM_BASE
      end
      if GbaBin.isRomPtr(d1, #data) then
        pc = d1 - GbaBin.ROM_BASE
      else
        pc = pc + 9
      end
    elseif op == 0x14 then                       -- fadetobg
      extra.fades[#extra.fades + 1] = {
        at = frame,
        bg = data:byte(pc + 2) or 0,
      }
      pc = pc + 2
    elseif op == 0x15 then                       -- restorebg
      extra.fades[#extra.fades + 1] = { at = frame, bg = 0 }
      pc = pc + 1
    elseif op == 0x25 then                       -- fadetobgfromset
      extra.fades[#extra.fades + 1] = {
        at = frame,
        bg = data:byte(pc + 2) or 0,
        bgPlayer = data:byte(pc + 3) or 0,
      }
      pc = pc + 4
    elseif op == 0x21 then                       -- jumpargeq
      -- argId, s16 value, pointer. Fall through; dests are variant arms.
      local dest = GbaBin.u32(data, pc + 4)
      if GbaBin.isRomPtr(dest, #data) then
        extra.argEq = extra.argEq or {}
        if #extra.argEq < Battle.ANIM_MAX_ARGEQ then
          extra.argEq[#extra.argEq + 1] = {
            arg = data:byte(pc + 2) or 0,
            value = GbaBin.s16(data, pc + 2),
            dest = dest - GbaBin.ROM_BASE,
            at = frame,
          }
        end
      end
      pc = pc + 8
    else
      local n = Battle.ANIM_CMD_LEN[op]
      if not n then return nil, ("unknown command 0x%02X"):format(op) end
      pc = pc + n
    end
  end
  return nil, "step cap"
end

-- Returns the plans and, beside them, the set of (sheet, w, h) their events
-- draw -- which is exactly what extractAnimFrames has to render.
function Battle.parseMoveAnimPlans(data)
  Battle._linearData = nil
  Battle._linearAt = nil
  Battle._arcData = nil
  Battle._arcAt = nil
  Battle._animHelpers = nil
  local plans = {}
  local wanted = {}
  local scripts = usOff(data, "ANIM_SCRIPT_TABLE")
  for i = 0, Battle.MOVE_COUNT - 1 do
    local ptr = GbaBin.u32(data, scripts + i * 4)
    if GbaBin.isRomPtr(ptr, #data) then
      local events, err, frames, tasks, sounds, extra = Battle.walkMoveAnim(data, ptr - GbaBin.ROM_BASE)
      extra = extra or { fades = {} }
      -- A script that does not walk cleanly is reported, not guessed at: the
      -- old single-sheet reading is kept so the move still shows something.
      local sheet
      for _, e in ipairs(events or {}) do
        if e.sheet then sheet = e.sheet break end
      end
      for _, e in ipairs(events or {}) do
        if e.sheet and e.w and e.h then
          wanted[("%d|%d|%d"):format(e.sheet, e.w, e.h)] = true
        end
      end
      local plan = {
        sheet = sheet or 0,
        delay = 16,
        frames = frames or 0,
        events = events or {},
        tasks = tasks or {},
        sounds = (sounds and #sounds > 0) and sounds or nil,
        fades = (#extra.fades > 0) and extra.fades or nil,
        error = err,
      }
      if extra.twoTurnHit ~= nil then
        local he, herr, hf, ht, hs, hextra = Battle.walkMoveAnim(data, extra.twoTurnHit)
        hextra = hextra or { fades = {} }
        if not herr then
          plan.hitEvents = he or {}
          plan.hitFrames = hf or 0
          plan.hitTasks = ht or {}
          plan.hitSounds = (hs and #hs > 0) and hs or nil
          plan.hitFades = (#hextra.fades > 0) and hextra.fades or nil
          for _, e in ipairs(plan.hitEvents) do
            if e.sheet and e.w and e.h then
              wanted[("%d|%d|%d"):format(e.sheet, e.w, e.h)] = true
            end
          end
        end
      end
      if extra.argEq then
        local arms = {}
        for ai = 1, #extra.argEq do
          local rec = extra.argEq[ai]
          local ev, aerr, af, atk, as, aextra = Battle.walkMoveAnim(data, rec.dest)
          aextra = aextra or { fades = {} }
          if not aerr then
            local arm = {
              arg = rec.arg, value = rec.value, at = rec.at or 0,
              events = ev or {},
              frames = af or 0,
              tasks = atk or {},
              sounds = (as and #as > 0) and as or nil,
              fades = (#aextra.fades > 0) and aextra.fades or nil,
            }
            arms[#arms + 1] = arm
            for _, e in ipairs(arm.events) do
              if e.sheet and e.w and e.h then
                wanted[("%d|%d|%d"):format(e.sheet, e.w, e.h)] = true
              end
            end
          end
        end
        if #arms > 0 then plan.argEq = arms end
      end
      plans[i] = plan
    end
  end
  Battle.discoverAnimHelpers(data, plans)
  Battle.classifyEventMotion(data, plans)
  Battle.classifyCams(plans)
  Battle.classifyBlends(plans)
  Battle.classifyMotions(plans)
  Battle.classifyShakes(plans)
  Battle.classifySurf(data, plans)
  Battle.classifyAfterimage(data, plans)
  Battle.classifyAffine(data, plans)
  Battle.classifyMinimize(data, plans)
  return plans, wanted
end

-- gTrainerFrontPicTable @ 0x1EC53C (cinema comment / front_pic_table.inc).
-- 83 CompressedSpriteSheet entries {ptr, size, tag}, pals immediately after.
Battle.TRAINER_PIC_TABLE = 0x1EC53C
Battle.TRAINER_PAL_TABLE = 0x1EC7D4
Battle.TRAINER_PIC_COUNT = 83

function Battle.trainerPicPath(id)
  return ("assets/generated/battle/trainers/ruby_%02d.png"):format(id)
end

function Battle.renderTrainerFront(data, picOff, palOff, sizeHint)
  local raw, err = GbaLz77.decompress(data, picOff)
  if not raw or #raw < 32 then return nil, err or "trainer gfx lz77 failed" end
  local palBytes = GbaLz77.decompress(data, palOff)
  if not palBytes or #palBytes < Battle.PAL_BYTES then
    return nil, "trainer pal lz77 failed"
  end
  local pal = {}
  for c = 0, 15 do
    local r, g, b = bgr555(GbaBin.u16(palBytes, c * 2))
    pal[c] = { r, g, b }
  end
  local tiles = math.floor(#raw / Battle.TILE_BYTES)
  if tiles < 1 then return nil, "empty trainer gfx" end
  local cols = 8
  local rows = math.max(1, math.floor((tiles + cols - 1) / cols))
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for t = 0, tiles - 1 do
    blitTile(image, (t % cols) * 8, math.floor(t / cols) * 8,
      raw:sub(t * Battle.TILE_BYTES + 1, (t + 1) * Battle.TILE_BYTES), pal)
  end
  return image
end

function Battle.extractTrainerFronts(data)
  if type(data) ~= "string" then return {} end
  local picTable = usOff(data, "TRAINER_PIC_TABLE")
  local palTable = usOff(data, "TRAINER_PAL_TABLE")
  local _, firstGfx = romPtr(data, picTable)
  if not firstGfx or GbaBin.u8(data, firstGfx) ~= 0x10 then
    return {}
  end
  local out = {}
  for i = 0, Battle.TRAINER_PIC_COUNT - 1 do
    local _, gfxOff = romPtr(data, picTable + i * 8)
    local _, palOff = romPtr(data, palTable + i * 8)
    if gfxOff and palOff then
      local img = Battle.renderTrainerFront(data, gfxOff, palOff)
      if img then
        local path = Battle.trainerPicPath(i)
        ImageWriter.save(img, path)
        out[i] = path
        if i == 0 then
          ImageWriter.save(img, "assets/generated/trainer_card/ruby_brendan.png")
        elseif i == 1 then
          ImageWriter.save(img, "assets/generated/trainer_card/ruby_may.png")
        end
      end
    end
  end
  return out
end

-- Trainer card chrome lives in graphics.c as uncompressed 4bpp + 48-color
-- star pals + 32x20 tilemaps. 0-star pal signature (first 8 GBA colors)
-- is unique in US Ruby.
Battle.CARD_GFX_BYTES = 0x1400
Battle.CARD_PAL_BYTES = 0x60
Battle.CARD_MAP_BYTES = 0x500
-- pokeruby.sym file offsets (addr - 0x08000000). Same on 1.0 / 1.1 / 1.2.
Battle.CARD_GFX = 0xE8B4E0
Battle.CARD_PAL0 = 0xE8C8E0
Battle.CARD_FRONT_MAP = 0xE8CAC0
Battle.CARD_BACK_MAP = 0xE8CFC0
Battle.CARD_BADGE_GFX = 0x3B5AB8
Battle.CARD_BADGE_PAL = 0x3B5F2C
Battle.CARD_STAR_SIG = {
  0x3991, 0x7FFF, 0x6FD3, 0x5294, 0x3DEF, 0x3D0C, 0x20E5, 0x4547,
}

local function palNeedle(sig)
  local parts = {}
  for i = 1, #sig do
    local c = sig[i]
    parts[#parts + 1] = string.char(c % 256, math.floor(c / 256) % 256)
  end
  return table.concat(parts)
end

local function findTrainerCardPal0(data)
  if type(data) ~= "string" then return nil end
  if #data > Battle.CARD_PAL0 + 16 then
    if GbaBin.u16(data, Battle.CARD_PAL0 + 2) == 0x7FFF then
      return Battle.CARD_PAL0
    end
  end
  local at = data:find(palNeedle(Battle.CARD_STAR_SIG), 1, true)
  if at then return at - 1 end
  return nil
end

function Battle.extractTrainerCard(data)
  if type(data) ~= "string" then return nil end
  local pal0 = findTrainerCardPal0(data)
  local gfxOff = Battle.CARD_GFX
  local frontOff = Battle.CARD_FRONT_MAP
  local backOff = Battle.CARD_BACK_MAP
  if pal0 and pal0 ~= Battle.CARD_PAL0 then
    gfxOff = pal0 - Battle.CARD_GFX_BYTES
    frontOff = pal0 + 5 * Battle.CARD_PAL_BYTES
    backOff = frontOff + Battle.CARD_MAP_BYTES
  elseif pal0 then
    gfxOff = Battle.CARD_GFX
  else
    pal0 = Battle.CARD_PAL0
  end
  if gfxOff < 0 or pal0 + 16 > #data then return nil end
  local tiles = data:sub(gfxOff + 1, gfxOff + Battle.CARD_GFX_BYTES)
  if #tiles ~= Battle.CARD_GFX_BYTES then return nil end
  local frontMap = data:sub(frontOff + 1, frontOff + Battle.CARD_MAP_BYTES)
  local backMap = data:sub(backOff + 1, backOff + Battle.CARD_MAP_BYTES)
  if #frontMap ~= Battle.CARD_MAP_BYTES then return nil end

  local function palBank(star, bank)
    local base = pal0 + star * Battle.CARD_PAL_BYTES + bank * 32
    local pal = {}
    for c = 0, 15 do
      local r, g, b = bgr555(GbaBin.u16(data, base + c * 2))
      pal[c] = { r, g, b }
    end
    return pal
  end

  local function paint(map, star)
    local pals = {}
    for bank = 0, 2 do pals[bank] = palBank(star, bank) end
    local image = ImageWriter.blank(240, 160, 0, 0, 0, 1)
    local tilesN = math.floor(#tiles / Battle.TILE_BYTES)
    for row = 0, 19 do
      for col = 0, 31 do
        local entry = GbaBin.u16(map, (row * 32 + col) * 2)
        local id = entry % 1024
        if id < tilesN then
          local palN = math.floor(entry / 4096) % 16
          local hflip = math.floor(entry / 1024) % 2 == 1
          local vflip = math.floor(entry / 2048) % 2 == 1
          local pal = pals[palN] or pals[0]
          local raw = tiles:sub(id * Battle.TILE_BYTES + 1,
            (id + 1) * Battle.TILE_BYTES)
          if raw and #raw >= Battle.TILE_BYTES then
            for ty = 0, 7 do
              for tx = 0, 7 do
                local sx = hflip and (7 - tx) or tx
                local sy = vflip and (7 - ty) or ty
                local byte = raw:byte(sy * 4 + math.floor(sx / 2) + 1) or 0
                local ci = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
                local rgb = pal[ci] or { 0, 0, 0 }
                local x, y = col * 8 + tx, row * 8 + ty
                if x < 240 and y < 160 then
                  image:setPixel(x, y, rgb[1], rgb[2], rgb[3], 1)
                end
              end
            end
          end
        end
      end
    end
    return image
  end

  local out = {}
  for star = 0, 4 do
    local img = paint(frontMap, star)
    if img then
      local path = ("assets/generated/trainer_card/ruby_front_%d.png"):format(star)
      ImageWriter.save(img, path)
      out["front" .. star] = path
    end
  end
  if #backMap == Battle.CARD_MAP_BYTES then
    for star = 0, 4 do
      local back = paint(backMap, star)
      if back then
        local path = ("assets/generated/trainer_card/ruby_back_%d.png"):format(star)
        ImageWriter.save(back, path)
        out["back" .. star] = path
        if star == 0 then
          ImageWriter.save(back, "assets/generated/trainer_card/ruby_back.png")
          out.back = "assets/generated/trainer_card/ruby_back.png"
        end
      end
    end
  end
  local badgeGfxOff = usOff(data, "CARD_BADGE_GFX")
  local badgePalOff = usOff(data, "CARD_BADGE_PAL")
  local badgeGfx = data:sub(badgeGfxOff + 1, badgeGfxOff + 0x400)
  if #badgeGfx == 0x400 then
    local pal = {}
    for c = 0, 15 do
      pal[c] = { bgr555(GbaBin.u16(data, badgePalOff + c * 2)) }
    end
    local badges = ImageWriter.blank(128, 16, 0, 0, 0, 0)
    for t = 0, 31 do
      blitTile(badges, (t % 16) * 8, math.floor(t / 16) * 8,
        badgeGfx:sub(t * 32 + 1, (t + 1) * 32), pal)
    end
    ImageWriter.save(badges, "assets/generated/trainer_card/ruby_badges.png")
    out.badges = "assets/generated/trainer_card/ruby_badges.png"
  end
  if not out.front0 then return nil end
  return out
end

local function palBytes(data, off)
  if type(data) ~= "string" or not off or off < 0 or off >= #data then
    return nil
  end
  if GbaBin.u8(data, off) == 0x10 then
    local raw = GbaLz77.decompress(data, off)
    if raw and #raw >= 32 then return raw end
  end
  return data:sub(off + 1, math.min(#data, off + 96))
end

local function pal16(bytes, bank)
  bank = bank or 0
  local pal = {}
  for c = 0, 15 do
    pal[c] = { bgr555(GbaBin.u16(bytes, bank * 32 + c * 2)) }
  end
  return pal
end

function Battle.renderLzTiles(data, gfxOff, palOff, cols)
  local raw = GbaLz77.decompress(data, gfxOff)
  if not raw or #raw < Battle.TILE_BYTES then
    raw = data:sub(gfxOff + 1, gfxOff + 0x3000)
    if not raw or #raw < Battle.TILE_BYTES then return nil end
  end
  local pb = palBytes(data, palOff)
  if not pb then return nil end
  local pal = pal16(pb, 0)
  local tiles = math.floor(#raw / Battle.TILE_BYTES)
  cols = cols or 16
  local rows = math.max(1, math.floor((tiles + cols - 1) / cols))
  local image = ImageWriter.blank(cols * 8, rows * 8, 0, 0, 0, 0)
  for t = 0, tiles - 1 do
    blitTile(image, (t % cols) * 8, math.floor(t / cols) * 8,
      raw:sub(t * Battle.TILE_BYTES + 1, (t + 1) * Battle.TILE_BYTES), pal)
  end
  return image
end

-- pokeruby.sym US Ruby (file offset = addr - 0x08000000)
Battle.PKNAV_MENU_GFX = 0xE88358
Battle.PKNAV_OPTIONS_GFX = 0xE884CC
Battle.PKNAV_PAL1 = 0xE88A28
Battle.PKNAV_PAL2 = 0xE88A48
Battle.PKNAV_HEADER_GFX = 0xE88A88
Battle.PKNAV_MAP_PAL = 0xE89628
Battle.PKNAV_OUTLINE_PAL = 0x3E05D4
Battle.PKNAV_OUTLINE_GFX = 0x3E05F4
Battle.PKNAV_OUTLINE_MAP = 0x3E0804

Battle.BAG_MALE_GFX = 0xE75024
Battle.BAG_FEMALE_GFX = 0xE75BA0
Battle.BAG_SPRITE_PAL = 0xE76700
Battle.BAG_SCREEN_GFX = 0xE76728
Battle.BAG_SCREEN_MALE_PAL = 0xE76F94
Battle.BAG_SCREEN_FEMALE_PAL = 0xE76FCC
Battle.BAG_SCREEN_MAP = 0xE77004
-- item_menu.c sub_80A39B8: sub_809D104(dest, 4, 10, gBagScreenLabels_Tilemap,
-- 0, pocket * 2, 8, 2) -- an 8x2 tile block per pocket, blitted to tile
-- (4, 10), i.e. pixels (32, 80). The pocket name is cart art, not text.
Battle.BAG_SCREEN_LABELS = 0xE96EC8
Battle.BAG_LABEL_COLS = 8
Battle.BAG_LABEL_ROWS = 2
Battle.BAG_LABEL_POCKETS = 6
-- item_menu.c DrawPocketIndicatorDots: tileMapBuffer[0x125 + i] is 0x107D
-- for the selected pocket and 0x107C otherwise -- tiles 0x7C/0x7D on
-- palette bank 1, at tilemap index 0x125 = row 9, col 5.
Battle.BAG_DOT_TILE_OFF = 0x7C
Battle.BAG_DOT_TILE_ON = 0x7D
Battle.BAG_DOT_PAL = 1

local function paintLzMap(data, gfxOff, palOff, mapOff, mapBytes)
  local raw = GbaLz77.decompress(data, gfxOff)
  if not raw or #raw < Battle.TILE_BYTES then
    raw = data:sub(gfxOff + 1, gfxOff + 0x4000)
  end
  if not raw or #raw < Battle.TILE_BYTES then return nil end
  local map = GbaLz77.decompress(data, mapOff)
  if not map or #map < 2 then
    map = data:sub(mapOff + 1, mapOff + mapBytes)
  end
  if not map or #map < 2 then return nil end
  local pb = palBytes(data, palOff)
  if not pb then return nil end
  local pals = { [0] = pal16(pb, 0), [1] = pal16(pb, 1), [2] = pal16(pb, 2) }
  local tilesN = math.floor(#raw / Battle.TILE_BYTES)
  local image = ImageWriter.blank(240, 160, 0, 0, 0, 1)
  local entries = math.floor(#map / 2)
  for i = 0, entries - 1 do
    local col = i % 32
    local row = math.floor(i / 32)
    if row > 19 then break end
    local entry = GbaBin.u16(map, i * 2)
    local id = entry % 1024
    if id < tilesN then
      local palN = math.floor(entry / 4096) % 16
      local pal = pals[palN] or pals[0]
      -- bits 10 and 11 are hflip/vflip. Ignoring them mirrored the bag's
      -- panel border: its left edge came out yellow-then-dark instead of
      -- dark-then-yellow, and the corner tile was unreadable.
      blitTile(image, col * 8, row * 8,
        raw:sub(id * Battle.TILE_BYTES + 1, (id + 1) * Battle.TILE_BYTES), pal,
        math.floor(entry / 0x400) % 2 == 1,
        math.floor(entry / 0x800) % 2 == 1)
    end
  end
  return image
end

function Battle.extractPokenav(data)
  if type(data) ~= "string" then return nil end
  local pal1 = usOff(data, "PKNAV_PAL1")
  local menuGfx = usOff(data, "PKNAV_MENU_GFX")
  local optsGfx = usOff(data, "PKNAV_OPTIONS_GFX")
  local headerGfx = usOff(data, "PKNAV_HEADER_GFX")
  local mapPal = usOff(data, "PKNAV_MAP_PAL")
  local outlinePal = usOff(data, "PKNAV_OUTLINE_PAL")
  local outlineGfx = usOff(data, "PKNAV_OUTLINE_GFX")
  local outlineMap = usOff(data, "PKNAV_OUTLINE_MAP")
  if #data < pal1 + 32 then return nil end
  local out = {}
  local menu = Battle.renderLzTiles(data, menuGfx, pal1, 8)
  if menu then
    ImageWriter.save(menu, "assets/generated/pokenav/menu.png")
    out.menu = "assets/generated/pokenav/menu.png"
  end
  -- Option buttons are 32x16 sprites packed in the LZ sheet.
  local opts = Battle.renderLzTiles(data, optsGfx, pal1, 4)
  if opts then
    ImageWriter.save(opts, "assets/generated/pokenav/options.png")
    out.options = "assets/generated/pokenav/options.png"
  end
  local header = Battle.renderLzTiles(data, headerGfx, mapPal, 16)
  if header then
    ImageWriter.save(header, "assets/generated/pokenav/header.png")
    out.header = "assets/generated/pokenav/header.png"
  end
  local outline = paintLzMap(data, outlineGfx, outlinePal, outlineMap, 0x168)
  if outline then
    ImageWriter.save(outline, "assets/generated/pokenav/outline.png")
    out.outline = "assets/generated/pokenav/outline.png"
  end
  if not (out.menu or out.options or out.outline) then return nil end
  return out
end

-- The six pocket labels as one 64x96 strip, pocket p at y = p * 16, so the
-- bag screen can blit whichever one it is showing.
function Battle.renderBagLabels(data)
  local gfx = usOff(data, "BAG_SCREEN_GFX")
  local pal = usOff(data, "BAG_SCREEN_MALE_PAL")
  local mapOff = usOff(data, "BAG_SCREEN_LABELS")
  local raw = GbaLz77.decompress(data, gfx)
  if not raw or #raw < Battle.TILE_BYTES then return nil end
  local pb = palBytes(data, pal)
  if not pb then return nil end
  local pals = { [0] = pal16(pb, 0), [1] = pal16(pb, 1), [2] = pal16(pb, 2) }
  local cols, rows = Battle.BAG_LABEL_COLS, Battle.BAG_LABEL_ROWS
  local pockets = Battle.BAG_LABEL_POCKETS
  local map = data:sub(mapOff + 1, mapOff + 2048)
  if #map < 2048 then return nil end
  local tilesN = math.floor(#raw / Battle.TILE_BYTES)
  local image = ImageWriter.blank(cols * 8, pockets * rows * 8, 0, 0, 0, 0)
  for p = 0, pockets - 1 do
    for r = 0, rows - 1 do
      for c = 0, cols - 1 do
        local i = (p * rows + r) * 32 + c
        local entry = GbaBin.u16(map, i * 2)
        local id = entry % 1024
        if id < tilesN then
          local pal = pals[math.floor(entry / 4096) % 16] or pals[0]
          blitTile(image, c * 8, (p * rows + r) * 8,
            raw:sub(id * Battle.TILE_BYTES + 1, (id + 1) * Battle.TILE_BYTES), pal)
        end
      end
    end
  end
  return image
end

-- The two pocket dots side by side: unselected at x 0, selected at x 8.
function Battle.renderBagDots(data)
  local gfx = usOff(data, "BAG_SCREEN_GFX")
  local palOff = usOff(data, "BAG_SCREEN_MALE_PAL")
  local raw = GbaLz77.decompress(data, gfx)
  if not raw or #raw < Battle.TILE_BYTES then return nil end
  local pb = palBytes(data, palOff)
  if not pb then return nil end
  local pal = pal16(pb, Battle.BAG_DOT_PAL)
  local image = ImageWriter.blank(16, 8, 0, 0, 0, 0)
  local ids = { Battle.BAG_DOT_TILE_OFF, Battle.BAG_DOT_TILE_ON }
  for i, id in ipairs(ids) do
    local at = id * Battle.TILE_BYTES
    if at + Battle.TILE_BYTES > #raw then return nil end
    blitTile(image, (i - 1) * 8, 0,
      raw:sub(at + 1, at + Battle.TILE_BYTES), pal)
  end
  return image
end

function Battle.extractBag(data)
  if type(data) ~= "string" then return nil end
  local spritePal = usOff(data, "BAG_SPRITE_PAL")
  if #data < spritePal + 32 then return nil end
  local out = {}
  -- 64x64 object, 6 pocket frames stacked (tile 0,64,128,...).
  local male = Battle.renderLzTiles(data, usOff(data, "BAG_MALE_GFX"), spritePal, 8)
  if male then
    ImageWriter.save(male, "assets/generated/bag/bag_male.png")
    out.male = "assets/generated/bag/bag_male.png"
  end
  local female = Battle.renderLzTiles(data, usOff(data, "BAG_FEMALE_GFX"), spritePal, 8)
  if female then
    ImageWriter.save(female, "assets/generated/bag/bag_female.png")
    out.female = "assets/generated/bag/bag_female.png"
  elseif male then
    ImageWriter.save(male, "assets/generated/bag/bag_female.png")
    out.female = out.male
  end
  local screen = paintLzMap(data, usOff(data, "BAG_SCREEN_GFX"), usOff(data, "BAG_SCREEN_MALE_PAL"),
    usOff(data, "BAG_SCREEN_MAP"), 0x800)
  if screen then
    ImageWriter.save(screen, "assets/generated/bag/bag_screen.png")
    out.screen = "assets/generated/bag/bag_screen.png"
  end
  local dots = Battle.renderBagDots(data)
  if dots then
    ImageWriter.save(dots, "assets/generated/bag/bag_dots.png")
    out.dots = "assets/generated/bag/bag_dots.png"
  end
  local labels = Battle.renderBagLabels(data)
  if labels then
    ImageWriter.save(labels, "assets/generated/bag/bag_labels.png")
    out.labels = "assets/generated/bag/bag_labels.png"
  end
  if not out.male then return nil end
  return out
end

return Battle
