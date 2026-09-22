-- WorldPrecip simulation test.
--
-- These assertions are written against BEHAVIOUR, not shape. AGENTS.md's
-- warning applies directly here: this module's previous test
-- (tools/test_world_precip.py) only grepped the source for the string
-- "WorldPrecip.update", so it passed green for every release in which the
-- module was a hard compile error and loaded on no host at all.
--
-- Everything below either loads and runs the real file or fails.
--
--   lua tests/world_precip_sim_test.lua        (run from the mod root)

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"

local failures, checks = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    io.write("FAIL: ", msg, "\n")
  end
end

-- ---------------------------------------------------------------------------
-- Mock love: enough of the graphics API for the draw path, and a counter so the
-- test can prove the vertex buffer stops allocating meshes once warm.
-- ---------------------------------------------------------------------------
local meshesCreated = 0
local lastDrawnCount = 0
local lastUploadSignature = nil
local depthModeCalls = {}

local function newMockMesh(fmt, capOrVerts)
  local cap = type(capOrVerts) == "number" and capOrVerts or #capOrVerts
  meshesCreated = meshesCreated + 1
  local m = { cap = cap, uploaded = 0 }
  function m:setVertices(verts, startv, count)
    if count then
      if count > self.cap then error("upload past mesh capacity") end
      -- verify the prefix is well formed
      for i = startv, startv + count - 1 do
        local v = verts[i]
        if type(v) ~= "table" or #v ~= 7 then error("malformed vertex at " .. i) end
        for k = 1, 7 do
          if type(v[k]) ~= "number" or v[k] ~= v[k] then
            error("non-finite vertex component at " .. i .. "," .. k)
          end
        end
      end
      self.uploaded = count
      local sums = {0,0,0,0,0,0,0}
      for i = startv, startv + count - 1 do
        local v = verts[i]
        for k = 1, 7 do sums[k] = sums[k] + v[k] end
      end
      lastUploadSignature = string.format("%d|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f",
        count, sums[1], sums[2], sums[3], sums[4], sums[5], sums[6], sums[7])
    else
      self.uploaded = #verts
    end
  end
  function m:setDrawRange(s, n) lastDrawnCount = n end
  return m
end

love = {
  graphics = {
    newMesh = function(fmt, a, b, c) return newMockMesh(fmt, a) end,
    newShader = function(src) return { send = function() end } end,
    setBlendMode = function() end,
    setDepthMode = function(mode) depthModeCalls[#depthModeCalls+1] = tostring(mode) end,
    setShader = function() end,
    setColor = function() end,
    draw = function() end,
  },
}

-- ---------------------------------------------------------------------------
-- Mock namespace. Quality reports a potato budget so the test also proves the
-- cap actually scales -- the thing that silently did nothing before the
-- DramalessAtmos require chain was fixed.
-- ---------------------------------------------------------------------------
local firstPersonFlag = true
local V = {}
function V.require(name)
  if name == "Quality" then
    return { budget = function() return { worldPrecip = 1.0 } end }
  elseif name == "Settings" then
    return { isFirstPerson = function() return firstPersonFlag end }
  end
  error("no module " .. name, 0)
end

local chunk = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))
local WP = chunk(V)
check(type(WP) == "table", "module returns a table")
check(type(WP.update) == "function", "WP.update exists")
check(type(WP.draw) == "function", "WP.draw exists")

-- ---------------------------------------------------------------------------
-- 1. The module compiles and runs on a 5.1-compatible dialect.
-- ---------------------------------------------------------------------------
-- The dead `hash()` helper used Lua 5.3 bitwise operators, which made the whole
-- file a compile error under LuaJIT. Its replacement must be callable and must
-- stay in the unit interval.
check(type(WP.hash) == "function", "float hash replaces the 5.3-bitwise one")
if type(WP.hash) == "function" then
  local inRange = true
  for i = 1, 500 do
    local h = WP.hash(i, 7)
    if not (h >= 0 and h < 1) then inRange = false end
  end
  check(inRange, "hash stays in [0,1)")
