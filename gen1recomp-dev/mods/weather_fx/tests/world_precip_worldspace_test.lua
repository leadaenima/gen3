-- Fast executable contract for Weather FX 3D world-space weather.
-- Covers camera invariance, cloud-deck spawning, and every WorldPrecip family.
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("FAIL: ", msg, "\n") end
end

local function mesh(fmt, capOrVerts)
  local cap = type(capOrVerts) == "number" and capOrVerts or #(capOrVerts or {})
  local m = { cap=cap }
  function m:setVertices(verts, startv, count)
    if count and count > self.cap then error("mesh overflow") end
  end
  function m:setDrawRange() end
  return m
end
love = { graphics = {
  newMesh=function(fmt,a) return mesh(fmt,a) end,
  newShader=function() return {send=function() end} end,
  setBlendMode=function() end, setDepthMode=function() end,
  setShader=function() end, setColor=function() end, draw=function() end,
}}

local V = {}
local Types = assert(loadfile(ROOT .. "lib/Types.lua"))()
function V.require(name)
  if name == "Types" then
    return Types
  elseif name == "Quality" then
    return { budget=function() return {worldPrecip=0.001} end }
  elseif name == "Settings" then
    return { isFirstPerson=function() return false end,
             splashOn=function() return false end }
  end
  error("no module " .. tostring(name), 0)
end

local function fresh()
  return assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)
end
local function sampleY(W, prefix)
  for _, line in ipairs(W.sample(12)) do
    if line:match("^" .. prefix) then
      return tonumber(line:match("pos=%([^,]+,([%-0-9.]+),"))
    end
  end
end
local function snapshot(W)
  return table.concat(W.sample(12), "|")
end
local function vx(eye, focus)
  return {
    eye=eye or {0,10,0}, focus=focus or {0,10,100}, far=400,
    vp={1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1},
  }
end

local anchor = {0,0,0}
local deck = {anchorKind="player", deckY=120, deckSpan=2}
local deckCases = {
  {name="snow", prefix="Snow#", weather={wxId="SNOW", snowIntensity=1.9}},
  {name="rain", prefix="Rain#", weather={wxId="RAIN", rainIntensity=1.0}},
  {name="hail", prefix="Hail#", weather={wxId="HAIL", hailIntensity=1.25}},
  {name="ash",  prefix="Ash#",  weather={wxId="ASHFALL", ashIntensity=1.45}},
}
for _, c in ipairs(deckCases) do
  local W = fresh()
  W.update(1/120, anchor, c.weather, deck)
  local y = sampleY(W, c.prefix)
  check(y ~= nil, c.name .. " family is live")
  if y then
    if c.name == "rain" then
      local lo,hi,n,deckY,deckSpan=W.rainColumnRange()
      check(n and n > 0 and hi and hi >= 112 and hi <= 123,
        string.format("%s retains live drops beside cloud-deck origin (hi=%.1f)", c.name, hi or -999))
      check(lo and lo < 90 and (hi-lo) > 30,
        string.format("%s activation immediately spans cloud-to-ground fall column (%.1f..%.1f)", c.name, lo or -999, hi or -999))
    else
      -- Fresh slow cloud-origin families are deliberately warm-started down
      -- their physical fall column so selecting the weather does not leave the
      -- world empty for tens of seconds. They may already be below the deck.
      check(y <= 122.5 and y > -40,
        string.format("%s is primed below its cloud-deck origin (%.1f)", c.name, y))
    end
  end
end

-- End-to-end spawn authority: provide NO family intensities at all. The live
-- Weather FX id in the shared 3D namespace must reconstruct the correct channel
-- before allocation. This catches the exact bug where rain survived a stale
-- cinematic profile while snow/hail/sand/leaves/ash received zero spawn demand.
local authorityCases = {
  {id="SNOW_LIGHT", field="snow"},
  {id="BLIZZARD", field="snow"},
  {id="THUNDERSNOW", field="snow"},
  {id="SLEET", field="snow"},
  {id="HAIL", field="hail"},
  {id="SANDSTORM", field="sand"},
  {id="DUSTSTORM", field="sand"},
  {id="GALE", field="debris"},
  {id="STRONG_WINDS", field="debris"},
  {id="BRAWL_WIND", field="debris"},
  {id="FLOCKSTORM", field="debris"},
  {id="SWARM", field="debris"},
  {id="ASHFALL", field="ash"},
  {id="SMOG", field="ash"},
}
for _, c in ipairs(authorityCases) do
  local W = fresh()
  V.weatherFxId = c.id
  W.update(1/60, anchor, {}, deck)
  local st = W.spawnStatus()
  check((tonumber(st[c.field]) or 0) > 0,
    c.id .. " reconstructs a live " .. c.field .. " particle target from Weather FX id")
end
V.weatherFxId = nil

-- Pure camera rotation may change visibility/billboards, never simulation XYZ.
do
  local W = fresh()
  local w = {wxId="SNOW", snowIntensity=1.9}
  W.update(1/60, anchor, w, deck)
  local before = snapshot(W)
  local eye = {0,10,0}
  for _, look in ipairs({{100,10,0},{-100,10,0},{0,120,0},{0,-100,0}}) do
    W.draw(vx(eye, look), {weather=w})
    check(snapshot(W) == before, "camera rotation does not move live snow")
  end
end

-- Every shipped 3D particle family must cross update -> allocation -> draw.
local families = {
  {name="rain", kind=0, w={wxId="RAIN", rainIntensity=1.0}},
  {name="snow", kind=-1, w={wxId="SNOW", snowIntensity=1.9}},
  {name="hail", kind=1, w={wxId="HAIL", hailIntensity=1.25}},
  {name="sand", kind=2, w={wxId="SANDSTORM", sandIntensity=2.35}},
  {name="debris", kind=3, w={wxId="GALE", debrisIntensity=1.15}},
  {name="ash", kind=4, w={wxId="ASHFALL", ashIntensity=1.45}},
}
for _, c in ipairs(families) do
  local W = fresh()
  W.update(1/60, anchor, c.w, deck)
  W.draw(vx(), {weather=c.w})
  local ok
  if c.kind == 0 then ok = W.drawingRain()
  elseif c.kind == -1 then ok = W.drawingSnow()
  else ok = W.drawingGrain(c.kind) end
  check(ok == true, c.name .. " reaches a healthy 3D draw path")
end

io.write(string.format("world_precip_worldspace_test: %d passed, %d failed\n", checks-failures, failures))
if failures > 0 then os.exit(1) end
