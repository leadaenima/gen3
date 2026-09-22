-- Emerald ModGens gate: unstated generations ⇒ allowed on gen3 (Ruby/Emerald).
-- free_fly / weather_fx / johto_radar ship games=["gen1","gen2"] with NO
-- generations field; Emerald loads them on gen3. Ruby must match.
package.path = "./?.lua;./?/init.lua;" .. package.path

local ModGens = require("src.mods.ModGens")

local pass, fail = 0, 0
local function check(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") end
end

-- --- ModGens.allows / permits (Emerald semantics) ---
check(ModGens.allows({}, 3) == true,
  "unstated generations allows gen3")
check(ModGens.allows({ generations = nil }, 3) == true,
  "nil generations allows gen3")
check(ModGens.allows({ generations = { 1, 2 } }, 3) == false,
  "generations [1,2] refuses gen3")
check(ModGens.allows({ generations = { 1, 2 } }, 2) == true,
  "generations [1,2] allows gen2")
check(ModGens.allows({ generations = { 3 } }, 3) == true,
  "generations [3] allows gen3")

local ok, why = ModGens.permits({ -- free_fly shape: no generations
}, nil, 3)
check(ok == true and why == "declared",
  "free_fly-shaped manifest permits gen3 as declared")

ok, why = ModGens.permits({ generations = { 1, 2 } }, nil, 3)
check(ok == false and why == "unsupported",
  "explicit [1,2] unsupported on gen3 without force")

local forced = ModGens.withForced(true, 3, true)
ok, why = ModGens.permits({ generations = { 1, 2 } }, forced, 3)
check(ok == true and why == "forced",
  "ModGens force chip permits [1,2] on gen3")

-- free_fly real manifest fragment
local free_fly = {
  id = "free_fly",
  games = { "gen1", "gen2" },
  -- no generations
}
ok, why = ModGens.permits(free_fly, nil, 3)
check(ok == true and why == "declared",
  "real free_fly.manifest permits Ruby/Emerald gen3")

local weather = { id = "weather_fx", games = { "gen1", "gen2" } }
ok, why = ModGens.permits(weather, nil, 3)
check(ok == true, "weather_fx-shaped permits gen3")

local radar = { id = "johto_radar", games = { "gen1", "gen2" } }
ok, why = ModGens.permits(radar, nil, 3)
check(ok == true, "johto_radar-shaped permits gen3")

-- Loader source-scan: gate must call ModGens.permits before ModTargets skip
local body = assert(io.open("src/mods/Loader.lua", "r")):read("*a")
check(body:find('ModGens = require%("src%.mods%.ModGens"%)') ~= nil
  or body:find('require%("src%.mods%.ModGens"%)') ~= nil,
  "Loader requires ModGens")
check(body:find("ModGens.permits") ~= nil, "Loader:_gateGeneration uses ModGens.permits")
check(body:find("generation = loader.generation") ~= nil,
  "Loader:_api injects mod.generation (Emerald host)")
check(body:find("gameVersion = loader:_targetVersion()") ~= nil,
  "Loader:_api injects mod.gameVersion")
check(body:find("host = %(function%(%)") ~= nil
  or body:find("host = %(function") ~= nil,
  "Loader:_api injects mod.host")

-- DO NOT touch Gen3Compat Font arming
local g3 = assert(io.open("src/mods/Gen3Compat.lua", "r")):read("*a")
check(g3:find("armPlainPixelFont") ~= nil, "Gen3Compat Font Plain Pixel arming preserved")

io.write(string.format("modgens_emerald_gate_test: %d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
