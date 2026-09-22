-- PRECIPITATION AND DEBRIS: everything that moves through the air.
--
-- FOUR DECISIONS WORTH THE COMMENT:
--
-- 1. ONE DRAW CALL, ALWAYS.  Every drop, flake, grain, leaf and splash
--    tick goes into a single SpriteBatch built on a 1x1 white texture, so
--    a full-tier downpour is one draw call and one texture bind rather
--    than 900.  The 1x1 texture is also the reason there is no `assets/`
--    folder: a white pixel stretched to (length, thickness) and rotated IS
--    a rain streak, and scaled square IS a flake.  Nothing is shipped,
--    nothing is derived from the ROM, and the batch's per-sprite colour
--    does the rest.
--
-- 2. NOTHING IS ALLOCATED AFTER WARMUP.  The pools are flat parallel
--    arrays sized once to the quality cap.  A drop that falls off the
--    bottom is not freed and a new one is not created -- the same slot is
--    rewound to the top with fresh randomness.  Density changes by moving
--    an `active` count, so a drizzle is the same memory as a storm and the
--    garbage collector never sees weather.
--
-- 3. THREE POOLS, NOT SIX.  Rain and snow each get their own because they
--    coexist (hail is snow with grains through it) and behave completely
--    differently.  Hail, sand and debris share the GRAIN pool: they are
--    all "a hard little thing thrown across the screen", they differ only
--    in colour, speed, angle and whether they tumble, and two of the three
--    are mutually exclusive weathers anyway.  Each grain carries its kind,
--    assigned at spawn by rolling against the live channel mix -- so a
--    transition from sandstorm to hail is grains changing kind one at a
--    time as they recycle, which reads as the storm turning over rather
--    than as one effect being swapped for another.
--
-- 4. PARTICLES ARE SIZED IN GAME-BOY PIXELS, NOT SCREEN PIXELS.  Every
--    length and speed here is in GB pixels and multiplied by the frame's
--    scale at draw time, so weather looks the same at 1x in a small
--    window, at 6x fullscreen, through the survey zoom, and over a voxel
--    diorama, whose scale is the same number measured the same way.
--
-- SPLASHES AND BOUNCES CARRY THEIR OWN CAMERA.  A splash is on the GROUND,
-- but this system draws in screen space, so one spawned while the player
-- is walking would slide with the screen for its whole life.  Each records
-- the camera position it was born at and is drawn offset by how far the
-- camera has moved since, which pins it to the ground for the third of a
-- second it exists, at the cost of two numbers per splash.

local V = ...

local P = {}

-- 4.35.32: both the legacy/2D leaf pass and the 3D world-space leaf pass
-- share Settings.leafColor() as their single colour authority. Settings in
-- turn resolves SEASONAL from Seasons.current(), so the colour changes on the
-- exact same season boundary as weather weighting and the 3D renderer.
local _Settings, _settingsTried = nil, false
local function settingsModule()
  if _Settings then return _Settings end
  if _settingsTried then return nil end
  _settingsTried = true
  local ok, m = pcall(V.require, "Settings")
  if ok and m then _Settings = m end
  return _Settings
end

local function leafTint()
  local leaf = "green"
  local S = settingsModule()
  if S and S.leafColor then
    local ok, v = pcall(S.leafColor)
    if ok and type(v) == "string" then leaf = v end
  end
  if leaf == "yellow" then return 0.78, 0.68, 0.18 end
  if leaf == "orange" then return 0.82, 0.42, 0.14 end
  if leaf == "brown" then return 0.48, 0.30, 0.14 end
  return 0.30, 0.58, 0.22
end

-- Lightweight diagnostic used by the executable release regression. The draw
-- path below calls this exact function, so the test cannot drift from runtime.
function P.leafTint() return leafTint() end

-- LÖVE 11 is LuaJIT, where math.atan2 exists; a 5.3+ host (a headless test
-- runner, a future LÖVE) folds it into math.atan.  One line here beats a
-- version check at the call site.
local atan2 = math.atan2 or math.atan
-- 2D snow evaluates three sine waves per active flake per frame. Use the
-- same table-driven approach as the 3D engine so MAX keeps every flake without
-- paying thousands of libm calls.
local SIN_N=4096; local SIN_TAB={}; for i=0,SIN_N-1 do SIN_TAB[i]=math.sin(i*math.pi*2/SIN_N) end
local SIN_SCALE=SIN_N/(math.pi*2)
local function fsin(a) return SIN_TAB[math.floor(a*SIN_SCALE)%SIN_N] end

-- ------- the runtime 2D particle atlas
--
-- 4.31.4: the old 1x1-only SpriteBatch made every soft particle a square.
-- Keep the single-batch performance model, but generate a tiny atlas at runtime:
--   * solid white texel block for rain/sand/debris/splashes
--   * round soft disc for snow
--   * ice sphere for hail (hard rim + cool body + highlight, matching 3D hail)
--   * three irregular cinder silhouettes for ash/black ash (matching 3D ash)
-- No shipped art and no 3D code dependency.

local pixel, batch, batchCap = nil, nil, 0
local atlasQuads = nil
local ATLAS_CELL = 32
local ATLAS_CELLS = 6
local SOLID_CELL = 8

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function smooth(a, b, x)
  if x <= a then return 0 end
  if x >= b then return 1 end
  local t = (x - a) / (b - a)
  return t * t * (3 - 2 * t)
end

local function put(data, x, y, r, g, b, a)
  data:setPixel(x, y, clamp01(r), clamp01(g), clamp01(b), clamp01(a))
end

