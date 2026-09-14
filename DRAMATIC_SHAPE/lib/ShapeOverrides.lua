-- Shape Studio: runtime + baked presentational overrides.
-- Presentational only. Never touches collision, scripts, or gameplay.
-- Loaded ahead of shipped voxel_heights / gen3_shapes pins.

local V = ...

local Overrides = {
  version = 1,
  rev = 0,
  cells = {},       -- "mapId:cx:cy" -> { class, h, art, zOff, tex }
  types = {},       -- "ts:meta:METATILE" or "ts:tile:TILE" -> { class, h, art, tex }
  sprites = {},     -- instance / sheet / gfx keys -> { yOff }
  chromakey = {},   -- "*" global, or sheet path -> { {r,g,b,tol}, ... }
  maps = {},        -- mapId -> { layerOffsets = { [elev]=n } }
}

local dirty = false
local undoStack = {}
local MAX_UNDO = 64

-- Debounced disk persist (autosave). Coalesces wheel/height spam so one
-- write lands after scrubbing stops. flushPersist() forces write on close.
local persistDue = nil
local PERSIST_DEBOUNCE = 0.3
local persistCb = nil

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do
    if type(v) == "table" then o[k] = copy(v) else o[k] = v end
  end
  return o
end

local function snapshot()
  return {
    cells = copy(Overrides.cells),
    types = copy(Overrides.types),
    sprites = copy(Overrides.sprites),
    chromakey = copy(Overrides.chromakey),
    maps = copy(Overrides.maps),
    rev = Overrides.rev,
  }
end

