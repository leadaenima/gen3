-- Release smoke: the config shipped in the archive must be accepted by the
-- same strict loader the mod uses, including variable-length encounter bans.
local function fail(msg) error(msg or "release config test failed", 2) end
local function eq(a, b, msg) if a ~= b then fail((msg or "mismatch") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")") end end

local Types = assert(loadfile("lib/Types.lua"))({})
local warnings = {}
local mod = {
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
  end,
  log = {
    warn = function(_, fmt, ...) warnings[#warnings + 1] = string.format(fmt, ...) end,
    info = function() end,
  },
}
local V = { mod = mod }
function V.require(name)
  if name == "Types" then return Types end
  fail("unexpected module " .. tostring(name))
end

local Config = assert(loadfile("lib/Config.lua"))(V)
local cfg = Config.load()
eq(#Config.problems, 0, "shipped config.lua must load clean")
eq(cfg.legendary.rateBoost, 1.05, "legendary.rateBoost survives validation")
eq(cfg.quality, "auto", "default quality")
if type(cfg.encounters.bans) ~= "table" then fail("encounters.bans must survive validation") end
if type(cfg.encounters.bans.wet) ~= "table" or cfg.encounters.bans.wet[1] ~= "FIRE" then
  fail("encounters.bans.wet must survive validation")
end
if type(cfg.encounters.bansById) ~= "table" then fail("encounters.bansById must survive validation") end

-- Literal false is a documented escape hatch and used to be rejected by the
-- strict shape merge. Drive it through the same loader.
mod.read = function(_, rel)
  if rel == "config.lua" then return "return { encounters = { bans = false } }" end
  return nil
end
cfg = Config.load()
eq(#Config.problems, 0, "encounters.bans=false must be valid")
eq(cfg.encounters.bans, false, "encounter bans can be disabled")

print("release config: PASS")
return true