local function fillParticleCell(data, cell, kind)
  local ox = cell * ATLAS_CELL
  local n = ATLAS_CELL
  local cx, cy = (n - 1) * 0.5, (n - 1) * 0.5
  local radius = n * 0.40
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local px = (x - cx) / radius
      local py = (y - cy) / radius
      local r = math.sqrt(px * px + py * py)
      local rr, gg, bb, aa = 1, 1, 1, 0
      if kind == "round" then
        -- Snow: genuinely circular, with a soft antialiased edge.
        aa = 1 - smooth(0.78, 1.02, r)
        local core = 1 - smooth(0.0, 0.92, r)
        rr, gg, bb = 0.96 + core * 0.04, 0.98 + core * 0.02, 1.0
      elseif kind == "hail" then
        -- 2D analogue of the 3D hail shader: hard icy ball, cool rim, bright
        -- upper-left specular spot. It must read as ice, not a white square.
        aa = 1 - smooth(0.88, 1.02, r)
        local edge = smooth(0.66, 0.96, r)
        local hx, hy = px + 0.32, py + 0.34
        local highlight = 1 - smooth(0.05, 0.34, math.sqrt(hx * hx + hy * hy))
        rr = 0.82 + 0.16 * (1 - edge) + 0.12 * highlight
        gg = 0.90 + 0.08 * (1 - edge) + 0.10 * highlight
        bb = 1.00
      else
        -- Procedural 2D versions of the three 3D ash silhouettes. These masks
        -- include cut-outs/char cracks so gray and black ash never read as
        -- rectangles even before rotation and aspect variation are applied.
        local ang = atan2(py, px)
        local seed = (kind == "ash1" and 0.7) or (kind == "ash2" and 1.9) or 3.1
        local qx, qy = px, py
        if kind == "ash2" then qx, qy = px * 1.45, py * 0.78 end
        local qr = math.sqrt(qx * qx + qy * qy)
        local rim = 0.78 + 0.13 * math.sin(ang * (kind == "ash3" and 3 or 4) + seed)
                         + 0.08 * math.sin(ang * 7 - seed * 1.7)
        local body = 1 - smooth(rim - 0.10, rim + 0.03, qr)
        local holes = 0
        if kind == "ash1" then
          holes = smooth(0.45, 0.86, math.sin(ang * 4 + seed) * math.sin(qr * 8 - seed))
                  * smooth(0.18, 0.48, qr)
        elseif kind == "ash2" then
          local crack = math.abs(math.sin(qx * 9 + seed * 3.0))
          holes = (1 - smooth(0.03, 0.18, crack)) * smooth(0.10, 0.58, qr)
        else
          local h1 = smooth(0.28, 0.72, math.sin(ang * 3 + seed) * math.sin(qr * 6 - seed))
          local h2 = smooth(0.34, 0.78, math.sin(ang * 5 - seed) * math.sin(qr * 8 + seed))
          holes = math.min(0.85, h1 * 0.65 + h2 * 0.42) * smooth(0.14, 0.55, qr)
        end
        aa = body * (1 - holes)
        local shade = 0.70 + 0.22 * ((px - py + 2) * 0.25)
        rr, gg, bb = shade, shade, shade * 0.98
      end
      put(data, ox + x, y, rr, gg, bb, aa)
    end
  end
end

local function ensureTexture()
  if pixel then return pixel end
  if not (love and love.graphics and love.image) then return nil end
  local ok, image = pcall(function()
    local w, h = ATLAS_CELL * ATLAS_CELLS, ATLAS_CELL
    local data = love.image.newImageData(w, h)
    -- Solid cell: leave padding around a white core so linear filtering never
    -- bleeds into the neighboring particle shape.
    for y = 0, SOLID_CELL - 1 do
      for x = 0, SOLID_CELL - 1 do put(data, x, y, 1, 1, 1, 1) end
    end
    fillParticleCell(data, 1, "round")
    fillParticleCell(data, 2, "hail")
    fillParticleCell(data, 3, "ash1")
    fillParticleCell(data, 4, "ash2")
    fillParticleCell(data, 5, "ash3")
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    if love.graphics.newQuad then
      atlasQuads = {
        solid = love.graphics.newQuad(0, 0, SOLID_CELL, SOLID_CELL, w, h),
        snow = love.graphics.newQuad(ATLAS_CELL, 0, ATLAS_CELL, ATLAS_CELL, w, h),
        hail = love.graphics.newQuad(ATLAS_CELL * 2, 0, ATLAS_CELL, ATLAS_CELL, w, h),
        ash = {
          love.graphics.newQuad(ATLAS_CELL * 3, 0, ATLAS_CELL, ATLAS_CELL, w, h),
          love.graphics.newQuad(ATLAS_CELL * 4, 0, ATLAS_CELL, ATLAS_CELL, w, h),
          love.graphics.newQuad(ATLAS_CELL * 5, 0, ATLAS_CELL, ATLAS_CELL, w, h),
        },
      }
    end
    return img
  end)
  if not ok then atlasQuads = nil; return nil end
  pixel = image
  return pixel
end

local function ensureBatch(capacity)
  if not ensureTexture() then return nil end
  if batch and batchCap >= capacity then return batch end
  local ok, made = pcall(love.graphics.newSpriteBatch, pixel, capacity, "stream")
  if not ok then return nil end
  batch, batchCap = made, capacity
  return batch
end

function P.ready()
  return ensureTexture() ~= nil
end

function P.invalidate()
  pixel, batch, batchCap, atlasQuads = nil, nil, 0, nil
end

-- ------- pools

local function newPool(fields)
  local pool = { n = 0, active = 0 }
  for _, name in ipairs(fields) do pool[name] = {} end
  return pool
end

