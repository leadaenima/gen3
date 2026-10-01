-- Hand-measured Emerald rooms and houses.
--
-- The piece tables in data/emerald_rooms.lua are the readings from the
-- drawings: a chair is a back and a seat, a wall is a plane, a plant is a
-- card. A layout is one room, so every map that uses it (every Pokémon
-- Center, every House1) gets the same pieces. An outdoor drawing is matched
-- by its metatile rows and stamped at every copy, including the canonical one.

local V = ...

local Gen3 = V.require("Gen3")

local EmeraldPieces = {}

local SHADE_SOUTH, SHADE_TOP, SHADE_SIDE, SHADE_NORTH = 1, 0.95, 0.78, 0.68

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

-- Outdoor drawings. wall is the facade height in pixels (the rows that
-- stand up). pitch 0 is a flat roof. match is the half-open row span that
-- has to be the same metatiles for another copy to count; the top row is
-- left out where a town paints its own path or a tree over the roof.
local OUTDOOR = {
  { layout = "LAYOUT_LITTLEROOT_TOWN", x = 2, y = 4, w = 5, h = 5, wall = 26, pitch = 22 },
  { layout = "LAYOUT_LITTLEROOT_TOWN", x = 13, y = 4, w = 5, h = 5, wall = 26, pitch = 22 },
  { layout = "LAYOUT_LITTLEROOT_TOWN", x = 3, y = 12, w = 7, h = 5, wall = 27, pitch = 18 },
  { layout = "LAYOUT_PETALBURG_CITY", x = 19, y = 13, w = 4, h = 4, wall = 26, pitch = 0, match = { 1, 4 } },
  { layout = "LAYOUT_MAUVILLE_CITY", x = 22, y = 11, w = 4, h = 4, wall = 26, pitch = 0, match = { 1, 4 } },
  { layout = "LAYOUT_OLDALE_TOWN", x = 4, y = 4, w = 4, h = 4, wall = 28, pitch = 22 },
  { layout = "LAYOUT_OLDALE_TOWN", x = 14, y = 13, w = 4, h = 4, wall = 28, pitch = 22 },
  { layout = "LAYOUT_ROUTE104", x = 15, y = 47, w = 5, h = 4, wall = 27, pitch = 22 },
  { layout = "LAYOUT_ROUTE104", x = 3, y = 15, w = 6, h = 4, wall = 24, pitch = 22 },
  { layout = "LAYOUT_PETALBURG_CITY", x = 9, y = 16, w = 4, h = 4, wall = 24, pitch = 22 },
  { layout = "LAYOUT_PETALBURG_CITY", x = 5, y = 2, w = 5, h = 4, wall = 24, pitch = 22 },
  { layout = "LAYOUT_PETALBURG_CITY", x = 12, y = 4, w = 6, h = 5, wall = 28, pitch = 18 },
  { layout = "LAYOUT_RUSTBORO_CITY", x = 24, y = 15, w = 6, h = 5, wall = 28, pitch = 18 },
  { layout = "LAYOUT_RUSTBORO_CITY", x = 7, y = 7, w = 10, h = 9, wall = 40, pitch = 0 },
  { layout = "LAYOUT_RUSTBORO_CITY", x = 27, y = 38, w = 3, h = 3, wall = 9, pitch = 0 },
}

local PINNED_LAYOUT = {
  LAYOUT_HOUSE1 = true,
  LAYOUT_HOUSE2 = true,
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB = true,
  LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE = true,
  LAYOUT_POKEMON_CENTER_1F = true,
  LAYOUT_POKEMON_CENTER_2F = true,
  LAYOUT_LAVARIDGE_TOWN_POKEMON_CENTER_1F = true,
  LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F = true,
  LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F = true,
  LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_1F = true,
  LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_2F = true,
}

local rooms = nil
local function roomTable()
  if rooms == nil then
    local ok, t = pcall(V.data, "emerald_rooms")
    rooms = (ok and type(t) == "table") and t or false
  end
  return rooms or nil
end

