-- ============================================================================
-- WORLD-SPACE LIGHTNING
-- ============================================================================
-- Architecture rules, same family as WorldPrecip:
--   WORLD -> WEATHER STATE -> STRIKE EVENT -> a bolt at real world coordinates
--   The camera only VIEWS a strike. It never decides where one happens.
--   A strike is placed by world azimuth and distance from the player, and it
--   descends from the cloud deck to the ground at that spot.
--   If the player is facing the other way, they miss it. That is the point.
--
-- WHY THIS EXISTS
--
-- The existing lib/Lightning.lua is a SCREEN-SPACE system: makeBolt() picks a
-- hit point in view coordinates (`pickFarImpact(viewW, viewH)`), builds the bolt
-- in pixels, and draws it flat over the frame. It cannot be missed by looking
-- away, because it is drawn relative to the screen rather than the world -- and
-- in first person that reads as a 2D overlay stapled to the camera, which is
-- exactly what it is.
--
-- That system is NOT removed. It still runs the flash envelope, the strike
-- schedule and the thunder trigger (Audio fires off Lightning.justStruck), and
-- it is still the right thing for the flat 2D presentation. This module draws
-- the BOLT in the world for 3D presentations, and takes its timing from the
-- same clock so the two never disagree about when a strike happened.
--
-- WHAT "REAL" MEANS HERE, concretely:
--   * bolts are placed at a world azimuth and distance, mostly far, sometimes
--     close -- see STRIKE_RADIAL_BIAS;
--   * they descend from the cloud deck height, not from the top of the screen;
--   * they are visible only if they are in front of you. Turning around means
--     you see the flash on the clouds and miss the bolt, like real weather;
--   * the flash intensity falls off with distance, so a far strike lights the
--     sky faintly and a near one is blinding;
--   * thunder is not this module's job, but the strike distance is published
--     (see WL.lastStrike) so the delay between flash and clap can be driven
--     from it. Sound is late by ~3s per kilometre; a distant bolt should
--     rumble well after it is seen.
-- ============================================================================

local V = ...

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, random = math.sin, math.cos, math.random
local PI2 = math.pi * 2

local WL = {}

-- ---------------------------------------------------------------------------
-- TUNABLES
-- ---------------------------------------------------------------------------
local TILE = 16

-- How far out strikes can land. Follows the render distance like the
-- precipitation volume does, so a bolt never lands past the fog line where it
-- would be invisible, nor bunches into the near field.
local STRIKE_R_MIN = 90
local STRIKE_R_MAX = 900
local STRIKE_FAR_FRACTION = 0.92

-- Radial placement. Unlike snow, lightning should be MOSTLY DISTANT: a strike
-- landing next to the player every few seconds would be absurd. Sampling
-- radius as R * u^(1/BIAS) with BIAS < 1 pushes mass outward. At 0.55 roughly
-- three quarters of strikes land beyond half the draw radius, and close ones
-- still happen often enough to be startling.
local STRIKE_RADIAL_BIAS = 0.55
local NEAR_STRIKE_CHANCE = 0.12   -- ordinary storms: fraction deliberately close

-- Psychic Storm should feel enormous, not like lightning is repeatedly
-- detonating beside the player. Ordinary terrain strikes use a much more
-- distant distribution; NPC redirects are intentionally exempt because they
-- are explicit world targets governed by NpcLightning's independent 10% roll.
local PSY_MIN_RADIUS = 160
local PSY_NEAR_WEIGHT = 0.04
local PSY_MID_WEIGHT = 0.32

-- Bolt geometry.
local BOLT_SEGMENTS = 14
local BOLT_JAG = 0.16       -- lateral wander as a fraction of fall height
-- World units at the channel, tapering to the tip. Rendering a real 237-unit
-- strike showed 0.55 produced a hairline a pixel or two wide -- geometrically
-- correct and useless: a lightning channel reads as thick because of its glow,
-- not its physical width. Widened, with a stronger distance term so a far bolt
-- keeps presence instead of thinning to a thread.
local BOLT_WIDTH = 1.9
local FORK_CHANCE = 0.72
local _CloudField=nil
local function cloudChargeAt(x,z)
  if _CloudField==nil then local ok,m=pcall(V.require,"CloudField"); _CloudField=(ok and m) or false end
  if _CloudField and _CloudField.sampleAt then local ok,c=pcall(_CloudField.sampleAt,x,z); if ok and type(c)=="table" then return math.max(0,math.min(1,tonumber(c.charge) or 0)) end end
  return 0