-- `ld` is the y this drop lands at.  THE WHOLE SCREEN IS GROUND in a
-- top-down game: rain that only bursts along the bottom edge is what a
-- side-on game would do, and it reads as the rain falling behind the world
-- instead of onto it.  Each drop picks its own landing depth at spawn, so
-- splashes appear at every distance at once, the way they do out a window.
local rain  = newPool({ "x", "y", "vs", "ls", "a", "ld", "dp" })
local snow  = newPool({ "x", "y", "vs", "ph", "sw", "sz", "a", "dp", "y0", "pathH" })
-- grain: kind 1 = hail, 2 = sand, 3 = debris, 4 = ash, 5 = black ash
local grain = newPool({ "x", "y", "vx", "vy", "kind", "sz", "a", "rot", "spin", "ld", "dp", "pathH" })
-- splash: kind 1 = water burst, 2 = hail bounce, 3 = dust puff
local splash = newPool({ "x", "y", "cx", "cy", "t", "sz", "kind" })
-- Ground wet residual after a drop hits (2s dry-up).
local wetGround = newPool({ "x", "y", "cx", "cy", "t", "sz" })
local wetCursor = 0

local function rnd(a, b)
  if love and love.math and love.math.random then return love.math.random() * (b - a) + a end
  return math.random() * (b - a) + a
end

local rect = { w = 0, h = 0, scale = 1 }

local function rescale(w, h)
  if rect.w <= 0 or rect.h <= 0 then return end
  local fx, fy = w / rect.w, h / rect.h
  for i = 1, rain.n do
    rain.x[i] = rain.x[i] * fx
    rain.y[i] = rain.y[i] * fy
    rain.ld[i] = rain.ld[i] * fy
  end
  for i = 1, snow.n do snow.x[i] = snow.x[i] * fx; snow.y[i] = snow.y[i] * fy end
  for i = 1, grain.n do
    grain.x[i] = grain.x[i] * fx
    grain.y[i] = grain.y[i] * fy
    grain.ld[i] = grain.ld[i] * fy
  end
  -- splashes are transient; letting them die where they are is cheaper
  -- and invisible
end

function P.setRect(w, h, scale)
  w, h = math.max(1, w or 1), math.max(1, h or 1)
  if w ~= rect.w or h ~= rect.h then
    rescale(w, h)
    rect.w, rect.h = w, h
  end
  rect.scale = math.max(0.25, scale or 1)
end

-- ------- spawners
--
-- `fresh` scatters through the whole field (first fill, so the sky is not
-- empty for a second); otherwise the particle is rewound to just outside
-- the edge it entered from, which is where a recycled one belongs.

-- How far up the screen a drop may land, 0..1 (config `splashSpread`).
-- 1 = anywhere on screen, 0 = the bottom edge only.
P.spread = 1.0

local function landingY(fresh, startY)
  local top = rect.h * (1 - math.max(0, math.min(1, P.spread)))
  local y = rnd(top, rect.h)
  -- A drop rewound to the top must not be given a landing depth it has
  -- already passed, or it recycles instantly and the pool thrashes.
  if startY and y < startY then y = rect.h end
  return y
end

local function spawnRain(i, fresh)
  -- 20 spread depth layers (near → far).
  local layer = math.min(19, math.floor(rnd(0, 1) * 20))
  local depth = 1.0 - (layer / 19)  -- 1 near … 0 far
  rain.dp[i] = depth
  rain.x[i] = rnd(-0.25 * rect.w, 1.25 * rect.w)
  rain.y[i] = fresh and rnd(0, rect.h) or rnd(-0.2 * rect.h, -2)
  rain.vs[i] = (0.72 + depth * 0.55) * rnd(0.88, 1.12)
  rain.ls[i] = rnd(0.55, 1.15) * (0.40 + depth * 1.15)
  rain.a[i] = rnd(0.32, 0.50) + depth * 0.50
  rain.ld[i] = landingY(fresh, rain.y[i])
end

local function spawnSnow(i, fresh)
  -- 20 depth layers. pathH is the SCREEN Y where the flake stops/recycles:
  -- layer 1 (near, depth=1) → past bottom of screen (exits)
  -- layer 20 (far, depth=0) → 50% down the screen
  -- layers between are linear steps.
  local layer = math.min(19, math.floor(rnd(0, 1) * 20))
  local depth = 1.0 - (layer / 19)  -- 1 nearest … 0 farthest
  snow.dp[i] = depth
  -- endY: near = 1.05*h (clear bottom exit), far = 0.50*h
  snow.pathH[i] = rect.h * (0.50 + 0.55 * depth)
  snow.x[i] = rnd(-0.22 * rect.w, 1.22 * rect.w)
  -- Fresh allocation represents an already-running snow column, not a newly
  -- opened emitter.  Distribute the first cohort across its complete visible
  -- lifetime so selecting/starting 2D snow cannot dump the entire pool from
  -- one narrow strip at the top.  Recycled flakes still re-enter from above.
  if fresh then
    snow.y[i] = rnd(-0.18 * rect.h, snow.pathH[i])
  else
    snow.y[i] = rnd(-0.22 * rect.h, -0.02 * rect.h)
  end
  snow.y0[i] = snow.y[i]
  snow.vs[i] = (0.16 + depth * 1.05) * rnd(0.72, 1.28)
  snow.ph[i] = rnd(0, math.pi * 2)
  snow.sw[i] = rnd(0.6, 2.8) * (0.35 + depth * 1.15)
  snow.sz[i] = rnd(0.45, 0.81) * (0.55 + depth * 0.55)
  snow.a[i] = rnd(0.28, 0.42) + depth * 0.28
end

-- The kind mix, refreshed each tick from the channels.  Rolling per spawn
-- rather than per pool is what makes a weather change look like the air
-- turning over instead of a swap.
local kindMix = { 0, 0, 0, 0, 0 }
local kindTotal = 0

