#!/usr/bin/env lua
-- Deep-merge a mobile Shape Studio export into Desktop overrides.lua.
-- Usage:
--   lua merge_mobile_overrides.lua [path/to/mobile_YYYYMMDD_HHMMSS.lua]
-- Default target: ../data/shape_studio/overrides.lua (relative to this script)

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return src:match("^(.*[/\\])") or "./"
end

local root = scriptDir() .. "../"
local target = root .. "data/shape_studio/overrides.lua"
local srcPath = arg[1]

local function readAll(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("*a"); f:close(); return s
end

local function writeAll(path, body)
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(body); f:close(); return true
end

local function loadTable(path)
  local s, err = readAll(path)
  if not s then return nil, err end
  local chunk, e2 = load(s, "@" .. path)
  if not chunk then return nil, e2 end
  local ok, data = pcall(chunk)
  if not ok then return nil, data end
  if type(data) ~= "table" then return nil, "not a table" end
  return data
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do
    o[k] = type(v) == "table" and copy(v) or v
  end
  return o
end

local function layer(dst, src)
  dst = dst or {}
  if type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and v[1] == nil and dst[k][1] == nil then
      -- field-merge leaf records and nested maps
      local nested = false
      for _, vv in pairs(v) do if type(vv) == "table" then nested = true break end end
      if nested and (v.class ~= nil or v.h ~= nil or v.art ~= nil or v.zOff ~= nil or v.tex ~= nil or v.yOff ~= nil) then
        dst[k] = copy(v)  -- cell/type/sprite record: replace
      else
        dst[k] = layer(dst[k], v)
      end
    else
      dst[k] = type(v) == "table" and copy(v) or v
    end
  end
  return dst
end

-- Minimal serializer (matches ShapeOverrides style enough for round-trip)
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
      for i = 1, n do if v[i] == nil then isArray = false break end end
    end
    if isArray then
      for i = 1, n do parts[#parts + 1] = emitValue(v[i], indent .. "  ") end
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

if not srcPath or srcPath == "" then
  io.stderr:write("Usage: lua merge_mobile_overrides.lua <mobile_export.lua>\n")
  os.exit(1)
end

local incoming, err = loadTable(srcPath)
if not incoming then
  io.stderr:write("Cannot load export: " .. tostring(err) .. "\n")
  os.exit(1)
end

local base = loadTable(target)
if not base then
  base = { version = 1, rev = 0, cells = {}, types = {}, sprites = {}, chromakey = {}, maps = {} }
end

base.cells = layer(base.cells or {}, incoming.cells)
base.types = layer(base.types or {}, incoming.types)
base.sprites = layer(base.sprites or {}, incoming.sprites)
base.chromakey = layer(base.chromakey or {}, incoming.chromakey)
base.maps = layer(base.maps or {}, incoming.maps)
base.rev = math.max(tonumber(base.rev) or 0, tonumber(incoming.rev) or 0) + 1
base.version = incoming.version or base.version or 1

local body = "-- Shape Studio baked overrides (presentational only).\n"
  .. "-- Merged mobile export: " .. tostring(srcPath) .. "\n"
  .. "return " .. emitValue(base, "") .. "\n"

local ok, werr = writeAll(target, body)
if not ok then
  io.stderr:write("Write failed: " .. tostring(werr) .. "\n")
  os.exit(1)
end

print("Merged into " .. target .. " (rev=" .. tostring(base.rev) .. ")")