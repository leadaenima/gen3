-- Dev preview: render the Gen 3 cinema extractor output to real PNGs so the
-- results can be eyeballed. Not part of the game; scratch tooling.
--
-- Run from the repo:  lovec tools/gen3_preview
-- PNG dumps go to tmp/debug/ (never the process CWD / Desktop).
local ROM = "C:/Users/Feces/Desktop/Pokemon - Ruby Version (USA).gba"

local function repoRoot()
  local src = (love.filesystem.getSource() or ""):gsub("\\", "/")
  return src:match("^(.*)/tools/gen3_preview/?$")
    or "C:/Users/Feces/Desktop/pkmn gen1recomp/gen1recomp-dev"
end

local REPO = repoRoot()
package.path = REPO .. "/?.lua;" .. REPO .. "/?/init.lua;" .. package.path

local OUT = REPO .. "/tmp/debug"

local function ensureDir(path)
  local ok, ffi = pcall(require, "ffi")
  if not ok then return end
  pcall(ffi.cdef,
    "int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);")
  pcall(ffi.C.CreateDirectoryA, path, nil)
end

local function writePng(img, name)
  ensureDir(REPO .. "/tmp")
  ensureDir(OUT)
  local fd = img:encode("png")
  local f = assert(io.open(OUT .. "/" .. name, "wb"))
  f:write(fd:getString())
  f:close()
end

local log = {}
local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  log[#log + 1] = table.concat(parts, " ")
  print(table.concat(parts, " "))
end

local function writeLog()
  ensureDir(REPO .. "/tmp")
  ensureDir(OUT)
  local f = io.open(OUT .. "/gen3_preview.log", "w")
  if f then
    f:write(table.concat(log, "\n"))
    f:close()
  end
end

function love.load()
  local f = io.open(ROM, "rb")
  if not f then
    say("NO ROM")
    writeLog()
    love.event.quit()
    return
  end
  local data = f:read("*a")
  f:close()
  say("rom bytes", #data)

  local ok, Cinema = pcall(require, "src.import.RomExtractorGen3Cinema")
  if not ok then
    say("require failed", Cinema)
    writeLog()
    love.event.quit()
    return
  end

  local layers = Cinema.renderIntro1Layers(data)
  if layers then
    for i = 1, 4 do
      writePng(layers[i], "intro1_bg" .. (i - 1) .. ".png")
      say("intro1 bg" .. (i - 1), "ok")
    end
  else
    say("intro1 layers nil")
  end

  local jobs = {
    { "copyright", Cinema.renderCopyright },
    { "intro2", Cinema.renderIntro2 },
    { "gamefreak", Cinema.renderGameFreak },
    { "title", Cinema.renderTitle },
    { "press_start", Cinema.renderPressStart },
    { "intro1_drop", Cinema.renderIntro1Drop },
    { "intro1_splash", Cinema.renderIntro1Splash },
    { "intro1_eon", Cinema.renderIntro1Eon },
    { "intro2_treesobj", Cinema.renderIntro2TreeObj },
    { "intro2_brendan", Cinema.renderIntro2Brendan },
    { "intro2_bike", Cinema.renderIntro2Bike },
    { "intro2_latios", Cinema.renderIntro2Latios },
    { "intro3_ball", Cinema.renderIntro3Ball },
    { "intro3_streaks", Cinema.renderIntro3Streaks },
    { "intro3_brendan", Cinema.renderIntro3Brendan },
    { "intro3_may", Cinema.renderIntro3May },
    { "intro3_poke", Cinema.renderIntro3Poke },
  }
  for _, job in ipairs(jobs) do
    local name, fn = job[1], job[2]
    local okr, img = pcall(fn, data)
    if not okr then
      say(name, "ERROR", img)
    elseif not img then
      say(name, "nil")
    else
      local w, h = img:getDimensions()
      writePng(img, name .. ".png")
      say(name, "ok", w .. "x" .. h)
    end
  end
  do
    local okr, blast, spark = pcall(Cinema.renderIntro3Misc, data)
    if okr and blast then
      writePng(blast, "intro3_blast.png")
      local w, h = blast:getDimensions()
      say("intro3_blast", "ok", w .. "x" .. h)
    else
      say("intro3_blast", okr and "nil" or blast)
    end
    if okr and spark then
      writePng(spark, "intro3_spark.png")
      local w, h = spark:getDimensions()
      say("intro3_spark", "ok", w .. "x" .. h)
    end
  end
  do
    local okr, water, ember = pcall(Cinema.renderIntro3AttackGfx, data)
    if okr and water then
      writePng(water, "intro3_water.png")
      local w, h = water:getDimensions()
      say("intro3_water", "ok", w .. "x" .. h)
    else
      say("intro3_water", okr and "nil" or water)
    end
    if okr and ember then
      writePng(ember, "intro3_ember.png")
      local w, h = ember:getDimensions()
      say("intro3_ember", "ok", w .. "x" .. h)
    end
  end

  local CacheFs = require("src.import.CacheFs")
  local LuaWriter = require("src.import.LuaWriter")
  CacheFs.prefix = "ruby/"
  local cinema = Cinema.extract(data)
  local n = 0
  for k in pairs(cinema) do n = n + 1 end
  say("cache cinema keys", n)
  local raw = CacheFs.read("data/generated/title.lua")
  local title = {}
  if type(raw) == "string" then
    local loader = loadstring or load
    local chunk = loader(raw)
    if chunk then title = chunk() or {} end
  end
  title.cinema = title.cinema or {}
  for k, v in pairs(cinema) do
    title.cinema[k] = v
    say("cache", k, tostring(v))
  end
  LuaWriter.write("data/generated/title.lua", title)
  CacheFs.prefix = ""

  say("dump dir", OUT)
  writeLog()
  love.event.quit()
end