local function pushUndo()
  undoStack[#undoStack + 1] = snapshot()
  if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
end

function Overrides.markDirty()
  dirty = true
  Overrides.rev = (Overrides.rev or 0) + 1
  Overrides.schedulePersist()
end

function Overrides.schedulePersist()
  persistDue = PERSIST_DEBOUNCE
end

function Overrides.onPersisted(cb)
  persistCb = cb
end

-- Write now if dirty (Studio close / force). Clears debounce timer.
function Overrides.flushPersist()
  persistDue = nil
  if not dirty then return true, "clean" end
  return Overrides.bake()
end

function Overrides.update(dt)
  if not persistDue then return end
  persistDue = persistDue - (dt or 0)
  if persistDue > 0 then return end
  persistDue = nil
  if not dirty then return end
  local ok, note = Overrides.bake()
  if persistCb then pcall(persistCb, ok, note) end
end

function Overrides.isDirty()
  return dirty
end

-- Deep copy of current override tables (Studio open/bake baseline).
function Overrides.captureSnapshot()
  return snapshot()
end

function Overrides.restoreSnapshot(snap, recordUndo)
  if type(snap) ~= "table" then return false end
  if recordUndo ~= false then pushUndo() end
  Overrides.cells = copy(snap.cells) or {}
  Overrides.types = copy(snap.types) or {}
  Overrides.sprites = copy(snap.sprites) or {}
  Overrides.chromakey = copy(snap.chromakey) or {}
  Overrides.maps = copy(snap.maps) or {}
  Overrides.rev = (Overrides.rev or 0) + 1
  dirty = false
  persistDue = nil
  return true
end


function Overrides.signature()
  return "studio-" .. tostring(Overrides.rev or 0)
end

function Overrides.cellKey(mapId, cx, cy)
  return tostring(mapId) .. ":" .. tostring(cx) .. ":" .. tostring(cy)
end

function Overrides.typeKeyMetatile(tilesetId, metatile)
  return "ts:" .. tostring(tilesetId) .. ":meta:" .. tostring(metatile)
end

function Overrides.typeKeyTile(tilesetId, tile)
  return "ts:" .. tostring(tilesetId) .. ":tile:" .. tostring(tile)
end

function Overrides.spriteInstanceKey(mapId, objId)
  return "map:" .. tostring(mapId) .. ":obj:" .. tostring(objId)
end

function Overrides.spriteSheetKey(path)
  return "sheet:" .. tostring(path)
end

function Overrides.spriteGfxKey(gfxId)
  return "gfx:" .. tostring(gfxId)
end

function Overrides.getCell(mapId, cx, cy)
  return Overrides.cells[Overrides.cellKey(mapId, cx, cy)]
end

function Overrides.getType(key)
  return Overrides.types[key]
end

function Overrides.getSprite(key)
  return Overrides.sprites[key]
end

-- Resolve shape override for one 8px tile. Instance (cell) wins over type.
function Overrides.shapeFor(map, tile, tx, ty)
  if not map then return nil end
  local mapId = map.id
  local cx, cy = math.floor(tx / 2), math.floor(ty / 2)
  local cell = Overrides.getCell(mapId, cx, cy)
  if cell and (cell.class ~= nil or cell.h ~= nil or cell.art ~= nil) then
    return cell
  end
  local ts = map.tileset
  local tsId = ts and (ts.id or ts.image) or "?"
  local Gen3 = V.require("Gen3")
  if Gen3.mapIsGen3 and Gen3.mapIsGen3(map) then
    local ctx = Gen3.forMap(map)
    if ctx and ctx.metatileAt then
      local ok, m = pcall(ctx.metatileAt, cx, cy)
      if ok and m ~= nil then
        local t = Overrides.types[Overrides.typeKeyMetatile(tsId, m)]
        if t then return t end
      end
    end
  end
  if tile ~= nil then
    local t = Overrides.types[Overrides.typeKeyTile(tsId, tile)]
    if t then return t end
  end
  return nil
end

function Overrides.zOffFor(map, cx, cy)
  if not map then return 0 end
  local mapId = map.id
  local z = 0
  local cell = Overrides.getCell(mapId, cx, cy)
  if cell and type(cell.zOff) == "number" then z = z + cell.zOff end
  local md = Overrides.maps[tostring(mapId)]
  if md and md.layerOffsets then
    local elev = nil
    local Gen3 = V.require("Gen3")
    local ctx = Gen3.forMap and Gen3.forMap(map)
    if ctx and ctx.elevationAt then
      local ok, e = pcall(ctx.elevationAt, cx, cy)
      if ok then elev = e end
    end
    if elev ~= nil and type(md.layerOffsets[elev]) == "number" then
      z = z + md.layerOffsets[elev]
    end
    if type(md.layerOffsets["*"]) == "number" then
      z = z + md.layerOffsets["*"]
    end
  end
  return z
end

-- Resolve presentational texture override for one 16px cell.
-- Instance (cell.tex) wins over type (types[...].tex). Mesh/atlas only.
-- tex = { tileset, metatile } for Gen3; optional tiles={q0..q3} for Gen1/2.
function Overrides.texFor(map, cx, cy)
  if not map then return nil end
  local cell = Overrides.getCell(map.id, cx, cy)
  if cell and type(cell.tex) == "table" then return cell.tex end
  local ts = map.tileset
  local tsId = ts and (ts.id or ts.image) or "?"
  local Gen3 = V.require("Gen3")
  if Gen3.mapIsGen3 and Gen3.mapIsGen3(map) then
    local ctx = Gen3.forMap(map)
    if ctx and ctx.metatileAt then
      local ok, m = pcall(ctx.metatileAt, cx, cy)
      if ok and m ~= nil then
        local t = Overrides.types[Overrides.typeKeyMetatile(tsId, m)]
        if t and type(t.tex) == "table" then return t.tex end
      end
    end
  else
    local tx, ty = cx * 2, cy * 2 + 1
    local tile = nil
    if Gen3.tileAt then
      local ok, t = pcall(Gen3.tileAt, map, tx, ty)
      if ok then tile = t end
    end
    if tile ~= nil then
      local t = Overrides.types[Overrides.typeKeyTile(tsId, tile)]
      if t and type(t.tex) == "table" then return t.tex end
    end
  end
  return nil
end

function Overrides.spriteLift(map, actor, def)
  local lift = 0
  if not def then return 0 end
  local sheet = def.image
  if sheet then
    local s = Overrides.sprites[Overrides.spriteSheetKey(sheet)]
    if s and type(s.yOff) == "number" then lift = lift + s.yOff end
  end
  local gfx = def.graphicsId or def.id or (actor and (actor.graphicsId or actor.id))
  if gfx ~= nil then
    local s = Overrides.sprites[Overrides.spriteGfxKey(gfx)]
    if s and type(s.yOff) == "number" then lift = lift + s.yOff end
  end
  if map and actor then
    local oid = actor.id or actor.localId or actor.eventId
    if oid ~= nil then
      local s = Overrides.sprites[Overrides.spriteInstanceKey(map.id, oid)]
      if s and type(s.yOff) == "number" then lift = lift + s.yOff end
    end
  end
  return lift
end

function Overrides.chromakeysFor(path)
  local list = {}
  local function add(src)
    if type(src) ~= "table" then return end
    for _, c in ipairs(src) do list[#list + 1] = c end
  end
  add(Overrides.chromakey["*"])
  if path then add(Overrides.chromakey[tostring(path)]) end
  return list
end

function Overrides.matchesChroma(r, g, b, path)
  -- r,g,b in 0..1
  local keys = Overrides.chromakeysFor(path)
  for _, c in ipairs(keys) do
    local cr, cg, cb = c.r or 0, c.g or 0, c.b or 0
    if cr > 1 or cg > 1 or cb > 1 then
      cr, cg, cb = cr / 255, cg / 255, cb / 255
    end
    local tol = (c.tol or 8) / 255
    if math.abs(r - cr) <= tol and math.abs(g - cg) <= tol
       and math.abs(b - cb) <= tol then
      return true
    end
  end
  return false
end

function Overrides.setCell(mapId, cx, cy, patch, recordUndo)
  if recordUndo ~= false then pushUndo() end
  local k = Overrides.cellKey(mapId, cx, cy)
  local cur = Overrides.cells[k] or {}
  for field, val in pairs(patch or {}) do cur[field] = val end
  Overrides.cells[k] = cur
  Overrides.markDirty()
  return cur
end

function Overrides.setType(key, patch, recordUndo)
  if recordUndo ~= false then pushUndo() end
  local cur = Overrides.types[key] or {}
  for field, val in pairs(patch or {}) do cur[field] = val end
  Overrides.types[key] = cur
  Overrides.markDirty()
  return cur
end

function Overrides.setSprite(key, patch, recordUndo)
  if recordUndo ~= false then pushUndo() end
  local cur = Overrides.sprites[key] or {}
  for field, val in pairs(patch or {}) do cur[field] = val end
  Overrides.sprites[key] = cur
  Overrides.markDirty()
  return cur
end

function Overrides.setLayerOffset(mapId, elev, dy, recordUndo)
  if recordUndo ~= false then pushUndo() end
  local id = tostring(mapId)
  local md = Overrides.maps[id] or { layerOffsets = {} }
  md.layerOffsets = md.layerOffsets or {}
  md.layerOffsets[elev] = dy
  Overrides.maps[id] = md
  Overrides.markDirty()
end

function Overrides.addChromakey(scope, r, g, b, tol, recordUndo)
  if recordUndo ~= false then pushUndo() end
  scope = scope or "*"
  local list = Overrides.chromakey[scope] or {}
  list[#list + 1] = { r = r, g = g, b = b, tol = tol or 32 }
  Overrides.chromakey[scope] = list
  Overrides.markDirty()
  return list
end

function Overrides.removeChromakey(scope, index, recordUndo)
  if recordUndo ~= false then pushUndo() end
  scope = scope or "*"
  local list = Overrides.chromakey[scope]
  if not list then return end
  table.remove(list, index)
  if #list == 0 then Overrides.chromakey[scope] = nil end
  Overrides.markDirty()
end

function Overrides.revertSelected(kind, key, recordUndo)
  if recordUndo ~= false then pushUndo() end
  if kind == "cell" then Overrides.cells[key] = nil
  elseif kind == "type" then Overrides.types[key] = nil
  elseif kind == "sprite" then Overrides.sprites[key] = nil
  elseif kind == "chroma" then Overrides.chromakey[key] = nil
  end
  Overrides.markDirty()
end

function Overrides.undo()
  local snap = table.remove(undoStack)
  if not snap then return false end
  Overrides.cells = snap.cells or {}
  Overrides.types = snap.types or {}
  Overrides.sprites = snap.sprites or {}
  Overrides.chromakey = snap.chromakey or {}
  Overrides.maps = snap.maps or {}
  Overrides.markDirty()
  return true
end

-- ---- serialize / load / bake ----

local function esc(s)
  return tostring(s):gsub("\\", "\\\\"):gsub("\"", "\\\"")
end

local function emitValue(v, indent)
  local t = type(v)
  if t == "number" then
    if v ~= v then return "0" end
    if math.floor(v) == v then return tostring(math.floor(v)) end
    return string.format("%.4g", v)
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "string" then
    return "\"" .. esc(v) .. "\""
  elseif t == "table" then
    local parts = {}
    local n = #v
    local isArray = n > 0
    if isArray then
      for i = 1, n do
        if v[i] == nil then isArray = false break end
      end
    end
    if isArray then
      for i = 1, n do
        parts[#parts + 1] = emitValue(v[i], indent .. "  ")
      end
      return "{ " .. table.concat(parts, ", ") .. " }"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. emitValue(k, indent) .. "]"
      end
      parts[#parts + 1] = indent .. "  " .. key .. " = "
        .. emitValue(v[k], indent .. "  ") .. ","
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function Overrides.serialize()
  local body = {
    version = Overrides.version or 1,
    rev = Overrides.rev or 0,
    cells = Overrides.cells,
    types = Overrides.types,
    sprites = Overrides.sprites,
    chromakey = Overrides.chromakey,
    maps = Overrides.maps,
  }
  return "-- Shape Studio baked overrides (presentational only).\n"
    .. "-- Auto-written; safe to edit by hand. Missing file = empty.\n"
    .. "return " .. emitValue(body, "") .. "\n"
end


-- ---- mobile / merge ----

local function isMobileOs()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

local function deepMergeMap(dst, src, preferHigherRev)
  if type(src) ~= "table" then return dst end
  dst = dst or {}
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table"
       and not (v[1] ~= nil or dst[k][1] ~= nil) then
      -- nested dict (maps.layerOffsets etc.)
      local bothScalarMaps = true
      for _, vv in pairs(v) do
        if type(vv) == "table" then bothScalarMaps = false break end
      end
      if bothScalarMaps then
        dst[k] = dst[k] or {}
        for kk, vv in pairs(v) do dst[k][kk] = vv end
      else
        -- leaf override record (cell/type/sprite): later wins whole table
        dst[k] = copy(v)
      end
    else
      dst[k] = type(v) == "table" and copy(v) or v
    end
  end
  return dst
end

-- Deep-merge another overrides table into current memory.
-- Same keys: incoming wins (or preferHigherRev uses meta.rev / table.rev).
function Overrides.merge(other, opts)
  opts = opts or {}
  if type(other) ~= "table" then return false, "not a table" end
  local incomingRev = tonumber(other.rev) or 0
  local curRev = tonumber(Overrides.rev) or 0
  if opts.preferHigherRev and incomingRev < curRev then
    -- still merge cells but keep higher rev stamp
  end
  pushUndo()
  Overrides.cells = deepMergeMap(Overrides.cells, other.cells)
  Overrides.types = deepMergeMap(Overrides.types, other.types)
  Overrides.sprites = deepMergeMap(Overrides.sprites, other.sprites)
  Overrides.chromakey = deepMergeMap(Overrides.chromakey, other.chromakey)
  Overrides.maps = deepMergeMap(Overrides.maps, other.maps)
  if opts.preferHigherRev then
    Overrides.rev = math.max(curRev, incomingRev) + 1
  else
    Overrides.rev = math.max(curRev, incomingRev) + 1
  end
  if other.version then Overrides.version = other.version end
  Overrides.markDirty()
  return true, "merged rev=" .. tostring(Overrides.rev)
end

local function deviceName()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return tostring(osName or "unknown")
end

local function saveIdentityRoot()
  if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
    return nil
  end
  local ok, d = pcall(love.filesystem.getSaveDirectory)
  if ok and type(d) == "string" and d ~= "" then return d end
  return nil
end

function Overrides.serializeMobileExport()
  local meta = {
    source = isMobileOs() and "android" or "touch",
    device = deviceName(),
    rev = Overrides.rev or 0,
    game = "ruby",
    mod = "DRAMATIC_SHAPE",
    exportedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  local body = {
    version = Overrides.version or 1,
    rev = Overrides.rev or 0,
    meta = meta,
    cells = Overrides.cells,
    types = Overrides.types,
    sprites = Overrides.sprites,
    chromakey = Overrides.chromakey,
    maps = Overrides.maps,
  }
  return "-- DRAMATIC_SHAPE mobile Shape Studio export.\n"
    .. "-- Merge on Desktop via Import/Merge or tools/merge_mobile_overrides.lua\n"
    .. "return " .. emitValue(body, "") .. "\n"
end

-- Write save-dir export snapshot. Returns relative love path or nil, err.
function Overrides.exportMobile()
  if not (love and love.filesystem) then
    return nil, "no love.filesystem"
  end
  pcall(love.filesystem.createDirectory, "shape_studio")
  pcall(love.filesystem.createDirectory, "shape_studio/export")
  local stamp = os.date("%Y%m%d_%H%M%S")
  local rel = "shape_studio/export/mobile_" .. stamp .. ".lua"
  local body = Overrides.serializeMobileExport()
  local ok = pcall(love.filesystem.write, rel, body)
  if not ok then return nil, "write failed" end
  -- Also refresh live overrides in save dir
  pcall(love.filesystem.write, "shape_studio/overrides.lua", Overrides.serialize())
  pcall(love.filesystem.createDirectory, "data")
  pcall(love.filesystem.createDirectory, "data/shape_studio")
  pcall(love.filesystem.write, "data/shape_studio/overrides.lua", Overrides.serialize())
  local abs = saveIdentityRoot()
  if abs then
    return abs:gsub("\\", "/") .. "/" .. rel, rel
  end
  return rel, rel
end

local function loadTableFromString(source, label)
  if not source or source == "" then return nil, "empty" end
  local chunk, err = load(source, "@" .. tostring(label or "import"))
  if not chunk then return nil, err end
  local ok, data = pcall(chunk)
  if not ok then return nil, data end
  if type(data) ~= "table" then return nil, "not a table" end
  return data
end

local function readLove(path)
  if not (love and love.filesystem and love.filesystem.read) then return nil end
  local ok, s = pcall(love.filesystem.read, path)
  if ok and s and s ~= "" then return s end
  return nil
end

local function listExportCandidates()
  local out = {}
  if not (love and love.filesystem and love.filesystem.getDirectoryItems) then
    return out
  end
  local ok, items = pcall(love.filesystem.getDirectoryItems, "shape_studio/export")
  if not ok or type(items) ~= "table" then return out end
  for _, name in ipairs(items) do
    if type(name) == "string" and name:match("%.lua$") then
      out[#out + 1] = "shape_studio/export/" .. name
    end
  end
  table.sort(out)
  return out
end

-- pathOrString: absolute/io path, love save relative path, raw lua source,
-- or nil to merge the newest shape_studio/export/*.lua in save dir.
function Overrides.importMerge(pathOrString)
  local source, label = nil, nil
  if type(pathOrString) == "string" and pathOrString:match("return%s*{") then
    source, label = pathOrString, "inline"
  elseif type(pathOrString) == "string" and pathOrString ~= "" then
    label = pathOrString
    -- love relative?
    source = readLove(pathOrString)
    if not source then
      -- picked_rom-style: basename under save dir
      local base = pathOrString:match("([^/\\]+)$")
      if base then source = readLove(base) or readLove("shape_studio/export/" .. base) end
    end
    if not source then
      local function ioRead(p)
        local f = io.open(p, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close(); return s
      end
      source = ioRead(pathOrString) or ioRead(pathOrString:gsub("/", "\\"))
    end
  else
    local cands = listExportCandidates()
    if #cands == 0 then return false, "no export files in shape_studio/export" end
    label = cands[#cands]
    source = readLove(label)
  end
  local data, err = loadTableFromString(source, label)
  if not data then return false, err end
  local ok, note = Overrides.merge(data, { preferHigherRev = true })
  if ok then
    Overrides.flushPersist()
    Overrides.refreshGeometry(nil)
  end
  return ok, tostring(note) .. " from " .. tostring(label)
end


local function applyLoaded(data)
  if type(data) ~= "table" then return end
  Overrides.version = data.version or 1
  Overrides.rev = data.rev or 0
  Overrides.cells = data.cells or {}
  Overrides.types = data.types or {}
  Overrides.sprites = data.sprites or {}
  Overrides.chromakey = data.chromakey or {}
  Overrides.maps = data.maps or {}
  dirty = false
end

-- V.path from the loader is usually relative ("mods/DRAMATIC_SHAPE"),
-- not an absolute Desktop folder. Relative io.open follows LOVE's CWD and
-- silently fails; love.filesystem then writes only to AppData. Resolve the
-- absolute gen1recomp-dev mod folder via getSource() so bake hits the same
-- tree mod.read loads on boot.
local function modRootCandidates()
  local roots = {}
  local seen = {}
  local function add(p)
    if type(p) ~= "string" or p == "" then return end
    if seen[p] then return end
    seen[p] = true
    roots[#roots + 1] = p
  end
  local rel = nil
  if V.mod and type(V.mod.path) == "string" and V.mod.path ~= "" then
    rel = V.mod.path
  elseif type(V.path) == "string" and V.path ~= "" then
    rel = V.path
  end
  local src = nil
  if love and love.filesystem and love.filesystem.getSource then
    local ok, s = pcall(love.filesystem.getSource)
    if ok and type(s) == "string" and s ~= "" then src = s end
  end
  local function isAbs(p)
    return p:match("^%a:[/\\]") ~= nil or p:sub(1, 1) == "/"
  end
  if rel then
    if isAbs(rel) then
      add(rel)
      add(rel:gsub("/", "\\"))
    else
      if src then
        add(src .. "/" .. rel)
        add((src .. "/" .. rel):gsub("/", "\\"))
        add(src:gsub("/", "\\") .. "\\" .. rel:gsub("/", "\\"))
      end
      add(rel)
      add(rel:gsub("/", "\\"))
    end
  elseif src then
    add(src)
    add(src:gsub("/", "\\"))
  end
  return roots
end

local function overridesRelPath()
  return "data/shape_studio/overrides.lua"
end

local function readTextFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("*a")
  f:close()
  return s
end

function Overrides.load()
  local mod = V.mod
  local source = nil
  local from = nil
  -- Prefer the absolute Desktop mod file first (same path bake writes),
  -- then PhysFS mod.read, then love.filesystem save-dir copy.
  for _, root in ipairs(modRootCandidates()) do
    local path = root:gsub("\\", "/") .. "/" .. overridesRelPath()
    local s = readTextFile(path)
    if (not s or s == "") then
      s = readTextFile(path:gsub("/", "\\"))
    end
    if s and s ~= "" then
      source = s
      from = path
      break
    end
  end
  if (not source or source == "") and mod and type(mod.read) == "function" then
    local ok, s = pcall(mod.read, mod, overridesRelPath())
    if ok and s and s ~= "" then
      source = s
      from = "mod.read"
    end
  end
  if (not source or source == "") and love and love.filesystem and love.filesystem.read then
    local ok, s = pcall(love.filesystem.read, overridesRelPath())
    if ok and s and s ~= "" then
      source = s
      from = "love.filesystem"
    end
  end
  if not source or source == "" then
    applyLoaded({})
    from = "empty"
  else
    local chunk, err = load(source, "@data/shape_studio/overrides.lua")
    if not chunk then
      applyLoaded({})
      return false, err
    end
    local ok, data = pcall(chunk)
    if not ok then
      applyLoaded({})
      return false, data
    end
    applyLoaded(data)
  end
  -- Always layer LOVE save-dir overrides on top (Android edits live here).
  do
    local function tryMergeLove(rel)
      if not (love and love.filesystem and love.filesystem.read) then return end
      local ok, s = pcall(love.filesystem.read, rel)
      if not (ok and s and s ~= "") then return end
      local chunk = load(s, "@" .. rel)
      if not chunk then return end
      local ok2, extra = pcall(chunk)
      if not ok2 or type(extra) ~= "table" then return end
      -- Merge without undo / dirty: boot compose.
      local function layer(dst, src)
        if type(src) ~= "table" then return dst or {} end
        dst = dst or {}
        for k, v in pairs(src) do
          dst[k] = type(v) == "table" and copy(v) or v
        end
        return dst
      end
      Overrides.cells = layer(Overrides.cells, extra.cells)
      Overrides.types = layer(Overrides.types, extra.types)
      Overrides.sprites = layer(Overrides.sprites, extra.sprites)
      Overrides.chromakey = layer(Overrides.chromakey, extra.chromakey)
      Overrides.maps = layer(Overrides.maps, extra.maps)
      if type(extra.rev) == "number" then
        Overrides.rev = math.max(Overrides.rev or 0, extra.rev)
      end
      dirty = false
      from = tostring(from) .. "+save:" .. rel
    end
    -- Prefer shape_studio/ (mobile canonical), then data/shape_studio/
    if from ~= "love.filesystem" then
      tryMergeLove("shape_studio/overrides.lua")
      tryMergeLove("data/shape_studio/overrides.lua")
    else
      -- Primary load already was love path; still try the other alias.
      tryMergeLove("shape_studio/overrides.lua")
    end
  end
  return true, from
end

local function writeText(path, body)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  local okw, werr = pcall(function() f:write(body) end)
  f:close()
  if not okw then return false, werr end
  return true
end

local function ensureDir(dir)
  local win = dir:gsub("/", "\\")
  pcall(os.execute, 'mkdir "' .. win .. '" 2>nul')
  pcall(os.execute, 'mkdir -p "' .. dir:gsub("\\", "/") .. '" 2>/dev/null')
end

local function writeLastBakeNote(root, path, ok, err)
  if not root then return end
  local notePath = (root:gsub("\\", "/") .. "/data/shape_studio/last_bake.txt")
  local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local line = string.format("%s ok=%s path=%s err=%s\n",
    stamp, tostring(ok), tostring(path), tostring(err or ""))
  local alt = notePath:gsub("/", "\\")
  if not writeText(notePath, line) then
    writeText(alt, line)
  end
end

function Overrides.bake()
  local body = Overrides.serialize()
  local notes = {}
  local okLove = false
  if love and love.filesystem then
    pcall(love.filesystem.createDirectory, "data")
    pcall(love.filesystem.createDirectory, "data/shape_studio")
    pcall(love.filesystem.createDirectory, "shape_studio")
    local ok = pcall(love.filesystem.write, "data/shape_studio/overrides.lua", body)
    pcall(love.filesystem.write, "shape_studio/overrides.lua", body)
    okLove = ok and true or false
    notes[#notes + 1] = okLove and "love.filesystem ok" or "love.filesystem failed"
  end

  local okDisk = false
  local diskPath = nil
  local diskErr = nil
  local usedRoot = nil
  local roots = modRootCandidates()
  for _, root in ipairs(roots) do
    local dir = root:gsub("\\", "/") .. "/data/shape_studio"
    local path = dir .. "/overrides.lua"
    ensureDir(dir)
    local ok, err = writeText(path, body)
    if not ok then
      local pathWin = path:gsub("/", "\\")
      ok, err = writeText(pathWin, body)
      if ok then path = pathWin end
    end
    if ok then
      okDisk = true
      diskPath = path
      usedRoot = root
      break
    else
      diskErr = tostring(err) .. " @ " .. path
    end
  end
  if okDisk then
    notes[#notes + 1] = "disk:" .. tostring(diskPath)
    writeLastBakeNote(usedRoot, diskPath, true, nil)
  else
    notes[#notes + 1] = "disk FAILED: " .. tostring(diskErr or "no mod root")
    if roots[1] then
      writeLastBakeNote(roots[1], diskPath, false, diskErr)
    end
  end

  -- Desktop: require mod-folder write when a root exists (Play-Developer).
  -- Android/iOS: love.filesystem save-dir is the source of truth.
  local mobile = false
  do
    local osName = love and love.system and love.system.getOS and love.system.getOS()
    mobile = (osName == "Android" or osName == "iOS")
  end
  if okDisk then
    dirty = false
    persistDue = nil
  elseif okLove and (#roots == 0 or mobile) then
    dirty = false
    persistDue = nil
  end

  -- Mobile export snapshots are explicit (Export button / exportMobile),
  -- not every autosave — avoids flooding shape_studio/export/.

  if okDisk or okLove then
    pcall(function()
      local ChunkMesher = V.require("ChunkMesher")
      if ChunkMesher.setCacheRulesTag then
        ChunkMesher.setCacheRulesTag(Overrides.signature())
      end
    end)
    pcall(function()
      local DiskCache = V.require("VoxelDiskCache")
      if DiskCache.setRulesTag then DiskCache.setRulesTag(Overrides.signature()) end
    end)
  end
  local mobile = false
  do
    local osName = love and love.system and love.system.getOS and love.system.getOS()
    mobile = (osName == "Android" or osName == "iOS")
  end
  local ok = okDisk or ((#roots == 0 or mobile) and okLove)
  if mobile and okLove then
    notes[#notes + 1] = "mobile-save-dir"
    local sd = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory()
    if sd then notes[#notes + 1] = "saveDir:" .. tostring(sd) end
  end
  return ok, table.concat(notes, "; ")
end

-- Soft path: height / shape / zOff / class / art / tex cell edits.
-- Stale meshes keep drawing while replacements cook. NEVER bumps the
-- global rules tag; NEVER wipes ImageCache / Gen3Sheets / billboards.
function Overrides.refreshGeometry(mapId)
  pcall(function()
    local TileShape = V.require("TileShape")
    TileShape.invalidate()
  end)
  pcall(function()
    local ChunkMesher = V.require("ChunkMesher")
    if ChunkMesher.refresh then
      ChunkMesher.refresh(mapId)
    else
      ChunkMesher.invalidate(mapId)
    end
  end)
end

-- Heavy path: chromakey / bake / sheet texture changes.
-- opts.bumpRules (default true), opts.textures (default true).
-- Prefer refresh over invalidate when meshes exist (refresh handles nil).
function Overrides.invalidateMeshes(mapId, opts)
  opts = opts or {}
  local bumpRules = opts.bumpRules ~= false
  local textures = opts.textures ~= false
  pcall(function()
    local TileShape = V.require("TileShape")
    TileShape.invalidate()
  end)
  pcall(function()
    local ChunkMesher = V.require("ChunkMesher")
    if bumpRules and ChunkMesher.setCacheRulesTag then
      ChunkMesher.setCacheRulesTag(Overrides.signature())
    end
    if ChunkMesher.refresh then
      ChunkMesher.refresh(mapId)
    else
      ChunkMesher.invalidate(mapId)
    end
  end)
  if textures then
    pcall(function()
      local ImageCache = V.require("ImageCache")
      ImageCache.invalidate()
    end)
    pcall(function()
      local ok, Gen3Sheets = pcall(require, "src.render.Gen3Sheets")
      if ok and Gen3Sheets and Gen3Sheets.invalidate then Gen3Sheets.invalidate() end
    end)
    -- Gen3.atlasCache holds the composited tile sheet the mesher UVs;
    -- TerrainAtlas caches the Image wrapper. Both must die or chromakey
    -- samples never reach the fence gaps on screen.
    pcall(function()
      local Gen3 = V.require("Gen3")
      if Gen3.releaseAtlases then Gen3.releaseAtlases()
      elseif Gen3.invalidate then Gen3.invalidate() end
    end)
    pcall(function()
      local TerrainAtlas = V.require("TerrainAtlas")
      if TerrainAtlas.invalidate then TerrainAtlas.invalidate() end
    end)
    pcall(function()
      local SpriteBillboards = V.require("SpriteBillboards")
      if SpriteBillboards.invalidate then SpriteBillboards.invalidate() end
    end)
  end
end

pcall(Overrides.load)

return Overrides
