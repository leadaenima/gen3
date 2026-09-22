-- Typed weather coverage: every Gen-1 damage type has a weather that can
-- carry its 1/16 residual effect.
local function assert_(v, msg)
  if not v then error(msg or "assertion failed", 2) end
end

local chunk = assert(loadfile("lib/Types.lua"))
local Types = chunk({})

local gen1 = {
  "NORMAL","FIRE","WATER","ELECTRIC","GRASS","ICE","FIGHTING","POISON",
  "GROUND","FLYING","PSYCHIC","BUG","ROCK","GHOST","DRAGON",
}

local seen = {}
for _, def in ipairs(Types.list) do
  if def.chipType then
    seen[def.chipType] = true
    assert_(type(def.battle) == "string", def.id .. " needs a battle weather id")
    local hasVisual = false
    for _, v in pairs(def.ch or {}) do
      if type(v) == "number" and v > 0 then hasVisual = true break end
    end
    assert_(hasVisual, def.id .. " needs an overworld/battle visual recipe")
  end
end

for _, t in ipairs(gen1) do
  assert_(seen[t], "missing typed weather for Gen-1 type " .. t)
end

assert_(Types.get("STORM").chipType == "ELECTRIC", "STORM must be Electric weather")
assert_(Types.get("SMOG").chipType == "POISON", "SMOG must be Poison weather")
assert_(Types.get("DUSTSTORM").chipType == "GROUND", "DUSTSTORM must be Ground weather")
assert_(Types.get("DRAGONSTORM").chipType == "DRAGON", "DRAGONSTORM must be Dragon weather")
assert_(Types.get("PLAIN_FRONT").chipType == "NORMAL", "PLAIN_FRONT must be Normal weather")

return true
