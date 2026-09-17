-- Shape Studio: pick a map cell or sprite under the cursor.
-- Uses Voxel3D.project over a neighbourhood (handles curve + free pitch).

local V = ...

local Voxel3D = V.require("Voxel3D")
local Structures = V.require("Structures")
local Gen3 = V.require("Gen3")
local TileShape = V.require("TileShape")

local Picker = {}

-- Map window mouse into the voxel canvas, assuming the presented world
-- canvas fills the window (DRAMATIC_SHAPE's usual path). Falls back to a
-- direct mapping when sizes are unknown.
function Picker.mouseToCanvas(mx, my)
  local cw, ch = Voxel3D.size()
  if not (cw and ch and cw > 0 and ch > 0) then return mx, my end
  local ww, wh = love.graphics.getDimensions()
  if not (ww and wh and ww > 0 and wh > 0) then return mx, my end
  -- letterbox-aware: fit canvas into window preserving aspect
  local scale = math.min(ww / cw, wh / ch)
  local dw, dh = cw * scale, ch * scale
  local ox, oy = (ww - dw) * 0.5, (wh - dh) * 0.5
  local cx = (mx - ox) / scale
  local cy = (my - oy) / scale
  return cx, cy, cw, ch
end

local function groundY(map, cx, cy)
  local ok, h = pcall(Structures.terraceAt, map, cx, cy)
  if ok and type(h) == "number" then return h end
  return 0
end

function Picker.pickCell(map, canvasX, canvasY, radius)
  if not map then return nil end
  radius = radius or 28
  local best, bestD = nil, radius * radius
  local focus = Voxel3D.focus or Voxel3D.eye
  if not focus then return nil end
  local cx0 = math.floor((focus[1] or 0) / 16)
  local cy0 = math.floor((focus[3] or 0) / 16)
  local Overrides = V.require("ShapeOverrides")
  for cy = cy0 - 14, cy0 + 14 do
    for cx = cx0 - 14, cx0 + 14 do
      local okB, inb = pcall(function() return map:inBounds(cx, cy) end)
      if okB and inb then
        local wx, wz = cx * 16 + 8, cy * 16 + 8
        local gh = groundY(map, cx, cy) + (Overrides.zOffFor(map, cx, cy) or 0)
        local sx, sy = Voxel3D.project(wx, gh, wz)
        if sx then
          local dx, dy = sx - canvasX, sy - canvasY
          local d = dx * dx + dy * dy
          if d < bestD then
            bestD = d
            best = { cx = cx, cy = cy, sx = sx, sy = sy }
          end
        end
      end
    end
  end
  return best
end

-- entities: list of { sprite=, px=, py=, gh=, lift=, actor= } (VoxelScene poses)
function Picker.pickSprite(entities, canvasX, canvasY, radius)
  if type(entities) ~= "table" then return nil end
  radius = radius or 36
  local best, bestD = nil, radius * radius
  for _, e in ipairs(entities) do
    if e and e.sprite and e.px and e.py then
      local y = (e.gh or 0) + (e.lift or 0)
      local sx, sy = Voxel3D.project(e.px + 8, y + 8, e.py + 8)
      if sx then
        local dx, dy = sx - canvasX, sy - canvasY
        local d = dx * dx + dy * dy
        if d < bestD then
          bestD = d
          best = e
        end
      end
    end
  end
  return best
end

function Picker.inspectCell(map, cx, cy)
  if not map then return nil end
  local info = {
    kind = "cell",
    mapId = map.id,
    cx = cx, cy = cy,
    tileset = map.tileset and (map.tileset.id or map.tileset.image),
  }
  local shapes = TileShape.forMap(map)
  local tx, ty = cx * 2, cy * 2 + 1
  local tile = Gen3.tileAt(map, tx, ty)
  info.tile = tile
  info.tx, info.ty = tx, ty
  local s = TileShape.at(map, shapes, tile, tx, ty)
  if s then
    info.class = s.class
    info.h = s.h
    info.art = s.art
    info.authored = s.authored
    info.override = s.override
  end
  local ctx = Gen3.forMap(map)
  if ctx then
    if ctx.metatileAt then
      local ok, m = pcall(ctx.metatileAt, cx, cy)
      if ok then info.metatile = m end
    end
    if ctx.elevationAt then
      local ok, e = pcall(ctx.elevationAt, cx, cy)
      if ok then info.elevation = e end
    end
    if ctx.classAt then
      local ok, c = pcall(ctx.classAt, cx, cy, info.metatile)
      if ok then info.behaviourClass = c end
    end
    -- behaviour byte when attributes exist
    if info.metatile and ctx.attributes then
      local ok, attr = pcall(ctx.attributes, info.metatile)
      if ok and type(attr) == "number" then
        info.behaviour = attr % 256
      end
    end
  end
  local Overrides = V.require("ShapeOverrides")
  info.zOff = Overrides.zOffFor(map, cx, cy)
  info.cellOverride = Overrides.getCell(map.id, cx, cy)
  if Overrides.texFor then
    info.tex = Overrides.texFor(map, cx, cy)
  end
  return info
end

function Picker.inspectSprite(map, entity)
  if not entity or not entity.sprite then return nil end
  local def = entity.sprite.def or {}
  local actor = entity.actor
  local info = {
    kind = "sprite",
    mapId = map and map.id,
    sheet = def.image,
    graphicsId = def.graphicsId or def.id,
    objId = actor and (actor.id or actor.localId or actor.eventId),
    cellX = actor and actor.cellX,
    cellY = actor and actor.cellY,
    px = entity.px, py = entity.py,
    yOff = 0,
  }
  local Overrides = V.require("ShapeOverrides")
  info.yOff = Overrides.spriteLift(map, actor, def)
  return info
end

return Picker
