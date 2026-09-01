-- pokeruby sRegionMapLayout (28x15) + gRegionMapEntries names.
-- MAPSEC ids are json order; MAPSEC_NONE follows DYNAMIC.
local M = {}
M.WIDTH = 28
M.HEIGHT = 15
M.CURSOR_X_MIN = 1
M.CURSOR_Y_MIN = 2
M.MAPSEC_NONE = 88
M.MAPSEC_LITTLEROOT = 0
M.MAPSEC_EVER_GRANDE = 15
M.MAPSEC_ROUTE_104 = 19
M.MAPSEC_BATTLE_TOWER = 58
M.MAPSEC_SOUTHERN_ISLAND = 73
M.MAPSEC_MT_CHIMNEY = 56
-- CalcZoomScrollParams pivot (0x38, 0x48). Affine PA 256 = 1×, 128 = 2×.
M.ZOOM_CX = 0x38
M.ZOOM_CY = 0x48
M.ZOOM_PA_OUT = 256
M.ZOOM_PA_IN = 128
M.ZOOM_FRAMES = 16
M.SCROLL_X_MIN = -44
M.SCROLL_X_MAX = 172
M.SCROLL_Y_MIN = -52
M.SCROLL_Y_MAX = 60
-- sub_80FB758
M.KIND_NONE = 0
M.KIND_LANDMARK = 1
M.KIND_FLY = 2
M.KIND_TOWN = 3
M.KIND_SPECIAL = 4
M.FLAG_ALWAYS = 0xFFFF
M.FLAG_LANDMARK_FLOWER_SHOP = 0x83C
M.FLAG_LANDMARK_MR_BRINEY_HOUSE = 0x83D
M.FLAG_LANDMARK_ABANDONED_SHIP = 0x83E
M.FLAG_LANDMARK_SEASHORE_HOUSE = 0x83F
M.FLAG_LANDMARK_NEW_MAUVILLE = 0x840
M.FLAG_LANDMARK_OLD_LADY_REST_SHOP = 0x841
M.FLAG_LANDMARK_TRICK_HOUSE = 0x842
M.FLAG_LANDMARK_WINSTRATE_FAMILY = 0x843
M.FLAG_LANDMARK_GLASS_WORKSHOP = 0x844
M.FLAG_LANDMARK_LANETTES_HOUSE = 0x845
M.FLAG_LANDMARK_POKEMON_DAYCARE = 0x846
M.FLAG_LANDMARK_SEAFLOOR_CAVERN = 0x847
M.FLAG_LANDMARK_BATTLE_TOWER = 0x848
M.FLAG_LANDMARK_SOUTHERN_ISLAND = 0x849
M.FLAG_LANDMARK_FIERY_PATH = 0x84A
M.FLAG_LANDMARK_ISLAND_CAVE = 0x855
M.FLAG_LANDMARK_DESERT_RUINS = 0x856
M.FLAG_LANDMARK_FOSSIL_MANIACS_HOUSE = 0x857
M.FLAG_LANDMARK_SCORCHED_SLAB = 0x858
M.FLAG_LANDMARK_ANCIENT_TOMB = 0x859
M.FLAG_LANDMARK_TUNNELERS_REST_HOUSE = 0x85A
M.FLAG_LANDMARK_HUNTERS_HOUSE = 0x85B
M.FLAG_LANDMARK_SEALED_CHAMBER = 0x85C
M.FLAG_LANDMARK_SKY_PILLAR = 0x85E
M.FLAG_LANDMARK_BERRY_MASTERS_HOUSE = 0x863
-- gRegionMapEntries width/height for MAPSEC 0-15 (fly-icon OAM shape).
M.ENTRY_W = string.char(1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 2, 2, 1, 1)
M.ENTRY_H = string.char(1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 2)
M.NAMES = {
  'LITTLEROOT TOWN',
  'OLDALE TOWN',
  'DEWFORD TOWN',
  'LAVARIDGE TOWN',
  'FALLARBOR TOWN',
  'VERDANTURF TOWN',
  'PACIFIDLOG TOWN',
  'PETALBURG CITY',
  'SLATEPORT CITY',
  'MAUVILLE CITY',
  'RUSTBORO CITY',
  'FORTREE CITY',
  'LILYCOVE CITY',
  'MOSSDEEP CITY',
  'SOOTOPOLIS CITY',
  'EVER GRANDE CITY',
  'ROUTE 101',
  'ROUTE 102',
  'ROUTE 103',
  'ROUTE 104',
  'ROUTE 105',
  'ROUTE 106',
  'ROUTE 107',
  'ROUTE 108',
  'ROUTE 109',
  'ROUTE 110',
  'ROUTE 111',
  'ROUTE 112',
  'ROUTE 113',
  'ROUTE 114',
  'ROUTE 115',
  'ROUTE 116',
  'ROUTE 117',
  'ROUTE 118',
  'ROUTE 119',
  'ROUTE 120',
  'ROUTE 121',
  'ROUTE 122',
  'ROUTE 123',
  'ROUTE 124',
  'ROUTE 125',
  'ROUTE 126',
  'ROUTE 127',
  'ROUTE 128',
  'ROUTE 129',
  'ROUTE 130',
  'ROUTE 131',
  'ROUTE 132',
  'ROUTE 133',
  'ROUTE 134',
  'UNDERWATER',
  'UNDERWATER',
  'UNDERWATER',
  'UNDERWATER',
  'UNDERWATER',
  'GRANITE CAVE',
  'MT. CHIMNEY',
  'SAFARI ZONE',
  'BATTLE TOWER',
  'PETALBURG WOODS',
  'RUSTURF TUNNEL',
  'ABANDONED SHIP',
  'NEW MAUVILLE',
  'METEOR FALLS',
  'METEOR FALLS',
  'MT. PYRE',
  'MAGMA HIDEOUT',
  'SHOAL CAVE',
  'SEAFLOOR CAVERN',
  'UNDERWATER',
  'VICTORY ROAD',
  'MIRAGE ISLAND',
  'CAVE OF ORIGIN',
  'SOUTHERN ISLAND',
  'FIERY PATH',
  'FIERY PATH',
  'JAGGED PASS',
  'JAGGED PASS',
  'SEALED CHAMBER',
  'UNDERWATER',
  'SCORCHED SLAB',
  'ISLAND CAVE',
  'DESERT RUINS',
  'ANCIENT TOMB',
  'INSIDE OF TRUCK',
  'SKY PILLAR',
  'SECRET BASE',
  '',
}
M.LAYOUT = table.concat({
    string.char(88, 29, 29, 4, 28, 28, 28, 28, 26, 88, 88, 34, 11, 35, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 29, 88, 88),
    string.char(88, 88, 56, 56, 26, 88, 88, 34, 88, 35, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 30, 29, 88, 88, 88, 88, 56, 56),
    string.char(26, 88, 88, 34, 88, 35, 88, 88, 57, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 30, 88, 88, 88, 88, 3, 27, 27, 26, 88, 88, 34),
    string.char(88, 35, 36, 36, 36, 36, 12, 12, 39, 39, 39, 39, 40, 40, 88, 88, 30, 88, 88, 88, 88, 88, 88, 88, 26, 88, 88, 34, 88, 88, 88, 88),
    string.char(37, 88, 88, 88, 39, 39, 39, 39, 40, 40, 88, 88, 10, 31, 31, 31, 31, 88, 88, 88, 26, 88, 88, 34, 88, 88, 88, 88, 37, 88, 88, 88),
    string.char(39, 39, 39, 39, 13, 13, 88, 88, 10, 88, 88, 88, 5, 32, 32, 32, 9, 9, 33, 33, 38, 38, 38, 38, 38, 88, 88, 88, 41, 41, 41, 42),
    string.char(42, 42, 88, 88, 19, 88, 88, 88, 88, 88, 88, 88, 25, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 41, 14, 41, 42, 42, 42, 88, 88),
    string.char(19, 88, 88, 88, 18, 18, 18, 18, 25, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 41, 41, 41, 42, 42, 42, 88, 15, 19, 7, 17, 17),
    string.char(1, 88, 88, 88, 25, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 43, 43, 43, 43, 15, 20, 88, 88, 88, 16, 88, 88, 88),
    string.char(8, 49, 49, 49, 48, 48, 48, 47, 47, 6, 46, 46, 46, 45, 45, 45, 44, 44, 88, 88, 20, 88, 88, 88, 0, 88, 88, 88, 8, 88, 88, 88),
    string.char(88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 20, 88, 88, 88, 88, 88, 88, 88, 24, 88, 88, 88, 88, 88, 88, 88),
    string.char(88, 88, 88, 88, 88, 88, 58, 88, 88, 88, 88, 88, 21, 21, 21, 88, 88, 88, 88, 88, 24, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88),
    string.char(88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 2, 22, 22, 22, 23, 23, 24, 88, 88, 88, 73, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88, 88),
    string.char(88, 88, 88, 88)
})
M.ENTRY_X = table.concat({
    string.char(4, 4, 2, 5, 3, 4, 17, 1, 8, 8, 0, 12, 18, 24, 21, 27, 4, 2, 4, 0, 0, 0, 3, 6, 8, 8, 8, 6, 4, 1, 0, 1),
    string.char(5, 10, 11, 13, 14, 16, 12, 20, 24, 20, 23, 23, 24, 21, 18, 15, 12, 9, 20, 20, 23, 23, 21, 1, 6, 16, 22, 0, 2, 6, 8, 0),
    string.char(1, 16, 19, 24, 24, 24, 27, 17, 21, 12, 6, 7, 6, 7, 11, 11, 13, 0, 8, 13, 0, 19, 0, 0)
})
M.ENTRY_Y = table.concat({
    string.char(11, 9, 14, 3, 0, 6, 10, 9, 10, 6, 5, 0, 3, 5, 7, 8, 10, 9, 8, 7, 10, 13, 14, 14, 12, 7, 0, 3, 0, 0, 2, 5),
    string.char(6, 6, 0, 0, 3, 4, 6, 3, 3, 6, 6, 9, 10, 10, 10, 10, 10, 10, 3, 6, 6, 9, 7, 13, 2, 2, 12, 8, 5, 14, 7, 3),
    string.char(2, 4, 3, 4, 9, 9, 9, 10, 7, 14, 3, 3, 3, 2, 10, 10, 0, 10, 3, 2, 0, 10, 0, 0)
})