local function rollKind()
  if kindTotal <= 0 then return 1 end
  local roll = rnd(0, kindTotal)
  for k = 1, 5 do
    roll = roll - kindMix[k]
    if roll <= 0 then return k end
  end
  return 1
end

-- Per-kind motion.  Hail falls hard and nearly straight; sand is thrown
-- almost horizontally and barely falls at all; debris tumbles across on
-- the wind at every height.
local function spawnGrain(i, fresh)
  local kind = rollKind()
  grain.kind[i] = kind
  local depth
  if kind == 4 or kind == 5 then
    -- Ash / black ash: 20 spread depth layers (FPV volume)
    local layer = math.min(19, math.floor(rnd(0, 1) * 20))
    depth = 1.0 - (layer / 19)
  elseif kind == 2 then
    -- Sand / dust: 20 spread depth layers
    local layer = math.min(19, math.floor(rnd(0, 1) * 20))
    depth = 1.0 - (layer / 19)
  elseif kind == 3 then
    -- Gale / debris leaves: 20 spread depth layers
    local layer = math.min(19, math.floor(rnd(0, 1) * 20))
    depth = 1.0 - (layer / 19)
  elseif kind == 1 then
    -- Hail: 10 spread depth layers
    local layer = math.min(9, math.floor(rnd(0, 1) * 10))
    depth = 1.0 - (layer / 9)
  else
    depth = rnd(0.08, 1.0)
  end
  grain.dp[i] = depth
  if kind == 2 then                                   -- sand / dust (20 depth layers)
    grain.x[i] = fresh and rnd(-0.15 * rect.w, 1.05 * rect.w) or rnd(-0.45 * rect.w, -4)
    -- Near lower in frame; far higher / more sparse vertical band
    grain.y[i] = rnd(-0.12 * rect.h + (1.0 - depth) * 0.15 * rect.h,
                     0.35 * rect.h + depth * 0.70 * rect.h)
    grain.vx[i] = rnd(1.4, 3.3) * (0.45 + depth * 1.05)
    grain.vy[i] = rnd(0.02, 0.35) * (0.45 + depth * 0.75)
    grain.sz[i] = rnd(0.7, 1.5) * (0.50 + depth * 0.65)
    grain.a[i] = rnd(0.26, 0.46) + depth * 0.35
  elseif kind == 4 or kind == 5 then                  -- ash / black ash (20 depth layers)
    -- pathH = end screen-Y: near exits bottom, layer 20 stops at 50% height
    grain.pathH[i] = rect.h * (0.50 + 0.55 * depth)
    grain.x[i] = rnd(-0.25 * rect.w, 1.25 * rect.w)
    -- Start near top so near layers travel full height and exit bottom
    if fresh then
      grain.y[i] = rnd(-0.18 * rect.h, 0.02 * rect.h)
    else
      grain.y[i] = rnd(-0.22 * rect.h, -0.02 * rect.h)
    end
    grain.vx[i] = rnd(-1.05, 1.1) * (0.35 + depth * 1.05)
    grain.vy[i] = rnd(0.06, 0.48) * (0.32 + depth * 1.15)
    grain.sz[i] = rnd(1.19, 2.17) * (0.52 + depth * 0.58)
    grain.a[i] = rnd(0.26, 0.40) + depth * 0.30
    grain.spin[i] = 0
  elseif kind == 3 then                               -- gale / debris leaves (20 depth layers)
    grain.x[i] = fresh and rnd(-0.1 * rect.w, 1.1 * rect.w) or rnd(-0.35 * rect.w, -8)
    grain.y[i] = rnd(-0.20 * rect.h + (1.0 - depth) * 0.12 * rect.h,
                     0.40 * rect.h + depth * 0.65 * rect.h)
    grain.vx[i] = rnd(0.7, 1.4) * (0.42 + depth * 1.15)
    grain.vy[i] = rnd(-0.45, 0.55) * (0.45 + depth * 0.85)
    grain.sz[i] = rnd(0.6, 1.4) * (0.48 + depth * 0.90)
    grain.a[i] = rnd(0.24, 0.48) + depth * 0.38
  else                                                -- hail (10 depth layers)
    -- pathH = end screen-Y: layer 1 exits bottom, layer 10 stops at 50%
    grain.pathH[i] = rect.h * (0.50 + 0.55 * depth)
    grain.x[i] = rnd(-0.15 * rect.w, 1.15 * rect.w)
    -- Start near top so near layers travel full height and exit bottom
    if fresh then
      grain.y[i] = rnd(-0.18 * rect.h, 0.02 * rect.h)
    else
      grain.y[i] = rnd(-0.22 * rect.h, -0.02 * rect.h)
    end
    grain.vx[i] = rnd(-0.12, 0.30) * (0.55 + depth * 0.55)
    grain.vy[i] = rnd(1.4, 2.3) * (0.50 + depth * 0.80)
    grain.sz[i] = rnd(0.88, 1.76) * (0.50 + depth * 0.70)
    grain.a[i] = rnd(0.36, 0.50) + depth * 0.35
  end
  -- hail bounces where it lands, and lands all over the screen for the
  -- same reason rain does
  grain.ld[i] = (kind == 1) and landingY(fresh, grain.y[i]) or (rect.h * 2)
  grain.rot[i] = rnd(0, math.pi * 2)
  grain.spin[i] = (kind == 3) and rnd(-6, 6) or ((kind == 4) and rnd(-1.2, 1.2) or 0)
end

local function spawnSplash(i)
  splash.x[i], splash.y[i] = 0, 0
  splash.cx[i], splash.cy[i] = 0, 0
  splash.t[i] = -1                      -- negative = dead slot
  splash.sz[i], splash.kind[i] = 1, 1