end

-- ---------------------------------------------------------------------------
-- 2. Snowy weather ids all resolve to falling snow.
-- ---------------------------------------------------------------------------
-- FROST*, ICEBOUND and WHITEOUT used to fall through the classifier entirely
-- and produce zero flakes.
-- HAIL deliberately NOT in this list since 4.30.2. It used to request a snow
-- target as well, so hail weather dropped snowflakes AND hailstones together --
-- which makes the two impossible to tell apart. Hail is ice pellets, rendered
-- by the grain family (kind 1); it is not snowfall. SLEET keeps its snow
-- because sleet genuinely is part snow.
local SNOWY = { "SNOW", "SNOW_LIGHT", "BLIZZARD", "THUNDERSNOW", "SLEET",
                "WHITEOUT", "ICEBOUND", "FROSTBOG", "FROSTWAVE", "SNOWSHREW",
                "TSNOW", "DRAGONSTORM" }
for _, id in ipairs(SNOWY) do
  check(WP.snowyTarget(id) > 0, id .. " is classified as snowy")
end
for _, id in ipairs({ "CLEAR", "RAIN", "SANDSTORM", "FOG", "", "HAIL" }) do
  check(WP.snowyTarget(id) == 0, id .. " is not snowy")
end

-- ---------------------------------------------------------------------------
-- 3. Cloud-fall families spawn from the published 3D cloud deck.
-- ---------------------------------------------------------------------------
-- CinematicAtmos now passes the lower band of the ACTUAL rendered cloud deck
-- into WorldPrecip. Exercise the simulator directly here so a future rename or
-- ignored metadata argument cannot silently return snow/rain/hail/ash to a
-- player-relative fake ceiling. Sand/debris are windborne world particles and
-- deliberately do not use the cloud deck.
local SmallV = {
  require = function(name)
    if name == "Quality" then
      return { budget = function() return { worldPrecip = 0.02 } end }
    elseif name == "Settings" then
      return { isFirstPerson = function() return false end }
    end
    error("no module " .. name, 0)
  end,
}
local function freshWP()
  return assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(SmallV)
end
local function firstY(list, prefix)
  for _, line in ipairs(list or {}) do
    if line:match("^" .. prefix) then
      return tonumber(line:match("pos=%([^,]+,([%-0-9.]+),"))
    end
  end
  return nil
end
local deckFocus = { 50, 0, 75 }
local deckMeta = { anchorKind = "player", deckY = 120, deckSpan = 2 }
for _, case in ipairs({
  { label="snow", prefix="Snow#", weather={wxId="SNOW", snowIntensity=1.9} },
  { label="rain", prefix="Rain#", weather={wxId="RAIN", rainIntensity=1.0} },
  { label="hail", prefix="Hail#", weather={wxId="HAIL", hailIntensity=1.25} },
  { label="ash",  prefix="Ash#",  weather={wxId="ASHFALL", ashIntensity=1.45} },
}) do
  local W = freshWP()
  W.update(1/120, deckFocus, case.weather, deckMeta)
  local y = firstY(W.sample(12), case.prefix)
  check(y ~= nil, case.label .. " has a live 3D particle family")
  if y then
    -- One tiny integration step has already happened. Rain is fastest and can
    -- move roughly one world unit in 1/120s, so allow a small lower margin.
    check(y >= 118.5 and y <= 122.5,
      string.format("%s begins in the 3D cloud-deck band (y=%.1f)", case.label, y))
  end
end

