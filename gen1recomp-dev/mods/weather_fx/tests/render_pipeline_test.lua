-- Executable 2D/3D weather pipeline audit.
--
-- This is intentionally a behavioural release test, not a source grep. It
-- proves that every falling particle family can spawn and reach a draw
-- submission, that mixed 3D families coexist (the regression that removed
-- leaves), and that 3D ownership fails closed when a draw pass breaks.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]*$") or "./"
local checks, failures = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    io.write("FAIL: ", msg, "\n")
  end
end

math.randomseed(4311)

-- -------------------------------------------------------------------------
-- 2D Particles: real module, mocked LÖVE SpriteBatch.
-- -------------------------------------------------------------------------
local batchAdds, drawCalls = 0, 0
local function install2DLove()
  batchAdds, drawCalls = 0, 0
  love = {
    math = { random = math.random },
    image = {
      newImageData = function()
        return { setPixel = function() end }
      end,
    },
    graphics = {
      newImage = function()
        return { setFilter = function() end }
      end,
      newSpriteBatch = function()
        return {
          clear = function() batchAdds = 0 end,
          setColor = function() end,
          add = function() batchAdds = batchAdds + 1 end,
        }
      end,
      setBlendMode = function() end,
      setColor = function() end,
      draw = function() drawCalls = drawCalls + 1 end,
    },
  }
end

local function newParticles()
  install2DLove()
  local P = assert(loadfile(ROOT .. "lib/Particles.lua"))({})
  P.setRect(160, 144, 1)
  return P
end

local budget = { rain=48, snow=48, grain=240, splash=24 }
local twoD = {
  rain   = { rain=1, rainSpeed=1, rainAngle=0, rainLen=1, splash=0.2 },
  snow   = { snow=1, snowSpeed=1, snowDrift=0.6 },
  hail   = { hail=1 },
  sand   = { sand=1 },
  debris = { debris=1 },
  ash    = { ash=1 },
}
for name, ch in pairs(twoD) do
  local P = newParticles()
  local ok, err = pcall(function()
    P.update(1/60, ch, budget, 0.4, 0, 0, true)
    P.draw(1, ch)
  end)
  check(ok, "2D " .. name .. " update/draw executes: " .. tostring(err))
  local r, s, g = P.counts()
  if name == "rain" then check(r > 0, "2D rain spawns")
  elseif name == "snow" then check(s > 0, "2D snow spawns")
  else
    check(g > 0, "2D " .. name .. " grains spawn")
    local kc = P.kindCounts()
    if name == "hail" then check((kc[1] or 0) > 0, "2D hail kind is active") end
    if name == "sand" then check((kc[2] or 0) > 0, "2D sand kind is active") end
    if name == "debris" then check((kc[3] or 0) > 0, "2D debris/leaves kind is active") end
    if name == "ash" then
      check((kc[4] or 0) + (kc[5] or 0) == g, "2D ash keeps full declared grain density")
      check((kc[4] or 0) > 0 and (kc[5] or 0) > 0, "2D ash contains gray and black flakes")
    end
  end
  check(batchAdds > 0 and drawCalls > 0, "2D " .. name .. " submits SpriteBatch geometry")
end

-- Rain impact animation: prove splashes are not merely allocated but become
-- live at multiple depths of the top-down playfield.  The fixed random seed
-- makes this deterministic while still exercising the real landing path.
do
  local P = newParticles()
  P.spread = 1.0
  local ch = { rain=1, rainSpeed=2.2, rainAngle=0, rainLen=1, splash=1 }
  for _ = 1, 420 do P.update(1/60, ch, budget, 0, 0, 0, true) end
  local live, bands = 0, {}
  local _,_,_,slots = P.counts()
  for i = 1, slots do
    local y = P.splashY(i)
    if y then
      live = live + 1
      bands[math.floor(y / 144 * 5)] = true
    end
  end
  local nBands = 0; for _ in pairs(bands) do nBands = nBands + 1 end
  check(live > 0, "2D rain produces live landing splashes")
  check(nBands >= 2, "2D rain splashes land across the top-down world, not one screen edge")
end

-- The actual weather catalogue must drive those same 2D families. This catches
-- a definition that declares an animation but cannot reach the shared renderer.
do
  local Types2D = assert(loadfile(ROOT .. "lib/Types.lua"))({})
  for _, id in ipairs(Types2D.ids()) do
    local def = Types2D.get(id)
    local ch = {}
    for k, v in pairs(def.ch or {}) do ch[k] = v end
    ch.rainSpeed, ch.rainAngle, ch.rainLen = ch.rainSpeed or 1, ch.rainAngle or 0, ch.rainLen or 1
    ch.snowSpeed, ch.snowDrift = ch.snowSpeed or 1, ch.snowDrift or 0.6
    local P = newParticles()
    P.update(1/60, ch, budget, ch.gust or 0, 0, 0, true)
    P.draw(1, ch)
    local r, sn, g = P.counts()
    if Types2D.channel(def, "rain") > 0.02 then check(r > 0, id .. " 2D rain channel spawns") end
    if Types2D.channel(def, "snow") > 0.02 then check(sn > 0, id .. " 2D snow channel spawns") end
    local kc = P.kindCounts()
    if Types2D.channel(def, "hail") > 0.02 then check((kc[1] or 0) > 0, id .. " 2D hail channel spawns") end
    if Types2D.channel(def, "sand") > 0.02 then check((kc[2] or 0) > 0, id .. " 2D sand channel spawns") end
    if Types2D.channel(def, "debris") > 0.02 then check((kc[3] or 0) > 0, id .. " 2D debris channel spawns") end
    if Types2D.channel(def, "ash") > 0.02 then check(((kc[4] or 0)+(kc[5] or 0)) > 0, id .. " 2D ash channel spawns") end
  end
  local hailDef = Types2D.get("HAIL")
  check(Types2D.channel(hailDef, "snow") == 0, "HAIL means hail in both 2D and 3D; it does not secretly add snowflakes")
end

