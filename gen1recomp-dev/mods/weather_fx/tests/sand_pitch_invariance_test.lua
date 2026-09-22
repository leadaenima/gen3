-- Regression: 3D sand presentation must not change when camera pitch changes.
-- Camera orientation may change visibility, never the world-space size, alpha,
-- ground lift or depth mode of a frozen sand field.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("FAIL: ", msg, "\n") end
end

local lastSig = nil
local depthModes = {}
local function mesh()
  local m = {}
  function m:setVertices(verts, startv, count)
    local sums = {0,0,0,0,0,0,0}
    for i = startv or 1, (startv or 1) + (count or #verts) - 1 do
      local v = verts[i]
      for k=1,7 do sums[k] = sums[k] + (v[k] or 0) end
    end
    lastSig = string.format("%d|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f",
      count or #verts, sums[1],sums[2],sums[3],sums[4],sums[5],sums[6],sums[7])
  end
  function m:setDrawRange() end
  return m
end

love = { graphics = {
  newMesh = function() return mesh() end,
  newShader = function() return { send=function() end } end,
  setBlendMode = function() end,
  setDepthMode = function(mode) depthModes[#depthModes+1] = tostring(mode) end,
  setShader = function() end,
  setColor = function() end,
  draw = function() end,
} }

local Q = { budget=function()
  return {
    worldPrecip=1.0, worldRadiusCap=96,
    worldRainCap=0, worldSnowCap=0, worldBlizzardCap=0,
    worldHailCap=0, worldSandCap=12, worldDebrisCap=0, worldAshCap=0,
    worldSplashCap=0, worldSnowMoundCap=0, worldFootprintCap=0,
  }
end }
local S = { isFirstPerson=function() return true end, leafColor=function() return "green" end }
local V = { require=function(name)
  if name == "Quality" then return Q end
  if name == "Settings" then return S end
  return nil
end }

local WP = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)
local focus = {100,0,100}
local weather = {wxId="SANDSTORM", sandIntensity=1.45}
for _=1,12 do WP.update(1/60, focus, weather, {anchorKind="player"}) end
local st = WP.spawnStatus()
check((st.sand or 0) > 0, "sand allocator produced a live test field")
check((st.sand or 0) <= 12, "test field obeys the tiny hard cap")

local eye={100,10,100}
local function render(focusTarget)
  lastSig=nil; depthModes={}
  WP.draw({vp={},eye=eye,focus=focusTarget,far=300}, {weather=weather})
  return lastSig, table.concat(depthModes, ",")
end

local horizonSig,horizonDepth = render({220,10,100})
local downSig,downDepth = render({104,-110,100})
local upSig,upDepth = render({104,130,100})

check(horizonSig ~= nil and downSig ~= nil and upSig ~= nil,
  "sand submits drawable geometry at horizon/down/up pitches")
check(horizonSig == downSig and horizonSig == upSig,
  "frozen sand submits identical geometry when only camera pitch changes")
check(not horizonDepth:find("always",1,true), "horizon sand does not use always-pass depth")
check(not downDepth:find("always",1,true), "look-down sand does not use always-pass depth")
check(not upDepth:find("always",1,true), "look-up sand does not use always-pass depth")

io.write(string.format("sand pitch invariance: %d passed, %d failed\n", checks-failures, failures))
os.exit(failures == 0 and 0 or 1)
