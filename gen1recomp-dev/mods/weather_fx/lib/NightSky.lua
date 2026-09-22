-- NightSky — celestial sphere for Weather FX (Dramaless / Potato / Gen2).
--
-- Architecture (do not break this model):
--   • Each star has a FIXED unit direction D in world space (permanent home).
--   • D is generated once; never regenerated from player position or camera.
--   • Render position = camera_eye + D * SKY_RADIUS (translation only).
--   • Orientation comes solely from Voxel3D.vp (view-projection).
--   • Camera rotation changes which part of the sphere is visible.
--   • Camera translation does not create parallax (sphere is re-centered).
--
-- Stars are drawn BEFORE volumetric clouds so weather occludes them.

local V = ...
local safe = (V.safeBind and V.safeBind("NightSky")) or pcall
local Constellations
local Aurora
safe(function() Constellations = V.require("Constellations") end)
safe(function() Aurora = V.require("Aurora") end)
local NightSky = {}

NightSky._DayNight = nil
NightSky._FirstPerson = nil
NightSky._Voxel = nil
NightSky._TOD = nil
NightSky.DEBUG = false  -- set true for marker star + basis dump

-- ---------------------------------------------------------------------------
-- Night detection
-- ---------------------------------------------------------------------------
function NightSky.isNight(body)
  if body and body.moon then return true end
  local TOD = NightSky._TOD
  if not TOD then
    safe(function()
      if V and V.require then TOD = V.require("TimeOfDay") end
    end)
    NightSky._TOD = TOD
  end
  if TOD then
    if TOD.hostMode == "night" then return true end
    if TOD.pin == "NITE" or TOD.pin == "NIGHT" then return true end
    if TOD.tod == "NITE" or TOD.tod == "NIGHT" then return true end
    if TOD.isNight and TOD.isNight() then return true end
    if type(TOD.hour) == "number" then
      local h = TOD.hour % 24
      if h >= 20 or h < 4 then return true end
    end
    -- Explicit day pins only block when host is also not night.
    if TOD.pin == "DAY" or TOD.pin == "MORN" then
      -- still allow Dramaless DayNight night below
    elseif TOD.tod == "MORN" or TOD.tod == "DAY" or TOD.tod == "EVE" then
      -- fall through to host DayNight check
    end
    if type(TOD.daylight) == "function" then
      local ok, d = safe(TOD.daylight)
      if ok and type(d) == "number" and d < 0.12 then return true end
    end
  end
  -- Dramaless / host voxel DayNight (primary for 3D outdoor night)
  local DN = NightSky._DayNight
  if DN then
    if DN.isNight and type(DN.isNight) == "function" then
      local ok, n = safe(DN.isNight)
      if ok and n then return true end
    end
    if type(DN.time) == "function" and DN.bodyAt then
      local ok, tt = safe(DN.time)
      if ok and type(tt) == "number" then
        local ok2, th, el, moon = safe(DN.bodyAt, tt)
        if ok2 and moon then return true end
      end
    end
    if type(DN.mix) == "function" and type(DN.time) == "function" then
      local ok, tt = safe(DN.time)
      if ok then
        local ok2, mix = safe(DN.mix, tt)
        if ok2 and type(mix) == "table" then
          local n = (mix.night or 0) + (mix.nite or 0)
          if n > 0.45 then return true end
        end
      end
    end
  end
  if package.loaded and package.loaded._WX_NIGHT then return true end
  return false
end

-- Stars always attempt at night (top-down may still depth-occlude).
function NightSky.skyVisible(_Voxel3D)
  return true
end

-- ---------------------------------------------------------------------------
-- Continuous celestial visibility (alpha only — fixed star directions never
-- change). CelestialEngine derives visibility from real solar altitude, cloud
-- cover and light pollution. DAY/NITE pins remain explicit hard overrides.
-- ---------------------------------------------------------------------------
NightSky._nightVis = 0
NightSky._nightVisRaw = 0

local function smoothstep(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

--- Global star visibility 0..1 from astronomical twilight + environment.
function NightSky.computeNightVisibility()
  local TOD=NightSky._TOD
  if not TOD then safe(function() TOD=V.require("TimeOfDay") end); NightSky._TOD=TOD end
  local pin=TOD and TOD.pin
  if pin=="DAY" then return 0 end
  -- NITE/NIGHT pins force astronomical time, not clear skies. CelestialEngine
  -- still owns weather/cloud transmission so stars and planets remain correctly
  -- hidden behind the live cloud bank instead of popping back to full alpha.
  local ok,E=safe(V.require,"CelestialEngine")
  if ok and E and E.state then
    local ok2,st=safe(E.state)
    if ok2 and st and type(st.starVisibility)=="number" then return clamp01(st.starVisibility) end
  end
  local okS,Sim=safe(V.require,"CelestialSim")
  if okS and Sim and Sim.sample then
    local ok2,st=safe(Sim.sample,TOD and TOD.hour or nil)
    if ok2 and st then
      return clamp01(tonumber(st.starVisibility) or 0)
    end
  end
  return NightSky.isNight(nil) and 1 or 0
end

function NightSky.starFade(s, globalVis)
  globalVis = tonumber(globalVis) or 0
  if globalVis <= 0.001 then return 0 end
  if globalVis >= 0.999 then return 1 end
  return clamp01(globalVis)
end

--- Twinkle multiplier for alpha only (never changes celestial direction D).
--- Combines a primary and secondary sine so the field does not pulse in unison.
-- Twinkle is evaluated for thousands of stars every frame at MAX. A 4096-entry
-- sine table removes ~13k libm calls/frame while keeping sub-pixel brightness
-- error far below what an 8-bit display can show.
local TW_SIN_N=4096
local TW_SIN={}
for i=0,TW_SIN_N-1 do TW_SIN[i]=math.sin(i*math.pi*2/TW_SIN_N) end
local TW_SIN_SCALE=TW_SIN_N/(math.pi*2)
local function twSin(a) return TW_SIN[math.floor(a*TW_SIN_SCALE)%TW_SIN_N] end

function NightSky.twinkleAlpha(s, time)
  time = tonumber(time) or 0
  if not s then return 1 end
  local d = tonumber(s.twDepth) or 0.2
  local tw = tonumber(s.tw) or 1
  local tw2 = tonumber(s.tw2) or 0.4
  local ph = tonumber(s.phase) or 0
  local ph2 = tonumber(s.phase2) or 1
  local w1 = 0.65 * twSin(time * tw + ph)
  local w2 = 0.35 * twSin(time * tw2 + ph2)
  local m = 1 + d * (0.55 * w1 + 0.45 * w2)
  if m < 0.35 then m = 0.35 end
  if m > 1.25 then m = 1.25 end
  return m
end

--- Building-proximity density: ~50% of stars (spatially balanced) fade out
--- near buildings. BuildingLight.factor is 0 near / 1 far — multiplies alpha
--- only for hideNearBuilding stars. Group assignment is permanent.
local _BuildingLight = nil
local function buildingLightModule()
  if _BuildingLight then return _BuildingLight end
  local ok, m = safe(V.require, "BuildingLight")
  if ok and m then _BuildingLight = m end
  return _BuildingLight
end

local function buildingFactorNow()
  local BL = buildingLightModule()
  local f = (BL and type(BL.factor) == "number") and BL.factor or 1
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f
end

function NightSky.buildingDensityMul(s)
  if not s or not s.hideNearBuilding then return 1 end
  return buildingFactorNow()
end


-- ---------------------------------------------------------------------------
-- Deterministic celestial catalog (generated once)
-- ---------------------------------------------------------------------------
local STARS = {}
local PLANETS = {}
local PLANET_SIZE_SCALE = 0.56 -- 4.35.31: 20% smaller than the 4.35.30 planet presentation
local SATURN_SIZE_SCALE = 0.455 -- 4.35.31: Saturn/rings 35% smaller than 4.35.30

do
  local function hash(n)
    local x = math.sin(n * 127.1) * 43758.5453
    return x - math.floor(x)
  end

  -- Natural distribution: clustered bands + sparse voids, full 360° azimuth.
  -- Dense natural background field; constellation stars live in a separate catalogue.
  local N = 5120
  for i = 1, N do
    local az = hash(i * 3.17) * math.pi * 2
    -- Full celestial sphere. Uniform-ish declination by sampling vertical
    -- component directly; the horizon clips it at render time as Earth rotates.
    local se = hash(i * 7.91) * 2 - 1
    local el = math.asin(se)
    local ce = math.sqrt(math.max(0,1-se*se))
    local dx = math.sin(az) * ce
    local dy = se
    local dz = math.cos(az) * ce
    local L = math.sqrt(dx * dx + dy * dy + dz * dz)
    if L > 1e-8 then dx, dy, dz = dx / L, dy / L, dz / L end

    local mag = hash(i * 11.3)
    -- Slightly lower peak alpha than 640-star field (richer, not washed out)
    local bright = 0.42 + (1 - mag) * 0.40
    STARS[i] = {
      id = i,
      dx = dx, dy = dy, dz = dz,
      az = az, el = el,
      size = 0.40 + (1 - mag) * 1.55 + hash(i * 2.7) * 0.35,
      a = bright,
      r = 0.86 + hash(i * 2.1) * 0.14,
      g = 0.88 + hash(i * 4.3) * 0.12,
      b = 0.94 + hash(i * 6.7) * 0.06,
      tw = 0.35 + hash(i * 13.7) * 2.2,
      tw2 = 0.15 + hash(i * 23.3) * 0.9,
      phase = hash(i * 19.1) * math.pi * 2,
      phase2 = hash(i * 29.7) * math.pi * 2,
      twDepth = 0.12 + hash(i * 31.1) * 0.28,
      hideNearBuilding = false,  -- set below (spatially balanced)
    }
  end

  -- Spatially balanced ~50% building-hidden group (deterministic, once).
  -- Bin by azimuth × elevation so no sky region is stripped bare.
  do
    local AZ_BINS, EL_BINS = 12, 6
    local bins = {}
    for i = 1, #STARS do
      local s = STARS[i]
      local az = s.az or 0
      if az < 0 then az = az + math.pi * 2 end
      local el = s.el or 0
      local elN = (el + math.pi * 0.5) / math.pi
      if elN < 0 then elN = 0 elseif elN > 1 then elN = 1 end
      local bi = math.floor(az / (math.pi * 2) * AZ_BINS) % AZ_BINS
      local bj = math.floor(elN * EL_BINS)
      if bj >= EL_BINS then bj = EL_BINS - 1 end
      local key = bi * EL_BINS + bj
      local bucket = bins[key]
      if not bucket then
        bucket = {}
        bins[key] = bucket
      end
      bucket[#bucket + 1] = i
    end
    for _, bucket in pairs(bins) do
      table.sort(bucket, function(a, b)
        return hash(a * 17.9) < hash(b * 17.9)
      end)
      local nHide = math.floor(#bucket * 0.5 + 0.5)
      for j = 1, #bucket do
        STARS[bucket[j]].hideNearBuilding = (j <= nHide)
      end
    end
  end

  -- Marker star for acceptance tests (DEBUG): bright gold; never hide near buildings
  STARS[1].r, STARS[1].g, STARS[1].b = 1.0, 0.82, 0.35
  STARS[1].a = 0.95
  STARS[1].size = 3.0
  STARS[1].hideNearBuilding = false
  -- az/el/id are catalogue-construction metadata only.  Dropping them removes
  -- 15,360 permanent Lua hash entries at MAX without changing the fallback or
  -- instanced renderer, both of which use the normalized world direction.
  for i=1,#STARS do STARS[i].az=nil;STARS[i].el=nil;STARS[i].id=nil end

local pdata = {
    -- Nine fixed planets distributed over the full celestial sphere. They share
    -- the same vault transform as the stars/constellations, so their relative
    -- angular separation never changes and they cannot drift into a trace.
    { az = math.rad(139.0), el = math.rad(62.7), size = 11.8,
      r=.95,g=.38,b=.14,a=.94, limbR=.55,limbG=.16,limbB=.06, hiR=1,hiG=.62,hiB=.28, feature="rings" },
    { az = math.rad(276.5), el = math.rad(41.8), size = 9.4,
      r=.62,g=.78,b=.98,a=.90, limbR=.28,limbG=.40,limbB=.62, hiR=.88,hiG=.94,hiB=1, feature="pole" },
    { az = math.rad(54.0), el = math.rad(26.4), size = 8.4,
      r=.92,g=.48,b=.32,a=.88, limbR=.48,limbG=.22,limbB=.14, hiR=1,hiG=.72,hiB=.50, feature="spot" },
    { az = math.rad(191.5), el = math.rad(12.8), size = 10.0,
      r=.72,g=.90,b=.78,a=.87, limbR=.32,limbG=.50,limbB=.42, hiR=.90,hiG=1,hiB=.92, feature="band" },
    { az = math.rad(329.0), el = math.rad(0.0), size = 7.6,
      r=.78,g=.62,b=.92,a=.84, limbR=.40,limbG=.28,limbB=.55, hiR=.95,hiG=.88,hiB=1, feature="crescent" },
    { az = math.rad(106.5), el = math.rad(-12.8), size = 8.9,
      r=.34,g=.74,b=.86,a=.86, limbR=.12,limbG=.34,limbB=.48, hiR=.66,hiG=.95,hiB=1, feature="storm" },
    { az = math.rad(244.0), el = math.rad(-26.4), size = 8.1,
      r=.94,g=.82,b=.40,a=.85, limbR=.48,limbG=.34,limbB=.12, hiR=1,hiG=.96,hiB=.70, feature="cap" },
    { az = math.rad(21.6), el = math.rad(8.0), size = 9.1,
      r=.42,g=.62,b=.96,a=.86, limbR=.14,limbG=.28,limbB=.58, hiR=.76,hiG=.88,hiB=1, feature="ice" },
    -- Planet X: warm copper/amber globe + pale gold crossed rings, deliberately
    -- separated from the night-sky blue and from the ring palette.
    { az = math.rad(159.1), el = math.rad(-62.7), size = 10.6,
      r=.92,g=.43,b=.16,a=.94, limbR=.50,limbG=.17,limbB=.06, hiR=1,hiG=.68,hiB=.26,
      ringR=.98,ringG=.82,ringB=.38, xBodyScale=1.42, feature="x_rings" },
  }
  for i, p in ipairs(pdata) do
    local ce, se = math.cos(p.el), math.sin(p.el)
    local dx = math.sin(p.az) * ce
    local dy = se
    local dz = math.cos(p.az) * ce
    local L = math.sqrt(dx * dx + dy * dy + dz * dz)
    PLANETS[i] = {
      id = i,
      dx = dx / L, dy = dy / L, dz = dz / L,
      size = p.size, r = p.r, g = p.g, b = p.b, a = p.a,
      limbR = p.limbR, limbG = p.limbG, limbB = p.limbB,
      hiR = p.hiR, hiG = p.hiG, hiB = p.hiB,
      ringR=p.ringR, ringG=p.ringG, ringB=p.ringB, xBodyScale=p.xBodyScale,
      feature = p.feature,
    }
  end
end

-- ---------------------------------------------------------------------------
-- GPU path: fixed directions → world pos via eye + D*R → Voxel3D.vp
-- ---------------------------------------------------------------------------
local STAR_SHADER = [[
  varying vec4 vColor;
  varying float vWorldY;
#ifdef VERTEX
  uniform mat4 vp;
  attribute vec4 VertexColor;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vColor = VertexColor;
    vWorldY = vertex_position.y;
    // Celestial geometry is an infinite vault. Force it to the far end of the
    // scene depth buffer so ANY terrain/building/NPC depth in front wins, even
    // if a host chooses a sky radius smaller than its terrain draw distance.
    vec4 clip = vp * vertex_position;
    clip.z = clip.w;
    return clip;
  }
#endif
#ifdef PIXEL
  uniform float horizonY;
  uniform float horizonClip;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    if (horizonClip > 0.5 && vWorldY < horizonY) discard;
    return vColor * color;
  }
#endif
]]

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexColor", "float", 4 },
}

local shader, mesh = nil, nil

local function ensureShader()
  if shader then return shader end
  if not (love and love.graphics and love.graphics.newShader) then return nil end
  local ok, sh = safe(love.graphics.newShader, STAR_SHADER)
  if ok then shader = sh end
  return shader
