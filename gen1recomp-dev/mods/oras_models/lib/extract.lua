-- Probe / describe the user-owned ORAS dump and any local extract cache.
-- Runs inside the mod sandbox: no host io. Status comes from a gitignored
-- marker the companion extract script writes to .local/status.json (and the
-- same payload under %APPDATA%/LOVE/pokemon-love2d/oras_extract/).
--
-- Status.texture_index embeds only the first 500 rows. The FULL index lives
-- at texture_index_path (cache) and is mirrored to .local/texture_index.json
-- so mod:read can load it. A slim battle_texture_map.json is preferred for
-- apply speed.
local M = {}

M.DEFAULT_SOURCE =
  [[C:\Users\Feces\Desktop\Pokemon Omega Ruby (USA) (En,Ja,Fr,De,Es,It,Ko) (Rev 2) Decrypted.zip]]

M.CACHE_REL = "oras_extract"
M.STATUS_MOD_PATH = ".local/status.json"
M.TEXTURE_INDEX_MOD_PATH = ".local/texture_index.json"
M.BATTLE_MAP_MOD_PATH = ".local/battle_texture_map.json"
M.MESH_INDEX_MOD_PATH = ".local/mesh_index.json"

local function decodeJson(text)
  if type(text) ~= "string" or text == "" then return nil end
  -- Engine JSON (sandbox-safe require). Prefer this over dkjson.
  local ok, Json = pcall(require, "src.link.Json")
  if ok and Json and Json.decode then
    local obj = Json.decode(text)
    if type(obj) == "table" then return obj end
  end
  local ok2, dkjson = pcall(require, "dkjson")
  if ok2 and dkjson and dkjson.decode then
    local obj = dkjson.decode(text)
    if type(obj) == "table" then return obj end
  end
  -- Minimal key extractors for the fields we care about (status files we write).
  local function str(key)
    return text:match('"' .. key .. '"%s*:%s*"([^"]*)"')
  end
  local function bool(key)
    local v = text:match('"' .. key .. '"%s*:%s*(true|false)')
    if v == "true" then return true end
    if v == "false" then return false end
    return nil
  end
  local function num(key)
    local v = text:match('"' .. key .. '"%s*:%s*(-?%d+)')
    return v and tonumber(v) or nil
  end
  return {
    ok = bool("ok") == true,
    kind = str("kind"),
    message = str("message"),
    source = str("source"),
    cache_dir = str("cache_dir"),
    entry_count = num("entry_count"),
    texture_count = num("texture_count"),
    model_count = num("model_count"),
    texture_index_path = str("texture_index_path"),
    texture_index_total = num("texture_index_total"),
    needs_ctrtool = bool("needs_ctrtool") == true,
    probed_at = str("probed_at"),
  }
end

local function readModFile(mod, rel)
  if not (mod and mod.read) then return nil end
  local ok, data = pcall(function() return mod:read(rel) end)
  if ok and type(data) == "string" and data ~= "" then return data end
  return nil
end

function M.readStatus(mod)
  local raw = readModFile(mod, M.STATUS_MOD_PATH)
  if not raw then
    return {
      ok = false,
      kind = "missing",
      message = "no extract status yet -- run extract/extract_oras.py",
      needs_ctrtool = true,
    }
  end
  local status = decodeJson(raw)
  if type(status) ~= "table" then
    return {
      ok = false,
      kind = "corrupt",
      message = "could not parse .local/status.json",
      needs_ctrtool = true,
    }
  end
  return status
end

-- Full texture list: prefer .local mirror of texture_index.json (sandbox-safe).
-- Falls back to the 500-row status.texture_index embed only as a last resort.
function M.loadTextureList(mod, status)
  local raw = readModFile(mod, M.TEXTURE_INDEX_MOD_PATH)
  if raw then
    local obj = decodeJson(raw)
    if type(obj) == "table" then
      if type(obj.textures) == "table" then return obj.textures end
      -- allow a bare array
      if #obj > 0 and type(obj[1]) == "table" then return obj end
    end
  end
  local embed = status and status.texture_index
  if type(embed) == "table" then return embed end
  return {}
end

function M.readBattleMap(mod)
  local raw = readModFile(mod, M.BATTLE_MAP_MOD_PATH)
  if not raw then return nil end
  local obj = decodeJson(raw)
  if type(obj) == "table" then return obj end
  return nil
end

function M.describeSourceHint(path)
  path = tostring(path or "")
  local lower = path:lower()
  if lower:match("%.zip$") then
    return "zip (may wrap a decrypted .3ds / CIA / RomFS tree; Deflate64 needs 7-Zip)"
  end
  if lower:match("%.3ds$") or lower:match("%.cci$") then
    return "decrypted NCSD (.3ds) -- needs ctrtool (or 3dstool) to pull ExeFS/RomFS"
  end
  if lower:match("%.cxi$") or lower:match("%.app$") then
    return "NCCH/CXI -- needs ctrtool to extract RomFS"
  end
  if lower:match("%.cia$") then
    return "CIA -- needs ctrtool to unpack content NCCH then RomFS"
  end
  return "unknown container -- probe with extract/extract_oras.py"
end

function M.readMeshIndex(mod)
  local raw = readModFile(mod, M.MESH_INDEX_MOD_PATH)
  if not raw then return nil end
  local obj = decodeJson(raw)
  if type(obj) == "table" then return obj end
  return nil
end

function M.readyForTextures(status)
  return type(status) == "table"
    and status.ok == true
    and (tonumber(status.texture_count) or 0) > 0
end

function M.readyForModels(status)
  return type(status) == "table"
    and status.ok == true
    and (tonumber(status.model_count) or 0) > 0
end

return M
