-- weather_fx: headless tests for WX PRESENT + 3D bridge contracts.
--
--   lua tests/present_3d_test.lua
--   (lua5.1 / 5.3 / 5.4 / LuaJIT)
--
-- Does not need LÖVE, a ROM, or Dramaless installed. Validates that the
-- presentation switch and bridge modules load and honor 2D/3D contracts.

local scriptPath = (arg and arg[0]) or "tests/present_3d_test.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1
  else failed = failed + 1; io.write("  FAIL  ", label, "\n") end
end
local function eq(a, b, label)
  if a ~= b then
    failed = failed + 1
    io.write("  FAIL  ", label, "  (", tostring(a), " ~= ", tostring(b), ")\n")
  else passed = passed + 1 end
end
local function section(name) io.write("\n", name, "\n") end

-- Minimal love stub
love = {
  graphics = {
    newImage = function()
      return { getDimensions = function() return 1, 1 end,
               setFilter = function() end }
    end,
    newShader = function() return { send = function() end } end,
    newMesh = function() return { setVertexMap = function() end } end,
    setShader = function() end,
    setDepthMode = function() end,
    setBlendMode = function() end,
    getBlendMode = function() return "alpha", "alphamultiply" end,
    setColor = function() end,
    getColor = function() return 1, 1, 1, 1 end,
    draw = function() end,
    rectangle = function() end,
    getWidth = function() return 160 end,
    getHeight = function() return 144 end,
    getCanvas = function() return nil end,
    getDimensions = function() return 160, 144 end,
  },
  filesystem = { read = function() return nil end, getInfo = function() return nil end },
  timer = { getTime = function() return 0 end },
  audio = { newSource = function() return { play = function() end, stop = function() end,
                                            setLooping = function() end, setVolume = function() end } end },
}

local optionStore = {}
local modStub = {
  path = ROOT,
  id = "weather_fx",
  log = { info = function() end, warn = function() end, error = function() end },
  save = {
    get = function() return nil end,
    set = function() end,
  },
  options = {
    define = function(_, schema) return schema end,
    get = function(_, key) return optionStore[key] end,
    set = function(_, key, value) optionStore[key] = value end,
  },
  content = {
    render_pipelines = {
      register = function() end,
      get = function() return nil end,
      patch = function() end,
    },
  },
  find = function(_, id)
    -- No host by default — bridge should stay inactive.
    return nil
  end,
  read = function(_, rel)
    local f = io.open(ROOT .. "/" .. rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}

local V = { mod = modStub, path = ROOT }
local modules = {}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local src = modStub:read("lib/" .. name .. ".lua")
  assert(src, "missing lib/" .. name .. ".lua")
  local chunk = assert((loadstring or load)(src, "@" .. name))
  local value = chunk(V)
  modules[name] = value
  return value
end

-- -------- load core pieces
local Types = V.require("Types")
local Settings = V.require("Settings")
Settings.define()

section("WX PRESENT schema")
do
  local found
  for _, row in ipairs(Settings.SCHEMA) do
    if row.key == "present" then found = row break end
  end
  check(found ~= nil, "present row exists in SCHEMA")
  if found then
    eq(found.default, "auto", "default is auto")
    local vals = {}
    for _, c in ipairs(found.choices or {}) do vals[c[2]] = true end
    check(vals["2d"] and vals["3d"] and vals["auto"], "choices include 2d, 3d, auto")
  end
  eq(Settings.presentMode(), "auto", "presentMode() defaults to auto")
  check(Settings.allow3dPresent() == true, "auto allows 3d")
  check(Settings.force2dPresent() == false, "auto does not force 2d")
  check(Settings.force3dPresent() == false, "auto does not force strict 3d")

  optionStore.present = "2d"
  eq(Settings.presentMode(), "2d", "presentMode reads 2d")
  check(Settings.force2dPresent() == true, "2d forces 2d")
  check(Settings.allow3dPresent() == false, "2d disallows 3d")
  check(Settings.force3dPresent() == false, "2d does not force strict 3d")

  optionStore.present = "3d"
  eq(Settings.presentMode(), "3d", "presentMode reads 3d")
  check(Settings.force2dPresent() == false, "3d does not force 2d")
  check(Settings.allow3dPresent() == true, "3d allows 3d")
  check(Settings.force3dPresent() == true, "3d forces strict 3d")

  optionStore.present = "bogus"
  eq(Settings.presentMode(), "auto", "invalid present falls back to default")
  optionStore.present = nil
end

section("Types catalogue still intact")
do
  check(Types.get("CLEAR") ~= nil, "CLEAR exists")
  check(Types.get("RAIN_LIGHT") ~= nil, "RAIN_LIGHT exists")
  check(Types.get("STORM") ~= nil, "STORM exists")
  check(Types.DEFAULT == "CLEAR", "DEFAULT is CLEAR")
end

section("VoxelAtmosBridge without host")
do
  local Bridge = V.require("VoxelAtmosBridge")
  check(type(Bridge.init) == "function", "init exists")
  check(type(Bridge.active) == "function", "active exists")
  local ok = Bridge.init()
  check(ok == false, "init fails closed with no host")
  check(Bridge.active() == false, "inactive without host")
  check(Bridge.handlesPrecipitation() == false, "no precip claim without host")
  check(Bridge.handlesFog() == false, "no fog claim without host")
  -- should not throw
  Bridge.syncFromWeatherFx({ id = "RAIN_LIGHT", ch = { rain = 1 } })
  Bridge.update(0.016)
  Bridge.invalidate()
  check(true, "sync/update/invalidate are safe no-ops when inactive")
end

section("DramalessAtmos without host")
do
  modules["DramalessAtmos"] = nil -- force reload if cached oddly
  -- Bridge already required it; get from modules
  local Atmos = modules["DramalessAtmos"] or V.require("DramalessAtmos")
  check(type(Atmos.install) == "function", "install exists")
  local ok = Atmos.install()
  check(ok == false, "install fails without host")
  check(Atmos.active() == false, "inactive without host")
  check(Atmos.handlesPrecipitation() == false, "no precip without host")
end

section("2d present forces no 3d handling even if somehow active")
do
  optionStore.present = "2d"
  local Atmos = modules["DramalessAtmos"]
  -- Manually poke internal flags to simulate a live host, then ensure
  -- want3d/handles* still refuse under 2d present.
  if Atmos then
    Atmos._active = true
    Atmos._drawing = true
    Atmos._wxId = "RAIN_LIGHT"
    check(type(Atmos.wants3d) == "function" and Atmos.wants3d() == false,
      "2d present makes active voxel host non-3d presentation")
    check(Atmos.handlesPrecipitation() == false,
      "2d present blocks handlesPrecipitation even if _active")
    check(Atmos.handlesFog() == false,
      "2d present blocks handlesFog even if _active")
    local oldFP = Settings.isFirstPerson
    Settings.isFirstPerson = function() return true end
    check(Atmos.wants3d() == true,
      "first-person intentionally forces strict 3d even when present row says 2d")
    Settings.isFirstPerson = oldFP
    Atmos._active = false
    Atmos._drawing = false
  else
    check(false, "DramalessAtmos module available for force test")
  end
  optionStore.present = nil
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
