-- HostRuntime — one generation/edition authority for Gen1Recomp + Gen2Recomped.
--
-- Engine modules are resolved at CALL time. Gen2Recomped can install edition-
-- specific proxies during boot; caching GameVersion at file scope can therefore
-- freeze the Red implementation before Gold/Silver/Crystal has finished loading.
local V = ...

local Host = {}

local SUPPORTED = {
  red = 1, blue = 1, yellow = 1,
  gold = 2, silver = 2, crystal = 2,
}

local function gameVersion()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and type(GV) == "table" then return GV end
  return nil
end

local function normalize(id)
  if type(id) ~= "string" then return nil end
  id = id:lower():gsub("pokemon%s*", ""):gsub("[^%w]", "")
  if id == "red" or id == "blue" or id == "yellow"
      or id == "gold" or id == "silver" or id == "crystal" then
    return id
  end
  return nil
end

function Host.versionId()
  local GV = gameVersion()
  if GV then
    local id
    if type(GV.get) == "function" then
      local ok, value = pcall(GV.get)
      if ok then id = normalize(value) end
    end
    if not id then id = normalize(GV.current) end
    if id then return id end
  end

  -- Fallback only for engine variants that do not expose GameVersion yet.
  local mod = V and V.mod
  local candidates = {
    mod and mod.game and mod.game.version,
    mod and mod.game and mod.game.id,
    mod and mod.context and mod.context.version,
  }
  for _, value in ipairs(candidates) do
    local id = normalize(value)
    if id then return id end
  end
  return nil
end

function Host.generation()
  local GV = gameVersion()
  if GV and type(GV.generation) == "function" then
    local ok, value = pcall(GV.generation)
    if ok and tonumber(value) then return tonumber(value) end
  end
  local id = Host.versionId()
  return SUPPORTED[id] or 1
end

function Host.isGen1() return Host.generation() == 1 end
function Host.isGen2() return Host.generation() == 2 end

function Host.supportsEdition(id)
  id = normalize(id)
  return id ~= nil and SUPPORTED[id] ~= nil
end

function Host.supportedEditions()
  return { "red", "blue", "yellow", "gold", "silver", "crystal" }
end

-- Gen2Recomped has a native Gen-2 Weather module. Its battle field uses
-- RAIN/SUN/SANDSTORM/HAIL and already owns the cartridge-accurate modifiers,
-- upkeep, Thunder/Solar Beam interactions, etc. Weather FX must draw those
-- conditions, but must not multiply their mechanics a second time.
function Host.nativeGen2BattleWeather()
  if not Host.isGen2() then return false end
  local ok, W = pcall(require, "src.battle.Weather")
  return ok and type(W) == "table"
      and type(W.current) == "function"
      and type(W.applyModifier) == "function"
end

return Host
