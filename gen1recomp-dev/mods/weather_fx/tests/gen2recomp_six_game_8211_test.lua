-- Weather FX 8.2.11: explicit Gen1Recomp + Gen2Recomped six-edition contract.
local passed, failed = 0, 0
local function check(ok, name)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name) end
end

local current = "red"
local generation = { red=1, blue=1, yellow=1, gold=2, silver=2, crystal=2 }
package.loaded["src.core.GameVersion"] = {
  get = function() return current end,
  generation = function(id) return generation[id or current] or 1 end,
}
package.loaded["src.battle.Weather"] = {
  current = function() return nil end,
  applyModifier = function(d) return d end,
}

local H = assert(loadfile("lib/HostRuntime.lua"))({ mod = {} })
local order = { "red", "blue", "yellow", "gold", "silver", "crystal" }
for _, id in ipairs(order) do
  current = id
  local gen = generation[id]
  check(H.versionId() == id, id .. " version id")
  check(H.generation() == gen, id .. " generation")
  check(H.supportsEdition(id), id .. " supported")
  check(H.isGen1() == (gen == 1), id .. " gen1 predicate")
  check(H.isGen2() == (gen == 2), id .. " gen2 predicate")
  check(H.nativeGen2BattleWeather() == (gen == 2), id .. " native battle-weather ownership")
end
check(not H.supportsEdition("prism"), "six-edition support boundary excludes unqualified hacks")

local T = assert(loadfile("lib/Types.lua"))()
check(T.forBattleWeather("RAIN") ~= nil, "native Gen2 RAIN has Weather FX visual")
check(T.forBattleWeather("SUN") ~= nil, "native Gen2 SUN has Weather FX visual")
check(T.forBattleWeather("SANDSTORM") ~= nil, "native Gen2 SANDSTORM has Weather FX visual")
check(T.forBattleWeather("HAIL") ~= nil, "native HAIL visual alias remains safe")

print(("gen2recomp six-game 8.2.11: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