-- Camera rotation itself must not mutate the world-space simulation. Render the
-- same live snow field from radically different look targets without an update;
-- particle positions must remain bit-for-bit the same.
do
  local W = freshWP()
  local w = { wxId="SNOW", snowIntensity=1.9 }
  W.update(1/60, deckFocus, w, deckMeta)
  local before = table.concat(W.sample(12), "|")
  local eye = { deckFocus[1], 10, deckFocus[3] }
  for _, look in ipairs({
    { 200, 10, 75 }, { -100, 10, 75 }, { 50, 140, 75 }, { 50, -80, 75 },
  }) do
    W.draw({ vp={}, eye=eye, focus=look, far=400 }, { weather=w })
    check(table.concat(W.sample(12), "|") == before,
      "camera rotation only views snow; it never drags/mutates particle world positions")
  end
end

-- ---------------------------------------------------------------------------
-- 4. A snow weather actually simulates: run a minute of frames.
-- ---------------------------------------------------------------------------
local focus = { 100, 0, 100 }
local weather = { wxId = "SNOW", snowIntensity = 0, snowWind = 0.65 }
local Voxel3D = { vp = {}, eye = { 100, 10, 100 }, focus = focus }

local ok, err = pcall(function()
  for _ = 1, 60 do
    WP.update(1 / 60, focus, weather)
    WP.draw(Voxel3D, { weather = weather })
  end
end)
check(ok, "one second of snow runs without error: " .. tostring(err))

local d = WP.describe()
local activeSnow = tonumber(d:match("snow=(%d+)")) or 0
check(activeSnow > 0, "snow particles are active (got: " .. d .. ")")
check(WP.drawingSnow(), "snow geometry was emitted, so 2D can be suppressed")
-- ...and the negative case, which is the one that matters. handlesSnow() turns
-- the 2D snow layer OFF based on this, so a drawingSnow() that reports intent
-- rather than fact would blank snow entirely in clear weather -- which is the
-- exact class of bug that made an earlier version hardcode `return false`.
do
  local clear = { wxId = "CLEAR" }
  for _ = 1, 5 do
    WP.update(1 / 60, focus, clear)
    WP.draw(Voxel3D, { weather = clear })
  end
  check(not WP.drawingSnow(), "drawingSnow() is false in clear weather")
  -- restore the snow state the later checks rely on
  for _ = 1, 60 do
    WP.update(1 / 60, focus, weather)
    WP.draw(Voxel3D, { weather = weather })
  end
end

