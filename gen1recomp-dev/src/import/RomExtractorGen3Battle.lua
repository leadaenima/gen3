-- Ruby battle tables: gBaseStats, gWildMonHeaders, LZ77 pics,
-- gBattleMoves, type chart, level-up learnsets.
-- Nintendo assets stay out of git -- extract at import time.
local GbaBin = require("src.import.GbaBin")
local GbaLz77 = require("src.import.GbaLz77")
local GbaText = require("src.import.GbaText")
local ImageWriter = require("src.import.ImageWriter")

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
}

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
  if Battle.parseOneStats(data, RUBY_US.baseStats + Battle.BASE_STATS_SIZE)
      and GbaBin.u8(data, RUBY_US.baseStats + Battle.BASE_STATS_SIZE) == 45 then
    return RUBY_US.baseStats
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
  if looksLikeWildTable(data, RUBY_US.wildHeaders) then
    return RUBY_US.wildHeaders
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
  local front, back, pal = RUBY_US.frontPics, RUBY_US.backPics, RUBY_US.palettes
  if picEntryOk(data, front + 8) and picEntryOk(data, back + 8) then
    local fp = GbaBin.u32(data, front + 8)
    local bp = GbaBin.u32(data, back + 8)
    if fp ~= bp then
      return front, back, pal
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
  local front, back = RUBY_US.frontCoords, RUBY_US.backCoords
  if GbaBin.u8(data, front) == 136 and GbaBin.u8(data, front + 4) == 69
      and GbaBin.u8(data, back) == 136 then
    return front, back
  end
  return nil
end

local function bgr555(c)
  local r = (c % 32) * 8
  local g = (math.floor(c / 32) % 32) * 8
  local b = (math.floor(c / 1024) % 32) * 8
  return r / 255, g / 255, b / 255
end

local function blitTile(image, x, y, raw, palette)
  if not raw or #raw < Battle.TILE_BYTES then return end
  for ty = 0, 7 do
    for tx = 0, 7 do
      local byte = raw:byte(ty * 4 + math.floor(tx / 2) + 1)
      local ci = (tx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      if ci ~= 0 then
        local col = palette[ci] or { 1, 0, 1 }
        image:setPixel(x + tx, y + ty, col[1], col[2], col[3], 1)
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
  if GbaBin.u8(data, tiles) ~= 0x10 then return nil end
  if GbaBin.u8(data, map) ~= 0x10 then return nil end
  if GbaBin.u8(data, pal) ~= 0x10 then return nil end
  return tiles, map, pal
end

-- pokeruby sBattleEnvironmentTable: 10 rows of 5 pointers. PLAIN reuses
-- BUILDING tiles/map with a different palette.
function Battle.findEnvironmentTable(data)
  if type(data) ~= "string" then return nil end
  local span = Battle.ENV_COUNT * 20
  local last = #data - span
  for off = 0, last, 4 do
    local t8 = GbaBin.u32(data, off + 8 * 20)
    local t9 = GbaBin.u32(data, off + 9 * 20)
    if t8 == t9 and GbaBin.isRomPtr(t8, #data) then
      local p8 = GbaBin.u32(data, off + 8 * 20 + 16)
      local p9 = GbaBin.u32(data, off + 9 * 20 + 16)
      if p8 ~= p9 and envRowPtrs(data, off + 8 * 20)
          and envRowPtrs(data, off + 9 * 20)
          and envRowPtrs(data, off) then
        local ok = true
        for i = 1, 7 do
          if not envRowPtrs(data, off + i * 20) then
            ok = false
            break
          end
        end
        if ok then return off end
      end
    end
  end
  return nil
end

function Battle.renderBattleBg(data, tilesOff, mapOff, palOff)
  local tiles = GbaLz77.decompress(data, tilesOff)
  local map = GbaLz77.decompress(data, mapOff)
  local palBytes = GbaLz77.decompress(data, palOff)
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
        local bank = math.floor(entry / 4096) % 16
        if bank >= 1 then bank = bank - 1 end
        local pal = pals[bank] or pals[0]
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
  if not tableOff then return bgs end
  for env = 0, Battle.ENV_COUNT - 1 do
    local tilesOff, mapOff, palOff = envRowPtrs(data, tableOff + env * 20)
    if tilesOff and mapOff and palOff then
      local image = Battle.renderBattleBg(data, tilesOff, mapOff, palOff)
      if image then
        local path = Battle.bgPath(env)
        ImageWriter.save(image, path)
        bgs[env] = path
      end
    end
  end
  return bgs
end

function Battle.collectSpecies(encounters, evolutions, trainers)
  local used = {
    [Battle.STARTER_SPECIES] = true,
    [277] = true,
    [281] = true, -- Combusken
    [283] = true,
    [286] = true, -- Poochyena (Birch chase; not national dex 261)
    [291] = true, -- Silcoon
    [292] = true, -- Cascoon
    [293] = true, -- Beautifly
    [294] = true, -- Dustox
    [350] = true, -- Azurill (Birch speech)
    [405] = true, -- Groudon (title / intro)
  }
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
    for i = 1, #extra do
      local list = evolutions[extra[i]]
      if type(list) == "table" then
        for e = 1, #list do
          local t = list[e] and list[e].target
          if type(t) == "number" and t > 0 then used[t] = true end
        end
      end
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
  local names, moves = RUBY_US.moveNames, RUBY_US.moveData
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
  local off = RUBY_US.typeChart
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
  local off = RUBY_US.learnsets
  local _, torchic = romPtr(data, off + Battle.STARTER_SPECIES * 4)
  if torchic then
    local first = Battle.parseLearnset(data, torchic)[1]
    if first and first.move == 10 then return off end
  end
  return nil
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
  if Battle.looksLikeTmhmLearnsets(data, RUBY_US.tmhmLearnsets) then
    return RUBY_US.tmhmLearnsets
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
  local off = RUBY_US.evolutions
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

function Battle.readTrainerIdFromScript(data, scriptOff)
  if type(data) ~= "string" or type(scriptOff) ~= "number" then return nil end
  for i = 0, 63 do
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
  local name = GbaText.decodeName(data:sub(
    offset + 5, offset + 4 + Battle.TRAINER_NAME_LENGTH))
  local doubleBattle = GbaBin.u32(data, offset + 24) ~= 0
  local items = {}
  for i = 0, 3 do
    local id = GbaBin.u16(data, offset + 16 + i * 2)
    if id ~= 0 then items[#items + 1] = id end
  end
  local partySize = GbaBin.u8(data, offset + 32)
  local _, partyOff = romPtr(data, offset + 36)
  local party = {}
  if partyOff and partySize > 0 then
    party = Battle.parseTrainerParty(data, partyOff, partySize, flags)
  end
  return {
    flags = flags,
    class = class,
    className = (classNames and classNames[class]) or "TRAINER",
    name = name ~= "" and name or "TRAINER",
    doubleBattle = doubleBattle,
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
  if looksLikeTrainerTable(data, RUBY_US.trainers) then
    return RUBY_US.trainers, RUBY_US.trainerClasses
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
  return {
    name = name,
    itemId = GbaBin.u16(data, offset + 14),
    price = GbaBin.u16(data, offset + 16),
    holdEffect = GbaBin.u8(data, offset + 18),
    holdEffectParam = GbaBin.u8(data, offset + 19),
    pocket = GbaBin.u8(data, offset + 26),
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
  if looksLikeItemTable(data, RUBY_US.items) then
    return RUBY_US.items
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

return Battle
