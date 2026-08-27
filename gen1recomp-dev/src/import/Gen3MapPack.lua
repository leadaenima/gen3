-- Ruby map cache. Phase 81 baked full script IR into every map, so a single
-- `maps.lua` `return { maps = { ... } }` chunk exceeds LuaJIT's 65536-constant
-- limit and CacheFs.loadActive returns nil. Game3:load then sees `{}`, spawn
-- and CONTINUE cannot enterMap, and drawScene falls through to the species
-- list. Maps are stored one file per id (`data/generated/maps/g0_9.lua`) with
-- a small index at `data/generated/maps.lua`. An oversized legacy file is
-- split on first load so a re-import is not required.

local Gen3MapPack = {}

local MAPS_INDEX = "data/generated/maps.lua"
local MAPS_DIR = "data/generated/maps/"

local function loader()
  return loadstring or load
end

-- Scan LuaWriter output: double-quoted strings, `{` / `}` elsewhere.
-- Byte-at-a-time so a 15 MB file does not allocate per character.
local function matchBrace(src, open)
  local n = #src
  local depth = 0
  local i = open
  while i <= n do
    local b = src:byte(i)
    if b == 34 then
      i = i + 1
      while i <= n do
        local d = src:byte(i)
        if d == 92 then
          i = i + 2
        elseif d == 34 then
          i = i + 1
          break
        else
          i = i + 1
        end
      end
    elseif b == 123 then
      depth = depth + 1
      i = i + 1
    elseif b == 125 then
      depth = depth - 1
      i = i + 1
      if depth == 0 then return i end
    else
      i = i + 1
    end
  end
end

local function mapsTableSpan(src)
  local at = src:find("\n  maps = {", 1, true)
  if not at then return nil end
  local open = at + #"\n  maps = {" - 1
  local close = matchBrace(src, open)
  if not close then return nil end
  return open, close
end

function Gen3MapPack.indexFromPack(pack)
  pack = pack or {}
  local ids = {}
  if type(pack.maps) == "table" then
    for id in pairs(pack.maps) do ids[#ids + 1] = id end
    table.sort(ids)
  end
  local index = { ids = ids }
  for k, v in pairs(pack) do
    if k ~= "maps" and k ~= "tilesets" and k ~= "ids" then
      index[k] = v
    end
  end
  return index, pack.maps or {}
end

function Gen3MapPack.split(src)
  if type(src) ~= "string" or src == "" then return nil end
  local open, close = mapsTableSpan(src)
  if not open then return nil end
  local slim = src:sub(1, open - 1) .. "{}" .. src:sub(close)
  local chunk, err = loader()(slim, "@maps-index")
  if not chunk then return nil, err end
  local ok, index = pcall(chunk)
  if not ok or type(index) ~= "table" then return nil, index end
  local maps = {}
  local ids = {}
  local pos = open
  while pos < close do
    local s, e, id = src:find("\n    (g%d+_%d+) = {", pos)
    if not s or s >= close then break end
    local mapClose = matchBrace(src, e)
    if not mapClose then break end
    local body = src:sub(e, mapClose - 1)
    local fn, loadErr = loader()("return " .. body, "@" .. id)
    if fn then
      local loaded, value = pcall(fn)
      if loaded and type(value) == "table" then
        maps[id] = value
        ids[#ids + 1] = id
      end
    else
      return nil, loadErr
    end
    pos = mapClose
  end
  table.sort(ids)
  index.ids = ids
  index.maps = maps
  return index
end

local function withVersionPrefix(fn)
  local CacheFs = require("src.import.CacheFs")
  local GameVersion = require("src.core.GameVersion")
  local saved = CacheFs.prefix
  local prefix = GameVersion.cachePrefix()
  if prefix and prefix ~= "" then CacheFs.prefix = prefix end
  local ok, a, b = pcall(fn, CacheFs)
  CacheFs.prefix = saved
  if not ok then return nil, a end
  return a, b
end

function Gen3MapPack.writeActive(rel, bytes)
  return withVersionPrefix(function(CacheFs)
    return CacheFs.write(rel, bytes)
  end)
end

function Gen3MapPack.attachMaps(index)
  if type(index) ~= "table" then return index end
  index.maps = type(index.maps) == "table" and index.maps or {}
  local ids = index.ids
  if type(ids) ~= "table" then return index end
  local CacheFs = require("src.import.CacheFs")
  for i = 1, #ids do
    local id = ids[i]
    if id and not index.maps[id] then
      local map = CacheFs.loadActive(MAPS_DIR .. id .. ".lua")
      if type(map) == "table" then index.maps[id] = map end
    end
  end
  return index
end

function Gen3MapPack.persist(pack)
  if type(pack) ~= "table" or type(pack.maps) ~= "table" then return false end
  local LuaWriter = require("src.import.LuaWriter")
  local index, maps = Gen3MapPack.indexFromPack(pack)
  if #index.ids == 0 then return false end
  if pack.mapCount and #index.ids ~= pack.mapCount then return false end
  for i = 1, #index.ids do
    local id = index.ids[i]
    local ok = Gen3MapPack.writeActive(MAPS_DIR .. id .. ".lua",
      LuaWriter.encode(maps[id]))
    if not ok then return false end
  end
  return Gen3MapPack.writeActive(MAPS_INDEX, LuaWriter.encode(index)) and true
end

function Gen3MapPack.hasMaps(pack)
  return type(pack) == "table" and type(pack.maps) == "table" and next(pack.maps) ~= nil
end

function Gen3MapPack.load()
  local CacheFs = require("src.import.CacheFs")
  local index = CacheFs.loadActive(MAPS_INDEX)
  if type(index) == "table" then
    if Gen3MapPack.hasMaps(index) then return index end
    if type(index.ids) == "table" and #index.ids > 0 then
      return Gen3MapPack.attachMaps(index)
    end
  end
  local bytes = CacheFs.readActive(MAPS_INDEX)
  if type(bytes) ~= "string" then return index or {} end
  local pack = Gen3MapPack.split(bytes)
  if not Gen3MapPack.hasMaps(pack) then return index or pack or {} end
  pcall(Gen3MapPack.persist, pack)
  return pack
end

return Gen3MapPack