-- -------------------------------------------------------------------------
-- 3D WorldPrecip: real module, mocked mesh/shader API.
-- -------------------------------------------------------------------------
local currentShader, failLeafCompile, failLeafDraw, failAllDraw, failRichCompile = nil, false, false, false, false
local meshDrawCalls = 0
local selectedLeafColor, selectedSnowShape = "green", "flake"
local shaderUses, leafPassColor = {}, nil
local function install3DLove()
  currentShader, meshDrawCalls = nil, 0
  shaderUses, leafPassColor = {}, nil
  love = {
    graphics = {
      newMesh = function(fmt, cap)
        local m = { cap=type(cap)=="number" and cap or #cap }
        function m:setVertices(verts, startv, count)
          local n = count or #verts
          if n > self.cap then error("mesh overflow") end
        end
        function m:setDrawRange() end
        return m
      end,
      newShader = function(src)
        local kind = "other"
        if src:find("0.72 + 0.28 * vCol.r", 1, true) then kind = "cardFallback"
        elseif src:find("float halfW", 1, true) then kind = "leaf"
        elseif src:find("float across = 1.0 - abs", 1, true) then kind = "rain"
        elseif src:find("Dendrite snowflake", 1, true) then kind = "snowFlake"
        elseif src:find("float d = dot(p, p);", 1, true) then kind = "snowBall" end
        if kind == "leaf" and failLeafCompile then error("forced leaf shader compile failure") end
        if failRichCompile and kind ~= "rain" and kind ~= "cardFallback" then error("forced non-rain shader compile failure") end
        return { _kind=kind, send=function() end }
      end,
      setBlendMode = function() end,
      setDepthMode = function() end,
      setShader = function(sh)
        currentShader = sh
        if sh and sh._kind then shaderUses[sh._kind] = (shaderUses[sh._kind] or 0) + 1 end
      end,
      setColor = function(r,g,b,a)
        if currentShader and currentShader._kind == "leaf" and r and g and b
            and not (r == 1 and g == 1 and b == 1) then
          leafPassColor = {r,g,b,a}
        end
      end,
      draw = function()
        if failAllDraw then error("forced draw failure") end
        if failLeafDraw and currentShader and currentShader._kind == "leaf" then
          error("forced leaf draw failure")
        end
        meshDrawCalls = meshDrawCalls + 1
      end,
    },
  }
end

local function newWP(q)
  install3DLove()
  local V = {}
  function V.require(name)
    if name == "Quality" then return { budget=function() return { worldPrecip=q or 0.025 } end } end
    if name == "Settings" then
      return {
        isFirstPerson=function() return true end,
        snowShape=function() return selectedSnowShape end,
        leafColor=function() return selectedLeafColor end,
      }
    end
    error("no module " .. tostring(name), 0)
  end
  return assert(loadfile(ROOT .. "lib/voxel_atmos/WorldPrecip.lua"))(V)
end

local focus = { 0, 0, 0 }
local voxel = { vp={}, eye={0,8,0}, focus={0,8,40}, player=focus, far=260 }
local function exercise3D(name, weather, expectedKinds)
  local WP = newWP(0.025)
  local ok, err = pcall(function()
    for _ = 1, 12 do
      WP.update(1/60, focus, weather)
      WP.draw(voxel, {weather=weather})
    end
  end)
  check(ok, "3D " .. name .. " update/draw executes: " .. tostring(err))
  local status = WP.grainStatus()
  for _, k in ipairs(expectedKinds or {}) do
    local key = ({[1]="hail",[2]="sand",[3]="debris",[4]="ash"})[k]
    check(status[key].target > 0, "3D " .. name .. " requests " .. key)
    check(status[key].verts > 0, "3D " .. name .. " submits " .. key .. " geometry")
    check(WP.drawingGrain(k), "3D " .. name .. " reports " .. key .. " as actually drawn")
  end
  check(WP.drawingAllRequested(), "3D " .. name .. " owns 2D fallback only after all requested families draw")
  return WP
end

exercise3D("hail", {wxId="HAIL", hailIntensity=0.7}, {1})
exercise3D("sand", {wxId="SANDSTORM", sandIntensity=0.7}, {2})
exercise3D("leaves", {wxId="GALE", debrisIntensity=0.7}, {3})
exercise3D("ash", {wxId="ASHFALL", ashIntensity=0.7}, {4})
exercise3D("mixed sand + leaves", {wxId="DRAGONSTORM", sandIntensity=0.55, debrisIntensity=0.45}, {2,3})
exercise3D("sandstorm debris mix", {wxId="SANDSTORM", sandIntensity=0.65, debrisIntensity=0.25}, {2,3})

-- User-facing 3D appearance settings must reach the actual shader/draw path,
-- not merely return the right helper value.
do
  local expected = {
    green={0.30,0.58,0.22}, yellow={0.78,0.68,0.18},
    orange={0.82,0.42,0.14}, brown={0.48,0.30,0.14},
  }
  for name, base in pairs(expected) do
    selectedLeafColor = name
    local WP = newWP(0.025)
    local w = {wxId="GALE", debrisIntensity=0.8}
    for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
    check(WP.drawingLeaves(), "LEAF COLOR " .. name .. " keeps the 3D leaf pass alive")
    local c = leafPassColor
    local ratioOK = c and c[1] > 0 and math.abs((c[2]/c[1]) - (base[2]/base[1])) < 0.08
                     and math.abs((c[3]/c[1]) - (base[3]/base[1])) < 0.08
    check(ratioOK, "LEAF COLOR " .. name .. " changes the real 3D leaf draw tint")
  end
  selectedLeafColor = "green"

  for _, shape in ipairs({"flake","ball"}) do
    selectedSnowShape = shape
    local WP = newWP(0.025)
    local w = {wxId="SNOW_LIGHT", snowIntensity=1.0, snowWind=0.7}
    for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
    local key = shape == "ball" and "snowBall" or "snowFlake"
    check((shaderUses[key] or 0) > 0, "SNOW SHAPE " .. shape .. " selects its real 3D shader")
    check(WP.drawingSnow(), "SNOW SHAPE " .. shape .. " still submits 3D snow geometry")
  end
  selectedSnowShape = "flake"
end

-- Optional torture test. Enable with WX_RENDER_STRESS=1 for the synthetic
-- all-family allocator/upload pressure test; normal release gates keep this
-- disabled so nested audit runs remain deterministic and bounded.
if os.getenv("WX_RENDER_STRESS") == "1" then
  -- Simultaneous-family stress: exercise the allocator/upload path at every
  -- shipped 3D quality scale with all precipitation families requested together.
  -- This is intentionally synthetic; it is a capacity/guard test, not a weather
  -- preset. No tier may overflow a mesh or lose a family when pressure rises.
  for _, q in ipairs({1.00, 0.70, 0.45, 0.28}) do
    local WP = newWP(q)
    local w = {wxId="DRAGONSTORM", rainIntensity=2.4, snowIntensity=2.4,
               hailIntensity=1.2, sandIntensity=2.4, debrisIntensity=2.0,
               ashIntensity=1.4, rainWind=1, snowWind=1}
    local ok, err = pcall(function()
      for _ = 1, 24 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
    end)
    check(ok, string.format("3D quality scale %.2f survives mixed-family stress: %s", q, tostring(err)))
    check(WP.drawingRain(), string.format("3D quality scale %.2f keeps rain alive", q))
    check(WP.drawingSnow(), string.format("3D quality scale %.2f keeps snow alive", q))
    for k = 1, 4 do
      check(WP.drawingGrain(k), string.format("3D quality scale %.2f keeps grain family %d alive", q, k))
    end
    check(WP.drawingAllRequested(), string.format("3D quality scale %.2f proves all mixed families", q))
  end

end

-- Rain and snow use their own pools but participate in the same ownership gate.
do
  local WP = newWP(0.025)
  local w = {wxId="RAIN_LIGHT", rainIntensity=0.8, rainWind=1}
  for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
  check(WP.drawingRain(), "3D rain submits geometry")
  check(WP.drawingAllRequested(), "3D rain satisfies all-requested ownership")
end
do
  local WP = newWP(0.025)
  local w = {wxId="SNOW_LIGHT", snowIntensity=1.0, snowWind=0.7}
  for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
  check(WP.drawingSnow(), "3D snow submits geometry")
  check(WP.drawingAllRequested(), "3D snow satisfies all-requested ownership")
end

-- 8.1.4 FPV rain regression.  Several current voxel hosts use `focus` as a
-- player/world anchor rather than a camera look target.  A first-person eye is
-- above that anchor, so treating eye->focus as forward points down and can cull
-- every cloud-bank rain streak.  The real horizontal `lookFlat` must win.
do
  local fpvVoxel = { vp={}, eye={0,12,0}, focus={0,0,0}, player=focus, lookFlat={0,0,1}, far=260 }
  local WP = newWP(0.025)
  local w = {wxId="RAIN_LIGHT", rainIntensity=0.8, rainWind=1}
  for _ = 1, 12 do WP.update(1/60, focus, w, {anchorKind="player",deckY=96,deckSpan=22}); WP.draw(fpvVoxel, {weather=w}) end
  local st = WP.drawStatus()
  check((st.rain.verts or 0) > 0, "FPV rain ignores downward player-anchor focus and submits visible 3D geometry")
  check(WP.drawingRain(), "FPV rain owns the 2D fallback only after a healthy 3D submission")
  check(WP.drawingAllRequested(), "FPV manual rain satisfies strict-3D ownership")
end

-- If a host supplies no trustworthy camera heading at all, skip CPU rear-cull
-- rather than guessing from a vertical focus.  The GPU can safely clip rear
-- geometry; losing the whole rain field is not an acceptable optimization.
do
  local ambiguousVoxel = { vp={}, eye={0,12,0}, focus={0,0,0}, player=focus, far=260 }
  local WP = newWP(0.025)
  local w = {wxId="RAIN_LIGHT", rainIntensity=0.8, rainWind=1}
  for _ = 1, 12 do WP.update(1/60, focus, w, {anchorKind="player",deckY=96,deckSpan=22}); WP.draw(ambiguousVoxel, {weather=w}) end
  local st = WP.drawStatus()
  check((st.rain.verts or 0) > 0, "ambiguous vertical focus disables CPU rain rear-cull instead of erasing cloud-bank rain")
  check(WP.drawingRain(), "ambiguous-focus rain remains a real submitted 3D pass")
end
do
  local rearVoxel = { vp={}, eye={0,8,1000}, focus={0,8,1040}, player=focus, far=260 }
  local WP = newWP(0.025)
  local w = {wxId="SNOW_LIGHT", snowIntensity=1.0, snowWind=0.7}
  for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(rearVoxel, {weather=w}) end
  check(WP.drawingSnow(), "rear-culled healthy 3D snow still owns the 2D fallback")
  check(WP.drawingAllRequested(), "rear-culled healthy snow does not resurrect 2D overlay")
end
for _, case in ipairs({
  {"hail", 1, {wxId="HAIL", hailIntensity=0.8}},
  {"sand", 2, {wxId="SANDSTORM", sandIntensity=0.8}},
  {"leaves", 3, {wxId="GALE", debrisIntensity=0.8}},
  {"ash", 4, {wxId="ASHFALL", ashIntensity=0.8}},
}) do
  local rearVoxel = { vp={}, eye={0,8,1000}, focus={0,8,1040}, player=focus, far=260 }
  local WP = newWP(0.025)
  for _ = 1, 12 do WP.update(1/60, focus, case[3]); WP.draw(rearVoxel, {weather=case[3]}) end
  local status = WP.grainStatus()
  local key = ({[1]="hail",[2]="sand",[3]="debris",[4]="ash"})[case[2]]
  check(status[key].verts > 0, "host focus direction cannot erase 3D " .. case[1] .. " geometry")
  check(WP.drawingGrain(case[2]), "3D " .. case[1] .. " remains healthy when focus is not a trustworthy view ray")
  check(WP.drawingAllRequested(), "3D " .. case[1] .. " keeps ownership under ambiguous host focus")
end

-- Rain/snow ownership must also be based on a successful draw submission, not
-- on vertex intent. Force the host draw call to fail and prove 2D remains live.
do
  failAllDraw = true
  local WP = newWP(0.025)
  local w = {wxId="RAIN_LIGHT", rainIntensity=0.8, rainWind=1}
  for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
  check(not WP.drawingRain(), "forced 3D rain draw failure is detected")
  check(not WP.drawingAllRequested(), "forced 3D rain draw failure keeps 2D fallback enabled")
  failAllDraw = false
end
do
  failAllDraw = true
  local WP = newWP(0.025)
  local w = {wxId="SNOW_LIGHT", snowIntensity=1.0, snowWind=0.7}
  for _ = 1, 12 do WP.update(1/60, focus, w); WP.draw(voxel, {weather=w}) end
  check(not WP.drawingSnow(), "forced 3D snow draw failure is detected")
  check(not WP.drawingAllRequested(), "forced 3D snow draw failure keeps 2D fallback enabled")
  failAllDraw = false
end

-- Every grain family must also fail closed. A renderer that proves this only
-- for leaves can still silently delete hail/sand/ash after a host draw error.
for _, case in ipairs({
  {"hail", 1, {wxId="HAIL", hailIntensity=0.8}},
  {"sand", 2, {wxId="SANDSTORM", sandIntensity=0.8}},
  {"leaves", 3, {wxId="GALE", debrisIntensity=0.8}},
  {"ash", 4, {wxId="ASHFALL", ashIntensity=0.8}},
}) do
  failAllDraw = true
  local WP = newWP(0.025)
  for _ = 1, 12 do WP.update(1/60, focus, case[3]); WP.draw(voxel, {weather=case[3]}) end
  check(not WP.drawingGrain(case[2]), "forced 3D " .. case[1] .. " draw failure is detected")
  check(not WP.drawingAllRequested(), "forced 3D " .. case[1] .. " failure keeps its 2D fallback enabled")
  failAllDraw = false
end

-- Leaf shader failure must degrade to a compatible shader, not delete leaves.
do
  failLeafCompile = true
  local WP = newWP(0.025)
  -- install3DLove reset does not change flags.
  local w = {wxId="GALE", debrisIntensity=0.8}
  WP.update(1/60, focus, w); WP.draw(voxel, {weather=w})
  check(WP.drawingLeaves(), "3D leaves fall back when the leaf shader cannot compile")
  failLeafCompile = false
end

-- Host/GLES fallback: if every richer non-rain shader fails to compile, the
-- rain-proven shared card layout + neutral fallback must keep every family visible.
do
  failRichCompile = true
  for _, c in ipairs({
    {"snow", -1, {wxId="SNOW_LIGHT", snowIntensity=1.0}},
    {"hail", 1, {wxId="HAIL", hailIntensity=0.8}},
    {"sand", 2, {wxId="SANDSTORM", sandIntensity=0.8}},
    {"leaves", 3, {wxId="GALE", debrisIntensity=0.8}},
    {"ash", 4, {wxId="ASHFALL", ashIntensity=0.8}},
  }) do
    local WP = newWP(0.025)
    WP.update(1/60, focus, c[3]); WP.draw(voxel, {weather=c[3]})
    local ok = c[2] == -1 and WP.drawingSnow() or WP.drawingGrain(c[2])
    check(ok, "3D " .. c[1] .. " survives specialized shader compile failure")
    check((shaderUses.cardFallback or 0) > 0 or (shaderUses.rain or 0) > 0,
          "3D " .. c[1] .. " reaches a host-compatible fallback shader")
  end
  failRichCompile = false
end

-- A real draw failure must revoke 3D ownership so 2D stays visible.
do
  failLeafDraw = true
  local WP = newWP(0.025)
  local w = {wxId="GALE", debrisIntensity=0.8}
  WP.update(1/60, focus, w); WP.draw(voxel, {weather=w})
  check(not WP.drawingLeaves(), "forced 3D leaf draw failure is detected")
  check(not WP.drawingAllRequested(), "forced 3D leaf draw failure keeps 2D fallback enabled")
  WP.markDrawFailed()
  check(not WP.drawingAllRequested(), "markDrawFailed revokes stale 3D ownership")
  failLeafDraw = false
end

-- -------------------------------------------------------------------------
-- Dramaless bridge ownership: behavioural fail-closed check.
-- -------------------------------------------------------------------------
do
  local Settings = {
    isFirstPerson=function() return true end,
    force2dPresent=function() return false end,
    allow3dPresent=function() return true end,
  }
  local V = { mod={} }
  function V.require(name)
    if name == "Settings" then return Settings end
    error("unexpected require " .. tostring(name), 0)
  end
  local Atmos = assert(loadfile(ROOT .. "lib/DramalessAtmos.lua"))(V)
  Atmos._active, Atmos._drawing = true, true
  local requested = false
  Atmos._ns = { require=function(name)
    if name == "WorldPrecip" then
      return {
        immersiveCamera=function() return true end,
        drawingAllRequested=function() return requested end,
      }
    end
  end }
  check(not Atmos.handlesAllPrecipitation(), "3D bridge does not suppress 2D before draw proof")
  requested = true
  check(Atmos.handlesAllPrecipitation(), "3D bridge suppresses 2D after draw proof")
  Atmos._ns = nil
  check(not Atmos.handlesAllPrecipitation(), "missing 3D namespace fails closed to 2D")
  Atmos._ns = { require=function() error("forced namespace failure") end }
  check(not Atmos.handlesAllPrecipitation(), "3D query error fails closed to 2D")
end

-- -------------------------------------------------------------------------
-- Draw compositor ownership: execute the real per-family filter.
-- -------------------------------------------------------------------------
do
  local owners = { rain=false, snow=false, hail=false, sand=false, debris=false, ash=false }
  local force2d = false
  local Scene = { now={visible="world"} }
  local Settings = {
    force2dPresent=function() return force2d end,
    isFirstPerson=function() return true end,
  }
  local Bridge = {
    handlesPrecipitation=function() return owners.rain end,
    handlesSnow=function() return owners.snow end,
    handlesGrains=function(kind)
      return ({[1]=owners.hail,[2]=owners.sand,[3]=owners.debris,[4]=owners.ash})[kind] or false
    end,
    handlesAllPrecipitation=function() return false end,
    handlesLightning=function() return false end,
    handlesFog=function() return false end,
  }
  local generic = setmetatable({}, {__index=function() return function() return false end end})
  local DV = {}
  function DV.require(name)
    if name == "Scene" then return Scene end
    if name == "Settings" then return Settings end
    if name == "VoxelAtmosBridge" then return Bridge end
    if name == "Config" then return {visual=function() return true end} end
    if name == "Particles" then return {ready=function() return true end} end
    if name == "WeatherState" then return {channels={}} end
    if name == "TimeOfDay" then return {} end
    if name == "BattleDraw" then return {} end
    return generic
  end
  local D = assert(loadfile(ROOT .. "lib/Draw.lua"))(DV)
  local all = {rain=1,snow=1,hail=1,sand=1,debris=1,ash=1}
  local function filt() return D._filter2dPrecipChannels(all) end

  local out = filt()
  check(out.rain == 1 and out.snow == 1 and out.debris == 1,
        "2D safety families remain when no 3D family has draw proof")

  owners.rain = true
  out = filt()
  check(out.rain == 0 and out.snow == 1,
        "mixed rain+snow suppresses only proven 3D rain; failed snow stays 2D")

  owners.sand = true
  out = filt()
  check(out.sand == 0 and out.debris == 1,
        "mixed sand+leaves suppresses proven 3D sand but keeps failed leaves 2D")

  owners.debris = true
  out = filt()
  check(out.sand == 0 and out.debris == 0,
        "mixed sand+leaves suppresses both only after both 3D families prove draw")

  owners.hail, owners.ash, owners.snow = true, true, true
  out = filt()
  check(out.rain == 0 and out.snow == 0 and out.hail == 0 and out.sand == 0
        and out.debris == 0 and out.ash == 0,
        "all six families independently suppress after successful 3D submissions")

  force2d = true
  out = filt()
  check(out.rain == 1 and out.snow == 1 and out.hail == 1 and out.sand == 1
        and out.debris == 1 and out.ash == 1,
        "WX PRESENT forced 2D restores every 2D precipitation family")
  force2d = false
  Scene.now.visible = "battle"
  out = filt()
  check(out.rain == 1 and out.snow == 1 and out.hail == 1 and out.sand == 1
        and out.debris == 1 and out.ash == 1,
        "battle compositor never loses families to overworld 3D ownership")
end

-- -------------------------------------------------------------------------
-- Fog/lightning ownership is health-based and fails closed.
-- -------------------------------------------------------------------------
do
  local Settings = {
    isFirstPerson=function() return true end,
    force2dPresent=function() return false end,
    allow3dPresent=function() return true end,
  }
  local V = { mod={} }
  function V.require(name)
    if name == "Settings" then return Settings end
    error("unexpected require " .. tostring(name), 0)
  end
  local Atmos = assert(loadfile(ROOT .. "lib/DramalessAtmos.lua"))(V)
  Atmos._active, Atmos._drawing = true, true
  local fogDrawn, lightningHealthy = false, false
  Atmos._cin = {
    fogDrawing=function() return fogDrawn end,
    passHealthy=function(tag) return tag == "world-lightning" and lightningHealthy end,
  }
  check(not Atmos.handlesFog(), "3D fog does not suppress 2D before real mist draw proof")
  fogDrawn = true
  check(Atmos.handlesFog(), "3D fog suppresses 2D only after mist geometry draws")
  fogDrawn = false
  check(not Atmos.handlesFog(), "3D fog failure immediately restores 2D fog")
  check(not Atmos.handlesLightning(), "3D lightning does not suppress 2D before healthy pass")
  lightningHealthy = true
  check(Atmos.handlesLightning(), "healthy 3D lightning pass owns the 2D bolt")
  lightningHealthy = false
  check(not Atmos.handlesLightning(), "3D lightning failure restores the 2D bolt path")
end

-- -------------------------------------------------------------------------
-- Cinematic 3D fog/lightning: actual draw submission proof.
-- -------------------------------------------------------------------------
do
  local fogDrawCalls, failAtmosDraw, failWorldLightning = 0, false, false
  local cloudsOn = true
  local burstCalls, burstCountSeen = 0, 0
  local publishedSerial, publishedDistances = nil, nil
  local lightningState = {strikeSerial=0, burstCount=1}
  function lightningState.publishWorldStrikeBatch(serial, distances)
    publishedSerial, publishedDistances = serial, distances
    return true
  end
  love = { graphics = {
    newShader=function() return {send=function() end} end,
    newMesh=function()
      local m = {}
      function m:setVertices() end
      function m:setVertexMap() end
      function m:setDrawRange() end
      return m
    end,
    draw=function()
      if failAtmosDraw then error("forced atmospheric draw failure") end
      fogDrawCalls = fogDrawCalls + 1
    end,
    setBlendMode=function() end, setDepthMode=function() end,
    setShader=function() end, setColor=function() end,
    getDimensions=function() return 640, 480 end,
  }}
  local Settings = {
    sandIntensity=function() return 1 end, dustIntensity=function() return 1 end,
    fogIntensity=function() return 1 end, fogOff=function() return false end,
    intensity=function() return 1 end,
    get=function(key) if key == "lightning" then return "full" end return "off" end,
    isFirstPerson=function() return true end, snowShape=function() return "flake" end,
    leafColor=function() return "green" end, cloudsOn=function() return cloudsOn end,
  }
  local Forest = {time=1, RAMP={day={fog={0.8,0.8,0.8}, ray={1,1,1}}}}
  local Day = {isCanopy=function() return false end, isNight=function() return false end,
               time=function() return 12 end, mix=function() return {day=1} end,
               tint=function() return {1,1,1} end, strengthAt=function() return 1 end,
               bodyAt=function() return 0,45,false end}
  local WP = {update=function() end, draw=function() end, markDrawFailed=function() end}
  local WL = {
    update=function() if failWorldLightning then error("forced world lightning failure") end end,
    draw=function() end,
    strike=function() return {pts={0,0,1,1},dist=180} end,
    strikeBurst=function(_,_,_,count)
      burstCalls=burstCalls+1; burstCountSeen=count
      return {{dist=100},{dist=450},{dist=900},{dist=700}}
    end,
  }
  local Vox = {
    focus={0,0,40}, eye={0,8,-40}, player={0,0,40}, far=260,
    vp={0.002,0,0,0, 0,0.002,0,0, 0,0,0.002,0, 0,0,0,1},
    lookFlat={0,0,1}, camera={up={0,1,0}},
    size=function() return 640,480 end,
    beginEffect=function() return true end, endEffect=function() end,
  }
  local generic = {}
  local CV = {mod={id="weather_fx", options={get=function() return nil end}}}
  function CV.require(name)
    if name == "Voxel3D" then return Vox end
    if name == "Settings" then return Settings end
    if name == "ForestAtmos" then return Forest end
    if name == "DayNight" then return Day end
    if name == "WorldPrecip" then return WP end
    if name == "WorldLightning" then return WL end
    if name == "Lightning" then return lightningState end
    if name == "WeatherSetting" then
      return {new=function() return {get=function() return "full" end} end}
    end
    if name == "Types" then return assert(loadfile(ROOT .. "lib/Types.lua"))({}) end
    if name == "TimeOfDay" then return {hour=12,isNight=function() return false end} end
    return generic
  end
  local Cin = assert(loadfile(ROOT .. "lib/voxel_atmos/CinematicAtmos.lua"))(CV)
  local frameWxId = "FOG"
  Cin.frame = function()
    return {level=1,wxId=frameWxId,canopy=false,
      weather={coverage=0.82,cloudShade=1,motes=1,wxId=frameWxId},
      fogColor={0.8,0.8,0.8},rayColor={1,0.95,0.8},mistWind={1,0},
      wind={0,0},lightIntensity=0}
  end
  local ok, err = pcall(Cin.draw, {}, true, nil, nil)
  check(ok, "3D cinematic atmosphere draw executes under headless renderer: " .. tostring(err))
  check(fogDrawCalls > 0 and Cin.fogDrawing(),
        "3D fog ownership requires and receives actual mist/roll-fog draw submission")
  check(Cin.passHealthy("world-lightning"),
        "3D lightning health is proven by an executed WorldLightning update/draw pass")

  frameWxId = "STORM"
  lightningState.strikeSerial = 1
  lightningState.burstCount = 4
  pcall(Cin.draw, {}, true, nil, nil)
  check(burstCalls == 1 and burstCountSeen == 4,
        "CinematicAtmos turns one severe-storm scheduler event into four simultaneous world bolts")
  check(publishedSerial == 1 and type(publishedDistances) == "table" and #publishedDistances == 4,
        "CinematicAtmos publishes every generated world-bolt distance to shared Lightning audio authority")
  check(publishedDistances and publishedDistances[1] == 100 and publishedDistances[3] == 900,
        "published thunder distances preserve the actual per-bolt world geometry")

  local cloudCount, cloudDrawn = Cin.cloudStatus()
  check(cloudCount > 0 and cloudDrawn,
        "CLOUDS ON builds real world descriptors into the active shared particle/cloud mesh")
  cloudsOn = false
  pcall(Cin.draw, {}, true, nil, nil)
  cloudCount, cloudDrawn = Cin.cloudStatus()
  check(cloudCount == 0 and not cloudDrawn,
        "CLOUDS OFF removes cloud descriptors from the active 3D shared mesh")
  cloudsOn = true

  failAtmosDraw, fogDrawCalls = true, 0
  pcall(Cin.draw, {}, true, nil, nil)
  check(not Cin.fogDrawing(), "forced 3D fog draw failure revokes fog ownership")
  failAtmosDraw = false

  failWorldLightning = true
  pcall(Cin.draw, {}, true, nil, nil)
  check(not Cin.passHealthy("world-lightning"),
        "forced WorldLightning failure revokes lightning ownership")
end

-- -------------------------------------------------------------------------
-- CinematicAtmos grain-driver matrix: run the real frame() mapping.
-- -------------------------------------------------------------------------
do
  local Types = assert(loadfile(ROOT .. "lib/Types.lua"))({})
  local settingV = { mod={ id="weather_fx", options={get=function() return nil end} } }
  local WeatherSetting = assert(loadfile(ROOT .. "lib/voxel_atmos/WeatherSetting.lua"))(settingV)
  local DayNight = {
    isCanopy=function() return false end,
    isNight=function() return false end,
    time=function() return 12 end,
    mix=function() return {day=1} end,
  }
  local ForestAtmos = {
    time=0,
    RAMP={ day={fog={0.78,0.86,0.76}, ray={1.0,0.93,0.72}} },
  }
  local Settings = {
    intensity=function() return 1 end,
    sandIntensity=function() return 1 end,
    dustIntensity=function() return 1 end,
    fogIntensity=function() return 1 end,
    fogOff=function() return false end,
  }
  local CV = { mod=settingV.mod }
  function CV.require(name)
    if name == "DayNight" then return DayNight end
    if name == "ForestAtmos" then return ForestAtmos end
    if name == "WeatherSetting" then return WeatherSetting end
    if name == "ShadowMap" or name == "TileShape" or name == "Sky"
        or name == "Mat4" or name == "SpriteBillboards" or name == "TerrainAtlas" then return {} end
    if name == "Types" then return Types end
    if name == "Settings" then return Settings end
    if name == "TimeOfDay" then return {hour=12, isNight=function() return false end} end
    if name == "WorldPrecip" then return {} end
    if name == "CelestialBodies" then return {} end
    error("no cinematic module " .. tostring(name), 0)
  end
  local Cin = assert(loadfile(ROOT .. "lib/voxel_atmos/CinematicAtmos.lua"))(CV)
  local Atmos = assert(loadfile(ROOT .. "lib/DramalessAtmos.lua"))({mod={}, require=function() return {} end})
  Atmos._active, Atmos._drawing, Atmos._cin = true, true, Cin
  local mapField = { hail="hailIntensity", sand="sandIntensity", ash="ashIntensity", debris="debrisIntensity" }
  for _, id in ipairs(Types.ids()) do
    local def = Types.get(id)
    Atmos.syncFromWeatherFx({id=id, level=1})
    local frame = Cin.frame({}, true)
    check(frame ~= nil, "3D cinematic frame builds for " .. id)
    if frame then
      for ch, field in pairs(mapField) do
        if Types.channel(def, ch) > 0.02 then
          check((tonumber(frame.weather[field]) or 0) > 0.02,
            id .. " declares " .. ch .. " and feeds 3D " .. field)
        end
      end
      if id=="RAIN_HEAVY" or id=="HEAVY_RAIN" or id=="STORM" then
        check(frame.weather._mistVisual==false,
          id .. " rain-only storm does not inherit the cinematic ground-mist overlay")
      end
    end
  end
end


-- -------------------------------------------------------------------------
-- Full catalogue -> REAL WorldPrecip execution matrix.  The mapping checks
-- above prove CinematicAtmos writes the drivers; this proves those exact
-- drivers survive the next module boundary and actually submit geometry.
-- -------------------------------------------------------------------------
do
  local Types = assert(loadfile(ROOT .. "lib/Types.lua"))({})
  local settingV = { mod={ id="weather_fx", options={get=function() return nil end} } }
  local WeatherSetting = assert(loadfile(ROOT .. "lib/voxel_atmos/WeatherSetting.lua"))(settingV)
  local DayNight = {
    isCanopy=function() return false end, isNight=function() return false end,
    time=function() return 12 end, mix=function() return {day=1} end,
  }
  local ForestAtmos = { time=0, RAMP={ day={fog={0.78,0.86,0.76}, ray={1,0.93,0.72}} } }
  local Settings = {
    intensity=function() return 1 end, sandIntensity=function() return 1 end,
    dustIntensity=function() return 1 end, fogIntensity=function() return 1 end,
    fogOff=function() return false end,
  }
  local CV = { mod=settingV.mod }
  function CV.require(name)
    if name == "DayNight" then return DayNight end
    if name == "ForestAtmos" then return ForestAtmos end
    if name == "WeatherSetting" then return WeatherSetting end
    if name == "Types" then return Types end
    if name == "Settings" then return Settings end
    if name == "TimeOfDay" then return {hour=12,isNight=function() return false end} end
    if name == "WorldPrecip" or name == "CelestialBodies" then return {} end
    if name == "ShadowMap" or name == "TileShape" or name == "Sky"
        or name == "Mat4" or name == "SpriteBillboards" or name == "TerrainAtlas" then return {} end
    error("no full-matrix module " .. tostring(name), 0)
  end
  local Cin = assert(loadfile(ROOT .. "lib/voxel_atmos/CinematicAtmos.lua"))(CV)
  local Atmos = assert(loadfile(ROOT .. "lib/DramalessAtmos.lua"))({mod={}, require=function() return {} end})
  Atmos._active, Atmos._drawing, Atmos._cin = true, true, Cin
  local grainMap = { hail={"hailIntensity",1}, sand={"sandIntensity",2},
                     debris={"debrisIntensity",3}, ash={"ashIntensity",4} }
  for _, id in ipairs(Types.ids()) do
    local def = Types.get(id)
    Atmos.syncFromWeatherFx({id=id, level=1})
    local frame = Cin.frame({}, true)
    check(frame ~= nil, id .. " reaches a real 3D weather frame")
    if frame then
      local WP = newWP(0.025)
      for _ = 1, 12 do
        WP.update(1/60, focus, frame.weather)
        WP.draw(voxel, frame)
      end
      local requested = false
      if Types.channel(def, "rain") > 0.02 then
        requested = true; check(WP.drawingRain(), id .. " catalogue rain reaches a successful 3D draw")
      end
      if Types.channel(def, "snow") > 0.02 then
        requested = true; check(WP.drawingSnow(), id .. " catalogue snow reaches a successful 3D draw")
      end
      for ch, meta in pairs(grainMap) do
        if Types.channel(def, ch) > 0.02 then
          requested = true
          check((tonumber(frame.weather[meta[1]]) or 0) > 0.02, id .. " feeds " .. ch .. " across CinematicAtmos boundary")
          check(WP.drawingGrain(meta[2]), id .. " catalogue " .. ch .. " reaches a successful 3D draw")
        end
      end
      if requested then
        check(WP.drawingAllRequested(), id .. " proves every requested 3D precipitation family before taking 2D ownership")
      end
    end
  end
end

-- -------------------------------------------------------------------------
-- 2D compositor layer execution: grade/fog/veil/precip/psy/glare/lightning.
-- These channels have very different blend/state paths; prove each live path
-- reaches a draw API instead of relying on source-level consumer checks.
-- -------------------------------------------------------------------------
do
  local rects, meshes, worldFogCalls, fogCalls, groundFogCalls = 0, 0, 0, 0, 0
  local particleCalls, lightningCalls, funnelCalls = 0, 0, 0
  love = { math={random=math.random}, graphics={
    getColor=function() return 1,1,1,1 end, getBlendMode=function() return "alpha","alphamultiply" end,
    setBlendMode=function() end, setColor=function() end, push=function() end, pop=function() end,
    translate=function() end, rectangle=function() rects=rects+1 end,
    newMesh=function() return {setVertices=function() end} end,
    draw=function() meshes=meshes+1 end,
  }}
  local mods = {}
  mods.Scene = {now={visible="world",indoors=false,camX=0,camY=0}}
  mods.WeatherState = {id="PSYSTORM",elapsed=5,
    ch={rain=0.8,rainSpeed=1,rainAngle=0,rainLen=1,splash=1,fog=0.7,fogSpeed=0.5,
        veil=0.45,dim=0.3,cool=0.2,warm=0.1,psy=0.8,glare=0.5,strike=0.5},
    isFogWeather=function() return true end}
  mods.Settings = {
    get=function(k) if k=="lightning" then return "full" end return "on" end,
    force2dPresent=function() return true end, fogOff=function() return false end,
    fogIntensity=function() return 1 end, intensity=function() return 1 end,
    isFirstPerson=function() return false end,
  }
  mods.Config = {visual=function() return true end}
  mods.Quality = {budget=function() return {fogLayers=3} end,tier=function() return "high" end}
  mods.Particles = {ready=function() return true end,setRect=function() end,draw=function() particleCalls=particleCalls+1 end}
  mods.Lightning = {flash=function() return 0.15 end,draw=function() lightningCalls=lightningCalls+1 end,age=0}
  mods.Fog = {ready=function() return true end,draw=function() fogCalls=fogCalls+1 end,
              drawGround=function() groundFogCalls=groundFogCalls+1 end,
              drawWorldField=function() worldFogCalls=worldFogCalls+1 end,
              setTint=function() end,resetTint=function() end}
  mods.Audio = {}
  mods.TimeOfDay = {grade=function() return nil end}
  mods.BattleDraw = {live=false}
  mods.Legendary = {boltTint=function() return nil end}
  mods.Funnel = {draw=function() funnelCalls=funnelCalls+1; return true end}
  mods.Rainbow = {}
  mods.Types = assert(loadfile(ROOT .. "lib/Types.lua"))({})
  local DV = {}
  function DV.require(name) if mods[name] then return mods[name] end error("optional "..tostring(name),0) end
  local Draw = assert(loadfile(ROOT .. "lib/Draw.lua"))(DV)
  local ok,err=pcall(Draw.pass,0,0,640,480,4,1,true)
  check(ok,"2D full compositor executes all active layer families: "..tostring(err))
  check(worldFogCalls>0 and fogCalls==0 and groundFogCalls==0,
        "2D haze submits through world-wrapped banks, not viewport/ground overlays")
  check(particleCalls>0,"2D precipitation layer submits")
  check(lightningCalls==1,"2D lightning layer submits exactly once")
  check(funnelCalls==1,"2D/world tornado layer submits exactly once")
  check(meshes>0,"2D glare mesh submits")
  check(rects>=2,"2D grade/psychic wash produce compositing rectangles without a haze veil")

  -- Fail two optional helpers in one frame. They must be isolated so the rest
  -- of the compositor still draws rather than the engine retiring WEATHER.
  mods.Fog.drawWorldField=function() error("forced fog helper failure") end
  mods.Lightning.draw=function() error("forced lightning helper failure") end
  particleCalls, funnelCalls = 0, 0
  local okFail,errFail=pcall(Draw.pass,0,0,640,480,4,1,true)
  check(okFail,"2D helper failures are isolated from the whole compositor: "..tostring(errFail))
  check(particleCalls>0,"2D rain still renders when fog helper fails")
  check(funnelCalls==1,"tornado still renders when lightning helper fails")
end

-- Real Funnel module lifecycle: active animation draws, survives a hitch, and
-- fires its completion callback only after its own bounded clock.
do
  local rects=0
  love={math={random=math.random},graphics={
    getColor=function() return 1,1,1,1 end,getBlendMode=function() return "alpha","alphamultiply" end,
    setBlendMode=function() end,setColor=function() end,rectangle=function() rects=rects+1 end,
  }}
  local F=assert(loadfile(ROOT.."lib/Funnel.lua"))({})
  local done=false
  F.start(0.5,function() done=true end)
  check(F.active and not done,"real tornado funnel starts before its carry callback")
  check(F.draw(0,0,640,480,4)==true and rects>20,"real tornado funnel submits column + debris geometry")
  F.update(5)
  check(F.active and not done,"tornado hitch clamp prevents instant warp")
  for _=1,40 do F.update(1/60) end
  check(not F.active and done,"tornado funnel completes and then fires its carry callback")
end

-- -------------------------------------------------------------------------
-- Tornado compositor ownership: full-frame exactly once, never precip-only.
-- -------------------------------------------------------------------------
do
  local funnelDraws = 0
  love = { graphics = {
    getColor=function() return 1,1,1,1 end,
    getBlendMode=function() return "alpha", "alphamultiply" end,
    setBlendMode=function() end, setColor=function() end,
    rectangle=function() end, push=function() end, pop=function() end,
    translate=function() end,
  }}
  local mods = {}
  mods.Scene = {now={visible="overworld", indoors=false, camX=0, camY=0}}
  mods.WeatherState = {id="CLEAR", elapsed=0, ch={}}
  mods.Settings = {
    get=function() return "off" end,
    force2dPresent=function() return true end,
    fogOff=function() return true end,
  }
  mods.Config = {visual=function() return false end}
  mods.Quality = {budget=function() return {fogLayers=1} end}
  mods.Particles = {ready=function() return false end, setRect=function() end}
  mods.Lightning = {flash=function() return 0 end, draw=function() end, age=-1}
  mods.Fog = {ready=function() return false end}
  mods.Audio = {}
  mods.TimeOfDay = {grade=function() return nil end}
  mods.BattleDraw = {live=false}
  mods.Legendary = {boltTint=function() return nil end}
  mods.Funnel = {draw=function() funnelDraws = funnelDraws + 1; return true end}
  mods.Rainbow = {}
  mods.Types = assert(loadfile(ROOT .. "lib/Types.lua"))({})
  local DV = {}
  function DV.require(name)
    if mods[name] then return mods[name] end
    error("optional module unavailable: " .. tostring(name), 0)
  end
  local Draw = assert(loadfile(ROOT .. "lib/Draw.lua"))(DV)
  local ok, err = pcall(Draw.pass, 0, 0, 640, 480, 4, 1, false)
  check(ok, "normal full-frame compositor executes tornado path: " .. tostring(err))
  check(funnelDraws == 1, "tornado funnel draws exactly once from normal full-frame compositor")
  local ok2, err2 = pcall(Draw.passPrecipitationOnly, 0, 0, 640, 480, 4, 1)
  check(ok2, "precipitation-only compositor executes without tornado: " .. tostring(err2))
  check(funnelDraws == 1, "precipitation-only/dialog clipping pass never duplicates or clips tornado funnel")
end

io.write(string.format("render pipeline audit: %d passed, %d failed\n", checks - failures, failures))
if failures > 0 then os.exit(1) end