end

local function grow(pool, capacity, spawn)
  while pool.n < capacity do
    pool.n = pool.n + 1
    spawn(pool.n, true)
  end
end

-- Splashes use a rolling cursor rather than a free list: the pool is
-- small, every entry has the same short life, and overwriting the oldest
-- is both correct and one increment.
local splashCursor = 0

local function addSplash(x, y, camX, camY, size, kind)
  if splash.n <= 0 then return end
  splashCursor = splashCursor % splash.n + 1
  local i = splashCursor
  splash.x[i], splash.y[i] = x, y
  splash.cx[i], splash.cy[i] = camX, camY
  splash.t[i] = 0
  splash.sz[i], splash.kind[i] = size, kind or 1
  -- Wet mark that remains after the splash animation (2s).
  if wetGround.n > 0 and (kind or 1) == 1 then
    wetCursor = wetCursor % wetGround.n + 1
    local w = wetCursor
    wetGround.x[w], wetGround.y[w] = x, y
    wetGround.cx[w], wetGround.cy[w] = camX, camY
    wetGround.t[w] = 0
    wetGround.sz[w] = (size or 1) * (0.35 + rnd(0, 0.45))
  end
end

-- ------- the tick

local SPLASH_LIFE = 0.35
local WET_LIFE = 1.0

-- `ch` is the eased channel table; `budget` the quality caps; `wind` the
-- frame's gust in GB pixels per second; `camX/camY` the world camera, for
-- splash anchoring; `splashesOn` the player's setting.
function P.update(dt, ch, budget, wind, camX, camY, splashesOn)
  if dt <= 0 then return end
  local px = rect.scale

  if rain.n < budget.rain then grow(rain, budget.rain, spawnRain) end
  -- 4.31.6: restore the full quality-tier snow pool. The 4.31.4 half-density
  -- cap made HIGH/BLIZZARD snow look too sparse once flakes were enlarged.
  -- Flake size remains doubled; only the available 2D population is restored.
  local snowBudget2d = math.max(0, math.floor((budget.snow or 0) + 0.5))
  if snow.n < snowBudget2d then grow(snow, snowBudget2d, spawnSnow) end
  if splash.n < budget.splash then grow(splash, budget.splash, spawnSplash) end
  if wetGround.n < math.max(64, (budget.splash or 40) * 3) then
    grow(wetGround, math.max(64, (budget.splash or 40) * 3), function(i)
      wetGround.x[i], wetGround.y[i] = 0, 0
      wetGround.cx[i], wetGround.cy[i] = 0, 0
      wetGround.t[i] = -1
      wetGround.sz[i] = 1
    end)
  end

  -- the grain mix has to be set before the pool grows, or the first fill
  -- is all hail whatever the weather
  kindMix[1] = math.max(0, ch.hail or 0)
  kindMix[2] = math.max(0, (ch.sand or 0) * 1.85)   -- sand density (channels may exceed 1)
  kindMix[3] = math.max(0, ch.debris or 0)
  -- Ash weather: half gray ash, half black ash, preserving the declared
  -- channel density. 0.25 + 0.25 accidentally halved the whole ash effect.
  local ash = math.max(0, ch.ash or 0)
  kindMix[4] = ash * 0.50
  kindMix[5] = ash * 0.50
  kindTotal = kindMix[1] + kindMix[2] + kindMix[3] + kindMix[4] + kindMix[5]
  if grain.n < budget.grain then grow(grain, budget.grain, spawnGrain) end

  rain.active = math.min(rain.n, math.floor(budget.rain * math.min(3.0, (ch.rain or 0)) + 0.5))
  snow.active = math.min(snow.n, math.floor(snowBudget2d * math.min(3.0, (ch.snow or 0)) + 0.5))
  grain.active = math.min(grain.n, math.floor(budget.grain * math.min(2.5, kindTotal) + 0.5))

  -- ------- rain
  local fall = 210 * (ch.rainSpeed or 1) * px
  local lean = math.tan(ch.rainAngle or 0)
  local drift = (lean * fall) + wind * px
  local splashChance = splashesOn and (ch.splash or 0) or 0
  for i = 1, rain.active do
    local vs = rain.vs[i]
    local ny = rain.y[i] + fall * vs * dt
    local nx = rain.x[i] + drift * vs * dt
    if ny >= rain.ld[i] then
      -- Land it.  A splash for a FRACTION of drops rather than all of
      -- them: every drop bursting reads as a solid line of foam, and the
      -- fraction is the channel, so a drizzle ticks and a downpour boils.
      if splashChance > 0 and rnd(0, 1) < splashChance * 0.35 then
        addSplash(nx, rain.ld[i], camX, camY, rnd(0.7, 1.3), 1)
      end
      spawnRain(i, false)
    elseif nx < -0.3 * rect.w or nx > 1.3 * rect.w then
      spawnRain(i, false)
    else
      rain.x[i], rain.y[i] = nx, ny
    end
  end

  -- ------- snow
  -- Realistic flake fall: slower base, layered sine sway (not straight down)
  local sfall = 28 * (ch.snowSpeed or 1) * px
  local sdrift = math.max(0.35, ch.snowDrift or 0.55)
  for i = 1, snow.active do
    local depth = snow.dp[i] or 0.5
    snow.ph[i] = snow.ph[i] + dt * (0.42 + snow.sw[i] * 0.55 + depth * 0.12)
    -- Multi-frequency drift (real flakes do not sway on one sine)
    local sway = fsin(snow.ph[i]) * 32 * sdrift * snow.sw[i] * px
               + fsin(snow.ph[i] * 1.73 + 0.4) * 16 * sdrift * px
               + fsin(snow.ph[i] * 0.37) * 8 * sdrift * (0.4 + depth) * px
    local ny = snow.y[i] + sfall * snow.vs[i] * dt * (0.88 + depth * 0.22)
    local nx = snow.x[i] + (sway + wind * px * (0.35 + depth * 0.35)) * dt
    -- Panoramic wrap around the view (do not despawn at left/right edges)
    local margin = 0.2 * rect.w
    local span = rect.w + margin * 2
    if nx < -margin then
      nx = nx + span
    elseif nx > rect.w + margin then
      nx = nx - span
    end
    -- pathH is the end screen-Y for this layer (not travel distance)
    local endY = snow.pathH[i] or rect.h
    if ny >= endY then
      spawnSnow(i, false)
    else
      snow.x[i], snow.y[i] = nx, ny
    end
  end

  -- ------- grains
  --
  -- One loop for all three kinds: the kind only picks the base speeds,
  -- which were baked into vx/vy at spawn, so the motion here is common.
  local base = 150 * px
  for i = 1, grain.active do
    local kind = grain.kind[i]
    local vx = grain.vx[i] * base + wind * px * (kind == 1 and 0.5 or 1.2)
    local vy = grain.vy[i] * base
    local nx = grain.x[i] + vx * dt
    local ny = grain.y[i] + vy * dt
    -- Ash uses spin as a color flag (0/1), not angular velocity.
    if grain.kind[i] ~= 4 and grain.spin[i] ~= 0 then
      grain.rot[i] = grain.rot[i] + grain.spin[i] * dt
    end
    if (kind == 4 or kind == 5) then
      local endY = grain.pathH[i] or rect.h
      if ny >= endY then
        spawnGrain(i, false)
      else
        grain.x[i], grain.y[i] = nx, ny
      end
    elseif kind == 1 then
      -- Hail path by depth layer (same idea as snow/ash)
      local endY = grain.pathH[i] or rect.h
      if ny >= endY then
        if splashesOn and rnd(0, 1) < 0.35 then
          addSplash(nx, math.min(endY, rect.h * 0.98), camX, camY, rnd(0.5, 0.9), 2)
        end
        spawnGrain(i, false)
      else
        grain.x[i], grain.y[i] = nx, ny
      end
    elseif ny >= rect.h * 1.2 or ny < -0.35 * rect.h
        or nx < -0.35 * rect.w or nx > 1.35 * rect.w then
      spawnGrain(i, false)
    else
      grain.x[i], grain.y[i] = nx, ny
    end
  end

  -- ------- splashes
  for i = 1, splash.n do
    local t = splash.t[i]
    if t >= 0 then
      t = t + dt
      splash.t[i] = (t >= SPLASH_LIFE) and -1 or t
    end
  end
  -- ------- ground wet residual (2s)
  for i = 1, wetGround.n do
    local t = wetGround.t[i]
    if t >= 0 then
      t = t + dt
      wetGround.t[i] = (t >= WET_LIFE) and -1 or t
    end
  end

  -- Random small wet flecks across the whole playfield while raining.
  local rainAmt = ch.rain or 0
  if rainAmt > 0.05 and wetGround.n > 0 then
    local rate = 18 * math.min(1.5, rainAmt) * dt
    local nSpawn = math.floor(rate)
    if rnd(0, 1) < (rate - nSpawn) then nSpawn = nSpawn + 1 end
    for _ = 1, nSpawn do
      wetCursor = wetCursor % wetGround.n + 1
      local w = wetCursor
      wetGround.x[w] = rnd(0, rect.w)
      wetGround.y[w] = rnd(rect.h * 0.35, rect.h * 0.98)
      wetGround.cx[w], wetGround.cy[w] = camX, camY
      wetGround.t[w] = 0
      wetGround.sz[w] = 0.25 + rnd(0, 0.4)
    end
  end