function M.sectionAt(cx, cy)
  cx = math.floor(tonumber(cx) or 0)
  cy = math.floor(tonumber(cy) or 0)
  if cy < M.CURSOR_Y_MIN or cy > M.CURSOR_Y_MIN + M.HEIGHT - 1
      or cx < M.CURSOR_X_MIN or cx > M.CURSOR_X_MIN + M.WIDTH - 1 then
    return M.MAPSEC_NONE
  end
  local i = (cx - M.CURSOR_X_MIN) + (cy - M.CURSOR_Y_MIN) * M.WIDTH
  return M.LAYOUT:byte(i + 1) or M.MAPSEC_NONE
end

function M.name(id)
  id = math.floor(tonumber(id) or 0)
  if id < 0 or id >= M.MAPSEC_NONE then return '' end
  return M.NAMES[id + 1] or ''
end

function M.cursorForSection(id)
  id = math.floor(tonumber(id) or 0)
  if id < 0 or id >= M.MAPSEC_NONE then id = 0 end
  local x = M.ENTRY_X:byte(id + 1) or 0
  local y = M.ENTRY_Y:byte(id + 1) or 0
  return x + M.CURSOR_X_MIN, y + M.CURSOR_Y_MIN
end

function M.entrySize(id)
  id = math.floor(tonumber(id) or 0)
  if id < 0 or id > 15 then return 1, 1 end
  return M.ENTRY_W:byte(id + 1) or 1, M.ENTRY_H:byte(id + 1) or 1
