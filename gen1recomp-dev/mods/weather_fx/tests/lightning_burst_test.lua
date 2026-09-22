-- Severe-storm simultaneous lightning burst regression.
-- Proves STORM/PRIML/PSY can request 2-4 bolts, non-severe weather stays single,
-- and WorldLightning really holds/draws four independent world-space strikes.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then failures = failures + 1; io.write("FAIL: ", msg, "\n") end
end

-- Deterministic random for the scheduler profile test.
local nextRandom = 0.5
love = { math = { random = function() return nextRandom end } }
local L = assert(loadfile(ROOT .. "lib/Lightning.lua"))({})

local function expectBurst(id, u, want)
  nextRandom = u
  local got = L.sampleBurstCount(id)
  check(got == want, string.format("%s u=%.3f -> %d bolts (wanted %d)", id, u, got, want))
end

-- STORM: 58% single, 30% double, 10% triple, 2% quad.
expectBurst("STORM", 0.10, 1)
expectBurst("STORM", 0.70, 2)
expectBurst("STORM", 0.93, 3)
expectBurst("STORM", 0.995, 4)
-- PRIML: stronger cluster behaviour.
expectBurst("PRIML", 0.10, 1)
expectBurst("PRIML", 0.55, 2)
expectBurst("PRIML", 0.82, 3)
expectBurst("PRIML", 0.97, 4)
-- PSY: most violent cluster behaviour.
expectBurst("PSY", 0.10, 1)
expectBurst("PSY", 0.35, 2)
expectBurst("PSY", 0.70, 3)
expectBurst("PSY", 0.95, 4)
expectBurst("GALE", 0.99, 1)
expectBurst("THUNDERSNOW", 0.99, 1)

-- Prove the live scheduler stores the sampled burst on the strike event, not
-- merely that the helper can calculate it. SOFT avoids constructing the legacy
-- 2D bolt while exercising the same event scheduler used by 3D.
local seq, qi = {0.5, 0.5, 0.995}, 1
love.math.random = function() local v=seq[qi] or 0.5; qi=qi+1; return v end
L.timer, L._hadRate, L.strikeSerial = 0, true, 0
L.update(0.016, 18, "soft", 0,0,160,144,1, "STORM")
check(L.strikeSerial == 1, "live scheduler emits a severe-storm strike event")
check(L.burstCount == 4 and L.burstWeather == "STORM",
  "live scheduler publishes the sampled simultaneous-bolt count")

-- Real world-bolt allocation/draw proof.
math.randomseed(4340)
love = { graphics = {
  newMesh=function(fmt,cap)
    local m={cap=cap}
    function m:setVertices(v,start,count) self.count=count or #v end
    function m:setDrawRange(a,b) self.range=b end
    return m
  end,
  newShader=function(src) return {send=function() end} end,
  setBlendMode=function() end,
  setDepthMode=function() end,
  setShader=function() end,
  setColor=function() end,
  draw=function(mesh) _G.__burstDraws=(_G.__burstDraws or 0)+1 end,
} }

local map = { id="current", def={width=64,height=48} }
local function ground(map,cx,cz) return 2 + ((cx*5 + cz*7) % 9) end
local V = {}
function V.require(name)
  if name == "VoxelScene" then return {groundAt=ground} end
  if name == "RenderDistance" then
    return {radius=function() return 900 end, point=function() return true end}
  end
  error("unexpected require " .. tostring(name), 0)
end
local WL = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldLightning.lua"))(V)
local Vox = {
  far=900, eye={500,50,380}, focus={500,0,380}, vp={},
  beginEffect=function() return true end, endEffect=function() end,
}
local focus={500,0,380}
local player={px=492,py=372}
local cluster = WL.strikeBurst(focus,120,{deckSpan=30,map=map,neighbors={},player=player,Voxel3D=Vox},4)
check(#cluster == 4, "quad severe-storm event allocates four bolts")
local live = WL.sample()
check(#live == 4, "all four bolts are live simultaneously")

local unique = {}
local terrainOK, cloudOK = 0, 0
for i,b in ipairs(live) do
  local key = string.format("%.1f:%.1f", b.x, b.z)
  unique[key] = true
  if b.cellX and b.cellZ and math.abs(b.y - (ground(map,b.cellX,b.cellZ)+0.08)) < 0.0001 then terrainOK=terrainOK+1 end
  if b.topY >= 120+30*0.18-0.001 and b.topY <= 120+30*0.82+0.001 then cloudOK=cloudOK+1 end
end
local uniqCount=0 for _ in pairs(unique) do uniqCount=uniqCount+1 end
check(uniqCount == 4, "simultaneous bolts use four distinct world targets")
check(terrainOK == 4, "all simultaneous bolts terminate on voxel terrain")
check(cloudOK == 4, "all simultaneous bolts originate inside the live cloud deck")

WL.draw(Vox)
check((_G.__burstDraws or 0) > 0, "quad burst reaches a 3D draw submission")
check(WL.drawingBolt(), "quad burst reports healthy 3D bolt ownership")
local desc=WL.describe()
check(desc:find("bolts=4/4",1,true) ~= nil, "debug status reports four live simultaneous bolts")

io.write(string.format("lightning burst: %d passed, %d failed\n", checks-failures, failures))
os.exit(failures==0 and 0 or 1)