-- ---------------------------------------------------------------------------
-- 5. Flakes occupy the near field -- you can walk through them.
-- ---------------------------------------------------------------------------
-- The old 720-unit uniform volume put almost nothing within reach of the
-- player. This is the assertion that fails if the radial bias is removed.
local samples = WP.sample(12)
check(#samples > 0, "sample() returns particles")

-- Warm up to a steady state first: a young field is still top-heavy with the
-- flakes it spawned high up, so measuring too early reads high and unstably.
for _ = 1, 1200 do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end

-- IS IT SNOWING OVER THE WORLD, OR ONLY ON THE PLAYER?
--
-- This replaces a near-field-share assertion that 4.28.69 used to guard a
-- deliberately near-biased distribution. That bias was wrong -- on screen it
-- read as a snow globe following the player across an otherwise clear map --
-- so the property to pin is the opposite one: constant flakes per unit AREA at
-- every distance. A field that clumps around the focus fails here, and so does
-- one that hollows out the near field.
local R = WP.snowCoverage()
local dIn  = WP.snowAreaDensity(focus[1], focus[3], 0,          R * 0.33)
local dMid = WP.snowAreaDensity(focus[1], focus[3], R * 0.33,   R * 0.66)
local dOut = WP.snowAreaDensity(focus[1], focus[3], R * 0.66,   R)
io.write(string.format("       [density /1000u^2  inner %.2f  mid %.2f  outer %.2f  (R=%.0f)]\n",
  dIn, dMid, dOut, R))
check(dIn > 0 and dMid > 0 and dOut > 0, "every annulus has snow in it")
if dIn > 0 and dOut > 0 then
  local spread = math.max(dIn, dMid, dOut) / math.min(dIn, dMid, dOut)
  io.write(string.format("       [density spread: %.2fx]\n", spread))
  -- Uniform sampling plus a single deck height should hold this near 1. 1.6
  -- allows for wind drift and sampling noise while still failing hard on a
  -- near-biased distribution, which spreads by well over an order of magnitude.
  check(spread < 1.6,
    string.format("snow density is even across the rendered disk (%.2fx spread)", spread))
end

-- ...and it should cover a real amount of ground, not a courtyard.
local radius, perTile = WP.snowCoverage()
io.write(string.format("       [coverage: r=%.0f (%.0f tiles wide), %.2f flakes/tile]\n",
  radius, 2 * radius / 16, perTile))
check(radius >= 160, string.format("the snow disk spans the rendered world (r=%.0f)", radius))
check(perTile > 0.5, string.format("density is high enough to read as weather (%.2f/tile)", perTile))

-- ---------------------------------------------------------------------------
-- 6. Flakes reach the ground instead of evaporating mid-air.
-- ---------------------------------------------------------------------------
-- NOTE: `gsnow > 0` is NOT the assertion to make here, even though it looks
-- like it should be. Ground drifts are also seeded by ambient scatter while it
-- snows, so gsnow is nonzero whether or not a single flake ever completes its
-- fall -- it passed green against a deliberately reintroduced flat-lifetime
-- regression. The real question is what fraction of flakes end on the ground
-- rather than expiring in mid air, which is what snowFate() reports.
local gs = tonumber(WP.describe():match("gsnow=(%d+)")) or 0
check(gs == 0, "ground snow accumulation is release-disabled (got: " .. WP.describe() .. ")")

-- Flakes must fall a full tile deeper than the focus plane.
--
-- The brief was literal: "the snow particles need to fall 1 more tile". A tile
-- is 16 world units, and the old ground plane sat 1.5 units under the focus, so
-- flakes settled almost a whole tile above where the world's floor reads.
--
-- Asserting on the GROUND_DROP constant would prove nothing -- the constant and
-- the simulation are different claims, and setting GROUND_EXTRA_TILES back to 0
-- changed no test result at all before this check existed. So this measures how
-- deep a flake actually descended.
do
  local deepest, groundDrop, tile = WP.snowDepth()
  io.write(string.format("       [flakes reach %.1f units below focus (%.2f tiles); ground plane %.1f]\n",
    deepest, deepest / tile, groundDrop))
  check(groundDrop >= tile,
    string.format("ground plane is at least a full tile below focus (%.1f of %d)", groundDrop, tile))
  check(deepest >= tile,
    string.format("flakes actually descend a full tile below focus (%.1f of %d)", deepest, tile))
  -- ...and that they stop at the plane rather than falling through the world.
  check(deepest <= groundDrop + tile,
    string.format("flakes stop near the ground plane (%.1f vs plane %.1f)", deepest, groundDrop))
end

local landed, expiredAir = WP.snowFate()
check(landed + expiredAir > 0, "flakes completed their lives")
if landed + expiredAir > 0 then
  local share = landed / (landed + expiredAir)
  -- Measured over 60 simulated seconds at SNOW:
  --   this build                            100.0% land
  --   this volume + the old flat lifetime     71.3%
  --   the shipped 4.28.68 tuning              26.6%   <- three flakes in four
  --                                                      evaporated in mid air
  -- 0.95 is set to sit above the 71.3% case, so reverting the derived lifetime
  -- fails here rather than passing on a loose bound.
  check(share > 0.95,
    string.format("flakes land instead of vanishing mid-air (%.1f%% of %d)",
      100 * share, landed + expiredAir))
end

-- ---------------------------------------------------------------------------
-- 7. Flakes land on your face in first person -- and only in first person.
-- ---------------------------------------------------------------------------
-- Contact is now a rare-ish event by design: a uniform field puts far fewer
-- flakes within reach than the old near-biased one, so this needs a real window
-- rather than the second or two the earlier version got away with. Measured
-- rate at default density is about one hit every 10 simulated seconds.
for _ = 1, 60 * 45 do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end
local faceHits = tonumber(WP.describe():match("face=%d+/(%d+)")) or 0
io.write(string.format("       [face contact: %d hits in 45s]\n", faceHits))
check(faceHits > 0, "flakes struck the eye sphere (got: " .. WP.describe() .. ")")

-- ---------------------------------------------------------------------------
-- 8. Rain still works, and its wet marks still deposit.
-- ---------------------------------------------------------------------------
-- `far()` was a nil global called on every rain particle every frame, which
-- aborted the shared pcall before draw ever ran. This is the regression guard.
WP.invalidate()
local rainWeather = { wxId = "RAIN", rainIntensity = 1.0, rainWind = 1.0 }
local okR, errR = pcall(function()
  for _ = 1, 120 do
    WP.update(1 / 60, focus, rainWeather)
    WP.draw(Voxel3D, { weather = rainWeather })
  end
end)
check(okR, "rain runs without error: " .. tostring(errR))

-- Rain parity with snow. Rain was left untouched through the snow rework as a
-- known-good reference; when it was finally measured the same way, it shared
-- snow's structural problems in milder form -- 1.41x radial density spread from
-- sampling uniformly in radius rather than in area, and a fixed drop budget
-- over a fixed disk that did not follow the rendered world.
do
  -- Warm to steady state, then measure across the WHOLE pool. An earlier
  -- version of this check polled WP.sample() -- 12 entries from the same pool
  -- indices -- and read 1.24x to 1.98x across warm-up lengths with no trend.
  -- That noise was nearly mistaken for a distribution bug in rain.
  for _ = 1, 1200 do
    WP.update(1 / 60, focus, rainWeather)
  end
  local RR = 220
  local d1 = WP.rainAreaDensity(focus[1], focus[3], 0, RR / 3)
  local d2 = WP.rainAreaDensity(focus[1], focus[3], RR / 3, 2 * RR / 3)
  local d3 = WP.rainAreaDensity(focus[1], focus[3], 2 * RR / 3, RR)
  local hi = math.max(d1, d2, d3)
  local lo = math.min(d1, d2, d3)
  local spread = hi / math.max(lo, 1e-9)
  io.write(string.format("       [rain density /1000u^2  inner %.2f  mid %.2f  outer %.2f  spread %.2fx]\n",
    d1, d2, d3, spread))
  local rr, perTile = WP.rainCoverage()
  io.write(string.format("       [rain coverage: r=%d, %.2f drops/tile]\n", rr, perTile))
  -- Uniform per-area sampling should hold this near 1.0. It does not reach
  -- exactly 1.0 because wind carries drops outward over their lifetime while
  -- rain culls at exactly the stream radius, so the outer band runs slightly
  -- rich.
  check(spread < 1.25,
    string.format("rain is spread evenly per unit area (%.2fx)", spread))
end

local rainActive = tonumber(WP.describe():match("rain=(%d+)")) or 0
check(rainActive > 0, "rain particles are active (got: " .. WP.describe() .. ")")

-- Rain must land and leave splashes, and must hit the lens in first person.
-- Snow had both from 4.28.69; rain had neither until 4.28.73, so a drop simply
-- vanished at the ground and never touched the camera.
do
  local Vx = { vp = {}, eye = { focus[1], focus[2] + 10, focus[3] }, far = 400 }
  -- Measure the DELTA, not the total. face=N/M is cumulative across the whole
  -- run, and the snow phase above has already put hits on the board -- so an
  -- absolute `> 0` check here passed happily with rain's lens contact disabled
  -- entirely. It was asserting on snow's hits.
  local faceBefore = tonumber(WP.describe():match("face=%d+/(%d+)")) or 0
  -- WINDOW SIZE IS LOAD-BEARING. Lens strikes are a Poisson process and this
  -- check was originally given 400 frames (6.7s). Measured over 12 trials, that
  -- window produced ZERO hits 3 times out of 12 -- a 25% chance of failing a
  -- correct build, and the source of the intermittent failure that held up
  -- 4.28.73. Hit counts per window, 400 frames: 2 3 2 0 1 0 2 1 3 0 2 3.
  -- At 1800 frames (30s) the same 12 trials gave 10 7 13 10 16 10 6 8 1 6 5 9
  -- and never zero. If this ever flakes again, lengthen the window -- do not
  -- weaken the assertion.
  for _ = 1, 1800 do
    WP.update(1 / 60, focus, rainWeather)
    WP.draw(Vx, { weather = rainWeather })
  end
  local d = WP.describe()
  local faceAfter = tonumber(d:match("face=%d+/(%d+)")) or 0
  check(faceAfter > faceBefore,
    string.format("rain strikes the lens in first person (%d -> %d)",
      faceBefore, faceAfter))
  -- Splashes live in the wet-mark pool; a nonzero active count means drops are
  -- reaching the ground plane and depositing there.
  -- Count IMPACTS, not pool occupancy. wetActive() is also fed by ambient
  -- scatter, so it stays nonzero with ground impacts deleted -- an earlier
  -- version of this check passed with exactly that mutation applied.
  check(WP.rainLanded() > 0,
    string.format("drops reach the ground and splash (%d impacts)", WP.rainLanded()))
end

-- ---------------------------------------------------------------------------
-- 9. Grains run: sand, ash and debris each spawn.
-- ---------------------------------------------------------------------------
-- spawnGrainAt was a nil global, so this whole family was dead.
for _, w in ipairs({
  { wxId = "SANDSTORM", sandIntensity = 1.45 },
  { wxId = "ASHFALL", ashIntensity = 1.10 },
  { wxId = "GALE", debrisIntensity = 1.15 },
}) do
  WP.invalidate()
  local okG, errG = pcall(function()
    for _ = 1, 60 do
      WP.update(1 / 60, focus, w)
      WP.draw(Voxel3D, { weather = w })
    end
  end)
  check(okG, w.wxId .. " runs without error: " .. tostring(errG))
  local g = tonumber(WP.describe():match("grain=(%d+)")) or 0
  check(g > 0, w.wxId .. " spawns grains (got: " .. WP.describe() .. ")")
end

-- ---------------------------------------------------------------------------
-- 10. Sand presentation is invariant to camera pitch.
-- ---------------------------------------------------------------------------
-- A shipped workaround treated "looking down" as a special voxel angle:
-- it raised sand farther above the floor, enlarged cards with distance, boosted
-- alpha and switched depth testing to ALWAYS. The exact same world-space sand
-- therefore became a dense screen layer when the player tilted the camera down.
-- Drawing the same frozen particle state from the same eye with two radically
-- different focus pitches must now produce identical submitted geometry and
-- must never request an always-pass depth mode.
do
  WP.invalidate()
  local sw = { wxId = "SANDSTORM", sandIntensity = 1.45 }
  for _ = 1, 30 do WP.update(1 / 60, focus, sw) end
  local eye = { focus[1], 10, focus[3] }

  depthModeCalls = {}
  lastUploadSignature = nil
  WP.draw({ vp={}, eye=eye, focus={focus[1] + 120, 10, focus[3]}, far=400 }, { weather=sw })
  local horizonSig = lastUploadSignature
  local horizonDepth = table.concat(depthModeCalls, ",")

  depthModeCalls = {}
  lastUploadSignature = nil
  WP.draw({ vp={}, eye=eye, focus={focus[1] + 4, -110, focus[3]}, far=400 }, { weather=sw })
  local downSig = lastUploadSignature
  local downDepth = table.concat(depthModeCalls, ",")

  check(horizonSig ~= nil and downSig ~= nil, "sand submits geometry at both camera pitches")
  check(horizonSig == downSig,
    "same frozen sand field submits identical world-space geometry at horizon and look-down pitch")
  check(not horizonDepth:find("always", 1, true) and not downDepth:find("always", 1, true),
    "sand never switches to always-pass depth when camera pitch changes")
end

-- ---------------------------------------------------------------------------
-- 11. The draw path stops allocating meshes once warm.
-- ---------------------------------------------------------------------------
-- This is the optimisation guard. The old path built a fresh mesh-sized table
-- of per-vertex tables every frame; the new one reuses a buffer and a VBO.
WP.invalidate()
meshesCreated = 0
for _ = 1, 90 do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end
local warmup = meshesCreated
meshesCreated = 0
for _ = 1, 300 do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end
check(meshesCreated <= 2,
  string.format("steady state creates no new meshes (warmup %d, then %d over 300 frames)",
    warmup, meshesCreated))

-- Mesh count alone does not prove the vertex path stopped churning: the old
-- code reused nothing and built a fresh 7-field table per vertex per frame. So
-- measure allocation directly. At the snow cap the old path produced ~25,200
-- tables a frame; anything in that region shows up immediately here.
collectgarbage("collect")
collectgarbage("collect")
local before = collectgarbage("count")
local FRAMES = 200
for _ = 1, FRAMES do
  WP.update(1 / 60, focus, weather)
  WP.draw(Voxel3D, { weather = weather })
end
local churn = (collectgarbage("count") - before) / FRAMES
io.write(string.format("       [draw+update churn: %.2f KB/frame]\n", churn))
-- Measured at the snow cap with this harness:
--   buffer reused (current)          0.09 KB/frame
--   fresh table per vertex (old)    21.95 KB/frame
-- 2.0 sits an order of magnitude above the real figure and an order of
-- magnitude below the regression, so it is neither flaky nor decorative. An
-- earlier draft of this check used 40 and sailed straight past the mutation --
-- a threshold that cannot fail is not a test.
check(churn < 2.0,
  string.format("steady-state allocation stays flat (%.2f KB/frame)", churn))

-- ---------------------------------------------------------------------------
-- 11. Quality budget is honoured (the require chain reaches the mod's Quality).
-- ---------------------------------------------------------------------------
local FullV = { require = V.require }
local potatoV = {
  require = function(name)
    if name == "Quality" then
      return { budget = function() return { worldPrecip = 0.28 } end }
    end
    return V.require(name)
  end,
}
local WPfull = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(FullV)
local WPpot = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(potatoV)
for _ = 1, 90 do
  WPfull.update(1 / 60, focus, weather)
  WPpot.update(1 / 60, focus, weather)
end
local nFull = tonumber(WPfull.describe():match("snow=(%d+)")) or 0
local nPot = tonumber(WPpot.describe():match("snow=(%d+)")) or 0
check(nPot > 0 and nPot < nFull,
  string.format("potato tier cuts the snow cap (%d vs %d)", nPot, nFull))

-- ---------------------------------------------------------------------------
-- 12. Third person takes no face hits.
-- ---------------------------------------------------------------------------
firstPersonFlag = false
local WPtp = assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)
for _ = 1, 240 do
  WPtp.update(1 / 60, focus, weather)
  WPtp.draw(Voxel3D, { weather = weather })
end
local tpFace = tonumber(WPtp.describe():match("face=%d+/(%d+)")) or -1
check(tpFace == 0, "no face specks outside first person (got " .. tpFace .. ")")
firstPersonFlag = true

-- ---------------------------------------------------------------------------
io.write(string.format("\n%d checks, %d failure(s)\n", checks, failures))
if failures > 0 then os.exit(1) end