end

-- sub_80FBAA0: any cell of this section on the row above.
local function sectionOnRow(sec, y)
  local xmin = M.CURSOR_X_MIN
  local xmax = xmin + M.WIDTH - 1
  for x = xmin, xmax do
    if M.sectionAt(x, y) == sec then return true end
  end
  return false
end

-- sub_80FBA18 everGrandeCityArea / landmark list id.
function M.areaIndex(cx, cy)
  local sec = M.sectionAt(cx, cy)
  if sec == M.MAPSEC_NONE then return 0 end
  local x = math.floor(tonumber(cx) or 0)
  local y = math.floor(tonumber(cy) or 0)
  local i = 0
  while true do
    if x <= 1 then
      local ny = y - 1
      if ny >= 0 and sectionOnRow(sec, ny) then
        y = ny
        x = 0x1D
      else
        break
      end
    else
      x = x - 1
      if M.sectionAt(x, y) == sec then i = i + 1 end
    end
  end
  return i
end

-- landmark.c GetLandmarkName. flag 0xFFFF is always-visible (ROM -1).
M.LANDMARKS = {
  [19] = { -- Route 104
    [0] = { { "FLOWER SHOP", M.FLAG_LANDMARK_FLOWER_SHOP } },
    [1] = {
      { "PETALBURG WOODS", M.FLAG_ALWAYS },
      { "MR. BRINEY'S COTTAGE", M.FLAG_LANDMARK_MR_BRINEY_HOUSE },
    },
  },
  [20] = { -- Route 105
    [0] = { { "ISLAND CAVE", M.FLAG_LANDMARK_ISLAND_CAVE } },
  },
  [21] = { -- Route 106
    [1] = { { "GRANITE CAVE", M.FLAG_ALWAYS } },
  },
  [23] = { -- Route 108
    [0] = { { "ABANDONED SHIP", M.FLAG_LANDMARK_ABANDONED_SHIP } },
  },
  [24] = { -- Route 109
    [0] = {
      { "SEASHORE HOUSE", M.FLAG_LANDMARK_SEASHORE_HOUSE },
      { "SLATEPORT BEACH", M.FLAG_ALWAYS },
    },
  },
  [25] = { -- Route 110
    [0] = {
      { "CYCLING ROAD", M.FLAG_ALWAYS },
      { "NEW MAUVILLE", M.FLAG_LANDMARK_NEW_MAUVILLE },
    },
    [1] = { { "CYCLING ROAD", M.FLAG_ALWAYS } },
    [2] = {
      { "CYCLING ROAD", M.FLAG_ALWAYS },
      { "TRICK HOUSE", M.FLAG_LANDMARK_TRICK_HOUSE },
    },
  },
  [26] = { -- Route 111
    [0] = { { "OLD LADY'S REST STOP", M.FLAG_LANDMARK_OLD_LADY_REST_SHOP } },
    [1] = { { "DESERT", M.FLAG_ALWAYS } },
    [2] = { { "DESERT", M.FLAG_ALWAYS } },
    [3] = {
      { "DESERT RUINS", M.FLAG_LANDMARK_DESERT_RUINS },
      { "DESERT", M.FLAG_ALWAYS },
    },
    [4] = {
      { "THE WINSTRATE FAMILY", M.FLAG_LANDMARK_WINSTRATE_FAMILY },
      { "DESERT", M.FLAG_ALWAYS },
    },
  },
  [27] = { -- Route 112
    [0] = {
      { "FIERY PATH", M.FLAG_LANDMARK_FIERY_PATH },
      { "JAGGED PASS", M.FLAG_ALWAYS },
    },
    [1] = {
      { "CABLE CAR", M.FLAG_ALWAYS },
      { "FIERY PATH", M.FLAG_LANDMARK_FIERY_PATH },
    },
  },
  [28] = { -- Route 113
    [1] = { { "GLASS WORKSHOP", M.FLAG_LANDMARK_GLASS_WORKSHOP } },
  },
  [29] = { -- Route 114
    [1] = { { "FOSSIL MANIAC'S HOUSE", M.FLAG_LANDMARK_FOSSIL_MANIACS_HOUSE } },
    [2] = { { "LANETTE'S HOUSE", M.FLAG_LANDMARK_LANETTES_HOUSE } },
    [3] = { { "METEOR FALLS", M.FLAG_ALWAYS } },
  },
  [30] = { -- Route 115
    [0] = { { "METEOR FALLS", M.FLAG_ALWAYS } },
    [1] = { { "METEOR FALLS", M.FLAG_ALWAYS } },
  },
  [31] = { -- Route 116
    [1] = {
      { "TUNNELER'S REST HOUSE", M.FLAG_LANDMARK_TUNNELERS_REST_HOUSE },
      { "RUSTURF TUNNEL", M.FLAG_ALWAYS },
    },
    [2] = { { "RUSTURF TUNNEL", M.FLAG_ALWAYS } },
  },
  [32] = { -- Route 117
    [2] = { { "POKeMON DAY CARE", M.FLAG_LANDMARK_POKEMON_DAYCARE } },
  },
  [34] = { -- Route 119
    [1] = { { "WEATHER INSTITUTE", M.FLAG_ALWAYS } },
  },
  [35] = { -- Route 120
    [0] = { { "SCORCHED SLAB", M.FLAG_LANDMARK_SCORCHED_SLAB } },
    [2] = { { "ANCIENT TOMB", M.FLAG_LANDMARK_ANCIENT_TOMB } },
  },
  [36] = { -- Route 121
    [2] = { { "SAFARI ZONE ENTRANCE", M.FLAG_ALWAYS } },
  },
  [37] = { -- Route 122
    [0] = { { "MT. PYRE", M.FLAG_ALWAYS } },
    [1] = { { "MT. PYRE", M.FLAG_ALWAYS } },
  },
  [38] = { -- Route 123
    [0] = { { "BERRY MASTER'S HOUSE", M.FLAG_LANDMARK_BERRY_MASTERS_HOUSE } },
  },
  [39] = { -- Route 124
    [7] = { { "HUNTER'S HOUSE", M.FLAG_LANDMARK_HUNTERS_HOUSE } },
  },
  [40] = { -- Route 125
    [2] = { { "SHOAL CAVE", M.FLAG_ALWAYS } },
  },
  [43] = { -- Route 128
    [1] = { { "SEAFLOOR CAVERN", M.FLAG_LANDMARK_SEAFLOOR_CAVERN } },
  },
  [46] = { -- Route 131
    [1] = { { "SKY PILLAR", M.FLAG_LANDMARK_SKY_PILLAR } },
  },
  [47] = { -- Route 132
    [0] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
    [1] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
  },
  [48] = { -- Route 133
    [0] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
    [1] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
    [2] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
  },
  [49] = { -- Route 134
    [0] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
    [1] = { { "OCEAN CURRENT", M.FLAG_ALWAYS } },
    [2] = {
      { "SEALED CHAMBER", M.FLAG_LANDMARK_SEALED_CHAMBER },
      { "OCEAN CURRENT", M.FLAG_ALWAYS },
    },
  },
  [56] = { -- Mt. Chimney
    [2] = {
      { "CABLE CAR", M.FLAG_ALWAYS },
      { "JAGGED PASS", M.FLAG_ALWAYS },
    },
  },
}