end
local BOLT_LIFE = 0.42      -- seconds the channel is visible
local MAX_BOLTS = 4

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------
local bolts = {}            -- ring of live bolts
local boltCursor = 0
local simTime = 0
local lastFar = nil
local boltMesh, boltShader
local drawnBoltVerts = 0
local strikeCount = 0

WL.lastStrike = nil         -- { x, y, z, dist, at } of the most recent strike

-- ---------------------------------------------------------------------------
-- VERTEX BUFFER (same reuse discipline as WorldPrecip: no per-frame garbage)
-- ---------------------------------------------------------------------------
local BOLT_FMT = {
  { "VertexPosition", "float", 3 },
  { "BoltTint", "float", 4 },
}

local buf = { v = {}, cap = 0, n = 0 }

local function bufReset() buf.n = 0 end

local function bufReserve(n)
  for i = buf.cap + 1, n do buf.v[i] = { 0, 0, 0, 0, 0, 0, 0 } end
  if n > buf.cap then buf.cap = n end
end

local function bufPush(x, y, z, r, g, b, a)
  local n = buf.n + 1
  buf.n = n
  local t = buf.v[n]
  if t then
    t[1], t[2], t[3], t[4], t[5], t[6], t[7] = x, y, z, r, g, b, a
  else
    buf.v[n] = { x, y, z, r, g, b, a }
    buf.cap = n
  end
end

local meshCap = 0
local prefixUpload = nil

local function uploadMesh()
  local n = buf.n
  if n < 3 then return nil end
  if (not boltMesh) or meshCap < n then
    local want = floor(n * 1.4) + 128
    bufReserve(want)
    local ok, m = pcall(love.graphics.newMesh, BOLT_FMT, want, "triangles", "stream")
    if not ok or not m then return nil end
    boltMesh, meshCap = m, want
  end
  if prefixUpload ~= false then
    if pcall(boltMesh.setVertices, boltMesh, buf.v, 1, n) then
      prefixUpload = true
      pcall(boltMesh.setDrawRange, boltMesh, 1, n)
      return boltMesh
    end
    prefixUpload = false
  end
  local slice = {}
  for i = 1, n do slice[i] = buf.v[i] end
  if not pcall(boltMesh.setVertices, boltMesh, slice) then return nil end
  pcall(boltMesh.setDrawRange, boltMesh, 1, n)
  return boltMesh
end

-- ---------------------------------------------------------------------------
-- STRIKE PLACEMENT
-- ---------------------------------------------------------------------------
local _VoxelScene = nil
local function voxelScene()
  if _VoxelScene then return _VoxelScene end
  local ok, m = pcall(V.require, "VoxelScene")
  if ok and m then _VoxelScene = m end
  return _VoxelScene
end

local _RenderDistance = nil
local function renderDistance()
  if _RenderDistance ~= nil then return _RenderDistance or nil end
  local ok, m = pcall(V.require, "RenderDistance")
  _RenderDistance = (ok and m) or false
  return _RenderDistance or nil
end

local function mapCellDims(map)
  if not map then return 0, 0 end
  local w = tonumber(map.widthCells)
  local h = tonumber(map.heightCells)
  if (not w or w <= 0) and map.def then
    local bw = tonumber(map.def.width)
    if bw and bw > 0 then w = bw * 2 end
  end
  if (not h or h <= 0) and map.def then
    local bh = tonumber(map.def.height)
    if bh and bh > 0 then h = bh * 2 end
  end
  return max(0, floor(w or 0)), max(0, floor(h or 0))
end

