-- Runtime spawn + submission proof for every 3D particle family.
-- IMPORTANT: cases provide only V.weatherFxId. No rain/snow/hail/sand/ash/
-- debris intensity is injected into the weather bag. The real WorldPrecip
-- module must reconstruct the requested channel, allocate actual particles,
-- build vertices and reach love.graphics.draw.
local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"

local drawCalls = 0
local function mesh(fmt, capOrVerts)
  local cap = type(capOrVerts) == "number" and capOrVerts or #(capOrVerts or {})
  local m = { cap=cap, submitted=0 }
  function m:setVertices(verts, startv, count)
    self.submitted = count or #verts
    if self.submitted > self.cap then error("mesh overflow", 0) end
  end
  function m:setDrawRange() end
  return m
end

love = { graphics = {
  newMesh=function(fmt,a) return mesh(fmt,a) end,
  newShader=function() return { send=function() end } end,
  setBlendMode=function() end,
  setDepthMode=function() end,
  setShader=function() end,
  setColor=function() end,
  draw=function(m)
    assert(m and (m.submitted or 0) > 0, "draw called without submitted vertices")
    drawCalls = drawCalls + 1
  end,
}}

local V = {}
local Types = assert(loadfile(ROOT .. "lib/Types.lua"))()
function V.require(name)
  if name == "Types" then return Types end
  if name == "Quality" then
    -- Keep the proof fast while still allocating enough particles to prove the
    -- real pool and geometry path. This scales counts, not family existence.
    return { budget=function() return { worldPrecip=0.01 } end }
  end
  if name == "Settings" then
    return {
      isFirstPerson=function() return false end,
      splashOn=function() return false end,
      leafColor=function() return "green" end,
    }
  end
  if name == "Scene" then return { now={ visible="world" } } end
  error("no module " .. tostring(name), 0)
end

-- Deliberately use the FPV host shape that regressed in 8.1.3: `focus` is
-- the player/world anchor below the eye, while `lookFlat` is the real camera
-- heading.  Rain must still build visible geometry from the cloud deck.
local Voxel3D = {
  eye={0,12,0}, focus={0,0,0}, player={0,0,0}, lookFlat={0,0,1}, far=400,
  vp={1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1},
}
local anchor = {0,0,0}
local deck = {anchorKind="player", deckY=120, deckSpan=24}

local cases = {
  { id="RAIN_LIGHT", field="rain" },
  { id="SNOW_LIGHT", field="snow" },
  { id="HAIL", field="hail" },
  { id="SANDSTORM", field="sand" },
  { id="DUSTSTORM", field="sand" },
  { id="GALE", field="debris" },
  { id="STRONG_WINDS", field="debris" },
  { id="ASHFALL", field="ash" },
}

local failures = 0
for _, c in ipairs(cases) do
  local W = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)
  V.weatherFxId = c.id
  drawCalls = 0
  local weather = {}
  W.update(1/60, anchor, weather, deck)
  local spawn = W.spawnStatus()
  local count = tonumber(spawn[c.field]) or 0
  if count <= 0 then
    failures = failures + 1
    io.write(string.format("FAIL %-13s spawn %s=%d\n", c.id, c.field, count))
  end
  W.draw(Voxel3D, {weather=weather})
  local draw = W.drawStatus()
  local d = draw[c.field] or {}
  local verts = tonumber(d.verts) or 0
  local healthy = d.healthy == true
  if verts <= 0 or not healthy or drawCalls <= 0 then
    failures = failures + 1
    io.write(string.format("FAIL %-13s draw %s active=%d verts=%d healthy=%s calls=%d\n",
      c.id, c.field, tonumber(d.active) or 0, verts, tostring(healthy), drawCalls))
  else
    io.write(string.format("SPAWN %-13s %-6s active=%d verts=%d drawCalls=%d\n",
      c.id, c.field, count, verts, drawCalls))
  end
end
V.weatherFxId = nil

io.write(string.format("world_precip_spawn_proof: %d cases, %d failures\n", #cases, failures))
if failures > 0 then os.exit(1) end