end

local SKY_RADIUS = 420  -- large vs playable map; re-centered on eye each frame

local function rotateY(dx,dy,dz,ang)
  -- Compatibility name retained for constellation API; rotation is now around
  -- the real north celestial pole, not world UP.
  local Sim
  safe(function() Sim=V.require("CelestialSim") end)
  if Sim and Sim.rotateStar then return Sim.rotateStar(dx,dy,dz,ang) end
  local c,ss=math.cos(ang),math.sin(ang)
  return dx*c+dz*ss,dy,-dx*ss+dz*c
end

local function skyRadius(Voxel3D)
  local r = SKY_RADIUS
  local far = Voxel3D and (Voxel3D.far or (Voxel3D.camera and Voxel3D.camera.far))
  if type(far) == "number" and far > 80 then
    r = math.min(far * 0.88, math.max(r, far * 0.7))
  end
  return r
end

-- Billboard axes from camera (orientation only — does not move star homes).
local function billboardAxes(Voxel3D)
  local e, fo = Voxel3D.eye, Voxel3D.focus
  if not e then return nil, nil end
  if not fo then fo = { e[1], e[2], e[3] - 1 } end
  local fx, fy, fz = fo[1] - e[1], fo[2] - e[2], fo[3] - e[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then return nil, nil end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  -- right ≈ forward × world-up alternate: (-fz, 0, fx)
  local rx, ry, rz = -fz, 0, fx
  local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
  if rl < 1e-6 then rx, ry, rz = 1, 0, 0 else rx, ry, rz = rx / rl, ry / rl, rz / rl end
  local ux = ry * fz - rz * fy
  local uy = rz * fx - rx * fz
  local uz = rx * fy - ry * fx
  local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
  if ul < 1e-6 then return { rx, ry, rz }, { 0, 1, 0 } end
  return { rx, ry, rz }, { ux / ul, uy / ul, uz / ul }
end

local VERT_POOL = {}
local function vertAt(i)
  local v = VERT_POOL[i]
  if not v then
    v = { 0, 0, 0, 0, 0, 0, 0 }
    VERT_POOL[i] = v
  end
  return v
end

local function pushTri(verts,n,
    x1,y1,z1,r1,g1,b1,a1,
    x2,y2,z2,r2,g2,b2,a2,
    x3,y3,z3,r3,g3,b3,a3)
  local v
  n=n+1;v=vertAt(n);v[1],v[2],v[3],v[4],v[5],v[6],v[7]=x1,y1,z1,r1,g1,b1,a1;verts[n]=v
  n=n+1;v=vertAt(n);v[1],v[2],v[3],v[4],v[5],v[6],v[7]=x2,y2,z2,r2,g2,b2,a2;verts[n]=v
  n=n+1;v=vertAt(n);v[1],v[2],v[3],v[4],v[5],v[6],v[7]=x3,y3,z3,r3,g3,b3,a3;verts[n]=v
  return n
end

local function pushQuad(verts, n, cx, cy, cz, half, axisR, axisU, r, g, b, a)
  local hx, hy, hz = axisR[1] * half, axisR[2] * half, axisR[3] * half
  local vx, vy, vz = axisU[1] * half, axisU[2] * half, axisU[3] * half

  -- Hot path: write the six vertices directly. The previous helper created a
  -- fresh closure for every star/planet/card, which meant thousands of short-
  -- lived closures per frame at MAX even though the geometry was identical.
  local v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx-hx-vx, cy-hy-vy, cz-hz-vz, r,g,b,a; verts[n] = v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx+hx-vx, cy+hy-vy, cz+hz-vz, r,g,b,a; verts[n] = v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx+hx+vx, cy+hy+vy, cz+hz+vz, r,g,b,a; verts[n] = v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx-hx-vx, cy-hy-vy, cz-hz-vz, r,g,b,a; verts[n] = v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx+hx+vx, cy+hy+vy, cz+hz+vz, r,g,b,a; verts[n] = v
  n = n + 1; v = vertAt(n); v[1],v[2],v[3],v[4],v[5],v[6],v[7] = cx-hx+vx, cy-hy+vy, cz-hz+vz, r,g,b,a; verts[n] = v
  return n
end

-- Pixel disk: stamps small quads only inside a circle so planets read as
-- round bodies, not squares. cell controls chunkiness (higher = fewer pixels).
local function pushPixelDisk(verts, n, cx, cy, cz, radius, axisR, axisU, r, g, b, a, cells, limbR, limbG, limbB, hiR, hiG, hiB)
  if not radius or radius < 0.2 or a < 0.01 then return n end
  cells = math.max(3, math.floor(cells or 5))
  limbR = limbR or (r * 0.4)
  limbG = limbG or (g * 0.4)
  limbB = limbB or (b * 0.4)
  hiR = hiR or math.min(1, r * 1.15)
  hiG = hiG or math.min(1, g * 1.12)
  hiB = hiB or math.min(1, b * 1.1)
  -- 0.5 = cells abut with no overlap. Overlap under additive blend made white seams.
  local half = radius / cells * 0.50
  local arx, ary, arz = axisR[1] or 0, axisR[2] or 0, axisR[3] or 0
  local aux, auy, auz = axisU[1] or 0, axisU[2] or 0, axisU[3] or 0
  for iy = -cells, cells do
    for ix = -cells, cells do
      local fx = ix / cells
      local fy = iy / cells
      local d2 = fx * fx + fy * fy
      if d2 <= 1.02 then
        local d = math.sqrt(d2)
        local pr, pg, pb, pa = r, g, b, a
        if d > 0.82 then
          -- outer limb: darker edge sells the sphere
          local t = (d - 0.82) / 0.20
          pr = r * (1 - t) + limbR * t
          pg = g * (1 - t) + limbG * t
          pb = b * (1 - t) + limbB * t
          pa = a * (1 - t * 0.25)
        elseif d < 0.35 then
          -- soft core (keep planet hue; additive blend forbids near-white)
          local t = (1 - (d / 0.35)) * 0.22
          pr = r * (1 - t) + hiR * t
          pg = g * (1 - t) + hiG * t
          pb = b * (1 - t) + hiB * t
        end
        local ox = arx * fx * radius + aux * fy * radius
        local oy = ary * fx * radius + auy * fy * radius
        local oz = arz * fx * radius + auz * fy * radius
        n = pushQuad(verts, n, cx + ox, cy + oy, cz + oz, half, axisR, axisU, pr, pg, pb, pa)
      end
    end
  end
  return n
end

-- Seam-free textured planet surface. The legacy square-card raster could reveal
-- moving horizontal/vertical seams at fractional camera angles. This polar
-- triangle mesh is watertight; color is evaluated continuously at vertices and
-- includes stable terrain/crater relief without per-frame allocations.
local function planetHash(v)
  local x=math.sin(v*91.731+17.113)*43758.5453
  return x-math.floor(x)
end

local function planetSurfaceColor(p,x,y)
  local d2=x*x+y*y; local mu=math.sqrt(math.max(0,1-d2)); local id=tonumber(p.id) or 1
  local r,g,b=p.r or .7,p.g or .7,p.b or .8
  local lr,lg,lb=p.limbR or r*.42,p.limbG or g*.42,p.limbB or b*.42
  local hr,hg,hb=p.hiR or math.min(1,r*1.15),p.hiG or math.min(1,g*1.12),p.hiB or math.min(1,b*1.10)
  local limb=.44+.56*mu; local light=.80+.20*math.max(0,math.min(1,.5+x*.38-y*.26))
  local grain=1+math.sin(x*19.7+y*13.1+id*2.73)*.045+math.sin(x*41.1-y*29.3+id*1.37)*.025
  local shade=limb*light*grain; local f=p.feature or ''
  if f=='band' or f=='rings' then shade=shade*(.94+.06*math.sin((y*11+id)*math.pi))
  elseif f=='storm' then shade=shade*(.93+.07*math.sin((x*8+y*15+id)*math.pi))
  elseif f=='pole' or f=='cap' or f=='ice' then shade=shade*(.95+.05*math.cos((y*7-id*.3)*math.pi)) end
  local craterStrength=(f=='band' or f=='storm') and .55 or .92
  for k=1,4 do
    local cx=-.58+planetHash(id*31.7+k*7.1)*1.16; local cy=-.56+planetHash(id*47.3+k*11.9)*1.12
    if cx*cx+cy*cy<.68 then
      local cr=.105+planetHash(id*59.9+k*13.7)*.115; local dx,dy=x-cx,y-cy; local q=math.sqrt(dx*dx+dy*dy)/cr
      if q<.68 then shade=shade*(1-craterStrength*(.18-.08*q/.68))
      elseif q<1 then shade=shade*(1+craterStrength*.10*(1-(q-.68)/.32)) end
    end
  end
  shade=math.max(.30,math.min(1.15,shade)); local edge=math.max(0,math.min(1,(1-mu)*1.20))
  local pr=(r*(1-edge)+lr*edge)*shade; local pg=(g*(1-edge)+lg*edge)*shade; local pb=(b*(1-edge)+lb*edge)*shade
  if mu>.82 then local t=(mu-.82)/.18*.16; pr=pr*(1-t)+hr*t; pg=pg*(1-t)+hg*t; pb=pb*(1-t)+hb*t end
  return math.min(1,pr),math.min(1,pg),math.min(1,pb)
end

-- 8.1.24: a planet's normalized polar topology and procedural surface color are
-- immutable.  Cache the exact triangle stream once per catalogue planet and only
-- apply the live billboard transform/alpha each frame.  This preserves vertex
-- count/order/color exactly while removing thousands of trig/sqrt/crater calls
-- from every visible-night frame.
local PLANET_DISC_CACHE=setmetatable({}, {__mode="k"})
local function planetDiscTemplate(p)
  local cached=PLANET_DISC_CACHE[p]
  if cached then return cached end
  local out={}
  local function emit(x,y)
    local rr,gg,bb=planetSurfaceColor(p,x,y)
    out[#out+1]={x,y,rr,gg,bb}
  end
  local function tri(x1,y1,x2,y2,x3,y3) emit(x1,y1); emit(x2,y2); emit(x3,y3) end
  local rings,segments=7,40; local first=1/rings
  for j=0,segments-1 do
    local a0=j/segments*math.pi*2; local a1=(j+1)/segments*math.pi*2
    tri(0,0,math.cos(a0)*first,math.sin(a0)*first,math.cos(a1)*first,math.sin(a1)*first)
  end
  for ri=1,rings-1 do
    local r0,r1=ri/rings,(ri+1)/rings
    for j=0,segments-1 do
      local a0=j/segments*math.pi*2; local a1=(j+1)/segments*math.pi*2
      local x00,y00=math.cos(a0)*r0,math.sin(a0)*r0; local x01,y01=math.cos(a1)*r0,math.sin(a1)*r0
      local x10,y10=math.cos(a0)*r1,math.sin(a0)*r1; local x11,y11=math.cos(a1)*r1,math.sin(a1)*r1
      tri(x00,y00,x10,y10,x11,y11); tri(x00,y00,x11,y11,x01,y01)
    end
  end
  PLANET_DISC_CACHE[p]=out
  return out
end

local MILKY_WAY_POINTS=nil
local function milkyWayPoints()
  if MILKY_WAY_POINTS then return MILKY_WAY_POINTS end
  local out={}
  local count=220
  local ct,stt=math.cos(1.0821),math.sin(1.0821)
  for j=1,count do
    local lon=(j/count)*math.pi*2
    local band=(math.sin(j*91.71)*43758.5453)%1
    local off=(band-0.5)*0.18
    local dx=math.cos(lon)*math.cos(off)
    local dy=math.sin(off)
    local dz=math.sin(lon)*math.cos(off)
    local ty=dy*ct-dz*stt; local tz=dy*stt+dz*ct
    out[j]={dx,ty,tz,0.035+((j*37)%17)/17*0.055}
  end
  MILKY_WAY_POINTS=out
  return out
end

local function pushPlanetDisc(verts,n,cx,cy,cz,radius,axisR,axisU,p,a)
  local tpl=planetDiscTemplate(p)
  local arx,ary,arz=axisR[1],axisR[2],axisR[3]
  local aux,auy,auz=axisU[1],axisU[2],axisU[3]
  for i=1,#tpl do
    local q=tpl[i]; local x,y=q[1],q[2]
    n=n+1; local v=vertAt(n)
    v[1]=cx+arx*x*radius+aux*y*radius; v[2]=cy+ary*x*radius+auy*y*radius; v[3]=cz+arz*x*radius+auz*y*radius
    v[4],v[5],v[6],v[7]=q[3],q[4],q[5],a; verts[n]=v
  end
  return n
end


-- Saturn / Planet-X ring topology is likewise invariant in normalized billboard
-- space. Cache the exact accepted grid points (including gap/occlusion decisions)
-- once; live frames only scale/transform the retained points.
local SATURN_RING_TEMPLATE=nil
local function saturnRingTemplate()
  if SATURN_RING_TEMPLATE then return SATURN_RING_TEMPLATE end
  local cells=22; local rang=math.rad(30); local rc,rs=math.cos(rang),math.sin(rang)
  local back,front={},{}
  for iy=-cells,cells do
    for ix=-cells,cells do
      local u,v=ix/cells,iy/cells
      local fx=u*rc-v*rs; local fy=u*rs+v*rc
      local ed=math.sqrt(fx*fx+(fy/.58)*(fy/.58))
      if ed>=.52 and ed<=1 then
        local t=(ed-.52)/.48; local gap=1
        if t>.38 and t<.55 then gap=.10 end
        if t>.70 and t<.78 then gap=.40 end
        local q={fx,fy,gap}
        if fy>=0 then
          front[#front+1]=q
        elseif math.sqrt((fx*2.55)^2+(fy*1.20)^2)>=1.20 then
          back[#back+1]=q
        end
      end
    end
  end
  SATURN_RING_TEMPLATE={back=back,front=front}
  return SATURN_RING_TEMPLATE
end

local X_RING_TEMPLATES={}
local function xRingTemplate(angle,bodyScale)
  local key=tostring(angle)..":"..tostring(bodyScale)
  local cached=X_RING_TEMPLATES[key]; if cached then return cached end
  local cells=20; local rc,rs=math.cos(angle),math.sin(angle)
  local back,front={},{}
  local hide=(bodyScale or 1.42)*1.04
  for iy=-cells,cells do
    for ix=-cells,cells do
      local u,v=ix/cells,iy/cells
      local fx=u*rc-v*rs; local fy=u*rs+v*rc
      local ed=math.sqrt(fx*fx+(fy/.54)*(fy/.54))
      if ed>=.54 and ed<=1 then
        local q={fx,fy}
        if fy>=0 then
          front[#front+1]=q
        elseif math.sqrt((fx*2.45)^2+(fy*1.08)^2)>=hide then
          back[#back+1]=q
        end
      end
    end
  end
  cached={back=back,front=front}; X_RING_TEMPLATES[key]=cached; return cached
end


local _Quality = nil
local function qualityModule()
  if _Quality then return _Quality end
  local ok, m = safe(V.require, "Quality")
  if ok and m then _Quality = m end
  return _Quality
end

local LOD_CACHE = { starStep = 1, maxPlanets = 9, twinkle = true, meteors = true }
local function celestialLod()
  local lod = LOD_CACHE
  lod.starStep, lod.maxPlanets, lod.twinkle, lod.meteors = 1, 9, true, true
  -- Celestial identity is not a quality budget. Skipping catalogue entries on
  -- LOW/POTATO caused the star/constellation population to change with camera
  -- pitch and host culling. Keep the complete fixed vault on every tier; the
  -- global performance work elsewhere removes CPU/GPU cost without deleting sky.
  lod.starStep,lod.maxPlanets,lod.twinkle,lod.meteors=1,#PLANETS,true,true
  return lod
end

local function starScaleNow()
  local starScale = 1
  local BL = buildingLightModule()
  if BL and BL.starScale then starScale = BL.starScale() or 1 end
  if type(starScale) ~= "number" or starScale ~= starScale then starScale = 1 end
  if starScale < 0.4 then starScale = 0.4 end
  if starScale > 1 then starScale = 1 end
  return starScale
end

function NightSky._nightSkyBrightnessScale()
  local S=NightSky._brightnessSettings
  if not S then
    local ok,m=safe(V.require,"Settings")
    if ok and m then NightSky._brightnessSettings=m; S=m end
  end
  if S and S.nightSkyBrightnessScale then
    local ok,v=safe(S.nightSkyBrightnessScale)
    if ok and tonumber(v) then return math.max(0.25,math.min(1.5,tonumber(v))) end
  end
  return 1
end


-- ---------------------------------------------------------------------------
-- Sun / Moon as world-space entities on the celestial sphere (same path as stars).
-- Drawn day AND night (does not use nightVis). Noon = overhead (+Y).
-- Player must look up in FPV/3rd to see noon sun; horizon view hides it.
-- ---------------------------------------------------------------------------

-- Stand down if another system already draws a sun/moon (voxel host DayNight bodies).
local function hostCelestialFlags()
  -- When the ultimate celestial engine is enabled Weather FX owns the visible
  -- celestial bodies; host DayNight is wrapped only as a lighting/clock adapter.
  local ok,E=safe(V.require,"CelestialEngine")
  if ok and E and E.state and E.state() then return false,false end
  local hasSun, hasMoon = false, false
  safe(function()
    local DN = NightSky._DayNight
    if not DN then return end
    -- Common host patterns: sunDir/moonDir, sunVisible, getSun, bodies
    if DN.sunDir or DN.sunPosition or DN.getSun or DN.sun then hasSun = true end
    if DN.moonDir or DN.moonPosition or DN.getMoon or DN.moon then hasMoon = true end
    if type(DN.hasSun) == "boolean" then hasSun = DN.hasSun end
    if type(DN.hasMoon) == "boolean" then hasMoon = DN.hasMoon end
    -- Explicit draw already done this frame by host
    if DN._wxHostDrewSun then hasSun = true end
    if DN._wxHostDrewMoon then hasMoon = true end
  end)
  safe(function()
    local Voxel = NightSky._Voxel
    if Voxel and Voxel.sunDrawn then hasSun = true end
    if Voxel and Voxel.moonDrawn then hasMoon = true end
  end)
  return hasSun, hasMoon
end

local MOON_CRATERS = {
  {-0.42,-0.18,0.13,0.54}, {0.20,0.44,0.11,0.62}, {0.48,-0.38,0.10,0.58},
  {-0.14,0.66,0.08,0.66}, {0.04,0.06,0.09,0.72}, {-0.58,0.28,0.07,0.70},
}
local function moonSurface(body,x,y,lit,lunarDark)
  local rr=x*x+y*y; local mu=math.sqrt(math.max(0,1-rr)); local c=body and body.color or {.73,.80,1.0}
  if not lit then
    -- Ordinary lunar earthshine is intentionally almost invisible. The old
    -- 5.5-15.5% full-disc backing layer made a crescent/quarter moon look like
    -- a new phase painted over the obsolete full moon. During a real solar
    -- eclipse the dark lunar silhouette becomes opaque again.
    local eclipse=clamp01(tonumber(body and body.solarEclipse) or 0)
    local earth=.012+.018*clamp01(tonumber(body and body.illumination) or 1)
    local a=earth+(0.94-earth)*eclipse
    return .028,.034,.052,a
  end
  local shade=.70+.30*mu; local crater=1
  for i=1,#MOON_CRATERS do local q=MOON_CRATERS[i]; local dx,dy=x-q[1],y-q[2]; if dx*dx+dy*dy<=q[3]*q[3] then crater=math.min(crater,q[4]) end end
  local r,g,b=(c[1] or .73)*shade*crater,(c[2] or .80)*shade*crater,(c[3] or 1)*shade*crater
  if (lunarDark or 0)>0 then r=r*(1-lunarDark)+.62*lunarDark; g=g*(1-lunarDark*.72); b=b*(1-lunarDark*.90) end
  return r,g,b,.76+.24*mu
end

function NightSky.drawSunMoonWorld(Voxel3D)
  -- 8.1.15 single-owner body renderer. The old world fallback built each disc
  -- from hundreds of overlapping square cells; those cell boundaries could
  -- become visible as a grid on real GPUs. Route every 3D host through the
  -- analytic far-depth disc path below so sun/moon geometry is identical on
  -- primary and fallback hosts.
  if NightSky.drawSunMoonProjectedWorld then
    return NightSky.drawSunMoonProjectedWorld(Voxel3D)
  end
  return false
end

local _CelestialSim = nil
local function celestialSimModule()
  if _CelestialSim then return _CelestialSim end
  local ok, m = safe(V.require, "CelestialSim")
  if ok and m then _CelestialSim = m end
  return _CelestialSim
end

--- Primary renderer: celestial sphere through the host view-projection matrix.
local function constellationVisibility(globalVis)
  globalVis=clamp01(tonumber(globalVis) or 0)
  if globalVis<=0 then return 0 end
  -- 8.1.16: constellation readability uses the same peak for every traced
  -- subject. Time/cloud attenuation remains continuous; brightness differences
  -- now come from landmark-star hierarchy rather than which source sheet a
  -- constellation happened to come from.
  return clamp01((globalVis^1.08)*1.14)
end

local function constellationBuildingScale()
  -- 8.1.46: use the explicitly monotonic building-distance contract. Near a
  -- building is dimmest; moving away can only increase the multiplier. The
  -- generic star path remains identical, but this named seam prevents a future
  -- light-pollution inversion from silently reversing traced constellations.
  local BL=buildingLightModule()
  if BL and BL.constellationScale then
    local ok,v=safe(BL.constellationScale)
    if ok and type(v)=="number" and v==v then return clamp01(v) end
  end
  return starScaleNow()
end

function NightSky._drawInstancedOrdinaryStars(Voxel3D,stars,opts)
  local M=NightSky._starFieldModule
  if not M then local ok,m=safe(V.require,"CelestialStarField");if not ok or not m then return false end;M=m;NightSky._starFieldModule=m end
  local ok,drew=safe(M.draw,Voxel3D,stars,opts)
  return ok and drew==true
end
function NightSky._drawInstancedProjectedStars(stars,opts)
  local M=NightSky._starFieldModule
  if not M then local ok,m=safe(V.require,"CelestialStarField");if not ok or not m then return false,0 end;M=m;NightSky._starFieldModule=m end
  local ok,drew,count=safe(M.drawProjected,stars,opts)
  return ok and drew==true,tonumber(count) or 0
end

function NightSky.drawWorld(Voxel3D, time)
  -- Always sample current TOD/pin so OPTIONS → NITE is never stuck at 0.
  local target = NightSky.computeNightVisibility()
  NightSky._nightVisRaw = target
  local nightVis = tonumber(NightSky._nightVis) or target
  -- Smooth the global deep-sky envelope in both directions. The target itself
  -- already follows solar altitude continuously; this small temporal filter
  -- removes frame/host sampling steps without delaying the celestial clock.
  local nowT = tonumber(time) or 0
  local lastT = NightSky._nightVisLastT
  local dt = (type(lastT)=="number") and (nowT-lastT) or (1/60)
  if dt <= 0 then dt = 1/60 elseif dt > 0.25 then dt = 0.25 end
  NightSky._nightVisLastT = nowT
  local k = 1 - math.exp(-1.35 * dt)
  nightVis = nightVis + (target - nightVis) * k
  -- Explicit Weather FX or voxel-host time pins are presentation commands.
  -- Snap the deep-sky envelope to the current weather-attenuated target so a
  -- DAY -> NIGHT menu change cannot spend seconds showing an empty sky.
  local TOD=NightSky._TOD
  if TOD and (TOD.pin=="NITE" or TOD.pin=="NIGHT" or TOD.hostMode=="night") then nightVis=target end
  if TOD and (TOD.pin=="DAY" or TOD.hostMode=="day") then nightVis=0 end
  NightSky._nightVis = clamp01(nightVis)
  nightVis = NightSky._nightVis
  if nightVis < 0.02 then return false end
  if not (Voxel3D and Voxel3D.vp) then return false end
  local e = Voxel3D.eye
  if not e then return false end

  local sh = ensureShader()
  if not sh then return false end
  local axisR, axisU = billboardAxes(Voxel3D)
  if not (axisR and axisU) then return false end

  local radius = skyRadius(Voxel3D)
  local t = tonumber(time) or 0
  local scale = starScaleNow() * NightSky._nightSkyBrightnessScale()
  local verts = NightSky._worldVerts
  if not verts then
    verts = {}
    NightSky._worldVerts = verts
  end
  local n = 0

  -- LOD: step through catalog (full positions still fixed on the sphere).
  local lod = celestialLod()
  local step = lod.starStep or 1
  -- Daily vault angle (same clock as sun) — stars share the celestial sphere.
  -- Resolve the simulation module and the identical sin/cos pair ONCE per
  -- frame. 4.33.0 repeated both the module lookup and trig inside the 2,560
  -- star loop even though vaultAng is constant for the whole frame.
  local Sim = celestialSimModule()
  local vaultAng = (Sim and Sim.starVaultAngle and Sim.starVaultAngle()) or (Sim and Sim.siderealAngle and (Sim.siderealAngle() * (Sim.STAR_VAULT_RATE or 0.25))) or ((Sim and Sim.solarAlpha and Sim.solarAlpha()) or 0)
  local vaultRotate = (Sim and Sim.starRotator and Sim.starRotator(vaultAng)) or function(dx,dy,dz) return rotateY(dx,dy,dz,vaultAng) end
  local horizonFade = Sim and Sim.horizonFade or nil
  local buildingFactor = buildingFactorNow()

  local gpuStars=NightSky._drawInstancedOrdinaryStars(Voxel3D,STARS,{axisR=axisR,axisU=axisU,radius=radius,vaultAngle=vaultAng,time=t,visibility=nightVis,scale=scale,buildingFactor=buildingFactor,twinkle=lod.twinkle})
  if not gpuStars then
    for i = 1, #STARS, step do
      local s = STARS[i]
      local fade = NightSky.starFade(s, nightVis)
      local dens = s.hideNearBuilding and buildingFactor or 1
      if fade > 0.01 and dens > 0.02 then
        local sdx,sdy,sdz=vaultRotate(s.dx,s.dy,s.dz)
        local hf = horizonFade and horizonFade(sdy) or 1
        if hf >= 0.02 then
          local cx = e[1] + sdx * radius
          local cy = e[2] + sdy * radius
          local cz = e[3] + sdz * radius
          local tw = lod.twinkle and NightSky.twinkleAlpha(s, t) or 1
          local a = s.a * scale * fade * dens * tw * hf
          if NightSky.DEBUG and i == 1 then a = math.max(a, 0.85 * fade) end
          local half = math.max(0.5, s.size * 0.55)
          n = pushQuad(verts, n, cx, cy, cz, half, axisR, axisU, s.r, s.g, s.b, a)
        end
      end
    end
  end

  local nPlan = math.min(#PLANETS, lod.maxPlanets or #PLANETS)
  for i = 1, nPlan do
    local p = PLANETS[i]
    local fade = NightSky.starFade(p, nightVis)
    if fade > 0.01 then
      local pdx,pdy,pdz
      pdx,pdy,pdz=vaultRotate(p.dx,p.dy,p.dz)
      local cx = e[1] + pdx * radius
      local cy = e[2] + pdy * radius
      local cz = e[3] + pdz * radius
      local pa = p.a * scale * fade
      -- 4.35.31: all planets are 20% smaller than 4.35.30; Saturn is 35% smaller total.
      local planetScale = (p.feature == "rings" or p.feature == "x_rings") and SATURN_SIZE_SCALE or PLANET_SIZE_SCALE
      local R = p.size * 1.05 * planetScale
      local arx, ary, arz = axisR[1] or 0, axisR[2] or 0, axisR[3] or 0
      local aux, auy, auz = axisU[1] or 0, axisU[2] or 0, axisU[3] or 0

      if p.feature == "rings" then
        -- Wrap: back tips only (fully outside body) → body → front arc across body.
        -- 8.1.24 reuses the exact normalized accepted-point set instead of
        -- re-running the 45x45 ellipse/sqrt/gap scan every visible frame.
        local cells=22; local spanX=R*2.55; local spanY=R*1.20; local half=spanX/cells*.50
        local tpl=saturnRingTemplate()
        local function emitCached(list)
          for k=1,#list do
            local q=list[k]; local fx,fy,gap=q[1],q[2],q[3]
            local ox=arx*fx*spanX+aux*fy*spanY; local oy=ary*fx*spanX+auy*fy*spanY; local oz=arz*fx*spanX+auz*fy*spanY
            n=pushQuad(verts,n,cx+ox,cy+oy,cz+oz,half,axisR,axisU,.96*gap,.90*gap,.72*gap,pa*.90*gap)
          end
        end
        emitCached(tpl.back)
        n=pushPlanetDisc(verts,n,cx,cy,cz,R*1.06,axisR,axisU,p,pa)
        emitCached(tpl.front)
      elseif p.feature == "x_rings" then
        local cells=20; local spanX=R*2.45; local spanY=R*1.08; local half=spanX/cells*.46
        local bodyScale=tonumber(p.xBodyScale) or 1.42; local bodyR=R*bodyScale
        local ringR,ringG,ringB=p.ringR or .98,p.ringG or .82,p.ringB or .38
        local plus=xRingTemplate(math.rad(45),bodyScale); local minus=xRingTemplate(math.rad(-45),bodyScale)
        local function emitCached(list)
          for k=1,#list do
            local q=list[k]; local fx,fy=q[1],q[2]
            local ox=arx*fx*spanX+aux*fy*spanY; local oy=ary*fx*spanX+auy*fy*spanY; local oz=arz*fx*spanX+auz*fy*spanY
            n=pushQuad(verts,n,cx+ox,cy+oy,cz+oz,half,axisR,axisU,ringR,ringG,ringB,pa*.72)
          end
        end
        emitCached(plus.back); emitCached(minus.back)
        n=pushPlanetDisc(verts,n,cx,cy,cz,bodyR,axisR,axisU,p,pa)
        emitCached(plus.front); emitCached(minus.front)
      else
        n = pushPlanetDisc(verts,n,cx,cy,cz,R,axisR,axisU,p,pa)
      end
    end
  end


  -- Milky Way: a faint tilted great-circle band. It shares the sidereal vault
  -- and is strongly suppressed by clouds/light pollution through CelestialEngine.
  do
    local mwVis=0
    safe(function() local E=V.require("CelestialEngine"); local st=E and E.state and E.state(); mwVis=st and st.milkyWayVisibility or 0 end)
    if mwVis>0.02 then
      local points=milkyWayPoints()
      for j=1,#points,math.max(1,step) do
        local q=points[j]
        local dx,dy,dz=vaultRotate(q[1],q[2],q[3])
        local hf=horizonFade and horizonFade(dy) or 1
        if hf>0.02 then
          local cx=e[1]+dx*radius; local cy=e[2]+dy*radius; local cz=e[3]+dz*radius
          local a=mwVis*hf*q[4]*NightSky._nightSkyBrightnessScale()
          n=pushQuad(verts,n,cx,cy,cz,0.55,axisR,axisU,0.62,0.68,0.88,a)
        end
      end
    end
  end

  -- Aurora is true celestial-vault geometry: layered thin curtains
  -- with altitude-coded colour and overhead corona perspective. It is emitted
  -- into the same far-depth vault before clouds, so terrain/cloud occlusion
  -- remains physically authoritative.
  if Aurora and Aurora.appendWorld then
    n=Aurora.appendWorld(verts,n,pushTri,e,radius,t,nightVis) or n
  end

  -- User-traced constellations use a stronger cloud envelope than an isolated
  -- background star so the dense drawings vanish naturally behind cloud banks.
  if Constellations and Constellations.appendWorld then
    local constVis=math.min(1.3,constellationVisibility(nightVis)*NightSky._nightSkyBrightnessScale())
    n = Constellations.appendWorld(
      verts, n, pushQuad, axisR, axisU, e, radius,
      vaultRotate, vaultAng, constVis, nil, NightSky.twinkleAlpha, t,
      constellationBuildingScale()
    ) or n
  end

  if lod.meteors and NightSky._appendMeteorsWorld then
    n = NightSky._appendMeteorsWorld(verts, n, axisR, axisU, e, radius) or n
  end

  for i = n + 1, #verts do verts[i] = nil end
  if n < 3 then return gpuStars==true end

  if not mesh then
    local ok, m = safe(love.graphics.newMesh, FORMAT, verts, "triangles", "stream")
    if not ok or not m then return false end
    mesh = m
  else
    if not safe(mesh.setVertices, mesh, verts) then
      -- 8.1.81: a denser vault can outgrow the original stream mesh. Retire
      -- that GPU allocation before recursive recreation so VRAM cannot spike
      -- until the Lua collector happens to run.
      safe(mesh.release,mesh)
      mesh = nil
      return NightSky.drawWorld(Voxel3D, time)
    end
  end

  local began = false
  if Voxel3D.beginEffect then
    began = Voxel3D.beginEffect(sh)
  end
  if not began then
    safe(love.graphics.setShader, sh)
    safe(love.graphics.setDepthMode, "lequal", false)
    began = true
  end

  -- Host matrices are row-major in Love shaders (Dramaless / Gen2 convention).
  if not safe(sh.send, sh, "vp", "row", Voxel3D.vp) then
    safe(sh.send, sh, "vp", Voxel3D.vp)
  end
  safe(sh.send, sh, "horizonClip", 0.0)
  safe(love.graphics.setBlendMode, "add", "alphamultiply")
  safe(love.graphics.setColor, 1, 1, 1, 1)
  safe(love.graphics.setDepthMode, "lequal", false)
  safe(love.graphics.draw, mesh)

  if Voxel3D.endEffect then
    safe(Voxel3D.endEffect)
  else
    safe(love.graphics.setShader)
    safe(love.graphics.setDepthMode, "lequal", true)
  end
  safe(love.graphics.setBlendMode, "alpha", "alphamultiply")
  safe(love.graphics.setColor, 1, 1, 1, 1)
  return true
end

-- ---------------------------------------------------------------------------
-- Math fallback when VP path is unavailable: project D through camera basis
-- (inverse orientation × direction). Not a screen-space position hack —
-- same celestial D, same orientation transform as a view matrix would apply.
-- ---------------------------------------------------------------------------
NightSky._basisR = nil
NightSky._basisU = nil
NightSky._basisF = nil

local function captureBasis(Voxel3D)
  local e = Voxel3D and Voxel3D.eye
  local fo = Voxel3D and Voxel3D.focus
  local fx, fy, fz
  if e and fo then
    fx, fy, fz = fo[1] - e[1], fo[2] - e[2], fo[3] - e[3]
  else
    local FP = NightSky._FirstPerson
    if FP and type(FP.yaw) == "number" then
      local yaw = FP.yaw
      local pitch = type(FP.pitch) == "number" and FP.pitch or 0
      local cp = math.cos(pitch)
      fx = math.sin(yaw) * cp
      fy = -math.sin(pitch)
      fz = math.cos(yaw) * cp
    else
      return false
    end
  end
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then return false end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local rx, ry, rz = -fz, 0, fx
  local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
  if rl < 1e-6 then rx, ry, rz = 1, 0, 0 else rx, ry, rz = rx / rl, ry / rl, rz / rl end
  local ux = ry * fz - rz * fy
  local uy = rz * fx - rx * fz
  local uz = rx * fy - ry * fx
  local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
  if ul < 1e-6 then ux, uy, uz = 0, 1, 0 else ux, uy, uz = ux / ul, uy / ul, uz / ul end
  NightSky._basisF = { fx, fy, fz }
  NightSky._basisR = { rx, ry, rz }
  NightSky._basisU = { ux, uy, uz }
  return true
end

local function projectCelestial(dx, dy, dz)
  local R, U, F = NightSky._basisR, NightSky._basisU, NightSky._basisF
  if not (R and U and F) then return nil, nil, 0 end
  -- View-space direction = basis^T * D  (camera orientation only)
  local sx = dx * R[1] + dy * R[2] + dz * R[3]
  local sy = dx * U[1] + dy * U[2] + dz * U[3]
  local sz = dx * F[1] + dy * F[2] + dz * F[3]
  if sz < 0.02 then return nil, nil, 0 end  -- behind camera
  local k = 0.55  -- focal scale (FOV-like)
  local u = 0.5 + (sx / sz) * k
  local v = 0.5 - (sy / sz) * k
  local fade = 1
  if sz < 0.2 then fade = sz / 0.2 end
  if u < -0.2 or u > 1.2 or v < -0.2 or v > 1.2 then return nil, nil, 0 end
  if u < 0 then fade = fade * math.max(0, 1 + u * 2) end
  if u > 1 then fade = fade * math.max(0, 1 - (u - 1) * 2) end
  if v < 0 then fade = fade * math.max(0, 1 + v * 2) end
  if v > 1 then fade = fade * math.max(0, 1 - (v - 1) * 2) end
  if fade < 0.03 then return nil, nil, 0 end
  return u, v, fade
end

function NightSky.draw(w, h, edge, body, time)
  local target = NightSky.computeNightVisibility()
  NightSky._nightVisRaw = target
  local nightVis = NightSky._nightVis or target
  if math.abs(target - nightVis) > 0.25 then nightVis = target end
  NightSky._nightVis = nightVis
  if nightVis < 0.02 then return false end
  if not (love and love.graphics) then return false end
  w = tonumber(w) or 160
  h = tonumber(h) or 144
  edge = tonumber(edge) or (h * 0.65)
  time = tonumber(time) or 0
  captureBasis(nil)

  local scale = starScaleNow() * NightSky._nightSkyBrightnessScale()
  local prev
  safe(function() prev = { love.graphics.getBlendMode() } end)
  safe(love.graphics.setBlendMode, "add", "alphamultiply")

  local drawn = 0
  local lod2 = celestialLod()
  local step2 = lod2.starStep or 1
  local buildingFactor = buildingFactorNow()
  for i = 1, #STARS, step2 do
    local s = STARS[i]
    local dayFade = NightSky.starFade(s, nightVis)
    if dayFade > 0.01 then
      local u, v, fade = projectCelestial(s.dx, s.dy, s.dz)
      if u and v and fade then
        local dens = s.hideNearBuilding and buildingFactor or 1
        local a = s.a * scale * fade * dayFade * NightSky.twinkleAlpha(s, time) * dens
        local sz = math.max(1.1, s.size * 0.7)
        safe(love.graphics.setColor, s.r, s.g, s.b, a)
        safe(love.graphics.rectangle, "fill", u * w, v * edge, sz, sz)
        drawn = drawn + 1
      end
    end
  end
  for i = 1, #PLANETS do
    local p = PLANETS[i]
    local dayFade = NightSky.starFade(p, nightVis)
    if dayFade > 0.01 then
      local u, v, fade = projectCelestial(p.dx, p.dy, p.dz)
      if u and v and fade then
        local a = p.a * scale * fade * dayFade
        local cx = u * w
        local cy = v * edge
        local planetScale = (p.feature == "rings" or p.feature == "x_rings") and SATURN_SIZE_SCALE or PLANET_SIZE_SCALE
        local rad = math.max(4.2, (p.size or 5) * 1.35 * planetScale)
        local lr = p.limbR or (p.r * 0.4)
        local lg = p.limbG or (p.g * 0.4)
        local lb = p.limbB or (p.b * 0.4)
        local cells = 7
        local pix = rad / cells
        for iy = -cells, cells do
          for ix = -cells, cells do
            local fx, fy = ix / cells, iy / cells
            local d2 = fx * fx + fy * fy
            if d2 <= 1.02 then
              local d = math.sqrt(d2)
              local pr, pg, pb, pa = p.r, p.g, p.b, a
              if d > 0.82 then
                local t = (d - 0.82) / 0.20
                pr = p.r * (1 - t) + lr * t
                pg = p.g * (1 - t) + lg * t
                pb = p.b * (1 - t) + lb * t
              elseif d < 0.35 then
                local t = (1 - (d / 0.35)) * 0.22
                pr = p.r * (1 - t) + (p.hiR or 1) * t
                pg = p.g * (1 - t) + (p.hiG or 1) * t
                pb = p.b * (1 - t) + (p.hiB or 1) * t
              end
              safe(love.graphics.setColor, pr, pg, pb, pa)
              -- exact 1.0 coverage: no overlap under additive blend
              safe(love.graphics.rectangle, "fill",
                cx + fx * rad - pix * 0.5, cy + fy * rad - pix * 0.5, pix, pix)
            end
          end
        end
        if p.feature == "rings" then
          local cells = 22
          local spanX = rad * 2.55
          local spanY = rad * 1.20
          local pix = spanX / cells
          local rang = math.rad(30)
          local rc, rs = math.cos(rang), math.sin(rang)
          local bodyHide = rad * 1.20
          local function emitScreenRing(frontPass)
            for iy = -cells, cells do
              for ix = -cells, cells do
                local u, v = ix / cells, iy / cells
                local fx = u * rc - v * rs
                local fy = u * rs + v * rc
                local ex, ey = fx / 1.00, fy / 0.58
                local ed = math.sqrt(ex * ex + ey * ey)
                if ed >= 0.52 and ed <= 1.00 then
                  local t = (ed - 0.52) / 0.48
                  local gap = 1.0
                  if t > 0.38 and t < 0.55 then gap = 0.10 end
                  if t > 0.70 and t < 0.78 then gap = 0.40 end
                  local isFront = (fy >= 0)
                  if frontPass == isFront then
                    local distR = math.sqrt(
                      (fx * spanX) * (fx * spanX) + (fy * spanY) * (fy * spanY))
                    local draw = true
                    if (not frontPass) and distR < bodyHide then draw = false end
                    if draw then
                      safe(love.graphics.setColor, 0.96 * gap, 0.90 * gap, 0.72 * gap, a * 0.90 * gap)
                      safe(love.graphics.rectangle, "fill",
                        cx + fx * spanX - pix * 0.5,
                        cy + fy * spanY - pix * 0.5,
                        pix, pix)
                    end
                  end
                end
              end
            end
          end
          emitScreenRing(false)
          do
            local cellsB = 8
            local radB = rad * 1.06
            local pixB = radB / cellsB
            local lr = p.limbR or (p.r * 0.4)
            local lg = p.limbG or (p.g * 0.4)
            local lb = p.limbB or (p.b * 0.4)
            for iy = -cellsB, cellsB do
              for ix = -cellsB, cellsB do
                local fx, fy = ix / cellsB, iy / cellsB
                local d2 = fx * fx + fy * fy
                if d2 <= 1.02 then
                  local d = math.sqrt(d2)
                  local pr, pg, pb, pa2 = p.r, p.g, p.b, a
                  if d > 0.82 then
                    local tt = (d - 0.82) / 0.20
                    pr = p.r * (1 - tt) + lr * tt
                    pg = p.g * (1 - tt) + lg * tt
                    pb = p.b * (1 - tt) + lb * tt
                  end
                  safe(love.graphics.setColor, pr, pg, pb, pa2)
                  safe(love.graphics.rectangle, "fill",
                    cx + fx * radB - pixB * 0.5, cy + fy * radB - pixB * 0.5, pixB, pixB)
                end
              end
            end
          end
          emitScreenRing(true)
        end
        drawn = drawn + 1
      end
    end
  end

  if NightSky._drawMeteorsScreen then
    NightSky._drawMeteorsScreen(w, h, edge)
  end
  safe(love.graphics.setColor, 1, 1, 1, 1)
  if prev then safe(love.graphics.setBlendMode, prev[1], prev[2]) end
  return drawn > 0
end


-- ---------------------------------------------------------------------------
-- Robust projected celestial vault for voxel hosts.
--
-- 4.35.33 correctly removed the old Sky.region screen copy because that copy
-- scaled its Y coordinates by a camera-pitch-dependent sky height. On some
-- live voxel hosts, however, the custom 3D star mesh/shader can fail silently,
-- which left strict 3D with no stars or planets at all. This path is NOT the
-- old overlay: every star/planet/body keeps its fixed WORLD direction, that
-- direction is transformed by the host's exact Voxel3D.vp matrix, and the
-- result is drawn into the scene background before terrain. Camera pitch only
-- changes which directions enter the frustum; it never rescales the vault.
-- Terrain and the later volumetric cloud pass naturally draw over this layer.
-- ---------------------------------------------------------------------------
function NightSky._directionProjectionBasis(Voxel3D,w,h)
  if type(Voxel3D)~='table' then return nil end
  w=tonumber(w)or 160;h=tonumber(h)or 144

  -- The supported voxel hosts do not all give `focus` the same meaning. On
  -- several of them it is a player/world anchor (and may even be a static
  -- fallback inserted by the bridge), not the camera look target. Using
  -- eye->focus unconditionally therefore makes 2D sun/moon projection appear
  -- stapled to the camera. Prefer explicit live camera orientation first.
  local fx,fy,fz
  local cam=Voxel3D.camera
  local cf=cam and (cam.forward or cam.look)
  if type(cf)=='table' then
    fx,fy,fz=tonumber(cf[1]),tonumber(cf[2]),tonumber(cf[3])
  end
  if not (fx and fy and fz) then
    local FP=NightSky._FirstPerson
    if FP and type(FP.yaw)=='number' then
      local yaw=FP.yaw;local pitch=type(FP.pitch)=='number' and FP.pitch or 0;local cp=math.cos(pitch)
      fx,fy,fz=math.sin(yaw)*cp,-math.sin(pitch),math.cos(yaw)*cp
    end
  end
  if not (fx and fy and fz) then
    -- Several third-person hosts publish a live horizontal heading even when
    -- `focus` is only a player anchor. Prefer it over eye->focus so the 2D
    -- celestial layer follows camera yaw instead of a static fallback vector.
    local lf=Voxel3D.lookFlat
    if type(lf)=='table' then
      local x,z=tonumber(lf[1]),tonumber(lf[3] or lf[2])
      if x and z then fx,fy,fz=x,0,z end
    end
  end
  if not (fx and fy and fz) then
    -- Final compatibility fallback. Exact-zenith cameras are valid here and
    -- remain supported; live camera.forward / FirstPerson / lookFlat above
    -- win whenever the host exposes them.
    local e=Voxel3D.eye;local fo=Voxel3D.focus
    if type(e)=='table' and type(fo)=='table' then
      local tx=(tonumber(fo[1])or 0)-(tonumber(e[1])or 0)
      local ty=(tonumber(fo[2])or 0)-(tonumber(e[2])or 0)
      local tz=(tonumber(fo[3])or 0)-(tonumber(e[3])or 0)
      local l2=tx*tx+ty*ty+tz*tz
      if l2>1e-8 then fx,fy,fz=tx,ty,tz end
    end
  end
  if not (fx and fy and fz) then return nil end
  local fl=math.sqrt(fx*fx+fy*fy+fz*fz);if fl<=1e-7 then return nil end;fx,fy,fz=fx/fl,fy/fl,fz/fl

  local hl=math.sqrt(fx*fx+fz*fz);local rx,ry,rz
  if hl>1e-5 then
    rx,ry,rz=-fz/hl,0,fx/hl;NightSky._projectionRightX,NightSky._projectionRightZ=rx,rz
  else
    rx,ry,rz=tonumber(NightSky._projectionRightX)or 1,0,tonumber(NightSky._projectionRightZ)or 0
  end
  local ux=ry*fz-rz*fy;local uy=rz*fx-rx*fz;local uz=rx*fy-ry*fx
  local ul=math.sqrt(ux*ux+uy*uy+uz*uz);if ul>1e-7 then ux,uy,uz=ux/ul,uy/ul,uz/ul else ux,uy,uz=0,1,0 end
  local fov=tonumber(Voxel3D.fovY)or tonumber(cam and(cam.fovY or cam.fov))or math.rad(65);if fov>math.pi then fov=math.rad(fov)end;fov=math.max(math.rad(15),math.min(math.rad(150),fov))
  local tanHalf=math.tan(fov*.5);local aspect=math.max(.1,w/math.max(1,h));local b=NightSky._projectionBasisScratch or{};NightSky._projectionBasisScratch=b
  b.fx,b.fy,b.fz,b.rx,b.ry,b.rz,b.ux,b.uy,b.uz=fx,fy,fz,rx,ry,rz,ux,uy,uz;b.invX,b.invY=1/(tanHalf*aspect),1/tanHalf;b.w,b.h=w,h;return b
end

local function makeDirectionProjector(Voxel3D,w,h)
  w=tonumber(w)or 160;h=tonumber(h)or 144
  -- 8.2.2: the live 4x4 VP matrix is the only source that is guaranteed to
  -- contain BOTH camera yaw and pitch on every supported voxel camera. 8.1.99
  -- could choose horizontal-only lookFlat first; at steep upward pitch that
  -- projected sun/moon against a horizon camera and let them disappear. Prefer
  -- exact VP projection whenever the matrix is complete, then use basis fallbacks.
  local e=Voxel3D and Voxel3D.eye;local m=Voxel3D and Voxel3D.vp
  if type(e)=='table' and type(m)=='table' then
    local complete=true
    for i=1,16 do if type(m[i])~='number' then complete=false;break end end
    local perspective=complete and (math.abs(m[13] or 0)+math.abs(m[14] or 0)+math.abs(m[15] or 0)>1e-8)
    if perspective then
      local ex,ey,ez=tonumber(e[1])or 0,tonumber(e[2])or 0,tonumber(e[3])or 0
      return function(dx,dy,dz)
        local R=256;local x=ex+(tonumber(dx)or 0)*R;local y=ey+(tonumber(dy)or 0)*R;local z=ez+(tonumber(dz)or 0)*R
        local cx=m[1]*x+m[2]*y+m[3]*z+m[4];local cy=m[5]*x+m[6]*y+m[7]*z+m[8];local cw=m[13]*x+m[14]*y+m[15]*z+m[16]
        if not cw or cw<=1e-6 then return nil end
        local nx,ny=cx/cw,cy/cw
        if nx< -1.25 or nx>1.25 or ny< -1.25 or ny>1.25 then return nil end
        return(nx*.5+.5)*w,(ny*.5+.5)*h,cw
      end
    end
  end
  local b=NightSky._directionProjectionBasis(Voxel3D,w,h)
  if not b then return nil end
  return function(dx,dy,dz)
    dx,dy,dz=tonumber(dx)or 0,tonumber(dy)or 0,tonumber(dz)or 0;local front=dx*b.fx+dy*b.fy+dz*b.fz;if front<=1e-6 then return nil end
    local nx=(dx*b.rx+dy*b.ry+dz*b.rz)*b.invX/front;local ny=(dx*b.ux+dy*b.uy+dz*b.uz)*b.invY/front;if nx< -1.25 or nx>1.25 or ny< -1.25 or ny>1.25 then return nil end
    return(nx*.5+.5)*b.w,(.5-ny*.5)*b.h,front
  end
end

local function vpProjectDirection(Voxel3D,dx,dy,dz,w,h)
  local p=makeDirectionProjector(Voxel3D,w,h); if not p then return nil end
  return p(dx,dy,dz)
end

NightSky.projectDirection = vpProjectDirection

local function pushScreenTri(out,n,
    x1,y1,r1,g1,b1,a1,x2,y2,r2,g2,b2,a2,x3,y3,r3,g3,b3,a3)
  local function v(x,y,r,g,b,a)
    n=n+1
    local t=out[n]
    if not t then t={0,0,0,0,0,0,0,0};out[n]=t end
    t[1],t[2],t[3],t[4]=x,y,0,0;t[5],t[6],t[7],t[8]=r,g,b,a
  end
  v(x1,y1,r1,g1,b1,a1);v(x2,y2,r2,g2,b2,a2);v(x3,y3,r3,g3,b3,a3)
  return n
end

local function pushScreenQuad(out,n,cx,cy,half,r,g,b,a)
  half=math.max(.35,tonumber(half) or .5)
  local x0,x1=cx-half,cx+half; local y0,y1=cy-half,cy+half
  local function v(x,y)
    n=n+1
    local t=out[n]
    if not t then t={0,0,0,0,0,0,0,0}; out[n]=t end
    t[1],t[2],t[3],t[4]=x,y,0,0
    t[5],t[6],t[7],t[8]=r,g,b,a
  end
  v(x0,y0); v(x1,y0); v(x1,y1)
  v(x0,y0); v(x1,y1); v(x0,y1)
  return n
end

local function pushScreenDisc(out,n,cx,cy,rad,r,g,b,a,cells,limb)
  cells=math.max(3,math.floor(cells or 7)); rad=math.max(1,rad or 1)
  local pix=rad/cells
  for iy=-cells,cells do
    for ix=-cells,cells do
      local fx,fy=ix/cells,iy/cells
      local d2=fx*fx+fy*fy
      if d2<=1.02 then
        local d=math.sqrt(d2)
        local rr,gg,bb,aa=r,g,b,a
        if limb and d>.82 then
          local q=math.min(1,(d-.82)/.20)
          rr=r*(1-q)+r*.42*q; gg=g*(1-q)+g*.42*q; bb=b*(1-q)+b*.42*q
          aa=a*(1-q*.18)
        end
        n=pushScreenQuad(out,n,cx+fx*rad,cy+fy*rad,pix*.52,rr,gg,bb,aa)
      end
    end
  end
  return n
end

local SCREEN_RING_ARCS={}
local function screenRingArc(cells,yScale)
  local key=tostring(cells)..":"..tostring(yScale)
  local cached=SCREEN_RING_ARCS[key]; if cached then return cached end
  local out={}
  for j=-cells,cells do
    local u=j/cells
    out[#out+1]={u,math.sqrt(math.max(0,1-u*u))*yScale}
  end
  SCREEN_RING_ARCS[key]=out
  return out
end

local function pushScreenPlanetDisc(out,n,cx,cy,rad,p,a)
  local tpl=planetDiscTemplate(p)
  for i=1,#tpl do
    local q=tpl[i]; n=n+1
    local t=out[n]; if not t then t={0,0,0,0,0,0,0,0}; out[n]=t end
    t[1],t[2],t[3],t[4]=cx+q[1]*rad,cy+q[2]*rad,0,0
    t[5],t[6],t[7],t[8]=q[3],q[4],q[5],a
  end
  return n
end

local PROJECTED_DEPTH_SHADER = [[
#ifdef VERTEX
varying vec4 vProjectedColor;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vProjectedColor = VertexColor;
  vec4 clip = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
  clip.z = clip.w;
  return clip;
}
#endif
#ifdef PIXEL
varying vec4 vProjectedColor;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vProjectedColor * color;
}
#endif
]]
local function projectedDepthShader()
  if NightSky._projectedDepthShader ~= nil then return NightSky._projectedDepthShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then NightSky._projectedDepthShader=false; return nil end
  local ok,sh=safe(love.graphics.newShader,PROJECTED_DEPTH_SHADER)
  NightSky._projectedDepthShader=(ok and sh) or false
  return NightSky._projectedDepthShader or nil
end

local function drawScreenMesh(cacheName,verts,n,blend,depthAware)
  if n<3 or not (love and love.graphics) then return false end
  for i=n+1,#verts do verts[i]=nil end
  local mesh=NightSky[cacheName]
  local capKey=cacheName.."Capacity"
  local capacity=tonumber(NightSky[capKey]) or 0
  -- LÖVE meshes have a fixed vertex capacity. Recreate when a denser part of
  -- the vault enters view; when the count shrinks, setDrawRange prevents stale
  -- vertices from the previous frame from surviving at the edge of the sky.
  if not mesh or capacity<n then
    if mesh then safe(mesh.release,mesh) end
    local ok,m=safe(love.graphics.newMesh,verts,"triangles","stream")
    if not ok or not m then NightSky[cacheName]=nil; return false end
    mesh=m; NightSky[cacheName]=mesh; capacity=n; NightSky[capKey]=capacity; NightSky[capKey]=capacity
  elseif not safe(mesh.setVertices,mesh,verts,1) then
    safe(mesh.release,mesh); NightSky[cacheName]=nil; NightSky[capKey]=0
    local ok,m=safe(love.graphics.newMesh,verts,"triangles","stream")
    if not ok or not m then return false end
    mesh=m; NightSky[cacheName]=mesh; capacity=n
  end
  if mesh.setDrawRange then safe(mesh.setDrawRange,mesh,1,n) end
  local prevShader,prevDepth,prevWrite,prevBlend,prevAlpha,pr,pg,pb,pa
  safe(function() prevShader=love.graphics.getShader() end)
  safe(function() prevDepth,prevWrite=love.graphics.getDepthMode() end)
  safe(function() prevBlend,prevAlpha=love.graphics.getBlendMode() end)
  safe(function() pr,pg,pb,pa=love.graphics.getColor() end)
  local farShader = depthAware and projectedDepthShader() or nil
  if farShader then safe(love.graphics.setShader,farShader) else safe(love.graphics.setShader) end
  if depthAware then safe(love.graphics.setDepthMode,"lequal",false) else safe(love.graphics.setDepthMode) end
  safe(love.graphics.setBlendMode,blend or "add","alphamultiply")
  safe(love.graphics.setColor,1,1,1,1)
  local okDraw=safe(love.graphics.draw,mesh)
  if prevShader then safe(love.graphics.setShader,prevShader) else safe(love.graphics.setShader) end
  if prevDepth then safe(love.graphics.setDepthMode,prevDepth,prevWrite) else safe(love.graphics.setDepthMode,"lequal",true) end
  if prevBlend then safe(love.graphics.setBlendMode,prevBlend,prevAlpha) end
  if pr then safe(love.graphics.setColor,pr,pg,pb,pa) end
  return okDraw and true or false
end

local function projectedNightVisibility()
  local target=NightSky.computeNightVisibility()
  NightSky._nightVisRaw=target
  local TOD=NightSky._TOD
  -- Manual NITE/NIGHT is a presentation command. Snap to the current
  -- weather-attenuated target immediately instead of spending several seconds
  -- easing up from a previous DAY value after the user changes the menu.
  if TOD and (TOD.pin=="NITE" or TOD.pin=="NIGHT" or TOD.hostMode=="night") then
    NightSky._nightVis=target
    return target
  end
  if TOD and (TOD.pin=="DAY" or TOD.hostMode=="day") then NightSky._nightVis=0; return 0 end
  local v=tonumber(NightSky._nightVis) or target
  if math.abs(target-v)>.25 then v=target end
  NightSky._nightVis=clamp01(v)
  return NightSky._nightVis
end


local METEOR
local meteorProgress

local function appendMeteorsProjected(verts,n,project)
  n=n or 0
  if not project then return n end
  for i=1,#METEOR.active do
    local m=METEOR.active[i]; local u=meteorProgress(m)
    if u then
      local fade=1; if u<.12 then fade=u/.12 end; if u>.72 then fade=(1-u)/.28 end
      local travel=(u-.05)*m.speed*1.8; local sz=tonumber(m.size) or 1
      local function emit(back,k)
        local px=m.ox+m.dx*(travel-back); local py=m.oy+m.dy*(travel-back); local pz=m.oz+m.dz*(travel-back)
        local x,y=project(px,py,pz); if not (x and y) then return end
        local a=m.bright*fade*(k==0 and 1 or math.max(.05,1-k/((tonumber(m.tail) or 5)+1))*.72)
        local half=(k==0 and 2.5 or math.max(.55,2.0-k*.10))*sz
        n=pushScreenQuad(verts,n,x,y,half,k==0 and 1.0 or .82,k==0 and .96 or .88,k==0 and .86 or 1.0,a)
        if k==0 then n=pushScreenQuad(verts,n,x,y,half*.42,1,1,1,a) end
      end
      emit(0,0)
      for k=1,(tonumber(m.tail) or 5) do emit(k*.035,k) end
    end
  end
  return n
end

function NightSky.drawProjectedWorld(Voxel3D,time,w,h)
  if not (Voxel3D and Voxel3D.vp and Voxel3D.eye) then return false end
  if not (love and love.graphics) then return false end
  if (not w or not h) and Voxel3D.size then
    local ok,cw,ch=safe(Voxel3D.size); if ok then w,h=cw,ch end
  end
  w=tonumber(w) or 160; h=tonumber(h) or 144
  local project=makeDirectionProjector(Voxel3D,w,h); if not project then return false end
  local nightVis=projectedNightVisibility()
  if nightVis<.02 then return false end
  local t=tonumber(time) or 0
  local scale=starScaleNow()*NightSky._nightSkyBrightnessScale(); local lod=celestialLod(); local step=lod.starStep or 1
  local Sim=celestialSimModule()
  local vaultAng=(Sim and Sim.starVaultAngle and Sim.starVaultAngle()) or (Sim and Sim.siderealAngle and (Sim.siderealAngle()*(Sim.STAR_VAULT_RATE or 0.25))) or ((Sim and Sim.solarAlpha and Sim.solarAlpha()) or 0)
  local rotate=(Sim and Sim.starRotator and Sim.starRotator(vaultAng)) or function(dx,dy,dz) return rotateY(dx,dy,dz,vaultAng) end
  local horizonFade=Sim and Sim.horizonFade or nil
  local buildingFactor=buildingFactorNow()
  local verts=NightSky._projectedVerts or {}; NightSky._projectedVerts=verts
  local n,visible=0,0
  local projectionBasis=NightSky._directionProjectionBasis(Voxel3D,w,h)
  local gpuStars,gpuStarCount=false,0
  if projectionBasis then gpuStars,gpuStarCount=NightSky._drawInstancedProjectedStars(STARS,{basis=projectionBasis,vaultAngle=vaultAng,time=t,visibility=nightVis,scale=scale,buildingFactor=buildingFactor,twinkle=lod.twinkle}) end
  if gpuStars then visible=visible+gpuStarCount else
    for i=1,#STARS,step do
      local s=STARS[i];local fade=NightSky.starFade(s,nightVis);local dens=s.hideNearBuilding and buildingFactor or 1
      if fade>.01 and dens>.02 then local dx,dy,dz=rotate(s.dx,s.dy,s.dz);local hf=horizonFade and horizonFade(dy) or(dy>0 and 1 or 0);if hf>.02 then local x,y=project(dx,dy,dz);if x and y then local tw=lod.twinkle and NightSky.twinkleAlpha(s,t) or 1;local a=s.a*scale*fade*dens*tw*hf;local half=math.max(.72,(s.size or 1)*.52);n=pushScreenQuad(verts,n,x,y,half,s.r,s.g,s.b,a);visible=visible+1 end end end
    end
  end
  local pverts=NightSky._projectedPlanetVerts or {}; NightSky._projectedPlanetVerts=pverts
  local pn=0
  local nPlan=math.min(#PLANETS,lod.maxPlanets or #PLANETS)
  for i=1,nPlan do
    local p=PLANETS[i]; local fade=NightSky.starFade(p,nightVis)
    if fade>.01 then
      local dx,dy,dz=rotate(p.dx,p.dy,p.dz)
      local hf=horizonFade and horizonFade(dy) or (dy>0 and 1 or 0)
      if hf>.02 then
        local x,y=project(dx,dy,dz)
        if x and y then
          local a=p.a*scale*fade*hf
          local pscale=(p.feature=="rings" or p.feature=="x_rings") and SATURN_SIZE_SCALE or PLANET_SIZE_SCALE
          local rad=math.max(2.8,(p.size or 5)*1.25*pscale)
          if p.feature=="rings" then
            local cells=22; local pix=rad*.16; local arc=screenRingArc(cells,.48)
            for k=1,#arc do
              local q=arc[k]; local u,yy=q[1],q[2]
              if math.abs(u)>.42 then
                pn=pushScreenQuad(pverts,pn,x+u*rad*2.2,y-yy*rad*1.25,pix,.96,.90,.72,a*.58)
              end
            end
            pn=pushScreenPlanetDisc(pverts,pn,x,y,rad*1.06,p,a)
            for k=1,#arc do
              local q=arc[k]; local u,yy=q[1],q[2]
              pn=pushScreenQuad(pverts,pn,x+u*rad*2.2,y+yy*rad*1.25,pix,.96,.90,.72,a*.76)
            end
          elseif p.feature=="x_rings" then
            local cells=20; local pix=rad*.14; local arc=screenRingArc(cells,.50)
            local bodyRad=rad*(tonumber(p.xBodyScale) or 1.42)
            local function emitCross(angle,front)
              local rc,rs=math.cos(angle),math.sin(angle)
              local function emit(u,vv)
                local fx=u*rc-vv*rs; local fy=u*rs+vv*rc
                if (fy>=0)==front then
                  local dist=math.sqrt((fx*rad*2.15)^2+(fy*rad*1.18)^2)
                  if front or dist>=bodyRad*.98 then
                    pn=pushScreenQuad(pverts,pn,x+fx*rad*2.15,y+fy*rad*1.18,pix,p.ringR or .98,p.ringG or .82,p.ringB or .38,a*.72)
                  end
                end
              end
              for k=1,#arc do local q=arc[k]; emit(q[1],-q[2]); emit(q[1],q[2]) end
            end
            emitCross(math.rad(45),false); emitCross(math.rad(-45),false)
            pn=pushScreenPlanetDisc(pverts,pn,x,y,bodyRad,p,a)
            emitCross(math.rad(45),true); emitCross(math.rad(-45),true)
          else
            pn=pushScreenPlanetDisc(pverts,pn,x,y,rad,p,a)
          end
          visible=visible+1
        end
      end
    end
  end
  if Aurora and Aurora.appendProjected then
    n=Aurora.appendProjected(verts,n,pushScreenTri,project,t,nightVis) or n
  end

  -- Projected fallback uses the same dim/cloud-attenuated traced catalogue.
  local constVis=math.min(1.3,constellationVisibility(nightVis)*NightSky._nightSkyBrightnessScale())
  local constBuilding=constellationBuildingScale()
  if Constellations and type(Constellations.STARS)=="table" and constVis>.02 then
    for i=1,#Constellations.STARS do
      local cs=Constellations.STARS[i]; local dx,dy,dz=rotate(cs.dx,cs.dy,cs.dz)
      local hf=horizonFade and horizonFade(dy) or (dy>0 and 1 or 0)
      if hf>.02 then
        local x,y=project(dx,dy,dz)
        if x and y then
          local tw=NightSky.twinkleAlpha(cs,t)
          local ca=math.min(1,(cs.a or .34)*(cs.constGain or 1)*constVis*constBuilding*hf*(.95+.05*tw))
          local half=cs.atlasExact and math.max(.90,(cs.size or .92)*.64) or math.max(.72,(cs.size or .86)*.48)
          n=pushScreenQuad(verts,n,x,y,half,cs.r,cs.g,cs.b,ca)
          if cs.primary then n=pushScreenQuad(verts,n,x,y,half*.23,1,1,1,ca*.28) end
        end
      end
    end
  end
  if lod.meteors then n=appendMeteorsProjected(verts,n,project) end
  local ok=drawScreenMesh("_projectedMesh",verts,n,"add",true)
  local pok=drawScreenMesh("_projectedPlanetMesh",pverts,pn,"alpha",true)
  NightSky._lastProjectedProof={vertices=n,planetVertices=pn,objects=visible,visibility=nightVis,w=w,h=h,starBackend=gpuStars and 'instanced' or 'cpu'}
  return gpuStars or ((ok or pok) and (n>=3 or pn>=3))
end

-- 8.1.16 physically richer analytic celestial bodies. The bodies remain one
-- seamless far-depth quad each, but the fragment shader now reconstructs a
-- curved photosphere/lunar sphere with continuous multi-scale surface relief.
-- This keeps the 8.1.15 grid-seam fix while making the bodies survive gameplay
-- scale instead of collapsing into smooth shaded circles.
NightSky._projectedBodyShaderSource = NightSky._projectedBodyShaderSource or [[
varying vec2 vBodyUV;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  // LÖVE 11.5 exposes VertexTexCoord as vec4 on this host; the body UV
  // varying is vec2. Explicit swizzle avoids a real GLSL validation failure.
  vBodyUV = VertexTexCoord.xy;
  vec4 clip = transform_projection * vec4(vertex_position.xy, 0.0, 1.0);
  clip.z = clip.w;
  return clip;
}
#endif
#ifdef PIXEL
uniform vec3 bodyColor;
uniform float bodyAlpha;
uniform float bodyKind;       // 0 sun, 1 moon
uniform float altitudeDeg;
uniform float radiusDeg;
uniform float phase;
uniform float illumination;
uniform float lunarDark;
uniform float solarEclipse;
uniform float bodyTime;

float h21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123);
}
float valueNoise(vec2 p) {
  vec2 i=floor(p), f=fract(p);
  f=f*f*(3.0-2.0*f);
  float a=h21(i), b=h21(i+vec2(1.0,0.0));
  float c=h21(i+vec2(0.0,1.0)), d=h21(i+vec2(1.0,1.0));
  return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float fbm(vec2 p) {
  float v=0.0, a=0.53;
  v+=a*valueNoise(p); p=mat2(1.62,-1.17,1.17,1.62)*p+7.1; a*=0.50;
  v+=a*valueNoise(p); p=mat2(1.54,-1.21,1.21,1.54)*p+3.7; a*=0.50;
  v+=a*valueNoise(p); p=mat2(1.73,-1.08,1.08,1.73)*p+5.3; a*=0.50;
  v+=a*valueNoise(p);
  return v;
}
float softCircle(vec2 p, vec2 c, float r, float soft) {
  float d=length(p-c);
  return 1.0-smoothstep(r-soft,r+soft,d);
}
float softEllipse(vec2 p, vec2 c, vec2 r, float soft) {
  float d=length((p-c)/r);
  return 1.0-smoothstep(1.0-soft,1.0+soft,d);
}
float craterRelief(vec2 p, vec2 c, float r, vec2 lightDir) {
  vec2 q=(p-c)/r; float d=length(q);
  float bowl=(1.0-smoothstep(0.18,0.92,d))*0.18;
  float rim=exp(-pow((d-0.88)*9.5,2.0))*0.20;
  float innerShadow=max(0.0,dot(normalize(q+vec2(0.0001)), -lightDir));
  float innerLight=max(0.0,dot(normalize(q+vec2(0.0001)), lightDir));
  float rel=1.0-bowl*(0.68+0.32*innerShadow)+rim*(0.48+0.52*innerLight);
  return mix(1.0,rel,1.0-smoothstep(0.92,1.08,d));
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 p=vBodyUV*2.0-1.0;
  float rr=dot(p,p);
  if (rr>1.0) discard;
  // UV y increases downward. Clip only the physically hidden portion of the
  // disc at the horizon, retaining first-limb sunrise/sunset continuity.
  if (altitudeDeg - p.y*radiusDeg < 0.0) discard;
  float mu=sqrt(max(0.0,1.0-rr));
  float edge=smoothstep(0.0,0.026,1.0-sqrt(rr));

  if (bodyKind < 0.5) {
    // The sun is not a painted orange ball. Reconstruct a hot photosphere with
    // coherent moving granulation, brighter inter-granular faculae, broad
    // active regions and real limb darkening. Motion is deliberately slow so
    // the surface feels enormous rather than like scrolling fire texture.
    vec2 flow=vec2(bodyTime*0.0035,-bodyTime*0.0021);
    float n1=fbm(p*6.2+flow);
    float n2=fbm(p*15.5-flow*1.7+19.0);
    float network=abs(n1-n2);
    float supergran=0.5+0.5*sin((p.x*8.0+p.y*5.5)+n1*5.0);
    float gran=0.82+0.24*n1+0.14*n2+0.055*supergran;
    float facula=smoothstep(0.20,0.48,network)*(0.12+0.19*(1.0-mu));

    // Active regions use soft umbra/penumbra structure; no quantised cells.
    float pen1=softEllipse(p,vec2(-0.30,0.14),vec2(0.16,0.095),0.22);
    float umb1=softEllipse(p,vec2(-0.31,0.145),vec2(0.060,0.035),0.30);
    float pen2=softEllipse(p,vec2(0.28,-0.20),vec2(0.105,0.070),0.24);
    float umb2=softEllipse(p,vec2(0.285,-0.205),vec2(0.040,0.026),0.30);
    float pen3=softEllipse(p,vec2(0.08,0.39),vec2(0.075,0.048),0.26);
    float spots=clamp(pen1*0.26+umb1*0.48+pen2*0.22+umb2*0.42+pen3*0.18,0.0,0.68);

    // Photographic limb darkening with a hot near-white centre and slightly
    // warmer grazing edge. Low-altitude bodyColor still supplies atmospheric
    // sunrise/sunset reddening; this term supplies the solar material itself.
    // Keep real limb darkening, but do not let a radial gradient overpower
    // the photospheric structure at gameplay scale.
    float limb=0.70+0.30*pow(mu,0.42);
    vec3 hot=mix(vec3(1.0,0.60,0.12),vec3(1.0,0.985,0.83),pow(mu,0.50));
    vec3 atmospheric=mix(hot,bodyColor,0.30);
    vec3 rgb=atmospheric*limb*gran*(1.0-spots);
    rgb+=vec3(1.0,0.82,0.34)*facula*(0.35+0.65*mu);
    rgb*=mix(1.0,0.24,solarEclipse);
    return vec4(rgb,bodyAlpha*edge)*color;
  }

  // Lunar phase stays continuous, but the lit face now has enough real relief
  // to compete visually with the star/constellation field: broad maria,
  // overlapping crater bowls/rims, highland mottling and subtle earthshine.
  float limbX=sqrt(max(0.0,1.0-p.y*p.y));
  float term=(1.0-2.0*illumination)*limbX;
  float litMask;
  if (phase < 0.5) litMask=smoothstep(term-0.020,term+0.020,p.x);
  else litMask=1.0-smoothstep(-term-0.020,-term+0.020,p.x);

  vec2 phaseLight=normalize(vec2(phase<0.5?1.0:-1.0,-0.30));
  float highlands=0.80+0.22*fbm(p*7.0+31.0)+0.11*fbm(p*19.0-9.0)+0.045*fbm(p*43.0+4.0);
  float maria=1.0
    -0.22*softEllipse(p,vec2(-0.30,0.12),vec2(0.31,0.22),0.22)
    -0.15*softEllipse(p,vec2(0.22,0.29),vec2(0.22,0.17),0.22)
    -0.12*softEllipse(p,vec2(0.16,-0.34),vec2(0.20,0.15),0.20)
    -0.10*softEllipse(p,vec2(-0.02,-0.03),vec2(0.17,0.12),0.24)
    -0.08*softEllipse(p,vec2(-0.47,0.43),vec2(0.12,0.09),0.24);
  float cr=1.0;
  cr*=craterRelief(p,vec2(-0.43,-0.18),0.115,phaseLight);
  cr*=craterRelief(p,vec2(0.20,0.44),0.098,phaseLight);
  cr*=craterRelief(p,vec2(0.48,-0.38),0.086,phaseLight);
  cr*=craterRelief(p,vec2(-0.14,0.66),0.070,phaseLight);
  cr*=craterRelief(p,vec2(0.04,0.06),0.082,phaseLight);
  cr*=craterRelief(p,vec2(0.35,0.08),0.052,phaseLight);
  cr*=craterRelief(p,vec2(-0.55,0.28),0.045,phaseLight);
  cr*=craterRelief(p,vec2(0.10,-0.62),0.058,phaseLight);
  cr*=craterRelief(p,vec2(-0.24,-0.48),0.041,phaseLight);
  cr*=craterRelief(p,vec2(0.57,0.32),0.037,phaseLight);

  // A subdued Tycho-like bright ejecta field prevents the southern highlands
  // from reading as featureless while staying far below fantasy glow levels.
  vec2 ty=p-vec2(0.10,-0.62); float tyd=length(ty);
  float rays=max(0.0,cos(atan(ty.y,ty.x)*7.0))*exp(-tyd*3.0)*(1.0-smoothstep(0.06,0.72,tyd));
  float rough=highlands*maria*cr + rays*0.055;
  vec3 neutral=mix(vec3(0.64,0.66,0.67),vec3(0.94,0.94,0.90),0.58+0.42*mu);
  // Lunar relief must read as maria/craters, not a generic centre-bright
  // sphere. Use only subtle limb rolloff and let terrain carry the contrast.
  vec3 lit=mix(neutral,bodyColor,0.22)*(0.79+0.21*mu)*rough;
  if (lunarDark>0.0) lit=mix(lit,vec3(0.62,0.09,0.045),lunarDark*0.82);
  float earth=0.018+0.050*(1.0-illumination);
  float darkA=mix(earth,0.94,solarEclipse);
  vec3 dark=vec3(0.030,0.036,0.050)*(0.66+0.34*mu)*(0.82+0.18*highlands);
  vec3 rgb=mix(dark,lit,litMask);
  float a=bodyAlpha*mix(darkA,0.82+0.18*mu,litMask)*edge;
  return vec4(rgb,a)*color;
}
#endif
]]

function NightSky._projectedBodyShader()
  if NightSky._projectedBodyShaderState ~= nil then return NightSky._projectedBodyShaderState or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    NightSky._projectedBodyShaderError='love.graphics.newShader unavailable'
    -- Do not poison the session forever if the first probe happened before the
    -- host finished bringing up its graphics backend.
    return nil
  end
  local ok,sh=safe(love.graphics.newShader,NightSky._projectedBodyShaderSource)
  if ok and sh then
    NightSky._projectedBodyShaderState=sh; NightSky._projectedBodyShaderError=nil
  else
    NightSky._projectedBodyShaderState=false; NightSky._projectedBodyShaderError=tostring(sh or 'shader compilation refused')
  end
  return NightSky._projectedBodyShaderState or nil
end

function NightSky._pushProjectedBodyQuad(out,n,cx,cy,rad)
  local x0,x1=cx-rad,cx+rad; local y0,y1=cy-rad,cy+rad
  local function v(x,y,u,vv)
    n=n+1; local t=out[n]; if not t then t={0,0,0,0,1,1,1,1}; out[n]=t end
    t[1],t[2],t[3],t[4]=x,y,u,vv; t[5],t[6],t[7],t[8]=1,1,1,1
  end
  v(x0,y0,0,0); v(x1,y0,1,0); v(x1,y1,1,1)
  v(x0,y0,0,0); v(x1,y1,1,1); v(x0,y1,0,1)
  return n
end

local FALLBACK_MOON_CRATERS={
  {-0.43,-0.18,.115},{.20,.44,.098},{.48,-.38,.086},{-.14,.66,.070},{.04,.06,.082},
  {.35,.08,.052},{-.55,.28,.045},{.10,-.62,.058},{-.24,-.48,.041},{.57,.32,.037}
}
local function fallbackEllipse(x,y,cx,cy,rx,ry)
  local dx=(x-cx)/rx; local dy=(y-cy)/ry; local d=dx*dx+dy*dy
  if d>=1 then return 0 end
  local q=1-d; return q*q*(3-2*q)
end
local function fallbackBodySample(body,kind,x,y,altDeg,radiusDeg,time)
  local rr=x*x+y*y
  if rr>1 then return 0,0,0,0 end
  if (tonumber(altDeg) or 90)-y*(tonumber(radiusDeg) or 1)<0 then return 0,0,0,0 end
  local mu=math.sqrt(math.max(0,1-rr)); local edge=math.min(1,math.max(0,(1-math.sqrt(rr))/.045))
  local c=body and body.color or (kind=='moon' and {.73,.80,1.0} or {1,.88,.42})
  local alpha=clamp01(tonumber(body and body.alpha) or 0)
  if kind=='sun' then
    -- CPU fallback for hosts that reject the analytic shader. Keep a real
    -- photosphere instead of collapsing to the old dark-rim/bright-centre disc.
    local t=tonumber(time) or 0
    local gran=.91+.055*math.sin(x*39+y*31+t*.021)+.040*math.sin(x*83-y*57-t*.014)+.025*math.sin(x*151+y*127+t*.009)
    local p1=fallbackEllipse(x,y,-.30,.14,.16,.095); local u1=fallbackEllipse(x,y,-.31,.145,.060,.035)
    local p2=fallbackEllipse(x,y,.28,-.20,.105,.070); local u2=fallbackEllipse(x,y,.285,-.205,.040,.026)
    local p3=fallbackEllipse(x,y,.08,.39,.075,.048)
    local spots=math.min(.58,p1*.20+u1*.36+p2*.17+u2*.31+p3*.13)
    local limb=.72+.28*(mu^.34) -- subtle limb darkening; texture remains dominant
    local hotR=1
    local hotG=.67+.315*(mu^.50)
    local hotB=.16+.67*(mu^.50)
    local r=hotR*.70+(c[1] or 1)*.30
    local g=hotG*.70+(c[2] or .88)*.30
    local b=hotB*.70+(c[3] or .42)*.30
    local fac=math.max(0,math.sin((x-y)*47+t*.016))*math.max(0,1-mu)*.055
    local e=clamp01(tonumber(body and body.solarEclipse) or 0)
    local shade=limb*gran*(1-spots)*(1-.76*e)
    return math.min(1.18,r*shade+fac),math.min(1.12,g*shade+fac*.78),math.min(1.04,b*shade+fac*.30),alpha*edge
  end

  local illum=clamp01(tonumber(body and body.illumination) or 1)
  local phase=(tonumber(body and body.phase) or .5)%1
  local limbX=math.sqrt(math.max(0,1-y*y)); local term=(1-2*illum)*limbX
  local lit=(phase<.5 and x>=term) or (phase>=.5 and x<=-term)
  local eclipse=clamp01(tonumber(body and body.solarEclipse) or 0)
  if not lit then
    local earth=.018+.05*(1-illum); local a=alpha*(earth+(.94-earth)*eclipse)
    return .030*(.72+.28*mu),.036*(.72+.28*mu),.052*(.72+.28*mu),a*edge
  end
  local maria=1-.22*fallbackEllipse(x,y,-.30,.12,.31,.22)-.15*fallbackEllipse(x,y,.22,.29,.22,.17)
                  -.12*fallbackEllipse(x,y,.16,-.34,.20,.15)-.10*fallbackEllipse(x,y,-.02,-.03,.17,.12)
                  -.08*fallbackEllipse(x,y,-.47,.43,.12,.09)
  local cr=1
  local lightx=(phase<.5) and 1 or -1
  for i=1,#FALLBACK_MOON_CRATERS do
    local q=FALLBACK_MOON_CRATERS[i]; local dx,dy=x-q[1],y-q[2]; local d=math.sqrt(dx*dx+dy*dy)/(q[3] or .05)
    if d<1.08 then
      local bowl=(1-math.min(1,d))*.15
      local rim=math.max(0,1-math.abs(d-.88)/.16)*.12
      local side=(dx*lightx-dy*.30)/(q[3] or .05)
      cr=cr*(1-bowl*(.76+.16*math.max(0,-side))+rim*(.62+.18*math.max(0,side)))
    end
  end
  local rough=.91+.055*math.sin(x*41+y*37)+.035*math.sin(x*103-y*79)+.020*math.sin(x*191+y*149)
  local limb=.78+.22*mu
  local neutralR=.82+.12*mu; local neutralG=.83+.11*mu; local neutralB=.82+.08*mu
  local r=(neutralR*.78+(c[1] or .73)*.22)*limb*maria*cr*rough
  local g=(neutralG*.78+(c[2] or .80)*.22)*limb*maria*cr*rough
  local b=(neutralB*.78+(c[3] or 1)*.22)*limb*maria*cr*rough
  local ld=clamp01(tonumber(body and body.lunarEclipse) or 0)
  if ld>0 then r=r*(1-ld)+.62*ld; g=g*(1-ld*.72); b=b*(1-ld*.90) end
  return r,g,b,alpha*(.84+.16*mu)*edge
end

function NightSky._drawProjectedBodyFallback(cacheName,verts,n,body,kind,altDeg,radiusDeg)
  -- 8.1.26: shader refusal is a quality fallback, not a visual downgrade.
  -- Rebuild the same circular body as a high-detail coloured polar mesh with
  -- solar granulation/sunspots or lunar maria/crater relief. This is slower
  -- than the shader but only runs on hosts that cannot compile it.
  if n<3 or not (verts[1] and verts[3]) then return false end
  local x0,y0=tonumber(verts[1][1]),tonumber(verts[1][2]); local x1,y1=tonumber(verts[3][1]),tonumber(verts[3][2])
  if not (x0 and y0 and x1 and y1) then return false end
  local cx,cy=(x0+x1)*.5,(y0+y1)*.5; local rad=math.max(.5,math.abs(x1-x0)*.5)
  local fv=NightSky[cacheName..'FallbackVerts'] or {}; NightSky[cacheName..'FallbackVerts']=fv
  local fn=0; local rings,segs=18,84; local bodyTime=tonumber(NightSky._visualTime) or 0
  local function emit(nx,ny)
    local r,g,b,a=fallbackBodySample(body,kind,nx,ny,altDeg,radiusDeg,bodyTime)
    fn=fn+1; local t=fv[fn] or {0,0,0,0,0,0,0,0}; fv[fn]=t
    t[1],t[2],t[3],t[4]=cx+nx*rad,cy+ny*rad,0,0; t[5],t[6],t[7],t[8]=r,g,b,a
  end
  for ring=1,rings do
    local r0=(ring-1)/rings; local r1=ring/rings
    for s=1,segs do
      local a0=(s-1)/segs*math.pi*2; local a1=s/segs*math.pi*2
      local x00,y00=math.cos(a0)*r0,math.sin(a0)*r0; local x10,y10=math.cos(a0)*r1,math.sin(a0)*r1
      local x11,y11=math.cos(a1)*r1,math.sin(a1)*r1; local x01,y01=math.cos(a1)*r0,math.sin(a1)*r0
      emit(x00,y00);emit(x10,y10);emit(x11,y11);emit(x00,y00);emit(x11,y11);emit(x01,y01)
    end
  end
  NightSky._lastProjectedBodyPath='detailed-cpu-fallback'
  return drawScreenMesh(cacheName..'FallbackMesh',fv,fn,'alpha',true)
end

function NightSky._drawProjectedBody(cacheName,verts,n,body,kind,altDeg,radiusDeg)
  if n<3 or not (love and love.graphics) then return false end
  for i=n+1,#verts do verts[i]=nil end
  local mesh=NightSky[cacheName]
  if not mesh then
    local ok,m=safe(love.graphics.newMesh,verts,"triangles","stream"); if not (ok and m) then return false end; mesh=m; NightSky[cacheName]=mesh
  elseif not safe(mesh.setVertices,mesh,verts,1) then
    safe(mesh.release,mesh); NightSky[cacheName]=nil
    local ok,m=safe(love.graphics.newMesh,verts,"triangles","stream"); if not (ok and m) then return false end; mesh=m; NightSky[cacheName]=mesh
  end
  if mesh.setDrawRange then safe(mesh.setDrawRange,mesh,1,n) end
  local sh=NightSky._projectedBodyShader(); if not sh then return NightSky._drawProjectedBodyFallback(cacheName,verts,n,body,kind,altDeg,radiusDeg) end
  local prevShader,prevDepth,prevWrite,prevBlend,prevAlpha,pr,pg,pb,pa
  safe(function() prevShader=love.graphics.getShader() end); safe(function() prevDepth,prevWrite=love.graphics.getDepthMode() end)
  safe(function() prevBlend,prevAlpha=love.graphics.getBlendMode() end); safe(function() pr,pg,pb,pa=love.graphics.getColor() end)
  safe(love.graphics.setShader,sh); safe(love.graphics.setDepthMode,"lequal",false); safe(love.graphics.setBlendMode,"alpha","alphamultiply"); safe(love.graphics.setColor,1,1,1,1)
  local c=body and body.color or (kind=="moon" and {.73,.80,1.0} or {1,.88,.42})
  safe(sh.send,sh,"bodyColor",{tonumber(c[1]) or 1,tonumber(c[2]) or 1,tonumber(c[3]) or 1})
  safe(sh.send,sh,"bodyAlpha",clamp01(tonumber(body and body.alpha) or 0)); safe(sh.send,sh,"bodyKind",kind=="moon" and 1 or 0)
  safe(sh.send,sh,"altitudeDeg",tonumber(altDeg) or 90); safe(sh.send,sh,"radiusDeg",tonumber(radiusDeg) or 1)
  safe(sh.send,sh,"phase",(tonumber(body and body.phase) or .5)%1); safe(sh.send,sh,"illumination",clamp01(tonumber(body and body.illumination) or 1))
  safe(sh.send,sh,"lunarDark",clamp01(tonumber(body and body.lunarEclipse) or 0)); safe(sh.send,sh,"solarEclipse",clamp01(tonumber(body and body.solarEclipse) or 0))
  safe(sh.send,sh,"bodyTime",tonumber(NightSky._visualTime) or 0)
  local okDraw=safe(love.graphics.draw,mesh)
  if okDraw then NightSky._lastProjectedBodyPath='analytic-shader' end
  if prevShader then safe(love.graphics.setShader,prevShader) else safe(love.graphics.setShader) end
  if prevDepth then safe(love.graphics.setDepthMode,prevDepth,prevWrite) else safe(love.graphics.setDepthMode,"lequal",true) end
  if prevBlend then safe(love.graphics.setBlendMode,prevBlend,prevAlpha) end; if pr then safe(love.graphics.setColor,pr,pg,pb,pa) end
  return okDraw
end

function NightSky.draw2DCelestialBody(body,kind,w,h,edge,cell)
  if not (body and body.x and body.y and love and love.graphics) then return false end
  w=tonumber(w) or 160; h=tonumber(h) or 144; edge=tonumber(edge) or h*.42; cell=math.max(1,tonumber(cell) or 4)
  kind=kind or (body.moon and 'moon' or 'sun')
  local logical={
    color=body._wxColor,alpha=body._wxAlpha,phase=body._wxPhase,illumination=body._wxIllumination,
    solarEclipse=body._wxSolarEclipse,lunarEclipse=body._wxLunarEclipse
  }
  local rad=math.max(cell*3,h*.028)
  local bx=tonumber(body.x) or w*.5; local by=tonumber(body.y) or edge*.5
  local verts=NightSky[kind=='moon' and '_2dMoonVerts' or '_2dSunVerts'] or {}
  if kind=='moon' then NightSky._2dMoonVerts=verts else NightSky._2dSunVerts=verts end
  local n=NightSky._pushProjectedBodyQuad(verts,0,bx,by,rad)
  local alt=tonumber(body._wxAltitudeDeg) or 90; local rd=(kind=='moon') and 3.0 or 4.5
  return NightSky._drawProjectedBody(kind=='moon' and '_2dMoonMesh' or '_2dSunMesh',verts,n,logical,kind,alt,rd)
end

local function screenRadiusFor(Voxel3D,h,halfWorld,radiusWorld)
  local fov=tonumber(Voxel3D and Voxel3D.fovY) or math.rad(65)
  fov=math.max(math.rad(15),math.min(math.rad(150),fov))
  local ang=math.atan((tonumber(halfWorld) or 1)/math.max(1,tonumber(radiusWorld) or 280))
  return math.max(1.2,math.tan(ang)/math.max(.01,math.tan(fov*.5))*(h*.5))
end

function NightSky.drawSunMoonProjectedWorld(Voxel3D,w,h)
  if not (Voxel3D and Voxel3D.eye and love and love.graphics) then return false end
  if (not w or not h) and Voxel3D.size then local ok,cw,ch=safe(Voxel3D.size); if ok then w,h=cw,ch end end
  w=tonumber(w) or 160; h=tonumber(h) or 144
  local project=makeDirectionProjector(Voxel3D,w,h); if not project then return false end
  local CB; safe(function() CB=V.require("CelestialBodies") end); local b=CB and CB.bodies and CB.bodies() or nil
  if not (b and b.sun and b.moon) then return false end
  local sunVerts=NightSky._projectedSunVerts or {}; NightSky._projectedSunVerts=sunVerts
  local moonVerts=NightSky._projectedMoonVerts or {}; NightSky._projectedMoonVerts=moonVerts; local sn,mn=0,0
  local function visible(body)
    if not body then return false end
    if body.discTransmission~=nil and (tonumber(body.discTransmission) or 0)<=.02 then return false end
    if body.horizonFraction~=nil then return (tonumber(body.horizonFraction) or 0)>0 and (tonumber(body.alpha) or 0)>.0001 end
    return (tonumber(body.alpha) or 0)>.02
  end
  local sunRad,moonRad,sunAlt,moonAlt
  if visible(b.sun) then
    local x,y=project(b.sun.dx,b.sun.dy,b.sun.dz)
    if x and y then
      sunAlt=tonumber(b.sun.altitudeDeg); sunRad=screenRadiusFor(Voxel3D,h,15.84,280)
      sn=NightSky._pushProjectedBodyQuad(sunVerts,sn,x,y,sunRad)
    end
  end
  if visible(b.moon) then
    local x,y=project(b.moon.dx,b.moon.dy,b.moon.dz)
    if x and y then
      moonAlt=tonumber(b.moon.altitudeDeg); moonRad=screenRadiusFor(Voxel3D,h,10.08*(tonumber(b.moon.apparentScale) or 1),280)
      mn=NightSky._pushProjectedBodyQuad(moonVerts,mn,x,y,moonRad)
    end
  end
  local ds=NightSky._drawProjectedBody("_projectedSunMesh",sunVerts,sn,b.sun,"sun",sunAlt,3.24)
  local dm=NightSky._drawProjectedBody("_projectedMoonMesh",moonVerts,mn,b.moon,"moon",moonAlt,2.16*(tonumber(b.moon.apparentScale) or 1))
  NightSky._lastProjectedBodies={sunVertices=sn,moonVertices=mn,hour=b.hour,sunRadius=sunRad,moonRadius=moonRad,analytic=true}
  return ds or dm
end

function NightSky.projectedProof()
  return NightSky._lastProjectedProof,NightSky._lastProjectedBodies,{bodyPath=NightSky._lastProjectedBodyPath,shaderError=NightSky._projectedBodyShaderError}
end

function NightSky.applyWeatherBands(bands, skyInfo)
  if not (bands and skyInfo and skyInfo.color and (skyInfo.blend or 0) > 0) then
    return bands
  end
  local b = math.min(1, math.max(0, skyInfo.blend))
  local c = skyInfo.color
  local flash = skyInfo.flash or 0
  local out = {}
  for i = 1, #bands do
    local band = bands[i]
    local r = band[1] or 0
    local g = band[2] or 0
    local bl = band[3] or 0
    local nr = r * (1 - b) + c[1] * b
    local ng = g * (1 - b) + c[2] * b
    local nb = bl * (1 - b) + c[3] * b
    if flash > 0 then
      nr = math.min(1, nr + flash * 0.35)
      ng = math.min(1, ng + flash * 0.38)
      nb = math.min(1, nb + flash * 0.42)
    end
    out[i] = { nr, ng, nb, band[4] or 1 }
  end
  return out
end

-- Expose catalog for tests / debug
NightSky._STARS = STARS
NightSky._PLANETS = PLANETS


-- ---------- Shooting stars (in-game clock, night only)
--
-- Per-night scheduler (8.1.14):
--   • Four isolated single shooting-star events are distributed across each
--     full night. Each event contains exactly ONE shooting star.
--   • At nightfall, roll once for a meteor shower. The shower has a 10% chance
--     to occur, is assigned one random point in that night, and can happen at
--     most once before dawn.
--   • Missed events never spill into the next night and events never stack.
--
-- A normal night is 20:00 -> 04:00 in the TimeOfDay fallback, i.e. 480 game
-- minutes. Alternate hosts still use the real night edge from NightSky.isNight;
-- elapsed night time advances from the host game clock so the same plan works.

METEOR = {
  lastGameMin = nil,
  wasNight = false,
  nightStartMin = nil,
  nightElapsed = 0,
  singleTargets = {},
  nextSingle = 1,
  singlesFired = 0,
  showerEligible = false,
  showerTarget = nil,
  showerDone = false,
  showerFired = false,
  pendingSingle = false,
  pendingShower = false,
  pendingFireball = false,
  fireballEligible = false, fireballTarget = nil, fireballDone = false, fireballFired = false,
  active = {},             -- { birth, life, ox,oy,oz, dx,dy,dz, speed, bright, shower }
  realTime = 0,
}

local SINGLE_PER_NIGHT = 4
local NIGHT_GAME_MINUTES = 480
local SHOWER_CHANCE = 0.10
local SHOWER_COUNT = 7
local SHOWER_SPREAD = 0.55   -- real-seconds between staggered heads
local FIREBALL_CHANCE = 0.025 -- rare bolide: one 2.5% roll per full night

local function gameMinutesNow()
  local TOD
  safe(function()
    if V and V.require then TOD = V.require("TimeOfDay") end
  end)
  if TOD and type(TOD.hour) == "number" then
    return (TOD.hour % 24) * 60
  end
  -- Host DayNight: map cycle position to 24h game minutes
  local DN = NightSky._DayNight
  if DN and type(DN.time) == "function" then
    local ok, t = safe(DN.time)
    local cycle = tonumber(DN.CYCLE) or 1200
    if ok and type(t) == "number" and cycle > 0 then
      return ((t % cycle) / cycle) * (24 * 60)
    end
  end
  return nil
end

local function wrapDelta(now, prev)
  -- Game clock wraps at 24h = 1440 minutes
  local d = now - prev
  if d < -720 then d = d + 1440 end  -- crossed midnight forward
  if d > 720 then d = d - 1440 end   -- went backward (pin change) — ignore large jumps
  if d < 0 then d = 0 end
  if d > 5 then d = 5 end            -- clamp hitch / source switch
  return d
end

local function fallbackNightElapsed(gmin)
  -- Used only when loading directly into the middle of a normal 20:00-04:00
  -- night. This prevents all four planned singles from trying to "catch up".
  if gmin >= 20 * 60 then return math.min(NIGHT_GAME_MINUTES, gmin - 20 * 60) end
  if gmin < 4 * 60 then return math.min(NIGHT_GAME_MINUTES, gmin + 4 * 60) end
  return 0
end

local function randomDir()
  -- Mostly horizontal, slight downward so trails read as falling.
  local az = math.random() * math.pi * 2
  local el = -0.15 - math.random() * 0.35  -- slight dive
  local ce, se = math.cos(el), math.sin(el)
  local dx = math.sin(az) * ce
  local dy = se
  local dz = math.cos(az) * ce
  local L = math.sqrt(dx * dx + dy * dy + dz * dz)
  return dx / L, dy / L, dz / L
end

local function meteorBusy()
  -- Any live or scheduled streak means an event is already on screen.
  for i = 1, #METEOR.active do
    local m = METEOR.active[i]
    if METEOR.realTime <= (m.birth + m.life + 0.05) then
      return true
    end
  end
  return false
end

local function spawnOne(dx, dy, dz, delay, shower, kind)
  delay = delay or 0
  kind = kind or (shower and "shower" or "single")
  -- Origin on upper hemisphere, offset opposite travel so it crosses the view.
  local az = math.random() * math.pi * 2
  local el = 0.35 + math.random() * 0.45
  local ce, se = math.cos(el), math.sin(el)
  local ox = math.cos(az) * ce
  local oy = se
  local oz = math.sin(az) * ce
  -- Nudge origin against direction so the path crosses overhead.
  ox = ox - dx * 0.35
  oy = oy - dy * 0.15
  oz = oz - dz * 0.35
  local L = math.sqrt(ox * ox + oy * oy + oz * oz)
  if L > 1e-6 then ox, oy, oz = ox / L, oy / L, oz / L end
  METEOR.active[#METEOR.active + 1] = {
    birth = METEOR.realTime + delay,
    life = 0.85 + math.random() * 0.55,
    ox = ox, oy = oy, oz = oz,
    dx = dx, dy = dy, dz = dz,
    speed = 0.55 + math.random() * 0.35,
    bright = kind=="fireball" and 1.0 or (shower and (0.85 + math.random() * 0.15) or (0.95 + math.random() * 0.05)),
    shower = shower and true or false, kind=kind,
    size = kind=="fireball" and 1.75 or 1.0,
    tail = kind=="fireball" and 10 or 5,
  }
end

local function spawnSingle()
  -- Hard rule: one isolated shooting star; never stack with another event.
  if meteorBusy() then return false end
  METEOR.active = {}
  local dx, dy, dz = randomDir()
  spawnOne(dx, dy, dz, 0, false, "single")
  return true
end

local function spawnFireball()
  -- Retained for compatibility/debug hooks, but deliberately not part of the
  -- automatic night cadence so regular sky streaks stay capped at four.
  if meteorBusy() then return false end
  METEOR.active={}
  local dx,dy,dz=randomDir()
  spawnOne(dx,dy,dz,0,false,"fireball")
  local m=METEOR.active[1]
  if m then m.life=1.45+math.random()*.45; m.speed=.42+math.random()*.18 end
  return true
end

local function spawnShower()
  if meteorBusy() then return false end
  METEOR.active = {}
  local dx, dy, dz = randomDir()
  for i = 1, SHOWER_COUNT do
    local jx = (math.random() - 0.5) * 0.12
    local jz = (math.random() - 0.5) * 0.12
    local jy = (math.random() - 0.5) * 0.04
    local sx, sy, sz = dx + jx, dy + jy, dz + jz
    local L = math.sqrt(sx * sx + sy * sy + sz * sz)
    sx, sy, sz = sx / L, sy / L, sz / L
    spawnOne(sx, sy, sz, (i - 1) * SHOWER_SPREAD, true)
  end
  return true
end

local function beginNightPlan(elapsed)
  elapsed = math.max(0, math.min(NIGHT_GAME_MINUTES, tonumber(elapsed) or 0))
  METEOR.nightElapsed = elapsed
  METEOR.singleTargets = {}
  METEOR.nextSingle = 1
  METEOR.singlesFired = 0
  METEOR.pendingSingle = false
  METEOR.pendingShower = false
  METEOR.pendingFireball = false
  METEOR.fireballEligible=false;METEOR.fireballTarget=nil;METEOR.fireballDone=false;METEOR.fireballFired=false

  -- One event per quarter of the night, but randomize well inside each quarter
  -- so the cadence never looks like a timer. This guarantees four widely
  -- separated opportunities instead of the old one-per-game-minute barrage.
  local quarter = NIGHT_GAME_MINUTES / SINGLE_PER_NIGHT
  for i = 1, SINGLE_PER_NIGHT do
    local q0 = (i - 1) * quarter
    local lo = q0 + quarter * 0.18
    local hi = q0 + quarter * 0.82
    METEOR.singleTargets[i] = lo + (hi - lo) * math.random()
  end
  while METEOR.nextSingle <= SINGLE_PER_NIGHT
      and METEOR.singleTargets[METEOR.nextSingle] <= elapsed do
    METEOR.nextSingle = METEOR.nextSingle + 1
  end

  -- Exactly one roll per night. A successful roll receives one random time and
  -- can produce at most one shower before dawn.
  METEOR.showerEligible = math.random() < SHOWER_CHANCE
  METEOR.showerTarget = METEOR.showerEligible and (5 + math.random() * (NIGHT_GAME_MINUTES - 10)) or nil
  METEOR.showerDone = not METEOR.showerEligible
  METEOR.showerFired = false
  if METEOR.showerTarget and METEOR.showerTarget <= elapsed then
    -- Loading after the chosen shower time means that night's shower was missed;
    -- never burst or defer it into the remainder of the night.
    METEOR.showerDone = true
  end
  -- Bolides/fireballs were renderable but unreachable in normal play. Give the
  -- existing renderer one deliberately rare natural opportunity per night.
  METEOR.fireballEligible=math.random()<FIREBALL_CHANCE
  METEOR.fireballTarget=METEOR.fireballEligible and (8+math.random()*(NIGHT_GAME_MINUTES-16)) or nil
  METEOR.fireballDone=not METEOR.fireballEligible;METEOR.fireballFired=false
  if METEOR.fireballTarget and METEOR.fireballTarget<=elapsed then METEOR.fireballDone=true end
end

local function endNightPlan()
  METEOR.nightStartMin = nil
  METEOR.nightElapsed = 0
  METEOR.singleTargets = {}
  METEOR.nextSingle = 1
  METEOR.singlesFired = 0
  METEOR.showerEligible = false
  METEOR.showerTarget = nil
  METEOR.showerDone = false
  METEOR.showerFired = false
  METEOR.pendingSingle = false
  METEOR.pendingShower = false
  METEOR.pendingFireball = false
  METEOR.fireballEligible=false;METEOR.fireballTarget=nil;METEOR.fireballDone=false;METEOR.fireballFired=false
end

function NightSky.update(dt)
  dt = tonumber(dt) or 0
  NightSky._visualTime=(tonumber(NightSky._visualTime) or 0)+math.max(0,math.min(dt,0.25))
  if Aurora and Aurora.update then safe(Aurora.update,dt) end
  if dt < 0 then dt = 0 end
  if dt > 0.25 then dt = 0.25 end
  -- Smooth within phase; snap on large jumps (sleep, pin, load, debug).
  local target = NightSky.computeNightVisibility()
  NightSky._nightVisRaw = target
  local cur = NightSky._nightVis or target
  local TOD=NightSky._TOD
  if TOD and (TOD.pin=="NITE" or TOD.pin=="NIGHT" or TOD.hostMode=="night") then
    NightSky._nightVis=target
  elseif TOD and (TOD.pin=="DAY" or TOD.hostMode=="day") then
    NightSky._nightVis=0
  elseif math.abs(target - cur) > 0.4 then
    NightSky._nightVis = target
  else
    local k = 1 - math.exp(-3.2 * dt)
    NightSky._nightVis = cur + (target - cur) * k
  end
  METEOR.realTime = METEOR.realTime + dt

  -- Retire finished meteors.
  local live = {}
  for i = 1, #METEOR.active do
    local m = METEOR.active[i]
    if METEOR.realTime <= m.birth + m.life + 0.05 then
      live[#live + 1] = m
    end
  end
  METEOR.active = live

  local night = NightSky.isNight(nil)
  local gmin = gameMinutesNow()
  if gmin == nil then return end

  if METEOR.lastGameMin == nil then
    METEOR.lastGameMin = gmin
    METEOR.wasNight = night
    if night then
      METEOR.nightStartMin = gmin
      beginNightPlan(fallbackNightElapsed(gmin))
    end
    return
  end

  local dmin = wrapDelta(gmin, METEOR.lastGameMin)
  METEOR.lastGameMin = gmin

  if night and not METEOR.wasNight then
    METEOR.nightStartMin = gmin
    beginNightPlan(0)
  elseif not night and METEOR.wasNight then
    endNightPlan()
  end
  METEOR.wasNight = night
  if not night then return end

  METEOR.nightElapsed = math.min(NIGHT_GAME_MINUTES, METEOR.nightElapsed + dmin)

  -- Meteor shower has priority if both events become due simultaneously. The
  -- single remains pending and fires only after the shower is fully off-screen.
  if not METEOR.showerDone and METEOR.showerTarget
      and METEOR.nightElapsed >= METEOR.showerTarget then
    METEOR.pendingShower = true
  end
  if METEOR.nextSingle <= SINGLE_PER_NIGHT then
    local at = METEOR.singleTargets[METEOR.nextSingle]
    if at and METEOR.nightElapsed >= at then METEOR.pendingSingle = true end
  end
  if not METEOR.fireballDone and METEOR.fireballTarget and METEOR.nightElapsed>=METEOR.fireballTarget then
    METEOR.pendingFireball=true
  end

  if not meteorBusy() then
    if METEOR.pendingShower then
      if spawnShower() then
        METEOR.pendingShower = false
        METEOR.showerDone = true
        METEOR.showerFired = true
      end
    elseif METEOR.pendingFireball then
      if spawnFireball() then
        METEOR.pendingFireball=false;METEOR.fireballDone=true;METEOR.fireballFired=true
      end
    elseif METEOR.pendingSingle then
      if spawnSingle() then
        METEOR.pendingSingle = false
        METEOR.singlesFired = METEOR.singlesFired + 1
        METEOR.nextSingle = METEOR.nextSingle + 1
      end
    end
  end
end

meteorProgress = function(m)
  if METEOR.realTime < m.birth then return nil end
  local u = (METEOR.realTime - m.birth) / m.life
  if u < 0 or u > 1 then return nil end
  return u
end

-- Append meteor quads into a vertex list (world dome space).
local function appendMeteorsWorld(verts, n, axisR, axisU, e, radius)
  n = n or 0
  for i = 1, #METEOR.active do
    local m = METEOR.active[i]
    local u = meteorProgress(m)
    if u then
      local fade = 1.0
      if u < 0.12 then fade = u / 0.12 end
      if u > 0.72 then fade = (1.0 - u) / 0.28 end
      local travel = (u - 0.05) * m.speed * 1.8
      local cx = e[1] + (m.ox + m.dx * travel) * radius
      local cy = e[2] + (m.oy + m.dy * travel) * radius
      local cz = e[3] + (m.oz + m.dz * travel) * radius
      local sm = 1
      safe(function()
        local BL = V.require("BuildingLight")
        if BL and BL.starScale then sm = BL.starScale() or 1 end
      end)
      local a = m.bright * fade * (type(sm) == "number" and sm or 1)
      local sz=tonumber(m.size) or 1
      n = pushQuad(verts, n, cx, cy, cz, 3.2*sz, axisR, axisU, 1.0, 0.95, 0.85, a)
      n = pushQuad(verts, n, cx, cy, cz, 1.4*sz, axisR, axisU, 1, 1, 1, a)
      for k = 1, (tonumber(m.tail) or 5) do
        local back = k * 0.035
        local tx = e[1] + (m.ox + m.dx * (travel - back)) * radius
        local ty = e[2] + (m.oy + m.dy * (travel - back)) * radius
        local tz = e[3] + (m.oz + m.dz * (travel - back)) * radius
        local ta = a * math.max(0.05,(1.0 - k / ((tonumber(m.tail) or 5)+1)))
        local half = math.max(.55,(2.4 - k * 0.18)*(tonumber(m.size) or 1))
        n = pushQuad(verts, n, tx, ty, tz, half, axisR, axisU, 0.85, 0.88, 1.0, ta * 0.7)
      end
    end
  end
  return n
end

-- Localised: `function name(...)` without `local` defines a GLOBAL.
local function drawMeteorsScreen(w, h, edge)
  if not (love and love.graphics) then return end
  for i = 1, #METEOR.active do
    local m = METEOR.active[i]
    local u = meteorProgress(m)
    if u then
      local fade = 1.0
      if u < 0.12 then fade = u / 0.12 end
      if u > 0.72 then fade = (1.0 - u) / 0.28 end
      local travel = (u - 0.05) * m.speed * 1.8
      local px = m.ox + m.dx * travel
      local py = m.oy + m.dy * travel
      local pz = m.oz + m.dz * travel
      local su = (px * 0.5 + 0.5)
      local sv = 1.0 - (py * 0.85 + 0.05)
      local x = su * w
      local y = sv * edge
      if y < edge - 1 and y > 0 then
        local a = m.bright * fade
        safe(love.graphics.setColor, 1, 0.95, 0.85, a)
        local sz=tonumber(m.size) or 1; safe(love.graphics.rectangle, "fill", x - sz, y - sz*.7, 3*sz, 2*sz)
        -- short trail
        for k = 1, math.min(8,(tonumber(m.tail) or 5)) do
          local tpx = m.ox + m.dx * (travel - k * 0.04)
          local tpy = m.oy + m.dy * (travel - k * 0.04)
          local tx = (tpx * 0.5 + 0.5) * w
          local ty = (1.0 - (tpy * 0.85 + 0.05)) * edge
          safe(love.graphics.setColor, 0.8, 0.88, 1.0, a * (1 - k * 0.2) * 0.7)
          safe(love.graphics.rectangle, "fill", tx, ty, 2, 1)
        end
      end
    end
  end
end


function NightSky._forceMeteorEvent(kind)
  kind=tostring(kind or "single"):lower()
  METEOR.active={}
  if kind=="shower" then return spawnShower() end
  if kind=="fireball" or kind=="bolide" then return spawnFireball() end
  return spawnSingle()
end

function NightSky.celestialEventProof()
  local kinds={}
  for i=1,#METEOR.active do kinds[#kinds+1]=METEOR.active[i].kind or "single" end
  return {active=kinds,pendingSingle=METEOR.pendingSingle,pendingShower=METEOR.pendingShower,pendingFireball=METEOR.pendingFireball,
    singlesFired=METEOR.singlesFired,nextSingle=METEOR.nextSingle,showerEligible=METEOR.showerEligible,
    showerDone=METEOR.showerDone,showerFired=METEOR.showerFired,fireballEligible=METEOR.fireballEligible,
    fireballTarget=METEOR.fireballTarget,fireballDone=METEOR.fireballDone,fireballFired=METEOR.fireballFired,nightElapsed=METEOR.nightElapsed}
end

NightSky._appendMeteorsWorld = appendMeteorsWorld
NightSky._drawMeteorsScreen = drawMeteorsScreen

return NightSky