local function captureFar(Voxel3D)
  if not Voxel3D then return end
  local f = tonumber(Voxel3D.far)
  if not f and Voxel3D.camera then f = tonumber(Voxel3D.camera.far) end
  if f and f > 80 then lastFar = f end
end

local function strikeRadius(context)
  local r = STRIKE_R_MAX
  if lastFar then r = lastFar * STRIKE_FAR_FRACTION end
  local RD = renderDistance()
  if RD and RD.radius and context and context.player then
    local ok, rr = pcall(RD.radius)
    if ok and tonumber(rr) and tonumber(rr) > 0 then r = min(r, tonumber(rr)) end
  end
  return max(STRIKE_R_MIN, min(STRIKE_R_MAX, r))
end

-- The rendered world is the current map plus the neighbour maps supplied by
-- VoxelScene.render. Keep strikes on those map surfaces instead of inventing a
-- screen-relative point. `ox/oz` are the exact world translations the host uses
-- when drawing neighbour terrain.
local function renderedRegions(map, neighbors)
  local out = {}
  local function add(one, ox, oz, label)
    local w, h = mapCellDims(one)
    if one and w > 0 and h > 0 then
      out[#out + 1] = { map=one, ox=ox or 0, oz=oz or 0,
        w=w, h=h, area=w*h, label=label or tostring(one.id or one) }
    end
  end
  add(map, 0, 0, "current")
  for i, nb in ipairs(neighbors or {}) do
    if nb and nb.map then add(nb.map, nb.ox or 0, nb.oy or 0, "neighbor:"..i) end
  end
  return out
end

local function groundAt(region, cx, cz)
  local gy = 0
  local VS = voxelScene()
  if VS and VS.groundAt then
    local ok, h = pcall(VS.groundAt, region.map, cx, cz)
    if ok and type(h) == "number" and h == h then gy = h end
  end
  -- Ground geometry starts exactly at this host height; lift a hair so the tip
  -- is not hidden by z fighting.
  return gy + 0.08
end

local function placementProfile(context)
  local id = type(context)=="table" and tostring(context.weatherId or ""):upper() or ""
  return id == "PSYSTORM" and "psystorm" or "default"
end

local function chooseZone(R, profile, forcedZone)
  if forcedZone == "near" or forcedZone == "mid" or forcedZone == "far" then return forcedZone end
  local u = random()
  if profile == "psystorm" then
    if u < PSY_NEAR_WEIGHT then return "near" end
    if u < PSY_NEAR_WEIGHT + PSY_MID_WEIGHT then return "mid" end
    return "far"
  end
  if u < 0.24 then return "near" end
  if u < 0.62 then return "mid" end
  return "far"
end

local function zoneBounds(zone, R, profile)
  if profile == "psystorm" then
    local floorR = min(R, PSY_MIN_RADIUS)
    if zone == "near" then return floorR, min(R, max(230, R * 0.34)) end
    if zone == "mid" then return min(R, max(230, R * 0.30)), min(R, max(460, R * 0.66)) end
    return min(R, max(460, R * 0.58)), R
  end
  if zone == "near" then return 45, min(R, max(90, R * 0.28)) end
  if zone == "mid" then return min(R, max(90, R * 0.20)), min(R, max(170, R * 0.62)) end
  return min(R, max(180, R * 0.48)), R
end