end

-- ------- the draw
--
-- Colours are chosen to read on the Game Boy's four-shade palettes as well
-- as on a full-colour diorama: rain is a cool near-white at low alpha (it
-- reads as a lightening streak on dark tiles and a darkening one on
-- light), snow and hail are flat white, sand is a warm tan, debris is a
-- dark olive.

local RAIN_R, RAIN_G, RAIN_B = 0.74, 0.83, 0.98
local GRAIN_COLOR = {
  { 0.92, 0.96, 1.00 },   -- hail: white with a blue edge
  { 0.85, 0.72, 0.48 },   -- sand: warm tan
  { 0.45, 0.42, 0.24 },   -- debris fallback; leaf pass overrides from Settings.leafColor()
  { 0.62, 0.62, 0.60 },   -- ash: ash gray
  { 0.08, 0.08, 0.09 },   -- black ash
}
local SPLASH_COLOR = {
  { RAIN_R, RAIN_G, RAIN_B },
  { 0.92, 0.96, 1.00 },
  { 0.80, 0.70, 0.50 },
}

function P.draw(alpha, ch)
  local total = rain.active + snow.active + grain.active + splash.n * 2
  if total <= 0 or alpha <= 0 then return end
  local b = ensureBatch(math.max(64, total + 32))
  if not b then return end
  b:clear()

  local px = rect.scale
  local added = 0

  -- rain: a 1x1 pixel stretched to (length, thickness) and rotated to the
  -- direction of travel, so the streak always points the way the drop is
  -- going however hard the wind is blowing
  if rain.active > 0 then
    local angle = atan2(1, math.tan(ch.rainAngle or 0))
    local len = 9 * (ch.rainLen or 1) * px
    local thick = math.max(1, 0.7 * px)
    local base = alpha * 0.55
    for i = 1, rain.active do
      local depth = rain.dp[i] or 0.5
      local la = base * rain.a[i] * (0.42 + depth * 0.58)
      local ll = len * rain.ls[i] * (0.70 + depth * 0.55)
      -- 4.31.4: 2D rain is exactly 50% thicker than the previous rendered
      -- streak after the minimum-pixel clamp, so it is visible at every scale.
      local th = math.max(1, thick * (0.65 + depth * 0.55)) * 1.50
      b:setColor(RAIN_R, RAIN_G, RAIN_B, la)
      if atlasQuads and atlasQuads.solid then
        b:add(atlasQuads.solid, rain.x[i], rain.y[i], angle,
          ll / SOLID_CELL, th / SOLID_CELL, 0, SOLID_CELL * 0.5)
      else
        b:add(rain.x[i], rain.y[i], angle, ll, th, 0, 0.5)
      end
      added = added + 1
    end
  end

  -- snow: depth-layered flakes (near large/opaque, far small/faint — like rain depth)
  if snow.active > 0 then
    local base = alpha * 0.9
    for i = 1, snow.active do
      local depth = snow.dp[i] or 0.5
      -- 4.31.4: double the previous 2D flake diameter and render a genuinely
      -- round alpha-masked particle. 4.31.6 restores the full quality-tier
      -- particle population so high-intensity snow reads as a real snowfall.
      local s = snow.sz[i] * px * (0.75 + depth * 0.55) * 2.0
      local a = base * snow.a[i] * (0.45 + depth * 0.55)
      local x, y = snow.x[i], snow.y[i]
      b:setColor(0.95, 0.97, 1.0, a)
      if atlasQuads and atlasQuads.snow then
        b:add(atlasQuads.snow, x, y, 0, s / ATLAS_CELL, s / ATLAS_CELL,
          ATLAS_CELL * 0.5, ATLAS_CELL * 0.5)
      else
        b:add(x, y, 0, s, s, 0.5, 0.5)
      end
      added = added + 1
    end
  end

  -- grains: hail is a short vertical dash, sand a long horizontal one,
  -- debris a tumbling flake.  All three are the same quad at different
  -- aspect ratios and rotations. Resolve leaf colour ONCE per draw so every
  -- 2D leaf changes in lockstep with the same season authority as 3D leaves.
  if grain.active > 0 then
    local leafR, leafG, leafB = leafTint()
    for i = 1, grain.active do
      local kind = grain.kind[i]
      local c = GRAIN_COLOR[kind]
      local cr, cg, cb = c[1], c[2], c[3]
      if kind == 3 then cr, cg, cb = leafR, leafG, leafB end
      local depth = grain.dp[i] or 0.5
      local s = grain.sz[i] * px * (0.72 + depth * 0.50)
      local depthA = 0.42 + depth * 0.58
      local w, h, rot
      if kind == 2 then
        w, h, rot = s * 3.2, math.max(1, s * 0.45), grain.rot[i] * 0 + 0.12
      elseif kind == 4 or kind == 5 then
        -- Soft irregular ash flake (gray ash or black ash)
        local seed = grain.rot[i] or 0
        local aw = 0.85 + (seed % 0.55)
        local ah = 0.70 + ((seed * 0.41) % 0.50)
        -- 4.31.6: double 2D ash/black-ash dimensions while preserving the
        -- irregular cinder silhouette and depth scaling.
        w, h, rot = s * aw * 2.0, s * ah * 2.0, grain.rot[i]
      elseif kind == 3 then
        -- Leaf-like aspect from stable rot seed (no per-frame flicker)
        local seed = grain.rot[i] or 0
        local aw = 1.2 + (seed % 1.25)
        local ah = 0.45 + ((seed * 0.37) % 0.7)
        w, h, rot = s * aw, s * ah, grain.rot[i]
      else
        -- Hail balls
        w, h, rot = math.max(1.5, s * 1.0), math.max(1.5, s * 1.0), 0
      end
      if kind == 4 or kind == 5 then
        -- 2D ash now uses the same visual language as the 3D ash shader:
        -- irregular cinder silhouettes with voids/cracks, not stacked squares.
        local gx, gy = grain.x[i], grain.y[i]
        local aa = alpha * grain.a[i] * depthA
        local q = nil
        if atlasQuads and atlasQuads.ash then
          local variant = (math.floor(math.abs((grain.rot[i] or 0) * 11)) % 3) + 1
          q = atlasQuads.ash[variant]
        end
        if kind == 4 then b:setColor(0.68, 0.68, 0.66, aa * 0.92)
        else b:setColor(0.14, 0.14, 0.15, aa * 0.92) end
        if q then
          b:add(q, gx, gy, rot, w / ATLAS_CELL, h / ATLAS_CELL,
            ATLAS_CELL * 0.5, ATLAS_CELL * 0.5)
        else
          b:add(gx, gy, rot, w, h, 0.5, 0.5)
        end
        added = added + 1
      elseif kind == 1 then
        -- 2D hail is a procedural ice sphere matching the 3D hail body's
        -- hard circular rim and cool specular highlight.
        local aa = alpha * grain.a[i] * 0.95 * depthA
        b:setColor(1, 1, 1, aa)
        if atlasQuads and atlasQuads.hail then
          b:add(atlasQuads.hail, grain.x[i], grain.y[i], 0,
            w / ATLAS_CELL, h / ATLAS_CELL, ATLAS_CELL * 0.5, ATLAS_CELL * 0.5)
        else
          b:add(grain.x[i], grain.y[i], 0, w, h, 0.5, 0.5)
        end
        added = added + 1
      else
        b:setColor(cr, cg, cb, alpha * grain.a[i] * 0.9 * depthA)
        if atlasQuads and atlasQuads.solid then
          b:add(atlasQuads.solid, grain.x[i], grain.y[i], rot,
            w / SOLID_CELL, h / SOLID_CELL, SOLID_CELL * 0.5, SOLID_CELL * 0.5)
        else
          b:add(grain.x[i], grain.y[i], rot, w, h, 0.5, 0.5)
        end
        added = added + 1
      end
    end
  end

  -- Ground wet residual (dark spots that dry over 2s)
  if wetGround.n > 0 then
    for i = 1, wetGround.n do
      local t = wetGround.t[i]
      if t >= 0 then
        local k = t / WET_LIFE
        local a = alpha * 0.40 * (1 - k) * (1 - k)
        if a > 0.02 then
          local ox = wetGround.x[i] + (wetGround.cx[i] - P.camX) * px
          local oy = wetGround.y[i] + (wetGround.cy[i] - P.camY) * px
          local sz = wetGround.sz[i] * px * (0.7 + k * 0.15)
          b:setColor(0.22, 0.26, 0.32, a)
          local ww, hh = math.max(1, sz * 1.1), math.max(1, sz * 0.45)
          if atlasQuads and atlasQuads.solid then
            b:add(atlasQuads.solid, ox, oy, 0, ww / SOLID_CELL, hh / SOLID_CELL,
              SOLID_CELL * 0.5, SOLID_CELL * 0.5)
          else
            b:add(ox, oy, 0, ww, hh, 0.5, 0.5)
          end
          added = added + 1
        end
      end
    end
  end

  -- splashes: two ticks thrown apart and up, shrinking as they fade, drawn
  -- at the camera offset they were born with so they stay on the ground
  if splash.n > 0 then
    for i = 1, splash.n do
      local t = splash.t[i]
      if t >= 0 then
        local k = t / SPLASH_LIFE
        local kind = splash.kind[i]
        local c = SPLASH_COLOR[kind] or SPLASH_COLOR[1]
        local spread = (1 + k * (kind == 2 and 2.0 or 3.2)) * splash.sz[i] * px
        local rise = -k * (kind == 2 and 3.4 or 2.4) * px
        local a = alpha * 0.7 * (1 - k) * (1 - k)
        local ox = splash.x[i] + (splash.cx[i] - P.camX) * px
        local oy = splash.y[i] + (splash.cy[i] - P.camY) * px
        local w = math.max(1, 1.1 * px * (1 - k * 0.5))
        b:setColor(c[1], c[2], c[3], a)
        local hh = math.max(1, 0.7 * px)
        if atlasQuads and atlasQuads.solid then
          b:add(atlasQuads.solid, ox - spread, oy + rise, 0,
            w / SOLID_CELL, hh / SOLID_CELL, SOLID_CELL * 0.5, SOLID_CELL * 0.5)
          b:add(atlasQuads.solid, ox + spread, oy + rise, 0,
            w / SOLID_CELL, hh / SOLID_CELL, SOLID_CELL * 0.5, SOLID_CELL * 0.5)
        else
          b:add(ox - spread, oy + rise, 0, w, hh, 0.5, 0.5)
          b:add(ox + spread, oy + rise, 0, w, hh, 0.5, 0.5)
        end
        added = added + 2
      end
    end
  end

  if added == 0 then return end
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(b)
end