local function entryFor(map)
  local ok, cat = pcall(V.data, "gen3_maps")
  if not (ok and cat and type(cat.maps) == "table") then return nil end
  local id = tostring(map.id or "")
  local hit = cat.maps[id]
  if type(hit) == "table" then return hit end
  local name = type(map.def) == "table" and map.def.name or nil
  if type(name) ~= "string" or name == "" then
    local okN, MapNames = pcall(require, "src.world.gen3.MapNames")
    if okN and MapNames and type(MapNames.of) == "function" then
      name = MapNames.of(id)
    end
  end
  if type(name) ~= "string" then return nil end
  for _, rec in pairs(cat.maps) do
    if type(rec) == "table" and rec.name == name then return rec end
  end
  return nil
end

local function insidePart(part, cx, cy)
  if part.ellipse then
    local rx, ry = part.rx, part.ry
    if not rx or not ry or rx == 0 or ry == 0 then return false end
    local dx = (cx - part.cx) / rx
    local dy = (cy - part.cy) / ry
    return dx * dx + dy * dy <= 1
  end
  if part.poly then
    local hit = false
    local n = #part.poly
    for k = 1, n do
      local a = part.poly[k]
      local b = part.poly[k % n + 1]
      local ay, by = a[2], b[2]
      if (ay > cy) ~= (by > cy) then
        local ax, bx = a[1], b[1]
        if cx < ax + (bx - ax) * (cy - ay) / (by - ay) then hit = not hit end
      end
    end
    return hit
  end
  local x0, y0, x1, y1 = part[1], part[2], part[3], part[4]
  if not x0 then return false end
  return x0 <= cx and cx < x1 and y0 <= cy and cy < y1
end

local function inside(shape, x, y)
  if not shape then return false end
  local cx, cy = x + 0.5, y + 0.5
  for i = 1, #shape do
    if insidePart(shape[i], cx, cy) then return true end
  end
  return false
end

local function hexSet(list)
  local set = {}
  if not list then return set end
  for i = 1, #list do set[list[i]] = true end
  return set
end

local function rgbHex(r, g, b)
  return string.format("%02x%02x%02x", r, g, b)
end

-- -----------------------------------------------------------------------
-- atlas sampling

local function beginSample(S, map)
  local tileset = map.tileset
  if not tileset or not Gen3.isGen3(tileset) then return nil end
  local info = Gen3.describe(tileset)
  local img = Gen3.atlasDataForTileset(tileset)
  if not (info and img and img.getPixel) then return nil end
  local perRow = info.perRow
  local atlasW, atlasH = info.width, info.height
  local function tileOrigin(tile)
    return (tile % perRow) * 8, math.floor(tile / perRow) * 8
  end
  local function pixelOf(tile, ox, oy)
    local ax, ay = tileOrigin(tile)
    ax, ay = ax + ox, ay + oy
    if ax < 0 or ay < 0 or ax >= atlasW or ay >= atlasH then return nil end
    local r, g, b = img:getPixel(ax, ay)
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
           math.floor(b * 255 + 0.5), ax, ay
  end
  local api = { perRow = perRow, atlasW = atlasW, atlasH = atlasH }
  function api.mapPixel(px, py)
    local tile = S.tileAt[keyOf(math.floor(px / 8), math.floor(py / 8))]
    if not tile then return nil end
    return pixelOf(tile, px % 8, py % 8)
  end
  function api.metaPixel(metatile, lx, ly)
    local tile = metatile * 4 + (ly >= 8 and 2 or 0) + (lx >= 8 and 1 or 0)
    return pixelOf(tile, lx % 8, ly % 8)
  end
  function api.uv(px, py)
    local tile = S.tileAt[keyOf(math.floor(px / 8), math.floor(py / 8))]
    if not tile then return 0, 0 end
    local ax, ay = tileOrigin(tile)
    return (ax + (px % 8)) / atlasW, (ay + (py % 8)) / atlasH
  end
  return api
end