function M.landmarkNames(mapsec, area, flags)
  local byArea = M.LANDMARKS[mapsec]
  local list = byArea and byArea[area]
  if not list then return {} end
  flags = flags or {}
  local out = {}
  for i = 1, #list do
    local row = list[i]
    local flag = row[2]
    if flag == M.FLAG_ALWAYS or flags[flag] then
      out[#out + 1] = row[1]
    end
  end
  return out
end

-- Zoom-in scroll that keeps the cursor cell at (ZOOM_CX, ZOOM_CY).
function M.zoomScrollForCursor(cx, cy)
  local sx = cx * 8 - 52
  local sy = cy * 8 - 68
  if sx < M.SCROLL_X_MIN then sx = M.SCROLL_X_MIN end
  if sx > M.SCROLL_X_MAX then sx = M.SCROLL_X_MAX end
  if sy < M.SCROLL_Y_MIN then sy = M.SCROLL_Y_MIN end
  if sy > M.SCROLL_Y_MAX then sy = M.SCROLL_Y_MAX end
  return sx, sy
end

function M.zoomCellFromScroll(sx, sy)
  return math.floor((sx + 44) / 8) + 1, math.floor((sy + 52) / 8) + 2
end

-- Map-pixel (mx, my) → screen, matching CalcZoomScrollParams.
function M.screenXY(mx, my, scrollX, scrollY, pa)
  pa = pa or M.ZOOM_PA_OUT
  if pa < 1 then pa = 1 end
  local s = M.ZOOM_PA_OUT / pa
  local ox = (scrollX or 0) + M.ZOOM_CX
  local oy = (scrollY or 0) + M.ZOOM_CY
  return M.ZOOM_CX + s * (mx - ox), M.ZOOM_CY + s * (my - oy)
end

return M