local function pickRegionWeighted(regions)
  local total = 0
  for i=1,#regions do total = total + (regions[i].area or 0) end
  if total <= 0 then return nil end
  local r = random() * total
  for i=1,#regions do
    r = r - (regions[i].area or 0)
    if r <= 0 then return regions[i] end
  end
  return regions[#regions]
end

local function candidateInRegion(region)
  local cx = floor(random() * region.w)
  local cz = floor(random() * region.h)
  if cx >= region.w then cx = region.w - 1 end
  if cz >= region.h then cz = region.h - 1 end
  -- Do not hit exactly at a tile seam every time. The strike still resolves to
  -- this cell's authoritative ground height.
  local wx = region.ox + cx * TILE + 2.5 + random() * 11.0
  local wz = region.oz + cz * TILE + 2.5 + random() * 11.0
  return wx, wz, cx, cz
end

local function separatedImpact(wx, wz, avoid, minSep)
  if type(avoid) ~= "table" or #avoid == 0 then return true end
  minSep = tonumber(minSep) or (TILE * 3)
  local min2 = minSep * minSep
  for i = 1, #avoid do
    local a = avoid[i]
    if a then
      local dx, dz = wx - (a[1] or a.x or 0), wz - (a[2] or a.z or 0)
      if dx * dx + dz * dz < min2 then return false end
    end
  end
  return true
end

local function mapImpact(px, pz, map, neighbors, R, player, avoid, profile, forcedZone)
  local regions = renderedRegions(map, neighbors)
  if #regions == 0 then return nil end
  local zone = chooseZone(R, profile, forcedZone)
  local r0, r1 = zoneBounds(zone, R, profile)
  local best, bestErr = nil, math.huge

  -- Random world cells across every rendered map. Sampling maps by cell area
  -- avoids making a tiny neighbour as likely as the entire current route.
  for _=1,72 do
    local region = pickRegionWeighted(regions)
    if region then
      local wx,wz,cx,cz = candidateInRegion(region)
      local dx,dz = wx-px, wz-pz
      local d = sqrt(dx*dx + dz*dz)
      local rendered = true
      local RD = renderDistance()
      if RD and RD.point and player then
        local ok, visible = pcall(RD.point, wx, wz, player)
        rendered = not ok or visible ~= false
      end
      local outsidePsyNearField = profile ~= "psystorm" or d + 1e-6 >= min(R, PSY_MIN_RADIUS)
      if rendered and outsidePsyNearField and separatedImpact(wx, wz, avoid, TILE * 3) then
        local err = 0
        if d < r0 then err = r0-d elseif d > r1 then err = d-r1 end
        if err < bestErr then
          bestErr = err
          best = {x=wx,z=wz,cx=cx,cz=cz,dist=d,region=region,zone=zone}
        end
        if err <= 0.001 then break end
      end
    end
  end
  if not best then return nil end
  best.y = groundAt(best.region, best.cx, best.cz)
  return best
end

local function radialImpact(px, py, pz, R, avoid, profile, forcedZone)
  local last
  for _ = 1, 24 do
    local ang = random() * PI2
    local rad, chosenZone
    if profile == "psystorm" then
      chosenZone = chooseZone(R, profile, forcedZone)
      local r0, r1 = zoneBounds(chosenZone, R, profile)
      if r1 < r0 then r0 = r1 end
      rad = r0 + (r1-r0) * (random() ^ 0.82)
    elseif random() < NEAR_STRIKE_CHANCE then
      rad = STRIKE_R_MIN * (0.35 + random() * 0.65)
    else
      rad = R * (random() ^ STRIKE_RADIAL_BIAS)
      if rad < STRIKE_R_MIN then rad = STRIKE_R_MIN + random() * 40 end
    end
    local wx, wz = px + cos(ang) * rad, pz + sin(ang) * rad
    last = {
      x = wx, y = py, z = wz, dist = rad,
      zone = chosenZone or (rad < 180 and "near" or (rad < 430 and "mid" or "far")),
      region = nil,
    }
    if separatedImpact(wx, wz, avoid, TILE * 3) then return last end
  end
  return last
end

--- Build one bolt as a world-space polyline from the LIVE cloud bank down to
--- the REAL voxel terrain at a random point on the currently rendered map set.
local function makeBolt(px, py, pz, deckY, context)
  context = type(context) == "table" and context or {}
  captureFar(context.Voxel3D)
  local R = strikeRadius(context)
  local profile = placementProfile(context)

  -- A caller may redirect this individual bolt to an already-validated live
  -- world target (Weather FX uses this for its rare visible-NPC gag). The
  -- override is deliberately tiny and generic: WorldLightning still owns the
  -- channel geometry, while target discovery remains outside this renderer.
  local hit
  local forced = context.forcedImpact
  if type(forced) == "table" and tonumber(forced.x) and tonumber(forced.y) and tonumber(forced.z) then
    local fx, fy, fz = tonumber(forced.x), tonumber(forced.y), tonumber(forced.z)
    local dx, dz = fx-px, fz-pz
    hit = {
      x=fx, y=fy, z=fz, lightY=tonumber(forced.lightY) or fy,
      dist=sqrt(dx*dx+dz*dz), zone=forced.zone or "forced",
      region={label=forced.region or "forced"},
      npcTarget=forced.npcTarget,
    }
  end
  hit = hit or mapImpact(px, pz, context.map, context.neighbors, R, context.player, context.avoidImpacts, profile, context.forcedZone)
      or radialImpact(px, py, pz, R, context.avoidImpacts, profile, context.forcedZone)

  local hx, hz = hit.x, hit.z
  local groundY = hit.y
  -- deckY is an ABSOLUTE world-Y band published by the cloud renderer. Older
  -- code added player/focus Y to it, which was only accidentally correct when
  -- focus Y happened to be zero.
  local span = max(0, tonumber(context.deckSpan) or 0)
  local topY = tonumber(deckY)
  if not topY then
    local scale=1.5
    local ok,S=pcall(V.require,"Settings")
    if ok and S and S.cloudHeightScale then scale=tonumber(S.cloudHeightScale()) or scale end
    topY=120*max(1.0,min(1.5,scale))
  end
  if span > 0 then topY = topY + span * (0.18 + random() * 0.64) end
  if topY < groundY + 35 then topY = groundY + 35 end

  -- Jagged descent. Each segment wanders laterally by a fraction of the drop,
  -- so the channel is ragged rather than a drawn zigzag of fixed amplitude.
  local pts = {}
  local n = BOLT_SEGMENTS
  local drop = topY - groundY
  local jag = drop * BOLT_JAG
  local sx = hx + (random() - 0.5) * jag * 1.6
  local sz = hz + (random() - 0.5) * jag * 1.6
  for i = 0, n do
    local t = i / n
    local w = jag * (1.0 - t) * (0.35 + random() * 0.65)
    local x = sx + (hx - sx) * t + (random() - 0.5) * w
    local z = sz + (hz - sz) * t + (random() - 0.5) * w
    local y = topY - drop * t
    pts[#pts + 1] = { x, y, z }
  end
  -- End point is exact terrain impact; start point remains in the cloud bank.
  pts[1] = { sx, topY, sz }
  pts[#pts] = { hx, groundY, hz }

  local forks = {}
  -- Cloud electrical charge enriches branching without changing the weather
  -- catalogue's strike frequency. Uncharged/default fields remain exactly at
  -- the historical 0.72 fork probability.
  local cloudCharge=cloudChargeAt(hx,hz)
  local forkChance=math.min(.94,FORK_CHANCE+cloudCharge*.18)
  if random() < forkChance then
    local start = 3 + floor(random() * (n - 6))
    if start < 1 then start = 1 end
    local base = pts[start] or pts[1]
    local fpts = { { base[1], base[2], base[3] } }
    local steps = 3 + floor(random() * 4)
    local dx = (random() - 0.5) * jag * 2.2
    local dz = (random() - 0.5) * jag * 2.2
    for i = 1, steps do
      local prev = fpts[#fpts]
      fpts[#fpts + 1] = {
        prev[1] + dx * (0.6 + random() * 0.8),
        prev[2] - drop / n * (0.7 + random() * 0.9),
        prev[3] + dz * (0.6 + random() * 0.8),
      }
    end
    forks[#forks + 1] = fpts
  end

  local dxp, dzp = hx - px, hz - pz
  local dist = sqrt(dxp * dxp + dzp * dzp)

  boltCursor = boltCursor % MAX_BOLTS + 1
  bolts[boltCursor] = {
    pts = pts, forks = forks,
    age = 0, life = BOLT_LIFE * (0.75 + random() * 0.6),
    x = hx, y = groundY, z = hz, dist = dist,
    lightY = tonumber(hit.lightY) or groundY,
    topX = sx, topY = topY, topZ = sz,
    zone = hit.zone or "unknown",
    region = hit.region and hit.region.label or "radial-fallback",
    cellX = hit.cx, cellZ = hit.cz,
    npcTarget = hit.npcTarget,
    seed = random(),
    power = (1.0+cloudCharge*.18) / (1.0 + (dist / 260) * (dist / 260)),
    cloudCharge = cloudCharge,
  }
  strikeCount = strikeCount + 1
  WL.lastStrike = {
    x=hx, y=groundY, z=hz, topX=sx, topY=topY, topZ=sz,
    dist=dist, zone=bolts[boltCursor].zone, region=bolts[boltCursor].region,
    cellX=hit.cx, cellZ=hit.cz, at=simTime,
  }
  return bolts[boltCursor]
end

--- Fire a strike now. Context may carry the current map/neighbour set and the
--- live voxel API; if present the impact is guaranteed onto that rendered world.
function WL.strike(focus, deckY, context)
  if not focus then return nil end
  return makeBolt(focus[1] or 0, focus[2] or 0, focus[3] or 0, deckY, context)
end

--- Fire a simultaneous severe-storm cluster. Every bolt is allocated in the
--- same simulation frame but receives its own independently sampled world-map
--- target, cloud origin, terrain impact, forks, power and distance. MAX_BOLTS
--- is four, so a burst can never overrun the live ring.
function WL.strikeBurst(focus, deckY, context, count)
  if not focus then return {} end
  count = math.max(1, math.min(MAX_BOLTS, math.floor(tonumber(count) or 1)))
  context = type(context) == "table" and context or {}
  local out, used = {}, {}
  local profile = placementProfile(context)
  for i = 1, count do
    local burstContext = {}
    for k, v in pairs(context) do burstContext[k] = v end
    burstContext.avoidImpacts = used
    -- Psychic Storm clusters are intentionally distributed across the visible
    -- world instead of allowing several ordinary terrain bolts to pile into
    -- the player's near field. Explicit NPC redirects still take priority.
    if profile == "psystorm" then
      local bands = { "far", "mid", "far", "far" }
      burstContext.forcedZone = bands[i] or "far"
    end
    -- Optional per-bolt target chooser. A nil return means normal map terrain.
    if type(context.forcedImpactForBolt) == "function" then
      local ok, forced = pcall(context.forcedImpactForBolt, i, used)
      if ok then burstContext.forcedImpact = forced end
    end
    local b = makeBolt(focus[1] or 0, focus[2] or 0, focus[3] or 0, deckY, burstContext)
    if b then
      out[#out + 1] = b
      used[#used + 1] = {b.x, b.z}
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- UPDATE
-- ---------------------------------------------------------------------------
function WL.update(dt, focus, weather)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 end
  if dt > 0.1 then dt = 0.1 end
  simTime = simTime + dt
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then b.age = b.age + dt end
  end
end

--- Combined flash from every live bolt, 0..1, distance-weighted. The host can
--- add this to its scene lighting so a strike lights the world rather than just
--- drawing a bright line in it.
function WL.flash()
  local f = 0
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then
      local t = b.age / b.life
      -- Sharp attack, ragged decay: real strikes flicker as the channel
      -- re-ionises rather than fading smoothly.
      -- No attack ramp. Lightning is instantaneous -- it is at full brightness
      -- on the frame it strikes and decays from there. An earlier version eased
      -- in over 0.06 of the life, which made flash() read 0.000 at the moment
      -- of the strike: the brightest instant was the one that emitted no light.
      local env = (1 - t) * (1 - t)
      local flicker = 0.72 + 0.28 * sin((b.seed + t) * 47.0)
      f = max(f, env * flicker * b.power)
    end
  end
  return min(1, f)
end

function WL.active()
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then return true end
  end
  return false
end


--- Active localized world lights for WorldLighting. These are the exact same
--- strikes as the bolt geometry, so illumination can never drift away from the
--- visible channel or become camera-relative.
function WL.lights()
  local out = {}
  for i=1,MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then
      local t = b.age / b.life
      local env = (1-t) * (1-t)
      local flicker = 0.72 + 0.28 * sin((b.seed + t) * 47.0)
      out[#out+1] = {
        x=b.x,y=b.lightY or b.y,z=b.z, topX=b.topX,topY=b.topY,topZ=b.topZ,
        dist=b.dist,power=b.power,zone=b.zone,region=b.region,
        intensity=max(0, min(1, env*flicker)),
      }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- DRAW
-- ---------------------------------------------------------------------------
local function getBoltShader()
  if boltShader ~= nil then return boltShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    boltShader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, [[
#ifdef VERTEX
  extern mat4 vp;
  attribute vec4 BoltTint;
  varying vec4 vCol;
  vec4 position(mat4 t, vec4 v) {
    vCol = BoltTint;
    return vp * vec4(v.xyz, 1.0);
  }
#endif
#ifdef PIXEL
  varying vec4 vCol;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // .g is across-ribbon; a hot white core inside a blue-white glow.
    float across = 1.0 - abs(vCol.g * 2.0 - 1.0);
    float core = pow(across, 8.0);
    float glow = across * across;
    vec3 rgb = mix(vec3(0.62, 0.72, 1.0), vec3(1.0, 1.0, 1.0), core);
    float a = vCol.a * (glow * 0.55 + core);
    return vec4(rgb, a) * color;
  }
#endif
]])
  boltShader = (ok and sh) or false
  return boltShader or nil
end

--- Emit one polyline as a camera-facing ribbon.
local function emitRibbon(pts, ex, ey, ez, alpha, width)
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local ax, ay, az = a[1], a[2], a[3]
    local bx, by, bz = b[1], b[2], b[3]
    -- Ribbon faces the eye: right = segmentDir x toEye.
    local sx, sy, sz = bx - ax, by - ay, bz - az
    local tx, ty, tz = ex - ax, ey - ay, ez - az
    local rx = sy * tz - sz * ty
    local ry = sz * tx - sx * tz
    local rz = sx * ty - sy * tx
    local rl = sqrt(rx * rx + ry * ry + rz * rz)
    if rl > 1e-5 then
      rx, ry, rz = rx / rl, ry / rl, rz / rl
      -- Taper: the channel is fattest aloft and narrows toward the tip.
      local t0 = (i - 1) / max(1, #pts - 1)
      local t1 = i / max(1, #pts - 1)
      local w0 = width * (1.0 - t0 * 0.55)
      local w1 = width * (1.0 - t1 * 0.55)
      local a1x, a1y, a1z = ax - rx * w0, ay - ry * w0, az - rz * w0
      local a2x, a2y, a2z = ax + rx * w0, ay + ry * w0, az + rz * w0
      local b1x, b1y, b1z = bx - rx * w1, by - ry * w1, bz - rz * w1
      local b2x, b2y, b2z = bx + rx * w1, by + ry * w1, bz + rz * w1
      bufPush(a1x, a1y, a1z, 1, 0, 0, alpha)
      bufPush(a2x, a2y, a2z, 1, 1, 0, alpha)
      bufPush(b2x, b2y, b2z, 1, 1, 1, alpha)
      bufPush(a1x, a1y, a1z, 1, 0, 0, alpha)
      bufPush(b2x, b2y, b2z, 1, 1, 1, alpha)
      bufPush(b1x, b1y, b1z, 1, 0, 1, alpha)
    end
  end
end

function WL.draw(Voxel3D)
  if not (Voxel3D and Voxel3D.vp) then return end
  local f = Voxel3D.far or (Voxel3D.camera and Voxel3D.camera.far)
  if type(f) == "number" and f > 80 then lastFar = f end
  local eye = Voxel3D.eye
  if not eye then return end
  local ex, ey, ez = eye[1] or 0, eye[2] or 0, eye[3] or 0

  bufReset()
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then
      local t = b.age / b.life
      local env = (1 - t) * (1 - t)
      -- Re-strike flicker: the channel visibly stutters instead of fading.
      local flick = 0.55 + 0.45 * sin((b.seed * 31.0) + t * 41.0)
      local alpha = env * flick
      if alpha > 0.02 then
        -- Width in world units, scaled a little with distance so a far bolt
        -- does not thin to a sub-pixel thread and vanish.
        local w = BOLT_WIDTH * (1.0 + b.dist / 170)
        emitRibbon(b.pts, ex, ey, ez, alpha, w)
        for k = 1, #b.forks do
          emitRibbon(b.forks[k], ex, ey, ez, alpha * 0.55, w * 0.5)
        end
      end
    end
  end

  drawnBoltVerts = buf.n
  if buf.n < 3 then return end
  local mesh = uploadMesh()
  if not mesh then return end

  local sh = getBoltShader()
  pcall(love.graphics.setBlendMode, "add", "alphamultiply")
  -- Depth-tested so a bolt behind world geometry is occluded by it, but no depth write:
  -- the channel is light, not geometry.
  pcall(love.graphics.setDepthMode, "lequal", false)
  local began = false
  if Voxel3D.beginEffect and sh then began = Voxel3D.beginEffect(sh) end
  if sh then
    if not began then pcall(love.graphics.setShader, sh) end
    pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
    pcall(sh.send, sh, "vp", Voxel3D.vp)
  end
  pcall(love.graphics.setColor, 1, 1, 1, 1)
  pcall(love.graphics.draw, mesh)
  if Voxel3D.endEffect then pcall(Voxel3D.endEffect)
  else pcall(love.graphics.setShader) end
  pcall(love.graphics.setBlendMode, "alpha", "alphamultiply")
  pcall(love.graphics.setDepthMode, "lequal", true)
end

function WL.clear()
  for i = 1, MAX_BOLTS do bolts[i] = nil end
  drawnBoltVerts = 0
  WL.lastStrike = nil
end

function WL.invalidate()
  WL.clear()
  boltMesh, boltShader = nil, nil
  meshCap, prefixUpload = 0, nil
end

--- True when bolt geometry was actually emitted last frame. The 2D lightning
--- overlay is suppressed on this basis, exactly as the 2D snow and rain sheets
--- are -- report what happened, never what was intended.
function WL.drawingBolt()
  return drawnBoltVerts >= 3
end

function WL.describe()
  local live = 0
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b and b.age < b.life then live = live + 1 end
  end
  local d = WL.lastStrike and WL.lastStrike.dist or -1
  return string.format("wl bolts=%d/%d verts=%d strikes=%d lastDist=%.0f flash=%.2f",
    live, MAX_BOLTS, drawnBoltVerts, strikeCount, d, WL.flash())
end

--- For the test suite: the live bolts' impact points and distances.
function WL.sample()
  local out = {}
  for i = 1, MAX_BOLTS do
    local b = bolts[i]
    if b then
      out[#out + 1] = { x = b.x, y = b.y, z = b.z, dist = b.dist,
                        topX=b.topX, topY=b.topY, topZ=b.topZ,
                        zone=b.zone, region=b.region, cellX=b.cellX, cellZ=b.cellZ,
                        npcHit = b.npcTarget ~= nil, lightY=b.lightY,
                        age = b.age, life = b.life, power = b.power,
                        pts = #b.pts, forks = #b.forks }
    end
  end
  return out
end

function WL.tune(t)
  if type(t) ~= "table" then return false end
  if tonumber(t.bias) then STRIKE_RADIAL_BIAS = max(0.1, tonumber(t.bias)) end
  if tonumber(t.nearChance) then NEAR_STRIKE_CHANCE = max(0, min(1, tonumber(t.nearChance))) end
  if tonumber(t.width) then BOLT_WIDTH = max(0.05, tonumber(t.width)) end
  if tonumber(t.life) then BOLT_LIFE = max(0.05, tonumber(t.life)) end
  if tonumber(t.maxRadius) then STRIKE_R_MAX = max(120, tonumber(t.maxRadius)) end
  return true
end

return WL