local function push(S, a, b, c, d, uv, shade)
  local quads = S.objectQuads
  quads[#quads + 1] = { a, b, c, d, uv = uv, shade = shade, own = true }
end

-- A south-facing quad. Art rows increase downward; world y increases up.
-- ayTop is the art row at the TOP of the face. One art row is one world pixel.
local function southQuad(S, sample, x0, x1, z, y0, y1, ax0, ayTop, base)
  local span = y1 - y0
  local u0, v0 = sample.uv(ax0, ayTop)
  local u1 = select(1, sample.uv(x1, ayTop))
  local _, v1 = sample.uv(ax0, ayTop + span)
  push(S,
    { x0, base + y0, z }, { x1, base + y0, z },
    { x1, base + y1, z }, { x0, base + y1, z },
    { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, SHADE_SOUTH)
end

local function topQuad(S, sample, x0, x1, z0, z1, y, ax0, ay0, ax1, ay1)
  local u0, v0 = sample.uv(ax0, ay0)
  local u1, _ = sample.uv(ax1, ay0)
  local _, v1 = sample.uv(ax0, ay1)
  push(S,
    { x0, y, z0 }, { x1, y, z0 },
    { x1, y, z1 }, { x0, y, z1 },
    { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, SHADE_TOP)
end

-- -----------------------------------------------------------------------
-- one room

local function claimCell(S, cx, cy, metatile)
  local shape = { class = "building", h = 0, art = "building",
                  flat = false, authored = true, base = 0 }
  local m = metatile or 0
  for dy = 0, 1 do
    for dx = 0, 1 do
      local k = keyOf(cx * 2 + dx, cy * 2 + dy)
      S.skip[k] = true
      S.shapeAt[k] = shape
      -- the floor metatile's own quadrant, so the painted ground is that
      -- cell's floor and not metatile 0
      S.ground[k] = m * 4 + dy * 2 + dx
    end
  end
end

local function buildRoom(S, map, g3, sample, room)
  local W = (g3.width or 0) * 16
  local H = (g3.height or 0) * 16
  if W <= 0 or H <= 0 or W > 4096 or H > 4096 then return end
  local pieces = room.pieces or {}
  local floors = room.ground or {}
  local function isFloor(x, y)
    local lx, ly = x % 16, y % 16
    local r, g, b = sample.mapPixel(x, y)
    if not r then return false end
    for i = 1, #floors do
      local fr, fg, fb = sample.metaPixel(floors[i], lx, ly)
      if fr and fr == r and fg == g and fb == b then return true end
    end
    return false
  end

  local owner = {}
  local function idx(x, y) return y * W + x end
  local claimedCell = {}

  for k, pc in ipairs(pieces) do
    local leave = hexSet(pc.leave)
    local left = {}
    if next(leave) then
      local seen = {}
      local stack = {}
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if not inside(pc.shape, x, y) then
            local r, g, b = sample.mapPixel(x, y)
            if r and leave[rgbHex(r, g, b)] then
              local i = idx(x, y)
              seen[i] = true
              stack[#stack + 1] = i
            end
          end
        end
      end
      local n = 1
      while n <= #stack do
        local i = stack[n]
        n = n + 1
        local x, y = i % W, math.floor(i / W)
        local neigh = { x + 1, y, x - 1, y, x, y + 1, x, y - 1 }
        for s = 1, 8, 2 do
          local nx, ny = neigh[s], neigh[s + 1]
          if nx >= 0 and ny >= 0 and nx < W and ny < H then
            local j = idx(nx, ny)
            if not seen[j] then
              local r, g, b = sample.mapPixel(nx, ny)
              if r and leave[rgbHex(r, g, b)] then
                seen[j] = true
                stack[#stack + 1] = j
                if inside(pc.shape, nx, ny) then left[j] = true end
              end
            end
          end
        end
      end
    end
    local solid = pc.fill or pc.facet
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local i = idx(x, y)
        if owner[i] == nil and not left[i]
           and (solid or inside(pc.claim, x, y) or not isFloor(x, y))
           and inside(pc.shape, x, y) then
          owner[i] = k
        end
      end
    end
  end

  local groundId = floors[1]
  local function note(x, y)
    if x < 0 or y < 0 then return end
    local c = math.floor(x / 16) + math.floor(y / 16) * 4096
    if not claimedCell[c] then
      claimedCell[c] = true
      claimCell(S, math.floor(x / 16), math.floor(y / 16), groundId)
    end
  end

  for k, pc in ipairs(pieces) do
    local base = pc.base or 0
    local mine = {}
    local maxY = -1
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if owner[idx(x, y)] == k then
          mine[#mine + 1] = x
          mine[#mine + 1] = y
          if y > maxY then maxY = y end
          note(x, y)
        end
      end
    end
    local height = pc.height or 0
    if #mine > 0 then
      if pc.card then
        local foot = maxY + 1
        local row, i = {}, 1
        while i <= #mine do
          local x, y = mine[i], mine[i + 1]
          i = i + 2
          local list = row[y]
          if not list then list = {}; row[y] = list end
          list[#list + 1] = x
        end
        for y, xs in pairs(row) do
          table.sort(xs)
          local run = xs[1]
          for n = 2, #xs + 1 do
            if xs[n] ~= xs[n - 1] + 1 then
              southQuad(S, sample, run, xs[n - 1] + 1, foot,
                        foot - (y + 1), foot - y, run, y, base)
              run = xs[n]
            end
          end
        end
      else
        local foot = pc.foot
        if foot == nil and not pc.fill then foot = maxY + 1 end
        local frontFrom = foot and (foot - height) or nil
        local rowTop, rowFront = {}, {}
        local i = 1
        while i <= #mine do
          local x, y = mine[i], mine[i + 1]
          i = i + 2
          local bucket, key
          if not foot or y >= frontFrom then
            bucket, key = rowFront, y
          else
            bucket, key = rowTop, y
          end
          local list = bucket[key]
          if not list then list = {}; bucket[key] = list end
          list[#list + 1] = x
        end
        local zFront = foot or (maxY + 1)
        for y, xs in pairs(rowFront) do
          table.sort(xs)
          local run = xs[1]
          local function flush(a, b)
            local yb = zFront - (y + 1)
            local yt = zFront - y
            if pc.fill and not pc.foot then
              yb = maxY - y
              yt = yb + 1
            end
            southQuad(S, sample, a, b, zFront, yb, yt, a, y, base)
          end
          for n = 2, #xs + 1 do
            if xs[n] ~= xs[n - 1] + 1 then
              flush(run, xs[n - 1] + 1)
              run = xs[n]
            end
          end
        end
        local yTop = base + height
        local limit = pc.against or pc.back
        for y, xs in pairs(rowTop) do
          table.sort(xs)
          local run = xs[1]
          local function flush(a, b)
            local z0 = y + height
            local z1 = z0 + 1
            if limit and z0 < limit then return end
            topQuad(S, sample, a, b, z0, z1, yTop, a, y, b, y + 1)
          end
          for n = 2, #xs + 1 do
            if xs[n] ~= xs[n - 1] + 1 then
              flush(run, xs[n - 1] + 1)
              run = xs[n]
            end
          end
        end
        if pc.back and foot then
          local north = {}
          for y, xs in pairs(rowTop) do
            if y + height <= pc.back then
              -- already at or north of the collision back
            else
              for n = 1, #xs do
                local x = xs[n]
                local prev = north[x]
                if not prev or y < prev then north[x] = y end
              end
            end
          end
          for x, y in pairs(north) do
            local z1 = y + height
            if z1 > pc.back then
              topQuad(S, sample, x, x + 1, pc.back, z1, yTop, x, y, x + 1, y + 1)
            end
          end
        end
      end
    end

    local side = pc.side
    local walls = pc.walls
    if side and walls then
      for w = 1, #walls do
        local wall = walls[w]
        local a, b = wall[1], wall[2]
        local tall = wall[3] or height
        if a and b then
          local x0, z0, x1, z1 = a[1], a[2], b[1], b[2]
          note(x0, z0)
          note(x1, z1)
          local y0, y1 = base, base + tall
          local sx0, sy0, sx1, sy1 = side[1], side[2], side[3], side[4]
          local u0, v0 = sample.uv(sx0, sy0)
          local u1, v1 = sample.uv(sx1, sy1)
          local uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }
          if z0 == z1 then
            push(S, { x0, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z0 },
                 uv, SHADE_SIDE)
          else
            push(S, { x0, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z0 },
                 uv, SHADE_SIDE)
          end
        end
      end
    end
    if pc.facet and side then
      local a, b = pc.facet[1], pc.facet[2]
      if a and b then
        local y0, y1 = base, base + height
        local u0, v0 = sample.uv(side[1], side[2])
        local u1, v1 = sample.uv(side[3], side[4])
        push(S,
          { a[1], y0, a[3] }, { b[1], y0, b[3] },
          { b[1], y1, b[3] }, { a[1], y1, a[3] },
          { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, SHADE_SIDE)
        note(a[1], a[3])
        note(b[1], b[3])
      end
    end
  end
end

-- -----------------------------------------------------------------------
-- outdoor copies

local patterns = {}

local function readPattern(metaAt, spec)
  local rows = {}
  local r0 = spec.match and spec.match[1] or 0
  local r1 = spec.match and spec.match[2] or spec.h
  local primary = true
  for row = r0, r1 - 1 do
    local line = {}
    for col = 0, spec.w - 1 do
      local id = metaAt(spec.x + col, spec.y + row)
      if id == nil then return nil end
      line[col + 1] = id
      if id >= 512 then primary = false end
    end
    rows[#rows + 1] = line
  end
  rows.primary = primary
  rows.layout = spec.layout
  return rows
end

local function defForLayout(layout)
  local ok, cat = pcall(V.data, "gen3_maps")
  if not (ok and cat and cat.maps) then return nil end
  local name
  for _, rec in pairs(cat.maps) do
    if type(rec) == "table" and rec.layout == layout then
      name = rec.name
      break
    end
  end
  if not name then return nil end
  local maps
  local game = rawget(_G, "Game")
  if game and game.data and game.data.maps then
    maps = game.data.maps.maps or game.data.maps
  end
  if type(maps) ~= "table" then
    local okD, Data = pcall(require, "src.core.Data")
    if okD and Data then maps = Data.maps end
  end
  if type(maps) ~= "table" then return nil end
  for _, def in pairs(maps) do
    if type(def) == "table" and def.name == name and def.width
       and (def.blocks or def.grid) then
      return def
    end
  end
  return nil
end

local function metaFromDef(def)
  local ok, Map = pcall(require, "src.world.Map")
  if not (ok and Map and Map.blockArray) then return nil end
  local arr = Map.blockArray(def)
  if type(arr) ~= "table" then return nil end
  local w = def.width
  return function(x, y)
    if x < 0 or y < 0 or x >= w or y >= (def.height or 0) then return nil end
    return arr[y * w + x + 1]
  end
end

local function patternFor(spec, metaHere, layoutHere)
  local hit = patterns[spec]
  if hit ~= nil then return hit or nil end
  local meta = metaHere
  if layoutHere ~= spec.layout then
    local def = defForLayout(spec.layout)
    meta = def and metaFromDef(def) or nil
  end
  if not meta then return nil end
  local rows = readPattern(meta, spec)
  if rows then patterns[spec] = rows end
  return rows
end

local function placeOutdoor(S, map, g3, sample, spec, cx, cy)
  local ox = cx * 16
  local oz = cy * 16
  local w, d = spec.w * 16, spec.h * 16
  local wall = math.min(spec.wall or 16, d - 1)
  local frontZ = oz + d
  local backZ = oz
  local floor = 1
  if g3.metatileAt then
    local okF, id = pcall(g3.metatileAt, cx, cy + spec.h)
    if okF and id then floor = id end
  end
  for row = 0, spec.h - 1 do
    for col = 0, spec.w - 1 do
      claimCell(S, cx + col, cy + row, floor)
    end
  end
  -- facade: the southern `wall` rows of the drawing, one art row per world pixel
  local ay = oz + d - wall
  for row = 0, wall - 1 do
    local artY = ay + (wall - 1 - row)
    local x = ox
    while x < ox + w do
      local nx = math.min(ox + w, x - (x % 8) + 8)
      if nx <= x then nx = x + 8 end
      southQuad(S, sample, x, nx, frontZ, row, row + 1, x, artY, 0)
      x = nx
    end
  end
  -- side walls, dressed with a plaster column of the facade
  local plasterX = ox + 8
  local u0, v1 = sample.uv(plasterX, ay + wall)
  local u1, v0 = sample.uv(plasterX + 8, ay)
  local uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }
  push(S, { ox, 0, backZ }, { ox, 0, frontZ }, { ox, wall, frontZ }, { ox, wall, backZ },
       uv, SHADE_SIDE)
  push(S, { ox + w, 0, frontZ }, { ox + w, 0, backZ },
       { ox + w, wall, backZ }, { ox + w, wall, frontZ }, uv, SHADE_SIDE)
  push(S, { ox + w, 0, backZ }, { ox, 0, backZ }, { ox, wall, backZ }, { ox + w, wall, backZ },
       uv, SHADE_NORTH)

  local pitch = spec.pitch or 0
  if pitch <= 0 then
    local z = backZ
    while z < frontZ do
      local nz = math.min(frontZ, z - (z % 8) + 8)
      if nz <= z then nz = z + 1 end
      local artY = z < ay and z or (ay - 1)
      local artSpan = (z < ay) and (nz - z) or 1
      local x = ox
      while x < ox + w do
        local nx = math.min(ox + w, x - (x % 8) + 8)
        if nx <= x then nx = x + 8 end
        topQuad(S, sample, x, nx, z, nz, wall, x, artY, nx, artY + artSpan)
        x = nx
      end
      z = nz
    end
    return
  end
  local halfD = (frontZ - backZ) / 2
  local rise = halfD * math.tan(pitch * math.pi / 180)
  local ridgeY = wall + rise
  local ridgeZ = (frontZ + backZ) / 2
  local inset = math.min(w / 2, halfD)
  local x0, x1 = ox + inset, ox + w - inset
  local ru0, rv0 = sample.uv(ox, oz)
  local ru1, rv1 = sample.uv(ox + w, ay)
  local roofUV = { { ru0, rv0 }, { ru1, rv0 }, { ru1, rv1 }, { ru0, rv1 } }
  push(S,
    { ox, wall, frontZ }, { ox + w, wall, frontZ },
    { x1, ridgeY, ridgeZ }, { x0, ridgeY, ridgeZ }, roofUV, SHADE_TOP)
  push(S,
    { ox + w, wall, backZ }, { ox, wall, backZ },
    { x0, ridgeY, ridgeZ }, { x1, ridgeY, ridgeZ }, roofUV, SHADE_TOP)
  push(S,
    { ox, wall, backZ }, { ox, wall, frontZ },
    { x0, ridgeY, ridgeZ }, { x0, ridgeY, ridgeZ }, uv, SHADE_SIDE)
  push(S,
    { ox + w, wall, frontZ }, { ox + w, wall, backZ },
    { x1, ridgeY, ridgeZ }, { x1, ridgeY, ridgeZ }, uv, SHADE_SIDE)
end

local function buildOutdoor(S, map, g3, sample, layout)
  if not g3.metatileAt then return end
  local function here(x, y)
    local ok, id = pcall(g3.metatileAt, x, y)
    if not ok then return nil end
    return id
  end
  for i = 1, #OUTDOOR do
    local spec = OUTDOOR[i]
    local rows = patternFor(spec, here, layout)
    if rows and (rows.primary or spec.layout == layout) then
      local mw, mh = g3.width or 0, g3.height or 0
      local r0 = spec.match and spec.match[1] or 0
      for cy = 0, mh - spec.h do
        for cx = 0, mw - spec.w do
          local same = true
          for r = 1, #rows do
            local line = rows[r]
            for c = 1, spec.w do
              if here(cx + c - 1, cy + r0 + r - 1) ~= line[c] then
                same = false
                break
              end
            end
            if not same then break end
          end
          if same then
            local corner = keyOf(cx * 2, cy * 2)
            if not S.skip[corner] then
              placeOutdoor(S, map, g3, sample, spec, cx, cy)
            end
          end
        end
      end
    end
  end
end

function EmeraldPieces.build(S, map)
  if not (S and S.isGen3 and map) then return end
  local ok, err = pcall(function()
    local g3ok, g3 = pcall(Gen3.forMap, map)
    if not (g3ok and g3) then return end
    local sample = beginSample(S, map)
    if not sample then return end
    local entry = entryFor(map)
    local layout = entry and entry.layout
    local roomsOf = roomTable()
    local room = layout and roomsOf and roomsOf[layout]
    -- These layouts already have metatile pins in data/gen3_shapes.lua.
    -- The piece pass would stand a second chair and table on the same cells.
    -- Marts and the Rustboro gym have no pin block, so their pieces stay.
    if room and not PINNED_LAYOUT[layout] then
      buildRoom(S, map, g3, sample, room)
    end
    -- Outdoor stamps stay off. The town mesher already builds each house
    -- from its door and its drawing. This pass stood a second facade and a
    -- pitched lid on the same footprint, which is the doubled exterior.
  end)
  if not ok and not EmeraldPieces._warned then
    EmeraldPieces._warned = true
    pcall(function()
      require("src.core.Logger").info("DRAMATIC_SHAPE: emerald pieces skipped: %s",
        tostring(err))
    end)
  end
end

function EmeraldPieces.invalidate()
  rooms = nil
  for k in pairs(patterns) do patterns[k] = nil end
end

return EmeraldPieces