-- The camera the CURRENT frame is drawn at; splashes subtract the one they
-- were born at from it.  Set by Draw before P.draw.
P.camX, P.camY = 0, 0

function P.counts()
  return rain.active, snow.active, grain.active, splash.n
end

-- Behavioural debug/test surface for the shared 2D grain pool. Returning what
-- is actually active (rather than the requested channel mix) catches a family
-- that is configured but never spawned/drawn.
function P.kindCounts()
  local out = { [1]=0, [2]=0, [3]=0, [4]=0, [5]=0 }
  for i = 1, grain.active do
    local k = grain.kind[i]
    if out[k] ~= nil then out[k] = out[k] + 1 end
  end
  return out
end

-- The y of one live splash, or nil for a dead slot.  For the test suite:
-- "splashes land at many depths" is the property that makes rain read as
-- falling ONTO a top-down world rather than behind it, and it is worth
-- asserting rather than eyeballing.
function P.splashY(i)
  if i < 1 or i > splash.n then return nil end
  if splash.t[i] < 0 then return nil end
  return splash.y[i]
end

function P.reset()
  rain.active, snow.active, grain.active = 0, 0, 0
  for i = 1, splash.n do splash.t[i] = -1 end
  for i = 1, wetGround.n do wetGround.t[i] = -1 end
end

-- Strict 3D has no flat-particle fallback by definition. On the transition into
-- strict ownership, release the warm 2D pools/atlas instead of leaving their RAM
-- and VRAM resident forever. AUTO never calls this because it retains family-level
-- 2D fallback. Switching back to 2D simply grows the same pools again before draw.
function P.suspend()
  P.reset()
  local function clear(pool,fields)
    for i=1,#fields do pool[fields[i]]={} end
    pool.n,pool.active=0,0
  end
  clear(rain,{"x","y","vs","ls","a","ld","dp"})
  clear(snow,{"x","y","vs","ph","sw","sz","a","dp","y0","pathH"})
  clear(grain,{"x","y","vx","vy","kind","sz","a","rot","spin","ld","dp","pathH"})
  clear(splash,{"x","y","cx","cy","t","sz","kind"})
  clear(wetGround,{"x","y","cx","cy","t","sz"})
  splashCursor,wetCursor=0,0
  if batch and batch.release then pcall(batch.release,batch) end
  if pixel and pixel.release then pcall(pixel.release,pixel) end
  P.invalidate()
end

return P
